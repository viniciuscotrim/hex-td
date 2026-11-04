import SpriteKit

/// Estado observável do Vs v3.
final class VsV3State: ObservableObject {
    @Published var wave = 0
    @Published var finished = false
    @Published var playerWon = false
    @Published var creditsEarned = 0
    @Published var playerGold = 0
    @Published var playerLives = 5
    @Published var aiLives = 5
    @Published var waveElementIcon = ""   // elemento dominante da onda atual (70%)
    @Published var bossBanner = ""        // anúncio central do boss (vazio = escondido)
    @Published var bossBannerDesc = ""
}

/// Mapeamentos entre o catálogo (strings) e o motor (Element/ícones).
enum VsV3Map {
    static func element(_ s: String) -> Element {
        switch s { case "fire": .fogo; case "water": .agua; case "ice": .gelo; case "phys": .fisico
                   case "poison": .veneno; case "arcane": .arcana; default: .natureza }
    }
    static func icon(_ k: VsStatusKind) -> String {
        switch k { case .burn: "🔥"; case .wet: "💧"; case .frozen: "❄️"; case .exposed: "🎯"
                   case .poison: "☠️"; case .marked: "🔮"; case .rooted: "🌿" }
    }
    /// Alcance em hexes por papel (blaster = alc-1; Balista perfura em linha longa).
    static func range(role: String, isBalista: Bool) -> Int {
        if isBalista { return 4 }
        switch role { case "blaster": return 1; case "support": return 2; default: return 2 }
    }
}

/// Torre-unidade do Vs v3: catálogo novo + estrela (raridade via merge).
private final class V3Tower {
    var unit: VsUnit
    let side: VsSide
    var cooldown = 0.0
    let node: SKNode
    var pos: CGPoint
    init(unit: VsUnit, side: VsSide, node: SKNode, pos: CGPoint) {
        self.unit = unit; self.side = side; self.node = node; self.pos = pos
    }
    var spec: VsTowerSpec { VsCatalog.spec(unit.specId)! }
    var damage: Double { spec.baseDamage * VsCatalog.statMult(tier: unit.star) }
    var cadence: Double { spec.cooldown }
    var isBalista: Bool { unit.specId == "phys_bla" }
    var rangeHex: Int { VsV3Map.range(role: unit.role, isBalista: isBalista) }
}

/// Pool de bosses. Cada um tem elemento predominante, cadência (a cada N tiles dispara a habilidade)
/// e MUITO HP. Entram no 19 e vão pro lado OPOSTO de quem deu mais dano.
enum BossKind: Int, CaseIterable {
    case demolidor = 1, mutante, permutador, embaralhador
    var name: String { switch self { case .demolidor: "Demolidor"; case .mutante: "Mutante"; case .permutador: "Permutador"; case .embaralhador: "Embaralhador" } }
    var icon: String { switch self { case .demolidor: "💥"; case .mutante: "🧬"; case .permutador: "🔀"; case .embaralhador: "🌀" } }
    var element: Element { switch self { case .demolidor: .fisico; case .mutante: .arcana; case .permutador: .veneno; case .embaralhador: .gelo } }
    var cadence: Int { (self == .demolidor || self == .embaralhador) ? 4 : 3 }
    var desc: String {
        switch self {
        case .demolidor:    "Destrói 1 torre de cada lado a cada 4 tiles"
        case .mutante:      "Muda 1 torre e o elemento a cada 3 tiles (mantém ⭐)"
        case .permutador:   "Troca 1 torre entre os lados a cada 3 tiles"
        case .embaralhador: "Embaralha as posições das torres a cada 4 tiles"
        }
    }
}

private final class V3Enemy {
    var route: [Hex]            // sequência de hexes (neutro + arco)
    var neutralCount: Int       // nº de hexes iniciais que são NEUTROS (contestados)
    var arcSide: VsSide         // dono do arco = quem defende e leva o vazamento
    var prog = 0.0
    var hp: Double; let maxHP: Double; let baseSpeed: Double
    let element: Element; let bounty: Int; let leaks: Int; let isBoss: Bool
    var status = VsStatusState()
    var lastHit: VsSide? = nil
    var dead = false
    // BOSS (nil pra monstro comum): posição assinada a partir do 19 (>0 vermelho/IA, <0 verde/jogador),
    // dano acumulado por lado (decide a direção), cadência de habilidade e trava ao entrar num arco.
    var boss: BossKind? = nil
    var bossPos = 0.0
    var bossLocked = false
    var bossDefaultDir = 1.0
    var dmgByPlayer = 0.0, dmgByAI = 0.0
    var bossTilesDone = 0
    var bossTilesAcc = 0.0
    let node: SKNode; let bar: SKShapeNode; let stroke: SKShapeNode; let stLabel: SKLabelNode
    init(route: [Hex], neutralCount: Int, arcSide: VsSide, hp: Double, speed: Double, element: Element,
         bounty: Int, leaks: Int, isBoss: Bool, node: SKNode, bar: SKShapeNode, stroke: SKShapeNode, stLabel: SKLabelNode) {
        self.route = route; self.neutralCount = neutralCount; self.arcSide = arcSide
        self.hp = hp; self.maxHP = hp; self.baseSpeed = speed; self.element = element
        self.bounty = bounty; self.leaks = leaks; self.isBoss = isBoss
        self.node = node; self.bar = bar; self.stroke = stroke; self.stLabel = stLabel
    }
    /// Índice do hex atual na rota.
    var idx: Int { route.isEmpty ? 0 : max(0, min(route.count - 1, Int((prog * Double(route.count - 1)).rounded()))) }
    /// Ainda na parte NEUTRA (contestada por ambos)?
    var contested: Bool { idx < neutralCount }
    func mark(_ s: VsSide) { lastHit = s }
}

/// Vs v3 — SPAWN/MERGE + combate redesenhado. Mapa yin-yang N/S, tug-of-war central. Torres
/// nascem Comuns; fundir 2 iguais sobe estrela. Combos por adjacência (elementos diferentes)
/// suprimem o tiro individual. Status/propagação vêm dos módulos T2–T4. Economia do §10.
final class VsSceneV3: SKScene {
    private unowned let meta: MetaProgress
    private unowned let state: VsV3State
    let palette: [String]                 // ids de torres que o jogador pode spawnar
    var selectedSpec = "fire_str"

    private let boardLayer = SKNode(), towerLayer = SKNode(), enemyLayer = SKNode(), fxLayer = SKNode()
    private var layout = HexLayout(size: 10, origin: .zero)
    private var cells: [Hex] = []
    private var regionOf: [Hex: VsSide] = [:]
    private var neutralPath: [Hex] = [], playerPath: [Hex] = [], aiPath: [Hex] = []
    private var pathSet: Set<Hex> = [], buildable: Set<Hex> = []
    private var hexSize: CGFloat = 24, rangeUnit: CGFloat = 24, midY: CGFloat = 0

    private var towers: [Hex: V3Tower] = [:]
    private var enemies: [V3Enemy] = []
    private var comboCooldown: [Set<Hex>: Double] = [:]
    private var comboFX: [Set<Hex>: SKNode] = [:]   // arte de destaque por par de torres em combo
    // Viés de elemento por lado, sorteado a cada partida → o Auto varia a composição entre jogos
    // (sem isto o planner é determinístico e converge sempre pro mesmo trio phys+gelo+água).
    private var aiBias: [VsSide: [String: Double]] = [:]

    private var lastTime: TimeInterval = 0, gameClock = 0.0
    private var waveClock = 3.0; private let waveInterval = 16.0
    private var spawnQueue: [VsEnemyType] = []; private var spawnClock = 0.0; private var waveHP = 20.0
    private var waveElement: Element = .fogo   // elemento dominante da onda (70% dos monstros)
    private var aiClock = 0.0
    private var playerGold = 160, aiGold = 160
    private var playerLives = 5, aiLives = 5

    static let startLives = 5, suddenDeathWave = 12, baseIncome = 8

    init(meta: MetaProgress, state: VsV3State, palette: [String], size: CGSize) {
        self.meta = meta; self.state = state; self.palette = palette
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 1)
        selectedSpec = palette.first ?? "fire_str"
        let elems = ["fire","water","ice","phys","poison","arcane","nature"]
        for side in [VsSide.player, .ai] {
            aiBias[side] = Dictionary(uniqueKeysWithValues: elems.map { ($0, Double.random(in: 0.5...1.7)) })
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = meta.frameLimit
        [boardLayer, towerLayer, enemyLayer, fxLayer].forEach(addChild)
        computeLayout(); drawBoard(); pushHUD()
    }
    override func didChangeSize(_ old: CGSize) {
        super.didChangeSize(old)
        guard size.width > 0, boardLayer.parent != nil else { return }
        computeLayout(); drawBoard()
        for (h, t) in towers { t.pos = layout.center(of: h); t.node.position = t.pos }
    }

    // MARK: layout (yin-yang N/S — mesmo do modo atual)

    // MAPA FIXO (desenhado na grade numerada): anel "0" com linha neutra cortando o meio.
    private static func hx(_ l: [(Int, Int)]) -> [Hex] { l.map { Hex(q: $0.0, r: $0.1) } }
    static let mNeutral  = hx([(-2,0),(-1,0),(0,0),(1,0),(2,0)])                                    // 17-21
    static let mGreen    = hx([(-2,-1),(-1,-2),(0,-3),(1,-4),(2,-4),(3,-4),(3,-3),(3,-2),(3,-1)])   // 22→…→27 (saída)
    static let mRed      = hx([(2,1),(1,2),(0,3),(-1,4),(-2,4),(-3,4),(-3,3),(-3,2),(-3,1)])         // 16→…→11 (saída)
    static let mPlayerBuild = hx([(-1,-1),(0,-1),(1,-1),(2,-1),(0,-2),(1,-2),(2,-2),(1,-3),(2,-3)])  // 23-26,29-31,34-35
    static let mAiBuild     = hx([(-2,3),(-1,3),(-2,2),(-1,2),(0,2),(-2,1),(-1,1),(0,1),(1,1)])       // 3-4,7-9,12-15
    // ROTAS: A nasce em 17, cruza o neutro e sobe pelo arco VERMELHO → saída 11 (IA); B nasce
    // em 21, cruza e desce pelo arco VERDE → saída 27 (jogador). Os dois cruzam no 19.
    static let routeA: [Hex] = mNeutral + mRed                 // 17→21 → 16→…→11
    static let routeB: [Hex] = Array(mNeutral.reversed()) + mGreen  // 21→17 → 22→…→27
    static let neutralLen = 5
    // BOSS: entra no 19 (centro) e vai pra UM lado. Caminho vermelho = 19,20,21 + arco IA (→11);
    // verde = 19,18,17 + arco jogador (→27). Índices 0-2 são neutros; 3 é o 1º tile do arco.
    static let bossRedPath:   [Hex] = [mNeutral[2], mNeutral[3], mNeutral[4]] + mRed
    static let bossGreenPath: [Hex] = [mNeutral[2], mNeutral[1], mNeutral[0]] + mGreen
    static let bossNeutralLen = 3

    private func computeLayout() {
        let W = size.width, H = size.height
        let unit = HexLayout(size: 1, origin: .zero)
        cells = VsSceneV3.mNeutral + VsSceneV3.mGreen + VsSceneV3.mRed + VsSceneV3.mPlayerBuild + VsSceneV3.mAiBuild
        let uc = cells.map { unit.center(of: $0) }
        let minX = uc.map(\.x).min()!, maxX = uc.map(\.x).max()!, minY = uc.map(\.y).min()!, maxY = uc.map(\.y).max()!
        hexSize = min(W*0.98/(maxX-minX+1.4), H*0.98/(maxY-minY+1.4)); rangeUnit = hexSize
        layout = HexLayout(size: hexSize, origin: CGPoint(x: W/2 - hexSize*((minX+maxX)/2), y: H/2 - hexSize*((minY+maxY)/2)))
        midY = layout.origin.y
        neutralPath = VsSceneV3.mNeutral            // linha divisória (spawn/contestado)
        playerPath = VsSceneV3.mGreen               // arco de BAIXO (você) → saída 27
        aiPath = VsSceneV3.mRed                      // arco de CIMA (IA) → saída 11
        pathSet = Set(neutralPath).union(playerPath).union(aiPath)
        buildable = Set(VsSceneV3.mPlayerBuild).union(VsSceneV3.mAiBuild)   // só o MIOLO
        regionOf = [:]
        for h in VsSceneV3.mPlayerBuild { regionOf[h] = .player }
        for h in VsSceneV3.mAiBuild { regionOf[h] = .ai }
        for h in cells where regionOf[h] == nil { regionOf[h] = h.r > 0 ? .ai : .player }
    }

    // MARK: caminho contínuo (hexes adjacentes, sem backtrack)

    private func cube(_ h: Hex) -> (Double, Double, Double) { (Double(h.q), Double(-h.q - h.r), Double(h.r)) }
    private func hexRound(_ x: Double, _ y: Double, _ z: Double) -> Hex {
        var rx = x.rounded(), ry = y.rounded(), rz = z.rounded()
        let dx = abs(rx - x), dy = abs(ry - y), dz = abs(rz - z)
        if dx > dy && dx > dz { rx = -ry - rz } else if dy > dz { ry = -rx - rz } else { rz = -rx - ry }
        return Hex(q: Int(rx), r: Int(rz))
    }
    /// Reta hexagonal (hexes ADJACENTES) de `a` a `b`.
    private func hexLine(_ a: Hex, _ b: Hex) -> [Hex] {
        let n = a.distance(to: b); guard n > 0 else { return [a] }
        let ca = cube(a), cb = cube(b); var out: [Hex] = []
        for i in 0...n {
            let t = Double(i) / Double(n)
            let h = hexRound(ca.0 + (cb.0 - ca.0)*t, ca.1 + (cb.1 - ca.1)*t, ca.2 + (cb.2 - ca.2)*t)
            if h != out.last { out.append(h) }
        }
        return out
    }
    /// Curva (bezier) amostrada → snap a cells → conecta buracos com reta hexagonal e remove
    /// backtrack → caminho CONTÍNUO de hexes adjacentes (o monstro nunca bate e volta).
    private func cleanPath(_ a: Hex, _ b: Hex, ctrl: CGPoint, unit: HexLayout, samples: Int = 60) -> [Hex] {
        let pa = unit.center(of: a), pb = unit.center(of: b); var out: [Hex] = []
        func push(_ h: Hex) {
            if h == out.last { return }
            if out.count >= 2 && h == out[out.count - 2] { return }   // anti-backtrack
            out.append(h)
        }
        for i in 0...samples {
            let t = CGFloat(i) / CGFloat(samples), u = 1 - t
            let p = CGPoint(x: u*u*pa.x + 2*u*t*ctrl.x + t*t*pb.x, y: u*u*pa.y + 2*u*t*ctrl.y + t*t*pb.y)
            guard let c = cells.min(by: { unit.center(of: $0).distanceSq(p) < unit.center(of: $1).distanceSq(p) }) else { continue }
            if out.isEmpty { out.append(c); continue }
            if c == out.last { continue }
            let d = out.last!.distance(to: c)
            if d == 1 { push(c) } else { for h in hexLine(out.last!, c).dropFirst() { push(h) } }
        }
        return out
    }

    private func pointOn(_ path: [Hex], _ p: Double) -> CGPoint {
        guard let f0 = path.first else { return CGPoint(x: size.width/2, y: size.height/2) }
        if path.count == 1 { return layout.center(of: f0) }
        let f = min(max(p, 0), 1)*Double(path.count-1); let i = min(path.count-2, Int(f)); let fr = CGFloat(f - Double(i))
        let a = layout.center(of: path[i]), b = layout.center(of: path[i+1])
        return CGPoint(x: a.x+(b.x-a.x)*fr, y: a.y+(b.y-a.y)*fr)
    }
    private func enemyPos(_ e: V3Enemy) -> CGPoint { pointOn(e.route, e.prog) }
    private func hexAt(_ p: CGPoint) -> Hex? {
        cells.min { layout.center(of: $0).distanceSq(p) < layout.center(of: $1).distanceSq(p) }
            .flatMap { layout.center(of: $0).distanceSq(p) <= hexSize*hexSize ? $0 : nil }
    }

    private func drawBoard() {
        boardLayer.removeAllChildren()
        let aiBase = aiPath.last, pBase = playerPath.last
        for h in cells {
            var pts = layout.corners(of: h); pts.append(pts[0])
            let poly = SKShapeNode(points: &pts, count: pts.count)
            poly.lineWidth = 1; poly.strokeColor = SKColor(white: 0.10, alpha: 0.9)
            let side = regionOf[h] ?? .player
            if h == aiBase { poly.fillColor = SKColor(red: 0.95, green: 0.35, blue: 0.38, alpha: 1) }
            else if h == pBase { poly.fillColor = SKColor(red: 0.30, green: 0.85, blue: 0.55, alpha: 1) }
            else if neutralPath.contains(h) { poly.fillColor = SKColor(white: 0.72, alpha: 1) }
            else if aiPath.contains(h) || playerPath.contains(h) {
                poly.fillColor = side == .player ? SKColor(red:0.22,green:0.58,blue:0.40,alpha:1) : SKColor(red:0.66,green:0.26,blue:0.30,alpha:1)
            } else {
                poly.fillColor = side == .player ? SKColor(red:0.11,green:0.28,blue:0.21,alpha:1) : SKColor(red:0.28,green:0.14,blue:0.17,alpha:1)
            }
            boardLayer.addChild(poly)
        }
        let line = SKShapeNode(rect: CGRect(x: 0, y: midY-1.5, width: size.width, height: 3))
        line.fillColor = SKColor(white: 1, alpha: 0.35); line.strokeColor = .clear; boardLayer.addChild(line)
    }

    // MARK: toque — spawn / merge

    private var mergeSource: Hex?     // torre selecionada pro merge (click-and-point)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !state.finished, let p = touches.first?.location(in: self) else { return }
        // 0) botão VENDER da torre selecionada (testa antes de mapear pra hex — o botão fica fora dela).
        if let src = mergeSource, nodes(at: p).contains(where: { $0.name == "sellBtn" }) { sellTower(src); return }
        guard let h = hexAt(p) else { return }
        // 1) tocou numa torre SUA → seleção/merge explícito.
        if let t = towers[h], t.side == .player {
            if let src = mergeSource {
                if src == h { clearSelection(); return }                     // toca a mesma → desmarca
                // Com só 10 tiles por lado, merge NÃO exige adjacência: 2 iguais quaisquer fundem.
                if let s = towers[src], VsMerge.canMerge(s.unit, t.unit),
                   let m = VsMerge.merge(s.unit, t.unit) {
                    t.unit = m; refreshTowerNode(t)                          // resultado fica NO ALVO (2º clique)
                    s.node.removeFromParent(); towers[src] = nil
                    Audio.shared.sfx("place"); clearSelection(); pushHUD(); return
                }
                selectMerge(h); return                                       // não-fundível → reseleciona
            }
            selectMerge(h); return                                          // 1º clique → seleciona a origem
        }
        // 2) hex vazio do seu lado → spawna Comum. (limpa qualquer seleção)
        clearSelection()
        guard regionOf[h] == .player, buildable.contains(h), towers[h] == nil else { return }
        spawnCommon(specId: selectedSpec, side: .player, at: h)
    }

    private func selectMerge(_ h: Hex) {
        clearSelection(); mergeSource = h
        guard let t = towers[h] else { return }
        // círculo de ALCANCE (semitransparente) por baixo da torre.
        let rangePx = CGFloat(t.rangeHex) * hexSize * sqrt(3.0)
        let area = SKShapeNode(circleOfRadius: rangePx); area.name = "range"
        area.fillColor = SKColor(white: 1, alpha: 0.12); area.strokeColor = SKColor(white: 1, alpha: 0.35); area.lineWidth = 1.5
        area.zPosition = -1; t.node.addChild(area)
        let ring = SKShapeNode(circleOfRadius: rangeUnit * 0.85)
        ring.strokeColor = .yellow; ring.lineWidth = 3; ring.fillColor = .clear; ring.name = "sel"
        ring.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.4), .fadeAlpha(to: 1, duration: 0.4)])))
        t.node.addChild(ring)
        // botão VENDER (metade do investido, upgrades somados) abaixo da torre.
        let bw = rangeUnit*2.0, bh = rangeUnit*0.82, by = -rangeUnit*1.55
        let btn = SKShapeNode(rect: CGRect(x: -bw/2, y: by - bh/2, width: bw, height: bh), cornerRadius: bh*0.42)
        btn.fillColor = SKColor(red:0.86,green:0.24,blue:0.30,alpha:0.96); btn.strokeColor = .white; btn.lineWidth = 1.5
        btn.name = "sellBtn"; btn.zPosition = 30
        let lbl = SKLabelNode(text: "Vender 💰\(refundValue(t))"); lbl.name = "sellBtn"
        lbl.fontSize = rangeUnit*0.42; lbl.fontColor = .white; lbl.verticalAlignmentMode = .center; lbl.position = CGPoint(x: 0, y: by)
        btn.addChild(lbl); t.node.addChild(btn)
    }
    private func clearSelection() {
        if let h = mergeSource, let n = towers[h]?.node {
            n.childNode(withName: "sel")?.removeFromParent()
            n.childNode(withName: "sellBtn")?.removeFromParent()
            n.childNode(withName: "range")?.removeFromParent()
        }
        mergeSource = nil
    }
    /// Reembolso da venda: metade do total investido = custo × 2^estrela (cada ★ dobra os Comuns).
    private func refundValue(_ t: V3Tower) -> Int { (t.spec.cost * (1 << t.unit.star)) / 2 }
    private func sellTower(_ h: Hex) {
        guard let t = towers[h] else { return }
        if t.side == .player { playerGold += refundValue(t) } else { aiGold += refundValue(t) }
        clearSelection()
        t.node.removeFromParent(); towers[h] = nil
        Audio.shared.sfx("place"); pushHUD()
    }

    /// Spawna uma torre COMUM (★0) num hex VAZIO (paga o custo). `autoMerge` só pra IA.
    private func spawnCommon(specId: String, side: VsSide, at h: Hex, autoMerge: Bool = false) {
        guard towers[h] == nil, let unit = VsMerge.spawn(specId: specId, at: h) else { return }
        let cost = VsCatalog.spec(specId)!.cost
        guard goldFor(side) >= cost else { return }
        spend(side, cost)
        place(unit, side: side, at: h)
        Audio.shared.sfx("place")
        if autoMerge { resolveMerges(side) }    // IA funde sozinha; o jogador funde manualmente (click-and-point)
        pushHUD()
    }

    /// MERGE sem adjacência (só 10 tiles/lado): enquanto houver 2 torres do MESMO lado IGUAIS
    /// (elem+papel+estrela), funde. Cascateia (★0→★1→★2…). O resultado FICA na posição que já
    /// forma COMBO (vizinho de outro elemento que combina); senão, no hex mais perto da entrada.
    private func resolveMerges(_ side: VsSide) {
        var merged = true, guardN = 0
        while merged && guardN < 200 {   // cap defensivo (nunca deve chegar perto)
            merged = false; guardN += 1
            let mine = towers.filter { $0.value.side == side }.sorted { ($0.key.r, $0.key.q) < ($1.key.r, $1.key.q) }
            outer: for i in 0..<mine.count {
                let (ha, ta) = mine[i]
                for j in (i+1)..<mine.count {
                    let (hb, tb) = mine[j]
                    guard VsMerge.canMerge(ta.unit, tb.unit), let m = VsMerge.merge(ta.unit, tb.unit) else { continue }
                    // 1º critério: mantém onde JÁ TEM COMBO; desempate: mais perto da entrada.
                    let comboA = formsCombo(at: ha, element: m.element, side: side, excluding: hb)
                    let comboB = formsCombo(at: hb, element: m.element, side: side, excluding: ha)
                    let keepA = comboA != comboB ? comboA : (distToEntry(ha, side) <= distToEntry(hb, side))
                    let keeper = keepA ? ta : tb, gonerHex = keepA ? hb : ha
                    keeper.unit = m; refreshTowerNode(keeper)
                    towers[gonerHex]?.node.removeFromParent(); towers[gonerHex] = nil
                    merged = true
                    break outer
                }
            }
        }
    }
    /// A posição `h` forma combo? (vizinho do MESMO lado, de elemento diferente, que combina com `el`.)
    private func formsCombo(at h: Hex, element el: String, side: VsSide, excluding: Hex) -> Bool {
        for hn in h.neighbors where hn != excluding {
            guard let n = towers[hn], n.side == side, n.unit.element != el else { continue }
            if VsCatalog.combo(n.unit.element, el) != nil { return true }
        }
        return false
    }

    @discardableResult
    private func place(_ unit: VsUnit, side: VsSide, at h: Hex) -> V3Tower {
        let p = layout.center(of: h)
        let node = SKNode(); node.position = p
        let el = VsV3Map.element(unit.element)
        let disc = SKShapeNode(circleOfRadius: rangeUnit*0.66)
        disc.fillColor = SKColor(red: el.rgb.r, green: el.rgb.g, blue: el.rgb.b, alpha: 1)
        disc.strokeColor = side == .player ? SKColor(red:0.4,green:0.85,blue:1,alpha:1) : SKColor(red:1,green:0.5,blue:0.5,alpha:1)
        disc.lineWidth = 3; disc.name = "disc"; node.addChild(disc)
        let icon = SKLabelNode(text: unit.role == "striker" ? "▲" : unit.role == "blaster" ? "⬢" : "■")
        icon.fontSize = rangeUnit*0.6; icon.verticalAlignmentMode = .center; icon.name = "role"; node.addChild(icon)
        let em = SKLabelNode(text: VsCatalog.spec(unit.specId)!.emoji); em.fontSize = rangeUnit*0.4
        em.verticalAlignmentMode = .center; em.position = CGPoint(x: 0, y: rangeUnit*0.02); em.name = "emoji"; node.addChild(em)
        let stars = SKLabelNode(text: starText(unit.star)); stars.fontSize = rangeUnit*0.34; stars.name = "stars"
        stars.verticalAlignmentMode = .center; stars.position = CGPoint(x: 0, y: -rangeUnit*0.78); stars.fontColor = .yellow; node.addChild(stars)
        towerLayer.addChild(node)
        let t = V3Tower(unit: unit, side: side, node: node, pos: p)
        towers[h] = t
        return t
    }
    private func starText(_ s: Int) -> String { s <= 0 ? "" : String(repeating: "★", count: min(s, 5)) }
    private func refreshTowerNode(_ t: V3Tower) {
        (t.node.childNode(withName: "stars") as? SKLabelNode)?.text = starText(t.unit.star)
        t.node.run(.sequence([.scale(to: 1.2, duration: 0.08), .scale(to: 1, duration: 0.08)]))
    }

    private func goldFor(_ s: VsSide) -> Int { s == .player ? playerGold : aiGold }
    private func spend(_ s: VsSide, _ c: Int) { if s == .player { playerGold -= c } else { aiGold -= c } }

    // MARK: loop

    override func update(_ currentTime: TimeInterval) {
        if lastTime == 0 { lastTime = currentTime }
        let dt = min(currentTime - lastTime, 1.0/20.0); lastTime = currentTime
        guard !state.finished else { return }
        gameClock += dt
        // Próxima onda só começa quando a atual TERMINOU de spawnar e o campo não está lotado —
        // evita acúmulo infinito de inimigos (que derrubava o framerate).
        waveClock -= dt
        if waveClock <= 0 && spawnQueue.isEmpty && enemies.count < 45 { startWave() }
        stepSpawns(dt: dt); stepEnemies(dt: dt); stepTowers(dt: dt)
        enemies.removeAll { $0.dead }
        aiStep(dt: dt); pushHUD()
        if playerLives <= 0 || aiLives <= 0 { finish() }   // rede de segurança: garante a tela de fim
    }

    private func pushHUD() {
        state.playerGold = playerGold; state.playerLives = max(0, playerLives)
        state.aiLives = max(0, aiLives)
    }

    // MARK: ondas / inimigos (tug-of-war central, igual ao modo atual)

    private func startWave() {
        state.wave += 1; waveClock = waveInterval
        waveHP = Progression.enemyHP(wave: state.wave) * 2.2 * pow(1.06, Double(state.wave))
        // A cada 5 ondas → ONDA DE BOSS: anúncio central + o boss entra no 19 (sem stream normal).
        if state.wave % 5 == 0 {
            let kind = BossKind.allCases.randomElement() ?? .demolidor
            waveElement = kind.element; state.waveElementIcon = waveElement.icon
            announceBoss(kind); spawnBoss(kind)
            spawnQueue = []; spawnClock = 0; Audio.shared.sfx("wave")
            return
        }
        waveElement = Element.allCases.randomElement() ?? .fogo   // dominante desta onda
        state.waveElementIcon = waveElement.icon
        var q: [VsEnemyType] = []
        // Ondas mais longas: bem mais grupos (crescendo com a onda) → mais monstros, demora mais.
        for _ in 0..<(6 + state.wave) { let t = VsEnemyType.weightedPick(); q.append(contentsOf: Array(repeating: t, count: t.groupSize)) }
        spawnQueue = q; spawnClock = 0; Audio.shared.sfx("wave")
    }
    private func announceBoss(_ kind: BossKind) {
        state.bossBanner = "\(kind.icon) BOSS: \(kind.name)"
        state.bossBannerDesc = kind.desc
        run(.sequence([.wait(forDuration: 3.5), .run { [weak self] in self?.state.bossBanner = ""; self?.state.bossBannerDesc = "" }]))
    }
    /// 70% do elemento dominante da onda, 30% variado entre os demais.
    private func pickWaveElement() -> Element {
        if Double.random(in: 0..<1) < 0.7 { return waveElement }
        return Element.allCases.filter { $0 != waveElement }.randomElement() ?? waveElement
    }
    private func stepSpawns(dt: Double) {
        guard !spawnQueue.isEmpty else { return }
        guard enemies.count < 150 else { return }   // trava dura de performance (não deixa lotar)
        spawnClock -= dt; guard spawnClock <= 0 else { return }
        let t = spawnQueue.removeFirst()
        spawnClock = t == .boss ? 0.35 : max(0.40, 0.65 - Double(state.wave)*0.008)
        spawnCenter(t)
    }
    private func spawnCenter(_ type: VsEnemyType) {
        // Duas correntes por evento: uma nasce em 17 (rota A → arco vermelho, saída da IA), outra
        // em 21 (rota B → arco verde, saída do jogador). Elas se cruzam no 19 se ninguém matar.
        let el = pickWaveElement()   // mesmo elemento nas duas correntes (monstros simétricos)
        spawnStream(type, arc: .ai,     route: VsSceneV3.routeA, element: el)
        spawnStream(type, arc: .player, route: VsSceneV3.routeB, element: el)
    }
    private func spawnStream(_ type: VsEnemyType, arc: VsSide, route: [Hex], element el: Element) {
        let s = rangeUnit*0.6*CGFloat(type.sizeMult)
        let node = SKNode()
        let dia = CGMutablePath(); dia.move(to: CGPoint(x:0,y:s)); dia.addLine(to: CGPoint(x:s,y:0))
        dia.addLine(to: CGPoint(x:0,y:-s)); dia.addLine(to: CGPoint(x:-s,y:0)); dia.closeSubpath()
        let body = SKShapeNode(path: dia); body.fillColor = SKColor(red:el.rgb.r,green:el.rgb.g,blue:el.rgb.b,alpha:1)
        body.strokeColor = type == .boss ? SKColor(red:1,green:0.85,blue:0.2,alpha:1) : type == .elite ? SKColor(red:0.95,green:0.35,blue:0.35,alpha:1) : .white
        body.lineWidth = type == .boss || type == .elite ? 3 : 2; node.addChild(body)
        let icon = SKLabelNode(text: type.marker ?? el.icon); icon.fontSize = rangeUnit*0.5*CGFloat(type.sizeMult)
        icon.verticalAlignmentMode = .center; node.addChild(icon)
        let barW = rangeUnit*1.1*CGFloat(type.sizeMult)
        let bg = SKShapeNode(rect: CGRect(x:-barW/2,y:s+3,width:barW,height:3), cornerRadius: 1.5); bg.fillColor = SKColor(white:0,alpha:0.5); bg.strokeColor = .clear; node.addChild(bg)
        let bar = SKShapeNode(rect: CGRect(x:0,y:s+3,width:barW,height:3), cornerRadius: 1.5); bar.fillColor = .green; bar.strokeColor = .clear; bar.position = CGPoint(x:-barW/2,y:0); node.addChild(bar)
        let st = SKLabelNode(text: ""); st.fontSize = rangeUnit*0.34; st.verticalAlignmentMode = .center; st.position = CGPoint(x:0,y:s+rangeUnit*0.42); node.addChild(st)
        node.zPosition = type == .boss ? 12 : 10; enemyLayer.addChild(node)
        // Gold por kill (mesma tabela dos outros modos): base sublinear por onda × TIER do tamanho
        // (swarm 1 … elite 4). Monstro maior → mais ouro.
        let bounty = Int((Progression.goldPerKill(wave: state.wave) * Double(type.bounty)).rounded())
        let e = V3Enemy(route: route, neutralCount: VsSceneV3.neutralLen, arcSide: arc,
                        hp: waveHP*type.hpMult, speed: 0.10*type.speedMult, element: el, bounty: max(1, bounty), leaks: type.lives,
                        isBoss: type == .boss, node: node, bar: bar, stroke: body, stLabel: st)
        e.node.position = enemyPos(e); enemies.append(e)
    }

    // MARK: BOSS
    private static let bossSpeed = 0.5   // tiles/seg (bem lento)

    private func spawnBoss(_ kind: BossKind) {
        let el = kind.element
        let s = rangeUnit * 1.6
        let node = SKNode()
        let dia = CGMutablePath(); dia.move(to: CGPoint(x:0,y:s)); dia.addLine(to: CGPoint(x:s,y:0))
        dia.addLine(to: CGPoint(x:0,y:-s)); dia.addLine(to: CGPoint(x:-s,y:0)); dia.closeSubpath()
        let body = SKShapeNode(path: dia); body.fillColor = SKColor(red:el.rgb.r,green:el.rgb.g,blue:el.rgb.b,alpha:1)
        body.strokeColor = SKColor(red:1,green:0.85,blue:0.2,alpha:1); body.lineWidth = 4; node.addChild(body)
        let icon = SKLabelNode(text: kind.icon); icon.fontSize = rangeUnit*1.3; icon.verticalAlignmentMode = .center; node.addChild(icon)
        let barW = rangeUnit*3.0
        let bg = SKShapeNode(rect: CGRect(x:-barW/2,y:s+4,width:barW,height:5), cornerRadius: 2.5); bg.fillColor = SKColor(white:0,alpha:0.6); bg.strokeColor = .clear; node.addChild(bg)
        let bar = SKShapeNode(rect: CGRect(x:0,y:s+4,width:barW,height:5), cornerRadius: 2.5); bar.fillColor = SKColor(red:1,green:0.3,blue:0.3,alpha:1); bar.strokeColor = .clear; bar.position = CGPoint(x:-barW/2,y:0); node.addChild(bar)
        let stl = SKLabelNode(text: ""); stl.fontSize = rangeUnit*0.5; stl.verticalAlignmentMode = .center; stl.position = CGPoint(x:0,y:s+rangeUnit*0.7); node.addChild(stl)
        node.zPosition = 15; enemyLayer.addChild(node)
        // MUITO HP (escala com a onda), vazamento pesado. Bounty gordo (vale ~40 kills da tabela).
        let hp = waveHP * 32
        let bounty = Int((Progression.goldPerKill(wave: state.wave) * 40).rounded())
        let e = V3Enemy(route: [], neutralCount: 0, arcSide: .ai, hp: hp, speed: 0, element: el,
                        bounty: max(50, bounty), leaks: 3, isBoss: true, node: node, bar: bar, stroke: body, stLabel: stl)
        e.boss = kind; e.bossDefaultDir = Bool.random() ? 1 : -1
        e.node.position = bossPoint(e); enemies.append(e)
    }

    private func bossPoint(_ e: V3Enemy) -> CGPoint {
        let path = e.bossPos >= 0 ? VsSceneV3.bossRedPath : VsSceneV3.bossGreenPath
        let p = min(abs(e.bossPos), Double(path.count - 1))
        let i = min(path.count - 2, Int(p)); let fr = CGFloat(p - Double(i))
        let a = layout.center(of: path[max(0, i)]), b = layout.center(of: path[min(path.count - 1, i + 1)])
        return CGPoint(x: a.x + (b.x - a.x)*fr, y: a.y + (b.y - a.y)*fr)
    }

    private func stepBoss(_ e: V3Enemy, dt: Double, now: Double) {
        let cfg = VsCatalog.status!
        let dot = e.status.burnDps(maxHP: e.maxHP, isBoss: true, now, cfg) + e.status.poisonDps(maxHP: e.maxHP, isBoss: true, now, cfg)
        if dot > 0 { e.hp -= dot*dt; updateBar(e); if e.hp <= 0 { bossDied(e); return } }
        e.status.expire(now); e.stLabel.text = e.status.activeIcons(now).prefix(4).map { VsV3Map.icon($0) }.joined()
        // DIREÇÃO: vai pro lado OPOSTO de quem deu MAIS dano (empate → direção atual/sorteada).
        // Travado num arco → segue reto pra saída, sem voltar.
        let dir: Double
        if e.bossLocked { dir = e.bossPos >= 0 ? 1 : -1 }
        else if e.dmgByPlayer > e.dmgByAI { dir = 1 }          // player bateu mais → vai pro lado da IA
        else if e.dmgByAI > e.dmgByPlayer { dir = -1 }         // IA bateu mais → vai pro lado do player
        else { dir = e.bossDefaultDir }
        let mm = e.status.moveMult(now, cfg)
        let delta = dir * VsSceneV3.bossSpeed * (mm.isFinite ? mm : 1) * dt
        e.bossPos += delta
        e.bossTilesAcc += abs(delta)
        // dispara habilidade a cada `cadence` tiles andados (com trava anti-hang).
        if e.bossTilesAcc.isFinite {
            let target = Int(e.bossTilesAcc); var guardN = 0
            while e.bossTilesDone < target && guardN < 50 {
                e.bossTilesDone += 1; guardN += 1
                if e.bossTilesDone % e.boss!.cadence == 0 { triggerBoss(e) }
            }
        }
        // TRAVA ao entrar no 1º tile de um arco → para de receber dano do lado oposto.
        if !e.bossLocked && abs(e.bossPos) >= Double(VsSceneV3.bossNeutralLen) {
            e.bossLocked = true; e.arcSide = e.bossPos >= 0 ? .ai : .player
            e.stroke.strokeColor = e.arcSide == .player ? SKColor(red:0.4,green:0.9,blue:0.5,alpha:1) : SKColor(red:1,green:0.5,blue:0.5,alpha:1)
        }
        // SAÍDA → vazamento pesado pro dono do arco.
        let path = e.bossPos >= 0 ? VsSceneV3.bossRedPath : VsSceneV3.bossGreenPath
        if abs(e.bossPos) >= Double(path.count - 1) {
            if e.arcSide == .player { playerLives -= e.leaks } else { aiLives -= e.leaks }
            e.dead = true; e.node.removeFromParent()
            if playerLives <= 0 || aiLives <= 0 { finish() }
            return
        }
        e.node.position = bossPoint(e)
    }

    private func bossDied(_ e: V3Enemy) {
        guard !e.dead else { return }
        e.dead = true
        let winner: VsSide = e.bossLocked ? e.arcSide : (e.dmgByPlayer >= e.dmgByAI ? .player : .ai)
        if winner == .player { playerGold += e.bounty } else { aiGold += e.bounty }
        flash(at: e.node.position, color: SKColor(white: 1, alpha: 0.8))
        e.node.removeFromParent()
    }

    // Habilidades do boss (a cada N tiles). No NEUTRO afetam os DOIS lados; depois que o boss trava
    // num arco, só afetam o lado pra onde ele está indo (o dono do arco).
    private func triggerBoss(_ e: V3Enemy) {
        let sides: [VsSide] = e.bossLocked ? [e.arcSide] : [.player, .ai]
        switch e.boss! {
        case .demolidor:    for s in sides { bossDestroy(s) }
        case .mutante:      for s in sides { bossMutate(s) }
        case .permutador:   bossSwap(sides)
        case .embaralhador: for s in sides { bossShuffle(s) }
        }
        flash(at: e.node.position, color: SKColor(red:1,green:0.3,blue:0.3,alpha:0.55))
        Audio.shared.sfx("place"); clearSelection(); pushHUD()
    }
    private func bossDestroy(_ side: VsSide) {                     // destrói 1 torre aleatória do lado
        let mine = towers.filter { $0.value.side == side }
        if let (h, t) = mine.randomElement() { t.node.removeFromParent(); towers[h] = nil }
    }
    private func bossMutate(_ side: VsSide) {                      // muda 1 torre (tipo+elemento), mantém ⭐
        let mine = towers.filter { $0.value.side == side }
        guard let (h, t) = mine.randomElement() else { return }
        var newId = palette.randomElement() ?? t.unit.specId, tries = 0
        while newId == t.unit.specId && tries < 6 { newId = palette.randomElement() ?? newId; tries += 1 }
        guard let spec = VsCatalog.spec(newId) else { return }
        t.unit = VsUnit(specId: newId, element: spec.element, role: spec.role, star: t.unit.star, hex: h)
        refreshTowerNode(t)
    }
    private func bossSwap(_ sides: [VsSide]) {
        if sides.count == 2 {                                     // neutro: troca 1 torre do player com 1 da IA
            guard let (hp, tp) = towers.filter({ $0.value.side == .player }).randomElement(),
                  let (ha, ta) = towers.filter({ $0.value.side == .ai }).randomElement() else { return }
            let up = tp.unit, ua = ta.unit
            tp.unit = VsUnit(specId: ua.specId, element: ua.element, role: ua.role, star: ua.star, hex: hp)
            ta.unit = VsUnit(specId: up.specId, element: up.element, role: up.role, star: up.star, hex: ha)
            refreshTowerNode(tp); refreshTowerNode(ta)
        } else if let side = sides.first {                        // travado: troca a POSIÇÃO de 2 torres do lado
            let picks = Array(towers.filter { $0.value.side == side }).shuffled().prefix(2)
            guard picks.count == 2 else { return }
            let (h0, t0) = picks[0], (h1, t1) = picks[1]
            t0.unit.hex = h1; t0.pos = layout.center(of: h1); t0.node.position = t0.pos
            t1.unit.hex = h0; t1.pos = layout.center(of: h0); t1.node.position = t1.pos
            towers[h0] = t1; towers[h1] = t0
        }
    }
    private func bossShuffle(_ side: VsSide) {                     // embaralha as POSIÇÕES dentro do lado
        let mine = towers.filter { $0.value.side == side }
        let hexes = Array(mine.keys); let tws = Array(mine.values)
        guard hexes.count > 1 else { return }
        let target = hexes.shuffled()
        for h in hexes { towers[h] = nil }
        for (i, t) in tws.enumerated() {
            let nh = target[i]
            t.unit.hex = nh; t.pos = layout.center(of: nh); t.node.position = t.pos; towers[nh] = t
        }
    }

    private func stepEnemies(dt: Double) {
        let now = gameClock
        for e in enemies where !e.dead {
            if e.boss != nil { stepBoss(e, dt: dt, now: now); continue }
            let cfg = VsCatalog.status!
            let dot = e.status.burnDps(maxHP: e.maxHP, isBoss: e.isBoss, now, cfg) + e.status.poisonDps(maxHP: e.maxHP, isBoss: e.isBoss, now, cfg)
            if dot > 0 { e.hp -= dot*dt; updateBar(e); if e.hp <= 0 { enemyDied(e); continue } }
            e.status.expire(now); e.stLabel.text = e.status.activeIcons(now).prefix(4).map { VsV3Map.icon($0) }.joined()
            // Ritmo: no NEUTRO andam a 1/3 da velocidade (janela grande pra matar/deflexionar);
            // nos arcos verde/vermelho, metade. Deixa a partida desafiante mas longa.
            let laneMult = e.contested ? (1.0/3.0) : 0.5
            e.prog += e.baseSpeed * e.status.moveMult(now, cfg) * laneMult * dt
            if e.prog >= 1 {
                // Chegou na saída do arco → vaza pro dono do arco (arcSide).
                let extra = state.wave >= VsSceneV3.suddenDeathWave ? 1 : 0
                if e.arcSide == .player { playerLives -= e.leaks + extra } else { aiLives -= e.leaks + extra }
                e.dead = true; e.node.removeFromParent()
                if playerLives <= 0 || aiLives <= 0 { finish() }
                continue
            }
            e.node.position = enemyPos(e)
        }
        enemies.removeAll { $0.dead }
    }

    // MARK: combate — combos (T4) + tiro individual (targets) + status (T2) + propagação (T3)

    private var groundEffects: [VsGroundEffect] = []

    private func encHex(_ h: Hex) -> Int { (h.q + 100) * 1000 + (h.r + 100) }   // id bijetivo (q,r ∈ ~-16..16)
    private func decHex(_ id: Int) -> Hex { Hex(q: id / 1000 - 100, r: id % 1000 - 100) }

    private func stepTowers(dt: Double) {
        let now = gameClock
        // 1) combos: detecta pares adjacentes de elementos diferentes (por lado).
        let lite = towers.map { (h, t) in VsTowerLite(id: encHex(h), element: t.unit.element, hex: h, star: t.unit.star) }
        let combos = VsCombat.detectCombos(lite)
        let suppressed = VsCombat.suppressed(combos)
        // 2) dispara os combos (cooldown por par de hexes) + mantém a ARTE de destaque.
        var activePairs = Set<Set<Hex>>()
        for ci in combos {
            let ha = decHex(ci.motherA), hb = decHex(ci.motherB)
            let key: Set<Hex> = [ha, hb]; activePairs.insert(key)
            if comboFX[key] == nil, let ta = towers[ha], let tb = towers[hb] {
                comboFX[key] = makeComboFX(ta.pos, tb.pos, combo: ci.combo())
            }
            comboCooldown[key, default: 0] -= dt
            guard comboCooldown[key]! <= 0, let ta = towers[ha] else { continue }
            comboCooldown[key] = ci.cooldown
            fireCombo(ci, from: ta)
        }
        for key in comboFX.keys where !activePairs.contains(key) { comboFX[key]?.removeFromParent(); comboFX[key] = nil }
        // 3) tiro individual das torres NÃO suprimidas.
        for (h, t) in towers {
            if suppressed.contains(encHex(h)) { continue }
            t.cooldown -= dt
            guard t.cooldown <= 0 else { continue }
            fireTower(t, now: now)
        }
        // efeitos de chão (striker) aplicam status a quem está em cima.
        groundEffects.removeAll { $0.until <= now }
        let onGround = VsPropagation.groundHits(groundEffects, enemies: enemies.enumerated().map { (id: $0.offset, hex: hexOf($0.element)) }, now: now)
        for hit in onGround where hit.id < enemies.count {
            _ = enemies[hit.id].status.apply(hit.status, chance: 1, isBoss: enemies[hit.id].isBoss, now: now, cfg: VsCatalog.status!, roll: 0)
        }
    }

    /// ARTE DE COMBO: destaca o par de torres que forma o combo — feixe pulsante entre elas, aura
    /// nas duas mães e o nome do combo no meio. Fica enquanto as duas estiverem adjacentes.
    private func makeComboFX(_ a: CGPoint, _ b: CGPoint, combo: VsCombo?) -> SKNode {
        let container = SKNode(); container.zPosition = 6
        let gold = SKColor(red: 1, green: 0.85, blue: 0.25, alpha: 1)
        let path = CGMutablePath(); path.move(to: a); path.addLine(to: b)
        let beam = SKShapeNode(path: path)
        beam.strokeColor = gold; beam.lineWidth = 5; beam.glowWidth = 5; beam.lineCap = .round
        beam.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.45), .fadeAlpha(to: 1, duration: 0.45)])))
        container.addChild(beam)
        for p in [a, b] {                                   // aura giratória nas duas mães
            let ring = SKShapeNode(circleOfRadius: rangeUnit * 0.7)
            ring.strokeColor = gold; ring.lineWidth = 2.5; ring.glowWidth = 2; ring.fillColor = .clear; ring.position = p
            ring.run(.repeatForever(.rotate(byAngle: .pi*2, duration: 2.2)))
            container.addChild(ring)
        }
        let mid = CGPoint(x: (a.x+b.x)/2, y: (a.y+b.y)/2)
        let burst = SKLabelNode(text: "⚡"); burst.fontSize = rangeUnit*0.85; burst.position = mid; burst.verticalAlignmentMode = .center
        burst.run(.repeatForever(.sequence([.scale(to: 1.35, duration: 0.35), .scale(to: 0.85, duration: 0.35)])))
        container.addChild(burst)
        if let combo = combo {
            let tag = SKLabelNode(text: combo.name); tag.fontSize = rangeUnit*0.42; tag.fontColor = .white
            tag.verticalAlignmentMode = .center; tag.position = CGPoint(x: mid.x, y: mid.y + rangeUnit*0.85)
            let bgW = CGFloat(combo.name.count) * rangeUnit*0.26 + rangeUnit*0.4
            let bgN = SKShapeNode(rect: CGRect(x: -bgW/2, y: -rangeUnit*0.28, width: bgW, height: rangeUnit*0.56), cornerRadius: rangeUnit*0.28)
            bgN.fillColor = SKColor(red: 0.5, green: 0.1, blue: 0.5, alpha: 0.85); bgN.strokeColor = gold; bgN.lineWidth = 1.5
            bgN.position = CGPoint(x: mid.x, y: mid.y + rangeUnit*0.85); bgN.zPosition = -1
            container.addChild(bgN); container.addChild(tag)
        }
        fxLayer.addChild(container)
        return container
    }

    private func hexOf(_ e: V3Enemy) -> Hex { e.route.isEmpty ? Hex(q: 0, r: 0) : e.route[e.idx] }

    private func valid(_ t: V3Tower, _ e: V3Enemy) -> Bool {
        // BOSS: no neutro os dois batem; travado num arco, só o dono do arco (o oposto para de bater).
        if e.boss != nil { return e.bossLocked ? (t.side == e.arcSide) : true }
        // No neutro (contestado) qualquer lado atira; no arco, só o dono do arco defende.
        return e.contested || e.arcSide == t.side
    }

    private func fireTower(_ t: V3Tower, now: Double) {
        let rangePx = CGFloat(t.rangeHex) * hexSize * sqrt(3.0)
        let inRange = enemies.filter { valid(t, $0) && $0.node.position.distanceSq(t.pos) <= rangePx*rangePx }
        guard !inRange.isEmpty else { return }
        t.cooldown = t.cadence
        switch t.spec.targetsFor(tier: t.unit.star) {
        case .count(let n):
            for e in inRange.sorted(by: { $0.prog > $1.prog }).prefix(n) { hitEnemy(t, e, now: now) }
        case .unlimited:
            for e in inRange { hitEnemy(t, e, now: now) }
        case .line:
            // Balista: perfura (atinge todos no alcance); Exposto → +40% (primed). 1ª versão do v3.
            for e in inRange { hitEnemy(t, e, now: now, primed: e.status.active(.exposed, now)) }
        }
    }

    private func hitEnemy(_ t: V3Tower, _ e: V3Enemy, now: Double, factor: Double = 1, primed: Bool = false) {
        let el = VsV3Map.element(t.unit.element)
        var dmg = t.damage * el.multiplier(against: e.element) * factor
        if primed { dmg *= 1 + (VsCatalog.propagation?.balista.primedBonus ?? 0.4) }
        dmg *= e.status.dmgTakenMult(now, VsCatalog.status!)
        e.hp -= dmg; e.mark(t.side); updateBar(e)
        // BOSS: acumula dano por lado (define pra que lado ele vai — o OPOSTO de quem bate mais).
        if e.boss != nil { if t.side == .player { e.dmgByPlayer += dmg } else { e.dmgByAI += dmg } }
        shootFX(from: t.pos, to: e.node.position, color: t.side == .player ? .cyan : .orange)
        // aplica status do elemento (bloqueio anti-combo + boss override).
        if let st = t.spec.appliesStatus, let kind = VsStatusKind(rawValue: st) {
            let has = Set(e.status.activeIcons(now).map { $0.rawValue })
            if !VsCombat.isBlocked(applying: st, whenTargetHas: has) {
                _ = e.status.apply(kind, chance: t.spec.statusChanceFor(tier: t.unit.star), isBoss: e.isBoss, now: now,
                                   cfg: VsCatalog.status!, roll: Double.random(in: 0..<1))
            }
        }
        if e.hp <= 0 { killedBy(e, tower: t, now: now) }
    }

    private func killedBy(_ e: V3Enemy, tower t: V3Tower, now: Double) {
        if e.boss != nil { bossDied(e); return }   // boss não propaga nem deflexiona
        // STRIKER: deixa efeito no chão. BLASTER: propaga por salto.
        if t.unit.role == "striker", let g = VsPropagation.strikerGround(element: t.unit.element, at: hexOf(e), now: now, cfg: VsCatalog.propagation!) {
            groundEffects.append(g)
        } else if t.unit.role == "blaster", let st = t.spec.appliesStatus, let kind = VsStatusKind(rawValue: st) {
            let cand = enemies.enumerated().filter { !$0.element.dead && $0.element !== e }.map { (id: $0.offset, hex: hexOf($0.element)) }
            let ids = VsPropagation.blasterSpread(fromHex: hexOf(e), deadId: -1, candidates: cand, cfg: VsCatalog.propagation!)
            for id in ids where id < enemies.count {
                _ = enemies[id].status.apply(kind, chance: 1, isBoss: enemies[id].isBoss, now: now, cfg: VsCatalog.status!, roll: 0)
            }
        }
        enemyDied(e)
    }

    private func fireCombo(_ ci: VsComboInstance, from t: V3Tower) {
        let now = gameClock
        let rangePx = CGFloat(max(t.rangeHex, 2)) * hexSize * sqrt(3.0)
        let inRange = enemies.filter { valid(t, $0) && $0.node.position.distanceSq(t.pos) <= rangePx*rangePx }
        guard let tgt = inRange.max(by: { $0.prog < $1.prog }), let combo = ci.combo() else { return }
        let r = CGFloat(max(1, combo.splash)) * hexSize * sqrt(3.0)
        flash(at: tgt.node.position, color: SKColor(white: 1, alpha: 0.5))
        for e in inRange where e.node.position.distanceSq(tgt.node.position) <= r*r {
            var dmg = ci.effectiveDamage
            if let crit = combo.critVsFrozen, e.status.active(.frozen, now) { dmg *= crit }
            dmg *= e.status.dmgTakenMult(now, VsCatalog.status!)
            e.hp -= dmg; e.mark(t.side); updateBar(e)
            for s in combo.applies { if let k = VsStatusKind(rawValue: s) {
                _ = e.status.apply(k, chance: 1, isBoss: e.isBoss, now: now, cfg: VsCatalog.status!, roll: 0) } }
            if e.hp <= 0 { enemyDied(e) }
        }
    }

    // MARK: morte / deflexão / fim

    private func updateBar(_ e: V3Enemy) { e.bar.xScale = max(0, CGFloat(e.hp / e.maxHP)) }
    private func enemyDied(_ e: V3Enemy) {
        guard !e.dead else { return }
        if e.boss != nil { bossDied(e); return }
        // Morto no NEUTRO (contestado) → não morre: teleporta pro arco do adversário de quem matou.
        if e.contested { deflect(e); return }
        e.dead = true
        if e.arcSide == .player { playerGold += e.bounty } else { aiGold += e.bounty }
        e.node.removeFromParent()
    }
    /// Deflexão: quem mata no neutro empurra o monstro pro arco do ADVERSÁRIO. Jogador mata →
    /// vai pro arco vermelho (16→…→11, saída da IA); IA mata → vai pro arco verde (22→…→27).
    private func deflect(_ e: V3Enemy) {
        let killer = e.lastHit ?? .player
        if killer == .player { e.route = VsSceneV3.mRed;   e.arcSide = .ai }
        else                 { e.route = VsSceneV3.mGreen; e.arcSide = .player }
        e.neutralCount = 0; e.prog = 0; e.hp = e.maxHP; e.lastHit = nil
        e.status = VsStatusState(); e.stLabel.text = ""; e.bar.xScale = 1
        e.stroke.strokeColor = e.arcSide == .player ? SKColor(red:0.4,green:0.9,blue:0.5,alpha:1) : SKColor(red:1,green:0.5,blue:0.5,alpha:1)
        e.node.position = enemyPos(e)
    }
    private var finishing = false
    private func finish() {
        guard !finishing else { return }   // uma vez só
        finishing = true
        let won = aiLives <= 0 && playerLives > 0 || (playerLives <= 0 && aiLives <= 0 && playerLives >= aiLives)
        VsLog.write("finish() called won=\(won) pL=\(playerLives) aiL=\(aiLives) w=\(state.wave) e=\(enemies.count)")
        isPaused = true   // para a cena (o loop de update não roda mais)
        // publica o fim num tick LIMPO do main (fora do callback do display-link) → garante que o
        // SwiftUI re-renderize e mostre a tela de vitória/derrota.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.state.playerWon = won
            if won { self.state.creditsEarned = self.meta.addCredits(50) }
            self.state.finished = true
            VsLog.write("state.finished=true published (won=\(won))")
        }
    }

    // MARK: IA simples — spawna e funde no lado norte, o de melhor score

    var playerAuto = false      // botão Auto On: a IA joga o lado do jogador também

    private func aiStep(dt: Double) {
        aiClock -= dt; guard aiClock <= 0 else { return }; aiClock = 0.6
        aiPlay(.ai)
        if playerAuto { aiPlay(.player) }
    }

    // Entradas dos monstros = pontas do neutro (17 e 21). A IA constrói PERTO da ENTRADA (mata cedo,
    // mais tempo de tiro) e não perto da saída dos arcos.
    private static let entryHexes: [Hex] = [mNeutral.first!, mNeutral.last!]
    private func distToEntry(_ h: Hex, _ side: VsSide) -> Int { VsSceneV3.entryHexes.map { $0.distance(to: h) }.min() ?? 9 }

    /// PLANEJADOR da IA (rule-based, uma ação por tick):
    /// 1) COMPLETAR merge de um ★0 solteiro (nunca deixa órfão esperando enquanto dá pra parear);
    /// 2) TILE LIVRE → começa um par novo, contra-atacando o elemento da onda (varia a cada onda);
    /// 3) BOARD CHEIO → RECICLA: vende a torre de menor estrela pra abrir espaço.
    private func aiPlay(_ side: VsSide) {
        let gold = goldFor(side)
        let affordable = palette.map { VsCatalog.spec($0)! }.filter { gold >= $0.cost }
        guard !affordable.isEmpty else { return }
        let mine = towers.filter { $0.value.side == side }

        // 1) ★0 solteiro (contagem ímpar) que eu posso parear → fecho o merge. Prioriza melhor counter.
        var oddZero: [String: Int] = [:]
        for (_, t) in mine where t.unit.star == 0 { oddZero[t.unit.specId, default: 0] += 1 }
        let pairable = oddZero.filter { $0.value % 2 == 1 }.keys
            .compactMap { VsCatalog.spec($0) }.filter { gold >= $0.cost }
            .sorted { counterScore($0) > counterScore($1) }
        if let spec = pairable.first {
            if let h = bestFreeHex(side) { spawnCommon(specId: spec.id, side: side, at: h, autoMerge: true); return }
            _ = aiSellToMakeRoom(side, keep: spec.id); return       // sem espaço → vende fraca; pareia no próximo tick
        }

        // 2) tile livre → começa um par NOVO (contra o elemento da onda + diversidade).
        if let h = bestFreeHex(side), let id = pickNewType(side, affordable) {
            spawnCommon(specId: id, side: side, at: h, autoMerge: true); return
        }

        // 3) board cheio e nada pra fundir → recicla a de menor estrela.
        _ = aiSellToMakeRoom(side, keep: nil)
    }

    private func counterScore(_ s: VsTowerSpec) -> Double { VsV3Map.element(s.element).multiplier(against: waveElement) }

    private func bestFreeHex(_ side: VsSide) -> Hex? {
        buildable.filter { regionOf[$0] == side && towers[$0] == nil }.min { distToEntry($0, side) < distToEntry($1, side) }
    }

    /// Tipo pra iniciar um par novo. Métrica principal = DANO EFETIVO na onda (dpsEff × counter da
    /// roda elemental). Suporte é raro (dano direto baixo). Aprofunda tipos que já tenho; não pulveriza.
    private func pickNewType(_ side: VsSide, _ affordable: [VsTowerSpec]) -> String? {
        let mine = towers.values.filter { $0.side == side }
        let distinct = Set(mine.map { $0.unit.specId })
        let supports = mine.filter { $0.unit.role == "support" }.count
        var best: String? = nil, bestV = -1e9
        for spec in affordable {
            let bias = aiBias[side]?[spec.element] ?? 1
            // dano efetivo vs a onda é o que manda; counter (0.5..2) ESCALA o dano, não o substitui.
            var v = spec.dpsEff * bias * counterScore(spec)
            if spec.role == "support" { v *= (supports >= 1 ? 0.15 : 0.4) }  // no máx ~1 suporte; sempre raro
            if distinct.contains(spec.id) { v += 15 }                        // aprofunda rumo a ★ maior
            if distinct.count >= 5 && !distinct.contains(spec.id) { v -= 60 } // não pulveriza
            v += Double.random(in: 0...6)                                    // jitter pequeno (não sorteia papel)
            if v > bestV { bestV = v; best = spec.id }
        }
        return best
    }

    /// Vende a torre de MENOR estrela (recicla espaço), desempate por PIOR counter vs onda e mais
    /// longe da entrada. Só recicla baixa estrela (★≤1) e só se sobrar gold pra reagir. Não vende `keep`.
    @discardableResult
    private func aiSellToMakeRoom(_ side: VsSide, keep: String?) -> Bool {
        let mine = towers.filter { $0.value.side == side && $0.value.unit.specId != keep }
        let victim = mine.min { a, b in
            if a.value.unit.star != b.value.unit.star { return a.value.unit.star < b.value.unit.star }
            let ca = counterScore(a.value.spec), cb = counterScore(b.value.spec)
            if ca != cb { return ca < cb }
            return distToEntry(a.key, side) > distToEntry(b.key, side)
        }
        guard let (h, t) = victim else { return false }
        let cheapest = palette.compactMap { VsCatalog.spec($0)?.cost }.min() ?? 0
        guard t.unit.star <= 1, goldFor(side) + refundValue(t) >= cheapest else { return false }
        if side == .player { playerGold += refundValue(t) } else { aiGold += refundValue(t) }
        t.node.removeFromParent(); towers[h] = nil; pushHUD()
        return true
    }

    // MARK: fx

    private func shootFX(from: CGPoint, to: CGPoint, color: SKColor) {
        let d = SKShapeNode(circleOfRadius: rangeUnit*0.12); d.fillColor = color; d.strokeColor = .clear; d.position = from; d.zPosition = 8
        fxLayer.addChild(d); d.run(.sequence([.move(to: to, duration: 0.07), .removeFromParent()]))
    }
    private func flash(at p: CGPoint, color: SKColor) {
        let f = SKShapeNode(circleOfRadius: rangeUnit*0.9); f.fillColor = color; f.strokeColor = .clear; f.position = p; f.zPosition = 9
        fxLayer.addChild(f); f.run(.sequence([.group([.scale(to: 1.6, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
    }
}

private extension CGPoint {
    func distanceSq(_ o: CGPoint) -> CGFloat { let dx = x-o.x, dy = y-o.y; return dx*dx + dy*dy }
}
