import Foundation

// Testes da Tarefa 2 — status novos/alterados (Molhado, Veneno, Boss).
// Roda isolado: swiftc HexTD/VsCatalog.swift HexTD/VsStatusState.swift <este como main.swift> ...

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✅ \(msg)") } else { print("  ❌ \(msg)"); failures += 1 }
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "progression_vs.json"
guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let parsed = try? VsCatalog.decode(data) else { print("❌ decode falhou"); exit(1) }
let cfg = parsed.status

print("== statusConfig bate o catálogo ==")
check(cfg.wet.dur == 4.0 && cfg.wet.moveMult == 0.85 && cfg.wet.nextStatusDurMult == 1.5, "Molhado 4s / -15% mov / próximo +50%")
check(cfg.poison.pctHPPerSecPerStack == 0.015 && cfg.poison.cap == 6 && cfg.poison.bossPctHPPerSecPerStack == 0.008, "Veneno 1.5%/stack cap 6 (Boss 0.8%)")
check(cfg.bossChance.default == 0.01 && cfg.bossChance.wet == 0.25, "Boss chance 1% (Molhado 25%)")
check(cfg.burn.pctHPPerSec == 0.02 && cfg.burn.dur == 6.0, "Burn 2%/s 6s")
check(cfg.frozen.slowMult == 0.50 && cfg.frozen.deepSlowMult == 0.30, "Frozen 0.50 (profundo 0.30)")
check(cfg.exposed.dmgMult == 1.25 && cfg.marked.dmgMult == 1.30, "Exposto ×1.25 / Marcado ×1.30")
check(cfg.rooted.moveMult == 0.20, "Enraizado mov 0.20")

print("\n== Molhado: -15% mov + próximo status elemental +50% duração ==")
var st = VsStatusState()
st.apply(.wet, chance: 1, isBoss: false, now: 0, cfg: cfg, roll: 0)
check(abs(st.moveMult(0, cfg) - 0.85) < 1e-9, "Molhado dá -15% mov (moveMult=0.85)")
// Burn aplicado enquanto molhado deve durar 6×1.5 = 9s
st.apply(.burn, chance: 1, isBoss: false, now: 0, cfg: cfg, roll: 0)
check(st.active(.burn, 8.9) && !st.active(.burn, 9.1), "Burn após Molhado dura +50% (≈9s)")
// segundo status elemental NÃO ganha mais (bônus consumido uma vez)
var st2 = VsStatusState()
st2.apply(.wet, chance: 1, isBoss: false, now: 0, cfg: cfg, roll: 0)
st2.apply(.frozen, chance: 1, isBoss: false, now: 0, cfg: cfg, roll: 0)  // consome o bônus
st2.apply(.rooted, chance: 1, isBoss: false, now: 0, cfg: cfg, roll: 0)  // já sem bônus
check(st2.active(.rooted, 1.4) && !st2.active(.rooted, 1.6), "2º status elemental já NÃO ganha +50% (dur normal 1.5s)")

print("\n== Veneno: empilha até cap 6 ==")
var pv = VsStatusState()
for _ in 0..<10 { pv.apply(.poison, chance: 1, isBoss: false, now: 0, cfg: cfg, roll: 0) }
check(pv.poisonStacks == 6, "Veneno empilha e trava no cap 6 (got \(pv.poisonStacks))")
let dpsPlayer = pv.poisonDps(maxHP: 1000, isBoss: false, 0, cfg)
check(abs(dpsPlayer - 6 * 0.015 * 1000) < 1e-6, "DoT veneno = 6×1.5%×1000 = 90/s (got \(dpsPlayer))")
let dpsBoss = pv.poisonDps(maxHP: 1000, isBoss: true, 0, cfg)
check(abs(dpsBoss - 6 * 0.008 * 1000) < 1e-6, "DoT veneno em Boss usa 0.8%/stack = 48/s (got \(dpsBoss))")

print("\n== Boss: chance de status é OVERRIDE (não recalcula da torre) ==")
// chance da torre alta (1.0), mas em Boss usa 0.01 → roll 0.5 NÃO pega (exceto Molhado 0.25).
var bs = VsStatusState()
let gotBurnBoss = bs.apply(.burn, chance: 1.0, isBoss: true, now: 0, cfg: cfg, roll: 0.5)
check(!gotBurnBoss, "Burn em Boss com roll 0.5 NÃO pega (override 1%)")
let gotWetBoss = bs.apply(.wet, chance: 1.0, isBoss: true, now: 0, cfg: cfg, roll: 0.2)
check(gotWetBoss, "Molhado em Boss com roll 0.2 PEGA (override 25%)")
let gotBurnLow = bs.apply(.burn, chance: 1.0, isBoss: true, now: 0, cfg: cfg, roll: 0.005)
check(gotBurnLow, "Burn em Boss com roll 0.005 pega (< 1%)")

print("\n== Expiração zera stacks de veneno ==")
var ex = VsStatusState()
ex.apply(.poison, chance: 1, isBoss: false, now: 0, cfg: cfg, roll: 0)
ex.expire(10)   // veneno dura 4s → expirou
check(ex.poisonStacks == 0, "após expirar, stacks de veneno = 0")

print("\n== Freeze profundo (Permafrost) usa deepSlow/deepDur ==")
var fz = VsStatusState(); fz.setDeepFreeze(true)
fz.apply(.frozen, chance: 1, isBoss: false, now: 0, cfg: cfg, roll: 0)
check(abs(fz.moveMult(0, cfg) - 0.30) < 1e-9, "freeze profundo = mov 0.30")
check(fz.active(.frozen, 2.1) && !fz.active(.frozen, 2.3), "freeze profundo dura 2.2s")

print("\n" + (failures == 0 ? "GATE T2: PASSOU ✅" : "GATE T2: FALHOU ❌ (\(failures) erros)"))
exit(failures == 0 ? 0 : 1)
