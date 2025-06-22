import Foundation
import MapKit
import SwiftUI

final class TrackVectorOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D
    var courseDeg: Double
    var groundSpeedKt: Double
    var radiusNm: Double
    var valid: Bool

    init(center: CLLocationCoordinate2D, courseDeg: Double, groundSpeedKt: Double, radiusNm: Double, valid: Bool) {
        self.coordinate = center
        self.courseDeg = courseDeg
        self.groundSpeedKt = groundSpeedKt
        self.radiusNm = radiusNm
        self.valid = valid
        super.init()
    }

    var boundingMapRect: MKMapRect {
        let meters = radiusNm * 1852.0
        let mapPoints = meters * MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        let center = MKMapPoint(coordinate)
        return MKMapRect(x: center.x - mapPoints, y: center.y - mapPoints, width: mapPoints * 2, height: mapPoints * 2)
    }
}

final class TrackVectorRenderer: MKOverlayRenderer {
    private let overlayObj: TrackVectorOverlay
    private let settings: Settings

    init(overlay: TrackVectorOverlay, settings: Settings) {
        self.overlayObj = overlay
        self.settings = settings
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard overlayObj.valid else { return }
        let centerPt = point(for: MKMapPoint(overlayObj.coordinate))
        let dest = GeodesicCalculator.destinationPoint(from: overlayObj.coordinate, courseDeg: overlayObj.courseDeg, distanceNm: overlayObj.radiusNm)
        let destPt = point(for: MKMapPoint(dest))
        var path = CGMutablePath()
        path.move(to: centerPt)
        path.addLine(to: destPt)

        let gsKt = overlayObj.groundSpeedKt
        if gsKt > 0 {
            let minuteDist = gsKt / 60.0
            let arrowCoord = GeodesicCalculator.destinationPoint(from: overlayObj.coordinate, courseDeg: overlayObj.courseDeg, distanceNm: minuteDist)
            let arrowPt = point(for: MKMapPoint(arrowCoord))
            path.move(to: centerPt)
            path.addLine(to: arrowPt)
            let vec = CGPoint(x: arrowPt.x - centerPt.x, y: arrowPt.y - centerPt.y)
            let len = hypot(vec.x, vec.y)
            let unit = CGPoint(x: vec.x / len, y: vec.y / len)
            let perp = CGPoint(x: -unit.y, y: unit.x)
            let headLen: CGFloat = 10 / zoomScale
            let p1 = CGPoint(x: arrowPt.x - unit.x * headLen + perp.x * headLen/2,
                             y: arrowPt.y - unit.y * headLen + perp.y * headLen/2)
            let p2 = CGPoint(x: arrowPt.x - unit.x * headLen - perp.x * headLen/2,
                             y: arrowPt.y - unit.y * headLen - perp.y * headLen/2)
            path.move(to: p1)
            path.addLine(to: arrowPt)
            path.addLine(to: p2)
            for m in 2...5 {
                let dist = minuteDist * Double(m)
                if dist > overlayObj.radiusNm { break }
                let markCoord = GeodesicCalculator.destinationPoint(from: overlayObj.coordinate, courseDeg: overlayObj.courseDeg, distanceNm: dist)
                let markPt = point(for: MKMapPoint(markCoord))
                path.move(to: markPt)
                path.addEllipse(in: CGRect(x: markPt.x - 3, y: markPt.y - 3, width: 6, height: 6))
            }
        }

        let trackHex = settings.useNightTheme ? Color("TrackNight", bundle: .module).hexString
                                             : Color("TrackDay", bundle: .module).hexString
        let stroke = UIColor(hex: trackHex) ?? .yellow
        context.setStrokeColor(stroke.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(2.0 / zoomScale)
        context.addPath(path)
        context.strokePath()
    }
}
