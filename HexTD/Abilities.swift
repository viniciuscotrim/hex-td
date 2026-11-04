import SwiftUI

/// Paleta de efeitos de habilidade (§5). Cada torre do catálogo referencia duas
/// (em `TowerSpec.abilities`); a 1ª libera na Azul, a 2ª na Laranja — o slot vem da
/// POSIÇÃO no array da torre. Muitos efeitos amarram no sistema de status/combos
/// (§combo). A lógica vive na GameScene; os números em `Tuning`.
enum TowerAbility: Int, CaseIterable {
    case precisao      // crítico
    case perfuracao    // atinge 2º alvo
    case cadencia      // dispara mais rápido
    case alcance       // +1 de alcance
    case execucao      // +dano em inimigo com pouca vida
    case queimadura    // reforça burn (DoT)
    case chamasVivas   // +raio de splash
    case profundo      // lentidão profunda
    case estilhacos    // alvo lento/frozen sofre +dano
    case potencia      // status mais fortes/longos
    case contagio      // burn/veneno contagiam um vizinho
    case detonador     // inimigo com 2+ status explode
    case cobranca      // +gold por acerto/kill
    case ressonancia   // aura de dano nas vizinhas

    /// Raridade que libera a habilidade no slot dado (0 → Azul, 1 → Laranja).
    static func unlockRarity(slot: Int) -> Rarity { slot == 0 ? .azul : .laranja }

    var nome: String {
        switch self {
        case .precisao:    return "Precisão"
        case .perfuracao:  return "Perfuração"
        case .cadencia:    return "Cadência"
        case .alcance:     return "Alcance"
        case .execucao:    return "Execução"
        case .queimadura:  return "Queimadura"
        case .chamasVivas: return "Chamas Vivas"
        case .profundo:    return "Congelamento Profundo"
        case .estilhacos:  return "Estilhaços"
        case .potencia:    return "Potência"
        case .contagio:    return "Contágio"
        case .detonador:   return "Detonador"
        case .cobranca:    return "Cobrança"
        case .ressonancia: return "Ressonância"
        }
    }

    var icon: String {
        switch self {
        case .precisao:    return "🎯"
        case .perfuracao:  return "➶"
        case .cadencia:    return "⚡"
        case .alcance:     return "🔭"
        case .execucao:    return "💀"
        case .queimadura:  return "🔥"
        case .chamasVivas: return "💥"
        case .profundo:    return "🧊"
        case .estilhacos:  return "🩸"
        case .potencia:    return "🧪"
        case .contagio:    return "☣️"
        case .detonador:   return "💣"
        case .cobranca:    return "💰"
        case .ressonancia: return "🌀"
        }
    }

    var desc: String {
        switch self {
        case .precisao:    return "\(Int(Tuning.critChance * 100))% de chance de crítico (×\(Int(Tuning.critMult)))"
        case .perfuracao:  return "Atinge também o 2º alvo no alcance (\(Int(Tuning.pierceFactor * 100))% do dano)"
        case .cadencia:    return "Dispara ~\(Int((1/Tuning.cadenciaMult - 1) * 100))% mais rápido"
        case .alcance:     return "+\(Tuning.alcanceBonus) de alcance"
        case .execucao:    return "+\(Int((Tuning.execucaoMult - 1) * 100))% de dano em inimigos abaixo de \(Int(Tuning.execucaoHp * 100))% de vida"
        case .queimadura:  return "Reforça a queimadura (dano contínuo mais forte)"
        case .chamasVivas: return "+\(Tuning.chamasSplashBonus) de raio de splash"
        case .profundo:    return "Lentidão mais forte (\(Int((1 - Tuning.freezeSlow) * 100))%) e mais longa"
        case .estilhacos:  return "Alvo lento/congelado sofre +\(Int((Tuning.shatterBonus - 1) * 100))% de qualquer torre"
        case .potencia:    return "Status aplicados \(Int((Tuning.potenciaMult - 1) * 100))% mais fortes/longos"
        case .contagio:    return "Burn/veneno contagiam um inimigo próximo"
        case .detonador:   return "Inimigo com 2+ status explode ao ser atingido"
        case .cobranca:    return "+\(Tuning.cobrancaPerHit) gold por acerto e bônus por kill"
        case .ressonancia: return "Torres vizinhas ganham +\(Int(Tuning.auraBonus * 100))% de dano"
        }
    }

    /// Números de balanço, num só lugar pra facilitar o tuning.
    enum Tuning {
        static let critChance = 0.25, critMult = 2.0
        static let pierceFactor = 0.60
        static let cadenciaMult = 0.80                 // cooldown ×0.8 → ~+25% cadência
        static let alcanceBonus = 1
        static let execucaoHp = 0.30, execucaoMult = 1.6
        static let burnDuration = 2.5, burnFraction = 0.40   // (legado; base vive em Status.T)
        static let burnBoostMult = 1.6                       // com Queimadura
        static let baseSlow = 0.50, baseSlowDuration = 1.2
        static let freezeSlow = 0.30, freezeDuration = 2.2
        static let shatterBonus = 1.25
        static let potenciaMult = 1.5                  // +50% dps/duração/força de status
        static let contagioFrac = 0.6                  // potência do status contagiado
        static let detonadorFrac = 0.6, detonadorMinStatus = 2
        static let cobrancaBounty = 12, cobrancaPerHit = 1
        static let auraBonus = 0.15, auraRange = 1
        static let chamasSplashBonus = 1
    }
}
