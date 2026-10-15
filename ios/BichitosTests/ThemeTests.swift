import SwiftUI
import XCTest
@testable import Bichitos

/// DESIGN.md "Accesibilidad": interface text reaches 4.5:1 against what it sits on.
final class ThemeTests: XCTestCase {
    /// sRGB components of `top` laid over the opaque `base`.
    private func over(_ top: Color, _ base: Color) -> [CGFloat] {
        let t = rgba(top), b = rgba(base)
        return (0..<3).map { t[$0] * t[3] + b[$0] * (1 - t[3]) }
    }

    private func rgba(_ c: Color) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    private func luminance(_ rgb: [CGFloat]) -> CGFloat {
        let l = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
    }

    /// WCAG contrast ratio of `text` over `background` (itself laid over `base` when translucent).
    private func contrast(_ text: Color, on background: Color, base: Color = .card) -> CGFloat {
        let bg = over(background, base)
        let bgColor = Color(red: bg[0], green: bg[1], blue: bg[2])
        let a = luminance(over(text, bgColor)), b = luminance(bg)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func testTextPairsReachFourAndAHalf() {
        let pairs: [(String, Color, Color)] = [
            ("ink on card", .ink, .card),
            ("ink on mist", .ink, .mist),
            ("ink on fill", .ink, .fill),
            ("inkDim on card", .inkDim, .card),
            ("inkDim on mist", .inkDim, .mist),
            ("ink on accent", .ink, .accent),
            ("card on ink", .card, .ink),
        ]
        for (name, text, background) in pairs {
            let ratio = contrast(text, on: background)
            print("contrast \(name): \(String(format: "%.2f", ratio))")
            XCTAssertGreaterThanOrEqual(ratio, 4.5, name)
        }
    }

    func testWhiteOnAccentIsWhyTheButtonTextIsInk() {
        XCTAssertLessThan(contrast(.card, on: .accent), 3)
    }
}
