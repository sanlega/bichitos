import SwiftUI

/// DESIGN.md `NewsFeed`: the terrarium's news, newest first, with the bichitos involved in pixel ×2.
/// Tapping a story sends the camera there.
struct NewsFeed: View {
    let scene: WorldScene
    var dismiss: () -> Void

    var body: some View {
        // The world is not observable; re-read it every second so times and new stories stay live.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let world = scene.world, es = world.language == .es
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(es ? "Noticias" : "News")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 8)
                    if world.news.items.isEmpty {
                        Text(es ? "Todo tranquilo por ahora. Cuando pase algo, saldrá aquí."
                                : "All quiet for now. When something happens, it shows up here.")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(Color.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(world.news.items.enumerated()), id: \.offset) { _, item in
                        row(item, world)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .foregroundStyle(Color.ink)
        .background(Color.white)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .presentationBackground(.white)
    }

    private func row(_ item: News.Item, _ world: World) -> some View {
        let es = world.language == .es
        return Button {
            scene.travel(to: item.place)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(item.bichitos, id: \.self) { id in
                        if let b = world.bichito(id) ?? world.notes.first(where: { $0.bichito.id == id })?.bichito {
                            Image(decorative: Sprites.shared.cgImage(SpriteKey(recipe: b.recipe, squash: Look.squashLevel(1),
                                                                               expression: .normal, legFrame: 0,
                                                                               wellbeing: Look.wellbeingLevel(b.needs))), scale: 1)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: CGFloat(Sprites.width) * 2, height: CGFloat(Sprites.height) * 2)
                        }
                    }
                    if item.bichitos.isEmpty { // a new district: no one to show
                        Image(systemName: "newspaper.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.fill))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(world.newsText(item, world.language))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(News.ago(item.date, now: world.date, world.language))
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.inkDim)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(es ? "Lleva la cámara allí" : "Takes the camera there")
    }
}
