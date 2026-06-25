import Foundation
import CoreGraphics

/// Pont d'action SwiftUI -> contrôleur AVFoundation.
///
/// Permet de déclencher la prise de vue (ou la mise au point) depuis un bouton
/// SwiftUI sans recréer le contrôleur ni piloter la capture via `@Binding`
/// (qui re-déclencherait `updateUIViewController` à chaque frappe d'état).
///
/// Le `CameraCaptureView` (Representable) câble les closures via `connect(...)`
/// au moment de la création du contrôleur ; l'écran appelle ensuite
/// `capturePhoto()` / `focus(at:)` sans jamais connaître le contrôleur sous-jacent.
@MainActor
final class CameraProxy {
    /// Action de capture branchée par le Representable (no-op tant que non câblée).
    private var captureAction: () -> Void = {}
    /// Action de mise au point branchée par le Representable.
    private var focusAction: (CGPoint) -> Void = { _ in }

    /// Déclenche une prise de vue unique.
    func capturePhoto() { captureAction() }

    /// Demande une mise au point sur un point de la preview (coordonnées vue).
    func focus(at point: CGPoint) { focusAction(point) }

    /// Câblage interne : réservé au `CameraCaptureView` pour relier le contrôleur.
    func connect(capture: @escaping () -> Void, focus: @escaping (CGPoint) -> Void) {
        captureAction = capture
        focusAction = focus
    }
}
