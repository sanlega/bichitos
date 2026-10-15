import SwiftUI

/// DESIGN.md `BichitoCard` (long press): big live sprite, name (renamable), description, personality,
/// needs as bars with numbers, friends and rivals by affinity, and family.
struct BichitoCard: View {
    let scene: WorldScene
    let id: Int
    @State private var name = ""

    var body: some View {
        // The world is not observable; re-read it every second so the bars stay live.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let b = scene.world.bichito(id) {
                card(b)
            } else {
                Text(es ? "Se ha escapado…" : "It ran away…")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.card)
        .foregroundStyle(Color.ink)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .onAppear { name = scene.world.bichito(id)?.name ?? "" }
        .onDisappear(perform: rename)
    }

    private var es: Bool { scene.world.language == .es }

    private func card(_ b: Bichito) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LiveSprite(recipe: b.recipe)
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.mist))
                VStack(alignment: .leading, spacing: 8) {
                    TextField(es ? "Nombre" : "Name", text: $name)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(rename)
                        .onChange(of: name) { _, typed in if typed.count > 16 { name = String(typed.prefix(16)) } }
                        .accessibilityLabel(es ? "Nombre" : "Name")
                    Text(b.description)
                        .font(.system(.subheadline, design: .rounded, weight: .medium).italic())
                        .foregroundStyle(Color.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Gene.personality.label(b.recipe.choice(.personality)).capitalized)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.card)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
                        .accessibilityLabel((es ? "Personalidad: " : "Personality: ") + "\(Gene.personality.label(b.recipe.choice(.personality)))")
                }
                section(es ? "Necesidades" : "Needs") {
                    ForEach(Need.allCases, id: \.self) { NeedBar($0, value: $0.value(b.needs), es: es) }
                }
                section(es ? "Amigos" : "Friends") { people(scene.world.friends(of: id), none: es ? "Todavía no tiene amigos." : "No friends yet.") }
                section(es ? "Rivales" : "Rivals") { people(scene.world.rivals(of: id), none: es ? "Se lleva bien con todos." : "Gets on with everyone.") }
                section(es ? "Padres" : "Parents") { people(scene.world.parents(of: id), none: es ? "Salió del editor." : "Came out of the editor.") }
                section(es ? "Crías" : "Children") { people(scene.world.children(of: id), none: es ? "Ninguna todavía." : "None yet.") }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(Color.inkDim)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    @ViewBuilder
    private func people(_ list: [Bichito], none: String) -> some View {
        if list.isEmpty {
            Text(none)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Color.inkDim)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(list) { other in
                        HStack(spacing: 6) {
                            Image(decorative: Sprites.shared.cgImage(SpriteKey(recipe: other.recipe, squash: Look.squashLevel(1),
                                                                               expression: .normal, legFrame: 0,
                                                                               wellbeing: Look.wellbeingLevel(other.needs))), scale: 1)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: CGFloat(Sprites.width), height: CGFloat(Sprites.height))
                            Text(other.name)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline))
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(1)
            }
        }
    }

    private func rename() { scene.rename(id, to: name) }
}
