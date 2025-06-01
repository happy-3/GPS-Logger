import Foundation

/// ISA 標準大気計算を提供するユーティリティ。
/// 0〜50kft の範囲をサポートする。
enum ISAAtmosphere {
    private static let T0 = 288.15       // K
    private static let P0 = 101_325.0    // Pa
    private static let L  = 0.0065       // K/m
    private static let R  = 287.05       // J/(kg*K)
    private static let g  = 9.80665      // m/s^2

    /// 指定高度における温度 (℃) を返す。
    static func temperature(altitudeFt: Double) -> Double {
        let h = altitudeFt * 0.3048
        if h <= 11_000 {
            return T0 - L * h - 273.15
        } else {
            return 216.65 - 273.15
        }
    }

    /// 指定高度における気圧 (Pa) を返す。
    static func pressure(altitudeFt: Double) -> Double {
        let h = altitudeFt * 0.3048
        if h <= 11_000 {
            let term = 1.0 - L * h / T0
            let exponent = g / (R * L)
            return P0 * pow(term, exponent)
        } else {
            let p11 = pressure(altitudeFt: 11_000 * 3.28084)
            let exponent = g / (R * 216.65)
            return p11 * exp(-exponent * (h - 11_000))
        }
    }

    /// 指定高度における大気密度 (kg/m³) を返す。
    static func density(altitudeFt: Double) -> Double {
        let tK = temperature(altitudeFt: altitudeFt) + 273.15
        let p = pressure(altitudeFt: altitudeFt)
        return p / (R * tK)
    }
}
