import Foundation
import SwiftData
import Observation

// MARK: - DataRepository
// SwiftData の CRUD を一手に担う。
// @Observable により、history / collection の変化が UI に自動伝播する。
// ModelContext はメインスレッド専用のため @MainActor。

@Observable
@MainActor
final class DataRepository {

    // MARK: - インメモリキャッシュ（@Observable で追跡される）
    private(set) var history:    [DailyRecord]  = []
    private(set) var collection: CollectionData

    private let modelContext: ModelContext

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        // 履歴をロード
        let desc = FetchDescriptor<DailyRecord>(sortBy: [SortDescriptor(\.date)])
        self.history = (try? modelContext.fetch(desc)) ?? []

        // コレクションをロード（なければ新規作成）
        let colDesc = FetchDescriptor<CollectionData>()
        if let existing = try? modelContext.fetch(colDesc).first {
            self.collection = existing
        } else {
            let new = CollectionData()
            modelContext.insert(new)
            try? modelContext.save()
            self.collection = new
        }
    }

    // MARK: - クエリ（キャッシュから返す・DB アクセスなし）

    func findRecord(for date: Date) -> DailyRecord? {
        let key = DailyRecord.makeKey(from: date)
        return history.first { $0.dateKey == key }
    }

    var yesterdayRecord: DailyRecord? {
        let yesterday = Calendar.current.date(
            byAdding: .day, value: -1,
            to: Calendar.current.startOfDay(for: Date()))!
        return findRecord(for: yesterday) ?? history.last
    }

    // MARK: - 書き込み

    /// 1日分のデータを保存（既存レコードがあれば更新）
    @discardableResult
    func saveRecord(date: Date, steps: Int, sleepHours: Double,
                    floors: Int, goalSteps: Int) -> Item? {
        let targetDate = Calendar.current.startOfDay(for: date)
        let item = ItemDatabase.shared.determineItem(steps: steps)

        if let existing = findRecord(for: targetDate) {
            existing.steps          = steps
            existing.sleepHours     = sleepHours
            existing.floors         = floors
            existing.obtainedItemId = item?.id
            existing.goalSteps      = goalSteps
        } else {
            let record = DailyRecord(
                date: targetDate, steps: steps, sleepHours: sleepHours,
                floors: floors, obtainedItemId: item?.id, goalSteps: goalSteps)
            modelContext.insert(record)
            history.append(record)
            history.sort { $0.date < $1.date }

            if let item {
                collection.add(itemId: item.id)
                collection.lastObtainedItemId = item.id
            }
        }

        try? modelContext.save()
        return item
    }

    /// 初回セットアップ・再取得用：歩数のみのバルク保存
    func saveHistoricalData(dailySteps: [(date: Date, steps: Int)], goalSteps: Int) {
        for entry in dailySteps {
            let targetDate = Calendar.current.startOfDay(for: entry.date)
            guard findRecord(for: targetDate) == nil else { continue }

            let item = ItemDatabase.shared.determineItem(steps: entry.steps)
            if let item { collection.add(itemId: item.id) }

            let record = DailyRecord(
                date: targetDate, steps: entry.steps, sleepHours: 0,
                floors: 0, obtainedItemId: item?.id, goalSteps: goalSteps)
            modelContext.insert(record)
            history.append(record)
        }
        history.sort { $0.date < $1.date }
        try? modelContext.save()
    }

    // MARK: - リセット

    func reset() {
        try? modelContext.delete(model: DailyRecord.self)
        try? modelContext.delete(model: CollectionData.self)
        try? modelContext.save()

        history = []

        let new = CollectionData()
        modelContext.insert(new)
        try? modelContext.save()
        collection = new
    }
}
