import SwiftUI

/// The tray in food mode (DESIGN.md "Modos"): the five foods in pixel ×3 and «Hecho», under the hint.
struct FoodPicker: View {
    @Binding var kind: Food.Kind
    var done: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Toca el suelo para soltar comida")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.card).floating())
                .allowsHitTesting(false)
            HStack(spacing: 4) {
                ForEach(Food.Kind.allCases, id: \.self) { k in
                    Button { kind = k } label: {
                        Image(decorative: Sprites.image(k.grid, k.palette), scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: CGFloat(Food.canvas * 3), height: CGFloat((Food.canvas + 1) * 3))
                    }
                    .buttonStyle(IconButtonStyle(background: k == kind ? Color.accent : Color.fill)) // accent = chosen, like an active mode
                    .accessibilityLabel(k.name(.es))
                    .accessibilityAddTraits(k == kind ? .isSelected : [])
                }
                Button("Hecho", action: done)
                    .buttonStyle(PrimaryButtonStyle())
                    .fixedSize() // the principal style stretches; here it shares the row
                    .padding(.leading, 4)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.card).floating()
            )
        }
    }
}
