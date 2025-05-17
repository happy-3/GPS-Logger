import Foundation
import Combine

/// Handles storage and export of flight log entries.
final class FlightLogManager: ObservableObject {
    @Published var flightLogs: [FlightLog] = []
    var sessionFolderURL: URL?

    /// Start a new logging session.
    func startSession() {
        flightLogs.removeAll()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy_MM_dd_HHmmss"
        let folderName = "FlightLog_\(formatter.string(from: Date()))"

        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let folderURL = docsURL.appendingPathComponent(folderName)
            if !FileManager.default.fileExists(atPath: folderURL.path) {
                try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
            sessionFolderURL = folderURL
        }
    }

    /// End the current session.
    func endSession() {
        sessionFolderURL = nil
    }

    /// Append a new log entry.
    func addLog(_ log: FlightLog) {
        flightLogs.append(log)
    }

    /// Export all logs as CSV with UTF-8 BOM.
    func exportCSV() -> URL? {
        guard let folderURL = sessionFolderURL else { return nil }
        let fileName = "FlightLog_\(Int(Date().timeIntervalSince1970)).csv"
        let fileURL = folderURL.appendingPathComponent(fileName)

        var csvText = "timestamp,latitude,longitude,gpsAltitude(ft),speed(kt),magneticCourse,horizontalAccuracy(m),verticalAccuracy(ft),altimeterPressure,rawGpsAltitudeChangeRate(ft/min),relativeAltitude(ft),barometricAltitude(ft),latestAcceleration(ft/s²),fusedAltitude(ft),fusedAltitudeChangeRate(ft/min),baselineAltitude(ft),measuredAltitude(ft),kalmanUpdateInterval(s),photoIndex\n"
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        for log in flightLogs {
            let ts = isoFormatter.string(from: log.timestamp)
            let photoIndexText = log.photoIndex.map(String.init) ?? ""
            csvText.append("\(ts),\(log.latitude),\(log.longitude),\(log.gpsAltitude),\(log.speedKt),\(log.magneticCourse),\(log.horizontalAccuracyM),\(log.verticalAccuracyFt),\(log.altimeterPressure ?? 0),\(log.rawGpsAltitudeChangeRate),\(log.relativeAltitude),\(log.barometricAltitude),\(log.latestAcceleration),\(log.fusedAltitude),\(log.fusedAltitudeChangeRate),\(log.baselineAltitude ?? 0),\(log.measuredAltitude ?? 0),\(log.kalmanUpdateInterval ?? 0),\(photoIndexText)\n")
        }

        if let bom = "\u{FEFF}".data(using: .utf8), let csvData = csvText.data(using: .utf8) {
            var combined = Data()
            combined.append(bom)
            combined.append(csvData)
            try? combined.write(to: fileURL, options: .atomic)
            return fileURL
        }
        return nil
    }
}
