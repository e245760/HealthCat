import SwiftUI

struct OnboardingView: View {
    @Environment(AppCoordinator.self) private var coordinator

    @State private var inputText: String = "8000"
    @FocusState private var isFocused: Bool

    private var parsedGoal: Int? {
        guard let value = Int(inputText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("🐾")
                .font(.system(size: 64))
                .padding(.bottom, 16)

            Text("HealthCat")
                .font(.title)
                .fontWeight(.bold)

            Text("毎日歩いてネコにアイテムを\nひろってきてもらおう")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.bottom, 48)

            // 目標歩数入力
            VStack(alignment: .leading, spacing: 12) {
                Text("1日の目標歩数")
                    .font(.headline)

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    TextField("8000", text: $inputText)
                        .keyboardType(.numberPad)
                        .focused($isFocused)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("歩")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if parsedGoal == nil && !inputText.isEmpty {
                    Text("正しい歩数を入力してください")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("あとから設定で変更できます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                guard let goal = parsedGoal else { return }
                coordinator.goalSteps = goal
                coordinator.completeOnboarding()
                // onboarding 完了後にセットアップ開始
                Task { await coordinator.startSetupIfNeeded() }
            } label: {
                Text("はじめる")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(parsedGoal != nil ? Color.accentColor : Color(.systemGray4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(parsedGoal == nil)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .onTapGesture { isFocused = false }
        .onAppear     { isFocused = true  }
    }
}
