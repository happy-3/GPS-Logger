import Foundation
import Combine
import MapKit

/// 空域データを管理し Map 上へ表示するためのマネージャ
final class AirspaceManager: ObservableObject {
    /// カテゴリごとに読み込んだオーバーレイを保持
    @Published private(set) var overlaysByCategory: [String: [MKOverlay]] = [:]
    /// カテゴリ内で名前からグループ化したオーバーレイ一覧
    @Published private(set) var featureGroupsByCategory: [String: [String: [MKOverlay]]] = [:]
    /// MBTiles ベクターデータのソース
    private var vectorSources: [String: MBTilesVectorSource] = [:]
    private var currentMapRect: MKMapRect = .world

    /// HUD 用の簡易空域リスト
    @Published private(set) var slimList: [AirspaceSlim] = []

    /// 設定で有効化されているカテゴリ
    private var enabledCategories: [String] { settings.enabledAirspaceCategories }

    /// 表示対象のオーバーレイ
    @Published private(set) var displayOverlays: [MKOverlay] = []

    /// グループごとのカテゴリ一覧
    @Published private(set) var categoriesByGroup: [String: [String]] = [:]
    private var categoryToGroup: [String: String] = [:]

    /// 利用可能なカテゴリ一覧
    var categories: [String] {
        let keys = Set(overlaysByCategory.keys).union(vectorSources.keys)
        return Array(keys).sorted()
    }

    /// 利用可能なグループ一覧
    var groups: [String] { Array(categoriesByGroup.keys).sorted() }

    /// 指定グループに属するカテゴリ
    func categories(inGroup group: String) -> [String] {
        categoriesByGroup[group] ?? []
    }

    /// 指定カテゴリが属するグループ名を取得
    func group(for category: String) -> String {
        categoryToGroup[category] ?? category
    }

    /// 指定カテゴリの全フィーチャオーバーレイを取得
    func features(in category: String) -> [MKOverlay] {
        return overlaysByCategory[category] ?? []
    }

    /// 指定カテゴリで利用可能なフィーチャグループ名一覧
    func featureGroups(in category: String) -> [String] {
        guard let keys = featureGroupsByCategory[category]?.keys else {
            return []
        }
        return Array(keys).sorted()
    }

    /// 指定カテゴリとグループの全オーバーレイ
    func features(in category: String, group: String) -> [MKOverlay] {
        featureGroupsByCategory[category]?[group] ?? []
    }

    private let settings: Settings
    private var cancellables = Set<AnyCancellable>()

    init(settings: Settings) {
        self.settings = settings
        settings.$enabledAirspaceCategories
            .sink { [weak self] _ in self?.updateDisplayOverlays() }
            .store(in: &cancellables)
        settings.$hiddenFeatureIDs
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
                let bundleDir = Bundle.module.resourceURL
                print("[AirspaceManager] Searching bundle at", bundleDir?.path ?? "nil")
                let jsons = Bundle.module.urls(forResourcesWithExtension: "geojson", subdirectory: nil) ?? []
                let mbts = Bundle.module.urls(forResourcesWithExtension: "mbtiles", subdirectory: nil) ?? []
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
            var groupMap: [String: [String]] = [:]
            var catToGroup: [String: String] = [:]
            var featureGroups: [String: [String: [MKOverlay]]] = [:]
            for url in files {
                let base = url.deletingPathExtension().lastPathComponent
                print("[AirspaceManager] loading", url.lastPathComponent, "category =", base)
                switch url.pathExtension.lowercased() {
                case "geojson":
                    if base == "jp_asp" {
                        let result = self.loadAspOverlays(from: url)
                        for (cat, list) in result.map {
                            map[cat] = list
                        }
                        for (cat, groupsDict) in result.featureGroups {
                            featureGroups[cat] = groupsDict
                        }
                        for (grp, cats) in result.groups {
                            groupMap[grp, default: []].append(contentsOf: cats)
                            for c in cats { catToGroup[c] = grp }
                        }
                        print("[AirspaceManager] loaded jp_asp as", Array(result.map.keys))
                    } else {
                        let result = self.loadOverlays(from: url, category: base)
                        map[base] = result.overlays
                        featureGroups[base] = result.groups
                        let grp = Self.parseGroupName(base)
                        groupMap[grp, default: []].append(base)
                        catToGroup[base] = grp
                        print("[AirspaceManager] loaded", result.overlays.count, "overlays from", url.lastPathComponent)
                    }
                case "mbtiles":
                    if let src = MBTilesVectorSource(url: url) {
                        sources[base] = src
                        let grp = Self.parseGroupName(base)
                        groupMap[grp, default: []].append(base)
                        catToGroup[base] = grp
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
                self.categoriesByGroup = groupMap
                self.categoryToGroup = catToGroup
                self.featureGroupsByCategory = featureGroups
                if self.settings.enabledAirspaceCategories.isEmpty {
                    self.settings.enabledAirspaceCategories = self.categories
                }
                print("overlaysByCategory keys:", Array(self.overlaysByCategory.keys))
                print("enabled categories:", self.settings.enabledAirspaceCategories)
                self.updateDisplayOverlays()
                self.slimList = self.buildSlimList(from: map)
                print("[AirspaceManager] slimList count:", self.slimList.count)
            }
        }
    }

    /// 単一ファイルからオーバーレイを読み込む
    private func loadOverlays(from url: URL, category: String) -> (overlays: [MKOverlay], groups: [String: [MKOverlay]]) {
        guard let data = try? Data(contentsOf: url) else {
            print("[AirspaceManager] Could not read data from", url.path)
            return ([], [:])
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = obj["features"] as? [[String: Any]] else {
            print("[AirspaceManager] Invalid GeoJSON:", url.lastPathComponent)
            return ([], [:])
        }

        var loaded: [MKOverlay] = []
        var grouped: [String: [MKOverlay]] = [:]
        for (index, feature) in features.enumerated() {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String else { continue }

            let name: String? = {
                if let props = feature["properties"] as? [String: Any] {
                    return props["name"] as? String
                }
                return nil
            }()

            let props = feature["properties"] as? [String: Any] ?? [:]
            let fid = feature["id"] as? String ?? "\(index)"

            switch type {
            case "LineString":
                if let coords = geometry["coordinates"] as? [[Double]] {
                    let points = coords.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    let polyline = FeaturePolyline(coordinates: points, count: points.count)
                    polyline.title = name
                    polyline.subtitle = category
                    polyline.featureID = fid
                    polyline.properties = props
                    loaded.append(polyline)
                    let g = Self.parseFeatureGroupName(name)
                    grouped[g, default: []].append(polyline)
                }
            case "Polygon":
                if let rings = geometry["coordinates"] as? [[[Double]]], let first = rings.first {
                    let points = first.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    let polygon = FeaturePolygon(coordinates: points, count: points.count)
                    polygon.title = name
                    polygon.subtitle = category
                    polygon.featureID = fid
                    polygon.properties = props
                    loaded.append(polygon)
                    let g = Self.parseFeatureGroupName(name)
                    grouped[g, default: []].append(polygon)
                }
            case "Point":
                if let coord = geometry["coordinates"] as? [Double], coord.count == 2 {
                    let center = CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                    let circle = FeatureCircle(center: center, radius: 300)
                    circle.title = name
                    circle.subtitle = category
                    circle.featureID = fid
                    circle.properties = props
                    loaded.append(circle)
                    let g = Self.parseFeatureGroupName(name)
                    grouped[g, default: []].append(circle)
                }
            default:
                print("[AirspaceManager] Unsupported geometry type:", type)
                continue
            }
        }
        if loaded.isEmpty {
            print("[AirspaceManager] No overlays parsed from", url.lastPathComponent)
        }
        return (loaded, grouped)
    }

    /// jp_asp.geojson をカテゴリ分割して読み込む
    private func loadAspOverlays(from url: URL) -> (map: [String: [MKOverlay]], featureGroups: [String: [String: [MKOverlay]]], groups: [String: [String]]) {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = obj["features"] as? [[String: Any]] else {
            print("[AirspaceManager] Invalid jp_asp file")
            return ([:], [:], [:])
        }

        var map: [String: [MKOverlay]] = [:]
        var groupMap: [String: Set<String>] = [:]
        var featureGroups: [String: [String: [MKOverlay]]] = [:]

        for (index, feature) in features.enumerated() {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let gtype = geometry["type"] as? String,
                  let props = feature["properties"] as? [String: Any],
                  let name = props["name"] as? String else { continue }
            let fid = feature["id"] as? String ?? "\(index)"
            let typ = props["type"] as? Int ?? 0

            let sub = Self.aspSubCategory(name: name, type: typ)
            let major = Self.aspMajorCategory(sub: sub)
            let featureGroup = Self.parseFeatureGroupName(name)

            var overlay: MKOverlay?
            switch gtype {
            case "LineString":
                if let coords = geometry["coordinates"] as? [[Double]] {
                    let points = coords.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    let poly = FeaturePolyline(coordinates: points, count: points.count)
                    poly.title = name
                    poly.subtitle = sub
                    poly.featureID = fid
                    poly.properties = props
                    overlay = poly
                }
            case "Polygon":
                if let rings = geometry["coordinates"] as? [[[Double]]], let first = rings.first {
                    let points = first.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    let poly = FeaturePolygon(coordinates: points, count: points.count)
                    poly.title = name
                    poly.subtitle = sub
                    poly.featureID = fid
                    poly.properties = props
                    overlay = poly
                }
            case "Point":
                if let coord = geometry["coordinates"] as? [Double], coord.count == 2 {
                    let center = CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                    let circle = FeatureCircle(center: center, radius: 300)
                    circle.title = name
                    circle.subtitle = sub
                    circle.featureID = fid
                    circle.properties = props
                    overlay = circle
                }
            default:
                continue
            }

            if let ov = overlay {
                map[sub, default: []].append(ov)
                featureGroups[sub, default: [:]][featureGroup, default: []].append(ov)
                groupMap[major, default: []].insert(sub)
            }
        }

        let groups = groupMap.mapValues { Array($0) }
        return (map, featureGroups, groups)
    }

    // MARK: - jp_asp category helpers

    private static let aspSubPatterns: [(String, NSRegularExpression)] = [
        ("CTR", try! NSRegularExpression(pattern: "\\bCTR\\b", options: [.caseInsensitive])),
        ("INFO ZONE", try! NSRegularExpression(pattern: "\\bINFO\\s*ZONE\\b", options: [.caseInsensitive])),
        ("TCA", try! NSRegularExpression(pattern: "\\bTCA\\b", options: [.caseInsensitive])),
        ("ACA", try! NSRegularExpression(pattern: "\\bACA\\b", options: [.caseInsensitive])),
        ("PCA", try! NSRegularExpression(pattern: "\\bPCA\\b", options: [.caseInsensitive])),
        ("HELI", try! NSRegularExpression(pattern: "\\bHELI\\b", options: [.caseInsensitive])),
        ("AP", try! NSRegularExpression(pattern: "\\bAP\\b", options: [.caseInsensitive])),
        ("GP", try! NSRegularExpression(pattern: "\\bGP\\b", options: [.caseInsensitive])),
        ("SURFACE", try! NSRegularExpression(pattern: "\\b(APPROACH|HORIZONTAL|CONICAL)\\s+SURFACE\\b", options: [.caseInsensitive])),
        ("JSDF", try! NSRegularExpression(pattern: "\\b(JS?DF|JASDF)\\b", options: [.caseInsensitive])),
        ("TRAINING AREA", try! NSRegularExpression(pattern: "\\bTRAINING\\s+AREA\\b", options: [.caseInsensitive])),
        ("CAMP", try! NSRegularExpression(pattern: "\\bCAMP\\b", options: [.caseInsensitive]))
    ]

    private static let aspMajorMap: [String: String] = [
        "CTR": "Control & Information Zones",
        "INFO ZONE": "Control & Information Zones",
        "TCA": "Terminal Control Airspace",
        "ACA": "Terminal Control Airspace",
        "PCA": "Positive Control Areas",
        "HELI": "Aerodrome & Heliport Airspaces",
        "AP": "Aerodrome & Heliport Airspaces",
        "GP": "Aerodrome & Heliport Airspaces",
        "SURFACE": "Obstacle Limitation Surfaces",
        "JSDF": "Special Use & Military Airspace",
        "TRAINING AREA": "Special Use & Military Airspace",
        "CAMP": "Special Use & Military Airspace"
    ]

    private static func aspSubCategory(name: String, type: Int) -> String {
        if type == 2 { return "JSDF" }
        let up = name.uppercased()
        for (sub, reg) in aspSubPatterns {
            if reg.firstMatch(in: up, range: NSRange(up.startIndex..., in: up)) != nil {
                return sub
            }
        }
        return "OTHER"
    }

    private static func aspMajorCategory(sub: String) -> String {
        aspMajorMap[sub] ?? "Other"
    }

    /// 表示対象オーバーレイを計算
    private func updateDisplayOverlays() {
        var result: [MKOverlay] = []
        for cat in enabledCategories {
            let hidden = Set(settings.hiddenFeatureIDs[cat] ?? [])
            if let overlays = overlaysByCategory[cat] {
                for ov in overlays {
                    var fid: String? = nil
                    if let p = ov as? FeaturePolyline { fid = p.featureID }
                    if let p = ov as? FeaturePolygon { fid = p.featureID }
                    if let c = ov as? FeatureCircle { fid = c.featureID }
                    if let id = fid, hidden.contains(id) { continue }
                    result.append(ov)
                }
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

    /// カテゴリ名からグループ名を抽出
    private static func parseGroupName(_ category: String) -> String {
        if let idx = category.firstIndex(where: { $0 == " " || $0 == "-" || $0 == "_" }) {
            return String(category[..<idx])
        }
        return category
    }

    /// フィーチャ名からグループ名を抽出
    private static func parseFeatureGroupName(_ name: String?) -> String {
        guard var base = name else { return "" }
        if let range = base.range(of: "-[0-9]+[A-Z]*$", options: .regularExpression) {
            base.removeSubrange(range)
        } else if let range = base.range(of: "-[A-Z]{1,3}$", options: .regularExpression) {
            base.removeSubrange(range)
        }
        return base.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - HUD helper

    private func buildSlimList(from map: [String: [MKOverlay]]) -> [AirspaceSlim] {
        func altString(_ info: [String: Any]?) -> String {
            guard let info = info,
                  let value = info["value"] as? Int,
                  let unit = info["unit"] as? Int else { return "0ft" }
            if unit == 6 { return "FL\(value)" }
            return "\(value)ft"
        }

        var result: [AirspaceSlim] = []
        for (cat, overlays) in map {
            for ov in overlays {
                var props: [String: Any] = [:]
                var fid: String = UUID().uuidString
                var name: String = cat
                var sub: String = cat
                if let p = ov as? FeaturePolyline {
                    props = p.properties
                    fid = p.featureID
                    name = p.title ?? cat
                    sub = p.subtitle ?? cat
                } else if let p = ov as? FeaturePolygon {
                    props = p.properties
                    fid = p.featureID
                    name = p.title ?? cat
                    sub = p.subtitle ?? cat
                } else if let c = ov as? FeatureCircle {
                    props = c.properties
                    fid = c.featureID
                    name = c.title ?? cat
                    sub = c.subtitle ?? cat
                } else { continue }

                let upper = altString(props["upperLimit"] as? [String: Any])
                let lower = altString(props["lowerLimit"] as? [String: Any])

                let typ = props["type"] as? Int ?? 0
                let icon = (typ == 2 || typ == 4) ? "M" : "C"

                let rect = ov.boundingMapRect
                let sw = MKMapPoint(x: rect.minX, y: rect.minY).coordinate
                let ne = MKMapPoint(x: rect.maxX, y: rect.maxY).coordinate
                let bbox = [sw.longitude, sw.latitude, ne.longitude, ne.latitude]

                let asp = AirspaceSlim(id: fid, name: name, sub: sub, icon: icon,
                                      upper: upper, lower: lower, bbox: bbox, active: true)
                result.append(asp)
            }
        }
        return result
    }
}
