#if DEBUG
import Foundation
import SwiftUI
import SwiftData

/// Données de démonstration pour les aperçus Xcode (`#Preview`) et un éventuel mode démo.
///
/// Construit un `ModelContainer` **en mémoire** (jamais persisté, jamais synchronisé)
/// peuplé d'une cave crédible : deux caves physiques, leurs emplacements, un catalogue
/// de vins variés couvrant **les sept couleurs** (rouge, blanc, rosé, effervescent,
/// liquoreux, fortifié, orange ; France, Italie, Espagne, Portugal, États-Unis) et des
/// bouteilles couvrant tous les états et tous les statuts d'apogée calculés par
/// ``ApogeeEngine`` à la date courante — utile pour juger les badges et leur contraste.
///
/// Compilé uniquement en `DEBUG` : ce fichier n'est pas embarqué en production.
enum SampleData {

    // MARK: - Point d'entrée

    /// Conteneur en mémoire prêt à brancher dans une vue : `.modelContainer(SampleData.makeContainer())`.
    @MainActor
    static func makeContainer() -> ModelContainer {
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("SampleData : impossible de créer le conteneur de démonstration en mémoire.")
        }
        populate(container.mainContext)
        return container
    }

    // MARK: - Amorçage du contenu

    @MainActor
    private static func populate(_ context: ModelContext) {
        let grapes = insertGrapes(into: context)
        let regions = insertRegions(into: context)
        let appellations = insertAppellations(into: context)
        let locations = insertCellars(into: context)

        let bottlesByWine = insertCatalog(
            into: context,
            grapes: grapes,
            regions: regions,
            appellations: appellations,
            locations: locations
        )

        insertTastingNotes(into: context, bottles: bottlesByWine)

        try? context.save()
    }

    // MARK: - Référentiel : cépages

    @MainActor
    private static func insertGrapes(into context: ModelContext) -> [String: Grape] {
        // (nom, couleur, apogée min / pic / max — années depuis le millésime)
        let definitions: [(String, String, Int, Int, Int)] = [
            ("Cabernet Sauvignon", "red", 5, 12, 30),
            ("Merlot", "red", 2, 10, 30),
            ("Cabernet Franc", "red", 2, 8, 20),
            ("Petit Verdot", "red", 4, 10, 20),
            ("Pinot Noir", "red", 2, 7, 30),
            ("Syrah", "red", 3, 10, 20),
            ("Grenache", "red", 2, 8, 18),
            ("Mourvèdre", "red", 4, 10, 20),
            ("Gamay", "red", 1, 4, 12),
            ("Nebbiolo", "red", 5, 15, 30),
            ("Sangiovese", "red", 10, 17, 30),
            ("Tempranillo", "red", 3, 11, 25),
            ("Chardonnay", "white", 2, 6, 15),
            ("Riesling", "white", 2, 8, 25),
            ("Sauvignon Blanc", "white", 0, 2, 8),
            ("Sémillon", "white", 2, 8, 20),
            ("Chenin Blanc", "white", 2, 8, 25),
            ("Cinsault", "red", 1, 3, 8),
            ("Touriga Nacional", "red", 5, 20, 50),
            ("Ribolla Gialla", "white", 2, 8, 16)
        ]
        var byName: [String: Grape] = [:]
        for (name, color, min, peak, max) in definitions {
            let grape = Grape(name: name, colorRaw: color, apogeeMin: min, apogeePeak: peak, apogeeMax: max)
            context.insert(grape)
            byName[name] = grape
        }
        return byName
    }

    // MARK: - Référentiel : régions

    @MainActor
    private static func insertRegions(into context: ModelContext) -> [String: Region] {
        // (nom, pays, niveau de qualité)
        let definitions: [(String, String, QualityTier)] = [
            ("Bordeaux", "France", .premium),
            ("Bourgogne", "France", .premium),
            ("Champagne", "France", .premium),
            ("Vallée du Rhône", "France", .premium),
            ("Vallée de la Loire", "France", .mid),
            ("Alsace", "France", .mid),
            ("Provence", "France", .mid),
            ("Beaujolais", "France", .mid),
            ("Piémont", "Italie", .premium),
            ("Toscane", "Italie", .premium),
            ("Rioja", "Espagne", .mid),
            ("Napa Valley", "États-Unis", .premium),
            ("Porto", "Portugal", .premium),
            ("Frioul", "Italie", .mid)
        ]
        var byName: [String: Region] = [:]
        for (name, country, tier) in definitions {
            let region = Region(name: name, country: country, qualityTier: tier)
            context.insert(region)
            byName[name] = region
        }
        return byName
    }

    // MARK: - Référentiel : appellations

    @MainActor
    private static func insertAppellations(into context: ModelContext) -> [String: Appellation] {
        // (nom, région de rattachement)
        let definitions: [(String, String)] = [
            ("Margaux", "Bordeaux"),
            ("Saint-Julien", "Bordeaux"),
            ("Sauternes", "Bordeaux"),
            ("Gevrey-Chambertin", "Bourgogne"),
            ("Champagne", "Champagne"),
            ("Hermitage", "Vallée du Rhône"),
            ("Châteauneuf-du-Pape", "Vallée du Rhône"),
            ("Alsace", "Alsace"),
            ("Bandol", "Provence"),
            ("Sancerre", "Vallée de la Loire"),
            ("Vouvray", "Vallée de la Loire"),
            ("Morgon", "Beaujolais"),
            ("Barolo", "Piémont"),
            ("Rioja", "Rioja")
        ]
        var byName: [String: Appellation] = [:]
        for (name, region) in definitions {
            let appellation = Appellation(name: name, regionName: region)
            context.insert(appellation)
            byName[name] = appellation
        }
        return byName
    }

    // MARK: - Caves & emplacements

    /// Crée deux caves physiques et leurs emplacements ; renvoie les emplacements indexés par libellé.
    @MainActor
    private static func insertCellars(into context: ModelContext) -> [String: Location] {
        var byLabel: [String: Location] = [:]

        let main = Cellar(name: "Cave électrique — salon", type: .electric, rows: 1, columns: 4, levels: 1)
        context.insert(main)
        for index in 0..<4 {
            // 4 clayettes sur un même niveau (colonnes 0…3) : levelIndex 0 cohérent
            // avec l'affichage (la vue regroupe par niveau réel des emplacements).
            let location = Location(
                kind: .shelf, label: "Clayette \(index + 1)",
                levelIndex: 0, column: index, isFront: true, capacity: 12, cellar: main
            )
            context.insert(location)
            byLabel[location.label] = location
        }

        let cellarRoom = Cellar(name: "Cave naturelle — sous-sol", type: .natural, rows: 3, columns: 4, levels: 1)
        context.insert(cellarRoom)
        for (kind, label) in [(LocationKind.zone, "Casier haut"), (LocationKind.zone, "Casier bas")] {
            let location = Location(
                kind: kind, label: label,
                levelIndex: 0, column: 0, isFront: true, capacity: 36, cellar: cellarRoom
            )
            context.insert(location)
            byLabel[label] = location
        }

        return byLabel
    }

    // MARK: - Catalogue de vins & bouteilles

    /// Décrit un vin et la bouteille associée. Les références (cépages, région…) sont par nom.
    private struct WineSpec {
        let wine: String
        let producer: String
        let color: WineColor
        let type: WineType
        let region: String
        let appellation: String?
        let grapes: [String]
        let vintage: Int?
        let format: BottleFormat
        let quantity: Int
        let price: Double
        let state: BottleState
        let isFavorite: Bool
        let lowStock: Int?
        let location: String
        let note: String?
    }

    /// Catalogue couvrant volontairement tous les statuts d'apogée (année de référence : 2026)
    /// ainsi que des formats, couleurs, pays, prix et états variés.
    private static let specs: [WineSpec] = [
        .init(wine: "Château Margaux", producer: "Château Margaux", color: .red, type: .still,
              region: "Bordeaux", appellation: "Margaux",
              grapes: ["Cabernet Sauvignon", "Merlot", "Cabernet Franc", "Petit Verdot"],
              vintage: 2015, format: .bottle, quantity: 6, price: 650, state: .inCellar,
              isFavorite: true, lowStock: 3, location: "Casier bas", note: nil),

        .init(wine: "Léoville Las Cases", producer: "Château Léoville Las Cases", color: .red, type: .still,
              region: "Bordeaux", appellation: "Saint-Julien",
              grapes: ["Cabernet Sauvignon", "Merlot"],
              vintage: 2010, format: .magnum, quantity: 2, price: 220, state: .inCellar,
              isFavorite: false, lowStock: nil, location: "Casier bas", note: "Magnum — pour un grand repas."),

        .init(wine: "Gevrey-Chambertin 1er Cru", producer: "Maison Louis Jadot", color: .red, type: .still,
              region: "Bourgogne", appellation: "Gevrey-Chambertin",
              grapes: ["Pinot Noir"],
              vintage: 2019, format: .bottle, quantity: 2, price: 78, state: .inCellar,
              isFavorite: false, lowStock: nil, location: "Clayette 1", note: nil),

        .init(wine: "Special Cuvée Brut", producer: "Champagne Bollinger", color: .sparkling, type: .sparkling,
              region: "Champagne", appellation: "Champagne",
              grapes: ["Pinot Noir", "Chardonnay"],
              vintage: nil, format: .bottle, quantity: 4, price: 60, state: .inCellar,
              isFavorite: true, lowStock: 2, location: "Clayette 2", note: "Sans millésime — apéritif."),

        .init(wine: "Hermitage", producer: "M. Chapoutier", color: .red, type: .still,
              region: "Vallée du Rhône", appellation: "Hermitage",
              grapes: ["Syrah"],
              vintage: 2017, format: .bottle, quantity: 2, price: 90, state: .inCellar,
              isFavorite: false, lowStock: nil, location: "Clayette 1", note: nil),

        .init(wine: "Bandol Rouge", producer: "Domaine Tempier", color: .red, type: .still,
              region: "Provence", appellation: "Bandol",
              grapes: ["Mourvèdre", "Grenache"],
              vintage: 2016, format: .bottle, quantity: 3, price: 45, state: .inCellar,
              isFavorite: false, lowStock: nil, location: "Casier haut", note: nil),

        .init(wine: "Riesling Grand Cru Brand", producer: "Domaine Zind-Humbrecht", color: .white, type: .still,
              region: "Alsace", appellation: "Alsace",
              grapes: ["Riesling"],
              vintage: 2018, format: .bottle, quantity: 2, price: 38, state: .inCellar,
              isFavorite: false, lowStock: nil, location: "Clayette 3", note: nil),

        .init(wine: "Sancerre Blanc", producer: "Domaine Vacheron", color: .white, type: .still,
              region: "Vallée de la Loire", appellation: "Sancerre",
              grapes: ["Sauvignon Blanc"],
              vintage: 2022, format: .bottle, quantity: 1, price: 28, state: .opened,
              isFavorite: false, lowStock: nil, location: "Clayette 3", note: "Ouverte hier soir."),

        .init(wine: "Château d'Yquem", producer: "Château d'Yquem", color: .sweet, type: .sweet,
              region: "Bordeaux", appellation: "Sauternes",
              grapes: ["Sémillon", "Sauvignon Blanc"],
              vintage: 2009, format: .demi, quantity: 2, price: 180, state: .inCellar,
              isFavorite: false, lowStock: nil, location: "Clayette 4", note: "Demi-bouteille — dessert."),

        .init(wine: "Morgon Côte du Py", producer: "Domaine Marcel Lapierre", color: .red, type: .still,
              region: "Beaujolais", appellation: "Morgon",
              grapes: ["Gamay"],
              vintage: 2013, format: .bottle, quantity: 1, price: 22, state: .inCellar,
              isFavorite: false, lowStock: nil, location: "Casier haut", note: "Oubliée au fond de la cave."),

        .init(wine: "Tignanello", producer: "Antinori", color: .red, type: .still,
              region: "Toscane", appellation: nil,
              grapes: ["Sangiovese", "Cabernet Sauvignon"],
              vintage: 2012, format: .bottle, quantity: 2, price: 110, state: .inCellar,
              isFavorite: false, lowStock: nil, location: "Casier bas", note: nil),

        .init(wine: "Barolo Cascina Francia", producer: "Giacomo Conterno", color: .red, type: .still,
              region: "Piémont", appellation: "Barolo",
              grapes: ["Nebbiolo"],
              vintage: 2014, format: .bottle, quantity: 3, price: 130, state: .inCellar,
              isFavorite: true, lowStock: 2, location: "Casier bas", note: nil),

        .init(wine: "Gran Reserva 904", producer: "La Rioja Alta", color: .red, type: .still,
              region: "Rioja", appellation: "Rioja",
              grapes: ["Tempranillo"],
              vintage: 2011, format: .bottle, quantity: 2, price: 55, state: .inCellar,
              isFavorite: false, lowStock: nil, location: "Casier haut", note: nil),

        .init(wine: "Vouvray Sec", producer: "Domaine Huet", color: .white, type: .still,
              region: "Vallée de la Loire", appellation: "Vouvray",
              grapes: ["Chenin Blanc"],
              vintage: 2022, format: .bottle, quantity: 2, price: 32, state: .inCellar,
              isFavorite: false, lowStock: nil, location: "Clayette 3", note: nil),

        .init(wine: "Opus One", producer: "Opus One Winery", color: .red, type: .still,
              region: "Napa Valley", appellation: nil,
              grapes: ["Cabernet Sauvignon", "Merlot", "Cabernet Franc", "Petit Verdot"],
              vintage: 2023, format: .bottle, quantity: 3, price: 350, state: .inCellar,
              isFavorite: true, lowStock: nil, location: "Casier bas", note: "Encore beaucoup trop jeune."),

        .init(wine: "Châteauneuf-du-Pape", producer: "Vieux Télégraphe", color: .red, type: .still,
              region: "Vallée du Rhône", appellation: "Châteauneuf-du-Pape",
              grapes: ["Grenache", "Syrah", "Mourvèdre"],
              vintage: 2016, format: .bottle, quantity: 1, price: 65, state: .consumed,
              isFavorite: false, lowStock: nil, location: "Clayette 1", note: "Bue à Noël 2025."),

        // Rosé de gastronomie (couleur rosé).
        .init(wine: "Bandol Rosé", producer: "Domaine Tempier", color: .rose, type: .still,
              region: "Provence", appellation: "Bandol",
              grapes: ["Mourvèdre", "Grenache", "Cinsault"],
              vintage: 2024, format: .bottle, quantity: 6, price: 32, state: .inCellar,
              isFavorite: true, lowStock: 3, location: "Clayette 2", note: "Rosé de garde, à servir frais."),

        // Porto Vintage (couleur fortifié).
        .init(wine: "Porto Vintage", producer: "Taylor's", color: .fortified, type: .fortified,
              region: "Porto", appellation: nil,
              grapes: ["Touriga Nacional"],
              vintage: 2011, format: .bottle, quantity: 2, price: 95, state: .inCellar,
              isFavorite: false, lowStock: nil, location: "Casier bas", note: "À carafer longuement avant le service."),

        // Vin orange du Frioul (couleur orange), entamé pour montrer aussi l'état « Entamée ».
        .init(wine: "Ribolla Gialla", producer: "Gravner", color: .orange, type: .still,
              region: "Frioul", appellation: nil,
              grapes: ["Ribolla Gialla"],
              vintage: 2019, format: .bottle, quantity: 2, price: 70, state: .opened,
              isFavorite: false, lowStock: nil, location: "Clayette 4", note: "Macération longue (vin orange), entamé.")
    ]

    /// Insère le catalogue ; renvoie les bouteilles indexées par nom de vin (pour les dégustations).
    @MainActor
    private static func insertCatalog(
        into context: ModelContext,
        grapes: [String: Grape],
        regions: [String: Region],
        appellations: [String: Appellation],
        locations: [String: Location]
    ) -> [String: Bottle] {
        var bottlesByWine: [String: Bottle] = [:]

        for spec in specs {
            let producer = Producer(name: spec.producer)
            context.insert(producer)

            let wine = Wine(
                name: spec.wine,
                color: spec.color,
                type: spec.type,
                producer: producer,
                region: regions[spec.region],
                appellation: spec.appellation.flatMap { appellations[$0] },
                grapes: spec.grapes.compactMap { grapes[$0] }
            )
            wine.isFavorite = spec.isFavorite
            wine.lowStockThreshold = spec.lowStock
            context.insert(wine)

            let bottle = Bottle(
                wine: wine,
                vintage: spec.vintage,
                format: spec.format,
                quantity: spec.quantity,
                location: locations[spec.location],
                state: spec.state
            )
            bottle.purchasePrice = spec.price
            bottle.notes = spec.note
            configureState(bottle, state: spec.state)
            context.insert(bottle)

            bottlesByWine[spec.wine] = bottle
        }

        return bottlesByWine
    }

    /// Renseigne les champs propres à l'état d'une bouteille (entamée / consommée).
    @MainActor
    private static func configureState(_ bottle: Bottle, state: BottleState) {
        switch state {
        case .opened:
            bottle.openedDate = day(2026, 6, 23)
            bottle.remainingServings = 2
        case .consumed:
            bottle.openedDate = day(2025, 12, 25)
            bottle.remainingServings = 0
        case .inCellar:
            break
        }
    }

    // MARK: - Notes de dégustation

    @MainActor
    private static func insertTastingNotes(into context: ModelContext, bottles: [String: Bottle]) {
        if let bottle = bottles["Châteauneuf-du-Pape"] {
            let note = TastingNote(bottle: bottle, wine: bottle.wine, date: day(2025, 12, 25), score: 92)
            note.eye = "Grenat profond, légers reflets tuilés."
            note.nose = "Garrigue, fruits noirs confits, cuir."
            note.palate = "Ample, tannins fondus, belle fraîcheur finale."
            note.pairing = "Gigot d'agneau aux herbes."
            note.body = "Corsé"
            note.tannin = "Moyen +"
            note.acidity = "Moyenne"
            note.finish = "Longue"
            context.insert(note)
        }

        if let bottle = bottles["Sancerre Blanc"] {
            let note = TastingNote(bottle: bottle, wine: bottle.wine, date: day(2026, 6, 23), score: 88)
            note.nose = "Agrumes, buis, pierre à fusil."
            note.palate = "Vif, tendu, salin."
            note.pairing = "Fromage de chèvre frais."
            context.insert(note)
        }

        if let bottle = bottles["Château Margaux"] {
            let note = TastingNote(bottle: bottle, wine: bottle.wine, date: day(2024, 9, 14), score: 96)
            note.text = "Aérien et précis, d'une longueur exceptionnelle. À attendre encore."
            context.insert(note)
        }
    }

    // MARK: - Utilitaires

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: .current, year: year, month: month, day: day).date ?? Date()
    }
}

// MARK: - Aperçus

/// Aperçu autonome de l'inventaire : ne dépend que de ``BottleRowView`` et du moteur d'apogée.
#Preview("Inventaire — échantillon") {
    let container = SampleData.makeContainer()
    let bottles = (try? container.mainContext.fetch(
        FetchDescriptor<Bottle>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    )) ?? []

    return NavigationStack {
        List(bottles, id: \.id) { bottle in
            BottleRowView(bottle: bottle)
        }
        .navigationTitle("Ma cave")
    }
    .modelContainer(container)
}

/// Aperçu de l'application complète peuplée des données de démonstration.
#Preview("Application complète") {
    ContentView()
        .modelContainer(SampleData.makeContainer())
        .environment(StoreManager())
}
#endif
