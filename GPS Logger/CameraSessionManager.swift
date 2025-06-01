import AVFoundation
import UIKit

/// Manages an AVCaptureSession and keeps a rolling buffer of still images
/// captured at the application's log interval. The buffer length is
/// determined by the configured pre/post capture durations so that frames
/// around the shutter event can be retrieved.
struct Frame {
    let image: UIImage
    let timestamp: Date
}

class CameraSessionManager: NSObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "CameraSessionQueue")

    private var lastCaptureTime: Date?
    private var ringBuffer: [Frame] = []
    private let ringCapacity: Int
    private var logInterval: Double
    private let preDuration: Double
    private let postDuration: Double

    init(logInterval: Double, preDuration: Double, postDuration: Double) {
        self.logInterval = logInterval
        self.preDuration = preDuration
        self.postDuration = postDuration
        self.ringCapacity = Int(ceil((preDuration + postDuration) / logInterval))
        super.init()
        configureSession()
    }

    /// Configure the capture session with the default video device.
    private func configureSession() {
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(videoOutput) {
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()
    }

    /// Start running the capture session and begin sampling frames.
    /// The call to `startRunning()` can block, so perform it on the
    /// dedicated session queue to avoid blocking the main thread.
    func startSession() {
        guard !session.isRunning else { return }
        queue.async { [session] in
            session.startRunning()
        }
    }

    /// Stop the session and clear the ring buffer.
    /// Like `startRunning()`, `stopRunning()` should also run off the main thread.
    func stopSession() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            ringBuffer.removeAll()
            lastCaptureTime = nil
        }
    }

    /// Configure the connection orientation for the next frame capture.
    private func captureCurrentFrame() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if #available(iOS 17, *) {
            connection.videoRotationAngle = 90
        } else {
            connection.videoOrientation = .portrait
        }
    }

    // Previous capture time is used instead of a repeating timer to sample frames

    /// Retrieve the buffered frames for saving.
    func bufferedFrames() -> [Frame] {
        return queue.sync { ringBuffer }
    }

    /// Save buffered frames to a folder named Photo_<index> inside the provided session URL.
    func saveBufferedFrames(to sessionURL: URL, index: Int, shutterTime: Date) {
        let frames = queue.sync { ringBuffer }
        let folder = sessionURL.appendingPathComponent("Photo_\(index)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let baseName = DateFormatter.shortNameFormatter.string(from: shutterTime)

        let validFrames = frames.filter { frame in
            let diff = frame.timestamp.timeIntervalSince(shutterTime)
            return diff >= -preDuration && diff <= postDuration
        }

        guard !validFrames.isEmpty else { return }
        let center = validFrames.min { a, b in
            abs(a.timestamp.timeIntervalSince(shutterTime)) < abs(b.timestamp.timeIntervalSince(shutterTime))
        }

        for frame in validFrames {
            let diff = frame.timestamp.timeIntervalSince(shutterTime)
            let fileName: String
            if frame.timestamp == center?.timestamp {
                fileName = "\(baseName).jpg"
            } else if diff < 0 {
                fileName = String(format: "\(baseName)-%.1fs.jpg", abs(diff))
            } else {
                fileName = String(format: "\(baseName)+%.1fs.jpg", diff)
            }
            let url = folder.appendingPathComponent(fileName)
            if let data = frame.image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: url)
            }
        }
        // Clear any frames that were just saved so previous captures are not
        // mixed into the next shutter event.
        queue.sync {
            ringBuffer.removeAll()
        }
    }
}

extension CameraSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        if let last = lastCaptureTime, now.timeIntervalSince(last) < logInterval {
            return
        }
        captureCurrentFrame()
        guard let image = imageFromSampleBuffer(sampleBuffer) else { return }
        if ringBuffer.count >= ringCapacity {
            ringBuffer.removeFirst()
        }
        ringBuffer.append(Frame(image: image, timestamp: now))
        lastCaptureTime = now
    }

    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}
