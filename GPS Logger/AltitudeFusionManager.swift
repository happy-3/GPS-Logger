import Foundation
import CoreMotion
import Combine

/// Combines barometric data, GPS altitude and user acceleration using Kalman filtering.
@MainActor
final class AltitudeFusionManager: ObservableObject {
    private let altimeter = CMAltimeter()
    private let motionManager = CMMotionManager()

    @Published var fusedAltitude: Double? = nil       // ft
    @Published var altitudeChangeRate: Double = 0.0   // ft/min
    @Published var baselineAltitude: Double? = nil
    @Published var relativeAltitude: Double? = nil
    @Published var latestAcceleration: Double = 0.0   // ft/s²
    @Published var measuredAltitude: Double? = nil
    @Published var kalmanUpdateInterval: Double? = nil
    @Published var gpsVerticalAccuracy: Double? = nil
    @Published var rawGpsVerticalSpeed: Double? = nil
    @Published var latestGpsAltitude: Double? = nil
    @Published var altimeterPressure: Double? = nil   // kPa

    private var kalmanFilter: KalmanFilter2D?
    private var lastKalmanUpdate: Date?
    private var lastMotionTimestamp: TimeInterval? = nil

    private let settings: Settings
    private var cancellables = Set<AnyCancellable>()

    init(settings: Settings) {
        self.settings = settings
        settings.$processNoise.combineLatest(settings.$measurementNoise)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] process, measure in
                guard let self, let filter = self.kalmanFilter else { return }
                filter.updateParameters(processNoise: process, measurementNoise: measure)
            }
            .store(in: &cancellables)

        settings.$useKalmanFilter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if !enabled {
                    self.kalmanFilter = nil
                    self.fusedAltitude = nil
                    self.altitudeChangeRate = self.rawGpsVerticalSpeed ?? 0.0
                }
            }
            .store(in: &cancellables)
    }

    /// Start sensor updates using initial GPS altitude if available.
    func startUpdates(gpsAltitude: Double?) {
        if let gpsAlt = gpsAltitude, baselineAltitude == nil {
            baselineAltitude = gpsAlt
        }
        latestGpsAltitude = gpsAltitude
        startAltimeterUpdates()
        startMotionUpdates()
    }

    /// Stop and reset sensors and filter.
    func stopUpdates() {
        altimeter.stopRelativeAltitudeUpdates()
        motionManager.stopDeviceMotionUpdates()
        DispatchQueue.main.async {
            self.fusedAltitude = nil
            self.baselineAltitude = nil
            self.relativeAltitude = nil
            self.latestGpsAltitude = nil
            self.latestAcceleration = 0.0
            self.altitudeChangeRate = 0.0
            self.kalmanFilter = nil
            self.lastKalmanUpdate = nil
            self.lastMotionTimestamp = nil
            self.altimeterPressure = nil
        }
    }

    private func startAltimeterUpdates() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            let relAltFt = data.relativeAltitude.doubleValue * 3.28084
            self.altimeterPressure = data.pressure.doubleValue
            self.relativeAltitude = relAltFt
            if let baseline = self.baselineAltitude {
                let barometricAltitude = baseline + relAltFt
                self.updateFusion(gpsAltitude: self.latestGpsAltitude, baroAltitude: barometricAltitude)
            }
        }
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            let currentTimestamp = motion.timestamp
            var dt = 0.1
            if let last = self.lastMotionTimestamp { dt = currentTimestamp - last }
            self.lastMotionTimestamp = currentTimestamp

            let a = motion.userAcceleration
            let Rm = motion.attitude.rotationMatrix
            let az = -(Rm.m31 * a.x + Rm.m32 * a.y + Rm.m33 * a.z)
            self.latestAcceleration = az * 3.28084

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
        if let gpsVertAcc = gpsVerticalAccuracy {
            let threshold = 2.0 * gpsVertAcc
            let difference = abs(weightedGps - baroAltitude)
            if difference > threshold {
                measuredAltitude = weightedGps
            } else {
                measuredAltitude = settings.baroWeight * baroAltitude + (1 - settings.baroWeight) * weightedGps
            }
        } else {
            measuredAltitude = settings.baroWeight * baroAltitude + (1 - settings.baroWeight) * weightedGps
        }
        self.measuredAltitude = measuredAltitude

        guard settings.useKalmanFilter else {
            kalmanFilter = nil
            fusedAltitude = nil
            altitudeChangeRate = rawGpsVerticalSpeed ?? 0.0
            kalmanUpdateInterval = nil
            lastKalmanUpdate = nil
            return
        }

        let now = Date()
        var dt = 0.1
        if let lastUpdate = lastKalmanUpdate { dt = now.timeIntervalSince(lastUpdate) }
        kalmanUpdateInterval = dt
        lastKalmanUpdate = now

        if kalmanFilter == nil {
            kalmanFilter = KalmanFilter2D(initialAltitude: measuredAltitude,
                                          initialVelocity: 0.0,
                                          dt: dt,
                                          processNoise: settings.processNoise,
                                          measurementNoise: settings.measurementNoise)
        } else {
            kalmanFilter?.updateTime(dt: dt)
        }

        kalmanFilter?.update(z: measuredAltitude)
        kalmanFilter?.updateParameters(processNoise: settings.processNoise, measurementNoise: settings.measurementNoise)

        if let filter = kalmanFilter {
            fusedAltitude = filter.x.0
            altitudeChangeRate = filter.x.1 * 60.0
            if let gpsVerticalSpeed = rawGpsVerticalSpeed, let gpsVertAcc = gpsVerticalAccuracy {
                let filterVerticalSpeed = filter.x.1 * 60.0
                let thresholdSpeed = 2.0 * gpsVertAcc
                if abs(filterVerticalSpeed - gpsVerticalSpeed) > thresholdSpeed {
                    filter.x.1 = gpsVerticalSpeed / 60.0
                    altitudeChangeRate = gpsVerticalSpeed
                }
            }
        }
    }

    /// 現在の基準高度と相対高度から計算される気圧高度(ft)
    var pressureAltitudeFt: Double? {
        baselineAltitude.map { $0 + (relativeAltitude ?? 0) }
    }
}
