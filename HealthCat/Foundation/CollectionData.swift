import Foundation
import SwiftData

// MARK: - コレクション記録（SwiftData永続化）

@Model
final class CollectionData {
    var itemCountsJSON: Data
    var lastObtainedItemId: String?

    init() {
        self.itemCountsJSON    = (try? JSONEncoder().encode([String: Int]())) ?? Data()
        self.lastObtainedItemId = nil
    }

    func count(for itemId: String) -> Int { counts[itemId] ?? 0 }

    func add(itemId: String, amount: Int = 1) {
        var c = counts
        c[itemId] = min((c[itemId] ?? 0) + amount, 999)
        counts = c
    }

    func hasItem(_ id: String) -> Bool { count(for: id) > 0 }

    var totalObtainedKinds: Int { counts.filter { $0.value > 0 }.count }

    private var counts: [String: Int] {
        get { (try? JSONDecoder().decode([String: Int].self, from: itemCountsJSON)) ?? [:] }
        set { itemCountsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
