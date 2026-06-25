import SwiftUI

/// Pastille « estimé » : marque un champ déduit par l'IA (passe 2), à vérifier.
///
/// L'UX « estimé » ne vit que dans le récapitulatif du scan : le modèle SwiftData
/// ne stocke pas la notion d'estimé. L'utilisateur confirme ou corrige la valeur
/// avant la création de la bouteille.
struct EstimatedBadge: View {
    var body: some View {
        Text("estimé")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.gold.opacity(0.18), in: Capsule())
            .foregroundStyle(Theme.gold)
            .accessibilityLabel("Champ estimé, à vérifier")
    }
}

/// En-tête de champ (titre discret) avec pastille « estimé » conditionnelle.
struct EstimatedFieldHeader: View {
    let title: String
    let isEstimated: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if isEstimated { EstimatedBadge() }
        }
    }
}

/// Champ texte estimable : une édition réelle de l'utilisateur confirme la valeur
/// et retire la marque « estimé » (via `onEdit`).
///
/// Le retrait n'est déclenché que si le champ est focalisé : un pré-remplissage
/// programmatique (réanalyse) modifie le texte sans focus et ne doit donc pas
/// effacer la pastille à tort.
struct EstimableTextField: View {
    let title: String
    @Binding var text: String
    let isEstimated: Bool
    let onEdit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            EstimatedFieldHeader(title: title, isEstimated: isEstimated)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onChange(of: text) { _, _ in
                    if isFocused { onEdit() }
                }
        }
    }
}
