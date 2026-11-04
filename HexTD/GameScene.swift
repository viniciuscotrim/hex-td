import SpriteKit

/// Torre colocada no tabuleiro (data-driven via `TowerSpec`). Estrelas = upgrade
/// in-run com gold (§Paragon): escala dano/cadência/range, teto = meta.maxStars.
private final class Tower {
    let spec: TowerSpec
    let hex: Hex
    var cooldown: Double = 0
    var level: Int = 1
    var spent: Int                 // gold total investido → base da venda
    var rarityMult: Double = 1     // multiplicador de stat do loadout meta (§4)
    var abilities: Set<TowerAbility> = []   // habilidades do loadout (§5)
    var auraMult: Double = 1       // bônus de aura de torres vizinhas (Ressonância/Suporte)
    let node: SKNode
    let ring: SKShapeNode          // indicador de alcance (oculto até selecionar)
    let maxLevel: Int              // teto de estrelas = meta.maxStars (Paragon, §4)

    init(spec: TowerSpec, hex: Hex, node: SKNode, ring: SKShapeNode, maxLevel: Int) {
        self.spec = spec; self.hex = hex; self.node = node; self.ring = ring
        self.maxLevel = maxLevel
        self.spent = spec.cost
    }

    func has(_ a: TowerAbility) -> Bool { abilities.contains(a) }

    var element: Element { spec.element }
    var appliesSlow: Bool { spec.applies == .frozen || spec.applies == .rooted }
    var appliesBurn: Bool { spec.applies == .burn }

    // Item 5: efeito do upgrade in-run = 1 + step·(nível de upgrade). level=1 = recém-colocada.
    var damage: Double { spec.baseDamage * Progression.upgradeEffect(lvl: level - 1) * rarityMult * auraMult }
    var cadence: Double {   // dispara mais rápido (nível + habilidade Cadência)
        spec.cooldown * pow(0.9, Double(level - 1)) * (has(.cadencia) ? TowerAbility.Tuning.cadenciaMult : 1)
    }
    var rangeHex: Int {     // +1 no nv.3 e +1 com a habilidade Alcance
        spec.range + (level >= 3 ? 1 : 0) + (has(.alcance) ? TowerAbility.Tuning.alcanceBonus : 0)
    }
    var splashHex: Int {
        spec.splash + (spec.splash > 0 && level >= 4 ? 1 : 0)
            + (has(.chamasVivas) ? TowerAbility.Tuning.chamasSplashBonus : 0)
    }
    // Item 5: custo geométrico do upgrade in-run = custoBase · growth^(level-1).
    var upgradeCost: Int? { level >= maxLevel ? nil : Int(Progression.upgradeCost(base: Double(spec.cost), lvl: level)) }
    var sellValue: Int { Int(Double(spent) * 0.6) }

    var trait: String {
        if spec.role == .support {
            return spec.auraDamageBonus > 0 ? "Suporte — +dano às aliadas" : "Suporte"
        }
        if let st = spec.applies { return "Aplica \(st.nome)" }
        return "Dano bruto"
    }
}

/// Inimigo caminhando pelo path (interpola entre centros de hex). Carrega um
/// container de status (§combo): cada status tem um timestamp de expiração; DoTs
/// (burn/poison) têm dps próprio; lentidão vem de frozen/rooted.
private final class Enemy {
    let element: Element
    var hp: Double
    let maxHp: Double
    var seg: Int = 0            // índice do trecho atual em path
    var t: Double = 0          // 0..1 progresso no trecho
    let speed: Double          // hexes por segundo
    var statusUntil: [Status: Double] = [:]   // expiração (gameClock) por status
    var slowFactor: Double = Status.T.slowFactor
    var burnDps: Double = 0    // dps da queimadura ativa
    var poisonDps: Double = 0  // dps do veneno acumulado (empilha)
    let bounty: Int
    let isBoss: Bool
    let splashResist: Double   // dano de área ×isto (1 = normal; <1 = resiste a AOE)
    let comboMult: Double      // combos/DoTs ×isto (>1 = depende de combo)
    let node: SKNode
    let hpBar: SKShapeNode
    let statusLabel: SKLabelNode   // ícones de status acima do inimigo
    init(element: Element, hp: Double, speed: Double, bounty: Int, isBoss: Bool = false,
         splashResist: Double = 1, comboMult: Double = 1,
         node: SKNode, hpBar: SKShapeNode, statusLabel: SKLabelNode) {
        self.element = element; self.hp = hp; self.maxHp = hp
        self.speed = speed; self.bounty = bounty; self.isBoss = isBoss
        self.splashResist = splashResist; self.comboMult = comboMult; self.node = node
        self.hpBar = hpBar; self.statusLabel = statusLabel
    }
    func active(_ s: Status, _ now: Double) -> Bool { (statusUntil[s] ?? 0) > now }
    func slowed(_ now: Double) -> Bool { active(.frozen, now) || active(.rooted, now) }
}

final class GameScene: SKScene {
    private let map: HexMap
    private unowned let model: GameModel
    private unowned let meta: MetaProgress
    private let config: GameConfig
    private let campaignTowers: Set<Int>?     // Campanha: só o loadout; nil = qualquer desbloqueada
    private var placed: Set<Int> = []         // ids de torres usadas na run → recompensa
    private var buildSpots: Set<Hex>? = nil   // Campanha: só 5 spots (anti-spam); nil = qualquer buildable
    /// RNG das ONDAS: quando há seed (Campanha/Vs), é determinístico → composição idêntica
    /// dos monstros (essencial pro Vs ser justo: os dois lados pegam os mesmos inimigos).
    /// Sem seed (Endless/Rogue), cai no RNG do sistema (aleatório).
    private lazy var waveRNG: RandomNumberGenerator = {
        if let s = config.seed { return SeededGenerator(seed: s &* 0x2545F4914F6CDD1D &+ 0xABCD) }
        return SystemRandomNumberGenerator()
    }()

    /// Torre pode ser colocada nesta run? Campanha limita ao loadout; senão, desbloqueadas.
    private func isAllowed(_ id: Int) -> Bool {
        if let c = campaignTowers { return c.contains(id) }
        return meta.isUnlocked(id)
    }

    /// Hexes onde é permitido construir nesta run: os 5 spots (campanha) ou tudo buildable.
    private var placeableHexes: [Hex] { Array(buildSpots ?? map.buildable) }
    private func canBuild(at h: Hex) -> Bool {
        map.buildable.contains(h) && (buildSpots?.contains(h) ?? true)
    }

    /// Campanha: escolhe 5 spots de construção (determinístico pela seed da fase),
    /// priorizando hexes adjacentes ao caminho e espalhados entre si → cortar o spam
    /// de torres sem inviabilizar a cobertura. nil fora da campanha (usa tudo buildable).
    private static let campaignBuildSpots = 5
    private func chooseBuildSpots() -> Set<Hex>? {
        guard campaignTowers != nil else { return nil }
        let all = Array(map.buildable)
        guard all.count > Self.campaignBuildSpots else { return Set(all) }
        var rng: RandomNumberGenerator = SeededGenerator(seed: (config.seed ?? 1) &* 0x9E3779B1)
        let adj = all.filter { h in h.neighbors.contains { map.isPath($0) } }
        let pool = adj.count >= Self.campaignBuildSpots ? adj : all
        var chosen: [Hex] = []
        var cands = pool.shuffled(using: &rng)
        if let first = cands.first { chosen.append(first); cands.removeFirst() }
        while chosen.count < Self.campaignBuildSpots, !cands.isEmpty {
            // greedy: pega o candidato mais distante dos já escolhidos (espalha).
            let next = cands.max { a, b in
                (chosen.map { $0.distance(to: a) }.min() ?? 0) < (chosen.map { $0.distance(to: b) }.min() ?? 0)
            }!
            chosen.append(next); cands.removeAll { $0 == next }
        }
        return Set(chosen)
    }
    private var layout: HexLayout = HexLayout(size: 10, origin: .zero)
    private var hexSize: CGFloat = 10

    private let boardLayer = SKNode()
    private let towerLayer = SKNode()
    private let enemyLayer = SKNode()
    private let fxLayer = SKNode()

    private var towers: [Hex: Tower] = [:]
    private var enemies: [Enemy] = []
    private var selectedTower: Tower?
    private var shatterActive = false   // alguma torre com Estilhaços em campo

    // relógio de jogo (acumula dt escalado) → timers de DoT/lentidão acompanham a
    // velocidade da simulação, ao contrário do relógio de parede.
    private var gameClock: Double = 0
    private var fxEnabled = true   // desliga efeitos nos sub-steps intermediários (2x–10x)
    private var aiClock: Double = 0
    private var testStarCap: Int? = nil   // override do teto de estrelas só no harness

    // controle de onda
    private var lastTime: TimeInterval = 0
    private var toSpawn = 0
    private var spawnClock: Double = 0
    private var spawnInterval: Double = 0.8
    private var waveHP: Double = 20
    private var interWave: Double = 0     // pausa antes da próxima onda
    private var started = false
    private var bossPending = false       // spawnar um Boss no início desta onda (Rogue)

    private let resumeRun: RunSave?   // se != nil, retoma a partida salva ao montar a cena

    init(map: HexMap, model: GameModel, meta: MetaProgress, config: GameConfig,
         campaignTowers: Set<Int>?, size: CGSize, resume: RunSave? = nil) {
        self.map = map; self.model = model; self.meta = meta; self.config = config
        self.campaignTowers = campaignTowers
        self.resumeRun = resume
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 1)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = meta.frameLimit   // Configurações: 30/60/120 FPS
        [boardLayer, towerLayer, enemyLayer, fxLayer].forEach(addChild)
        model.gold = config.startGold     // valores iniciais curados por modo/fase
        model.lives = config.startLives
        buildSpots = chooseBuildSpots()   // campanha: fixa 5 spots antes de desenhar
        computeLayout()
        drawBoard()
        // Janela inicial: jogador posiciona torres e chama a 1ª onda (Fase 4).
        model.waveReady = true
        interWave = intermission
        model.doStartWave = { [weak self] in self?.startWaveNow() }
        model.towerSnapshot = { [weak self] in self?.snapshotTowers() ?? [] }
        if let r = resumeRun { restoreRun(r) }   // retoma a partida salva (gold/vidas/onda + torres)
        // Harness de teste (§dev): joga sozinho, acelerado e com teto de estrelas
        // alto (25) só na run — pra ver o Paragon sem depender do save real.
        let env = ProcessInfo.processInfo.environment
        if env["HEXTD_AUTOTEST"] != nil || env["HEXTD_CAMPTEST"] != nil {
            model.autoPlay = true; testStarCap = 25
            model.speed = env["HEXTD_ROGUE"] != nil ? 2 : (env["HEXTD_CAMPTEST"] != nil ? 5 : 10)
            meta.debugUnlockAll()   // harness: IA precisa de torres desbloqueadas
        }
    }

    private let intermission: Double = 8.0   // janela até auto-iniciar a onda

    override func didChangeSize(_ old: CGSize) {
        super.didChangeSize(old)
        guard size.width > 0, boardLayer.parent != nil else { return }
        computeLayout(); drawBoard()
        // reposiciona torres + anéis existentes
        for (hex, t) in towers {
            let c = layout.center(of: hex)
            t.node.position = c; t.ring.position = c
            if !t.ring.isHidden { updateRing(t) }
        }
    }

    // MARK: layout

    private func computeLayout() {
        let unit = HexLayout(size: 1, origin: .zero)
        let centers = map.cells.map { unit.center(of: $0) }
        let minX = centers.map(\.x).min()!, maxX = centers.map(\.x).max()!
        let minY = centers.map(\.y).min()!, maxY = centers.map(\.y).max()!
        let bw = (maxX - minX) + 2, bh = (maxY - minY) + 2   // +2 = margem de 1 raio
        let availW = size.width * 0.94
        let availH = size.height * 0.72        // topo p/ HUD, base p/ seletor
        hexSize = min(availW / bw, availH / bh)
        let ox = size.width / 2 - hexSize * ((minX + maxX) / 2)
        let oy = size.height * 0.56 - hexSize * ((minY + maxY) / 2)
        layout = HexLayout(size: hexSize, origin: CGPoint(x: ox, y: oy))
    }

    private func drawBoard() {
        boardLayer.removeAllChildren()
        for h in map.cells {
            var pts = corners(h)
            let poly = SKShapeNode(points: &pts, count: pts.count)
            poly.lineWidth = 1
            poly.strokeColor = SKColor(white: 0.0, alpha: 0.35)
            if map.blocked.contains(h) {
                poly.fillColor = SKColor(red: 0.20, green: 0.20, blue: 0.26, alpha: 1)
            } else if h == map.entrance {
                poly.fillColor = SKColor(red: 0.30, green: 0.70, blue: 0.40, alpha: 1)
            } else if h == map.exit {
                poly.fillColor = SKColor(red: 0.85, green: 0.30, blue: 0.35, alpha: 1)
            } else if map.isPath(h) {
                poly.fillColor = SKColor(red: 0.40, green: 0.36, blue: 0.30, alpha: 1)
            } else if buildSpots?.contains(h) == true {
                // Spot de construção (campanha): destaque + anel tracejado dourado.
                poly.fillColor = SKColor(red: 0.22, green: 0.42, blue: 0.34, alpha: 1)
                poly.strokeColor = SKColor(red: 1.0, green: 0.83, blue: 0.25, alpha: 0.9)
                poly.lineWidth = 2.5
            } else {
                poly.fillColor = SKColor(red: 0.17, green: 0.30, blue: 0.26, alpha: 1)
            }
            boardLayer.addChild(poly)
        }
    }

    private func corners(_ h: Hex) -> [CGPoint] {
        var pts = layout.corners(of: h); pts.append(pts[0]); return pts
    }

    // MARK: input — seleciona torre existente ou coloca uma nova

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !model.gameOver, let p = touches.first?.location(in: self) else { return }
        guard let hex = nearestCell(to: p) else { deselect(); return }
        if let tw = towers[hex] { select(tw); return }        // tocou numa torre → inspeciona
        guard canBuild(at: hex) else { deselect(); return }
        let spec = TowerCatalog.spec(model.selected)
        guard isAllowed(spec.id) else {   // fora do loadout (campanha) / não desbloqueada
            flash(at: layout.center(of: hex), color: .red); return
        }
        guard model.gold >= spec.cost else {
            flash(at: layout.center(of: hex), color: .red); return
        }
        model.gold -= spec.cost
        let tw = placeTower(spec, at: hex)
        select(tw)
    }

    private func nearestCell(to p: CGPoint) -> Hex? {
        map.cells.min { layout.center(of: $0).distanceSq(p) < layout.center(of: $1).distanceSq(p) }
            .flatMap { layout.center(of: $0).distanceSq(p) <= (hexSize * hexSize) ? $0 : nil }
    }

    @discardableResult
    private func placeTower(_ spec: TowerSpec, at hex: Hex) -> Tower {
        let c = layout.center(of: hex)
        let ring = SKShapeNode()
        ring.strokeColor = .white; ring.lineWidth = 1.5
        let rgb0 = spec.element.rgb
        ring.fillColor = SKColor(red: rgb0.r, green: rgb0.g, blue: rgb0.b, alpha: 0.10)
        ring.isHidden = true; ring.position = c
        towerLayer.addChild(ring)

        let node = SKNode(); node.position = c
        let rgb = spec.element.rgb
        let disc = SKShapeNode(circleOfRadius: hexSize * 0.55)
        disc.fillColor = SKColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        // Suporte tem borda dourada tracejada → distingue os 3 do elemento no tabuleiro.
        disc.strokeColor = spec.role == .support ? SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1) : .white
        disc.lineWidth = spec.role == .support ? 3 : 2
        disc.name = "disc"
        let label = SKLabelNode(text: spec.icon)
        label.fontSize = hexSize * 0.8; label.verticalAlignmentMode = .center
        // Helvetica-Bold: negrito E tem o glifo ★ (U+2605). Amarelo p/ destacar.
        let lvlPip = SKLabelNode(text: "")
        lvlPip.fontName = "Helvetica-Bold"
        lvlPip.fontSize = hexSize * 0.5
        lvlPip.fontColor = SKColor(red: 1.0, green: 0.83, blue: 0.20, alpha: 1)
        lvlPip.verticalAlignmentMode = .center; lvlPip.position = CGPoint(x: 0, y: -hexSize * 0.76)
        lvlPip.name = "pip"
        node.addChild(disc); node.addChild(label); node.addChild(lvlPip)
        towerLayer.addChild(node)
        let tw = Tower(spec: spec, hex: hex, node: node, ring: ring,
                       maxLevel: testStarCap ?? meta.maxStars(spec.id))
        tw.rarityMult = meta.statMult(spec.id)      // loadout meta escala o stat base (§4)
        tw.abilities = Set(meta.abilities(spec.id)) // habilidades do loadout (§5)
        placed.insert(spec.id)
        towers[hex] = tw
        if !restoring { Audio.shared.sfx("place") }
        updatePip(tw)     // mostra ★1 desde a colocação
        refreshAuras()
        return tw
    }

    private var restoring = false

    /// Torres atuais → lista serializável (para salvar a partida da Campanha).
    func snapshotTowers() -> [TowerSave] {
        towers.values.map { TowerSave(q: $0.hex.q, r: $0.hex.r, specId: $0.spec.id,
                                      level: $0.level, spent: $0.spent) }
    }

    /// Retoma a partida salva: mapa já veio regenerado pela seed fixa; reconstrói torres
    /// e restaura gold/vidas/onda. Retoma ENTRE ondas (sem inimigos no campo).
    private func restoreRun(_ r: RunSave) {
        restoring = true
        for ts in r.towers where map.cells.contains(Hex(q: ts.q, r: ts.r)) {
            let tw = placeTower(TowerCatalog.spec(ts.specId), at: Hex(q: ts.q, r: ts.r))
            tw.level = max(1, ts.level); tw.spent = ts.spent
            updatePip(tw); updateRing(tw)
        }
        restoring = false
        refreshAuras()
        model.gold = r.gold; model.lives = r.lives; model.wave = r.wave
        model.waveReady = true; interWave = intermission
    }

    /// Recalcula o bônus de aura (Ressonância + suportes) e a flag de Estilhaços
    /// sempre que o conjunto de torres muda (colocar/vender).
    private func refreshAuras() {
        for (_, t) in towers { t.auraMult = 1 }
        shatterActive = false
        for (_, src) in towers {
            if src.has(.estilhacos) { shatterActive = true }
            // Ressonância (habilidade) + aura base de torre de suporte somam no vizinho.
            let bonus = (src.has(.ressonancia) ? TowerAbility.Tuning.auraBonus : 0) + src.spec.auraDamageBonus
            guard bonus > 0 else { continue }
            for (_, t) in towers where t !== src &&
                t.hex.distance(to: src.hex) <= TowerAbility.Tuning.auraRange {
                t.auraMult += bonus
            }
        }
        if let sel = selectedTower { pushInspect(sel) }
    }

    // MARK: seleção / upgrade / venda (in-run, §6)

    private func select(_ tw: Tower) {
        selectedTower?.ring.isHidden = true
        selectedTower = tw
        updateRing(tw)
        pushInspect(tw)
        model.doUpgrade = { [weak self] in self?.upgrade(tw) }
        model.doSell = { [weak self] in self?.sell(tw) }
        model.doDeselect = { [weak self] in self?.deselect() }
    }

    private func deselect() {
        selectedTower?.ring.isHidden = true
        selectedTower = nil
        model.inspect = nil
    }

    private func upgrade(_ tw: Tower) {
        guard let cost = tw.upgradeCost, model.gold >= cost else {
            flash(at: tw.node.position, color: .red); return
        }
        model.gold -= cost
        tw.spent += cost
        tw.level += 1
        Audio.shared.sfx("upgrade")
        updateRing(tw)
        updatePip(tw)
        pushInspect(tw)
        flash(at: tw.node.position, color: SKColor(white: 1, alpha: 0.5))
    }

    private func sell(_ tw: Tower) {
        model.gold += tw.sellValue
        tw.node.removeFromParent(); tw.ring.removeFromParent()
        towers[tw.hex] = nil
        deselect()
        refreshAuras()
    }

    private func pushInspect(_ tw: Tower) {
        model.inspect = TowerInspect(
            name: tw.spec.nome, icon: tw.spec.icon, element: tw.spec.element,
            rarity: meta.rarity(tw.spec.id),
            level: tw.level, maxLevel: tw.maxLevel, damage: tw.damage,
            range: tw.rangeHex, trait: tw.trait,
            abilities: tw.spec.abilities.filter { tw.has($0) },
            upgradeCost: tw.upgradeCost, sellValue: tw.sellValue)
    }

    private func updatePip(_ tw: Tower) {
        (tw.node.childNode(withName: "pip") as? SKLabelNode)?.text = "★\(tw.level)"
    }

    private func updateRing(_ tw: Tower) {
        let r = CGFloat(tw.rangeHex) * hexSize * sqrt(3.0)
        tw.ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2*r, height: 2*r), transform: nil)
        tw.ring.isHidden = false
    }

    // MARK: loop

    override func update(_ currentTime: TimeInterval) {
        if lastTime == 0 { lastTime = currentTime }
        let raw = min(currentTime - lastTime, 1.0 / 20.0)
        lastTime = currentTime
        if model.gameOver || model.won || model.paused { return }   // pause congela a simulação

        let steps = max(1, model.speed)
        self.speed = CGFloat(steps)
        for i in 0..<steps {
            fxEnabled = (i == steps - 1)
            gameClock += raw
            aiStep(dt: raw)
            stepWaves(dt: raw, now: gameClock)
            stepEnemies(dt: raw)
            stepTowers(dt: raw, now: gameClock)
        }
        fxEnabled = true
    }

    private func stepWaves(dt: Double, now: TimeInterval) {
        if toSpawn == 0 && enemies.isEmpty {
            if let target = config.targetWave, model.wave >= target { winGame(); return }
            if !model.waveReady { model.waveReady = true; interWave = intermission }
            interWave -= dt
            model.waveBonus = max(0, Int(interWave * 2))
            if interWave <= 0 { launchWave(earlyBonus: 0) }
            return
        }
        guard toSpawn > 0 else { return }
        spawnClock -= dt
        if spawnClock <= 0 {
            spawnClock = spawnInterval
            if bossPending { bossPending = false; spawnEnemy(boss: true) }   // chefão primeiro
            else { spawnStep() }                                             // grupo de um tipo
        }
    }

    private func startWaveNow() {
        guard model.waveReady, !model.gameOver, !model.won else { return }
        Audio.shared.sfx("wave")
        launchWave(earlyBonus: model.waveBonus)
    }

    private func launchWave(earlyBonus: Int) {
        model.gold += earlyBonus
        model.waveReady = false
        model.waveBonus = 0
        startNextWave()
    }

    private func startNextWave() {
        Progression.reload()   // hot-reload dos coeficientes em dev build
        model.wave += 1
        let w = model.wave
        toSpawn = Int((Double(6 + w) * config.enemyCountMult).rounded())   // mais monstros/onda
        spawnInterval = max(0.30, 0.85 - Double(w) * 0.02)
        // HP base por wave: exponencial amortecida (item 1) × curadoria por mapa (hpScale).
        waveHP = Progression.enemyHP(wave: w) * config.hpScale
        spawnClock = 0
        groupRemaining = 0   // não carrega grupo entre ondas
        // Onda de Boss (Rogue): 1 chefão + menos regulares.
        bossPending = config.bossEvery > 0 && w % config.bossEvery == 0
        if bossPending { toSpawn = max(3, toSpawn - 3) }
    }

    // MARK: auto-mode (IA)

    private enum AI {
        static let tickInterval = 0.30
        static let maxTowersFinite = 8
        static let softCapEndless = 12
        static let minCoverage = 3
        static let upgradeStep = 0.42
        static let splashFactor = 1.7
        static let reservePerWave = 3
        static let reserveCap = 60
    }

    private var isEndless: Bool { config.targetWave == nil }
    private func aiTowerCap(allMaxed: Bool) -> Int {
        guard isEndless else { return min(AI.maxTowersFinite, buildSpots?.count ?? AI.maxTowersFinite) }
        return allMaxed ? map.buildable.count : AI.softCapEndless
    }
    private var aiReserve: Int { isEndless ? 0 : min(AI.reserveCap, model.wave * AI.reservePerWave) }

    private func aiStep(dt: Double) {
        guard model.autoPlay, !model.gameOver, !model.won else { return }
        aiClock -= dt
        guard aiClock <= 0 else { return }
        aiClock = AI.tickInterval

        let spendable = model.gold - aiReserve
        let allMaxed = !towers.isEmpty && towers.values.allSatisfy { $0.upgradeCost == nil }
        let cap = aiTowerCap(allMaxed: allMaxed)

        // 1) COMBO incompleto: o próximo papel faltante tem prioridade absoluta.
        if towers.count < cap, let want = aiCoreWant() {
            if model.gold >= want.cost, let hex = aiBestHex(for: want) {
                model.gold -= want.cost
                placeTower(want, at: hex)
                return
            }
            if let upg = aiBestUpgrade(budget: spendable) { aiApplyUpgrade(upg); return }
            if model.waveReady { startWaveNow() }
            return
        }

        // 2) EFICIÊNCIA: excedente acima da reserva.
        let build = aiBestBuild(budget: spendable, cap: cap)
        let upg   = aiBestUpgrade(budget: spendable)
        // SWAP: vender uma torre fraca e por outra melhor no lugar. Só entra quando não há
        // mais espaço pra construir (cap cheio) — aí a única forma de subir de patamar é
        // trocar. Fora disso, construir/upar são sempre preferíveis (não perde investimento).
        let swap = (build == nil) ? aiBestSwap(budget: spendable) : nil

        // Escolhe a ação de maior eficiência entre as disponíveis.
        let buildEff = build?.eff ?? -1
        let upgEff   = upg?.eff ?? -1
        let swapEff  = swap?.eff ?? -1
        let bestEff  = max(buildEff, upgEff, swapEff)

        func act() -> Bool {
            if bestEff < 0 { return false }
            if swapEff == bestEff, let s = swap { aiApplySwap(s); return true }
            if upgEff == bestEff, let u = upg { aiApplyUpgrade(u); return true }
            if let b = build { aiPlace(b); return true }
            return false
        }

        if model.waveReady {
            if act() { return }
            startWaveNow()
        } else {
            _ = act()
        }
    }

    /// Contagem de torres por elemento em campo.
    private func elementCounts() -> [Element: Int] {
        Dictionary(grouping: towers.values, by: { $0.spec.element }).mapValues(\.count)
    }

    /// Anti-combo: burn (Fogo) anula/é-anulado por wet (Água) e frozen (Gelo). A IA não
    /// mistura Fogo com Água/Gelo — assim forma naturalmente ou a família EXPLOSÃO
    /// (Fogo+Veneno) ou a de CONGELAMENTO (Água+Gelo), conforme o loadout disponível.
    private func aiCompatible(_ spec: TowerSpec) -> Bool {
        let elems = Set(towers.values.map { $0.spec.element })
        let hasFire = elems.contains(.fogo)
        let hasCold = elems.contains(.agua) || elems.contains(.gelo)
        if spec.element == .fogo && hasCold { return false }
        if (spec.element == .agua || spec.element == .gelo) && hasFire { return false }
        return true
    }

    /// Estrutura o início com um MIX de papéis: alterna striker (foco) e blaster (área),
    /// cada um de um elemento novo compatível, até ~5 torres. Depois entra a eficiência.
    /// Usa o que estiver liberado (loadout na Campanha), não um arquétipo fixo.
    private func aiCoreWant() -> TowerSpec? {
        guard towers.count < 5 else { return nil }
        let present = Set(towers.values.map { $0.spec.element })
        let roles = Dictionary(grouping: towers.values, by: { $0.spec.role }).mapValues(\.count)
        func best(_ role: TowerRole) -> TowerSpec? {
            TowerCatalog.all.filter {
                isAllowed($0.id) && $0.role == role && !present.contains($0.element) && aiCompatible($0)
            }.max { power($0) < power($1) }
        }
        // Alterna: menos representado primeiro (garante ao menos 1 blaster no núcleo).
        let wantBlasterFirst = (roles[.blaster] ?? 0) <= (roles[.striker] ?? 0)
        if wantBlasterFirst { return best(.blaster) ?? best(.striker) }
        return best(.striker) ?? best(.blaster)
    }

    private func aiBestHex(for spec: TowerSpec) -> Hex? {
        var best: Hex?; var bestCov = 0
        for h in placeableHexes where towers[h] == nil {
            let cov = coverage(at: h, range: spec.range)
            if cov > bestCov { bestCov = cov; best = h }
        }
        return bestCov >= AI.minCoverage ? best : nil
    }

    // MARK: — avaliação

    private func coverage(at h: Hex, range: Int) -> Int {
        map.path.reduce(0) { $0 + (h.distance(to: $1) <= range ? 1 : 0) }
    }

    /// Fator elemental esperado vs os inimigos. Na Campanha 65% são do elemento dominante
    /// → vantagem (×2) ou desvantagem (×0.5) conta. Sem dominante (Endless/Rogue) = 1.
    private func elementalFactor(_ e: Element) -> Double {
        guard let dom = config.dominantElement else { return 1.0 }
        return 0.65 * e.multiplier(against: dom) + 0.35 * 1.07
    }

    /// Bônus de POTENCIAL: torres de raridade maior têm mais teto de estrelas (maxStars),
    /// logo mais headroom de upgrade in-run → escalam melhor. +9% por estrela acima do piso
    /// (2). Ex.: Épica 5★ ×1.27, Mítica 7★ ×1.45. Faz o Auto preferir torres com mais teto.
    private func ceilingBonus(_ spec: TowerSpec) -> Double {
        1.0 + 0.09 * Double(max(0, meta.maxStars(spec.id) - MetaProgress.baseMaxStars))
    }

    /// DPS aproximado da torre no nível `level` (1 = recém-colocada), já com raridade meta,
    /// bônus de área, vantagem elemental e o potencial de teto (maxStars). Usado pra COLOCAR.
    private func power(_ spec: TowerSpec, level: Int = 1) -> Double {
        let dps = spec.baseDamage * Progression.upgradeEffect(lvl: level - 1)
                * meta.statMult(spec.id) / spec.cooldown
        return dps * (spec.splash > 0 ? AI.splashFactor : 1.0)
                   * elementalFactor(spec.element) * ceilingBonus(spec)
    }

    /// DPS REAL de uma torre já colocada: usa dano/cadência/splash efetivos (nível +
    /// raridade + habilidades + aura) × vantagem elemental. Usado pra avaliar UPGRADE.
    private func towerDPS(_ tw: Tower) -> Double {
        tw.damage / tw.cadence * (tw.splashHex > 0 ? AI.splashFactor : 1.0) * elementalFactor(tw.element)
    }

    /// Sinergia de colocar `spec` em `h`, PRIORIZANDO os pares que combam (§5):
    /// Veneno onde há Fogo (e vice-versa) → explosão; Arcana marca amplifica tudo;
    /// Físico expõe. Diversidade só entre os elementos do arquétipo.
    private func aiSynergy(_ spec: TowerSpec, at h: Hex) -> Double {
        let counts = elementCounts()
        var s = 1.0
        // Diversidade: bônus por trazer um elemento ainda ausente (habilita combos).
        if (counts[spec.element] ?? 0) == 0 { s *= 1.25 }
        // Mix de papéis: num caminho de fila única, muito single-target vira OVERKILL no
        // inimigo da frente. Penaliza excesso de striker e valoriza blaster (área/grupos)
        // quanto mais desbalanceado estiver → a IA alterna striker+blaster.
        let roles = Dictionary(grouping: towers.values, by: { $0.spec.role }).mapValues(\.count)
        let strikers = roles[.striker] ?? 0, blasters = roles[.blaster] ?? 0
        if spec.role == .striker { s *= strikers <= blasters ? 1.1 : 0.70 }
        if spec.role == .blaster { s *= min(3.0, pow(1.25, Double(max(0, strikers - blasters)))) }
        // Pares que combam.
        switch spec.applies {
        case .poison: if (counts[.fogo] ?? 0) > 0 { s *= 1.4 }        // burn+veneno = explosão
        case .burn:   if (counts[.veneno] ?? 0) > 0 { s *= 1.4 }
        case .frozen: if (counts[.agua] ?? 0) > 0 { s *= 1.35 }       // molhado+gelo = congelamento total
        case .wet:    if (counts[.gelo] ?? 0) > 0 { s *= 1.2 }
        case .marked: s *= 1.25                                       // amplifica todo o dano
        case .exposed: s *= 1.12
        default: break
        }
        if spec.role == .support {
            let near = towers.values.filter { $0.hex.distance(to: h) <= TowerAbility.Tuning.auraRange }.count
            s *= 1.0 + 0.12 * Double(near)
        }
        if meta.abilities(spec.id).contains(.precisao) { s *= 1.06 }
        return s
    }

    private struct BuildOption { let hex: Hex; let spec: TowerSpec; let eff: Double; let cost: Int }
    private struct UpgradeOption { let hex: Hex; let eff: Double; let cost: Int }

    private func aiBestBuild(budget: Int, cap: Int) -> BuildOption? {
        guard towers.count < cap else { return nil }
        var best: BuildOption?
        for h in placeableHexes where towers[h] == nil {
            for spec in TowerCatalog.all where spec.cost <= budget && isAllowed(spec.id) && aiCompatible(spec) {
                let cover = coverage(at: h, range: spec.range)
                guard cover >= AI.minCoverage else { continue }
                let value = Double(cover) * power(spec) * aiSynergy(spec, at: h)
                let eff = value / Double(spec.cost)
                if eff > (best?.eff ?? 0) { best = BuildOption(hex: h, spec: spec, eff: eff, cost: spec.cost) }
            }
        }
        return best
    }

    private func aiBestUpgrade(budget: Int) -> UpgradeOption? {
        var best: UpgradeOption?
        for (h, tw) in towers {
            guard let cost = tw.upgradeCost, cost <= budget else { continue }
            let cover = coverage(at: h, range: tw.rangeHex)
            let value = Double(cover) * towerDPS(tw) * AI.upgradeStep
            let eff = value / Double(cost)
            if eff > (best?.eff ?? 0) { best = UpgradeOption(hex: h, eff: eff, cost: cost) }
        }
        return best
    }

    private struct SwapOption { let hex: Hex; let spec: TowerSpec; let eff: Double; let netCost: Int }

    /// Vende uma torre em DESVANTAGEM elemental e coloca outra em VANTAGEM no mesmo spot.
    /// DIRECIONAL de propósito (só desvantagem→vantagem) pra não oscilar: a torre nova, já
    /// vantajosa, nunca vira candidata a novo swap → sem loop de venda/compra. Sem elemento
    /// dominante (Endless), NÃO troca — ali o synergy é contextual e causaria churn.
    /// Compara DPS PURO (mesma métrica dos dois lados, sem synergy) — o custo do upgrade
    /// perdido é respeitado: uma torre evoluída só é trocada se a nova ainda supera o DPS.
    private func aiBestSwap(budget: Int) -> SwapOption? {
        guard let dom = config.dominantElement else { return nil }
        var best: SwapOption?
        for (h, tw) in towers {
            // só considera trocar torres que NÃO têm vantagem contra o inimigo da fase.
            guard tw.spec.element.multiplier(against: dom) <= 1.0 else { continue }
            let curValue = Double(coverage(at: h, range: tw.rangeHex)) * towerDPS(tw)
            let refund = tw.sellValue
            for spec in TowerCatalog.all where isAllowed(spec.id) {
                // alvo TEM que ter vantagem elemental (direcional → não oscila).
                guard spec.element.multiplier(against: dom) > 1.0 else { continue }
                let netCost = spec.cost - refund
                guard netCost <= budget else { continue }
                // compatibilidade anti-combo ignorando a própria torre (que vai sair).
                let others = Set(towers.values.filter { $0 !== tw }.map { $0.spec.element })
                let hasFire = others.contains(.fogo)
                let hasCold = others.contains(.agua) || others.contains(.gelo)
                if spec.element == .fogo && hasCold { continue }
                if (spec.element == .agua || spec.element == .gelo) && hasFire { continue }
                let cover = coverage(at: h, range: spec.range)
                guard cover >= AI.minCoverage else { continue }
                // DPS puro dos dois lados (sem synergy) → comparação estável.
                let newValue = Double(cover) * power(spec)
                // só troca com ganho claro (evita churn); eff pondera o custo líquido.
                guard newValue > curValue * 1.25 else { continue }
                let eff = (newValue - curValue) / Double(max(1, netCost))
                if eff > (best?.eff ?? 0) { best = SwapOption(hex: h, spec: spec, eff: eff, netCost: netCost) }
            }
        }
        return best
    }

    private func aiApplySwap(_ s: SwapOption) {
        guard let tw = towers[s.hex] else { return }
        sell(tw)                       // devolve o gold da venda
        guard model.gold >= s.spec.cost else { return }
        model.gold -= s.spec.cost
        placeTower(s.spec, at: s.hex)
    }

    // MARK: — ações

    private func aiPlace(_ b: BuildOption) {
        guard model.gold >= b.cost else { return }
        model.gold -= b.cost
        placeTower(b.spec, at: b.hex)
    }

    private func aiApplyUpgrade(_ u: UpgradeOption) {
        guard let tw = towers[u.hex], let cost = tw.upgradeCost, model.gold >= cost else { return }
        model.gold -= cost
        tw.spent += cost
        tw.level += 1
        updatePip(tw)
        if selectedTower === tw { updateRing(tw); pushInspect(tw) }
    }

    private enum Boss {
        static let hpMult = 12.0
        static let speedMult = 0.55
        static let bounty = 5           // tier de gold do boss (o maior de todos)
        static let exitDamage = 5
        static let splashResist = 0.35   // torres de ÁREA fazem só 35% no boss (§boss)
    }

    /// Arquétipos de inimigo (§enemies). Cada um spawna em grupo, com HP/tamanho e
    /// vulnerabilidades próprias, exigindo estratégias diferentes.
    private enum EnemyType: CaseIterable {
        case swarm   // pequeno, muitos, morre rápido → arma AOE
        case trio    // pequeno, 3, mais HP → depende de combo (DoT/explosão)
        case duo     // médio, par, mais HP → torres individuais
        case elite   // grande, solo, muito HP (½ boss) → só arma solo, AOE bem reduzido

        var groupSize: Int { switch self { case .swarm: return 6; case .trio: return 3; case .duo: return 2; case .elite: return 1 } }
        var hpMult: Double { switch self { case .swarm: return 0.35; case .trio: return 1.4; case .duo: return 2.2; case .elite: return 6.0 } }
        var sizeMult: Double { switch self { case .swarm: return 0.7; case .trio: return 0.85; case .duo: return 1.05; case .elite: return 1.5 } }
        var splashResist: Double { switch self { case .duo: return 0.55; case .elite: return 0.30; default: return 1.0 } }
        var comboMult: Double { self == .trio ? 1.4 : 1.0 }   // trio sofre +40% de combos/DoTs
        var bounty: Int { switch self { case .swarm: return 1; case .trio: return 2; case .duo: return 3; case .elite: return 4 } }  // tier de gold 1…5 (boss=5)
        var weight: Int { switch self { case .swarm: return 35; case .trio: return 25; case .duo: return 25; case .elite: return 12 } }
        var marker: String? { self == .elite ? "💪" : nil }
    }

    private var groupType: EnemyType = .swarm
    private var groupRemaining = 0

    private func pickEnemyType() -> EnemyType {
        let total = EnemyType.allCases.reduce(0) { $0 + $1.weight }
        var r = Int.random(in: 0..<total, using: &waveRNG)
        for t in EnemyType.allCases { if r < t.weight { return t }; r -= t.weight }
        return .swarm
    }

    /// Um passo de spawn: continua o grupo atual ou começa um novo (tipo sorteado).
    private func spawnStep() {
        if groupRemaining <= 0 { groupType = pickEnemyType(); groupRemaining = groupType.groupSize }
        spawnEnemy(type: groupType)
        groupRemaining -= 1
    }

    private func spawnEnemy(type: EnemyType = .swarm, boss: Bool = false) {
        if !boss { toSpawn -= 1 }
        // Elemento tema da fase predomina (§element); senão aleatório.
        let el: Element
        if let dom = config.dominantElement, Double.random(in: 0..<1, using: &waveRNG) < 0.65 { el = dom }
        else { el = Element.allCases.randomElement(using: &waveRNG)! }
        let c = layout.center(of: map.entrance)
        let node = SKNode(); node.position = c
        let rgb = el.rgb
        let sizeMult = boss ? 1.62 : type.sizeMult
        let s = hexSize * 0.38 * sizeMult
        let dia = CGMutablePath()
        dia.move(to: CGPoint(x: 0, y: s));  dia.addLine(to: CGPoint(x: s, y: 0))
        dia.addLine(to: CGPoint(x: 0, y: -s)); dia.addLine(to: CGPoint(x: -s, y: 0))
        dia.closeSubpath()
        let body = SKShapeNode(path: dia)
        body.fillColor = SKColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        let isElite = !boss && type == .elite
        body.strokeColor = boss ? SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
                         : isElite ? SKColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1) : .black
        body.lineWidth = boss ? 3 : (isElite ? 3 : 1)
        node.addChild(body)
        if boss {
            let crown = SKLabelNode(text: "👑")
            crown.fontSize = hexSize * 0.5; crown.verticalAlignmentMode = .center
            node.addChild(crown)
        } else if let m = type.marker {
            let mk = SKLabelNode(text: m); mk.fontSize = hexSize * 0.42
            mk.verticalAlignmentMode = .center; node.addChild(mk)
        }
        let barW = hexSize * 0.8 * sizeMult
        let by = hexSize * 0.5 * sizeMult
        let bg = SKShapeNode(rect: CGRect(x: -barW/2, y: by, width: barW, height: 4), cornerRadius: 2)
        bg.fillColor = .black; bg.strokeColor = .clear; node.addChild(bg)
        let bar = SKShapeNode(rect: CGRect(x: -barW/2, y: by, width: barW, height: 4), cornerRadius: 2)
        bar.fillColor = .green; bar.strokeColor = .clear; node.addChild(bar)
        let stLabel = SKLabelNode(text: "")
        stLabel.fontSize = hexSize * 0.34; stLabel.verticalAlignmentMode = .center
        stLabel.position = CGPoint(x: 0, y: by + hexSize * 0.28); node.addChild(stLabel)
        enemyLayer.addChild(node)
        let hp = waveHP * (boss ? Boss.hpMult : type.hpMult)
        let speed = (1.1 + Double(model.wave) * 0.02) * (boss ? Boss.speedMult : 1) * config.enemySpeedMult
        // Gold por kill (item 3): base sublinear por wave × TIER do tipo (1=swarm … 5=boss).
        let goldWeight = Double(boss ? Boss.bounty : type.bounty)
        let bounty = Int((Progression.goldPerKill(wave: model.wave) * goldWeight).rounded())
        enemies.append(Enemy(element: el, hp: hp, speed: speed,
                             bounty: bounty, isBoss: boss,
                             splashResist: boss ? Boss.splashResist : type.splashResist,
                             comboMult: boss ? 1 : type.comboMult,
                             node: node, hpBar: bar, statusLabel: stLabel))
    }

    private func stepEnemies(dt: Double) {
        guard map.path.count >= 2 else { return }
        var survivors: [Enemy] = []
        let now = gameClock
        for e in enemies {
            // DoTs: queimadura + veneno (empilhado).
            var dot = 0.0
            if e.active(.burn, now) { dot += e.burnDps }
            if e.active(.poison, now) { dot += e.poisonDps }
            if dot > 0 {
                e.hp -= dot * dt * e.comboMult   // trio sofre +40% de DoT
                updateHpBar(e)
                if e.hp <= 0 { killByDot(e); continue }
            }
            updateStatusIcons(e, now: now)
            let v = e.speed * (e.slowed(now) ? e.slowFactor : 1.0)
            e.t += v * dt
            while e.t >= 1 && e.seg < map.path.count - 1 { e.t -= 1; e.seg += 1 }
            if e.seg >= map.path.count - 1 {
                model.lives -= e.isBoss ? Boss.exitDamage : 1   // boss custa mais vidas
                e.node.removeFromParent()
                if model.lives <= 0 { endGame() }
                continue
            }
            let a = layout.center(of: map.path[e.seg])
            let b = layout.center(of: map.path[e.seg + 1])
            e.node.position = CGPoint(x: a.x + (b.x - a.x) * e.t, y: a.y + (b.y - a.y) * e.t)
            survivors.append(e)
        }
        enemies = survivors
    }

    private func stepTowers(dt: Double, now: TimeInterval) {
        for (_, tw) in towers {
            tw.cooldown -= dt
            guard tw.cooldown <= 0 else { continue }
            guard let target = enemyInRange(of: tw) else { continue }
            tw.cooldown = tw.cadence
            fire(tw, at: target)
        }
    }

    private func enemyInRange(of tw: Tower) -> Enemy? {
        let rangePx = CGFloat(tw.rangeHex) * hexSize * sqrt(3.0)
        let c = tw.node.position
        return enemies
            .filter { $0.node.position.distanceSq(c) <= rangePx * rangePx }
            .max { ($0.seg, $0.t) < ($1.seg, $1.t) }
    }

    private func fire(_ tw: Tower, at target: Enemy) {
        if fxEnabled { Audio.shared.sfx("shoot") }   // fxEnabled = só no passo visível (não nos sub-steps)
        beam(from: tw.node.position, to: target.node.position, element: tw.element)
        applyDamage(tw, to: target)
        // Perfuração: o tiro segue e atinge o 2º alvo mais avançado.
        if tw.has(.perfuracao), let second = secondTarget(of: tw, excluding: target) {
            beam(from: target.node.position, to: second.node.position, element: tw.element)
            applyDamage(tw, to: second, factor: TowerAbility.Tuning.pierceFactor, splash: true)
        }
        if tw.splashHex > 0 {
            let r = CGFloat(tw.splashHex) * hexSize * sqrt(3.0)
            for e in enemies where e !== target &&
                e.node.position.distanceSq(target.node.position) <= r * r {
                applyDamage(tw, to: e, splash: true)
            }
            let rgb = tw.element.rgb
            flash(at: target.node.position, color: SKColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 0.5))
        }
    }

    private func secondTarget(of tw: Tower, excluding first: Enemy) -> Enemy? {
        let rangePx = CGFloat(tw.rangeHex) * hexSize * sqrt(3.0)
        let c = tw.node.position
        return enemies
            .filter { $0 !== first && $0.node.position.distanceSq(c) <= rangePx * rangePx }
            .max { ($0.seg, $0.t) < ($1.seg, $1.t) }
    }

    /// Aplica dano de um tiro + o status-base do elemento (§combo). `factor` reduz
    /// (perfuração/splash); `splash` marca acertos secundários.
    private func applyDamage(_ tw: Tower, to e: Enemy, factor: Double = 1, splash: Bool = false) {
        let now = gameClock
        let mult = tw.element.multiplier(against: e.element)
        var dealt = tw.damage * mult * factor
        // Resistência a ÁREA por tipo (boss/elite/duo) → força single-target.
        if tw.spec.splash > 0 { dealt *= e.splashResist }
        // Estilhaços (habilidade): alvo lento sofre +25% de qualquer torre.
        if shatterActive && e.slowed(now) { dealt *= TowerAbility.Tuning.shatterBonus }
        // Combo Estilhaçar: Físico num inimigo CONGELADO → burst e consome o gelo.
        var shattered = false
        if tw.element == .fisico && e.active(.frozen, now) {
            dealt *= Status.T.shatterMult; e.statusUntil[.frozen] = 0; shattered = true
        }
        // Marcado/Exposto amplificam o dano recebido.
        if e.active(.marked, now)  { dealt *= Status.T.markedMult }
        if e.active(.exposed, now) { dealt *= Status.T.exposedMult }
        // Execução: dano extra em inimigo com pouca vida.
        if tw.has(.execucao) && e.hp < e.maxHp * TowerAbility.Tuning.execucaoHp {
            dealt *= TowerAbility.Tuning.execucaoMult
        }
        var crit = false
        if !splash && tw.has(.precisao) && Double.random(in: 0..<1) < TowerAbility.Tuning.critChance {
            dealt *= TowerAbility.Tuning.critMult; crit = true
        }
        e.hp -= dealt
        floatDamage(dealt, mult: mult, crit: crit, at: e.node.position)
        if shattered { comboFlash(at: e.node.position, color: sk(.gelo)) }
        // Aplica o status-base do elemento (com reações de combo). Torres de área
        // aplicam também no splash; strikers só no acerto direto.
        if let st = tw.spec.applies, (!splash || tw.spec.splash > 0) {
            applyStatus(st, to: e, from: tw, now: now)
        }
        // Detonador: inimigo com 2+ status explode ao ser atingido.
        if tw.has(.detonador) && !splash && statusCount(e, now) >= TowerAbility.Tuning.detonadorMinStatus {
            explodeArea(around: e, boom: tw.damage * TowerAbility.Tuning.detonadorFrac, color: sk(.arcana))
        }
        if tw.has(.cobranca) && !splash { model.gold += TowerAbility.Tuning.cobrancaPerHit }
        updateHpBar(e)
        if e.hp <= 0 { kill(e, bonus: killBonus(tw)) }
    }

    private func statusCount(_ e: Enemy, _ now: Double) -> Int {
        Status.allCases.reduce(0) { $0 + (e.active($1, now) ? 1 : 0) }
    }

    /// Aplica um status ao inimigo, resolvendo as reações de combo do NÚCLEO (§3):
    /// molhado⊘burn, burn⊘congelar, molhado+gelo=congelamento total, burn+veneno=explosão.
    private func applyStatus(_ st: Status, to e: Enemy, from tw: Tower, now: Double) {
        let pot = tw.has(.potencia) ? TowerAbility.Tuning.potenciaMult : 1.0   // Potência: status mais fortes/longos
        switch st {
        case .burn:
            if e.active(.wet, now) { e.statusUntil[.wet] = 0; comboFlash(at: e.node.position, color: sk(.agua)); return }  // molhado apaga o fogo
            let boost = tw.has(.queimadura) ? TowerAbility.Tuning.burnBoostMult : 1.0
            let dps = tw.damage * Status.T.burnFrac * boost * pot
            e.burnDps = max(e.burnDps, dps)
            e.statusUntil[.burn] = now + Status.T.burnDur * pot
            if e.active(.poison, now) { explodeArea(around: e, boom: tw.damage * Status.T.explosionFrac, color: sk(.veneno)) }  // burn + veneno
            if tw.has(.contagio) { spreadStatus(.burn, from: e, dps: dps * TowerAbility.Tuning.contagioFrac, now: now) }
        case .frozen:
            if e.active(.burn, now) { e.statusUntil[.burn] = 0; comboFlash(at: e.node.position, color: sk(.fogo)); return }  // burn impede congelar
            let wetCombo = e.active(.wet, now)
            let deep = tw.has(.profundo) || wetCombo
            if wetCombo { e.statusUntil[.wet] = 0; comboFlash(at: e.node.position, color: sk(.gelo)) }   // congelamento total
            e.slowFactor = deep ? Status.T.freezeFactor : Status.T.slowFactor
            e.statusUntil[.frozen] = now + (deep ? Status.T.freezeDur : Status.T.slowDur) * pot
        case .rooted:
            e.slowFactor = min(e.slowFactor, Status.T.rootedFactor)
            e.statusUntil[.rooted] = now + Status.T.slowDur * pot
        case .poison:
            let dps = tw.damage * Status.T.poisonFrac * pot
            e.poisonDps += dps
            e.statusUntil[.poison] = now + Status.T.poisonDur * pot
            if e.active(.burn, now) { explodeArea(around: e, boom: tw.damage * Status.T.explosionFrac, color: sk(.veneno)) }  // veneno + burn
            if tw.has(.contagio) { spreadStatus(.poison, from: e, dps: dps * TowerAbility.Tuning.contagioFrac, now: now) }
        case .wet:
            if e.active(.burn, now) { e.statusUntil[.burn] = 0 }   // molhar apaga fogo existente
            e.statusUntil[.wet] = now + Status.T.wetDur * pot
        case .exposed:
            e.statusUntil[.exposed] = now + Status.T.exposedDur * pot
        case .marked:
            e.statusUntil[.marked] = now + Status.T.markedDur * pot
        }
    }

    /// Contágio: espalha burn/veneno pro inimigo mais próximo (potência reduzida).
    private func spreadStatus(_ st: Status, from e: Enemy, dps: Double, now: Double) {
        let r = hexSize * sqrt(3.0) * 1.4
        guard let near = enemies
            .filter({ $0 !== e && $0.node.position.distanceSq(e.node.position) <= r * r })
            .min(by: { $0.node.position.distanceSq(e.node.position) < $1.node.position.distanceSq(e.node.position) })
        else { return }
        if st == .burn { near.burnDps = max(near.burnDps, dps); near.statusUntil[.burn] = now + Status.T.burnDur }
        if st == .poison { near.poisonDps += dps; near.statusUntil[.poison] = now + Status.T.poisonDur }
    }

    /// Explosão em área (burn+veneno ou Detonador): dano nos inimigos vizinhos.
    private func explodeArea(around e: Enemy, boom: Double, color: SKColor) {
        let r = hexSize * sqrt(3.0)
        comboFlash(at: e.node.position, color: color)
        for other in enemies where other.node.position.distanceSq(e.node.position) <= r * r {
            let dmg = boom * other.comboMult
            other.hp -= dmg
            floatDamage(dmg, mult: 1, at: other.node.position)
            updateHpBar(other)
        }
        for other in enemies where other.hp <= 0 { kill(other, bonus: 0) }
    }

    /// Ícones dos status ativos acima do inimigo (leitura dos combos).
    private func updateStatusIcons(_ e: Enemy, now: Double) {
        var s = ""
        for st in Status.allCases where e.active(st, now) { s += st.icon }
        if e.statusLabel.text != s { e.statusLabel.text = s }
    }

    private func sk(_ el: Element, _ a: CGFloat = 0.85) -> SKColor {
        let c = el.rgb; return SKColor(red: c.r, green: c.g, blue: c.b, alpha: a)
    }

    /// Flash maior/destacado pras reações de combo.
    private func comboFlash(at p: CGPoint, color: SKColor) {
        guard fxEnabled else { return }
        let n = SKShapeNode(circleOfRadius: hexSize * 0.7)
        n.position = p; n.fillColor = color; n.strokeColor = .white; n.lineWidth = 2
        fxLayer.addChild(n)
        n.run(.sequence([.group([.scale(to: 2.0, duration: 0.3), .fadeOut(withDuration: 0.3)]),
                         .removeFromParent()]))
    }

    private func killBonus(_ tw: Tower) -> Int {
        tw.has(.cobranca) ? TowerAbility.Tuning.cobrancaBounty : tw.spec.bounty
    }

    private func updateHpBar(_ e: Enemy) {
        let frac = max(0, e.hp / e.maxHp)
        e.hpBar.xScale = CGFloat(frac)
        e.hpBar.fillColor = frac > 0.5 ? .green : (frac > 0.25 ? .yellow : .red)
    }

    // Gold por kill reduzido 25% (§economia). Buffer fracionário → exato ao longo do
    // jogo mesmo com gold inteiro (6×0.75 = 4.5 alterna entre 4 e 5).
    private static let bountyMult = 0.75
    private var goldFrac: Double = 0
    private func bountyGold(_ base: Int) -> Int {
        goldFrac += Double(base) * Self.bountyMult
        let whole = Int(goldFrac); goldFrac -= Double(whole)
        return whole
    }

    private func killByDot(_ e: Enemy) {
        guard e.node.parent != nil else { return }
        model.gold += bountyGold(e.bounty)
        flash(at: e.node.position, color: SKColor(red: e.element.rgb.r, green: e.element.rgb.g,
                                                  blue: e.element.rgb.b, alpha: 0.6))
        e.node.removeFromParent()
        enemies.removeAll { $0 === e }
    }

    private func kill(_ e: Enemy, bonus: Int) {
        guard e.node.parent != nil else { return }
        if fxEnabled { Audio.shared.sfx("hit") }
        model.gold += bountyGold(e.bounty) + bonus
        flash(at: e.node.position, color: SKColor(red: e.element.rgb.r, green: e.element.rgb.g,
                                                  blue: e.element.rgb.b, alpha: 0.6))
        e.node.removeFromParent()
        enemies.removeAll { $0 === e }
    }

    private func floatDamage(_ dmg: Double, mult: Double, crit: Bool = false, at p: CGPoint) {
        guard fxEnabled else { return }
        let l = SKLabelNode(text: crit ? "\(Int(dmg.rounded()))!" : "\(Int(dmg.rounded()))")
        l.fontName = "AvenirNext-Bold"
        l.fontSize = hexSize * (crit ? 0.7 : (mult > 1 ? 0.58 : 0.46))
        l.verticalAlignmentMode = .center; l.position = p
        l.fontColor = crit ? SKColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 1)
                    : mult > 1 ? SKColor(red: 0.40, green: 0.95, blue: 0.45, alpha: 1)
                    : mult < 1 ? SKColor(white: 0.60, alpha: 1)
                    : .white
        fxLayer.addChild(l)
        l.run(.sequence([.group([.moveBy(x: 0, y: hexSize * 0.9, duration: 0.5),
                                 .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
    }

    // MARK: fx

    private func beam(from a: CGPoint, to b: CGPoint, element: Element) {
        guard fxEnabled else { return }
        let line = SKShapeNode()
        let path = CGMutablePath(); path.move(to: a); path.addLine(to: b); line.path = path
        let rgb = element.rgb
        line.strokeColor = SKColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 0.9)
        line.lineWidth = 2.5
        fxLayer.addChild(line)
        line.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
    }

    private func flash(at p: CGPoint, color: SKColor) {
        guard fxEnabled else { return }
        let n = SKShapeNode(circleOfRadius: hexSize * 0.5)
        n.position = p; n.fillColor = color; n.strokeColor = .clear
        fxLayer.addChild(n)
        n.run(.sequence([.group([.scale(to: 1.6, duration: 0.2), .fadeOut(withDuration: 0.2)]),
                         .removeFromParent()]))
    }

    private func endGame() {
        deselect()
        Audio.shared.sfx("lose")
        // Vs: crédito/score são resolvidos na VsView (não por tabuleiro). Só marca a derrota.
        if !config.isVs {
            awardCredits(won: false)
            if isEndless { meta.recordEndless(model.wave) }
        }
        model.gameOver = true
        model.message = "Derrota — onda \(model.wave)"
    }

    private func winGame() {
        deselect()
        Audio.shared.sfx("win")
        awardCredits(won: true)
        if isEndless { meta.recordEndless(model.wave) }
        model.won = true
        model.message = "Vitória! 🏆"
    }

    /// Créditos por partida (§economia): Endless = 1/onda; Campanha vitória = 10;
    /// Rogue vitória = 20; derrota em modo finito = 0. O crédito máximo é ganho com
    /// as 10 vidas intactas e reduz 10% por vida perdida (proporção `lives / maxLives`).
    private func awardCredits(won: Bool) {
        let rogue = config.seed == nil && config.targetWave != nil
        if isEndless {
            let c = model.wave
            model.creditsEarned = c
            meta.addCredits(c)
            return
        }
        guard won else { model.creditsEarned = 0; return }
        let base = rogue ? MetaProgress.creditsRogueWin : MetaProgress.creditsCampaignWin
        let frac = Double(max(0, model.lives)) / Double(MetaProgress.maxLives)  // 1.0 … 0.0
        let c = max(0, Int((Double(base) * frac).rounded()))
        model.creditsEarned = c
        meta.addCredits(c)
    }
}

private extension CGPoint {
    func distanceSq(_ o: CGPoint) -> CGFloat { let dx = x - o.x, dy = y - o.y; return dx*dx + dy*dy }
}
