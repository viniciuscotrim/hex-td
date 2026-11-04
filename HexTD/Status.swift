import Foundation

/// Status que uma torre aplica no inimigo. São a matéria-prima dos combos (§combo):
/// cada elemento aplica o seu, e a matriz de reações (Fase 3) faz eles combarem ou
/// se anularem. Na Fase 1 só `burn` e `frozen` têm efeito (mapeados na lógica antiga
/// de DoT/lentidão); os demais são aplicados mas ainda inertes até a Fase 2/3.
enum Status: Int, CaseIterable {
    case burn      // Fogo — dano contínuo
    case wet       // Água — molhado (habilita combos)
    case frozen    // Gelo — lentidão/congelamento
    case poison    // Veneno — DoT que empilha
    case exposed   // Físico — recebe mais dano
    case marked    // Arcana — amplifica o próximo dano/combo
    case rooted    // Natureza — preso/lento

    var nome: String {
        switch self {
        case .burn:    return "Queimando"
        case .wet:     return "Molhado"
        case .frozen:  return "Congelado"
        case .poison:  return "Envenenado"
        case .exposed: return "Exposto"
        case .marked:  return "Marcado"
        case .rooted:  return "Preso"
        }
    }

    var icon: String {
        switch self {
        case .burn:    return "🔥"
        case .wet:     return "💧"
        case .frozen:  return "❄️"
        case .poison:  return "☠️"
        case .exposed: return "🎯"
        case .marked:  return "🔮"
        case .rooted:  return "🌿"
        }
    }

    /// Balanço dos status e das reações de combo (§combo). Num só lugar pra tunar.
    enum T {
        static let burnDur = 2.5, burnFrac = 0.40      // DoT base = 40% do dano/s
        static let poisonDur = 3.0, poisonFrac = 0.25  // empilha por acerto
        static let wetDur = 3.5
        static let slowDur = 1.2, slowFactor = 0.50    // frozen/rooted base
        static let rootedFactor = 0.35                 // raiz prende mais
        static let freezeDur = 2.2, freezeFactor = 0.30 // congelamento profundo (wet/ability)
        static let exposedDur = 3.0, exposedMult = 1.25
        static let markedDur = 3.0, markedMult = 1.30
        static let shatterMult = 1.6                   // frozen + físico
        static let explosionFrac = 1.2                 // burn + veneno = 120% do dano em área
    }
}
