import XCTest
@testable import Bichitos

final class PixelFontTests: XCTestCase {
    func testEveryNameCanBeDrawn() {
        let lists = Names.namesEs + Names.namesEn + Names.suffixesEs + Names.suffixesEn
        for text in lists { XCTAssertTrue(PixelFont.covers(text), text) }
        // Past the suffixes a plain number is added; the editor names in either language.
        XCTAssertTrue(PixelFont.covers("0123456789 áéíóúü ÁÉÍÓÚÜ ñÑ .,'-!?"))
        XCTAssertTrue(PixelFont.covers("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"))
        XCTAssertFalse(PixelFont.covers("🐛"))
    }

    func testGlyphsStayInsideTheCell() {
        let all = Array(PixelFont.glyphs.keys) + Array("áéíóúüÁÉÍÓÚÜñÑ")
        for c in all {
            let rows = PixelFont.glyphs[Character(String(c).decomposedStringWithCanonicalMapping.unicodeScalars.first!)]!
            XCTAssertTrue(rows.count == 7 || rows.count == 9, "\(c)")
            XCTAssertTrue(rows.allSatisfy { $0.count == rows[0].count && $0.allSatisfy { ".#".contains($0) } }, "\(c)")
            guard let cell = PixelFont.cell(c) else { return XCTFail("\(c)") }
            XCTAssertEqual(cell.count, PixelFont.height, "\(c)")
            XCTAssertTrue((1...PixelFont.maxWidth).contains(cell[0].count), "\(c)")
            XCTAssertTrue(cell.allSatisfy { $0.count == cell[0].count }, "\(c)")
            XCTAssertEqual(c == " ", !cell.joined().contains(true), "\(c) has ink")
        }
        // The accent sits above the letter, which keeps its rows.
        let a = PixelFont.cell("a")!, acute = PixelFont.cell("á")!
        let body = PixelFont.top + 2 // the x-height
        XCTAssertEqual(Array(acute[body...]), Array(a[body...]))
        XCTAssertTrue(acute[..<body].joined().contains(true))
    }

    func testANameHasInkAndAnOutline() {
        let g = PixelFont.grid("Ñoqui Jr.")
        XCTAssertEqual(g.height, PixelFont.height + 2)
        XCTAssertTrue(g.indices.contains(1) && g.indices.contains(2))
        XCTAssertTrue(g.indices.allSatisfy { $0 <= 2 })
        // The margin is only outline.
        for x in 0..<g.width { XCTAssertNotEqual(g[x, 0], 1); XCTAssertNotEqual(g[x, g.height - 1], 1) }
        XCTAssertEqual(PixelFont.grid("🐛").indices, PixelFont.grid("?").indices, "unknown characters draw as ?")
        for y in 0..<g.height {
            print(String((0..<g.width).map { [".", "#", "o"][Int(g[$0, y])] }))
        }
    }
}
