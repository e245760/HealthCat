import SwiftUI

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    @State private var inputText:     String = ""
    @FocusState private var isFocused: Bool

    // 再取得 UI 状態（SettingsView 固有のローカル状態）
    @State private var isRefetching:  Bool           = false
    @State private var refetchMessage: String        = ""
    @State private var refetchResult:  RefetchResult? = nil

    enum RefetchResult { case success(Int), failure }

    private var parsedGoal: Int? {
        guard let value = Int(inputText), value > 0 else { return nil }
        return value
    }

    private var availableYears: [Int] {
        let years = Set((coordinator.repository?.history ?? []).map {
            Calendar.current.component(.year, from: $0.date)
        })
        return years.sorted().reversed()
    }

    var body: some View {
        NavigationStack {
            List {

                // ふりかえり
                Section {
                    if availableYears.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles").foregroundStyle(.secondary)
                            Text("記録が溜まるとふりかえりが見られます")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(availableYears, id: \.self) { year in
                            NavigationLink {
                                WrappedView(year: year)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "sparkles")
                                    Text("\(year)年のふりかえり")
                                }
                            }
                        }
                    }
                } header: {
                    Text("ふりかえり")
                } footer: {
                    Text("1年間の歩数・睡眠・コレクションをまとめて振り返ります")
                }

                // 目標歩数
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("現在の目標").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(coordinator.goalSteps)歩").fontWeight(.semibold)
                        }

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
                    .padding(.vertical, 8)
                } header: {
                    Text("目標歩数")
                } footer: {
                    Text("新しい歩数を入力して「変更」を押してください")
                }

                // 過去データの再取得
                Section {
                    refetchRow
                } header: {
                    Text("データ")
                } footer: {
                    Text("HealthKitから過去365日分のデータを再取得します。データが消えた場合などにお使いください。")
                }

                // アプリ情報
                Section(header: Text("アプリ情報")) {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.secondary)
                    }
                }

                #if DEBUG
                Section(header: Text("デバッグ")) {
                    Button(role: .destructive) {
                        coordinator.resetAll()
                    } label: {
                        Text("データをリセット")
                    }
                }
                #endif
            }
            .navigationTitle("設定")
            .onTapGesture { isFocused = false }
        }
    }

    // MARK: - 再取得行

    @ViewBuilder
    private var refetchRow: some View {
        if isRefetching {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(refetchMessage).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else {
            Button {
                Task { await startRefetch() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise.icloud")
                    Text("過去365日のデータを再取得")
                }
            }

            if let result = refetchResult {
                HStack(spacing: 8) {
                    switch result {
                    case .success(let days):
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(days)日分を取得しました")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .failure:
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("取得に失敗しました")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 再取得処理
    // coordinator のグローバルオーバーレイを使わず、
    // SettingsView 内のローカル UI で進捗を表示する

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

        // 3秒後に結果表示を消す
        try? await Task.sleep(for: .seconds(3))
        withAnimation { refetchResult = nil }
    }
}
