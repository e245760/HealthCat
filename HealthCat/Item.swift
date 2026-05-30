import Foundation

// MARK: - アイテムモデル

struct Item: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let emoji: String
    let condition: ItemCondition
}

// MARK: - 入手条件

enum ItemCondition: Codable, Equatable {
    case steps(min: Int, max: Int)   // 歩数範囲で確定取得

    func isSatisfied(steps: Int) -> Bool {
        switch self {
        case .steps(let min, let max):
            return steps >= min && steps < max
        }
    }
}

// MARK: - コレクション記録

struct CollectionRecord: Codable {
    // アイテムIDごとの個数（上限999）
    var itemCounts: [String: Int] = [:]
    var lastObtainedItems: [String] = []   // 直近で取得したアイテムのID

    static let maxCount = 999

    mutating func add(itemId: String, count: Int = 1) {
        let current = itemCounts[itemId] ?? 0
        itemCounts[itemId] = min(current + count, Self.maxCount)
    }

    func count(for itemId: String) -> Int {
        itemCounts[itemId] ?? 0
    }

    func hasItem(_ id: String) -> Bool {
        (itemCounts[id] ?? 0) > 0
    }

    var totalObtainedKinds: Int {
        itemCounts.filter { $0.value > 0 }.count
    }
}
