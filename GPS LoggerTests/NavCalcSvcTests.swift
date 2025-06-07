import Testing
@testable import GPS_Logger
import SQLite3

struct NavCalcSvcTests {
    @Test
    func testBearingDistance() {
        // 一時 SQLite データベースを生成
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nav.db")
        var db: OpaquePointer? = nil
        sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil)
        sqlite3_exec(db, "CREATE TABLE navaids (ident TEXT, lat REAL, lon REAL);", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO navaids VALUES ('AAA', 35.0, 135.0);", nil, nil, nil)
        sqlite3_close(db)

        guard let svc = NavCalcSvc(dbURL: tmp) else {
            #expect(false, "svc init failed")
            return
        }
        let from = CLLocationCoordinate2D(latitude: 34.0, longitude: 134.0)
        if let info = svc.info(from: from, toIdent: "AAA", declination: -7.0) {
            #expect(info.distance > 70 && info.distance < 90)
            #expect(info.bearing > 44 && info.bearing < 48)
        } else {
            #expect(false, "info nil")
        }
    }
}
