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

    /// TAS(kt)と高度(ft)から外気温度(℃)を求める
    static func oat(tasKt: Double, altitudeFt: Double) -> Double {
        let tasMps = tasKt * 0.514444
        let tIsa = ISAAtmosphere.temperature(altitudeFt: altitudeFt) + 273.15
        let speedOfSound = sqrt(1.4 * 287.05 * tIsa)
        let mach = tasMps / speedOfSound
        return oat(tasMps: tasMps, mach: mach)
    }

    /// TAS(kt)と高度(ft)、外気温度(℃)からCAS(kt)を概算する
    static func cas(tasKt: Double, altitudeFt: Double, oatC: Double) -> Double {
        let tasMps = tasKt * 0.514444
        let pressure = ISAAtmosphere.pressure(altitudeFt: altitudeFt)
        let density = pressure / (287.05 * (oatC + 273.15))
        let eas = tasMps * sqrt(density / 1.225)
        return eas / 0.514444
    }

    /// 外気温度に基づく気圧高度を概算する。ここでは簡易的に幾何高度を返す
    static func pressureAltitude(altitudeFt: Double, oatC: Double) -> Double {
        // 実際の圧力値が不明なため、暫定的にGPS高度をそのまま用いる
        return altitudeFt
    }

    /// TAS, CAS, 気圧高度から外気温度(℃)を求める
    static func oat(tasKt: Double, casKt: Double, pressureAltitudeFt: Double) -> Double {
        let tas = tasKt * 0.514444
        let cas = casKt * 0.514444
        let hp  = pressureAltitudeFt * 0.3048

        let gamma = 1.4
        let R     = 287.053
        let g0    = 9.80665
        let T0    = 288.15
        let P0    = 101_325.0
        let L     = 0.0065
        let a0    = sqrt(gamma * R * T0)

        let tIsa  = T0 - L * hp
        let p     = P0 * pow(tIsa / T0, g0 / (R * L))
        let delta = p / P0

        let a2    = pow(cas / a0, 2)
        let term  = pow(1 + a2 / 5, 3.5) - 1
        let mach  = sqrt(5 * (pow(1 + term / delta, 2.0 / 7.0) - 1))

        let tempK = tas * tas / (gamma * R * mach * mach)
        return tempK - 273.15
    }
}
