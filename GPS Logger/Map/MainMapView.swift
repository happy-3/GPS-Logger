import SwiftUI
import MapKit
import Combine

/// 新しいズーム倍率（旧来の 4 倍）
private func metersForRng(_ radiusNm: Double) -> Double {
    let diameterNm = radiusNm * 4
    return diameterNm * 2 * 1852.0
}

/// Map 表示を行うメインビュー
struct MainMapView: View {
    @StateObject var settings: Settings
    @StateObject var flightLogManager: FlightLogManager
    @StateObject var altitudeFusionManager: AltitudeFusionManager
    @StateObject var locationManager: LocationManager
    @StateObject var airspaceManager: AirspaceManager
    @State private var showLayerSettings = false
    @StateObject private var hudViewModel: HUDViewModel
    @State private var waypoint: Waypoint? = nil
    @State private var navInfo: NavComputed? = nil
    @State private var freeScroll: Bool = false

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

        let hudVM = HUDViewModel(airspaceManager: aspManager)
        _hudViewModel = StateObject(wrappedValue: hudVM)

        _locationManager = StateObject(wrappedValue: LocationManager(flightLogManager: flightLog, altitudeFusionManager: altitudeFusion, settings: settings))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MapViewRepresentable(locationManager: locationManager,
                                    airspaceManager: airspaceManager,
                                    settings: settings,
                                    hudViewModel: hudViewModel,
                                    waypoint: $waypoint,
                                    navInfo: $navInfo,
                                    freeScroll: $freeScroll)
                    .ignoresSafeArea()

                if let nav = navInfo {
                    TargetBannerView(nav: nav)
                        .position(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)
                }

                HStack {
                    Spacer()
                    Text(String(format: "RNG %.0f NM", settings.rangeRingRadiusNm * 2))
                        .font(.caption.monospacedDigit())
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .padding(.trailing, 10)
                        .padding(.top, 10)
                }

                StatusRibbonView(locationManager: locationManager)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            
                VStack(spacing: 8) {
                    Image(systemName: "z.circle.fill")
                        .resizable()
                        .frame(width: 44, height: 44)
                        .opacity(freeScroll ? 1.0 : 0.3)
                        .foregroundStyle(freeScroll ? Color.accentColor : Color.primary)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                freeScroll.toggle()
                            }
                        }

                    HUDView(viewModel: hudViewModel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding([.trailing, .bottom], 10)

                if hudViewModel.showStack {
                    VStack {
                        Spacer()
                        StackChipView(list: hudViewModel.stackList)
                            .padding(.bottom, 100)
                    }
                }

                if freeScroll {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("FREE SCROLL")
                                .font(.caption2.monospacedDigit())
                                .padding(4)
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                                .padding(.bottom, 50)
                                .padding(.trailing, 10)
                        }
                    }
                }
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
                UIApplication.shared.isIdleTimerDisabled = true
                locationManager.startUpdatingForDisplay()
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .onReceive(locationManager.$lastLocation.compactMap { $0 }) { loc in
                hudViewModel.onNewGPSSample(loc)
            }
        }
    }
}

struct MapViewRepresentable: UIViewRepresentable {
    let locationManager: LocationManager
    @ObservedObject var airspaceManager: AirspaceManager
    @ObservedObject var settings: Settings
    @ObservedObject var hudViewModel: HUDViewModel
    @Binding var waypoint: Waypoint?
    @Binding var navInfo: NavComputed?
    @Binding var freeScroll: Bool

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.showsUserLocation = true
        map.delegate = context.coordinator
        map.isZoomEnabled = false
        map.isScrollEnabled = freeScroll
        map.isRotateEnabled = (settings.orientationMode == .manual)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        let long = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        map.addGestureRecognizer(long)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        map.addGestureRecognizer(pinch)
        context.coordinator.mapView = map
        context.coordinator.updateForCurrentState()
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

        map.isScrollEnabled = freeScroll

        context.coordinator.mapView = map
        context.coordinator.updateForCurrentState()

        if !context.coordinator.regionSet,
           let loc = locationManager.lastLocation {
            let meters = metersForRng(settings.rangeRingRadiusNm)
            let camera = map.camera
            camera.centerCoordinateDistance = meters * 0.65
            camera.centerCoordinate = loc.coordinate
            map.setCamera(camera, animated: false)
            context.coordinator.regionSet = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(airspaceManager: airspaceManager,
                    settings: settings,
                    viewModel: hudViewModel,
                    locationManager: locationManager,
                    waypoint: $waypoint,
                    navInfo: $navInfo,
                    freeScroll: $freeScroll)
    }

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        private var infoAnnotation: MKPointAnnotation?
        private let airspaceManager: AirspaceManager
        private let settings: Settings
        private let viewModel: HUDViewModel
        private let locationManager: LocationManager
        private var cancellable: AnyCancellable?
        private var settingsCancellables = Set<AnyCancellable>()
        var mapView: MKMapView?
        var regionSet = false
        private var aircraft = MKPointAnnotation()
        private var rangeLayer = CAShapeLayer()
        private var trackLayer = CAShapeLayer()
        private var targetOverlay: MKPolyline?
        private var bannerAnnotation: MKPointAnnotation?
        private var waypoint: Binding<Waypoint?>
        private var navInfo: Binding<NavComputed?>
        private var freeScroll: Binding<Bool>
        private var lastVisibleRect = MKMapRect.null
        private var pendingLayerWorkItem: DispatchWorkItem?

        private var pinchLevelIndex = 0
        private var pinchAccum: CGFloat = 1.0

        init(airspaceManager: AirspaceManager,
             settings: Settings,
             viewModel: HUDViewModel,
             locationManager: LocationManager,
             waypoint: Binding<Waypoint?>,
             navInfo: Binding<NavComputed?>,
             freeScroll: Binding<Bool>) {
            self.airspaceManager = airspaceManager
            self.settings = settings
            self.viewModel = viewModel
            self.locationManager = locationManager
            self.waypoint = waypoint
            self.navInfo = navInfo
            self.freeScroll = freeScroll
            super.init()

            cancellable = locationManager.$lastLocation
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] loc in
                    self?.updateAircraftLocation(loc)
                }

            settings.$rangeRingRadiusNm
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.scheduleUpdateLayers()
                }
                .store(in: &settingsCancellables)

            settings.$useNightTheme
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.scheduleUpdateLayers() }
                .store(in: &settingsCancellables)

            settings.$orientationMode
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateCamera() }
                .store(in: &settingsCancellables)

            // RNG 変更時もカメラ距離を更新
            settings.$rangeRingRadiusNm
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateCamera() }
                .store(in: &settingsCancellables)
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            let mapView = sender.view as! MKMapView
            let point = sender.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            if viewModel.zoneQueryOn {
                viewModel.onMapTap(coord)
            } else {
                waypoint.wrappedValue = Waypoint(coordinate: coord)
                updateNav()
            }
        }

        @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
            if sender.state == .began {
                waypoint.wrappedValue = nil
                navInfo.wrappedValue = nil
                if let overlay = targetOverlay { mapView?.removeOverlay(overlay) }
                if let ann = bannerAnnotation { mapView?.removeAnnotation(ann) }
            }
        }

        @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
            guard let mapView = mapView else { return }
            switch sender.state {
            case .began:
                let radius = settings.rangeRingRadiusNm
                let levels = Settings.zoomDiametersNm.map { $0 / 2 }
                let idx = levels.enumerated().min(by: { abs($0.element - radius) < abs($1.element - radius) })?.offset ?? 0
                pinchLevelIndex = idx
                pinchAccum = 1.0
            case .changed:
                pinchAccum *= sender.scale
                sender.scale = 1.0
                // 指を開いた場合はズームイン (半径縮小)
                if pinchAccum > 1.4, pinchLevelIndex > 0 {
                    pinchLevelIndex -= 1
                    applyZoom(mapView)
                    pinchAccum = 1.0
                // 指を閉じた場合はズームアウト (半径拡大)
                } else if pinchAccum < 0.6, pinchLevelIndex < Settings.zoomDiametersNm.count - 1 {
                    pinchLevelIndex += 1
                    applyZoom(mapView)
                    pinchAccum = 1.0
                }
            case .ended, .cancelled:
                pinchAccum = 1.0
            default:
                break
            }
        }

        private func applyZoom(_ mapView: MKMapView) {
            let radiusNm = Settings.zoomDiametersNm[pinchLevelIndex] / 2
            settings.rangeRingRadiusNm = radiusNm

            let center = locationManager.lastLocation?.coordinate ?? mapView.region.center
            let meters = metersForRng(radiusNm)
            let region = MKCoordinateRegion(center: center,
                                            latitudinalMeters: meters,
                                            longitudinalMeters: meters)
            mapView.setRegion(region, animated: true)

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
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


        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                // Use default user location annotation (blue dot)
                return nil
            }

            if annotation === aircraft {
                let id = "aircraft"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.image = UIImage(systemName: "airplane")
                view.bounds.size = CGSize(width: 30, height: 30)
                if let hdg = locationManager.lastLocation?.course {
                    view.transform = CGAffineTransform(rotationAngle: CGFloat(hdg * .pi / 180))
                }
                let tag = 1001
                let label: UILabel
                if let existing = view.viewWithTag(tag) as? UILabel {
                    label = existing
                } else {
                    label = UILabel()
                    label.tag = tag
                    label.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                    label.textColor = .white
                    label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
                    view.addSubview(label)
                }
                if let loc = locationManager.lastLocation {
                    let gs = max(0, loc.speed * 1.94384)
                    label.text = String(format: "TRK %03.0f° GS %.0f kt ALT %.0f ft", loc.course, gs, locationManager.rawGpsAltitude)
                    label.sizeToFit()
                    label.center = CGPoint(x: view.bounds.midX, y: view.bounds.maxY + label.bounds.height/2)
                }
                return view
            }

            if annotation === bannerAnnotation {
                let id = "banner"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                if let nav = navInfo.wrappedValue {
                    let label = UILabel()
                    label.numberOfLines = 0
                    label.font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
                    let fmt = DateFormatter()
                    fmt.dateFormat = "HH:mm:ss"
                    label.text = String(format: "BRG %03.0f\nDST %.1f\nETE %.0f\nETA %@", nav.bearing, nav.distance, nav.ete, fmt.string(from: nav.eta))
                    label.textColor = .white
                    label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
                    label.sizeToFit()
                    view.addSubview(label)
                    view.bounds = label.bounds
                }
                return view
            }

            let id = "info"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.canShowCallout = true
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let rect = mapView.visibleMapRect
            let dx = abs(rect.midX - lastVisibleRect.midX)
            let dy = abs(rect.midY - lastVisibleRect.midY)
            let dw = abs(rect.size.width - lastVisibleRect.size.width)
            let dh = abs(rect.size.height - lastVisibleRect.size.height)
            let threshold = max(rect.size.width, rect.size.height) * 0.1
            if lastVisibleRect.isNull || dx > threshold || dy > threshold || dw > threshold || dh > threshold {
                airspaceManager.updateMapRect(rect)
                lastVisibleRect = rect
            }
            scheduleUpdateLayers()
        }

        private func formattedProps(_ props: [String: Any]) -> String {
            guard !props.isEmpty else { return "" }
            let filtered = props.filter { $0.key != "name" }
            let items = filtered.prefix(3).map { "\($0.key): \($0.value)" }
            return items.joined(separator: "\n")
        }

        private func scheduleUpdateLayers() {
            pendingLayerWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.updateLayers() }
            pendingLayerWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }

        private func updateLayers() {
            guard let mapView else { return }
            // CAShapeLayer はインスタンスを再利用し、パスのみ更新する
            if rangeLayer.superlayer == nil {
                mapView.layer.addSublayer(rangeLayer)
            }
            if trackLayer.superlayer == nil {
                mapView.layer.addSublayer(trackLayer)
            }

            guard let loc = locationManager.lastLocation else { return }
            let center = mapView.convert(loc.coordinate, toPointTo: mapView)
            let rangeNm = settings.rangeRingRadiusNm
            let edge = GeodesicCalculator.destinationPoint(from: loc.coordinate, courseDeg: 90, distanceNm: rangeNm)
            let edgePt = mapView.convert(edge, toPointTo: mapView)
            let radius = hypot(edgePt.x - center.x, edgePt.y - center.y)
            let ringPath = UIBezierPath()
            for frac in [0.25, 0.5, 0.75, 1.0] {
                ringPath.append(UIBezierPath(arcCenter: center, radius: radius * frac, startAngle: 0, endAngle: .pi*2, clockwise: true))
            }
            rangeLayer.fillColor = UIColor.clear.cgColor
            let ringHex = settings.useNightTheme ? Color("RangeRingNight", bundle: .module).hexString
                                                 : Color("RangeRingDay", bundle: .module).hexString
            rangeLayer.strokeColor = UIColor(hex: ringHex)?.cgColor ?? UIColor.orange.cgColor
            rangeLayer.lineWidth = 1
            rangeLayer.path = ringPath.cgPath

            let vecDest = GeodesicCalculator.destinationPoint(from: loc.coordinate, courseDeg: loc.course, distanceNm: 1)
            let vecPt = mapView.convert(vecDest, toPointTo: mapView)
            let vecPath = UIBezierPath()
            vecPath.move(to: center)
            vecPath.addLine(to: vecPt)
            let trackHex = settings.useNightTheme ? Color("TrackNight", bundle: .module).hexString
                                                 : Color("TrackDay", bundle: .module).hexString
            trackLayer.strokeColor = UIColor(hex: trackHex)?.cgColor ?? UIColor.yellow.cgColor
            trackLayer.lineWidth = 2
            trackLayer.path = vecPath.cgPath
        }

        private func normalizedHeading(_ raw: CLLocationDirection?) -> CLLocationDirection {
            guard let h = raw, h.isFinite, h >= 0 else { return 0 }
            return fmod(h, 360)
        }

        private func updateCamera() {
            guard let mapView,
                  let loc = locationManager.lastLocation else { return }

            DispatchQueue.main.async {
                let cam = mapView.camera
                // ズーム距離を設定
                let meters = metersForRng(self.settings.rangeRingRadiusNm) * 0.65
                cam.centerCoordinateDistance = meters
                switch self.settings.orientationMode {
                case .northUp:
                    cam.heading = 0
                case .trackUp:
                    cam.heading = self.normalizedHeading(loc.course)
                case .magneticUp:
                    cam.heading = self.normalizedHeading(
                        self.locationManager.lastHeading?.magneticHeading ?? loc.course)
                case .manual:
                    break
                }
                if !self.freeScroll.wrappedValue {
                    cam.centerCoordinate = loc.coordinate
                }
                mapView.setCamera(cam, animated: false)
                mapView.isRotateEnabled = (self.settings.orientationMode == .manual)
            }
        }

        private func updateAircraftLocation(_ loc: CLLocation) {
            aircraft.coordinate = loc.coordinate
            if let mapView,
               let view = mapView.view(for: aircraft) {
                let tag = 1001
                let label = view.viewWithTag(tag) as? UILabel
                let gs = max(0, loc.speed * 1.94384)
                label?.text = String(format: "TRK %03.0f° GS %.0f kt ALT %.0f ft", loc.course, gs, locationManager.rawGpsAltitude)
                label?.sizeToFit()
                label?.center = CGPoint(x: view.bounds.midX, y: view.bounds.maxY + (label?.bounds.height ?? 0)/2)
                view.transform = CGAffineTransform(rotationAngle: CGFloat(loc.course * .pi / 180))
            } else {
                mapView?.addAnnotation(aircraft)
            }
            scheduleUpdateLayers()
            updateNav()
            updateCamera()
        }

        private func updateNav() {
            guard let wp = waypoint.wrappedValue,
                  let mapView else { return }
            let state = AircraftState(position: aircraft.coordinate,
                                     groundTrack: locationManager.lastLocation?.course ?? 0,
                                     groundSpeedKt: max(0, locationManager.lastLocation?.speed ?? 0 * 1.94384),
                                     altitudeFt: locationManager.rawGpsAltitude,
                                     timestamp: Date())
            let bd = GeodesicCalculator.bearingDistance(from: state.position, to: wp.coordinate)
            let ete = state.groundSpeedKt > 0 ? bd.distance / state.groundSpeedKt * 3600 : 0
            let eta = Date().addingTimeInterval(ete)
            let ten = GeodesicCalculator.tenMinPoint(state: state)
            navInfo.wrappedValue = NavComputed(bearing: bd.bearing, distance: bd.distance, ete: ete, eta: eta, tenMinPoint: ten)

            if let old = targetOverlay { mapView.removeOverlay(old) }
            var coords = [state.position, wp.coordinate]
            let poly = MKPolyline(coordinates: &coords, count: 2)
            targetOverlay = poly
            mapView.addOverlay(poly)

            let mid = GeodesicCalculator.destinationPoint(from: state.position, courseDeg: bd.bearing, distanceNm: bd.distance/2)
            if let ann = bannerAnnotation { mapView.removeAnnotation(ann) }
            let ann = MKPointAnnotation()
            ann.coordinate = mid
            bannerAnnotation = ann
            mapView.addAnnotation(ann)
        }

        func updateForCurrentState() {
            if let loc = locationManager.lastLocation {
                updateAircraftLocation(loc)
            }
        }
    }
}

#if swift(>=5.9)
@available(iOS 17.0, *)
extension MapViewRepresentable.Coordinator {
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

    func mapView(_ mapView: MKMapView, didDeselect overlay: MKOverlay) {
        if let ann = infoAnnotation {
            mapView.removeAnnotation(ann)
            infoAnnotation = nil
        }
    }
}
#endif

struct TargetBannerView: View {
    let nav: NavComputed

    private var etaText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: nav.eta)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "BRG %03.0f°", nav.bearing))
            Text(String(format: "DST %.1f NM", nav.distance))
            Text(String(format: "ETE %.0f s", nav.ete))
            Text("ETA \(etaText)")
        }
        .font(.caption2.monospacedDigit())
        .padding(6)
        .background(Color.black.opacity(0.6))
        .foregroundColor(.white)
        .cornerRadius(6)
    }
}

struct StatusRibbonView: View {
    @ObservedObject var locationManager: LocationManager
    @State private var useMetric = false

    private var gsText: String {
        if useMetric {
            return String(format: "%.1f km/h", max(0, (locationManager.lastLocation?.speed ?? 0) * 3.6))
        } else {
            return String(format: "%.1f kt", max(0, (locationManager.lastLocation?.speed ?? 0) * 1.94384))
        }
    }

    private var altText: String {
        if useMetric {
            return String(format: "%.0f m", locationManager.rawGpsAltitude * 0.3048)
        } else {
            return String(format: "%.0f ft", locationManager.rawGpsAltitude)
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            if let track = locationManager.lastLocation?.course, track >= 0 {
                Text(String(format: "TRK %.0f°", track))
            } else {
                Text("TRK --")
            }
            Text("GS \(gsText)")
            Text("ALT \(altText)")
        }
        .font(.caption.monospacedDigit())
        .padding(6)
        .background(Color.black.opacity(0.6))
        .foregroundColor(.white)
        .cornerRadius(6)
        .onTapGesture { useMetric.toggle() }
    }
}
