import Foundation

/// A stored range test session for historical reference.
struct RangeTestHistoryEntry: Identifiable, Codable {
    let id: UUID
    let testID: Int
    let timestamp: Date
    let beacons: [RangeTestBeacon]
    
    init(testID: Int, beacons: [RangeTestBeacon]) {
        self.id = UUID()
        self.testID = testID
        // Use the last beacon's GPS timestamp so the history list sorts by
        // actual field activity, not wall-clock save time.
        self.timestamp = beacons.last?.timestamp ?? Date()
        self.beacons = beacons
    }
}

/// Manager for range test history storage and retrieval.
struct RangeTestHistoryStore {
    private let userDefaults: UserDefaults
    private let historyKey: String

    /// - Parameter radioID: The UUID of the connected radio. When provided the
    ///   history is scoped to that device, preventing entries from one radio
    ///   leaking into another radio's history.
    init(radioID: UUID? = nil, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let radioID {
            self.historyKey = "rangeTest.history.\(radioID.uuidString)"
        } else {
            self.historyKey = "rangeTest.history"
        }
    }
    
    /// Get all stored history entries, sorted by most recent first.
    func allEntries(limit: Int) -> [RangeTestHistoryEntry] {
        guard let data = userDefaults.data(forKey: historyKey) else {
            return []
        }
        
        do {
            let entries = try JSONDecoder().decode([RangeTestHistoryEntry].self, from: data)
            let sorted = entries.sorted { $0.timestamp > $1.timestamp }

            // Keep only the latest entry per testID to enforce uniqueness.
            var seenTestIDs = Set<Int>()
            let unique = sorted.filter { entry in
                seenTestIDs.insert(entry.testID).inserted
            }

            return Array(unique.prefix(limit))
        } catch {
            return []
        }
    }
    
    /// Save a new history entry, respecting the history limit.
    func saveEntry(_ entry: RangeTestHistoryEntry, limit: Int) {
        var entries = allEntries(limit: Int.max)
        entries.removeAll { $0.testID == entry.testID }
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(limit))
        
        do {
            let data = try JSONEncoder().encode(entries)
            userDefaults.set(data, forKey: historyKey)
        } catch {
            // Silently fail to preserve user data
        }
    }
    
    /// Delete a specific history entry.
    func deleteEntry(_ entryID: UUID, limit: Int) {
        var entries = allEntries(limit: Int.max)
        entries.removeAll { $0.id == entryID }
        
        do {
            let data = try JSONEncoder().encode(entries)
            userDefaults.set(data, forKey: historyKey)
        } catch {
            // Silently fail to preserve user data
        }
    }
    
    /// Delete all history entries.
    func clearAll() {
        userDefaults.removeObject(forKey: historyKey)
    }
}
