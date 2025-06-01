import Foundation

struct TASTriangularSolver {
    struct Leg {
        /// 機体の真方位
        let headingDeg: Double
        /// 実際の対地針路
        let trackDeg: Double
        /// 対地速度 (kt)
        let groundSpeedKt: Double
    }

    /// 三脚法により風速・風向・TASを算出する
    /// - Parameter legs: 各レグの機首方位(真方位), 対地針路, 対地速度 (kt)。少なくとも3レグ必要。
    /// - Returns: (TAS, windDirectionDegFrom, windSpeedKt)
    static func solve(legs: [Leg]) -> (tasKt: Double, windDirectionDeg: Double, windSpeedKt: Double)? {
        guard legs.count >= 3 else { return nil }

        var rows: [[Double]] = []
        var rhs: [Double] = []

        for leg in legs {
            let hdRad = leg.headingDeg * .pi / 180.0
            let trRad = leg.trackDeg * .pi / 180.0
            let gx = leg.groundSpeedKt * sin(trRad)
            let gy = leg.groundSpeedKt * cos(trRad)

            // gx = TAS * sin(hd) + Wx
            rows.append([sin(hdRad), 1, 0])
            rhs.append(gx)
            // gy = TAS * cos(hd) + Wy
            rows.append([cos(hdRad), 0, 1])
            rhs.append(gy)
        }

        // 最小二乗法の正規方程式 (M^T M) X = M^T Y を構築
        var mtm = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
        var mty = Array(repeating: 0.0, count: 3)

        for i in 0..<rows.count {
            let row = rows[i]
            mty[0] += row[0] * rhs[i]
            mty[1] += row[1] * rhs[i]
            mty[2] += row[2] * rhs[i]
            for j in 0..<3 {
                for k in 0..<3 {
                    mtm[j][k] += row[j] * row[k]
                }
            }
        }

        // Invert 3x3 matrix
        let det = mtm[0][0]*(mtm[1][1]*mtm[2][2]-mtm[1][2]*mtm[2][1]) -
                  mtm[0][1]*(mtm[1][0]*mtm[2][2]-mtm[1][2]*mtm[2][0]) +
                  mtm[0][2]*(mtm[1][0]*mtm[2][1]-mtm[1][1]*mtm[2][0])
        guard det != 0 else { return nil }
        var inv = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
        inv[0][0] =  (mtm[1][1]*mtm[2][2]-mtm[1][2]*mtm[2][1])/det
        inv[0][1] = -(mtm[0][1]*mtm[2][2]-mtm[0][2]*mtm[2][1])/det
        inv[0][2] =  (mtm[0][1]*mtm[1][2]-mtm[0][2]*mtm[1][1])/det
        inv[1][0] = -(mtm[1][0]*mtm[2][2]-mtm[1][2]*mtm[2][0])/det
        inv[1][1] =  (mtm[0][0]*mtm[2][2]-mtm[0][2]*mtm[2][0])/det
        inv[1][2] = -(mtm[0][0]*mtm[1][2]-mtm[0][2]*mtm[1][0])/det
        inv[2][0] =  (mtm[1][0]*mtm[2][1]-mtm[1][1]*mtm[2][0])/det
        inv[2][1] = -(mtm[0][0]*mtm[2][1]-mtm[0][1]*mtm[2][0])/det
        inv[2][2] =  (mtm[0][0]*mtm[1][1]-mtm[0][1]*mtm[1][0])/det

        var x = Array(repeating: 0.0, count: 3)
        for i in 0..<3 {
            for j in 0..<3 {
                x[i] += inv[i][j] * mty[j]
            }
        }

        let tas = x[0]
        let wx = x[1]
        let wy = x[2]
        let windSpeed = sqrt(wx*wx + wy*wy)
        var windTo = atan2(wx, wy) * 180 / .pi // 風が向かう方位
        windTo.formTruncatingRemainder(dividingBy: 360)
        if windTo < 0 { windTo += 360 }
        let windFrom = (windTo + 180).truncatingRemainder(dividingBy: 360)
        return (tas, windFrom, windSpeed)
    }
}

