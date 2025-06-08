import Foundation
import Combine
import MapKit

/// 空域データを管理し Map 上へ表示するためのマネージャ
final class AirspaceManager: ObservableObject {
    /// カテゴリごとに読み込んだオーバーレイを保持
    @Published private(set) var overlaysByCategory: [String: [MKOverlay]] = [:]
    /// 設定で有効化されているカテゴリ
    private var enabledCategories: [String] { settings.enabledAirspaceCategories }

    /// 表示対象のオーバーレイ
    @Published private(set) var displayOverlays: [MKOverlay] = []

    /// 利用可能なカテゴリ一覧
    var categories: [String] { overlaysByCategory.keys.sorted() }

    private let settings: Settings
    private var cancellables = Set<AnyCancellable>()

    init(settings: Settings) {
        self.settings = settings
        settings.$enabledAirspaceCategories
            .sink { [weak self] _ in self?.updateDisplayOverlays() }
            .store(in: &cancellables)
    }

    /// バンドル内の Airspace フォルダからすべての GeoJSON を読み込む
    func loadAll() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "geojson", subdirectory: "Airspace") else {
            return
        }

        var map: [String: [MKOverlay]] = [:]
        for url in urls {
            let category = url.deletingPathExtension().lastPathComponent
            map[category] = loadOverlays(from: url)
        }
        DispatchQueue.main.async { [self] in
            overlaysByCategory = map
            if settings.enabledAirspaceCategories.isEmpty {
                settings.enabledAirspaceCategories = categories
            }
            updateDisplayOverlays()
        }
    }

    /// 単一ファイルからオーバーレイを読み込む
    private func loadOverlays(from url: URL) -> [MKOverlay] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = obj["features"] as? [[String: Any]] else { return [] }

        var loaded: [MKOverlay] = []
        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String else { continue }

            switch type {
            case "LineString":
                if let coords = geometry["coordinates"] as? [[Double]] {
                    let points = coords.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    let polyline = MKPolyline(coordinates: points, count: points.count)
                    loaded.append(polyline)
                }
            case "Polygon":
                if let rings = geometry["coordinates"] as? [[[Double]]], let first = rings.first {
                    let points = first.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    let polygon = MKPolygon(coordinates: points, count: points.count)
                    loaded.append(polygon)
                }
            default:
                continue
            }
        }
        return loaded
    }

    /// 表示対象オーバーレイを計算
    private func updateDisplayOverlays() {
        displayOverlays = enabledCategories.flatMap { overlaysByCategory[$0] ?? [] }
    }
}
