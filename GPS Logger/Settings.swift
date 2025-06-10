import Foundation
import Combine

/// Stores adjustable parameters for altitude filtering.
final class Settings: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var cancellables = Set<AnyCancellable>()

    @UserDefaultBacked(key: "processNoise") var processNoise: Double = 0.2
    @UserDefaultBacked(key: "measurementNoise") var measurementNoise: Double = 15.0
    @UserDefaultBacked(key: "useKalmanFilter") var useKalmanFilter: Bool = true
    @UserDefaultBacked(key: "logInterval") var logInterval: Double = 1.0
    @UserDefaultBacked(key: "baroWeight") var baroWeight: Double = 0.75

    // Flight Assist stability thresholds
    @UserDefaultBacked(key: "faStableDuration") var faStableDuration: Double = 3.0
    @UserDefaultBacked(key: "faTrackCILimit") var faTrackCILimit: Double = 3.0
    @UserDefaultBacked(key: "faSpeedCILimit") var faSpeedCILimit: Double = 3.0

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

    // Display / record options
    @UserDefaultBacked(key: "showEllipsoidalAltitude") var showEllipsoidalAltitude: Bool = false
    @UserDefaultBacked(key: "recordEllipsoidalAltitude") var recordEllipsoidalAltitude: Bool = false

    /// 表示する空域カテゴリ
    @UserDefaultBacked(key: "enabledAirspaceCategories") var enabledAirspaceCategories: [String] = []

    /// 有効化された空域グループ
    @UserDefaultBacked(key: "enabledAirspaceGroups") var enabledAirspaceGroups: [String] = []

    /// 非表示フィーチャ ID
    @UserDefaultBacked(key: "hiddenFeatureIDs") var hiddenFeatureIDs: [String: [String]] = [:]
    /// 線色設定
    @UserDefaultBacked(key: "airspaceStrokeColors") var airspaceStrokeColors: [String: String] = [:]
    /// 塗り色設定
    @UserDefaultBacked(key: "airspaceFillColors") var airspaceFillColors: [String: String] = [:]

    // Mach/CAS calculation option
    @UserDefaultBacked(key: "enableMachCalculation") var enableMachCalculation: Bool = true

    /// 使用可能なレンジ段階 (レンジリング半径)
    static let rangeLevelsNm: [Double] = [2.5, 5, 10, 20, 40, 80, 160]

    /// レンジリングの半径 (NM)
    @UserDefaultBacked(key: "rangeRingRadiusNm") var rangeRingRadiusNm: Double = 10.0

    /// Night テーマを使用するかどうか
    @UserDefaultBacked(key: "useNightTheme") var useNightTheme: Bool = false

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

        $useKalmanFilter
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $faStableDuration
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $faTrackCILimit
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $faSpeedCILimit
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $showEllipsoidalAltitude
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordEllipsoidalAltitude
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $enabledAirspaceCategories
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $enabledAirspaceGroups
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $hiddenFeatureIDs
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $airspaceStrokeColors
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $airspaceFillColors
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $enableMachCalculation
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $rangeRingRadiusNm
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $useNightTheme
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
