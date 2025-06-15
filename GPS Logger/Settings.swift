import Foundation
import Combine

/// Stores adjustable parameters for altitude filtering.
@MainActor
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

    enum MapOrientationMode: String, CaseIterable, Identifiable {
        case northUp, trackUp, magneticUp, manual
        var id: Self { self }
        var label: String {
            switch self {
            case .northUp: "North UP"
            case .trackUp: "Track UP"
            case .magneticUp: "Magnetic UP"
            case .manual: "Free Rotate"
            }
        }
    }

    @UserDefaultBacked(key: "orientationMode") var orientationMode: MapOrientationMode = .trackUp

    /// ズーム可能な正方形サイズ (一辺) を NM で定義
    static let zoomDiametersNm: [Double] = [5, 10, 20, 40, 80, 160, 320]

    /// 既存コードとの互換用に半径値も保持
    static let rangeLevelsNm: [Double] = zoomDiametersNm.map { $0 / 2 }

    /// レンジリングの半径 (NM)
    @UserDefaultBacked(key: "rangeRingRadiusNm") var rangeRingRadiusNm: Double = 10.0

    /// Night テーマを使用するかどうか
    @UserDefaultBacked(key: "useNightTheme") var useNightTheme: Bool = false

    init() {
        $processNoise
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $measurementNoise
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $logInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $baroWeight
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $photoPreSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $photoPostSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordAcceleration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordAltimeterPressure
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordRawGpsRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordRelativeAltitude
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordBarometricAltitude
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordFusedAltitude
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordFusedRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordBaselineAltitude
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordMeasuredAltitude
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordKalmanInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $useKalmanFilter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $faStableDuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $faTrackCILimit
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $faSpeedCILimit
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $showEllipsoidalAltitude
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $recordEllipsoidalAltitude
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $enabledAirspaceCategories
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $enabledAirspaceGroups
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $hiddenFeatureIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $airspaceStrokeColors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $airspaceFillColors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $enableMachCalculation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $rangeRingRadiusNm
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $useNightTheme
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $orientationMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
