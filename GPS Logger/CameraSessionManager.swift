import AVFoundation
import UIKit

/// Manages an AVCaptureSession and keeps a rolling buffer of still images
/// captured at the application's log interval. The buffer keeps roughly
/// six seconds of frames so that three seconds before and after a shutter
/// event can be retrieved.
class CameraSessionManager: NSObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "CameraSessionQueue")

    private var timer: Timer?
    private var ringBuffer: [UIImage] = []
    private let ringCapacity: Int
    private var logInterval: Double

    init(logInterval: Double) {
        self.logInterval = logInterval
        self.ringCapacity = Int(ceil(6.0 / logInterval))
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
    func startSession() {
        guard !session.isRunning else { return }
        session.startRunning()
        startTimer()
    }

    /// Stop the session and clear the ring buffer.
    func stopSession() {
        timer?.invalidate()
        timer = nil
        session.stopRunning()
        ringBuffer.removeAll()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: logInterval, repeats: true) { [weak self] _ in
            self?.captureCurrentFrame()
        }
    }

    /// Capture the most recent frame in the video output and store it in the ring buffer.
    private func captureCurrentFrame() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        connection.videoOrientation = .portrait
        // Actual frame capture happens via delegate; here we just ensure we get called regularly.
    }

    /// Retrieve the buffered frames for saving.
    func bufferedFrames() -> [UIImage] {
        return ringBuffer
    }

    /// Save buffered frames to a folder named Photo_<index> inside the provided session URL.
    func saveBufferedFrames(to sessionURL: URL, index: Int) {
        let folder = sessionURL.appendingPathComponent("Photo_\(index)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (i, image) in ringBuffer.enumerated() {
            let filename = String(format: "frame_%04d.jpg", i + 1)
            let url = folder.appendingPathComponent(filename)
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: url)
            }
        }
    }
}

extension CameraSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let image = imageFromSampleBuffer(sampleBuffer) else { return }
        if ringBuffer.count >= ringCapacity {
            ringBuffer.removeFirst()
        }
        ringBuffer.append(image)
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
