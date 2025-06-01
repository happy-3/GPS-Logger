import Testing
@testable import GPS_Logger

struct LegRecorderTests {
    @Test
    func testWindowFiltering() async throws {
        var leg = FlightAssistView.LegRecorder(heading: 0, window: 3)
        let base = Date()
        for i in 0..<10 {
            leg.add(track: Double(i), speed: 100, at: base.addingTimeInterval(Double(i)))
        }
        if let summary = leg.summary(at: base.addingTimeInterval(10)) {
            #expect(summary.duration <= 3.1 && summary.duration >= 2.9)
            #expect(abs(summary.avgTrack - 8) < 0.1)
        } else {
            #expect(false, "summary was nil")
        }
    }

    @Test
    func testCircularAverage() async throws {
        var leg = FlightAssistView.LegRecorder(heading: 0, window: 3)
        let base = Date()
        leg.add(track: 350, speed: 100, at: base)
        leg.add(track: 10, speed: 100, at: base.addingTimeInterval(1))
        leg.add(track: 0, speed: 100, at: base.addingTimeInterval(2))
        if let sum = leg.summary(at: base.addingTimeInterval(2.5)) {
            #expect(abs(FlightAssistUtils.angleDifferenceDeg(sum.avgTrack, 0)) < 1)
        } else {
            #expect(false, "summary was nil")
        }
    }
}
