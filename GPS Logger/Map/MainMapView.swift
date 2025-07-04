import SwiftUI
import MapKit
import Combine
import QuartzCore

/// 新しいズーム倍率（旧来の 4 倍）
private func metersForRng(_ radiusNm: Double) -> Double {
    let diameterNm = radiusNm * 4
    return diameterNm * 2 * 1852.0
}

/// Map 表示を行うメインビュー
struct MainMapView: View {
    @StateObject var settings: Settings
    @StateObject var flightLogManager: FlightLogManager
    @StateObject var locationManager: LocationManager
    @StateObject var airspaceManager: AirspaceManager
    @State private var showLayerSettings = false
    @StateObject private var hudViewModel: HUDViewModel
    @State private var waypoint: Waypoint? = nil
    @State private var navInfo: NavComputed? = nil
    @State private var freeScroll: Bool = false
    @State private var gpsAlert: Bool = false

    init() {
        let settings = Settings()
        _settings = StateObject(wrappedValue: settings)
        let flightLog = FlightLogManager(settings: settings)
        _flightLogManager = StateObject(wrappedValue: flightLog)

        let aspManager = AirspaceManager(settings: settings)
        aspManager.loadAll()
        _airspaceManager = StateObject(wrappedValue: aspManager)

        let hudVM = HUDViewModel(airspaceManager: aspManager)
        _hudViewModel = StateObject(wrappedValue: hudVM)

        _locationManager = StateObject(wrappedValue: LocationManager(flightLogManager: flightLog, settings: settings))
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
                                    freeScroll: $freeScroll,
                                    gpsAlert: $gpsAlert)
                    .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.red, lineWidth: 20)
                    .opacity(gpsAlert ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: gpsAlert)
                    .ignoresSafeArea()

                if let nav = navInfo {
                    // bannerAnnotation は廃止したため、ナビゲーション情報は
                    // 画面中央の HUD で表示し続ける
                    TargetBannerView(nav: nav, locationManager: locationManager)
                        .position(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)
                }


                StatusRibbonView(locationManager: locationManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .offset(y: -UIScreen.main.bounds.height / 3)
            
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
    @Binding var gpsAlert: Bool

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        if let scrollView = map.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
            scrollView.bounces = false
        }
        map.showsUserLocation = true
        map.delegate = context.coordinator
        map.isZoomEnabled = false
        map.isScrollEnabled = freeScroll
        map.isRotateEnabled = (settings.orientationMode == .manual)
        // 俯瞰(ピッチ)操作は常に無効化しておく
        map.isPitchEnabled = false
        map.showsCompass = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        let long = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        map.addGestureRecognizer(long)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        map.addGestureRecognizer(pinch)
        context.coordinator.mapView = map
        context.coordinator.updateForCurrentState()
        context.coordinator.updateFacilityAnnotations()
        let compass = MKCompassButton(mapView: map)
        compass.compassVisibility = .visible
        let compassTap = UITapGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.handleCompassTap))
        compass.addGestureRecognizer(compassTap)
        map.addSubview(compass)
        compass.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            compass.topAnchor.constraint(equalTo: map.topAnchor, constant: 10),
            compass.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -10)
        ])
        if let mbURL = Bundle.module.url(forResource: "basemap", withExtension: "mbtiles"),
           let overlay = MBTilesOverlay(mbtilesURL: mbURL) {
            map.addOverlay(overlay, level: .aboveLabels)
        }
        DispatchQueue.main.async {
            airspaceManager.updateMapRect(map.visibleMapRect)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let targetIDs = Set(airspaceManager.displayOverlays.map { ObjectIdentifier($0) })
        let toRemove = map.overlays
            .filter { context.coordinator.overlayIDs.contains(ObjectIdentifier($0)) }
            .filter { !targetIDs.contains(ObjectIdentifier($0)) }
        if !toRemove.isEmpty {
            map.removeOverlays(toRemove)
            context.coordinator.clearRenderers(for: toRemove)
        }

        let toAdd = airspaceManager.displayOverlays
            .filter { !context.coordinator.overlayIDs.contains(ObjectIdentifier($0)) }
        if !toAdd.isEmpty { map.addOverlays(toAdd) }

        context.coordinator.overlayIDs = targetIDs

        // annotations
        let targetAnnIDs = Set(airspaceManager.displayAnnotations.map { ObjectIdentifier($0) })
        let annToRemove = map.annotations
            .filter { context.coordinator.annotationIDs.contains(ObjectIdentifier($0 as AnyObject)) }
            .filter { !targetAnnIDs.contains(ObjectIdentifier($0 as AnyObject)) }
        if !annToRemove.isEmpty { map.removeAnnotations(annToRemove) }

        let annToAdd = airspaceManager.displayAnnotations
            .filter { !context.coordinator.annotationIDs.contains(ObjectIdentifier($0)) }
        if !annToAdd.isEmpty { map.addAnnotations(annToAdd) }

        context.coordinator.annotationIDs = targetAnnIDs
        context.coordinator.updateFacilityAnnotations()

        map.isScrollEnabled = freeScroll
        if let scrollView = map.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
            scrollView.bounces = false
        }
        // isPitchEnabled は設定変更で再有効化されないよう毎回 false を指定
        map.isPitchEnabled = false

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
                    freeScroll: $freeScroll,
                    gpsAlert: $gpsAlert)
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
        private var rangeOverlay: RangeRingOverlay?
        private var trackOverlay: TrackVectorOverlay?
        private var targetOverlay: MKPolyline?
        var overlayIDs = Set<ObjectIdentifier>()
        var annotationIDs = Set<ObjectIdentifier>()
        private var annotationCatCancellable: AnyCancellable?
        private var rendererCache: [ObjectIdentifier: MKOverlayRenderer] = [:]
        private var waypoint: Binding<Waypoint?>
        private var navInfo: Binding<NavComputed?>
        private var freeScroll: Binding<Bool>
        private var gpsAlert: Binding<Bool>
        private var lastVisibleRect = MKMapRect.null
        private let layerUpdateSubject = PassthroughSubject<Void, Never>()
        private var layerUpdateCancellable: AnyCancellable?

        private var pinchLevelIndex = 0
        private var pinchAccum: CGFloat = 1.0

        init(airspaceManager: AirspaceManager,
             settings: Settings,
             viewModel: HUDViewModel,
             locationManager: LocationManager,
             waypoint: Binding<Waypoint?>,
             navInfo: Binding<NavComputed?>,
             freeScroll: Binding<Bool>,
             gpsAlert: Binding<Bool>) {
            self.airspaceManager = airspaceManager
            self.settings = settings
            self.viewModel = viewModel
            self.locationManager = locationManager
            self.waypoint = waypoint
            self.navInfo = navInfo
            self.freeScroll = freeScroll
            self.gpsAlert = gpsAlert
            super.init()

            layerUpdateCancellable = layerUpdateSubject
                .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
                .sink { [weak self] in self?.updateLayers() }

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

            settings.$enabledFacilityCategories
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateFacilityAnnotations() }
                .store(in: &settingsCancellables)

            settings.$useNightTheme
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.scheduleUpdateLayers() }
                .store(in: &settingsCancellables)

            settings.$orientationModeValue
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateCamera() }
                .store(in: &settingsCancellables)

            // RNG 変更時もカメラ距離を更新
            settings.$rangeRingRadiusNm
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateCamera() }
                .store(in: &settingsCancellables)

            annotationCatCancellable = airspaceManager.$annotationsByCategory
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateFacilityAnnotations() }
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
                if let overlay = targetOverlay {
                    mapView?.removeOverlay(overlay)
                    rendererCache.removeValue(forKey: ObjectIdentifier(overlay))
                }
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

        @objc func handleCompassTap() {
            let modes = Settings.MapOrientationMode.allCases
            if let idx = modes.firstIndex(of: settings.orientationMode) {
                let next = modes[(idx + 1) % modes.count]
                settings.orientationMode = next
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let key = ObjectIdentifier(overlay)
            if let cached = rendererCache[key] { return cached }

            let renderer: MKOverlayRenderer
            if let ov = overlay as? MBTilesOverlay {
                renderer = MKTileOverlayRenderer(tileOverlay: ov)
            } else if let ring = overlay as? RangeRingOverlay {
                renderer = RangeRingRenderer(overlay: ring, settings: settings)
            } else if let track = overlay as? TrackVectorOverlay {
                renderer = TrackVectorRenderer(overlay: track, settings: settings)
            } else if let poly = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: poly)
                let cat = poly.subtitle ?? ""
                let hex = settings.airspaceStrokeColors[cat] ?? "FF0000FF"
                r.strokeColor = UIColor(hex: hex) ?? .red
                r.lineWidth = 2
                renderer = r
            } else if let polygon = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: polygon)
                let cat = polygon.subtitle ?? ""
                let strokeHex = settings.airspaceStrokeColors[cat] ?? "0000FFFF"
                let fillHex = settings.airspaceFillColors[cat] ?? "0000FF33"
                r.strokeColor = UIColor(hex: strokeHex) ?? .blue
                r.fillColor = UIColor(hex: fillHex) ?? UIColor.blue.withAlphaComponent(0.2)
                r.lineWidth = 1
                renderer = r
            } else if let circle = overlay as? MKCircle {
                let r = MKCircleRenderer(circle: circle)
                let cat = circle.subtitle ?? ""
                let strokeHex = settings.airspaceStrokeColors[cat] ?? "800080FF"
                let fillHex = settings.airspaceFillColors[cat] ?? "80008055"
                r.strokeColor = UIColor(hex: strokeHex) ?? .purple
                r.fillColor = UIColor(hex: fillHex) ?? UIColor.purple.withAlphaComponent(0.3)
                r.lineWidth = 1
                renderer = r
            } else {
                renderer = MKOverlayRenderer(overlay: overlay)
            }

            rendererCache[key] = renderer
            return renderer
        }


        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                // Use default user location annotation (blue dot)
                return nil
            }

            let identifier: String
            if annotation is FacilityAnnotation {
                identifier = "facility"
            } else {
                identifier = "info"
            }

            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.canShowCallout = true

            if let ann = annotation as? FacilityAnnotation,
               let mv = view as? MKMarkerAnnotationView {
                mv.clusteringIdentifier = "facility"
                mv.calloutOffset = calloutOffset(for: ann.subtitle ?? "")
                switch ann.facilityType.lowercased() {
                case "airport", "ad":
                    mv.glyphImage = UIImage(systemName: "airplane")
                case "heliport", "heli" , "helipad":
                    mv.glyphImage = UIImage(systemName: "helicopter")
                case "vor":
                    mv.glyphImage = UIImage(systemName: "antenna.radiowaves.left.and.right")
                case "ndb":
                    mv.glyphImage = UIImage(systemName: "dot.radiowaves.left.and.right")
                default:
                    mv.glyphImage = UIImage(systemName: "mappin")
                }
            } else if let ann = annotation as? MKPointAnnotation,
                      let category = ann.subtitle,
                      let mv = view as? MKMarkerAnnotationView {
                mv.calloutOffset = calloutOffset(for: category)
            }
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
                lastVisibleRect = rect
                Task { @MainActor in
                    airspaceManager.updateMapRect(rect)
                }
            }

            if let ring = rangeOverlay {
                ring.update(center: ring.coordinate,
                            radiusNm: ring.radiusNm,
                            courseDeg: ring.courseDeg,
                            mapHeading: mapView.camera.heading)
                rendererCache[ObjectIdentifier(ring)]?.setNeedsDisplay()
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            // 移動のみではオーバーレイを再生成しない
        }

        private func formattedProps(_ props: [String: Any]) -> String {
            guard !props.isEmpty else { return "" }
            let filtered = props.filter { $0.key != "name" }
            let items = filtered.prefix(3).map { "\($0.key): \($0.value)" }
            return items.joined(separator: "\n")
        }

        private func calloutOffset(for category: String) -> CGPoint {
            switch category.uppercased() {
            case "CTR", "INFO ZONE":
                return CGPoint(x: 0, y: -10)
            case "TCA", "ACA", "PCA":
                return CGPoint(x: 0, y: -20)
            default:
                return CGPoint(x: 0, y: -15)
            }
        }

        private func scheduleUpdateLayers() {
            layerUpdateSubject.send(())
        }

        fileprivate func updateFacilityAnnotations() {
            guard let mapView else { return }
            let enabled = Set(settings.enabledFacilityCategories)
            var targets: [FacilityAnnotation] = []
            for cat in enabled {
                let hidden = Set(settings.hiddenFeatureIDs[cat] ?? [])
                if let list = airspaceManager.annotationsByCategory[cat] {
                    targets.append(contentsOf: list.filter { !hidden.contains($0.featureID) })
                }
            }

            let targetIDs = Set(targets.map { ObjectIdentifier($0) })
            let existing = mapView.annotations.filter {
                annotationIDs.contains(ObjectIdentifier($0 as AnyObject))
            }
            let toRemove = existing.filter {
                !targetIDs.contains(ObjectIdentifier($0 as AnyObject))
            }
            if !toRemove.isEmpty { mapView.removeAnnotations(toRemove) }

            let toAdd = targets.filter { !annotationIDs.contains(ObjectIdentifier($0)) }
            if !toAdd.isEmpty { mapView.addAnnotations(toAdd) }

            annotationIDs = targetIDs
        }

        private func updateLayers() {
            guard let mapView else { return }
            guard let loc = locationManager.lastLocation else { return }

            let validTrack = loc.course >= 0 && loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 100
            gpsAlert.wrappedValue = !validTrack
            let rangeNm = settings.rangeRingRadiusNm
            let course = validTrack ? loc.course : 90

            if let ring = rangeOverlay {
                let dist = GeodesicCalculator.bearingDistance(from: ring.coordinate,
                                                              to: loc.coordinate).distance
                let ratio = max(rangeNm / ring.radiusNm, ring.radiusNm / rangeNm)
                if dist > ring.radiusNm * 10 || ratio >= 3 {
                    mapView.removeOverlay(ring)
                    rendererCache.removeValue(forKey: ObjectIdentifier(ring))
                    let heading = mapView.camera.heading
                    let newRing = RangeRingOverlay(center: loc.coordinate,
                                                 radiusNm: rangeNm,
                                                 courseDeg: course,
                                                 mapHeading: heading)
                    rangeOverlay = newRing
                    mapView.addOverlay(newRing, level: .aboveLabels)
                } else {
                    let heading = mapView.camera.heading
                    ring.update(center: loc.coordinate,
                                radiusNm: rangeNm,
                                courseDeg: course,
                                mapHeading: heading)
                    rendererCache[ObjectIdentifier(ring)]?.setNeedsDisplay()
                }
            } else {
                let heading = mapView.camera.heading
                let ring = RangeRingOverlay(center: loc.coordinate,
                                            radiusNm: rangeNm,
                                            courseDeg: course,
                                            mapHeading: heading)
                rangeOverlay = ring
                mapView.addOverlay(ring, level: .aboveLabels)
            }

            let gs = max(0, loc.speed * 1.94384)
            if let track = trackOverlay {
                let dist = GeodesicCalculator.bearingDistance(from: track.coordinate,
                                                              to: loc.coordinate).distance
                let ratio = max(rangeNm / track.radiusNm, track.radiusNm / rangeNm)
                if dist > track.radiusNm * 10 || ratio >= 3 {
                    mapView.removeOverlay(track)
                    rendererCache.removeValue(forKey: ObjectIdentifier(track))
                    let newTrack = TrackVectorOverlay(center: loc.coordinate,
                                                     courseDeg: course,
                                                     groundSpeedKt: gs,
                                                     radiusNm: rangeNm,
                                                     valid: validTrack)
                    trackOverlay = newTrack
                    mapView.addOverlay(newTrack, level: .aboveLabels)
                } else {
                    track.update(center: loc.coordinate,
                                 courseDeg: course,
                                 groundSpeedKt: gs,
                                 radiusNm: rangeNm,
                                 valid: validTrack)
                    rendererCache[ObjectIdentifier(track)]?.setNeedsDisplay()
                }
            } else {
                let track = TrackVectorOverlay(center: loc.coordinate,
                                               courseDeg: course,
                                               groundSpeedKt: gs,
                                               radiusNm: rangeNm,
                                               valid: validTrack)
                trackOverlay = track
                mapView.addOverlay(track, level: .aboveLabels)
            }
        }

        private func normalizedHeading(_ raw: CLLocationDirection?) -> CLLocationDirection {
            guard let h = raw, h.isFinite, h >= 0 else { return 0 }
            return fmod(h, 360)
        }

        private func updateCamera() {
            guard let mapView,
                  let loc = locationManager.lastLocation else { return }

            // フリースクロール中はカメラの自動更新を行わない
            if freeScroll.wrappedValue { return }

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

                if let ring = self.rangeOverlay {
                    ring.update(center: ring.coordinate,
                                radiusNm: ring.radiusNm,
                                courseDeg: ring.courseDeg,
                                mapHeading: cam.heading)
                    self.rendererCache[ObjectIdentifier(ring)]?.setNeedsDisplay()
                }
            }
        }

        private func updateAircraftLocation(_ loc: CLLocation) {
            scheduleUpdateLayers()
            updateNav()
            updateCamera()
        }

        private func updateNav() {
            guard let wp = waypoint.wrappedValue,
                  let mapView,
                  let loc = locationManager.lastLocation else { return }
            let state = AircraftState(position: loc.coordinate,
                                     groundTrack: loc.course,
                                     groundSpeedKt: max(0, loc.speed * 1.94384),
                                     altitudeFt: locationManager.rawGpsAltitude,
                                     timestamp: Date())
            let bd = GeodesicCalculator.bearingDistance(from: state.position, to: wp.coordinate)
            let ete = state.groundSpeedKt > 0 ? bd.distance / state.groundSpeedKt * 3600 : 0
            let eta = Date().addingTimeInterval(ete)
            let ten = GeodesicCalculator.tenMinPoint(state: state)
            navInfo.wrappedValue = NavComputed(bearing: bd.bearing,
                                               radial: nil,
                                               distance: bd.distance,
                                               ete: ete,
                                               eta: eta,
                                               tenMinPoint: ten)

            if let old = targetOverlay {
                mapView.removeOverlay(old)
                rendererCache.removeValue(forKey: ObjectIdentifier(old))
            }
            var coords = [state.position, wp.coordinate]
            let poly = MKPolyline(coordinates: &coords, count: 2)
            targetOverlay = poly
            mapView.addOverlay(poly, level: .aboveLabels)

        }

        func updateForCurrentState() {
            if let loc = locationManager.lastLocation {
                updateAircraftLocation(loc)
            }
        }

        func clearRenderers(for overlays: [MKOverlay]) {
            for ov in overlays {
                rendererCache.removeValue(forKey: ObjectIdentifier(ov))
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

        // ナビゲーション計算
        if let loc = locationManager.lastLocation {
            let state = AircraftState(position: loc.coordinate,
                                     groundTrack: loc.course,
                                     groundSpeedKt: max(0, loc.speed * 1.94384),
                                     altitudeFt: locationManager.rawGpsAltitude,
                                     timestamp: Date())
            let bd = GeodesicCalculator.bearingDistance(from: state.position, to: coord)
            let ete = state.groundSpeedKt > 0 ? bd.distance / state.groundSpeedKt * 3600 : 0
            let eta = Date().addingTimeInterval(ete)
            let ten = GeodesicCalculator.tenMinPoint(state: state)
            let radial = fmod(bd.bearing + 180.0, 360.0)
            navInfo.wrappedValue = NavComputed(bearing: bd.bearing,
                                               radial: radial,
                                               distance: bd.distance,
                                               ete: ete,
                                               eta: eta,
                                               tenMinPoint: ten)
        }

        let ann = MKPointAnnotation()
        // 画面上端へ吹き出しを表示するため、座標を変換してずらす
        let pt = CGPoint(x: mapView.bounds.midX, y: 40)
        ann.coordinate = mapView.convert(pt, toCoordinateFrom: mapView)
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
        navInfo.wrappedValue = nil
    }
}
#endif

struct TargetBannerView: View {
    let nav: NavComputed
    @ObservedObject var locationManager: LocationManager

    private var etaText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: nav.eta)
    }

    private var eteText: String {
        let fmt = DateComponentsFormatter()
        fmt.allowedUnits = [.hour, .minute, .second]
        fmt.unitsStyle = .positional
        fmt.zeroFormattingBehavior = [.pad]
        return fmt.string(from: nav.ete) ?? "--:--:--"
    }

    private var radialText: String? {
        guard let rad = nav.radial else { return nil }
        guard let loc = locationManager.lastLocation else {
            return String(format: "RAD %03.0f°", rad)
        }
        var mag = rad - MagneticVariation.declination(at: loc.coordinate)
        if mag < 0 { mag += 360 }
        if mag >= 360 { mag -= 360 }
        return String(format: "RAD %03.0f°", mag)
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 12) {
                if let rText = radialText {
                    Text(rText)
                    Text(String(format: "DME %.1f NM", nav.distance))
                } else {
                    Text(String(format: "BRG %03.0f°", nav.bearing))
                    Text(String(format: "RNG %.1f NM", nav.distance))
                }
            }
            HStack(spacing: 12) {
                Text("ETE \(eteText)")
                Text("ETA \(etaText)")
            }
        }
        .font(.title3.monospacedDigit())
        .padding(8)
        .background(Color.black.opacity(0.6))
        .foregroundColor(.white)
        .cornerRadius(6)
    }
}

struct StatusRibbonView: View {
    @ObservedObject var locationManager: LocationManager
    @State private var useMetric = false
    private static let fieldWidth: CGFloat = 150

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
            Text("GS \(gsText)")
                .frame(width: Self.fieldWidth, alignment: .center)
            Text("ALT \(altText)")
                .frame(width: Self.fieldWidth, alignment: .center)
        }
        .font(.title3.monospacedDigit())
        .padding(8)
        .background(Color.black.opacity(0.6))
        .foregroundColor(.white)
        .cornerRadius(6)
        .onTapGesture { useMetric.toggle() }
    }
}
