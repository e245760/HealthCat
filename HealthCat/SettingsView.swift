import SwiftUI

struct SettingsView: View {
    @ObservedObject var gameState: GameState
    var healthKit: HealthKitManager

    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool
    @State private var showWrapped = false

    // 再取得状態
    @State private var isRefetching = false
    @State private var refetchMessage = ""
    @State private var refetchResult: RefetchResult? = nil

    enum RefetchResult {
        case success(Int)   // 取得できた日数
        case failure
    }

    private var parsedGoal: Int? {
        guard let value = Int(inputText), value > 0 else { return nil }
        return value
    }

    private var availableYears: [Int] {
        let calendar = Calendar.current
        let years = Set(gameState.dailyHistory.map {
            calendar.component(.year, from: $0.date)
        })
        return years.sorted().reversed()
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        NavigationStack {
            List {

                // ふりかえり（Wrapped）
                Section {
                    if availableYears.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.secondary)
                            Text("記録が溜まるとふりかえりが見られます")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(availableYears, id: \.self) { year in
                            Button {
                                showWrapped = true
                            } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.primary)
                                    Text("\(year)年のふりかえり")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                            Text("現在の目標")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(gameState.goalSteps)歩")
                                .fontWeight(.semibold)
                        }

                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            TextField("\(gameState.goalSteps)", text: $inputText)
                                .keyboardType(.numberPad)
                                .focused($isFocused)
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .monospacedDigit()

                            Text("歩")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("変更") {
                                guard let goal = parsedGoal else { return }
                                gameState.goalSteps = goal
                                inputText = ""
                                isFocused = false
                            }
                            .disabled(parsedGoal == nil)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        if parsedGoal == nil && !inputText.isEmpty {
                            Text("正しい歩数を入力してください")
                                .font(.caption)
                                .foregroundStyle(.red)
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
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }

                #if DEBUG
                Section(header: Text("デバッグ")) {
                    Button(role: .destructive) {
                        gameState.resetAll()
                    } label: {
                        Text("データをリセット")
                    }
                }
                #endif
            }
            .navigationTitle("設定")
            .onTapGesture { isFocused = false }
            .fullScreenCover(isPresented: $showWrapped) {
                NavigationStack {
                    WrappedView(gameState: gameState, year: availableYears.first ?? currentYear)
                }
            }
        }
    }

    // MARK: - 再取得行

    @ViewBuilder
    private var refetchRow: some View {
        if isRefetching {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text(refetchMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else {
            Button {
                startRefetch()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise.icloud")
                    Text("過去365日のデータを再取得")
                }
            }

            // 結果バナー
            if let result = refetchResult {
                HStack(spacing: 8) {
                    switch result {
                    case .success(let days):
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(days)日分を取得しました")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    case .failure:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("取得に失敗しました")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 再取得処理

    private func startRefetch() {
        isRefetching = true
        refetchResult = nil
        refetchMessage = "HealthKitに接続中…"

        healthKit.requestAuthorization { success in
            guard success else {
                isRefetching = false
                refetchResult = .failure
                return
            }

            refetchMessage = "過去365日分を取得中…"

            // 既存データを全削除してから取り直す
            gameState.resetAll()

            healthKit.fetchPastDaysSteps(days: 365) { dailySteps in
                refetchMessage = "歩数データを保存中…"
                gameState.applyHistoricalData(dailySteps: dailySteps)

                // 睡眠・階数の差分補完
                let missing = gameState.missingDates()
                guard !missing.isEmpty else {
                    isRefetching = false
                    refetchResult = .success(dailySteps.count)
                    return
                }

                refetchMessage = "睡眠・階数を補完中…"
                healthKit.fetchDailyData(for: missing) { dataList in
                    for data in dataList {
                        gameState.applyDailyResult(
                            steps: data.steps,
                            sleepHours: data.sleepHours,
                            floors: data.floors,
                            for: data.date
                        )
                    }
                    isRefetching = false
                    refetchResult = .success(dailySteps.count)

                    // 3秒後にバナーを消す
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { refetchResult = nil }
                    }
                }
            }
        }
    }
}
