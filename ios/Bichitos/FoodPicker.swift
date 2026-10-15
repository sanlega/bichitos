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
                .background(Capsule().fill(.white).shadow(color: Color.ink.opacity(0.08), radius: 8, y: 4))
                .allowsHitTesting(false)
            HStack(spacing: 6) {
                ForEach(Food.Kind.allCases, id: \.self) { k in
                    Button {
                        kind = k
                        Haptics.tap()
                    } label: {
                        Image(decorative: Sprites.image(k.grid, k.palette), scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: CGFloat(Food.canvas * 3), height: CGFloat((Food.canvas + 1) * 3))
                            .frame(width: 44, height: 48)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(k == kind ? Color.brand.opacity(0.18) : Color.ink.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(k == kind ? Color.brand : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(k.name(.es))
                    .accessibilityAddTraits(k == kind ? .isSelected : [])
                }
                Button(action: done) {
                    Text("Hecho")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Capsule().fill(Color.brand))
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white)
                    .shadow(color: Color.ink.opacity(0.08), radius: 8, y: 4)
            )
        }
    }
}
