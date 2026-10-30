import Foundation

/// `UserDefaults` that keeps every value in memory, so a test leaves no plist: `removePersistentDomain(forName:)`
/// empties a real suite, but cfprefsd writes an empty `~/Library/Preferences/<suite>.plist` seconds later.
/// `UpdateDefaults` reads through `object(forKey:)` (which `string(forKey:)` and `bool(forKey:)` call) and writes
/// through `set(_:forKey:)` and `removeObject(forKey:)`, the three this overrides.
final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    /// What was written.
    private(set) var values: [String: Any] = [:]
    /// Read after `values`, never written: stands in for the argument domain.
    private let readOnly: [String: Any]

    /// Fails only if Foundation cannot open the process's own domain, which sits underneath unused: every accessor
    /// `UpdateDefaults` uses is overridden, so nothing reaches it.
    init?(readOnly: [String: Any] = [:]) {
        self.readOnly = readOnly
        super.init(suiteName: nil)
    }

    override func object(forKey defaultName: String) -> Any? {
        values[defaultName] ?? readOnly[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }

    override func removeObject(forKey defaultName: String) {
        values[defaultName] = nil
    }
}
