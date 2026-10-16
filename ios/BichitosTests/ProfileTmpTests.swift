import XCTest
@testable import Bichitos

/// TEMPORARY (#92): cost of the primitives `update()` runs, in Debug.
final class ProfileTmpTests: XCTestCase {
    func testMicro() {
        var w = World(testSeed: 21, date: World.testStart)
        var g = SeededRNG(seed: 21)
        for _ in 0..<50 { w.add(Recipe.random(using: &g)) }
        let n = 200_000
        func time(_ name: String, _ body: () -> Void) {
            let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            body()
            let ns = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0) / Double(n)
            print("MICRO \(name): \(String(format: "%.0f", ns)) ns")
        }
        var sink = 0.0
        time("empty loop") { for k in 0..<n { sink += Double(k) } }
        time("terrain getter") { for _ in 0..<n { sink += w.terrain.origin.x } }
        time("drowsiness") { for _ in 0..<n { sink += w.drowsiness } }
        var rng = w.rng
        time("Double.random closed") { for _ in 0..<n { sink += Double.random(in: -1...1, using: &rng) } }
        time("Double.random 0..<1") { for _ in 0..<n { sink += Double.random(in: 0..<1, using: &rng) } }
        let ground = w.terrain
        let p = w.bichitos[0].pos
        time("walkable") { for _ in 0..<n { if ground.walkable(p) { sink += 1 } } }
        time("nearestWalkable (walkable)") { for _ in 0..<n { sink += ground.nearestWalkable(p).x } }
        let a = Vec(1, 2), b = Vec(3, 4)
        time("vec a + b * k") { for _ in 0..<n { sink += (a + b * 0.5).x } }
        time("vec unit") { for _ in 0..<n { sink += b.unit.x } }
        time("cos+sin") { for k in 0..<n { sink += cos(Double(k)) + sin(Double(k)) } }
        time("bichito copy in/out") { for k in 0..<n { var c = w.bichitos[k % 50]; c.timer -= 1; w.bichitos[k % 50] = c } }
        time("bichito field via subscript") { for k in 0..<n { w.bichitos[k % 50].timer -= 1 } }
        time("index(of:) last") { let id = w.bichitos[49].id; for _ in 0..<n { sink += Double(w.index(of: id)!) } }
        time("recipe.radius+speed+sleepiness") { let r = w.bichitos[3].recipe; for _ in 0..<n { sink += r.radius + r.speed + r.sleepiness } }
        time("bedtime") { let c = w.bichitos[3]; for _ in 0..<n { sink += c.bedtime } }
        time("district rect contains+center") { let c = w.bichitos[3]; for _ in 0..<n { let h = w.districts[c.district].rect; if h.contains(c.pos) { sink += h.center.x } } }
        time("max/min") { for k in 0..<n { sink += max(0, min(1, Double(k))) } }
        print("MICRO sink \(sink)")
    }
}
