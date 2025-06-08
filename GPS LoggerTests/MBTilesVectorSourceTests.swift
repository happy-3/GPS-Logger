import XCTest
@testable import GPS_Logger
import SQLite3

final class MBTilesVectorSourceTests: XCTestCase {
    /// 簡易的な MBTiles ファイルを生成
    private func makeMBTiles() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.mbtiles")
        var db: OpaquePointer? = nil
        sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil)
        defer { if let db = db { sqlite3_close(db) } }
        sqlite3_exec(db, "CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);", nil, nil, nil)
        let json = "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[0,0],[0.1,0.1]]}}]}"
        var stmt: OpaquePointer? = nil
        sqlite3_prepare_v2(db, "INSERT INTO tiles VALUES (0,0,0,?)", -1, &stmt, nil)
        sqlite3_bind_blob(stmt, 1, json, Int32(json.utf8.count), nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        return url
    }

    /// 2 タイル分のデータを持つ MBTiles ファイルを生成
    private func makeMultiTiles() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_multi.mbtiles")
        var db: OpaquePointer? = nil
        sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil)
        defer { if let db = db { sqlite3_close(db) } }
        sqlite3_exec(db, "CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);", nil, nil, nil)
        let json = "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[0,0],[0.1,0.1]]}}]}"
        var stmt: OpaquePointer? = nil
        // タイル (0,0)
        sqlite3_prepare_v2(db, "INSERT INTO tiles VALUES (1,0,1,?)", -1, &stmt, nil)
        sqlite3_bind_blob(stmt, 1, json, Int32(json.utf8.count), nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        // タイル (1,0)
        sqlite3_prepare_v2(db, "INSERT INTO tiles VALUES (1,1,1,?)", -1, &stmt, nil)
        sqlite3_bind_blob(stmt, 1, json, Int32(json.utf8.count), nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        return url
    }

    func testLoadTile() throws {
        let url = try makeMBTiles()
        guard let src = MBTilesVectorSource(url: url) else {
            XCTFail("failed to open mbtiles")
            return
        }
        let overlays = src.overlays(in: MKMapRect.world)
        XCTAssertEqual(overlays.count, 1)
    }

    func testCacheLimit() throws {
        let url = try makeMultiTiles()
        guard let src = MBTilesVectorSource(url: url, zoomLevel: 1, cacheLimit: 1) else {
            XCTFail("failed to open mbtiles")
            return
        }
        let half = MKMapRect(x: 0, y: 0, width: MKMapRect.world.width / 2, height: MKMapRect.world.height / 2)
        _ = src.overlays(in: half)
        XCTAssertEqual(src.cacheCount, 1)
        let half2 = MKMapRect(x: MKMapRect.world.midX, y: 0, width: MKMapRect.world.width / 2, height: MKMapRect.world.height / 2)
        _ = src.overlays(in: half2)
        XCTAssertEqual(src.cacheCount, 1)
    }
}
