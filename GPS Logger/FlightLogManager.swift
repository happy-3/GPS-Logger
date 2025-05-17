import Foundation
import Combine
import CoreLocation

/// Handles storage and export of flight log entries.
final class FlightLogManager: ObservableObject {
    @Published var flightLogs: [FlightLog] = []
    /// Completed distance measurements within the current session.
    @Published var distanceMeasurements: [DistanceMeasurement] = []
    var sessionFolderURL: URL?

    private var measurementStartTime: Date?

    /// Start a new logging session.
    func startSession() {
        flightLogs.removeAll()
        distanceMeasurements.removeAll()
        measurementStartTime = nil
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
        measurementStartTime = nil
    }

    /// Append a new log entry.
    func addLog(_ log: FlightLog) {
        flightLogs.append(log)
    }

    // MARK: - Distance Measurement

    /// Start recording a distance measurement.
    func startMeasurement(at time: Date) {
        measurementStartTime = time
    }

    /// Finish measuring distance and return the result if possible.
    func finishMeasurement(at time: Date) -> DistanceMeasurement? {
        guard let start = measurementStartTime else { return nil }
        guard let startEstimate = interpolatedLocation(at: start),
              let endEstimate = interpolatedLocation(at: time) else {
            measurementStartTime = nil
            return nil
        }

        let startCoord = startEstimate.coord
        let endCoord = endEstimate.coord

        let startHoriz = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
        let endHoriz = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)
        let horizontalDistance = startHoriz.distance(from: endHoriz)

        let startAltM = startEstimate.altitude * 0.3048
        let endAltM = endEstimate.altitude * 0.3048
        let startFull = CLLocation(coordinate: startCoord,
                                   altitude: startAltM,
                                   horizontalAccuracy: 1,
                                   verticalAccuracy: 1,
                                   timestamp: start)
        let endFull = CLLocation(coordinate: endCoord,
                                 altitude: endAltM,
                                 horizontalAccuracy: 1,
                                 verticalAccuracy: 1,
                                 timestamp: time)
        let totalDistance = startFull.distance(from: endFull)

        let measurement = DistanceMeasurement(startTime: start,
                                              endTime: time,
                                              startLocation: startCoord,
                                              endLocation: endCoord,
                                              horizontalDistance: horizontalDistance,
                                              totalDistance: totalDistance)
        distanceMeasurements.append(measurement)
        measurementStartTime = nil
        return measurement
    }

    /// Estimate interpolated coordinate and altitude at a given time.
    private func interpolatedLocation(at time: Date) -> (coord: CLLocationCoordinate2D, altitude: Double)? {
        guard let first = flightLogs.first, let last = flightLogs.last else { return nil }
        if time <= first.timestamp { return (CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude), first.gpsAltitude) }
        if time >= last.timestamp { return (CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude), last.gpsAltitude) }

        for i in 1..<flightLogs.count {
            let prev = flightLogs[i - 1]
            let next = flightLogs[i]
            if time >= prev.timestamp && time <= next.timestamp {
                let dt = next.timestamp.timeIntervalSince(prev.timestamp)
                guard dt > 0 else { return nil }
                let ratio = time.timeIntervalSince(prev.timestamp) / dt
                let lat = prev.latitude + (next.latitude - prev.latitude) * ratio
                let lon = prev.longitude + (next.longitude - prev.longitude) * ratio
                let alt = prev.gpsAltitude + (next.gpsAltitude - prev.gpsAltitude) * ratio
                return (CLLocationCoordinate2D(latitude: lat, longitude: lon), alt)
            }
        }
        return nil
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

    /// Export distance measurements as CSV with UTF-8 BOM.
    func exportDistanceCSV() -> URL? {
        guard let folderURL = sessionFolderURL else { return nil }
        let fileName = "Distance_\(Int(Date().timeIntervalSince1970)).csv"
        let fileURL = folderURL.appendingPathComponent(fileName)

        var csvText = "startTime,endTime,horizontalDistance(m),totalDistance(m)\n"
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        for m in distanceMeasurements {
            let start = isoFormatter.string(from: m.startTime)
            let end = isoFormatter.string(from: m.endTime)
            csvText.append("\(start),\(end),\(m.horizontalDistance),\(m.totalDistance)\n")
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
