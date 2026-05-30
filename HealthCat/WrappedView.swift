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
    let monthlyAverages: [(month: Date, average: Double)]   // 最大12件
    let weekdayAverages: [Int: Double]                      // weekday(1=日..7=土): 平均歩数
    let itemCounts: [(item: Item, count: Int)]              // 取得回数降順
    let averageSleep: Double
    let totalKinds: Int

    // 目標達成率（%）
    var achievementPercent: Int {
        guard recordedDays > 0 else { return 0 }
        return Int(Double(achievedDays) / Double(recordedDays) * 100)
    }

    // 最多歩数の曜日（1=日〜7=土）
    var bestWeekday: Int? {
        weekdayAverages.max(by: { $0.value < $1.value })?.key
    }

    // 最少歩数の曜日
    var worstWeekday: Int? {
        weekdayAverages.min(by: { $0.value < $1.value })?.key
    }

    static func weekdayName(_ weekday: Int) -> String {
        ["日", "月", "火", "水", "木", "金", "土"][safe: weekday - 1] ?? ""
    }

    static func make(from gameState: GameState, year: Int) -> WrappedData {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end   = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!

        let records = gameState.dailyHistory.filter { $0.date >= start && $0.date < end }

        // 月別平均
        var monthBuckets: [Date: [Int]] = [:]
        for r in records {
            let m = calendar.startOfMonth(for: r.date)
            monthBuckets[m, default: []].append(r.steps)
        }
        let monthlyAvg = monthBuckets
            .map { (month: $0.key, average: Double($0.value.reduce(0, +)) / Double($0.value.count)) }
            .sorted { $0.month < $1.month }

        // 曜日別平均
        var wdBuckets: [Int: [Int]] = [:]
        for r in records {
            let wd = calendar.component(.weekday, from: r.date)
            wdBuckets[wd, default: []].append(r.steps)
        }
        let wdAvg = wdBuckets.mapValues { Double($0.reduce(0, +)) / Double($0.count) }

        // ストリーク計算（最長期間も）
        var longest = 0, current = 0
        var streakStart: Date? = nil
        var tempStart: Date? = nil
        var streakEnd: Date? = nil
        for r in records.sorted(by: { $0.date < $1.date }) {
            if r.isGoalAchieved {
                if current == 0 { tempStart = r.date }
                current += 1
                if current > longest {
                    longest = current
                    streakStart = tempStart
                    streakEnd = r.date
                }
            } else {
                current = 0
                tempStart = nil
            }
        }

        // アイテム取得回数（コレクションから）
        let itemCounts = ItemDatabase.shared.allItems.compactMap { item -> (item: Item, count: Int)? in
            let c = gameState.collection.count(for: item.id)
            return c > 0 ? (item: item, count: c) : nil
        }.sorted { $0.count > $1.count }

        // 平均睡眠
        let sleepRecords = records.filter { $0.sleepHours > 0 }
        let avgSleep = sleepRecords.isEmpty ? 0
            : sleepRecords.reduce(0.0) { $0 + $1.sleepHours } / Double(sleepRecords.count)

        return WrappedData(
            year: year,
            recordedDays: records.count,
            totalSteps: records.reduce(0) { $0 + $1.steps },
            achievedDays: records.filter { $0.isGoalAchieved }.count,
            bestDay: records.max(by: { $0.steps < $1.steps }),
            longestStreak: longest,
            longestStreakStart: streakStart,
            longestStreakEnd: streakEnd,
            monthlyAverages: monthlyAvg,
            weekdayAverages: wdAvg,
            itemCounts: itemCounts,
            averageSleep: avgSleep,
            totalKinds: gameState.totalCount
        )
    }
}

// MARK: - メイン画面

struct WrappedView: View {
    @ObservedObject var gameState: GameState
    @Environment(\.dismiss) private var dismiss

    let year: Int

    @State private var currentSlide = 0
    @State private var animationTrigger = false

    private var data: WrappedData {
        WrappedData.make(from: gameState, year: year)
    }

    private let totalSlides = 6

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()

            // スライド本体
            Group {
                switch currentSlide {
                case 0: slide0
                case 1: slide1
                case 2: slide2
                case 3: slide3
                case 4: slide4
                case 5: slide5
                default: EmptyView()
                }
            }
            .id(currentSlide)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentSlide)
            .padding(.bottom, 100)

            // ナビゲーション
            navigationBar
        }
        .navigationBarHidden(true)
        .onAppear { animationTrigger = true }
    }

    // MARK: - スライド0: 年間サマリー

    private var slide0: some View {
        WrappedSlide {
            WrappedLabel(text: "\(year)年のふりかえり")

            WrappedBigNumber(
                number: "\(data.recordedDays)",
                unit: "日",
                caption: "ことしもぼくといっしょに歩いた"
            )

            HStack(spacing: 12) {
                WrappedStatBox(
                    label: "総歩数",
                    value: data.totalSteps.shortString,
                    unit: "歩"
                )
                WrappedStatBox(
                    label: "目標達成",
                    value: "\(data.achievementPercent)%",
                    unit: "\(data.achievedDays)日 / \(data.recordedDays)日"
                )
            }
            .padding(.top, 8)
        }
    }

    // MARK: - スライド1: いちばん歩いた日

    private var slide1: some View {
        WrappedSlide {
            WrappedLabel(text: "いちばんよく歩いた日")

            if let best = data.bestDay {
                WrappedBigNumber(
                    number: best.steps.shortString,
                    unit: "歩",
                    caption: "\(best.date.wrappedDateString)\nぼく、ちょっと疲れた"
                )
            } else {
                WrappedBigNumber(number: "---", unit: "", caption: "データがまだ少ない")
            }

            // 月別棒グラフ
            WrappedBarChart(
                values: data.monthlyAverages.map { $0.average },
                labels: data.monthlyAverages.map { $0.month.monthLabel },
                highlightIndex: data.monthlyAverages.indices.max(by: {
                    data.monthlyAverages[$0].average < data.monthlyAverages[$1].average
                }),
                caption: "月別平均歩数"
            )
            .padding(.top, 8)
        }
    }

    // MARK: - スライド2: 曜日のくせ

    private var slide2: some View {
        WrappedSlide {
            WrappedLabel(text: "曜日のくせ")

            if let best = data.bestWeekday, let worst = data.worstWeekday,
               let bestAvg = data.weekdayAverages[best],
               let worstAvg = data.weekdayAverages[worst] {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(WrappedData.weekdayName(best))曜日")
                        .font(.system(size: 48, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("がいちばん好きみたい")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("平均 \(Int(bestAvg).formattedSteps)歩")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }

                WrappedBarChart(
                    values: (1...7).map { data.weekdayAverages[$0] ?? 0 },
                    labels: ["日", "月", "火", "水", "木", "金", "土"],
                    highlightIndex: best - 1,
                    caption: "曜日別平均歩数"
                )
                .padding(.top, 8)

                Text("\(WrappedData.weekdayName(worst))曜日はそうでもない（平均 \(Int(worstAvg).formattedSteps)歩）")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            } else {
                WrappedBigNumber(number: "---", unit: "", caption: "データがまだ少ない")
            }
        }
    }

    // MARK: - スライド3: 連続達成ストリーク

    private var slide3: some View {
        WrappedSlide {
            WrappedLabel(text: "連続達成")

            WrappedBigNumber(
                number: "\(data.longestStreak)",
                unit: "日",
                caption: streakCaption
            )

            WrappedStreakDots(
                records: gameState.dailyHistory.filter {
                    let y = Calendar.current.component(.year, from: $0.date)
                    return y == year
                },
                longestStart: data.longestStreakStart,
                longestEnd:   data.longestStreakEnd
            )
            .padding(.top, 8)

            HStack(spacing: 16) {
                WrappedDotLegend(color: .primary, label: "達成")
                WrappedDotLegend(color: .secondary, label: "最長ストリーク期間")
                WrappedDotLegend(color: Color(.systemGray5), label: "未達成")
            }
            .padding(.top, 8)
        }
    }

    private var streakCaption: String {
        guard data.longestStreak > 0,
              let s = data.longestStreakStart,
              let e = data.longestStreakEnd else {
            return "まだストリークがない"
        }
        return "\(s.wrappedShortDateString)〜\(e.wrappedShortDateString)"
    }

    // MARK: - スライド4: アイテムランキング

    private var slide4: some View {
        WrappedSlide {
            WrappedLabel(text: "拾ってきたもの")

            let kinds = data.itemCounts.count
            let total = ItemDatabase.shared.allItems.count
            Text(kinds == total ? "ことし、\(kinds)種類ぜんぶ集まった" : "ことし、\(kinds)種類集まった")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            VStack(spacing: 10) {
                ForEach(data.itemCounts.prefix(4), id: \.item.id) { pair in
                    let maxCount = data.itemCounts.first?.count ?? 1
                    WrappedItemRow(
                        item: pair.item,
                        count: pair.count,
                        ratio: Double(pair.count) / Double(maxCount)
                    )
                }

                if data.itemCounts.isEmpty {
                    Text("まだアイテムがない")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
        }
    }

    // MARK: - スライド5: 総まとめ

    private var slide5: some View {
        WrappedSlide {
            WrappedLabel(text: "ことしのまとめ")

            VStack(alignment: .leading, spacing: 4) {
                Text("また来年も")
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                Text("よろしく")
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                HStack {
                    Text("\(year)年 総まとめ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        WrappedFinalStat(label: "平均睡眠", value: String(format: "%.1fh", data.averageSleep))
                    }
                    WrappedFinalStat(label: "コレクション",   value: "\(data.itemCounts.count)/\(data.totalKinds)種")
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
                // 前へ
                Button {
                    withAnimation { currentSlide = max(0, currentSlide - 1) }
                } label: {
                    Text("もどる")
                        .font(.subheadline)
                        .foregroundStyle(currentSlide == 0 ? Color(.tertiaryLabel) : .primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(currentSlide == 0)

                Spacer()

                // ページドット
                HStack(spacing: 5) {
                    ForEach(0..<totalSlides, id: \.self) { i in
                        Capsule()
                            .fill(i == currentSlide ? Color.primary : Color(.systemGray4))
                            .frame(width: i == currentSlide ? 18 : 6, height: 6)
                            .animation(.spring(response: 0.3), value: currentSlide)
                    }
                }

                Spacer()

                // 次へ / 閉じる
                if currentSlide < totalSlides - 1 {
                    Button {
                        withAnimation { currentSlide += 1 }
                    } label: {
                        Text("つぎへ")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Text("とじる")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - スライドコンテナ

private struct WrappedSlide<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 24)
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
            .foregroundStyle(.tertiary)
            .kerning(1.2)
            .textCase(.uppercase)
    }
}

private struct WrappedBigNumber: View {
    let number: String
    let unit: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(number)
                    .font(.system(size: 72, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
    }
}

private struct WrappedStatBox: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            Text(unit)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct WrappedBarChart: View {
    let values: [Double]
    let labels: [String]
    let highlightIndex: Int?
    let caption: String

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
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100, alignment: .bottom)

            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
        }
    }
}

private struct WrappedStreakDots: View {
    let records: [DailyRecord]
    let longestStart: Date?
    let longestEnd: Date?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 14)

    private func color(for record: DailyRecord) -> Color {
        if let s = longestStart, let e = longestEnd,
           record.date >= s && record.date <= e {
            return record.isGoalAchieved ? .primary : .secondary
        }
        return record.isGoalAchieved ? .primary : Color(.systemGray5)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(records.sorted(by: { $0.date < $1.date })) { record in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(for: record))
                    .frame(height: 14)
            }
        }
    }
}

private struct WrappedDotLegend: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct WrappedItemRow: View {
    let item: Item
    let count: Int
    let ratio: Double

    var body: some View {
        HStack(spacing: 14) {
            Text(item.emoji)
                .font(.system(size: 28))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text("\(count)回")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary)
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
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Extensions

private extension Int {
    /// 1000以上は "1.2k" 形式、万以上は "1.2万" 形式
    var shortString: String {
        if self >= 10_000 {
            return String(format: "%.1f万", Double(self) / 10_000)
        } else if self >= 1_000 {
            return String(format: "%.1fk", Double(self) / 1_000)
        }
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日（E）"
        return f.string(from: self)
    }

    var wrappedShortDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d"
        return f.string(from: self)
    }

    var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M"
        return f.string(from: self)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
