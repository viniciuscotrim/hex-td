import Foundation

// Testes da Tarefa 1 — carga de progression_vs.json no data model do Vs.
// Roda isolado:  swiftc HexTD/VsCatalog.swift VsCatalogTests.swift -o /tmp/vt && /tmp/vt [caminho.json]

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✅ \(msg)") } else { print("  ❌ \(msg)"); failures += 1 }
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "progression_vs.json"
guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let parsed = try? VsCatalog.decode(data) else {
    print("❌ não conseguiu ler/decodificar \(path)"); exit(1)
}
let (towers, combos, _, _) = parsed

print("== Carga: 21 torres + 6 combos ==")
check(towers.count == 21, "21 torres carregam (got \(towers.count))")
check(combos.count == 6, "6 combos carregam (got \(combos.count))")

let expectedIds = ["fire_str","fire_bla","fire_sup","watr_str","watr_bla","watr_sup",
                   "ice_str","ice_bla","ice_sup","phys_str","phys_bla","phys_sup",
                   "pois_str","pois_bla","pois_sup","arc_str","arc_bla","arc_sup",
                   "nat_str","nat_bla","nat_sup"]
let loadedIds = Set(towers.map { $0.id })
check(Set(expectedIds) == loadedIds, "os 21 IDs esperados carregam sem faltar/sobrar")

print("\n== Consistência dos números (dpsEff / valuePerCost / cost / cooldown) ==")
for t in towers {
    // dpsEff computado a partir dos campos do JSON = valuePerCost × cost (±0.1).
    let recomputed = t.valuePerCost * Double(t.cost)
    check(abs(recomputed - t.dpsEff) <= 0.1,
          "\(t.id): dpsEff(\(t.dpsEff)) ≈ valuePerCost×cost(\(String(format:"%.2f",recomputed))) ±0.1")
    // cooldown = 1/atkPerSec (±0.01).
    check(abs(t.cooldown - 1.0 / t.atkPerSec) <= 0.01,
          "\(t.id): cooldown(\(t.cooldown)) ≈ 1/atkPerSec(\(String(format:"%.3f",1/t.atkPerSec)))")
}

print("\n== Papéis / alvos / targets polimórficos ==")
let strikers = towers.filter { $0.role == "striker" }
let blasters = towers.filter { $0.role == "blaster" }
let supports = towers.filter { $0.role == "support" }
check(strikers.count == 7 && blasters.count == 7 && supports.count == 7, "7 strikers / 7 blasters / 7 supports")
check(strikers.allSatisfy { $0.targets == .count(1) && $0.targetsEpicPlus == 2 },
      "strikers têm targets single com targetsEpicPlus=2")
// Balista = phys_bla = line ; blasters de dano-em-área = unlimited
check(towers.first { $0.id == "phys_bla" }?.targets == .line, "phys_bla (Balista) = targets 'line'")
check(towers.first { $0.id == "fire_bla" }?.targets == .unlimited, "fire_bla (Dragão) = targets 'unlimited'")

print("\n== Regras por raridade (Épica+ sobe alvos e chance de status) ==")
if let faisca = towers.first(where: { $0.id == "fire_str" }) {
    check(faisca.targetsFor(tier: 2) == .count(1), "Faísca alvos tier 2 (Rara) = 1")
    check(faisca.targetsFor(tier: 3) == .count(2), "Faísca alvos tier 3 (Épica) = 2")
    check(faisca.statusChanceFor(tier: 3) > faisca.statusChance, "Faísca chance de status sobe na Épica+")
    check(abs(faisca.damageFor(tier: 1) - faisca.baseDamage * 1.5) < 1e-9, "damageFor tier 1 = base ×1.5")
    check(abs(faisca.damageFor(tier: 5) - faisca.baseDamage * 7.59375) < 1e-6, "damageFor tier 5 (Mítica) = base ×7.59")
}

print("\n== Combos: 2 mães, lookup por par independente da ordem ==")
check(combos.allSatisfy { $0.mothers.count == 2 }, "todo combo tem exatamente 2 mães")
let comboByPair = Dictionary(uniqueKeysWithValues: combos.map { (Set($0.mothers), $0) })
check(comboByPair[Set(["fire","poison"])]?.id == "C3_explosao_toxica", "combo fire+poison achado")
check(comboByPair[Set(["poison","fire"])]?.id == "C3_explosao_toxica", "combo poison+fire (ordem trocada) achado")
check(comboByPair[Set(["ice","phys"])]?.critVsFrozen == 1.6, "Estilhaçar tem critVsFrozen 1.6 (campo opcional)")
check(comboByPair[Set(["arcane","phys"])]?.bonusIfPrimed == 0.55, "Sentença tem bonusIfPrimed 0.55")

print("\n" + (failures == 0 ? "GATE T1: PASSOU ✅" : "GATE T1: FALHOU ❌ (\(failures) erros)"))
exit(failures == 0 ? 0 : 1)
