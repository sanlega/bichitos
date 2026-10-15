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
                ForEach(scene.world.barrioRows, id: \.theme) { row in
                    let theme = District.themes[row.theme]
                    Button {
                        guard let place = row.place else { return } // not .disabled: it would fade the row past readable
                        scene.travel(to: place)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: theme.tint).opacity(row.place != nil ? 1 : 0.35))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if row.place == nil {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Color.ink.opacity(0.6))
                                    }
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language == .es ? theme.es : theme.en)
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .foregroundStyle(row.place != nil ? Color.ink : Color.inkDim)
                                Text(BarrioPicker.affinity(theme.affine, es: es))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.inkDim)
                            }
                            Spacer(minLength: 8)
                            if row.place != nil {
                                Text("\(row.population)/\(World.capacity)")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            } else if let affine = theme.affine {
                                // How affine the population is to it: the most affine one opens next.
                                Text("\(row.fans) \(BarrioPicker.name(affine, es: es, count: row.fans))")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.inkDim)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(row.place == here ? Color.mist : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(row.place == here ? .isSelected : [])
                    .accessibilityHint(row.place != nil ? (es ? "Lleva la cámara allí" : "Takes the camera there")
                                                        : (es ? "Bloqueado" : "Locked"))
                }
                if let n = scene.world.bichitosToNextDistrict {
                    Text(es ? "Con \(n) \(n == 1 ? "bichito" : "bichitos") más se abre un barrio nuevo: el más afín a tus bichitos."
                            : "\(n) more \(n == 1 ? "bichito opens" : "bichitos open") a new district: the one your bichitos like best.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 24)
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
        return es ? "Para las \(name(p, es: true, count: 2))" : "For \(name(p, es: false, count: 2))"
    }

    /// "territorial" / "territoriales", "sleepyhead" / "sleepyheads".
    static func name(_ p: Recipe.Personality, es: Bool, count: Int) -> String {
        let (one, many): (String, String) = switch p {
        case .curiosa: es ? ("curiosa", "curiosas") : ("curious one", "curious ones")
        case .nerviosa: es ? ("nerviosa", "nerviosas") : ("nervous one", "nervous ones")
        case .dormilona: es ? ("dormilona", "dormilonas") : ("sleepyhead", "sleepyheads")
        case .hiperactiva: es ? ("hiperactiva", "hiperactivas") : ("hyperactive one", "hyperactive ones")
        case .territorial: es ? ("territorial", "territoriales") : ("territorial one", "territorial ones")
        case .romantica: es ? ("romántica", "románticas") : ("romantic one", "romantic ones")
        }
        return count == 1 ? one : many
    }
}
