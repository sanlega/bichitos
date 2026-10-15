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
            let es = scene.world.language == .es
            if let b = scene.world.bichito(id) {
                peek(b, es: es)
            } else {
                Text(es ? "Se ha escapado…" : "It ran away…")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
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

    private func peek(_ b: Bichito, es: Bool) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                LiveSprite(recipe: b.recipe, pixel: 3)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.mist))
                VStack(alignment: .leading, spacing: 8) {
                    Text(b.name)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .lineLimit(1)
                    ForEach(Need.allCases, id: \.self) { NeedBar($0, value: $0.value(b.needs), es: es) }
                }
            }
            HStack(spacing: 8) {
                action("hand.raised.fill", es ? "Acariciar" : "Pet") { scene.pet(id) }
                action("carrot.fill", es ? "Dar de comer" : "Feed") { scene.feed(id) }
                action("scope", es ? "Seguir" : "Follow") { scene.startFollowing(id) }
                action("list.bullet.rectangle.fill", es ? "Ficha" : "Card", openCard)
            }
        }
    }

    private func action(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(.body, weight: .semibold))
                    .frame(minHeight: 22) // symbols differ in height; keep the labels on one line
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
