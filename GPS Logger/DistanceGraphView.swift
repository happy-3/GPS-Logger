import SwiftUI
import Charts
import UIKit

/// Displays altitude over time for a distance measurement.
struct DistanceGraphView: View {
    let logs: [FlightLog]
    let measurement: DistanceMeasurement

    var body: some View {
        VStack(alignment: .leading) {
            altitudeChart

            HStack {
                Text(String(format: "水平距離: %.1f m", measurement.horizontalDistance))
                Spacer()
                Text(String(format: "総距離: %.1f m", measurement.totalDistance))
            }
            .font(.headline)
            .padding(.top, 8)
        }
        .padding()
        .navigationTitle("Distance Graph")
    }

    private var altitudeChart: some View {
        Chart {
            ForEach(logs) { log in
                LineMark(
                    x: .value("Time", log.timestamp),
                    y: .value("GPS Altitude", log.gpsAltitude)
                )
                .foregroundStyle(.red)
            }
            ForEach(logs) { log in
                LineMark(
                    x: .value("Time", log.timestamp),
                    y: .value("Kalman Altitude", log.fusedAltitude)
                )
                .foregroundStyle(.blue)
            }
        }
        .frame(height: 240)
    }

    /// Render the altitude chart to a `UIImage` for export.
    func chartImage() -> UIImage? {
        let renderer = ImageRenderer(content: altitudeChart)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

struct DistanceGraphView_Previews: PreviewProvider {
    static var previews: some View {
        let measurement = DistanceMeasurement(startTime: Date(),
                                              endTime: Date().addingTimeInterval(60),
                                              startLocation: .init(latitude: 0, longitude: 0),
                                              endLocation: .init(latitude: 0, longitude: 0),
                                              horizontalDistance: 100,
                                              totalDistance: 110)
        let logs: [FlightLog] = (0..<10).map { i -> FlightLog in
            let timestamp = Date().addingTimeInterval(Double(i) * 6)
            let gpsAlt = Double(1000 + i * 10)
            let fusedAlt = Double(1000 + i * 8)

            return FlightLog(
                timestamp: timestamp,
                latitude: 0,
                longitude: 0,
                gpsAltitude: gpsAlt,
                speedKt: nil,
                magneticCourse: 0,
                horizontalAccuracyM: 5,
                verticalAccuracyFt: 10,
                altimeterPressure: nil,
                rawGpsAltitudeChangeRate: 0,
                relativeAltitude: 0,
                barometricAltitude: gpsAlt,
                latestAcceleration: nil,
                fusedAltitude: fusedAlt,
                fusedAltitudeChangeRate: 0,
                baselineAltitude: nil,
                measuredAltitude: nil,
                kalmanUpdateInterval: nil,
                photoIndex: nil
            )
        }
        NavigationStack {
            DistanceGraphView(logs: logs, measurement: measurement)
        }
    }
}
