import Foundation
import CoreLocation
import SwiftUI
import Combine
import MapKit

/// HUD 更新ロジックを担当する ViewModel
final class HUDViewModel: ObservableObject {
    @Published var hudRows: [String] = []
    @Published var stackList: [AirspaceSlim] = []
    @Published var showStack: Bool = false
    @Published var zoneQueryOn: Bool = false
    private var lastPos: CLLocationCoordinate2D?
    private var lastAlt: Double?
    private var lastTS: Date?
    private var hudIDs: [String] = []
    private let thresholdDist: Double = 500.0  // m
    private let thresholdAlt: Double = 100.0   // m
    private let thresholdTime: TimeInterval = 60.0
    private var airspaces: [AirspaceSlim] = []
    private var cancellables = Set<AnyCancellable>()

    init(airspaceManager: AirspaceManager) {
        self.airspaces = Self.buildSlimList(from: airspaceManager.overlaysByCategory)
        airspaceManager.$overlaysByCategory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] map in
                self?.airspaces = Self.buildSlimList(from: map)
            }
            .store(in: &cancellables)
    }

    /// 新しい位置情報を受け取って HUD 更新判定を行う
    func onNewGPSSample(_ loc: CLLocation) {
        let pos = loc.coordinate
        let alt = loc.altitude
        let now = Date()
        if let lp = lastPos, let la = lastAlt, let lt = lastTS {
            let dist = CLLocation(latitude: lp.latitude, longitude: lp.longitude)
                .distance(from: CLLocation(latitude: pos.latitude, longitude: pos.longitude))
            let altDiff = abs(alt - la)
            let dt = now.timeIntervalSince(lt)
            if dist <= thresholdDist && altDiff <= thresholdAlt && dt <= thresholdTime {
                return
            }
        }
        let newIDs = queryActive(pos: pos, alt: alt, now: now)
        if newIDs != hudIDs {
            hudStripUpdate(ids: newIDs)
            hudIDs = newIDs
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        lastPos = pos
        lastAlt = alt
        lastTS = now
    }

    private func hudStripUpdate(ids: [String]) {
        let asps = airspaces.filter { ids.contains($0.id) }
        let rows = asps.sorted { a, b in
            if alt_m(a.upper) != alt_m(b.upper) {
                return alt_m(a.upper) > alt_m(b.upper)
            }
            if milRank(a) != milRank(b) {
                return milRank(a) < milRank(b)
            }
            return a.name < b.name
        }.prefix(3).map { asp in
            String(format: "%@-%@ %-4@ %@", asp.upper, asp.lower, asp.sub, asp.icon)
        }
        self.hudRows = Array(rows)
    }

    /// 現在位置から有効空域 ID 一覧を返す
    private func queryActive(pos: CLLocationCoordinate2D, alt: Double, now: Date) -> [String] {
        var list: [AirspaceSlim] = []
        for asp in airspaces {
            guard contains(pos, bbox: asp.bbox) else { continue }
            guard is_active(asp, now: now) else { continue }
            let upper = alt_m(asp.upper)
            let lower = alt_m(asp.lower)
            if Int(alt) <= upper && Int(alt) >= lower {
                list.append(asp)
            }
        }
        list.sort { a, b in
            if alt_m(a.upper) != alt_m(b.upper) {
                return alt_m(a.upper) > alt_m(b.upper)
            }
            if milRank(a) != milRank(b) {
                return milRank(a) < milRank(b)
            }
            return a.name < b.name
        }
        return list.map { $0.id }
    }

    /// Map 画面でタップされた位置を処理
    func onMapTap(_ coord: CLLocationCoordinate2D) {
        guard zoneQueryOn else { return }
        var hit: [AirspaceSlim] = []
        for asp in airspaces {
            if contains(coord, bbox: asp.bbox) {
                hit.append(asp)
            }
        }
        hit.sort { a, b in
            if alt_m(a.upper) != alt_m(b.upper) {
                return alt_m(a.upper) > alt_m(b.upper)
            }
            if milRank(a) != milRank(b) {
                return milRank(a) < milRank(b)
            }
            return a.name < b.name
        }
        self.stackList = Array(hit.prefix(4))
        self.showStack = !stackList.isEmpty
        if showStack {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// AirspaceManager のオーバーレイ情報から簡易リストを生成
    private static func buildSlimList(from map: [String: [MKOverlay]]) -> [AirspaceSlim] {
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
