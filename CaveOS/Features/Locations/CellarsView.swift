import SwiftUI
import SwiftData

/// Liste des caves de l'utilisateur.
struct CellarsView: View {
    @Query(sort: \Cellar.createdAt, order: .reverse) private var cellars: [Cellar]

    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            Group {
                if cellars.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(cellars) { cellar in
                            NavigationLink {
                                CellarDetailView(cellar: cellar)
                            } label: {
                                CellarRow(cellar: cellar)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mes caves")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ajouter une cave")
                }
            }
            .sheet(isPresented: $showingEditor) {
                CellarEditView()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aucune cave", systemImage: "square.grid.3x3")
        } description: {
            Text("Ajoutez une cave pour organiser vos bouteilles par emplacement.")
        } actions: {
            Button("Ajouter une cave") {
                showingEditor = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Ligne d'affichage d'une cave.
private struct CellarRow: View {
    let cellar: Cellar

    private var bottleCount: Int {
        cellar.locations.reduce(0) { total, location in
            total + location.bottles.reduce(0) { $0 + $1.quantity }
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: cellar.type.symbol)
                .font(.title2)
                .foregroundStyle(Theme.wine)
                .frame(width: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(cellar.name)
                    .font(.headline)
                Text(cellar.type.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(
                text: "\(bottleCount)",
                color: Theme.gold,
                systemImage: "wineglass"
            )
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
