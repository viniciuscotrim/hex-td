import Foundation

// Testes da Tarefa 5 — spawn/merge do modo Vs.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✅ \(msg)") } else { print("  ❌ \(msg)"); failures += 1 }
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "progression_vs.json"
guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let parsed = try? VsCatalog.decode(data) else { print("❌ decode falhou"); exit(1) }
VsCatalog.install(towers: parsed.towers, combos: parsed.combos, status: parsed.status, prop: parsed.prop)

let h = Hex(q: 0, r: 0)

print("== Spawn: nasce Comum (star 0) ==")
guard let u0 = VsMerge.spawn(specId: "fire_str", at: h) else { print("❌ spawn falhou"); exit(1) }
check(u0.star == 0 && u0.element == "fire" && u0.role == "striker", "Faísca spawna Comum (star 0)")
check(VsMerge.spawn(specId: "id_inexistente", at: h) == nil, "spawn de id inválido = nil")

print("\n== Merge só de IGUAIS (elemento+papel+estrela) ==")
let fireStrA = VsMerge.spawn(specId: "fire_str", at: h)!
let fireStrB = VsMerge.spawn(specId: "fire_str", at: h)!
let waterStr = VsMerge.spawn(specId: "watr_str", at: h)!     // elemento diferente
let fireBla  = VsMerge.spawn(specId: "fire_bla", at: h)!     // papel diferente
check(VsMerge.canMerge(fireStrA, fireStrB), "2 Faísca (mesmo elem+papel+estrela) fundem")
check(!VsMerge.canMerge(fireStrA, waterStr), "Faísca + Jato (elemento diferente) NÃO fundem")
check(!VsMerge.canMerge(fireStrA, fireBla), "Faísca + Dragão (papel diferente) NÃO fundem")

print("\n== 2× → sobe estrela ==")
guard let s1 = VsMerge.merge(fireStrA, fireStrB) else { print("❌ merge falhou"); exit(1) }
check(s1.star == 1, "2× star 0 → star 1")
check(abs(s1.damage - (VsCatalog.spec("fire_str")!.baseDamage * 1.5)) < 1e-9, "dano da star 1 usa statMult(1)=×1.5")

print("\n== 3× exige 2×+2× (não funde estrela diferente) ==")
let star1a = VsMerge.merge(fireStrA, fireStrB)!          // star 1
let commonC = VsMerge.spawn(specId: "fire_str", at: h)!  // star 0
check(!VsMerge.canMerge(star1a, commonC), "star 1 + star 0 NÃO fundem (estrelas diferentes)")
let star1b = VsMerge.merge(VsMerge.spawn(specId: "fire_str", at: h)!, VsMerge.spawn(specId: "fire_str", at: h)!)!
guard let star2 = VsMerge.merge(star1a, star1b) else { print("❌ merge star2 falhou"); exit(1) }
check(star2.star == 2, "2× star 1 → star 2 (ou seja, star 2 custou 4 Comuns = 2×+2×)")

print("\n== Teto de estrelas (Mítica = 5) ==")
var top = VsMerge.spawn(specId: "fire_str", at: h)!; top.star = 5
let other5 = { var u = VsMerge.spawn(specId: "fire_str", at: h)!; u.star = 5; return u }()
check(!VsMerge.canMerge(top, other5), "duas Míticas (star 5) NÃO fundem (no teto)")
var four = VsMerge.spawn(specId: "fire_str", at: h)!; four.star = 4
let other4 = { var u = VsMerge.spawn(specId: "fire_str", at: h)!; u.star = 4; return u }()
check(VsMerge.merge(four, other4)?.star == 5, "2× star 4 → star 5 (Mítica)")

print("\n== Raridade sobe SÓ via merge (statMult acompanha a estrela) ==")
check(abs(u0.damage - VsCatalog.spec("fire_str")!.baseDamage * 1.0) < 1e-9, "star 0 = dano base ×1.0")
check(abs(star2.damage - VsCatalog.spec("fire_str")!.baseDamage * 2.25) < 1e-9, "star 2 = base ×2.25 (statMult tier 2)")

print("\n== tryMergePair helper ==")
check(VsMerge.tryMergePair([fireStrA, fireStrB])?.star == 1, "par igual → funde")
check(VsMerge.tryMergePair([fireStrA, waterStr]) == nil, "par diferente → nil")
check(VsMerge.tryMergePair([fireStrA]) == nil, "1 unidade só → nil")

print("\n" + (failures == 0 ? "GATE T5 (merge/spawn): PASSOU ✅" : "GATE T5: FALHOU ❌ (\(failures) erros)"))
exit(failures == 0 ? 0 : 1)
