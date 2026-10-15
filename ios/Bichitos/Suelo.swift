import SpriteKit
import UIKit

/// The soft world's ground (DESIGN.md "Terreno"): each district's terrain, its tint and the paths through it,
/// painted once per district and zoom level into a texture. Vector, antialiased, no outlines, no corners.
enum Ground {
    /// What a texture shows. `open` (the open districts' themes, sorted) decides which paths are painted.
    struct Key: Hashable {
        let seed: UInt64
        let district: Int // theme index
        let open: [Int]
        let texel: Double // texture pixels per world unit
    }

    /// One texture pixel per screen point at Barrio, capped at 2 per world unit (4 per u) so a district stays under
    /// 2k pixels: Calle and Cerca share it, and the soft world is low contrast enough to scale up smoothly.
    static func texel(_ level: Camera.Level) -> Double { min(level.scale / 2, 2) }

    /// Half the mist to each neighbour, plus 2 overlapping it so the paths show no seam where two textures meet.
    static let margin = World.districtGap / 2 + 2

    /// The part of the world a district's texture covers.
    static func frame(_ r: Rect) -> Rect { Rect(x: r.x - margin, y: r.y - margin, w: r.w + 2 * margin, h: r.h + 2 * margin) }

    static let card = UIColor.white

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func color(_ c: Terrain.Cell) -> UIColor {
        switch c {
        case .mist: color(0xF3F1EC)
        case .meadow: color(0xDDE6D0)
        case .sand: color(0xEEE4CE)
        case .rock: color(0xD7D3CB)
        case .water: color(0xCFE2E7)
        case .path: color(0xE7E3DA) // ground
        }
    }

    static let waterEdge = color(0xB7D1D8)
    static let groundShadow = Ink.ink.withAlphaComponent(0.1)

    /// Ground (rounded 16 u), its patches, its rock (with a shadow 4 u to the right) or water (with a 2 u
    /// `waterEdge` rim inside), the district tint at 8% over all of it, then the paths of 24 u with round ends.
    static func paint(_ key: Key, _ t: Terrain) -> SKTexture {
        let rect = World.layout(seed: key.seed)[key.district], f = frame(rect), s = CGFloat(key.texel)
        let look = Terrain.look(District.themes[key.district].terrain)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: (CGFloat(f.w) * s).rounded(.up), height: (CGFloat(f.h) * s).rounded(.up))
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let g = ctx.cgContext
            g.scaleBy(x: s, y: s)
            g.translateBy(x: -CGFloat(f.x), y: -CGFloat(f.y))
            let box = CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
            let land = CGPath(roundedRect: box, cornerWidth: 32, cornerHeight: 32, transform: nil)
            func fill(_ p: CGPath, _ c: UIColor) {
                g.addPath(p)
                g.setFillColor(c.cgColor)
                g.fillPath(using: .evenOdd)
            }
            fill(land, color(look.base))
            g.saveGState()
            g.addPath(land)
            g.clip()
            fill(path(t.outlines(look.other, in: rect, under: [.rock, .water])), color(look.other))
            if let o = look.obstacle {
                let blobs = path(t.outlines(o, in: rect))
                if o == .water {
                    fill(blobs, color(.water))
                    g.saveGState()
                    g.addPath(blobs)
                    g.clip(using: .evenOdd)
                    g.addPath(blobs)
                    g.setLineWidth(8) // half of it inside: 2 u
                    g.setStrokeColor(waterEdge.cgColor)
                    g.strokePath()
                    g.restoreGState()
                } else {
                    g.saveGState()
                    g.translateBy(x: 8, y: 4)
                    fill(blobs, groundShadow)
                    g.restoreGState()
                    fill(blobs, color(o))
                }
            }
            g.setFillColor(color(District.themes[key.district].tint, 0.08).cgColor)
            g.fill(box)
            g.restoreGState()
            let roads = CGMutablePath(), plaza = World.layout(seed: key.seed)[0], r = Terrain.pathWidth / 2
            for (k, p) in t.paths.enumerated() where p.count == 2 {
                var end = p[1]
                if !key.open.contains(k + 1) { // locked: the star still crosses Plaza Mayor, its round end at the edge
                    let d = p[1] - p[0]
                    end = p[0] + d * min(abs(d.x) > 0 ? (plaza.w / 2 - r) / abs(d.x) : 1, abs(d.y) > 0 ? (plaza.h / 2 - r) / abs(d.y) : 1, 1)
                }
                roads.addLines(between: [CGPoint(x: p[0].x, y: p[0].y), CGPoint(x: end.x, y: end.y)])
            }
            g.addPath(roads)
            g.setLineWidth(CGFloat(Terrain.pathWidth))
            g.setLineCap(.round)
            g.setLineJoin(.round)
            g.setStrokeColor(color(.path).cgColor)
            g.strokePath()
        }
        return SKTexture(image: image)
    }

    /// The outlines as a quadratic B-spline through their midpoints: smooth everywhere, so no corner survives.
    static func path(_ loops: [[Vec]]) -> CGPath {
        let p = CGMutablePath()
        for l in loops where l.count >= 3 {
            func at(_ i: Int) -> CGPoint { CGPoint(x: l[i % l.count].x, y: l[i % l.count].y) }
            func mid(_ i: Int) -> CGPoint { CGPoint(x: (at(i).x + at(i + 1).x) / 2, y: (at(i).y + at(i + 1).y) / 2) }
            p.move(to: mid(0))
            for i in 1...l.count { p.addQuadCurve(to: mid(i), control: at(i)) }
            p.closeSubpath()
        }
        return p
    }

    /// Where a district's two water reflections sit: centres of water cells with water all around.
    static func glints(_ t: Terrain, in r: Rect) -> [Vec] {
        var deep: [Vec] = []
        for y in stride(from: r.y + Terrain.cell / 2, to: r.y + r.h, by: Terrain.cell) {
            for x in stride(from: r.x + Terrain.cell / 2, to: r.x + r.w, by: Terrain.cell) {
                let p = Vec(x, y)
                if (-1...1).allSatisfy({ dy in (-1...1).allSatisfy { dx in t.at(p + Vec(Double(dx), Double(dy)) * Terrain.cell) == .water } }) {
                    deep.append(p)
                }
            }
        }
        return deep.count < 2 ? deep : [deep[deep.count / 3], deep[2 * deep.count / 3]]
    }

    /// A reflection: a 6×2 u capsule of `card`, shown at 60%.
    static let glint: SKTexture = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let r = CGRect(x: 0, y: 0, width: 24, height: 8)
        return SKTexture(image: UIGraphicsImageRenderer(size: r.size, format: format).image { _ in
            card.setFill()
            UIBezierPath(roundedRect: r, cornerRadius: 4).fill()
        })
    }()
}
