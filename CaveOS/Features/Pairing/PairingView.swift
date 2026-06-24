import SwiftUI
import SwiftData

/// Accords mets-vins : l'utilisateur décrit son plat, l'app recommande
/// des couleurs/styles et propose les bouteilles correspondantes de sa cave.
struct PairingView: View {

    @Query private var bottles: [Bottle]

    @State private var dishInput: String = ""
    @State private var suggestion: PairingSuggestion?

    private let quickCategories: [(label: String, dish: String, symbol: String)] = [
        ("Viande rouge", "viande rouge", "fork.knife"),
        ("Volaille", "poulet rôti", "bird"),
        ("Poisson", "poisson grillé", "fish"),
        ("Fruits de mer", "plateau de fruits de mer", "water.waves"),
        ("Fromage", "plateau de fromages", "triangle"),
        ("Dessert", "dessert au chocolat", "birthday.cake"),
        ("Épicé", "curry épicé", "flame"),
        ("Gratin", "gratin dauphinois", "square.stack.3d.up"),
        ("Charcuterie", "planche de charcuterie", "takeoutbag.and.cup.and.straw"),
        ("Légumes", "légumes de saison", "leaf")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    inputSection
                    quickCategoriesSection

                    if let suggestion {
                        suggestionSection(suggestion)
                        matchingBottlesSection(suggestion)
                    }
                }
                .padding(Theme.Spacing.m)
            }
            .navigationTitle("Accords mets-vins")
            .background(Theme.surface.opacity(0.4))
        }
    }

    // MARK: - Sections

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Qu'est-ce que je mange ?")
                .font(.headline)
            HStack {
                TextField("ex. gratin dauphinois", text: $dishInput)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit(runSuggestion)
                Button(action: runSuggestion) {
                    Image(systemName: "wand.and.stars")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.wine)
                .disabled(dishInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .cardStyle()
    }

    private var quickCategoriesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Catégories rapides")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Theme.Spacing.s)],
                      spacing: Theme.Spacing.s) {
                ForEach(quickCategories, id: \.label) { category in
                    Button {
                        dishInput = category.dish
                        suggestion = PairingEngine.suggest(forDish: category.dish)
                    } label: {
                        Label(category.label, systemImage: category.symbol)
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.s)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.wine)
                }
            }
        }
    }

    private func suggestionSection(_ suggestion: PairingSuggestion) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Recommandation")
                .font(.headline)

            Text(suggestion.rationale)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !suggestion.colors.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Couleurs conseillées")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowRow(spacing: Theme.Spacing.xs) {
                        ForEach(suggestion.colors) { color in
                            StatusBadge(text: color.label, color: color.tint, systemImage: "drop.fill")
                        }
                    }
                }
            }

            if !suggestion.styleHints.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Styles à privilégier")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowRow(spacing: Theme.Spacing.xs) {
                        ForEach(suggestion.styleHints, id: \.self) { hint in
                            StatusBadge(text: hint, color: Theme.gold)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func matchingBottlesSection(_ suggestion: PairingSuggestion) -> some View {
        let matches = PairingEngine.matchingBottles(for: suggestion, in: bottles)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Dans ma cave")
                .font(.headline)

            if matches.isEmpty {
                let hasBottlesInCellar = bottles.contains { $0.state == .inCellar }
                Text(hasBottlesInCellar
                    ? "Aucune bouteille de votre cave ne correspond à cet accord pour le moment."
                    : "Vous n'avez aucune bouteille en cave actuellement. Ajoutez-en pour voir vos accords.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
            } else {
                ForEach(matches) { bottle in
                    bottleRow(bottle)
                }
            }
        }
    }

    private func bottleRow(_ bottle: Bottle) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .fill((bottle.wine?.color.tint ?? Theme.slate).opacity(0.85))
                .frame(width: 6, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.wine?.name ?? "Vin sans nom")
                    .font(.subheadline.weight(.semibold))
                if let producer = bottle.wine?.producer?.name, !producer.isEmpty {
                    Text(producer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let vintage = bottle.vintage, vintage > 0 {
                    Text(verbatim: "\(vintage)")
                        .font(.caption.weight(.semibold))
                }
                Text("×\(bottle.quantity)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Actions

    private func runSuggestion() {
        let trimmed = dishInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        suggestion = PairingEngine.suggest(forDish: trimmed)
    }
}

// MARK: - Disposition fluide (wrapping de badges)

/// Layout maison qui répartit ses enfants sur plusieurs lignes selon la largeur disponible.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: maxWidth == .infinity ? rows.map(\.width).max() ?? 0 : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct RowLayout {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [RowLayout] {
        var rows: [RowLayout] = []
        var current = RowLayout()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.width == 0 ? size.width : current.width + spacing + size.width
            if projected > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = RowLayout()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = projected
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
