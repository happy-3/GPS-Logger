import XCTest
import MapKit
import SwiftUI
@testable import GPS_Logger

final class MainMapViewInteractionTests: XCTestCase {
    // MKMapView で座標変換結果を固定するためのモック
    final class MockMapView: MKMapView {
        var forcedCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        override func convert(_ point: CGPoint, toCoordinateFrom view: UIView?) -> CLLocationCoordinate2D {
            forcedCoordinate
        }
    }

    // タップ位置を固定するモック
    final class MockTapGesture: UITapGestureRecognizer {
        var point = CGPoint.zero
        override func location(in view: UIView?) -> CGPoint { point }
    }

    /// テスト用 Coordinator を生成
    private func makeCoordinator(waypoint: Binding<Waypoint?>, navInfo: Binding<NavComputed?>) -> (MapViewRepresentable.Coordinator, LocationManager, MockMapView) {
        let settings = Settings()
        let flm = FlightLogManager(settings: settings)
        let loc = LocationManager(flightLogManager: flm, settings: settings)
        let air = AirspaceManager(settings: settings)
        let hud = HUDViewModel(airspaceManager: air)
        let repr = MapViewRepresentable(locationManager: loc, airspaceManager: air, settings: settings, hudViewModel: hud, waypoint: waypoint, navInfo: navInfo)
        let coord = repr.makeCoordinator()
        let map = MockMapView()
        coord.mapView = map
        return (coord, loc, map)
    }

    func testHandleTapCreatesWaypoint() {
        var wp: Waypoint?
        var nav: NavComputed?
        let bindingWp = Binding<Waypoint?>(get: { wp }, set: { wp = $0 })
        let bindingNav = Binding<NavComputed?>(get: { nav }, set: { nav = $0 })
        let (coord, _, map) = makeCoordinator(waypoint: bindingWp, navInfo: bindingNav)
        map.forcedCoordinate = CLLocationCoordinate2D(latitude: 1, longitude: 2)
        let tap = MockTapGesture()
        tap.view = map
        coord.handleTap(tap)
        XCTAssertEqual(wp?.coordinate.latitude, 1, accuracy: 0.0001)
        XCTAssertEqual(wp?.coordinate.longitude, 2, accuracy: 0.0001)
    }

    func testRangeRingUpdated() {
        var wp: Waypoint?
        var nav: NavComputed?
        let bwp = Binding<Waypoint?>(get: { wp }, set: { wp = $0 })
        let bnav = Binding<NavComputed?>(get: { nav }, set: { nav = $0 })
        let (coord, loc, map) = makeCoordinator(waypoint: bwp, navInfo: bnav)
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, course: 90, speed: 100/1.94384, timestamp: Date())
        loc.lastLocation = location
        coord.updateForCurrentState()
        let hasOverlay = map.overlays.contains { $0 is RangeRingOverlay }
        XCTAssertTrue(hasOverlay)
    }

    func testOverlayObjectsAreReused() {
        var wp: Waypoint?
        var nav: NavComputed?
        let bwp = Binding<Waypoint?>(get: { wp }, set: { wp = $0 })
        let bnav = Binding<NavComputed?>(get: { nav }, set: { nav = $0 })
        let (coord, loc, map) = makeCoordinator(waypoint: bwp, navInfo: bnav)

        let loc1 = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, course: 90, speed: 80/1.94384, timestamp: Date())
        loc.lastLocation = loc1
        coord.updateForCurrentState()

        let ring1 = map.overlays.first { $0 is RangeRingOverlay } as? RangeRingOverlay
        let track1 = map.overlays.first { $0 is TrackVectorOverlay } as? TrackVectorOverlay

        let loc2 = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, course: 100, speed: 50/1.94384, timestamp: Date())
        loc.lastLocation = loc2
        coord.updateForCurrentState()

        let ring2 = map.overlays.first { $0 is RangeRingOverlay } as? RangeRingOverlay
        let track2 = map.overlays.first { $0 is TrackVectorOverlay } as? TrackVectorOverlay

        XCTAssertTrue(ring1 === ring2)
        XCTAssertTrue(track1 === track2)
        XCTAssertEqual(ring2?.coordinate.latitude, 1, accuracy: 0.0001)
        XCTAssertEqual(track2?.courseDeg, 100, accuracy: 0.0001)
    }

    func testOverlayRecreatedWhenChangeIsLarge() {
        var wp: Waypoint?
        var nav: NavComputed?
        let bwp = Binding<Waypoint?>(get: { wp }, set: { wp = $0 })
        let bnav = Binding<NavComputed?>(get: { nav }, set: { nav = $0 })
        let (coord, loc, map) = makeCoordinator(waypoint: bwp, navInfo: bnav)

        let loc1 = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, course: 90, speed: 80/1.94384, timestamp: Date())
        loc.lastLocation = loc1
        coord.updateForCurrentState()

        let ring1 = map.overlays.first { $0 is RangeRingOverlay } as? RangeRingOverlay
        let track1 = map.overlays.first { $0 is TrackVectorOverlay } as? TrackVectorOverlay

        let loc2 = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 5, longitude: 5), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, course: 100, speed: 50/1.94384, timestamp: Date())
        loc.lastLocation = loc2
        coord.updateForCurrentState()

        let ring2 = map.overlays.first { $0 is RangeRingOverlay } as? RangeRingOverlay
        let track2 = map.overlays.first { $0 is TrackVectorOverlay } as? TrackVectorOverlay

        XCTAssertFalse(ring1 === ring2)
        XCTAssertFalse(track1 === track2)
        XCTAssertEqual(ring2?.coordinate.latitude, 5, accuracy: 0.0001)
        XCTAssertEqual(track2?.courseDeg, 100, accuracy: 0.0001)
    }
}
