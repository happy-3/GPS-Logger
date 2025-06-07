import Foundation
import MapKit

/// 空域データを管理し Map 上へ表示するためのマネージャ
final class AirspaceManager: ObservableObject {
    @Published private(set) var overlays: [MKPolyline] = []

    /// GeoJSON ファイルから空域ラインを読み込む
    func load(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard let features = obj["features"] as? [[String: Any]] else { return }

        var loaded: [MKPolyline] = []
        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String,
                  type == "LineString",
                  let coords = geometry["coordinates"] as? [[Double]] else { continue }
            let points = coords.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
            let polyline = MKPolyline(coordinates: points, count: points.count)
            loaded.append(polyline)
        }
        DispatchQueue.main.async {
            self.overlays = loaded
        }
    }
}
