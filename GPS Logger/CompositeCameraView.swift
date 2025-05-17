import SwiftUI
import UIKit

/// A simple camera view that saves captured image and overlay text.
/// This is a minimal placeholder implementation and does not include
/// advanced functionality.
struct CompositeCameraView: UIViewControllerRepresentable {
    @Binding var capturedCompositeImage: UIImage?
    @Binding var capturedOverlayText: String
    @EnvironmentObject var locationManager: LocationManager

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: CompositeCameraView

        init(parent: CompositeCameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedCompositeImage = image
                if let loc = parent.locationManager.lastLocation {
                    parent.capturedOverlayText = String(format: "Lat: %.5f\nLon: %.5f", loc.coordinate.latitude, loc.coordinate.longitude)
                }
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}
