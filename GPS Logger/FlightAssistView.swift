import SwiftUI
import CoreHaptics

/// Flight Assist の表示とレグ管理を行うビュー。
struct FlightAssistView: View {
    @EnvironmentObject var locationManager: LocationManager

    // 簡易ステート
    @State private var headingMag: Int = 0
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 30) {
            Stepper(value: $headingMag, in: 0...330, step: 30) {
                Text("機種方位: \(headingMag)°")
            }

            if isRunning {
                HStack(spacing: 40) {
                    Button("Left Turn") { headingMag = (headingMag + 270) % 360 }
                        .frame(width: 100, height: 50)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    Button("Right Turn") { headingMag = (headingMag + 90) % 360 }
                        .frame(width: 100, height: 50)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    Button("Restart") { isRunning = false }
                        .frame(width: 100, height: 50)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            } else {
                Button("Start") { isRunning = true }
                    .frame(width: 120, height: 50)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("測風")
        .onAppear {
            if let track = locationManager.lastLocation?.course, track >= 0 {
                var mag = track - locationManager.declination
                mag = mag.truncatingRemainder(dividingBy: 360)
                if mag < 0 { mag += 360 }
                headingMag = Int((mag + 15) / 30) * 30 % 360
            }
        }
    }
}

struct FlightAssistView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FlightAssistView()
                .environmentObject(LocationManager(flightLogManager: FlightLogManager(settings: Settings()),
                                                altitudeFusionManager: AltitudeFusionManager(settings: Settings()),
                                                settings: Settings()))
        }
    }
}
