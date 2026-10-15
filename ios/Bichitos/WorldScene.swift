import SpriteKit
import UIKit

enum Ink {
    static let mist = UIColor(red: 0xF3 / 255, green: 0xF1 / 255, blue: 0xEC / 255, alpha: 1)
    static let ink = UIColor(red: 0x2B / 255, green: 0x2A / 255, blue: 0x33 / 255, alpha: 1)
    static let accent = UIColor(red: 1, green: 0x6B / 255, blue: 0x4A / 255, alpha: 1)

    /// District tint: its own hue mixed 8% over mist, so districts tell apart without competing with the bichitos.
    static func tint(_ district: Int) -> UIColor {
        let hues: [UInt32] = [0x5AA9E6, 0xE6B85A, 0xA98BE6, 0xE68A5A, 0x5AE6A9, 0xE65AA9, 0x5AD0E6, 0x9BC25A]
        let h = hues[district % hues.count]
        func mix(_ shift: UInt32, _ base: CGFloat) -> CGFloat { base * 0.92 + CGFloat((h >> shift) & 0xFF) / 255 * 0.08 }
        return UIColor(red: mix(16, 0xF3 / 255), green: mix(8, 0xF1 / 255), blue: mix(0, 0xEC / 255), alpha: 1)
    }
}

/// Draws the world. The simulation decides everything; this only advances it in 20 Hz ticks and paints
/// positions interpolated between the last two ticks.
final class WorldScene: SKScene, ObservableObject {
    private(set) var world: World
    /// Called once, when the first visible rect is known, to put the starting bichitos on screen.
    private var populate: ((inout World, Rect) -> Void)?

    /// Name of the district the camera is looking at, for the title on top.
    @Published private(set) var title = ""
    /// A short line about something the map just did (a bichito moving out, a new district).
    @Published private(set) var news: String? = nil
    private var newsUntil = 0.0
    private var homes: [Int: Int] = [:]  // bichito → home district, to notice emigrations
    private var knownDistricts: Int

    private var lens: Camera
    private var pinchFrom = 3
    private var districtNodes: [SKSpriteNode] = []
    /// Points per sprite pixel: always an integer, so every pixel is a whole square on screen.
    private var pixel: CGFloat { CGFloat(lens.pixel) }
    private var unit: CGFloat { CGFloat(lens.unit) }
    private var screenSize: Vec { Vec(Double(size.width), Double(size.height)) }
    private var origin: Vec { // world point at the top-left of the screen
        let r = lens.rect(screenSize)
        return Vec(r.x, r.y)
    }
    private var lastTime: TimeInterval?
    private var pending = 0.0
    private var previous: [Int: Vec] = [:]
    private var bichitoNodes: [Int: BichitoNode] = [:]
    private var foodNodes: [Int: SKNode] = [:]
    private var eggNodes: [Int: SKNode] = [:]
    private var noteNodes: [Int: SKNode] = [:]
    /// Tray toggle: a tap on the ground drops food.
    var foodMode = false
    private var touch: Touch?
    private var finger: UITouch?
    private var grabOffset = Vec.zero
    private var dropping = Set<Int>() // just released from the editor: they fall in when their node appears

    /// The camera starts on `focus`, or on the centre of the first district.
    init(world: World, focus: Vec? = nil, populate: ((inout World, Rect) -> Void)? = nil) {
        self.world = world
        self.populate = populate
        lens = Camera(center: focus ?? world.districts[0].rect.center, pixel: Camera.pixels.lowerBound)
        knownDistricts = world.districts.count
        homes = Dictionary(world.bichitos.map { ($0.id, $0.district) }, uniquingKeysWith: { a, _ in a })
        super.init(size: CGSize(width: 1, height: 1))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = Ink.mist
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 10, size.height > 10 else { return }
        if oldSize.width <= 10 { lens.pixel = max(Camera.pixels.lowerBound, Int(min(size.width, size.height) / 140)) }
        fit()
        if let populate, let visible = world.visibleRect {
            populate(&world, visible)
            self.populate = nil
        }
        relayout()
    }

    /// Keeps the camera on the (possibly grown) map and tells the simulation what is on screen.
    private func fit() {
        lens.clamp(to: world.size, screenSize)
        world.visibleRect = lens.rect(screenSize)
    }

    /// After a zoom: sizes follow the new pixel; simple things are simply drawn again.
    private func relayout() {
        for node in bichitoNodes.values { node.layout(pixel: pixel) }
        for nodes in [foodNodes, eggNodes, noteNodes] { for n in nodes.values { n.removeFromParent() } }
        foodNodes = [:]
        eggNodes = [:]
        noteNodes = [:]
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        guard longPress == nil else { return }
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched)))
        let g = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        view.addGestureRecognizer(g)
        longPress = g
    }

    /// Pinch zoom in whole pixel steps, around the fingers.
    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        if g.state == .began { pinchFrom = lens.pixel }
        guard g.state == .changed, let view else { return }
        let target = Int((Double(pinchFrom) * Double(g.scale)).rounded())
        let before = lens.pixel
        let f = g.location(in: view)
        lens.zoom(to: target, around: Vec(Double(f.x), Double(f.y)), screenSize)
        fit()
        if lens.pixel != before { relayout() }
    }

    // MARK: - New bichitos

    /// A bichito from the editor: it appears in the middle of the screen, falls in from above and lands with a boing.
    func drop(_ recipe: Recipe, name: String, description: String) {
        let id = world.add(recipe, at: world.visibleRect?.center, name: name, description: description)
        if let i = world.index(of: id) { world.bichitos[i].enter(.happy, for: 2) }
        dropping.insert(id)
    }

    func rename(_ id: Int, to name: String) { world.rename(id, to: name) }

    // MARK: - Long press → card

    /// Called with the id of the bichito under a long press.
    var onLongPress: ((Int) -> Void)?
    private var longPress: UILongPressGestureRecognizer?

    @objc private func longPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let view else { return }
        let p = convertPoint(fromView: g.location(in: view))
        // The body's centre sits about 12 sprite pixels above the feet (the node's origin).
        let hit = bichitoNodes
            .map { (id: $0.key, d: hypot($0.value.position.x - p.x, $0.value.position.y + 12 * pixel - p.y)) }
            .filter { $0.d < 16 * pixel }
            .min { $0.d < $1.d }
        if let hit { onLongPress?(hit.id) }
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
        fit()
        let name = world.districts[world.district(at: lens.center)].name(world.language)
        if name != title { title = name }
        if news != nil, currentTime > newsUntil { news = nil }
        if world.districts.count > knownDistricts {
            knownDistricts = world.districts.count
            let place = world.districts[knownDistricts - 1].name(world.language)
            announce(world.language == .es ? "Se abrió un barrio nuevo: \(place)" : "A new district opened: \(place)", at: currentTime)
        }
        draw(alpha: pending / World.dt, dt: dt, now: currentTime)
    }

    private func announce(_ line: String, at time: TimeInterval) {
        news = line
        newsUntil = time + 5
    }

    private func draw(alpha: Double, dt: Double, now: TimeInterval) {
        drawDistricts()
        var alive = Set<Int>()
        for b in world.bichitos {
            if let old = homes[b.id], old != b.district {
                let place = world.districts[b.district].name(world.language)
                announce(world.language == .es ? "\(b.name) se muda a \(place)" : "\(b.name) is moving to \(place)", at: now)
            }
            homes[b.id] = b.district
            alive.insert(b.id)
            let node: BichitoNode
            if let n = bichitoNodes[b.id] {
                node = n
            } else {
                node = BichitoNode(b, pixel: pixel)
                bichitoNodes[b.id] = node
                addChild(node)
                if dropping.remove(b.id) != nil { node.dropIn(from: size.height / 2) }
            }
            let from = previous[b.id] ?? b.pos
            let p = from + (b.pos - from) * alpha
            // Feet sit a bit below the body centre the simulation tracks.
            node.position = screen(Vec(p.x, p.y + b.recipe.radius * 0.6))
            node.zPosition = depth(node.position)
            node.render(b, dt: dt, moving: !world.districts[b.district].rect.contains(b.pos))
        }
        for (id, node) in bichitoNodes where !alive.contains(id) {
            node.removeFromParent()
            bichitoNodes[id] = nil
            homes[id] = nil
        }
        sync(&foodNodes, world.foods.map { ($0.id, $0.pos) }, make: makeFood)
        sync(&eggNodes, world.eggs.map { ($0.id, $0.pos) }, make: makeEgg)
        sync(&noteNodes, world.notes.map { ($0.bichito.id, $0.pos) }, make: makeNote)
    }

    /// Each district is a tinted patch of ground with its name near the top.
    private func drawDistricts() {
        while districtNodes.count < world.districts.count {
            let d = world.districts[districtNodes.count]
            let patch = SKSpriteNode(color: Ink.tint(d.index), size: .zero)
            patch.anchorPoint = CGPoint(x: 0, y: 1)
            patch.zPosition = -100
            let font = UIFont.systemFont(ofSize: 28, weight: .heavy)
            let label = SKLabelNode()
            label.attributedText = NSAttributedString(string: d.name(world.language), attributes: [
                .font: UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 28),
                .foregroundColor: Ink.ink.withAlphaComponent(0.18),
            ])
            label.verticalAlignmentMode = .top
            label.zPosition = 1
            patch.addChild(label)
            addChild(patch)
            districtNodes.append(patch)
        }
        for (k, patch) in districtNodes.enumerated() {
            let r = world.districts[k].rect
            patch.position = screen(Vec(r.x, r.y))
            patch.size = CGSize(width: CGFloat(r.w) * unit, height: CGFloat(r.h) * unit)
            patch.children.first?.position = CGPoint(x: patch.size.width / 2, y: -60)
        }
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

// MARK: - Gestures

extension WorldScene {
    /// Screen point (y down) → world point.
    private func worldPoint(_ p: CGPoint) -> Vec {
        Vec(origin.x + Double(p.x / unit), origin.y + Double(p.y / unit))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touch == nil, let t = touches.first, let view else { return }
        let p = t.location(in: view)
        let w = worldPoint(p)
        let target = world.bichito(at: w, pad: Double(12 / unit))
        touch = Touch(at: Vec(Double(p.x), Double(p.y)), time: t.timestamp, target: target, foodMode: foodMode)
        finger = t
        if let id = target, let b = world.bichito(id) { grabOffset = b.pos - w }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = finger, touches.contains(t), var g = touch, let view else { return }
        let p = t.location(in: view)
        if case let .grab(id) = g.move(to: Vec(Double(p.x), Double(p.y)), time: t.timestamp) {
            world.grab(id)
            Haptics.tap()
        }
        touch = g
        guard g.isDrag else { return }
        if let id = g.target {
            world.move(id, to: worldPoint(p) + grabOffset)
        } else { // dragging empty ground pans the map
            let q = t.previousLocation(in: view)
            lens.pan(by: Vec(Double(p.x - q.x), Double(p.y - q.y)))
            fit()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = finger, touches.contains(t), let g = touch, let view else { return }
        switch g.tapAction {
        case let .pet(id): world.pet(id); Haptics.tap()
        case .feed: world.dropFood(at: worldPoint(t.location(in: view))); Haptics.tap()
        default: break
        }
        if g.isDrag, let id = g.target {
            // Throw with the finger's speed, capped so a wild flick doesn't cross the whole map.
            var v = g.velocity(at: t.timestamp) * Double(1 / unit)
            if v.length > 2000 { v = v.unit * 2000 }
            world.release(id, velocity: v)
        }
        touch = nil
        finger = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = finger, touches.contains(t) else { return }
        if let g = touch, g.isDrag, let id = g.target { world.release(id, velocity: .zero) }
        touch = nil
        finger = nil
    }

    /// Shaking the phone: everybody jumps.
    func scareEveryone() {
        world.scare(at: nil)
        Haptics.tap()
    }
}

@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    static func tap() { light.impactOccurred() }
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
    private var shownName = ""

    init(_ b: Bichito, pixel: CGFloat) {
        recipe = b.recipe
        lastVel = b.vel
        lastMood = b.mood
        super.init()
        sprite.anchorPoint = CGPoint(x: 0.5, y: 1 / CGFloat(Sprites.height)) // feet on the node's origin, shadow below
        addChild(sprite)

        show(name: b.name)
        label.verticalAlignmentMode = .top
        label.zPosition = 50
        addChild(label)

        bubble.fillColor = .white
        bubble.strokeColor = Ink.ink.withAlphaComponent(0.1)
        bubble.zPosition = 100
        bubble.isHidden = true
        bubbleText.fontSize = 14
        bubbleText.fontColor = Ink.ink // SKLabelNode defaults to white, invisible on the white bubble
        bubbleText.verticalAlignmentMode = .center
        bubble.addChild(bubbleText)
        addChild(bubble)
        layout(pixel: pixel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func layout(pixel: CGFloat) {
        self.pixel = pixel
        sprite.size = CGSize(width: CGFloat(Sprites.width) * pixel, height: CGFloat(Sprites.height) * pixel)
        label.position = CGPoint(x: 0, y: -2 * pixel)
        // Bubble: rounded box with a little tail pointing down at the head.
        let w: CGFloat = 30, h: CGFloat = 24, tail: CGFloat = 6
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: -w / 2, y: tail, width: w, height: h), cornerWidth: 10, cornerHeight: 10)
        path.move(to: CGPoint(x: -5, y: tail + 0.5))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 5, y: tail + 0.5))
        path.closeSubpath()
        bubble.path = path
        bubble.position = CGPoint(x: 0, y: 26 * pixel)
        bubbleText.position = CGPoint(x: 0, y: tail + h / 2)
    }

    private func show(name: String) {
        shownName = name
        let font = UIFont.systemFont(ofSize: 11, weight: .bold)
        label.attributedText = NSAttributedString(string: name, attributes: [
            .font: UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 11),
            .foregroundColor: Ink.ink.withAlphaComponent(0.7),
        ])
    }

    /// Falls from `height` points above its feet, then squashes on landing and springs back.
    func dropIn(from height: CGFloat) {
        let fall = 0.45
        spring.kick(3) // stretched while falling
        sprite.position.y = height
        sprite.run(.sequence([
            // Whole points, so the pixels stay on the grid on the way down.
            .customAction(withDuration: fall) { node, t in
                let k = min(Double(t) / fall, 1)
                node.position.y = (height * CGFloat(1 - k * k)).rounded()
            },
            .run { [weak self] in self?.spring.kick(-8) },
        ]))
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
    func render(_ b: Bichito, dt: Double, moving: Bool = false) {
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
        if b.name != shownName { show(name: b.name) }
        let text = Look.bubble(mood: b.mood, needs: b.needs, dizzy: b.dizzy, moving: moving)
        if text != shownBubble {
            shownBubble = text
            bubble.isHidden = text == nil
            bubbleText.text = text
        }
    }
}
