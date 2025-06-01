import Foundation

/// Flight Assist で利用する各種計算ユーティリティ。
enum FlightAssistUtils {
    /// TAS とマッハ数から外気温度 (℃) を求める。
    static func oat(tasMps: Double, mach: Double) -> Double {
        let gamma = 1.4
        let R = 287.0
        let tempK = (tasMps / mach) * (tasMps / mach) / (gamma * R)
        return tempK - 273.15
    }

    /// 正規分布乱数を生成する。
    static func randomNormal(mean: Double, sd: Double) -> Double {
        let u1 = Double.random(in: 0..<1)
        let u2 = Double.random(in: 0..<1)
        let z0 = sqrt(-2.0 * log(u1)) * cos(2 * .pi * u2)
        return z0 * sd + mean
    }

    /// 角度差を -180°...180° の範囲で返す。
    static func angleDifferenceDeg(_ a: Double, _ b: Double) -> Double {
        var diff = (a - b).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return diff
    }

    /// 角度配列の循環平均を求める。
    static func circularMeanDeg(_ values: [Double]) -> Double {
        let sumSin = values.map { sin($0 * .pi / 180) }.reduce(0, +)
        let sumCos = values.map { cos($0 * .pi / 180) }.reduce(0, +)
        guard sumSin != 0 || sumCos != 0 else { return 0 }
        var rad = atan2(sumSin, sumCos)
        if rad < 0 { rad += 2 * .pi }
        return rad * 180 / .pi
    }
}
