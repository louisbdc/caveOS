import SwiftUI
import AVFoundation
import UIKit

/// Contrôleur de capture photo **unique** (pas de flux par frame, conforme à la
/// règle « pas de scan continu » : économie CPU/tokens et évite tout conflit
/// caméra avec le `DataScannerViewController` du mode appareil).
///
/// Le pilotage de session (`startRunning`/`stopRunning`/`beginConfiguration`)
/// est bloquant : il s'exécute sur une file série dédiée, jamais sur le main
/// thread. Les objets AVFoundation sont marqués `nonisolated(unsafe)` car ils
/// sont manipulés exclusivement sur cette file série (et à la configuration
/// initiale), pas via l'isolation `@MainActor` du `UIViewController`.
@MainActor
final class CameraCaptureController: UIViewController {

    // Pilotage de session hors du main thread (start/stop/configure bloquants).
    private let sessionQueue = DispatchQueue(label: "caveos.camera.session")
    nonisolated(unsafe) private let session = AVCaptureSession()
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    nonisolated(unsafe) private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var isConfigured = false

    /// Livré sur le main actor avec une image déjà redressée (`normalizedUp()`).
    var onCapture: ((UIImage) -> Void)?
    /// Livré sur le main actor en cas d'échec (config impossible, données vides…).
    var onError: ((Error) -> Void)?

    enum CameraError: Error { case configurationFailed, emptyData }

    // MARK: - Cycle de vue

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill          // remplit, recadre (pas de bandes)
        view.layer.addSublayer(layer)
        previewLayer = layer
        configureSessionIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds               // suit rotations / safe area
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startRunning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopRunning()
    }

    // MARK: - Configuration (une seule fois, paresseuse)

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo          // pleine résolution étiquette
            defer { self.session.commitConfiguration() }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input),
                self.session.canAddOutput(self.photoOutput)
            else {
                self.deliverError(CameraError.configurationFailed)
                return
            }
            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)
            self.photoOutput.maxPhotoQualityPrioritization = .quality

            self.setUpRotationCoordinator(for: device)
        }
    }

    /// Orientation moderne (iOS 17+) : pilote la preview ET la sortie photo via
    /// `RotationCoordinator` (remplace `videoOrientation`, déprécié).
    ///
    /// `nonisolated` car appelée depuis la file session ; le travail touchant la
    /// preview repasse explicitement sur le main actor.
    nonisolated private func setUpRotationCoordinator(for device: AVCaptureDevice) {
        // `device` est créé sur la file session ; sa région a fusionné avec celle
        // de `self` (@MainActor) via `session.addInput`. On le ré-expose en
        // `nonisolated(unsafe)` pour le confier à la closure main actor : sûr car
        // l'objet n'est plus touché ailleurs après cet appel (lecture seule).
        nonisolated(unsafe) let device = device
        Task { @MainActor in
            let coordinator = AVCaptureDevice.RotationCoordinator(
                device: device,
                previewLayer: self.previewLayer
            )
            self.rotationCoordinator = coordinator
            if let connection = self.previewLayer?.connection {
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
        }
    }

    // MARK: - Run / stop (file session)

    private func startRunning() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    private func stopRunning() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - Capture unique

    func capturePhoto() {
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.photoQualityPrioritization = .quality
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Aligne la photo sur l'angle « horizon » courant (évite une image tournée).
            if let coordinator = self.rotationCoordinator,
               let connection = self.photoOutput.connection(with: .video) {
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Mise au point optionnelle (tap-to-focus). `point` en coordonnées de la vue.
    func focus(at point: CGPoint) {
        guard let previewLayer else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        sessionQueue.async { [weak self] in
            guard
                let self,
                let input = self.session.inputs.first as? AVCaptureDeviceInput
            else { return }
            let device = input.device
            guard (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
        }
    }

    /// Repasse une erreur sur le main actor pour la livrer à SwiftUI.
    nonisolated private func deliverError(_ error: Error) {
        Task { @MainActor in self.onError?(error) }
    }
}

// MARK: - Réception de la photo

extension CameraCaptureController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            deliverError(error)
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            deliverError(CameraError.emptyData)
            return
        }
        // L'image embarque l'orientation EXIF -> on redresse les pixels avant le
        // handoff : Vision et le JPEG aval ignorent l'EXIF (sinon étiquette tournée).
        let normalized = image.normalizedUp()
        Task { @MainActor in self.onCapture?(normalized) }
    }
}

// MARK: - Representable SwiftUI

/// Pont SwiftUI vers `CameraCaptureController`. La capture est déclenchée via
/// `proxy` ; aucun état SwiftUI ne reconfigure la session (`updateUIViewController`
/// volontairement vide) pour éviter tout churn.
@MainActor
struct CameraCaptureView: UIViewControllerRepresentable {
    let proxy: CameraProxy
    let onCapture: (UIImage) -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> CameraCaptureController {
        let controller = CameraCaptureController()
        controller.onCapture = onCapture
        controller.onError = onError
        proxy.connect(
            capture: { [weak controller] in controller?.capturePhoto() },
            focus: { [weak controller] point in controller?.focus(at: point) }
        )
        return controller
    }

    func updateUIViewController(_ controller: CameraCaptureController, context: Context) {
        // Volontairement vide : aucun état SwiftUI ne doit reconfigurer la session.
    }
}

// MARK: - Normalisation d'orientation

extension UIImage {
    /// Réécrit les pixels pour que `imageOrientation` soit `.up`.
    ///
    /// Vision et l'encodage JPEG aval ignorent l'orientation EXIF : sans cette
    /// normalisation, une étiquette photographiée en portrait part tournée de 90°
    /// et l'OCR/IA échoue.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
