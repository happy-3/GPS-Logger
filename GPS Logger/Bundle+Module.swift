#if !SWIFT_PACKAGE
import Foundation

extension Bundle {
    /// Swift Package Manager 環境以外で `Bundle.module` を利用できるようにする
    static var module: Bundle {
        Bundle.main
    }
}
#endif
