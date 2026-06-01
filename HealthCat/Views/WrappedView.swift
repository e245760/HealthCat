import SwiftUI

// MARK: - Wrapped データモデル

struct WrappedData {
    let year: Int
    let recordedDays: Int
    let totalSteps: Int
    let achievedDays: Int
    let bestDay: DailyRecord?
    let longestStreak: Int
    let longestStreakStart: Date?
    let longestStreakEnd: Date?
    let monthlyAverages: [(month: Date, average: Double)]
    let weekdayAverages: [Int: Double]
    let itemCounts: [(item: Item, count: Int)]
    let averageSleep: Double
    let totalKinds: Int
    let yearRecords: [DailyRecord]

    var achievementPercent: Int {
        guard recordedDays > 0 else { return 0 }
        return Int(Double(achievedDays) / Double(recordedDays) * 100)
    }

    var bestWeekday:  Int? { weekdayAverages.max(by: { $0.value < $1.value })?.key }
    var worstWeekday: Int? { weekdayAverages.min(by: { $0.value < $1.value })?.key }

    static func weekdayName(_ weekday: Int) -> String {
        ["日", "月", "火", "水", "木", "金", "土"][safe: weekday - 1] ?? ""
    }

    // MARK: - ファクトリー（AppCoordinator から生成）
    // AnalyticsEngine に分析を委譲し、WrappedData はデータの集約のみを担う

    static func make(from coordinator: AppCoordinator, year: Int) -> WrappedData {
        guard let repo = coordinator.repository else {
            return WrappedData(
                year: year, recordedDays: 0, totalSteps: 0, achievedDays: 0,
                bestDay: nil, longestStreak: 0, longestStreakStart: nil, longestStreakEnd: nil,
                monthlyAverages: [], weekdayAverages: [:], itemCounts: [],
                averageSleep: 0, totalKinds: ItemDatabase.shared.allItems.count, yearRecords: [])
        }

        let calendar = Calendar.current
        let start    = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end      = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        let records  = repo.history.filter { $0.date >= start && $0.date < end }

        // AnalyticsEngine に委譲
        let streak      = AnalyticsEngine.longestStreak(in: records)
        let monthlyAvg  = AnalyticsEngine.monthlyAverageSteps(in: records)
        let wdAvg       = AnalyticsEngine.averageStepsByWeekday(in: records)
        let best        = AnalyticsEngine.bestDay(in: records)

        // アイテム取得回数
        let itemCounts = ItemDatabase.shared.allItems.compactMap { item -> (item: Item, count: Int)? in
            let c = repo.collection.count(for: item.id)
            return c > 0 ? (item: item, count: c) : nil
        }.sorted { $0.count > $1.count }

        // 平均睡眠
        let sleepRecords = records.filter { $0.sleepHours > 0 }
        let avgSleep = sleepRecords.isEmpty ? 0.0
            : sleepRecords.reduce(0.0) { $0 + $1.sleepHours } / Double(sleepRecords.count)

        return WrappedData(
            year:               year,
            recordedDays:       records.count,
            totalSteps:         records.reduce(0) { $0 + $1.steps },
            achievedDays:       records.filter { $0.isGoalAchieved }.count,
            bestDay:            best,
            longestStreak:      streak.count,
            longestStreakStart:  streak.start,
            longestStreakEnd:    streak.end,
            monthlyAverages:    monthlyAvg,
            weekdayAverages:    wdAvg,
            itemCounts:         itemCounts,
            averageSleep:       avgSleep,
            totalKinds:         ItemDatabase.shared.allItems.count,
            yearRecords:        records
        )
    }
}

// MARK: - メイン画面

struct WrappedView: View {
    @Environment(AppCoordinator.self) private var coordinator
    let year: Int

    @State private var currentSlide  = 0
    @State private var goingForward  = true   // スライドアニメーションの方向管理
    @State private var data: WrappedData? = nil

    private let totalSlides = 6

    /// 進行方向に合わせたトランジション
    private var slideTransition: AnyTransition {
        goingForward
            ? .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity))
            : .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal:   .move(edge: .trailing).combined(with: .opacity))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()

            if let data {
                wrappedContent(data: data)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("ふりかえりを準備中…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("\(year)年のふりかえり")
        .navigationBarTitleDisplayMode(.inline)
        .background { NavigationBackGestureDisabler() }  // バックスワイプを無効化
        .task {
            // repository アクセスはメインアクターで行う
            // 365件程度のデータなら同期計算で十分高速
            if data == nil {
                data = WrappedData.make(from: coordinator, year: year)
            }
        }
    }

    @ViewBuilder
    private func wrappedContent(data: WrappedData) -> some View {
        ZStack(alignment: .bottom) {
            Group {
                switch currentSlide {
                case 0: slide0(data)
                case 1: slide1(data)
                case 2: slide2(data)
                case 3: slide3(data)
                case 4: slide4(data)
                case 5: slide5(data)
                default: EmptyView()
                }
            }
            .id(currentSlide)
            .transition(slideTransition)
            // .animation(value:) は使わず withAnimation に一本化
            .padding(.bottom, 100)
            // 水平スワイプでスライド切り替え
            // simultaneousGesture にすることで内部の ScrollView（縦）と競合しない
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        let h = value.translation.width
                        let v = value.translation.height
                        // 横方向の移動が支配的なときだけ反応
                        guard abs(h) > abs(v) else { return }
                        if h < -50 {
                            // goingForward を withAnimation の外で先に確定させる
                            // → SwiftUI がトランジション方向を正しく読み取れる
                            goingForward = true
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                currentSlide = min(totalSlides - 1, currentSlide + 1)
                            }
                        } else if h > 50 {
                            goingForward = false
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                currentSlide = max(0, currentSlide - 1)
                            }
                        }
                    }
            )

            navigationBar
        }
    }

    // MARK: - スライド0: 年間サマリー

    private func slide0(_ data: WrappedData) -> some View {
        WrappedSlide {
            WrappedLabel(text: "\(year)年のふりかえり")
            WrappedBigNumber(number: "\(data.recordedDays)", unit: "日",
                             caption: "ことしもぼくといっしょに歩いた")
            HStack(spacing: 12) {
                WrappedStatBox(label: "総歩数",   value: data.totalSteps.shortString, unit: "歩")
                WrappedStatBox(label: "目標達成", value: "\(data.achievementPercent)%",
                               unit: "\(data.achievedDays)日 / \(data.recordedDays)日")
            }
            .padding(.top, 8)
        }
    }

    // MARK: - スライド1: いちばん歩いた日

    private func slide1(_ data: WrappedData) -> some View {
        WrappedSlide {
            WrappedLabel(text: "いちばんよく歩いた日")
            if let best = data.bestDay {
                WrappedBigNumber(number: best.steps.shortString, unit: "歩",
                                 caption: "\(best.date.wrappedDateString)\nぼく、ちょっと疲れた")
            } else {
                WrappedBigNumber(number: "---", unit: "", caption: "データがまだ少ない")
            }
            WrappedBarChart(
                values:         data.monthlyAverages.map { $0.average },
                labels:         data.monthlyAverages.map { $0.month.monthLabel },
                highlightIndex: data.monthlyAverages.indices.max(by: {
                    data.monthlyAverages[$0].average < data.monthlyAverages[$1].average
                }),
                caption: "月別平均歩数"
            )
            .padding(.top, 8)
        }
    }

    // MARK: - スライド2: 曜日のくせ

    private func slide2(_ data: WrappedData) -> some View {
        WrappedSlide {
            WrappedLabel(text: "曜日のくせ")
            if let best = data.bestWeekday, let worst = data.worstWeekday,
               let bestAvg = data.weekdayAverages[best],
               let worstAvg = data.weekdayAverages[worst] {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(WrappedData.weekdayName(best))曜日")
                        .font(.system(size: 48, weight: .medium, design: .rounded))
                    Text("がいちばん好きみたい").font(.subheadline).foregroundStyle(.secondary)
                    Text("平均 \(Int(bestAvg).formattedSteps)歩").font(.caption).foregroundStyle(.tertiary)
                }
                WrappedBarChart(
                    values:         (1...7).map { data.weekdayAverages[$0] ?? 0 },
                    labels:         ["日", "月", "火", "水", "木", "金", "土"],
                    highlightIndex: best - 1,
                    caption:        "曜日別平均歩数"
                )
                .padding(.top, 8)
                Text("\(WrappedData.weekdayName(worst))曜日はそうでもない（平均 \(Int(worstAvg).formattedSteps)歩）")
                    .font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
            } else {
                WrappedBigNumber(number: "---", unit: "", caption: "データがまだ少ない")
            }
        }
    }

    // MARK: - スライド3: 連続達成ストリーク

    private func slide3(_ data: WrappedData) -> some View {
        WrappedSlide {
            WrappedLabel(text: "連続達成")
            WrappedBigNumber(number: "\(data.longestStreak)", unit: "日",
                             caption: streakCaption(data))
            WrappedStreakDots(
                records:      data.yearRecords,
                longestStart: data.longestStreakStart,
                longestEnd:   data.longestStreakEnd
            )
            .padding(.top, 8)
            HStack(spacing: 16) {
                WrappedDotLegend(color: .primary,              label: "達成")
                WrappedDotLegend(color: .secondary,            label: "最長ストリーク期間")
                WrappedDotLegend(color: Color(.systemGray5),   label: "未達成")
            }
            .padding(.top, 8)
        }
    }

    private func streakCaption(_ data: WrappedData) -> String {
        guard data.longestStreak > 0,
              let s = data.longestStreakStart,
              let e = data.longestStreakEnd else { return "まだストリークがない" }
        return "\(s.wrappedShortDateString)〜\(e.wrappedShortDateString)"
    }

    // MARK: - スライド4: アイテムランキング

    private func slide4(_ data: WrappedData) -> some View {
        WrappedSlide {
            WrappedLabel(text: "拾ってきたもの")
            let kinds = data.itemCounts.count
            let total = ItemDatabase.shared.allItems.count
            Text(kinds == total ? "ことし、\(kinds)種類ぜんぶ集まった" : "ことし、\(kinds)種類集まった")
                .font(.subheadline).foregroundStyle(.secondary).padding(.bottom, 4)
            VStack(spacing: 10) {
                ForEach(data.itemCounts.prefix(4), id: \.item.id) { pair in
                    let maxCount = data.itemCounts.first?.count ?? 1
                    WrappedItemRow(item: pair.item, count: pair.count,
                                  ratio: Double(pair.count) / Double(maxCount))
                }
                if data.itemCounts.isEmpty {
                    Text("まだアイテムがない")
                        .font(.subheadline).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
        }
    }

    // MARK: - スライド5: 総まとめ

    private func slide5(_ data: WrappedData) -> some View {
        WrappedSlide {
            WrappedLabel(text: "ことしのまとめ")
            VStack(alignment: .leading, spacing: 4) {
                Text("また来年も").font(.system(size: 36, weight: .medium, design: .rounded))
                Text("よろしく").font(.system(size: 36, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                HStack {
                    Text("\(year)年 総まとめ").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.bottom, 12)
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 12) {
                    WrappedFinalStat(label: "記録した日",     value: "\(data.recordedDays)日")
                    WrappedFinalStat(label: "目標達成日",     value: "\(data.achievedDays)日")
                    WrappedFinalStat(label: "最長ストリーク", value: "\(data.longestStreak)日")
                    WrappedFinalStat(label: "総歩数",         value: data.totalSteps.shortString)
                    if data.averageSleep > 0 {
                        WrappedFinalStat(label: "平均睡眠",
                                         value: String(format: "%.1fh", data.averageSleep))
                    }
                    WrappedFinalStat(label: "コレクション",
                                     value: "\(data.itemCounts.count)/\(data.totalKinds)種")
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.top, 8)
        }
    }

    // MARK: - ナビゲーションバー

    private var navigationBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button {
                    goingForward = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        currentSlide = max(0, currentSlide - 1)
                    }
                } label: {
                    Text("もどる")
                        .font(.subheadline)
                        .foregroundStyle(currentSlide == 0 ? Color(.tertiaryLabel) : .primary)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(currentSlide == 0)

                Spacer()

                HStack(spacing: 5) {
                    ForEach(0..<totalSlides, id: \.self) { i in
                        Capsule()
                            .fill(i == currentSlide ? Color.primary : Color(.systemGray4))
                            .frame(width: i == currentSlide ? 18 : 6, height: 6)
                            .animation(.spring(response: 0.3), value: currentSlide)
                    }
                }

                Spacer()

                if currentSlide < totalSlides - 1 {
                    Button {
                        goingForward = true
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            currentSlide += 1
                        }
                    } label: {
                        Text("つぎへ")
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    Button {
                        goingForward = false
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            currentSlide = 0
                        }
                    } label: {
                        Text("さいしょへ")
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - スライドコンテナ

private struct WrappedSlide<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(.horizontal, 24).padding(.top, 48).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 共通コンポーネント

private struct WrappedLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.tertiary).kerning(1.2).textCase(.uppercase)
    }
}

private struct WrappedBigNumber: View {
    let number: String; let unit: String; let caption: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(number).font(.system(size: 72, weight: .medium, design: .rounded))
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 28, weight: .regular)).foregroundStyle(.secondary)
                }
            }
            Text(caption).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
        }
    }
}

private struct WrappedStatBox: View {
    let label: String; let value: String; let unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 22, weight: .medium, design: .rounded))
            Text(unit).font(.system(size: 12)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct WrappedBarChart: View {
    let values: [Double]; let labels: [String]
    let highlightIndex: Int?; let caption: String
    private var maxValue: Double { values.max() ?? 1 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(i == highlightIndex ? Color.primary : Color(.systemGray5))
                            .frame(height: maxValue > 0 ? CGFloat(v / maxValue) * 80 : 4)
                        Text(labels[safe: i] ?? "")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100, alignment: .bottom)
            Text(caption).font(.system(size: 11)).foregroundStyle(.quaternary)
        }
    }
}

private struct WrappedStreakDots: View {
    let records: [DailyRecord]; let longestStart: Date?; let longestEnd: Date?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 14)
    private func color(for r: DailyRecord) -> Color {
        if let s = longestStart, let e = longestEnd, r.date >= s && r.date <= e {
            return r.isGoalAchieved ? .primary : .secondary
        }
        return r.isGoalAchieved ? .primary : Color(.systemGray5)
    }
    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(records.sorted(by: { $0.date < $1.date })) { r in
                RoundedRectangle(cornerRadius: 3).fill(color(for: r)).frame(height: 14)
            }
        }
    }
}

private struct WrappedDotLegend: View {
    let color: Color; let label: String
    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

private struct WrappedItemRow: View {
    let item: Item; let count: Int; let ratio: Double
    var body: some View {
        HStack(spacing: 14) {
            Text(item.emoji).font(.system(size: 28)).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline).fontWeight(.medium)
                Text("\(count)回").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(.systemGray5)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(Color.primary)
                        .frame(width: geo.size.width * ratio, height: 4)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 80, height: 20)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct WrappedFinalStat: View {
    let label: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 20, weight: .medium, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Extensions（WrappedView 専用）

private extension Int {
    var shortString: String {
        if self >= 10_000 { return String(format: "%.1f万", Double(self) / 10_000) }
        if self >= 1_000  { return String(format: "%.1fk",  Double(self) / 1_000)  }
        return "\(self)"
    }
    var formattedSteps: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

private extension Date {
    var wrappedDateString: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日（E）"; return f.string(from: self)
    }
    var wrappedShortDateString: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d"; return f.string(from: self)
    }
    var monthLabel: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M"; return f.string(from: self)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - バックスワイプ無効化
// WrappedView 表示中だけ iOS のシステムバックスワイプを止める。
// viewDidAppear で無効化 → viewWillDisappear で復元するので
// 他の画面には一切影響しない。

private struct NavigationBackGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ vc: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
