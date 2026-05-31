import Foundation
import SwiftData

// MARK: - 日別記録（SwiftData永続化）

@Model
final class DailyRecord {
    @Attribute(.unique) var dateKey: String
    var date: Date
    var steps: Int
    var sleepHours: Double
    var floors: Int
    var obtainedItemId: String?
    var goalSteps: Int

    init(date: Date, steps: Int, sleepHours: Double, floors: Int,
         obtainedItemId: String?, goalSteps: Int) {
        self.date        = Calendar.current.startOfDay(for: date)
        self.dateKey     = Self.makeKey(from: date)
        self.steps       = steps
        self.sleepHours  = sleepHours
        self.floors      = floors
        self.obtainedItemId = obtainedItemId
        self.goalSteps   = goalSteps
    }

    static func makeKey(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.timeZone   = TimeZone.current
        return f.string(from: date)
    }

    var achievementRate: Double {
        guard goalSteps > 0 else { return 0 }
        return min(1.0, Double(steps) / Double(goalSteps))
    }

    var isGoalAchieved: Bool { steps >= goalSteps }
}
