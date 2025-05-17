import Foundation

extension Double {
    /// Convert decimal coordinate to degree-minute format.
    func toDegMin() -> String {
        let degrees = Int(self)
        let minutes = (self - Double(degrees)) * 60
        return "\(degrees)°\(String(format: "%.3f", minutes))'"
    }
}
