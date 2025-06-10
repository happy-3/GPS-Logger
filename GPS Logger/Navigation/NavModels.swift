import Foundation
import CoreLocation

/// 自機の現在状態を表すモデル
struct AircraftState {
    /// 位置
    var position: CLLocationCoordinate2D
    /// グランドトラック (真方位)
    var groundTrack: Double
    /// グランドスピード (kt)
    var groundSpeedKt: Double
    /// 高度 (ft)
    var altitudeFt: Double
    /// 計測時刻
    var timestamp: Date
}

/// マップ上の目標地点
struct Waypoint: Identifiable {
    let id = UUID()
    /// 座標
    var coordinate: CLLocationCoordinate2D
    /// 任意名称
    var name: String = "WP"
}

/// 航法計算結果
struct NavComputed {
    /// 目的地への真方位方位
    var bearing: Double
    /// 目的地までの距離 (NM)
    var distance: Double
    /// 到達までの予想到達時間 (秒)
    var ete: TimeInterval
    /// 予想到達時刻
    var eta: Date
    /// 10 分後の予測位置
    var tenMinPoint: CLLocationCoordinate2D
}
