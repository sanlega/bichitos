import CoreGraphics
import SpriteKit

/// Everything that changes a bichito's pixels, quantised so the cache stays small.
struct SpriteKey: Hashable {
    var recipe: Recipe
    var squash: Int     // index into Look.squashLevels
    var expression: Expression
    var legFrame: Int   // 0 or 1
    var wellbeing: Int  // 0...Look.wellbeingSteps
}

/// Generator grids → `SKTexture` with `.nearest`, cached by `SpriteKey`.
/// The texture is one row taller than the canvas: the bottom row is the pixel shadow under the feet.
final class Sprites {
    static let shared = Sprites()
    static let width = Generator.canvas, height = Generator.canvas + 1

    private var cache: [SpriteKey: SKTexture] = [:]
    private var images: [SpriteKey: CGImage] = [:]
    var count: Int { cache.count }

    func texture(_ key: SpriteKey) -> SKTexture {
        if let t = cache[key] { return t }
        let t = SKTexture(cgImage: Self.image(key))
        t.filteringMode = .nearest
        cache[key] = t
        return t
    }

    /// The same pixels as a `CGImage`, for SwiftUI.
    func cgImage(_ key: SpriteKey) -> CGImage {
        if let i = images[key] { return i }
        let i = Self.image(key)
        images[key] = i
        return i
    }

    private var foods: [Food.Kind: SKTexture] = [:]

    func texture(_ kind: Food.Kind) -> SKTexture {
        if let t = foods[kind] { return t }
        let t = SKTexture(cgImage: Self.image(kind.grid, kind.palette))
        t.filteringMode = .nearest
        foods[kind] = t
        return t
    }

    func removeAll() {
        cache.removeAll()
        images.removeAll()
    }

    static func image(_ key: SpriteKey) -> CGImage {
        let wellbeing = Double(key.wellbeing) / Double(Look.wellbeingSteps)
        let grid = Generator.render(key.recipe, expression: key.expression, squash: Look.squashLevels[key.squash],
                                    legFrame: key.legFrame, wellbeing: wellbeing)
        return image(grid, Palette.of(key.recipe).desaturate(1 - wellbeing))
    }

    static func image(_ grid: PixelGrid, _ palette: Palette) -> CGImage {
        let w = grid.width, h = grid.height + 1
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<grid.height {
            for x in 0..<grid.width where grid[x, y] != 0 {
                let c = palette.colors[Int(grid[x, y])]
                let p = (y * w + x) * 4
                bytes[p] = c.r; bytes[p + 1] = c.g; bytes[p + 2] = c.b; bytes[p + 3] = c.a
            }
        }
        // Shadow: ink at 14% under the lowest row, one pixel wider on each side.
        let ground = (0..<grid.height).last { y in (0..<grid.width).contains { grid[$0, y] != 0 } } ?? grid.height - 1
        let feet = (0..<grid.width).filter { grid[$0, ground] != 0 }
        if let lo = feet.min(), let hi = feet.max() {
            let a = 0.14
            for x in max(0, lo - 1)...min(w - 1, hi + 1) {
                let p = (grid.height * w + x) * 4
                bytes[p] = UInt8(0x2B * a); bytes[p + 1] = UInt8(0x2A * a); bytes[p + 2] = UInt8(0x33 * a); bytes[p + 3] = UInt8(255 * a)
            }
        }
        // Premultiplied: the palette is opaque, so only the shadow needed premultiplying above.
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }
}
