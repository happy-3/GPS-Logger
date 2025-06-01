import SwiftUI
import CoreLocation
import CoreMotion
import AVFoundation
import UIKit
import Combine

// MARK: - ContentView
struct ContentView: View {
    // 各種ObservableObjectの生成（Settingsも含む）
    @StateObject var settings = Settings()
    @StateObject var flightLogManager: FlightLogManager
    @StateObject var altitudeFusionManager: AltitudeFusionManager
    @StateObject var locationManager: LocationManager
    
    @State private var currentTime = Date()
    @State private var capturedCompositeImage: UIImage?
    @State private var showingCompositeCamera = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []

    @State private var measuringDistance = false
    @State private var measurementStart: Date?
    @State private var measurementResultMessage: String?
    @State private var showingMeasurementAlert = false
    @State private var showingDistanceGraph = false
    @State private var graphLogs: [FlightLog] = []
    @State private var lastMeasurement: DistanceMeasurement?
    @State private var measurementLogURL: URL?
    @State private var measurementGraphURL: URL?
    @State private var showSettings = false
    @State private var showFlightAssist = false
    

    // 風情報
    @State private var windDirection: Double?
    @State private var windSpeed: Double?
    @State private var windSource: String?
    @State private var manualWindDirection = ""
    @State private var manualWindSpeed = ""
    @State private var windBaseAltitude: Double?

    // 気圧高度入力
    @State private var pressureAltitude: Double?
    @State private var pressureInput: Int = 0

    // 垂直誤差に基づく色分けの関数
    func verticalErrorColor(for error: Double) -> Color {
        switch error {
        case ..<10:
            return Color.green    // 10ft未満：最適
        case 10..<20:
            return Color.yellow   // 10ft～20ft：良好
        case 20..<50:
            return Color.orange   // 20ft～50ft：注意
        case 50..<100:
            return Color.red.opacity(0.7) // 50ft～100ft：警戒
        default:
            return Color.red      // 100ft超：非常に悪い
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 40) {
            Text("現在時刻 (JST): \(currentTime, formatter: DateFormatter.jstFormatter)")
                .font(.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let loc = locationManager.lastLocation {
                let timeDiff = currentTime.timeIntervalSince(loc.timestamp)
                let gpsColor: Color = timeDiff > 3 ? .red : .white

                let magneticText: String = {
                    if loc.course < 0 {
                        return "未計測"
                    } else {
                        var mc = loc.course - locationManager.declination
                        mc = mc.truncatingRemainder(dividingBy: 360)
                        if mc < 0 { mc += 360 }
                        return String(format: "%.0f°", mc)
                    }
                }()

                VStack(alignment: .leading, spacing: 5) {
                    if timeDiff > 3 {
                        Text(String(format: "未受信 %.0f 秒", timeDiff))
                            .foregroundColor(.red)
                    }
                    Text(String(format: "水平誤差: ±%.1f m", loc.horizontalAccuracy))
                    Text("磁方位: \(magneticText)").font(.title)
                    Text(String(format: "速度: %.1f kt", loc.speed * 1.94384)).font(.title)
                    Text(String(format: "GPS 高度: %.1f ft", locationManager.rawGpsAltitude)).font(.title).padding(.top, 40)

                    if let fusedAlt = altitudeFusionManager.fusedAltitude {
                        Text(String(format: "高度 (Kalman): %.1f ft", fusedAlt))
                    } else {
                        Text(String(format: "高度: %.1f ft", loc.altitude * 3.28084))
                    }
                    Text(String(format: "垂直誤差: ±%.1f ft", loc.verticalAccuracy * 3.28084))
                        .font(.title)
                        .padding(.bottom, 40)
                        .foregroundColor(verticalErrorColor(for: loc.verticalAccuracy * 3.28084))
                    Text(String(format: "GPS 高度変化率: %.1f ft/min", locationManager.rawGpsAltitudeChangeRate))

                    Text(String(format: "高度変化率 (Kalman): %.1f ft/min", altitudeFusionManager.altitudeChangeRate))

                    if let wd = windDirection, let ws = windSpeed {
                        let within = windBaseAltitude.map { abs(locationManager.rawGpsAltitude - $0) <= 500 } ?? false
                        if let base = windBaseAltitude, let hp = pressureAltitude, abs(locationManager.rawGpsAltitude - base) > 2000 {
                            Text("高度が2000ft以上変化しました。気圧高度を再入力してください")
                                .foregroundColor(.orange)
                        }
                        let tas = within ? computeTAS(from: loc) : nil
                        let oat = tas.map { computeOAT(tasKt: $0, altitudeFt: locationManager.rawGpsAltitude) }
                        Text(String(format: "風向 %.0f° 風速 %.1f kt (%@)", wd, ws, windSource ?? ""))
                        if let tas = tas {
                            Text(String(format: "TAS: %.1f kt", tas))
                        }
                        if let tas = tas, let oat = oat {
                            let cas = FlightAssistUtils.cas(tasKt: tas,
                                                           altitudeFt: locationManager.rawGpsAltitude,
                                                           oatC: oat)
                            let hp = FlightAssistUtils.pressureAltitude(altitudeFt: locationManager.rawGpsAltitude,
                                                                          oatC: oat)
                            Group {
                                Text(String(format: "外気温: %.1f ℃", oat))
                                Text(String(format: "CAS: %.1f kt", cas))
                                Text(String(format: "気圧高度: %.0f ft", hp))
                            }
                            .onAppear {
                                locationManager.estimatedOAT = oat
                                locationManager.theoreticalCAS = cas
                                locationManager.theoreticalHP = hp
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("風向")
                                    .frame(width: 40, alignment: .leading)
                                TextField("°", text: $manualWindDirection)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                            }
                            HStack {
                                Text("風速")
                                    .frame(width: 40, alignment: .leading)
                                TextField("kt", text: $manualWindSpeed)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                            }
                            Button("風入力保存") {
                                if let d = Double(manualWindDirection), let s = Double(manualWindSpeed) {
                                    windDirection = d
                                    windSpeed = s
                                    windSource = "manual"
                                    windBaseAltitude = locationManager.rawGpsAltitude
                                    locationManager.windDirection = d
                                    locationManager.windSpeed = s
                                    locationManager.windSource = "manual"
                                }
                            }
                        }
                    }

                    if pressureAltitude == nil {
                        Stepper(value: $pressureInput, in: -10000...60000, step: 1000) {
                            Text("気圧高度: \(pressureInput) ft")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button("HP保存") {
                            pressureAltitude = Double(pressureInput)
                            locationManager.pressureAltitudeFt = pressureAltitude
                        }
                    } else {
                        Text(String(format: "気圧高度: %.0f ft", pressureAltitude!))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
                .font(.body)
                .foregroundColor(gpsColor)
            } else {
                Text("GPSデータ未取得")
                    .font(.title)
                    .foregroundColor(.gray)
            }

            if locationManager.isRecording,
               let startTime = flightLogManager.flightLogs.first?.timestamp {
                Text("記録経過時間: \(elapsedTimeString(from: startTime))")
                    .font(.title2)
            }

            if !flightLogManager.distanceMeasurements.isEmpty {
                VStack(alignment: .leading) {
                    Text("距離計測ログ:")
                        .font(.headline)
                    ForEach(Array(flightLogManager.distanceMeasurements.enumerated()), id: \.offset) { index, m in
                        Text(String(format: "#%d 水平: %.1f m 3D: %.1f m", index + 1, m.horizontalDistance, m.totalDistance))
                            .font(.footnote)
                            .padding(.leading, 8)
                    }
                    Button("距離CSV出力") {
                        if let csvURL = flightLogManager.exportDistanceCSV() {
                            shareItems = [csvURL]
                            showingShareSheet = true
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
            buttonRibbon
        }
        .padding()
    }
    
    
    let uiUpdateTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    init() {
        // 初期化順序に注意
        let settings = Settings()
        let flightLogManager = FlightLogManager(settings: settings)
        let altitudeFusionManager = AltitudeFusionManager(settings: settings)
        let locationManager = LocationManager(flightLogManager: flightLogManager,
                                              altitudeFusionManager: altitudeFusionManager,
                                              settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _flightLogManager = StateObject(wrappedValue: flightLogManager)
        _altitudeFusionManager = StateObject(wrappedValue: altitudeFusionManager)
        _locationManager = StateObject(wrappedValue: locationManager)
    }


    /// ナビゲーション周りをまとめたビュー
    private var navigationContent: some View {
        NavigationContentView(
            mainContent: AnyView(mainContent),
            currentTime: $currentTime,
            capturedCompositeImage: $capturedCompositeImage,
            showingCompositeCamera: $showingCompositeCamera,
            showingShareSheet: $showingShareSheet,
            shareItems: $shareItems,
            showingDistanceGraph: $showingDistanceGraph,
            graphLogs: $graphLogs,
            lastMeasurement: $lastMeasurement,
            measurementLogURL: $measurementLogURL,
            measurementGraphURL: $measurementGraphURL,
            measurementResultMessage: $measurementResultMessage,
            showingMeasurementAlert: $showingMeasurementAlert,
            showSettings: $showSettings,
            showFlightAssist: $showFlightAssist,
            windDirection: $windDirection,
            windSpeed: $windSpeed,
            windSource: $windSource,
            windBaseAltitude: $windBaseAltitude,
            pressureAltitude: $pressureAltitude,
            pressureInput: $pressureInput,
            uiUpdateTimer: uiUpdateTimer
        )
        .environmentObject(settings)
        .environmentObject(flightLogManager)
        .environmentObject(altitudeFusionManager)
        .environmentObject(locationManager)
    }

    var body: some View {
        NavigationStack {
            navigationContent
        }
    }
    
    func elapsedTimeString(from start: Date) -> String {
        let elapsed = Date().timeIntervalSince(start)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    func computeTAS(from location: CLLocation) -> Double? {
        guard let wd = windDirection, let ws = windSpeed, ws >= 0 else { return nil }
        guard location.speed >= 0, location.course >= 0 else { return nil }
        let gs = location.speed * 1.94384
        let angle = (location.course - wd) * .pi / 180
        let tas = sqrt(gs * gs + ws * ws - 2 * gs * ws * cos(angle))
        return tas.isFinite ? tas : nil
    }

    func computeOAT(tasKt: Double, altitudeFt: Double) -> Double {
        let tasMps = tasKt * 0.514444
        let tIsa = ISAAtmosphere.temperature(altitudeFt: altitudeFt) + 273.15
        let speedOfSound = sqrt(1.4 * 287.05 * tIsa)
        let mach = tasMps / speedOfSound
        return FlightAssistUtils.oat(tasMps: tasMps, mach: mach)
    }

    // Bottom ribbon containing action buttons
    @ViewBuilder
    var buttonRibbon: some View {
        if locationManager.isRecording {
            HStack(spacing: 20) {
                Button("記録停止") {
                    locationManager.stopRecording()
                    if let csvURL = flightLogManager.exportCSV() {
                        shareItems = [csvURL]
                        showingShareSheet = true
                    }
                    flightLogManager.endSession()
                }
                .frame(width: 120, height: 50)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(12)

                Button(measuringDistance ? "距離計測終了" : "距離計測開始") {
                    if measuringDistance {
                        let now = Date()
                        if let result = flightLogManager.finishMeasurement(at: now) {
                            graphLogs = flightLogManager.flightLogs.filter { log in
                                log.timestamp >= result.startTime && log.timestamp <= result.endTime
                            }
                            measurementLogURL = flightLogManager.exportMeasurementLogs(for: result,
                                                                               logs: graphLogs)
                            let graphView = DistanceGraphView(logs: graphLogs, measurement: result)
                            if let image = graphView.chartImage() {
                                measurementGraphURL = flightLogManager.exportMeasurementGraphImage(for: result,
                                                                                                chartImage: image)
                            } else {
                                measurementGraphURL = nil
                            }
                            lastMeasurement = result
                            showingDistanceGraph = true
                            measurementResultMessage = nil
                        } else {
                            measurementResultMessage = "計測に失敗しました"
                            showingMeasurementAlert = true
                            measurementLogURL = nil
                            measurementGraphURL = nil
                        }
                        measuringDistance = false
                        measurementStart = nil
                    } else {
                        let start = Date()
                        measurementStart = start
                        flightLogManager.startMeasurement(at: start)
                        measuringDistance = true
                        measurementResultMessage = nil
                        measurementLogURL = nil
                        measurementGraphURL = nil
                    }
                }
                .frame(width: 140, height: 50)
                .background(measuringDistance ? Color.blue : Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)

                Button("静止画撮影") {
                    showingCompositeCamera = true
                }
                .frame(width: 120, height: 50)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        } else {
            HStack {
                Button("記録開始") {
                    locationManager.startRecording()
                }
                .frame(width: 150, height: 50)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
    }

}

// MARK: - NavigationContentView
private struct NavigationContentView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var flightLogManager: FlightLogManager
    @EnvironmentObject var altitudeFusionManager: AltitudeFusionManager
    @EnvironmentObject var locationManager: LocationManager

    @Binding var currentTime: Date
    @Binding var capturedCompositeImage: UIImage?
    @Binding var showingCompositeCamera: Bool
    @Binding var showingShareSheet: Bool
    @Binding var shareItems: [Any]
    @Binding var showingDistanceGraph: Bool
    @Binding var graphLogs: [FlightLog]
    @Binding var lastMeasurement: DistanceMeasurement?
    @Binding var measurementLogURL: URL?
    @Binding var measurementGraphURL: URL?
    @Binding var measurementResultMessage: String?
    @Binding var showingMeasurementAlert: Bool
    @Binding var showSettings: Bool
    @Binding var showFlightAssist: Bool
    @Binding var windDirection: Double?
    @Binding var windSpeed: Double?
    @Binding var windSource: String?
    @Binding var windBaseAltitude: Double?
    @Binding var pressureAltitude: Double?
    @Binding var pressureInput: Int

    let uiUpdateTimer: Publishers.Autoconnect<Timer.TimerPublisher>
    let mainContent: AnyView

    init(
        mainContent: AnyView,
        currentTime: Binding<Date>,
        capturedCompositeImage: Binding<UIImage?>,
        showingCompositeCamera: Binding<Bool>,
        showingShareSheet: Binding<Bool>,
        shareItems: Binding<[Any]>,
        showingDistanceGraph: Binding<Bool>,
        graphLogs: Binding<[FlightLog]>,
        lastMeasurement: Binding<DistanceMeasurement?>,
        measurementLogURL: Binding<URL?>,
        measurementGraphURL: Binding<URL?>,
        measurementResultMessage: Binding<String?>,
        showingMeasurementAlert: Binding<Bool>,
        showSettings: Binding<Bool>,
        showFlightAssist: Binding<Bool>,
        windDirection: Binding<Double?>,
        windSpeed: Binding<Double?>,
        windSource: Binding<String?>,
        windBaseAltitude: Binding<Double?>,
        pressureAltitude: Binding<Double?>,
        pressureInput: Binding<Int>,
        uiUpdateTimer: Publishers.Autoconnect<Timer.TimerPublisher>
    ) {
        self._currentTime = currentTime
        self._capturedCompositeImage = capturedCompositeImage
        self._showingCompositeCamera = showingCompositeCamera
        self._showingShareSheet = showingShareSheet
        self._shareItems = shareItems
        self._showingDistanceGraph = showingDistanceGraph
        self._graphLogs = graphLogs
        self._lastMeasurement = lastMeasurement
        self._measurementLogURL = measurementLogURL
        self._measurementGraphURL = measurementGraphURL
        self._measurementResultMessage = measurementResultMessage
        self._showingMeasurementAlert = showingMeasurementAlert
        self._showSettings = showSettings
        self._showFlightAssist = showFlightAssist
        self._windDirection = windDirection
        self._windSpeed = windSpeed
        self._windSource = windSource
        self._windBaseAltitude = windBaseAltitude
        self._pressureAltitude = pressureAltitude
        self._pressureInput = pressureInput
        self.uiUpdateTimer = uiUpdateTimer
        self.mainContent = mainContent
    }

    var body: some View {
        baseView
            .fullScreenCover(isPresented: $showingCompositeCamera) { compositeCameraView }
            .sheet(isPresented: $showingShareSheet) { ActivityView(activityItems: shareItems) }
            .sheet(isPresented: $showingDistanceGraph) { distanceGraphSheet }
            .alert(measurementResultMessage ?? "", isPresented: $showingMeasurementAlert) {
                Button("OK", role: .cancel) {}
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView(settings: settings)
                    .environmentObject(locationManager)
            }
            .navigationDestination(isPresented: $showFlightAssist) {
                FlightAssistView()
                    .environmentObject(locationManager)
                    .environmentObject(settings)
            }
    }

    private var baseView: some View {
        ZStack { mainContent }
            .navigationTitle("GPS Logger")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: assistButton, trailing: settingsButton)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                locationManager.startUpdatingForDisplay()
                altitudeFusionManager.startUpdates(gpsAltitude: nil)
            }
            .onReceive(uiUpdateTimer) { _ in
                currentTime = Date()
            }
            .onReceive(locationManager.$windDirection) { new in
                windDirection = new
                if new != nil {
                    windBaseAltitude = locationManager.rawGpsAltitude
                }
            }
            .onReceive(locationManager.$windSpeed) { new in
                windSpeed = new
            }
            .onReceive(locationManager.$windSource) { new in
                windSource = new
            }
            .onReceive(locationManager.$pressureAltitudeFt) { new in
                pressureAltitude = new
                if let val = new {
                    pressureInput = Int(val)
                }
            }
    }

    @ViewBuilder
    private var compositeCameraView: some View {
        CompositeCameraView(capturedCompositeImage: $capturedCompositeImage,
                            settings: settings)
            .environmentObject(locationManager)
    }

    @ViewBuilder
    private var distanceGraphSheet: some View {
        if let measurement = lastMeasurement {
            NavigationStack {
                DistanceGraphView(logs: graphLogs, measurement: measurement)
                    .navigationBarItems(trailing: shareButton)
            }
        }
    }

    /// ナビゲーションバー左側のボタン
    private var assistButton: some View {
        Button {
            showFlightAssist = true
        } label: {
            Label("Assist", systemImage: "airplane")
        }
    }

    /// ナビゲーションバー右側のボタン
    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Label("設定", systemImage: "gearshape")
        }
    }

    /// グラフ表示画面の共有ボタン
    private var shareButton: some View {
        Group {
            if measurementLogURL != nil || measurementGraphURL != nil {
                Button {
                    shareItems.removeAll()
                    if let logURL = measurementLogURL {
                        shareItems.append(logURL)
                    }
                    if let graphURL = measurementGraphURL {
                        shareItems.append(graphURL)
                    }
                    showingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

}


// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
