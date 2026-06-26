import SwiftUI
import AVFoundation
import UIKit

/// Caméra de scan IA affichée EN LIGNE dans `ScanView` (et non plus en plein
/// écran modal) : preview AVFoundation + silhouette blueprint + obturateur unique
/// centré, avec import discret en coin et replis (permission refusée / caméra
/// indisponible).
///
/// Aligne l'UX du mode IA sur celle du mode Appareil : la caméra est
/// immédiatement visible et il n'y a qu'un seul déclencheur clair (l'obturateur),
/// au lieu d'un écran-invite suivi d'un duo de boutons concurrents.
@MainActor
struct AICameraCaptureArea: View {
    let proxy: CameraProxy
    let onCapture: (UIImage) -> Void
    let onImport: () -> Void
    @Binding var cameraStatus: AVAuthorizationStatus

    @State private var phase: CapturePhase = .ready
    /// Session AVFoundation impossible (simulateur, caméra absente ou occupée).
    @State private var sessionUnavailable = false

    /// Machine à états de l'obturateur.
    enum CapturePhase: Equatable {
        case ready
        case capturing
        case failed(String)
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
            fallback(CameraDeniedView())
        case .authorized:
            if Self.hasBackCamera && !sessionUnavailable {
                liveCapture
            } else {
                fallback(ScannerUnavailableView())
            }
        default: // .notDetermined : demande en cours
            requesting
        }
    }

    // MARK: - Capture en direct

    private var liveCapture: some View {
        ZStack {
            Color.black

            CameraCaptureView(proxy: proxy, onCapture: onCapture, onError: handleError)

            BlueprintOverlay()

            // Flash bref pendant la prise de vue (feedback anti double-tap).
            if phase == .capturing {
                Color.white.opacity(0.25)
            }

            VStack {
                Spacer()
                if case let .failed(message) = phase {
                    errorBanner(message)
                }
                shutterRow
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.l)
        }
        .clipped()
    }

    /// Obturateur centré + import discret en coin gauche (pattern app Appareil photo).
    private var shutterRow: some View {
        ZStack {
            shutterButton
            HStack {
                importButton
                Spacer()
            }
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

    private var importButton: some View {
        Button(action: onImport) {
            Image(systemName: "photo.on.rectangle")
                .font(.title3)
                .padding(Theme.Spacing.s)
                .background(.ultraThinMaterial, in: Circle())
        }
        .tint(Theme.gold)
        .accessibilityLabel("Importer une photo")
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

    private var requesting: some View {
        ZStack {
            Theme.surface
            ProgressView("Accès à la caméra…")
        }
    }

    /// Encadre une vue d'information (refus / indisponible) avec un repli import
    /// toujours visible, sur le fond de surface adaptatif (texte lisible).
    private func fallback<Content: View>(_ info: Content) -> some View {
        ZStack(alignment: .bottom) {
            Theme.surface
            info
            Button(action: onImport) {
                Label("Importer une photo", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.gold)
            .padding(Theme.Spacing.l)
        }
    }

    // MARK: - Erreurs & permission

    private func handleError(_ error: Error) {
        if case CameraCaptureController.CameraError.configurationFailed = error {
            // Session impossible : bascule vers le repli import (simulateur, caméra occupée).
            sessionUnavailable = true
        } else {
            phase = .failed("La capture a échoué. Réessayez ou importez une photo.")
        }
    }

    /// Demande l'autorisation caméra si nécessaire et met à jour le binding partagé.
    private func ensureCameraAccess() async {
        guard cameraStatus == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }
}
