import SwiftUI

/// Destinations de navigation racine, partagées entre iPhone (TabView) et iPad (NavigationSplitView).
private enum RootDestination: String, CaseIterable, Identifiable {
    case inventory
    case cellars
    case search
    case stats
    case pairing
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inventory: return "Cave"
        case .cellars: return "Caves"
        case .search: return "Recherche"
        case .stats: return "Stats"
        case .pairing: return "Accords"
        case .settings: return "Réglages"
        }
    }

    var systemImage: String {
        switch self {
        case .inventory: return "wineglass"
        case .cellars: return "square.grid.3x3"
        case .search: return "magnifyingglass"
        case .stats: return "chart.pie"
        case .pairing: return "fork.knife"
        case .settings: return "gearshape"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .inventory: InventoryView()
        case .cellars: CellarsView()
        case .search: SearchView()
        case .stats: StatsView()
        case .pairing: PairingView()
        case .settings: SettingsView()
        }
    }
}

/// Navigation racine adaptative : TabView sur iPhone, NavigationSplitView sur iPad.
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Onboarding affiché une seule fois, au premier lancement.
    @AppStorage("caveos.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                SplitNavigation()
            } else {
                TabNavigation()
            }
        }
        .tint(Theme.wine)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .onAppear {
            if !hasCompletedOnboarding { showOnboarding = true }
        }
    }
}

/// Navigation par onglets pour iPhone (et largeurs compactes).
private struct TabNavigation: View {
    var body: some View {
        TabView {
            ForEach(RootDestination.allCases) { item in
                item.destination
                    .tabItem {
                        Label(item.label, systemImage: item.systemImage)
                    }
            }
        }
    }
}

/// Navigation à colonnes pour iPad (largeurs régulières).
private struct SplitNavigation: View {
    @State private var selection: RootDestination? = .inventory

    var body: some View {
        NavigationSplitView {
            List(RootDestination.allCases, selection: $selection) { item in
                NavigationLink(value: item) {
                    Label(item.label, systemImage: item.systemImage)
                }
            }
            .navigationTitle("CaveOS")
        } detail: {
            if let selection {
                selection.destination
            } else {
                ContentUnavailableView(
                    "Sélectionnez une rubrique",
                    systemImage: "wineglass"
                )
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(StoreManager())
}
