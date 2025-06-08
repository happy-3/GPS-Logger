import XCTest
@testable import GPS_Logger

final class AirspaceManagerAsyncTests: XCTestCase {
    /// 大きめの GeoJSON ファイルを生成
    private func makeLargeGeoJSON() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("large.geojson")
        var features: [String] = []
        for i in 0..<200 {
            var points: [String] = []
            for j in 0..<50 {
                let lat = Double(i) * 0.001 + Double(j) * 0.0001
                let lon = Double(i) * 0.001 + Double(j) * 0.0001
                points.append("[\(lon),\(lat)]")
            }
            let line = "{\"type\":\"Feature\",\"geometry\":{\"type\":\"LineString\",\"coordinates\":[" + points.joined(separator: ",") + "]}}"
            features.append(line)
        }
        let json = "{\"type\":\"FeatureCollection\",\"features\":[" + features.joined(separator: ",") + "]}"
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testBackgroundLoadDoesNotBlockMain() throws {
        let fileURL = try makeLargeGeoJSON()
        let settings = Settings()
        let manager = AirspaceManager(settings: settings)

        // 呼び出しが即座に返ることを確認
        let start = CFAbsoluteTimeGetCurrent()
        manager.loadAll(urls: [fileURL])
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(elapsed, 0.1)

        // 読み込み完了を待つ
        let exp = expectation(description: "load")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if !manager.displayOverlays.isEmpty {
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5.0)
    }
}
