import SpriteKit
import UIKit

enum Ink {
    static let mist = UIColor(red: 0xF3 / 255, green: 0xF1 / 255, blue: 0xEC / 255, alpha: 1)
    static let ink = UIColor(red: 0x2B / 255, green: 0x2A / 255, blue: 0x33 / 255, alpha: 1)
    static let accent = UIColor(red: 1, green: 0x6B / 255, blue: 0x4A / 255, alpha: 1)
}

/// Draws the world. The simulation decides everything; this only advances it in 20 Hz ticks and paints
/// positions interpolated between the last two ticks.
final class WorldScene: SKScene {
    private(set) var world: World
    /// Called once, when the first visible rect is known, to put the starting bichitos on screen.
    private var populate: ((inout World, Rect) -> Void)?

    /// Points per sprite pixel: always an integer, so every pixel is a whole square on screen.
    private var pixel: CGFloat = 2
    /// A sprite pixel is 2 world units, so a bichito's drawn body matches its collision radius.
    private var unit: CGFloat { pixel / 2 }
    private var origin = Vec.zero // world point at the top-left of the screen
    private var lastTime: TimeInterval?
    private var pending = 0.0
    private var previous: [Int: Vec] = [:]
    private var bichitoNodes: [Int: BichitoNode] = [:]
    private var foodNodes: [Int: SKNode] = [:]
    private var eggNodes: [Int: SKNode] = [:]
    private var noteNodes: [Int: SKNode] = [:]

    init(world: World, populate: ((inout World, Rect) -> Void)? = nil) {
        self.world = world
        self.populate = populate
        super.init(size: CGSize(width: 1, height: 1))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = Ink.mist
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 10, size.height > 10 else { return }
        pixel = max(3, (min(size.width, size.height) / 140).rounded(.down))
        let w = Double(size.width / unit), h = Double(size.height / unit)
        // shortcut: the camera sits on the centre of the first district; panning and zoom come with the map (#11).
        let home = world.districts[0].rect.center
        origin = Vec(home.x - w / 2, home.y - h / 2)
        let visible = Rect(x: origin.x, y: origin.y, w: w, h: h)
        world.visibleRect = visible
        if let populate {
            populate(&world, visible)
            self.populate = nil
        }
        for node in bichitoNodes.values { node.layout(pixel: pixel) }
    }

    // MARK: - Frame

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime.map { min(max(currentTime - $0, 0), 0.25) } ?? 0
        lastTime = currentTime
        pending += dt
        while pending >= World.dt {
            pending -= World.dt
            previous = Dictionary(world.bichitos.map { ($0.id, $0.pos) }, uniquingKeysWith: { a, _ in a })
            world.tick()
            for b in world.bichitos { bichitoNodes[b.id]?.tick(b) }
        }
        draw(alpha: pending / World.dt, dt: dt)
    }

    private func draw(alpha: Double, dt: Double) {
        var alive = Set<Int>()
        for b in world.bichitos {
            alive.insert(b.id)
            let node: BichitoNode
            if let n = bichitoNodes[b.id] {
                node = n
            } else {
                node = BichitoNode(b, pixel: pixel)
                node.language = world.language
                bichitoNodes[b.id] = node
                addChild(node)
            }
            let from = previous[b.id] ?? b.pos
            let p = from + (b.pos - from) * alpha
            // Feet sit a bit below the body centre the simulation tracks.
            node.position = screen(Vec(p.x, p.y + b.recipe.radius * 0.6))
            node.zPosition = depth(node.position)
            node.render(b, dt: dt)
        }
        for (id, node) in bichitoNodes where !alive.contains(id) {
            node.removeFromParent()
            bichitoNodes[id] = nil
        }
        sync(&foodNodes, world.foods.map { ($0.id, $0.pos) }, make: makeFood)
        sync(&eggNodes, world.eggs.map { ($0.id, $0.pos) }, make: makeEgg)
        sync(&noteNodes, world.notes.map { ($0.bichito.id, $0.pos) }, make: makeNote)
    }

    /// Simple things (food, eggs, notes) appear, follow their world position and disappear with it.
    private func sync(_ nodes: inout [Int: SKNode], _ items: [(Int, Vec)], make: () -> SKNode) {
        var alive = Set<Int>()
        for (id, pos) in items {
            alive.insert(id)
            let node: SKNode
            if let n = nodes[id] {
                node = n
            } else {
                node = make()
                nodes[id] = node
                addChild(node)
            }
            node.position = screen(pos)
            node.zPosition = depth(node.position)
        }
        for (id, node) in nodes where !alive.contains(id) {
            node.removeFromParent()
            nodes[id] = nil
        }
    }

    /// World (y down) → scene (y up), snapped to device pixels so sprites never straddle them.
    private func screen(_ p: Vec) -> CGPoint {
        let s = view?.contentScaleFactor ?? 3
        let x = CGFloat(p.x - origin.x) * unit, y = size.height - CGFloat(p.y - origin.y) * unit
        return CGPoint(x: (x * s).rounded() / s, y: (y * s).rounded() / s)
    }

    /// Lower on screen = closer = drawn on top.
    private func depth(_ p: CGPoint) -> CGFloat { 1000 - p.y / 10 }

    private func makeFood() -> SKNode {
        let n = SKShapeNode(circleOfRadius: 3 * pixel)
        n.fillColor = Ink.accent
        n.strokeColor = Ink.ink.withAlphaComponent(0.2)
        return n
    }

    private func makeEgg() -> SKNode {
        let n = SKShapeNode(ellipseOf: CGSize(width: 8 * pixel, height: 10 * pixel))
        n.fillColor = UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
        n.strokeColor = Ink.ink.withAlphaComponent(0.25)
        return n
    }

    private func makeNote() -> SKNode {
        let n = SKShapeNode(rectOf: CGSize(width: 14 * pixel, height: 10 * pixel), cornerRadius: pixel)
        n.fillColor = .white
        n.strokeColor = Ink.ink.withAlphaComponent(0.15)
        n.zRotation = 0.12
        let mark = SKLabelNode(text: "✉️")
        mark.fontSize = 6 * pixel
        mark.verticalAlignmentMode = .center
        n.addChild(mark)
        return n
    }
}

/// One bichito on screen: sprite (with its pixel shadow), name under it, bubble over it.
final class BichitoNode: SKNode {
    private let sprite = SKSpriteNode()
    private let label = SKLabelNode()
    private let bubble = SKShapeNode()
    private let bubbleText = SKLabelNode()
    private let recipe: Recipe
    private var pixel: CGFloat = 2
    private var spring = Spring()
    private var legPhase = 0.0
    private var blinkIn = Double.random(in: 1...4)
    private var blinkLeft = 0.0
    private var lastVel: Vec
    private var lastMood: Bichito.Mood
    private var key: SpriteKey?
    private var shownBubble: String?
    var language = Language.es
    /// `-screenshot-talk` (CI): every bubble becomes a phrase and stays up.
    static let alwaysTalk = CommandLine.arguments.contains("-screenshot-talk")
    private var talk: (text: String, times: [Double], clock: Double, shown: Int)?
    private var bubbleSize = CGSize(width: 30, height: 24)
    private static let bubbleMaxWidth: CGFloat = 120
    private static let bubbleFont: UIFont = {
        let font = UIFont.systemFont(ofSize: 13, weight: .bold)
        return UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 13)
    }()

    init(_ b: Bichito, pixel: CGFloat) {
        recipe = b.recipe
        lastVel = b.vel
        lastMood = b.mood
        super.init()
        sprite.anchorPoint = CGPoint(x: 0.5, y: 1 / CGFloat(Sprites.height)) // feet on the node's origin, shadow below
        addChild(sprite)

        let font = UIFont.systemFont(ofSize: 11, weight: .bold)
        label.attributedText = NSAttributedString(string: b.name, attributes: [
            .font: UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 11),
            .foregroundColor: Ink.ink.withAlphaComponent(0.7),
        ])
        label.verticalAlignmentMode = .top
        label.zPosition = 50
        addChild(label)

        bubble.fillColor = .white
        bubble.strokeColor = Ink.ink.withAlphaComponent(0.1)
        bubble.zPosition = 100
        bubble.isHidden = true
        bubbleText.verticalAlignmentMode = .center
        bubbleText.numberOfLines = 0
        bubbleText.preferredMaxLayoutWidth = BichitoNode.bubbleMaxWidth
        bubble.addChild(bubbleText)
        addChild(bubble)
        layout(pixel: pixel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func layout(pixel: CGFloat) {
        self.pixel = pixel
        sprite.size = CGSize(width: CGFloat(Sprites.width) * pixel, height: CGFloat(Sprites.height) * pixel)
        label.position = CGPoint(x: 0, y: -2 * pixel)
        bubble.position = CGPoint(x: 0, y: 26 * pixel)
        shapeBubble()
    }

    /// Rounded box with a little tail pointing down at the head, sized to `bubbleSize`.
    private func shapeBubble() {
        let w = bubbleSize.width, h = bubbleSize.height, tail: CGFloat = 6
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: -w / 2, y: tail, width: w, height: h), cornerWidth: 10, cornerHeight: 10)
        path.move(to: CGPoint(x: -5, y: tail + 0.5))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 5, y: tail + 0.5))
        path.closeSubpath()
        bubble.path = path
        bubbleText.position = CGPoint(x: 0, y: tail + h / 2)
    }

    /// After every simulation tick: speeding up stretches, braking or bonks squash, a new mood gives a hop.
    func tick(_ b: Bichito) {
        let dv = (b.vel - lastVel).length
        if dv > 1 { spring.kick((b.vel.length >= lastVel.length ? 1 : -1) * min(dv, 200) * 0.03) }
        if b.mood != lastMood { spring.kick(-2.5) }
        lastVel = b.vel
        lastMood = b.mood
    }

    /// Every frame: advance the spring, the legs and the blink, and pick the cached texture.
    func render(_ b: Bichito, dt: Double) {
        spring.step(dt)
        let speed = b.vel.length
        legPhase = speed > 6 ? legPhase + dt * speed / 8 : 0 // a step every 8 world units
        blinkIn -= dt
        if blinkIn <= 0 {
            blinkLeft = 0.15
            blinkIn = Double.random(in: 2...5)
        }
        blinkLeft -= dt
        let next = SpriteKey(recipe: recipe, squash: Look.squashLevel(spring.squash),
                             expression: Look.expression(mood: b.mood, needs: b.needs, dizzy: b.dizzy, blinking: blinkLeft > 0),
                             legFrame: recipe.legs == 0 ? 0 : Int(legPhase) % 2,
                             wellbeing: Look.wellbeingLevel(b.needs))
        if next != key {
            key = next
            sprite.texture = Sprites.shared.texture(next)
        }
        let text = Look.bubble(mood: b.mood, needs: b.needs, dizzy: b.dizzy)
        if var t = talk {
            t.clock += dt
            if t.clock < t.times[t.times.count - 1] + (BichitoNode.alwaysTalk ? 600 : 2) {
                let shown = t.times.dropLast().filter { $0 <= t.clock }.count
                if shown != t.shown { showBubble(t.text, revealed: shown) }
                t.shown = shown
                talk = t
                return
            }
            talk = nil
            shownBubble = text
            showBubble(text)
        }
        if text != shownBubble {
            shownBubble = text
            if text == nil || !startTalking(b) { showBubble(text) }
        }
    }

    /// Voice (#14): now and then, only on screen, a phrase replaces the emoji and appears in step with the babble.
    private func startTalking(_ b: Bichito) -> Bool {
        guard BichitoNode.alwaysTalk || Double.random(in: 0..<1) < 0.35,
              let scene, CGRect(origin: .zero, size: scene.size).contains(position) else { return false }
        let line = Phrases.say(mood: b.mood, needs: b.needs, dizzy: b.dizzy, personality: recipe.personality,
                               seed: .random(in: 0...UInt64.max), language: language)
        let voice = recipe.voice
        talk = (line, Babble.timeline(line, voice: voice), 0, -1)
        Speaker.shared.say(line, voice: voice, id: b.id)
        return true
    }

    /// The first `revealed` characters are drawn; the rest are laid out but clear, so the bubble never jumps.
    private func showBubble(_ text: String?, revealed: Int = .max) {
        bubble.isHidden = text == nil
        guard let text else { return }
        let chars = Array(text), k = min(revealed, chars.count)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let s = NSMutableAttributedString(string: String(chars[..<k]), attributes: [
            .font: BichitoNode.bubbleFont, .foregroundColor: Ink.ink, .paragraphStyle: style,
        ])
        s.append(NSAttributedString(string: String(chars[k...]), attributes: [
            .font: BichitoNode.bubbleFont, .foregroundColor: UIColor.clear, .paragraphStyle: style,
        ]))
        bubbleText.attributedText = s
        let box = s.boundingRect(with: CGSize(width: BichitoNode.bubbleMaxWidth, height: 200),
                                 options: .usesLineFragmentOrigin, context: nil)
        let size = CGSize(width: max(30, ceil(box.width) + 16), height: max(24, ceil(box.height) + 10))
        if size != bubbleSize {
            bubbleSize = size
            shapeBubble()
        }
    }
}
