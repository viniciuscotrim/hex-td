import SpriteKit

/// Os 6 upgrades in-run do Rogue idle (estilo The Tower). Resetam a cada partida.
enum RogueUpgrade: Int, CaseIterable {
    case damage, atkSpeed, hp, regen, range, crit
    var icon: String {
        switch self {
        case .damage:   return "⚔️"
        case .atkSpeed: return "⚡️"
        case .hp:       return "❤️"
        case .regen:    return "➕"
        case .range:    return "🎯"
        case .crit:     return "🎲"
        }
    }
    var nome: String {
        switch self {
        case .damage:   return "Dano"
        case .atkSpeed: return "Vel. Ataque"
        case .hp:       return "HP Máx."
        case .regen:    return "HP / s"
        case .range:    return "Distância"
        case .crit:     return "Crítico 2×"
        }
    }
}

/// Rogue = sobrevivência idle: UMA torre (a escolhida, com stats/skills do meta) no
/// centro de uma arena aberta; inimigos vêm de todos os lados. Ela atira sozinha; o
/// jogador só compra os 6 upgrades com o gold dos kills. Game over ao zerar o HP.
final class RogueScene: SKScene {
    private unowned let model: GameModel
    private unowned let meta: MetaProgress

    // Torre central (fixada no início da run).
    private var spec: TowerSpec = TowerCatalog.spec(9)
    private var rarityMult: Double = 1
    private var abilities: Set<TowerAbility> = []

    // Balanço (tunável).
    private let baseMaxHP = 250.0
    private let baseRegenPct = 0.004       // 0.4%/s do HP máx no nível 0 (escala com o HP)
    private let regenPctPerLvl = 0.002     // +0.2%/s por nível
    private let waveInterval = 8.0         // segundos por onda (~33% mais lento p/ dar tempo de upar)
    private let baseRangePts: CGFloat = 110
    private let contactRadius: CGFloat = 30

    private final class Foe {
        let node: SKShapeNode
        var hp: Double
        let maxHp: Double
        var pos: CGPoint
        let vel: CGVector          // direção normalizada * velocidade base
        let element: Element
        let bounty: Int
        let touchDPS: Double
        // status
        var burnUntil = 0.0, burnDps = 0.0
        var poisonUntil = 0.0, poisonDps = 0.0
        var slowUntil = 0.0, slowFactor = 1.0
        var markedUntil = 0.0, exposedUntil = 0.0, wetUntil = 0.0
        var dead = false
        init(node: SKShapeNode, hp: Double, pos: CGPoint, vel: CGVector,
             element: Element, bounty: Int, touchDPS: Double) {
            self.node = node; self.hp = hp; self.maxHp = hp; self.pos = pos
            self.vel = vel; self.element = element; self.bounty = bounty; self.touchDPS = touchDPS
        }
    }

    private var foes: [Foe] = []
    private var center = CGPoint.zero
    private var clock = 0.0
    private var cooldown = 0.0
    private var spawnClock = 0.0
    private var spawnInterval = 1.0
    private var toSpawn = 0
    private var hp = 0.0

    private let towerNode = SKNode()
    private let rangeRing = SKShapeNode()
    private let hpBar = SKShapeNode()
    private let foeLayer = SKNode()
    private let fxLayer = SKNode()
    private let cam = SKCameraNode()
    private var camScale: CGFloat = 1     // zoom out (≥1) p/ o alcance caber sempre no frame

    init(model: GameModel, meta: MetaProgress, size: CGSize) {
        self.model = model; self.meta = meta
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = meta.frameLimit
        [rangeRing, foeLayer, fxLayer, towerNode, cam].forEach(addChild)
        camera = cam
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        cam.position = center
        model.doRogueUpgrade = { [weak self] i in self?.buyUpgrade(i) }
        model.doRogueStart = { [weak self] in self?.beginRun() }
        buildTower()
        recompute()
        // Harness (§dev): HEXTD_ROGUE inicia a run sozinho, acelerado.
        let env = ProcessInfo.processInfo.environment
        if env["HEXTD_ROGUE"] != nil {
            meta.debugUnlockAll(); model.speed = 5; model.autoPlay = true
            if let t = env["HEXTD_ROGUE_TOWER"], let id = Int(t) { model.selected = id }
            beginRun()
        }
    }

    override func didChangeSize(_ old: CGSize) {
        super.didChangeSize(old)
        guard size.width > 0 else { return }
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        cam.position = center
        towerNode.position = center; rangeRing.position = center
        updateRangeRing(); updateZoom()
    }

    /// Zoom out da câmera proporcional ao alcance → o anel de alcance (e a arena) sempre
    /// cabem no frame. Zoom só aumenta (≥1): no alcance base a câmera fica em 1×.
    private func updateZoom() {
        guard size.width > 0 else { return }
        let desired = min(size.width, size.height) * 0.5 * 0.92   // raio-alvo do anel na tela
        camScale = max(1, rangePts / max(1, desired))
        cam.removeAction(forKey: "zoom")
        cam.run(.scale(to: camScale, duration: 0.35), withKey: "zoom")
    }

    // MARK: início da run

    private var runSeed: UInt64 = 0
    private var rogueCfg = ProgressionConfig()   // config do run com r±variância por seed (item 7)

    private func beginRun() {
        guard !model.rogueStarted else { return }
        spec = TowerCatalog.spec(model.selected)
        rarityMult = meta.statMult(spec.id)
        abilities = Set(meta.abilities(spec.id))
        runSeed = UInt64.random(in: .min ... .max)
        rogueCfg = Progression.rogueConfig(seed: runSeed)
        model.rogueUpg = Array(repeating: 0, count: 6)
        recompute()
        hp = model.rogueMaxHP
        model.rogueHP = hp
        model.wave = 0; model.rogueKills = 0
        buildTower()
        model.rogueStarted = true
    }

    private func buildTower() {
        towerNode.removeAllChildren()
        towerNode.position = center
        let rgb = spec.element.rgb
        let disc = SKShapeNode(circleOfRadius: contactRadius)
        disc.fillColor = SKColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        disc.strokeColor = .white; disc.lineWidth = 3
        let icon = SKLabelNode(text: spec.icon)
        icon.fontSize = contactRadius * 1.1; icon.verticalAlignmentMode = .center
        towerNode.addChild(disc); towerNode.addChild(icon)
        // barra de HP acima da torre
        hpBar.position = CGPoint(x: 0, y: contactRadius + 12)
        towerNode.addChild(hpBar)
        updateHPBar()
        rangeRing.position = center
        rangeRing.strokeColor = SKColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 0.35)
        rangeRing.lineWidth = 1.5
        rangeRing.fillColor = SKColor(white: 0.5, alpha: 0.25)   // área de ataque: cinza leve 25%
        updateRangeRing()
    }

    // MARK: stats derivados (spec meta + upgrades da run)

    private var lvl: [Int] { model.rogueUpg }
    private var damage: Double { spec.baseDamage * rarityMult * (1 + 0.30 * Double(lvl[0])) }
    private var cadence: Double {
        let ab = abilities.contains(.cadencia) ? TowerAbility.Tuning.cadenciaMult : 1
        return spec.cooldown * pow(0.92, Double(lvl[1])) * ab
    }
    private var maxHP: Double { baseMaxHP * (1 + 0.25 * Double(lvl[2])) }
    private var regenPct: Double { baseRegenPct + regenPctPerLvl * Double(lvl[3]) }
    private var regen: Double { maxHP * regenPct }   // hp/s = % do HP máx → escala com o HP
    private var rangePts: CGFloat {
        let ab = abilities.contains(.alcance) ? CGFloat(TowerAbility.Tuning.alcanceBonus) : 0
        return baseRangePts + CGFloat(spec.range) * 22 + CGFloat(lvl[4]) * 22 + ab * 22
    }
    private var critChance: Double { min(0.75, Double(lvl[5]) * 0.06) }
    // Raio de área (torres blaster/AoE): metade do anterior (estava forte demais).
    private var splashPts: CGFloat { spec.splash > 0 ? 30 + CGFloat(spec.splash) * 17 + CGFloat(lvl[4]) * 3 : 0 }

    /// Torres SEM área atacam vários alvos ao mesmo tempo (tipo Balista). Blaster de
    /// dano único = 3 alvos; Perfuração soma +2 alvos. Torres de área usam splash (1).
    private var multiShot: Int {
        guard spec.splash == 0 else { return 1 }
        var n = 1
        if spec.role == .blaster { n += 2 }                 // Balista: canhão multi-alvo
        if abilities.contains(.perfuracao) { n += 2 }       // habilidade Perfuração
        return n
    }

    private static let baseCost = [30, 34, 40, 34, 30, 55]
    private func recompute() {
        for i in 0..<6 {
            model.rogueCost[i] = Int(Double(Self.baseCost[i]) * pow(1.55, Double(lvl[i])))
        }
        // Multiplicador atual de cada stat (1.X×) mostrado nos cards.
        let baseRange = Double(baseRangePts + CGFloat(spec.range) * 22)
        model.rogueMult = [
            1 + 0.30 * Double(lvl[0]),                       // Dano
            1 / pow(0.92, Double(lvl[1])),                   // Vel. de ataque (cadência)
            1 + 0.25 * Double(lvl[2]),                       // HP máx.
            regenPct * 100,                                  // HP/s → mostrado como %/s (não é ×)
            (baseRange + Double(lvl[4]) * 22) / baseRange,   // Distância
            1 + critChance                                   // Crítico 2× (dano efetivo esperado)
        ]
        model.rogueMaxHP = maxHP
        updateRangeRing(); updateHPBar(); updateZoom()
    }

    private func buyUpgrade(_ i: Int) {
        guard model.rogueStarted, !model.gameOver, i >= 0, i < 6 else { return }
        let cost = model.rogueCost[i]
        guard model.gold >= cost else { return }
        model.gold -= cost
        let before = maxHP
        model.rogueUpg[i] += 1
        if !model.autoPlay { Audio.shared.sfx("upgrade") }   // evita spam quando a IA compra
        recompute()
        if i == RogueUpgrade.hp.rawValue { hp += maxHP - before; model.rogueHP = hp } // HP+ cura o delta
    }

    private func updateRangeRing() {
        let r = rangePts
        rangeRing.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
    }
    private func updateHPBar() {
        let w: CGFloat = 70, h: CGFloat = 7
        let frac = maxHP > 0 ? CGFloat(max(0, hp) / maxHP) : 0
        hpBar.removeAllChildren()
        let bg = SKShapeNode(rect: CGRect(x: -w/2, y: 0, width: w, height: h), cornerRadius: 3)
        bg.fillColor = SKColor(white: 0, alpha: 0.55); bg.strokeColor = .clear
        let fg = SKShapeNode(rect: CGRect(x: -w/2, y: 0, width: max(1, w * frac), height: h), cornerRadius: 3)
        fg.fillColor = frac > 0.35 ? SKColor(red: 0.35, green: 0.85, blue: 0.4, alpha: 1)
                                   : SKColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1)
        fg.strokeColor = .clear
        hpBar.addChild(bg); hpBar.addChild(fg)
    }

    // MARK: loop

    private var lastTime: TimeInterval = 0
    override func update(_ t: TimeInterval) {
        let raw = lastTime == 0 ? 0 : t - lastTime
        lastTime = t
        guard model.rogueStarted, !model.gameOver, !model.paused else { return }
        let dt = min(raw, 0.05) * Double(max(1, model.speed))
        step(dt)
    }

    private func step(_ dt: Double) {
        clock += dt
        // dificuldade por onda (a cada waveInterval).
        if clock >= Double(model.wave + 1) * waveInterval {
            Progression.reload()                            // hot-reload em dev
            rogueCfg = Progression.rogueConfig(seed: runSeed)
            model.wave += 1
            toSpawn += 2 + model.wave / 2           // menos inimigos por onda (menos pileup)
            spawnInterval = max(0.35, 1.1 - Double(model.wave) * 0.025)
        }
        // spawns
        spawnClock -= dt
        if toSpawn > 0 && spawnClock <= 0 { spawnFoe(); toSpawn -= 1; spawnClock = spawnInterval }

        // regen
        if hp < maxHP { hp = min(maxHP, hp + regen * dt) }

        moveAndTouch(dt)
        tickStatus(dt)
        fire(dt)

        if model.autoPlay {
            aiClock -= dt
            if aiClock <= 0 { aiClock = 0.3; autoStep() }
        }

        model.rogueHP = hp
        updateHPBar()
        if hp <= 0 { gameOver() }
    }

    private func spawnFoe() {
        let ang = CGFloat.random(in: 0..<(2 * .pi))
        // spawna logo fora da área visível atual (que cresce com o zoom out).
        let R = hypot(size.width, size.height) * 0.5 * camScale + 24
        let p = CGPoint(x: center.x + cos(ang) * R, y: center.y + sin(ang) * R)
        let dir = CGVector(dx: center.x - p.x, dy: center.y - p.y)
        let len = max(1, hypot(dir.dx, dir.dy))
        let speed: CGFloat = 20 + CGFloat(model.wave) * 0.4
        let vel = CGVector(dx: dir.dx / len * speed, dy: dir.dy / len * speed)
        let hpv = Progression.enemyHP(wave: model.wave, rogueCfg)   // item 1 (r±variância por seed)
        let elem = Element.allCases.randomElement()!
        let rgb = elem.rgb
        let node = SKShapeNode(circleOfRadius: 10)
        node.fillColor = SKColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        node.strokeColor = .black; node.lineWidth = 1
        node.position = p
        foeLayer.addChild(node)
        let bounty = Int(Progression.goldPerKill(wave: model.wave, rogueCfg))     // item 3
        let touch = Progression.enemyDamage(wave: model.wave, rogueCfg)           // item 2 (contato)
        foes.append(Foe(node: node, hp: hpv, pos: p, vel: vel, element: elem, bounty: bounty, touchDPS: touch))
    }

    private func moveAndTouch(_ dt: Double) {
        for f in foes where !f.dead {
            let slow = f.slowUntil > clock ? f.slowFactor : 1.0
            let d = hypot(f.pos.x - center.x, f.pos.y - center.y)
            if d > contactRadius + 8 {
                f.pos.x += f.vel.dx * CGFloat(dt) * CGFloat(slow)
                f.pos.y += f.vel.dy * CGFloat(dt) * CGFloat(slow)
            } else {
                hp -= f.touchDPS * dt          // encostou → dano contínuo na torre
            }
            f.node.position = f.pos
        }
    }

    private func tickStatus(_ dt: Double) {
        for f in foes where !f.dead {
            if f.burnUntil > clock { f.hp -= f.burnDps * dt }
            if f.poisonUntil > clock { f.hp -= f.poisonDps * dt }
            // tint por status dominante
            if f.burnUntil > clock || f.poisonUntil > clock { f.node.alpha = 0.85 }
            if f.hp <= 0 { kill(f) }
        }
        foes.removeAll { $0.dead }
    }

    private func fire(_ dt: Double) {
        cooldown -= dt
        var guardLoops = 0
        while cooldown <= 0 && guardLoops < 12 {
            guardLoops += 1
            cooldown += cadence
            guard let primary = nearestFoe() else { cooldown = cadence; break }
            Audio.shared.sfx("shoot")   // throttle interno evita ruído em alta cadência
            var base = damage
            if abilities.contains(.precisao) { base *= 1.15 }
            let crit = Double.random(in: 0...1) < critChance
            let dmg = crit ? base * 2 : base
            if splashPts > 0 {
                // Torre de área: alvo + todos no raio em volta (75% do dano).
                tracer(to: primary.pos, crit: crit)
                hitFoe(primary, dmg: dmg)
                for f in foes where !f.dead && f !== primary {
                    if hypot(f.pos.x - primary.pos.x, f.pos.y - primary.pos.y) <= splashPts {
                        hitFoe(f, dmg: dmg * 0.75)
                    }
                }
                let rgb = spec.element.rgb
                flash(at: primary.pos, color: SKColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1),
                      radius: splashPts)
            } else {
                // Torre multi-alvo: dano cheio nos N inimigos mais próximos ao mesmo tempo.
                for f in nearestFoes(multiShot) {
                    tracer(to: f.pos, crit: crit)
                    hitFoe(f, dmg: dmg)
                }
            }
            foes.removeAll { $0.dead }
        }
    }

    private func dist2(_ f: Foe) -> CGFloat {
        (f.pos.x - center.x) * (f.pos.x - center.x) + (f.pos.y - center.y) * (f.pos.y - center.y)
    }
    private func nearestFoe() -> Foe? {
        let r2 = rangePts * rangePts
        return foes.filter { !$0.dead && dist2($0) <= r2 }.min { dist2($0) < dist2($1) }
    }
    /// Os `n` inimigos vivos mais próximos dentro do alcance (multi-alvo).
    private func nearestFoes(_ n: Int) -> [Foe] {
        let r2 = rangePts * rangePts
        return Array(foes.filter { !$0.dead && dist2($0) <= r2 }
                         .sorted { dist2($0) < dist2($1) }.prefix(n))
    }

    // MARK: — Auto (IA de upgrades)

    private var aiClock = 0.0

    /// Estima (DPS, HP-efetivo) para um vetor de níveis dos 6 upgrades, sem mutar nada.
    /// Usa as MESMAS fórmulas dos stats reais. O produto DPS×EHP é o "poder" total —
    /// subir ofensiva ou defesa aumenta o produto, então maximizar Δpoder÷custo equilibra
    /// naturalmente os dois (quando um está muito atrás, melhorá-lo rende mais).
    private func statsFor(_ L: [Int]) -> (dps: Double, ehp: Double) {
        let dmg = spec.baseDamage * rarityMult * (1 + 0.30 * Double(L[0]))
        let prec = abilities.contains(.precisao) ? 1.15 : 1.0
        let cadAb = abilities.contains(.cadencia) ? TowerAbility.Tuning.cadenciaMult : 1.0
        let cad = spec.cooldown * pow(0.92, Double(L[1])) * cadAb
        let crit = min(0.75, Double(L[5]) * 0.06)
        let mHP = baseMaxHP * (1 + 0.25 * Double(L[2]))
        let rPct = baseRegenPct + regenPctPerLvl * Double(L[3])
        let abR = abilities.contains(.alcance) ? Double(TowerAbility.Tuning.alcanceBonus) : 0
        let rng = Double(baseRangePts) + Double(spec.range) * 22 + Double(L[4]) * 22 + abR * 22
        let targets: Double
        if spec.splash > 0 {
            targets = 1 + (30 + Double(spec.splash) * 17 + Double(L[4]) * 3) / 55   // cobertura aprox.
        } else {
            var n = 1.0
            if spec.role == .blaster { n += 2 }
            if abilities.contains(.perfuracao) { n += 2 }
            targets = n
        }
        let rangeFactor = 0.7 + 0.3 * (rng / 200.0)      // alcance ajuda a acertar mais/antes
        let dps = dmg * prec * (1 + crit) / max(0.05, cad) * targets * rangeFactor
        let ehp = mHP * (1 + rPct * 30)                  // janela de ~30s de regen
        return (dps, ehp)
    }

    /// Compra repetidamente o upgrade com maior ganho de poder por gold, enquanto der.
    private func autoStep() {
        var iters = 0
        while iters < 24 {
            iters += 1
            let cur = statsFor(lvl); let curP = cur.dps * cur.ehp
            var bestI = -1; var bestVal = 0.0
            for i in 0..<6 {
                let cost = model.rogueCost[i]
                guard cost > 0, model.gold >= cost else { continue }
                var L = lvl; L[i] += 1
                let s = statsFor(L)
                let gain = (s.dps * s.ehp - curP) / Double(cost)
                if gain > bestVal { bestVal = gain; bestI = i }
            }
            if bestI < 0 { break }
            buyUpgrade(bestI)
        }
    }

    /// Aplica dano + status do spec, com multiplicadores de marcado/exposto e combos.
    private func hitFoe(_ f: Foe, dmg: Double) {
        var d = dmg
        if f.markedUntil > clock { d *= Status.T.markedMult }
        if f.exposedUntil > clock { d *= Status.T.exposedMult }
        f.hp -= d
        applyStatus(spec.applies, on: f)
        if f.hp <= 0 { kill(f) }
    }

    private func applyStatus(_ s: Status?, on f: Foe) {
        guard let s = s else { return }
        switch s {
        case .burn:
            if f.wetUntil > clock { f.wetUntil = 0; return }   // molhado ⊘ burn
            f.burnUntil = clock + Status.T.burnDur; f.burnDps = damage * Status.T.burnFrac
            if f.poisonUntil > clock { explode(f) }            // burn + veneno = explosão
        case .poison:
            f.poisonUntil = clock + Status.T.poisonDur; f.poisonDps += damage * Status.T.poisonFrac
            if f.burnUntil > clock { explode(f) }
        case .frozen:
            if f.burnUntil > clock { f.burnUntil = 0; return }  // burn ⊘ congelar
            let strong = f.wetUntil > clock                     // molhado + gelo = congelamento total
            f.slowUntil = clock + (strong ? Status.T.freezeDur : Status.T.slowDur)
            f.slowFactor = strong ? Status.T.freezeFactor : Status.T.slowFactor
        case .rooted:
            f.slowUntil = clock + Status.T.slowDur; f.slowFactor = Status.T.rootedFactor
        case .wet:     f.wetUntil = clock + Status.T.wetDur
        case .marked:  f.markedUntil = clock + Status.T.markedDur
        case .exposed: f.exposedUntil = clock + Status.T.exposedDur
        }
    }

    /// burn + veneno = explosão tóxica em área nos vizinhos.
    private func explode(_ f: Foe) {
        let boom = damage * Status.T.explosionFrac
        let r: CGFloat = 60
        for other in foes where !other.dead && other !== f {
            if hypot(other.pos.x - f.pos.x, other.pos.y - f.pos.y) <= r {
                other.hp -= boom
                if other.hp <= 0 { kill(other) }
            }
        }
        flash(at: f.pos, color: SKColor(red: 0.6, green: 0.9, blue: 0.2, alpha: 1), radius: r)
    }

    private func kill(_ f: Foe) {
        guard !f.dead else { return }
        f.dead = true
        f.node.removeFromParent()
        Audio.shared.sfx("hit")
        model.gold += f.bounty
        model.rogueKills += 1
    }

    // MARK: fx

    private func tracer(to p: CGPoint, crit: Bool) {
        let path = CGMutablePath()
        path.move(to: center); path.addLine(to: p)
        let line = SKShapeNode(path: path)
        line.strokeColor = crit ? SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 0.95)
                                 : SKColor(white: 1, alpha: 0.6)
        line.lineWidth = crit ? 3 : 1.5
        fxLayer.addChild(line)
        line.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
    }

    private func flash(at p: CGPoint, color: SKColor, radius: CGFloat) {
        let c = SKShapeNode(circleOfRadius: radius)
        c.position = p; c.fillColor = color.withAlphaComponent(0.35); c.strokeColor = color
        fxLayer.addChild(c)
        c.run(.sequence([.group([.fadeOut(withDuration: 0.25), .scale(to: 1.3, duration: 0.25)]), .removeFromParent()]))
    }

    private func gameOver() {
        guard !model.gameOver else { return }
        model.gameOver = true
        Audio.shared.sfx("lose")
        let c = model.wave                     // créditos ∝ progresso (ondas sobrevividas)
        model.creditsEarned = c
        _ = meta.addCredits(c)
    }
}
