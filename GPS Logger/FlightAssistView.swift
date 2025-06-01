import SwiftUI
import CoreHaptics

/// Flight Assist の表示とレグ管理を行うビュー。
struct FlightAssistView: View {
    @EnvironmentObject var locationManager: LocationManager

    // 簡易ステート
    @State private var headingMag: Int = 0
    @State private var isRunning = false

    @State private var legs: [TASTriangularSolver.Leg] = []
    @State private var tasResult: Double?
    @State private var windDirResult: Double?
    @State private var windSpeedResult: Double?

    private func captureCurrentLeg() {
        guard let loc = locationManager.lastLocation,
              loc.speed >= 0,
              loc.course >= 0 else { return }
        let speedKt = loc.speed * 1.94384
        var hdTrue = Double(headingMag) + locationManager.declination
        hdTrue.formTruncatingRemainder(dividingBy: 360)
        if hdTrue < 0 { hdTrue += 360 }
        let leg = TASTriangularSolver.Leg(
            headingDeg: hdTrue,
            trackDeg: loc.course,
            groundSpeedKt: speedKt)
        legs.append(leg)
    }

    var body: some View {
        VStack(spacing: 30) {
            Stepper(value: $headingMag, in: 0...330, step: 30) {
                Text("機種方位: \(headingMag)°")
            }

            if isRunning {
                HStack(spacing: 40) {
                    Button("Left Turn") {
                        captureCurrentLeg()
                        headingMag = (headingMag + 270) % 360
                    }
                        .frame(width: 100, height: 50)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    Button("Right Turn") {
                        captureCurrentLeg()
                        headingMag = (headingMag + 90) % 360
                    }
                        .frame(width: 100, height: 50)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    Button("Stop") {
                        captureCurrentLeg()
                        if let result = TASTriangularSolver.solve(legs: legs) {
                            tasResult = result.tasKt
                            windDirResult = result.windDirectionDeg
                            windSpeedResult = result.windSpeedKt
                        }
                        isRunning = false
                    }
                        .frame(width: 100, height: 50)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            } else {
                Button("Start") {
                    legs.removeAll()
                    tasResult = nil
                    windDirResult = nil
                    windSpeedResult = nil
                    captureCurrentLeg()
                    isRunning = true
                }
                    .frame(width: 120, height: 50)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Spacer()

            if let tas = tasResult,
               let wd = windDirResult,
               let ws = windSpeedResult {
                Text(String(format: "TAS %.1f kt\n風向 %.0f° 風速 %.1f kt", tas, wd, ws))
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
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
