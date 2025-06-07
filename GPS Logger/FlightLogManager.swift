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
        let folderName = "FlightLog_\(DateFormatter.logFolderNameFormatter.string(from: Date()))"

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

        struct Field {
            let header: String
            let include: Bool
            let value: (FlightLog) -> String
        }

        let isoFormatter = ISO8601DateFormatter.jst

        let fields: [Field] = [
            Field(header: "timestamp", include: true) { isoFormatter.string(from: $0.timestamp) },
            Field(header: "gpsTimestamp", include: true) { isoFormatter.string(from: $0.gpsTimestamp) },
            Field(header: "latitude", include: true) { "\($0.latitude)" },
            Field(header: "longitude", include: true) { "\($0.longitude)" },
            Field(header: "gpsAltitude(ft)", include: true) { "\($0.gpsAltitude)" },
            Field(header: "ellipsoidalAltitude(ft)", include: settings.recordEllipsoidalAltitude) { "\($0.ellipsoidalAltitude ?? 0)" },
            Field(header: "speed(kt)", include: true) { "\($0.speedKt ?? 0)" },
            Field(header: "trueCourse", include: true) { "\($0.trueCourse)" },
            Field(header: "magneticVariation", include: true) { "\($0.magneticVariation)" },
            Field(header: "horizontalAccuracy(m)", include: true) { "\($0.horizontalAccuracyM)" },
            Field(header: "verticalAccuracy(ft)", include: true) { "\($0.verticalAccuracyFt)" },
            Field(header: "altimeterPressure", include: settings.recordAltimeterPressure) { "\($0.altimeterPressure ?? 0)" },
            Field(header: "rawGpsAltitudeChangeRate(ft/min)", include: settings.recordRawGpsRate) { "\($0.rawGpsAltitudeChangeRate ?? 0)" },
            Field(header: "relativeAltitude(ft)", include: settings.recordRelativeAltitude) { "\($0.relativeAltitude ?? 0)" },
            Field(header: "barometricAltitude(ft)", include: settings.recordBarometricAltitude) { "\($0.barometricAltitude ?? 0)" },
            Field(header: "latestAcceleration(ft/s²)", include: settings.recordAcceleration) { "\($0.latestAcceleration ?? 0)" },
            Field(header: "fusedAltitude(ft)", include: settings.recordFusedAltitude) { "\($0.fusedAltitude ?? 0)" },
            Field(header: "fusedAltitudeChangeRate(ft/min)", include: settings.recordFusedRate) { "\($0.fusedAltitudeChangeRate ?? 0)" },
            Field(header: "baselineAltitude(ft)", include: settings.recordBaselineAltitude) { "\($0.baselineAltitude ?? 0)" },
            Field(header: "measuredAltitude(ft)", include: settings.recordMeasuredAltitude) { "\($0.measuredAltitude ?? 0)" },
            Field(header: "kalmanUpdateInterval(s)", include: settings.recordKalmanInterval) { "\($0.kalmanUpdateInterval ?? 0)" },
            Field(header: "photoIndex", include: true) { $0.photoIndex.map(String.init) ?? "" },
            Field(header: "estimatedOAT(C)", include: true) { "\($0.estimatedOAT ?? 0)" },
            Field(header: "theoreticalCAS(kt)", include: true) { "\($0.theoreticalCAS ?? 0)" },
            Field(header: "theoreticalHP(ft)", include: true) { "\($0.theoreticalHP ?? 0)" },
            Field(header: "estimatedMach", include: true) { "\($0.estimatedMach ?? 0)" },
            Field(header: "deltaCAS(kt)", include: true) { "\($0.deltaCAS ?? 0)" },
            Field(header: "deltaHP(ft)", include: true) { "\($0.deltaHP ?? 0)" },
            Field(header: "windDirection", include: true) { "\($0.windDirection ?? 0)" },
            Field(header: "windSpeed(kt)", include: true) { "\($0.windSpeed ?? 0)" },
            Field(header: "windSource", include: true) { $0.windSource ?? "" },
            Field(header: "windDirectionCI", include: true) { "\($0.windDirectionCI ?? 0)" },
            Field(header: "windSpeedCI(kt)", include: true) { "\($0.windSpeedCI ?? 0)" }
        ]

        let activeFields = fields.filter { $0.include }
        var csvText = activeFields.map { $0.header }.joined(separator: ",") + "\n"

        for log in flightLogs {
            let row = activeFields.map { $0.value(log) }
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

        var csvText = "startTime,endTime,horizontalDistance(m),horizontalDistance(nm),horizontalDistance(ft),totalDistance(m),totalDistance(nm),totalDistance(ft)\n"
        let isoFormatter = ISO8601DateFormatter.jst
        for m in distanceMeasurements {
            let start = isoFormatter.string(from: m.startTime)
            let end = isoFormatter.string(from: m.endTime)
            csvText.append("\(start),\(end),\(m.horizontalDistance),\(m.horizontalDistanceNM),\(m.horizontalDistanceFT),\(m.totalDistance),\(m.totalDistanceNM),\(m.totalDistanceFT)\n")
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

        let fileName = "MeasurementLog_\(DateFormatter.shortNameFormatter.string(from: Date())).csv"
        let fileURL = folderURL.appendingPathComponent(fileName)

        var headers = ["timestamp","gpsAltitude(ft)"]
        if settings.recordFusedAltitude { headers.append("fusedAltitude(ft)") }
        if settings.recordRawGpsRate { headers.append("rawGpsAltitudeChangeRate(ft/min)") }
        if settings.recordFusedRate { headers.append("fusedAltitudeChangeRate(ft/min)") }
        var csvText = headers.joined(separator: ",") + "\n"
        let isoFormatter = ISO8601DateFormatter.jst
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

        let name = DateFormatter.shortNameFormatter.string(from: measurement.startTime)
        let fileName = "MeasurementGraph_\(name).png"
        let fileURL = folderURL.appendingPathComponent(fileName)

        if let data = chartImage.pngData() {
            try? data.write(to: fileURL, options: .atomic)
            return fileURL
        }

        return nil
    }
}
