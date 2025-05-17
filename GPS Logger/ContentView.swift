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
    @StateObject var flightLogManager = FlightLogManager()
    @StateObject var altitudeFusionManager: AltitudeFusionManager
    @StateObject var locationManager: LocationManager
    
    @State private var currentTime = Date()
    @State private var capturedCompositeImage: UIImage?
    @State private var capturedOverlayText: String = ""
    @State private var showingCompositeCamera = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []

    @State private var measuringDistance = false
    @State private var measurementStart: Date?
    @State private var measurementResultMessage: String?
    @State private var showingMeasurementAlert = false
    
    // UI表示用のサンプルデータ
    @State var gpsTime: String = "12:34:56"
    @State var isGPSAvailable: Bool = true
    @State var magneticHeading: Double = 123.45
    @State var speed: Double = 50.0
    @State var altitude: Double = 5000.0
    @State var altitudeChangeRate: Double = 20.0
    @State var latitude: Double = 35.6895
    @State var longitude: Double = 139.6917

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
    
    let jstFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f
    }()
    
    let uiUpdateTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    init() {
        // 初期化順序に注意
        let settings = Settings()
        let flightLogManager = FlightLogManager()
        let altitudeFusionManager = AltitudeFusionManager(settings: settings)
        let locationManager = LocationManager(flightLogManager: flightLogManager,
                                              altitudeFusionManager: altitudeFusionManager,
                                              settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _flightLogManager = StateObject(wrappedValue: flightLogManager)
        _altitudeFusionManager = StateObject(wrappedValue: altitudeFusionManager)
        _locationManager = StateObject(wrappedValue: locationManager)
    }
    
    var body: some View {
        NavigationView {
                VStack(spacing: 40) {
                    Text("現在時刻 (JST): \(currentTime, formatter: jstFormatter)")
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
                            Text("GPS受信時刻 (JST): \(loc.timestamp, formatter: jstFormatter)")
                            Text("緯度: \(loc.coordinate.latitude.toDegMin())  経度: \(loc.coordinate.longitude.toDegMin())").padding(.top, 4)
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
                    
                    if locationManager.isRecording {
                        HStack(spacing: 40) {
                            Button("記録停止") {
                                locationManager.stopRecording()
                                if let csvURL = flightLogManager.exportCSV() {
                                    shareItems = [csvURL]
                                    showingShareSheet = true
                                }
                                flightLogManager.endSession()
                            }
                            .font(.title2)
                            .frame(width: 150, height: 60)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(15)

                            Button(measuringDistance ? "距離計測終了" : "距離計測開始") {
                                if measuringDistance {
                                    let now = Date()
                                    if let result = flightLogManager.finishMeasurement(at: now) {
                                        measurementResultMessage = String(format: "水平距離: %.1f m\n3D距離: %.1f m", result.horizontalDistance, result.totalDistance)
                                    } else {
                                        measurementResultMessage = "計測に失敗しました"
                                    }
                                    showingMeasurementAlert = true
                                    measuringDistance = false
                                    measurementStart = nil
                                } else {
                                    let start = Date()
                                    measurementStart = start
                                    flightLogManager.startMeasurement(at: start)
                                    measuringDistance = true
                                }
                            }
                            .font(.title2)
                            .frame(width: 160, height: 60)
                            .background(measuringDistance ? Color.blue : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(15)

                            Button("静止画撮影") {
                                showingCompositeCamera = true
                            }
                            .font(.title2)
                            .frame(width: 160, height: 60)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                        }
                    } else {
                        Button("記録開始") {
                            locationManager.startRecording()
                        }
                        .font(.title2)
                        .frame(width: 150, height: 60)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                    }
                    
//                    if let compositeImage = capturedCompositeImage {
//                        Button(action: {
//                            // 画像プレビュー表示
//                            showingCompositeCamera = false
//                        }) {
//                            Image(uiImage: compositeImage)
//                                .resizable()
//                                .scaledToFit()
//                                .frame(height: 200)
//                        }
//                        .sheet(isPresented: Binding(
//                            get: { capturedCompositeImage != nil },
//                            set: { newValue in
//                                if !newValue { capturedCompositeImage = nil }
//                            }
//                        ), onDismiss: {
//                            capturedCompositeImage = nil
//                        }) {
//                            if let compositeImage = capturedCompositeImage {
//                                ImagePreviewView(image: compositeImage,
//                                                 overlayText: capturedOverlayText)
//                            }
//                        }
//                    }
                    
                    if !flightLogManager.distanceMeasurements.isEmpty {
                        VStack(alignment: .leading) {
                            Text("距離計測ログ:")
                                .font(.headline)
                            ForEach(Array(flightLogManager.distanceMeasurements.enumerated()), id: \.offset) { index, m in
                                Text(String(format: "#%d 水平: %.1f m 3D: %.1f m", index + 1, m.horizontalDistance, m.totalDistance))
                                    .font(.footnote)
                                    .padding(.leading, 8)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView(settings: settings)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                locationManager.startUpdatingForDisplay()
                altitudeFusionManager.startUpdates(gpsAltitude: nil)
            }
            .onReceive(uiUpdateTimer) { _ in
                currentTime = Date()
            }
            .fullScreenCover(isPresented: $showingCompositeCamera) {
                CompositeCameraView(capturedCompositeImage: $capturedCompositeImage,
                                    capturedOverlayText: $capturedOverlayText)
                    .environmentObject(locationManager)
            }
            .sheet(isPresented: $showingShareSheet) {
                ActivityView(activityItems: shareItems)
            }
            .alert(measurementResultMessage ?? "", isPresented: $showingMeasurementAlert) {
                Button("OK", role: .cancel) {}
            }
        }
    }
    
    func elapsedTimeString(from start: Date) -> String {
        let elapsed = Date().timeIntervalSince(start)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }


// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
