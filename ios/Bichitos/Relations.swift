import Foundation

/// What the card shows and edits: who a bichito likes, dislikes and is family with (only bichitos still in the world), and its name.
extension World {
    /// Below this, affinity is just "knows them".
    static let feeling = 0.1

    /// Liked most first; ties by id so the card never shuffles.
    func friends(of id: Int, limit: Int = 3) -> [Bichito] {
        feelings(id).filter { $0.a >= World.feeling }
            .sorted { $0.a != $1.a ? $0.a > $1.a : $0.b.id < $1.b.id }
            .prefix(limit).map { $0.b }
    }

    /// Disliked most first.
    func rivals(of id: Int, limit: Int = 3) -> [Bichito] {
        feelings(id).filter { $0.a <= -World.feeling }
            .sorted { $0.a != $1.a ? $0.a < $1.a : $0.b.id < $1.b.id }
            .prefix(limit).map { $0.b }
    }

    func parents(of id: Int) -> [Bichito] { bichito(id)?.parents.compactMap { bichito($0) } ?? [] }

    func children(of id: Int) -> [Bichito] { bichitos.filter { $0.parents.contains(id) } }

    /// Blank names are ignored; a description that starts with the old name follows along.
    mutating func rename(_ id: Int, to name: String) {
        let new = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        guard !new.isEmpty, let i = index(of: id) else { return }
        let old = bichitos[i].name
        bichitos[i].name = new
        if bichitos[i].description.hasPrefix(old) {
            bichitos[i].description = new + bichitos[i].description.dropFirst(old.count)
        }
    }

    private func feelings(_ id: Int) -> [(b: Bichito, a: Double)] {
        guard let me = bichito(id) else { return [] }
        return me.affinity.compactMap { other, a in bichito(other).map { (b: $0, a: a) } }
    }
}
