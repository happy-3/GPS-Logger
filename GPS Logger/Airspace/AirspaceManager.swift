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
        print("AirspaceManager.loadAll called")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var files: [URL]
            if let urls = urls {
                files = urls
            } else {
                let bundleDir = Bundle.module.resourceURL?.appendingPathComponent("Airspace")
                print("[AirspaceManager] Searching bundle at", bundleDir?.path ?? "nil")
                let jsons = Bundle.module.urls(forResourcesWithExtension: "geojson", subdirectory: "Airspace") ?? []
                let mbts = Bundle.module.urls(forResourcesWithExtension: "mbtiles", subdirectory: "Airspace") ?? []
                files = jsons + mbts

                if files.isEmpty {
                    print("[AirspaceManager] No airspace data found in bundle")
                    if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        let dir = docs.appendingPathComponent("Airspace")
                        print("[AirspaceManager] Searching documents at", dir.path)
                        if let all = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                            files = all.filter { ["geojson", "mbtiles"].contains($0.pathExtension.lowercased()) }
                        }
                    }
                }
            }

            var map: [String: [MKOverlay]] = [:]
            var sources: [String: MBTilesVectorSource] = [:]
            for url in files {
                let category = url.deletingPathExtension().lastPathComponent
                print("[AirspaceManager] loading", url.lastPathComponent, "category =", category)
                switch url.pathExtension.lowercased() {
                case "geojson":
                    let overlays = self.loadOverlays(from: url)
                    print("[AirspaceManager] loaded", overlays.count, "overlays from", url.lastPathComponent)
                    map[category] = overlays
                case "mbtiles":
                    if let src = MBTilesVectorSource(url: url) {
                        sources[category] = src
                    } else {
                        print("[AirspaceManager] failed to open MBTiles:", url.path)
                    }
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
                print("overlaysByCategory keys:", Array(self.overlaysByCategory.keys))
                print("enabled categories:", self.settings.enabledAirspaceCategories)
                self.updateDisplayOverlays()
            }
        }
    }

    /// 単一ファイルからオーバーレイを読み込む
    private func loadOverlays(from url: URL) -> [MKOverlay] {
        guard let data = try? Data(contentsOf: url) else {
            print("[AirspaceManager] Could not read data from", url.path)
            return []
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = obj["features"] as? [[String: Any]] else {
            print("[AirspaceManager] Invalid GeoJSON:", url.lastPathComponent)
            return []
        }

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
            case "Point":
                if let coord = geometry["coordinates"] as? [Double], coord.count == 2 {
                    let center = CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                    let circle = MKCircle(center: center, radius: 300)
                    circle.title = name
                    loaded.append(circle)
                }
            default:
                print("[AirspaceManager] Unsupported geometry type:", type)
                continue
            }
        }
        if loaded.isEmpty {
            print("[AirspaceManager] No overlays parsed from", url.lastPathComponent)
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
