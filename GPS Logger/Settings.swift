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

    // Recording options
    @Published var recordAcceleration: Bool {
        didSet { UserDefaults.standard.set(recordAcceleration, forKey: "recordAcceleration") }
    }
    @Published var recordAltimeterPressure: Bool {
        didSet { UserDefaults.standard.set(recordAltimeterPressure, forKey: "recordAltimeterPressure") }
    }
    @Published var recordRawGpsRate: Bool {
        didSet { UserDefaults.standard.set(recordRawGpsRate, forKey: "recordRawGpsRate") }
    }
    @Published var recordRelativeAltitude: Bool {
        didSet { UserDefaults.standard.set(recordRelativeAltitude, forKey: "recordRelativeAltitude") }
    }
    @Published var recordBarometricAltitude: Bool {
        didSet { UserDefaults.standard.set(recordBarometricAltitude, forKey: "recordBarometricAltitude") }
    }
    @Published var recordFusedAltitude: Bool {
        didSet { UserDefaults.standard.set(recordFusedAltitude, forKey: "recordFusedAltitude") }
    }
    @Published var recordFusedRate: Bool {
        didSet { UserDefaults.standard.set(recordFusedRate, forKey: "recordFusedRate") }
    }
    @Published var recordBaselineAltitude: Bool {
        didSet { UserDefaults.standard.set(recordBaselineAltitude, forKey: "recordBaselineAltitude") }
    }
    @Published var recordMeasuredAltitude: Bool {
        didSet { UserDefaults.standard.set(recordMeasuredAltitude, forKey: "recordMeasuredAltitude") }
    }
    @Published var recordKalmanInterval: Bool {
        didSet { UserDefaults.standard.set(recordKalmanInterval, forKey: "recordKalmanInterval") }
    }

    init() {
        processNoise = UserDefaults.standard.object(forKey: "processNoise") as? Double ?? 0.2
        measurementNoise = UserDefaults.standard.object(forKey: "measurementNoise") as? Double ?? 15.0
        logInterval = UserDefaults.standard.object(forKey: "logInterval") as? Double ?? 1.0
        baroWeight = UserDefaults.standard.object(forKey: "baroWeight") as? Double ?? 0.75
        recordAcceleration = UserDefaults.standard.object(forKey: "recordAcceleration") as? Bool ?? true
        recordAltimeterPressure = UserDefaults.standard.object(forKey: "recordAltimeterPressure") as? Bool ?? true
        recordRawGpsRate = UserDefaults.standard.object(forKey: "recordRawGpsRate") as? Bool ?? true
        recordRelativeAltitude = UserDefaults.standard.object(forKey: "recordRelativeAltitude") as? Bool ?? true
        recordBarometricAltitude = UserDefaults.standard.object(forKey: "recordBarometricAltitude") as? Bool ?? true
        recordFusedAltitude = UserDefaults.standard.object(forKey: "recordFusedAltitude") as? Bool ?? true
        recordFusedRate = UserDefaults.standard.object(forKey: "recordFusedRate") as? Bool ?? true
        recordBaselineAltitude = UserDefaults.standard.object(forKey: "recordBaselineAltitude") as? Bool ?? true
        recordMeasuredAltitude = UserDefaults.standard.object(forKey: "recordMeasuredAltitude") as? Bool ?? true
        recordKalmanInterval = UserDefaults.standard.object(forKey: "recordKalmanInterval") as? Bool ?? true
    }
}
