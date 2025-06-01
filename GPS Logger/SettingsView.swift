import SwiftUI

/// A screen to adjust parameters used by altitude filtering and logging.
struct SettingsView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section(header: Text("Kalman Filter")) {
                HStack {
                    Text("Process Noise")
                    Slider(value: $settings.processNoise, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", settings.processNoise))
                        .frame(width: 50, alignment: .trailing)
                }

                HStack {
                    Text("Measurement Noise")
                    Slider(value: $settings.measurementNoise, in: 1...50, step: 0.5)
                    Text(String(format: "%.2f", settings.measurementNoise))
                        .frame(width: 50, alignment: .trailing)
                }
            }

            Section(header: Text("Logging")) {
                HStack {
                    Text("Interval (s)")
                    Slider(value: $settings.logInterval, in: 0.5...10, step: 0.5)
                    Text(String(format: "%.1f", settings.logInterval))
                        .frame(width: 50, alignment: .trailing)
                }

                HStack {
                    Text("Barometer Weight")
                    Slider(value: $settings.baroWeight, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", settings.baroWeight))
                        .frame(width: 50, alignment: .trailing)
                }
            }

            Section(header: Text("Photo Buffer")) {
                HStack {
                    Text("Seconds Before")
                    Slider(value: $settings.photoPreSeconds, in: 0...10, step: 0.5)
                    Text(String(format: "%.1f", settings.photoPreSeconds))
                        .frame(width: 50, alignment: .trailing)
                }

                HStack {
                    Text("Seconds After")
                    Slider(value: $settings.photoPostSeconds, in: 0...10, step: 0.5)
                    Text(String(format: "%.1f", settings.photoPostSeconds))
                        .frame(width: 50, alignment: .trailing)
                }
            }

            Section(header: Text("Flight Assist")) {
                HStack {
                    Text("Stable Duration")
                    Slider(value: $settings.faStableDuration, in: 1...10, step: 0.5)
                    Text(String(format: "%.1f", settings.faStableDuration))
                        .frame(width: 50, alignment: .trailing)
                }

                HStack {
                    Text("Track CI Limit")
                    Slider(value: $settings.faTrackCILimit, in: 1...10, step: 0.5)
                    Text(String(format: "%.1f", settings.faTrackCILimit))
                        .frame(width: 50, alignment: .trailing)
                }

                HStack {
                    Text("Speed CI Limit")
                    Slider(value: $settings.faSpeedCILimit, in: 1...10, step: 0.5)
                    Text(String(format: "%.1f", settings.faSpeedCILimit))
                        .frame(width: 50, alignment: .trailing)
                }
            }

            Section(header: Text("Recorded Fields")) {
                Toggle("Record Acceleration", isOn: $settings.recordAcceleration)
                Toggle("Record Altimeter Pressure", isOn: $settings.recordAltimeterPressure)
                Toggle("Record Raw GPS Rate", isOn: $settings.recordRawGpsRate)
                Toggle("Record Relative Altitude", isOn: $settings.recordRelativeAltitude)
                Toggle("Record Barometric Altitude", isOn: $settings.recordBarometricAltitude)
                Toggle("Record Fused Altitude", isOn: $settings.recordFusedAltitude)
                Toggle("Record Fused Rate", isOn: $settings.recordFusedRate)
                Toggle("Record Baseline Altitude", isOn: $settings.recordBaselineAltitude)
                Toggle("Record Measured Altitude", isOn: $settings.recordMeasuredAltitude)
                Toggle("Record Kalman Interval", isOn: $settings.recordKalmanInterval)
            }
        }
        .navigationTitle("Settings")
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: Settings())
    }
}
