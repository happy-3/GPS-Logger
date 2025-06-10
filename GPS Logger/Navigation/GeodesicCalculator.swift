import Foundation
import CoreLocation

/// 大圏計算を行うユーティリティ
enum GeodesicCalculator {
    /// 2点間の初期方位(真方位)と距離(NM)を求める
    static func bearingDistance(from: CLLocationCoordinate2D,
                                to: CLLocationCoordinate2D) -> (bearing: Double, distance: Double) {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var bearing = atan2(y, x) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        let r = 6371.0 // km
        let d = acos(sin(lat1) * sin(lat2) + cos(lat1) * cos(lat2) * cos(dLon)) * r
        let nm = d / 1.852
        return (bearing, nm)
    }

    /// 始点から方位と距離で終点を求める
    static func destinationPoint(from: CLLocationCoordinate2D,
                                 courseDeg: Double,
                                 distanceNm: Double) -> CLLocationCoordinate2D {
        let distRad = (distanceNm * 1.852) / 6371.0
        let brg = courseDeg * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(distRad) + cos(lat1) * sin(distRad) * cos(brg))
        let lon2 = lon1 + atan2(sin(brg) * sin(distRad) * cos(lat1),
                                cos(distRad) - sin(lat1) * sin(lat2))
        let latDeg = lat2 * 180 / .pi
        var lonDeg = lon2 * 180 / .pi
        if lonDeg > 180 { lonDeg -= 360 }
        if lonDeg < -180 { lonDeg += 360 }
        return CLLocationCoordinate2D(latitude: latDeg, longitude: lonDeg)
    }

    /// 与えられた自機状態から10分後の予測位置を求める
    static func tenMinPoint(state: AircraftState) -> CLLocationCoordinate2D {
        let dist = state.groundSpeedKt * (10.0 / 60.0)
        return destinationPoint(from: state.position, courseDeg: state.groundTrack, distanceNm: dist)
    }
}
