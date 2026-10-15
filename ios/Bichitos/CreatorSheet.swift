import SwiftUI

/// The editor (DESIGN.md `CreatorSheet`): big live preview, chips per gene, folded fine-tunes, dice, name, Soltar.
struct CreatorSheet: View {
    let language: Language
    /// Recipe, name and description of the bichito to drop into the world.
    let onRelease: (Recipe, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recipe: Recipe
    @State private var textSeed: UInt64
    @State private var name: String
    @State private var unfolded: Set<Gene> = []

    init(seed: UInt64 = .random(in: 1...UInt64.max), language: Language, onRelease: @escaping (Recipe, String, String) -> Void) {
        var rng = SeededRNG(seed: seed)
        let recipe = Recipe.random(using: &rng)
        let textSeed = rng.next()
        _recipe = State(initialValue: recipe)
        _textSeed = State(initialValue: textSeed)
        _name = State(initialValue: Names.make(seed: textSeed, language: language).name)
        self.language = language
        self.onRelease = onRelease
    }

    private var finalName: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? Names.make(seed: textSeed, language: language).name : typed
    }

    private var description: String { Names.make(seed: textSeed, language: language, name: finalName).description }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                preview
                naming
                ForEach(Gene.allCases, id: \.self) { row($0) }
            }
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { release }
        .background(Color.card)
        .foregroundStyle(Color.ink)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }

    private var preview: some View {
        ZStack(alignment: .bottomTrailing) {
            LiveSprite(recipe: recipe, pixel: 7)
                .frame(maxWidth: .infinity, minHeight: 260)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.mist))
            Dice(reseed: { recipe.seed = .random(in: 1...UInt64.max) }, randomise: randomiseAll)
                .padding(12)
        }
        .padding(.horizontal, 16)
    }

    private var naming: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Nombre", text: $name)
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onChange(of: name) { _, typed in if typed.count > 16 { name = String(typed.prefix(16)) } }
                Button(action: rerollText) { Image(systemName: "arrow.triangle.2.circlepath") }
                    .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Otro nombre y descripción")
            }
            Text(description)
                .font(.system(.subheadline, design: .rounded, weight: .medium).italic())
                .foregroundStyle(Color.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
    }

    private func row(_ gene: Gene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(gene.title)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(Color.inkDim)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<gene.count, id: \.self) { i in
                        Chip(label: gene.label(i),
                             swatch: gene == .palette ? Color(Palette.all[i].colors[3]) : nil,
                             selected: recipe.choice(gene) == i) { recipe.choose(i, gene) }
                    }
                }
                .padding(.horizontal, 16)
            }
            if !gene.fineTunes.isEmpty {
                DisclosureGroup(isExpanded: Binding(get: { unfolded.contains(gene) },
                                                    set: { if $0 { unfolded.insert(gene) } else { unfolded.remove(gene) } })) {
                    ForEach(gene.fineTunes, id: \.name) { tune in
                        HStack(spacing: 12) {
                            Text(tune.name)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .frame(width: 96, alignment: .leading)
                            Slider(value: $recipe[dynamicMember: tune.key], in: 0...1)
                                .tint(Color.ink)
                                .accessibilityLabel(tune.name)
                        }
                    }
                } label: {
                    Text("Ajustes finos")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.inkDim)
                }
                .tint(Color.inkDim)
                .padding(.horizontal, 16)
            }
        }
    }

    private var release: some View {
        Button {
            onRelease(recipe, finalName, description)
            dismiss()
        } label: {
            Text("Soltar")
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Color.card)
    }

    private func rerollText() {
        textSeed = .random(in: 1...UInt64.max)
        name = Names.make(seed: textSeed, language: language).name
    }

    private func randomiseAll() {
        var rng = SystemRandomNumberGenerator()
        recipe = Recipe.random(using: &rng)
        rerollText()
    }
}

/// DESIGN.md `Dice`: tap = new seed (same choices, other details), hold = everything random.
struct Dice: View {
    let reseed: () -> Void
    let randomise: () -> Void

    var body: some View {
        Button(action: reseed) { Image(systemName: "die.face.5.fill") }
            .buttonStyle(IconButtonStyle(background: Color.card, shadow: true))
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in randomise() })
            .accessibilityLabel("Dado")
            .accessibilityHint("Otros detalles. Mantén pulsado para hacerlo todo al azar.")
            .accessibilityAction(named: "Todo al azar") { randomise() }
    }
}
