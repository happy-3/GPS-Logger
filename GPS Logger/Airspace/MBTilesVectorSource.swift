import Foundation
import MapKit
import SQLite3

/// MBTiles 形式で保存されたベクターデータを読み込み、表示領域に応じてオーバーレイを生成するクラス
final class MBTilesVectorSource {
    private let db: OpaquePointer?
    private let zoomLevel: Int
    private struct TileIndex: Hashable { let x: Int; let y: Int; let z: Int }
    private var cache: [TileIndex: [MKOverlay]] = [:]

    init?(url: URL, zoomLevel: Int = 8) {
        var handle: OpaquePointer? = nil
        if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            return nil
        }
        self.db = handle
        self.zoomLevel = zoomLevel
    }

    deinit {
        if let handle = db {
            sqlite3_close(handle)
        }
    }

    /// 指定した MapRect 内に含まれるタイルのオーバーレイを返す
    func overlays(in mapRect: MKMapRect) -> [MKOverlay] {
        let nw = MKMapPoint(x: mapRect.minX, y: mapRect.minY).coordinate
        let se = MKMapPoint(x: mapRect.maxX, y: mapRect.maxY).coordinate
        let (minX, minY) = tileXY(for: nw)
        let (maxX, maxY) = tileXY(for: se)
        var result: [MKOverlay] = []
        for x in minX...maxX {
            for y in minY...maxY {
                let idx = TileIndex(x: x, y: y, z: zoomLevel)
                if let cached = cache[idx] {
                    result.append(contentsOf: cached)
                } else if let overlays = loadTile(x: x, y: y, z: zoomLevel) {
                    cache[idx] = overlays
                    result.append(contentsOf: overlays)
                }
            }
        }
        return result
    }

    private func tileXY(for coord: CLLocationCoordinate2D) -> (Int, Int) {
        let n = pow(2.0, Double(zoomLevel))
        let x = Int((coord.longitude + 180.0) / 360.0 * n)
        let latRad = coord.latitude * Double.pi / 180.0
        let y = Int((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / Double.pi) / 2.0 * n)
        return (max(0, min(Int(n) - 1, x)), max(0, min(Int(n) - 1, y)))
    }

    private func loadTile(x: Int, y: Int, z: Int) -> [MKOverlay]? {
        guard let handle = db else { return nil }
        let row = Int(pow(2.0, Double(z))) - 1 - y
        let query = "SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?"
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(handle, query, -1, &stmt, nil) != SQLITE_OK { return nil }
        sqlite3_bind_int(stmt, 1, Int32(z))
        sqlite3_bind_int(stmt, 2, Int32(x))
        sqlite3_bind_int(stmt, 3, Int32(row))
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if let bytes = sqlite3_column_blob(stmt, 0) {
            let size = sqlite3_column_bytes(stmt, 0)
            let data = Data(bytes: bytes, count: Int(size))
            return parseTileData(data)
        }
        return nil
    }

    /// tile_data は GeoJSON の FeatureCollection を想定
    private func parseTileData(_ data: Data) -> [MKOverlay]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = obj["features"] as? [[String: Any]] else { return nil }
        var overlays: [MKOverlay] = []
        for feat in features {
            guard let geom = feat["geometry"] as? [String: Any],
                  let type = geom["type"] as? String else { continue }
            switch type {
            case "LineString":
                if let coords = geom["coordinates"] as? [[Double]] {
                    let points = coords.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    overlays.append(MKPolyline(coordinates: points, count: points.count))
                }
            case "Polygon":
                if let rings = geom["coordinates"] as? [[[Double]]], let first = rings.first {
                    let points = first.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    overlays.append(MKPolygon(coordinates: points, count: points.count))
                }
            default:
                continue
            }
        }
        return overlays
    }
}
