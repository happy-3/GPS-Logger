import SwiftUI
import MapKit

/// Map 表示を行うメインビュー
struct MainMapView: View {
    @StateObject var settings = Settings()
    @StateObject var flightLogManager = FlightLogManager(settings: Settings())
    @StateObject var altitudeFusionManager = AltitudeFusionManager(settings: Settings())
    @StateObject var locationManager: LocationManager
    @StateObject var airspaceManager = AirspaceManager()

    init() {
        let settings = Settings()
        _locationManager = StateObject(wrappedValue: LocationManager(flightLogManager: FlightLogManager(settings: settings), altitudeFusionManager: AltitudeFusionManager(settings: settings), settings: settings))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MapViewRepresentable(locationManager: locationManager, airspaceManager: airspaceManager)
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

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.showsUserLocation = true
        map.delegate = context.coordinator
        if let mbURL = Bundle.main.url(forResource: "basemap", withExtension: "mbtiles"),
           let overlay = MBTilesOverlay(mbtilesURL: mbURL) {
            map.addOverlay(overlay, level: .aboveLabels)
        }
        if let airURL = Bundle.main.url(forResource: "airspace", withExtension: "geojson") {
            airspaceManager.load(from: airURL)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let current = Set(map.overlays.compactMap { $0 as? MKPolyline })
        let newSet = Set(airspaceManager.overlays)
        if current != newSet {
            map.removeOverlays(map.overlays)
            if let mbURL = Bundle.main.url(forResource: "basemap", withExtension: "mbtiles"),
               let overlay = MBTilesOverlay(mbtilesURL: mbURL) {
                map.addOverlay(overlay, level: .aboveLabels)
            }
            map.addOverlays(Array(newSet))
        }
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
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
