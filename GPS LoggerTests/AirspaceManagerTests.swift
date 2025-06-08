import XCTest
@testable import GPS_Logger

final class AirspaceManagerTests: XCTestCase {
    /// テスト用 GeoJSON ファイル URL を取得
    private func testFileURLs() throws -> [URL] {
        guard let a = Bundle.module.url(forResource: "catA", withExtension: "geojson"),
              let b = Bundle.module.url(forResource: "catB", withExtension: "geojson") else {
            throw XCTSkip("Test files not found")
        }
        return [a, b]
    }

    func testLoadAndFilter() throws {
        let urls = try testFileURLs()
        let settings = Settings()
        let manager = AirspaceManager(settings: settings)

        let exp = expectation(description: "load")
        manager.loadAll(urls: urls)
        // 読み込みが完了し displayOverlays が更新されるまで待つ
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if manager.displayOverlays.count == 2 {
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(manager.displayOverlays.count, 2)
        XCTAssertEqual(Set(settings.enabledAirspaceCategories), Set(["catA", "catB"]))

        // カテゴリを片方だけ有効に
        settings.enabledAirspaceCategories = ["catA"]
        XCTAssertEqual(manager.displayOverlays.count, 1)

        settings.enabledAirspaceCategories = ["catB"]
        XCTAssertEqual(manager.displayOverlays.count, 1)
    }

    func testPointFeatures() throws {
        guard let url = Bundle.module.url(forResource: "catC", withExtension: "geojson") else {
            throw XCTSkip("Test file not found")
        }
        let settings = Settings()
        let manager = AirspaceManager(settings: settings)

        let exp = expectation(description: "load")
        manager.loadAll(urls: [url])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if manager.displayOverlays.count == 1 {
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(manager.displayOverlays.count, 1)
        XCTAssertTrue(manager.displayOverlays.first is MKCircle)
    }
}
