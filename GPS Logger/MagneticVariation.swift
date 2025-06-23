import Foundation
import CoreLocation

struct MagneticVariation {
    /// 直近に計算した座標
    private static var cachedCoordinate: CLLocationCoordinate2D?
    /// 直近に計算した日時
    private static var cachedDate: Date?
    /// 直近に計算した磁気偏差
    private static var cachedValue: Double = 0

    /// 同一地点とみなす距離しきい値 (m)
    private static let distanceThreshold: CLLocationDistance = 50_000
    /// 計算結果を保持する時間 (s)
    private static let timeThreshold: TimeInterval = 21_600  // 6 時間

    /// 与えられた座標の磁気偏差を取得する
    /// - Parameters:
    ///   - coordinate: 取得したい地点の座標
    ///   - date: 計算に使用する日時 (既定値は現在時刻)
    /// - Returns: 東偏を正とする磁気偏差 (度)
    static func declination(at coordinate: CLLocationCoordinate2D,
                            date: Date = Date()) -> Double {
        if let prev = cachedCoordinate,
           let prevDate = cachedDate {
            let loc1 = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let loc2 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let dist = loc1.distance(from: loc2)
            if dist < distanceThreshold,
               date.timeIntervalSince(prevDate) < timeThreshold {
                return cachedValue
            }
        }

        // Geomagnetism を使って磁気偏差を算出
        let geo = Geomagnetism(longitude: coordinate.longitude,
                               latitude: coordinate.latitude,
                               altitude: 0,
                               date: date)
        let value = geo.declination
        cachedCoordinate = coordinate
        cachedDate = date
        cachedValue = value
        return value
    }
}
