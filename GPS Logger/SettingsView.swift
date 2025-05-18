import SwiftUI

/// A screen to adjust parameters used by altitude filtering and logging.
struct SettingsView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section(header: Text("Kalman Filter")) {
                HStack {
                    Text("Process Noise")
                    Spacer()
                    Text(String(format: "%.2f", settings.processNoise))
                }
                Slider(value: $settings.processNoise, in: 0...1, step: 0.05)

                HStack {
                    Text("Measurement Noise")
                    Spacer()
                    Text(String(format: "%.2f", settings.measurementNoise))
                }
                Slider(value: $settings.measurementNoise, in: 1...50, step: 0.5)
            }

            Section(header: Text("Logging")) {
                HStack {
                    Text("Interval (s)")
                    Spacer()
                    Text(String(format: "%.1f", settings.logInterval))
                }
                Slider(value: $settings.logInterval, in: 0.5...10, step: 0.5)

                HStack {
                    Text("Barometer Weight")
                    Spacer()
                    Text(String(format: "%.2f", settings.baroWeight))
                }
                Slider(value: $settings.baroWeight, in: 0...1, step: 0.05)
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
