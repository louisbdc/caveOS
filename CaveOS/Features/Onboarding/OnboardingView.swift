import SwiftUI

/// Écran d'accueil animé affiché au tout premier lancement.
/// Esthétique « cave premium » : bordeaux profond, or, effervescence.
struct OnboardingView: View {
    /// Appelé lorsque l'utilisateur termine l'onboarding.
    var onFinish: () -> Void

    @State private var page = 0
    @State private var appeared = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "wineglass.fill",
            title: "Bienvenue dans CaveOS",
            subtitle: "La cave à vin dans la poche — rapide, hors-ligne, et pour toujours.",
            isHero: true
        ),
        OnboardingPage(
            symbol: "doc.text.viewfinder",
            title: "Scannez vos étiquettes",
            subtitle: "Reconnaissance native sur l'appareil. Aucune connexion requise, même au fond de la cave.",
            effect: .scan
        ),
        OnboardingPage(
            symbol: "square.grid.3x3.fill",
            title: "Organisez votre cave",
            subtitle: "Clayettes, niveaux et positions configurables librement, en glisser-déposer.",
            effect: .grid
        ),
        OnboardingPage(
            symbol: "hourglass.bottomhalf.filled",
            title: "Ne ratez plus l'apogée",
            subtitle: "Des alertes au bon moment pour boire chaque bouteille à son sommet.",
            effect: .pulse
        )
    ]

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            AnimatedWineBackground()
                .ignoresSafeArea()
            RisingBubbles()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                skipButton

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingSlide(page: item, isActive: page == index)
                            .tag(index)
                            .padding(.horizontal, Theme.Spacing.l)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                pageIndicator
                    .padding(.bottom, Theme.Spacing.l)

                primaryButton
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.xl)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 24)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { appeared = true }
        }
    }

    // MARK: - Sous-vues

    private var skipButton: some View {
        HStack {
            Spacer()
            if !isLast {
                Button("Passer") { finish() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.cream.opacity(0.7))
                    .padding(Theme.Spacing.m)
            }
        }
        .frame(height: 44)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Theme.gold : Theme.cream.opacity(0.3))
                    .frame(width: index == page ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: page)
            }
        }
    }

    private var primaryButton: some View {
        Button {
            if isLast {
                finish()
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { page += 1 }
            }
        } label: {
            Text(isLast ? "Commencer" : "Suivant")
                .font(.headline)
                .foregroundStyle(Theme.wineDeepest)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
                .background(
                    LinearGradient(
                        colors: [Theme.gold, Theme.gold.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.l)
                )
                .shadow(color: Theme.gold.opacity(0.4), radius: 16, y: 6)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func finish() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onFinish()
    }
}

// MARK: - Modèle de page

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let subtitle: String
    var isHero: Bool = false
    var effect: SlideEffect = .none
}

private enum SlideEffect { case none, scan, grid, pulse }

// MARK: - Contenu d'une page

private struct OnboardingSlide: View {
    let page: OnboardingPage
    let isActive: Bool

    @State private var showText = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            if page.isHero {
                WineGlassFill()
                    .frame(width: 170, height: 170)
            } else {
                AnimatedSymbol(symbol: page.symbol, effect: page.effect, isActive: isActive)
            }

            VStack(spacing: Theme.Spacing.m) {
                Text(page.title)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundStyle(Theme.cream)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.title3)
                    .foregroundStyle(Theme.cream.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.s)
            }
            .opacity(showText ? 1 : 0)
            .offset(y: showText ? 0 : 18)

            Spacer()
            Spacer()
        }
        .onChange(of: isActive, initial: true) { _, active in
            showText = false
            if active {
                withAnimation(.easeOut(duration: 0.6).delay(0.15)) { showText = true }
            }
        }
    }
}

// MARK: - Symbole animé

private struct AnimatedSymbol: View {
    let symbol: String
    let effect: SlideEffect
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.gold.opacity(0.35), .clear],
                        center: .center, startRadius: 4, endRadius: 110
                    )
                )
                .frame(width: 220, height: 220)

            Image(systemName: symbol)
                .font(.system(size: 88, weight: .regular))
                .foregroundStyle(
                    LinearGradient(colors: [Theme.gold, Theme.cream], startPoint: .top, endPoint: .bottom)
                )
                .modifier(SymbolEffectModifier(effect: effect, isActive: isActive))
                .shadow(color: Theme.wineDeepest.opacity(0.6), radius: 12, y: 8)
        }
        .scaleEffect(isActive ? 1 : 0.85)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isActive)
    }
}

/// Applique un effet de symbole selon la page (iOS 17+).
private struct SymbolEffectModifier: ViewModifier {
    let effect: SlideEffect
    let isActive: Bool

    func body(content: Content) -> some View {
        switch effect {
        case .scan:
            content.symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: isActive)
        case .pulse:
            content.symbolEffect(.pulse, isActive: isActive)
        case .grid, .none:
            content.symbolEffect(.bounce, value: isActive)
        }
    }
}

// MARK: - Verre de vin qui se remplit (animation héro)

private struct WineGlassFill: View {
    @State private var fill: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t.truncatingRemainder(dividingBy: 1000)) * 2.4

            ZStack {
                WaveShape(progress: fill, phase: phase, amplitude: 5)
                    .fill(
                        LinearGradient(
                            colors: [Theme.wineDeep, Theme.wineDeepest],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            .mask(
                Image(systemName: "wineglass.fill")
                    .resizable()
                    .scaledToFit()
            )
            .overlay(
                Image(systemName: "wineglass")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.gold)
            )
            .shadow(color: Theme.gold.opacity(0.35), radius: 18)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.9)) { fill = 0.7 }
        }
    }
}

/// Surface de liquide ondulante, remplissant de bas en haut.
private struct WaveShape: Shape {
    var progress: CGFloat
    var phase: CGFloat
    var amplitude: CGFloat = 6

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseY = rect.height * (1 - progress)
        path.move(to: CGPoint(x: 0, y: baseY))

        var x: CGFloat = 0
        while x <= rect.width {
            let relative = x / max(rect.width, 1)
            let y = baseY + sin(relative * .pi * 4 + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 3
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Fond dégradé animé

private struct AnimatedWineBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Theme.wineDeepest
                blob(color: Theme.wineDeep, t: t, speed: 0.18, radius: 360, base: CGPoint(x: 0.3, y: 0.25))
                blob(color: Color(red: 0.32, green: 0.04, blue: 0.10), t: t, speed: 0.13, radius: 420, base: CGPoint(x: 0.75, y: 0.7))
                blob(color: Theme.gold.opacity(0.18), t: t, speed: 0.22, radius: 260, base: CGPoint(x: 0.6, y: 0.2))
            }
        }
    }

    private func blob(color: Color, t: TimeInterval, speed: Double, radius: CGFloat, base: CGPoint) -> some View {
        GeometryReader { geo in
            let dx = CGFloat(sin(t * speed)) * 0.12
            let dy = CGFloat(cos(t * speed * 0.8)) * 0.12
            let center = CGPoint(
                x: (base.x + dx) * geo.size.width,
                y: (base.y + dy) * geo.size.height
            )
            RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: radius)
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
                .blur(radius: 30)
        }
    }
}

// MARK: - Bulles d'effervescence

private struct RisingBubbles: View {
    private let bubbles: [Bubble] = RisingBubbles.makeBubbles()

    static func makeBubbles() -> [Bubble] {
        var result: [Bubble] = []
        for i in 0..<18 {
            let x = CGFloat(i * 53 % 100) / 100.0
            let size = CGFloat(4 + (i * 7 % 12))
            let duration = Double(6 + (i * 3 % 7))
            let delay = Double(i) * 0.4
            result.append(Bubble(x: x, size: size, duration: duration, delay: delay))
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(bubbles) { bubble in
                        bubbleView(bubble, t: t, size: geo.size)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bubbleView(_ bubble: Bubble, t: TimeInterval, size: CGSize) -> some View {
        let progress: CGFloat = CGFloat(((t + bubble.delay) / bubble.duration).truncatingRemainder(dividingBy: 1))
        let sway: CGFloat = CGFloat(sin(Double(progress) * .pi * 4)) * 10
        let posX: CGFloat = bubble.x * size.width + sway
        let posY: CGFloat = size.height * (1 - progress)

        Circle()
            .fill(Theme.gold.opacity(0.5))
            .frame(width: bubble.size, height: bubble.size)
            .position(x: posX, y: posY)
            .opacity(bubbleOpacity(progress))
    }

    private func bubbleOpacity(_ progress: CGFloat) -> Double {
        let p = Double(progress)
        if p < 0.1 { return p * 10 * 0.6 }
        if p > 0.85 { return ((1 - p) / 0.15) * 0.6 }
        return 0.6
    }

    struct Bubble: Identifiable {
        let id = UUID()
        let x: CGFloat
        let size: CGFloat
        let duration: Double
        let delay: Double
    }
}

// MARK: - Style de bouton pressable

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
