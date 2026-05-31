import SwiftUI

struct ActivityTrackingView: View {
    @Environment(AppCoordinator.self) private var coordinator

    // ビュー固有のローカル状態
    @State private var activities:    [HealthKitService.DailyActivity] = []
    @State private var isLoading:     Bool = true
    @State private var currentMonth:  Date = Calendar.current.startOfMonth(for: Date())

    private var recent7: [HealthKitService.DailyActivity] { Array(activities.suffix(7)) }

    private var currentMonthActivities: [HealthKitService.DailyActivity] {
        activities.filter {
            Calendar.current.isDate($0.date, equalTo: currentMonth, toGranularity: .month)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 20) {
                        weeklySummaryCard.padding(.horizontal)
                        stepsChartCard.padding(.horizontal)
                        calendarSection.padding(.horizontal)
                    }
                    .padding(.vertical, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("きろく")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            activities = await coordinator.healthKit.fetchActivityHistory(days: 60)
            isLoading = false
        }
    }

    // MARK: - 今週のまとめ

    private var weeklySummaryCard: some View {
        let goalSteps     = coordinator.goalSteps
        let achievedDays  = recent7.filter { $0.steps >= goalSteps }.count
        let totalSteps    = recent7.reduce(0) { $0 + $1.steps }
        let totalDistance = recent7.reduce(0.0) { $0 + $1.distanceKm }
        let totalCalories = recent7.reduce(0) { $0 + $1.calories }

        return VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今週の達成")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(achievedDays)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(achievedDays >= 5 ? .green : achievedDays >= 3 ? .orange : .primary)
                        Text("/ 7日")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("目標 \(goalSteps)歩/日")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 6) {
                    Text("月〜日").font(.system(size: 9)).foregroundStyle(.tertiary)
                    HStack(spacing: 5) {
                        ForEach(Array(recent7.enumerated()), id: \.offset) { _, a in
                            Circle()
                                .fill(a.steps >= goalSteps
                                      ? Color.green
                                      : a.steps > 0 ? Color.orange.opacity(0.5) : Color(.systemGray4))
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 0) {
                summaryItem(label: "歩数",
                    value: totalSteps >= 10000
                        ? String(format: "%.1fk", Double(totalSteps) / 1000) : "\(totalSteps)",
                    unit: "歩")
                Divider().frame(height: 32)
                summaryItem(label: "距離",
                    value: String(format: "%.1f", totalDistance), unit: "km")
                Divider().frame(height: 32)
                summaryItem(label: "カロリー", value: "\(totalCalories)", unit: "kcal")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func summaryItem(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.title3).fontWeight(.semibold).monospacedDigit()
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 歩数グラフ

    private var stepsChartCard: some View {
        let goalSteps = coordinator.goalSteps
        let maxSteps  = max(goalSteps, recent7.map { $0.steps }.max() ?? 1)

        return VStack(alignment: .leading, spacing: 12) {
            Text("過去7日間の歩数").font(.caption).foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(recent7) { a in
                    let ratio    = Double(a.steps) / Double(maxSteps)
                    let achieved = a.steps >= goalSteps

                    VStack(spacing: 6) {
                        if achieved {
                            Text(a.steps >= 10000
                                 ? String(format: "%.0fk", Double(a.steps) / 1000)
                                 : "\(a.steps / 1000)k")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.green)
                        } else {
                            Text(" ").font(.system(size: 9))
                        }

                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5)).frame(height: 120)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(achieved ? Color.green : Color.blue.opacity(0.5))
                                .frame(height: max(4, CGFloat(ratio) * 120))
                        }

                        Text(dayLabel(a.date))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - カレンダー

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("カレンダー").font(.caption).foregroundStyle(.secondary).padding(.leading, 4)

            VStack(spacing: 0) {
                monthNavigationHeader
                Divider()
                weekdayHeader
                calendarGrid
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var monthNavigationHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentMonth = Calendar.current.date(
                        byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.primary).padding(8)
            }
            .disabled(isOldestMonth)

            Spacer()
            Text(monthLabel(currentMonth)).font(.subheadline).fontWeight(.semibold)
            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentMonth = Calendar.current.date(
                        byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(isCurrentMonth ? .secondary : .primary).padding(8)
            }
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { day in
                Text(day)
                    .font(.caption2)
                    .foregroundStyle(day == "日" ? .red : day == "土" ? .blue : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 8)
    }

    private var calendarGrid: some View {
        let days    = calendarDays(for: currentMonth)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let date = day { calendarCell(for: date) }
                else { Color.clear.frame(height: 44) }
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 12)
    }

    private func calendarCell(for date: Date) -> some View {
        let calendar = Calendar.current
        let activity = activities.first { calendar.isDate($0.date, inSameDayAs: date) }
        let steps    = activity?.steps ?? 0
        let isToday  = calendar.isDateInToday(date)
        let isFuture = date > Date()
        let achieved = steps >= coordinator.goalSteps && !isFuture
        let hasData  = steps > 0 && !isFuture

        return VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 13, weight: isToday ? .bold : .regular))
                .foregroundStyle(isFuture ? Color(.tertiaryLabel) : isToday ? Color.white : Color(.label))
                .frame(width: 32, height: 32)
                .background(Group {
                    if isToday          { Circle().fill(Color.accentColor) }
                    else if achieved    { Circle().fill(Color.green.opacity(0.2)) }
                    else                { Circle().fill(Color.clear) }
                })

            Circle()
                .fill(hasData ? (achieved ? Color.green : Color.orange.opacity(0.6)) : Color.clear)
                .frame(width: 5, height: 5)
        }
        .frame(height: 44)
    }

    // MARK: - ユーティリティ

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(currentMonth, equalTo: Date(), toGranularity: .month)
    }

    private var isOldestMonth: Bool {
        guard let oldest = activities.first?.date else { return false }
        return currentMonth <= Calendar.current.startOfMonth(for: oldest)
    }

    private func monthLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "E"
        return f.string(from: date)
    }

    private func calendarDays(for month: Date) -> [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }

        var weekday = calendar.component(.weekday, from: firstDay)
        weekday = ((weekday - 2) + 7) % 7  // 月曜=0

        var days: [Date?] = Array(repeating: nil, count: weekday)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
}
