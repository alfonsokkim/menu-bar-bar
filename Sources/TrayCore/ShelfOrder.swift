import Foundation

public enum ShelfOrder {
    public static func moving<ID: Equatable>(_ id: ID, beside target: ID, before: Bool, in order: [ID]) -> [ID] {
        guard id != target, order.contains(id), order.contains(target) else { return order }
        var result = order.filter { $0 != id }
        guard let index = result.firstIndex(of: target) else { return order }
        result.insert(id, at: before ? index : index + 1)
        return result
    }

    /// Retain unknown items in their native relative order after saved items.
    public static func indices(for keys: [String], saved: [String]) -> [Int] {
        var ranks: [String: Int] = [:]
        for (index, key) in saved.enumerated() where ranks[key] == nil { ranks[key] = index }
        return keys.indices.sorted {
            let left = ranks[keys[$0]] ?? Int.max
            let right = ranks[keys[$1]] ?? Int.max
            return left == right ? $0 < $1 : left < right
        }
    }

    public static func identity(bundle: String, title: String, occurrence: Int) -> String {
        // Length prefixes avoid collisions when names contain separators.
        "\(bundle.utf8.count):\(bundle)\(title.utf8.count):\(title):\(occurrence)"
    }
}
