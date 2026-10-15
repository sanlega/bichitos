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

/// Districts sit side by side, left to right, in unlock order.
struct District: Codable, Equatable {
    static let namesEs = ["Villa Charco", "Monte Miga", "Barrio Pelusa", "Las Tostadas", "Rincón Grumo", "Valle Calcetín", "Puerto Fideo", "Colina Bostezo"]
    static let namesEn = ["Puddle Town", "Crumb Hill", "Fluffville", "Toast Corner", "Lumpy Nook", "Sock Valley", "Noodle Harbor", "Yawn Hill"]

    var index: Int
    var rect: Rect { Rect(x: Double(index) * World.districtSize.x, y: 0, w: World.districtSize.x, h: World.districtSize.y) }
    func name(_ language: Language) -> String { (language == .es ? District.namesEs : District.namesEn)[index] }
}

struct Food: Codable, Equatable { let id: Int; var pos: Vec }
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
    case escaped(Int), recovered(Int), unlocked(Int)
}

/// Buckets points in square cells; neighbours closer than one cell are always in the 3×3 block around a point.
struct SpatialHash {
    private let cell: Double
    private var cells: [Int: [Int]] = [:]

    init(cell: Double, points: [Vec]) {
        self.cell = cell
        for (i, p) in points.enumerated() { cells[key(p, 0, 0), default: []].append(i) }
    }

    func near(_ p: Vec) -> [Int] {
        var out: [Int] = []
        for dx in -1...1 { for dy in -1...1 { out += cells[key(p, dx, dy)] ?? [] } }
        return out
    }

    private func key(_ p: Vec, _ dx: Int, _ dy: Int) -> Int {
        (Int((p.x / cell).rounded(.down)) + dx) * 100_000 + Int((p.y / cell).rounded(.down)) + dy
    }
}

/// The whole terrarium. Pure value, deterministic for a seed, always advanced in fixed 1/20 s ticks.
struct World: Codable, Equatable {
    static let hz = 20.0
    static let dt = 1 / hz
    static let districtSize = Vec(1000, 1600)
    static let capacity = 12              // bichitos per district before the next one unlocks
    static var maxPopulation: Int { capacity * District.namesEs.count }
    static let lod = 10                   // off-screen bichitos move every 10 ticks (2 Hz) with a 10× step
    static let encounterEvery = 20        // ticks between encounter checks; doubled when nobody watches
    static let hungerSpan = 36 * 3600.0   // seconds from full to starving
    static let affectionSpan = 48 * 3600.0
    static let awakeSpan = 16 * 3600.0
    static let napSpan = 600.0            // seconds of sleep from exhausted to rested
    static let hatchTime = 180.0
    static let breedCooldown = 3600.0
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
    var districts = [District(index: 0)]
    var events: [WorldEvent] = []
    /// Events recorded since launch (the log above is capped): the scene's cursor for live toasts.
    var eventTotal: Int { tally.n }
    private var tally = Tally()
    var rng: SimRNG
    /// Set by the scene; nil = nobody is watching, so everyone gets the cheap off-screen physics.
    var visibleRect: Rect? = nil
    private var pending = 0.0

    private enum CodingKeys: String, CodingKey {
        case language, date, tickCount, nextId, bichitos, foods, eggs, notes, districts, events, rng
    }

    init(seed: UInt64, date: Date = Date(), language: Language = .es) {
        rng = SimRNG(state: seed)
        self.date = date
        self.language = language
    }

    var size: Vec { Vec(Double(districts.count) * World.districtSize.x, World.districtSize.y) }

    func index(of id: Int) -> Int? { bichitos.firstIndex { $0.id == id } }
    func bichito(_ id: Int) -> Bichito? { index(of: id).map { bichitos[$0] } }

    func clamp(_ p: Vec, _ r: Double) -> Vec {
        let s = size
        return Vec(min(max(p.x, r), s.x - r), min(max(p.y, r), s.y - r))
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
        p = clamp(p, recipe.radius)
        let heading = roll(0...(2 * Double.pi))
        let generated = Names.make(seed: recipe.seed, language: language)
        let b = Bichito(id: id, recipe: recipe, name: name ?? generated.name, description: description ?? generated.description,
                        born: date, parents: parents, pos: p, heading: heading, district: d)
        bichitos.append(b)
        return id
    }

    /// Opens the next district once the population outgrows the current ones, so there is always room.
    mutating func unlockIfCrowded(extra: Int = 0) {
        guard bichitos.count + extra > World.capacity * districts.count, districts.count < District.namesEs.count else { return }
        districts.append(District(index: districts.count))
        record(.unlocked(districts.count - 1))
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
        bichitos[i].vel = v
        bichitos[i].dizzy = min(3, v.length / 300)
    }

    /// Hungry bichitos run to it. Dropped next to a goodbye note, it brings the runaway back.
    @discardableResult
    mutating func dropFood(at p: Vec) -> Int {
        if let n = notes.firstIndex(where: { ($0.pos - p).length < 60 }) { recover(n) }
        let id = newId()
        foods.append(Food(id: id, pos: clamp(p, 4)))
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
        tickCount += 1
        date += World.dt
        let watched = visibleRect != nil
        for i in bichitos.indices {
            let visible = watched && isVisible(bichitos[i].pos)
            if !visible && (tickCount + i) % World.lod != 0 { continue }
            update(i, visible ? World.dt : World.dt * Double(World.lod))
        }
        if watched { collide() }
        if tickCount % (watched ? World.encounterEvery : 2 * World.encounterEvery) == 0 { encounters() }
        if tickCount % 600 == 0 { emigrate() }
        if tickCount % 20 == 0 { escapeNeglected() }
        hatchEggs(World.dt)
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

    private mutating func passTime(_ s: Double) {
        guard s > 0 else { return }
        date += s
        for i in bichitos.indices {
            bichitos[i].needs.hunger = max(0, bichitos[i].needs.hunger - s / World.hungerSpan)
            bichitos[i].needs.affection = max(0, bichitos[i].needs.affection - s / World.affectionSpan)
            bichitos[i].needs.sleep = 1 // they nap on their own while nobody watches
            bichitos[i].breedCooldown -= s
        }
        escapeNeglected()
    }

    // MARK: - Brain and body

    private mutating func update(_ i: Int, _ h: Double) {
        var b = bichitos[i]
        guard b.mood != .held else { return }
        let r = b.recipe
        b.timer -= h
        b.calm -= h
        b.dizzy -= h
        b.breedCooldown -= h
        b.needs.hunger = max(0, b.needs.hunger - h / World.hungerSpan)
        b.needs.affection = max(0, b.needs.affection - h / World.affectionSpan)
        if b.mood == .sleep {
            b.needs.sleep = min(1, b.needs.sleep + h / World.napSpan)
            if b.needs.sleep >= 1 { b.timer = 0 }
        } else {
            b.needs.sleep = max(0, b.needs.sleep - h * r.sleepiness / World.awakeSpan)
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
                if d.length < r.radius + 6 + r.speed * 1.3 * h { eat(f.id, &b) } else { dir = d.unit; pace = 1.3 }
            } else {
                b.timer = 0
            }
        case .love, .fight, .chase, .imitate:
            guard let t = b.target, let j = index(of: t) else { b.timer = 0; break }
            let o = bichitos[j]
            let d = o.pos - b.pos
            switch b.mood {
            case .love: if d.length > r.radius + o.recipe.radius + 4 { dir = d.unit; pace = 0.8 }
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
        case .sleep, .happy, .held:
            break
        }

        if b.dizzy > 0 {
            b.vel = b.vel * max(0, 1 - 2.5 * h)
        } else {
            b.vel = b.vel + (dir * (r.speed * pace) - b.vel) * min(1, 6 * h)
        }
        b.pos = b.pos + b.vel * h
        bounce(&b)
        if b.timer <= 0 { decide(&b) }
        bichitos[i] = b
    }

    private mutating func decide(_ b: inout Bichito) {
        if b.needs.sleep < 0.3 || roll() < 0.04 * b.recipe.sleepiness {
            b.enter(.sleep, for: roll(60...240))
        } else if b.needs.hunger < 0.6, let f = foods.min(by: { ($0.pos - b.pos).length < ($1.pos - b.pos).length }) {
            b.enter(.eat, for: 30, target: f.id)
        } else {
            b.enter(.wander, for: roll(3...8))
            b.heading = roll(0...(2 * Double.pi))
        }
    }

    private mutating func eat(_ food: Int, _ b: inout Bichito) {
        foods.removeAll { $0.id == food }
        b.needs.hunger = 1
        b.enter(.happy, for: 2)
    }

    private func bounce(_ b: inout Bichito) {
        let r = b.recipe.radius
        let s = size
        if b.pos.x < r { b.pos.x = r; b.vel.x = abs(b.vel.x) * 0.6; b.heading = .pi - b.heading }
        if b.pos.x > s.x - r { b.pos.x = s.x - r; b.vel.x = -abs(b.vel.x) * 0.6; b.heading = .pi - b.heading }
        if b.pos.y < r { b.pos.y = r; b.vel.y = abs(b.vel.y) * 0.6; b.heading = -b.heading }
        if b.pos.y > s.y - r { b.pos.y = s.y - r; b.vel.y = -abs(b.vel.y) * 0.6; b.heading = -b.heading }
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
        for (a, i) in ids.enumerated() {
            for k in grid.near(bichitos[i].pos) where k > a {
                let j = ids[k]
                let d = bichitos[j].pos - bichitos[i].pos
                let len = d.length
                let reach = bichitos[i].recipe.radius + bichitos[j].recipe.radius
                guard len < reach else { continue }
                let n = len > 1e-6 ? d * (1 / len) : Vec(1, 0)
                let push = n * ((reach - len) / 2)
                let p1 = clamp(bichitos[i].pos - push, bichitos[i].recipe.radius)
                let p2 = clamp(bichitos[j].pos + push, bichitos[j].recipe.radius)
                bichitos[i].pos = p1
                bichitos[j].pos = p2
                if fighting(bichitos[i], bichitos[j]) {
                    let bonk = n * 160
                    bichitos[i].vel = bichitos[i].vel - bonk
                    bichitos[j].vel = bichitos[j].vel + bonk
                    bichitos[i].dizzy = 0.3
                    bichitos[j].dizzy = 0.3
                }
            }
        }
    }

    private func fighting(_ a: Bichito, _ b: Bichito) -> Bool {
        (a.mood == .fight && a.target == b.id) || (b.mood == .fight && b.target == a.id)
    }

    // MARK: - Social life

    private func isOpen(_ b: Bichito) -> Bool { b.mood.isFree && b.calm <= 0 }

    private mutating func encounters() {
        let grid = SpatialHash(cell: 64, points: bichitos.map { $0.pos })
        for i in bichitos.indices where isOpen(bichitos[i]) {
            for j in grid.near(bichitos[i].pos) where j != i && isOpen(bichitos[j]) {
                let reach = bichitos[i].recipe.radius + bichitos[j].recipe.radius + 24
                if (bichitos[j].pos - bichitos[i].pos).length < reach {
                    meet(i, j)
                    break
                }
            }
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
            bichitos[i].enter(.love, for: 5, target: b.id)
            bichitos[j].enter(.love, for: 5, target: a.id)
            breed(i, j)
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
        let a = bichitos[i], b = bichitos[j]
        guard (a.affinity[b.id] ?? 0) >= 0.7, (b.affinity[a.id] ?? 0) >= 0.7,
              a.breedCooldown <= 0, b.breedCooldown <= 0,
              bichitos.count + eggs.count < World.maxPopulation else { return }
        let id = newId()
        let recipe = Recipe.child(of: a.recipe, and: b.recipe, using: &rng)
        let pos = clamp((a.pos + b.pos) * 0.5, 8)
        eggs.append(Egg(id: id, pos: pos, parents: [a.id, b.id], recipe: recipe, hatchIn: World.hatchTime))
        bichitos[i].breedCooldown = World.breedCooldown
        bichitos[j].breedCooldown = World.breedCooldown
        bichitos[i].enter(.incubating, for: World.hatchTime + 5, target: id)
        record(.eggLaid(a.id, b.id))
    }

    private mutating func hatchEggs(_ h: Double) {
        guard !eggs.isEmpty else { return }
        for k in eggs.indices { eggs[k].hatchIn -= h }
        while let k = eggs.firstIndex(where: { $0.hatchIn <= 0 }) {
            let e = eggs.remove(at: k)
            let child = add(e.recipe, at: e.pos, parents: e.parents)
            if let c = index(of: child) { bichitos[c].enter(.happy, for: 2) }
            for p in bichitos.indices where bichitos[p].mood == .incubating && bichitos[p].target == e.id {
                bichitos[p].enter(.happy, for: 3)
            }
            record(.hatched(child))
        }
    }

    /// Now and then a bichito moves to the district where its friends (and its own kind) live.
    private mutating func emigrate() {
        guard districts.count > 1 else { return }
        for i in bichitos.indices where bichitos[i].mood == .wander && roll() < 0.05 {
            let b = bichitos[i]
            var score = Array(repeating: 0.0, count: districts.count)
            var count = Array(repeating: 0, count: districts.count)
            for o in bichitos where o.id != b.id {
                score[o.district] += (b.affinity[o.id] ?? 0) + (o.recipe.personality == b.recipe.personality ? 0.3 : 0)
                count[o.district] += 1
            }
            func value(_ d: Int) -> Double {
                (count[d] == 0 ? 0 : score[d] / Double(count[d])) - Double(count[d]) / Double(World.capacity) * 0.3
            }
            guard let best = districts.indices.max(by: { value($0) < value($1) }),
                  best != b.district, value(best) > value(b.district) + 0.25 else { continue }
            bichitos[i].district = best
            record(.emigrated(b.id, best))
        }
    }

    private mutating func escapeNeglected() {
        for k in bichitos.indices.reversed() where bichitos[k].isNeglected && bichitos[k].mood != .held {
            let b = bichitos.remove(at: k)
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
        events.append(e)
        tally.n += 1
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
            case let .unlocked(d):
                let place = districts[d].name(language)
                line = es ? "Se abrió un barrio nuevo: \(place)." : "A new district opened: \(place)."
            case .fought, .eggLaid: continue
            }
            if !lines.contains(line) { lines.append(line) }
        }
        return Array(lines.prefix(8))
    }
}
