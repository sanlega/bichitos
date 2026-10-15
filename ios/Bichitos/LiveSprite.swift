import SwiftUI

/// DESIGN.md colour tokens for SwiftUI.
extension Color {
    static let mist = Color(uiColor: Ink.mist)
    static let ink = Color(uiColor: Ink.ink)
    static let inkDim = Color(uiColor: Ink.ink).opacity(0.55)
    static let hairline = Color(uiColor: Ink.ink).opacity(0.1)
    static let brand = Color(uiColor: Ink.accent)

    init(_ c: RGBA) {
        self.init(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }
}

/// A bichito alive outside the world: it breathes, blinks and hops when its recipe changes.
/// Driven by its own little simulation (never by SwiftUI animations); pixels are whole squares, never smoothed.
struct LiveSprite: View {
    let recipe: Recipe
    var pixel: CGFloat = 6
    @State private var life = Life()

    var body: some View {
        TimelineView(.animation) { context in
            Image(decorative: life.frame(recipe, at: context.date.timeIntervalSinceReferenceDate), scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: CGFloat(Sprites.width) * pixel, height: CGFloat(Sprites.height) * pixel)
        }
        .onChange(of: recipe) { old, new in life.react(from: old, to: new) }
        .accessibilityHidden(true)
    }
}

/// State of the animation. A plain class: it changes every frame and must not trigger SwiftUI updates.
final class Life {
    // Its own cache, dropped on every recipe change, so slider drags don't fill the world's cache.
    private let sprites = Sprites()
    private var drawn: Recipe?
    private var spring = Spring()
    private var last: Double?
    private var blinkIn = 1.5, blinkLeft = 0.0
    private var reaction: Expression?
    private var reactionLeft = 0.0

    /// A new personality pulls its face and hops; another chip gives a small squash; sliders just redraw.
    func react(from old: Recipe, to new: Recipe) {
        if old.personality != new.personality {
            reaction = Look.reaction(new.personality)
            reactionLeft = 1.2
            spring.kick(4)
        } else if Gene.allCases.contains(where: { old.choice($0) != new.choice($0) }) || old.seed != new.seed {
            spring.kick(-3)
        }
    }

    func frame(_ recipe: Recipe, at t: Double) -> CGImage {
        let dt = last.map { min(max(t - $0, 0), 0.1) } ?? 0
        last = t
        spring.step(dt)
        blinkIn -= dt
        if blinkIn <= 0 {
            blinkLeft = 0.15
            blinkIn = Double.random(in: 2...4)
        }
        blinkLeft -= dt
        reactionLeft -= dt
        if reactionLeft <= 0 { reaction = nil }
        let breath = 0.12 * sin(t * 2 * .pi / 2.4)
        let face = reaction ?? (blinkLeft > 0 ? .blink : .normal)
        if recipe != drawn {
            sprites.removeAll()
            drawn = recipe
        }
        return sprites.cgImage(SpriteKey(recipe: recipe, squash: Look.squashLevel(spring.squash + breath), expression: face,
                                         legFrame: 0, wellbeing: Look.wellbeingSteps))
    }
}
