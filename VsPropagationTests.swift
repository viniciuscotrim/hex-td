import Foundation

// Testes da Tarefa 3 — propagação por papel (striker no espaço / blaster por salto / Balista linha).

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✅ \(msg)") } else { print("  ❌ \(msg)"); failures += 1 }
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "progression_vs.json"
guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let parsed = try? VsCatalog.decode(data) else { print("❌ decode falhou"); exit(1) }
let cfg = parsed.prop

print("== propagation config bate o catálogo ==")
check(cfg.striker.count == 7, "7 efeitos de chão de striker (um por elemento)")
check(cfg.blaster.maxTargets == 2 && cfg.blaster.rangeTiles == 1, "blaster: até 2 alvos a ≤1 tile")
check(cfg.balista.applies == "exposed" && cfg.balista.primedBonus == 0.40, "Balista: Exposto, +40% se já exposto")

print("\n== STRIKER: deixa efeito no hex (propaga no ESPAÇO) ==")
if let g = VsPropagation.strikerGround(element: "fire", at: Hex(q: 0, r: 0), now: 0, cfg: cfg) {
    check(g.kind == "poca_lava" && g.status == .burn && g.until == 4.0, "Fogo → poça de lava (burn) por 4s")
}
if let g = VsPropagation.strikerGround(element: "ice", at: Hex(q: 0, r: 0), now: 0, cfg: cfg) {
    check(g.kind == "piso_gelo" && g.status == .frozen && g.until == 3.0, "Gelo → piso de gelo (frozen) por 3s")
}
if let g = VsPropagation.strikerGround(element: "phys", at: Hex(q: 0, r: 0), now: 0, cfg: cfg) {
    check(g.kind == "marca_sangue" && g.status == .exposed && g.chains, "Físico → marca de sangue (exposto) que encadeia")
}
// inimigo SOBRE o efeito recebe status; fora do hex não; efeito expirado não.
let eff = [VsPropagation.strikerGround(element: "poison", at: Hex(q: 1, r: 1), now: 0, cfg: cfg)!]
let hitsNow = VsPropagation.groundHits(eff, enemies: [(1, Hex(q: 1, r: 1)), (2, Hex(q: 2, r: 2))], now: 1.0)
check(hitsNow.count == 1 && hitsNow[0].id == 1 && hitsNow[0].status == .poison, "inimigo no hex do efeito recebe veneno; fora não")
let hitsExpired = VsPropagation.groundHits(eff, enemies: [(1, Hex(q: 1, r: 1))], now: 5.0)   // efeito durou 3s
check(hitsExpired.isEmpty, "efeito expirado não aplica")

print("\n== BLASTER: propaga por SALTO ao morrer (≤2 alvos, ≤1 tile) ==")
let dead = Hex(q: 0, r: 0)
let cands = [(id: 1, hex: Hex(q: 1, r: 0)),     // dist 1
             (id: 2, hex: Hex(q: 0, r: 1)),     // dist 1
             (id: 3, hex: Hex(q: 2, r: 0)),     // dist 2 → fora
             (id: 99, hex: dead)]               // o próprio morto
let spread = VsPropagation.blasterSpread(fromHex: dead, deadId: 99, candidates: cands, cfg: cfg)
check(spread.count == 2 && Set(spread) == Set([1, 2]), "salta pros 2 vizinhos a 1 tile (exclui o dist-2 e o morto)")

print("\n== BALISTA: perfura em LINHA (NÃO radial) + Exposto/primed ==")
// linha na direção 0 = (1,0) a partir de (0,0): (1,0),(2,0),(3,0)...
let onLine1 = Hex(q: 1, r: 0), onLine2 = Hex(q: 3, r: 0)
let offLineAdjacent = Hex(q: 0, r: 1)           // vizinho (dist 1) mas FORA da reta → prova não-radial
let enemies = [(id: 10, hex: onLine1, exposed: false),
               (id: 11, hex: onLine2, exposed: true),
               (id: 12, hex: offLineAdjacent, exposed: false)]
let line = VsPropagation.balistaLine(origin: Hex(q: 0, r: 0), dir: 0, enemies: enemies)
let hitIds = Set(line.map { $0.id })
check(hitIds == Set([10, 11]), "perfura só quem está na reta (10,11); o vizinho fora da linha (12) NÃO é atingido")
check(line.first { $0.id == 11 }?.primed == true, "alvo já Exposto na linha vem 'primed' (ganha +40%)")
check(line.first { $0.id == 10 }?.primed == false, "alvo não-exposto na linha vem sem primed")
check(!hitIds.contains(12), "Balista NÃO é AoE radial (vizinho adjacente fora da reta ileso)")

print("\n" + (failures == 0 ? "GATE T3: PASSOU ✅" : "GATE T3: FALHOU ❌ (\(failures) erros)"))
exit(failures == 0 ? 0 : 1)
