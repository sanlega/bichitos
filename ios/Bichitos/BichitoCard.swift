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
                Text("Se ha escapado…")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.white)
        .foregroundStyle(Color.ink)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .onAppear { name = scene.world.bichito(id)?.name ?? "" }
        .onDisappear(perform: rename)
    }

    private func card(_ b: Bichito) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LiveSprite(recipe: b.recipe)
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.mist))
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Nombre", text: $name)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(rename)
                        .onChange(of: name) { _, typed in if typed.count > 16 { name = String(typed.prefix(16)) } }
                        .accessibilityLabel("Nombre")
                    Text(b.description)
                        .font(.system(.subheadline, design: .rounded, weight: .medium).italic())
                        .foregroundStyle(Color.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Gene.personality.label(b.recipe.choice(.personality)).capitalized)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
                        .accessibilityLabel("Personalidad: \(Gene.personality.label(b.recipe.choice(.personality)))")
                }
                section("Necesidades") {
                    NeedBar(name: "Comida", value: b.needs.hunger)
                    NeedBar(name: "Descanso", value: b.needs.sleep)
                    NeedBar(name: "Cariño", value: b.needs.affection)
                }
                section("Amigos") { people(scene.world.friends(of: id), none: "Todavía no tiene amigos.") }
                section("Rivales") { people(scene.world.rivals(of: id), none: "Se lleva bien con todos.") }
                section("Padres") { people(scene.world.parents(of: id), none: "Salió del editor.") }
                section("Crías") { people(scene.world.children(of: id), none: "Ninguna todavía.") }
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

/// One need as a bar with its number (DESIGN.md "Accesibilidad": never only the sprite's look).
struct NeedBar: View {
    let name: String
    let value: Double

    private var percent: Int { Int((min(max(value, 0), 1) * 100).rounded()) }

    var body: some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .frame(width: 84, alignment: .leading)
            Capsule()
                .fill(Color.hairline)
                .frame(height: 10)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule()
                            .fill(value < 0.3 ? Color.brand : Color.ink)
                            .frame(width: g.size.width * CGFloat(percent) / 100)
                    }
                }
            Text("\(percent)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(percent) de 100")
    }
}
