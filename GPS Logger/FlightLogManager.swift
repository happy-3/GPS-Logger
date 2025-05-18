import Foundation
import Combine
import CoreLocation
import UIKit

/// Handles storage and export of flight log entries.
final class FlightLogManager: ObservableObject {
    @Published var flightLogs: [FlightLog] = []
    /// Completed distance measurements within the current session.
    @Published var distanceMeasurements: [DistanceMeasurement] = []
    var sessionFolderURL: URL?

    let settings: Settings

    init(settings: Settings) {
        self.settings = settings
    }

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

        var headers = ["timestamp","latitude","longitude","gpsAltitude(ft)","speed(kt)","magneticCourse","horizontalAccuracy(m)","verticalAccuracy(ft)"]
        if settings.recordAltimeterPressure { headers.append("altimeterPressure") }
        if settings.recordRawGpsRate { headers.append("rawGpsAltitudeChangeRate(ft/min)") }
        if settings.recordRelativeAltitude { headers.append("relativeAltitude(ft)") }
        if settings.recordBarometricAltitude { headers.append("barometricAltitude(ft)") }
        if settings.recordAcceleration { headers.append("latestAcceleration(ft/s²)") }
        if settings.recordFusedAltitude { headers.append("fusedAltitude(ft)") }
        if settings.recordFusedRate { headers.append("fusedAltitudeChangeRate(ft/min)") }
        if settings.recordBaselineAltitude { headers.append("baselineAltitude(ft)") }
        if settings.recordMeasuredAltitude { headers.append("measuredAltitude(ft)") }
        if settings.recordKalmanInterval { headers.append("kalmanUpdateInterval(s)") }
        headers.append("photoIndex")
        var csvText = headers.joined(separator: ",") + "\n"
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        for log in flightLogs {
            let ts = isoFormatter.string(from: log.timestamp)
            let photoIndexText = log.photoIndex.map(String.init) ?? ""
            var row = ["\(ts)","\(log.latitude)","\(log.longitude)","\(log.gpsAltitude)","\(log.speedKt ?? 0)","\(log.magneticCourse)","\(log.horizontalAccuracyM)","\(log.verticalAccuracyFt)"]
            if settings.recordAltimeterPressure { row.append("\(log.altimeterPressure ?? 0)") }
            if settings.recordRawGpsRate { row.append("\(log.rawGpsAltitudeChangeRate ?? 0)") }
            if settings.recordRelativeAltitude { row.append("\(log.relativeAltitude ?? 0)") }
            if settings.recordBarometricAltitude { row.append("\(log.barometricAltitude ?? 0)") }
            if settings.recordAcceleration { row.append("\(log.latestAcceleration ?? 0)") }
            if settings.recordFusedAltitude { row.append("\(log.fusedAltitude ?? 0)") }
            if settings.recordFusedRate { row.append("\(log.fusedAltitudeChangeRate ?? 0)") }
            if settings.recordBaselineAltitude { row.append("\(log.baselineAltitude ?? 0)") }
            if settings.recordMeasuredAltitude { row.append("\(log.measuredAltitude ?? 0)") }
            if settings.recordKalmanInterval { row.append("\(log.kalmanUpdateInterval ?? 0)") }
            row.append(photoIndexText)
            csvText.append(row.joined(separator: ",") + "\n")
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


    /// Export logs for a specific distance measurement as CSV.
    /// - Parameters:
    ///   - measurement: The measurement to export logs for.
    ///   - logs: Flight logs displayed in the distance graph.
    /// - Returns: URL of the exported CSV if successful.
    func exportMeasurementLogs(for measurement: DistanceMeasurement,
                               logs: [FlightLog]) -> URL? {
        guard let folderURL = sessionFolderURL else { return nil }

        let nameFormatter = DateFormatter()
        nameFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "MeasurementLog_\(nameFormatter.string(from: Date())).csv"
        let fileURL = folderURL.appendingPathComponent(fileName)

        var headers = ["timestamp","gpsAltitude(ft)"]
        if settings.recordFusedAltitude { headers.append("fusedAltitude(ft)") }
        if settings.recordRawGpsRate { headers.append("rawGpsAltitudeChangeRate(ft/min)") }
        if settings.recordFusedRate { headers.append("fusedAltitudeChangeRate(ft/min)") }
        var csvText = headers.joined(separator: ",") + "\n"
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        for log in logs {
            let ts = isoFormatter.string(from: log.timestamp)
            var row = ["\(ts)","\(log.gpsAltitude)"]
            if settings.recordFusedAltitude { row.append("\(log.fusedAltitude ?? 0)") }
            if settings.recordRawGpsRate { row.append("\(log.rawGpsAltitudeChangeRate ?? 0)") }
            if settings.recordFusedRate { row.append("\(log.fusedAltitudeChangeRate ?? 0)") }
            csvText.append(row.joined(separator: ",") + "\n")
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

    /// Export an altitude chart image for a specific measurement.
    /// - Parameters:
    ///   - measurement: The associated distance measurement.
    ///   - chartImage: Image created from `DistanceGraphView`.
    /// - Returns: URL of the saved PNG if successful.
    func exportMeasurementGraphImage(for measurement: DistanceMeasurement,
                                     chartImage: UIImage) -> URL? {
        guard let folderURL = sessionFolderURL else { return nil }

        let nameFormatter = DateFormatter()
        nameFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = nameFormatter.string(from: measurement.startTime)
        let fileName = "MeasurementGraph_\(name).png"
        let fileURL = folderURL.appendingPathComponent(fileName)

        if let data = chartImage.pngData() {
            try? data.write(to: fileURL, options: .atomic)
            return fileURL
        }

        return nil
    }
}
