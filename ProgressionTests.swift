import Foundation

// Testes unitários das fórmulas de progressão (§critério de aceite). Rodam em isolamento
// na linha de comando:  swiftc HexTD/Progression.swift ProgressionTests.swift -o /tmp/pt && /tmp/pt
// Cobrem waves 1/50/200/1000 + teste de estresse até 5000 (sem overflow/NaN).

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✅ \(msg)") } else { print("  ❌ \(msg)"); failures += 1 }
}
func finite(_ x: Double) -> Bool { x.isFinite && !x.isNaN }

let c = ProgressionConfig()   // defaults = estimativas do brief
let waves = [1, 50, 200, 1000]

print("== (1) HP de inimigo / (2) Dano / (3) Gold por kill ==")
for n in waves {
    let hp = Progression.enemyHP(wave: n, c)
    let dmg = Progression.enemyDamage(wave: n, c)
    let gold = Progression.goldPerKill(wave: n, c)
    print(String(format: "  wave %4d → HP %12.1f | Dano %10.2f | Gold %8.2f | d(n)=%.4f",
                 n, hp, dmg, gold, Progression.damping(n, k: c.kHP, p: c.pHP)))
    check(finite(hp) && hp > 0, "HP(\(n)) finito e positivo")
    check(finite(dmg) && dmg > 0, "Dano(\(n)) finito e positivo")
    check(finite(gold) && gold > 0, "Gold(\(n)) finito e positivo")
}

print("\n== HP cresce e o Dano escala mais devagar que o HP ==")
check(Progression.enemyHP(wave: 1000, c) > Progression.enemyHP(wave: 200, c), "HP(1000) > HP(200) (monotônico)")
let hpRatio = Progression.enemyHP(wave: 200, c) / Progression.enemyHP(wave: 50, c)
let dmgRatio = Progression.enemyDamage(wave: 200, c) / Progression.enemyDamage(wave: 50, c)
check(dmgRatio < hpRatio, "Dano escala mais devagar que HP (ratio 50→200: dano \(String(format:"%.2f",dmgRatio)) < hp \(String(format:"%.2f",hpRatio)))")

print("\n== Amortecimento: crescimento por patamar DESACELERA ==")
let g1 = Progression.enemyHP(wave: 20, c) / Progression.enemyHP(wave: 10, c)
let g2 = Progression.enemyHP(wave: 210, c) / Progression.enemyHP(wave: 200, c)
check(g2 < g1, "crescimento relativo cai em waves altas (\(String(format:"%.3f",g2)) < \(String(format:"%.3f",g1)))")

print("\n== Teste de estresse: waves 1..5000 sem overflow/NaN ==")
var stressOK = true
for n in 1...5000 {
    if !finite(Progression.enemyHP(wave: n, c)) || !finite(Progression.enemyDamage(wave: n, c))
        || !finite(Progression.goldPerKill(wave: n, c)) { stressOK = false; break }
}
check(stressOK, "todas as fórmulas finitas de 1 a 5000")
print(String(format: "  HP(5000) = %.3e (finito=%@)", Progression.enemyHP(wave: 5000, c),
             finite(Progression.enemyHP(wave: 5000, c)) ? "sim" : "NÃO"))

print("\n== (3) Gold é sublinear (n^a, a<1) ==")
let goldRatio = Progression.goldPerKill(wave: 400, c) / Progression.goldPerKill(wave: 100, c)
check(goldRatio < 4.0, "Gold 100→400 cresce menos que linear (×\(String(format:"%.2f",goldRatio)) < ×4)")

print("\n== (4) Stat por tier de raridade = ∏(1+b_i) ==")
for t in 0...5 {
    print(String(format: "  tier %d → ×%.3f", t, Progression.rarityStat(tier: t, c)))
}
check(abs(Progression.rarityStat(tier: 0, c) - 1.0) < 1e-9, "tier 0 = ×1.00 (base)")
let expected1 = 1 + c.statBonuses[0]
check(abs(Progression.rarityStat(tier: 1, c) - expected1) < 1e-9, "tier 1 = 1+b₀ = ×\(String(format:"%.3f",expected1))")
let expected5 = c.statBonuses.reduce(1.0) { $0 * (1 + $1) }
check(abs(Progression.rarityStat(tier: 5, c) - expected5) < 1e-9, "tier 5 = ∏(1+bᵢ) = ×\(String(format:"%.3f",expected5))")
check(Progression.rarityStat(tier: 2, c) > Progression.rarityStat(tier: 1, c), "tiers são crescentes")

print("\n== (5) Upgrade in-run: custo geométrico + efeito linear ==")
for lvl in 1...3 {
    print(String(format: "  lvl %d → custo ×%.3f | efeito ×%.2f", lvl,
                 Progression.upgradeCost(base: 1, lvl: lvl, c), Progression.upgradeEffect(lvl: lvl, c)))
}
check(abs(Progression.upgradeCost(base: 100, lvl: 1, c) - 100) < 1e-9, "custo lvl1 = base")
check(abs(Progression.upgradeCost(base: 100, lvl: 3, c) - 225) < 1e-9, "custo lvl3 = base·1.5² = 225")
check(abs(Progression.upgradeEffect(lvl: 3, c) - 1.75) < 1e-9, "efeito lvl3 = 1.75")

print("\n== (6) Modificador elemental ==")
check(Progression.elementalMult(.advantage, c) == 2.0, "vantagem = ×2.0")
check(Progression.elementalMult(.neutral, c) == 1.0, "neutro = ×1.0")
check(Progression.elementalMult(.disadvantage, c) == 0.5, "desvantagem = ×0.5")

print("\n== (7) Rogue: variância de r por seed dentro de ±rogueVariance ==")
let rA = Progression.rogueGrowth(baseR: c.rHP, seed: 111, c)
let rB = Progression.rogueGrowth(baseR: c.rHP, seed: 222, c)
check(abs(rA - c.rHP) <= c.rogueVariance + 1e-9, "seed 111 dentro de ±\(c.rogueVariance)")
check(abs(rB - c.rHP) <= c.rogueVariance + 1e-9, "seed 222 dentro de ±\(c.rogueVariance)")
check(rA != rB, "seeds diferentes → r diferentes (determinístico)")
check(Progression.rogueGrowth(baseR: c.rHP, seed: 111, c) == rA, "mesma seed → mesmo r (reprodutível)")

print(failures == 0 ? "\n🎉 TODOS OS TESTES PASSARAM" : "\n💥 \(failures) FALHA(S)")
exit(failures == 0 ? 0 : 1)
