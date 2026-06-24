import SwiftUI
import PhotosUI
import Vision
import VisionKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Vue de scan d'étiquette : capture en direct (VisionKit) ou import photo
/// (Vision sur image fixe), puis analyse via `LabelParser` et récapitulatif éditable.
@MainActor
struct ScanView: View {
    let onComplete: (ScannedLabel) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(StoreManager.self) private var store

    // Référentiels chargés depuis la base pour le matching.
    @State private var knownAppellations: [String] = []
    @State private var knownGrapes: [String] = []

    // Lignes OCR brutes accumulées.
    @State private var recognizedLines: [String] = []

    // Code-barres (EAN) capté en direct ou détecté.
    @State private var scannedEAN: String?

    // Format et degré détectés par l'analyse (affichés en lecture seule).
    @State private var detectedFormat: String?
    @State private var detectedABV: String?

    // Champs détectés / éditables.
    @State private var producer: String = ""
    @State private var wineName: String = ""
    @State private var vintageText: String = ""
    @State private var appellation: String = ""
    @State private var grapesText: String = ""

    @State private var hasAnalyzed = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if store.canUseScan() {
                    scannerContent
                } else {
                    gatingContent
                }
            }
            .navigationTitle("Scanner une étiquette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .task { loadReferenceData() }
        }
    }

    // MARK: - Contenu principal (scan autorisé)

    @ViewBuilder
    private var scannerContent: some View {
        VStack(spacing: 0) {
            captureArea
                .frame(maxHeight: .infinity)

            controls
                .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var captureArea: some View {
        if LiveScannerAvailability.isAvailable {
            DataScannerRepresentable(
                onRecognizedText: { lines in
                    recognizedLines = lines
                },
                onRecognizedBarcode: { payload in
                    scannedEAN = payload
                }
            )
            .ignoresSafeArea(edges: .horizontal)
        } else {
            ScannerUnavailableView()
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Importer une photo", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    analyze(lines: recognizedLines)
                } label: {
                    Label("Analyser", systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(recognizedLines.isEmpty && !hasAnalyzed)
            }

            if isProcessingPhoto {
                ProgressView("Analyse de la photo…")
            }

            if hasAnalyzed {
                editableSummary
                validateButton
            }
        }
        .padding(Theme.Spacing.m)
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task { await processPhoto(newValue) }
        }
    }

    // MARK: - Récapitulatif éditable

    private var editableSummary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Champs détectés")
                .font(.headline)

            labeledField("Domaine", text: $producer)
            labeledField("Cuvée", text: $wineName)
            labeledField("Millésime", text: $vintageText)
                .keyboardType(.numberPad)
            labeledField("Appellation", text: $appellation)
            labeledField("Cépages (séparés par des virgules)", text: $grapesText)

            if let detectedFormat {
                readOnlyField("Format", value: detectedFormat)
            }
            if let detectedABV {
                readOnlyField("Degré", value: detectedABV)
            }
            if let scannedEAN {
                readOnlyField("Code-barres (EAN)", value: scannedEAN, monospaced: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func readOnlyField(_ title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .body.monospaced() : .body)
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var validateButton: some View {
        Button {
            validate()
        } label: {
            Label("Valider", systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    // MARK: - Gating (scan non autorisé)

    private var gatingContent: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.gold)
            Text("Scans épuisés")
                .font(.headline)
            Text("Vous avez utilisé tous vos scans gratuits. Passez à CaveOS Pro pour scanner sans limite.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showPaywall = true
            } label: {
                Text("Découvrir Pro")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Données de référence

    private func loadReferenceData() {
        let repository = CaveRepository(context: context)
        knownAppellations = repository.appellations().map(\.name)
        knownGrapes = repository.grapes().map(\.name)
    }

    // MARK: - Analyse

    private func analyze(lines: [String]) {
        let label = LabelParser.parse(
            lines: lines,
            knownAppellations: knownAppellations,
            knownGrapes: knownGrapes
        )
        applyToFields(label)
        hasAnalyzed = true
    }

    private func applyToFields(_ label: ScannedLabel) {
        producer = label.producer ?? ""
        wineName = label.wineName ?? ""
        vintageText = label.vintage.map(String.init) ?? ""
        appellation = label.appellation ?? ""
        grapesText = label.grapes.joined(separator: ", ")
        detectedFormat = label.format
        detectedABV = label.abv
    }

    private func validate() {
        var label = ScannedLabel()
        label.rawLines = recognizedLines
        label.ean = scannedEAN
        label.format = detectedFormat
        label.abv = detectedABV
        label.producer = producer.isEmpty ? nil : producer
        label.wineName = wineName.isEmpty ? nil : wineName
        label.vintage = Int(vintageText.trimmingCharacters(in: .whitespaces))
        label.appellation = appellation.isEmpty ? nil : appellation
        label.grapes = grapesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        store.consumeFreeScan()
        onComplete(label)
        dismiss()
    }

    // MARK: - Import photo (Vision sur image fixe)

    private func processPhoto(_ item: PhotosPickerItem) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else {
                return
            }
            // Redresse l'étiquette (courbe/inclinée) avant l'OCR pour fiabiliser la lecture.
            let prepared = await perspectiveCorrected(cgImage)
            let lines = try await recognizeText(in: prepared)
            recognizedLines = lines
            analyze(lines: lines)
        } catch {
            // En cas d'échec OCR, on conserve l'état courant.
        }
    }

    /// Détecte le plus grand rectangle (l'étiquette) et applique une correction
    /// de perspective (CIPerspectiveCorrection) pour redresser les étiquettes
    /// courbes/inclinées avant l'OCR. Renvoie l'image d'origine si rien n'est détecté.
    private func perspectiveCorrected(_ cgImage: CGImage) async -> CGImage {
        await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, _ in
                let rects = request.results as? [VNRectangleObservation] ?? []
                guard let rect = rects.max(by: {
                    ($0.boundingBox.width * $0.boundingBox.height) < ($1.boundingBox.width * $1.boundingBox.height)
                }) else {
                    continuation.resume(returning: cgImage)
                    return
                }

                let ci = CIImage(cgImage: cgImage)
                let w = ci.extent.width, h = ci.extent.height
                func denorm(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: p.y * h) }

                let filter = CIFilter.perspectiveCorrection()
                filter.inputImage = ci
                filter.topLeft = denorm(rect.topLeft)
                filter.topRight = denorm(rect.topRight)
                filter.bottomLeft = denorm(rect.bottomLeft)
                filter.bottomRight = denorm(rect.bottomRight)

                let context = CIContext()
                guard let output = filter.outputImage,
                      let corrected = context.createCGImage(output, from: output.extent) else {
                    continuation.resume(returning: cgImage)
                    return
                }
                continuation.resume(returning: corrected)
            }
            request.maximumObservations = 1
            request.minimumConfidence = 0.6
            request.minimumAspectRatio = 0.2
            request.minimumSize = 0.2

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: cgImage)
            }
        }
    }

    private func recognizeText(in cgImage: CGImage) async throws -> [String] {
        let customWords = makeCustomWords()
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                // On lit plusieurs candidats par observation mais retient le meilleur.
                let lines = observations.compactMap { observation -> String? in
                    let candidates = observation.topCandidates(10)
                    return candidates.first?.string
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["fr-FR", "en-US", "it-IT", "es-ES"]
            request.minimumTextHeight = 0.012
            request.customWords = customWords

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Vocabulaire spécialisé injecté dans l'OCR : cépages, appellations et mentions usuelles.
    private func makeCustomWords() -> [String] {
        let mentions = [
            "Grand Cru",
            "Premier Cru",
            "Appellation",
            "Contrôlée",
            "Mis en bouteille au château"
        ]
        return knownGrapes + knownAppellations + mentions
    }
}
