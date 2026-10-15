import XCTest
@testable import Bichitos

final class LabelsTests: XCTestCase {
    private func assertApart(_ rects: [CGRect], file: StaticString = #filePath, line: UInt = #line) {
        let shown = rects.filter { !$0.isNull }
        for i in shown.indices { for j in shown.indices where j > i {
            XCTAssertFalse(LabelLayout.touch(shown[i], shown[j]), "\(shown[i]) touches \(shown[j])", file: file, line: line)
        } }
    }

    func testClearNamesStayPut() {
        var layout = LabelLayout(), shown: [Bool] = []
        let start = [CGRect(x: 0, y: 0, width: 40, height: 14), CGRect(x: 60, y: 0, width: 40, height: 14)]
        var names = start
        layout.place(names: &names, bubbles: [], shown: &shown)
        XCTAssertEqual(names, start)
    }

    func testTouchingNamesSeparateNearTheirBichito() {
        var layout = LabelLayout(), shown: [Bool] = []
        let start = [CGRect(x: 0, y: 0, width: 50, height: 14), CGRect(x: 20, y: 0, width: 50, height: 14)]
        var names = start
        layout.place(names: &names, bubbles: [], shown: &shown)
        XCTAssertEqual(names[0], start[0], "the first keeps its place")
        XCTAssertFalse(names[1].isNull)
        assertApart(names)
        XCTAssertLessThanOrEqual(abs(names[1].midX - start[1].midX), 50 * 0.75 + 8)
        XCTAssertLessThanOrEqual(names[1].minY, start[1].minY, "never up into its own sprite")
    }

    func testSameSpotStaggersOneLower() {
        var layout = LabelLayout(), shown: [Bool] = []
        let r = CGRect(x: 0, y: 100, width: 60, height: 14)
        var names = [r, r]
        layout.place(names: &names, bubbles: [], shown: &shown)
        assertApart(names)
        XCTAssertEqual(names[1].midX, r.midX, "a row lower beats a long nudge")
        XCTAssertEqual(names[1].maxY, r.minY - LabelLayout.gap)
    }

    func testOnlyOneOfTwoTouchingBubblesShows() {
        var layout = LabelLayout(), shown: [Bool] = [], names: [CGRect] = []
        let a = CGRect(x: 0, y: 50, width: 80, height: 30), b = a.offsetBy(dx: 40, dy: 10), c = a.offsetBy(dx: 200, dy: 0)
        layout.place(names: &names, bubbles: [a, b, c], shown: &shown)
        XCTAssertEqual(shown, [true, false, true])
    }

    func testBubbleWaitsForAName() {
        var layout = LabelLayout(), shown: [Bool] = []
        let name = CGRect(x: 10, y: 10, width: 40, height: 14)
        var names = [name]
        layout.place(names: &names, bubbles: [CGRect(x: 0, y: 20, width: 80, height: 30), CGRect(x: 0, y: 40, width: 80, height: 30)], shown: &shown)
        XCTAssertEqual(names, [name], "the name stays")
        XCTAssertEqual(shown, [false, true])
    }

    /// 40 bichitos packed in a corner: no two names touch, each stays near its own, and it is quick.
    func testCrowdOfForty() {
        var g = SeededRNG(seed: 77)
        func r(_ n: Double) -> CGFloat { CGFloat(Double(g.next() >> 11) / Double(1 << 53) * n) }
        let start = (0..<40).map { _ in CGRect(x: r(300), y: r(400), width: 30 + r(40), height: 14) }
        var layout = LabelLayout(), shown: [Bool] = [], names = start
        layout.place(names: &names, bubbles: [], shown: &shown)
        assertApart(names)
        for (a, b) in zip(start, names) where !b.isNull {
            XCTAssertLessThanOrEqual(abs(a.midX - b.midX), a.width * 0.75 + 8)
            XCTAssertLessThanOrEqual(a.minY - b.minY, 2 * (a.height + LabelLayout.gap) + 0.5)
        }
        XCTAssertGreaterThan(names.filter { !$0.isNull }.count, 30, "most still show")
        measure {
            for _ in 0..<60 { names = start; layout.place(names: &names, bubbles: [], shown: &shown) } // a second of frames
        }
    }
}
