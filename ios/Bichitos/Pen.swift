import Foundation

/// Where the world lives between launches: one JSON file in Documents.
struct Pen {
    struct Saved: Codable { var world: World; var lastSaved: Date }

    /// What opening the pen finds, already fast-forwarded to now.
    struct Opening {
        var world: World?        // nil: no save yet, or a broken one; start a new world
        var away: [String] = []  // "mientras no estabas"; empty when nothing happened
        var broken = false       // the save would not load
        var backup: URL?         // where the broken save was moved; nil while `broken` = it couldn't be moved, so never save over it
        var took = 0.0           // wall-clock seconds the fast-forward took
    }

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
        var saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: url))
        saved.world.fitDistricts()
        return saved
    }

    /// Loads the save and fast-forwards it to `now`. A save that won't load is moved aside, never overwritten.
    /// Can take a couple of seconds: call it off the main thread.
    func open(now: Date = Date()) -> Opening {
        do {
            guard let saved = try load() else { return Opening() }
            return Pen.fastForward(saved.world, from: saved.lastSaved, to: now)
        } catch {
            return Opening(broken: true, backup: try? backUp(now))
        }
    }

    /// Moves the save to pen-broken-<time>.json next to it, so the next save starts a new file.
    func backUp(_ now: Date = Date()) throws -> URL {
        let backup = url.deletingLastPathComponent().appendingPathComponent("pen-broken-\(Int(now.timeIntervalSince1970)).json")
        try FileManager.default.moveItem(at: url, to: backup)
        return backup
    }

    static func fastForward(_ world: World, from lastSaved: Date, to now: Date) -> Opening {
        var world = world
        let start = Date()
        world.catchUp(seconds: now.timeIntervalSince(lastSaved))
        return Opening(world: world, away: world.summary(world.language), took: Date().timeIntervalSince(start))
    }
}
