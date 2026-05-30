import SwiftUI
import SwiftData

struct RootView: View {
    @StateObject private var gameState = GameState()
    @StateObject private var healthKit = HealthKitManager()
    @State private var isSettingUp = false
    @State private var setupMessage = "過去のきろくを確認中…"

    // SwiftDataのcontextを環境から受け取る
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            TabView {
                CatView(gameState: gameState, healthKit: healthKit)
                    .tabItem {
                        Image(systemName: "pawprint.fill")
                        Text("ネコ")
                    }

                ActivityTrackingView(healthKit: healthKit, gameState: gameState)
                    .tabItem {
                        Image(systemName: "chart.bar.fill")
                        Text("きろく")
                    }

                CollectionView(gameState: gameState)
                    .tabItem {
                        Image(systemName: "bag.fill")
                        Text("コレクション")
                    }

                SettingsView(gameState: gameState, healthKit: healthKit)
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("設定")
                    }
            }
            .onAppear {
                // modelContextをGameStateに注入
                gameState.modelContext = modelContext

                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }

            // セットアップ中オーバーレイ
            if isSettingUp {
                ZStack {
                    Color(.systemBackground).opacity(0.9).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                        Text(setupMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        // オンボーディング（初回のみ）
        .fullScreenCover(isPresented: Binding(
            get: { !gameState.isOnboardingDone },
            set: { _ in }
        )) {
            OnboardingView(
                isPresented: Binding(
                    get: { !gameState.isOnboardingDone },
                    set: { if !$0 { finishOnboarding() } }
                ),
                gameState: gameState
            )
        }
    }

    // MARK: - オンボーディング完了後

    private func finishOnboarding() {
        gameState.completeOnboarding()
        setupIfNeeded()
    }

    // MARK: - 起動時フロー

    private func setupIfNeeded() {
        healthKit.requestAuthorization { success in
            guard success else { return }

            if !gameState.isInitialSetupDone {
                // 初回: 過去365日の歩数を一括取得してSwiftDataに保存
                isSettingUp = true
                setupMessage = "過去1年のきろくを確認中…"

                healthKit.fetchPastDaysSteps(days: 365) { dailySteps in
                    gameState.applyHistoricalData(dailySteps: dailySteps)
                    // 初回セットアップ後に差分補完（睡眠・階数含む全データ）
                    fillMissingData {
                        isSettingUp = false
                        fetchYesterday()
                    }
                }
            } else {
                // 2回目以降: 差分補完してから前日を取得
                fillMissingData {
                    if !gameState.hasAlreadyFetchedToday {
                        fetchYesterday()
                    }
                }
            }
        }
    }

    // MARK: - 差分補完
    // 保存されていない日を最大365日分遡って埋める

    private func fillMissingData(completion: @escaping () -> Void) {
        let missing = gameState.missingDates()
        guard !missing.isEmpty else { completion(); return }

        isSettingUp = true
        setupMessage = "\(missing.count)日分のきろくを補完中…"

        healthKit.fetchDailyData(for: missing) { dataList in
            for data in dataList {
                gameState.applyDailyResult(
                    steps: data.steps,
                    sleepHours: data.sleepHours,
                    floors: data.floors,
                    for: data.date
                )
            }
            isSettingUp = false
            completion()
        }
    }

    // MARK: - 前日データ取得

    private func fetchYesterday() {
        healthKit.fetchYesterdayData { data in
            gameState.applyDailyResult(
                steps: data.steps,
                sleepHours: data.sleepHours,
                floors: data.floors,
                for: data.date
            )
        }
    }
}
