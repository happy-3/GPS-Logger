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
}
