import Foundation

/// Single log entry describing aircraft state and sensor information.
struct FlightLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let latitude: Double
    let longitude: Double

    // GPS related data
    let gpsAltitude: Double           // ft
    let speedKt: Double               // knots
    let magneticCourse: Double        // -1 if not available
    let horizontalAccuracyM: Double   // meters
    let verticalAccuracyFt: Double    // feet
    let altimeterPressure: Double?    // optional

    // Sensor / fusion related data
    let rawGpsAltitudeChangeRate: Double   // ft/min
    let relativeAltitude: Double           // ft
    let barometricAltitude: Double         // ft
    let latestAcceleration: Double         // ft/s²
    let fusedAltitude: Double              // ft
    let fusedAltitudeChangeRate: Double    // ft/min

    // Parameters used for log optimisation
    let baselineAltitude: Double?          // initial GPS altitude
    let measuredAltitude: Double?          // weighted altitude
    let kalmanUpdateInterval: Double?      // seconds

    // photo index (when capturing)
    let photoIndex: Int?
}
