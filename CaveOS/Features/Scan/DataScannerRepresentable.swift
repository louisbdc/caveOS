import SwiftUI
import UIKit
import VisionKit

/// Indique si le scanner de données en direct (VisionKit) est disponible
/// sur l'appareil courant (indisponible sur simulateur / matériel ancien).
@MainActor
enum LiveScannerAvailability {
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }
}

/// Wrapper SwiftUI autour de `DataScannerViewController` pour la
/// reconnaissance de texte en temps réel.
@MainActor
struct DataScannerRepresentable: UIViewControllerRepresentable {

    /// Callback appelé avec l'ensemble des lignes de texte actuellement détectées.
    var onRecognizedText: ([String]) -> Void

    /// Callback appelé avec la charge utile d'un code-barres détecté.
    var onRecognizedBarcode: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecognizedText: onRecognizedText, onRecognizedBarcode: onRecognizedBarcode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(), .barcode()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard LiveScannerAvailability.isAvailable else { return }
        try? uiViewController.startScanning()
    }

    static func dismantleUIViewController(
        _ uiViewController: DataScannerViewController,
        coordinator: Coordinator
    ) {
        uiViewController.stopScanning()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onRecognizedText: ([String]) -> Void
        private let onRecognizedBarcode: ((String) -> Void)?

        init(
            onRecognizedText: @escaping ([String]) -> Void,
            onRecognizedBarcode: ((String) -> Void)? = nil
        ) {
            self.onRecognizedText = onRecognizedText
            self.onRecognizedBarcode = onRecognizedBarcode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            emit(items: allItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            emit(items: allItems)
        }

        private func emit(items: [RecognizedItem]) {
            let lines: [String] = items.compactMap { item in
                if case let .text(text) = item {
                    return text.transcript
                }
                return nil
            }
            if !lines.isEmpty {
                onRecognizedText(lines)
            }

            guard let onRecognizedBarcode else { return }
            for item in items {
                if case let .barcode(barcode) = item,
                   let payload = barcode.payloadStringValue,
                   !payload.isEmpty {
                    onRecognizedBarcode(payload)
                }
            }
        }
    }
}

/// Vue affichée lorsque l'accès à la caméra a été refusé : explique et renvoie aux Réglages iOS.
struct CameraDeniedView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Accès caméra refusé")
                .font(.headline)
            Text("CaveOS a besoin de la caméra pour scanner vos étiquettes. Autorisez-la dans les Réglages iOS, ou importez une photo ci-dessous.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Ouvrir les Réglages iOS", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Vue de repli affichée lorsque le scanner en direct n'est pas disponible.
struct ScannerUnavailableView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "camera.metering.unknown")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Scanner indisponible")
                .font(.headline)
            Text("La caméra en direct n'est pas disponible sur cet appareil. Importez une photo de l'étiquette pour l'analyser.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
