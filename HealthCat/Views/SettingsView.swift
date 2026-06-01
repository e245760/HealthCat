import SwiftUI

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    @State private var inputText:      String = ""
    @FocusState private var isFocused: Bool

    @State private var isRefetching:   Bool            = false
    @State private var refetchMessage: String          = ""
    @State private var refetchResult:  RefetchResult?  = nil

    enum RefetchResult { case success(Int), failure }

    private var parsedGoal: Int? {
        guard let value = Int(inputText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: 目標歩数

                    sectionHeader("目標歩数")

                    card {
                        // 現在値
                        HStack {
                            Text("現在の目標").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(coordinator.goalSteps)歩").fontWeight(.semibold)
                        }

                        Divider()

                        // 入力
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            TextField("\(coordinator.goalSteps)", text: $inputText)
                                .keyboardType(.numberPad)
                                .focused($isFocused)
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .monospacedDigit()

                            Text("歩").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()

                            Button("変更") {
                                guard let goal = parsedGoal else { return }
                                coordinator.goalSteps = goal
                                inputText = ""
                                isFocused = false
                            }
                            .disabled(parsedGoal == nil)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        if parsedGoal == nil && !inputText.isEmpty {
                            Text("正しい歩数を入力してください")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }

                    sectionFooter("新しい歩数を入力して「変更」を押してください")

                    // MARK: データ再取得

                    sectionHeader("データ")

                    card {
                        if isRefetching {
                            HStack(spacing: 12) {
                                ProgressView().controlSize(.small)
                                Text(refetchMessage)
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                            }
                        } else {
                            // 再取得ボタン
                            Button {
                                Task { await startRefetch() }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise.icloud")
                                        .foregroundStyle(Color.accentColor)
                                    Text("過去365日のデータを再取得")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            // 結果表示
                            if let result = refetchResult {
                                Divider()
                                HStack(spacing: 8) {
                                    switch result {
                                    case .success(let days):
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                        Text("\(days)日分を取得しました")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    case .failure:
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                        Text("取得に失敗しました")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }

                    sectionFooter("HealthKitから過去365日分のデータを再取得します。データが消えた場合などにお使いください。")

                    // MARK: アプリ情報

                    sectionHeader("アプリ情報")

                    card {
                        HStack {
                            Text("バージョン")
                            Spacer()
                            Text("1.0.0").foregroundStyle(.secondary)
                        }
                    }

                    // MARK: デバッグ

                    #if DEBUG
                    sectionHeader("デバッグ")
                    card {
                        Button(role: .destructive) {
                            coordinator.resetAll()
                        } label: {
                            Text("データをリセット")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    #endif

                    Spacer(minLength: 32)
                }
                .padding(.horizontal)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .onTapGesture { isFocused = false }
        }
    }

    // MARK: - レイアウトヘルパー

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.top, 24)
            .padding(.bottom, 6)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.top, 6)
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 再取得処理

    private func startRefetch() async {
        isRefetching = true
        refetchResult = nil
        refetchMessage = "HealthKitに接続中…"

        guard await coordinator.healthKit.requestAuthorization(),
              let repo = coordinator.repository else {
            isRefetching  = false
            refetchResult = .failure
            return
        }

        repo.reset()

        refetchMessage = "過去365日分を取得中…"
        let dailySteps = await coordinator.healthKit.fetchPastDaysSteps(days: 365)

        refetchMessage = "データを保存中…"
        repo.saveHistoricalData(dailySteps: dailySteps, goalSteps: coordinator.goalSteps)

        let missing = AnalyticsEngine.missingDates(existing: repo.history)
        if !missing.isEmpty {
            refetchMessage = "睡眠・階数を補完中…"
            let dataList = await coordinator.healthKit.fetchDailyData(for: missing)
            for data in dataList {
                repo.saveRecord(date: data.date, steps: data.steps,
                                sleepHours: data.sleepHours, floors: data.floors,
                                goalSteps: coordinator.goalSteps)
            }
        }

        isRefetching  = false
        refetchResult = .success(dailySteps.count)

        try? await Task.sleep(for: .seconds(3))
        withAnimation { refetchResult = nil }
    }
}
