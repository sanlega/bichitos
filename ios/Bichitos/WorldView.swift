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
                    .foregroundStyle(Color(Ink.ink))
                    .allowsHitTesting(false)
                if let event = scene.toast {
                    Button { scene.onToastTap?(event) } label: {
                        Text(scene.world.toastText(event))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(Ink.ink))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(.white).shadow(color: Color(Ink.ink).opacity(0.08), radius: 8, y: 4))
                    }
                    .buttonStyle(.plain)
                    .id(scene.world.toastText(event)) // a new event slides in fresh instead of morphing the old one
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.top, 8)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: scene.toast)
            VStack {
                Spacer()
                Tray(foodMode: $foodMode, scare: { scene.scareEveryone() }, add: { creating = true })
                    .padding(.bottom, 8)
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

/// Floating bottom tray: white card, radius 20, round icon buttons.
struct Tray: View {
    @Binding var foodMode: Bool
    var scare: () -> Void
    var add: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            icon("carrot.fill", "Modo comida", fill: foodMode ? Color(Ink.ink) : Color(Ink.ink).opacity(0.06),
                 tint: foodMode ? .white : Color(Ink.ink)) {
                foodMode.toggle()
                Haptics.tap()
            }
            .accessibilityAddTraits(foodMode ? .isSelected : [])
            icon("bolt.fill", "Asustar", fill: Color(Ink.ink).opacity(0.06), tint: Color(Ink.ink), action: scare)
            icon("plus", "Nuevo bichito", fill: Color(Ink.accent), tint: .white, action: add)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
                .shadow(color: Color(Ink.ink).opacity(0.08), radius: 8, y: 4)
        )
    }

    private func icon(_ symbol: String, _ label: String, fill: Color, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
