import SwiftUI

/// Navigation racine de l'application : 4 onglets principaux.
struct ContentView: View {
    var body: some View {
        TabView {
            InventoryView()
                .tabItem {
                    Label("Cave", systemImage: "wineglass")
                }

            CellarsView()
                .tabItem {
                    Label("Caves", systemImage: "square.grid.3x3")
                }

            SearchView()
                .tabItem {
                    Label("Recherche", systemImage: "magnifyingglass")
                }

            SettingsView()
                .tabItem {
                    Label("Réglages", systemImage: "gearshape")
                }
        }
        .tint(Theme.wine)
    }
}

#Preview {
    ContentView()
        .environment(StoreManager())
}
