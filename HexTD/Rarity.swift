import SwiftUI

/// Tiers de raridade (GDD §4). Cada tier libera multiplicador de stat base e,
/// em tiers específicos, slots de habilidade. Custo em cards cresce ~geométrico.
enum Rarity: Int, CaseIterable, Codable {
    case cinza, verde, azul, roxa, laranja, vermelha

    var nome: String {
        switch self {
        case .cinza:    return "Comum"
        case .verde:    return "Incomum"
        case .azul:     return "Rara"
        case .roxa:     return "Épica"
        case .laranja:  return "Lendária"
        case .vermelha: return "Mítica"
        }
    }

    var color: Color {
        switch self {
        case .cinza:    return Color(white: 0.62)
        case .verde:    return Color(red: 0.35, green: 0.80, blue: 0.40)
        case .azul:     return Color(red: 0.30, green: 0.60, blue: 0.95)
        case .roxa:     return Color(red: 0.68, green: 0.40, blue: 0.92)
        case .laranja:  return Color(red: 0.98, green: 0.60, blue: 0.20)
        case .vermelha: return Color(red: 0.92, green: 0.30, blue: 0.32)
        }
    }

    /// Multiplicador de stat base liberado pelo tier (§4). Fórmula ∏(1+bᵢ) do item 4 do
    /// brief — coeficientes `statBonuses` tunáveis em progression.json. tier = rawValue
    /// (0=Comum … 5=Mítica). Defaults: 1.0 / 1.6 / 2.48 / 3.72 / 5.39 / 7.55.
    var statMult: Double { Progression.rarityStat(tier: rawValue) }

    /// Slots de habilidade liberados (§4): Slot 1 → Azul, Slot 2 → Laranja.
    var abilitySlots: Int {
        switch self {
        case .cinza, .verde:      return 0
        case .azul, .roxa:        return 1
        case .laranja, .vermelha: return 2
        }
    }

    /// Custo em cards para subir DESTE tier ao próximo (nil = já é máximo).
    /// Progressão geométrica do §4: 3 / 6 / 12 / 24 / 48.
    var upgradeCost: Int? {
        switch self {
        case .cinza:    return 3
        case .verde:    return 6
        case .azul:     return 12
        case .roxa:     return 24
        case .laranja:  return 48
        case .vermelha: return nil
        }
    }

    var next: Rarity? { Rarity(rawValue: rawValue + 1) }
}
