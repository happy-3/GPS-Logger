import SwiftUI
import MapKit

/// Map 表示を行うメインビュー
struct MainMapView: View {
    @StateObject var settings: Settings
    @StateObject var flightLogManager: FlightLogManager
    @StateObject var altitudeFusionManager: AltitudeFusionManager
    @StateObject var locationManager: LocationManager
    @StateObject var airspaceManager: AirspaceManager
    @State private var showLayerSettings = false

    init() {
        let settings = Settings()
        _settings = StateObject(wrappedValue: settings)
        let flightLog = FlightLogManager(settings: settings)
        let altitudeFusion = AltitudeFusionManager(settings: settings)
        _flightLogManager = StateObject(wrappedValue: flightLog)
        _altitudeFusionManager = StateObject(wrappedValue: altitudeFusion)

        let aspManager = AirspaceManager(settings: settings)
        aspManager.loadAll()
        _airspaceManager = StateObject(wrappedValue: aspManager)

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
                Button {
                    showLayerSettings = true
                } label: {
                    Label("レイヤ", systemImage: "square.3.stack.3d")
                }
            })
            .sheet(isPresented: $showLayerSettings) {
                NavigationStack {
                    MapLayerSettingsView()
                        .environmentObject(settings)
                        .environmentObject(airspaceManager)
                }
            }
            .onAppear {
                locationManager.startUpdatingForDisplay()
            }
        }
    }
}

struct MapViewRepresentable: UIViewRepresentable {
    let locationManager: LocationManager
    @ObservedObject var airspaceManager: AirspaceManager
    @ObservedObject var settings: Settings

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.showsUserLocation = true
        map.delegate = context.coordinator
        if let mbURL = Bundle.module.url(forResource: "basemap", withExtension: "mbtiles"),
           let overlay = MBTilesOverlay(mbtilesURL: mbURL) {
            map.addOverlay(overlay, level: .aboveLabels)
        }
        airspaceManager.updateMapRect(map.visibleMapRect)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let current = map.overlays.filter { !($0 is MBTilesOverlay) }
        map.removeOverlays(current)
        map.addOverlays(airspaceManager.displayOverlays)

        if !context.coordinator.regionSet,
           let loc = locationManager.lastLocation {
            let meters = 40.0 * 1852.0
            let region = MKCoordinateRegion(center: loc.coordinate,
                                            latitudinalMeters: meters,
                                            longitudinalMeters: meters)
            map.setRegion(region, animated: false)
            context.coordinator.regionSet = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(airspaceManager: airspaceManager)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        private var infoAnnotation: MKPointAnnotation?
        private let airspaceManager: AirspaceManager
        var regionSet = false

        init(airspaceManager: AirspaceManager) {
            self.airspaceManager = airspaceManager
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let overlay = overlay as? MBTilesOverlay {
                return MKTileOverlayRenderer(tileOverlay: overlay)
            } else if let poly = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: poly)
                let cat = (poly.subtitle ?? "")
                let hex = settings.airspaceStrokeColors[cat] ?? "FF0000FF"
                renderer.strokeColor = UIColor(hex: hex) ?? .red
                renderer.lineWidth = 2
                return renderer
            } else if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                let cat = (polygon.subtitle ?? "")
                let strokeHex = settings.airspaceStrokeColors[cat] ?? "0000FFFF"
                let fillHex = settings.airspaceFillColors[cat] ?? "0000FF33"
                renderer.strokeColor = UIColor(hex: strokeHex) ?? .blue
                renderer.fillColor = UIColor(hex: fillHex) ?? UIColor.blue.withAlphaComponent(0.2)
                renderer.lineWidth = 1
                return renderer
            } else if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                let cat = (circle.subtitle ?? "")
                let strokeHex = settings.airspaceStrokeColors[cat] ?? "800080FF"
                let fillHex = settings.airspaceFillColors[cat] ?? "80008055"
                renderer.strokeColor = UIColor(hex: strokeHex) ?? .purple
                renderer.fillColor = UIColor(hex: fillHex) ?? UIColor.purple.withAlphaComponent(0.3)
                renderer.lineWidth = 1
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        @available(iOS 17.0, *)
        func mapView(_ mapView: MKMapView, didSelect overlay: MKOverlay) {
            guard let shape = overlay as? MKShape,
                  let title = shape.title else { return }
            let rect = overlay.boundingMapRect
            let coord = CLLocationCoordinate2D(latitude: rect.midY, longitude: rect.midX)
            let ann = MKPointAnnotation()
            ann.coordinate = coord
            ann.title = title
            if let f = overlay as? FeaturePolyline {
                ann.subtitle = formattedProps(f.properties)
            } else if let f = overlay as? FeaturePolygon {
                ann.subtitle = formattedProps(f.properties)
            } else if let f = overlay as? FeatureCircle {
                ann.subtitle = formattedProps(f.properties)
            }
            infoAnnotation = ann
            mapView.addAnnotation(ann)
        }

        @available(iOS 17.0, *)
        func mapView(_ mapView: MKMapView, didDeselect overlay: MKOverlay) {
            if let ann = infoAnnotation {
                mapView.removeAnnotation(ann)
                infoAnnotation = nil
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                // Use default user location annotation (blue dot)
                return nil
            }

            let id = "info"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.canShowCallout = true
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            airspaceManager.updateMapRect(mapView.visibleMapRect)
        }

        private func formattedProps(_ props: [String: Any]) -> String {
            guard !props.isEmpty else { return "" }
            let filtered = props.filter { $0.key != "name" }
            let items = filtered.prefix(3).map { "\($0.key): \($0.value)" }
            return items.joined(separator: "\n")
        }
    }
}
