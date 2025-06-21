import SwiftUI

/// A screen to adjust parameters used by altitude filtering and logging.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var airspaceManager: AirspaceManager

    var body: some View {
        Form {
            Section(header: Text("Current Location")) {
                if let loc = locationManager.lastLocation {
                    Text(String(format: "緯度: %.5f", loc.coordinate.latitude))
                    Text(String(format: "経度: %.5f", loc.coordinate.longitude))
                } else {
                    Text("GPSデータ未取得")
                }
            }

            Section(header: Text("Logging")) {
                HStack {
                    Text("Interval (s)")
                    Slider(value: $settings.logInterval, in: 0.5...10, step: 0.5)
                    Text(String(format: "%.1f", settings.logInterval))
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

            Section(header: Text("Display Options")) {
                Toggle("楕円体高を表示", isOn: $settings.showEllipsoidalAltitude)
                Toggle("Mach/CAS計算を有効化", isOn: $settings.enableMachCalculation)
            }


            Section(header: Text("Recorded Fields")) {
                Toggle("Record Raw GPS Rate", isOn: $settings.recordRawGpsRate)
                Toggle("Record Ellipsoidal Altitude", isOn: $settings.recordEllipsoidalAltitude)
            }
        }
        .navigationTitle("Settings")
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: Settings())
            .environmentObject(LocationManager(flightLogManager: FlightLogManager(settings: Settings()),
                                             settings: Settings()))
    }
}
