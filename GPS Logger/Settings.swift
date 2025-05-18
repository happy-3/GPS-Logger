import Foundation
import Combine

/// Stores adjustable parameters for altitude filtering.
final class Settings: ObservableObject {
    @UserDefaultBacked(key: "processNoise") var processNoise: Double = 0.2
    @UserDefaultBacked(key: "measurementNoise") var measurementNoise: Double = 15.0
    @UserDefaultBacked(key: "logInterval") var logInterval: Double = 1.0
    @UserDefaultBacked(key: "baroWeight") var baroWeight: Double = 0.75

    // Recording options
    @UserDefaultBacked(key: "recordAcceleration") var recordAcceleration: Bool = true
    @UserDefaultBacked(key: "recordAltimeterPressure") var recordAltimeterPressure: Bool = true
    @UserDefaultBacked(key: "recordRawGpsRate") var recordRawGpsRate: Bool = true
    @UserDefaultBacked(key: "recordRelativeAltitude") var recordRelativeAltitude: Bool = true
    @UserDefaultBacked(key: "recordBarometricAltitude") var recordBarometricAltitude: Bool = true
    @UserDefaultBacked(key: "recordFusedAltitude") var recordFusedAltitude: Bool = true
    @UserDefaultBacked(key: "recordFusedRate") var recordFusedRate: Bool = true
    @UserDefaultBacked(key: "recordBaselineAltitude") var recordBaselineAltitude: Bool = true
    @UserDefaultBacked(key: "recordMeasuredAltitude") var recordMeasuredAltitude: Bool = true
    @UserDefaultBacked(key: "recordKalmanInterval") var recordKalmanInterval: Bool = true

    init() {}
}
