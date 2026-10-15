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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

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
                        .accessibilityAction(named: "Acariciar") { scene.pet(b.id) }
                        .accessibilityAction(named: "Lanzar") { scene.toss(b.id) }
                        .accessibilityAction(named: "Ficha") { card = b.id }
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
                BarrioPill(scene: scene) { picking = true }
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
                    .id(scene.world.toastText(event)) // a new event slides in fresh instead of morphing the old one
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: scene.toast)
            .sheet(isPresented: $picking) { BarrioPicker(scene: scene) { picking = false } }
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
                    FoodPicker(kind: $foodKind) { foodMode = false }
                        .padding(.bottom, 16)
                } else {
                    if let id = peek {
                        BichitoPeek(scene: scene, id: id, openCard: { card = id; peek = nil }, close: { peek = nil })
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Tray(foodMode: $foodMode, scare: { scene.scareEveryone() }, add: { creating = true })
                        .padding(.bottom, 16)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: peek)
        }
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
            if CommandLine.arguments.contains("-screenshot-editor") { creating = true }
            if CommandLine.arguments.contains("-screenshot-barrios") { // after the staged world is populated
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { picking = true }
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

/// DESIGN.md `Tray`: floating `card`, radius 20, icon buttons with the principal one in the centre.
struct Tray: View {
    @Binding var foodMode: Bool
    var scare: () -> Void
    var add: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button { foodMode.toggle() } label: { Image(systemName: "carrot.fill") }
                .buttonStyle(IconButtonStyle(background: foodMode ? Color.accent : Color.fill))
                .accessibilityLabel("Modo comida")
                .accessibilityAddTraits(foodMode ? .isSelected : [])
            Button(action: add) { Image(systemName: "plus") }
                .buttonStyle(IconButtonStyle(background: Color.accent, size: 56))
                .accessibilityLabel("Nuevo bichito")
            Button(action: scare) { Image(systemName: "bolt.fill") }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Asustar")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.card).floating())
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
    /// What VoiceOver says: name and current state, «Pocholo, durmiendo, con hambre».
    var voiceLabel: String {
        let state: String
        switch mood {
        case .wander: state = "paseando"
        case .sleep: state = "durmiendo"
        case .eat: state = "comiendo"
        case .love: state = "enamorado"
        case .fight: state = "peleando"
        case .chase: state = "persiguiendo a alguien"
        case .flee: state = "huyendo"
        case .imitate: state = "imitando a alguien"
        case .scared: state = "asustado"
        case .happy: state = "contento"
        case .held: state = "en tu mano"
        case .incubating: state = "incubando"
        }
        var parts = [name, dizzy > 0 ? "mareado" : state]
        if needs.hunger < 0.3 { parts.append("con hambre") }
        if needs.sleep < 0.3 { parts.append("con sueño") }
        if needs.affection < 0.3 { parts.append("quiere mimos") }
        return parts.joined(separator: ", ")
    }
}
