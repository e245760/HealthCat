import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            TabView {
                CatView()
                    .tabItem {
                        Image(systemName: "pawprint.fill")
                        Text("ネコ")
                    }

                RecordsHubView()
                    .tabItem {
                        Image(systemName: "chart.bar.fill")
                        Text("きろく")
                    }

                CollectionView()
                    .tabItem {
                        Image(systemName: "bag.fill")
                        Text("コレクション")
                    }

                SettingsView()
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("設定")
                    }
            }
            .onAppear {
                // ModelContext を Coordinator に注入してからセットアップ開始
                coordinator.configure(modelContext: modelContext)

                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                UITabBar.appearance().standardAppearance    = appearance
                UITabBar.appearance().scrollEdgeAppearance  = appearance
            }
            .task {
                // オンボーディング完了済みなら即セットアップ
                if coordinator.isOnboardingDone {
                    await coordinator.startSetupIfNeeded()
                }
            }

            // セットアップ中オーバーレイ
            if coordinator.isSettingUp {
                setupOverlay
            }
        }
        // オンボーディング（初回のみ）
        .fullScreenCover(isPresented: Binding(
            get:  { !coordinator.isOnboardingDone },
            set:  { _ in }
        )) {
            OnboardingView()
        }
    }

    private var setupOverlay: some View {
        ZStack {
            Color(.systemBackground).opacity(0.9).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                Text(coordinator.setupMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
