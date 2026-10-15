import XCTest
@testable import Bichitos

final class NamesTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func full(_ language: Language, seed: UInt64) -> World {
        var w = World(seed: seed, date: start)
        w.language = language
        var rng = SeededRNG(seed: seed)
        for _ in 0..<World.maxPopulation { w.add(Recipe.random(using: &rng)) }
        return w
    }

    func testAFullWorldHasNoRepeatedNames() {
        for language in Language.allCases {
            let w = full(language, seed: 7)
            XCTAssertEqual(w.bichitos.count, 98)
            XCTAssertEqual(Set(w.bichitos.map(\.name)).count, 98, "\(language)")
            XCTAssertTrue(w.bichitos.allSatisfy { $0.description.hasPrefix($0.name + ", ") })
            XCTAssertEqual(w.bichitos.map(\.name), full(language, seed: 7).bichitos.map(\.name), "same seed, same names")
        }
        print(full(.es, seed: 7).bichitos.suffix(10).map(\.name).joined(separator: " | "))
    }

    func testEscapedNamesAreTaken() {
        var w = World(seed: 1, date: start)
        var rng = SeededRNG(seed: 1)
        let recipe = Recipe.random(using: &rng)
        w.add(recipe)
        let gone = w.bichitos.removeFirst()
        w.notes.append(Note(pos: gone.pos, text: "bye", bichito: gone))
        w.add(recipe)
        XCTAssertNotEqual(w.bichitos[0].name, gone.name)
    }

    func testSuffixOnceTheListIsExhausted() {
        let es = Names.make(seed: 5, language: .es, taken: Set(Names.namesEs))
        XCTAssertTrue(es.name.hasSuffix(" II"), es.name)
        XCTAssertTrue(Names.namesEs.contains(String(es.name.dropLast(3))))
        let joven = Names.make(seed: 5, language: .es, taken: Set(Names.namesEs + Names.namesEs.map { $0 + " II" }))
        XCTAssertTrue(joven.name.hasSuffix(" el Joven"), joven.name)
        let jr = Names.make(seed: 5, language: .en, taken: Set(Names.namesEn + Names.namesEn.map { $0 + " II" }))
        XCTAssertTrue(jr.name.hasSuffix(" Jr."), jr.name)
        let all = Set(Names.namesEs.flatMap { n in [n] + Names.suffixesEs.map { n + $0 } })
        XCTAssertFalse(all.contains(Names.make(seed: 5, language: .es, taken: all).name))
    }

    func testATypedNameIsKeptEvenIfRepeated() {
        var w = World(seed: 2, date: start)
        var rng = SeededRNG(seed: 2)
        w.add(Recipe.random(using: &rng), name: "Zorro")
        w.add(Recipe.random(using: &rng), name: "Zorro")
        XCTAssertEqual(w.bichitos.map(\.name), ["Zorro", "Zorro"])
        XCTAssertEqual(Names.make(seed: 5, language: .es, name: "Zorro", taken: ["Zorro"]).name, "Zorro")
    }
}
