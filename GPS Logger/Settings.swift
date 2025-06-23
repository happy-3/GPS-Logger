import Foundation
import Combine

/// Stores adjustable parameters for altitude filtering.
@MainActor
final class Settings: ObservableObject {
    nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()
    private var cancellables = Set<AnyCancellable>()

    @UserDefaultBacked(key: "logInterval") var logInterval: Double = 1.0

    // Flight Assist stability thresholds
    @UserDefaultBacked(key: "faStableDuration") var faStableDuration: Double = 3.0
    @UserDefaultBacked(key: "faTrackCILimit") var faTrackCILimit: Double = 3.0
    @UserDefaultBacked(key: "faSpeedCILimit") var faSpeedCILimit: Double = 3.0

    // Photo capture options
    @UserDefaultBacked(key: "photoPreSeconds") var photoPreSeconds: Double = 3.0
    @UserDefaultBacked(key: "photoPostSeconds") var photoPostSeconds: Double = 3.0

    // Recording options
    @UserDefaultBacked(key: "recordRawGpsRate") var recordRawGpsRate: Bool = true

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

    @UserDefaultBacked(key: "orientationMode") var orientationModeValue: String = MapOrientationMode.trackUp.rawValue
    var orientationMode: MapOrientationMode {
        get { MapOrientationMode(rawValue: orientationModeValue) ?? .trackUp }
        set { orientationModeValue = newValue.rawValue }
    }

    /// ズーム可能な正方形サイズ (一辺) を NM で定義
    static let zoomDiametersNm: [Double] = [5, 10, 20, 40, 80, 160, 320]

    /// 既存コードとの互換用に半径値も保持
    static let rangeLevelsNm: [Double] = zoomDiametersNm.map { $0 / 2 }

    /// レンジリングの半径 (NM)
    @UserDefaultBacked(key: "rangeRingRadiusNm") var rangeRingRadiusNm: Double = 10.0

    /// Night テーマを使用するかどうか
    @UserDefaultBacked(key: "useNightTheme") var useNightTheme: Bool = false

    /// 前回計算した磁気偏差
    @UserDefaultBacked(key: "lastDeclination") var lastDeclination: Double = 0.0
    /// 磁気偏差計算地点
    @UserDefaultBacked(key: "declinationLocation") var declinationLocation: Data?
    /// 磁気偏差計算日時
    @UserDefaultBacked(key: "declinationTimestamp") var declinationTimestamp: Date?

    init() {
        $logInterval
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

        $recordRawGpsRate
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

        $lastDeclination
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $orientationModeValue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
