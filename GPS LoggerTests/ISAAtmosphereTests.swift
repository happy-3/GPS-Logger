import Testing
@testable import GPS_Logger

struct ISAAtmosphereTests {
    @Test
    func testSeaLevelTemperature() {
        let t = ISAAtmosphere.temperature(altitudeFt: 0)
        #expect(abs(t - 15.0) < 0.1)
    }

    @Test
    func testTropopauseTemperature() {
        let t = ISAAtmosphere.temperature(altitudeFt: 36089.0)
        #expect(abs(t + 56.5) < 0.2)
    }
}
