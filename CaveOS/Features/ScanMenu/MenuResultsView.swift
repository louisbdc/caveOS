import SwiftUI
import SwiftData

/// Écran de résultats de la carte des vins scannée.
/// Permet à l'utilisateur d'indiquer son plat, de trier les vins et
/// de visualiser les badges (accord, valeur, apogée, cave).
struct MenuResultsView: View {
    @Environment(\.modelContext) private var context

    let wines: [ScannedMenuWine]
    /// La carte dépassait la limite serveur : seuls les premiers vins sont remontés.
    var truncated: Bool = false
    /// `true` si le résultat provient du repli Vision local (pas du serveur IA).
    var degraded: Bool = false

    @State private var dish: String = ""
    @State private var sort: MenuSort = .value

    private static let quickCategories: [(label: String, dish: String, symbol: String)] = [
        ("Viande rouge",   "viande rouge",                 "fork.knife"),
        ("Volaille",       "poulet rôti",                  "bird"),
        ("Poisson",        "poisson grillé",               "fish"),
        ("Fruits de mer",  "plateau de fruits de mer",     "water.waves"),
        ("Fromage",        "plateau de fromages",          "triangle"),
        ("Dessert",        "dessert au chocolat",          "birthday.cake"),
        ("Épicé",          "curry épicé",                  "flame"),
        ("Gratin",         "gratin dauphinois",            "square.stack.3d.up"),
        ("Charcuterie",    "planche de charcuterie",       "takeoutbag.and.cup.and.straw"),
        ("Légumes",        "légumes de saison",            "leaf")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if degraded {
                        Label("Résultat en mode local — connexion indisponible. Prix et enrichissements non disponibles.", systemImage: "wifi.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle()
                    }
                    dishSection
                    sortSection
                    resultsSection
                }
                .padding(Theme.Spacing.m)
            }
            .navigationTitle("Résultats de la carte")
            .navigationBarTitleDisplayMode(.inline)
            .background(Theme.surface.opacity(0.4))
        }
    }

    // MARK: - Sections

    private var dishSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Avec quel plat ?")
                .font(.headline)

            TextField("ex. entrecôte, poisson grillé…", text: $dish)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)

            Text("Catégories rapides")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: Theme.Spacing.s)],
                spacing: Theme.Spacing.s
            ) {
                ForEach(Self.quickCategories, id: \.label) { category in
                    Button {
                        dish = category.dish
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
        .cardStyle()
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Trier par")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Tri", selection: $sort) {
                Text("Valeur").tag(MenuSort.value)
                Text("Prix").tag(MenuSort.price)
                Text("Accord")
                    .tag(MenuSort.pairing)
                    .disabled(dishIsEmpty)
            }
            .pickerStyle(.segmented)
            .onChange(of: dish) { _, newDish in
                if newDish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   sort == .pairing {
                    sort = .value
                }
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("\(ranked.count) vin\(ranked.count == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if truncated {
                Label("Liste longue : seuls les premiers vins de la carte ont été lus.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(ranked) { item in
                MenuWineRow(item: item)
            }
        }
    }

    // MARK: - Computed state

    private var dishIsEmpty: Bool {
        dish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Vins classés et triés, calculés synchroniquement depuis le contexte SwiftData.
    /// Pré-charge vins et régions une seule fois pour éviter des requêtes N×M.
    private var ranked: [RankedMenuWine] {
        let repo = CaveRepository(context: context)
        let allWines = repo.fetchWines()
        let allRegions = repo.regions()
        let currentYear = Calendar.current.component(.year, from: .now)
        let trimmedDish = dish.trimmingCharacters(in: .whitespacesAndNewlines)

        let tierLookup: (String?) -> QualityTier? = { name in
            guard let name else { return nil }
            let normalized = MenuMatching.normalize(name)
            return allRegions.first { MenuMatching.normalize($0.name) == normalized }?.qualityTier
        }

        let cellarLookup: (ScannedMenuWine) -> (count: Int, score: Int?) = { w in
            let wine = allWines.first { candidate in
                MenuMatching.matches(
                    candidateProducer: w.producer,
                    candidateName: w.wineName,
                    wineProducer: candidate.producer?.name,
                    wineName: candidate.name
                )
            }
            let count = wine?.bottles
                .filter { $0.state == .inCellar }
                .reduce(0) { $0 + $1.quantity } ?? 0
            let score = bestScore(wine: wine)
            return (count, score)
        }

        let result = MenuRankingEngine.rank(
            wines,
            dish: trimmedDish,
            tierLookup: tierLookup,
            cellarLookup: cellarLookup,
            now: currentYear
        )
        return MenuRankingEngine.sort(result, by: sort)
    }

    // MARK: - Helpers

    /// Meilleure note `/100` trouvée parmi les dégustations de toutes les bouteilles du vin.
    private func bestScore(wine: Wine?) -> Int? {
        wine?.bottles
            .flatMap(\.tastingNotes)
            .compactMap(\.score)
            .max()
    }
}

// MARK: - Preview

#if DEBUG
#Preview("MenuResultsView") {
    let wines: [ScannedMenuWine] = [
        PreviewMenuWine.make(lineIndex: 0, producer: "Château Pichon Baron",
                             name: "Pichon Baron", vintage: 2019, price: 95.0),
        PreviewMenuWine.make(lineIndex: 1, producer: "Domaine Leflaive",
                             name: "Puligny-Montrachet", vintage: 2021, price: 68.0),
        PreviewMenuWine.make(lineIndex: 2, producer: "E. Guigal",
                             name: "Côte-Rôtie La Mouline", vintage: 2018, price: 340.0),
        PreviewMenuWine.make(lineIndex: 3, producer: "Château Lynch-Bages",
                             name: "Lynch-Bages", vintage: 2016, price: 120.0),
        PreviewMenuWine.make(lineIndex: 4, producer: nil,
                             name: "Sancerre", vintage: 2022, price: 45.0)
    ]
    MenuResultsView(wines: wines)
        .modelContainer(SampleData.makeContainer())
}
#endif
