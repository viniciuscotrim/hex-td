import Foundation

/// Status do Vs (redesenho). Reusa os 7 status como enum próprio (Foundation-only, testável),
/// SEM tocar no `Status.swift`/motor comum. Números vêm do `statusConfig` do JSON.
enum VsStatusKind: String, CaseIterable {
    case burn, wet, frozen, exposed, poison, marked, rooted
    var isElemental: Bool { self != .wet }   // "próximo status elemental" = qualquer um menos o Molhado
}

/// Estado de status de UM inimigo no Vs. Contém a lógica nova:
/// - Molhado: 4s, -15% mov E faz o PRÓXIMO status elemental durar +50% (consumido uma vez).
/// - Veneno: empilha 1.5% HP/s por stack (cap 6), 4s; Boss 0.8%/stack.
/// - Boss: chance de status é OVERRIDE (1% padrão, 25% Molhado) — não recalcula da torre.
struct VsStatusState {
    private var until: [VsStatusKind: Double] = [:]
    private(set) var poisonStacks = 0
    private(set) var deepFreeze = false     // Permafrost (água+gelo) → freeze profundo
    private var wetPrimed = false           // Molhado ativo "armando" o próximo status elemental

    func active(_ s: VsStatusKind, _ now: Double) -> Bool { (until[s] ?? 0) > now }

    /// Tenta aplicar `s`. `roll` ∈ [0,1) é o dado (injetado → determinístico no teste). Em Boss,
    /// a chance é o OVERRIDE do config (não a `chance` da torre). Retorna se pegou.
    /// Combos de bloqueio (Molhado⊘Burn, Burn⊘Congelar) NÃO são resolvidos aqui — ficam no motor
    /// como anti-combo. Aqui só a mecânica de status + a extensão do Molhado.
    @discardableResult
    mutating func apply(_ s: VsStatusKind, chance: Double, isBoss: Bool, now: Double,
                        cfg: VsStatusConfig, roll: Double = 0) -> Bool {
        let eff = isBoss ? (s == .wet ? cfg.bossChance.wet : cfg.bossChance.default) : chance
        guard roll < eff else { return false }
        // duração base do status + bônus do Molhado (próximo elemental +50%, consumido).
        var durMult = 1.0
        if s.isElemental && wetPrimed && active(.wet, now) { durMult = cfg.wet.nextStatusDurMult; wetPrimed = false }
        switch s {
        case .wet:
            until[.wet] = now + cfg.wet.dur; wetPrimed = true
        case .burn:
            until[.burn] = now + cfg.burn.dur * durMult
        case .frozen:
            until[.frozen] = now + (deepFreeze ? cfg.frozen.deepDur : cfg.frozen.dur) * durMult
        case .poison:
            poisonStacks = min(poisonStacks + 1, cfg.poison.cap)
            until[.poison] = now + cfg.poison.dur * durMult
        case .exposed:
            until[.exposed] = now + cfg.exposed.dur * durMult
        case .marked:
            until[.marked] = now + cfg.marked.dur * durMult
        case .rooted:
            until[.rooted] = now + cfg.rooted.dur * durMult
        }
        return true
    }

    /// Marca freeze profundo (combo Permafrost). O próximo `apply(.frozen)` usa deepDur/deepSlow.
    mutating func setDeepFreeze(_ on: Bool) { deepFreeze = on }

    /// Multiplicador de movimento combinado: Molhado (×0.85) × o slow mais forte (freeze/root).
    func moveMult(_ now: Double, _ cfg: VsStatusConfig) -> Double {
        var slow = 1.0
        if active(.frozen, now) { slow = min(slow, deepFreeze ? cfg.frozen.deepSlowMult : cfg.frozen.slowMult) }
        if active(.rooted, now) { slow = min(slow, cfg.rooted.moveMult) }
        let wetM = active(.wet, now) ? cfg.wet.moveMult : 1.0
        return wetM * slow
    }

    /// DoT do veneno (HP/s) = stacks × %HP por stack (Boss menor).
    func poisonDps(maxHP: Double, isBoss: Bool, _ now: Double, _ cfg: VsStatusConfig) -> Double {
        guard active(.poison, now) else { return 0 }
        let pct = isBoss ? cfg.poison.bossPctHPPerSecPerStack : cfg.poison.pctHPPerSecPerStack
        return Double(poisonStacks) * pct * maxHP
    }

    /// DoT do burn (HP/s) — Boss menor.
    func burnDps(maxHP: Double, isBoss: Bool, _ now: Double, _ cfg: VsStatusConfig) -> Double {
        guard active(.burn, now) else { return 0 }
        return (isBoss ? cfg.burn.bossPctHPPerSec : cfg.burn.pctHPPerSec) * maxHP
    }

    /// Multiplicador de dano recebido: Exposto × Marcado (ambos empilham).
    func dmgTakenMult(_ now: Double, _ cfg: VsStatusConfig) -> Double {
        var m = 1.0
        if active(.exposed, now) { m *= cfg.exposed.dmgMult }
        if active(.marked, now)  { m *= cfg.marked.dmgMult }
        return m
    }

    /// Limpa status expirados; zera stacks de veneno quando o veneno acaba.
    mutating func expire(_ now: Double) {
        for (k, t) in until where t <= now { until[k] = nil }
        if !active(.poison, now) { poisonStacks = 0 }
        if !active(.wet, now) { wetPrimed = false }
    }

    func activeIcons(_ now: Double) -> [VsStatusKind] { VsStatusKind.allCases.filter { active($0, now) } }
}
