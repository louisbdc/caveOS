import SwiftUI
import SwiftData

/// Formulaire de saisie d'une note de dégustation pour une bouteille.
struct TastingNoteEditView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let bottle: Bottle

    @State private var score: Double = 85
    @State private var eye: String = ""
    @State private var nose: String = ""
    @State private var palate: String = ""
    @State private var pairing: String = ""
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        HStack {
                            Text("Note sur 100")
                            Spacer()
                            Text("\(Int(score))")
                                .font(.headline)
                                .foregroundStyle(Theme.wine)
                        }
                        Slider(value: $score, in: 0...100, step: 1)
                    }
                }

                Section("Œil") {
                    TextField("Aspect, couleur, brillance…", text: $eye, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Nez") {
                    TextField("Arômes, intensité…", text: $nose, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Bouche") {
                    TextField("Attaque, équilibre, finale…", text: $palate, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Accords") {
                    TextField("Suggestions d'accords mets-vin…", text: $pairing, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Commentaire libre") {
                    TextField("Vos impressions générales…", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Dégustation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                }
            }
        }
    }

    /// Crée la note de dégustation liée à la bouteille et à son vin, puis la persiste.
    private func save() {
        let note = TastingNote(
            bottle: bottle,
            wine: bottle.wine,
            date: Date(),
            score: Int(score)
        )
        note.eye = trimmed(eye)
        note.nose = trimmed(nose)
        note.palate = trimmed(palate)
        note.text = trimmed(text)
        note.pairing = trimmed(pairing)

        context.insert(note)
        do {
            try context.save()
            dismiss()
        } catch {
            print("Échec de l'enregistrement de la note de dégustation : \(error)")
        }
    }

    /// Retourne nil pour un texte vide afin de ne pas stocker de chaînes inutiles.
    private func trimmed(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
