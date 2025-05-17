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
        }
        .navigationTitle("Settings")
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: Settings())
    }
}
