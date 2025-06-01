import Foundation

/// Single log entry describing aircraft state and sensor information.
struct FlightLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let latitude: Double
    let longitude: Double

    // GPS related data
    let gpsAltitude: Double           // ft
    let speedKt: Double?              // knots
    let magneticCourse: Double        // -1 if not available
    let horizontalAccuracyM: Double   // meters
    let verticalAccuracyFt: Double    // feet
    let altimeterPressure: Double?    // optional

    // Sensor / fusion related data
    let rawGpsAltitudeChangeRate: Double?   // ft/min
    let relativeAltitude: Double?           // ft
    let barometricAltitude: Double?         // ft
    let latestAcceleration: Double?        // ft/s²
    let fusedAltitude: Double?              // ft
    let fusedAltitudeChangeRate: Double?    // ft/min

    // Parameters used for log optimisation
    let baselineAltitude: Double?          // initial GPS altitude
    let measuredAltitude: Double?          // weighted altitude
    let kalmanUpdateInterval: Double?      // seconds

    // Flight Assist 計算値
    let estimatedOAT: Double?              // ℃
    let theoreticalCAS: Double?            // kt
    let theoreticalHP: Double?             // ft
    let deltaCAS: Double?                  // kt
    let deltaHP: Double?                   // ft

    /// 風向 (真方位) のログ。nil の場合は未記録。
    let windDirection: Double?
    /// 風速 (kt)。nil の場合は未記録。
    let windSpeed: Double?
    /// 風情報の入力ソース。"measured" または "manual" などを想定。
    let windSource: String?
    /// 風向の95%信頼区間
    let windDirectionCI: Double?
    /// 風速の95%信頼区間
    let windSpeedCI: Double?

    // photo index (when capturing)
    let photoIndex: Int?
}
