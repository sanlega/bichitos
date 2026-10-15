import SwiftUI
import UIKit

/// The two switches of the settings sheet (DESIGN.md "Accesibilidad": voice and haptics go off separately).
/// Kept in UserDefaults under the keys the sheet's `@AppStorage` uses; both start on.
enum Settings {
    static let voiceKey = "voz", hapticsKey = "vibracion"
    /// Tests swap in their own suite.
    static var store = UserDefaults.standard

    static var voice: Bool {
        get { store.object(forKey: voiceKey) as? Bool ?? true }
        set { store.set(newValue, forKey: voiceKey) }
    }

    static var haptics: Bool {
        get { store.object(forKey: hapticsKey) as? Bool ?? true }
        set { store.set(newValue, forKey: hapticsKey) }
    }
}

/// Every haptic in the app goes through here, so «Vibración» turns them all off (DESIGN.md "Movimiento y háptica").
@MainActor
enum Haptics {
    enum Kind { case tap, pet, toss, land, success }

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notice = UINotificationFeedbackGenerator()

    /// What actually plays one; tests replace it to see what fired.
    static var play: @MainActor (Kind) -> Void = { kind in
        switch kind {
        case .tap: Haptics.light.impactOccurred()
        case .pet: Haptics.soft.impactOccurred()
        case .toss: Haptics.medium.impactOccurred()
        case .land: Haptics.rigid.impactOccurred(intensity: 0.5) // «rigid ligero»
        case .success: Haptics.notice.notificationOccurred(.success)
        }
    }

    static func fire(_ kind: Kind) { if Settings.haptics { play(kind) } }
    /// Buttons and small touches.
    static func tap() { fire(.tap) }
}

/// The gearshape at the top right: «Voz» and «Vibración».
struct SettingsSheet: View {
    let language: Language
    @AppStorage(Settings.voiceKey) private var voice = true
    @AppStorage(Settings.hapticsKey) private var haptics = true

    var body: some View {
        let es = language == .es
        VStack(alignment: .leading, spacing: 16) {
            Text(es ? "Ajustes" : "Settings")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .accessibilityAddTraits(.isHeader)
            toggle($voice, "speaker.wave.2.fill", es ? "Voz" : "Voice",
                   es ? "Los bichitos balbucean cuando hablan" : "Bichitos babble when they talk")
            toggle($haptics, "iphone.radiowaves.left.and.right", es ? "Vibración" : "Haptics",
                   es ? "Toques suaves al acariciar, lanzar y más" : "Gentle taps when you pet, throw and more")
            Spacer(minLength: 0)
        }
        .padding(24)
        .foregroundStyle(Color.ink)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.card)
    }

    private func toggle(_ on: Binding<Bool>, _ symbol: String, _ title: String, _ detail: String) -> some View {
        Toggle(isOn: on) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(.body, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.fill))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: .rounded, weight: .heavy))
                    Text(detail)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Color.accent)
    }
}

extension Animation {
    /// Interface spring (`response 0.35, damping 0.7`); with Reduce Motion, a 0.2 s fade.
    static func ui(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.7)
    }
}
