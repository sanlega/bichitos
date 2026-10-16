import Foundation

struct Vec: Codable, Equatable {
    var x: Double, y: Double
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    static let zero = Vec(0, 0)
    static func + (a: Vec, b: Vec) -> Vec { Vec(a.x + b.x, a.y + b.y) }
    static func - (a: Vec, b: Vec) -> Vec { Vec(a.x - b.x, a.y - b.y) }
    static func * (a: Vec, k: Double) -> Vec { Vec(a.x * k, a.y * k) }
    var length: Double { (x * x + y * y).squareRoot() }
    var unit: Vec { length > 1e-9 ? self * (1 / length) : .zero }
}

struct Rect: Codable, Equatable {
    var x: Double, y: Double, w: Double, h: Double
    var center: Vec { Vec(x + w / 2, y + h / 2) }
    func contains(_ p: Vec) -> Bool { p.x >= x && p.x <= x + w && p.y >= y && p.y <= y + h }
}

/// SplitMix64 like `SeededRNG`, but with its state out in the open so the world can save it.
struct SimRNG: RandomNumberGenerator, Codable, Equatable {
    var state: UInt64
    mutating func next() -> UInt64 {
        var g = SeededRNG(seed: state)
        state &+= 0x9E37_79B9_7F4A_7C15
        return g.next()
    }
}

struct Food: Codable, Equatable { let id: Int; var pos: Vec; var kind = Kind.fruta } // kinds and favourites: Comida.swift
struct Egg: Codable, Equatable { let id: Int; var pos: Vec; var parents: [Int]; var recipe: Recipe; var hatchIn: Double }
/// What an escaped bichito leaves behind. It keeps the bichito so food at the note can bring it back.
struct Note: Codable, Equatable { var pos: Vec; var text: String; var bichito: Bichito }

/// Session counter left out of saving and of ==, so a reopened world still equals the one saved.
struct Tally: Equatable {
    var n = 0
    static func == (_: Tally, _: Tally) -> Bool { true }
}

enum WorldEvent: Codable, Equatable {
    case fought(Int, Int), fellInLove(Int, Int), eggLaid(Int, Int), hatched(Int)
    case emigrated(Int, Int) // bichito, district
    case escaped(Int), recovered(Int)
    case unlocked(Int, Recipe.Personality?) // district, and the personality it opened for (nil: just for room)
}

/// Buckets points in square cells; neighbours closer than one cell are always in the 3×3 block around a point.
/// The points sorted by cell key, one sort per pass (n log n, no per-cell storage): a column of the 3×3 block is one
/// run of consecutive keys, found by binary search, so queries allocate nothing.
struct SpatialHash {
    private let cell: Double
    private var keys: [Int] = []  // sorted cell keys, one per point
    private var order: [Int] = [] // the point behind each key: by cell, then by index

    init(cell: Double, points: [Vec]) {
        self.cell = cell
        let k = points.map { key($0, 0, 0) }
        order = points.indices.sorted { k[$0] != k[$1] ? k[$0] < k[$1] : $0 < $1 }
        keys = order.map { k[$0] }
    }

    /// Visits the points in the 3×3 block around `p` column by column (x−1, x, x+1), each column by row and each cell
    /// in index order, until `stop` returns true. Callers depend on this order: it is what keeps the world deterministic.
    func forEach(near p: Vec, _ stop: (Int) -> Bool) {
        for dx in -1...1 {
            let first = key(p, dx, -1), last = key(p, dx, 1)
            var lo = 0, hi = keys.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if keys[mid] < first { lo = mid + 1 } else { hi = mid }
            }
            while lo < keys.count && keys[lo] <= last {
                if stop(order[lo]) { return }
                lo += 1
            }
        }
    }

    private func key(_ p: Vec, _ dx: Int, _ dy: Int) -> Int {
        (Int((p.x / cell).rounded(.down)) + dx) * 100_000 + Int((p.y / cell).rounded(.down)) + dy
    }
}

/// TEMPORARY (#92): where `tick()` spends its time, in ns per phase.
enum Profile {
    static let names = ["tick total", "update()", "encounters", "emigrate", "escapeNeglected", "hatchEggs", "tick preamble (terrain, drowsiness)", "  decide()", "  toBench()", "  meet()", "record (events+news)", "  nearestWalkable at start", "  steer()", "  breed()", "  add() child"]
    static var ns = Array(repeating: 0, count: 15)
    static var hits = Array(repeating: 0, count: 15)
    static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    static func add(_ k: Int, _ since: UInt64) { ns[k] += Int(now() - since); hits[k] += 1 }
    static func reset() { ns = Array(repeating: 0, count: 15); hits = ns }
    static var report: String {
        names.indices.map { "\(names[$0]): " + String(format: "%.3f s (%ld)", Double(ns[$0]) / 1e9, hits[$0]) }.joined(separator: "\n")
    }
}

/// The whole terrarium. Pure value, deterministic for a seed, always advanced in fixed 1/20 s ticks.
struct World: Codable, Equatable {
    static let hz = 20.0
    static let dt = 1 / hz
    static let capacity = 14              // bichitos per district before the next one unlocks
    static var maxPopulation: Int { capacity * District.themes.count }
    static let lod = 10                   // off-screen bichitos move every 10 ticks (2 Hz) with a 10× step
    static let encounterEvery = 20        // ticks between encounter checks; doubled when nobody watches
    static let hungerSpan = 36 * 3600.0   // seconds from full to starving
    static let affectionSpan = 48 * 3600.0
    static let awakeSpan = 16 * 3600.0
    static let napSpan = 600.0            // seconds of sleep from exhausted to rested
    static let hatchTime = 180.0
    static let breedCooldown = 3600.0
    static let benchStay = 40.0           // seconds a pair sits together on the banco
    static let benchLove = 0.005          // affinity per second they sit there
    static let fullCatchUp = 2 * 3600.0
    static let maxCatchUp = 7 * 86400.0
    static let maxEvents = 2000

    var language: Language
    var date: Date
    var tickCount = 0
    var nextId = 1
    var bichitos: [Bichito] = []
    var foods: [Food] = []
    var eggs: [Egg] = []
    var notes: [Note] = []
    var districts: [District] = []
    /// Places the districts (Barrios.swift); nil in saves from before the ring, until `fitDistricts`.
    var layoutSeed: UInt64?
    var events: [WorldEvent] = []
    /// Events recorded since launch (the log above is capped): the scene's cursor for live toasts.
    var eventTotal: Int { tally.n }
    private var tally = Tally()
    var newsLog: News? = nil // read it through `news` (Noticias.swift); optional so saves from before it still load
    var rng: SimRNG
    /// Set by the scene; nil = nobody is watching, so everyone gets the cheap off-screen physics.
    var visibleRect: Rect? = nil
    /// Whose clock sets day and night (Noche.swift): the device's, never saved. Tests pin it.
    var timeZone = TimeZone.current
    private var pending = 0.0

    private enum CodingKeys: String, CodingKey {
        case language, date, tickCount, nextId, bichitos, foods, eggs, notes, districts, layoutSeed, events, newsLog, rng
    }

    init(seed: UInt64, date: Date = Date(), language: Language = .es) {
        rng = SimRNG(state: seed)
        layoutSeed = seed
        self.date = date
        self.language = language
        unlock(0)
    }

    /// Through the buffer: in Debug `bichitos[i]` copies the whole `Bichito` (~0.2 µs), and every lover, fighter and
    /// chaser looks its partner up on every step.
    func index(of id: Int) -> Int? {
        bichitos.withUnsafeBufferPointer { all in
            for i in all.indices where all[i].id == id { return i }
            return nil
        }
    }
    func bichito(_ id: Int) -> Bichito? { index(of: id).map { bichitos[$0] } }

    func clamp(_ p: Vec, _ r: Double) -> Vec {
        let s = bounds
        return Vec(min(max(p.x, s.x + r), s.x + s.w - r), min(max(p.y, s.y + r), s.y + s.h - r))
    }

    // MARK: - Population

    @discardableResult
    mutating func add(_ recipe: Recipe, at pos: Vec? = nil, name: String? = nil, description: String? = nil, parents: [Int] = []) -> Int {
        unlockIfCrowded(extra: 1)
        let id = newId()
        let d = home(for: pos)
        var p: Vec
        if let pos = pos {
            p = pos
        } else {
            let r = districts[d].rect
            let fx = roll(0.1...0.9), fy = roll(0.1...0.9)
            p = Vec(r.x + fx * r.w, r.y + fy * r.h)
        }
        p = terrain.nearestWalkable(clamp(p, recipe.radius))
        let heading = roll(0...(2 * Double.pi))
        let generated = Names.make(seed: recipe.seed, language: language, taken: takenNames)
        let b = Bichito(id: id, recipe: recipe, name: name ?? generated.name, description: description ?? generated.description,
                        born: date, parents: parents, pos: p, heading: heading, district: d)
        bichitos.append(b)
        findHome(bichitos.count - 1)
        return id
    }

    /// Opens a district once the population outgrows the current ones, so there is always room:
    /// the one most of them are affine to (`nextDistrict`).
    mutating func unlockIfCrowded(extra: Int = 0) {
        guard bichitos.count + extra > World.capacity * districts.count, let next = nextDistrict() else { return }
        unlock(next.theme)
        record(.unlocked(districts.count - 1, next.reason))
    }

    private func home(for p: Vec?) -> Int {
        var counts = Array(repeating: 0, count: districts.count)
        for b in bichitos { counts[b.district] += 1 }
        if let p = p, let d = districts.firstIndex(where: { $0.rect.contains(p) }), counts[d] < World.capacity { return d }
        return counts.indices.min { counts[$0] < counts[$1] } ?? 0
    }

    // MARK: - User actions

    /// Returns false when it grumbles instead (it was asleep).
    @discardableResult
    mutating func pet(_ id: Int) -> Bool {
        guard let i = index(of: id), bichitos[i].mood != .held else { return false }
        if bichitos[i].mood == .sleep {
            bichitos[i].enter(.wander, for: 2)
            return false
        }
        bichitos[i].needs.affection = min(1, bichitos[i].needs.affection + 0.25)
        bichitos[i].enter(.happy, for: 1.5)
        return true
    }

    mutating func grab(_ id: Int) {
        guard let i = index(of: id) else { return }
        bichitos[i].enter(.held, for: 0)
        bichitos[i].vel = .zero
    }

    mutating func move(_ id: Int, to p: Vec) {
        guard let i = index(of: id) else { return }
        bichitos[i].pos = clamp(p, bichitos[i].recipe.radius)
    }

    /// Throw it: it keeps the momentum, bounces off the walls and is dizzy for a moment.
    mutating func release(_ id: Int, velocity v: Vec) {
        guard let i = index(of: id) else { return }
        bichitos[i].enter(.wander, for: 1)
        bichitos[i].pos = terrain.nearestWalkable(bichitos[i].pos) // dropped over water or rock: lands on the shore
        bichitos[i].vel = v
        bichitos[i].dizzy = min(3, v.length / 300)
    }

    /// Hungry bichitos run to it. Its favourite dropped next to a goodbye note brings the runaway back.
    @discardableResult
    mutating func dropFood(at p: Vec, kind: Food.Kind = .fruta) -> Int {
        if let n = notes.firstIndex(where: { ($0.pos - p).length < 60 && $0.bichito.favorite == kind }) { recover(n) }
        let id = newId()
        foods.append(Food(id: id, pos: foodSpot(clamp(p, 4)), kind: kind))
        for i in bichitos.indices where bichitos[i].needs.hunger < 0.7 && bichitos[i].mood.isFree {
            bichitos[i].enter(.eat, for: 30, target: id)
        }
        return id
    }

    /// A fright around `p`, or everyone at once when `p` is nil (shaking the phone).
    mutating func scare(at p: Vec? = nil, radius: Double = 250) {
        for i in bichitos.indices where bichitos[i].mood != .held {
            let pos = bichitos[i].pos
            if let p = p, (pos - p).length > radius { continue }
            var threat = pos + Vec(roll(-1...1), roll(-1...1))
            if let p = p { threat = p }
            bichitos[i].enter(.scared, for: 2, threat: threat)
        }
    }

    // MARK: - Time

    /// Feed it real frame time; the world itself only moves in fixed ticks.
    mutating func step(_ dt: Double) {
        pending = min(pending + dt, 0.25)
        while pending >= World.dt {
            pending -= World.dt
            tick()
        }
    }

    mutating func tick() {
        let p0 = Profile.now()
        defer { Profile.add(0, p0) }
        tickCount += 1
        date += World.dt
        let watched = visibleRect != nil
        let walls = bounds // once per tick, not per body: districts only unlock after the moves
        let ground = terrain
        let drowsy = drowsiness
        Profile.add(6, p0)
        if watched {
            for i in bichitos.indices {
                let visible = isVisible(bichitos[i].pos)
                if !visible && (tickCount + i) % World.lod != 0 { continue }
                update(i, visible ? World.dt : World.dt * Double(World.lod), walls, ground, drowsy)
            }
        } else {
            // Only every lod-th bichito is due: jump straight to them instead of skipping the rest one by one.
            let lod = World.lod, h = World.dt * Double(World.lod)
            var i = (lod - tickCount % lod) % lod
            while i < bichitos.count {
                let u0 = Profile.now()
                update(i, h, walls, ground, drowsy)
                Profile.add(1, u0)
                i += lod
            }
        }
        if watched { collide() }
        var q = Profile.now()
        if tickCount % (watched ? World.encounterEvery : 2 * World.encounterEvery) == 0 { encounters(); Profile.add(2, q) }
        q = Profile.now()
        if tickCount % 600 == 0 { emigrate(); Profile.add(3, q) }
        q = Profile.now()
        if tickCount % 20 == 0 { escapeNeglected(); Profile.add(4, q) }
        q = Profile.now()
        hatchEggs(World.dt)
        Profile.add(5, q)
    }

    /// Fast-forward after being away: the last 2 h fully simulated, the rest (up to 7 days) only needs and escapes.
    /// Clears the event log first, so afterwards it holds exactly what happened while away.
    mutating func catchUp(seconds: Double) {
        events.removeAll()
        for i in bichitos.indices where bichitos[i].mood == .held { bichitos[i].enter(.wander, for: 1) }
        let total = min(max(0, seconds), World.maxCatchUp)
        let full = min(total, World.fullCatchUp)
        passTime(total - full)
        let watching = visibleRect
        visibleRect = nil
        for _ in 0..<Int(full * World.hz) { tick() }
        visibleRect = watching
    }

    /// Needs only, in 10-minute steps so each one sees its own hour: asleep and rested from its bedtime until dawn,
    /// awake the rest of the day, tiring faster in the evening and napping on its own when worn out.
    private mutating func passTime(_ s: Double) {
        guard s > 0 else { return }
        var left = s
        while left > 0 {
            let c = min(600, left)
            left -= c
            date += c
            let drowsy = drowsiness
            for i in bichitos.indices {
                var n = bichitos[i].needs
                n.hunger = max(0, n.hunger - c / World.hungerSpan)
                n.affection = max(0, n.affection - c / World.affectionSpan)
                if drowsy > bichitos[i].bedtime {
                    n.sleep = 1
                } else {
                    n.sleep -= c * bichitos[i].recipe.sleepiness * (1 + 3 * drowsy) / World.awakeSpan
                    if n.sleep < 0.3 { n.sleep = 1 } // a nap
                }
                bichitos[i].needs = n
                bichitos[i].breedCooldown -= c
            }
        }
        escapeNeglected()
        // Handing over to the full simulation at night: whoever it is bedtime for is already asleep in bed.
        let ground = terrain, drowsy = drowsiness
        for i in bichitos.indices where drowsy > bichitos[i].bedtime {
            if let p = bedSpot(for: bichitos[i], ground) { bichitos[i].pos = p }
            bichitos[i].vel = .zero
            let nap = roll(60...240)
            bichitos[i].enter(.sleep, for: nap)
        }
    }

    // MARK: - Brain and body

    private mutating func update(_ i: Int, _ h: Double, _ walls: Rect, _ ground: Terrain, _ drowsy: Double) {
        var b = bichitos[i]
        guard b.mood != .held else { return }
        let n0 = Profile.now()
        b.pos = ground.nearestWalkable(b.pos)
        Profile.add(11, n0) // only moves one that something else left in water or rock
        let r = b.recipe
        b.timer -= h
        b.calm -= h
        b.dizzy -= h
        b.breedCooldown -= h
        b.needs.hunger = max(0, b.needs.hunger - h / World.hungerSpan)
        b.needs.affection = max(0, b.needs.affection - h / World.affectionSpan)
        if b.mood == .sleep {
            b.needs.sleep = min(1, b.needs.sleep + h / World.napSpan)
            if b.needs.sleep >= 1 && drowsy <= b.bedtime { b.timer = 0 } // rested: up, unless it is its night
        } else {
            b.needs.sleep = max(0, b.needs.sleep - h * r.sleepiness * (1 + 3 * drowsy) / World.awakeSpan)
        }

        var dir = Vec.zero
        var pace = 0.0
        switch b.mood {
        case .wander:
            let home = districts[b.district].rect
            if home.contains(b.pos) {
                let wobble = roll(-1...1)
                b.heading += wobble * r.turn * h * 2
            } else {
                b.heading = atan2(home.center.y - b.pos.y, home.center.x - b.pos.x)
            }
            dir = Vec(cos(b.heading), sin(b.heading))
            pace = 0.6
        case .eat:
            if let f = foods.first(where: { $0.id == b.target }) {
                let d = f.pos - b.pos
                // Reachable within this step counts as there, so the 2 Hz off-screen step never overshoots the food.
                if d.length < r.radius + 6 + r.speed * 1.3 * h { eat(f, &b) } else { dir = d.unit; pace = 1.3 }
            } else {
                b.timer = 0
            }
        case .love, .fight, .chase, .imitate:
            guard let t = b.target, let j = index(of: t) else { b.timer = 0; break }
            let o = bichitos[j]
            let d = o.pos - b.pos
            switch b.mood {
            case .love:
                if let k = b.bench { let t0 = Profile.now(); dir = toBench(i, &b, j, o, k, h, ground, drowsy); pace = 0.8; Profile.add(8, t0) }
                else if d.length > r.radius + o.recipe.radius + 4 { dir = d.unit; pace = 0.8 }
            case .fight: dir = d.unit; pace = 1.2
            case .chase: dir = d.unit; pace = 1.4
            default: // imitate: catch up, then copy their moves
                if d.length > 120 { dir = d.unit; pace = 1 } else { dir = o.vel.unit; pace = min(1.5, o.vel.length / r.speed) }
            }
        case .flee, .scared:
            if let t = b.threat { dir = (b.pos - t).unit }
            pace = b.mood == .scared ? 1.8 : 1.5
        case .incubating:
            if let e = eggs.first(where: { $0.id == b.target }) {
                let d = e.pos - b.pos
                if d.length > 6 { dir = d.unit; pace = 0.7 }
            } else {
                b.timer = 0
            }
        case .toBed:
            let spot = b.target.flatMap { ground.buildings.indices.contains($0) ? ground.buildings[$0].bed : nil } ?? b.pos
            let d = spot - b.pos
            if d.length < 8 + r.speed * 0.8 * h {
                b.vel = .zero
                b.enter(.sleep, for: roll(60...240))
            } else {
                dir = d.unit; pace = 0.8
            }
        case .sleep, .happy, .held:
            break
        }
        if dir != .zero {
            let s0 = Profile.now()
            let d = steer(dir, b, ground)
            Profile.add(12, s0)
            if d != dir { dir = d; if b.mood == .wander { b.heading = atan2(d.y, d.x) } }
        }

        if b.dizzy > 0 {
            b.vel = b.vel * max(0, 1 - 2.5 * h)
        } else {
            b.vel = b.vel + (dir * (r.speed * pace) - b.vel) * min(1, 6 * h)
        }
        let from = b.pos
        b.pos = b.pos + b.vel * h
        bounce(&b, walls)
        if !ground.walkable(b.pos) { shore(&b, from, ground) }
        if b.timer <= 0 { let d0 = Profile.now(); decide(&b, ground, drowsy); Profile.add(7, d0) }
        bichitos[i] = b
    }

    private mutating func decide(_ b: inout Bichito, _ ground: Terrain, _ drowsy: Double) {
        if b.mood == .toBed { b.enter(.sleep, for: roll(60...240)); return } // never got there: sleeps where it is
        let late = drowsy > b.bedtime // from its bedtime at dusk until it wakes at dawn
        if late, b.mood == .sleep, bedSpot(for: b, ground).map({ (b.pos - $0).length < 48 }) ?? true {
            b.enter(.sleep, for: roll(60...240)) // in bed: sleeps on
            return
        }
        if late || b.needs.sleep < 0.3 || roll() < 0.04 * b.recipe.sleepiness {
            if let bed = bed(for: b, ground) { b.enter(.toBed, for: 90, target: bed) } else { b.enter(.sleep, for: roll(60...240)) }
        } else if b.needs.hunger < 0.6, let f = foods.min(by: { ($0.pos - b.pos).length < ($1.pos - b.pos).length }) {
            b.enter(.eat, for: 30, target: f.id)
        } else {
            b.enter(.wander, for: roll(3...8))
            b.heading = roll(0...(2 * Double.pi))
        }
    }

    /// Its casita, or else the tree of its district nearest to it; nil when its district has neither.
    private func bed(for b: Bichito, _ ground: Terrain) -> Int? {
        if let h = b.home { return h }
        let theme = districts[b.district].index
        return ground.buildings.filter { $0.kind == .tree && $0.theme == theme }
            .min { ($0.rect.center - b.pos).length < ($1.rect.center - b.pos).length }?.id
    }

    private func bedSpot(for b: Bichito, _ ground: Terrain) -> Vec? { bed(for: b, ground).flatMap { ground.buildings[$0].bed } }

    private mutating func eat(_ food: Food, _ b: inout Bichito) {
        foods.removeAll { $0.id == food.id }
        b.eat(food.kind)
        b.enter(.happy, for: 2)
    }

    private func bounce(_ b: inout Bichito, _ s: Rect) {
        let r = b.recipe.radius
        let x0 = s.x + r, x1 = s.x + s.w - r, y0 = s.y + r, y1 = s.y + s.h - r
        if b.pos.x < x0 { b.pos.x = x0; b.vel.x = abs(b.vel.x) * 0.6; b.heading = .pi - b.heading }
        if b.pos.x > x1 { b.pos.x = x1; b.vel.x = -abs(b.vel.x) * 0.6; b.heading = .pi - b.heading }
        if b.pos.y < y0 { b.pos.y = y0; b.vel.y = abs(b.vel.y) * 0.6; b.heading = -b.heading }
        if b.pos.y > y1 { b.pos.y = y1; b.vel.y = -abs(b.vel.y) * 0.6; b.heading = -b.heading }
    }

    private static let detours = [0.6, 1.2, 1.8, 2.4, 3.0] // radians, tried on each side in turn

    /// Water or rock just ahead: the first clear heading turning away from it, each bichito favouring its own side.
    /// A simple detour, no pathfinding: it slides along the shore and may give up in a dead end.
    private func steer(_ dir: Vec, _ b: Bichito, _ ground: Terrain) -> Vec {
        let ahead = b.recipe.radius + Terrain.cell
        guard !ground.walkable(b.pos + dir * ahead) else { return dir }
        let side = b.id % 2 == 0 ? 1.0 : -1.0
        for a in World.detours {
            for k in 0..<2 {
                let s = k == 0 ? side : -side, c = cos(a * s), n = sin(a * s)
                let d = Vec(dir.x * c - dir.y * n, dir.x * n + dir.y * c)
                if ground.walkable(b.pos + d * ahead) { return d }
            }
        }
        return dir
    }

    /// Never into water or rock: slide along it on one axis, bouncing off like off the walls, or stop where it was.
    private func shore(_ b: inout Bichito, _ from: Vec, _ ground: Terrain) {
        if ground.walkable(Vec(b.pos.x, from.y)) {
            b.pos.y = from.y; b.vel.y = -b.vel.y * 0.6
        } else if ground.walkable(Vec(from.x, b.pos.y)) {
            b.pos.x = from.x; b.vel.x = -b.vel.x * 0.6
        } else {
            b.pos = from; b.vel = b.vel * -0.6
        }
    }

    private func isVisible(_ p: Vec) -> Bool {
        guard let v = visibleRect else { return false }
        return v.contains(p)
    }

    /// Soft collisions between on-screen bodies; fighters bonk each other away.
    private mutating func collide() {
        let ids = bichitos.indices.filter { bichitos[$0].mood != .held && isVisible(bichitos[$0].pos) }
        guard ids.count > 1 else { return }
        let grid = SpatialHash(cell: 64, points: ids.map { bichitos[$0].pos })
        let ground = terrain
        for (a, i) in ids.enumerated() {
            grid.forEach(near: bichitos[i].pos) { k in
                guard k > a else { return false }
                let j = ids[k]
                let d = bichitos[j].pos - bichitos[i].pos
                let len = d.length
                let reach = bichitos[i].recipe.radius + bichitos[j].recipe.radius
                guard len < reach else { return false }
                let n = len > 1e-6 ? d * (1 / len) : Vec(1, 0)
                let push = n * ((reach - len) / 2)
                let p1 = clamp(bichitos[i].pos - push, bichitos[i].recipe.radius)
                let p2 = clamp(bichitos[j].pos + push, bichitos[j].recipe.radius)
                if ground.walkable(p1) { bichitos[i].pos = p1 } // pushed against the shore, it stays put
                if ground.walkable(p2) { bichitos[j].pos = p2 }
                if fighting(bichitos[i], bichitos[j]) {
                    let bonk = n * 160
                    bichitos[i].vel = bichitos[i].vel - bonk
                    bichitos[j].vel = bichitos[j].vel + bonk
                    bichitos[i].dizzy = 0.3
                    bichitos[j].dizzy = 0.3
                }
                return false
            }
        }
    }

    private func fighting(_ a: Bichito, _ b: Bichito) -> Bool {
        (a.mood == .fight && a.target == b.id) || (b.mood == .fight && b.target == a.id)
    }

    // MARK: - Social life

    private mutating func encounters() {
        // Only the open (free and calm) can meet, and meeting never opens anyone, so the rest stay out of the grid.
        let open = bichitos.indices.filter { bichitos[$0].mood.isFree && bichitos[$0].calm <= 0 }
        guard open.count > 1 else { return }
        let grid = SpatialHash(cell: 64, points: open.map { bichitos[$0].pos })
        for i in open where bichitos[i].mood.isFree && bichitos[i].calm <= 0 {
            var met = -1
            grid.forEach(near: bichitos[i].pos) { k in
                let j = open[k]
                guard j != i, bichitos[j].mood.isFree, bichitos[j].calm <= 0 else { return false }
                let reach = bichitos[i].recipe.radius + bichitos[j].recipe.radius + 24
                guard (bichitos[j].pos - bichitos[i].pos).length < reach else { return false }
                met = j
                return true
            }
            if met >= 0 { let m0 = Profile.now(); meet(i, met); Profile.add(9, m0) }
        }
    }

    /// `i` bumps into `j`: what happens is weighted by i's personality and by what i thinks of j.
    private mutating func meet(_ i: Int, _ j: Int) {
        let a = bichitos[i], b = bichitos[j]
        let aff = a.affinity[b.id] ?? 0
        let p = a.recipe.personality
        func weight(_ fan: Recipe.Personality, _ others: Double) -> Double { p == fan ? 3 : others }
        let warm = max(0, 1 + aff), cold = max(0, 1 - aff)
        let options: [(Bichito.Mood, Double)] = [
            (.fight, weight(.territorial, 0.2) * cold),
            (.love, weight(.romantica, 0.3) * warm),
            (.flee, weight(.nerviosa, 0.2) * cold),
            (.imitate, weight(.curiosa, 0.3) * warm),
            (.chase, weight(.hiperactiva, 0.3)),
            (.wander, 1.5), // shrug and carry on
        ]
        var left = roll() * options.reduce(0.0) { $0 + $1.1 }
        var pick = Bichito.Mood.wander
        for (mood, w) in options {
            left -= w
            if left < 0 { pick = mood; break }
        }
        let calmA = roll(6...14), calmB = roll(6...14)
        bichitos[i].calm = calmA
        bichitos[j].calm = calmB

        switch pick {
        case .fight:
            bichitos[i].enter(.fight, for: 3, target: b.id)
            bichitos[j].enter(.fight, for: 3, target: a.id)
            like(i, j, -0.15)
            like(j, i, -0.15)
            record(.fought(a.id, b.id))
        case .love:
            guard (b.affinity[a.id] ?? 0) > -0.2 else {
                bichitos[j].enter(.flee, for: 1.5, threat: a.pos) // not interested
                return
            }
            like(i, j, 0.12)
            like(j, i, 0.12)
            if aff < 0.6 && aff + 0.12 >= 0.6 { record(.fellInLove(a.id, b.id)) }
            for k in [i, j] { bichitos[k].needs.affection = min(1, bichitos[k].needs.affection + 0.2) }
            // To the district's banco while it is free (they lay their egg there, `toBench`); else love here and now.
            let bench = freeBench(a.district)
            bichitos[i].enter(.love, for: bench == nil ? 5 : 90, target: b.id)
            bichitos[j].enter(.love, for: bench == nil ? 5 : 90, target: a.id)
            if bench == nil { breed(i, j) } else { bichitos[i].bench = bench; bichitos[j].bench = bench }
        case .flee:
            bichitos[i].enter(.flee, for: 2, threat: b.pos)
            like(i, j, -0.03)
        case .imitate:
            bichitos[i].enter(.imitate, for: 4, target: b.id)
            like(i, j, 0.05)
        case .chase:
            bichitos[i].enter(.chase, for: 3, target: b.id)
            like(i, j, 0.02)
            if b.recipe.personality == .nerviosa { bichitos[j].enter(.flee, for: 3, threat: a.pos) }
        default:
            break
        }
    }

    private mutating func like(_ i: Int, _ j: Int, _ delta: Double) {
        let id = bichitos[j].id
        bichitos[i].affinity[id] = min(1, max(-1, (bichitos[i].affinity[id] ?? 0) + delta))
    }

    /// Two who adore each other lay an egg; `i` sits on it until it hatches.
    private mutating func breed(_ i: Int, _ j: Int) {
        let b0 = Profile.now()
        defer { Profile.add(13, b0) }
        let a = bichitos[i], b = bichitos[j]
        guard (a.affinity[b.id] ?? 0) >= 0.7, (b.affinity[a.id] ?? 0) >= 0.7,
              a.breedCooldown <= 0, b.breedCooldown <= 0,
              bichitos.count + eggs.count < World.maxPopulation else { return }
        let id = newId()
        let recipe = Recipe.child(of: a.recipe, and: b.recipe, using: &rng)
        let pos = nestSpot(a.district) ?? terrain.nearestWalkable(clamp((a.pos + b.pos) * 0.5, 8))
        eggs.append(Egg(id: id, pos: pos, parents: [a.id, b.id], recipe: recipe, hatchIn: World.hatchTime))
        bichitos[i].breedCooldown = World.breedCooldown
        bichitos[j].breedCooldown = World.breedCooldown
        bichitos[i].enter(.incubating, for: World.hatchTime + 5, target: id)
        record(.eggLaid(a.id, b.id))
    }

    /// A bench lover (`i`, its partner `j` = `o`) walks to its end of the banco `k`. Seated, it faces its partner and
    /// waits, its clock stopped, until both sit; then they stay `benchStay` and love grows. The lower id ends the date: they
    /// lay their egg (if they can) and get up. Returns where to walk, zero once seated. The partner gone calls it off,
    /// and so does its bedtime: night wins, the date ends with no egg and `decide` sends it to bed (the partner follows).
    private mutating func toBench(_ i: Int, _ b: inout Bichito, _ j: Int, _ o: Bichito, _ k: Int, _ h: Double,
                                  _ ground: Terrain, _ drowsy: Double) -> Vec {
        guard o.bench == k, o.target == b.id, ground.buildings.indices.contains(k), drowsy <= b.bedtime else {
            b.timer = 0
            return .zero
        }
        let bench = ground.buildings[k], seat = World.seat(on: bench, b.id, o.id)
        let d = seat - b.pos
        guard d.length < 2 + b.recipe.speed * 0.8 * h else { return d.unit }
        let arriving = b.pos != seat
        b.pos = seat
        b.vel = .zero
        b.heading = b.id < o.id ? 0 : .pi // facing each other
        guard o.pos == World.seat(on: bench, o.id, b.id) else { b.timer = World.benchStay; return .zero } // waits
        if arriving { b.timer = World.benchStay }
        let aff = b.affinity[o.id] ?? 0, grow = h * World.benchLove
        b.affinity[o.id] = min(1, aff + grow)
        guard b.id < o.id else { return .zero }
        if aff < 0.6 && aff + grow >= 0.6 { record(.fellInLove(b.id, o.id)) }
        if b.timer < 2 {
            bichitos[i] = b
            breed(i, j)
            for n in [i, j] where bichitos[n].mood == .love { bichitos[n].enter(.happy, for: 3) }
            b = bichitos[i]
        }
        return .zero
    }

    private mutating func hatchEggs(_ h: Double) {
        guard !eggs.isEmpty else { return }
        for k in eggs.indices { eggs[k].hatchIn -= h }
        while let k = eggs.firstIndex(where: { $0.hatchIn <= 0 }) {
            let e = eggs.remove(at: k)
            let a0 = Profile.now()
            let child = add(e.recipe, at: e.pos, parents: e.parents)
            Profile.add(14, a0)
            if let c = index(of: child) { bichitos[c].enter(.happy, for: 2) }
            for p in bichitos.indices where bichitos[p].mood == .incubating && bichitos[p].target == e.id {
                bichitos[p].enter(.happy, for: 3)
            }
            record(.hatched(child))
        }
    }

    /// Now and then a bichito moves to the district where its friends (and its own kind) live, or the one affine to it.
    /// Only unlocked districts are in `districts`, and full ones are skipped.
    mutating func emigrate() {
        guard districts.count > 1 else { return }
        for i in bichitos.indices where bichitos[i].mood == .wander && roll() < 0.05 {
            let b = bichitos[i]
            var score = Array(repeating: 0.0, count: districts.count)
            var count = Array(repeating: 0, count: districts.count)
            for o in bichitos where o.id != b.id {
                score[o.district] += (b.affinity[o.id] ?? 0) + (o.recipe.personality == b.recipe.personality ? 0.3 : 0)
                count[o.district] += 1
            }
            let affine = districts.map { $0.theme.affine == b.recipe.personality }
            func value(_ d: Int) -> Double {
                let friends = count[d] == 0 ? 0 : score[d] / Double(count[d])
                let crowd = Double(count[d]) / Double(World.capacity) * 0.3
                return friends - crowd + (affine[d] ? 0.4 : 0)
            }
            let open = districts.indices.filter { $0 == b.district || count[$0] < World.capacity }
            guard let best = open.max(by: { value($0) < value($1) }),
                  best != b.district, value(best) > value(b.district) + 0.25 else { continue }
            moveHome(i, to: best)
            record(.emigrated(b.id, best))
        }
    }

    /// Its home district is now `district` (it walks there by itself), with a casita there if one has room.
    mutating func moveHome(_ i: Int, to district: Int) {
        let old = bichitos[i].district
        bichitos[i].district = district
        findHome(i)
        rehome(in: old)
    }

    /// Running away frees its casita: `occupants` only counts the bichitos still here.
    private mutating func escapeNeglected() {
        for k in bichitos.indices.reversed() where bichitos[k].isNeglected && bichitos[k].mood != .held {
            let b = bichitos.remove(at: k)
            rehome(in: b.district)
            let seed = rng.next()
            notes.append(Note(pos: b.pos, text: Names.goodbye(name: b.name, seed: seed, language: language), bichito: b))
            record(.escaped(b.id))
        }
    }

    private mutating func recover(_ n: Int) {
        var b = notes.remove(at: n).bichito
        b.needs = Bichito.Needs(hunger: 0.3, sleep: 1, affection: 0.5)
        b.enter(.wander, for: 1)
        bichitos.append(b)
        findHome(bichitos.count - 1) // its casita may have been taken meanwhile
        record(.recovered(b.id))
    }

    // MARK: - Helpers

    private mutating func roll() -> Double { Double.random(in: 0..<1, using: &rng) }
    private mutating func roll(_ r: ClosedRange<Double>) -> Double { Double.random(in: r, using: &rng) }

    private mutating func newId() -> Int {
        nextId += 1
        return nextId - 1
    }

    mutating func record(_ e: WorldEvent) {
        let r0 = Profile.now()
        defer { Profile.add(10, r0) }
        events.append(e)
        tally.n += 1
        report(e)
        if events.count > World.maxEvents { events.removeFirst(events.count - World.maxEvents) }
    }

    // MARK: - "Mientras no estabas"

    /// Empty when nothing worth telling happened: then the app shows no summary at all.
    func summary(_ language: Language) -> [String] {
        let es = language == .es
        func name(_ id: Int) -> String {
            bichito(id)?.name ?? notes.first(where: { $0.bichito.id == id })?.bichito.name ?? "?"
        }
        var pairs: [(a: Int, b: Int, n: Int)] = []
        for case let .fought(x, y) in events {
            let a = min(x, y), b = max(x, y)
            if let k = pairs.firstIndex(where: { $0.a == a && $0.b == b }) { pairs[k].n += 1 } else { pairs.append((a, b, 1)) }
        }
        var lines: [String] = []
        for p in pairs.sorted(by: { $0.n > $1.n }).prefix(3) {
            let times = es ? (p.n == 1 ? "una vez" : "\(p.n) veces") : (p.n == 1 ? "once" : "\(p.n) times")
            lines.append(es ? "\(name(p.a)) y \(name(p.b)) se pelearon \(times)." : "\(name(p.a)) and \(name(p.b)) fought \(times).")
        }
        for e in events {
            let line: String
            switch e {
            case let .fellInLove(a, b): line = es ? "\(name(a)) y \(name(b)) se enamoraron." : "\(name(a)) and \(name(b)) fell in love."
            case let .hatched(c): line = es ? "Nació \(name(c))." : "\(name(c)) was born."
            case let .emigrated(a, d):
                let place = districts[d].name(language)
                line = es ? "\(name(a)) se mudó a \(place)." : "\(name(a)) moved to \(place)."
            case let .escaped(a): line = es ? "\(name(a)) se escapó y dejó una nota." : "\(name(a)) ran away and left a note."
            case let .recovered(a): line = es ? "\(name(a)) volvió a casa." : "\(name(a)) came back home."
            case let .unlocked(d, _):
                let place = districts[d].name(language)
                line = es ? "Se abrió un barrio nuevo: \(place)." : "A new district opened: \(place)."
            case .fought, .eggLaid: continue
            }
            if !lines.contains(line) { lines.append(line) }
        }
        return Array(lines.prefix(8))
    }
}
