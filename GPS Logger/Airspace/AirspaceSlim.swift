import Foundation
import CoreLocation

/// airspace_slim.json のエントリを表す構造体
struct AirspaceSlim: Codable, Identifiable {
    let id: String
    let name: String
    let sub: String
    let icon: String
    let upper: String
    let lower: String
    let bbox: [Double]    // [minLon, minLat, maxLon, maxLat]
    let active: Bool?
}

/// 高度文字列をメートル単位で返す。"FL100" や "5000ft" 等に対応
func alt_m(_ s: String) -> Int {
    let lower = s.lowercased()
    if lower.hasPrefix("fl"), let val = Int(lower.dropFirst(2)) {
        return Int(Double(val) * 100.0 * 0.3048)
    }
    if lower.hasSuffix("ft"), let val = Int(lower.dropLast(2)) {
        return Int(Double(val) * 0.3048)
    }
    return Int(Double(lower) ?? 0.0)
}

/// 指定座標が bbox 内に含まれるか判定
func contains(_ coord: CLLocationCoordinate2D, bbox: [Double]) -> Bool {
    guard bbox.count == 4 else { return false }
    return coord.longitude >= bbox[0] && coord.longitude <= bbox[2] &&
           coord.latitude >= bbox[1] && coord.latitude <= bbox[3]
}

/// 現在時刻に対して空域が有効か判定。active フィールドが無ければ常に true
func is_active(_ asp: AirspaceSlim, now: Date = Date()) -> Bool {
    return asp.active ?? true
}

/// 軍事空域かどうかを大まかに判定し、優先度として数値を返す
/// ここでは icon が "M" で始まる場合を軍事扱いとする簡易実装
func milRank(_ asp: AirspaceSlim) -> Int {
    asp.icon.uppercased().hasPrefix("M") ? 0 : 1
}
