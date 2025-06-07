import Testing
@testable import GPS_Logger
import CoreLocation

struct TASCalculationTests {
    @Test
    func testComputeTASTailwind() {
        var view = ContentView()
        view.windDirection = 0 // 北からの追い風
        view.windSpeed = 20
        let speedMps = 100 / 1.94384
        let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                             altitude: 0,
                             horizontalAccuracy: 5,
                             verticalAccuracy: 5,
                             course: 180,
                             speed: speedMps,
                             timestamp: Date())
        let tas = view.computeTAS(from: loc)
        #expect(abs((tas ?? 0) - 80) < 0.5)
    }

    @Test
    func testComputeTASHeadwind() {
        var view = ContentView()
        view.windDirection = 180 // 南からの向かい風
        view.windSpeed = 20
        let speedMps = 100 / 1.94384
        let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                             altitude: 0,
                             horizontalAccuracy: 5,
                             verticalAccuracy: 5,
                             course: 0,
                             speed: speedMps,
                             timestamp: Date())
        let tas = view.computeTAS(from: loc)
        #expect(abs((tas ?? 0) - 120) < 0.5)
    }
}

