import Foundation

/// T5 — Spawn/Merge do modo Vs. `star` = raridade (0=Comum … 5=Mítica). Nasce Comum. Merge é
/// a ÚNICA via de subir raridade in-run: funde 2 IGUAIS (mesmo elemento+papel+estrela) → +1
/// estrela. Como o merge é sempre 2→1, chegar em N estrelas exige 2×(N-1), que exige 2×(N-2)…
/// ou seja "3× exige 2×+2×" (uma árvore binária). O dano usa `statMult(star)` (×1.5/tier).
struct VsUnit: Equatable {
    let specId: String
    let element: String
    let role: String
    var star: Int
    var hex: Hex

    /// Chave de merge: só funde quem compartilha as TRÊS (elemento, papel, estrela).
    var mergeKey: String { "\(element)|\(role)|\(star)" }
    var damage: Double { (VsCatalog.spec(specId)?.baseDamage ?? 0) * VsCatalog.statMult(tier: star) }
}

enum VsMerge {
    static let maxStar = 5            // Mítica (6 tiers: Comum..Mítica = 0..5)

    /// Spawn: escolhe a spec e o hex; nasce COMUM (star 0).
    static func spawn(specId: String, at hex: Hex) -> VsUnit? {
        guard let s = VsCatalog.spec(specId) else { return nil }
        return VsUnit(specId: s.id, element: s.element, role: s.role, star: 0, hex: hex)
    }

    /// Podem fundir? Só IGUAIS (elemento+papel+estrela) e abaixo do teto.
    static func canMerge(_ a: VsUnit, _ b: VsUnit) -> Bool {
        a.mergeKey == b.mergeKey && a.star < maxStar
    }

    /// Funde `b` em `a` (fica no hex de `a`): sobe 1 estrela. Consome as duas → devolve a nova.
    static func merge(_ a: VsUnit, _ b: VsUnit) -> VsUnit? {
        guard canMerge(a, b) else { return nil }
        var m = a; m.star = min(a.star + 1, maxStar); return m
    }

    /// Dado um conjunto de unidades no MESMO hex-alvo (ou par selecionado), retorna a fusão se
    /// houver EXATAMENTE 2 iguais. (helper pro loop de merge da cena.)
    static func tryMergePair(_ units: [VsUnit]) -> VsUnit? {
        guard units.count == 2, let m = merge(units[0], units[1]) else { return nil }
        return m
    }
}
