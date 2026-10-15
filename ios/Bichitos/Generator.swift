import Foundation

/// Face states (DESIGN.md "Expresiones"): each one is a parametric variation of eyes and mouth.
enum Expression: String, CaseIterable, Codable {
    case normal, blink, asleep, inLove, angry, scared, hungry, happy, dizzy
}

/// `(recipe, state) → 32×32 grid of palette indices`. Pure and deterministic.
enum Generator {
    static let canvas = 32

    /// `squash` 0.7...1.3 (area-preserving), `legFrame` 0 or 1, `wellbeing` 0...1 (low = thinner).
    static func render(_ recipe: Recipe, expression: Expression = .normal, squash: Double = 1,
                       legFrame: Int = 0, wellbeing: Double = 1) -> PixelGrid {
        switch recipe.engine {
        // Only v1 exists. Future engines get their own case; old ones are never changed.
        default:
            return GeneratorV1.render(recipe: recipe, expression: expression, squash: squash,
                                      legFrame: legFrame, wellbeing: wellbeing)
        }
    }
}

/// A small drawing to stamp onto the grid: palette indices, -1 = leave the pixel as is.
private typealias Sprite = [[Int]]

private func sprite(_ rows: [String]) -> Sprite {
    rows.map { $0.map { $0.wholeNumberValue ?? -1 } }
}

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }
private func iround(_ x: Double) -> Int { Int(x.rounded()) }

fileprivate extension SeededRNG {
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
}

/// First generator. The body is a signed distance field (< 0 inside) symmetric around x = 16,
/// rasterised, outlined and shaded; traits, eyes and mouth are stamped on top.
struct GeneratorV1 {
    private static let n = Generator.canvas
    private static let bodyRegion: UInt8 = 1, legRegion: UInt8 = 2

    private let recipe: Recipe
    private let expression: Expression
    private let rx, ry, cy, amp, a1, a2, k1, k2, squash: Double
    private let bottom: Int  // first row below the body; legs fill from there to the ground
    private var region: PixelGrid
    private var grid: PixelGrid

    static func render(recipe: Recipe, expression: Expression, squash: Double, legFrame: Int, wellbeing: Double) -> PixelGrid {
        var g = GeneratorV1(recipe: recipe, expression: expression, squash: squash, wellbeing: wellbeing)
        return g.draw(legFrame: legFrame)
    }

    private init(recipe: Recipe, expression: Expression, squash: Double, wellbeing: Double) {
        self.recipe = recipe
        self.expression = expression
        let base: (w: Double, h: Double)
        switch recipe.body {
        case .gota: base = (16, 15)
        case .alubia: base = (19, 12)
        case .torre: base = (13, 17)
        case .cuadradito: base = (17, 14)
        case .pera: base = (16, 15)
        case .estrella: base = (16, 15)
        }
        var w = base.w * lerp(1.04, 0.92, recipe.height) * lerp(0.88, 1, clamp(wellbeing, 0, 1))
        var h = base.h * lerp(0.88, 1.12, recipe.height) * (recipe.personality == .dormilona ? 0.9 : 1)
        let legLength = recipe.legs == 0 ? 0 : 2 + iround(recipe.legLength * 2)
        bottom = Self.n - legLength
        var rng = SeededRNG(seed: recipe.seed)
        k1 = Double(3 + Int(rng.unit() * 4)); a1 = rng.unit() < 0.5 ? 1 : -1
        k2 = Double(5 + Int(rng.unit() * 4)); a2 = rng.unit() < 0.5 ? 1 : -1
        amp = recipe.bumps * 0.07
        // Cap the base size so the most squashed and most stretched frames still fit: squash then keeps the area.
        h = min(h, 2 * Double(bottom - 2 - Self.traitReserve(recipe.personality)) / (1 + Self.clip + amp) / 1.3)
        w = min(w, 2 * 13.5 / (1 + amp + (recipe.body == .estrella ? 0.18 : 0)) * 0.7)
        self.squash = clamp(squash, 0.7, 1.3)
        rx = w / 2 / self.squash
        ry = h / 2 * self.squash
        cy = Double(bottom) - ry * Self.clip
        region = PixelGrid(width: Self.n, height: Self.n)
        grid = PixelGrid(width: Self.n, height: Self.n)
    }

    /// The flat base cuts the shape this far below its centre, as a fraction of ry.
    private static let clip = 0.9

    private static func traitReserve(_ p: Recipe.Personality) -> Int {
        switch p {
        case .curiosa, .hiperactiva: return 6
        case .nerviosa, .territorial: return 3
        case .dormilona, .romantica: return 0
        }
    }

    /// Vertical position of the eyes, as a fraction of ry from the body centre.
    private var eyeLevel: Double {
        switch recipe.body {
        case .gota: return 0
        case .alubia, .cuadradito: return -0.1
        case .torre: return -0.25
        case .pera: return 0.1
        case .estrella: return 0.05
        }
    }

    // MARK: Silhouette

    /// Signed distance-like field of the body at canvas point (x, y); < 0 inside.
    private func field(_ x: Double, _ y: Double) -> Double {
        if y > Double(bottom) { return 1 }
        let r = recipe.roundness
        var u = abs(x - 16) / rx, v = (y - cy) / ry
        var p = 2.0
        switch recipe.body {
        case .gota: if v < 0 { u /= max(0.2, 1 + 0.5 * v * (1 - 0.5 * r)) }
        case .alubia:
            if v < 0 { v -= 0.16 * exp(-u * u * 5) }
            p = 2.2 + 1.2 * (1 - r)
        case .torre: p = 2.4 + 2 * (1 - r)
        case .cuadradito: p = 3 + 3 * (1 - r)
        case .pera:
            u /= 0.72 + 0.28 * clamp(v, -1, 1)
            p = 2 + 0.6 * (1 - r)
        case .estrella: break
        }
        if recipe.personality == .dormilona { u /= 0.9 + 0.1 * clamp(v, -1, 1) }
        let theta = atan2(u, -v)  // 0 at the top; u >= 0 keeps everything symmetric
        let d = recipe.body == .estrella
            ? hypot(u, v) / (1 + (0.12 + 0.12 * (1 - r)) * cos(5 * theta)) - 1
            : pow(pow(abs(u), p) + pow(abs(v), p), 1 / p) - 1
        return d - amp * (a1 * 0.6 * cos(k1 * theta) + a2 * 0.4 * cos(k2 * theta))
    }

    private func neighbours4(_ g: PixelGrid, _ x: Int, _ y: Int) -> [UInt8] {
        [g[x + 1, y], g[x - 1, y], g[x, y + 1], g[x, y - 1]]
    }

    private func top(_ x: Int) -> Int {
        (0..<Self.n).first { region[x, $0] == Self.bodyRegion } ?? 0
    }

    private func low(_ x: Int) -> Int? {
        (0..<Self.n).last { region[x, $0] == Self.bodyRegion }
    }

    private mutating func rasteriseBody() {
        for y in 0..<Self.n {
            for x in 0..<Self.n where field(Double(x) + 0.5, Double(y) + 0.5) < 0 { region[x, y] = Self.bodyRegion }
        }
        // Clean the silhouette: drop pixels that stick out alone, fill pinholes.
        for _ in 0..<2 {
            for y in 0..<Self.n {
                for x in 0..<Self.n {
                    let count = neighbours4(region, x, y).filter { $0 == Self.bodyRegion }.count
                    if region[x, y] == Self.bodyRegion && count <= 1 { region[x, y] = 0 }
                    else if region[x, y] == 0 && count >= 3 { region[x, y] = Self.bodyRegion }
                }
            }
        }
    }

    private mutating func addLegs(frame: Int) {
        let perSide = recipe.legs / 2
        guard perSide > 0 else { return }
        var xmin = 16
        for y in max(0, bottom - 3)..<bottom {
            for x in 0..<Self.n where region[x, y] == Self.bodyRegion { xmin = min(xmin, x) }
        }
        // Body columns on the left half near the base, measured unsquashed so legs don't jump while squashing.
        let half = max(1, min(16 - xmin, iround(Double(16 - xmin) * squash)))
        let width = [3, 2].first { perSide * $0 + perSide <= half } ?? 1
        for i in 0..<perSide {
            let inner = perSide == 1
                ? iround(lerp(1, Double(half - width), 0.55))
                : iround(1 + Double(half - width - 1) * Double(i) / Double(perSide - 1))
            for side in 0..<2 {
                let order = side == 0 ? perSide - 1 - i : perSide + i  // left to right
                let raised = frame == 1 && order % 2 == 0
                for k in 0..<width {
                    let x = side == 0 ? 15 - inner - k : 16 + inner + k
                    guard let lo = low(x) else { continue }
                    for y in stride(from: lo + 1, to: Self.n - (raised ? 1 : 0), by: 1) { region[x, y] = Self.legRegion }
                }
            }
        }
    }

    /// Border pixels become outline; the body is shaded from the field with light from the top left.
    private mutating func outlineAndShade() {
        let away = 0.7071  // unit step away from the light (down-right)
        for y in 0..<Self.n {
            for x in 0..<Self.n {
                let r = region[x, y]
                guard r != 0 else { continue }
                let around = neighbours4(region, x, y)
                if around.contains(0) || (r == Self.bodyRegion && around.contains(Self.legRegion)) { grid[x, y] = 1; continue }
                if r == Self.legRegion { grid[x, y] = 2; continue }
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                if field(px + 1.5 * away, py + 1.5 * away) >= 0 { grid[x, y] = 2 }
                else if field(px - 2 * away, py - 2 * away) >= 0 { grid[x, y] = 4 }
                else { grid[x, y] = 3 }
            }
        }
        // A lone shadow or highlight pixel is noise.
        for y in 0..<Self.n {
            for x in 0..<Self.n where grid[x, y] == 2 || grid[x, y] == 4 {
                if !neighbours4(grid, x, y).contains(grid[x, y]) { grid[x, y] = 3 }
            }
        }
    }

    // MARK: Stamping

    /// Draws `s` with its top-left at (x0, y0) and, if `mirror`, its mirror image on the right half.
    private mutating func stamp(_ s: Sprite, _ x0: Int, _ y0: Int, mirror: Bool = true) {
        for (j, row) in s.enumerated() {
            for (i, c) in row.enumerated() where c >= 0 {
                grid[x0 + i, y0 + j] = UInt8(c)
                if mirror { grid[Self.n - 1 - (x0 + i), y0 + j] = UInt8(c) }
            }
        }
    }

    /// Draws a symmetric sprite (even width) centred on the axis.
    private mutating func stampCentered(_ s: Sprite, _ y0: Int) {
        stamp(s, 16 - (s.first?.count ?? 0) / 2, y0, mirror: false)
    }

    private mutating func addTraits() {
        switch recipe.personality {
        case .curiosa:
            stampCentered(sprite([".11.", "1551", "1551", ".11.", ".11.", ".11."]), top(15) - 6)
        case .hiperactiva:
            let x = 15 - iround(rx * 0.35)
            stamp(sprite([".1.", "151", ".1.", ".1.", "..1", "..1"]), x - 2, top(x) - 6)
        case .territorial:
            let x = 15 - iround(rx * 0.45)
            stamp(sprite(["1..", "15.", "151"]), x - 1, top(x) - 3)
        case .nerviosa:
            stamp(sprite(["1", "1"]), 15, top(15) - 2)
            let x = 15 - max(2, iround(rx * 0.3))
            stamp(sprite(["1.", "1.", ".1"]), x - 1, top(x) - 3)
        case .dormilona, .romantica:
            break  // dormilona droops in the field; romantica's cheeks go with the eyes
        }
    }

    // MARK: Eyes

    private enum EyeBase { case dark, white, sleepy }

    private static func ellipse(_ w: Int, _ h: Int) -> [[Bool]] {
        (0..<h).map { j -> [Bool] in
            (0..<w).map { i -> Bool in
                let u = (Double(i) + 0.5 - Double(w) / 2) / (Double(w) / 2)
                let v = (Double(j) + 0.5 - Double(h) / 2) / (Double(h) / 2)
                return u * u + v * v <= 1.2
            }
        }
    }

    /// A solid dark eye with a glint.
    private static func dark(_ w: Int, _ h: Int) -> Sprite {
        let m = ellipse(w, h)
        var s: Sprite = m.map { $0.map { $0 ? 7 : -1 } }
        let g = w >= 4 ? 1 : 0
        if m[g][g] { s[g][g] = 6 }
        return s
    }

    /// An outlined eye socket filled with `fill`.
    private static func socket(_ w: Int, _ h: Int, fill: Int = 6) -> Sprite {
        let m = ellipse(w, h)
        func inside(_ i: Int, _ j: Int) -> Bool { i >= 0 && j >= 0 && i < w && j < h && m[j][i] }
        return (0..<h).map { j -> [Int] in
            (0..<w).map { i -> Int in
                guard m[j][i] else { return -1 }
                let edge = !inside(i + 1, j) || !inside(i - 1, j) || !inside(i, j + 1) || !inside(i, j - 1)
                return edge ? 1 : fill
            }
        }
    }

    /// Paints a pw×ph pupil roughly centred (plus offset) over the white of `s`.
    private static func pupil(_ s: Sprite, _ pw: Int, _ ph: Int, dx: Int = 0, dy: Int = 0) -> Sprite {
        var s = s
        let h = s.count, w = s.first?.count ?? 0
        let x0 = (w - pw + 1) / 2 + dx, y0 = (h - ph + 1) / 2 + dy
        for j in 0..<ph {
            for i in 0..<pw where y0 + j >= 0 && y0 + j < h && x0 + i >= 0 && x0 + i < w && s[y0 + j][x0 + i] == 6 {
                s[y0 + j][x0 + i] = 7
            }
        }
        return s
    }

    /// Copies the non-empty pixels of `top` onto `s`, centred, where `s` has one of `onto`.
    private static func overlay(_ mark: Sprite, on s: Sprite, onto: Set<Int>? = nil) -> Sprite {
        var s = s
        let yo = (s.count - mark.count) / 2, xo = ((s.first?.count ?? 0) - (mark.first?.count ?? 0)) / 2
        for (j, row) in mark.enumerated() {
            for (i, c) in row.enumerated() where c >= 0 && s.indices.contains(yo + j) && s[yo + j].indices.contains(xo + i) {
                if onto?.contains(s[yo + j][xo + i]) ?? true { s[yo + j][xo + i] = c }
            }
        }
        return s
    }

    private static func arc(_ w: Int, up: Bool) -> Sprite {
        let ends = [1] + Array(repeating: -1, count: w - 2) + [1]
        let middle = [-1] + Array(repeating: 1, count: w - 2) + [-1]
        return up ? [middle, ends] : [ends, middle]
    }

    private static func heart(_ w: Int) -> Sprite {
        if w >= 6 { return sprite(["55..55", "555555", ".5555.", "..55.."]) }
        if w >= 5 { return sprite(["55.55", "55555", ".555.", "..5.."]) }
        return sprite(["5.5", "555", ".5."])
    }

    private static let spiral = sprite(["11111", "66661", "11161", "16661", "11111"])

    /// Angry lid: clears the top of the eye along a slope that drops towards the face's centre.
    private static func angry(_ s: Sprite, center: Bool) -> Sprite {
        var s = s
        let h = s.count, w = s.first?.count ?? 0
        guard w > 1 else { return s }
        let mid = Double(w - 1) / 2
        for i in 0..<w {
            let t = center ? 1 - abs(Double(i) - mid) / mid : Double(i) / Double(w - 1)
            let cut = iround(t * Double(h / 2)) + 1
            guard let j0 = (0..<h).first(where: { s[$0][i] >= 0 }) else { continue }
            for j in j0..<min(h, j0 + cut) { s[j][i] = j < j0 + cut - 1 ? -1 : 1 }
        }
        return s
    }

    /// The left eye (or the centre one) of size w×h for the current expression.
    private func eye(_ base: EyeBase, _ w: Int, _ h: Int, center: Bool = false) -> Sprite {
        let white = base != .dark
        switch expression {
        case .blink, .asleep, .happy:
            var aw = max(3, w - (white ? 2 : 0))
            if center { aw += aw % 2 }
            let mark: Sprite = expression == .blink ? [Array(repeating: 1, count: aw)] : Self.arc(aw, up: expression == .happy)
            return white ? Self.overlay(mark, on: Self.socket(w, h, fill: 3)) : mark
        case .inLove:
            if white { return Self.overlay(Self.heart(center ? w - 2 - w % 2 : w - 2), on: Self.socket(w, h), onto: [6]) }
            return Self.heart(center ? 6 : max(3, w + 1))
        case .dizzy:
            return Self.spiral
        case .scared:
            return Self.pupil(Self.socket(w + 1 + (center ? 1 : 0), h + 1), center ? 2 : 1, 1)
        case .hungry:
            if !white { return Self.dark(w + 1, h + 1) }
            return Self.pupil(Self.socket(w + 1 + (center ? 1 : 0), h + 1), 2, 2, dy: 1)
        case .normal, .angry:
            break
        }
        var s: Sprite
        switch base {
        case .dark:
            s = Self.dark(w, h)
        case .sleepy:
            s = Self.socket(w, h)
            for j in 0..<(h / 2) {
                for i in 0..<w where s[j][i] == 6 { s[j][i] = j < h / 2 - 1 ? 3 : 1 }
            }
            s = Self.pupil(s, 2, 1, dy: 1)
        case .white:
            s = center && w >= 9 ? Self.pupil(Self.socket(w, h), 4, 3) : Self.pupil(Self.socket(w, h), 2, 2)
        }
        return expression == .angry ? Self.angry(s, center: center) : s
    }

    /// Draws the eyes (and romantica's cheeks) and returns the first row below them.
    private mutating func addEyes() -> Int {
        let size = min(2, Int(recipe.eyeSize * 3))
        let ey = cy + ry * eyeLevel
        let cheeks = recipe.personality == .romantica
        switch recipe.eyes {
        case .normales, .adormilados, .tres:
            let sizes: [(Int, Int)]
            switch recipe.eyes {
            case .normales: sizes = [(2, 3), (3, 4), (4, 5)]
            case .adormilados: sizes = [(4, 3), (5, 4), (6, 4)]
            default: sizes = [(2, 2), (2, 3), (3, 3)]
            }
            // The pixel left of the eye must still be body and the eyes must not touch.
            func fits(_ s: Double, _ w: Int, _ h: Int) -> Bool {
                let x0 = iround(16 - s - Double(w) / 2), y0 = iround(ey - Double(h) / 2)
                return x0 + w <= 15 && field(Double(x0) - 0.5, Double(y0) + 0.5) < 0
                    && field(Double(x0) - 0.5, Double(y0 + h) - 0.5) < 0
            }
            var w = sizes[0].0, h = sizes[0].1, s = 0.0
            for (sw, sh) in sizes[0...size].reversed() {
                w = sw
                h = sh
                s = rx * lerp(0.32, 0.55, recipe.eyeSpacing)
                if recipe.eyes == .tres { s = max(s, Double(w) / 2 + 2.5) }
                while s > Double(w) / 2 + 1 && !fits(s, w, h) { s -= 1 }
                if fits(s, w, h) { break }
            }
            let rows = eye(recipe.eyes == .adormilados ? .sleepy : .dark, w, h)
            let x0 = iround(16 - s - Double(rows[0].count) / 2), y0 = iround(ey - Double(rows.count) / 2)
            stamp(rows, x0, y0)
            if recipe.eyes == .tres {
                let third = eye(.dark, 2, h, center: true)
                stampCentered(third, y0 - third.count + (h < 3 ? 0 : 1) - 1)
            }
            if cheeks { stamp([[5, 5]], s > rx * 0.4 ? x0 - 1 : x0, y0 + rows.count) }
            return y0 + rows.count
        case .saltones:
            let w = [5, 6, 7][size]
            let s = max(Double(w) / 2, rx * lerp(0.25, 0.45, recipe.eyeSpacing))
            let x0 = iround(16 - s - Double(w) / 2)
            let rows = eye(.white, w, w)
            // Bulging eyes sit on top of the head, half outside the silhouette.
            let y0 = iround(Double(top(min(max(x0 + w / 2, 0), Self.n - 1)) + 1) - Double(rows.count) / 2)
            stamp(rows, x0 - (rows[0].count - w) / 2, y0)
            if cheeks { stamp([[5, 5]], x0 - 1, y0 + rows.count) }
            return y0 + rows.count
        case .ciclope:
            var w = [6, 8, 10][size]
            while w > 6 && field(16 - Double(w) / 2 - 0.5, ey) >= 0 { w -= 2 }
            let rows = eye(.white, w, w - 1, center: true)
            let y0 = iround(ey - Double(rows.count) / 2)
            stampCentered(rows, y0)
            if cheeks { stamp([[5, 5]], 16 - w / 2 - 2, y0 + rows.count - 1) }
            return y0 + rows.count
        }
    }

    private var mouth: Sprite {
        switch expression {
        case .normal, .blink: return sprite(["11"])
        case .asleep: return sprite(["11", "11"])
        case .inLove: return sprite(["1..1", ".11."])
        case .angry: return sprite([".1..1.", "1.11.1"])
        case .scared: return sprite([".11.", "1771", ".11."])
        case .hungry: return sprite(["1111", "1771", ".115", "...5"])  // drool in accent
        case .happy: return sprite(["111111", ".1771.", "..11.."])
        case .dizzy: return sprite([".11..11.", "1..11..1"])
        }
    }

    // MARK: Pipeline

    private mutating func draw(legFrame: Int) -> PixelGrid {
        rasteriseBody()
        addLegs(frame: legFrame)
        outlineAndShade()
        addTraits()
        let eyesBottom = addEyes()
        let m = mouth
        stampCentered(m, min(max(eyesBottom + 1, iround(cy + ry * 0.25)), bottom - 1 - m.count))
        removeOrphans()
        return grid
    }

    /// Any pixel without an opaque 8-neighbour is a stray and goes.
    private mutating func removeOrphans() {
        for y in 0..<Self.n {
            for x in 0..<Self.n where grid[x, y] != 0 {
                let alone = (-1...1).allSatisfy { dy in (-1...1).allSatisfy { dx in (dx == 0 && dy == 0) || grid[x + dx, y + dy] == 0 } }
                if alone { grid[x, y] = 0 }
            }
        }
    }
}
