import Foundation

/// Analyseur d'étiquettes : extrait domaine, cuvée, millésime, appellation et cépages
/// à partir des lignes de texte reconnues par l'OCR.
enum LabelParser {

    // Mots-clés indiquant un nom de domaine / propriété.
    private static let producerKeywords = [
        "château", "chateau", "domaine", "clos", "mas", "bodega", "tenuta"
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
        guard let regex = try? NSRegularExpression(
            pattern: "Appellation\\s+(.+?)\\s+(Contr[oô]lée|Prot[eé]gée)",
            options: [.caseInsensitive]
        ) else { return nil }

        let range = NSRange(joined.startIndex..<joined.endIndex, in: joined)
        guard let match = regex.firstMatch(in: joined, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: joined) else { return nil }

        let captured = joined[r].trimmingCharacters(in: .whitespacesAndNewlines)
        return captured.isEmpty ? nil : captured
    }

    // MARK: - Format

    private static func detectFormat(in lines: [String]) -> String? {
        let joined = lines.joined(separator: " ")
        guard let regex = try? NSRegularExpression(
            pattern: "(75\\s?cl|750\\s?ml|magnum)",
            options: [.caseInsensitive]
        ) else { return nil }

        let range = NSRange(joined.startIndex..<joined.endIndex, in: joined)
        guard let match = regex.firstMatch(in: joined, range: range),
              let r = Range(match.range, in: joined) else { return nil }

        return String(joined[r])
    }

    // MARK: - Degré d'alcool

    private static func detectABV(in lines: [String]) -> String? {
        let joined = lines.joined(separator: " ")
        guard let regex = try? NSRegularExpression(
            pattern: "\\d{1,2}([.,]\\d)?\\s?%"
        ) else { return nil }

        let range = NSRange(joined.startIndex..<joined.endIndex, in: joined)
        guard let match = regex.firstMatch(in: joined, range: range),
              let r = Range(match.range, in: joined) else { return nil }

        return joined[r].trimmingCharacters(in: .whitespaces)
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
        // Ligne contenant un mot-clé de propriété.
        for line in lines {
            let lowered = normalize(line)
            if producerKeywords.contains(where: { lowered.contains($0) }) {
                return line
            }
        }
        // Fallback : la plus longue ligne du haut (3 premières lignes).
        let top = Array(lines.prefix(3))
        return top.max(by: { $0.count < $1.count })
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
