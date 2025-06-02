import Foundation
import CoreLocation

/// Represents a distance measurement between two location estimates.
struct DistanceMeasurement {
    let startTime: Date
    let endTime: Date

    /// Estimated starting location.
    let startLocation: CLLocationCoordinate2D
    /// Estimated ending location.
    let endLocation: CLLocationCoordinate2D

    /// Horizontal distance on a 2D plane in meters.
    let horizontalDistance: Double
    /// Total 3D distance in meters.
    let totalDistance: Double

    /// Horizontal distance in nautical miles.
    var horizontalDistanceNM: Double { horizontalDistance / 1852.0 }

    /// Horizontal distance in feet.
    var horizontalDistanceFT: Double { horizontalDistance * 3.28084 }

    /// Total 3D distance in nautical miles.
    var totalDistanceNM: Double { totalDistance / 1852.0 }

    /// Total 3D distance in feet.
    var totalDistanceFT: Double { totalDistance * 3.28084 }
}
