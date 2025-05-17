import SwiftUI
import CoreLocation
import CoreMotion
import AVFoundation
import UIKit
import Combine

// MARK: - Settings: 各種設定を管理するObservableObject
class Settings: ObservableObject {
    @Published var processNoise: Double {
        didSet {
            UserDefaults.standard.set(processNoise, forKey: "processNoise")
        }
    }
    @Published var measurementNoise: Double {
        didSet {
            UserDefaults.standard.set(measurementNoise, forKey: "measurementNoise")
        }
    }
    @Published var logInterval: Double {
        didSet {
            UserDefaults.standard.set(logInterval, forKey: "logInterval")
        }
    }
    @Published var baroWeight: Double {
        didSet {
            UserDefaults.standard.set(baroWeight, forKey: "baroWeight")
        }
    }
    
    init() {
        self.processNoise = UserDefaults.standard.object(forKey: "processNoise") as? Double ?? 0.2
        self.measurementNoise = UserDefaults.standard.object(forKey: "measurementNoise") as? Double ?? 15.0
        self.logInterval = UserDefaults.standard.object(forKey: "logInterval") as? Double ?? 1.0
        self.baroWeight = UserDefaults.standard.object(forKey: "baroWeight") as? Double ?? 0.75
    }
}

// MARK: - Utilities
extension Double {
    /// 小数点表記の座標を度・分表記に変換する
    func toDegMin() -> String {
        let degrees = Int(self)
        let minutes = (self - Double(degrees)) * 60
        return "\(degrees)°\(String(format: "%.5f", minutes))'"
    }
}

// MARK: - FlightLog Model
struct FlightLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    
    // GPS関連データ
    let gpsAltitude: Double            // ft
    let speedKt: Double                // ノット
    let magneticCourse: Double         // 測定不能時は -1
    let horizontalAccuracyM: Double    // m
    let verticalAccuracyFt: Double      // ft
    let altimeterPressure: Double?      // オプション
    
    // センサー／フュージョン関連データ
    let rawGpsAltitudeChangeRate: Double   // ft/min
    let relativeAltitude: Double           // ft
    let barometricAltitude: Double         // ft
    let latestAcceleration: Double         // ft/s²
    let fusedAltitude: Double              // ft
    let fusedAltitudeChangeRate: Double    // ft/min
    
    // ログ最適化用追加パラメータ
    let baselineAltitude: Double?          // ft（初期GPS高度）
    let measuredAltitude: Double?          // 加重測定高度
    let kalmanUpdateInterval: Double?      // dt（秒）
    
    // 撮影連番（撮影時のみ）
    let photoIndex: Int?
}

// MARK: - FlightLogManager
class FlightLogManager: ObservableObject {
    @Published var flightLogs: [FlightLog] = []
    var sessionFolderURL: URL?
    
    /// セッション開始：ログをクリアし新規フォルダを作成
    func startSession() {
        flightLogs.removeAll()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy_MM_dd_HHmmss"
        let startString = formatter.string(from: Date())
        let folderName = "FlightLog_\(startString)"
        
        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let folderURL = docsURL.appendingPathComponent(folderName)
            if !FileManager.default.fileExists(atPath: folderURL.path) {
                do {
                    try FileManager.default.createDirectory(at: folderURL,
                                                            withIntermediateDirectories: true,
                                                            attributes: nil)
                } catch {
                    print("Error creating session folder: \(error.localizedDescription)")
                }
            }
            sessionFolderURL = folderURL
        }
    }
    
    /// セッション終了
    func endSession() {
        sessionFolderURL = nil
    }
    
    /// ログを追加する
    func addLog(_ log: FlightLog) {
        flightLogs.append(log)
    }
    
    /// CSV出力（BOM付き）
    func exportCSV() -> URL? {
        guard let folderURL = sessionFolderURL else {
            print("Session folder URL not available")
            return nil
        }
        
        let fileName = "FlightLog_\(Int(Date().timeIntervalSince1970)).csv"
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        // CSVヘッダ
        var csvText = """
timestamp,latitude,longitude,gpsAltitude(ft),speed(kt),magneticCourse,horizontalAccuracy(ft),verticalAccuracy(ft),altimeterPressure,rawGpsAltitudeChangeRate(ft/min),relativeAltitude(ft),barometricAltitude(ft),latestAcceleration(ft/s²),fusedAltitude(ft),fusedAltitudeChangeRate(ft/min),baselineAltitude(ft),measuredAltitude(ft),kalmanUpdateInterval(s),photoIndex
"""
        csvText.append("\n")
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        
        for log in flightLogs {
            let ts = isoFormatter.string(from: log.timestamp)
            let photoIndexText = log.photoIndex != nil ? String(log.photoIndex!) : ""
            csvText.append("\(ts),\(log.latitude),\(log.longitude),\(log.gpsAltitude),\(log.speedKt),\(log.magneticCourse),\(log.horizontalAccuracyM),\(log.verticalAccuracyFt),\(log.altimeterPressure ?? 0),\(log.rawGpsAltitudeChangeRate),\(log.relativeAltitude),\(log.barometricAltitude),\(log.latestAcceleration),\(log.fusedAltitude),\(log.fusedAltitudeChangeRate),\(log.baselineAltitude ?? 0),\(log.measuredAltitude ?? 0),\(log.kalmanUpdateInterval ?? 0),\(photoIndexText)\n")
        }
        
        if let bom = "\u{FEFF}".data(using: .utf8),
           let csvData = csvText.data(using: .utf8) {
            var combinedData = Data()
            combinedData.append(bom)
            combinedData.append(csvData)
            do {
                try combinedData.write(to: fileURL, options: .atomic)
                return fileURL
            } catch {
                print("FlightLog CSV write error: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }
}

// MARK: - KalmanFilter2D (高度と垂直速度の2次元フィルタ)
class KalmanFilter2D {
    var x: (Double, Double)         // (高度, 速度)
    var P: [[Double]]
    var F: [[Double]]
    var B: [Double]
    let H: [Double] = [1, 0]
    var Q: [[Double]]
    var R: Double
    
    init(initialAltitude: Double,
         initialVelocity: Double,
         dt: Double,
         processNoise: Double,
         measurementNoise: Double) {
        
        self.x = (initialAltitude, initialVelocity)
        self.P = [[1, 0], [0, 1]]
        self.F = [[1, dt], [0, 1]]
        self.B = [0.5 * dt * dt, dt]
        self.Q = [[processNoise, 0], [0, processNoise]]
        self.R = measurementNoise
    }
    
    func updateTime(dt: Double) {
        F = [[1, dt], [0, 1]]
        B = [0.5 * dt * dt, dt]
    }
    
    func predict(u: Double) {
        let newAltitude = F[0][0] * x.0 + F[0][1] * x.1 + B[0] * u
        let newVelocity = F[1][0] * x.0 + F[1][1] * x.1 + B[1] * u
        x = (newAltitude, newVelocity)
        
        let p00 = F[0][0] * P[0][0] + F[0][1] * P[1][0]
        let p01 = F[0][0] * P[0][1] + F[0][1] * P[1][1]
        let p10 = F[1][0] * P[0][0] + F[1][1] * P[1][0]
        let p11 = F[1][0] * P[0][1] + F[1][1] * P[1][1]
        
        let PP00 = p00 * F[0][0] + p01 * F[0][1] + Q[0][0]
        let PP01 = p00 * F[1][0] + p01 * F[1][1] + Q[0][1]
        let PP10 = p10 * F[0][0] + p11 * F[0][1] + Q[1][0]
        let PP11 = p10 * F[1][0] + p11 * F[1][1] + Q[1][1]
        
        P = [[PP00, PP01], [PP10, PP11]]
    }
    
    func update(z: Double) {
        let y = z - (H[0] * x.0 + H[1] * x.1)
        let S = H[0]*P[0][0]*H[0] + H[0]*P[0][1]*H[1] +
                H[1]*P[1][0]*H[0] + H[1]*P[1][1]*H[1] + R
        
        let K0 = (P[0][0]*H[0] + P[0][1]*H[1]) / S
        let K1 = (P[1][0]*H[0] + P[1][1]*H[1]) / S
        
        x.0 += K0 * y
        x.1 += K1 * y
        
        let I_KH0 = 1 - K0 * H[0]
        let I_KH1 = -K0 * H[1]
        let I_KH2 = -K1 * H[0]
        let I_KH3 = 1 - K1 * H[1]
        
        let newP00 = I_KH0 * P[0][0] + I_KH1 * P[1][0]
        let newP01 = I_KH0 * P[0][1] + I_KH1 * P[1][1]
        let newP10 = I_KH2 * P[0][0] + I_KH3 * P[1][0]
        let newP11 = I_KH2 * P[0][1] + I_KH3 * P[1][1]
        P = [[newP00, newP01], [newP10, newP11]]
    }
    
    /// 設定値の変更に応じて、プロセスノイズ(Q)と測定ノイズ(R)を更新
    func updateParameters(processNoise: Double, measurementNoise: Double) {
        Q = [[processNoise, 0], [0, processNoise]]
        R = measurementNoise
    }
}

// MARK: - AltitudeFusionManager (センサーフュージョン＋Kalmanフィルタ)
class AltitudeFusionManager: ObservableObject {
    private let altimeter = CMAltimeter()
    private let motionManager = CMMotionManager()
    
    @Published var fusedAltitude: Double? = nil        // ft
    @Published var altitudeChangeRate: Double = 0.0      // ft/min
    @Published var baselineAltitude: Double? = nil
    @Published var relativeAltitude: Double? = nil
    @Published var latestAcceleration: Double = 0.0      // ft/s²
    @Published var measuredAltitude: Double? = nil
    @Published var kalmanUpdateInterval: Double? = nil
    @Published var gpsVerticalAccuracy: Double? = nil
    @Published var rawGpsVerticalSpeed: Double? = nil
    
    private var kalmanFilter: KalmanFilter2D?
    private var lastKalmanUpdate: Date?
    private var lastMotionTimestamp: TimeInterval? = nil
    
    
    // Settingsへの参照
    private var settings: Settings
    private var cancellables = Set<AnyCancellable>()
    
    init(settings: Settings) {
        self.settings = settings
        
        // Settings の変更があった場合、フィルタパラメータを更新（既存フィルタがあれば）
        settings.$processNoise
            .combineLatest(settings.$measurementNoise)
            .sink { [weak self] newProcessNoise, newMeasurementNoise in
                guard let self = self else { return }
                if let filter = self.kalmanFilter {
                    filter.updateParameters(processNoise: newProcessNoise, measurementNoise: newMeasurementNoise)
                }
            }
            .store(in: &cancellables)
    }
    
    /// センサ更新開始（オプションの初期GPS高度を利用）
    func startUpdates(gpsAltitude: Double?) {
        if let gpsAlt = gpsAltitude, baselineAltitude == nil {
            baselineAltitude = gpsAlt
        }
        startAltimeterUpdates(gpsAltitude: gpsAltitude)
        startMotionUpdates()
    }
    
    /// センサ更新停止・初期化
    func stopUpdates() {
        altimeter.stopRelativeAltitudeUpdates()
        motionManager.stopDeviceMotionUpdates()
        DispatchQueue.main.async {
            self.fusedAltitude = nil
            self.baselineAltitude = nil
            self.relativeAltitude = nil
            self.latestAcceleration = 0.0
            self.altitudeChangeRate = 0.0
            self.kalmanFilter = nil
            self.lastKalmanUpdate = nil
            self.lastMotionTimestamp = nil
        }
    }
    
    private func startAltimeterUpdates(gpsAltitude: Double?) {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            print("CMAltimeter is not available")
            return
        }
        altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { [weak self] data, error in
            guard let self = self, let data = data, error == nil else {
                print("Altimeter error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            let relAltFt = data.relativeAltitude.doubleValue * 3.28084
            self.relativeAltitude = relAltFt
            if let baseline = self.baselineAltitude {
                let barometricAltitude = baseline + relAltFt
                self.updateFusion(gpsAltitude: gpsAltitude, baroAltitude: barometricAltitude)
            }
        }
    }
    
    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion is not available")
            return
        }
        motionManager.deviceMotionUpdateInterval = 0.1 // 高頻度更新
        motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else {
                print("Device motion error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            let currentTimestamp = motion.timestamp
            var dt: Double = 0.1
            if let last = self.lastMotionTimestamp {
                dt = currentTimestamp - last
            }
            self.lastMotionTimestamp = currentTimestamp

            let a = motion.userAcceleration
            let Rm = motion.attitude.rotationMatrix
            let az = -(Rm.m31 * a.x + Rm.m32 * a.y + Rm.m33 * a.z)
            self.latestAcceleration = az * 3.28084 // m/s² → ft/s²

            if let filter = self.kalmanFilter {
                filter.updateTime(dt: dt)
                filter.predict(u: self.latestAcceleration)
                self.fusedAltitude = filter.x.0
                self.altitudeChangeRate = filter.x.1 * 60.0
            }
        }
    }
    
    private func updateFusion(gpsAltitude: Double?, baroAltitude: Double) {
        let weightedGps = gpsAltitude ?? baroAltitude
        let measuredAltitude: Double
        if let gpsVertAcc = self.gpsVerticalAccuracy {
            let threshold = 2.0 * gpsVertAcc
            let difference = abs(weightedGps - baroAltitude)
            if difference > threshold {
                measuredAltitude = weightedGps
            } else {
                measuredAltitude = self.settings.baroWeight * baroAltitude + (1 - self.settings.baroWeight) * weightedGps
            }
        } else {
            measuredAltitude = self.settings.baroWeight * baroAltitude + (1 - self.settings.baroWeight) * weightedGps
        }
        self.measuredAltitude = measuredAltitude

        let now = Date()
        var dt: Double = 0.1
        if let lastUpdate = self.lastKalmanUpdate {
            dt = now.timeIntervalSince(lastUpdate)
        }
        self.kalmanUpdateInterval = dt
        self.lastKalmanUpdate = now

        if self.kalmanFilter == nil {
            self.kalmanFilter = KalmanFilter2D(
                initialAltitude: measuredAltitude,
                initialVelocity: 0.0,
                dt: dt,
                processNoise: settings.processNoise,
                measurementNoise: settings.measurementNoise
            )
        } else {
            self.kalmanFilter?.updateTime(dt: dt)
        }

        self.kalmanFilter?.update(z: measuredAltitude)
        self.kalmanFilter?.updateParameters(processNoise: settings.processNoise, measurementNoise: settings.measurementNoise)

        if let filter = self.kalmanFilter {
            self.fusedAltitude = filter.x.0
            self.altitudeChangeRate = filter.x.1 * 60.0

            // Vertical speed fusion: if the difference between the filter's vertical speed and GPS vertical speed exceeds threshold
            if let gpsVerticalSpeed = self.rawGpsVerticalSpeed, let gpsVertAcc = self.gpsVerticalAccuracy {
                let filterVerticalSpeed = filter.x.1 * 60.0
                let thresholdSpeed = 2.0 * gpsVertAcc
                if abs(filterVerticalSpeed - gpsVerticalSpeed) > thresholdSpeed {
                    filter.x.1 = gpsVerticalSpeed / 60.0
                    self.altitudeChangeRate = gpsVerticalSpeed
                }
            }
        }
    }
}

// MARK: - LocationManager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    let flightLogManager: FlightLogManager
    private let altitudeFusionManager: AltitudeFusionManager
    let settings: Settings
    
    @Published var lastLocation: CLLocation?
    @Published var isRecording = false
    
    @Published var rawGpsAltitude: Double = 0.0
    @Published var rawGpsAltitudeChangeRate: Double = 0.0
    private var previousRawAltitudeTimestamp: Date?
    
    @Published var declination: Double = 0.0
    
    var photoCounter: Int = 0
    var pendingPhotoIndex: Int? = nil
    var logTimer: Timer?
    
    private var cancellables = Set<AnyCancellable>()
    
    init(flightLogManager: FlightLogManager,
         altitudeFusionManager: AltitudeFusionManager,
         settings: Settings) {
        self.flightLogManager = flightLogManager
        self.altitudeFusionManager = altitudeFusionManager
        self.settings = settings
        super.init()
        
        UIDevice.current.isBatteryMonitoringEnabled = true
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestAlwaysAuthorization()
        
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(willEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        
        // Settings の logInterval の変更を監視し、タイマーの再設定を実施
        settings.$logInterval
            .sink { [weak self] newInterval in
                guard let self = self else { return }
                if self.isRecording {
                    self.logTimer?.invalidate()
                    self.logTimer = Timer.scheduledTimer(withTimeInterval: newInterval, repeats: true) { [weak self] _ in
                        self?.recordLog()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func didEnterBackground() {
        if !isRecording {
            locationManager.stopUpdatingLocation()
            print("バックグラウンドに入り、記録中でないため位置情報更新を停止")
        }
    }
    
    @objc private func willEnterForeground() {
        startUpdatingForDisplay()
        print("フォアグラウンドに復帰、位置情報更新を再開")
    }
    
    func startUpdatingForDisplay() {
        locationManager.startUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    func startRecording() {
        flightLogManager.startSession()
        isRecording = true
        
        rawGpsAltitude = 0.0
        rawGpsAltitudeChangeRate = 0.0
        previousRawAltitudeTimestamp = nil
        
        // settings.logInterval を用いてタイマー開始
        logTimer = Timer.scheduledTimer(withTimeInterval: settings.logInterval, repeats: true) { [weak self] _ in
            self?.recordLog()
        }
    }
    
    func stopRecording() {
        isRecording = false
        logTimer?.invalidate()
        logTimer = nil
        // センサフュージョンは引き続き更新（表示用）
    }
    
    func recordPhotoCapture() -> Int? {
        guard lastLocation != nil else { return nil }
        photoCounter += 1
        pendingPhotoIndex = photoCounter
        return photoCounter
    }
    
    // MARK: - CLLocationManagerDelegate Methods
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        
        let currentAltitude = location.altitude * 3.28084
        if let prevTime = previousRawAltitudeTimestamp, rawGpsAltitude != 0.0 {
            let deltaTime = Date().timeIntervalSince(prevTime)
            if deltaTime > 0 {
                rawGpsAltitudeChangeRate = (currentAltitude - rawGpsAltitude) / (deltaTime / 60.0)
            }
        }
        rawGpsAltitude = currentAltitude
        previousRawAltitudeTimestamp = Date()
        
        // Update fusion manager with GPS vertical accuracy and vertical speed
        altitudeFusionManager.gpsVerticalAccuracy = location.verticalAccuracy * 3.28084
        altitudeFusionManager.rawGpsVerticalSpeed = rawGpsAltitudeChangeRate
        
        if altitudeFusionManager.baselineAltitude == nil {
            altitudeFusionManager.baselineAltitude = currentAltitude
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.trueHeading >= 0 {
            declination = newHeading.trueHeading - newHeading.magneticHeading
        } else {
            declination = 0.0
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("GPS Error: \(error.localizedDescription)")
    }
    
    /// 最新の位置情報とセンサデータからログを記録
    func recordLog() {
        guard let loc = lastLocation else { return }
        let currentAltitude = loc.altitude * 3.28084
        if altitudeFusionManager.baselineAltitude == nil {
            altitudeFusionManager.baselineAltitude = currentAltitude
        }
        
        let fusedAlt = altitudeFusionManager.fusedAltitude ?? currentAltitude
        let fusedRate = altitudeFusionManager.altitudeChangeRate
        let relAlt = altitudeFusionManager.relativeAltitude ?? 0.0
        let baseAlt = altitudeFusionManager.baselineAltitude ?? currentAltitude
        let speedKt = loc.speed * 1.94384
        let hAcc = loc.horizontalAccuracy
        let vAcc = loc.verticalAccuracy * 3.28084
        
        let magCourse: Double = {
            if loc.course < 0 {
                return -1
            } else {
                var mc = loc.course - declination
                mc = mc.truncatingRemainder(dividingBy: 360)
                if mc < 0 { mc += 360 }
                return mc
            }
        }()
        
        let photoIndexToLog = pendingPhotoIndex
        pendingPhotoIndex = nil
        
        let newLog = FlightLog(
            timestamp: loc.timestamp,
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            gpsAltitude: currentAltitude,
            speedKt: speedKt,
            magneticCourse: magCourse,
            horizontalAccuracyM: hAcc,
            verticalAccuracyFt: vAcc,
            altimeterPressure: nil,
            rawGpsAltitudeChangeRate: rawGpsAltitudeChangeRate,
            relativeAltitude: relAlt,
            barometricAltitude: baseAlt + relAlt,
            latestAcceleration: altitudeFusionManager.latestAcceleration,
            fusedAltitude: fusedAlt,
            fusedAltitudeChangeRate: fusedRate,
            baselineAltitude: altitudeFusionManager.baselineAltitude,
            measuredAltitude: altitudeFusionManager.measuredAltitude,
            kalmanUpdateInterval: altitudeFusionManager.kalmanUpdateInterval,
            photoIndex: photoIndexToLog
        )
        flightLogManager.addLog(newLog)
    }
}

// MARK: - CompositeCameraView（静止画撮影・オーバーレイ合成）
struct CompositeCameraView: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var locationManager: LocationManager
    
    @Binding var capturedCompositeImage: UIImage?
    @Binding var capturedOverlayText: String
    
    class Coordinator: NSObject, AVCapturePhotoCaptureDelegate {
        var parent: CompositeCameraView
        var captureSession: AVCaptureSession!
        var previewLayer: AVCaptureVideoPreviewLayer!
        var photoOutput: AVCapturePhotoOutput!
        var overlayLabel: UILabel!
        var updateTimer: Timer?
        
        init(_ parent: CompositeCameraView) {
            self.parent = parent
            super.init()
            setupSession()
        }
        
        func setupSession() {
            captureSession = AVCaptureSession()
            captureSession.sessionPreset = .photo
            
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                            for: .video,
                                                            position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
                print("カメラデバイスの取得に失敗")
                return
            }
            do {
                try videoDevice.lockForConfiguration()
                if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                    videoDevice.focusMode = .continuousAutoFocus
                }
                videoDevice.unlockForConfiguration()
            } catch {
                print("Failed to set autofocus: \(error.localizedDescription)")
            }
            
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            photoOutput = AVCapturePhotoOutput()
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspect
            captureSession.startRunning()
        }
        
        func currentOverlayText(photoIndex: Int? = nil) -> String {
            let photoText = "Photo Index: \(photoIndex != nil ? String(photoIndex!) : "Pending")"
            if let loc = parent.locationManager.lastLocation {
                let magneticText: String = {
                    if loc.course < 0 {
                        return "未計測"
                    } else {
                        var mc = loc.course - parent.locationManager.declination
                        mc = mc.truncatingRemainder(dividingBy: 360)
                        if mc < 0 { mc += 360 }
                        return String(format: "%.2f°", mc)
                    }
                }()
                let speedKnots = loc.speed * 1.94384
                let altitudeFt = loc.altitude * 3.28084
                let verticalAccuracyFt = loc.verticalAccuracy * 3.28084
                return """
                \(photoText)
                磁方位: \(magneticText)
                速度: \(String(format: "%.2f kt", speedKnots))
                高度: \(String(format: "%.2f ft", altitudeFt))
                垂直誤差: \(String(format: "±%.2f ft", verticalAccuracyFt))
                """
            } else {
                return "\(photoText)\nGPSデータなし"
            }
        }
        
        func addOverlayToImage(image: UIImage, overlayText: String) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: image.size)
            let newImage = renderer.image { context in
                image.draw(in: CGRect(origin: .zero, size: image.size))
                
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .left
                let fontSize = image.size.width * 0.05
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: fontSize),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]
                
                let textPadding: CGFloat = 20
                let textHeight = image.size.height * 0.15
                let textRect = CGRect(x: textPadding,
                                      y: image.size.height - textHeight - textPadding,
                                      width: image.size.width - 2 * textPadding,
                                      height: textHeight)
                
                overlayText.draw(in: textRect, withAttributes: attributes)
            }
            return newImage
        }
        
        @objc func handleCaptureButton() {
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
        
        func photoOutput(_ output: AVCapturePhotoOutput,
                         didFinishProcessingPhoto photo: AVCapturePhoto,
                         error: Error?) {
            if let error = error {
                print("Error capturing photo: \(error.localizedDescription)")
                return
            }
            guard let imageData = photo.fileDataRepresentation(),
                  let uiImage = UIImage(data: imageData) else { return }
            
            let photoIndex = parent.locationManager.recordPhotoCapture() ?? 0
            let overlayText = currentOverlayText(photoIndex: photoIndex)
            parent.capturedOverlayText = overlayText
            
            // 合成画像の生成と保存
            let compositeImage = addOverlayToImage(image: uiImage, overlayText: overlayText)
            
            if let sessionFolderURL = parent.locationManager.flightLogManager.sessionFolderURL {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                let captureDateString = dateFormatter.string(from: Date())
                let fileName = "photo_\(photoIndex)_\(captureDateString).jpg"
                let fileURL = sessionFolderURL.appendingPathComponent(fileName)
                
                if let jpegData = compositeImage.jpegData(compressionQuality: 1.0) {
                    do {
                        try jpegData.write(to: fileURL, options: .atomic)
                        print("Composite Image saved to \(fileURL)")
                    } catch {
                        print("Failed to save composite image: \(error.localizedDescription)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.parent.capturedCompositeImage = compositeImage
                self.parent.presentationMode.wrappedValue.dismiss()
            }
        }
        
        @objc func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
            guard let device = AVCaptureDevice.default(for: .video) else { return }
            do {
                try device.lockForConfiguration()
                let newZoomFactor = device.videoZoomFactor * gesture.scale
                let maxZoomFactor = device.activeFormat.videoMaxZoomFactor
                device.videoZoomFactor = max(1.0, min(newZoomFactor, maxZoomFactor))
                device.unlockForConfiguration()
                gesture.scale = 1.0
            } catch {
                print("Error adjusting zoom: \(error.localizedDescription)")
            }
        }
        
        @objc func handleZoomIn() {
            guard let deviceInput = captureSession.inputs.first as? AVCaptureDeviceInput else { return }
            let device = deviceInput.device
            do {
                try device.lockForConfiguration()
                let newZoom = min(device.videoZoomFactor * 1.1, device.activeFormat.videoMaxZoomFactor)
                device.videoZoomFactor = newZoom
                device.unlockForConfiguration()
            } catch {
                print("Error zooming in: \(error)")
            }
        }
        
        @objc func handleZoomOut() {
            guard let deviceInput = captureSession.inputs.first as? AVCaptureDeviceInput else { return }
            let device = deviceInput.device
            do {
                try device.lockForConfiguration()
                let newZoom = max(device.videoZoomFactor / 1.1, 1.0)
                device.videoZoomFactor = newZoom
                device.unlockForConfiguration()
            } catch {
                print("Error zooming out: \(error)")
            }
        }
        
        deinit {
            updateTimer?.invalidate()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        context.coordinator.previewLayer.frame = controller.view.bounds
        context.coordinator.previewLayer.position = CGPoint(x: controller.view.bounds.midX,
                                                            y: controller.view.bounds.midY)
        controller.view.layer.addSublayer(context.coordinator.previewLayer)
        
        // オーバーレイラベルの作成と追加
        let overlayLabel = UILabel(frame: CGRect(x: 20,
                                                 y: controller.view.bounds.height - 150,
                                                 width: controller.view.bounds.width - 40,
                                                 height: 100))
        overlayLabel.textColor = .white
        overlayLabel.font = UIFont.boldSystemFont(ofSize: 24)
        overlayLabel.numberOfLines = 0
        overlayLabel.textAlignment = .left
        overlayLabel.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        overlayLabel.text = context.coordinator.currentOverlayText()
        controller.view.addSubview(overlayLabel)
        context.coordinator.overlayLabel = overlayLabel
        
        // 定期的にオーバーレイラベルを更新
        context.coordinator.updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            DispatchQueue.main.async {
                overlayLabel.text = context.coordinator.currentOverlayText()
            }
        }
        
        let captureButton = UIButton(type: .system)
        captureButton.frame = CGRect(x: (controller.view.bounds.width - 120) / 2,
                                     y: controller.view.bounds.height - 150,
                                     width: 120, height: 120)
        captureButton.layer.cornerRadius = 60
        captureButton.backgroundColor = UIColor.red.withAlphaComponent(0.7)
        captureButton.setTitle("撮影", for: .normal)
        captureButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 28)
        captureButton.setTitleColor(.white, for: .normal)
        captureButton.addTarget(context.coordinator,
                                action: #selector(Coordinator.handleCaptureButton),
                                for: .touchUpInside)
        controller.view.addSubview(captureButton)
        
        let zoomInButton = UIButton(type: .system)
        zoomInButton.frame = CGRect(x: controller.view.bounds.width - 80, y: 40,
                                    width: 60, height: 60)
        zoomInButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        zoomInButton.setTitle("+", for: .normal)
        zoomInButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 30)
        zoomInButton.setTitleColor(.white, for: .normal)
        zoomInButton.layer.cornerRadius = 30
        zoomInButton.addTarget(context.coordinator,
                               action: #selector(Coordinator.handleZoomIn),
                               for: .touchUpInside)
        controller.view.addSubview(zoomInButton)
        
        let zoomOutButton = UIButton(type: .system)
        zoomOutButton.frame = CGRect(x: 20, y: 40,
                                     width: 60, height: 60)
        zoomOutButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        zoomOutButton.setTitle("-", for: .normal)
        zoomOutButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 30)
        zoomOutButton.setTitleColor(.white, for: .normal)
        zoomOutButton.layer.cornerRadius = 30
        zoomOutButton.addTarget(context.coordinator,
                                action: #selector(Coordinator.handleZoomOut),
                                for: .touchUpInside)
        controller.view.addSubview(zoomOutButton)
        
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator,
                                                    action: #selector(Coordinator.handlePinchGesture(_:)))
        controller.view.addGestureRecognizer(pinchGesture)
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController,
                                context: Context) {
    }
}

// MARK: - ImagePreviewView
struct ImagePreviewView: View {
    var image: UIImage
    var overlayText: String
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.edgesIgnoringSafeArea(.all)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
            Text(overlayText)
                .font(.system(size: 20))
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.5))
                .padding()
        }
        .overlay(
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .padding()
                    .foregroundColor(.white)
            },
            alignment: .topTrailing
        )
    }
}

// MARK: - ActivityView (共有用)
struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems,
                                 applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController,
                                context: Context) {
    }
}

// MARK: - SettingsView
struct SettingsView: View {
    @ObservedObject var settings: Settings
    
    var body: some View {
        Form {
            Section(header: Text("カルマンフィルタ設定")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Process Noise")
                        Slider(value: $settings.processNoise, in: 0.0...1.0, step: 0.01)
                        Text(String(format: "%.2f", settings.processNoise))
                    }
                    Text("Process Noiseはフィルタの予測モデルにおける不確実性を示します。値が大きいと、変化に対して敏感になりますが、ノイズも増加します。")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    HStack {
                        Text("Measurement Noise")
                        Slider(value: $settings.measurementNoise, in: 1.0...50.0, step: 0.5)
                        Text(String(format: "%.1f", settings.measurementNoise))
                    }
                    Text("Measurement Noiseはセンサーの測定誤差を表します。値が大きいと、センサーデータの影響が減り、予測に依存します。")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                HStack {
                    Text("気圧高度")
                    Slider(value: $settings.baroWeight, in: 0.0...1.0, step: 0.25)
                    Text("GPS高度")
                }
                HStack {
                    Spacer()
                    Text(String(format: "%.0f%%", settings.baroWeight * 100))
                    Spacer()
                }
                Text("スライダーの左側は気圧高度、右側はGPS高度に対応します。")
                    .font(.caption)
                    .foregroundColor(.gray)
                }
            }
            Section(header: Text("ログ設定")) {
                Picker("ログ周期", selection: $settings.logInterval) {
                    Text("1Hz").tag(1.0)
                    Text("2Hz").tag(0.5)
                    Text("5Hz").tag(0.2)
                    Text("10Hz").tag(0.1)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }
        .navigationTitle("設定")
    }
}

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
    
    // UI表示用のサンプルデータ
    @State var gpsTime: String = "12:34:56"
    @State var isGPSAvailable: Bool = true
    @State var magneticHeading: Double = 123.45
    @State var speed: Double = 50.0
    @State var altitude: Double = 5000.0
    @State var altitudeChangeRate: Double = 20.0
    @State var verticalError: Double = 15.0
    @State var latitude: Double = 35.6895
    @State var longitude: Double = 139.6917
    
    // 垂直誤差に基づく色分けの関数
    func verticalErrorColor() -> Color {
        switch verticalError {
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
                                return String(format: "%.2f°", mc)
                            }
                        }()
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("GPS受信時刻 (JST): \(loc.timestamp, formatter: jstFormatter)")
                            Text("緯度: \(loc.coordinate.latitude.toDegMin())  経度: \(loc.coordinate.longitude.toDegMin())").padding(.top, 4)
                            Text(String(format: "水平誤差: ±%.2f m", loc.horizontalAccuracy))
                            Text("磁方位: \(magneticText)").font(.title)
                            Text(String(format: "速度: %.2f kt", loc.speed * 1.94384)).font(.title)
                            Text(String(format: "GPS 高度: %.2f ft", locationManager.rawGpsAltitude)).font(.title).padding(.top, 40)
                            
                            if let fusedAlt = altitudeFusionManager.fusedAltitude {
                                Text(String(format: "高度 (Kalman): %.2f ft", fusedAlt))
                            } else {
                                Text(String(format: "高度: %.2f ft", loc.altitude * 3.28084))
                            }
                            Text(String(format: "垂直誤差: ±%.2f ft", loc.verticalAccuracy * 3.28084)).font(.title).padding(.bottom, 40)
                            Text(String(format: "GPS 高度変化率: %.2f ft/min", locationManager.rawGpsAltitudeChangeRate))

                            Text(String(format: "高度変化率 (Kalman): %.2f ft/min", altitudeFusionManager.altitudeChangeRate))


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
                            }
                            .font(.title2)
                            .frame(width: 150, height: 60)
                            .background(Color.red)
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
