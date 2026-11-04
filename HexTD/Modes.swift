import Foundation

/// RNG determinístico (SplitMix64). Seed fixa → mapa reproduzível: é o que faz a
/// Campanha ser "curada" (GDD §2/§3) reaproveitando o gerador por constraint.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Parâmetros de uma partida. Um motor único, três portas (GDD §2): a diferença
/// entre modos é só a configuração — seed fixa vs. aleatória, alvo de onda vs.
/// infinito, e a curadoria de dificuldade.
struct GameConfig {
    let cols: Int
    let rows: Int
    let obstacleRatio: Double
    let seed: UInt64?        // nil = aleatório (Rogue/Endless); fixo = curado (Campanha)
    let targetWave: Int?     // nil = infinito (Endless); N = vencer ao limpar a onda N
    let startLives: Int
    let startGold: Int
    let hpScale: Double        // multiplicador de HP base da onda (curadoria de dificuldade)
    let pathComplexity: Double // 0=fino/iniciante, 1=serpentina cobrindo ~2/3
    let bossEvery: Int         // spawn de Boss a cada N ondas (0 = sem boss)
    var enemyCountMult: Double = 1.0   // multiplica a quantidade de inimigos por onda
    var enemySpeedMult: Double = 1.0   // multiplica a velocidade dos inimigos
    var dominantElement: Element? = nil // elemento predominante dos inimigos (nil = aleatório)
    var isVs: Bool = false             // modo Vs (2 tabuleiros): suprime crédito/score in-scene

    // Rogue: desafiador — HP maior + Boss a cada 5 ondas (senão o Endless o substitui).
    static let rogue = GameConfig(cols: 7, rows: 13, obstacleRatio: 0.10, seed: nil,
                                  targetWave: 15, startLives: MetaProgress.maxLives, startGold: 130, hpScale: 1.35, pathComplexity: 0.8, bossEvery: 5)
    static let endless = GameConfig(cols: 7, rows: 13, obstacleRatio: 0.08, seed: nil,
                                    targetWave: nil, startLives: MetaProgress.maxLives, startGold: 130, hpScale: 1.0, pathComplexity: 0.9, bossEvery: 0)
    // Vs (estilo Rush Royale): CAMPO NOVO e fixo (mesma seed → mapa e ondas idênticos pros
    // dois lados), last-stand infinito (targetWave nil). HP determinístico por seed pra ser
    // justo. Boss a cada 8 ondas. Você e a IA disputam quem sobrevive mais.
    static let vs = GameConfig(cols: 7, rows: 12, obstacleRatio: 0.08, seed: 770077,
                               targetWave: nil, startLives: MetaProgress.maxLives, startGold: 140,
                               hpScale: 1.0, pathComplexity: 0.85, bossEvery: 8,
                               enemyCountMult: 1.35, isVs: true)
}

/// Campanha (§3): 150 fases com progressão e dificuldade LINEAR. A fase 1 é trivial
/// (torres base, sem upgrade, já vencem); a 150 exige raridade Mítica nas 5 torres do
/// loadout. Cada fase tem seed fixa (curada/reproduzível). Números lineares e tunáveis.
enum Campaign {
    static let count = 150

    /// Config da fase `i` (0-based). Tudo interpola linearmente de fácil → difícil.
    static func make(_ i: Int) -> GameConfig {
        let t = Double(i) / Double(count - 1)          // 0 (fase 1) … 1 (fase 150)
        let cols = 6 + Int((t * 2).rounded())          // 6 … 8
        let rows = 9 + Int((t * 7).rounded())          // 9 … 16
        let dom = Element.allCases[i % Element.allCases.count]   // elemento tema (rotaciona)
        return GameConfig(
            cols: cols, rows: rows, obstacleRatio: 0.08,
            seed: UInt64(1001 + i),                     // curada por fase
            targetWave: 4 + Int((t * 16).rounded()),    // 4 … 20 ondas
            startLives: MetaProgress.maxLives,          // 10 (crédito máx. com 10 vidas)
            startGold: 130,
            hpScale: (0.5 + t * 11.5) * 3.0,             // 1.5 … 36 (monstros bem mais fortes)
            pathComplexity: min(1.0, 0.1 + t * 0.95),
            bossEvery: 5,                                // boss a cada 5 ondas (contra spam de AoE)
            enemyCountMult: 1.5 + t * 1.0,               // 1.5 … 2.5 (mais monstros por onda)
            enemySpeedMult: 0.85,                        // um pouco mais devagar
            dominantElement: dom)                        // inimigos predominam nesse elemento
    }

    static let stages: [GameConfig] = (0..<count).map(make)
}
