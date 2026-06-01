import SwiftUI

// MARK: - RecordsHubView
// きろくタブの起点。歩数のきろく / ふりかえり を選択する。

struct RecordsHubView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    NavigationLink { ActivityTrackingView() } label: {
                        HubCard(
                            title:       "歩数のきろく",
                            subtitle:    "週間グラフ・カレンダーで確認",
                            systemImage: "figure.walk",
                            color:       .blue
                        )
                    }

                    NavigationLink { WrappedSelectionView() } label: {
                        HubCard(
                            title:       "ふりかえり",
                            subtitle:    "年ごとの歩数をまとめてふりかえる",
                            systemImage: "sparkles",
                            color:       .purple
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("きろく")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - WrappedSelectionView
// ふりかえりの年選択画面。RecordsHubView の NavigationStack 内に push される。

struct WrappedSelectionView: View {
    @Environment(AppCoordinator.self) private var coordinator

    private var availableYears: [Int] {
        let years = Set((coordinator.repository?.history ?? []).map {
            Calendar.current.component(.year, from: $0.date)
        })
        return years.sorted().reversed()
    }

    var body: some View {
        List {
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
        }
        .navigationTitle("ふりかえり")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - HubCard
// ハブ画面のカードコンポーネント

private struct HubCard: View {
    let title:       String
    let subtitle:    String
    let systemImage: String
    let color:       Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 54, height: 54)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
