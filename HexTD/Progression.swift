import Foundation

/// Coeficientes do sistema de progressão (§brief). NENHUM número fica hardcode nas
/// fórmulas — tudo vem daqui, e daqui de um `progression.json` externo (bundle +
/// hot-reload em DEBUG) → permite tunar balanceamento sem rebuild. Defaults = as
/// estimativas iniciais do brief.
struct ProgressionConfig: Codable, Equatable {
    // 1 — HP de inimigo por wave: HP(n) = hp0 · rHP^(n·d(n)),  d(n)=1/(1+kHP·⌊n/pHP⌋)
    // (tunado: r mais íngreme que a estimativa 1.08 — amortização deixava mid/late fácil)
    var hp0: Double = 22
    var rHP: Double = 1.11
    var kHP: Double = 0.15
    var pHP: Int = 10
    // 2 — Dano de inimigo por wave (mesma forma, r menor → escala mais devagar que HP)
    var dano0: Double = 5
    var rDano: Double = 1.06
    var kDano: Double = 0.15
    var pDano: Int = 10
    // 3 — Gold por kill: Gold(n) = gold0 · n^goldA  (sublinear, a∈[0.3,0.5])
    var gold0: Double = 4
    var goldA: Double = 0.42
    // 4 — Stat de torre por tier de raridade: Stat = Stat0 · ∏(1+b_i), i=1..tier
    // +50% por salto de raridade → Mítica ×7.59 (1.5⁵).
    var statBonuses: [Double] = [0.50, 0.50, 0.50, 0.50, 0.50]
    // 5 — Upgrade in-run (gold, reseta por run): Custo=base·g^(lvl-1), Efeito=1+step·lvl
    var upgradeCostGrowth: Double = 1.5
    var upgradeEffectStep: Double = 0.25
    // 6 — Modificador elemental (aplicado por último na cadeia de dano)
    var elementalAdvantage: Double = 2.0
    var elementalNeutral: Double = 1.0
    var elementalDisadvantage: Double = 0.5
    // 7 — Rogue: variância leve de `r` por seed (r ± rogueVariance)
    var rogueVariance: Double = 0.02
}

/// Fórmulas de progressão como funções PURAS (recebem a config → testáveis isoladas).
/// Sem dependência de SpriteKit/SwiftUI — só Foundation.
enum Progression {

    // MARK: — Config (bundle + hot-reload em DEBUG)

    private(set) static var config = ProgressionConfig()
    private static var devMTime: Date?

    /// Carrega `progression.json` do bundle (se existir); senão mantém os defaults.
    static func load() {
        if let url = Bundle.main.url(forResource: "progression", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let c = try? JSONDecoder().decode(ProgressionConfig.self, from: data) {
            config = c
        }
        reload()
    }

    #if DEBUG
    /// Override de dev: coloque um `progression.json` no diretório Documents do app
    /// (no simulador é acessível) e ele é recarregado a quente quando muda.
    static var devOverrideURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("progression.json")
    }
    static func reload() {
        let url = devOverrideURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let m = attrs[.modificationDate] as? Date, m != devMTime,
              let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(ProgressionConfig.self, from: data) else { return }
        config = c; devMTime = m
    }
    #else
    static func reload() {}
    #endif

    // MARK: — Fórmulas puras

    /// Amortecimento por patamar: d(n) = 1 / (1 + k·⌊n/P⌋). Cai em degraus a cada P waves.
    static func damping(_ n: Int, k: Double, p: Int) -> Double {
        1.0 / (1.0 + k * Double(max(0, n) / max(1, p)))
    }

    /// (1) HP de inimigo na wave `n`. Exponencial amortecida — não estoura em Endless.
    static func enemyHP(wave n: Int, _ c: ProgressionConfig = config) -> Double {
        c.hp0 * pow(c.rHP, Double(max(0, n)) * damping(n, k: c.kHP, p: c.pHP))
    }

    /// (2) Dano de inimigo na wave `n` (escala mais devagar que o HP).
    static func enemyDamage(wave n: Int, _ c: ProgressionConfig = config) -> Double {
        c.dano0 * pow(c.rDano, Double(max(0, n)) * damping(n, k: c.kDano, p: c.pDano))
    }

    /// (3) Gold por kill na wave `n`. Sublinear (raiz) → cria pressão de economia.
    static func goldPerKill(wave n: Int, _ c: ProgressionConfig = config) -> Double {
        c.gold0 * pow(Double(max(1, n)), c.goldA)
    }

    /// (4) Multiplicador de stat da raridade `tier` (0 = base, 1..N = saltos). ∏(1+b_i).
    static func rarityStat(tier: Int, _ c: ProgressionConfig = config) -> Double {
        var m = 1.0
        for i in 0..<max(0, min(tier, c.statBonuses.count)) { m *= (1 + c.statBonuses[i]) }
        return m
    }

    /// (5) Custo do upgrade in-run para comprar o nível `lvl` (1-based): base·g^(lvl-1).
    static func upgradeCost(base: Double, lvl: Int, _ c: ProgressionConfig = config) -> Double {
        base * pow(c.upgradeCostGrowth, Double(max(0, lvl - 1)))
    }

    /// (5) Efeito acumulado no nível de upgrade `lvl` (0 = recém-colocada): 1 + step·lvl.
    static func upgradeEffect(lvl: Int, _ c: ProgressionConfig = config) -> Double {
        1 + c.upgradeEffectStep * Double(max(0, lvl))
    }

    /// (6) Multiplicador elemental — aplicado por ÚLTIMO na cadeia de dano.
    enum ElementRelation { case advantage, neutral, disadvantage }
    static func elementalMult(_ r: ElementRelation, _ c: ProgressionConfig = config) -> Double {
        switch r {
        case .advantage:    return c.elementalAdvantage
        case .neutral:      return c.elementalNeutral
        case .disadvantage: return c.elementalDisadvantage
        }
    }

    /// (7) `r` do Rogue com variância leve determinística por seed (r ± rogueVariance).
    static func rogueGrowth(baseR: Double, seed: UInt64, _ c: ProgressionConfig = config) -> Double {
        // SplitMix64 inline (determinístico, sem depender do RNG do jogo).
        var z = seed &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= (z >> 31)
        let unit = Double(z % 10_000) / 10_000.0          // [0,1)
        return baseR + (unit * 2 - 1) * c.rogueVariance   // baseR ± variance
    }

    /// Config do Rogue para um run: aplica a variância de seed em rHP/rDano (7).
    static func rogueConfig(seed: UInt64, _ c: ProgressionConfig = config) -> ProgressionConfig {
        var rc = c
        rc.rHP = rogueGrowth(baseR: c.rHP, seed: seed, c)
        rc.rDano = rogueGrowth(baseR: c.rDano, seed: seed &* 0x2545F4914F6CDD1D, c)
        return rc
    }
}
