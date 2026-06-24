import Foundation

// MARK: - Suggestion d'accord mets-vins

/// Recommandation d'accord pour un plat donné.
struct PairingSuggestion: Identifiable, Sendable {
    let id = UUID()
    let dish: String
    let rationale: String
    let colors: [WineColor]
    let styleHints: [String]
}

// MARK: - Moteur d'accords mets-vins

/// Base de règles statiques (catégorie de plat → couleurs/styles recommandés).
/// Matching par mots-clés en français, avec repli générique.
enum PairingEngine {

    /// Catégorie d'accord interne : libellé, mots-clés déclencheurs, et recommandation.
    private struct Rule: Sendable {
        let category: String
        let keywords: [String]
        let rationale: String
        let colors: [WineColor]
        let styleHints: [String]
    }

    private static let rules: [Rule] = [
        Rule(
            category: "Viande rouge",
            keywords: ["boeuf", "bœuf", "steak", "entrecote", "entrecôte", "agneau", "gigot",
                       "cote de boeuf", "côte de bœuf", "viande rouge", "bavette", "rumsteck",
                       "magret", "gibier", "chevreuil", "sanglier", "daube", "bourguignon", "tournedos"],
            rationale: "Une viande rouge structurée appelle un rouge tannique et corsé qui soutient le gras et les sucs.",
            colors: [.red],
            styleHints: ["Rouge tannique", "Corsé", "Boisé", "Cabernet sauvignon", "Syrah", "Tannat"]
        ),
        Rule(
            category: "Volaille",
            keywords: ["poulet", "volaille", "dinde", "chapon", "pintade", "canard", "caille",
                       "coq au vin", "poularde", "roti de volaille", "rôti de volaille"],
            rationale: "Une volaille délicate s'accorde avec un rouge léger ou un blanc ample et rond.",
            colors: [.red, .white],
            styleHints: ["Rouge léger", "Pinot noir", "Blanc ample", "Chardonnay", "Souple"]
        ),
        Rule(
            category: "Poisson",
            keywords: ["poisson", "saumon", "cabillaud", "bar", "dorade", "sole", "truite",
                       "lieu", "merlu", "thon", "maquereau", "sardine", "lotte", "turbot"],
            rationale: "Un poisson met en valeur un blanc sec, vif et minéral qui en respecte la finesse.",
            colors: [.white],
            styleHints: ["Blanc sec", "Vif", "Minéral", "Sauvignon blanc", "Chablis", "Riesling"]
        ),
        Rule(
            category: "Fruits de mer",
            keywords: ["fruits de mer", "huitre", "huître", "moule", "crevette", "langoustine",
                       "homard", "crabe", "coquille", "saint-jacques", "saint jacques", "bulot",
                       "plateau de fruits de mer", "oursin"],
            rationale: "Les fruits de mer iodés réclament un blanc sec, tendu et salin, voire un effervescent.",
            colors: [.white, .sparkling],
            styleHints: ["Blanc sec", "Salin", "Muscadet", "Picpoul", "Champagne", "Crémant"]
        ),
        Rule(
            category: "Fromage",
            keywords: ["fromage", "comte", "comté", "brie", "camembert", "roquefort", "bleu",
                       "chevre", "chèvre", "munster", "reblochon", "gruyere", "gruyère", "plateau de fromages"],
            rationale: "Selon la pâte, un blanc moelleux (bleus) ou un rouge souple sublime le fromage.",
            colors: [.white, .red, .sweet],
            styleHints: ["Blanc moelleux", "Rouge souple", "Liquoreux pour les bleus", "Vin jaune"]
        ),
        Rule(
            category: "Dessert",
            keywords: ["dessert", "gateau", "gâteau", "tarte", "patisserie", "pâtisserie",
                       "chocolat", "fruits", "creme", "crème", "glace", "sucre", "sucré", "macaron", "fraise"],
            rationale: "Un dessert s'équilibre avec un vin liquoreux ou un effervescent doux, jamais sec.",
            colors: [.sweet, .sparkling, .fortified],
            styleHints: ["Liquoreux", "Sauternes", "Moelleux", "Effervescent doux", "Porto sur le chocolat"]
        ),
        Rule(
            category: "Plats épicés",
            keywords: ["epice", "épice", "epicé", "épicé", "curry", "thai", "thaï", "indien",
                       "mexicain", "piment", "tandoori", "tex-mex", "asiatique", "wok", "colombo"],
            rationale: "Un plat épicé s'apaise avec un blanc aromatique légèrement demi-sec ou un rosé frais.",
            colors: [.white, .rose],
            styleHints: ["Blanc aromatique", "Gewurztraminer", "Demi-sec", "Rosé frais", "Riesling"]
        ),
        Rule(
            category: "Gratin / Dauphinois",
            keywords: ["gratin", "dauphinois", "tartiflette", "raclette", "fondue", "croziflette",
                       "gratin dauphinois", "pomme de terre", "puree", "purée", "lasagne", "crozet"],
            rationale: "Un gratin crémeux appelle un blanc gras et boisé, ou un rouge léger et frais de montagne.",
            colors: [.white, .red],
            styleHints: ["Blanc gras", "Boisé", "Rouge léger", "Vin de Savoie", "Mondeuse", "Roussette"]
        ),
        Rule(
            category: "Charcuterie",
            keywords: ["charcuterie", "saucisson", "jambon", "terrine", "pate", "pâté", "rillette",
                       "chorizo", "coppa", "mortadelle", "andouille", "boudin", "planche"],
            rationale: "La charcuterie grasse et salée s'accorde à un rouge léger et fruité ou un rosé vif.",
            colors: [.red, .rose],
            styleHints: ["Rouge fruité", "Beaujolais", "Gamay", "Rosé vif", "Léger"]
        ),
        Rule(
            category: "Légumes",
            keywords: ["legume", "légume", "salade", "vegetarien", "végétarien", "vegan", "ratatouille",
                       "asperge", "courgette", "aubergine", "champignon", "risotto", "quiche", "tarte aux legumes"],
            rationale: "Un plat de légumes met en avant un blanc sec et frais ou un rosé léger et désaltérant.",
            colors: [.white, .rose],
            styleHints: ["Blanc sec", "Frais", "Rosé léger", "Sauvignon", "Vermentino"]
        )
    ]

    private static let generic = PairingSuggestion(
        dish: "",
        rationale: "Pas de correspondance précise : optez pour un vin polyvalent, frais et souple, qui s'adapte à la plupart des mets.",
        colors: [.red, .white, .rose],
        styleHints: ["Polyvalent", "Souple", "Frais", "Tanins discrets"]
    )

    /// Détermine la meilleure suggestion d'accord pour un plat décrit librement.
    static func suggest(forDish dish: String) -> PairingSuggestion {
        let normalized = normalize(dish)
        guard !normalized.isEmpty else {
            return PairingSuggestion(
                dish: dish,
                rationale: generic.rationale,
                colors: generic.colors,
                styleHints: generic.styleHints
            )
        }

        let best = rules
            .map { rule -> (rule: Rule, score: Int) in
                let score = rule.keywords.reduce(0) { partial, keyword in
                    normalized.contains(normalize(keyword)) ? partial + 1 : partial
                }
                return (rule, score)
            }
            .filter { $0.score > 0 }
            .max { $0.score < $1.score }

        guard let match = best else {
            return PairingSuggestion(
                dish: dish,
                rationale: generic.rationale,
                colors: generic.colors,
                styleHints: generic.styleHints
            )
        }

        return PairingSuggestion(
            dish: dish,
            rationale: match.rule.rationale,
            colors: match.rule.colors,
            styleHints: match.rule.styleHints
        )
    }

    /// Bouteilles de la cave correspondant aux couleurs recommandées, encore disponibles.
    static func matchingBottles(for suggestion: PairingSuggestion, in bottles: [Bottle]) -> [Bottle] {
        let targetColors = Set(suggestion.colors)
        return bottles.filter { bottle in
            guard bottle.state == .inCellar, bottle.quantity > 0 else { return false }
            guard let color = bottle.wine?.color else { return false }
            return targetColors.contains(color)
        }
    }

    // MARK: - Utilitaires

    /// Normalise une chaîne : minuscules, sans accents, sans ponctuation superflue.
    private static func normalize(_ text: String) -> String {
        text
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
