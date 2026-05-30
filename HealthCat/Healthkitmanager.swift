import HealthKit
import Foundation
import Combine

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()

    private let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
    private let floorType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed)!
    private let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

    // MARK: - 認証

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        let types: Set<HKObjectType> = [
            stepType, distanceType, floorType, calType, exerciseType, sleepType
        ]
        healthStore.requestAuthorization(toShare: [], read: types) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    // MARK: - 前日データ（毎日の処理用）

    struct DailyHealthData {
        var steps: Int
        var sleepHours: Double
        var floors: Int
    }

    func fetchYesterdayData(completion: @escaping (DailyHealthData) -> Void) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let group = DispatchGroup()
        var steps = 0
        var floors = 0
        var sleepHours = 0.0

        group.enter()
        fetchSteps(from: yesterday, to: today) { value in
            steps = value; group.leave()
        }

        group.enter()
        fetchQuantity(type: floorType, from: yesterday, to: today, unit: .count()) { value in
            floors = Int(value); group.leave()
        }

        group.enter()
        let sleepStart = calendar.date(byAdding: .hour, value: 20, to: yesterday)!
        let sleepEnd = calendar.date(byAdding: .hour, value: 10, to: today)!
        fetchSleep(from: sleepStart, to: sleepEnd) { hours in
            sleepHours = hours; group.leave()
        }

        group.notify(queue: .main) {
            completion(DailyHealthData(steps: steps, sleepHours: sleepHours, floors: floors))
        }
    }

    // MARK: - 過去7日分の歩数（初回セットアップ用）

    func fetchPast7DaysSteps(completion: @escaping ([(date: Date, steps: Int)]) -> Void) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let group = DispatchGroup()
        var results: [(date: Date, steps: Int)] = []
        let lock = NSLock()

        // 1〜7日前（前日を1とする）
        for i in 1...7 {
            let start = calendar.date(byAdding: .day, value: -i, to: today)!
            let end = calendar.date(byAdding: .day, value: 1, to: start)!

            group.enter()
            fetchSteps(from: start, to: end) { steps in
                lock.lock()
                results.append((date: start, steps: steps))
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            // 古い順に並べ直す
            let sorted = results.sorted { $0.date < $1.date }
            completion(sorted)
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

    func fetchActivityHistory(days: Int, completion: @escaping ([DailyActivity]) -> Void) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var activities: [DailyActivity] = (1...days).map { i in
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            return DailyActivity(date: date)
        }

        let group = DispatchGroup()

        for i in 0..<activities.count {
            let start = activities[i].date
            let end = calendar.date(byAdding: .day, value: 1, to: start)!

            group.enter()
            fetchSteps(from: start, to: end) { value in
                activities[i].steps = value; group.leave()
            }

            group.enter()
            fetchQuantity(type: distanceType, from: start, to: end, unit: .meter()) { value in
                activities[i].distanceKm = value / 1000; group.leave()
            }

            group.enter()
            fetchQuantity(type: floorType, from: start, to: end, unit: .count()) { value in
                activities[i].floors = Int(value); group.leave()
            }

            group.enter()
            fetchQuantity(type: calType, from: start, to: end, unit: .kilocalorie()) { value in
                activities[i].calories = Int(value); group.leave()
            }

            group.enter()
            fetchQuantity(type: exerciseType, from: start, to: end, unit: .minute()) { value in
                activities[i].exerciseMinutes = Int(value); group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(activities.reversed())
        }
    }

    // MARK: - 内部実装

    private func fetchSteps(from start: Date, to end: Date, completion: @escaping (Int) -> Void) {
        fetchQuantity(type: stepType, from: start, to: end, unit: .count()) { value in
            completion(Int(value))
        }
    }

    private func fetchQuantity(
        type: HKQuantityType,
        from start: Date,
        to end: Date,
        unit: HKUnit,
        completion: @escaping (Double) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, _ in
            let value = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
            DispatchQueue.main.async { completion(value) }
        }
        healthStore.execute(query)
    }

    private func fetchSleep(from start: Date, to end: Date, completion: @escaping (Double) -> Void) {
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, _ in
            let totalSeconds = (samples as? [HKCategorySample])?.filter {
                $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
            }.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0
            DispatchQueue.main.async { completion(totalSeconds / 3600) }
        }
        healthStore.execute(query)
    }
}
