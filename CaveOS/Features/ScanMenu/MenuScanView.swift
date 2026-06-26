import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

/// Écran d'entrée du scan de carte des vins : capture en direct (caméra IA
/// réutilisée du scan d'étiquette) ou import photo, puis analyse via
/// `MenuScanService` et présentation des résultats (`MenuResultsView`).
///
/// L'accès à l'IA est gardé par le freemium (`StoreManager`) : un crédit n'est
/// décompté QUE pour une vraie carte des vins (jamais sur `notWineList`).
/// En cas d'échec réseau ou de quota épuisé, le repli `MenuDeviceFallback`
/// (Vision sur l'appareil) est proposé automatiquement avec une bannière
/// « mode dégradé ».
@MainActor
struct MenuScanView: View {

    @Environment(StoreManager.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// États du flux : capture → analyse → carte invalide / erreur.
    /// (Le succès n'est pas un état : il présente immédiatement la feuille de résultats.)
    private enum ScanPhase: Equatable {
        case idle
        case scanning
        case notWineList
        case error(String)
    }

    @State private var phase: ScanPhase = .idle

    // Capture caméra IA partagée (même proxy/obturateur que le scan d'étiquette).
    @State private var captureProxy = CameraProxy()
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

    // Import photo.
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false

    // Feuilles présentées.
    @State private var showPaywall = false
    @State private var showResults = false

    /// Résultat conservé pour alimenter la feuille de résultats (vins + troncature).
    @State private var result: MenuScanResult?

    /// `true` si le résultat provient du repli local (pas du serveur).
    @State private var degradedResult = false

    // Référentiels chargés depuis la base pour le repli local.
    @State private var knownAppellations: [String] = []
    @State private var knownGrapes: [String] = []

    var body: some View {
        NavigationStack {
            captureArea
                .overlay {
                    if phase == .scanning {
                        ScanLoadingView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: phase)
                .navigationTitle("Scanner une carte")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                }
                .sheet(isPresented: $showResults) {
                    if let result {
                        MenuResultsView(wines: result.wines, truncated: result.truncated, degraded: degradedResult)
                    }
                }
                .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
                .onChange(of: photoItem) { _, newValue in
                    guard let newValue else { return }
                    Task { await processPhoto(newValue) }
                }
                .task {
                    loadReferenceData()
                }
        }
    }

    // MARK: - Zone de capture

    @ViewBuilder
    private var captureArea: some View {
        ZStack {
            AICameraCaptureArea(
                proxy: captureProxy,
                onCapture: { image in Task { await scan(image) } },
                onImport: { showPhotoPicker = true },
                cameraStatus: $cameraStatus,
                blueprint: .document
            )

            switch phase {
            case .notWineList:
                feedbackCard(
                    icon: "questionmark.text.page",
                    message: "Ça ne ressemble pas à une carte des vins. Cadrez bien la liste et réessayez."
                )
            case .error(let message):
                feedbackCard(icon: "wifi.exclamationmark", message: message)
            default:
                EmptyView()
            }
        }
    }

    /// Carte d'information non bloquante (carte invalide / erreur réseau) avec une
    /// seule action « Réessayer » qui relance la capture.
    private func feedbackCard(icon: String, message: String) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Theme.gold)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            Button {
                phase = .idle
            } label: {
                Label("Réessayer", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.wine)
        }
        .padding(Theme.Spacing.l)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
        .padding(Theme.Spacing.l)
    }

    // MARK: - Données de référence

    private func loadReferenceData() {
        let repository = CaveRepository(context: context)
        knownAppellations = repository.appellations().map(\.name)
        knownGrapes = repository.grapes().map(\.name)
    }

    // MARK: - Analyse

    /// Analyse une photo de carte via le serveur, sous garde freemium.
    /// Décompte un crédit uniquement pour une vraie carte des vins.
    /// En cas d'échec réseau ou de quota épuisé, bascule sur le repli Vision local.
    private func scan(_ image: UIImage) async {
        degradedResult = false

        // Quota épuisé : proposer le repli local gratuit plutôt qu'un hard paywall.
        guard store.canUseAIScan() else {
            let wines = await MenuDeviceFallback.scan(
                image: image,
                knownAppellations: knownAppellations,
                knownGrapes: knownGrapes
            )
            if wines.isEmpty {
                showPaywall = true
            } else {
                result = MenuScanResult(wines: wines, truncated: false, notWineList: false)
                degradedResult = true
                phase = .idle
                showResults = true
            }
            return
        }

        phase = .scanning
        do {
            let scanResult = try await MenuScanService.scanList(image: image)
            if scanResult.notWineList {
                // Aucun vin : pas une carte → aucun crédit consommé.
                phase = .notWineList
            } else {
                store.consumeFreeScan()
                result = scanResult
                phase = .idle
                showResults = true
            }
        } catch {
            // Échec réseau : repli Vision local.
            let wines = await MenuDeviceFallback.scan(
                image: image,
                knownAppellations: knownAppellations,
                knownGrapes: knownGrapes
            )
            result = MenuScanResult(wines: wines, truncated: false, notWineList: wines.isEmpty)
            degradedResult = true
            if wines.isEmpty {
                phase = .error("La lecture de la carte a échoué hors-ligne. Vérifiez votre connexion.")
            } else {
                phase = .idle
                showResults = true
            }
        }
    }

    /// Charge l'image importée puis lance l'analyse.
    private func processPhoto(_ item: PhotosPickerItem) async {
        // Réinitialiser dans tous les cas : sans cela, re-sélectionner la même photo
        // après une erreur ne déclencherait pas `onChange(of: photoItem)`.
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                phase = .error("Impossible de charger cette image. Réessayez avec une autre photo.")
                return
            }
            await scan(uiImage)
        } catch {
            phase = .error("Impossible de charger cette image. Réessayez avec une autre photo.")
        }
    }
}
