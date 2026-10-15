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

    /// The state icon above its head, or nil when there is nothing worth saying.
    /// `moving`: it is walking to a new home district (emigrating).
    static func bubble(mood: Bichito.Mood, needs: Bichito.Needs, dizzy: Double, moving: Bool = false) -> Icon? {
        if dizzy > 0.5 { return .dizzy }
        switch mood {
        case .sleep: return .zzz
        case .love: return .heart
        case .fight: return .anger
        case .scared: return .alert
        case .flee: return .sweat
        case .eat: return .hunger
        case .incubating: return .egg
        case .happy: return .note
        default: return moving && mood == .wander ? .suitcase : needs.hunger < 0.3 ? .hunger : nil
        }
    }
}

extension Look {
    /// The state icons over the head (DESIGN.md "Los dos mundos"): pixel art, never emoji.
    /// Hand-drawn 12×12 indexed grids with a 1 px outline, resting on the bottom row.
    enum Icon: String, CaseIterable {
        case zzz, heart, anger, alert, sweat, hunger, egg, note, dizzy, suitcase

        static let canvas = 12

        /// One string per row, like `Food.Kind.art`: '.' transparent, 1 outline, 2 shadow, 3 base, 4 highlight, 6 white.
        var art: [String] {
            switch self {
            case .zzz: return [
                "......111111", "......144441", "......111311", "......113111", "......133321", "111111111111",
                "1444441.....", "1111311.....", ".11311......", "1131111.....", "1333321.....", "1111111.....",
            ]
            case .heart: return [
                "............", "............", "............", "..11111111..", ".1133113311.", ".1344333331.",
                ".1343333331.", ".1333333321.", ".1133333211.", "..11333211..", "...113211...", "....1111....",
            ]
            case .anger: return [
                "..111..111..", "..131..131..", "11141..14111", "14431..13441", "11111..11111", "............",
                "............", "11111..11111", "13321..12331", "11121..12111", "..121..121..", "..111..111..",
            ]
            case .alert: return [
                "............", "....1111....", "....1341....", "....1341....", "....1331....", "....1331....",
                "....1331....", "....1221....", "....1111....", "....1331....", "....1221....", "....1111....",
            ]
            case .sweat: return [
                "............", "............", "..111.......", "..131.......", ".11311......", "1136311111..",
                "13643311311.", "13333113631.", "13332113431.", "11321113331.", ".1111.13211.", "......1111..",
            ]
            case .hunger: return [
                "............", "..1111111...", "..1414141...", "..1413131...", "..1313131...", "..1333331...",
                "..1133211...", "...11311....", "....131.....", "....131.....", "....121.....", "....111.....",
            ]
            case .note: return [
                "....1111....", "....14411...", "....133411..", "....131331..", "....131131..", "....131111..",
                "...11311....", "..114331....", "..134331....", "..133221....", "..112211....", "...1111.....",
            ]
            case .dizzy: return [
                "............", "..111.......", ".11311......", "1134311.....", "1346331111..", "11343111311.",
                ".1131113631.", "..111111311.", "..11311111..", "..13631.....", "..11311.....", "...111......",
            ]
            case .suitcase: return [
                "............", "............", "...111111...", "...133331...", "111131131111", "144444444441",
                "133332233331", "133332233331", "133332233331", "133332233331", "122222222221", "111111111111",
            ]
            case .egg: return [
                "............", "............", "............", "....1111....", "...113311...", "..11344311..",
                "..13463331..", "..13433331..", "..13333321..", "..13333221..", "..11322211..", "...111111...",
            ]
            }
        }

        var grid: PixelGrid {
            var g = PixelGrid(width: Icon.canvas, height: Icon.canvas)
            for (y, row) in art.enumerated() {
                for (x, c) in row.enumerated() { g[x, y] = UInt8(c.wholeNumberValue ?? 0) }
            }
            return g
        }

        /// Tones from one saturated base: outline and shadow towards ink, highlight towards white.
        /// The heart is the bichito's `accent`; the name keys the texture cache, so it carries the base.
        func palette(accent: RGBA) -> Palette {
            let hex: UInt32
            switch self {
            case .heart: hex = 0
            case .zzz, .sweat: hex = 0x6DB3FF
            case .anger: hex = 0xF2405A
            case .alert: hex = 0xFF6B4A
            case .hunger: hex = 0xC8CCD8
            case .egg: hex = 0xF2E2C4
            case .note: hex = 0xAE97F2
            case .dizzy: hex = 0xFFD23F
            case .suitcase: hex = 0xC47E4A
            }
            let base = self == .heart ? accent : RGBA(hex: hex)
            let ink = RGBA(hex: Palette.pupil), white = RGBA(hex: Palette.eyeWhite)
            func mix(_ to: RGBA, _ k: Double) -> RGBA {
                func m(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) + (Double(b) - Double(a)) * k).rounded()) }
                return RGBA(r: m(base.r, to.r), g: m(base.g, to.g), b: m(base.b, to.b), a: 255)
            }
            return Palette(name: "\(rawValue) \(base.r),\(base.g),\(base.b)", colors: [
                RGBA(r: 0, g: 0, b: 0, a: 0), mix(ink, 0.7), mix(ink, 0.25), base, mix(white, 0.5), base, white, ink,
            ])
        }
    }
}

extension Look {
    /// Where the name (its top) and the bubble (its tail) sit, in points above a sprite's origin (the bottom of its
    /// canvas, the feet): a fixed gap under the pixel shadow and over the highest drawn row, at `pixel` points per pixel.
    static func anchors(_ grid: PixelGrid, pixel: Double) -> (name: Double, bubble: Double) {
        let top = (0..<grid.height).first { y in (0..<grid.width).contains { grid[$0, y] != 0 } } ?? grid.height
        return (name: -pixel - 2, bubble: Double(grid.height - top) * pixel + 3)
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
