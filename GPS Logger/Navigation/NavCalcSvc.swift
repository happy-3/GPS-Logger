import Foundation
import CoreLocation
import SQLite3

/// Navaid データベースから地点を検索し、方位・距離計算を行うサービス
final class NavCalcSvc {
    private let db: OpaquePointer?

    init?(dbURL: URL) {
        var handle: OpaquePointer? = nil
        if sqlite3_open_v2(dbURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            return nil
        }
        db = handle
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    /// 指定した識別子の Navaid 座標を取得
    func coordinate(for ident: String) -> CLLocationCoordinate2D? {
        guard let db else { return nil }
        let query = "SELECT lat, lon FROM navaids WHERE ident=? LIMIT 1"
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, ident, -1, nil)
        var coord: CLLocationCoordinate2D?
        if sqlite3_step(stmt) == SQLITE_ROW {
            let lat = sqlite3_column_double(stmt, 0)
            let lon = sqlite3_column_double(stmt, 1)
            coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        sqlite3_finalize(stmt)
        return coord
    }

    /// 2 点間の距離(NM)と方位(磁方位)を計算
    /// - Parameters:
    ///   - from: 出発点座標
    ///   - to: 目的点座標
    ///   - declination: 磁気偏差 (度)。東偏は正、 西偏は負とする。
    func bearingDistance(from: CLLocationCoordinate2D,
                         to: CLLocationCoordinate2D,
                         declination: Double = 0.0) -> (bearing: Double, distance: Double) {
        let lat1 = from.latitude * Double.pi / 180
        let lon1 = from.longitude * Double.pi / 180
        let lat2 = to.latitude * Double.pi / 180
        let lon2 = to.longitude * Double.pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var bearing = atan2(y, x) * 180 / Double.pi
        if bearing < 0 { bearing += 360 }
        // 真方位から磁気偏差を引いて磁方位を得る
        bearing -= declination
        if bearing < 0 { bearing += 360 }
        if bearing >= 360 { bearing -= 360 }
        let r = 6371.0 // km
        let d = acos(sin(lat1) * sin(lat2) + cos(lat1) * cos(lat2) * cos(dLon)) * r
        let nm = d / 1.852
        return (bearing, nm)
    }

    /// 現在地と指定 Navaid との方位・距離を返す
    /// - Parameters:
    ///   - current: 現在地
    ///   - ident: 対象 Navaid の識別子
    ///   - declination: 磁気偏差 (度)
    func info(from current: CLLocationCoordinate2D,
              toIdent ident: String,
              declination: Double = 0.0) -> (bearing: Double, distance: Double)? {
        guard let dest = coordinate(for: ident) else { return nil }
        return bearingDistance(from: current, to: dest, declination: declination)
    }
}
