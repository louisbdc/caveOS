import SwiftUI
import AVFoundation
import UIKit

// MARK: - Contrat public (à l'attention de l'intégrateur)
//
// Écran plein écran à présenter en `fullScreenCover` depuis `ScanView` :
//
//   AICaptureView(
//       proxy: captureProxy,              // CameraProxy détenu en @State par l'appelant,
//                                         //   partagé pour déclencher le shutter sans churn.
//       onCapture: { image in ... },      // (UIImage) -> Void : photo redressée (normalizedUp).
//                                         //   L'appelant ferme le cover puis lance l'analyse IA.
//       onImport: { ... },                // () -> Void : repli « Importer une photo ».
//                                         //   L'appelant ferme le cover puis présente un PhotosPicker.
//       cameraStatus: $cameraStatus       // Binding<AVAuthorizationStatus> : l'écran demande
//                                         //   l'accès si .notDetermined et met le binding à jour.
//   )
//
// Responsabilités de fermeture :
//   - Bouton « Fermer » : l'écran se ferme lui-même via @Environment(\.dismiss).
//   - onCapture / onImport : closures pures (handoff). L'APPELANT est responsable
//     de fermer le cover (p. ex. showAICapture = false) puis d'enchaîner.
//     -> Découplage volontaire pour éviter une course « présenter pendant la fermeture »
//        (notamment quand onImport doit présenter un PhotosPicker juste après).
//
// L'écran gère seul : permission caméra, simulateur / caméra indisponible,
// double-tap shutter, et erreur de capture (bannière + repli import).

/// Écran de capture photo pour le scan IA : preview AVFoundation + blueprint
/// bouteille + shutter unique, avec repli import si la caméra est indisponible.
@MainActor
struct AICaptureView: View {
    let proxy: CameraProxy
    let onCapture: (UIImage) -> Void
    let onImport: () -> Void
    @Binding var cameraStatus: AVAuthorizationStatus

    @Environment(\.dismiss) private var dismiss

    @State private var phase: CapturePhase = .ready
    /// Session AVFoundation impossible (simulateur, caméra absente ou occupée).
    @State private var sessionUnavailable = false

    /// Machine à états du shutter.
    enum CapturePhase: Equatable {
        case ready              // preview + overlay + shutter actif
        case capturing          // shutter désactivé (anti double-tap) + flash
        case failed(String)     // bannière d'erreur + repli import
    }

    /// `true` si l'appareil expose une caméra arrière (faux sur simulateur).
    static var hasBackCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    var body: some View {
        content
            .task { await ensureCameraAccess() }
    }

    @ViewBuilder
    private var content: some View {
        switch cameraStatus {
        case .denied, .restricted:
            fallbackScreen(CameraDeniedView())
        case .authorized:
            if Self.hasBackCamera && !sessionUnavailable {
                liveCapture
            } else {
                fallbackScreen(ScannerUnavailableView())
            }
        default: // .notDetermined : demande en cours
            requestingScreen
        }
    }

    // MARK: - Capture en direct

    private var liveCapture: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraCaptureView(
                proxy: proxy,
                onCapture: handleCapture,
                onError: handleError
            )
            .ignoresSafeArea()

            BlueprintOverlay()

            // Flash bref pendant la prise de vue (feedback anti double-tap).
            if phase == .capturing {
                Color.white.opacity(0.25).ignoresSafeArea()
            }

            VStack(spacing: Theme.Spacing.m) {
                topBar
                Spacer()
                if case let .failed(message) = phase {
                    errorBanner(message)
                }
                controls
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.l)
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(Theme.Spacing.s)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Fermer")
            Spacer()
        }
    }

    private var controls: some View {
        VStack(spacing: Theme.Spacing.m) {
            shutterButton

            Button {
                onImport()
            } label: {
                Label("Importer une photo", systemImage: "photo")
            }
            .buttonStyle(.bordered)
            .tint(Theme.gold)
        }
    }

    private var shutterButton: some View {
        Button {
            phase = .capturing
            proxy.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .stroke(Theme.gold, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(Theme.gold)
                    .frame(width: 62, height: 62)
            }
            .opacity(phase == .capturing ? 0.5 : 1)
        }
        .disabled(phase == .capturing)
        .accessibilityLabel("Prendre la photo")
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wineDeep.opacity(0.85), in: RoundedRectangle(cornerRadius: Theme.Radius.m))
    }

    // MARK: - Écrans de repli

    private var requestingScreen: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ProgressView("Accès à la caméra…")
        }
    }

    /// Encadre une vue d'information (refus / indisponible) avec un repli import
    /// toujours visible, sur le fond de surface adaptatif (texte lisible).
    private func fallbackScreen<Content: View>(_ info: Content) -> some View {
        ZStack(alignment: .bottom) {
            Theme.surface.ignoresSafeArea()
            info
            VStack(spacing: Theme.Spacing.s) {
                Button {
                    onImport()
                } label: {
                    Label("Importer une photo", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.gold)

                Button("Fermer") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(Theme.Spacing.l)
        }
    }

    // MARK: - Handoff & erreurs

    private func handleCapture(_ image: UIImage) {
        onCapture(image)
    }

    private func handleError(_ error: Error) {
        if case CameraCaptureController.CameraError.configurationFailed = error {
            // Session impossible : bascule vers le repli import (simulateur, caméra occupée).
            sessionUnavailable = true
        } else {
            phase = .failed("La capture a échoué. Réessayez ou importez une photo.")
        }
    }

    // MARK: - Permission caméra

    /// Demande l'autorisation caméra si nécessaire et met à jour le binding partagé.
    private func ensureCameraAccess() async {
        guard cameraStatus == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }
}
