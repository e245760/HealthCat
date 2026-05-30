import Foundation

class ItemDatabase {
    static let shared = ItemDatabase()

    // MARK: - アイテム定義
    // 歩数の範囲に応じて確定取得するアイテム

    let allItems: [Item] = [
        // 1万歩以上
        Item(
            id: "glowing_stone",
            name: "光る石",
            description: "なぜか温かかった",
            emoji: "✨",
            condition: .steps(min: 10000, max: Int.max)
        ),

        // 5000〜9999歩
        Item(
            id: "rusty_key",
            name: "さびた鍵",
            description: "どこのかわからない",
            emoji: "🗝️",
            condition: .steps(min: 5000, max: 10000)
        ),

        // 3000〜4999歩
        Item(
            id: "pebble",
            name: "小石",
            description: "気に入った",
            emoji: "🪨",
            condition: .steps(min: 3000, max: 5000)
        ),

        // 3000歩未満
        Item(
            id: "dry_grass",
            name: "枯れ草のたば",
            description: "においがした",
            emoji: "🌾",
            condition: .steps(min: 0, max: 3000)
        ),
    ]

    // MARK: - 1日分の歩数からアイテムを確定取得

    func determineItem(steps: Int) -> Item? {
        allItems.first { $0.condition.isSatisfied(steps: steps) }
    }
}
