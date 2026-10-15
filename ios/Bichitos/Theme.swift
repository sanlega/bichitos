import SwiftUI

/// DESIGN.md "La interfaz": colour tokens, button styles, `Chip` and `NeedBar`, shared by every view.
extension Color {
    static let mist = Color(uiColor: Ink.mist)
    static let ink = Color(uiColor: Ink.ink)
    // DESIGN.md says 55%, which is only 3.4:1 on white; 70% clears 4.5:1 on card and on mist (ThemeTests).
    static let inkDim = Color(uiColor: Ink.ink).opacity(0.7)
    static let hairline = Color(uiColor: Ink.ink).opacity(0.1)
    static let fill = Color(uiColor: Ink.ink).opacity(0.06)
    static let card = Color.white
    static let accent = Color(uiColor: Ink.accent)
    static let brand = accent // old name, kept for branches in flight
    static let hunger = Color(hex: 0xFFA45B)
    static let sleep = Color(hex: 0x9C8FE0)
    static let love = Color(hex: 0xFF7FA8)
    static let warmLight = Color(hex: 0xFFD27A)

    init(_ c: RGBA) {
        self.init(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// Soft, diffuse shadow for everything that floats over the map.
    func floating() -> some View { shadow(color: Color.ink.opacity(0.08), radius: 8, y: 4) }
}

/// Press feedback shared by all buttons: 0.94 with a spring and a light haptic; 35% when disabled.
private struct Press: ViewModifier {
    let pressed: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
            .opacity(enabled ? (pressed && reduceMotion ? 0.7 : 1) : 0.35)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.7), value: pressed)
            .onChange(of: pressed) { _, now in if now { Haptics.tap() } }
    }
}

/// Principal: `accent` capsule, `ink` text 17 Heavy, 50 tall.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .heavy))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(Color.accent))
            .contentShape(Capsule())
            .modifier(Press(pressed: configuration.isPressed))
    }
}

/// Secundario: `fill` capsule, `ink` text 15 Semibold, 44 tall.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color.fill))
            .contentShape(Capsule())
            .modifier(Press(pressed: configuration.isPressed))
    }
}

/// Icono: 44 pt circle, `fill` inside sheets and the tray, `card` with a shadow over the map.
/// `accent` marks the principal button or an active mode.
struct IconButtonStyle: ButtonStyle {
    var background = Color.fill
    var size: CGFloat = 44
    var shadow = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .semibold))
            .imageScale(.medium)
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(background).shadow(color: Color.ink.opacity(shadow ? 0.08 : 0), radius: 8, y: 4))
            .contentShape(Circle())
            .modifier(Press(pressed: configuration.isPressed))
    }
}

/// Chip: `hairline` border; selected = `ink` fill with `card` text.
struct ChipButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(selected ? Color.card : Color.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.ink : Color.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .modifier(Press(pressed: configuration.isPressed))
    }
}

struct Chip: View {
    let label: String
    var swatch: Color? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let swatch {
                    Circle().fill(swatch).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.card.opacity(selected ? 0.6 : 0)))
                }
                Text(label)
            }
        }
        .buttonStyle(ChipButtonStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The three needs, with their icon and colour.
enum Need: CaseIterable {
    case hunger, sleep, love

    var name: String {
        switch self {
        case .hunger: "Comida"
        case .sleep: "Descanso"
        case .love: "Cariño"
        }
    }

    var symbol: String {
        switch self {
        case .hunger: "fork.knife"
        case .sleep: "moon.fill"
        case .love: "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .hunger: .hunger
        case .sleep: .sleep
        case .love: .love
        }
    }

    func value(_ needs: Bichito.Needs) -> Double {
        switch self {
        case .hunger: needs.hunger
        case .sleep: needs.sleep
        case .love: needs.affection
        }
    }
}

/// One need as a bar with its number (DESIGN.md "Accesibilidad": never only the sprite's look).
/// `fill` track 8 tall, radius 4, filled in the need's colour; under 25% the fill turns `accent`.
struct NeedBar: View {
    let need: Need
    let value: Double

    init(_ need: Need, value: Double) {
        self.need = need
        self.value = value
    }

    private var percent: Int { Int((min(max(value, 0), 1) * 100).rounded()) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: need.symbol)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(need.color)
                .frame(width: 24)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.fill)
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(value < 0.25 ? Color.accent : need.color)
                            .frame(width: g.size.width * CGFloat(percent) / 100)
                    }
                }
            Text("\(percent)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.ink)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(need.name)
        .accessibilityValue("\(percent) de 100")
    }
}
