import Testing
@testable import GPS_Logger

struct FlightAssistUtilsTests {
    @Test
    func testOAT() {
        let oat = FlightAssistUtils.oat(tasMps: 250.0, mach: 0.8)
        #expect(oat > -60 && oat < 40)
    }
}
