import os
import Foundation

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "GPSLogger"
    static let airspace = Logger(subsystem: subsystem, category: "airspace")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let flightlog = Logger(subsystem: subsystem, category: "flightlog")
}
