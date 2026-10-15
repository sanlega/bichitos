import Foundation

/// How a bichito's state reads on screen: face, bubble, squash. Pure, so it is tested without SpriteKit.
enum Look {
    /// Squash levels cached per bichito (CONCEPT.md: 0.7...1.3). 1.0 is one of them, so standing still is the rest pose.
    static let squashLevels = [0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3]
    /// Wellbeing is cached in 4 steps: 0, 1/3, 2/3, 1.
    static let wellbeingSteps = 3

    static func squashLevel(_ squash: Double) -> Int {
        let i = Int(((squash - 0.7) / 0.1).rounded())
        return min(max(i, 0), squashLevels.count - 1)
    }

    static func wellbeing(_ needs: Bichito.Needs) -> Double {
        min(max((needs.hunger + needs.sleep + needs.affection) / 3, 0), 1)
    }

    static func wellbeingLevel(_ needs: Bichito.Needs) -> Int {
        Int((wellbeing(needs) * Double(wellbeingSteps)).rounded())
    }

    static func expression(mood: Bichito.Mood, needs: Bichito.Needs, dizzy: Double, blinking: Bool) -> Expression {
        if dizzy > 0 { return .dizzy }
        switch mood {
        case .sleep: return .asleep
        case .love: return .inLove
        case .fight: return .angry
        case .scared, .flee: return .scared
        case .happy, .chase: return .happy
        case .eat: return .hungry
        default: break
        }
        if needs.hunger < 0.3 { return .hungry }
        return blinking ? .blink : .normal
    }

    /// The face it pulls for a moment when the editor gives it a new personality.
    static func reaction(_ p: Recipe.Personality) -> Expression {
        switch p {
        case .curiosa, .hiperactiva: return .happy
        case .nerviosa: return .scared
        case .dormilona: return .asleep
        case .territorial: return .angry
        case .romantica: return .inLove
        }
    }

    /// The emoji above its head, or nil when there is nothing worth saying.
    /// `moving`: it is walking to a new home district (emigrating).
    static func bubble(mood: Bichito.Mood, needs: Bichito.Needs, dizzy: Double, moving: Bool = false) -> String? {
        if dizzy > 0.5 { return "💫" }
        switch mood {
        case .sleep: return "💤"
        case .love: return "❤️"
        case .fight: return "💢"
        case .scared: return "❗"
        case .flee: return "💦"
        case .eat: return "🍎"
        case .incubating: return "🥚"
        case .happy: return "♪"
        default: return moving && mood == .wander ? "🧳" : needs.hunger < 0.3 ? "🍎" : nil
        }
    }
}

/// Damped spring around 0 driving squash & stretch: `squash = 1 + x`.
struct Spring: Equatable {
    var x = 0.0, v = 0.0
    var stiffness = 160.0, damping = 9.0

    var squash: Double { min(max(1 + x, 0.7), 1.3) }

    mutating func step(_ dt: Double) {
        // Semi-implicit Euler is stable at frame rates.
        v += (-stiffness * x - damping * v) * dt
        x += v * dt
    }

    /// Positive stretches (taller), negative squashes (flatter).
    mutating func kick(_ dv: Double) { v += dv }
}
