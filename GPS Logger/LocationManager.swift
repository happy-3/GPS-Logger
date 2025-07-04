import Foundation
import CoreLocation
import UIKit
import Combine

/// Handles location updates and recording of log entries and photos.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate, PressureAltitudeSource {
    private let locationManager = CLLocationManager()

    let flightLogManager: FlightLogManager
    let settings: Settings

    @Published var lastLocation: CLLocation?
    @Published var isRecording = false

    @Published var rawGpsAltitude: Double = 0.0
    @Published var rawGpsAltitudeChangeRate: Double = 0.0
    private var previousRawAltitudeTimestamp: Date?

    @Published var rawEllipsoidalAltitude: Double = 0.0

    @Published var declination: Double = 0.0
    @Published var lastHeading: CLHeading?

    private var declinationLocation: CLLocation?
    private var declinationTimestamp: Date?

    var photoCounter: Int = 0
    var pendingPhotoIndex: Int? = nil
    var logTimer: Timer?

    /// 手動または計測による風向・風速
    @Published var windDirection: Double?
    @Published var windSpeed: Double?
    @Published var windSource: String?
    @Published var windDirectionCI: Double?
    @Published var windSpeedCI: Double?

    /// 手動入力による気圧高度(ft)
    @Published var pressureAltitudeFt: Double?

    /// 推算結果
    @Published var estimatedOAT: Double?
    @Published var theoreticalCAS: Double?
    @Published var theoreticalHP: Double?
    @Published var estimatedMach: Double?

    private var cancellables = Set<AnyCancellable>()

    @MainActor
    init(flightLogManager: FlightLogManager,
         settings: Settings) {
        self.flightLogManager = flightLogManager
        self.settings = settings
        super.init()

        // 保存された磁気偏差情報を復元
        self.declination = settings.lastDeclination
        if let data = settings.declinationLocation,
           let savedLoc = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CLLocation.self, from: data) {
            self.declinationLocation = savedLoc
        }
        self.declinationTimestamp = settings.declinationTimestamp

        UIDevice.current.isBatteryMonitoringEnabled = true
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestAlwaysAuthorization()

        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)

        settings.$logInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newInterval in
                guard let self else { return }
                if self.isRecording {
                    self.logTimer?.invalidate()
                    self.logTimer = Timer.scheduledTimer(timeInterval: newInterval,
                                                         target: self,
                                                         selector: #selector(handleLogTimer),
                                                         userInfo: nil,
                                                         repeats: true)
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
        }
    }

    @objc private func willEnterForeground() {
        startUpdatingForDisplay()
    }

    func startUpdatingForDisplay() {
        locationManager.startUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    @MainActor func startRecording() {
        flightLogManager.startSession()
        isRecording = true

        rawGpsAltitude = 0.0
        rawGpsAltitudeChangeRate = 0.0
        rawEllipsoidalAltitude = 0.0
        previousRawAltitudeTimestamp = nil
        pressureAltitudeFt = nil

        logTimer = Timer.scheduledTimer(timeInterval: settings.logInterval,
                                        target: self,
                                        selector: #selector(handleLogTimer),
                                        userInfo: nil,
                                        repeats: true)
    }

    @MainActor @objc private func handleLogTimer() {
        recordLog()
    }

    @MainActor func stopRecording() {
        isRecording = false
        logTimer?.invalidate()
        logTimer = nil
        // no sensor updates to stop
    }

    @MainActor func recordPhotoCapture() -> Int? {
        if !isRecording { return nil }
        photoCounter += 1
        pendingPhotoIndex = photoCounter
        return photoCounter
    }

    @MainActor private func updateAltitude(with loc: CLLocation) {
        let altitudeFt = loc.altitude * 3.28084
        let ellipsoidFt = loc.ellipsoidalAltitude * 3.28084
        let now = Date()
        var vspeed = rawGpsAltitudeChangeRate
        if let prevTimestamp = previousRawAltitudeTimestamp {
            let dt = now.timeIntervalSince(prevTimestamp)
            if dt > 0 {
                let change = altitudeFt - rawGpsAltitude
                vspeed = change / dt * 60
            }
        }
        previousRawAltitudeTimestamp = now
        rawGpsAltitude = altitudeFt
        rawEllipsoidalAltitude = ellipsoidFt
        rawGpsAltitudeChangeRate = vspeed
    }

    @MainActor func recordLog() {
        guard let loc = lastLocation else { return }
        let altitudeFt = rawGpsAltitude
        let now = Date()

        let speedKt: Double? = {
            let spd = loc.speed
            return spd >= 0 ? spd * 1.94384 : nil
        }()
        let log = FlightLog(timestamp: now,
                             gpsTimestamp: loc.timestamp,
                             latitude: loc.coordinate.latitude,
                             longitude: loc.coordinate.longitude,
                             gpsAltitude: altitudeFt,
                             ellipsoidalAltitude: settings.recordEllipsoidalAltitude ? rawEllipsoidalAltitude : nil,
                             speedKt: speedKt,
                             trueCourse: loc.course,
                             magneticVariation: declination,
                             horizontalAccuracyM: loc.horizontalAccuracy,
                             verticalAccuracyFt: loc.verticalAccuracy * 3.28084,
                             rawGpsAltitudeChangeRate: settings.recordRawGpsRate ? rawGpsAltitudeChangeRate : nil,
                             estimatedOAT: estimatedOAT,
                             theoreticalCAS: theoreticalCAS,
                             theoreticalHP: theoreticalHP,
                             estimatedMach: estimatedMach,
                             deltaCAS: nil,
                             deltaHP: nil,
                             windDirection: windDirection,
                             windSpeed: windSpeed,
                             windSource: windSource,
                             windDirectionCI: windDirectionCI,
                             windSpeedCI: windSpeedCI,
                             photoIndex: pendingPhotoIndex)
        pendingPhotoIndex = nil
        flightLogManager.addLog(log)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = latest
            self.updateAltitude(with: latest)
            self.updateDeclinationIfNeeded(with: latest)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            Task { @MainActor in
                startUpdatingForDisplay()
            }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        locationManagerDidChangeAuthorization(manager)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.lastHeading = newHeading
        }
    }

    @MainActor
    private func updateDeclinationIfNeeded(with loc: CLLocation) {
        let distanceThreshold: CLLocationDistance = 50_000
        let timeThreshold: TimeInterval = 21_600  // 6 時間

        var needUpdate = false
        if let prevLoc = declinationLocation,
           let prevTime = declinationTimestamp {
            let distance = loc.distance(from: prevLoc)
            let age = Date().timeIntervalSince(prevTime)
            if distance > distanceThreshold || age > timeThreshold {
                needUpdate = true
            }
        } else {
            needUpdate = true
        }

        if needUpdate {
            declination = MagneticVariation.declination(at: loc.coordinate)
            declinationLocation = loc
            declinationTimestamp = Date()
            settings.lastDeclination = declination
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: loc, requiringSecureCoding: true) {
                settings.declinationLocation = data
            } else {
                settings.declinationLocation = nil
            }
            settings.declinationTimestamp = declinationTimestamp
        }
    }
}
