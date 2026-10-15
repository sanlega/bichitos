import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Bichitos

/// Writes contact sheets of the generator to `GALLERY_DIR` (CI sets it) so the art can be reviewed by eye.
final class GalleryTests: XCTestCase {
    private typealias Cell = (grid: PixelGrid, palette: Palette)

    func testWriteGallery() throws {
        guard let dir = ProcessInfo.processInfo.environment["GALLERY_DIR"], !dir.isEmpty else {
            throw XCTSkip("GALLERY_DIR not set")
        }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let recipes = (UInt64(1)...100).map(GeneratorTests.recipe)
        func cell(_ r: Recipe, _ face: Face = .normal, squash: Double = 1, frame: Int = 0) -> Cell {
            (Generator.render(r, expression: face, squash: squash, legFrame: frame), Palette.of(r))
        }

        try write(recipes.map { cell($0) }, columns: 10, to: out.appendingPathComponent("gallery.png"))
        try write(recipes.prefix(6).flatMap { r in Face.allCases.map { cell(r, $0) } },
                  columns: Face.allCases.count, to: out.appendingPathComponent("expressions.png"))
        let squashes = stride(from: 0.7, through: 1.3001, by: 0.1).map { $0 }
        try write(recipes[6..<10].flatMap { r in (0...1).flatMap { f in squashes.map { cell(r, squash: $0, frame: f) } } },
                  columns: squashes.count, to: out.appendingPathComponent("squash.png"))
        var base = recipes[0]
        base.roundness = 0.5; base.height = 0.5; base.bumps = 0.3; base.eyeSize = 0.5; base.eyeSpacing = 0.5; base.legLength = 0.5
        var bodies: [Cell] = []
        for (i, body) in Recipe.Body.allCases.enumerated() {
            for (j, eyes) in Recipe.Eyes.allCases.enumerated() {
                var r = base
                r.body = body; r.eyes = eyes; r.legs = Recipe.legOptions[(i + j) % 4]
                r.personality = Recipe.Personality.allCases[(i + j) % Recipe.Personality.allCases.count]
                r.palette = (i * 5 + j) % Recipe.paletteCount
                bodies.append(cell(r))
            }
        }
        try write(bodies, columns: Recipe.Eyes.allCases.count, to: out.appendingPathComponent("bodies.png"))
        // Each palette on the same bichito; second row: low wellbeing (thinner, desaturated).
        let palettes = [1.0, 0.0].flatMap { wellbeing in
            Palette.all.indices.map { i -> Cell in
                var r = recipes[i]
                r.palette = i
                return (Generator.render(r, wellbeing: wellbeing), Palette.all[i].desaturate(1 - wellbeing))
            }
        }
        try write(palettes, columns: Palette.all.count, to: out.appendingPathComponent("palettes.png"))
    }

    /// A sheet of cells, ×`scale` nearest-neighbour on the app's light background (#F3F1EC).
    private func write(_ cells: [Cell], columns: Int, scale: Int = 8, to url: URL) throws {
        let side = Generator.canvas * scale
        let width = columns * side, height = (cells.count + columns - 1) / columns * side
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for p in stride(from: 0, to: bytes.count, by: 4) {
            bytes[p] = 0xF3; bytes[p + 1] = 0xF1; bytes[p + 2] = 0xEC; bytes[p + 3] = 0xFF
        }
        for (n, cell) in cells.enumerated() {
            let ox = n % columns * side, oy = n / columns * side
            for y in 0..<cell.grid.height {
                for x in 0..<cell.grid.width where cell.grid[x, y] != 0 {
                    let c = cell.palette.colors[Int(cell.grid[x, y])]
                    for dy in 0..<scale {
                        var p = ((oy + y * scale + dy) * width + ox + x * scale) * 4
                        for _ in 0..<scale {
                            bytes[p] = c.r; bytes[p + 1] = c.g; bytes[p + 2] = c.b
                            p += 4
                        }
                    }
                }
            }
        }
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData)), decode: nil,
            shouldInterpolate: false, intent: .defaultIntent))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), url.lastPathComponent)
    }
}
