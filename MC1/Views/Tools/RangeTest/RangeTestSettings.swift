import Foundation

/// Persisted preferences for the Range Test tool.
struct RangeTestSettings {

    // MARK: - Keys

    private enum Key {
        static let minDistance = "rangeTest.minDistanceMeters"
        static let minInterval = "rangeTest.minIntervalSeconds"
        static let messageTemplate = "rangeTest.messageTemplate"
        static let historyLimit = "rangeTest.historyLimit"
    }

    // MARK: - Defaults

    static let defaultMinDistance: Double = 10.0   // metres
    static let defaultMinInterval: Double = 30.0   // seconds
    static let defaultMessageTemplate = "pos {\"id\": <id>, \"seq\": <seq>, \"lat\": <lat>, \"lon\": <lon>}"
    static let defaultHistoryLimit: Int = 100

    // MARK: - Storage

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Minimum distance threshold

    /// Minimum distance (metres) the device must move before a new beacon can be sent.
    var minimumDistanceMeters: Double {
        get {
            let stored = defaults.double(forKey: Key.minDistance)
            return stored > 0 ? stored : Self.defaultMinDistance
        }
        set {
            defaults.set(max(0, newValue), forKey: Key.minDistance)
        }
    }

    // MARK: - Minimum time interval

    /// Minimum time (seconds) that must elapse between consecutive beacons.
    var minimumIntervalSeconds: Double {
        get {
            let stored = defaults.double(forKey: Key.minInterval)
            return stored > 0 ? stored : Self.defaultMinInterval
        }
        set {
            defaults.set(max(0, newValue), forKey: Key.minInterval)
        }
    }

    // MARK: - Beacon message template

    /// User-defined template for beacon payloads with token inserts, e.g. `{lat}`.
    var messageTemplate: String {
        get {
            let stored = defaults.string(forKey: Key.messageTemplate)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let stored, !stored.isEmpty else {
                return Self.defaultMessageTemplate
            }
            return stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? Self.defaultMessageTemplate : trimmed, forKey: Key.messageTemplate)
        }
    }

    // MARK: - History limit

    /// Maximum number of range tests to keep in history.
    var historyLimit: Int {
        get {
            let stored = defaults.integer(forKey: Key.historyLimit)
            // Migrate older low caps (for example 5) to the new default retention.
            return stored > 0 ? max(stored, Self.defaultHistoryLimit) : Self.defaultHistoryLimit
        }
        set {
            defaults.set(max(Self.defaultHistoryLimit, newValue), forKey: Key.historyLimit)
        }
    }
}
