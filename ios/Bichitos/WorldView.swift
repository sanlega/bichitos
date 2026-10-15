import SpriteKit
import SwiftUI
import UIKit

/// The map full screen, with the tray in the thumb zone.
struct WorldView: View {
    @ObservedObject var scene: WorldScene
    @State private var foodMode = false
    @State private var creating = false
    @State private var card: Int? // id of the bichito whose card is open

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .ignoresSafeArea()
                .sheet(isPresented: Binding(get: { card != nil }, set: { if !$0 { card = nil } })) {
                    if let card { BichitoCard(scene: scene, id: card) }
                }
            VStack(spacing: 8) {
                Text(scene.title)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.ink)
                if let news = scene.news {
                    Text(news)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.card).floating())
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.top, 8)
            .allowsHitTesting(false)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: scene.news)
            VStack {
                Spacer()
                Tray(foodMode: $foodMode, scare: { scene.scareEveryone() }, add: { creating = true })
                    .padding(.bottom, 16)
            }
        }
        .onChange(of: foodMode) { _, on in scene.foodMode = on }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in scene.scareEveryone() }
        .sheet(isPresented: $creating) {
            CreatorSheet(seed: CommandLine.arguments.contains("-screenshot") ? 11 : .random(in: 1...UInt64.max),
                         language: scene.world.language) { recipe, name, description in
                scene.drop(recipe, name: name, description: description)
            }
        }
        .onAppear {
            scene.onLongPress = { card = $0 }
            if CommandLine.arguments.contains("-screenshot-editor") { creating = true }
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
