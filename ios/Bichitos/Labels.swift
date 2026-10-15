import Foundation

/// Keeps the names and phrase bubbles over the bichitos from touching (DESIGN.md "Capas", #77).
/// Pure: rects in, rects out, in scene points (y up). State icons are left alone: they may cluster.
/// Holds its scratch buffers so a frame with 40 bichitos on screen allocates nothing once warmed up.
struct LabelLayout {
    /// Minimum clear space between two labels, in points.
    static let gap: CGFloat = 6 // 2 pt still read as one word on screen
    /// Most spots tried for one name before it hides.
    private static let tries = 12

    private var kept: [CGRect] = []
    private var queue: [CGRect] = []

    /// Names first: each keeps its place if it is clear, or moves to the nearest clear spot, nudged left or right
    /// past what it touches or one or two rows lower; one with no clear spot near its bichito becomes `.null` (hidden).
    /// Then `bubbles`, most important first: one that would touch a name or a bubble already kept waits (`shown` false).
    /// Names go first because they stay, while a phrase can wait a moment.
    /// `obstacles` (#79) are the interface floating over the map: nothing is placed touching them.
    mutating func place(names: inout [CGRect], bubbles: [CGRect], shown: inout [Bool], obstacles: [CGRect] = []) {
        kept.removeAll(keepingCapacity: true)
        kept.append(contentsOf: obstacles)
        shown.removeAll(keepingCapacity: true)
        for i in names.indices {
            names[i] = spot(for: names[i])
            if !names[i].isNull { kept.append(names[i]) }
        }
        for b in bubbles {
            let free = clear(b)
            shown.append(free)
            if free { kept.append(b) }
        }
    }

    private func clear(_ r: CGRect) -> Bool { !kept.contains { LabelLayout.touch(r, $0) } }

    static func touch(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX + gap && b.minX < a.maxX + gap && a.minY < b.maxY + gap && b.minY < a.maxY + gap
    }

    /// Breadth-first over the spots next to whatever the name touches, keeping the closest clear one.
    private mutating func spot(for r: CGRect) -> CGRect {
        if clear(r) { return r }
        let gap = LabelLayout.gap
        let maxShift = r.width * 0.75 + 8, maxDrop = 2 * (r.height + gap) + 0.5
        var best = CGRect.null, bestD = CGFloat.infinity
        queue.removeAll(keepingCapacity: true)
        queue.append(r)
        var k = 0
        while k < queue.count, k < LabelLayout.tries {
            let t = queue[k]
            k += 1
            guard let hit = kept.first(where: { LabelLayout.touch(t, $0) }) else { continue }
            for c in [t.offsetBy(dx: hit.minX - gap - t.maxX, dy: 0), // left of it
                      t.offsetBy(dx: hit.maxX + gap - t.minX, dy: 0), // right of it
                      t.offsetBy(dx: 0, dy: hit.minY - gap - t.maxY)] { // under it
                let dx = c.midX - r.midX, dy = r.minY - c.minY
                guard abs(dx) <= maxShift, dy >= 0, dy <= maxDrop else { continue }
                let d = dx * dx + dy * dy
                guard d < bestD else { continue }
                if clear(c) { best = c; bestD = d } else { queue.append(c) }
            }
        }
        return best
    }
}
