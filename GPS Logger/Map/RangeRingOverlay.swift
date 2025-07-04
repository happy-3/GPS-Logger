import Foundation
import MapKit
import SwiftUI

final class RangeRingOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D
    var radiusNm: Double
    var courseDeg: Double
    /// カメラの heading 値 (地図の回転角)
    var mapHeading: Double
    private(set) var lastHeading: Double
    /// ラベルまで含めて描画するため、半径に少し余裕を持たせる
    private let marginRatio = 1.1

    func update(center: CLLocationCoordinate2D,
                radiusNm: Double,
                courseDeg: Double,
                mapHeading: Double) {
        self.coordinate = center
        self.radiusNm = radiusNm
        self.courseDeg = courseDeg
        self.mapHeading = mapHeading
        let newHeading = MagneticVariation.declination(at: center)
        if abs(newHeading - lastHeading) >= 1 {
            lastHeading = newHeading
        }
    }

    init(center: CLLocationCoordinate2D,
         radiusNm: Double,
         courseDeg: Double,
         mapHeading: Double) {
        self.coordinate = center
        self.radiusNm = radiusNm
        self.courseDeg = courseDeg
        self.mapHeading = mapHeading
        self.lastHeading = MagneticVariation.declination(at: center)
        super.init()
    }

    var boundingMapRect: MKMapRect {
        let meters = radiusNm * 1852.0 * marginRatio
        let mapPoints = meters * MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        let center = MKMapPoint(coordinate)
        return MKMapRect(x: center.x - mapPoints, y: center.y - mapPoints,
                         width: mapPoints * 2, height: mapPoints * 2)
    }
}

@MainActor
final class RangeRingRenderer: MKOverlayRenderer {
    private struct Tick {
        let path: UIBezierPath
        let width: CGFloat
        let label: String?
        let labelPos: CGPoint?
        /// ラベル描画時に使用する回転角 (deg)
        let angle: CGFloat
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
        // コンパスローズとして利用する半径
        let compassRadius = radius * 0.5

        for frac in [0.25, 0.75, 1.0] {
            let r = radius * frac
            ringPath.append(UIBezierPath(ovalIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)))

            var p = CGPoint(x: 0, y: -(r + labelOffset))
            p = p.applying(CGAffineTransform(rotationAngle: CGFloat((labelAngle + heading) * .pi / 180)))
            let text = String(format: "%.0f NM", overlayObj.radiusNm * frac)
            ringLabels.append(RingLabel(text: text, pos: p))
        }

        // 中間リング(0.5R)のラベル
        var midLabelPos = CGPoint(x: 0, y: -(compassRadius + labelOffset))
        midLabelPos = midLabelPos.applying(CGAffineTransform(rotationAngle: CGFloat((labelAngle + heading) * .pi / 180)))
        let midText = String(format: "%.0f NM", overlayObj.radiusNm * 0.5)
        ringLabels.append(RingLabel(text: midText, pos: midLabelPos))

        ticks.removeAll()
        let majorLen = radius * 0.1
        let midLen = majorLen * 2.0 / 3.0
        let tenLen = majorLen * 0.5
        let minorLen = majorLen * 0.3
        // 方位ラベルを外側に配置して線と重ならないようにする
        let midLabelRadius = compassRadius + labelOffset

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

            path.move(to: CGPoint(x: 0, y: -compassRadius))
            path.addLine(to: CGPoint(x: 0, y: -compassRadius + len))

            let angleDeg = Double(deg) + heading
            let transform = CGAffineTransform(rotationAngle: CGFloat(angleDeg * .pi / 180))
            path.apply(transform)

            var labelPos: CGPoint? = nil
            if let _ = label {
                let r = midLabelRadius
                var p = CGPoint(x: 0, y: -r)
                p = p.applying(transform)
                labelPos = p
            }
            ticks.append(Tick(path: path, width: width, label: label, labelPos: labelPos, angle: CGFloat(angleDeg)))
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

        // 地図の回転角を引いた値を使ってコンパスローズを描画する
        // lastHeading は磁気偏差 (真北-磁北) を表す
        // mapHeading は現在の地図の回転角で、これを差し引くことで
        // 地図表示に合わせた正しい方位を求める
        let heading = overlayObj.lastHeading - overlayObj.mapHeading
        if radius != cachedRadius || heading != cachedHeading {
            rebuildPaths(radius: radius, heading: heading)
        }

        context.saveGState()
        context.translateBy(x: centerPt.x, y: centerPt.y)
        // mapHeading は地図自体の回転角。コンパスローズの計算では
        // 上記 heading に組み込んでいるため、ここでは mapHeading の
        // 回転だけを適用してオーバーレイ全体を回転させる
        context.rotate(by: CGFloat(overlayObj.mapHeading * .pi / 180))

        context.setStrokeColor(ringColor.cgColor)
        context.setLineWidth(3.0 / zoomScale)
        context.addPath(ringPath.cgPath)
        context.strokePath()

        for tick in ticks {
            context.setLineWidth(tick.width * 3 / zoomScale)
            context.addPath(tick.path.cgPath)
            context.strokePath()
        }

        let attrs: [NSAttributedString.Key: Any] = [
            // ズームによってラベルサイズが変化しないよう調整
            .font: UIFont.systemFont(ofSize: 36 / zoomScale),
            .foregroundColor: ringColor,
            .backgroundColor: UIColor.black.withAlphaComponent(0.5)
        ]

        UIGraphicsPushContext(context)
        for tick in ticks {
            guard let label = tick.label, let pos = tick.labelPos else { continue }
            let str = NSString(string: label)
            let size = str.size(withAttributes: attrs)
            context.saveGState()
            context.translateBy(x: pos.x, y: pos.y)
            context.rotate(by: tick.angle * .pi / 180)
            let rect = CGRect(x: -size.width / 2, y: -size.height / 2,
                              width: size.width, height: size.height)
            str.draw(in: rect, withAttributes: attrs)
            context.restoreGState()
        }

        for ring in ringLabels {
            let str = NSString(string: ring.text)
            let size = str.size(withAttributes: attrs)
            let rect = CGRect(x: ring.pos.x - size.width / 2, y: ring.pos.y - size.height / 2, width: size.width, height: size.height)
            str.draw(in: rect, withAttributes: attrs)
        }
        UIGraphicsPopContext()

        context.restoreGState()
    }
}
