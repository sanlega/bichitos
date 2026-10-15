import SwiftUI

/// DESIGN.md `BichitoPeek` (a tap on a bichito): compact card over the tray with its sprite, name, three
/// need bars and its actions. A tap on the ground or a swipe down closes it.
struct BichitoPeek: View {
    let scene: WorldScene
    let id: Int
    var openCard: () -> Void
    var close: () -> Void

    var body: some View {
        // The world is not observable; re-read it every second so the bars stay live.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let b = scene.world.bichito(id) {
                peek(b)
            } else {
                Text("Se ha escapado…")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding(16)
        .foregroundStyle(Color.ink)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
                .shadow(color: Color.ink.opacity(0.08), radius: 8, y: 4)
        )
        .gesture(DragGesture(minimumDistance: 20).onEnded { if $0.translation.height > 40 { close() } })
    }

    private func peek(_ b: Bichito) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                LiveSprite(recipe: b.recipe, pixel: 3)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.mist))
                VStack(alignment: .leading, spacing: 8) {
                    Text(b.name)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                    NeedBar(name: "Comida", value: b.needs.hunger)
                    NeedBar(name: "Descanso", value: b.needs.sleep)
                    NeedBar(name: "Cariño", value: b.needs.affection)
                }
            }
            HStack(spacing: 8) {
                action("hand.raised.fill", "Acariciar") { scene.pet(id) }
                action("carrot.fill", "Dar de comer") { scene.feed(id) }
                action("scope", "Seguir") { scene.startFollowing(id) }
                action("list.bullet.rectangle.fill", "Ficha", openCard)
            }
        }
    }

    private func action(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 22) // symbols differ in height; keep the labels on one line
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}
