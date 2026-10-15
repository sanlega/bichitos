import Foundation

/// Where the world lives between launches: one JSON file in Documents.
struct Pen {
    struct Saved: Codable { var world: World; var lastSaved: Date }

    let url: URL

    init(url: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pen.json")) {
        self.url = url
    }

    func save(_ world: World, at date: Date = Date()) throws {
        try JSONEncoder().encode(Saved(world: world, lastSaved: date)).write(to: url, options: .atomic)
    }

    /// nil only when there is no save yet. A broken file throws, so the caller never overwrites it with a fresh world by accident.
    func load() throws -> Saved? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Saved.self, from: Data(contentsOf: url))
    }
}
