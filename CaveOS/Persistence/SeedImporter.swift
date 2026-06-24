import Foundation

/// Amorce la base de données avec un référentiel de cépages, régions et appellations
/// embarqué dans le bundle (`winedata.json`). N'agit qu'une seule fois.
enum SeedImporter {

    // MARK: - Structures de décodage du JSON embarqué

    private struct SeedData: Codable {
        let grapes: [SeedGrape]
        let regions: [SeedRegion]
        let appellations: [SeedAppellation]
    }

    private struct SeedGrape: Codable {
        let name: String
        let color: String
        let apogeeMin: Int
        let apogeePeak: Int
        let apogeeMax: Int
    }

    private struct SeedRegion: Codable {
        let name: String
        let country: String
        let qualityTier: String
    }

    private struct SeedAppellation: Codable {
        let name: String
        let regionName: String?
    }

    // MARK: - Amorçage

    /// Importe le référentiel embarqué si la base ne contient encore aucun cépage.
    @MainActor
    static func seedIfNeeded(repository: CaveRepository) {
        // Déjà amorcé : on ne fait rien.
        guard repository.count(of: Grape.self) == 0 else { return }

        guard let data = loadSeedData() else { return }

        for grape in data.grapes {
            let model = Grape(
                name: grape.name,
                colorRaw: grape.color,
                wikidataId: nil,
                apogeeMin: grape.apogeeMin,
                apogeePeak: grape.apogeePeak,
                apogeeMax: grape.apogeeMax
            )
            repository.insert(model)
        }

        for region in data.regions {
            let tier = QualityTier(rawValue: region.qualityTier) ?? .mid
            let model = Region(
                name: region.name,
                country: region.country,
                qualityTier: tier
            )
            repository.insert(model)
        }

        for appellation in data.appellations {
            let model = Appellation(
                name: appellation.name,
                regionName: appellation.regionName,
                inaoCode: nil
            )
            repository.insert(model)
        }

        if case let .failure(error) = repository.save() {
            print("SeedImporter: échec de l'enregistrement du référentiel — \(error)")
        }
    }

    // MARK: - Chargement du fichier

    /// Décode `winedata.json` depuis le bundle principal. Renvoie `nil` proprement
    /// si le fichier est absent ou illisible.
    private static func loadSeedData() -> SeedData? {
        guard let url = Bundle.main.url(forResource: "winedata", withExtension: "json") else {
            print("SeedImporter: fichier winedata.json introuvable dans le bundle.")
            return nil
        }

        do {
            let raw = try Data(contentsOf: url)
            return try JSONDecoder().decode(SeedData.self, from: raw)
        } catch {
            print("SeedImporter: échec du décodage de winedata.json — \(error)")
            return nil
        }
    }
}
