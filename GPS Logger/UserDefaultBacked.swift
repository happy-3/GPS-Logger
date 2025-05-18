import Foundation
import Combine

/// A property wrapper that synchronizes a value with UserDefaults and publishes changes.
@propertyWrapper
final class UserDefaultBacked<Value> {
    private let key: String
    private let defaultValue: Value
    @Published private var value: Value

    var wrappedValue: Value {
        get { value }
        set {
            value = newValue
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }

    var projectedValue: Published<Value>.Publisher { $value }

    init(wrappedValue defaultValue: Value, key: String) {
        self.key = key
        self.defaultValue = defaultValue
        let stored = UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue
        self.value = stored
    }
}
