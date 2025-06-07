import Testing
@testable import GPS_Logger

struct FlightAssistUtilsTests {
    @Test
    func testOAT() {
        let oat = FlightAssistUtils.oat(tasMps: 250.0, mach: 0.8)
        #expect(oat > -60 && oat < 40)
    }

    @Test
    func testOATFromTASCAS() {
        let oat = FlightAssistUtils.oat(tasKt: 194.4, casKt: 194.4, pressureAltitudeFt: 0)
        #expect(abs(oat - 15.0) < 0.5)
    }
}
