import Testing
@testable import GPS_Logger

struct TASTriangularSolverTests {
    @Test
    func testSimpleCase() async throws {
        let legs = [
            TASTriangularSolver.Leg(headingDeg: 0, trackDeg: 0, groundSpeedKt: 270),
            TASTriangularSolver.Leg(headingDeg: 90, trackDeg: 95.71, groundSpeedKt: 301.5),
            TASTriangularSolver.Leg(headingDeg: 180, trackDeg: 180, groundSpeedKt: 330)
        ]
        if let result = TASTriangularSolver.solve(legs: legs) {
            #expect(abs(result.tasKt - 300) < 1)
            #expect(abs(result.windDirectionDeg - 0) < 1)
            #expect(abs(result.windSpeedKt - 30) < 1)
        } else {
            #expect(false, "solve returned nil")
        }
    }
}
