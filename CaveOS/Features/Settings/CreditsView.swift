import SwiftUI

/// Crédite les sources de données vin embarquées et leurs licences.
/// CaveOS est offline-first : ces données sont intégrées à l'application.
struct CreditsView: View {
    var body: some View {
        List {
            Section {
                Text("Les données vin de CaveOS sont embarquées dans l'application : producteurs, régions, appellations, cépages et fenêtres d'apogée. CaveOS fonctionne entièrement hors-ligne (offline-first), sans serveur ni compte.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Sources de données") {
                creditRow(
                    title: "Wikidata",
                    license: "Licence CC0 1.0 (domaine public)",
                    detail: "Cépages, producteurs et identifiants associés.",
                    systemImage: "globe"
                )
                creditRow(
                    title: "INAO via data.gouv.fr",
                    license: "Licence Ouverte v1.0 (Etalab)",
                    detail: "Appellations d'origine et codes INAO français.",
                    systemImage: "checkmark.seal"
                )
                creditRow(
                    title: "LWIN / Liv-ex",
                    license: "Creative Commons",
                    detail: "Identifiants standardisés des vins (LWIN).",
                    systemImage: "barcode"
                )
            }

            Section {
                Text("Conformément aux licences, CaveOS attribue ces sources et conserve leurs mentions. Les éventuelles modifications apportées aux données restent compatibles avec les termes des licences citées.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Attribution")
            }
        }
        .navigationTitle("Sources & crédits")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Ligne d'attribution pour une source de données.
    @ViewBuilder
    private func creditRow(
        title: String,
        license: String,
        detail: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(license)
                .font(.subheadline)
                .foregroundStyle(Theme.wine)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

#Preview {
    NavigationStack {
        CreditsView()
    }
}
