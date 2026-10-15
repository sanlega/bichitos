import SwiftUI

/// DESIGN.md `BarrioPill`: `card` capsule at the top left with the district under the camera and its population.
struct BarrioPill: View {
    @ObservedObject var scene: WorldScene
    var open: () -> Void

    var body: some View {
        let es = scene.world.language == .es
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scene.title)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                Text("\(scene.population)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.inkDim)
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.inkDim)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color.card).floating())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(scene.title), \(scene.population) bichitos")
        .accessibilityHint(es ? "Abre la lista de barrios" : "Opens the list of districts")
    }
}

/// DESIGN.md `BarrioPicker`: every district with its tint, population and affinity; locked ones with a lock and
/// what they still need. Tapping an open one sends the camera there.
struct BarrioPicker: View {
    let scene: WorldScene
    var dismiss: () -> Void

    var body: some View {
        let language = scene.world.language, es = language == .es, here = scene.here
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(es ? "Barrios" : "Districts")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .padding(.bottom, 8)
                ForEach(scene.world.barrioRows, id: \.district) { row in
                    let theme = District.themes[row.district]
                    Button {
                        guard row.missing == nil else { return } // not .disabled: it would fade the row past readable
                        scene.travel(to: row.district)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: theme.tint).opacity(row.missing == nil ? 1 : 0.35))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if row.missing != nil {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Color.ink.opacity(0.6))
                                    }
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language == .es ? theme.es : theme.en)
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .foregroundStyle(row.missing == nil ? Color.ink : Color.inkDim)
                                Text(BarrioPicker.affinity(theme.affine, es: es))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.inkDim)
                            }
                            Spacer(minLength: 8)
                            if let missing = row.missing {
                                Text(es ? "faltan \(missing) bichitos" : "\(missing) bichitos to go")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.inkDim)
                            } else {
                                Text("\(row.population)/\(World.capacity)")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(row.district == here ? Color.mist : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(row.district == here ? .isSelected : [])
                    .accessibilityHint(row.missing == nil ? (es ? "Lleva la cámara allí" : "Takes the camera there")
                                                          : (es ? "Bloqueado" : "Locked"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
        }
        .foregroundStyle(Color.ink)
        .background(Color.white)
        .presentationDetents([.fraction(0.72), .large]) // all 7 rows on a Pro Max; smaller phones scroll
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .presentationBackground(.white)
    }

    static func affinity(_ p: Recipe.Personality?, es: Bool) -> String {
        guard let p else { return es ? "De todos" : "Home to everyone" }
        let (s, e): (String, String) = switch p {
        case .curiosa: ("curiosas", "curious ones")
        case .nerviosa: ("nerviosas", "nervous ones")
        case .dormilona: ("dormilonas", "sleepyheads")
        case .hiperactiva: ("hiperactivas", "hyperactive ones")
        case .territorial: ("territoriales", "territorial ones")
        case .romantica: ("románticas", "romantic ones")
        }
        return es ? "Para las \(s)" : "For \(e)"
    }
}
