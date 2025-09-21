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
        let result = GeodesicCalculator.bearingDistance(from: from, to: to)
        var magnetic = result.bearing - declination
        if magnetic < 0 { magnetic += 360 }
        if magnetic >= 360 { magnetic -= 360 }
        return (magnetic, result.distance)
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
