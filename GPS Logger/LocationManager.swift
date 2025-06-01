import Foundation
import CoreLocation
import UIKit
import Combine

/// Handles location updates and recording of log entries and photos.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate, PressureAltitudeSource {
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

        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)

        settings.$logInterval
            .sink { [weak self] newInterval in
                guard let self else { return }
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

    func startRecording() {
        flightLogManager.startSession()
        isRecording = true

        rawGpsAltitude = 0.0
        rawGpsAltitudeChangeRate = 0.0
        previousRawAltitudeTimestamp = nil
        pressureAltitudeFt = nil

        logTimer = Timer.scheduledTimer(withTimeInterval: settings.logInterval, repeats: true) { [weak self] _ in
            self?.recordLog()
        }
    }

    func stopRecording() {
        isRecording = false
        logTimer?.invalidate()
        logTimer = nil
        altitudeFusionManager.stopUpdates()
    }

    func recordPhotoCapture() -> Int? {
        if !isRecording { return nil }
        photoCounter += 1
        pendingPhotoIndex = photoCounter
        return photoCounter
    }

    private func updateAltitude(with loc: CLLocation) {
        let altitudeFt = loc.altitude * 3.28084
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
        rawGpsAltitudeChangeRate = vspeed
        altitudeFusionManager.latestGpsAltitude = altitudeFt
        altitudeFusionManager.rawGpsVerticalSpeed = vspeed
        altitudeFusionManager.gpsVerticalAccuracy = loc.verticalAccuracy * 3.28084
        altitudeFusionManager.startUpdates(gpsAltitude: altitudeFt)
    }

    func recordLog() {
        guard let loc = lastLocation else { return }
        let altitudeFt = rawGpsAltitude
        let now = Date()

        let speedKt: Double? = {
            let spd = loc.speed
            return spd >= 0 ? spd * 1.94384 : nil
        }()
        let latestAcc = settings.recordAcceleration ? altitudeFusionManager.latestAcceleration : nil

        let log = FlightLog(timestamp: now,
                             gpsTimestamp: loc.timestamp,
                             latitude: loc.coordinate.latitude,
                             longitude: loc.coordinate.longitude,
                             gpsAltitude: altitudeFt,
                             speedKt: speedKt,
                             magneticCourse: loc.course,
                             horizontalAccuracyM: loc.horizontalAccuracy,
                             verticalAccuracyFt: loc.verticalAccuracy * 3.28084,
                             altimeterPressure: settings.recordAltimeterPressure ? altitudeFusionManager.altimeterPressure : nil,
                             rawGpsAltitudeChangeRate: settings.recordRawGpsRate ? rawGpsAltitudeChangeRate : nil,
                             relativeAltitude: settings.recordRelativeAltitude ? altitudeFusionManager.relativeAltitude : nil,
                             barometricAltitude: settings.recordBarometricAltitude ? altitudeFusionManager.baselineAltitude.map { $0 + (altitudeFusionManager.relativeAltitude ?? 0) } ?? altitudeFt : nil,
                             latestAcceleration: latestAcc,
                             fusedAltitude: settings.recordFusedAltitude ? (altitudeFusionManager.fusedAltitude ?? altitudeFt) : nil,
                             fusedAltitudeChangeRate: settings.recordFusedRate ? altitudeFusionManager.altitudeChangeRate : nil,
                             baselineAltitude: settings.recordBaselineAltitude ? altitudeFusionManager.baselineAltitude : nil,
                             measuredAltitude: settings.recordMeasuredAltitude ? altitudeFusionManager.measuredAltitude : nil,
                             kalmanUpdateInterval: settings.recordKalmanInterval ? altitudeFusionManager.kalmanUpdateInterval : nil,
                             estimatedOAT: estimatedOAT,
                             theoreticalCAS: theoreticalCAS,
                             theoreticalHP: theoreticalHP,
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
        DispatchQueue.main.async {
            self.lastLocation = latest
            self.updateAltitude(with: latest)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdatingForDisplay()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        locationManagerDidChangeAuthorization(manager)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 {
            declination = newHeading.trueHeading - newHeading.magneticHeading
        }
    }
}
