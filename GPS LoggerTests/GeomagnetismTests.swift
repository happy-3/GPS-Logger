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
            #if canImport(CoreLocation)
            if #available(iOS 16.0, macOS 13.0, *),
               let model = CLGeomagneticModel(date: date) {
                let result = model.declination(atLatitude: coord.latitude,
                                               longitude: coord.longitude,
                                               altitude: 0)
                XCTAssertEqual(geo.declination, result, accuracy: 0.1)
                continue
            }
            #endif
            XCTAssertEqual(geo.declination, expected, accuracy: 0.1)
        }
    }
}
