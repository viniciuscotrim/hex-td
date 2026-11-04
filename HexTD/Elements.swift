import SwiftUI

/// Roda cíclica de 7 elementos (GDD §8). A ordem abaixo É a cadeia de força:
/// cada elemento é 2x contra o ANTERIOR e 0.5x contra o PRÓXIMO (ciclicamente).
///
/// Fonte de verdade = a TABELA do §8, não a sequência em prosa (que diverge):
///   Água>Fogo, Gelo>Água, Físico>Gelo, Veneno>Físico,
///   Arcana>Veneno, Natureza>Arcana, Fogo>Natureza
/// Isso dá O(n): 1 forte + 1 fraco por elemento, sem par mútuo.
enum Element: Int, CaseIterable {
    case fogo, agua, gelo, fisico, veneno, arcana, natureza

    var nome: String {
        switch self {
        case .fogo:     return "Fogo"
        case .agua:     return "Água"
        case .gelo:     return "Gelo"
        case .fisico:   return "Físico"
        case .veneno:   return "Veneno"
        case .arcana:   return "Arcana"
        case .natureza: return "Natureza"
        }
    }

    var icon: String {
        switch self {
        case .fogo:     return "🔥"
        case .agua:     return "💧"
        case .gelo:     return "❄️"
        case .fisico:   return "🗡️"
        case .veneno:   return "☠️"
        case .arcana:   return "🔮"
        case .natureza: return "🌿"
        }
    }

    var color: Color {
        switch self {
        case .fogo:     return Color(red: 0.95, green: 0.35, blue: 0.20)
        case .agua:     return Color(red: 0.25, green: 0.55, blue: 0.95)
        case .gelo:     return Color(red: 0.55, green: 0.85, blue: 0.95)
        case .fisico:   return Color(red: 0.70, green: 0.70, blue: 0.74)
        case .veneno:   return Color(red: 0.55, green: 0.80, blue: 0.25)
        case .arcana:   return Color(red: 0.70, green: 0.40, blue: 0.90)
        case .natureza: return Color(red: 0.20, green: 0.65, blue: 0.40)
        }
    }

    var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .fogo:     return (0.95, 0.35, 0.20)
        case .agua:     return (0.25, 0.55, 0.95)
        case .gelo:     return (0.55, 0.85, 0.95)
        case .fisico:   return (0.70, 0.70, 0.74)
        case .veneno:   return (0.55, 0.80, 0.25)
        case .arcana:   return (0.70, 0.40, 0.90)
        case .natureza: return (0.20, 0.65, 0.40)
        }
    }

    /// Multiplicador multiplicativo (compõe corretamente com habilidades — GDD §8).
    /// 2x contra o elemento anterior no ciclo, 0.5x contra o próximo, 1x no resto.
    func multiplier(against defender: Element) -> Double {
        let n = Element.allCases.count
        let prev = (rawValue - 1 + n) % n   // eu venço este
        let next = (rawValue + 1) % n       // este me vence
        if defender.rawValue == prev { return 2.0 }
        if defender.rawValue == next { return 0.5 }
        return 1.0
    }
}
