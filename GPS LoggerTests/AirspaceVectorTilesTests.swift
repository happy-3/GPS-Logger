import XCTest
@testable import GPS_Logger

final class AirspaceVectorTilesTests: XCTestCase {
    private func makeMBTiles() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vec.mbtiles")
        var db: OpaquePointer? = nil
        sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil)
        defer { if let db = db { sqlite3_close(db) } }
        sqlite3_exec(db, "CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);", nil, nil, nil)
        let json = "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[0,0],[0,0.1],[0.1,0],[0,0]]]}]}]" // purposely simple
        var stmt: OpaquePointer? = nil
        sqlite3_prepare_v2(db, "INSERT INTO tiles VALUES (0,0,0,?)", -1, &stmt, nil)
        sqlite3_bind_blob(stmt, 1, json, Int32(json.utf8.count), nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        return url
    }

    func testManagerLoadsVectorTiles() throws {
        let tileURL = try makeMBTiles()
        let settings = Settings()
        let manager = AirspaceManager(settings: settings)
        manager.loadAll(urls: [tileURL])

        let exp = expectation(description: "load")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            manager.updateMapRect(.world)
            if manager.displayOverlays.count == 1 {
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(manager.displayOverlays.count, 1)
    }
}
