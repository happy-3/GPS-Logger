import Foundation
import MapKit
import SwiftUI

final class RangeRingOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D
    var radiusNm: Double
    var courseDeg: Double

    init(center: CLLocationCoordinate2D, radiusNm: Double, courseDeg: Double) {
        self.coordinate = center
        self.radiusNm = radiusNm
        self.courseDeg = courseDeg
        super.init()
    }

    var boundingMapRect: MKMapRect {
        let meters = radiusNm * 1852.0
        let mapPoints = meters * MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        let center = MKMapPoint(coordinate)
        return MKMapRect(x: center.x - mapPoints, y: center.y - mapPoints, width: mapPoints * 2, height: mapPoints * 2)
    }
}

@MainActor
final class RangeRingRenderer: MKOverlayRenderer {
    private let overlayObj: RangeRingOverlay
    private let settings: Settings

    init(overlay: RangeRingOverlay, settings: Settings) {
        self.overlayObj = overlay
        self.settings = settings
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let centerMapPoint = MKMapPoint(overlayObj.coordinate)
        let dest = GeodesicCalculator.destinationPoint(from: overlayObj.coordinate, courseDeg: 90, distanceNm: overlayObj.radiusNm)
        let destMapPoint = MKMapPoint(dest)
        let centerPt = point(for: centerMapPoint)
        let destPt = point(for: destMapPoint)
        let radius = hypot(destPt.x - centerPt.x, destPt.y - centerPt.y)

        let ringHex = settings.useNightTheme ? Color("RangeRingNight", bundle: .module).hexString
                                             : Color("RangeRingDay", bundle: .module).hexString
        let ringColor = UIColor(hex: ringHex) ?? .orange

        context.setStrokeColor(ringColor.cgColor)
        context.setLineWidth(1.0 / zoomScale)
        for frac in [0.25, 0.5, 0.75, 1.0] {
            let r = radius * frac
            let rect = CGRect(x: centerPt.x - r, y: centerPt.y - r, width: r * 2, height: r * 2)
            context.strokeEllipse(in: rect)
        }

        let course = overlayObj.courseDeg * .pi / 180
        let perp = CGPoint(x: -sin(course), y: cos(course))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: ringColor,
            .backgroundColor: UIColor.black.withAlphaComponent(0.5)
        ]
        for frac in [0.25, 0.5, 0.75, 1.0] {
            let nm = overlayObj.radiusNm * frac
            let dest = GeodesicCalculator.destinationPoint(from: overlayObj.coordinate, courseDeg: overlayObj.courseDeg, distanceNm: nm)
            let pt = point(for: MKMapPoint(dest))
            let offset = CGPoint(x: perp.x * 12, y: perp.y * 12)
            let rect = CGRect(x: pt.x + offset.x - 20, y: pt.y + offset.y - 8, width: 40, height: 16)
            let str = NSString(string: String(format: "%.0f NM", nm))
            str.draw(in: rect, withAttributes: attrs)
        }
    }
}
