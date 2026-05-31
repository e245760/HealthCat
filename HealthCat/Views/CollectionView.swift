import SwiftUI

struct CollectionView: View {
    @Environment(AppCoordinator.self) private var coordinator

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // 今日拾ってきたもの
                    if !coordinator.todaysItems.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("今日ひろってきたもの")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(coordinator.todaysItems) { item in
                                        TodaysItemCard(item: item)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // 図鑑
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("図鑑")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(coordinator.collectedCount) / \(coordinator.totalItemCount)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(ItemDatabase.shared.allItems) { item in
                                let count = coordinator.repository?.collection.count(for: item.id) ?? 0
                                CollectionCell(item: item, count: count)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("コレクション")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 今日拾ってきたアイテムカード

struct TodaysItemCard: View {
    let item: Item

    var body: some View {
        VStack(spacing: 8) {
            Text(item.emoji).font(.system(size: 36))
            Text(item.name).font(.caption).fontWeight(.medium).multilineTextAlignment(.center)
            Text(item.description).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(width: 100)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 図鑑セル

struct CollectionCell: View {
    let item: Item
    let count: Int

    var obtained: Bool { count > 0 }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(obtained ? Color(.secondarySystemBackground) : Color(.systemGray5))

                if obtained {
                    Text(item.emoji)
                        .font(.system(size: 28))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if count > 1 {
                        Text("×\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                            .padding(4)
                    }
                } else {
                    Text("？").font(.system(size: 22)).foregroundStyle(.tertiary)
                }
            }
            .frame(height: 64)

            if obtained {
                Text(item.name)
                    .font(.system(size: 10)).foregroundStyle(.primary)
                    .multilineTextAlignment(.center).lineLimit(2)
            } else {
                Text("???").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }
}
