import HealthKit
import Foundation
import Combine

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()

    private let stepType     = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
    private let floorType    = HKQuantityType.quantityType(forIdentifier: .flightsClimbed)!
    private let calType      = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
    private let sleepType    = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

    // MARK: - 認証

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { completion(false); return }
        let types: Set<HKObjectType> = [
            stepType, distanceType, floorType, calType, exerciseType, sleepType
        ]
        healthStore.requestAuthorization(toShare: [], read: types) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    // MARK: - 前日データ

    struct DailyHealthData {
        var date: Date
        var steps: Int
        var sleepHours: Double
        var floors: Int
    }

    func fetchYesterdayData(completion: @escaping (DailyHealthData) -> Void) {
        let calendar = Calendar.current
        let today     = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        fetchDayData(for: yesterday, completion: completion)
    }

    // MARK: - 任意の日のデータ

    func fetchDayData(for date: Date, completion: @escaping (DailyHealthData) -> Void) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end   = calendar.date(byAdding: .day, value: 1, to: start)!

        let group = DispatchGroup()
        var steps = 0, floors = 0
        var sleepHours = 0.0

        group.enter()
        fetchSteps(from: start, to: end) { v in steps = v; group.leave() }

        group.enter()
        fetchQuantity(type: floorType, from: start, to: end, unit: .count()) { v in
            floors = Int(v); group.leave()
        }

        group.enter()
        // 睡眠は前日20時〜当日10時
        let sleepStart = calendar.date(byAdding: .hour, value: 20,
                                       to: calendar.date(byAdding: .day, value: -1, to: start)!)!
        let sleepEnd   = calendar.date(byAdding: .hour, value: 10, to: start)!
        fetchSleep(from: sleepStart, to: sleepEnd) { h in sleepHours = h; group.leave() }

        group.notify(queue: .main) {
            completion(DailyHealthData(date: start, steps: steps,
                                       sleepHours: sleepHours, floors: floors))
        }
    }

    // MARK: - 複数日の一括取得（差分補完・初回セットアップ用）

    func fetchDailyData(for dates: [Date],
                        completion: @escaping ([DailyHealthData]) -> Void) {
        guard !dates.isEmpty else { completion([]); return }

        let group = DispatchGroup()
        var results: [DailyHealthData] = []
        let lock = NSLock()

        for date in dates {
            group.enter()
            fetchDayData(for: date) { data in
                lock.lock()
                results.append(data)
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(results.sorted { $0.date < $1.date })
        }
    }

    // MARK: - 過去N日分の歩数のみ（初回セットアップ軽量版）

    func fetchPastDaysSteps(days: Int,
                            completion: @escaping ([(date: Date, steps: Int)]) -> Void) {
        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: Date())
        let group    = DispatchGroup()
        var results: [(date: Date, steps: Int)] = []
        let lock     = NSLock()

        for i in 1...max(1, days) {
            let start = calendar.date(byAdding: .day, value: -i, to: today)!
            let end   = calendar.date(byAdding: .day, value: 1, to: start)!
            group.enter()
            fetchSteps(from: start, to: end) { steps in
                lock.lock()
                results.append((date: start, steps: steps))
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(results.sorted { $0.date < $1.date })
        }
    }

    // MARK: - 活動履歴（きろく画面用）

    struct DailyActivity: Identifiable {
        let id = UUID()
        let date: Date
        var steps: Int = 0
        var distanceKm: Double = 0
        var floors: Int = 0
        var calories: Int = 0
        var exerciseMinutes: Int = 0
    }

    func fetchActivityHistory(days: Int,
                              completion: @escaping ([DailyActivity]) -> Void) {
        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: Date())

        var activities: [DailyActivity] = (1...max(1, days)).map { i in
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            return DailyActivity(date: date)
        }

        let group = DispatchGroup()

        for i in 0..<activities.count {
            let start = activities[i].date
            let end   = calendar.date(byAdding: .day, value: 1, to: start)!

            group.enter()
            fetchSteps(from: start, to: end) { v in activities[i].steps = v; group.leave() }

            group.enter()
            fetchQuantity(type: distanceType, from: start, to: end, unit: .meter()) { v in
                activities[i].distanceKm = v / 1000; group.leave()
            }

            group.enter()
            fetchQuantity(type: floorType, from: start, to: end, unit: .count()) { v in
                activities[i].floors = Int(v); group.leave()
            }

            group.enter()
            fetchQuantity(type: calType, from: start, to: end, unit: .kilocalorie()) { v in
                activities[i].calories = Int(v); group.leave()
            }

            group.enter()
            fetchQuantity(type: exerciseType, from: start, to: end, unit: .minute()) { v in
                activities[i].exerciseMinutes = Int(v); group.leave()
            }
        }

        group.notify(queue: .main) { completion(activities.reversed()) }
    }

    // MARK: - 内部実装

    private func fetchSteps(from start: Date, to end: Date,
                            completion: @escaping (Int) -> Void) {
        fetchQuantity(type: stepType, from: start, to: end, unit: .count()) {
            completion(Int($0))
        }
    }

    private func fetchQuantity(type: HKQuantityType, from start: Date, to end: Date,
                               unit: HKUnit, completion: @escaping (Double) -> Void) {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end,
                                               options: .strictStartDate)
        let q = HKStatisticsQuery(quantityType: type,
                                  quantitySamplePredicate: pred,
                                  options: .cumulativeSum) { _, result, _ in
            let v = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
            DispatchQueue.main.async { completion(v) }
        }
        healthStore.execute(q)
    }

    private func fetchSleep(from start: Date, to end: Date,
                            completion: @escaping (Double) -> Void) {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end,
                                               options: .strictStartDate)
        let q = HKSampleQuery(sampleType: sleepType, predicate: pred,
                              limit: HKObjectQueryNoLimit,
                              sortDescriptors: nil) { _, samples, _ in
            let secs = (samples as? [HKCategorySample])?.filter {
                [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                 HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                 HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains($0.value)
            }.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0
            DispatchQueue.main.async { completion(secs / 3600) }
        }
        healthStore.execute(q)
    }
}
