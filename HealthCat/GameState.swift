import Foundation
import SwiftData
import Combine

// MARK: - GameState
// SwiftDataのModelContextを直接操作して永続化する

class GameState: ObservableObject {
    // SwiftDataコンテキスト（RootViewから注入）
    var modelContext: ModelContext?

    // MARK: Published（UI用キャッシュ）
    @Published var todaysItems: [Item] = []
    @Published var lastFetchedDate: Date?
    @Published var isInitialSetupDone: Bool
    @Published var isOnboardingDone: Bool
    @Published var goalSteps: Int {
        didSet { UserDefaults.standard.set(goalSteps, forKey: "goalSteps") }
    }

    // UserDefaultsキー（軽量な設定値のみ残す）
    private let initialSetupKey  = "initialSetupDone"
    private let onboardingKey    = "onboardingDone"
    private let lastFetchedKey   = "lastFetchedDate"

    // MARK: Init

    init() {
        self.isInitialSetupDone = UserDefaults.standard.bool(forKey: "initialSetupDone")
        self.isOnboardingDone   = UserDefaults.standard.bool(forKey: "onboardingDone")
        self.lastFetchedDate    = UserDefaults.standard.object(forKey: "lastFetchedDate") as? Date
        let saved = UserDefaults.standard.integer(forKey: "goalSteps")
        self.goalSteps = saved > 0 ? saved : 8000
    }

    // MARK: - SwiftData helpers

    private func fetchAllRecords() -> [DailyRecord] {
        guard let ctx = modelContext else { return [] }
        let desc = FetchDescriptor<DailyRecord>(sortBy: [SortDescriptor(\.date)])
        return (try? ctx.fetch(desc)) ?? []
    }

    private func fetchRecord(for date: Date) -> DailyRecord? {
        guard let ctx = modelContext else { return nil }
        let key = DailyRecord.makeKey(from: date)
        var desc = FetchDescriptor<DailyRecord>(
            predicate: #Predicate { $0.dateKey == key }
        )
        desc.fetchLimit = 1
        return try? ctx.fetch(desc).first
    }

    private func collectionData() -> CollectionData {
        guard let ctx = modelContext else { return CollectionData() }
        let desc = FetchDescriptor<CollectionData>()
        if let existing = try? ctx.fetch(desc).first { return existing }
        let new = CollectionData()
        ctx.insert(new)
        return new
    }

    // MARK: - 公開プロパティ

    var dailyHistory: [DailyRecord] { fetchAllRecords() }

    var yesterdayRecord: DailyRecord? {
        let yesterday = Calendar.current.date(
            byAdding: .day, value: -1,
            to: Calendar.current.startOfDay(for: Date())
        )!
        return fetchRecord(for: yesterday) ?? fetchAllRecords().last
    }

    var achievementRate: Double  { yesterdayRecord?.achievementRate ?? 0 }
    var achievementPercent: Int  { Int(achievementRate * 100) }
    var collectedCount: Int      { collectionData().totalObtainedKinds }
    var totalCount: Int          { ItemDatabase.shared.allItems.count }
    var collection: CollectionData { collectionData() }

    var hasAlreadyFetchedToday: Bool {
        guard let last = lastFetchedDate else { return false }
        return Calendar.current.isDateInToday(last)
    }

    // MARK: - 毎日の処理

    /// 1日分のデータを保存（upsert）
    func applyDailyResult(steps: Int, sleepHours: Double, floors: Int, for date: Date = Date()) {
        guard let ctx = modelContext else { return }

        // 保存対象は「その日」（fetchYesterdayなら前日）
        let targetDate = Calendar.current.startOfDay(for: date)
        let key = DailyRecord.makeKey(from: targetDate)

        let obtainedItem = ItemDatabase.shared.determineItem(steps: steps)

        // upsert
        if let existing = fetchRecord(for: targetDate) {
            // 既存レコードを更新
            existing.steps        = steps
            existing.sleepHours   = sleepHours
            existing.floors       = floors
            existing.obtainedItemId = obtainedItem?.id
            existing.goalSteps    = goalSteps
        } else {
            // 新規挿入
            let record = DailyRecord(
                date: targetDate,
                steps: steps,
                sleepHours: sleepHours,
                floors: floors,
                obtainedItemId: obtainedItem?.id,
                goalSteps: goalSteps
            )
            ctx.insert(record)

            // コレクションに追加（新規のみ）
            if let item = obtainedItem {
                let col = collectionData()
                col.add(itemId: item.id)
                col.lastObtainedItemId = item.id
            }
        }

        todaysItems = obtainedItem.map { [$0] } ?? []
        lastFetchedDate = Date()
        UserDefaults.standard.set(lastFetchedDate, forKey: lastFetchedKey)

        try? ctx.save()
    }

    // MARK: - 初回セットアップ（過去N日分の歩数のみ）

    func applyHistoricalData(dailySteps: [(date: Date, steps: Int)]) {
        guard let ctx = modelContext else { return }
        let col = collectionData()

        for record in dailySteps {
            let targetDate = Calendar.current.startOfDay(for: record.date)
            guard fetchRecord(for: targetDate) == nil else { continue }

            let item = ItemDatabase.shared.determineItem(steps: record.steps)
            if let item { col.add(itemId: item.id) }

            ctx.insert(DailyRecord(
                date: targetDate,
                steps: record.steps,
                sleepHours: 0,
                floors: 0,
                obtainedItemId: item?.id,
                goalSteps: goalSteps
            ))
        }

        isInitialSetupDone = true
        UserDefaults.standard.set(true, forKey: initialSetupKey)
        try? ctx.save()
    }

    // MARK: - 差分補完
    // 最後に保存した日〜昨日の間が空いている場合に呼ぶ

    /// 補完が必要な日付（保存済みの翌日〜昨日）を返す
    func missingDates() -> [Date] {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1,
                                      to: calendar.startOfDay(for: Date()))!

        // 既存のdateKeyセット
        let existingKeys = Set(fetchAllRecords().map { $0.dateKey })

        // 過去365日のうち未保存の日
        var missing: [Date] = []
        for i in 1...365 {
            let d = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: Date()))!
            if d > yesterday { continue }
            let key = DailyRecord.makeKey(from: d)
            if !existingKeys.contains(key) { missing.append(d) }
        }
        return missing.sorted()
    }

    // MARK: - 完了処理

    func completeOnboarding() {
        isOnboardingDone = true
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }

    // MARK: - リセット

    func resetAll() {
        guard let ctx = modelContext else { return }
        try? ctx.delete(model: DailyRecord.self)
        try? ctx.delete(model: CollectionData.self)
        try? ctx.save()

        todaysItems     = []
        lastFetchedDate = nil
        isInitialSetupDone = false
        isOnboardingDone   = false

        for key in ["collection", "lastFetchedDate", "initialSetupDone",
                    "onboardingDone", "dailyHistory", "goalSteps", lastFetchedKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - デバッグ

    func debugApplyResult(steps: Int) {
        applyDailyResult(steps: steps, sleepHours: 7.0, floors: 3,
                         for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
    }

    // MARK: - 分析ヘルパー（Wrapped用）

    func history(from start: Date, to end: Date) -> [DailyRecord] {
        guard let ctx = modelContext else { return [] }
        let desc = FetchDescriptor<DailyRecord>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? ctx.fetch(desc)) ?? []
    }

    func longestStreak(in records: [DailyRecord]) -> (count: Int, start: Date?, end: Date?) {
        var longest = 0, current = 0
        var streakStart: Date?, tempStart: Date?, streakEnd: Date?
        for r in records.sorted(by: { $0.date < $1.date }) {
            if r.isGoalAchieved {
                if current == 0 { tempStart = r.date }
                current += 1
                if current > longest {
                    longest = current
                    streakStart = tempStart
                    streakEnd = r.date
                }
            } else { current = 0; tempStart = nil }
        }
        return (longest, streakStart, streakEnd)
    }

    func averageStepsByWeekday(in records: [DailyRecord]) -> [Int: Double] {
        var buckets: [Int: [Int]] = [:]
        for r in records {
            let wd = Calendar.current.component(.weekday, from: r.date)
            buckets[wd, default: []].append(r.steps)
        }
        return buckets.mapValues { Double($0.reduce(0, +)) / Double($0.count) }
    }

    func monthlyAverageSteps(in records: [DailyRecord]) -> [(month: Date, average: Double)] {
        var buckets: [Date: [Int]] = [:]
        for r in records {
            let m = Calendar.current.startOfMonth(for: r.date)
            buckets[m, default: []].append(r.steps)
        }
        return buckets
            .map { (month: $0.key, average: Double($0.value.reduce(0, +)) / Double($0.value.count)) }
            .sorted { $0.month < $1.month }
    }

    var bestDay: DailyRecord? { fetchAllRecords().max(by: { $0.steps < $1.steps }) }
}
