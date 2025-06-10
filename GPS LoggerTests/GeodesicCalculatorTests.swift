import XCTest
import CoreLocation
@testable import GPS_Logger

final class GeodesicCalculatorTests: XCTestCase {
    func testBearingDistance() {
        let from = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let to = CLLocationCoordinate2D(latitude: 1, longitude: 1)
        let result = GeodesicCalculator.bearingDistance(from: from, to: to)
        XCTAssertEqual(result.bearing, 44.996, accuracy: 0.01)
        XCTAssertEqual(result.distance, 84.908, accuracy: 0.01)
    }

    func testDestinationPoint() {
        let start = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let dest = GeodesicCalculator.destinationPoint(from: start, courseDeg: 90, distanceNm: 60)
        XCTAssertEqual(dest.latitude, 0, accuracy: 0.0001)
        XCTAssertEqual(dest.longitude, 1.0, accuracy: 0.01)
    }

    func testETAComputation() {
        let from = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let to = CLLocationCoordinate2D(latitude: 0, longitude: 0.5)
        let bd = GeodesicCalculator.bearingDistance(from: from, to: to)
        XCTAssertEqual(bd.bearing, 90, accuracy: 0.01)
        XCTAssertEqual(bd.distance, 30.02, accuracy: 0.01)
        let speed = 120.0
        let ete = bd.distance / speed * 3600
        XCTAssertEqual(ete, 900.6, accuracy: 0.5)
        let now = Date()
        let eta = now.addingTimeInterval(ete)
        XCTAssertEqual(eta.timeIntervalSince(now), ete, accuracy: 0.5)
    }

    func testTenMinutePoint() {
        let state = AircraftState(position: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                  groundTrack: 90,
                                  groundSpeedKt: 120,
                                  altitudeFt: 0,
                                  timestamp: Date())
        let point = GeodesicCalculator.tenMinPoint(state: state)
        XCTAssertEqual(point.latitude, 0, accuracy: 0.0001)
        XCTAssertEqual(point.longitude, 0.333, accuracy: 0.001)
    }
}
