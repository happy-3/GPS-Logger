import SwiftUI

/// Flight Assist の表示とレグ管理を行うビュー。
struct FlightAssistView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var settings: Settings
    @Environment(\.dismiss) private var dismiss

    /// 各レグで収集したサンプルから統計を算出するヘルパ
    struct LegRecorder {
        let heading: Int
        private(set) var samples: [(track: Double, speed: Double, time: Date)] = []
        let window: TimeInterval

        init(heading: Int, window: TimeInterval) {
            self.heading = heading
            self.window = window
        }

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
            let avgTrack = FlightAssistUtils.circularMeanDeg(tracks)
            let avgSpeed = speeds.reduce(0, +) / Double(speeds.count)
            let diffs = tracks.map { FlightAssistUtils.angleDifferenceDeg($0, avgTrack) }
            let sdTrack = sqrt(diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count))
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

        func isStable(using settings: Settings) -> Bool {
            duration >= settings.faStableDuration &&
            ciTrack <= settings.faTrackCILimit &&
            ciSpeed <= settings.faSpeedCILimit
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
    @State private var windDirCI: Double?
    @State private var windSpeedCI: Double?

    @State private var turnDirection: Int? = nil // -1 left, 1 right
    @State private var showRestart = false

    @State private var manualWindDirection = ""
    @State private var manualWindSpeed = ""

    // MARK: 基本処理
    private func startNewLeg() {
        currentLeg = LegRecorder(heading: headingMag, window: settings.faStableDuration)
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
            let windDirTrue = result.windDirectionDeg
            var windDirMag = windDirTrue - locationManager.declination
            windDirMag.formTruncatingRemainder(dividingBy: 360)
            if windDirMag < 0 { windDirMag += 360 }
            windDirResult = windDirMag
            windSpeedResult = result.windSpeedKt
            if let ci = windConfidenceIntervals(base: result) {
                windDirCI = ci.0
                windSpeedCI = ci.1
            } else {
                windDirCI = nil
                windSpeedCI = nil
            }
            locationManager.windDirection = windDirTrue
            locationManager.windSpeed = windSpeedResult
            locationManager.windSource = "triangle"
            locationManager.windDirectionCI = windDirCI
            locationManager.windSpeedCI = windSpeedCI

            let oat = FlightAssistUtils.oat(tasKt: result.tasKt, altitudeFt: locationManager.rawGpsAltitude)
            let cas = FlightAssistUtils.cas(tasKt: result.tasKt, altitudeFt: locationManager.rawGpsAltitude, oatC: oat)
            let hp = FlightAssistUtils.pressureAltitude(altitudeFt: locationManager.rawGpsAltitude, oatC: oat)
            let mach = FlightAssistUtils.mach(tasKt: result.tasKt, oatC: oat)
            locationManager.estimatedOAT = oat
            locationManager.theoreticalCAS = cas
            locationManager.theoreticalHP = hp
            if settings.enableMachCalculation {
                locationManager.estimatedMach = mach
            } else {
                locationManager.estimatedMach = nil
            }
        }
    }

    private func windConfidenceIntervals(base: (tasKt: Double, windDirectionDeg: Double, windSpeedKt: Double)) -> (Double, Double)? {
        let iterations = 200
        var dirs: [Double] = []
        var speeds: [Double] = []
        for _ in 0..<iterations {
            var legs: [TASTriangularSolver.Leg] = []
            for sum in summaries {
                var hd = Double(sum.heading) + locationManager.declination
                hd.formTruncatingRemainder(dividingBy: 360)
                if hd < 0 { hd += 360 }
                let tr = FlightAssistUtils.randomNormal(mean: sum.avgTrack, sd: sum.ciTrack / 1.96)
                let sp = FlightAssistUtils.randomNormal(mean: sum.avgSpeed, sd: sum.ciSpeed / 1.96)
                legs.append(TASTriangularSolver.Leg(headingDeg: hd, trackDeg: tr, groundSpeedKt: sp))
            }
            if let r = TASTriangularSolver.solve(legs: legs) {
                dirs.append(r.windDirectionDeg)
                speeds.append(r.windSpeedKt)
            }
        }
        guard !dirs.isEmpty else { return nil }
        let meanDir = base.windDirectionDeg
        let dirDiffs = dirs.map { FlightAssistUtils.angleDifferenceDeg($0, meanDir) }
        let dirSD = sqrt(dirDiffs.map { $0*$0 }.reduce(0, +) / Double(dirDiffs.count))
        let dirCI = dirSD * 1.96
        let meanSpeed = base.windSpeedKt
        let speedSD = sqrt(speeds.map { pow($0 - meanSpeed, 2) }.reduce(0, +) / Double(speeds.count))
        let speedCI = speedSD * 1.96
        return (dirCI, speedCI)
    }

    private func resetAll() {
        summaries.removeAll()
        tasResult = nil
        windDirResult = nil
        windSpeedResult = nil
        windDirCI = nil
        windSpeedCI = nil
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
                let trackText: String = {
                    if loc.course < 0 { return "計測不可" }
                    var mc = loc.course - locationManager.declination
                    mc = mc.truncatingRemainder(dividingBy: 360)
                    if mc < 0 { mc += 360 }
                    return String(format: "%.0f°", mc)
                }()
                let trackColor: Color = loc.course < 0 ? .red : .primary

                VStack(alignment: .leading) {
                    Text("グランドトラック: \(trackText)")
                        .foregroundColor(trackColor)
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
                    .foregroundColor(sum.isStable(using: settings) ? .green : .primary)
                }
                if let running = currentLeg, let sum = running.summary() {
                    HStack {
                        Text("機首方位 \(running.heading)°")
                        Spacer()
                        Text(String(format: "GT %.0f° ±%.1f°", sum.avgTrack, sum.ciTrack))
                        Text(String(format: "GS %.1f ±%.1f kt", sum.avgSpeed, sum.ciSpeed))
                    }
                    .foregroundColor(sum.isStable(using: settings) ? .green : .primary)
                    if !sum.isStable(using: settings) {
                        Text(String(format: "安定まで %.1f 秒", max(0, settings.faStableDuration - sum.duration)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("風向")
                        .frame(width: 40, alignment: .leading)
                    TextField("°", text: $manualWindDirection)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                HStack {
                    Text("風速")
                        .frame(width: 40, alignment: .leading)
                    TextField("kt", text: $manualWindSpeed)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                Button("風入力保存") {
                    if let d = Double(manualWindDirection), let s = Double(manualWindSpeed) {
                        var dTrue = d + locationManager.declination
                        dTrue.formTruncatingRemainder(dividingBy: 360)
                        if dTrue < 0 { dTrue += 360 }
                        locationManager.windDirection = dTrue
                        locationManager.windSpeed = s
                        locationManager.windSource = "manual"
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
                let dirCIText = windDirCI.map { String(format: " ±%.1f°", $0) } ?? ""
                let spdCIText = windSpeedCI.map { String(format: " ±%.1f", $0) } ?? ""
                Text(String(format: "TAS %.1f kt\n風向 %.0f°%@ 風速 %.1f kt%@", tas, wd, dirCIText, ws, spdCIText))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.top)
            }
        }
        .padding()
        .font(.title2)
        .monospacedDigit()
        .navigationTitle("測風")
        .onAppear {
            headingMag = nearestHeading()
        }
        .onReceive(locationManager.$lastLocation.compactMap { $0 }) { loc in
            guard isRunning, var leg = currentLeg, loc.course >= 0, loc.speed >= 0 else { return }
            leg.add(track: loc.course, speed: loc.speed * 1.94384)
            if let sum = leg.summary(), sum.isStable(using: settings) {
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
                .environmentObject(Settings())
        }
    }
}
