import AVFoundation
import Observation
import UIKit

/// Owns the capture session for the label camera.
@Observable
@MainActor
final class CameraController: NSObject {
    enum Authorization: Equatable {
        case notDetermined
        case authorized
        case denied
        case restricted
        /// The simulator has no camera; the UI offers the photo library instead of a dead
        /// viewfinder.
        case unavailable
    }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var isRunning = false
    private(set) var isCapturing = false
    private(set) var isTorchOn = false
    private(set) var isTorchAvailable = false
    private(set) var failureMessage: String?

    nonisolated let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.ullage.camera-session")
    private var device: AVCaptureDevice?
    private var isConfigured = false
    private var captureContinuation: CheckedContinuation<UIImage, Error>?

    enum CaptureError: LocalizedError {
        case notReady
        case noImageData

        var errorDescription: String? {
            switch self {
            case .notReady: return "The camera is not ready yet."
            case .noImageData: return "The photo could not be read."
            }
        }
    }

    // MARK: - Permissions and lifecycle

    func prepare() async {
        #if targetEnvironment(simulator)
        authorization = .unavailable
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .authorized
        case .notDetermined:
            authorization = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        case .denied:
            authorization = .denied
        case .restricted:
            authorization = .restricted
        @unknown default:
            authorization = .denied
        }
        guard authorization == .authorized else { return }
        await configureIfNeeded()
        start()
        #endif
    }

    func start() {
        guard isConfigured, !isRunning else { return }
        isRunning = true
        sessionQueue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        setTorch(on: false)
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureIfNeeded() async {
        guard !isConfigured else { return }

        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        ).devices.first

        guard let device = discovered else {
            authorization = .unavailable
            return
        }
        self.device = device
        isTorchAvailable = device.hasTorch

        // The result is reported back out of the session queue rather than read from the
        // session afterwards, so nothing inspects session state off its own queue.
        let didConfigure = await withCheckedContinuation { continuation in
            sessionQueue.async { [session, output] in
                session.beginConfiguration()
                session.sessionPreset = .photo

                var succeeded = false
                defer {
                    session.commitConfiguration()
                    continuation.resume(returning: succeeded)
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else { return }
                    session.addInput(input)
                } catch {
                    return
                }

                guard session.canAddOutput(output) else { return }
                session.addOutput(output)
                output.maxPhotoQualityPrioritization = .quality
                succeeded = true
            }
        }

        configureFocusForLabels(device)
        isConfigured = didConfigure
        if !isConfigured {
            failureMessage = "The camera could not be started."
        }
    }

    /// Labels are photographed close up, so continuous autofocus with a near-field bias finds
    /// the text far more reliably than the default distant-subject configuration.
    private func configureFocusForLabels(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            // Focus tuning is an improvement, not a requirement; the camera still works.
        }
    }

    // MARK: - Torch

    /// Worth having: wine gets photographed in restaurants and cellars, which are dark.
    func toggleTorch() {
        setTorch(on: !isTorchOn)
    }

    private func setTorch(on: Bool) {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            isTorchOn = on
        } catch {
            isTorchOn = false
        }
    }

    // MARK: - Capture

    func capturePhoto() async throws -> UIImage {
        guard isConfigured, isRunning else { throw CaptureError.notReady }
        guard !isCapturing else { throw CaptureError.notReady }
        isCapturing = true
        defer { isCapturing = false }

        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.photoQualityPrioritization = .quality
        settings.flashMode = .off

        return try await withCheckedThrowingContinuation { continuation in
            captureContinuation = continuation
            sessionQueue.async { [output] in
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func finishCapture(with result: Result<UIImage, Error>) {
        guard let continuation = captureContinuation else { return }
        captureContinuation = nil
        continuation.resume(with: result)
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let result: Result<UIImage, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            result = .success(image)
        } else {
            result = .failure(CaptureError.noImageData)
        }
        Task { @MainActor [weak self] in
            self?.finishCapture(with: result)
        }
    }
}
