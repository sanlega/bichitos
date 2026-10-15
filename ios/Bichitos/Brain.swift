import Foundation

/// One creature. Its look and voice come from `recipe`; everything else is what it lives through.
struct Bichito: Codable, Equatable, Identifiable {
    enum Mood: String, Codable {
        case wander, sleep, eat, love, fight, chase, flee, imitate, scared, happy, held, incubating
        case toBed // walking to its casita (or a tree) to sleep there; `target` is that building's id
        /// Moods an encounter or food can pull a bichito out of.
        var isFree: Bool { self == .wander || self == .happy }
    }

    /// 1 = satisfied, 0 = desperate. They go down with the clock.
    struct Needs: Codable, Equatable { var hunger = 1.0, sleep = 1.0, affection = 1.0 }

    let id: Int
    var recipe: Recipe
    var name: String
    var description: String
    var born: Date
    var parents: [Int] = []
    var pos: Vec
    var vel = Vec.zero
    var heading = 0.0
    var mood = Mood.wander
    var timer = 0.0           // seconds left in the current mood
    var target: Int?          // the bichito, food or egg the mood is about
    var threat: Vec?          // what a scared or fleeing bichito runs from
    var needs = Needs()
    var affinity: [Int: Double] = [:] // other id → −1…1
    var district = 0          // home district index
    var home: Int?            // its casita's `Building.id` (Edificios.swift); nil: none had room, it sleeps under a tree
    var dizzy = 0.0           // seconds tumbling after a throw or a bonk: momentum only, no steering
    var calm = 0.0            // seconds until it can have another encounter
    var breedCooldown = 0.0
    var bench: Int?           // in love: the banco (`Building.id`) the pair goes to sit on; any other mood clears it

    var isNeglected: Bool { needs.hunger <= 0.02 && needs.affection <= 0.1 }

    mutating func enter(_ mood: Mood, for time: Double, target: Int? = nil, threat: Vec? = nil) {
        self.mood = mood
        timer = time
        self.target = target
        self.threat = threat
        bench = nil
    }
}

/// Behaviour traits derived from the recipe.
extension Recipe {
    /// Points per second at full pace.
    var speed: Double {
        let base: Double
        switch personality {
        case .hiperactiva: base = 75
        case .nerviosa: base = 55
        case .curiosa, .territorial: base = 45
        case .romantica: base = 40
        case .dormilona: base = 25
        }
        return base * (0.8 + 0.4 * legLength) * (legs == 0 ? 0.8 : 1)
    }

    /// How fast the wandering heading wobbles (rad/s).
    var turn: Double {
        switch personality {
        case .hiperactiva: return 3
        case .nerviosa: return 2.5
        case .dormilona: return 0.6
        default: return 1.2
        }
    }

    var sleepiness: Double {
        switch personality {
        case .dormilona: return 2.5
        case .hiperactiva: return 0.5
        default: return 1
        }
    }

    var radius: Double { 14 + 6 * height }
}
