import Foundation
import CoreLocation
import SwiftUI
import Combine
import MapKit
import os

/// HUD 更新ロジックを担当する ViewModel
final class HUDViewModel: ObservableObject, AirspaceSlimBuilder {
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
    private var tree = RTree<AirspaceSlim>()
    private var cancellables = Set<AnyCancellable>()

    init(airspaceManager: AirspaceManager) {
        self.airspaces = airspaceManager.slimList
        rebuildTree()
        airspaceManager.$slimList
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                guard let self else { return }
                self.airspaces = list
                self.rebuildTree()
                Logger.airspace.debug("HUDViewModel loaded airspaces: \(list.count)")
            }
            .store(in: &cancellables)
    }

    /// 新しい位置情報を受け取って HUD 更新判定を行う
    func onNewGPSSample(_ loc: CLLocation) {
        let pos = loc.coordinate
        let alt = loc.altitude
        let now = Date()
        Logger.airspace.debug("HUD GPS sample lat=\(String(format: "%.4f", pos.latitude)) lon=\(String(format: "%.4f", pos.longitude)) alt=\(String(format: "%.1f", alt))")
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
        Logger.airspace.debug("HUD active IDs: \(newIDs)")
        if newIDs != hudIDs {
            hudStripUpdate(ids: newIDs)
            hudIDs = newIDs
            DispatchQueue.main.async {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
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
            String(format: "%@ %@-%@ %-4@ %@", asp.name, asp.upper, asp.lower, asp.sub, asp.icon)
        }
        self.hudRows = Array(rows)
    }

    /// 現在位置から有効空域 ID 一覧を返す
    private func queryActive(pos: CLLocationCoordinate2D, alt: Double, now: Date) -> [String] {
        let candidates = tree.search(point: pos)
        var list: [AirspaceSlim] = []
        for asp in candidates {
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
        Logger.airspace.debug("HUD map tap lat=\(String(format: "%.4f", coord.latitude)) lon=\(String(format: "%.4f", coord.longitude))")
        guard zoneQueryOn else { return }
        let hit = tree.search(point: coord)
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
        Logger.airspace.debug("HUD tap hits: \(hit.count)")
        if showStack {
            DispatchQueue.main.async {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    /// 現在位置に基づく空域一覧を表示
    func showActiveZones() {
        let asps = airspaces.filter { hudIDs.contains($0.id) }
        self.stackList = Array(asps.prefix(4))
        self.showStack = !stackList.isEmpty
        if showStack {
            DispatchQueue.main.async {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func rebuildTree() {
        tree = RTree<AirspaceSlim>()
        for asp in airspaces {
            guard asp.bbox.count == 4 else { continue }
            let rect = RTreeRect(minX: asp.bbox[0], minY: asp.bbox[1], maxX: asp.bbox[2], maxY: asp.bbox[3])
            tree.insert(rect: rect, value: asp)
        }
    }

}
