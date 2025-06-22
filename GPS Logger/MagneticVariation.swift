import Foundation
import CoreLocation

struct MagneticVariation {
    /// 与えられた座標の磁気偏差を取得する
    /// - Parameters:
    ///   - coordinate: 取得したい地点の座標
    ///   - date: 計算に使用する日時 (既定値は現在時刻)
    /// - Returns: 東偏を正とする磁気偏差 (度)
    static func declination(at coordinate: CLLocationCoordinate2D, date: Date = Date()) -> Double {
        if #available(iOS 16.0, macOS 13.0, *) {
            if let model = CLGeomagneticModel(date: date) {
                return model.declination(atLatitude: coordinate.latitude,
                                         longitude: coordinate.longitude,
                                         altitude: 0)
            }
        }
        return 0
    }
}
