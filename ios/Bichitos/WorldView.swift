import SpriteKit
import SwiftUI
import UIKit

/// The map full screen, with the tray in the thumb zone.
struct WorldView: View {
    @ObservedObject var scene: WorldScene
    @State private var foodMode = false
    @State private var foodKind = Food.Kind.fruta
    @State private var creating = false
    @State private var card: Int? // id of the bichito whose card is open
    @State private var peek: Int? // id of the bichito whose peek is up
    @State private var picking = false // BarrioPicker is open
    @State private var reading = false // NewsFeed is open
    @State private var setting = false // SettingsSheet is open

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var es: Bool { scene.world.language == .es }

    /// VoiceOver: an element over each bichito on screen, with the gestures as actions (DESIGN.md Accesibilidad).
    /// Re-read every second, like `BichitoPeek`: the world is not observable.
    private var bichitoElements: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ZStack {
                ForEach(scene.onScreen) { b in
                    Rectangle().fill(Color.clear)
                        .frame(width: b.frame.width, height: b.frame.height)
                        .position(x: b.frame.midX, y: b.frame.midY)
                        .accessibilityElement()
                        .accessibilityLabel(b.label)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { peek = b.id }
                        .accessibilityAction(named: es ? "Acariciar" : "Pet") { scene.pet(b.id) }
                        .accessibilityAction(named: es ? "Lanzar" : "Throw") { scene.toss(b.id) }
                        .accessibilityAction(named: es ? "Ficha" : "Card") { card = b.id }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea() // same space as the SpriteView
        .allowsHitTesting(false) // touches still reach the map
    }

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .ignoresSafeArea()
                .sheet(isPresented: Binding(get: { card != nil }, set: { if !$0 { card = nil } })) {
                    if let card { BichitoCard(scene: scene, id: card) }
                }
            if voiceOver { bichitoElements }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    BarrioPill(scene: scene) { picking = true }
                        .obstacle()
                    Spacer(minLength: 8)
                    Button { setting = true } label: { Image(systemName: "gearshape.fill") }
                        .buttonStyle(IconButtonStyle(background: Color.card, shadow: true))
                        .accessibilityLabel(es ? "Ajustes" : "Settings")
                        .obstacle()
                }
                if let event = scene.toast {
                    Button { scene.onToastTap?(event) } label: {
                        Text(scene.world.toastText(event))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.card).floating())
                    }
                    .buttonStyle(.plain)
                    .obstacle()
                    .id(scene.world.toastText(event)) // a new event slides in fresh instead of morphing the old one
                    .transition(reduceMotion ? AnyTransition.opacity : .move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .animation(.ui(reduceMotion: reduceMotion), value: scene.toast)
            .sheet(isPresented: $picking) { BarrioPicker(scene: scene) { picking = false } }
            .sheet(isPresented: $reading) { NewsFeed(scene: scene) { reading = false } }
            .sheet(isPresented: $setting) { SettingsSheet(language: scene.world.language) }
            if foodMode {
                // Food mode marks the screen edge (DESIGN.md "Modos").
                Rectangle().strokeBorder(Color.accent, lineWidth: 3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            VStack(spacing: 8) {
                Spacer()
                // One mode at a time: in food mode the tray is the picker, and «Hecho» is the only way out.
                if foodMode {
                    FoodPicker(kind: $foodKind, language: scene.world.language) { foodMode = false }
                        .obstacle()
                        .padding(.bottom, 16)
                } else {
                    if let id = peek {
                        BichitoPeek(scene: scene, id: id, openCard: { card = id; peek = nil }, close: { peek = nil })
                            .obstacle()
                            .padding(.horizontal, 16)
                            .transition(reduceMotion ? AnyTransition.opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                    Tray(foodMode: $foodMode, es: es, scare: { scene.scareEveryone() }, add: { creating = true }, news: { reading = true })
                        .obstacle()
                        .padding(.bottom, 16)
                }
            }
            .animation(.ui(reduceMotion: reduceMotion), value: peek)
        }
        .onPreferenceChange(Obstacles.self) { scene.obstacles = $0 } // toast, peek, rotation, safe area
        .onChange(of: foodMode) { _, on in scene.foodMode = on; if on { peek = nil } }
        .onChange(of: foodKind) { _, k in scene.foodKind = k }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in scene.scareEveryone() }
        .sheet(isPresented: $creating) {
            CreatorSheet(seed: CommandLine.arguments.contains("-screenshot") ? 11 : .random(in: 1...UInt64.max),
                         language: scene.world.language, taken: scene.world.takenNames) { recipe, name, description in
                scene.drop(recipe, name: name, description: description)
            }
        }
        .onAppear {
            scene.onLongPress = { card = $0 }
            scene.onPeek = { peek = $0 }
            scene.onToastTap = { event in
                if let place = scene.world.news.place(of: event) { scene.travel(to: place) }
                reading = false
            }
            if CommandLine.arguments.contains("-screenshot-editor") { creating = true }
            if CommandLine.arguments.contains("-screenshot-settings") { setting = true }
            if CommandLine.arguments.contains("-screenshot-barrios") { // after the staged world is populated
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { picking = true }
            }
            if CommandLine.arguments.contains("-screenshot-news") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { reading = true }
            }
            if CommandLine.arguments.contains("-screenshot-food") { foodMode = true; foodKind = .croqueta }
            if CommandLine.arguments.contains("-screenshot-peek") { // the staged bichito with mixed needs
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { peek = scene.world.bichitos.first { !$0.affinity.isEmpty }?.id }
            }
            if CommandLine.arguments.contains("-screenshot-card") {
                // After the staged world is populated: the one with friends, rivals and family.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { card = scene.world.bichitos.first { !$0.affinity.isEmpty }?.id }
            }
        }
    }
}

/// DESIGN.md `Tray`: floating `card`, radius 20, icon buttons in the order «comida susto (+) noti mapa»;
/// the principal one sits in the centre once the map button (5th) lands.
struct Tray: View {
    @Binding var foodMode: Bool
    let es: Bool
    var scare: () -> Void
    var add: () -> Void
    var news: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button { foodMode.toggle() } label: { Image(systemName: "carrot.fill") }
                .buttonStyle(IconButtonStyle(background: foodMode ? Color.accent : Color.fill))
                .accessibilityLabel(es ? "Modo comida" : "Food mode")
                .accessibilityAddTraits(foodMode ? .isSelected : [])
            Button(action: scare) { Image(systemName: "bolt.fill") }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel(es ? "Asustar" : "Scare")
            Button(action: add) { Image(systemName: "plus") }
                .buttonStyle(IconButtonStyle(background: Color.accent, size: 56))
                .accessibilityLabel(es ? "Nuevo bichito" : "New bichito")
            Button(action: news) { Image(systemName: "newspaper.fill") }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel(es ? "Noticias" : "News")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.card).floating())
    }
}

/// #79: frames of the interface floating over the map, in window points, so names and bubbles keep out from under it.
struct Obstacles: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

extension View {
    func obstacle() -> some View {
        background(GeometryReader { g in Color.clear.preference(key: Obstacles.self, value: [g.frame(in: .global)]) })
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    // SwiftUI has no shake gesture; the key window sees the motion event first.
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}

extension Bichito {
    /// What VoiceOver says: name and current state, «Pocholo, durmiendo, con hambre» / «Pocholo, sleeping, hungry».
    func voiceLabel(_ language: Language) -> String {
        let es = language == .es
        let state: String
        switch mood {
        case .wander: state = es ? "paseando" : "wandering"
        case .sleep: state = es ? "durmiendo" : "sleeping"
        case .toBed: state = es ? "yendo a dormir" : "going to bed"
        case .eat: state = es ? "comiendo" : "eating"
        case .love: state = es ? "enamorado" : "in love"
        case .fight: state = es ? "peleando" : "fighting"
        case .chase: state = es ? "persiguiendo a alguien" : "chasing someone"
        case .flee: state = es ? "huyendo" : "running away"
        case .imitate: state = es ? "imitando a alguien" : "copying someone"
        case .scared: state = es ? "asustado" : "scared"
        case .happy: state = es ? "contento" : "happy"
        case .held: state = es ? "en tu mano" : "in your hand"
        case .incubating: state = es ? "incubando" : "incubating"
        }
        var parts = [name, dizzy > 0 ? (es ? "mareado" : "dizzy") : state]
        if needs.hunger < 0.3 { parts.append(es ? "con hambre" : "hungry") }
        if needs.sleep < 0.3 { parts.append(es ? "con sueño" : "sleepy") }
        if needs.affection < 0.3 { parts.append(es ? "quiere mimos" : "wants cuddles") }
        return parts.joined(separator: ", ")
    }
}
