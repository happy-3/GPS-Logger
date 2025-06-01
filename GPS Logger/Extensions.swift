import Foundation

extension Double {
    /// Convert decimal coordinate to degree-minute format.
    func toDegMin() -> String {
        let degrees = Int(self)
        let minutes = (self - Double(degrees)) * 60
        return "\(degrees)°\(String(format: "%.3f", minutes))'"
    }
}

extension DateFormatter {
    /// "yyyy-MM-dd HH:mm:ss" in JST.
    static let jstFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f
    }()

    /// "yyyy_MM_dd_HHmmss" used for log folder names.
    static let logFolderNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy_MM_dd_HHmmss"
        return f
    }()

    /// "yyyyMMdd_HHmmss" used for file names.
    static let shortNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()
}

extension ISO8601DateFormatter {
    /// ISO8601 formatter with fractional seconds in JST.
    static let jst: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f
    }()
}
