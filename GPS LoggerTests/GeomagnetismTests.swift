import XCTest
#if canImport(CoreLocation)
import CoreLocation
#endif
@testable import GPS_Logger

final class GeomagnetismTests: XCTestCase {
    func testDeclination() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2025, month: 6, day: 22))!
        let samples: [(CLLocationCoordinate2D, expected: Double)] = [
            (CLLocationCoordinate2D(latitude: 35.0, longitude: 135.0), -8.222613260768057),
            (CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0), -3.838927190050675),
            (CLLocationCoordinate2D(latitude: -35.0, longitude: -135.0), 19.676383990221552)
        ]
        for (coord, expected) in samples {
            let geo = Geomagnetism(longitude: coord.longitude,
                                   latitude: coord.latitude,
                                   altitude: 0,
                                   date: date)
            XCTAssertEqual(geo.declination, expected, accuracy: 0.1)
        }
    }
}
