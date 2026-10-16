import SpriteKit
import UIKit

/// Paints a building's `Maqueta` shapes into a texture, once per zoom level (`SKShapeNode` live is expensive).
/// Antialiased vector, no outlines: the soft world (DESIGN.md "Los dos mundos").
enum Fachada {
    static func paint(_ b: Building, _ key: Maqueta.Key) -> SKTexture {
        let f = Maqueta.frame(b), s = CGFloat(key.texel), pad = CGFloat(Maqueta.pad)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: (CGFloat(f.w) * s).rounded(.up), height: (CGFloat(f.h) * s).rounded(.up))
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let g = ctx.cgContext
            g.scaleBy(x: s, y: s)
            g.translateBy(x: pad, y: pad)
            for shape in Maqueta.shapes(b, closed: key.closed, lit: key.lit) { draw(shape, g) }
        }
        return SKTexture(image: image)
    }

    private static func cg(_ r: Rect) -> CGRect { CGRect(x: r.x, y: r.y, width: r.w, height: r.h) }
    private static func cg(_ p: Vec) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    private static func draw(_ shape: Maqueta.Shape, _ g: CGContext) {
        g.saveGState()
        defer { g.restoreGState() }
        if let c = shape.clip { g.clip(to: cg(c)) }
        let c = shape.color
        let color = UIColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: CGFloat(c.a) / 255).cgColor
        g.setFillColor(color)
        g.setStrokeColor(color)
        switch shape.form {
        case let .box(r, radius):
            let box = cg(r), k = min(CGFloat(radius), box.width / 2, box.height / 2)
            g.addPath(CGPath(roundedRect: box, cornerWidth: k, cornerHeight: k, transform: nil))
            g.fillPath()
        case let .oval(r):
            g.fillEllipse(in: cg(r))
        case let .poly(points, radius):
            guard points.count >= 3 else { return }
            let p = points.map { cg($0) }, n = p.count, path = CGMutablePath()
            path.move(to: CGPoint(x: (p[n - 1].x + p[0].x) / 2, y: (p[n - 1].y + p[0].y) / 2))
            for i in 0..<n { path.addArc(tangent1End: p[i], tangent2End: p[(i + 1) % n], radius: CGFloat(radius)) }
            path.closeSubpath()
            g.addPath(path)
            g.fillPath()
        case let .arch(r):
            let b = cg(r), k = b.width / 2, path = CGMutablePath()
            path.move(to: CGPoint(x: b.minX, y: b.maxY))
            path.addLine(to: CGPoint(x: b.minX, y: b.minY + k))
            path.addArc(tangent1End: CGPoint(x: b.minX, y: b.minY), tangent2End: CGPoint(x: b.midX, y: b.minY), radius: k)
            path.addArc(tangent1End: CGPoint(x: b.maxX, y: b.minY), tangent2End: CGPoint(x: b.maxX, y: b.minY + k), radius: k)
            path.addLine(to: CGPoint(x: b.maxX, y: b.maxY))
            path.closeSubpath()
            g.addPath(path)
            g.fillPath()
        case let .line(points, width):
            guard let first = points.first else { return }
            g.move(to: cg(first))
            for p in points.dropFirst() { g.addLine(to: cg(p)) }
            g.setLineWidth(CGFloat(width))
            g.setLineCap(.round)
            g.setLineJoin(.round)
            g.strokePath()
        case let .ring(r, width):
            g.setLineWidth(CGFloat(width))
            g.strokeEllipse(in: cg(r).insetBy(dx: CGFloat(width) / 2, dy: CGFloat(width) / 2))
        }
    }
}
