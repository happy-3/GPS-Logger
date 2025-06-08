import SwiftUI
import MapKit

/// Map 表示を行うメインビュー
struct MainMapView: View {
    @StateObject var settings: Settings
    @StateObject var flightLogManager: FlightLogManager
    @StateObject var altitudeFusionManager: AltitudeFusionManager
    @StateObject var locationManager: LocationManager
    @StateObject var airspaceManager: AirspaceManager

    init() {
        let settings = Settings()
        _settings = StateObject(wrappedValue: settings)
        let flightLog = FlightLogManager(settings: settings)
        let altitudeFusion = AltitudeFusionManager(settings: settings)
        _flightLogManager = StateObject(wrappedValue: flightLog)
        _altitudeFusionManager = StateObject(wrappedValue: altitudeFusion)
        _airspaceManager = StateObject(wrappedValue: AirspaceManager(settings: settings))
        _locationManager = StateObject(wrappedValue: LocationManager(flightLogManager: flightLog, altitudeFusionManager: altitudeFusion, settings: settings))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MapViewRepresentable(locationManager: locationManager, airspaceManager: airspaceManager, settings: settings)
                    .ignoresSafeArea()
            }
            .navigationTitle("Map")
            .toolbar(content: {
                NavigationLink("Detail") {
                    ContentView(
                        flightLogManager: flightLogManager,
                        altitudeFusionManager: altitudeFusionManager,
                        locationManager: locationManager
                    )
                    .environmentObject(airspaceManager)
                }
            })
            .onAppear {
                locationManager.startUpdatingForDisplay()
            }
        }
    }
}

struct MapViewRepresentable: UIViewRepresentable {
    let locationManager: LocationManager
    let airspaceManager: AirspaceManager
    let settings: Settings

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.showsUserLocation = true
        map.delegate = context.coordinator
        if let mbURL = Bundle.main.url(forResource: "basemap", withExtension: "mbtiles"),
           let overlay = MBTilesOverlay(mbtilesURL: mbURL) {
            map.addOverlay(overlay, level: .aboveLabels)
        }
        airspaceManager.loadAll()
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let current = map.overlays.filter { !($0 is MBTilesOverlay) }
        map.removeOverlays(current)
        map.addOverlays(airspaceManager.displayOverlays)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let overlay = overlay as? MBTilesOverlay {
                return MKTileOverlayRenderer(tileOverlay: overlay)
            } else if let poly = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: poly)
                renderer.strokeColor = .red
                renderer.lineWidth = 2
                return renderer
            } else if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.strokeColor = UIColor.blue.withAlphaComponent(0.7)
                renderer.fillColor = UIColor.blue.withAlphaComponent(0.2)
                renderer.lineWidth = 1
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
