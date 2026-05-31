import Foundation

// MARK: - AnalyticsEngine
// 副作用なし・テスト可能な純粋関数のみ

enum AnalyticsEngine {

    // MARK: - ストリーク

    struct StreakResult {
        let count: Int
        let start: Date?
        let end: Date?
    }

    static func longestStreak(in records: [DailyRecord]) -> StreakResult {
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
            } else {
                current = 0
                tempStart = nil
            }
        }
        return StreakResult(count: longest, start: streakStart, end: streakEnd)
    }

    // MARK: - 曜日別平均

    static func averageStepsByWeekday(in records: [DailyRecord]) -> [Int: Double] {
        var buckets: [Int: [Int]] = [:]
        for r in records {
            let wd = Calendar.current.component(.weekday, from: r.date)
            buckets[wd, default: []].append(r.steps)
        }
        return buckets.mapValues { Double($0.reduce(0, +)) / Double($0.count) }
    }

    // MARK: - 月別平均

    static func monthlyAverageSteps(in records: [DailyRecord]) -> [(month: Date, average: Double)] {
        var buckets: [Date: [Int]] = [:]
        for r in records {
            let m = Calendar.current.startOfMonth(for: r.date)
            buckets[m, default: []].append(r.steps)
        }
        return buckets
            .map { (month: $0.key, average: Double($0.value.reduce(0, +)) / Double($0.value.count)) }
            .sorted { $0.month < $1.month }
    }

    // MARK: - ベスト日

    static func bestDay(in records: [DailyRecord]) -> DailyRecord? {
        records.max(by: { $0.steps < $1.steps })
    }

    // MARK: - 差分日付（データが欠けている日の一覧）

    static func missingDates(existing records: [DailyRecord]) -> [Date] {
        let calendar  = Calendar.current
        let today     = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let existingKeys = Set(records.map { $0.dateKey })

        return (1...365).compactMap { i -> Date? in
            let d = calendar.date(byAdding: .day, value: -i, to: today)!
            guard d <= yesterday else { return nil }
            return existingKeys.contains(DailyRecord.makeKey(from: d)) ? nil : d
        }.sorted()
    }
}

// MARK: - Calendar extension

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
