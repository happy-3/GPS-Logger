import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    init?(hex: String) {
        var hexString = hex
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        guard hexString.count == 6 || hexString.count == 8,
              let value = UInt64(hexString, radix: 16) else { return nil }
        let hasAlpha = hexString.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255.0
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255.0
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255.0
        let a = hasAlpha ? Double(value & 0xFF) / 255.0 : 1.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var hexString: String {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let rv = Int(r * 255)
        let gv = Int(g * 255)
        let bv = Int(b * 255)
        let av = Int(a * 255)
        return String(format: "%02X%02X%02X%02X", rv, gv, bv, av)
        #else
        return "FFFFFF"
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init?(hex: String) {
        var hexString = hex
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        guard hexString.count == 6 || hexString.count == 8,
              let value = UInt64(hexString, radix: 16) else { return nil }
        let hasAlpha = hexString.count == 8
        let r = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255.0
        let g = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255.0
        let b = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255.0
        let a = hasAlpha ? CGFloat(value & 0xFF) / 255.0 : 1.0
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
#endif
