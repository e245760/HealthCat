import Foundation
import SwiftData
import Observation

// MARK: - AppCoordinator
// アプリ全体のフローを管理するシングルトン的な状態クラス。
// - オンボーディング / 初回セットアップ / 差分補完 の順序制御
// - Views は @Environment で取得し、repository / healthKit に間接アクセス

@Observable
@MainActor
final class AppCoordinator {

    // MARK: - 永続化された設定（UserDefaults）

    var goalSteps: Int {
        didSet { UserDefaults.standard.set(goalSteps, forKey: "goalSteps") }
    }
    var isOnboardingDone: Bool
    var lastFetchedDate: Date? {
        didSet { UserDefaults.standard.set(lastFetchedDate, forKey: "lastFetchedDate") }
    }

    // MARK: - セットアップ進捗（UI表示用）

    var isSettingUp:  Bool   = false
    var setupMessage: String = ""

    // MARK: - 今日のアイテム（CatView 表示用）

    var todaysItems: [Item] = []

    // MARK: - 依存サービス

    let healthKit: HealthKitService
    private(set) var repository: DataRepository?

    // MARK: - 内部状態

    private var isInitialSetupDone: Bool {
        get { UserDefaults.standard.bool(forKey: "initialSetupDone") }
        set { UserDefaults.standard.set(newValue, forKey: "initialSetupDone") }
    }

    var hasAlreadyFetchedToday: Bool {
        guard let last = lastFetchedDate else { return false }
        return Calendar.current.isDateInToday(last)
    }

    // MARK: - 計算プロパティ（repository への糖衣）

    var achievementRate:    Double { repository?.yesterdayRecord?.achievementRate ?? 0 }
    var achievementPercent: Int    { Int(achievementRate * 100) }
    var collectedCount:     Int    { repository?.collection.totalObtainedKinds ?? 0 }
    var totalItemCount:     Int    { ItemDatabase.shared.allItems.count }

    // MARK: - Init

    init() {
        self.healthKit       = HealthKitService()
        self.isOnboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone")
        self.lastFetchedDate  = UserDefaults.standard.object(forKey: "lastFetchedDate") as? Date
        let saved = UserDefaults.standard.integer(forKey: "goalSteps")
        self.goalSteps = saved > 0 ? saved : 8000
    }

    // MARK: - ModelContext 注入（RootView.onAppear から1回だけ呼ぶ）

    func configure(modelContext: ModelContext) {
        guard repository == nil else { return }
        repository = DataRepository(modelContext: modelContext)
    }

    // MARK: - オンボーディング

    func completeOnboarding() {
        isOnboardingDone = true
        UserDefaults.standard.set(true, forKey: "onboardingDone")
    }

    // MARK: - 起動フロー

    func startSetupIfNeeded() async {
        let authorized = await healthKit.requestAuthorization()
        guard authorized, let repo = repository else { return }

        if !isInitialSetupDone {
            // 初回: 過去365日の歩数を一括取得
            isSettingUp  = true
            setupMessage = "過去1年のきろくを確認中…"

            let dailySteps = await healthKit.fetchPastDaysSteps(days: 365)
            repo.saveHistoricalData(dailySteps: dailySteps, goalSteps: goalSteps)
            isInitialSetupDone = true

            await fillMissingData(repo: repo)
            await fetchAndApplyYesterday(repo: repo)
            isSettingUp = false

        } else {
            // 2回目以降: 差分補完してから前日を取得
            await fillMissingData(repo: repo)
            if !hasAlreadyFetchedToday {
                await fetchAndApplyYesterday(repo: repo)
            }
        }
    }

    // MARK: - 差分補完

    private func fillMissingData(repo: DataRepository) async {
        let missing = AnalyticsEngine.missingDates(existing: repo.history)
        guard !missing.isEmpty else { return }

        isSettingUp  = true
        setupMessage = "\(missing.count)日分のきろくを補完中…"

        let dataList = await healthKit.fetchDailyData(for: missing)
        for data in dataList {
            repo.saveRecord(date: data.date, steps: data.steps,
                            sleepHours: data.sleepHours, floors: data.floors,
                            goalSteps: goalSteps)
        }
        isSettingUp = false
    }

    // MARK: - 前日データ取得

    private func fetchAndApplyYesterday(repo: DataRepository) async {
        let data = await healthKit.fetchYesterdayData()
        let item = repo.saveRecord(
            date: data.date, steps: data.steps,
            sleepHours: data.sleepHours, floors: data.floors,
            goalSteps: goalSteps)
        todaysItems  = item.map { [$0] } ?? []
        lastFetchedDate = Date()
    }

    // MARK: - データ再取得（設定画面から）

    func refetch() async -> Int {
        guard await healthKit.requestAuthorization(), let repo = repository else { return 0 }

        repo.reset()
        isInitialSetupDone = false
        todaysItems = []

        isSettingUp  = true
        setupMessage = "過去365日分を取得中…"

        let dailySteps = await healthKit.fetchPastDaysSteps(days: 365)
        repo.saveHistoricalData(dailySteps: dailySteps, goalSteps: goalSteps)
        isInitialSetupDone = true

        setupMessage = "睡眠・階数を補完中…"
        let missing  = AnalyticsEngine.missingDates(existing: repo.history)
        if !missing.isEmpty {
            let dataList = await healthKit.fetchDailyData(for: missing)
            for data in dataList {
                repo.saveRecord(date: data.date, steps: data.steps,
                                sleepHours: data.sleepHours, floors: data.floors,
                                goalSteps: goalSteps)
            }
        }
        isSettingUp = false
        return dailySteps.count
    }

    // MARK: - 全リセット

    func resetAll() {
        repository?.reset()
        todaysItems         = []
        lastFetchedDate     = nil
        isInitialSetupDone  = false
        isOnboardingDone    = false

        ["lastFetchedDate", "initialSetupDone", "onboardingDone", "goalSteps"]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    // MARK: - デバッグ

    func debugApplyResult(steps: Int) {
        guard let repo = repository else { return }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let item = repo.saveRecord(date: yesterday, steps: steps,
                                   sleepHours: 7.0, floors: 3, goalSteps: goalSteps)
        todaysItems = item.map { [$0] } ?? []
    }
}
