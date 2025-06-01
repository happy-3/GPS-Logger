import Foundation

/// 気圧高度入力を抽象化するためのプロトコル。
protocol PressureAltitudeSource {
    /// 取得可能な気圧高度 (ft)。nil の場合は値未設定。
    var pressureAltitudeFt: Double? { get }
}
