import MapKit

/// 施設表示用のポイントアノテーション
class FacilityAnnotation: MKPointAnnotation {
    /// 施設種別
    var facilityType: String = ""
    /// GeoJSON Feature ID
    var featureID: String = UUID().uuidString
    /// GeoJSON プロパティ
    var properties: [String: Any] = [:]
}
