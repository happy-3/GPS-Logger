import Foundation
import Combine
import MapKit

/// 空域データを管理し Map 上へ表示するためのマネージャ
final class AirspaceManager: ObservableObject {
    /// カテゴリごとに読み込んだオーバーレイを保持
    @Published private(set) var overlaysByCategory: [String: [MKOverlay]] = [:]
    /// MBTiles ベクターデータのソース
    private var vectorSources: [String: MBTilesVectorSource] = [:]
    private var currentMapRect: MKMapRect = .world

    /// 設定で有効化されているカテゴリ
    private var enabledCategories: [String] { settings.enabledAirspaceCategories }

    /// 表示対象のオーバーレイ
    @Published private(set) var displayOverlays: [MKOverlay] = []

    /// 利用可能なカテゴリ一覧
    var categories: [String] {
        let keys = Set(overlaysByCategory.keys).union(vectorSources.keys)
        return Array(keys).sorted()
    }

    private let settings: Settings
    private var cancellables = Set<AnyCancellable>()

    init(settings: Settings) {
        self.settings = settings
        settings.$enabledAirspaceCategories
            .sink { [weak self] _ in self?.updateDisplayOverlays() }
            .store(in: &cancellables)
    }

    /// バンドル内の Airspace フォルダからすべての GeoJSON を読み込む
    /// - Parameter urls: テスト用に指定するファイル URL 配列。省略時はバンドル内を検索する。
    func loadAll(urls: [URL]? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let files: [URL]
            if let urls = urls {
                files = urls
            } else {
                let jsons = Bundle.module.urls(forResourcesWithExtension: "geojson", subdirectory: "Airspace") ?? []
                let mbts = Bundle.module.urls(forResourcesWithExtension: "mbtiles", subdirectory: "Airspace") ?? []
                files = jsons + mbts
            }

            var map: [String: [MKOverlay]] = [:]
            var sources: [String: MBTilesVectorSource] = [:]
            for url in files {
                let category = url.deletingPathExtension().lastPathComponent
                switch url.pathExtension.lowercased() {
                case "geojson":
                    map[category] = self.loadOverlays(from: url)
                case "mbtiles":
                    if let src = MBTilesVectorSource(url: url) { sources[category] = src }
                default:
                    continue
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.overlaysByCategory = map
                self.vectorSources = sources
                if self.settings.enabledAirspaceCategories.isEmpty {
                    self.settings.enabledAirspaceCategories = self.categories
                }
                self.updateDisplayOverlays()
            }
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

            let name: String? = {
                if let props = feature["properties"] as? [String: Any] {
                    return props["name"] as? String
                }
                return nil
            }()

            switch type {
            case "LineString":
                if let coords = geometry["coordinates"] as? [[Double]] {
                    let points = coords.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    let polyline = MKPolyline(coordinates: points, count: points.count)
                    polyline.title = name
                    loaded.append(polyline)
                }
            case "Polygon":
                if let rings = geometry["coordinates"] as? [[[Double]]], let first = rings.first {
                    let points = first.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    let polygon = MKPolygon(coordinates: points, count: points.count)
                    polygon.title = name
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
        var result: [MKOverlay] = []
        for cat in enabledCategories {
            if let overlays = overlaysByCategory[cat] {
                result.append(contentsOf: overlays)
            }
            if let src = vectorSources[cat] {
                result.append(contentsOf: src.overlays(in: currentMapRect))
            }
        }
        DispatchQueue.main.async {
            self.displayOverlays = result
        }
    }

    /// MapView から現在の表示範囲を受け取る
    func updateMapRect(_ rect: MKMapRect) {
        currentMapRect = rect
        updateDisplayOverlays()
    }
}
