import Foundation
import Combine

/// Stores adjustable parameters for altitude filtering.
final class Settings: ObservableObject {
    @Published var processNoise: Double {
        didSet { UserDefaults.standard.set(processNoise, forKey: "processNoise") }
    }
    @Published var measurementNoise: Double {
        didSet { UserDefaults.standard.set(measurementNoise, forKey: "measurementNoise") }
    }
    @Published var logInterval: Double {
        didSet { UserDefaults.standard.set(logInterval, forKey: "logInterval") }
    }
    @Published var baroWeight: Double {
        didSet { UserDefaults.standard.set(baroWeight, forKey: "baroWeight") }
    }

    init() {
        processNoise = UserDefaults.standard.object(forKey: "processNoise") as? Double ?? 0.2
        measurementNoise = UserDefaults.standard.object(forKey: "measurementNoise") as? Double ?? 15.0
        logInterval = UserDefaults.standard.object(forKey: "logInterval") as? Double ?? 1.0
        baroWeight = UserDefaults.standard.object(forKey: "baroWeight") as? Double ?? 0.75
    }
}
