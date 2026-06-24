import SwiftUI

/// Barre horizontale de filtres (couleur, apogée, région, appellation, cépage,
/// millésime, emplacement, prix) appliquée à la liste de bouteilles.
/// Reçoit les valeurs disponibles afin de rester purement présentationnelle.
struct WineFilterBar: View {
    @Binding var filter: WineFilter

    let regions: [String]
    let appellations: [String]
    let grapes: [String]
    let vintages: [Int]
    let locations: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                colorMenu
                statusMenu
                regionMenu
                appellationMenu
                grapeMenu
                vintageMenu
                locationMenu
                priceMenu
                if !filter.isEmpty {
                    Button {
                        filter = WineFilter()
                    } label: {
                        Label("Réinitialiser", systemImage: "xmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.wine)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
        }
        .background(.bar)
    }

    // MARK: - Menus

    private var colorMenu: some View {
        Menu {
            ForEach(WineColor.allCases) { color in
                Button {
                    filter.colors.toggle(color)
                } label: {
                    Label(color.label, systemImage: filter.colors.contains(color) ? "checkmark" : "")
                }
            }
            if !filter.colors.isEmpty {
                Divider()
                Button("Effacer", role: .destructive) { filter.colors = [] }
            }
        } label: {
            FilterChip(
                title: filter.colors.isEmpty ? "Couleur" : "Couleur (\(filter.colors.count))",
                isActive: !filter.colors.isEmpty,
                systemImage: "drop.fill"
            )
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(ApogeeStatus.allCases) { status in
                Button {
                    filter.statuses.toggle(status)
                } label: {
                    Label(status.label, systemImage: filter.statuses.contains(status) ? "checkmark" : status.symbol)
                }
            }
            if !filter.statuses.isEmpty {
                Divider()
                Button("Effacer", role: .destructive) { filter.statuses = [] }
            }
        } label: {
            FilterChip(
                title: filter.statuses.isEmpty ? "Apogée" : "Apogée (\(filter.statuses.count))",
                isActive: !filter.statuses.isEmpty,
                systemImage: "clock.fill"
            )
        }
    }

    private var regionMenu: some View {
        Menu {
            Button {
                filter.regionName = nil
            } label: {
                Label("Toutes", systemImage: filter.regionName == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(regions, id: \.self) { name in
                Button {
                    filter.regionName = (filter.regionName == name) ? nil : name
                } label: {
                    Label(name, systemImage: filter.regionName == name ? "checkmark" : "")
                }
            }
        } label: {
            FilterChip(
                title: filter.regionName ?? "Région",
                isActive: filter.regionName != nil,
                systemImage: "map.fill"
            )
        }
    }

    private var appellationMenu: some View {
        Menu {
            Button {
                filter.appellationName = nil
            } label: {
                Label("Toutes", systemImage: filter.appellationName == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(appellations, id: \.self) { name in
                Button {
                    filter.appellationName = (filter.appellationName == name) ? nil : name
                } label: {
                    Label(name, systemImage: filter.appellationName == name ? "checkmark" : "")
                }
            }
        } label: {
            FilterChip(
                title: filter.appellationName ?? "Appellation",
                isActive: filter.appellationName != nil,
                systemImage: "seal.fill"
            )
        }
    }

    private var grapeMenu: some View {
        Menu {
            Button {
                filter.grapeName = nil
            } label: {
                Label("Tous", systemImage: filter.grapeName == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(grapes, id: \.self) { name in
                Button {
                    filter.grapeName = (filter.grapeName == name) ? nil : name
                } label: {
                    Label(name, systemImage: filter.grapeName == name ? "checkmark" : "")
                }
            }
        } label: {
            FilterChip(
                title: filter.grapeName ?? "Cépage",
                isActive: filter.grapeName != nil,
                systemImage: "leaf.fill"
            )
        }
    }

    private var vintageMenu: some View {
        Menu {
            Section("Millésime minimum") {
                Button {
                    filter.vintageMin = nil
                } label: {
                    Label("Indifférent", systemImage: filter.vintageMin == nil ? "checkmark" : "")
                }
                ForEach(vintages, id: \.self) { year in
                    Button {
                        filter.vintageMin = (filter.vintageMin == year) ? nil : year
                    } label: {
                        Label("\(year)", systemImage: filter.vintageMin == year ? "checkmark" : "")
                    }
                }
            }
            Section("Millésime maximum") {
                Button {
                    filter.vintageMax = nil
                } label: {
                    Label("Indifférent", systemImage: filter.vintageMax == nil ? "checkmark" : "")
                }
                ForEach(vintages, id: \.self) { year in
                    Button {
                        filter.vintageMax = (filter.vintageMax == year) ? nil : year
                    } label: {
                        Label("\(year)", systemImage: filter.vintageMax == year ? "checkmark" : "")
                    }
                }
            }
        } label: {
            FilterChip(
                title: vintageLabel,
                isActive: filter.vintageMin != nil || filter.vintageMax != nil,
                systemImage: "calendar"
            )
        }
    }

    private var locationMenu: some View {
        Menu {
            Button {
                filter.locationName = nil
            } label: {
                Label("Tous", systemImage: filter.locationName == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(locations, id: \.self) { name in
                Button {
                    filter.locationName = (filter.locationName == name) ? nil : name
                } label: {
                    Label(name, systemImage: filter.locationName == name ? "checkmark" : "")
                }
            }
        } label: {
            FilterChip(
                title: filter.locationName ?? "Emplacement",
                isActive: filter.locationName != nil,
                systemImage: "square.grid.3x3.fill"
            )
        }
    }

    private var priceMenu: some View {
        Menu {
            ForEach(PriceRange.allCases) { range in
                Button {
                    apply(range)
                } label: {
                    Label(range.label, systemImage: isSelected(range) ? "checkmark" : "")
                }
            }
            if filter.minPrice != nil || filter.maxPrice != nil {
                Divider()
                Button("Effacer", role: .destructive) {
                    filter.minPrice = nil
                    filter.maxPrice = nil
                }
            }
        } label: {
            FilterChip(
                title: priceLabel,
                isActive: filter.minPrice != nil || filter.maxPrice != nil,
                systemImage: "eurosign.circle.fill"
            )
        }
    }

    // MARK: - Libellés dérivés

    private var vintageLabel: String {
        switch (filter.vintageMin, filter.vintageMax) {
        case (nil, nil): return "Millésime"
        case let (min?, max?): return min == max ? "\(min)" : "\(min)–\(max)"
        case let (min?, nil): return "≥ \(min)"
        case let (nil, max?): return "≤ \(max)"
        }
    }

    private var priceLabel: String {
        switch (filter.minPrice, filter.maxPrice) {
        case (nil, nil): return "Prix"
        case let (min?, max?): return "\(Int(min))–\(Int(max)) €"
        case let (min?, nil): return "≥ \(Int(min)) €"
        case let (nil, max?): return "≤ \(Int(max)) €"
        }
    }

    private func apply(_ range: PriceRange) {
        if isSelected(range) {
            filter.minPrice = nil
            filter.maxPrice = nil
        } else {
            filter.minPrice = range.min
            filter.maxPrice = range.max
        }
    }

    private func isSelected(_ range: PriceRange) -> Bool {
        filter.minPrice == range.min && filter.maxPrice == range.max
    }
}

// MARK: - Pastille de filtre

/// Puce cliquable représentant un filtre, mise en évidence lorsqu'elle est active.
struct FilterChip: View {
    let title: String
    let isActive: Bool
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(
            (isActive ? Theme.wine : Color(.systemGray5)),
            in: Capsule()
        )
        .foregroundStyle(isActive ? .white : .primary)
    }
}
