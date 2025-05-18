import SwiftUI
import AVFoundation
import UIKit

/// SwiftUI wrapper around `CameraViewController`.
struct CompositeCameraView: UIViewControllerRepresentable {
    @Binding var capturedCompositeImage: UIImage?
    @EnvironmentObject var locationManager: LocationManager
    let settings: Settings

    func makeUIViewController(context: Context) -> CameraViewController {
        let manager = CameraSessionManager(logInterval: settings.logInterval)
        let vc = CameraViewController(manager: manager, locationManager: locationManager) { image in
            capturedCompositeImage = image
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // no-op
    }
}

/// Basic view controller displaying camera preview and a shutter button.
final class CameraViewController: UIViewController {
    private let manager: CameraSessionManager
    private weak var locationManager: LocationManager?
    private let completion: (UIImage?) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?

    init(manager: CameraSessionManager,
         locationManager: LocationManager,
         completion: @escaping (UIImage?) -> Void) {
        self.manager = manager
        self.locationManager = locationManager
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let layer = AVCaptureVideoPreviewLayer(session: manager.session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("\u{f030}", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 40)
        button.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        manager.startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        manager.stopSession()
    }

    @objc private func shutterTapped() {
        guard let index = locationManager?.recordPhotoCapture(),
              let folderURL = locationManager?.flightLogManager.sessionFolderURL else {
            dismiss(animated: true)
            return
        }
        // Capture frames after 3 seconds then save.
        let shutterTime = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            self.manager.saveBufferedFrames(to: folderURL, index: index, shutterTime: shutterTime)
            let first = self.manager.bufferedFrames().last?.image
            self.completion(first)
            self.dismiss(animated: true)
        }
    }
}
