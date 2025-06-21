//
//  GPS_LoggerTests.swift
//  GPS LoggerTests
//
//  Created by 小祝賢一 on 2025/03/22.
//

import Testing
@testable import GPS_Logger

struct GPS_LoggerTests {

    /// Verify that logs are stored and CSV export creates a file.
    @Test func testLogSavingAndCSVExport() async throws {
        let settings = Settings()
        let manager = FlightLogManager(settings: settings)
        manager.startSession()
        // Use a temporary directory for predictable behavior
        manager.sessionFolderURL = FileManager.default.temporaryDirectory

        let now = Date()
        let log = FlightLog(
            timestamp: now,
            gpsTimestamp: now,
            latitude: 35.0,
            longitude: 135.0,
            gpsAltitude: 1000,
            ellipsoidalAltitude: nil,
            speedKt: 100,
            trueCourse: 0,
            magneticVariation: 0,
            horizontalAccuracyM: 5,
            verticalAccuracyFt: 10,
            rawGpsAltitudeChangeRate: nil,
            estimatedOAT: nil,
            theoreticalCAS: nil,
            theoreticalHP: nil,
            estimatedMach: nil,
            windDirection: nil,
            windSpeed: nil,
            windSource: nil,
            windDirectionCI: nil,
            windSpeedCI: nil,
            photoIndex: nil)
        manager.addLog(log)

        #expect(manager.flightLogs.count == 1)
        if let url = manager.exportCSV() {
            let exists = FileManager.default.fileExists(atPath: url.path)
            #expect(exists)
        } else {
            #expect(false, "CSV export failed")
        }
    }

    /// Ensure a distance measurement can be completed using stored logs.
    @Test func testDistanceMeasurement() async throws {
        let settings = Settings()
        let manager = FlightLogManager(settings: settings)
        manager.startSession()

        let start = Date()
        let end = start.addingTimeInterval(60)

        let log1 = FlightLog(
            timestamp: start,
            gpsTimestamp: start,
            latitude: 35.0,
            longitude: 135.0,
            gpsAltitude: 0,
            ellipsoidalAltitude: nil,
            speedKt: nil,
            trueCourse: 0,
            magneticVariation: 0,
            horizontalAccuracyM: 5,
            verticalAccuracyFt: 10,
            rawGpsAltitudeChangeRate: nil,
            estimatedOAT: nil,
            theoreticalCAS: nil,
            theoreticalHP: nil,
            estimatedMach: nil,
            windDirection: nil,
            windSpeed: nil,
            windSource: nil,
            windDirectionCI: nil,
            windSpeedCI: nil,
            photoIndex: nil)
        let log2 = FlightLog(
            timestamp: end,
            gpsTimestamp: end,
            latitude: 35.001,
            longitude: 135.001,
            gpsAltitude: 100,
            ellipsoidalAltitude: nil,
            speedKt: nil,
            trueCourse: 0,
            magneticVariation: 0,
            horizontalAccuracyM: 5,
            verticalAccuracyFt: 10,
            rawGpsAltitudeChangeRate: nil,
            estimatedOAT: nil,
            theoreticalCAS: nil,
            theoreticalHP: nil,
            estimatedMach: nil,
            windDirection: nil,
            windSpeed: nil,
            windSource: nil,
            windDirectionCI: nil,
            windSpeedCI: nil,
            photoIndex: nil)
        manager.addLog(log1)
        manager.addLog(log2)

        manager.startMeasurement(at: start)
        let result = manager.finishMeasurement(at: end)

        #expect(result != nil)
        if let m = result {
            #expect(m.horizontalDistance > 0)
            #expect(m.totalDistance > 0)
        }
    }

}
