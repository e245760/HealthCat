import Foundation

final class ItemDatabase {
    static let shared = ItemDatabase()

    let allItems: [Item] = [
        Item(
            id: "glowing_stone",
            name: "光る石",
            description: "なぜか温かかった",
            emoji: "✨",
            condition: .steps(min: 10000, max: Int.max)
        ),
        Item(
            id: "rusty_key",
            name: "さびた鍵",
            description: "どこのかわからない",
            emoji: "🗝️",
            condition: .steps(min: 5000, max: 10000)
        ),
        Item(
            id: "pebble",
            name: "小石",
            description: "気に入った",
            emoji: "🪨",
            condition: .steps(min: 3000, max: 5000)
        ),
        Item(
            id: "dry_grass",
            name: "枯れ草のたば",
            description: "においがした",
            emoji: "🌾",
            condition: .steps(min: 0, max: 3000)
        ),
    ]

    /// 歩数からアイテムを確定取得
    func determineItem(steps: Int) -> Item? {
        allItems.first { $0.condition.isSatisfied(steps: steps) }
    }

    /// ID からアイテムを逆引き
    func item(for id: String?) -> Item? {
        guard let id else { return nil }
        return allItems.first { $0.id == id }
    }
}
