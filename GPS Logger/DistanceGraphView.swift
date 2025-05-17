import SwiftUI
import Charts

/// Displays altitude over time for a distance measurement.
struct DistanceGraphView: View {
    let logs: [FlightLog]
    let measurement: DistanceMeasurement

    var body: some View {
        VStack(alignment: .leading) {
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
}

struct DistanceGraphView_Previews: PreviewProvider {
    static var previews: some View {
        let measurement = DistanceMeasurement(startTime: Date(),
                                              endTime: Date().addingTimeInterval(60),
                                              startLocation: .init(latitude: 0, longitude: 0),
                                              endLocation: .init(latitude: 0, longitude: 0),
                                              horizontalDistance: 100,
                                              totalDistance: 110)
        let logs: [FlightLog] = (0..<10).map { i in
            FlightLog(timestamp: Date().addingTimeInterval(Double(i)*6),
                      latitude: 0,
                      longitude: 0,
                      gpsAltitude: Double(1000 + i*10),
                      speedKt: 0,
                      magneticCourse: 0,
                      horizontalAccuracyM: 5,
                      verticalAccuracyFt: 10,
                      altimeterPressure: nil,
                      rawGpsAltitudeChangeRate: 0,
                      relativeAltitude: 0,
                      barometricAltitude: Double(1000 + i*10),
                      latestAcceleration: 0,
                      fusedAltitude: Double(1000 + i*8),
                      fusedAltitudeChangeRate: 0,
                      baselineAltitude: nil,
                      measuredAltitude: nil,
                      kalmanUpdateInterval: nil,
                      photoIndex: nil)
        }
        NavigationView {
            DistanceGraphView(logs: logs, measurement: measurement)
        }
    }
}
