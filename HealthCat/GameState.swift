import Foundation
import Combine

// MARK: - 表示用データ

struct DailyRecord: Codable {
    var steps: Int = 0
    var sleepHours: Double = 0
    var floors: Int = 0
}

// MARK: - GameState

class GameState: ObservableObject {
    @Published var collection: CollectionRecord
    @Published var todaysItems: [Item] = []
    @Published var lastFetchedDate: Date?
    @Published var lastDailyRecord: DailyRecord? = nil
    @Published var isInitialSetupDone: Bool = false
    @Published var goalSteps: Int {
        didSet { UserDefaults.standard.set(goalSteps, forKey: goalStepsKey) }
    }

    private let collectionKey = "collection"
    private let lastFetchedDateKey = "lastFetchedDate"
    private let initialSetupKey = "initialSetupDone"
    private let goalStepsKey = "goalSteps"
    private let onboardingKey = "onboardingDone"

    @Published var isOnboardingDone: Bool

    init() {
        if let data = UserDefaults.standard.data(forKey: collectionKey),
           let decoded = try? JSONDecoder().decode(CollectionRecord.self, from: data) {
            self.collection = decoded
        } else {
            self.collection = CollectionRecord()
        }

        self.lastFetchedDate = UserDefaults.standard.object(forKey: lastFetchedDateKey) as? Date
        self.isInitialSetupDone = UserDefaults.standard.bool(forKey: initialSetupKey)
        self.isOnboardingDone = UserDefaults.standard.bool(forKey: onboardingKey)

        let savedGoal = UserDefaults.standard.integer(forKey: goalStepsKey)
        self.goalSteps = savedGoal > 0 ? savedGoal : 8000
    }

    // MARK: - 達成率

    var achievementRate: Double {
        guard let record = lastDailyRecord, goalSteps > 0 else { return 0 }
        return min(1.0, Double(record.steps) / Double(goalSteps))
    }

    var achievementPercent: Int {
        Int(achievementRate * 100)
    }

    // MARK: - 初回セットアップ（過去7日分）

    func applyHistoricalData(dailySteps: [(date: Date, steps: Int)]) {
        for record in dailySteps {
            if let item = ItemDatabase.shared.determineItem(steps: record.steps) {
                collection.add(itemId: item.id)
            }
        }
        isInitialSetupDone = true
        UserDefaults.standard.set(true, forKey: initialSetupKey)
        save()
    }

    func completeOnboarding() {
        isOnboardingDone = true
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }

    // MARK: - 毎日の処理

    func applyDailyResult(steps: Int, sleepHours: Double, floors: Int) {
        lastDailyRecord = DailyRecord(steps: steps, sleepHours: sleepHours, floors: floors)

        if let item = ItemDatabase.shared.determineItem(steps: steps) {
            collection.add(itemId: item.id)
            collection.lastObtainedItems = [item.id]
            todaysItems = [item]
        } else {
            todaysItems = []
        }

        lastFetchedDate = Date()
        save()
    }

    // MARK: - 永続化

    func save() {
        if let encoded = try? JSONEncoder().encode(collection) {
            UserDefaults.standard.set(encoded, forKey: collectionKey)
        }
        UserDefaults.standard.set(lastFetchedDate, forKey: lastFetchedDateKey)
    }

    func resetAll() {
        collection = CollectionRecord()
        todaysItems = []
        lastFetchedDate = nil
        lastDailyRecord = nil
        isInitialSetupDone = false
        isOnboardingDone = false
        UserDefaults.standard.removeObject(forKey: collectionKey)
        UserDefaults.standard.removeObject(forKey: lastFetchedDateKey)
        UserDefaults.standard.removeObject(forKey: initialSetupKey)
        UserDefaults.standard.removeObject(forKey: onboardingKey)
    }

    // MARK: - ユーティリティ

    var hasAlreadyFetchedToday: Bool {
        guard let last = lastFetchedDate else { return false }
        return Calendar.current.isDateInToday(last)
    }

    var collectedCount: Int { collection.totalObtainedKinds }
    var totalCount: Int { ItemDatabase.shared.allItems.count }
    var yesterdayRecord: DailyRecord? { lastDailyRecord }

    // デバッグ用
    func debugApplyResult(steps: Int) {
        applyDailyResult(steps: steps, sleepHours: 7.0, floors: 3)
    }
}
