import SwiftUI

struct CatView: View {
    @ObservedObject var gameState: GameState
    @ObservedObject var healthKit: HealthKitManager

    @State private var showMonologue = false
    @State private var monologueText = ""
    @State private var showDebugAlert = false
    @State private var showNewItems = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // ネコウィンドウ（画面の1/3）
                    catWindow
                        .padding(.horizontal)

                    // 昨日のデータカード
                    yesterdayStatsSection
                        .padding(.horizontal)

                    // 拾ってきたもの
                    todaysItemsSection
                        .padding(.horizontal)

                    #if DEBUG
                    Button("🐛 テスト用データ") { showDebugAlert = true }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 8)
                    #endif
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("HealthCat")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showNewItems) {
            NewItemsView(items: gameState.todaysItems)
        }
        .alert("デバッグ: 結果を追加", isPresented: $showDebugAlert) {
            Button("1000歩") { gameState.debugApplyResult(steps: 1000) }
            Button("5000歩") { gameState.debugApplyResult(steps: 5000) }
            Button("10000歩") { gameState.debugApplyResult(steps: 10000) }
            Button("キャンセル", role: .cancel) {}
        }
.onAppear {}
    }

    // MARK: - ネコウィンドウ

    private var catWindow: some View {
        GeometryReader { geo in
            ZStack {
                // 3Dネコ
                CatSceneView()
                    .onTapGesture { triggerMonologue() }

                // 独り言
                if showMonologue {
                    VStack {
                        Spacer()
                        Text(monologueText)
                            .font(.callout)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThickMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                    }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                // コレクション進捗（右上）
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Text("🎒")
                            Text("\(gameState.collectedCount)/\(gameState.totalCount)")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(12)
                    }
                    Spacer()
                }
            }
            .frame(height: geo.size.width * 0.85) // 横幅の85%を高さに（正方形より少し縦長）
            .background(
                TimeBasedGradient()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        }
        .frame(height: UIScreen.main.bounds.width * 0.85)
    }

    // MARK: - 昨日のデータ

    private var yesterdayStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("きのうのきろく")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            // 達成率バー
            achievementCard

            HStack(spacing: 10) {
                statCard(emoji: "👣", label: "歩数", value: yesterdayStepsText, unit: "")
                statCard(emoji: "🌙", label: "ねむり", value: yesterdaySleepText, unit: "")
                statCard(emoji: "🪜", label: "かいだん", value: yesterdayFloorsText, unit: "")
            }
        }
    }

    private var achievementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("目標達成率")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(gameState.achievementPercent)%")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(achievementColor)
                Text("/ \(gameState.goalSteps)歩")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // プログレスバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(achievementColor)
                        .frame(width: geo.size.width * CGFloat(gameState.achievementRate), height: 10)
                        .animation(.easeOut(duration: 0.8), value: gameState.achievementRate)
                }
            }
            .frame(height: 10)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var achievementColor: Color {
        switch gameState.achievementRate {
        case 1.0...: return .green
        case 0.7...: return .blue
        case 0.4...: return .orange
        default: return .red
        }
    }

    private func statCard(emoji: String, label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji)
                .font(.title2)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 今日拾ってきたもの

    private var todaysItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ひろってきたもの")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            if gameState.todaysItems.isEmpty {
                HStack {
                    Text(gameState.hasAlreadyFetchedToday ? "今日は何も拾ってこなかった" : "データを取得中…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Button {
                    showNewItems = true
                } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            ForEach(gameState.todaysItems.prefix(3)) { item in
                                Text(item.emoji)
                                    .font(.title2)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ひろってきたものがある")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("\(gameState.todaysItems.count)個")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: - 表示用テキスト

    private var yesterdayStepsText: String {
        guard let r = gameState.yesterdayRecord else { return "---" }
        return r.steps >= 1000
            ? String(format: "%.1fk", Double(r.steps) / 1000)
            : "\(r.steps)"
    }

    private var yesterdaySleepText: String {
        guard let r = gameState.yesterdayRecord else { return "---" }
        return r.sleepHours > 0 ? String(format: "%.1fh", r.sleepHours) : "---"
    }

    private var yesterdayFloorsText: String {
        guard let r = gameState.yesterdayRecord else { return "---" }
        return r.floors > 0 ? "\(r.floors)階" : "---"
    }

    // MARK: - 独り言トリガー

    private func triggerMonologue() {
        guard !showMonologue else { return }

        if let item = gameState.todaysItems.randomElement() {
            monologueText = item.description
        } else {
            let defaults = ["…", "ふーん", "まあね", "そう", "知ってた", "…べつに"]
            monologueText = defaults.randomElement()!
        }

        withAnimation(.spring(response: 0.3)) { showMonologue = true }

        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) { showMonologue = false }
            }
        }
    }


}

// MARK: - 今日のアイテム発表画面

struct NewItemsView: View {
    let items: [Item]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Text("ひろってきた")
                    .font(.title2)
                    .fontWeight(.medium)
                    .padding(.top, 32)

                HStack(spacing: 16) {
                    ForEach(items) { item in
                        TodaysItemCard(item: item)
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("みた")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
        }
    }
}
