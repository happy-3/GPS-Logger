import MapKit

/// GeoJSON フィーチャの属性を保持するオーバーレイ
class FeaturePolyline: MKPolyline {
    var featureID: String = UUID().uuidString
    var properties: [String: Any] = [:]
}

class FeaturePolygon: MKPolygon {
    var featureID: String = UUID().uuidString
    var properties: [String: Any] = [:]
}

class FeatureCircle: MKCircle {
    var featureID: String = UUID().uuidString
    var properties: [String: Any] = [:]
}
