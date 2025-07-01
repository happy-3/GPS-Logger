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

    /// 表示する施設カテゴリ
    @UserDefaultBacked(key: "enabledFacilityCategories") var enabledFacilityCategories: [String] = []

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
            case .northUp: return "North UP"
            case .trackUp: return "Track UP"
            case .magneticUp: return "Magnetic UP"
            case .manual: return "Free Rotate"
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
    @UserDefaultBacked(key: "declinationLocation") var declinationLocation: Data? = nil
    /// 磁気偏差計算日時
    @UserDefaultBacked(key: "declinationTimestamp") var declinationTimestamp: Date? = nil

    init() {
        subscribeChanges([
            $logInterval.asVoid(),
            $photoPreSeconds.asVoid(),
            $photoPostSeconds.asVoid(),
            $recordRawGpsRate.asVoid(),
            $faStableDuration.asVoid(),
            $faTrackCILimit.asVoid(),
            $faSpeedCILimit.asVoid(),
            $showEllipsoidalAltitude.asVoid(),
            $recordEllipsoidalAltitude.asVoid(),
            $enabledAirspaceCategories.asVoid(),
            $enabledAirspaceGroups.asVoid(),
            $enabledFacilityCategories.asVoid(),
            $hiddenFeatureIDs.asVoid(),
            $airspaceStrokeColors.asVoid(),
            $airspaceFillColors.asVoid(),
            $enableMachCalculation.asVoid(),
            $rangeRingRadiusNm.asVoid(),
            $useNightTheme.asVoid(),
            $lastDeclination.asVoid(),
            $orientationModeValue.asVoid()
        ])
    }

    private func subscribeChanges(_ publishers: [AnyPublisher<Void, Never>]) {
        publishers.forEach { publisher in
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }
}

private extension Published.Publisher {
    func asVoid() -> AnyPublisher<Void, Never> {
        map { _ in () }.eraseToAnyPublisher()
    }
}
