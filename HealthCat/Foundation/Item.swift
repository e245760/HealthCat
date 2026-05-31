import Foundation

// MARK: - Item（値型・永続化不要）

struct Item: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let emoji: String
    let condition: ItemCondition
}

// MARK: - 入手条件

enum ItemCondition: Codable, Equatable {
    case steps(min: Int, max: Int)

    func isSatisfied(steps: Int) -> Bool {
        switch self {
        case .steps(let min, let max):
            return steps >= min && steps < max
        }
    }
}
