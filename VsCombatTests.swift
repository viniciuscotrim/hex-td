import Foundation

// Testes da Tarefa 4 — sistema de combo (adjacência, ataque único com stats do JSON).

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✅ \(msg)") } else { print("  ❌ \(msg)"); failures += 1 }
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "progression_vs.json"
guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let parsed = try? VsCatalog.decode(data) else { print("❌ decode falhou"); exit(1) }
VsCatalog.install(towers: parsed.towers, combos: parsed.combos, status: parsed.status, prop: parsed.prop)

// hexes adjacentes (dist 1) e não-adjacentes (dist 2).
let h0 = Hex(q: 0, r: 0), hAdj = Hex(q: 1, r: 0), hFar = Hex(q: 2, r: 0)

print("== Detecção de adjacência: par fogo+veneno (combo C3) ==")
let firePoison = [VsTowerLite(id: 1, element: "fire", hex: h0, star: 3),
                  VsTowerLite(id: 2, element: "poison", hex: hAdj, star: 0)]   // Comum (star 0)
let combos = VsCombat.detectCombos(firePoison)
check(combos.count == 1, "1 combo detectado no par adjacente")
check(combos.first?.comboId == "C3_explosao_toxica", "combo é Explosão Tóxica (fire+poison)")

print("\n== Stats PRÓPRIOS do JSON (não herdados) + escala = menor estrela ==")
if let ci = combos.first, let c = ci.combo() {
    check(c.damage == 20 && c.cooldown == 1.4 && c.splash == 1, "stats vêm do combos[] do JSON (dmg 20 / cd 1.4 / splash 1)")
    check(ci.scaleTier == 0, "escala = menor estrela das mães (min(3,0)=0, Comum)")
    check(abs(ci.effectiveDamage - 20 * 1.0) < 1e-9, "dano efetivo = 20 × statMult(0)=×1.0 = 20")
    // e uma mãe Épica (tier 3) → statMult(3)=×3.375
    check(abs(VsComboInstance(motherA: 0, motherB: 0, comboId: "C3_explosao_toxica", scaleTier: 3).effectiveDamage - 20 * 3.375) < 1e-6,
          "escala tier 3 (Épica) = 20 × 3.375 = 67.5")
}

print("\n== Suprime tiro individual das duas mães ==")
check(VsCombat.suppressed(combos) == Set([1, 2]), "as 2 mães têm tiro individual suprimido")

print("\n== Sem adjacência → sem combo (volta ao tiro individual) ==")
let farPair = [VsTowerLite(id: 1, element: "fire", hex: h0, star: 2),
               VsTowerLite(id: 2, element: "poison", hex: hFar, star: 2)]   // dist 2
check(VsCombat.detectCombos(farPair).isEmpty, "par não-adjacente NÃO forma combo")
check(VsCombat.suppressed(VsCombat.detectCombos(farPair)).isEmpty, "ninguém suprimido → tiro individual volta")

print("\n== Mesmo elemento adjacente → NÃO é combo (é merge) ==")
let same = [VsTowerLite(id: 1, element: "fire", hex: h0, star: 1),
            VsTowerLite(id: 2, element: "fire", hex: hAdj, star: 1)]
check(VsCombat.detectCombos(same).isEmpty, "mesmo elemento não combina (reservado a merge)")

print("\n== Par diferente SEM entrada em combos[] → sem combo ==")
let noCombo = [VsTowerLite(id: 1, element: "fire", hex: h0, star: 1),
               VsTowerLite(id: 2, element: "arcane", hex: hAdj, star: 1)]   // fire+arcane não existe
check(VsCombat.detectCombos(noCombo).isEmpty, "fire+arcane (sem combo no JSON) não dispara")

print("\n== Merge de uma mãe durante combo NÃO crasha (recomputa) ==")
let afterMerge = [VsTowerLite(id: 1, element: "fire", hex: h0, star: 2)]   // a mãe 2 sumiu (fundiu)
check(VsCombat.detectCombos(afterMerge).isEmpty, "com a mãe removida, adjacência quebra sem crash")

print("\n== Cada torre entra em no máximo 1 combo ==")
// 3 torres em linha: fire(0,0) - poison(1,0) - ice(2,0); fire+poison e poison+ice? poison+ice sem combo.
// Trio que forma 2 combos possíveis com a do meio: garante que a do meio entra em 1 só.
let trio = [VsTowerLite(id: 1, element: "water", hex: h0, star: 1),
            VsTowerLite(id: 2, element: "ice",  hex: hAdj, star: 1),      // water+ice = Permafrost
            VsTowerLite(id: 3, element: "phys", hex: Hex(q: 2, r: 0), star: 1)] // ice+phys = Estilhaçar
let trioCombos = VsCombat.detectCombos(trio)
let usedIds = trioCombos.flatMap { [$0.motherA, $0.motherB] }
check(Set(usedIds).count == usedIds.count, "nenhuma torre participa de 2 combos (id do meio usado 1×)")

print("\n== Anti-combos (bloqueio) NÃO geram ataque ==")
check(VsCombat.isBlocked(applying: "burn", whenTargetHas: ["wet"]), "Molhado ⊘ Burn (burn em molhado bloqueado)")
check(VsCombat.isBlocked(applying: "frozen", whenTargetHas: ["burn"]), "Burn ⊘ Congelar (freeze em quem queima bloqueado)")
check(!VsCombat.isBlocked(applying: "poison", whenTargetHas: ["wet"]), "veneno em molhado NÃO é bloqueado")
check(!VsCombat.isBlocked(applying: "burn", whenTargetHas: ["frozen"]), "burn em congelado NÃO é bloqueado por essa regra")

print("\n" + (failures == 0 ? "GATE T4: PASSOU ✅" : "GATE T4: FALHOU ❌ (\(failures) erros)"))
exit(failures == 0 ? 0 : 1)
