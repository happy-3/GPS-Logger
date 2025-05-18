import Foundation
import Combine

/// Stores adjustable parameters for altitude filtering.
final class Settings: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var cancellables = Set<AnyCancellable>()

    @UserDefaultBacked(key: "processNoise") var processNoise: Double = 0.2
    @UserDefaultBacked(key: "measurementNoise") var measurementNoise: Double = 15.0
    @UserDefaultBacked(key: "logInterval") var logInterval: Double = 1.0
    @UserDefaultBacked(key: "baroWeight") var baroWeight: Double = 0.75

    // Photo capture options
    @UserDefaultBacked(key: "photoPreSeconds") var photoPreSeconds: Double = 3.0
    @UserDefaultBacked(key: "photoPostSeconds") var photoPostSeconds: Double = 3.0

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

    init() {
        $processNoise
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $measurementNoise
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $logInterval
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $baroWeight
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $photoPreSeconds
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $photoPostSeconds
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordAcceleration
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordAltimeterPressure
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordRawGpsRate
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordRelativeAltitude
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordBarometricAltitude
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordFusedAltitude
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordFusedRate
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordBaselineAltitude
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordMeasuredAltitude
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordKalmanInterval
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
