import SwiftUI
import SwiftData
import PhotosUI

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

    // Grille WSET avancée
    @State private var sweetness: String = ""
    @State private var acidity: String = ""
    @State private var tannin: String = ""
    @State private var body_: String = ""
    @State private var finish: String = ""

    // Photo
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    // Valeurs WSET FR proposées
    private let sweetnessOptions = ["", "sec", "demi-sec", "moelleux"]
    private let acidityOptions = ["", "faible", "moyenne", "élevée"]
    private let tanninOptions = ["", "souples", "fermes"]
    private let bodyOptions = ["", "léger", "moyen", "charpenté"]
    private let finishOptions = ["", "courte", "moyenne", "longue"]

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

                Section("Grille WSET") {
                    wsetPicker(title: "Sucrosité", selection: $sweetness, options: sweetnessOptions)
                    wsetPicker(title: "Acidité", selection: $acidity, options: acidityOptions)
                    wsetPicker(title: "Tanins", selection: $tannin, options: tanninOptions)
                    wsetPicker(title: "Corps", selection: $body_, options: bodyOptions)
                    wsetPicker(title: "Finale", selection: $finish, options: finishOptions)
                }

                Section("Photo") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoData == nil ? "Ajouter une photo" : "Modifier la photo",
                              systemImage: "camera")
                    }
                    if let photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                        Button("Supprimer la photo", role: .destructive) {
                            self.photoData = nil
                            self.photoItem = nil
                        }
                    }
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
            .task(id: photoItem) {
                guard let photoItem else { return }
                if let data = try? await photoItem.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
    }

    /// Picker WSET réutilisable affichant une valeur libellée par défaut quand vide.
    @ViewBuilder
    private func wsetPicker(title: String, selection: Binding<String>, options: [String]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(option.isEmpty ? "—" : option).tag(option)
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
        note.sweetness = trimmed(sweetness)
        note.acidity = trimmed(acidity)
        note.tannin = trimmed(tannin)
        note.body = trimmed(body_)
        note.finish = trimmed(finish)
        note.photoData = photoData

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
