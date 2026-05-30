import Foundation
import SwiftData

// MARK: - アイテムモデル（静的定義、SwiftData不要）

struct Item: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let emoji: String
    let condition: ItemCondition
}

// MARK: - 入手条件

enum ItemCondition: Codable, Equatable {
    case steps(min: Int, max: Int)

    func isSatisfied(steps: Int) -> Bool {
        switch self {
        case .steps(let min, let max):
            return steps >= min && steps < max
        }
    }
}

// MARK: - 日別記録（SwiftData永続化）

@Model
final class DailyRecord {
    // @Attribute(.unique) で同じ日付の重複を防ぐ
    @Attribute(.unique) var dateKey: String   // "yyyy-MM-dd"
    var date: Date
    var steps: Int
    var sleepHours: Double
    var floors: Int
    var obtainedItemId: String?
    var goalSteps: Int

    init(date: Date, steps: Int, sleepHours: Double, floors: Int,
         obtainedItemId: String?, goalSteps: Int) {
        self.date = Calendar.current.startOfDay(for: date)
        self.dateKey = Self.makeKey(from: date)
        self.steps = steps
        self.sleepHours = sleepHours
        self.floors = floors
        self.obtainedItemId = obtainedItemId
        self.goalSteps = goalSteps
    }

    static func makeKey(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    var achievementRate: Double {
        guard goalSteps > 0 else { return 0 }
        return min(1.0, Double(steps) / Double(goalSteps))
    }

    var isGoalAchieved: Bool { steps >= goalSteps }
}

// MARK: - コレクション記録（SwiftData永続化）

@Model
final class CollectionData {
    // JSON文字列として [itemId: count] を保持
    var itemCountsJSON: Data
    var lastObtainedItemId: String?

    init() {
        self.itemCountsJSON = (try? JSONEncoder().encode([String: Int]())) ?? Data()
        self.lastObtainedItemId = nil
    }

    // MARK: 操作

    func count(for itemId: String) -> Int {
        counts[itemId] ?? 0
    }

    func add(itemId: String, amount: Int = 1) {
        var c = counts
        c[itemId] = min((c[itemId] ?? 0) + amount, 999)
        counts = c
    }

    func hasItem(_ id: String) -> Bool { count(for: id) > 0 }

    var totalObtainedKinds: Int { counts.filter { $0.value > 0 }.count }

    // MARK: 内部

    private var counts: [String: Int] {
        get { (try? JSONDecoder().decode([String: Int].self, from: itemCountsJSON)) ?? [:] }
        set { itemCountsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
