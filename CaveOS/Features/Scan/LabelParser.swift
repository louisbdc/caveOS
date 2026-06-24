import Foundation

/// Analyseur d'étiquettes : extrait domaine, cuvée, millésime, appellation et cépages
/// à partir des lignes de texte reconnues par l'OCR.
enum LabelParser {

    // Mots-clés indiquant un nom de domaine / propriété.
    private static let producerKeywords = [
        "château", "chateau", "domaine", "clos", "mas", "bodega", "tenuta",
        "weingut", "cantina", "quinta", "maison", "cave", "vignoble", "estate"
    ]

    // Termes qui disqualifient une ligne comme nom de producteur (mentions légales).
    private static let nonProducerTerms = [
        "appellation", "controlee", "contrôlée", "protegee", "protégée",
        "mis en bouteille", "mise en bouteille", "produit de", "product of",
        "grand vin", "vol.", "% vol", "contient", "sulfites", "aop", "aoc",
        "igp", "doc", "docg"
    ]

    /// Année courante, utilisée pour filtrer les millésimes aberrants.
    private static var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    static func parse(
        lines: [String],
        knownAppellations: [String],
        knownGrapes: [String]
    ) -> ScannedLabel {
        var label = ScannedLabel()
        label.rawLines = lines

        let cleanedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        label.vintage = detectVintage(in: cleanedLines)
        label.appellation = detectAppellation(in: cleanedLines, known: knownAppellations)
            ?? detectAppellationMention(in: cleanedLines)
        label.grapes = detectGrapes(in: cleanedLines, known: knownGrapes)
        label.format = detectFormat(in: cleanedLines)
        label.abv = detectABV(in: cleanedLines)
        label.producer = detectProducer(in: cleanedLines)
        label.wineName = detectWineName(
            in: cleanedLines,
            producer: label.producer,
            appellation: label.appellation
        )

        return label
    }

    // MARK: - Millésime

    private static func detectVintage(in lines: [String]) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "\\b(19|20)\\d{2}\\b") else {
            return nil
        }

        var candidates: [Int] = []
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, range: range)
            for match in matches {
                guard let r = Range(match.range, in: line),
                      let year = Int(line[r]) else { continue }
                if year >= 1900, year <= currentYear {
                    candidates.append(year)
                }
            }
        }
        // On retient l'année plausible la plus récente.
        return candidates.max()
    }

    // MARK: - Appellation (match flou)

    private static func detectAppellation(in lines: [String], known: [String]) -> String? {
        guard !known.isEmpty else { return nil }

        var best: (name: String, distance: Int)?

        for line in lines {
            let normalizedLine = normalize(line)
            for appellation in known {
                let normalizedApp = normalize(appellation)
                guard !normalizedApp.isEmpty else { continue }

                // Seuil proportionnel à la longueur de l'appellation.
                let threshold = max(2, normalizedApp.count / 4)

                // Cas direct : la ligne contient l'appellation.
                if normalizedLine.contains(normalizedApp) {
                    return appellation
                }

                let distance = levenshtein(normalizedLine, normalizedApp)
                if distance <= threshold {
                    if best == nil || distance < best!.distance {
                        best = (appellation, distance)
                    }
                }
            }
        }

        return best?.name
    }

    /// Détecte une mention « Appellation … Contrôlée/Protégée » dans le texte brut,
    /// utilisée en repli lorsque le match flou n'a rien trouvé.
    private static func detectAppellationMention(in lines: [String]) -> String? {
        let joined = lines.joined(separator: " ")

        // « Appellation X (d'Origine) Contrôlée/Protégée » ou acronyme « AOC/AOP/AOVDQS X ».
        let patterns = [
            "Appellation\\s+(?:d['’]Origine\\s+)?(.+?)\\s+(?:Contr[oô]l[ée]+e|Prot[ée]+g[ée]+e)",
            "\\b(?:AOC|AOP|AOVDQS|DOCG|DOC|IGP)\\s+([A-Za-zÀ-ÿ' \\-]{3,40})"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(joined.startIndex..<joined.endIndex, in: joined)
            if let match = regex.firstMatch(in: joined, range: range),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: joined) {
                let captured = joined[r].trimmingCharacters(in: .whitespacesAndNewlines)
                if !captured.isEmpty { return captured }
            }
        }
        return nil
    }

    // MARK: - Format

    private static func detectFormat(in lines: [String]) -> String? {
        let text = normalize(lines.joined(separator: " "))

        // Formats nommés (priorité car non ambigus).
        let named: [(needles: [String], label: String)] = [
            (["nabuchodonosor"], "Nabuchodonosor (15 L)"),
            (["balthazar"], "Balthazar (12 L)"),
            (["salmanazar"], "Salmanazar (9 L)"),
            (["mathusalem", "mathusalah"], "Mathusalem (6 L)"),
            (["rehoboam", "réhoboam"], "Réhoboam (4,5 L)"),
            (["double magnum"], "Double Magnum (3 L)"),
            (["jeroboam", "jéroboam"], "Jéroboam (3 L)"),
            (["magnum"], "Magnum (1,5 L)"),
            (["piccolo"], "Piccolo (20 cl)"),
            (["demi", "half"], "Demi (37,5 cl)")
        ]
        for entry in named where entry.needles.contains(where: { text.contains($0) }) {
            return entry.label
        }

        // Volume explicite (cl / ml / L), ex. "75 cl", "750ml", "1,5 l".
        if let volume = detectVolumeFormat(in: text) {
            return volume
        }
        return nil
    }

    /// Reconnaît un volume chiffré et le ramène au format standard le plus proche.
    private static func detectVolumeFormat(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "([0-9]+(?:[.,][0-9]+)?)\\s?(cl|ml|l)\\b"
        ) else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }

        let number = Double(text[numberRange].replacingOccurrences(of: ",", with: ".")) ?? 0
        let unit = String(text[unitRange])
        let centiliters: Double
        switch unit {
        case "ml": centiliters = number / 10
        case "l": centiliters = number * 100
        default: centiliters = number   // cl
        }

        // Associe au format standard dont la contenance est la plus proche.
        guard centiliters > 0,
              let closest = BottleFormat.allCases.min(by: {
                  abs(Double($0.centiliters) - centiliters) < abs(Double($1.centiliters) - centiliters)
              }) else { return nil }
        return closest.label
    }

    // MARK: - Degré d'alcool

    private static func detectABV(in lines: [String]) -> String? {
        let joined = lines.joined(separator: " ")
        guard let regex = try? NSRegularExpression(
            pattern: "(\\d{1,2}(?:[.,]\\d)?)\\s?%"
        ) else { return nil }

        let range = NSRange(joined.startIndex..<joined.endIndex, in: joined)
        let matches = regex.matches(in: joined, range: range)
        for match in matches {
            guard let valueRange = Range(match.range(at: 1), in: joined),
                  let full = Range(match.range, in: joined) else { continue }
            let value = Double(joined[valueRange].replacingOccurrences(of: ",", with: ".")) ?? 0
            // On ne retient qu'un degré d'alcool réaliste pour un vin.
            if (3.0...25.0).contains(value) {
                return joined[full].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: - Cépages

    private static func detectGrapes(in lines: [String], known: [String]) -> [String] {
        guard !known.isEmpty else { return [] }

        let joined = normalize(lines.joined(separator: " "))
        var found: [String] = []

        for grape in known {
            let normalizedGrape = normalize(grape)
            guard !normalizedGrape.isEmpty else { continue }
            if joined.contains(normalizedGrape), !found.contains(grape) {
                found.append(grape)
            }
        }

        return found
    }

    // MARK: - Domaine / Producteur

    private static func detectProducer(in lines: [String]) -> String? {
        // Ligne contenant un mot-clé de propriété (et pas une mention légale).
        for line in lines {
            let lowered = normalize(line)
            if producerKeywords.contains(where: { lowered.contains($0) }),
               !isNonProducerLine(lowered) {
                return line
            }
        }
        // Fallback : la plus longue ligne du haut, en écartant les mentions légales.
        let top = lines.prefix(3).filter { !isNonProducerLine(normalize($0)) }
        return top.max(by: { $0.count < $1.count }) ?? lines.first
    }

    /// Une ligne est écartée comme producteur si elle ressemble à une mention légale.
    private static func isNonProducerLine(_ normalizedLine: String) -> Bool {
        nonProducerTerms.contains { normalizedLine.contains($0) }
    }

    // MARK: - Nom de cuvée

    private static func detectWineName(
        in lines: [String],
        producer: String?,
        appellation: String?
    ) -> String? {
        // On cherche une ligne qui n'est ni le producteur, ni l'appellation,
        // ni un simple millésime.
        let normalizedAppellation = appellation.map(normalize)
        for line in lines {
            if let producer, line == producer { continue }
            let normalizedLine = normalize(line)
            if let normalizedAppellation, normalizedLine == normalizedAppellation { continue }
            if isYearOnly(line) { continue }
            if normalizedLine.count < 3 { continue }
            return line
        }
        return nil
    }

    private static func isYearOnly(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 4, let year = Int(trimmed) else { return false }
        return year >= 1900 && year <= currentYear
    }

    // MARK: - Normalisation

    /// Minuscule + suppression des accents pour des comparaisons robustes.
    private static func normalize(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Distance de Levenshtein

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let n = aChars.count
        let m = bChars.count

        if n == 0 { return m }
        if m == 0 { return n }

        var previous = Array(0...m)
        var current = Array(repeating: 0, count: m + 1)

        for i in 1...n {
            current[0] = i
            for j in 1...m {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,        // suppression
                    current[j - 1] + 1,     // insertion
                    previous[j - 1] + cost  // substitution
                )
            }
            previous = current
        }

        return previous[m]
    }
}
