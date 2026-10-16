import Foundation

/// The time of day by the local clock (DESIGN.md, "Ambiente"): day 8–19, dusk 19–21, night 21–6, dawn 6–8.
enum DayPhase: String {
    case dawn, day, dusk, night

    init(hour h: Double) {
        switch h {
        case 6..<8: self = .dawn
        case 8..<19: self = .day
        case 19..<21: self = .dusk
        default: self = .night
        }
    }

    /// How much the hour pulls bichitos to bed: 0 by day, 1 at night, rising across dusk and falling across dawn.
    static func drowsiness(hour h: Double) -> Double {
        switch DayPhase(hour: h) {
        case .day: return 0
        case .dusk: return (h - 19) / 2
        case .night: return 1
        case .dawn: return 1 - (h - 6) / 2
        }
    }
}

extension Bichito {
    /// The drowsiness at which it heads to bed (and below which it wakes), its own from the recipe, so they go one by one
    /// through dusk and wake one by one through dawn; dormilonas first to bed and last up.
    var bedtime: Double { min(0.95, Double(recipe.seed % 1000) / 1000 / recipe.sleepiness) }
}

extension World {
    /// The local hour (0..<24) of the simulated date in `timeZone`: the catch-up sees the real hour of every moment.
    var hour: Double {
        let t = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        let h = t.truncatingRemainder(dividingBy: 86400) / 3600
        return h < 0 ? h + 24 : h
    }

    var phase: DayPhase { DayPhase(hour: hour) }
    var drowsiness: Double { DayPhase.drowsiness(hour: hour) }

    /// Whether casita `id`'s window glows: from dusk to dawn, while one of its owners is home (at its door, awake or
    /// asleep). Empty casitas, and owners still out, leave it dark.
    func windowLit(_ id: Int) -> Bool {
        guard phase != .day, let door = building(id)?.door else { return false }
        return bichitos.contains { $0.home == id && ($0.pos - door).length < 48 }
    }
}
