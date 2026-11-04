import SpriteKit

/// Estado observável do Vs (SwiftUI observa pro HUD/resultado).
final class VsState: ObservableObject {
    @Published var wave: Int = 0
    @Published var finished = false
    @Published var playerWon = false
    @Published var playerPlaced: Set<Int> = []   // ids já em campo do jogador (não repetir)
    @Published var creditsEarned = 0             // créditos ganhos ao vencer
    // Leitura do oponente (Norte) + economia (HUD).
    @Published var playerIncome = 8              // gold/s total do jogador (base 8 + creeps)
    @Published var aiIncome = 8                  // gold/s total do oponente (info-chave de leitura)
    @Published var aiTowers: [TowerBadge] = []   // torres do oponente (elemento + papel)
}

/// Resumo de uma torre do oponente pro HUD do Norte.
struct TowerBadge: Identifiable, Equatable {
    let id: Int          // spec id (chave estável na lista)
    let icon: String     // ícone do elemento
    let role: String     // papel curto
}

enum VsSide { case player, ai }
private enum Lane { case center, left, right }   // left = jogador, right = IA

/// Mercado de creeps (Vs v2): enviar é INVESTIMENTO — cada compra adiciona renda passiva
/// PERMANENTE ao comprador, e o creep nasce na lane do adversário.
enum VsCreep: Int, CaseIterable {
    case corredor, tanque, enxame, elemental
    var nome: String { switch self { case .corredor: "Corredor"; case .tanque: "Tanque"; case .enxame: "Enxame"; case .elemental: "Elemental" } }
    var icon: String { switch self { case .corredor: "🏃"; case .tanque: "🛡️"; case .enxame: "🐝"; case .elemental: "✨" } }
    var cost: Int { switch self { case .corredor: 40; case .tanque: 90; case .enxame: 120; case .elemental: 110 } }
    var income: Int { switch self { case .corredor: 2; case .tanque: 4; case .enxame: 5; case .elemental: 3 } }  // +gold/s permanente
}

/// Arquétipos de inimigo (mesmos do modo normal): variam HP/tamanho/quantidade → exigem
/// mistura de torres. `boss` = chefão a cada 5 ondas.
enum VsEnemyType: CaseIterable {
    case swarm, trio, duo, elite, boss
    var groupSize: Int { switch self { case .swarm: 6; case .trio: 3; case .duo: 2; case .elite: 1; case .boss: 1 } }
    var hpMult: Double { switch self { case .swarm: 0.35; case .trio: 1.4; case .duo: 2.2; case .elite: 6.0; case .boss: 16.0 } }
    var sizeMult: Double { switch self { case .swarm: 0.7; case .trio: 0.85; case .duo: 1.05; case .elite: 1.5; case .boss: 2.0 } }
    var speedMult: Double { switch self { case .swarm: 1.25; case .trio: 1.05; case .duo: 0.9; case .elite: 0.7; case .boss: 0.55 } }
    var bounty: Int { switch self { case .swarm: 1; case .trio: 2; case .duo: 3; case .elite: 4; case .boss: 5 } }  // gold por inimigo 1…5
    var splashResist: Double { switch self { case .duo: 0.55; case .elite: 0.30; case .boss: 0.35; default: 1.0 } }
    var lives: Int { self == .boss ? 3 : 1 }     // quanto tira da base ao vazar
    var weight: Int { switch self { case .swarm: 35; case .trio: 25; case .duo: 25; case .elite: 12; case .boss: 0 } }
    var marker: String? { switch self { case .elite: "💪"; case .boss: "👑"; default: nil } }
    static func weightedPick() -> VsEnemyType {
        let pool = allCases.filter { $0.weight > 0 }
        let total = pool.reduce(0) { $0 + $1.weight }
        var r = Int.random(in: 0..<total)
        for t in pool { if r < t.weight { return t }; r -= t.weight }
        return .swarm
    }
}

private final class VsTower {
    let spec: TowerSpec
    let side: VsSide
    let hex: Hex
    let abilities: [TowerAbility]
    var level = 1
    var cooldown = 0.0
    var priority: Lane = .center      // lane priorizada no alvo (.center = ataque / ownLane = defesa)
    let maxStars: Int                 // teto de estrelas (rar. + Paragon) — igual ao resto do jogo
    let node: SKNode
    let pos: CGPoint
    let rangePx: CGFloat
    let rarityMult: Double
    init(spec: TowerSpec, side: VsSide, hex: Hex, abilities: [TowerAbility], maxStars: Int,
         node: SKNode, pos: CGPoint, rangePx: CGFloat, rarityMult: Double) {
        self.spec = spec; self.side = side; self.hex = hex; self.abilities = abilities
        self.maxStars = maxStars
        self.node = node; self.pos = pos; self.rangePx = rangePx; self.rarityMult = rarityMult
    }
    func has(_ a: TowerAbility) -> Bool { abilities.contains(a) }
    var damage: Double { spec.baseDamage * Progression.upgradeEffect(lvl: level - 1) * rarityMult }
    var cadence: Double { spec.cooldown * pow(0.9, Double(level - 1)) * (has(.cadencia) ? TowerAbility.Tuning.cadenciaMult : 1) }
    var splashHex: Int { spec.splash + (spec.splash > 0 && level >= 4 ? 1 : 0) + (has(.chamasVivas) ? TowerAbility.Tuning.chamasSplashBonus : 0) }
    var upgradeCost: Int? { level >= maxStars ? nil : Int(Progression.upgradeCost(base: Double(spec.cost), lvl: level)) }
}

private final class VsEnemy {
    var lane: Lane
    var hp: Double
    let maxHP: Double
    let baseSpeed: Double
    let element: Element
    let bounty: Int
    let leaks: Int                 // vidas que tira da base ao vazar (boss = 3)
    let splashResist: Double       // <1 → AOE faz menos (elite/boss/duo)
    var prog = 0.0                 // 0 (topo) … 1 (base)
    var dmgP = 0.0, dmgA = 0.0     // dano por lado (empurra a deflexão)
    // status
    var until: [Status: Double] = [:]
    var burnDps = 0.0, poisonDps = 0.0
    var burnSide: VsSide = .player, poisonSide: VsSide = .player
    var lastHit: VsSide? = nil     // quem deu o ÚLTIMO hit (decide a deflexão)
    var xOff: CGFloat = 0          // deslocamento lateral (oscila de lado a cada spawn)
    var slowFactor = 1.0
    var dead = false
    let node: SKNode
    let bar: SKShapeNode
    let stroke: SKShapeNode
    let stLabel: SKLabelNode
    init(hp: Double, speed: Double, element: Element, bounty: Int, leaks: Int, splashResist: Double,
         node: SKNode, bar: SKShapeNode, stroke: SKShapeNode, stLabel: SKLabelNode) {
        self.lane = .center; self.hp = hp; self.maxHP = hp; self.baseSpeed = speed
        self.element = element; self.bounty = bounty; self.leaks = leaks; self.splashResist = splashResist
        self.node = node; self.bar = bar; self.stroke = stroke; self.stLabel = stLabel
    }
    func active(_ s: Status, _ now: Double) -> Bool { (until[s] ?? 0) > now }
    func slowed(_ now: Double) -> Bool { active(.frozen, now) || active(.rooted, now) }
    func addDmg(_ d: Double, _ side: VsSide) { if side == .player { dmgP += d } else { dmgA += d }; lastHit = side }
}

/// Vs — 3 LANES (estilo cabo de guerra). Monstros nascem na lane CENTRAL; os dois lados
/// atiram. Quem causa mais dano empurra o monstro (vida cheia) pra lane do adversário, que
/// então precisa matá-lo antes de chegar na base — senão perde vida. Você defende DUAS
/// lanes: a central (ataque) e a sua, à esquerda (defesa). Last-stand. Auto On pros dois.
final class VsScene: SKScene {
    private unowned let meta: MetaProgress
    private unowned let playerModel: GameModel
    private unowned let aiModel: GameModel
    private unowned let state: VsState

    private let boardLayer = SKNode()
    private let slotLayer = SKNode()
    private let towerLayer = SKNode()
    private let enemyLayer = SKNode()

    let loadout: [Int]                         // as 5 torres do JOGADOR
    private var aiLoadout: [Int] = []          // a IA tem o SEU próprio loadout (diferente)
    var pvp: PvPSession?                        // != nil → o NORTE é um jogador remoto (não IA)
    var pvpSeed: UInt64 = 0
    private var spawnRNG = SeededGenerator(seed: 1)
    private var pvpStateClock = 0.0
    private var isPvP: Bool { pvp != nil }
    /// Espelha um hex sul↔norte (reflete na linha divisória): (q,r) → (q+r, -r).
    private func mirror(_ h: Hex) -> Hex { Hex(q: h.q + h.r, r: -h.r) }

    // Geometria HEX (yin-yang). Recalculada no didChangeSize.
    private var layout = HexLayout(size: 10, origin: .zero)
    private var cells: [Hex] = []
    private var regionOf: [Hex: VsSide] = [:]   // metade (yin/yang) de cada hex
    private var neutralPath: [Hex] = []         // a "lane neutra" = miolo da curva S
    private var playerPath: [Hex] = []          // do centro → base do jogador (lóbulo inferior)
    private var aiPath: [Hex] = []              // do centro → base da IA (lóbulo superior)
    private var pathSet: Set<Hex> = []
    private var rangeUnit: CGFloat = 30          // unidade VISUAL (tamanho de torre/inimigo)
    private var hexSize: CGFloat = 24            // unidade de ALCANCE (mesma dos outros mapas)

    private var towers: [Hex: VsTower] = [:]    // hex → torre (colocação livre)
    private var enemies: [VsEnemy] = []

    private var lastTime: TimeInterval = 0
    private var gameClock = 0.0
    private var waveClock = 3.0
    private let waveInterval = 8.0
    private var spawnQueue: [VsEnemyType] = []   // fila de inimigos desta onda (grupos já expandidos)
    private var spawnClock = 0.0
    private var waveHP = 20.0
    private var incomeClock = 0.0
    private var pAIClock = 0.0, aAIClock = 0.0
    static let startLives = 5              // Vs v2: metade da margem = metade da duração
    static let suddenDeathWave = 12        // a partir daqui, todo vazamento tira +1 vida extra
    static let baseIncome = 8              // renda passiva base (sem creeps)
    /// Teto de renda/s = metade do custo da unidade mais cara → sem isso, renda estoura e vira spam.
    static var incomeCap: Int { (VsCreep.allCases.map(\.cost).max() ?? 120) / 2 }   // = 60/s

    init(meta: MetaProgress, playerModel: GameModel, aiModel: GameModel, state: VsState,
         loadout: [Int], size: CGSize) {
        self.meta = meta; self.playerModel = playerModel; self.aiModel = aiModel; self.state = state
        self.loadout = loadout
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 1)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = meta.frameLimit
        [boardLayer, slotLayer, towerLayer, enemyLayer].forEach(addChild)
        playerModel.gold = 160; playerModel.lives = VsScene.startLives
        aiModel.gold = 160; aiModel.lives = VsScene.startLives
        aiModel.autoPlay = !isPvP           // PvP: o norte é o jogador remoto, não a IA
        playerModel.selected = loadout.first ?? 0
        aiLoadout = makeAILoadout()
        if isPvP { spawnRNG = SeededGenerator(seed: pvpSeed == 0 ? 1 : pvpSeed)
                   pvp?.onMessage = { [weak self] m in self?.applyRemote(m) } }
        computeLayout(); drawBoard()
    }

    override func didChangeSize(_ old: CGSize) {
        super.didChangeSize(old)
        guard size.width > 0, boardLayer.parent != nil else { return }
        computeLayout(); drawBoard()
        for (h, t) in towers { t.node.position = layout.center(of: h) }
    }

    // MARK: geometria (oval hex, dividido Norte/Sul)

    private var buildable: Set<Hex> = []       // hexes construíveis (fora dos caminhos)
    private var midY: CGFloat = 0              // linha divisória Norte(IA)/Sul(jogador) em px

    private func computeLayout() {
        let W = size.width, H = size.height
        // 1) OVAL de hexes UNIFORMES que acompanha a tela (retrato → mais alto que largo).
        let unit = HexLayout(size: 1, origin: .zero)
        let aspect = H / W
        let A: CGFloat = 5.4                    // semi-eixo horizontal (unit)
        let B = A * aspect                      // semi-eixo vertical → oval enche a tela
        cells = []
        for q in -10...10 { for r in -16...16 {
            let c = unit.center(of: Hex(q: q, r: r))
            if (c.x / A) * (c.x / A) + (c.y / B) * (c.y / B) <= 1 { cells.append(Hex(q: q, r: r)) }
        } }
        let uc = cells.map { unit.center(of: $0) }
        let minX = uc.map(\.x).min()!, maxX = uc.map(\.x).max()!
        let minY = uc.map(\.y).min()!, maxY = uc.map(\.y).max()!
        // hexSize UNIFORME (mesmo em X e Y): fit no menor eixo → hexágonos regulares.
        hexSize = min(W * 0.98 / (maxX - minX + 1.4), H * 0.98 / (maxY - minY + 1.4))
        rangeUnit = hexSize
        let ox = W / 2 - hexSize * ((minX + maxX) / 2)
        let oy = H / 2 - hexSize * ((minY + maxY) / 2)
        layout = HexLayout(size: hexSize, origin: CGPoint(x: ox, y: oy))
        midY = oy                               // y da linha unit=0 (fronteira N/S)
        // 2) TERRITÓRIO por Norte/Sul: norte (y≥0) = IA, sul = jogador.
        regionOf = [:]
        for h in cells { regionOf[h] = unit.center(of: h).y >= 0 ? .ai : .player }
        // 3) curva S (yin-yang) como caminho: topo (base IA) → centro (neutra) → base (jogador).
        let ax = max(abs(minX), abs(maxX)), ay = max(abs(minY), abs(maxY))
        var sPath: [Hex] = []
        for i in 0...60 {
            let t = CGFloat(i) / 60, y = 1 - 2 * t
            let x: CGFloat = y >= 0 ?  sqrt(max(0, 0.25 - (y - 0.5) * (y - 0.5)))
                                    : -sqrt(max(0, 0.25 - (y + 0.5) * (y + 0.5)))
            let target = CGPoint(x: x * ax, y: y * ay)
            if let h = cells.min(by: { unit.center(of: $0).distanceSq(target) < unit.center(of: $1).distanceSq(target) }),
               h != sPath.last { sPath.append(h) }
        }
        let n = sPath.count
        let ci = n / 2
        let cLo = max(1, ci - 2), cHi = min(n - 1, ci + 2)      // 5 hexes neutros no centro
        neutralPath = Array(sPath[cLo...cHi])
        aiPath = Array(sPath[0...cLo].reversed())
        playerPath = Array(sPath[cHi..<n])
        pathSet = Set(sPath)
        buildable = Set(cells).subtracting(pathSet)     // colocação LIVRE nos hexes fora do caminho
    }

    private func pointOn(_ path: [Hex], _ prog: Double) -> CGPoint {
        guard let first = path.first else { return CGPoint(x: size.width/2, y: size.height/2) }
        if path.count == 1 { return layout.center(of: first) }
        let f = min(max(prog, 0), 1) * Double(path.count - 1)
        let i = min(path.count - 2, Int(f)); let frac = CGFloat(f - Double(i))
        let a = layout.center(of: path[i]), b = layout.center(of: path[i + 1])
        return CGPoint(x: a.x + (b.x - a.x) * frac, y: a.y + (b.y - a.y) * frac)
    }
    private func enemyPos(_ e: VsEnemy) -> CGPoint {
        pointOn(e.lane == .center ? neutralPath : e.lane == .left ? playerPath : aiPath, e.prog)
    }
    /// Posiciona o nó do inimigo (com o deslocamento lateral de oscilação).
    private func placeNode(_ e: VsEnemy) {
        let p = enemyPos(e); e.node.position = CGPoint(x: p.x + e.xOff, y: p.y)
    }
    private func hexAt(_ p: CGPoint) -> Hex? {
        cells.min { layout.center(of: $0).distanceSq(p) < layout.center(of: $1).distanceSq(p) }
            .flatMap { layout.center(of: $0).distanceSq(p) <= hexSize * hexSize ? $0 : nil }
    }

    private func drawBoard() {
        boardLayer.removeAllChildren(); slotLayer.removeAllChildren()
        let aiBase = aiPath.last, playerBase = playerPath.last
        for h in cells {
            var pts = layout.corners(of: h); pts.append(pts[0])
            let poly = SKShapeNode(points: &pts, count: pts.count)
            poly.lineWidth = 1; poly.strokeColor = SKColor(white: 0.10, alpha: 0.9)
            let side = regionOf[h] ?? .player
            if h == aiBase {
                poly.fillColor = SKColor(red: 0.95, green: 0.35, blue: 0.38, alpha: 1)
            } else if h == playerBase {
                poly.fillColor = SKColor(red: 0.30, green: 0.85, blue: 0.55, alpha: 1)
            } else if neutralPath.contains(h) {
                poly.fillColor = SKColor(white: 0.72, alpha: 1)                     // lane neutra
            } else if aiPath.contains(h) || playerPath.contains(h) {
                poly.fillColor = side == .player ? SKColor(red: 0.22, green: 0.58, blue: 0.40, alpha: 1)
                                                 : SKColor(red: 0.66, green: 0.26, blue: 0.30, alpha: 1)
            } else {
                poly.fillColor = side == .player ? SKColor(red: 0.11, green: 0.28, blue: 0.21, alpha: 1)
                                                 : SKColor(red: 0.28, green: 0.14, blue: 0.17, alpha: 1)
            }
            boardLayer.addChild(poly)
        }
        // linha divisória Norte/Sul.
        let line = SKShapeNode(rect: CGRect(x: 0, y: midY - 1.5, width: size.width, height: 3))
        line.fillColor = SKColor(white: 1, alpha: 0.35); line.strokeColor = .clear; line.zPosition = 2
        boardLayer.addChild(line)
        chip("— NORTE · IA 🤖 —", CGPoint(x: size.width/2, y: midY + hexSize * 0.9), SKColor(red: 1, green: 0.6, blue: 0.6, alpha: 0.9))
        chip("— SUL · VOCÊ 🛡️ —", CGPoint(x: size.width/2, y: midY - hexSize * 0.9), SKColor(red: 0.5, green: 1, blue: 0.7, alpha: 0.9))
        if let b = aiBase { chip("🤖 IA", layout.center(of: b), .white) }
        if let b = playerBase { chip("🛡️ VOCÊ", layout.center(of: b), .white) }
    }

    private func chip(_ text: String, _ pos: CGPoint, _ color: SKColor) {
        let l = SKLabelNode(text: text); l.fontSize = size.width * 0.028; l.fontName = "AvenirNext-Heavy"
        l.fontColor = color; l.verticalAlignmentMode = .center; l.position = pos; l.zPosition = 5
        boardLayer.addChild(l)
    }

    // MARK: toque — colocação LIVRE no SEU lado (sul)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !state.finished, let p = touches.first?.location(in: self), let h = hexAt(p) else { return }
        if let tw = towers[h], tw.side == .player {
            if p.y >= layout.center(of: h).y { upgradeTower(tw); pvp?.send(.upgrade(h.q, h.r)) }
            else { togglePriority(tw); pvp?.send(.priority(h.q, h.r, tw.priority == .center)) }
            return
        }
        // constrói LIVRE: hex construível do SEU território (sul), sem torre.
        guard regionOf[h] == .player, buildable.contains(h), towers[h] == nil else { return }
        let spec = TowerCatalog.spec(playerModel.selected)
        guard loadout.contains(spec.id), !placedIds(.player).contains(spec.id),   // sem repetir
              playerModel.gold >= spec.cost else { return }
        playerModel.gold -= spec.cost
        place(spec, side: .player, hex: h)
        Audio.shared.sfx("place")
        autoSelectNext()
        pvp?.send(.place(h.q, h.r, spec.id))
    }

    // MARK: torres

    /// Forma da base da torre por PAPEL (distingue visualmente): striker=triângulo,
    /// blaster=hexágono, support=quadrado. Cor = elemento; borda = lado.
    private func roleShape(_ role: TowerRole, r: CGFloat) -> SKShapeNode {
        switch role {
        case .striker:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: r)); p.addLine(to: CGPoint(x: r * 0.87, y: -r * 0.5))
            p.addLine(to: CGPoint(x: -r * 0.87, y: -r * 0.5)); p.closeSubpath()
            return SKShapeNode(path: p)
        case .support:
            return SKShapeNode(rectOf: CGSize(width: r * 1.5, height: r * 1.5), cornerRadius: r * 0.2)
        case .blaster:
            let p = CGMutablePath()
            for i in 0..<6 {
                let a = CGFloat.pi / 3 * CGFloat(i) + .pi / 6
                let pt = CGPoint(x: r * cos(a), y: r * sin(a))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath(); return SKShapeNode(path: p)
        }
    }

    @discardableResult
    private func place(_ spec: TowerSpec, side: VsSide, hex: Hex) -> VsTower {
        let p = layout.center(of: hex)
        let range = spec.range + (spec.abilities.prefix(meta.rarity(spec.id).abilitySlots).contains(.alcance) ? TowerAbility.Tuning.alcanceBonus : 0)
        let rangePx = CGFloat(range) * hexSize * sqrt(3.0)   // MESMO alcance dos outros mapas
        // anel de alcance (sutil) — deixa claro o que a torre cobre → posição pesa.
        let ring = SKShapeNode(circleOfRadius: rangePx)
        ring.position = p; ring.fillColor = .clear; ring.lineWidth = 1
        ring.strokeColor = side == .player ? SKColor(red: 0.4, green: 0.8, blue: 1, alpha: 0.18)
                                           : SKColor(red: 1, green: 0.5, blue: 0.5, alpha: 0.14)
        towerLayer.addChild(ring)
        let node = SKNode(); node.position = p
        let shape = roleShape(spec.role, r: rangeUnit * 0.74)
        shape.fillColor = SKColor(red: spec.element.rgb.r, green: spec.element.rgb.g, blue: spec.element.rgb.b, alpha: 1)
        shape.strokeColor = side == .player ? SKColor(red: 0.4, green: 0.85, blue: 1, alpha: 1)
                                            : SKColor(red: 1, green: 0.5, blue: 0.5, alpha: 1)
        shape.lineWidth = 3; node.addChild(shape)
        let icon = SKLabelNode(text: spec.element.icon); icon.fontSize = rangeUnit * 0.62
        icon.verticalAlignmentMode = .center; node.addChild(icon)
        // Badge de nível ★N — bem visível (cápsula amarela acima da torre).
        let badgeW = rangeUnit * 0.9
        let badge = SKShapeNode(rect: CGRect(x: -badgeW/2, y: rangeUnit * 0.55, width: badgeW, height: rangeUnit * 0.5), cornerRadius: rangeUnit * 0.25)
        badge.fillColor = SKColor(red: 1, green: 0.78, blue: 0.15, alpha: 1); badge.strokeColor = .black; badge.lineWidth = 1
        node.addChild(badge)
        let maxStars = meta.maxStars(spec.id)
        let pip = SKLabelNode(text: "★1/\(maxStars)"); pip.fontSize = rangeUnit * 0.34; pip.name = "pip"
        pip.fontName = "AvenirNext-Heavy"; pip.verticalAlignmentMode = .center
        pip.position = CGPoint(x: 0, y: rangeUnit * 0.8); pip.fontColor = .black; node.addChild(pip)
        // Seta de PRIORIDADE de ataque (meio ⟷ própria lane). Toque na base da torre alterna.
        let arrow = SKLabelNode(text: ""); arrow.fontSize = rangeUnit * 0.44; arrow.name = "arrow"
        arrow.verticalAlignmentMode = .center; arrow.position = CGPoint(x: 0, y: -rangeUnit * 0.82)
        node.addChild(arrow)
        towerLayer.addChild(node)
        let tw = VsTower(spec: spec, side: side, hex: hex, abilities: meta.abilities(spec.id),
                         maxStars: maxStars, node: node, pos: p, rangePx: rangePx, rarityMult: meta.statMult(spec.id))
        towers[hex] = tw
        updateArrow(tw)
        if side == .player { state.playerPlaced = placedIds(.player) } else { syncAITowers() }
        return tw
    }

    /// Publica as torres do oponente (Norte) pro HUD de leitura.
    private func syncAITowers() {
        state.aiTowers = towers.values.filter { $0.side == .ai }
            .map { TowerBadge(id: $0.spec.id, icon: $0.spec.element.icon, role: $0.spec.role.nome) }
            .sorted { $0.id < $1.id }
    }

    private func placedIds(_ side: VsSide) -> Set<Int> {
        Set(towers.values.filter { $0.side == side }.map { $0.spec.id })
    }

    /// Depois de colocar, seleciona automaticamente a próxima torre do loadout ainda não usada.
    private func autoSelectNext() {
        let placed = placedIds(.player)
        if let next = loadout.first(where: { !placed.contains($0) }) { playerModel.selected = next }
    }

    private func updateArrow(_ tw: VsTower) {
        // ➡️/⬅️ conforme prioriza o MEIO (ataque) ou a PRÓPRIA lane (defesa).
        let a = tw.node.childNode(withName: "arrow") as? SKLabelNode
        let toCenter = tw.priority == .center
        if tw.side == .player { a?.text = toCenter ? "▶" : "◀" }
        else { a?.text = toCenter ? "◀" : "▶" }
        a?.fontColor = toCenter ? SKColor(white: 0.9, alpha: 1) : SKColor(red: 0.4, green: 0.9, blue: 0.6, alpha: 1)
    }

    private func upgradeTower(_ tw: VsTower) {
        let model = tw.side == .player ? playerModel : aiModel
        guard let cost = tw.upgradeCost, model.gold >= cost else { return }
        model.gold -= cost; tw.level += 1
        (tw.node.childNode(withName: "pip") as? SKLabelNode)?.text = "★\(tw.level)/\(tw.maxStars)"
        // pulso pra dar feedback do upgrade
        tw.node.run(.sequence([.scale(to: 1.18, duration: 0.08), .scale(to: 1.0, duration: 0.08)]))
    }

    private func togglePriority(_ tw: VsTower) {
        let ownLane: Lane = tw.side == .player ? .left : .right
        tw.priority = tw.priority == .center ? ownLane : .center
        updateArrow(tw)
    }

    // MARK: loop

    override func update(_ currentTime: TimeInterval) {
        if lastTime == 0 { lastTime = currentTime }
        let dt = min(currentTime - lastTime, 1.0 / 20.0)
        lastTime = currentTime
        guard !state.finished else { return }
        gameClock += dt

        waveClock -= dt
        if waveClock <= 0 { startWave() }
        stepSpawns(dt: dt)
        stepEnemies(dt: dt)
        stepTowers(dt: dt)
        enemies.removeAll { $0.dead }     // remove os que morreram nas torres/explosões deste frame
        income(dt: dt)
        if !isPvP { aiBuild(dt: dt, side: .ai, model: aiModel, clock: &aAIClock) }
        if playerModel.autoPlay { aiBuild(dt: dt, side: .player, model: playerModel, clock: &pAIClock) }
        if isPvP { pvpStateClock -= dt; if pvpStateClock <= 0 { pvpStateClock = 0.5
            pvp?.send(.state(max(0, playerModel.lives), state.wave)) } }
    }

    private func startWave() {
        state.wave += 1; waveClock = waveInterval
        let w = state.wave
        // HP base do Rogue (amortecido) × multiplicador que CRESCE por onda (composto) → o
        // late-game aperta de verdade. Fácil de tunar: 2.2 = base, 1.06 = ritmo de escalada.
        waveHP = Progression.enemyHP(wave: w) * 2.2 * pow(1.06, Double(w))
        // Monta a onda como GRUPOS: nº de grupos cresce com a onda; cada grupo é um tipo
        // sorteado (swarm/trio/duo/elite) expandido no seu tamanho. Boss a cada 5 ondas.
        var q: [VsEnemyType] = []
        let groups = 2 + w / 2
        for _ in 0..<groups {
            let t = pickType()
            q.append(contentsOf: Array(repeating: t, count: t.groupSize))
        }
        if w % 5 == 0 { q.append(.boss) }
        spawnQueue = q; spawnClock = 0
        recentReceived[.player] = []; recentReceived[.ai] = []   // "recente" = desde a onda anterior
        Audio.shared.sfx("wave")
    }

    private func stepSpawns(dt: Double) {
        guard !spawnQueue.isEmpty else { return }
        spawnClock -= dt
        guard spawnClock <= 0 else { return }
        let t = spawnQueue.removeFirst()
        spawnClock = t == .boss ? 0.2 : max(0.28, 0.55 - Double(state.wave) * 0.01)
        spawnCenter(t)
    }

    /// Sorteia o tipo — semeado (determinístico) no PvP pros dois lados spawnarem igual.
    private func pickType() -> VsEnemyType {
        guard isPvP else { return VsEnemyType.weightedPick() }
        let pool = VsEnemyType.allCases.filter { $0.weight > 0 }
        let total = pool.reduce(0) { $0 + $1.weight }
        var r = Int.random(in: 0..<total, using: &spawnRNG)
        for t in pool { if r < t.weight { return t }; r -= t.weight }
        return .swarm
    }

    private func spawnCenter(_ type: VsEnemyType) {
        let w = max(1, state.wave)
        let el = Element.allCases[(w &+ enemies.count) % Element.allCases.count]
        makeEnemy(lane: .center, element: el, hp: waveHP * type.hpMult, speed: 0.10 * type.speedMult,
                  sizeMult: type.sizeMult, marker: type.marker, boss: type == .boss, elite: type == .elite,
                  bounty: type.bounty, leaks: type.lives, splashResist: type.splashResist)
    }

    /// Construtor genérico de inimigo (usado por ondas E por creeps do mercado).
    @discardableResult
    private func makeEnemy(lane: Lane, element el: Element, hp: Double, speed: Double, sizeMult: Double,
                           marker: String? = nil, boss: Bool = false, elite: Bool = false, bounty: Int,
                           leaks: Int, splashResist: Double, applyOnSpawn: Element? = nil) -> VsEnemy {
        let node = SKNode()
        let s = rangeUnit * 0.6 * CGFloat(sizeMult)
        let dia = CGMutablePath()
        dia.move(to: CGPoint(x: 0, y: s)); dia.addLine(to: CGPoint(x: s, y: 0))
        dia.addLine(to: CGPoint(x: 0, y: -s)); dia.addLine(to: CGPoint(x: -s, y: 0)); dia.closeSubpath()
        let body = SKShapeNode(path: dia)
        body.fillColor = SKColor(red: el.rgb.r, green: el.rgb.g, blue: el.rgb.b, alpha: 1)
        body.strokeColor = lane == .left ? SKColor(red: 0.4, green: 0.9, blue: 0.5, alpha: 1)
                         : lane == .right ? SKColor(red: 1, green: 0.5, blue: 0.5, alpha: 1)
                         : boss ? SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
                         : elite ? SKColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1) : .white
        body.lineWidth = boss || elite ? 3 : 2; node.addChild(body)
        let icon = SKLabelNode(text: marker ?? el.icon); icon.fontSize = rangeUnit * 0.5 * CGFloat(sizeMult)
        icon.verticalAlignmentMode = .center; node.addChild(icon)
        let barW = rangeUnit * 1.1 * CGFloat(sizeMult)
        let bg = SKShapeNode(rect: CGRect(x: -barW/2, y: s + 3, width: barW, height: 3), cornerRadius: 1.5)
        bg.fillColor = SKColor(white: 0, alpha: 0.5); bg.strokeColor = .clear; node.addChild(bg)
        let bar = SKShapeNode(rect: CGRect(x: 0, y: s + 3, width: barW, height: 3), cornerRadius: 1.5)
        bar.fillColor = .green; bar.strokeColor = .clear; bar.position = CGPoint(x: -barW/2, y: 0); node.addChild(bar)
        let st = SKLabelNode(text: ""); st.fontSize = rangeUnit * 0.34; st.verticalAlignmentMode = .center
        st.position = CGPoint(x: 0, y: s + rangeUnit * 0.42); node.addChild(st)
        node.zPosition = boss ? 12 : 10
        enemyLayer.addChild(node)
        let e = VsEnemy(hp: hp, speed: speed, element: el, bounty: bounty, leaks: leaks,
                        splashResist: splashResist, node: node, bar: bar, stroke: body, stLabel: st)
        e.lane = lane
        if lane == .center { e.xOff = (spawnParity ? 1 : -1) * hexSize * 0.6; spawnParity.toggle() }
        placeNode(e)
        enemies.append(e)
        // Creep Elemental: aplica o status do elemento em área ao nascer (combo defensivo forçado).
        if let selEl = applyOnSpawn, let stat = statusFor(selEl) {
            e.until[stat] = gameClock + Status.T.wetDur    // dura o suficiente pra o oponente lidar
            if stat == .burn { e.burnDps = hp * 0.05 }
            if stat == .poison { e.poisonDps = hp * 0.05 }
            updateStatusIcons(e, gameClock)
        }
        return e
    }
    private var spawnParity = false

    private func statusFor(_ e: Element) -> Status? {
        switch e {
        case .fogo: return .burn; case .agua: return .wet; case .gelo: return .frozen
        case .fisico: return .exposed; case .veneno: return .poison; case .arcana: return .marked
        case .natureza: return .rooted
        }
    }

    // MARK: mercado de creeps (economia — enviar = INVESTIMENTO, não gasto)

    /// Renda passiva ACUMULADA por creeps enviados (soma por cima da base +8/s, sem teto).
    private var creepIncome: [VsSide: Int] = [.player: 0, .ai: 0]
    /// Creeps recebidos por lado nas últimas ondas (a IA lê pra reagir).
    private var recentReceived: [VsSide: [VsCreep]] = [.player: [], .ai: []]

    /// Compra um creep: custo pago, renda passiva ADICIONADA ao comprador (permanente), e o
    /// creep nasce na lane do ADVERSÁRIO. `element` só pra o Elemental. Retorna se comprou.
    @discardableResult
    func buyCreep(_ creep: VsCreep, element: Element? = nil, from side: VsSide) -> Bool {
        guard !state.finished else { return false }
        let model = side == .player ? playerModel : aiModel
        guard model.gold >= creep.cost else { return false }
        model.gold -= creep.cost
        // renda composta e permanente, mas com TETO (metade da unidade mais cara).
        let cap = VsScene.incomeCap - VsScene.baseIncome
        creepIncome[side] = min((creepIncome[side] ?? 0) + creep.income, cap)
        if side == .player { state.playerIncome = VsScene.baseIncome + creepIncome[.player, default: 0] }
        else { state.aiIncome = VsScene.baseIncome + creepIncome[.ai, default: 0] }
        let foeLane: Lane = side == .player ? .right : .left    // vai pra base do ADVERSÁRIO
        recentReceived[side == .player ? .ai : .player, default: []].append(creep)
        spawnCreep(creep, element: element, lane: foeLane)
        Audio.shared.sfx("wave")
        return true
    }

    private func spawnCreep(_ creep: VsCreep, element: Element?, lane: Lane) {
        let el = element ?? Element.allCases[(state.wave &+ enemies.count) % Element.allCases.count]
        // Creeps summonados são FORTES (pra pressionar de verdade): HP bem acima do inimigo de onda.
        let base = waveHP
        switch creep {
        case .corredor:
            makeEnemy(lane: lane, element: el, hp: base * 0.9, speed: 0.10 * 1.6, sizeMult: 0.75,
                      bounty: 2, leaks: 1, splashResist: 1.0)
        case .tanque:
            makeEnemy(lane: lane, element: el, hp: base * 6.0, speed: 0.10 * 0.6, sizeMult: 1.5,
                      elite: true, bounty: 3, leaks: 2, splashResist: 0.4)     // vaza valendo 2
        case .enxame:
            for _ in 0..<4 { makeEnemy(lane: lane, element: el, hp: base * 0.7, speed: 0.10 * 1.2,
                                       sizeMult: 0.7, bounty: 1, leaks: 1, splashResist: 1.0) }
        case .elemental:
            makeEnemy(lane: lane, element: el, hp: base * 2.4, speed: 0.10 * 0.9, sizeMult: 1.15,
                      marker: el.icon, bounty: 3, leaks: 1, splashResist: 0.7, applyOnSpawn: el)
        }
    }

    /// Aplica uma ação do jogador REMOTO no lado NORTE (espelhado).
    func applyRemote(_ msg: PvPMsg) {
        switch msg {
        case .place(let q, let r, let id):
            let h = mirror(Hex(q: q, r: r))
            guard buildable.contains(h), towers[h] == nil else { return }
            place(TowerCatalog.spec(id), side: .ai, hex: h)
        case .upgrade(let q, let r):
            if let tw = towers[mirror(Hex(q: q, r: r))], tw.side == .ai { upgradeTower(tw) }
        case .priority(let q, let r, let toCenter):
            if let tw = towers[mirror(Hex(q: q, r: r))], tw.side == .ai {
                tw.priority = toCenter ? .center : .right; updateArrow(tw)
            }
        case .send:
            spawnCreep(.corredor, element: nil, lane: .left)    // oponente me enviou → minha lane
        case .state(let lives, _):
            aiModel.lives = lives
            if lives <= 0 && !state.finished { finish() }
        case .quit:
            aiModel.lives = 0; if !state.finished { finish() }
        case .hello: break
        }
    }

    private func stepEnemies(dt: Double) {
        let now = gameClock
        for e in enemies where !e.dead {
            // DoTs (burn + veneno), atribuídos ao lado que aplicou (conta pra deflexão).
            var dot = 0.0
            if e.active(.burn, now) { dot += e.burnDps; e.addDmg(e.burnDps * dt, e.burnSide) }
            if e.active(.poison, now) { dot += e.poisonDps; e.addDmg(e.poisonDps * dt, e.poisonSide) }
            if dot > 0 { e.hp -= dot * dt; updateBar(e); if e.hp <= 0 { enemyDied(e) } }
            if e.dead { continue }
            updateStatusIcons(e, now)
            let v = e.baseSpeed * (e.slowed(now) ? e.slowFactor : 1.0)
            e.prog += v * dt
            if e.prog >= 1 {
                if e.lane == .center { deflect(e, killed: false) }
                else {
                    let model: GameModel = e.lane == .left ? playerModel : aiModel
                    // morte súbita: onda ≥12 → todo vazamento tira +1 vida extra.
                    let extra = state.wave >= VsScene.suddenDeathWave ? 1 : 0
                    model.lives -= e.leaks + extra
                    e.dead = true; e.node.removeFromParent()
                    if model.lives <= 0 { finish() }
                }
                continue
            }
            placeNode(e)
        }
        enemies.removeAll { $0.dead }
    }

    private func stepTowers(dt: Double) {
        for (_, tw) in towers {
            tw.cooldown -= dt
            guard tw.cooldown <= 0, let target = target(for: tw) else { continue }
            tw.cooldown = tw.cadence
            shootFX(from: tw.pos, to: target.node.position, color: tw.side == .player ? .cyan : .orange)
            applyDamage(tw, to: target)
            // Perfuração: 2º alvo no alcance.
            if tw.has(.perfuracao), let second = enemies.filter({ $0 !== target && valid(tw, $0)
                && $0.node.position.distanceSq(tw.pos) <= tw.rangePx * tw.rangePx }).max(by: { $0.prog < $1.prog }) {
                applyDamage(tw, to: second, factor: TowerAbility.Tuning.pierceFactor, splash: true)
            }
            // Splash/AOE: atinge todos no raio ao redor do alvo.
            if tw.splashHex > 0 {
                let r = CGFloat(tw.splashHex) * hexSize * sqrt(3.0)
                for e in enemies where e !== target && valid(tw, e)
                    && e.node.position.distanceSq(target.node.position) <= r * r {
                    applyDamage(tw, to: e, splash: true)
                }
                flash(at: target.node.position, color: sk(tw.spec.element, 0.4))
            }
        }
    }

    private func valid(_ tw: VsTower, _ e: VsEnemy) -> Bool {
        let ownLane: Lane = tw.side == .player ? .left : .right
        return e.lane == .center || e.lane == ownLane
    }

    /// Alvo: respeita a PRIORIDADE do slot (meio vs própria lane); dentro dela, o mais avançado.
    private func target(for tw: VsTower) -> VsEnemy? {
        let ownLane: Lane = tw.side == .player ? .left : .right
        let inRange = enemies.filter { valid(tw, $0) && $0.node.position.distanceSq(tw.pos) <= tw.rangePx * tw.rangePx }
        let pref = inRange.filter { $0.lane == tw.priority }
        return (pref.isEmpty ? inRange : pref).max { $0.prog < $1.prog }
    }

    /// Dano de um tiro + status do elemento + combos + habilidades.
    private func applyDamage(_ tw: VsTower, to e: VsEnemy, factor: Double = 1, splash: Bool = false) {
        let now = gameClock
        let mult = tw.spec.element.multiplier(against: e.element)
        var dealt = tw.damage * mult * factor
        if tw.spec.splash > 0 { dealt *= e.splashResist }                          // AOE faz menos em elite/boss/duo
        // Combo Estilhaçar: físico em CONGELADO → burst e consome o gelo.
        if tw.spec.element == .fisico && e.active(.frozen, now) { dealt *= Status.T.shatterMult; e.until[.frozen] = 0; comboFlash(e, sk(.gelo, 0.6)) }
        if e.active(.marked, now)  { dealt *= Status.T.markedMult }
        if e.active(.exposed, now) { dealt *= Status.T.exposedMult }
        if tw.has(.estilhacos) && e.slowed(now) { dealt *= TowerAbility.Tuning.shatterBonus }
        if tw.has(.execucao) && e.hp < e.maxHP * TowerAbility.Tuning.execucaoHp { dealt *= TowerAbility.Tuning.execucaoMult }
        if !splash && tw.has(.precisao) && Double.random(in: 0..<1) < TowerAbility.Tuning.critChance { dealt *= TowerAbility.Tuning.critMult }
        e.hp -= dealt; e.addDmg(dealt, tw.side); updateBar(e)
        // status-base do elemento (strikers só no acerto direto; blasters também no splash).
        if let stat = tw.spec.applies, (!splash || tw.spec.splash > 0) { applyStatus(stat, to: e, from: tw, now: now) }
        // Detonador: 2+ status → explode em área.
        if tw.has(.detonador) && !splash && statusCount(e, now) >= TowerAbility.Tuning.detonadorMinStatus {
            explode(around: e, boom: tw.damage * TowerAbility.Tuning.detonadorFrac, side: tw.side, color: sk(.arcana, 0.6))
        }
        if tw.has(.cobranca) && !splash { (tw.side == .player ? playerModel : aiModel).gold += TowerAbility.Tuning.cobrancaPerHit }
        if e.hp <= 0 { enemyDied(e) }
    }

    private func applyStatus(_ st: Status, to e: VsEnemy, from tw: VsTower, now: Double) {
        let pot = tw.has(.potencia) ? TowerAbility.Tuning.potenciaMult : 1.0
        switch st {
        case .burn:
            if e.active(.wet, now) { e.until[.wet] = 0; comboFlash(e, sk(.agua, 0.6)); return }   // molhado apaga fogo
            let boost = tw.has(.queimadura) ? TowerAbility.Tuning.burnBoostMult : 1.0
            e.burnDps = max(e.burnDps, tw.damage * Status.T.burnFrac * boost * pot); e.burnSide = tw.side
            e.until[.burn] = now + Status.T.burnDur * pot
            if e.active(.poison, now) { explode(around: e, boom: tw.damage * Status.T.explosionFrac, side: tw.side, color: sk(.veneno, 0.6)) }
        case .frozen:
            if e.active(.burn, now) { e.until[.burn] = 0; comboFlash(e, sk(.fogo, 0.6)); return }  // fogo impede congelar
            let wet = e.active(.wet, now), deep = tw.has(.profundo) || wet
            if wet { e.until[.wet] = 0; comboFlash(e, sk(.gelo, 0.6)) }
            e.slowFactor = deep ? Status.T.freezeFactor : Status.T.slowFactor
            e.until[.frozen] = now + (deep ? Status.T.freezeDur : Status.T.slowDur) * pot
        case .rooted:
            e.slowFactor = min(e.slowFactor, Status.T.rootedFactor); e.until[.rooted] = now + Status.T.slowDur * pot
        case .poison:
            e.poisonDps += tw.damage * Status.T.poisonFrac * pot; e.poisonSide = tw.side
            e.until[.poison] = now + Status.T.poisonDur * pot
            if e.active(.burn, now) { explode(around: e, boom: tw.damage * Status.T.explosionFrac, side: tw.side, color: sk(.veneno, 0.6)) }
        case .wet:
            if e.active(.burn, now) { e.until[.burn] = 0 }
            e.until[.wet] = now + Status.T.wetDur * pot
        case .exposed: e.until[.exposed] = now + Status.T.exposedDur * pot
        case .marked:  e.until[.marked] = now + Status.T.markedDur * pot
        }
    }

    private func statusCount(_ e: VsEnemy, _ now: Double) -> Int {
        Status.allCases.reduce(0) { $0 + (e.active($1, now) ? 1 : 0) }
    }

    private func explode(around e: VsEnemy, boom: Double, side: VsSide, color: SKColor) {
        let r = rangeUnit * 1.6
        flash(at: e.node.position, color: color)
        for o in enemies where o !== e && o.lane == e.lane
            && o.node.position.distanceSq(e.node.position) <= r * r {
            o.hp -= boom; o.addDmg(boom, side); updateBar(o)
            if o.hp <= 0 { enemyDied(o) }
        }
    }

    /// Morte: no meio → deflexão (vida cheia pro lado que atacou menos); na lane → gold ao dono.
    /// NÃO muta `enemies` (evita crash em iteração); marca `dead` e a limpeza remove depois.
    private func enemyDied(_ e: VsEnemy) {
        guard !e.dead else { return }
        if e.lane == .center { deflect(e, killed: true); return }   // teleporta pra lane do adversário
        e.dead = true
        (e.lane == .left ? playerModel : aiModel).gold += e.bounty
        e.node.removeFromParent()
    }

    private func updateBar(_ e: VsEnemy) { e.bar.xScale = max(0, CGFloat(e.hp / e.maxHP)) }
    private func updateStatusIcons(_ e: VsEnemy, _ now: Double) {
        e.stLabel.text = Status.allCases.filter { e.active($0, now) }.prefix(4).map(\.icon).joined()
    }
    private func sk(_ el: Element, _ a: CGFloat) -> SKColor { SKColor(red: el.rgb.r, green: el.rgb.g, blue: el.rgb.b, alpha: a) }
    private func comboFlash(_ e: VsEnemy, _ color: SKColor) { flash(at: e.node.position, color: color) }
    private func flash(at p: CGPoint, color: SKColor) {
        let f = SKShapeNode(circleOfRadius: rangeUnit * 0.9); f.fillColor = color; f.strokeColor = .clear
        f.position = p; f.zPosition = 9; enemyLayer.addChild(f)
        f.run(.sequence([.group([.scale(to: 1.6, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
    }

    /// Manda um inimigo do meio pra lane do ADVERSÁRIO e teleporta pro INÍCIO dela (vida cheia).
    /// `killed` → decide pelo ÚLTIMO hit (quem matou manda pro outro); senão (sobreviveu o
    /// miolo) → vai pra lane de quem causou MENOS dano.
    private func deflect(_ e: VsEnemy, killed: Bool) {
        let receiver: VsSide
        if killed, let hitter = e.lastHit { receiver = hitter == .player ? .ai : .player }
        else if e.dmgP == e.dmgA { receiver = Bool.random() ? .player : .ai }
        else { receiver = e.dmgP < e.dmgA ? .player : .ai }
        e.lane = receiver == .player ? .left : .right
        e.prog = 0; e.hp = e.maxHP; e.dmgP = 0; e.dmgA = 0; e.lastHit = nil
        e.until = [:]; e.burnDps = 0; e.poisonDps = 0; e.slowFactor = 1; e.stLabel.text = ""
        e.bar.xScale = 1
        e.stroke.strokeColor = receiver == .player ? SKColor(red: 0.4, green: 0.9, blue: 0.5, alpha: 1)
                                                   : SKColor(red: 1, green: 0.5, blue: 0.5, alpha: 1)
        placeNode(e)
    }

    private func income(dt: Double) {
        incomeClock -= dt
        guard incomeClock <= 0 else { return }
        incomeClock = 1.0
        // renda base +8/s + renda composta de creeps enviados (sem teto → runaway intencional).
        playerModel.gold += 8 + creepIncome[.player, default: 0]
        aiModel.gold += 8 + creepIncome[.ai, default: 0]
    }

    private func finish() {
        if playerModel.lives <= 0 && aiModel.lives <= 0 { state.playerWon = playerModel.lives >= aiModel.lives }
        else { state.playerWon = aiModel.lives <= 0 }
        state.finished = true
        playerModel.gameOver = true; aiModel.gameOver = true
        if state.playerWon { state.creditsEarned = meta.addCredits(50) }   // 50 créditos por vitória
    }

    // MARK: IA — colocação livre no seu território (norte), cobrindo o miolo neutro

    private var swappedHexes: Set<Hex> = []    // trava anti-loop: cada hex troca no máximo 1×

    private func aiBuild(dt: Double, side: VsSide, model: GameModel, clock: inout Double) {
        clock -= dt
        guard clock <= 0 else { return }
        clock = 0.6
        balancePriorities(side)     // reage aos creeps recebidos (ajusta ataque/defesa)
        func minPathDist(_ h: Hex) -> Int { pathSet.map { $0.distance(to: h) }.min() ?? 99 }
        let free = buildable.filter { regionOf[$0] == side && towers[$0] == nil }
            .sorted { minPathDist($0) < minPathDist($1) }
        // Constrói VARIADO num bom hex (perto do caminho): escolhe a torre que melhor
        // COMPLEMENTA a composição (diversidade de elemento + mistura área/single).
        if let hex = free.first, let best = compBest(side: side, gold: model.gold) {
            model.gold -= best.cost
            place(best, side: side, hex: hex)
            balancePriorities(side)
            return
        }
        // SWAP (sem loop): troca uma torre NÍVEL-1 redundante por uma que complementa melhor.
        // Trava: cada hex só pode ser trocado UMA vez → impossível oscilar.
        if let (w, better) = compSwap(side: side, gold: model.gold), !swappedHexes.contains(w.hex) {
            let hex = w.hex
            swappedHexes.insert(hex)
            sell(w); model.gold -= better.cost
            place(better, side: side, hex: hex)
            balancePriorities(side)
            return
        }
        // Upa a MELHOR torre acessível (concentra poder na mais forte / mais bem posicionada),
        // não a mais barata. Valor = poder da torre × cobertura do caminho (nº de hexes do
        // caminho no alcance) × nível atual (snowball na já-forte).
        func upValue(_ tw: VsTower) -> Double {
            let cover = Double(pathSet.filter { layout.center(of: $0).distanceSq(tw.pos) <= tw.rangePx * tw.rangePx }.count)
            return score(tw.spec) * (1 + cover) * Double(tw.level)
        }
        let mine = towers.values.filter { $0.side == side && $0.upgradeCost != nil }
        let bestUp = mine.filter { model.gold >= ($0.upgradeCost ?? .max) }
            .max { upValue($0) < upValue($1) }
        let placed = placedIds(side).count
        let defenseCore = placed >= min(3, sideLoadout(side).count)
        let income = VsScene.baseIncome + (creepIncome[side] ?? 0)
        if defenseCore {
            // FASE ECONÔMICA: enquanto a renda não bate o TETO, POUPA e compra Corredor (melhor
            // renda/custo) — NÃO upa (senão o gold nunca acumula pra creep e a renda trava em 8).
            if income < VsScene.incomeCap {
                if model.gold >= VsCreep.corredor.cost { buyCreep(.corredor, from: side); return }
                // guarda uma folga pra 1 upgrade defensivo, senão poupa pro creep.
                if let up = bestUp, model.gold >= (up.upgradeCost ?? .max) + VsCreep.corredor.cost {
                    upgradeTower(up)
                }
                return
            }
            // RENDA NO TETO → PRESSÃO + DEFESA. Manda creep forte (counter Elemental / Enxame) com
            // reserva pra upgrade; e upa a melhor torre com o resto.
            let reserve = 60 + state.wave * 8
            if model.gold >= VsCreep.enxame.cost + reserve {
                if Int.random(in: 0..<2) == 0 { buyCreep(.elemental, element: counterElement(attacker: side), from: side) }
                else { buyCreep(.enxame, from: side) }
                return
            }
        }
        // gold intermediário → upa a MELHOR torre da defesa.
        if let up = bestUp { upgradeTower(up) }
    }

    /// Elemento de COUNTER: o elemento que a defesa do adversário sofre 0.5× (torre dele = dom.next).
    private func counterElement(attacker: VsSide) -> Element {
        let defender: VsSide = attacker == .player ? .ai : .player
        let elems = towers.values.filter { $0.side == defender }.map { $0.spec.element }
        var count: [Element: Int] = [:]; for e in elems { count[e, default: 0] += 1 }
        guard let dom = count.max(by: { $0.value < $1.value })?.key else { return Element.allCases.randomElement()! }
        return Element(rawValue: (dom.rawValue + 1) % Element.allCases.count)!   // dom faz 0.5× nisto
    }

    /// Prioridades: quanto MAIS creeps recebidos recentemente, MAIS torres defendendo a própria lane.
    private func balancePriorities(_ side: VsSide) {
        let mine = towers.values.filter { $0.side == side }.sorted { ($0.hex.r, $0.hex.q) < ($1.hex.r, $1.hex.q) }
        let ownLane: Lane = side == .player ? .left : .right
        let received = recentReceived[side]?.count ?? 0
        let defenseShare = received >= 4 ? 0.7 : received >= 2 ? 0.55 : 0.4   // fração defendendo
        for (i, tw) in mine.enumerated() {
            let frac = mine.isEmpty ? 0 : Double(i) / Double(mine.count)
            let p: Lane = frac < defenseShare ? ownLane : .center
            if tw.priority != p { tw.priority = p; updateArrow(tw) }
        }
    }

    private func sell(_ tw: VsTower) {
        let model = tw.side == .player ? playerModel : aiModel
        let side = tw.side
        model.gold += Int(Double(tw.spec.cost) * 0.6)
        tw.node.removeFromParent()
        towers[tw.hex] = nil
        if side == .player { state.playerPlaced = placedIds(.player) } else { syncAITowers() }
    }

    /// Loadout do lado: o jogador usa o dele; a IA usa o SEU próprio (diferente).
    private func sideLoadout(_ side: VsSide) -> [Int] { side == .player ? loadout : aiLoadout }

    /// A IA monta um loadout PRÓPRIO: 5 torres distintas, variadas em elemento e, de
    /// preferência, diferentes das do jogador → cada partida tem confrontos distintos.
    private func makeAILoadout() -> [Int] {
        let specs = meta.unlockedIds.map { TowerCatalog.spec($0) }
        guard !specs.isEmpty else { return loadout }
        let playerSet = Set(loadout)
        func selScore(_ s: TowerSpec, _ elems: Set<Element>) -> Double {
            var v = score(s)
            if !elems.contains(s.element) { v *= 1.35 }        // diversidade de elemento
            if !playerSet.contains(s.id) { v *= 1.25 }         // diferente do jogador
            return v
        }
        var chosen: [TowerSpec] = []; var elems: Set<Element> = []
        while chosen.count < 5 {
            let rem = specs.filter { c in !chosen.contains { $0.id == c.id } }
            guard let pick = rem.max(by: { selScore($0, elems) < selScore($1, elems) }) else { break }
            chosen.append(pick); elems.insert(pick.element)
        }
        return chosen.map(\.id)
    }

    /// Melhor torre do loadout DO LADO pra ADICIONAR (afford, NÃO repetida), por composição.
    private func compBest(side: VsSide, gold: Int) -> TowerSpec? {
        let placed = placedIds(side)
        return sideLoadout(side).map { TowerCatalog.spec($0) }
            .filter { gold >= $0.cost && !placed.contains($0.id) }      // regra: sem repetir
            .max { compScore($0, side: side) < compScore($1, side: side) }
    }
    /// Par (torre fraca a vender, torre melhor a colocar) se houver ganho claro de composição.
    /// A candidata não pode já estar em campo (exceto a própria que sai).
    private func compSwap(side: VsSide, gold: Int) -> (VsTower, TowerSpec)? {
        let mine = towers.values.filter { $0.side == side && $0.level == 1 }
        var bestGain = 0.30; var result: (VsTower, TowerSpec)? = nil
        for w in mine {
            let placed = placedIds(side).subtracting([w.spec.id])       // a torre que sai libera o slot
            let refund = Int(Double(w.spec.cost) * 0.6)
            let cur = compScore(w.spec, side: side, excluding: w)
            for cand in sideLoadout(side).map({ TowerCatalog.spec($0) })
                where cand.id != w.spec.id && !placed.contains(cand.id) && gold + refund >= cand.cost {
                let gain = compScore(cand, side: side, excluding: w) - cur
                if gain > bestGain { bestGain = gain; result = (w, cand) }
            }
        }
        return result
    }

    /// Pontuação de composição: poder bruto × diversidade de elemento × equilíbrio de papel
    /// × sinergia de combo (fogo+veneno, água/gelo) e anti-combo (fogo⊘água/gelo).
    private func compScore(_ s: TowerSpec, side: VsSide, excluding: VsTower? = nil) -> Double {
        let others = towers.values.filter { $0.side == side && $0 !== excluding }
        let elems = others.map { $0.spec.element }
        let strikers = others.filter { $0.spec.role == .striker }.count
        let blasters = others.filter { $0.spec.role == .blaster }.count
        var m = 1.0
        m *= elems.contains(s.element) ? 0.7 : 1.25                       // diversidade
        switch s.role {                                                   // mistura área/single
        case .blaster: m *= blasters <= strikers ? 1.2 : 0.85
        case .striker: m *= strikers <= blasters ? 1.15 : 0.9
        case .support: m *= 0.8
        }
        if (s.element == .veneno && elems.contains(.fogo)) || (s.element == .fogo && elems.contains(.veneno)) { m *= 1.3 }
        if (s.element == .agua || s.element == .gelo) && elems.contains(where: { $0 == .agua || $0 == .gelo }) { m *= 1.2 }
        if s.element == .fogo && elems.contains(where: { $0 == .agua || $0 == .gelo }) { m *= 0.55 }
        if (s.element == .agua || s.element == .gelo) && elems.contains(.fogo) { m *= 0.55 }
        return score(s) * m
    }
    private func score(_ s: TowerSpec) -> Double {
        let dps = s.baseDamage * meta.statMult(s.id) / s.cooldown * (s.splash > 0 ? 1.4 : 1.0)
        return dps * (1 + 0.09 * Double(max(0, meta.maxStars(s.id) - 2)))
    }

    private func shootFX(from: CGPoint, to: CGPoint, color: SKColor) {
        let dot = SKShapeNode(circleOfRadius: rangeUnit * 0.12)
        dot.fillColor = color; dot.strokeColor = .clear; dot.position = from; dot.zPosition = 8
        towerLayer.addChild(dot)
        dot.run(.sequence([.move(to: to, duration: 0.07), .removeFromParent()]))
    }
}

private extension CGPoint {
    func distanceSq(_ o: CGPoint) -> CGFloat { let dx = x - o.x, dy = y - o.y; return dx * dx + dy * dy }
}
