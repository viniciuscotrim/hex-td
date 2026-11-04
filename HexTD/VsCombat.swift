import Foundation

/// T4 — Sistema de COMBO. Duas torres ADJACENTES de elementos DIFERENTES que têm entrada em
/// `combos[]` formam um combo: suprimem o tiro individual das mães e disparam UM ataque-combo
/// com os stats PRÓPRIOS do JSON (não herdados por fórmula). As mães NÃO se consomem — seguem
/// ocupando os hexes e sobem estrela via merge. Escala do combo = MENOR estrela das duas mães.
struct VsComboInstance: Equatable {
    let motherA: Int          // id da torre
    let motherB: Int
    let comboId: String
    let scaleTier: Int        // menor estrela (raridade) das duas mães

    func combo() -> VsCombo? { VsCatalog.combos.first { $0.id == comboId } }
    /// Dano do ataque-combo já escalado pela menor estrela (statMult ×1.5/tier).
    var effectiveDamage: Double { (combo()?.damage ?? 0) * VsCatalog.statMult(tier: scaleTier) }
    var cooldown: Double { combo()?.cooldown ?? 1 }
    var splash: Int { combo()?.splash ?? 0 }
}

struct VsTowerLite: Equatable {   // visão mínima de torre pra detecção (id, elemento, hex, estrela)
    let id: Int
    let element: String
    let hex: Hex
    let star: Int
}

enum VsCombat {
    /// Detecta combos entre torres adjacentes (dist hex = 1) de elementos diferentes com combo
    /// no catálogo. Cada torre entra em NO MÁXIMO 1 combo (determinístico: menor id primeiro).
    static func detectCombos(_ towers: [VsTowerLite]) -> [VsComboInstance] {
        let sorted = towers.sorted { $0.id < $1.id }
        var used = Set<Int>()
        var out: [VsComboInstance] = []
        for (i, a) in sorted.enumerated() where !used.contains(a.id) {
            for b in sorted[(i + 1)...] where !used.contains(b.id) {
                guard a.element != b.element,
                      a.hex.distance(to: b.hex) == 1,
                      let c = VsCatalog.combo(a.element, b.element) else { continue }
                out.append(VsComboInstance(motherA: a.id, motherB: b.id,
                                           comboId: c.id, scaleTier: min(a.star, b.star)))
                used.insert(a.id); used.insert(b.id)
                break
            }
        }
        return out
    }

    /// Ids das torres com o tiro individual SUPRIMIDO (participam de algum combo).
    static func suppressed(_ combos: [VsComboInstance]) -> Set<Int> {
        Set(combos.flatMap { [$0.motherA, $0.motherB] })
    }

    /// Reação de BLOQUEIO (anti-combo, §7 do MASTER): NÃO gera ataque, não está em combos[].
    /// Molhado ⊘ Burn (aplicar burn em molhado falha) · Burn ⊘ Congelar (congelar quem queima falha).
    static func isBlocked(applying status: String, whenTargetHas has: Set<String>) -> Bool {
        if status == "burn" && has.contains("wet") { return true }
        if status == "frozen" && has.contains("burn") { return true }
        return false
    }
}
