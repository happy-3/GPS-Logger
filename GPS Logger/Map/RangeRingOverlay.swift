import Foundation
import MapKit
import SwiftUI

final class RangeRingOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D
    var radiusNm: Double
    var courseDeg: Double
    private(set) var lastHeading: Double

    func update(center: CLLocationCoordinate2D, radiusNm: Double, courseDeg: Double) {
        self.coordinate = center
        self.radiusNm = radiusNm
        self.courseDeg = courseDeg
        let newHeading = courseDeg - MagneticVariation.declination(at: center)
        if abs(newHeading - lastHeading) >= 1 {
            lastHeading = newHeading
        }
    }

    init(center: CLLocationCoordinate2D, radiusNm: Double, courseDeg: Double) {
        self.coordinate = center
        self.radiusNm = radiusNm
        self.courseDeg = courseDeg
        self.lastHeading = courseDeg - MagneticVariation.declination(at: center)
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
    private struct Tick {
        let path: UIBezierPath
        let width: CGFloat
        let label: String?
        let labelPos: CGPoint?
    }

    private let overlayObj: RangeRingOverlay
    private let settings: Settings

    private var cachedRadius: CGFloat = -1
    private var cachedHeading: Double = -1
    private var ringPath = UIBezierPath()
    private var ticks: [Tick] = []
    private struct RingLabel {
        let text: String
        let pos: CGPoint
    }
    private var ringLabels: [RingLabel] = []

    init(overlay: RangeRingOverlay, settings: Settings) {
        self.overlayObj = overlay
        self.settings = settings
        super.init(overlay: overlay)
    }

    private func rebuildPaths(radius: CGFloat, heading: Double) {
        cachedRadius = radius
        cachedHeading = heading

        ringPath = UIBezierPath()
        ringLabels.removeAll()
        let labelOffset = radius * 0.05
        let labelAngle = 135.0
        for frac in [0.25, 0.5, 0.75, 1.0] {
            let r = radius * frac
            ringPath.append(UIBezierPath(ovalIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)))

            var p = CGPoint(x: 0, y: -(r + labelOffset))
            p = p.applying(CGAffineTransform(rotationAngle: CGFloat((labelAngle + heading) * .pi / 180)))
            let text = String(format: "%.0f NM", overlayObj.radiusNm * frac)
            ringLabels.append(RingLabel(text: text, pos: p))
        }

        ticks.removeAll()
        let majorLen = radius * 0.1
        let midLen = majorLen * 2.0 / 3.0
        let tenLen = majorLen * 0.5
        let minorLen = majorLen * 0.3
        let labelRadius = radius * 0.75

        for deg in stride(from: 0, to: 360, by: 5) {
            let path = UIBezierPath()
            var len: CGFloat = minorLen
            var width: CGFloat = 0.5
            var label: String? = nil
            if deg % 90 == 0 {
                len = majorLen
                width = 3.0
                let dirs = ["N", "E", "S", "W"]
                label = dirs[(deg / 90) % 4]
            } else if deg % 30 == 0 {
                len = midLen
                width = 1.5
                label = String(format: "%03d", deg)
            } else if deg % 10 == 0 {
                len = tenLen
                width = 1.0
            }

            path.move(to: CGPoint(x: 0, y: -radius))
            path.addLine(to: CGPoint(x: 0, y: -radius + len))

            var transform = CGAffineTransform(rotationAngle: CGFloat((Double(deg) + heading) * .pi / 180))
            path.apply(transform)

            var labelPos: CGPoint? = nil
            if let _ = label {
                var p = CGPoint(x: 0, y: -labelRadius)
                p = p.applying(transform)
                labelPos = p
            }
            ticks.append(Tick(path: path, width: width, label: label, labelPos: labelPos))
        }
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

        let heading = overlayObj.lastHeading
        if radius != cachedRadius || heading != cachedHeading {
            rebuildPaths(radius: radius, heading: heading)
        }

        context.saveGState()
        context.translateBy(x: centerPt.x, y: centerPt.y)

        context.setStrokeColor(ringColor.cgColor)
        context.setLineWidth(1.0 / zoomScale)
        context.addPath(ringPath.cgPath)
        context.strokePath()

        for tick in ticks {
            context.setLineWidth(tick.width / zoomScale)
            context.addPath(tick.path.cgPath)
            context.strokePath()
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: ringColor,
            .backgroundColor: UIColor.black.withAlphaComponent(0.5)
        ]

        for tick in ticks {
            guard let label = tick.label, let pos = tick.labelPos else { continue }
            let str = NSString(string: label)
            let size = str.size(withAttributes: attrs)
            let rect = CGRect(x: pos.x - size.width / 2, y: pos.y - size.height / 2, width: size.width, height: size.height)
            str.draw(in: rect, withAttributes: attrs)
        }

        for ring in ringLabels {
            let str = NSString(string: ring.text)
            let size = str.size(withAttributes: attrs)
            let rect = CGRect(x: ring.pos.x - size.width / 2, y: ring.pos.y - size.height / 2, width: size.width, height: size.height)
            str.draw(in: rect, withAttributes: attrs)
        }

        context.restoreGState()
    }
}
