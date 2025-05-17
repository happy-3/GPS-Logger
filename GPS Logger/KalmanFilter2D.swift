import Foundation

/// Simple two dimensional Kalman filter for altitude and vertical speed.
final class KalmanFilter2D {
    var x: (Double, Double)             // (altitude, speed)
    private(set) var P: [[Double]]
    private var F: [[Double]]
    private var B: [Double]
    private let H: [Double] = [1, 0]
    private var Q: [[Double]]
    private var R: Double

    init(initialAltitude: Double, initialVelocity: Double, dt: Double, processNoise: Double, measurementNoise: Double) {
        x = (initialAltitude, initialVelocity)
        P = [[1, 0], [0, 1]]
        F = [[1, dt], [0, 1]]
        B = [0.5 * dt * dt, dt]
        Q = [[processNoise, 0], [0, processNoise]]
        R = measurementNoise
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
        let S = H[0]*P[0][0]*H[0] + H[0]*P[0][1]*H[1] + H[1]*P[1][0]*H[0] + H[1]*P[1][1]*H[1] + R

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

    func updateParameters(processNoise: Double, measurementNoise: Double) {
        Q = [[processNoise, 0], [0, processNoise]]
        R = measurementNoise
    }
}
