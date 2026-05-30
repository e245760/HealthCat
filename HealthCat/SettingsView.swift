import SwiftUI

struct SettingsView: View {
    @ObservedObject var gameState: GameState

    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool

    private var parsedGoal: Int? {
        guard let value = Int(inputText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            List {
                // 目標歩数
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        // 現在の目標
                        HStack {
                            Text("現在の目標")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(gameState.goalSteps)歩")
                                .fontWeight(.semibold)
                        }

                        // 自由入力
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
        }
    }
}
