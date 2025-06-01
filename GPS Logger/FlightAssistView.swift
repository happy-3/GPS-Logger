import SwiftUI

/// Flight Assist の表示とレグ管理を行うビュー。
struct FlightAssistView: View {
    static let stableDuration: TimeInterval = 3
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    /// 各レグで収集したサンプルから統計を算出するヘルパ
    struct LegRecorder {
        let heading: Int
        private(set) var samples: [(track: Double, speed: Double, time: Date)] = []
        private let window: TimeInterval = FlightAssistView.stableDuration

        mutating func add(track: Double, speed: Double, at time: Date = Date()) {
            samples.append((track, speed, time))
            prune(olderThan: time)
        }

        private mutating func prune(olderThan time: Date) {
            let limit = time.addingTimeInterval(-window)
            while let first = samples.first, first.time < limit { samples.removeFirst() }
        }

        func duration(at time: Date = Date()) -> TimeInterval {
            guard let first = samples.first?.time else { return 0 }
            return time.timeIntervalSince(first)
        }

        func summary(at time: Date = Date()) -> LegSummary? {
            let limit = time.addingTimeInterval(-window)
            let windowSamples = samples.filter { $0.time >= limit }
            guard !windowSamples.isEmpty else { return nil }
            let tracks = windowSamples.map { $0.track }
            let speeds = windowSamples.map { $0.speed }
            let avgTrack = tracks.reduce(0, +) / Double(tracks.count)
            let avgSpeed = speeds.reduce(0, +) / Double(speeds.count)
            let sdTrack = sqrt(tracks.map { pow($0 - avgTrack, 2) }.reduce(0, +) / Double(tracks.count))
            let sdSpeed = sqrt(speeds.map { pow($0 - avgSpeed, 2) }.reduce(0, +) / Double(speeds.count))
            let ciTrack = 1.96 * sdTrack / sqrt(Double(tracks.count))
            let ciSpeed = 1.96 * sdSpeed / sqrt(Double(speeds.count))
            let dur = time.timeIntervalSince(windowSamples.first!.time)
            return LegSummary(heading: heading,
                              avgTrack: avgTrack,
                              ciTrack: ciTrack,
                              avgSpeed: avgSpeed,
                              ciSpeed: ciSpeed,
                              duration: dur)
        }
    }

    /// 完了したレグの結果
    struct LegSummary: Identifiable {
        let id = UUID()
        let heading: Int
        let avgTrack: Double
        let ciTrack: Double
        let avgSpeed: Double
        let ciSpeed: Double
        let duration: TimeInterval

        var isStable: Bool {
            duration >= FlightAssistView.stableDuration && ciTrack <= 3 && ciSpeed <= 3
        }
    }

    // MARK: 状態
    @State private var headingMag: Int = 0
    @State private var isRunning = false
    @State private var currentLeg: LegRecorder?
    @State private var summaries: [LegSummary] = []

    @State private var tasResult: Double?
    @State private var windDirResult: Double?
    @State private var windSpeedResult: Double?

    @State private var turnDirection: Int? = nil // -1 left, 1 right
    @State private var showRestart = false

    // MARK: 基本処理
    private func startNewLeg() {
        currentLeg = LegRecorder(heading: headingMag)
    }

    private func finalizeCurrentLeg() {
        if let sum = currentLeg?.summary() {
            summaries.append(sum)
        }
        currentLeg = nil
    }

    private func computeResults() {
        let legsForSolver = summaries.map { sum -> TASTriangularSolver.Leg in
            var hdTrue = Double(sum.heading) + locationManager.declination
            hdTrue.formTruncatingRemainder(dividingBy: 360)
            if hdTrue < 0 { hdTrue += 360 }
            return TASTriangularSolver.Leg(headingDeg: hdTrue,
                                            trackDeg: sum.avgTrack,
                                            groundSpeedKt: sum.avgSpeed)
        }
        if let result = TASTriangularSolver.solve(legs: legsForSolver) {
            tasResult = result.tasKt
            windDirResult = result.windDirectionDeg
            windSpeedResult = result.windSpeedKt
            locationManager.windDirection = windDirResult
            locationManager.windSpeed = windSpeedResult
            locationManager.windSource = "triangle"
        }
    }

    private func resetAll() {
        summaries.removeAll()
        tasResult = nil
        windDirResult = nil
        windSpeedResult = nil
        turnDirection = nil
        showRestart = false
        isRunning = false
        headingMag = nearestHeading()
        currentLeg = nil
    }

    private func nearestHeading() -> Int {
        if let track = locationManager.lastLocation?.course, track >= 0 {
            let mag = (track - locationManager.declination).truncatingRemainder(dividingBy: 360)
            let m = mag < 0 ? mag + 360 : mag
            return Int((m + 15) / 30) * 30 % 360
        }
        return 0
    }

    // MARK: ビュー
    var body: some View {
        VStack(spacing: 20) {
            Stepper {
                Text("機首方位: \(headingMag)°")
            } onIncrement: {
                headingMag = (headingMag + 30) % 360
            } onDecrement: {
                headingMag = (headingMag + 330) % 360
            }
            .padding(.top)

            if let loc = locationManager.lastLocation {
                VStack(alignment: .leading) {
                    Text(String(format: "グランドトラック: %.0f°", loc.course))
                    Text(String(format: "グランドスピード: %.1f kt", max(0, loc.speed * 1.94384)))
                    Text(String(format: "高度: %.0f ft", locationManager.rawGpsAltitude))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("GPSデータ未取得")
            }

            VStack(alignment: .leading) {
                ForEach(summaries) { sum in
                    HStack {
                        Text("機首方位 \(sum.heading)°")
                        Spacer()
                        Text(String(format: "GT %.0f° ±%.1f°", sum.avgTrack, sum.ciTrack))
                        Text(String(format: "GS %.1f ±%.1f kt", sum.avgSpeed, sum.ciSpeed))
                    }
                    .foregroundColor(sum.isStable ? .green : .primary)
                }
                if let running = currentLeg, let sum = running.summary() {
                    HStack {
                        Text("機首方位 \(running.heading)°")
                        Spacer()
                        Text(String(format: "GT %.0f° ±%.1f°", sum.avgTrack, sum.ciTrack))
                        Text(String(format: "GS %.1f ±%.1f kt", sum.avgSpeed, sum.ciSpeed))
                    }
                    .foregroundColor(sum.isStable ? .green : .primary)
                    if !sum.isStable {
                        Text(String(format: "安定まで %.1f 秒", max(0, FlightAssistView.stableDuration - sum.duration)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if isRunning {
                HStack(spacing: 40) {
                    if summaries.isEmpty {
                        Button("Left Turn") {
                            finalizeCurrentLeg()
                            turnDirection = -1
                            headingMag = (headingMag + 270) % 360
                            startNewLeg()
                        }
                        .frame(width: 100, height: 50)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)

                        Button("Right Turn") {
                            finalizeCurrentLeg()
                            turnDirection = 1
                            headingMag = (headingMag + 90) % 360
                            startNewLeg()
                        }
                        .frame(width: 100, height: 50)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    } else if summaries.count == 1 {
                        if turnDirection == -1 {
                            Button("Left Turn") {
                                finalizeCurrentLeg()
                                headingMag = (headingMag + 270) % 360
                                startNewLeg()
                            }
                            .frame(width: 100, height: 50)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        } else {
                            Button("Right Turn") {
                                finalizeCurrentLeg()
                                headingMag = (headingMag + 90) % 360
                                startNewLeg()
                            }
                            .frame(width: 100, height: 50)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    } else {
                        Button("Stop") {
                            finalizeCurrentLeg()
                            isRunning = false
                            computeResults()
                            showRestart = true
                        }
                        .frame(width: 100, height: 50)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
            } else {
                if showRestart {
                    Button("Restart") { resetAll() }
                        .frame(width: 120, height: 50)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                } else {
                    Button("Start") {
                        resetAll()
                        headingMag = nearestHeading()
                        isRunning = true
                        startNewLeg()
                    }
                    .frame(width: 120, height: 50)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }

            if let tas = tasResult, let wd = windDirResult, let ws = windSpeedResult {
                Text(String(format: "TAS %.1f kt\n風向 %.0f° 風速 %.1f kt", tas, wd, ws))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.top)
            }
        }
        .padding()
        .navigationTitle("測風")
        .onAppear {
            headingMag = nearestHeading()
        }
        .onReceive(locationManager.$lastLocation.compactMap { $0 }) { loc in
            guard isRunning, var leg = currentLeg, loc.course >= 0, loc.speed >= 0 else { return }
            leg.add(track: loc.course, speed: loc.speed * 1.94384)
            if let sum = leg.summary(), sum.isStable {
                currentLeg = leg
                finalizeCurrentLeg()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if summaries.count >= 3 {
                    isRunning = false
                    computeResults()
                    locationManager.recordLog()
                    showRestart = true
                    dismiss()
                }
            } else {
                currentLeg = leg
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
