import SwiftUI

/// Écran d'enrichissement opt-in : interroge un serveur distant pour récupérer
/// la fenêtre d'apogée d'un vin. Reste non bloquant et fonctionnel hors-ligne.
struct EnrichmentView: View {

    @State private var isEnabled = EnrichmentService.isEnabled
    @State private var name = ""
    @State private var vintageText = ""

    @State private var isSearching = false
    @State private var result: EnrichmentResult?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            activationSection

            if isEnabled {
                searchSection

                if isSearching {
                    Section {
                        HStack(spacing: Theme.Spacing.s) {
                            ProgressView()
                            Text("Recherche en cours…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let result {
                    resultSection(result)
                }

                if let errorMessage {
                    errorSection(errorMessage)
                }
            }
        }
        .navigationTitle("Enrichissement")
    }

    // MARK: - Activation

    @ViewBuilder
    private var activationSection: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                Label("Activer l'enrichissement", systemImage: "sparkles")
            }
            .onChange(of: isEnabled) { _, enabled in
                EnrichmentService.isEnabled = enabled
                if !enabled {
                    result = nil
                    errorMessage = nil
                }
            }
        } header: {
            Text("Service distant")
        } footer: {
            Text("Optionnel. Une fois activé, recherchez un vin ci-dessous pour récupérer manuellement sa fenêtre d'apogée depuis la base distante. Rien n'est envoyé automatiquement ; l'app reste pleinement fonctionnelle hors-ligne.")
        }
    }

    // MARK: - Recherche

    @ViewBuilder
    private var searchSection: some View {
        Section {
            TextField("Nom du vin", text: $name)
                .textInputAutocapitalization(.words)

            TextField("Millésime (optionnel)", text: $vintageText)
                .keyboardType(.numberPad)

            Button {
                search()
            } label: {
                Label("Rechercher", systemImage: "magnifyingglass")
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
        } header: {
            Text("Rechercher un vin")
        }
    }

    // MARK: - Résultat

    @ViewBuilder
    private func resultSection(_ result: EnrichmentResult) -> some View {
        Section("Résultat") {
            LabeledContent("Vin", value: result.name)

            if let vintage = result.vintage {
                LabeledContent("Millésime", value: String(vintage))
            }
            if let regionName = result.regionName {
                LabeledContent("Région", value: regionName)
            }
            if let matchedOn = result.matchedOn {
                LabeledContent("Correspondance", value: matchedOn)
            }

            if hasApogee(result) {
                LabeledContent("Fenêtre d'apogée", value: apogeeWindowText(result))
            } else {
                Text("Aucune fenêtre d'apogée disponible.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Erreur

    @ViewBuilder
    private func errorSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func hasApogee(_ result: EnrichmentResult) -> Bool {
        result.drinkFrom != nil || result.peak != nil || result.drinkBy != nil
    }

    private func apogeeWindowText(_ result: EnrichmentResult) -> String {
        let from = result.drinkFrom.map(String.init) ?? "?"
        let peak = result.peak.map(String.init) ?? "?"
        let by = result.drinkBy.map(String.init) ?? "?"
        return "\(from) → apogée \(peak) → \(by)"
    }

    // MARK: - Actions

    private func search() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let vintage = Int(vintageText.trimmingCharacters(in: .whitespaces))

        result = nil
        errorMessage = nil
        isSearching = true

        Task {
            do {
                let enriched = try await EnrichmentService.enrich(name: trimmedName, vintage: vintage)
                result = enriched
            } catch {
                let description = (error as? LocalizedError)?.errorDescription
                errorMessage = description ?? "Service indisponible, l'app reste fonctionnelle hors-ligne."
            }
            isSearching = false
        }
    }
}
