import SwiftUI

/// Snapshot de uma torre selecionada, pro painel de inspeção in-run (GDD §6).
struct TowerInspect {
    let name: String
    let icon: String
    let element: Element
    let rarity: Rarity
    let level: Int
    let maxLevel: Int
    let damage: Double
    let range: Int
    let trait: String        // resumo da função-1
    let abilities: [TowerAbility]  // habilidades ativas do loadout (§5)
    let upgradeCost: Int?    // nil quando no nível máximo
    let sellValue: Int
}

/// Estado do HUD compartilhado entre SwiftUI e a cena (GDD §6 in-run: gold/vidas).
/// A lógica de regras vive na GameScene; aqui é só o que a UI precisa observar.
final class GameModel: ObservableObject {
    @Published var gold: Int = 120
    @Published var lives: Int = 20
    @Published var wave: Int = 0
    @Published var selected: Int = 9        // id no TowerCatalog (default: Físico-Lança)
    @Published var gameOver: Bool = false
    @Published var won: Bool = false
    @Published var message: String = ""
    @Published var creditsEarned: Int = 0  // créditos ganhos na run (fim de jogo)

    // Controle manual de onda (Fase 4): jogador chama a próxima; bônus por antecipar.
    @Published var waveReady: Bool = false
    @Published var waveBonus: Int = 0
    var doStartWave: (() -> Void)?

    // Ferramentas de teste: velocidade da simulação e IA que joga sozinha.
    @Published var speed: Int = 1          // 1 / 2 / 5 / 10 (sub-steps por frame)
    @Published var autoPlay: Bool = false  // IA constrói, upgrada e chama ondas
    @Published var paused: Bool = false    // menu de pause: congela a simulação
    /// Snapshot das torres colocadas (para salvar/retomar a partida). A cena preenche.
    var towerSnapshot: (() -> [TowerSave])?

    /// Torre atualmente inspecionada (nil = mostra o seletor de compra).
    @Published var inspect: TowerInspect? = nil
    // Ações que a cena registra ao selecionar uma torre; o painel SwiftUI dispara.
    var doUpgrade: (() -> Void)?
    var doSell: (() -> Void)?
    var doDeselect: (() -> Void)?

    // MARK: — Rogue idle (torre central, estilo The Tower)
    @Published var rogueHP: Double = 0
    @Published var rogueMaxHP: Double = 0
    @Published var rogueUpg: [Int] = Array(repeating: 0, count: 6)   // níveis dos 6 upgrades
    @Published var rogueCost: [Int] = Array(repeating: 0, count: 6)  // custo do próximo nível
    @Published var rogueMult: [Double] = Array(repeating: 1, count: 6) // multiplicador atual do stat (1.X×)
    @Published var rogueStarted: Bool = false   // run começou (torre escolhida)
    @Published var rogueKills: Int = 0
    var doRogueUpgrade: ((Int) -> Void)?        // compra o upgrade i (0…5)
    var doRogueStart: (() -> Void)?             // inicia a run com a torre `selected`

    func reset() {
        gold = 120; lives = 20; wave = 0
        selected = 9; gameOver = false; won = false; message = ""; creditsEarned = 0
        waveReady = false; waveBonus = 0
        speed = 1; autoPlay = false; paused = false
        inspect = nil; doUpgrade = nil; doSell = nil; doDeselect = nil; doStartWave = nil
        towerSnapshot = nil
        rogueHP = 0; rogueMaxHP = 0
        rogueUpg = Array(repeating: 0, count: 6); rogueCost = Array(repeating: 0, count: 6)
        rogueMult = Array(repeating: 1, count: 6)
        rogueStarted = false; rogueKills = 0
        doRogueUpgrade = nil; doRogueStart = nil
    }
}

/// Torre salva (para retomar a partida da Campanha). O mapa é regenerado pela seed fixa.
struct TowerSave: Codable {
    var q: Int; var r: Int; var specId: Int; var level: Int; var spent: Int
}

/// Snapshot de uma partida de Campanha em andamento (retomável).
struct RunSave: Codable {
    var stage: Int; var gold: Int; var lives: Int; var wave: Int
    var loadout: [Int]
    var towers: [TowerSave]
}
