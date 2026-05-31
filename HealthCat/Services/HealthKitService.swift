import HealthKit
import Foundation

// MARK: - HealthKitService
// すべてのメソッドを async/await で提供。コールバックなし。

final class HealthKitService {
    private let store = HKHealthStore()

    private let stepType     = HKQuantityType(.stepCount)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)
    private let floorType    = HKQuantityType(.flightsClimbed)
    private let calType      = HKQuantityType(.activeEnergyBurned)
    private let exerciseType = HKQuantityType(.appleExerciseTime)
    private let sleepType    = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

    // MARK: - 取得データ型

    struct DailyHealthData {
        let date: Date
        let steps: Int
        let sleepHours: Double
        let floors: Int
    }

    struct DailyActivity: Identifiable {
        let id = UUID()
        let date: Date
        var steps: Int = 0
        var distanceKm: Double = 0
        var floors: Int = 0
        var calories: Int = 0
        var exerciseMinutes: Int = 0
    }

    // MARK: - 認証

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let types: Set<HKObjectType> = [
            stepType, distanceType, floorType, calType, exerciseType, sleepType
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            return true
        } catch {
            return false
        }
    }

    // MARK: - 1日分取得

    func fetchDayData(for date: Date) async -> DailyHealthData {
        let calendar = Calendar.current
        let start    = calendar.startOfDay(for: date)
        let end      = calendar.date(byAdding: .day, value: 1, to: start)!

        let sleepStart = calendar.date(
            byAdding: .hour, value: 20,
            to: calendar.date(byAdding: .day, value: -1, to: start)!)!
        let sleepEnd = calendar.date(byAdding: .hour, value: 10, to: start)!

        async let steps  = fetchSteps(from: start, to: end)
        async let floors = fetchQuantity(type: floorType, from: start, to: end, unit: .count())
        async let sleep  = fetchSleep(from: sleepStart, to: sleepEnd)

        return await DailyHealthData(
            date: start,
            steps: steps,
            sleepHours: sleep,
            floors: Int(floors)
        )
    }

    func fetchYesterdayData() async -> DailyHealthData {
        let yesterday = Calendar.current.date(
            byAdding: .day, value: -1,
            to: Calendar.current.startOfDay(for: Date()))!
        return await fetchDayData(for: yesterday)
    }

    // MARK: - 複数日一括取得

    func fetchPastDaysSteps(days: Int) async -> [(date: Date, steps: Int)] {
        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: Date())

        return await withTaskGroup(of: (Date, Int).self) { group in
            for i in 1...max(1, days) {
                let start = calendar.date(byAdding: .day, value: -i, to: today)!
                let end   = calendar.date(byAdding: .day, value:  1, to: start)!
                group.addTask {
                    let s = await self.fetchSteps(from: start, to: end)
                    return (start, s)
                }
            }
            var results: [(Date, Int)] = []
            for await pair in group { results.append(pair) }
            return results.sorted { $0.0 < $1.0 }
        }
    }

    func fetchDailyData(for dates: [Date]) async -> [DailyHealthData] {
        guard !dates.isEmpty else { return [] }
        return await withTaskGroup(of: DailyHealthData.self) { group in
            for date in dates {
                group.addTask { await self.fetchDayData(for: date) }
            }
            var results: [DailyHealthData] = []
            for await data in group { results.append(data) }
            return results.sorted { $0.date < $1.date }
        }
    }

    // MARK: - 活動履歴（きろく画面用）

    func fetchActivityHistory(days: Int) async -> [DailyActivity] {
        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: Date())

        return await withTaskGroup(of: DailyActivity.self) { group in
            for i in 1...max(1, days) {
                let date = calendar.date(byAdding: .day, value: -i, to: today)!
                let end  = calendar.date(byAdding: .day, value: 1, to: date)!
                group.addTask {
                    async let steps    = self.fetchSteps(from: date, to: end)
                    async let distance = self.fetchQuantity(
                        type: self.distanceType, from: date, to: end, unit: .meter())
                    async let floors   = self.fetchQuantity(
                        type: self.floorType, from: date, to: end, unit: .count())
                    async let calories = self.fetchQuantity(
                        type: self.calType, from: date, to: end, unit: .kilocalorie())
                    async let exercise = self.fetchQuantity(
                        type: self.exerciseType, from: date, to: end, unit: .minute())
                    return await DailyActivity(
                        date: date,
                        steps: steps,
                        distanceKm: distance / 1000,
                        floors: Int(floors),
                        calories: Int(calories),
                        exerciseMinutes: Int(exercise)
                    )
                }
            }
            var results: [DailyActivity] = []
            for await activity in group { results.append(activity) }
            // 古い順で返す（UI側が suffix(7) で直近7日を取れるように）
            return results.sorted { $0.date < $1.date }
        }
    }

    // MARK: - 内部実装（withCheckedContinuation でコールバックをラップ）

    private func fetchSteps(from start: Date, to end: Date) async -> Int {
        Int(await fetchQuantity(type: stepType, from: start, to: end, unit: .count()))
    }

    private func fetchQuantity(type: HKQuantityType, from start: Date, to end: Date,
                               unit: HKUnit) async -> Double {
        await withCheckedContinuation { continuation in
            let pred = HKQuery.predicateForSamples(
                withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: pred,
                options: .cumulativeSum
            ) { _, result, _ in
                continuation.resume(
                    returning: result?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func fetchSleep(from start: Date, to end: Date) async -> Double {
        await withCheckedContinuation { continuation in
            let pred = HKQuery.predicateForSamples(
                withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: pred,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                let secs = (samples as? [HKCategorySample])?.filter {
                    [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                     HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                     HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                     HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains($0.value)
                }.reduce(0.0) {
                    $0 + $1.endDate.timeIntervalSince($1.startDate)
                } ?? 0
                continuation.resume(returning: secs / 3600)
            }
            self.store.execute(query)
        }
    }
}
