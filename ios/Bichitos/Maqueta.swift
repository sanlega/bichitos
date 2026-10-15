import Foundation

/// How buildings and decoration look (DESIGN.md "Edificaciones", "Cómo se dibujan"): a `Building` → rounded vector
/// shapes, deterministic from its seed, like painted wooden toys. Pure, so tests compare recipes; `Fachada` paints them.
/// Shapes are in world units (1 u = 2), from the top-left of `Building.rect`, y down; they may spill `pad` around it.
enum Maqueta {
    struct Shape: Equatable {
        enum Form: Equatable {
            case box(Rect, radius: Double)
            case oval(Rect)
            case poly([Vec], radius: Double) // every corner rounded
            case arch(Rect)                  // a door: half a circle on top
            case line([Vec], width: Double)  // round caps and joins
            case ring(Rect, width: Double)
        }
        let form: Form
        let color: RGBA
        var clip: Rect? = nil
    }

    /// Room around `rect` for shadows (4 u to the right), chimneys and flags.
    static let pad = 16.0

    /// The part of the world a building's texture covers.
    static func frame(_ b: Building) -> Rect { Rect(x: b.rect.x - pad, y: b.rect.y - pad, w: b.rect.w + 2 * pad, h: b.rect.h + 2 * pad) }

    // MARK: - Drawing order (DESIGN.md "Capas", layer 5)

    /// Where a building stands for the y-sort: its base's bottom edge. Low bowls (nest, feeder) sort by their middle,
    /// so what lies inside them (eggs, food, a bichito) is drawn over their back rim.
    static func sortY(_ b: Building) -> Double {
        switch b.kind {
        case .nido, .comedero: return b.rect.y + b.rect.h / 2
        default: return b.rect.y + b.rect.h
        }
    }

    /// The y-sort itself: lower on screen (a larger world `y` of the feet or the base) is closer, so drawn on top.
    /// `top` is the world y at the top of the screen; the result stays near 1000, under labels and bubbles (+100).
    static func depth(_ y: Double, top: Double, unit: Double) -> Double { 1000 + (y - top) * unit / 10 }

    /// A bichito sorts by its feet, a bit below the body centre the simulation tracks.
    static func feet(_ pos: Vec, radius: Double) -> Double { pos.y + radius * 0.6 }

    // MARK: - Texture cache

    /// What a building's texture shows. Its id and seed say which building; `closed` is "Ocupado" (its door shut);
    /// `lit` its windows at night (#40).
    struct Key: Hashable {
        let id: Int
        let seed: UInt64
        let closed: Bool
        let lit: Bool
        let texel: Double // texture pixels per world unit
    }

    /// A texture pixel per device pixel of a 3× screen (1 u = `scale` points, 2 world units), capped at 6 per world
    /// unit so a monument stays under 2k pixels: Cerca scales Calle's a little, which the soft world takes well.
    static func texel(_ level: Camera.Level) -> Double { min(level.scale * 1.5, 6) }

    static func key(_ b: Building, closed: Bool = false, lit: Bool = false, level: Camera.Level) -> Key {
        Key(id: b.id, seed: b.seed, closed: closed && b.kind == .casita, lit: lit, texel: texel(level))
    }

    // MARK: - Colours (DESIGN.md "Terreno", "Tres tonos")

    static let card = RGBA(hex: 0xFFFFFF), ink = RGBA(hex: 0x2B2A33), mist = RGBA(hex: 0xF3F1EC)
    static let warmLight = RGBA(hex: 0xFFD27A), water = RGBA(hex: 0xCFE2E7), waterEdge = RGBA(hex: 0xB7D1D8)
    static let foliage = RGBA(hex: 0xB9CCA9), foliageShade = RGBA(hex: 0xA1B791)
    static let bark = RGBA(hex: 0xC9B9A3), rock = RGBA(hex: 0xD7D3CB)
    static let groundShadow = alpha(ink, 0.1)

    static func mix(_ a: RGBA, _ b: RGBA, _ k: Double) -> RGBA {
        func m(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8((Double(x) * (1 - k) + Double(y) * k).rounded()) }
        return RGBA(r: m(a.r, b.r), g: m(a.g, b.g), b: m(a.b, b.b), a: a.a)
    }

    /// Lighter (`k` > 1) or darker, capped at white.
    static func shade(_ c: RGBA, _ k: Double) -> RGBA {
        func s(_ x: UInt8) -> UInt8 { UInt8(min(255, (Double(x) * k).rounded())) }
        return RGBA(r: s(c.r), g: s(c.g), b: s(c.b), a: c.a)
    }

    static func alpha(_ c: RGBA, _ a: Double) -> RGBA { RGBA(r: c.r, g: c.g, b: c.b, a: UInt8((a * 255).rounded())) }

    /// `face` = card with 15% of the district's tint; `side` = face 8% darker; `roof` = the tint at 45% over mist;
    /// `dark` = ink at 70%, for doors and windows. `light` is the seed's ±4%.
    struct Tones: Equatable {
        let face, side, base, roof, roofSide, dark, flag: RGBA
        init(theme: Int, light: Double) {
            let tint = RGBA(hex: District.themes[theme % District.themes.count].tint)
            let f = Maqueta.shade(Maqueta.mix(Maqueta.card, tint, 0.15), light)
            let s = Maqueta.shade(f, 0.92), r = Maqueta.shade(Maqueta.mix(Maqueta.mist, tint, 0.45), light)
            face = f; side = s; roof = r
            base = Maqueta.shade(s, 0.94)
            roofSide = Maqueta.shade(r, 0.92)
            dark = Maqueta.alpha(Maqueta.ink, 0.7)
            flag = Maqueta.mix(Maqueta.mist, tint, 0.75)
        }
    }

    // MARK: - Recipes

    /// The shapes of `b`, back to front.
    static func shapes(_ b: Building, closed: Bool = false, lit: Bool = false) -> [Shape] {
        var rng = SeededRNG(seed: b.seed)
        let t = Tones(theme: b.theme, light: Double.random(in: 0.96...1.04, using: &rng))
        let w = b.rect.w, h = b.rect.h
        switch b.kind {
        case .casita: return casita(t, &rng, closed: closed, lit: lit)
        case .comedero: return comedero(t, w)
        case .banco: return banco(t, w)
        case .nido: return nido(&rng, w)
        case .monument: return monument(District.themes[b.theme % District.themes.count].monument, t, w, lit: lit)
        case .tree: return tree(&rng)
        case .bush: return bush(&rng)
        case .rock: return rockShapes(&rng, w)
        case .flower: return flower(&rng, theme: b.theme)
        case .fence: return fence(b.theme, w, h)
        case .lamp: return lamp(lit: lit)
        }
    }

    private static func shadow(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Shape {
        Shape(form: .oval(Rect(x: x + 8, y: y, w: w, h: h)), color: groundShadow)
    }

    /// A box in `face` with its right quarter in `side`.
    private static func body(_ r: Rect, _ radius: Double, _ face: RGBA, _ side: RGBA) -> [Shape] {
        [Shape(form: .box(r, radius: radius), color: side),
         Shape(form: .box(r, radius: radius), color: face, clip: Rect(x: r.x - 1, y: r.y - 1, w: r.w * 0.75 + 1, h: r.h + 2))]
    }

    private static func window(_ x: Double, _ y: Double, round: Bool, _ c: RGBA) -> Shape {
        let r = Rect(x: x, y: y, w: 16, h: 16)
        return Shape(form: round ? .oval(r) : .box(r, radius: 6), color: c)
    }

    /// 48×48 u: base, body, an arched 20×26 u door, one or two windows, a roof (dome, blunt triangle or flat with eaves)
    /// and an extra (chimney, flag or antenna) behind it.
    private static func casita(_ t: Tones, _ rng: inout SeededRNG, closed: Bool, lit: Bool) -> [Shape] {
        let roofKind = Int.random(in: 0..<3, using: &rng), extra = Int.random(in: 0..<3, using: &rng)
        let doorAt = Int.random(in: 0..<3, using: &rng), round = Bool.random(using: &rng)
        let glass = lit ? warmLight : t.dark
        var s = [shadow(4, 84, 88, 12)]
        s += [Shape(form: .box(Rect(x: 2, y: 80, w: 92, h: 16), radius: 8), color: t.base)]
        s += body(Rect(x: 6, y: 24, w: 84, h: 62), 16, t.face, t.side)
        let doorX: Double
        switch doorAt {
        case 0: doorX = 28; s += [window(9, 46, round: round, glass), window(71, 46, round: round, glass)]
        case 1: doorX = 14; s += [window(64, 46, round: round, glass)]
        default: doorX = 42; s += [window(16, 46, round: round, glass)]
        }
        let door = Rect(x: doorX, y: 34, w: 40, h: 52)
        if closed {
            s += [Shape(form: .arch(door), color: shade(t.roof, 0.86)),
                  Shape(form: .oval(Rect(x: doorX + 28, y: 60, w: 8, h: 8)), color: t.dark)]
        } else {
            s += [Shape(form: .arch(door), color: t.dark)]
        }
        // The extra goes before the roof, which hides its foot.
        switch extra {
        case 0: s += [Shape(form: .box(Rect(x: 62, y: -8, w: 16, h: 32), radius: 8), color: t.side)]
        case 1: s += [Shape(form: .line([Vec(22, 24), Vec(22, -12)], width: 4), color: shade(bark, 0.8)),
                      Shape(form: .box(Rect(x: 24, y: -14, w: 24, h: 16), radius: 8), color: t.flag)]
        default: s += [Shape(form: .line([Vec(70, 24), Vec(70, -6)], width: 4), color: shade(bark, 0.8)),
                       Shape(form: .oval(Rect(x: 64, y: -14, w: 12, h: 12)), color: t.roofSide)]
        }
        let side = Rect(x: 72, y: -16, w: 40, h: 64)
        switch roofKind {
        case 0:
            let dome = Rect(x: 4, y: 0, w: 88, h: 68), top = Rect(x: -1, y: -1, w: 98, h: 35)
            s += [Shape(form: .oval(dome), color: t.roofSide, clip: top),
                  Shape(form: .oval(dome), color: t.roof, clip: Rect(x: -1, y: -1, w: 73, h: 35))]
        case 1:
            let tri = [Vec(0, 34), Vec(48, 0), Vec(96, 34)]
            s += [Shape(form: .poly(tri, radius: 10), color: t.roofSide),
                  Shape(form: .poly(tri, radius: 10), color: t.roof, clip: Rect(x: -1, y: -1, w: 73, h: 40))]
        default:
            s += [Shape(form: .box(Rect(x: 12, y: 6, w: 72, h: 20), radius: 8), color: t.roofSide),
                  Shape(form: .box(Rect(x: 0, y: 18, w: 96, h: 16), radius: 8), color: t.roof),
                  Shape(form: .box(Rect(x: 0, y: 18, w: 96, h: 16), radius: 8), color: t.roofSide, clip: side)]
        }
        return s
    }

    /// Joins pieces back to front (one call, not a chain of `+`, so the type checker stays quick).
    private static func join(_ parts: [Shape]...) -> [Shape] { parts.flatMap { $0 } }

    /// 40×24 u: a low bowl with its rim in the roof's colour.
    private static func comedero(_ t: Tones, _ w: Double) -> [Shape] {
        join([shadow(4, 36, w - 8, 12)], body(Rect(x: 6, y: 18, w: w - 12, h: 28), 12, t.face, t.side), [
            Shape(form: .box(Rect(x: 0, y: 10, w: w, h: 16), radius: 8), color: t.roof),
            Shape(form: .oval(Rect(x: 10, y: 12, w: w - 20, h: 10)), color: shade(t.roof, 0.82)),
        ])
    }

    /// 40×20 u: legs, a seat and a backrest.
    private static func banco(_ t: Tones, _ w: Double) -> [Shape] {
        join([shadow(4, 32, w - 8, 8),
              Shape(form: .box(Rect(x: 8, y: 20, w: 16, h: 20), radius: 8), color: t.base),
              Shape(form: .box(Rect(x: w - 24, y: 20, w: 16, h: 20), radius: 8), color: t.base),
              Shape(form: .box(Rect(x: 6, y: 0, w: w - 12, h: 16), radius: 8), color: t.roof)],
             body(Rect(x: 0, y: 14, w: w, h: 16), 8, t.face, t.side))
    }

    /// 32×16 u: a bowl of straw (`bark`).
    private static func nido(_ rng: inout SeededRNG, _ w: Double) -> [Shape] {
        let k = Double.random(in: -4...4, using: &rng), straw = shade(bark, 1.06)
        return [shadow(2, 22, w - 6, 10),
                Shape(form: .oval(Rect(x: 0, y: 4, w: w, h: 28)), color: bark),
                Shape(form: .oval(Rect(x: 10, y: 4, w: w - 20, h: 12)), color: shade(bark, 0.84)),
                Shape(form: .line([Vec(8, 20 + k), Vec(22, 25)], width: 4), color: straw),
                Shape(form: .line([Vec(w - 22, 25 - k), Vec(w - 8, 19)], width: 4), color: straw)]
    }

    /// Each district's landmark (DESIGN.md "Barrios"), 96–128 u wide and 64 u tall, centred.
    private static func monument(_ m: District.Monument, _ t: Tones, _ w: Double, lit: Bool) -> [Shape] {
        let c = w / 2, pole = shade(bark, 0.8), glass = lit ? warmLight : t.dark
        switch m {
        case .fountain:
            return join([shadow(4, 108, w - 16, 20)], body(Rect(x: 8, y: 76, w: w - 16, h: 44), 16, t.face, t.side), [
                Shape(form: .oval(Rect(x: 10, y: 62, w: w - 20, h: 30)), color: t.face),
                Shape(form: .oval(Rect(x: 22, y: 66, w: w - 44, h: 22)), color: water),
            ], body(Rect(x: c - 12, y: 34, w: 24, h: 44), 8, t.face, t.side), [
                Shape(form: .box(Rect(x: c - 40, y: 26, w: 80, h: 16), radius: 8), color: t.roof),
                Shape(form: .oval(Rect(x: c - 10, y: 0, w: 20, h: 30)), color: water),
                Shape(form: .oval(Rect(x: c - 38, y: 10, w: 10, h: 10)), color: waterEdge),
                Shape(form: .oval(Rect(x: c + 28, y: 10, w: 10, h: 10)), color: waterEdge),
            ])
        case .telescope:
            let a = Vec(c - 52, 66), b = Vec(c + 44, 14), d = (b - a).unit
            let n = Vec(-d.y, d.x) * 14
            let tube: [Vec] = [a + n, b + n, b - n, a - n]
            return join([shadow(c - 56, 108, 112, 20),
                         Shape(form: .line([Vec(c, 54), Vec(c - 30, 94)], width: 6), color: pole),
                         Shape(form: .line([Vec(c, 54), Vec(c + 30, 94)], width: 6), color: pole),
                         Shape(form: .line([Vec(c, 54), Vec(c, 94)], width: 6), color: shade(pole, 0.9))],
                        body(Rect(x: c - 48, y: 88, w: 96, h: 32), 8, t.face, t.side), [
                            Shape(form: .poly(tube, radius: 8), color: t.roof),
                            Shape(form: .oval(Rect(x: b.x - 12, y: b.y - 16, w: 24, h: 32)), color: t.face),
                            Shape(form: .oval(Rect(x: b.x - 6, y: b.y - 8, w: 12, h: 16)), color: t.dark),
                        ])
        case .flagTower:
            return join([shadow(8, 108, w - 16, 20)], body(Rect(x: 0, y: 84, w: w, h: 36), 8, t.face, t.side),
                        body(Rect(x: c - 30, y: 24, w: 60, h: 96), 12, t.face, t.side), [
                            Shape(form: .oval(Rect(x: c - 8, y: 42, w: 16, h: 16)), color: glass),
                            Shape(form: .arch(Rect(x: c - 20, y: 68, w: 40, h: 52)), color: t.dark),
                            Shape(form: .line([Vec(c, 12), Vec(c, -14)], width: 4), color: pole),
                            Shape(form: .box(Rect(x: c + 2, y: -16, w: 28, h: 16), radius: 8), color: t.flag),
                            Shape(form: .poly([Vec(c - 38, 30), Vec(c, 2), Vec(c + 38, 30)], radius: 8), color: t.roof),
                        ])
        case .giantHammock:
            let sag: [Vec] = (0...8).map { k in
                let f = Double(k) / 8
                return Vec(36 + f * (w - 72), 44 + 144 * f * (1 - f))
            }
            return join([shadow(12, 110, w - 24, 18)], body(Rect(x: 8, y: 10, w: 20, h: 112), 8, bark, shade(bark, 0.92)),
                        body(Rect(x: w - 28, y: 10, w: 20, h: 112), 8, bark, shade(bark, 0.92)), [
                            Shape(form: .line([Vec(18, 24), Vec(38, 44)], width: 4), color: pole),
                            Shape(form: .line([Vec(w - 18, 24), Vec(w - 38, 44)], width: 4), color: pole),
                            Shape(form: .line(sag, width: 20), color: t.roof),
                            Shape(form: .oval(Rect(x: 44, y: 48, w: 40, h: 22)), color: t.face),
                        ])
        case .hamsterWheel:
            let hub = Vec(c, 60)
            let spokes: [Shape] = (0..<3).map { k in
                let a = Double(k) * Double.pi / 3
                let r = Vec(cos(a), sin(a)) * 48
                return Shape(form: .line([hub - r, hub + r], width: 4), color: t.roofSide)
            }
            return join([shadow(c - 60, 108, 120, 18),
                         Shape(form: .poly([Vec(c - 44, 116), Vec(c, 56), Vec(c + 44, 116)], radius: 8), color: t.side)],
                        spokes, [
                            Shape(form: .ring(Rect(x: c - 54, y: 6, w: 108, h: 108), width: 12), color: t.roof),
                            Shape(form: .oval(Rect(x: c - 10, y: 50, w: 20, h: 20)), color: t.face),
                        ], body(Rect(x: c - 60, y: 106, w: 120, h: 16), 8, t.face, t.side))
        case .hideoutBox:
            return join([shadow(20, 108, w - 40, 20),
                         Shape(form: .poly([Vec(24, 40), Vec(6, 14), Vec(c - 4, 20), Vec(c - 4, 40)], radius: 8), color: t.roof),
                         Shape(form: .poly([Vec(c + 4, 40), Vec(c + 4, 20), Vec(w - 6, 14), Vec(w - 24, 40)], radius: 8), color: t.roofSide)],
                        body(Rect(x: 20, y: 34, w: w - 40, h: 88), 8, t.face, t.side),
                        [Shape(form: .arch(Rect(x: c - 22, y: 66, w: 44, h: 56)), color: t.dark)])
        case .gazebo:
            let cols: [Shape] = (0..<4).flatMap { k in
                body(Rect(x: 12 + Double(k) * (w - 40) / 3, y: 36, w: 16, h: 68), 8, t.face, t.side)
            }
            return join([shadow(4, 108, w - 16, 20)], body(Rect(x: 0, y: 100, w: w, h: 22), 8, t.face, t.side),
                        [Shape(form: .box(Rect(x: c - 36, y: 78, w: 72, h: 16), radius: 8), color: bark)], cols, [
                            Shape(form: .oval(Rect(x: 4, y: 0, w: w - 8, h: 84)), color: t.roof, clip: Rect(x: -1, y: -1, w: w + 2, h: 41)),
                            Shape(form: .box(Rect(x: -4, y: 30, w: w + 8, h: 16), radius: 8), color: t.roofSide),
                            Shape(form: .oval(Rect(x: c - 8, y: -12, w: 16, h: 16)), color: t.roof),
                        ])
        }
    }

    /// Blobs of leaves over their shade, which falls to the lower right.
    private static func leaves(_ blobs: [Rect], _ dx: Double, _ dy: Double) -> [Shape] {
        let under: [Shape] = blobs.map { Shape(form: .oval(Rect(x: $0.x + dx, y: $0.y + dy, w: $0.w, h: $0.h)), color: foliageShade) }
        let over: [Shape] = blobs.map { Shape(form: .oval($0), color: foliage) }
        return under + over
    }

    /// 40×56 u: a trunk under three blobs of leaves.
    private static func tree(_ rng: inout SeededRNG) -> [Shape] {
        var j: [Double] = []
        for _ in 0..<5 { j.append(Double.random(in: -5...5, using: &rng)) }
        let crown = [Rect(x: 2 + j[0], y: 18 + j[1], w: 50, h: 50), Rect(x: 28 + j[2], y: 14 + j[3], w: 50, h: 50),
                     Rect(x: 12, y: j[4], w: 56, h: 54)]
        return join([shadow(8, 98, 64, 14)], body(Rect(x: 32, y: 56, w: 16, h: 52), 8, bark, shade(bark, 0.92)), leaves(crown, 4, 6))
    }

    /// 24×16 u: three blobs of leaves.
    private static func bush(_ rng: inout SeededRNG) -> [Shape] {
        var j: [Double] = []
        for _ in 0..<3 { j.append(Double.random(in: -3...3, using: &rng)) }
        let blobs = [Rect(x: 0, y: 8 + j[0], w: 28, h: 22), Rect(x: 18, y: 6 + j[1], w: 28, h: 24), Rect(x: 8 + j[2], y: 0, w: 28, h: 22)]
        return join([shadow(2, 24, 44, 8)], leaves(blobs, 3, 4))
    }

    /// 16–32 u: a rounded lump of `rock`.
    private static func rockShapes(_ rng: inout SeededRNG, _ s: Double) -> [Shape] {
        let top = s * Double.random(in: 0.2...0.4, using: &rng)
        return join([shadow(0, s * 0.7, s - 4, s * 0.3)], body(Rect(x: 0, y: top, w: s, h: s - top), s * 0.3, rock, shade(rock, 0.92)))
    }

    /// 8×12 u: a stem and a muted blossom, the district's tint or a pastel next to it.
    private static func flower(_ rng: inout SeededRNG, theme: Int) -> [Shape] {
        let hues: [UInt32] = [District.themes[theme % District.themes.count].tint, 0xE89BB0, 0xE6C55A, 0xA99BD6, 0xFFFFFF]
        let petals = mix(mist, RGBA(hex: hues.randomElement(using: &rng)!), 0.6)
        return [Shape(form: .line([Vec(8, 22), Vec(8, 10)], width: 4), color: foliageShade),
                Shape(form: .oval(Rect(x: 8, y: 14, w: 8, h: 6)), color: foliage),
                Shape(form: .oval(Rect(x: 0, y: 0, w: 16, h: 14)), color: petals),
                Shape(form: .oval(Rect(x: 5, y: 4, w: 6, h: 6)), color: mix(mist, warmLight, 0.8))]
    }

    /// A low wall on its 8 u strip: stone in Las Esquinas, painted wood elsewhere.
    private static func fence(_ theme: Int, _ w: Double, _ h: Double) -> [Shape] {
        let c = District.themes[theme % District.themes.count].terrain == .rockWalls ? rock : bark
        return body(Rect(x: 0, y: -8, w: w, h: h + 8), 8, c, shade(c, 0.9))
    }

    /// 8×40 u: a pole on a foot, with its lamp on top.
    private static func lamp(lit: Bool) -> [Shape] {
        let pole = shade(rock, 0.86)
        return [shadow(0, 72, 16, 8),
                Shape(form: .line([Vec(8, 74), Vec(8, 12)], width: 6), color: pole),
                Shape(form: .box(Rect(x: 0, y: 66, w: 16, h: 16), radius: 8), color: pole),
                Shape(form: .oval(Rect(x: 0, y: 0, w: 16, h: 16)), color: lit ? warmLight : card)]
    }
}

extension World {
    /// Casita id → who sleeps inside it: its owners asleep at its door. They are drawn as its shut door and their icon.
    var asleepInside: [Int: [Int]] {
        var inside: [Int: [Int]] = [:]
        let all = terrain.buildings
        for b in bichitos where b.mood == .sleep {
            guard let h = b.home, all.indices.contains(h), let door = all[h].door, (b.pos - door).length < 24 else { continue }
            inside[h, default: []].append(b.id)
        }
        return inside
    }
}
