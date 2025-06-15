import MapKit

protocol AirspaceSlimBuilder {}

extension AirspaceSlimBuilder {
    func buildSlimList(from map: [String: [MKOverlay]]) -> [AirspaceSlim] {
        func altString(_ info: [String: Any]?) -> String {
            guard let info = info,
                  let value = info["value"] as? Int,
                  let unit = info["unit"] as? Int else { return "0ft" }
            if unit == 6 { return "FL\(value)" }
            return "\(value)ft"
        }

        var result: [AirspaceSlim] = []
        for (cat, overlays) in map {
            for ov in overlays {
                var props: [String: Any] = [:]
                var fid: String = UUID().uuidString
                var name: String = cat
                var sub: String = cat
                if let p = ov as? FeaturePolyline {
                    props = p.properties
                    fid = p.featureID
                    name = p.title ?? cat
                    sub = p.subtitle ?? cat
                } else if let p = ov as? FeaturePolygon {
                    props = p.properties
                    fid = p.featureID
                    name = p.title ?? cat
                    sub = p.subtitle ?? cat
                } else if let c = ov as? FeatureCircle {
                    props = c.properties
                    fid = c.featureID
                    name = c.title ?? cat
                    sub = c.subtitle ?? cat
                } else { continue }

                let upper = altString(props["upperLimit"] as? [String: Any])
                let lower = altString(props["lowerLimit"] as? [String: Any])

                let typ = props["type"] as? Int ?? 0
                let icon = (typ == 2 || typ == 4) ? "M" : "C"

                let rect = ov.boundingMapRect
                let sw = MKMapPoint(x: rect.minX, y: rect.maxY).coordinate
                let ne = MKMapPoint(x: rect.maxX, y: rect.minY).coordinate
                let bbox = [sw.longitude, sw.latitude, ne.longitude, ne.latitude]

                let asp = AirspaceSlim(id: fid, name: name, sub: sub, icon: icon,
                                      upper: upper, lower: lower, bbox: bbox, active: true)
                result.append(asp)
            }
        }
        return result
    }
}
