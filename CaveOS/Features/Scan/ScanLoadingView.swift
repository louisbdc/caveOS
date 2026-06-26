import SwiftUI

/// État de chargement « scan par IA » : voile plein écran, icône animée et
/// messages d'étape qui défilent, pour occuper l'attente serveur (~10-30 s, deux
/// passes : lecture d'image puis déduction œnologique).
///
/// La progression est SIMULÉE côté client : `AIScanService.scan` est opaque (un
/// seul `await`, aucune progression remontée par le serveur). Les messages
/// avancent au rythme `stepDuration` puis restent sur le dernier jusqu'à la
/// réponse réelle. La boucle est portée par `.task`, donc annulée automatiquement
/// quand la vue disparaît (overlay retiré).
struct ScanLoadingView: View {
    private static let steps: [String] = [
        "Lecture de l'étiquette…",
        "Identification du domaine…",
        "Recherche œnologique…",
        "Finalisation…"
    ]
    private static let stepDuration: Duration = .seconds(2.5)

    @State private var stepIndex = 0
    @State private var pulse = false

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            icon
            messages
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .task { await advanceSteps() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyse par IA en cours")
        .accessibilityValue(Self.steps[stepIndex])
    }

    private var icon: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 44))
            .foregroundStyle(Theme.gold)
            .symbolEffect(.variableColor.iterative, options: .repeating)
            .scaleEffect(pulse ? 1.08 : 0.92)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)
    }

    private var messages: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Analyse par IA")
                .font(.headline)
            Text(Self.steps[stepIndex])
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .id(stepIndex)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            ProgressView(value: Double(stepIndex + 1), total: Double(Self.steps.count))
                .tint(Theme.gold)
                .frame(maxWidth: 180)
        }
        .animation(.easeInOut, value: stepIndex)
    }

    /// Avance les messages un à un puis reste sur le dernier (« Finalisation… »).
    /// Annulable : on sort proprement si la vue disparaît avant la réponse.
    private func advanceSteps() async {
        for index in 1..<Self.steps.count {
            try? await Task.sleep(for: Self.stepDuration)
            guard !Task.isCancelled else { return }
            stepIndex = index
        }
    }
}
