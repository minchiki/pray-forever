import AVFoundation
import UIKit

/// Живая камера (без доступа к галерее — нельзя подсунуть старое фото).
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum State: Equatable { case idle, running, denied, unavailable }

    static let maxSide: CGFloat = 1024

    @Published private(set) var state: State = .idle

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "sajda.camera")
    private var configured = false
    private var completion: ((CGImage?) -> Void)?

    override init() {
        super.init()
        // Камера не должна перехватывать аудиосессию, иначе будильник замолчит.
        session.automaticallyConfiguresApplicationAudioSession = false
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.startSession() } else { self?.publish(.denied) }
            }
        default:
            publish(.denied)
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Делает снимок и возвращает его в нормальной ориентации (.up), уменьшенным до 1024 px.
    func capture(_ done: @escaping (CGImage?) -> Void) {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else {
                DispatchQueue.main.async { done(nil) }
                return
            }
            self.completion = done
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:)).flatMap(Self.normalized)
        let done = completion
        completion = nil
        DispatchQueue.main.async { done?(image) }
    }

    private func startSession() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                guard self.configure() else { return self.publish(.unavailable) }
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            self.publish(.running)
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        return true
    }

    private func publish(_ state: State) {
        DispatchQueue.main.async { self.state = state }
    }

    private static func normalized(_ image: UIImage) -> CGImage? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
