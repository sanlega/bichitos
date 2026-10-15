import Foundation

/// The editor's chip rows (CONCEPT.md "El editor") and what picking a chip does to a recipe.
/// Pure, so it is tested without SwiftUI.
enum Gene: CaseIterable {
    case body, eyes, legs, palette, personality

    struct FineTune {
        let name: String
        let key: WritableKeyPath<Recipe, Double>
    }

    // shortcut: editor labels are Spanish only; add English when the app gets localised.
    var title: String {
        switch self {
        case .body: "Cuerpo"
        case .eyes: "Ojos"
        case .legs: "Patas"
        case .palette: "Paleta"
        case .personality: "Personalidad"
        }
    }

    var count: Int {
        switch self {
        case .body: Recipe.Body.allCases.count
        case .eyes: Recipe.Eyes.allCases.count
        case .legs: Recipe.legOptions.count
        case .palette: Recipe.paletteCount
        case .personality: Recipe.Personality.allCases.count
        }
    }

    /// Chip text for option `i`, in `allCases` order.
    func label(_ i: Int) -> String {
        switch self {
        case .body: ["gota", "alubia", "torre", "cuadradito", "pera", "estrella"][i]
        case .eyes: ["normales", "saltones", "cíclope", "tres", "adormilados"][i]
        case .legs: Recipe.legOptions[i] == 0 ? "sin patas" : "\(Recipe.legOptions[i]) patas"
        case .palette: Palette.all[i].name
        case .personality: ["curiosa", "nerviosa", "dormilona", "hiperactiva", "territorial", "romántica"][i]
        }
    }

    /// The optional sliders folded under each row.
    var fineTunes: [FineTune] {
        switch self {
        case .body: [.init(name: "Redondez", key: \.roundness), .init(name: "Altura", key: \.height), .init(name: "Bultos", key: \.bumps)]
        case .eyes: [.init(name: "Tamaño", key: \.eyeSize), .init(name: "Separación", key: \.eyeSpacing)]
        case .legs: [.init(name: "Largo", key: \.legLength)]
        case .palette, .personality: []
        }
    }
}

extension Recipe {
    /// Index of the chip selected in a row.
    func choice(_ gene: Gene) -> Int {
        switch gene {
        case .body: Body.allCases.firstIndex(of: body)!
        case .eyes: Eyes.allCases.firstIndex(of: eyes)!
        case .legs: Recipe.legOptions.firstIndex(of: legs) ?? 0
        case .palette: (palette % Recipe.paletteCount + Recipe.paletteCount) % Recipe.paletteCount
        case .personality: Personality.allCases.firstIndex(of: personality)!
        }
    }

    /// Picks chip `i` of a row; everything else (fine-tunes, seed) stays.
    mutating func choose(_ i: Int, _ gene: Gene) {
        switch gene {
        case .body: body = Body.allCases[i]
        case .eyes: eyes = Eyes.allCases[i]
        case .legs: legs = Recipe.legOptions[i]
        case .palette: palette = i
        case .personality: personality = Personality.allCases[i]
        }
    }
}
