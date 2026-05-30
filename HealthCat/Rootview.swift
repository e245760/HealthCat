import SwiftUI

struct RootView: View {
    @StateObject private var gameState = GameState()
    @StateObject private var healthKit = HealthKitManager()
    @State private var isSettingUp = false

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

                SettingsView(gameState: gameState)
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("設定")
                    }
            }
            .onAppear {
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }

            // 初回セットアップ中のローディング
            if isSettingUp {
                ZStack {
                    Color(.systemBackground).opacity(0.9).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("過去のきろくを確認中…")
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

    // MARK: - オンボーディング完了後の処理

    private func finishOnboarding() {
        gameState.completeOnboarding()
        setupIfNeeded()
    }

    // MARK: - HealthKit初期化

    private func setupIfNeeded() {
        healthKit.requestAuthorization { success in
            guard success else { return }

            if !gameState.isInitialSetupDone {
                isSettingUp = true
                healthKit.fetchPast7DaysSteps { dailySteps in
                    gameState.applyHistoricalData(dailySteps: dailySteps)
                    isSettingUp = false
                    fetchYesterday()
                }
            } else if !gameState.hasAlreadyFetchedToday {
                fetchYesterday()
            }
        }
    }

    private func fetchYesterday() {
        healthKit.fetchYesterdayData { data in
            gameState.applyDailyResult(
                steps: data.steps,
                sleepHours: data.sleepHours,
                floors: data.floors
            )
        }
    }
}
