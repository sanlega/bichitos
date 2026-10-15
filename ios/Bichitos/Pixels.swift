import Foundation

/// A grid of palette indices, row-major with y growing downwards. 0 is transparent.
struct PixelGrid: Hashable {
    let width: Int
    let height: Int
    var indices: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        indices = Array(repeating: 0, count: width * height)
    }

    func contains(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height }

    /// Reads outside the grid give 0 and writes outside are ignored, so drawing code needs no bounds checks.
    subscript(x: Int, y: Int) -> UInt8 {
        get { contains(x, y) ? indices[y * width + x] : 0 }
        set { if contains(x, y) { indices[y * width + x] = newValue } }
    }
}

struct RGBA: Hashable {
    var r, g, b, a: UInt8
}

extension RGBA {
    init(hex: UInt32) {
        self.init(r: UInt8(hex >> 16 & 0xFF), g: UInt8(hex >> 8 & 0xFF), b: UInt8(hex & 0xFF), a: 255)
    }
}

/// Colours for the indices of a `PixelGrid` (DESIGN.md "Paletas indexadas").
struct Palette: Hashable {
    let name: String
    /// 0 transparent, 1 outline, 2 shadow, 3 base, 4 highlight, 5 accent, 6 eye white, 7 pupil.
    let colors: [RGBA]

    static let eyeWhite: UInt32 = 0xFFFFFF
    static let pupil: UInt32 = 0x2B2A33

    /// `tones`: outline, shadow, base, highlight, accent.
    init(_ name: String, _ tones: [UInt32]) {
        self.init(name: name, colors: [RGBA(r: 0, g: 0, b: 0, a: 0)] + (tones + [Palette.eyeWhite, Palette.pupil]).map(RGBA.init(hex:)))
    }

    init(name: String, colors: [RGBA]) {
        self.name = name
        self.colors = colors
    }

    /// Mixes every colour towards its grey; `amount` 0...1 maps to 0...40% (low needs).
    func desaturate(_ amount: Double) -> Palette {
        let t = min(max(amount, 0), 1) * 0.4
        return Palette(name: name, colors: colors.map { c in
            let grey = 0.299 * Double(c.r) + 0.587 * Double(c.g) + 0.114 * Double(c.b)
            func mix(_ v: UInt8) -> UInt8 { UInt8((Double(v) + (grey - Double(v)) * t).rounded()) }
            return RGBA(r: mix(c.r), g: mix(c.g), b: mix(c.b), a: c.a)
        })
    }

    static let all: [Palette] = [
        Palette("fresa", [0x6B1E2E, 0xC93B54, 0xF2607A, 0xFFA3B1, 0x7ED957]),
        Palette("mandarina", [0x6E2E12, 0xD9692A, 0xFF9845, 0xFFC48A, 0x3FA34D]),
        Palette("limón", [0x6B5A10, 0xD4B12A, 0xF9DC4A, 0xFFF3A3, 0xFF7A59]),
        Palette("menta", [0x1E5C4C, 0x3DB394, 0x6EE0BE, 0xBFF7E6, 0xFF6F91]),
        Palette("aguacate", [0x2E4A14, 0x6E9E2E, 0x9CCB4A, 0xD3EE8E, 0x8B5A2B]),
        Palette("cielo", [0x1C3F73, 0x3F86D9, 0x6DB3FF, 0xBEE0FF, 0xFFD23F]),
        Palette("lavanda", [0x3E2A6E, 0x8169C9, 0xAE97F2, 0xDCD0FF, 0xFFB347]),
        Palette("chicle", [0x6E1F5C, 0xD45AB4, 0xFF8AD8, 0xFFC9EE, 0x4DD6E0]),
        Palette("cacao", [0x3B2216, 0x7A4A30, 0xA66D4C, 0xD49B76, 0xF2C14E]),
        Palette("pizarra", [0x23283A, 0x4F5A73, 0x7A869E, 0xB3BCD0, 0xFF6B4A]),
        Palette("coral", [0x6B2420, 0xD9534A, 0xFF7F6E, 0xFFB9A8, 0x3FBFB0]),
        Palette("lima", [0x3A5212, 0x86B82A, 0xB8E04A, 0xE6F7A0, 0x9B59D0]),
    ]

    static func of(_ recipe: Recipe) -> Palette { all[(recipe.palette % all.count + all.count) % all.count] }
}
