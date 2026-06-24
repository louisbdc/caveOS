import SwiftUI
import SwiftData
import Charts

/// Journal des relevés de température d'une cave : saisie manuelle, historique,
/// graphique et seuils d'alerte configurables (persistés par cave dans UserDefaults).
struct TemperatureLogView: View {
    @Environment(\.modelContext) private var modelContext

    let cellar: Cellar

    @State private var newCelsius: Double = 12.0
    @State private var newNote: String = ""
    @State private var thresholds: TemperatureThresholds
    @State private var showThresholdEditor = false

    init(cellar: Cellar) {
        self.cellar = cellar
        _thresholds = State(initialValue: TemperatureThresholds.load(for: cellar.id))
    }

    /// Relevés triés du plus récent au plus ancien.
    private var sortedReadings: [TemperatureReading] {
        cellar.temperatureReadings.sorted { $0.date > $1.date }
    }

    /// Relevés triés chronologiquement (pour le graphique).
    private var chronologicalReadings: [TemperatureReading] {
        cellar.temperatureReadings.sorted { $0.date < $1.date }
    }

    var body: some View {
        List {
            inputSection
            thresholdSection
            if !chronologicalReadings.isEmpty {
                chartSection
            }
            historySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Température")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showThresholdEditor) {
            ThresholdEditor(thresholds: $thresholds) { updated in
                updated.save(for: cellar.id)
            }
        }
    }

    // MARK: - Saisie

    private var inputSection: some View {
        Section("Nouveau relevé") {
            HStack {
                Text("Température")
                Spacer()
                Text(formatted(newCelsius))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(isOutOfRange(newCelsius) ? Theme.wine : .primary)
            }
            Slider(value: $newCelsius, in: -2...25, step: 0.5) {
                Text("Température")
            } minimumValueLabel: {
                Text("-2")
            } maximumValueLabel: {
                Text("25")
            }

            TextField("Note (optionnelle)", text: $newNote)

            if isOutOfRange(newCelsius) {
                Label(
                    "Cette valeur est hors de la plage [\(formatted(thresholds.low)) – \(formatted(thresholds.high))].",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(Theme.wine)
            }

            Button {
                addReading()
            } label: {
                Label("Enregistrer le relevé", systemImage: "plus.circle.fill")
            }
        }
    }

    // MARK: - Seuils

    private var thresholdSection: some View {
        Section("Seuils d'alerte") {
            HStack {
                Label("Plage cible", systemImage: "thermometer.medium")
                Spacer()
                Text("\(formatted(thresholds.low)) – \(formatted(thresholds.high))")
                    .foregroundStyle(.secondary)
            }
            Button("Modifier les seuils") {
                showThresholdEditor = true
            }
        }
    }

    // MARK: - Graphique

    private var chartSection: some View {
        Section("Évolution") {
            Chart {
                RectangleMark(
                    yStart: .value("Bas", thresholds.low),
                    yEnd: .value("Haut", thresholds.high)
                )
                .foregroundStyle(Theme.gold.opacity(0.12))

                ForEach(chronologicalReadings) { reading in
                    LineMark(
                        x: .value("Date", reading.date),
                        y: .value("°C", reading.celsius)
                    )
                    .foregroundStyle(Theme.wine)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", reading.date),
                        y: .value("°C", reading.celsius)
                    )
                    .foregroundStyle(isOutOfRange(reading.celsius) ? Theme.wine : Theme.gold)
                }
            }
            .frame(height: 200)
            .chartYScale(domain: chartDomain)
            .padding(.vertical, Theme.Spacing.s)
        }
    }

    private var chartDomain: ClosedRange<Double> {
        let values = chronologicalReadings.map(\.celsius) + [thresholds.low, thresholds.high]
        let minValue = (values.min() ?? 0) - 1
        let maxValue = (values.max() ?? 20) + 1
        return minValue...maxValue
    }

    // MARK: - Historique

    private var historySection: some View {
        Section("Historique") {
            if sortedReadings.isEmpty {
                ContentUnavailableView(
                    "Aucun relevé",
                    systemImage: "thermometer.variable.and.figure",
                    description: Text("Ajoute un premier relevé pour suivre la température.")
                )
            } else {
                ForEach(sortedReadings) { reading in
                    ReadingRow(reading: reading, outOfRange: isOutOfRange(reading.celsius))
                }
                .onDelete(perform: deleteReadings)
            }
        }
    }

    // MARK: - Actions

    private func addReading() {
        let reading = TemperatureReading(
            cellar: cellar,
            date: Date(),
            celsius: newCelsius,
            note: newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newNote
        )
        modelContext.insert(reading)
        do {
            try modelContext.save()
            newNote = ""
        } catch {
            modelContext.delete(reading)
        }
    }

    private func deleteReadings(at offsets: IndexSet) {
        let targets = offsets.map { sortedReadings[$0] }
        for reading in targets {
            modelContext.delete(reading)
        }
        try? modelContext.save()
    }

    // MARK: - Helpers

    private func isOutOfRange(_ value: Double) -> Bool {
        value < thresholds.low || value > thresholds.high
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.1f °C", value)
    }
}

// MARK: - Ligne d'historique

private struct ReadingRow: View {
    let reading: TemperatureReading
    let outOfRange: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(String(format: "%.1f °C", reading.celsius))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(outOfRange ? Theme.wine : .primary)
                Text(reading.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = reading.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if outOfRange {
                StatusBadge(
                    text: "Hors plage",
                    color: Theme.wine,
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - Éditeur de seuils

private struct ThresholdEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var thresholds: TemperatureThresholds
    let onSave: (TemperatureThresholds) -> Void

    @State private var low: Double
    @State private var high: Double

    init(thresholds: Binding<TemperatureThresholds>, onSave: @escaping (TemperatureThresholds) -> Void) {
        _thresholds = thresholds
        self.onSave = onSave
        _low = State(initialValue: thresholds.wrappedValue.low)
        _high = State(initialValue: thresholds.wrappedValue.high)
    }

    private var isValid: Bool { low < high }

    var body: some View {
        NavigationStack {
            Form {
                Section("Seuil bas") {
                    Stepper(value: $low, in: -2...20, step: 0.5) {
                        Text(String(format: "%.1f °C", low))
                    }
                }
                Section("Seuil haut") {
                    Stepper(value: $high, in: 0...25, step: 0.5) {
                        Text(String(format: "%.1f °C", high))
                    }
                }
                if !isValid {
                    Section {
                        Label("Le seuil bas doit être inférieur au seuil haut.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.wine)
                    }
                }
            }
            .navigationTitle("Seuils d'alerte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let updated = TemperatureThresholds(low: low, high: high)
                        thresholds = updated
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

// MARK: - Seuils persistés par cave (UserDefaults)

struct TemperatureThresholds {
    var low: Double
    var high: Double

    static let `default` = TemperatureThresholds(low: 10, high: 14)

    private static func lowKey(_ id: UUID) -> String { "caveos.temp.low.\(id.uuidString)" }
    private static func highKey(_ id: UUID) -> String { "caveos.temp.high.\(id.uuidString)" }

    static func load(for cellarID: UUID) -> TemperatureThresholds {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: lowKey(cellarID)) != nil,
              defaults.object(forKey: highKey(cellarID)) != nil else {
            return .default
        }
        return TemperatureThresholds(
            low: defaults.double(forKey: lowKey(cellarID)),
            high: defaults.double(forKey: highKey(cellarID))
        )
    }

    func save(for cellarID: UUID) {
        let defaults = UserDefaults.standard
        defaults.set(low, forKey: Self.lowKey(cellarID))
        defaults.set(high, forKey: Self.highKey(cellarID))
    }
}

#Preview {
    NavigationStack {
        TemperatureLogView(cellar: Cellar(name: "Cave principale"))
    }
    .modelContainer(for: AppSchema.models, inMemory: true)
}
