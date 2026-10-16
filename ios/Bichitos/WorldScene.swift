import SpriteKit
import UIKit

enum Ink {
    static let mist = UIColor(red: 0xF3 / 255, green: 0xF1 / 255, blue: 0xEC / 255, alpha: 1)
    static let ink = UIColor(red: 0x2B / 255, green: 0x2A / 255, blue: 0x33 / 255, alpha: 1)
    static let accent = UIColor(red: 1, green: 0x6B / 255, blue: 0x4A / 255, alpha: 1)

    /// District tint: its theme colour mixed 8% over mist, so districts tell apart without competing with the bichitos.
    /// The Mapa level, with no ground to read, mixes more (`amount`).
    static func tint(_ district: Int, _ amount: CGFloat = 0.08) -> UIColor {
        let h = District.themes[district % District.themes.count].tint
        func mix(_ shift: UInt32, _ base: CGFloat) -> CGFloat { base * (1 - amount) + CGFloat((h >> shift) & 0xFF) / 255 * amount }
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
    /// The live event on the toast under the title, if any.
    @Published private(set) var toast: WorldEvent? = nil
    /// Tapping the toast: `WorldView` sends the camera to the story.
    var onToastTap: ((WorldEvent) -> Void)?
    private var toasts = Toasts()
    /// The district (place in `districts`) just unlocked, for `UnlockBanner`; nil once dismissed.
    @Published var unlocked: Int? = nil
    /// Unlocking: mist over the new district that clears from the centre out (DESIGN.md "Desbloqueo").
    private var mists: [(node: SKShapeNode, rect: Rect, start: TimeInterval)] = []
    private var mistDuration = 1.2
    private var signNodes: [(node: SKNode, at: Vec)] = []
    private var signKey = ""
    private var seenEvents: Int
    /// How many bichitos live in that district, for `BarrioPill`.
    @Published private(set) var population = 0
    /// The district the camera is looking at.
    var here: Int { world.district(at: lens.center) }

    private var lens: Camera
    private var pinchFrom = 3.0
    /// Each district's ground (`Ground`) and its water reflections.
    private var districtNodes: [SKSpriteNode] = []
    private var glintNodes: [[(node: SKSpriteNode, at: Vec)]] = []
    /// Painted ground, only what `Ground.keep` says (#84); painted off the main thread, `painting` meanwhile.
    private var groundTextures: [Ground.Key: SKTexture] = [:]
    private var kept: Set<Ground.Key> = []
    private var painting: Set<Ground.Key> = []
    /// A tiny plain ground per district, shown until its painted one is ready.
    private var placeholders: [Ground.Key: SKTexture] = [:]
    /// Zoom level the camera is at (or springing to), for what each level shows.
    var level: Camera.Level { lens.level }
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
    /// Buildings and decoration near the screen (#37), by `Building.id`, and their textures for this zoom level.
    private var buildingNodes: [Int: SKSpriteNode] = [:]
    private var buildingTextures: [Maqueta.Key: SKTexture] = [:]
    /// Mapa level: a dot per bichito, and the district blobs, paths and locked outlines (`drawMap`).
    private var dotNodes: [Int: SKNode] = [:]
    private var labels = LabelLayout()
    private var named: [BichitoNode] = [], names: [CGRect] = []
    private var talkers: [BichitoNode] = [], bubbles: [CGRect] = [], shown: [Bool] = []
    /// #79: frames of the SwiftUI interface over the map, in window points (y down), set by `WorldView`.
    var obstacles: [CGRect] = []
    private var walls: [CGRect] = []
    private let mapLayer = SKNode()
    private var mapKey = ""
    private var mapShown = false // where `mapLayer` is fading to
    /// Tray toggle: a tap on the ground drops food.
    var foodMode = false
    var foodKind = Food.Kind.fruta
    private var touch: Touch?
    private var finger: UITouch?
    private var grabOffset = Vec.zero
    private var dropping = Set<Int>() // just released from the editor: they fall in when their node appears
    private(set) var follow = Follow()

    /// The camera starts on `focus`, or on the centre of the first district.
    init(world: World, focus: Vec? = nil, populate: ((inout World, Rect) -> Void)? = nil) {
        self.world = world
        self.populate = populate
        lens = Camera(center: focus ?? world.districts[0].rect.center, scale: Camera.Level.district.scale)
        seenEvents = world.eventTotal
        // `-screenshot-toast` (CI): toasts stay up so the capture finds one.
        if CommandLine.arguments.contains("-screenshot-toast") { toasts.duration = 600 }
        // `-screenshot-unlock` (CI): the mist clears slowly, so the capture catches it halfway.
        if CommandLine.arguments.contains("-screenshot-unlock") { mistDuration = 10 }
        super.init(size: CGSize(width: 1, height: 1))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = Ink.mist
        NotificationCenter.default.addObserver(self, selector: #selector(memoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    /// Low memory: every ground texture goes; the next frame paints again only what is on screen.
    @objc private func memoryWarning() {
        groundTextures = [:]
        placeholders = [:]
        for patch in districtNodes { patch.texture = nil }
    }

    /// Paints the ground in the background; the texture is made back on the main thread, if still wanted.
    private func paint(_ key: Ground.Key) {
        painting.insert(key)
        let terrain = world.terrain
        DispatchQueue.global(qos: .userInitiated).async {
            let image = Ground.paint(key, terrain)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                painting.remove(key)
                if kept.contains(key) { groundTextures[key] = SKTexture(cgImage: image) }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Takes back this scene's world after a fast-forward (coming back to the app); nodes follow it by id.
    func fastForwarded(to world: World) {
        self.world = world
        previous = [:]
        seenEvents = world.eventTotal // what happened while away goes to the summary, not to toasts
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 10, size.height > 10 else { return }
        if oldSize.width <= 10 {
            // `-screenshot-zoom 5` (CI) starts at another level.
            let start = UserDefaults.standard.double(forKey: "screenshot-zoom")
            lens.scale = Camera.Level.nearest(start > 0 ? start : max(3, Double(Int(min(size.width, size.height) / 140)))).scale
        }
        if mapLayer.parent == nil { mapLayer.zPosition = -50; mapLayer.alpha = 0; mapLayer.isHidden = true; addChild(mapLayer) }
        fit()
        if let populate, let visible = world.visibleRect {
            populate(&world, visible)
            self.populate = nil
        }
        relayout()
    }

    /// Keeps the camera on the (possibly grown) map and tells the simulation what is on screen.
    private func fit() {
        lens.clamp(to: level == .map ? world.mapBounds : world.bounds, screenSize)
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

    /// Pinch: the map scales smoothly around the fingers; letting go springs it to the nearest level.
    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        guard let view else { return }
        let f = g.location(in: view), focus = Vec(Double(f.x), Double(f.y))
        switch g.state {
        case .began:
            lens.grab()
            pinchFrom = lens.scale
        case .changed:
            zoom { $0.zoom(to: pinchFrom * Double(g.scale), around: focus, screenSize) }
        case .ended, .cancelled, .failed:
            if UIAccessibility.isReduceMotionEnabled { // no spring: straight to the level
                let to = lens.level.scale
                zoom { $0.zoom(to: to, around: focus, screenSize) }
            } else { lens.release(around: focus) }
        default: break
        }
    }

    /// Changes the camera; sprites are laid out again only when their whole pixel size changes.
    private func zoom(_ change: (inout Camera) -> Void) {
        let before = lens.pixel
        change(&lens)
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

    // MARK: - BichitoPeek actions

    /// Called with the bichito under a tap, or nil when the tap was on the ground (closes the peek).
    var onPeek: ((Int?) -> Void)?
    /// Called with the escaped bichito's id when a tap lands on its goodbye note.
    var onNote: ((Int) -> Void)?

    /// The squash comes on every pet, not only when the mood changes, so a rub keeps it squishing.
    func pet(_ id: Int) {
        if world.pet(id) { bichitoNodes[id]?.squish() }
        Haptics.fire(.pet)
    }

    /// VoiceOver «Lanzar».
    func toss(_ id: Int) {
        var rng = SystemRandomNumberGenerator()
        world.toss(id, using: &rng)
        Haptics.fire(.toss)
    }

    /// VoiceOver: one on-screen bichito, its body's frame in view points (y down).
    struct Seen: Identifiable {
        let id: Int
        let label: String
        let frame: CGRect
    }

    var onScreen: [Seen] {
        guard let visible = world.visibleRect else { return [] }
        return world.bichitos.filter { visible.contains($0.pos) }.map { b in
            let r = CGFloat(b.recipe.radius) * unit
            let c = CGPoint(x: CGFloat(b.pos.x - origin.x) * unit, y: CGFloat(b.pos.y - origin.y) * unit)
            return Seen(id: b.id, label: b.voiceLabel(world.language), frame: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
    }

    /// Drops its favourite food right next to it, to the side so it doesn't land under its body.
    func feed(_ id: Int) {
        guard let b = world.bichito(id) else { return }
        world.dropFood(at: b.pos + Vec(b.recipe.radius + 8, 0), kind: b.favorite)
        Haptics.tap()
    }

    func startFollowing(_ id: Int) { follow.start(id) }

    /// `BarrioPicker`: the camera travels to the middle of a district (with Reduce Motion, it is just there).
    func travel(to district: Int) { travel(to: world.districts[district].rect.center) }

    /// `NewsFeed` and `Toast`: the camera travels to where a story happened.
    func travel(to place: Vec) {
        follow.stop()
        if UIAccessibility.isReduceMotionEnabled { lens.center = place } else { lens.travel(to: place) }
        Haptics.tap()
    }

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
        if lens.snap != nil { zoom { $0.settle(dt: dt, screenSize) } }
        pending += dt
        while pending >= World.dt {
            pending -= World.dt
            previous = Dictionary(world.bichitos.map { ($0.id, $0.pos) }, uniquingKeysWith: { a, _ in a })
            world.tick()
            for b in world.bichitos { bichitoNodes[b.id]?.tick(b) }
        }
        lens.glide(dt: dt)
        if let to = follow.target(in: world) { // glide, so the 20 Hz steps and the first trip don't jump
            lens.center = lens.center + (to - lens.center) * (1 - exp(-6 * dt))
        }
        fit()
        let name = world.districts[here].name(world.language), count = world.population(of: here)
        if name != title { title = name }
        if count != population { population = count }
        for e in world.events.suffix(min(world.eventTotal - seenEvents, world.events.count)) {
            switch e {
            case let .unlocked(d, _): // the banner says it instead of a toast
                unlocked = d
                let mist = SKShapeNode()
                mist.fillColor = Ink.mist
                mist.strokeColor = .clear
                mist.zPosition = 2000 // over the y-sorted layer and the names
                addChild(mist)
                mists.append((node: mist, rect: world.districts[d].rect, start: currentTime))
            default: toasts.push(e, at: currentTime)
            }
            switch e { case .hatched, .unlocked, .recovered: Haptics.fire(.success); default: break }
        }
        seenEvents = world.eventTotal
        toasts.update(at: currentTime)
        if toasts.current != toast { toast = toasts.current }
        draw(alpha: pending / World.dt, dt: dt)
        drawMists(currentTime)
    }

    /// A hole opens in the mist from the district's centre while the rest fades; with Reduce Motion, just a 0.2 s fade.
    private func drawMists(_ now: TimeInterval) {
        let still = UIAccessibility.isReduceMotionEnabled
        mists.removeAll { m in
            let t = min(max((now - m.start) / (still ? 0.2 : mistDuration), 0), 1)
            guard t < 1 else { m.node.removeFromParent(); return true }
            let f = Ground.frame(m.rect), hw = CGFloat(f.w / 2) * unit, hh = CGFloat(f.h / 2) * unit
            let path = CGMutablePath()
            path.addLines(between: [CGPoint(x: -hw, y: -hh), CGPoint(x: hw, y: -hh), CGPoint(x: hw, y: hh), CGPoint(x: -hw, y: hh)])
            path.closeSubpath()
            let r = still ? 0 : CGFloat(1 - (1 - t) * (1 - t)) * hypot(hw, hh)
            if r > 0 { // wound against the box, so it is a hole under either fill rule
                path.move(to: CGPoint(x: r, y: 0))
                path.addArc(center: .zero, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
                path.closeSubpath()
            }
            m.node.path = path
            m.node.position = screen(m.rect.center)
            m.node.alpha = CGFloat(1 - t * t)
            m.node.isHidden = level == .map
            return false
        }
    }

    /// DESIGN.md "Cartel": a `bark` post with a `card` board and the district's name in 15 Heavy, at each path entrance
    /// (`World.signs`). A fixed size on screen, like the names; not on the Mapa level.
    private func drawSigns() {
        let key = "\(world.districts.count) \(world.language)"
        if key != signKey {
            signKey = key
            for s in signNodes { s.node.removeFromParent() }
            signNodes = world.signs.map { s in
                let node = WorldScene.sign(District(index: s.theme).name(world.language))
                addChild(node)
                return (node: node, at: s.pos)
            }
        }
        for s in signNodes {
            s.node.isHidden = level == .map
            s.node.position = screen(s.at)
            s.node.zPosition = depth(s.at.y)
        }
    }

    private static func sign(_ name: String) -> SKNode {
        let font = UIFont.systemFont(ofSize: 15, weight: .heavy)
        let text = SKLabelNode()
        text.attributedText = NSAttributedString(string: name, attributes: [
            .font: UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 15),
            .foregroundColor: Ink.ink,
        ])
        text.verticalAlignmentMode = .center
        let w = text.frame.width + 16, h: CGFloat = 26, post: CGFloat = 14
        let stick = SKShapeNode(rect: CGRect(x: -2, y: 0, width: 4, height: post + h / 2), cornerRadius: 1)
        stick.fillColor = Ground.color(0xC9B9A3) // bark
        stick.strokeColor = .clear
        let board = SKShapeNode(rect: CGRect(x: -w / 2, y: post, width: w, height: h), cornerRadius: 6)
        board.fillColor = Ground.card
        board.strokeColor = Ink.ink.withAlphaComponent(0.1)
        board.zPosition = 1
        text.position = CGPoint(x: 0, y: post + h / 2)
        text.zPosition = 2
        let node = SKNode()
        for n in [stick, board, text] as [SKNode] { node.addChild(n) }
        return node
    }

    private func draw(alpha: Double, dt: Double) {
        drawDistricts()
        let inside = world.asleepInside, sleepingIn = Set(inside.values.joined())
        drawBuildings(inside)
        drawSigns()
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
                if dropping.remove(b.id) != nil { node.dropIn(from: size.height / 2) }
            }
            let from = previous[b.id] ?? b.pos
            let p = from + (b.pos - from) * alpha
            let feet = Maqueta.feet(p, radius: b.recipe.radius)
            node.position = screen(Vec(p.x, feet))
            node.zPosition = depth(feet)
            node.level = level
            // A dot instead on the map (`dotNodes`); asleep in its casita, its shut door and icon instead.
            node.isHidden = level == .map || sleepingIn.contains(b.id)
            node.render(b, dt: dt, moving: !world.districts[b.district].rect.contains(b.pos))
        }
        for (id, node) in bichitoNodes where !alive.contains(id) {
            node.removeFromParent()
            bichitoNodes[id] = nil
        }
        placeLabels()
        // The Mapa level shows only districts and dots: food, eggs and notes would be specks.
        let onMap = level == .map
        sync(&dotNodes, onMap ? world.bichitos.map { ($0.id, $0.pos) } : [], make: makeDot)
        sync(&foodNodes, onMap ? [] : world.foods.map { ($0.id, $0.pos) }, make: makeFood)
        sync(&eggNodes, onMap ? [] : world.eggs.map { ($0.id, $0.pos) }, make: { _ in makeEgg() }, gone: { id, n in
            if self.world.eggs.contains(where: { $0.id == id }) { n.removeFromParent() } else { Self.hatch(n) } // gone from the world: it hatched
        })
        for e in world.eggs { // #12: it trembles harder as it gets ready, and cracks in its last seconds
            eggNodes[e.id]?.speed = 1 + 3 * CGFloat(max(0, 1 - e.hatchIn / World.hatchTime))
            eggNodes[e.id]?.children.first?.isHidden = e.hatchIn > 20
        }
        sync(&noteNodes, onMap ? [] : world.notes.map { ($0.bichito.id, $0.pos) }, make: makeNote)
    }

    /// #77: names and phrase bubbles on screen never touch (`LabelLayout`). Buffers are kept between frames.
    private func placeLabels() {
        let bounds = CGRect(origin: .zero, size: size), mid = CGPoint(x: size.width / 2, y: size.height / 2)
        named.removeAll(keepingCapacity: true)
        names.removeAll(keepingCapacity: true)
        talkers.removeAll(keepingCapacity: true)
        bubbles.removeAll(keepingCapacity: true)
        for b in world.bichitos { // the world's order is stable, so names don't swap places from frame to frame
            guard let node = bichitoNodes[b.id] else { continue }
            node.bubbleBlocked = false
            if let r = node.nameFrame, r.intersects(bounds) { named.append(node); names.append(r) }
            if let r = node.bubbleFrame, r.intersects(bounds) { talkers.append(node) }
        }
        // Ties (everybody starting at once) go to the one nearer the middle of the screen.
        func away(_ n: BichitoNode) -> CGFloat { hypot(n.position.x - mid.x, n.position.y - mid.y) }
        talkers.sort { $0.bubbleRank != $1.bubbleRank ? $0.bubbleRank > $1.bubbleRank : away($0) < away($1) }
        for n in talkers { bubbles.append(n.bubbleFrame ?? .null) }
        walls.removeAll(keepingCapacity: true)
        // The SpriteView fills the window, so only y flips.
        for r in obstacles { walls.append(CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height)) }
        labels.place(names: &names, bubbles: bubbles, shown: &shown, obstacles: walls)
        for (n, ok) in zip(talkers, shown) { n.bubbleBlocked = !ok }
        for (n, r) in zip(named, names) { n.placeName(r) }
    }

    /// Each district is its painted ground (its name shows only on the Mapa level); the Mapa level draws blobs instead (`drawMap`).
    private func drawDistricts() {
        while districtNodes.count < world.districts.count {
            let d = world.districts[districtNodes.count]
            let patch = SKSpriteNode() // its texture comes before any size
            patch.anchorPoint = CGPoint(x: 0, y: 1)
            patch.zPosition = -100
            // Two reflections on the water, fading in and out every 4 s, half a cycle apart.
            let glints = Ground.glints(world.terrain, in: d.rect).enumerated().map { k, p in
                let g = SKSpriteNode(texture: Ground.glint)
                g.alpha = 0
                g.zPosition = 1
                g.run(.sequence([.wait(forDuration: 2 * Double(k)), .repeatForever(.sequence([
                    .fadeAlpha(to: 0.6, duration: 1), .wait(forDuration: 1), .fadeAlpha(to: 0, duration: 1), .wait(forDuration: 1),
                ]))]))
                patch.addChild(g)
                return (node: g, at: p)
            }
            glintNodes.append(glints)
            addChild(patch)
            districtNodes.append(patch)
        }
        // #83: the Mapa layer (names, blobs, locked outlines) fades in and out as a pinch crosses the threshold.
        let onMap = level == .map
        if onMap != mapShown {
            mapShown = onMap
            mapLayer.removeAction(forKey: "fade")
            let t = UIAccessibility.isReduceMotionEnabled ? 0 : 0.2
            if onMap { mapLayer.isHidden = false }
            mapLayer.run(onMap ? .fadeIn(withDuration: t) : .sequence([.fadeOut(withDuration: t), .hide()]), withKey: "fade")
        }
        if !mapLayer.isHidden { drawMap() }
        let seed = world.layoutSeed ?? 0, still = UIAccessibility.isReduceMotionEnabled
        kept = Ground.keep(lens.rect(screenSize), here: here, world.districts, seed: seed, level: level)
        groundTextures = groundTextures.filter { kept.contains($0.key) }
        for key in kept where groundTextures[key] == nil && !painting.contains(key) { paint(key) }
        for (k, patch) in districtNodes.enumerated() {
            let index = world.districts[k].index, wanted = kept.first { $0.district == index }
            if let wanted, let t = groundTextures[wanted] {
                if patch.texture !== t { patch.texture = t }
            } else if wanted == nil || patch.texture == nil { // a texture on its way keeps the last one up meanwhile
                let plain = Ground.Key(seed: seed, district: index, open: [], texel: 1.0 / 8)
                if placeholders[plain] == nil { placeholders[plain] = SKTexture(cgImage: Ground.paint(plain, world.terrain, plain: true)) }
                if patch.texture !== placeholders[plain] { patch.texture = placeholders[plain] }
            }
            patch.isHidden = level == .map
            guard level != .map else { continue }
            let f = Ground.frame(world.districts[k].rect)
            patch.position = screen(Vec(f.x, f.y))
            patch.size = CGSize(width: CGFloat(f.w) * unit, height: CGFloat(f.h) * unit)
            for g in glintNodes[k] {
                g.node.isHidden = still // Reduce Motion: no reflections
                g.node.position = CGPoint(x: CGFloat(g.at.x - f.x) * unit, y: -CGFloat(g.at.y - f.y) * unit)
                g.node.size = CGSize(width: 12 * unit, height: 4 * unit)
            }
        }
    }

    /// Mapa level (DESIGN.md "Zoom", "Barrios"): open districts as blobs of their tint with the name on top,
    /// soft straight paths between neighbours, and locked ones as a dashed `hairline` outline with a lock.
    /// Built in points from the world origin and moved as one layer; built again only when it changes.
    private func drawMap() {
        mapLayer.position = screen(.zero)
        let locked = world.lockedOutlines, es = world.language == .es
        let key = "\(unit) \(world.districts.count) \(locked.compactMap(\.missing)) \(es)"
        guard key != mapKey else { return }
        mapKey = key
        mapLayer.removeAllChildren()
        func box(_ r: Rect) -> CGRect {
            CGRect(x: CGFloat(r.x) * unit, y: -CGFloat(r.y + r.h) * unit, width: CGFloat(r.w) * unit, height: CGFloat(r.h) * unit)
        }
        func point(_ p: Vec) -> CGPoint { CGPoint(x: CGFloat(p.x) * unit, y: -CGFloat(p.y) * unit) }
        func label(_ text: String, size: CGFloat, alpha: CGFloat, at p: CGPoint) {
            let font = UIFont.systemFont(ofSize: size, weight: .heavy)
            let l = SKLabelNode()
            l.attributedText = NSAttributedString(string: text, attributes: [
                .font: UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: size),
                .foregroundColor: Ink.ink.withAlphaComponent(alpha),
            ])
            l.verticalAlignmentMode = .top
            l.position = p
            l.zPosition = 2
            mapLayer.addChild(l)
        }
        let corner = 32 * unit // 16 u: blobs, not boxes
        let open = world.districts
        for (i, a) in open.enumerated() {
            for b in open[(i + 1)...] where (a.rect.center - b.rect.center).length < 1000 { // ring neighbours only
                let path = CGMutablePath()
                path.move(to: point(a.rect.center))
                path.addLine(to: point(b.rect.center))
                let line = SKShapeNode(path: path)
                line.strokeColor = Ink.ink.withAlphaComponent(0.12)
                line.lineWidth = 3
                line.lineCap = .round
                mapLayer.addChild(line)
            }
        }
        for d in open {
            let r = box(d.rect)
            let blob = SKShapeNode(rect: r, cornerRadius: corner)
            blob.fillColor = Ink.tint(d.index, 0.45)
            blob.strokeColor = .clear
            blob.zPosition = 1
            mapLayer.addChild(blob)
            // Just above the blob, in the mist between districts, so the dots never cover it.
            label(d.name(world.language), size: 11, alpha: 0.7, at: CGPoint(x: r.midX, y: r.maxY + 16))
        }
        for l in locked {
            let r = box(l.rect)
            let outline = SKShapeNode(path: CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil)
                .copy(dashingWithPhase: 0, lengths: [6, 4]))
            outline.strokeColor = Ink.ink.withAlphaComponent(0.1) // hairline
            outline.lineWidth = 1
            outline.zPosition = 1
            mapLayer.addChild(outline)
            let lock = SKSpriteNode(texture: WorldScene.lock)
            lock.position = CGPoint(x: r.midX, y: r.midY + (l.missing == nil ? 0 : 8))
            lock.zPosition = 2
            mapLayer.addChild(lock)
            if let n = l.missing {
                label(es ? "\(n == 1 ? "falta" : "faltan") \(n) \(n == 1 ? "bichito" : "bichitos")" : "\(n) more \(n == 1 ? "bichito" : "bichitos")",
                      size: 10, alpha: 0.55, at: CGPoint(x: r.midX, y: r.midY - 4))
            }
        }
    }

    /// `lock.fill` in ink at 35%, drawn into a bitmap: SpriteKit ignores a symbol's tint.
    private static let lock: SKTexture = {
        let symbol = UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))!
            .withTintColor(Ink.ink.withAlphaComponent(0.35), renderingMode: .alwaysOriginal)
        return SKTexture(image: UIGraphicsImageRenderer(size: symbol.size).image { _ in symbol.draw(at: .zero) })
    }()

    /// Simple things (food, eggs, notes) appear, follow their world position and disappear with it.
    private func sync(_ nodes: inout [Int: SKNode], _ items: [(Int, Vec)], make: (Int) -> SKNode,
                      gone: (Int, SKNode) -> Void = { $1.removeFromParent() }) {
        var alive = Set<Int>()
        for (id, pos) in items {
            alive.insert(id)
            let node: SKNode
            if let n = nodes[id] {
                node = n
            } else {
                node = make(id)
                nodes[id] = node
                addChild(node)
            }
            node.position = screen(pos)
            node.zPosition = depth(pos.y)
        }
        for (id, node) in nodes where !alive.contains(id) {
            gone(id, node)
            nodes[id] = nil
        }
    }

    /// World (y down) → scene (y up), snapped to device pixels so sprites never straddle them.
    private func screen(_ p: Vec) -> CGPoint {
        let s = view?.contentScaleFactor ?? 3
        let x = CGFloat(p.x - origin.x) * unit, y = size.height - CGFloat(p.y - origin.y) * unit
        return CGPoint(x: (x * s).rounded() / s, y: (y * s).rounded() / s)
    }

    /// The y-sort (`Maqueta.depth`) of something standing at world `y`.
    private func depth(_ y: Double) -> CGFloat { CGFloat(Maqueta.depth(y, top: origin.y, unit: lens.unit)) }

    /// #37: the open districts' buildings and decoration near the screen, each a cached texture in the y-sorted layer.
    /// A casita with someone asleep inside shows its door shut and that one's state icon over the roof.
    /// Not on the map, which shows only blobs and dots (DESIGN.md "Zoom").
    private func drawBuildings(_ inside: [Int: [Int]]) {
        var alive = Set<Int>(), used = Set<Maqueta.Key>()
        if level != .map, let seen = world.visibleRect {
            let open = Set(world.districts.map(\.index)), m = Maqueta.pad
            let near = Rect(x: seen.x - m, y: seen.y - m, w: seen.w + 2 * m, h: seen.h + 2 * m)
            for b in world.terrain.buildings where open.contains(b.theme) && Maqueta.frame(b).intersects(near) {
                alive.insert(b.id)
                let who = inside[b.id] ?? []
                let key = Maqueta.key(b, closed: !who.isEmpty, level: level)
                used.insert(key)
                let texture = buildingTextures[key] ?? Fachada.paint(b, key)
                buildingTextures[key] = texture
                let node: SKSpriteNode
                if let n = buildingNodes[b.id] {
                    node = n
                } else {
                    node = SKSpriteNode(texture: texture)
                    node.anchorPoint = CGPoint(x: 0, y: 1)
                    let icon = SKSpriteNode()
                    icon.anchorPoint = CGPoint(x: 0.5, y: 0)
                    icon.size = CGSize(width: CGFloat(Look.Icon.canvas) * 2, height: CGFloat(Look.Icon.canvas) * 2) // like BichitoNode's
                    icon.zPosition = 100
                    node.addChild(icon)
                    buildingNodes[b.id] = node
                    addChild(node)
                }
                if node.texture !== texture { node.texture = texture }
                let f = Maqueta.frame(b)
                node.position = screen(Vec(f.x, f.y))
                node.size = CGSize(width: CGFloat(f.w) * unit, height: CGFloat(f.h) * unit)
                node.zPosition = depth(Maqueta.sortY(b))
                guard let icon = node.children.first as? SKSpriteNode else { continue }
                let sleeper = who.first.flatMap { world.bichito($0) }
                let state = sleeper.flatMap { Look.bubble(mood: $0.mood, needs: $0.needs, dizzy: $0.dizzy) }
                icon.isHidden = state == nil || !level.showsIcons
                if let state, let sleeper {
                    icon.texture = Sprites.shared.texture(state, accent: Palette.of(sleeper.recipe).colors[5])
                    icon.position = CGPoint(x: node.size.width / 2, y: -CGFloat(m) * unit + 4)
                }
            }
        }
        for (id, node) in buildingNodes where !alive.contains(id) {
            node.removeFromParent()
            buildingNodes[id] = nil
        }
        // Only what is on screen is kept, once other levels or places pile up.
        if buildingTextures.count > used.count + 32 { buildingTextures = buildingTextures.filter { used.contains($0.key) } }
    }

    private func makeFood(_ id: Int) -> SKNode {
        let t = Sprites.shared.texture(world.foods.first { $0.id == id }?.kind ?? .fruta)
        let n = SKSpriteNode(texture: t, size: CGSize(width: t.size().width * pixel, height: t.size().height * pixel))
        // Centred on its world point, 6 whole pixels up from the shadow row, so it never straddles device pixels.
        n.anchorPoint = CGPoint(x: 0.5, y: 6 / t.size().height)
        return n
    }

    /// A 6 pt dot of its palette's base colour.
    private func makeDot(_ id: Int) -> SKNode {
        let n = SKShapeNode(circleOfRadius: 3)
        let c = world.bichito(id).map { Look.dot($0.recipe) } ?? RGBA(hex: 0x2B2A33)
        n.fillColor = UIColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
        n.strokeColor = .clear
        return n
    }

    /// An egg rocks now and then (`speed` hurries it); its first child is the crack, shown just before it hatches.
    private func makeEgg() -> SKNode {
        let n = SKShapeNode(ellipseOf: CGSize(width: 8 * pixel, height: 10 * pixel))
        n.fillColor = UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
        n.strokeColor = Ink.ink.withAlphaComponent(0.25)
        let path = CGMutablePath(), p = pixel
        path.move(to: CGPoint(x: -4 * p, y: 0))
        for (k, x) in [-2, 0, 2, 4].enumerated() { path.addLine(to: CGPoint(x: CGFloat(x) * p, y: k % 2 == 0 ? p : -p)) }
        let crack = SKShapeNode(path: path)
        crack.strokeColor = Ink.ink.withAlphaComponent(0.6)
        crack.lineWidth = max(1, p / 2)
        crack.isHidden = true
        n.addChild(crack)
        let rock = SKAction.sequence([.rotate(toAngle: 0.2, duration: 0.08), .rotate(toAngle: -0.2, duration: 0.16),
                                      .rotate(toAngle: 0, duration: 0.08)])
        n.run(.repeatForever(.sequence([.wait(forDuration: 2, withRange: 1.5), rock, rock])))
        return n
    }

    /// The shell bursts: the egg swells, flashes white and fades while the chick (already in the world) appears there.
    private static func hatch(_ n: SKNode) {
        n.removeAllActions()
        n.speed = 1
        n.zRotation = 0
        n.run(.sequence([.group([.scale(to: 1.6, duration: 0.25), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
    }

    /// DESIGN.md `Note`: a `card` slip of 20×16 u, turned ±6° (by id, so it keeps its tilt) with a shadow under it.
    private func makeNote(_ id: Int) -> SKNode {
        let size = CGSize(width: 20 * pixel, height: 16 * pixel)
        let n = SKShapeNode(rectOf: size, cornerRadius: pixel)
        n.fillColor = .white
        n.strokeColor = Ink.ink.withAlphaComponent(0.15)
        n.zRotation = (id % 2 == 0 ? 6 : -6) * .pi / 180
        let shadow = SKShapeNode(rectOf: size, cornerRadius: pixel)
        shadow.fillColor = Ink.ink.withAlphaComponent(0.12)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: pixel, y: -pixel)
        shadow.zPosition = -0.01
        n.addChild(shadow)
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
        let reach = target.flatMap { world.bichito($0) }.map { $0.recipe.radius * Double(unit) + 12 } ?? 0
        touch = Touch(at: Vec(Double(p.x), Double(p.y)), time: t.timestamp, target: target, foodMode: foodMode, reach: reach)
        finger = t
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = finger, touches.contains(t), var g = touch, let view else { return }
        let p = t.location(in: view)
        let action = g.move(to: Vec(Double(p.x), Double(p.y)), time: t.timestamp)
        follow.after(action)
        switch action {
        case let .grab(id):
            // Taken where the finger is now, so it doesn't jump by the bit the finger moved before grabbing.
            if let b = world.bichito(id) { grabOffset = b.pos - worldPoint(p) }
            world.grab(id)
            Haptics.tap()
        case let .rub(id): pet(id)
        default: break
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
        case let .peek(id): onPeek?(id); Haptics.tap()
        case .close:
            if let id = world.note(at: worldPoint(t.location(in: view)), pad: Double(8 / unit)) { onNote?(id); Haptics.tap() } else { onPeek?(nil) }
        case .feed:
            let gone = Set(world.notes.map(\.bichito.id))
            world.dropFood(at: worldPoint(t.location(in: view)), kind: foodKind)
            // Its favourite at the note brought it back: it falls in triumphantly, like a new one from the editor.
            for b in world.bichitos where gone.contains(b.id) { dropping.insert(b.id) }
            Haptics.tap()
        default: break
        }
        if g.isDrag, let id = g.target {
            // Throw with the finger's speed, capped so a wild flick doesn't cross the whole map.
            var v = g.velocity(at: t.timestamp) * Double(1 / unit)
            if v.length > 2000 { v = v.unit * 2000 }
            world.release(id, velocity: v)
            Haptics.fire(.toss)
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

/// One bichito on screen: sprite (with its pixel shadow), name under it, state icon or phrase bubble over it.
/// Name, icon and bubble keep their size on screen at any zoom; only their anchors follow the sprite.
final class BichitoNode: SKNode {
    private let sprite = SKSpriteNode()
    /// The name in the pixel font (DESIGN.md "Tipografía"): ×2 at Calle, ×3 at Cerca.
    private let label = SKSpriteNode()
    private let bubble = SKShapeNode()
    private let bubbleText = SKLabelNode()
    /// The pixel state icon, bare over the head (DESIGN.md "Los dos mundos": no soft bubble around pixel art).
    private let icon = SKSpriteNode()
    /// Points per icon pixel: fixed on screen, an integer so the pixels stay square.
    private static let iconScale: CGFloat = 2
    private let recipe: Recipe
    /// Its rest-pose pixels, for where its head is.
    private let rest: PixelGrid
    private var pixel: CGFloat = 2
    private var spring = Spring()
    private var legPhase = 0.0
    private var blinkIn = Double.random(in: 1...4)
    private var blinkLeft = 0.0
    private var lastVel: Vec
    private var lastMood: Bichito.Mood
    private var key: SpriteKey?
    private var shownIcon: Look.Icon?
    var language = Language.es
    /// Zoom level: decides whether the name, the state icon and phrases show.
    var level = Camera.Level.district {
        didSet {
            guard level != oldValue else { return }
            label.isHidden = !level.showsWords
            sizeLabel()
            if talk != nil { talk?.shown = -1 } else { show(icon: shownIcon) } // redrawn for the new level
        }
    }
    /// `-screenshot-talk` (CI): every bubble becomes a phrase and stays up.
    static let alwaysTalk = CommandLine.arguments.contains("-screenshot-talk")
    /// A phrase. While its bubble has no room it waits, silent and with the clock stopped, up to `patience`;
    /// then it is heard and revealed in step with the babble.
    private struct Talk {
        let text: String, times: [Double], id: Int
        var clock = 0.0, shown = -1, waited = 0.0
        var started = false, visible = false
    }
    private var talk: Talk?
    private static let patience = alwaysTalk ? 600.0 : 3
    /// Set every frame by the scene's `LabelLayout`: another bubble is in the way.
    var bubbleBlocked = false
    /// Where the name sits when nothing is in its way.
    private var nameAnchor = CGPoint.zero
    private var bubbleSize = CGSize(width: 30, height: 24)
    private static let bubbleMaxWidth: CGFloat = 120
    private static let bubbleFont: UIFont = {
        let font = UIFont.systemFont(ofSize: 13, weight: .bold)
        return UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: 13)
    }()
    private var shownName = ""

    init(_ b: Bichito, pixel: CGFloat) {
        recipe = b.recipe
        rest = Generator.render(b.recipe)
        lastVel = b.vel
        lastMood = b.mood
        super.init()
        sprite.anchorPoint = CGPoint(x: 0.5, y: 1 / CGFloat(Sprites.height)) // feet on the node's origin, shadow below
        addChild(sprite)

        show(name: b.name)
        label.anchorPoint = CGPoint(x: 0.5, y: 1)
        label.zPosition = 50
        label.isHidden = !level.showsWords
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

        icon.anchorPoint = CGPoint(x: 0.5, y: 0)
        icon.size = CGSize(width: CGFloat(Look.Icon.canvas) * BichitoNode.iconScale, height: CGFloat(Look.Icon.canvas) * BichitoNode.iconScale)
        icon.zPosition = 100
        icon.isHidden = true
        addChild(icon)
        layout(pixel: pixel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func layout(pixel: CGFloat) {
        self.pixel = pixel
        sprite.size = CGSize(width: CGFloat(Sprites.width) * pixel, height: CGFloat(Sprites.height) * pixel)
        let at = Look.anchors(rest, pixel: Double(pixel))
        nameAnchor = CGPoint(x: 0, y: at.name)
        label.position = nameAnchor
        bubble.position = CGPoint(x: 0, y: at.bubble)
        icon.position = bubble.position
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

    private func show(name: String) {
        shownName = name
        label.texture = Sprites.shared.texture(name: name)
        sizeLabel()
    }

    private func sizeLabel() {
        guard let size = label.texture?.size() else { return }
        let k: CGFloat = level == .close ? 3 : 2
        label.size = CGSize(width: size.width * k, height: size.height * k)
    }

    /// A happy squash: the spring bounces it back.
    func squish() { spring.kick(-5) }

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
            .run { [weak self] in
                self?.spring.kick(-8)
                MainActor.assumeIsolated { Haptics.fire(.land) } // SpriteKit runs actions on the main thread
            },
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
        let state = Look.bubble(mood: b.mood, needs: b.needs, dizzy: b.dizzy, moving: moving)
        if var t = talk, !t.started, bubbleBlocked { // waits for room, showing the icon meanwhile
            t.waited += dt
            talk = t.waited < BichitoNode.patience ? t : nil
            if talk != nil { return }
        }
        if var t = talk {
            if !t.started {
                t.started = true
                Speaker.shared.say(t.text, voice: recipe.voice, id: t.id)
            }
            t.clock += dt
            if t.clock < t.times[t.times.count - 1] + (BichitoNode.alwaysTalk ? 600 : 2) {
                let shown = t.times.dropLast().filter { $0 <= t.clock }.count
                // Below Calle the phrase is still heard, but the bubble keeps the state icon; so it does
                // while another bubble is in the way.
                let visible = level.showsWords && !bubbleBlocked
                if shown != t.shown || visible != t.visible {
                    if visible { showBubble(t.text, revealed: shown) } else { show(icon: state) }
                }
                t.shown = shown
                t.visible = visible
                talk = t
                return
            }
            talk = nil
            shownIcon = state
            show(icon: state)
        }
        if state != shownIcon {
            shownIcon = state
            show(icon: state)
            if state != nil { startTalking(b) }
        }
    }

    /// Voice (#14): now and then, only on screen, a phrase replaces the icon and appears in step with the babble.
    private func startTalking(_ b: Bichito) {
        guard BichitoNode.alwaysTalk || Double.random(in: 0..<1) < 0.35,
              let scene, CGRect(origin: .zero, size: scene.size).contains(position) else { return }
        let line = Phrases.say(mood: b.mood, needs: b.needs, dizzy: b.dizzy, personality: recipe.personality,
                               seed: .random(in: 0...UInt64.max), language: language)
        talk = Talk(text: line, times: Babble.timeline(line, voice: recipe.voice), id: b.id)
        write(line, revealed: 0) // sized now, so the layout knows its room before it shows
        bubbleBlocked = true // until the scene's layout has looked
    }

    // MARK: - Label layout (#77)

    /// The whole bubble with its tail, in scene points, while there is a phrase for it at this level.
    var bubbleFrame: CGRect? {
        guard talk != nil, level.showsWords, !isHidden else { return nil }
        return CGRect(x: position.x - bubbleSize.width / 2, y: position.y + bubble.position.y,
                      width: bubbleSize.width, height: bubbleSize.height + 6)
    }

    /// Who keeps the bubble when two touch: one already talking (the longest first), else the one waiting longest.
    var bubbleRank: Double { talk.map { $0.started ? 1e6 + $0.clock : $0.waited } ?? -1 }

    /// The name where it sits with nothing in its way, in scene points; nil when names don't show.
    var nameFrame: CGRect? {
        guard level.showsWords, !isHidden else { return nil }
        let s = label.size
        return CGRect(x: position.x + nameAnchor.x - s.width / 2, y: position.y + nameAnchor.y - s.height, width: s.width, height: s.height)
    }

    /// Moves the name to `r` from `LabelLayout`, or hides it for `.null`.
    func placeName(_ r: CGRect) {
        label.isHidden = r.isNull
        if !r.isNull { label.position = CGPoint(x: r.midX - position.x, y: r.maxY - position.y) }
    }

    private func show(icon state: Look.Icon?) {
        bubble.isHidden = true
        icon.isHidden = state == nil || !level.showsIcons
        if let state { icon.texture = Sprites.shared.texture(state, accent: Palette.of(recipe).colors[5]) }
    }

    private func showBubble(_ text: String, revealed: Int) {
        icon.isHidden = true
        bubble.isHidden = !level.showsIcons
        write(text, revealed: revealed)
    }

    /// The first `revealed` characters are drawn; the rest are laid out but clear, so the bubble never jumps.
    private func write(_ text: String, revealed: Int) {
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
        // SKLabelNode wraps a little differently from boundingRect: take whichever is bigger.
        let label = bubbleText.frame.size
        let size = CGSize(width: max(30, ceil(max(box.width, label.width)) + 16),
                          height: max(24, ceil(max(box.height, label.height)) + 10))
        if size != bubbleSize {
            bubbleSize = size
            shapeBubble()
        }
    }
}
