import SwiftUI
import PhotosUI
import Vision
import VisionKit
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation
import UIKit

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
    @State private var scanFeedback: String?
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

    // Moteur d'analyse choisi (Appareil / IA), persisté.
    // Migration : un ancien rawValue "mistral"/"gemini" ne correspond plus à un
    // case → `@AppStorage` (RawRepresentable) retombe sur la valeur par défaut
    // `.device` sans crash.
    @AppStorage(ScanEngine.storageKey) private var scanEngine = ScanEngine.device
    // Dernière photo (capturée ou importée), conservée pour réanalyse au changement de moteur.
    @State private var lastImage: UIImage?
    // Indique que l'IA a échoué et que l'analyse locale a pris le relais.
    @State private var usedFallback = false
    // Moteur ayant réellement produit la dernière analyse (≠ moteur sélectionné si fallback).
    @State private var analysisSource: ScanEngine?
    // Évite de décompter deux fois le quota IA pour une même photo (une réanalyse
    // au changement de moteur ne doit pas re-décompter). Remis à false à chaque
    // nouvelle photo capturée/importée.
    @State private var aiScanConsumed = false

    // Champs déduits par l'IA (passe 2), éditables et confirmables dans le récap.
    @State private var color: WineColor?
    @State private var wineType: WineType?
    @State private var region: String = ""
    @State private var country: String = ""
    @State private var peakFrom: Int?
    @State private var peakTo: Int?
    // Clés des champs marqués « estimé » (déductions IA non encore confirmées).
    @State private var inferredFields: Set<String> = []

    // Capture IA plein écran (preview AVFoundation + blueprint bouteille) et son
    // pont d'action partagé pour déclencher le shutter sans recréer le contrôleur.
    @State private var captureProxy = CameraProxy()
    @State private var showAICapture = false
    // Import demandé depuis l'écran de capture : présenté après fermeture du cover
    // (évite la course « présenter pendant la fermeture »).
    @State private var pendingImport = false
    @State private var showPhotoPicker = false

    var body: some View {
        NavigationStack {
            // Le scan « Appareil » est gratuit et illimité : aucun gating global.
            // L'accès à l'IA est géré au niveau du sélecteur (quota / paywall).
            scannerContent
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
                .fullScreenCover(isPresented: $showAICapture, onDismiss: handleCaptureCoverDismiss) {
                    aiCaptureCover
                }
                .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
                .task {
                    loadReferenceData()
                    // IA persistée mais quota épuisé (non-Pro) : on repasse sur l'appareil
                    // pour ne pas afficher un mode IA qui retomberait en local silencieux.
                    if scanEngine.isAI && !store.canUseAIScan() {
                        scanEngine = .device
                    }
                }
        }
    }

    // MARK: - Capture IA (plein écran)

    private var aiCaptureCover: some View {
        AICaptureView(
            proxy: captureProxy,
            onCapture: { image in
                lastImage = image
                aiScanConsumed = false
                showAICapture = false
                Task { await analyzeImage(image) }
            },
            onImport: {
                // L'appelant ferme le cover puis présente le PhotosPicker.
                pendingImport = true
                showAICapture = false
            },
            cameraStatus: $cameraStatus
        )
    }

    private func handleCaptureCoverDismiss() {
        guard pendingImport else { return }
        pendingImport = false
        showPhotoPicker = true
    }

    // MARK: - Contenu principal (scan autorisé)

    @ViewBuilder
    private var scannerContent: some View {
        VStack(spacing: 0) {
            // Zone de capture : plein écran tant qu'aucun résultat, puis réduite pour
            // laisser la place au récap défilable (bouton Valider épinglé en bas).
            captureArea
                .frame(maxHeight: hasAnalyzed ? 220 : .infinity)

            if hasAnalyzed {
                ScrollView {
                    controls
                }
                .background(.ultraThinMaterial)

                validateButton
                    .padding(Theme.Spacing.m)
                    .background(.ultraThinMaterial)
            } else {
                controls
                    .background(.ultraThinMaterial)
            }
        }
    }

    @ViewBuilder
    private var captureArea: some View {
        if scanEngine.isAI {
            aiCapturePrompt
        } else {
            deviceCaptureArea
        }
    }

    /// Aperçu de scan live « Appareil » (DataScanner Apple Vision, hors-ligne).
    @ViewBuilder
    private var deviceCaptureArea: some View {
        if cameraStatus == .denied || cameraStatus == .restricted {
            CameraDeniedView()
        } else if LiveScannerAvailability.isAvailable {
            ZStack {
                DataScannerRepresentable(
                    onRecognizedText: { lines in
                        recognizedLines = lines
                    },
                    onRecognizedBarcode: { payload in
                        if let ean = Self.validEAN(payload) {
                            scannedEAN = ean
                        }
                    }
                )
                .ignoresSafeArea(edges: .horizontal)
                .task { await ensureCameraAccess() }

                // Même silhouette de cadrage qu'en mode IA, mais voile très léger
                // pour ne pas gêner la lecture OCR en direct.
                BlueprintOverlay(dimming: 0.12)
            }
        } else {
            ScannerUnavailableView()
        }
    }

    /// Invite à la capture IA : la preview AVFoundation + blueprint vit dans
    /// `AICaptureView`, présentée en plein écran via le bouton « Prendre une photo ».
    private var aiCapturePrompt: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 52))
                .foregroundStyle(Theme.gold)
                .accessibilityHidden(true)
            Text("Scan par IA")
                .font(.headline)
            Text("Cadrez l'étiquette dans la silhouette puis prenez la photo. L'IA lit l'étiquette et complète les informations du vin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: Theme.Spacing.m) {
            enginePicker
            actionButtons

            if isProcessingPhoto {
                ProgressView("Analyse de la photo…")
            }

            if let scanFeedback {
                Label(scanFeedback, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hasAnalyzed {
                editableSummary
            }
        }
        .padding(Theme.Spacing.m)
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task { await processPhoto(newValue) }
        }
        .onChange(of: scanEngine) { _, newValue in
            // L'IA est accessible aux non-Pro tant qu'il reste des scans IA gratuits ;
            // sinon on rebascule sur l'appareil et on propose Pro.
            if newValue.isAI && !store.canUseAIScan() {
                scanEngine = .device
                showPaywall = true
                return
            }
            // Réanalyse la dernière photo avec le nouveau moteur, si disponible.
            if let image = lastImage {
                Task { await analyzeImage(image) }
            }
        }
    }

    /// Boutons d'action adaptés au moteur : capture/import en IA, import/analyse en local.
    @ViewBuilder
    private var actionButtons: some View {
        if scanEngine.isAI {
            HStack(spacing: Theme.Spacing.m) {
                Button {
                    showAICapture = true
                } label: {
                    Label("Prendre une photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Importer", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        } else {
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
        }
    }

    // MARK: - Sélecteur de moteur

    @ViewBuilder
    private var enginePicker: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Picker("Moteur d'analyse", selection: $scanEngine) {
                ForEach(ScanEngine.allCases) { engine in
                    Text(engine.label).tag(engine)
                }
            }
            .pickerStyle(.segmented)

            Text(scanEngine.isAI
                ? (store.isPro
                    ? "IA : Mistral + Gemini, lecture puis déduction."
                    : "IA : \(store.freeScansRemaining) scan(s) gratuit(s) restant(s).")
                : "Analyse sur l'appareil, hors-ligne et gratuite.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Récapitulatif éditable

    private var editableSummary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Champs détectés")
                .font(.headline)

            if let analysisSource {
                Label(analysisSource.analysisLabel, systemImage: analysisSource.systemImage)
                    .font(.caption)
                    .foregroundStyle(analysisSource.isAI ? Theme.gold : .secondary)
            }

            labeledField("Domaine", text: $producer)
            labeledField("Cuvée", text: $wineName)
            labeledField("Millésime", text: $vintageText)
                .keyboardType(.numberPad)
            labeledField("Appellation", text: $appellation)

            EstimableTextField(
                title: "Cépages (séparés par des virgules)",
                text: $grapesText,
                isEstimated: inferredFields.contains(ScannedLabel.Field.grapes),
                onEdit: { inferredFields.remove(ScannedLabel.Field.grapes) }
            )

            colorPicker
            typePicker

            EstimableTextField(
                title: "Région",
                text: $region,
                isEstimated: inferredFields.contains(ScannedLabel.Field.region),
                onEdit: { inferredFields.remove(ScannedLabel.Field.region) }
            )
            // « Pays » et « Apogée estimée » volontairement absents du récap (v1) :
            // il n'y a pas de Wine.country à persister, et l'apogée est calculée par
            // ApogeeEngine (cépages × région × stockage) pour rester cohérente avec
            // la fiche bouteille — afficher une seconde fenêtre IA induirait en erreur.

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

    /// Picker couleur (pré-rempli par l'IA) : sélectionner confirme et retire le badge.
    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            EstimatedFieldHeader(
                title: "Couleur",
                isEstimated: inferredFields.contains(ScannedLabel.Field.color)
            )
            Picker("Couleur", selection: Binding(
                get: { color },
                set: { newValue in
                    color = newValue
                    inferredFields.remove(ScannedLabel.Field.color)
                }
            )) {
                Text("Non précisé").tag(WineColor?.none)
                ForEach(WineColor.allCases) { c in
                    Text(c.label).tag(WineColor?.some(c))
                }
            }
            .pickerStyle(.menu)
            .tint(color?.tint ?? .secondary)
        }
    }

    /// Picker type de vin (pré-rempli par l'IA) : sélectionner confirme et retire le badge.
    private var typePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            EstimatedFieldHeader(
                title: "Type",
                isEstimated: inferredFields.contains(ScannedLabel.Field.wineType)
            )
            Picker("Type", selection: Binding(
                get: { wineType },
                set: { newValue in
                    wineType = newValue
                    inferredFields.remove(ScannedLabel.Field.wineType)
                }
            )) {
                Text("Non précisé").tag(WineType?.none)
                ForEach(WineType.allCases) { t in
                    Text(t.label).tag(WineType?.some(t))
                }
            }
            .pickerStyle(.menu)
        }
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

    // MARK: - Permission caméra

    /// Demande l'autorisation caméra si nécessaire et met à jour l'état affiché.
    private func ensureCameraAccess() async {
        guard cameraStatus == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Valide un code-barres : seul un EAN/UPC (8 à 13 chiffres) est conservé.
    static func validEAN(_ payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...13).contains(trimmed.count), trimmed.allSatisfy(\.isNumber) else { return nil }
        return trimmed
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
        // Reconnaissance Apple Vision : l'analyse provient bien de l'appareil.
        analysisSource = .device
        applyAnalyzedLabel(label)
    }

    /// Applique un label analysé (local ou IA) aux champs éditables et calcule le
    /// message de retour adéquat.
    private func applyAnalyzedLabel(_ label: ScannedLabel) {
        applyToFields(label)
        hasAnalyzed = true

        // Feedback explicite si rien d'exploitable n'a été reconnu.
        let nothingDetected = (label.wineName ?? "").isEmpty
            && (label.producer ?? "").isEmpty
            && label.vintage == nil
            && (label.appellation ?? "").isEmpty
            && label.grapes.isEmpty
            && (scannedEAN ?? "").isEmpty

        if nothingDetected {
            scanFeedback = "Aucune information détectée. Rapprochez l'étiquette, améliorez l'éclairage et réessayez — ou complétez les champs à la main."
        } else if usedFallback {
            scanFeedback = "Analyse effectuée hors-ligne sur l'appareil (IA indisponible)."
        } else {
            scanFeedback = nil
        }
    }

    private func applyToFields(_ label: ScannedLabel) {
        producer = label.producer ?? ""
        wineName = label.wineName ?? ""
        vintageText = label.vintage.map(String.init) ?? ""
        appellation = label.appellation ?? ""
        grapesText = label.grapes.joined(separator: ", ")
        detectedFormat = label.format
        detectedABV = label.abv
        color = label.color
        wineType = label.wineType
        region = label.region ?? ""
        country = label.country ?? ""
        peakFrom = label.peakFrom
        peakTo = label.peakTo
        inferredFields = label.inferredFields
    }

    /// `true` si le label porte au moins un champ exploitable (≠ étiquette illisible) :
    /// sert à ne décompter le quota IA que pour un scan réellement utile.
    private static func isExploitable(_ label: ScannedLabel) -> Bool {
        label.wineName != nil || label.producer != nil || label.ean != nil
            || label.vintage != nil || label.appellation != nil || !label.grapes.isEmpty
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
        label.color = color
        label.wineType = wineType
        label.region = region.isEmpty ? nil : region
        label.country = country.isEmpty ? nil : country
        label.peakFrom = peakFrom
        label.peakTo = peakTo
        label.inferredFields = inferredFields

        // Le décompte du quota IA a déjà eu lieu au scan réussi (voir analyzeImage) :
        // valider ou annuler ne (dé)compte plus rien. Le device OCR reste gratuit illimité.
        onComplete(label)
        dismiss()
    }

    // MARK: - Import photo (Vision sur image fixe)

    private func processPhoto(_ item: PhotosPickerItem) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                scanFeedback = "Impossible de charger cette image. Réessayez avec une autre photo."
                return
            }
            lastImage = uiImage
            aiScanConsumed = false
            await analyzeImage(uiImage)
        } catch {
            scanFeedback = "L'analyse de la photo a échoué. Réessayez avec une image plus nette."
        }
    }

    /// Analyse une image selon le moteur choisi. En mode IA (quota gratuit ou Pro),
    /// délègue au serveur (Mistral + Gemini + déduction) ; en cas d'échec réseau,
    /// bascule automatiquement sur l'OCR local.
    private func analyzeImage(_ uiImage: UIImage) async {
        usedFallback = false

        if scanEngine.isAI, store.canUseAIScan() {
            do {
                let label = try await AIScanService.scan(image: uiImage)
                recognizedLines = label.rawLines
                analysisSource = scanEngine
                // Décompte le quota IA dès qu'un scan renvoie un résultat exploitable,
                // une seule fois par photo : un non-Pro ne peut plus lire les champs
                // puis « Annuler » pour scanner gratuitement à l'infini.
                if !aiScanConsumed, Self.isExploitable(label) {
                    store.consumeFreeScan()
                    aiScanConsumed = true
                }
                applyAnalyzedLabel(label)
                return
            } catch {
                // Fallback silencieux vers l'analyse embarquée.
                usedFallback = true
            }
        }

        await analyzeLocally(uiImage)
    }

    /// Analyse 100 % locale : correction de perspective + OCR Apple Vision + parsing.
    private func analyzeLocally(_ uiImage: UIImage) async {
        guard let cgImage = uiImage.cgImage else {
            scanFeedback = "Impossible d'analyser cette image. Réessayez avec une autre photo."
            return
        }
        // Redresse l'étiquette (courbe/inclinée) avant l'OCR pour fiabiliser la lecture.
        let prepared = await perspectiveCorrected(cgImage)
        do {
            let lines = try await recognizeText(in: prepared)
            recognizedLines = lines
            analyze(lines: lines)
        } catch {
            scanFeedback = "L'analyse de la photo a échoué. Réessayez avec une image plus nette."
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
