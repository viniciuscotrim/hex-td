import Foundation

/// Papel da torre no combo-sistema (§design): striker = rápida/single, blaster =
/// lenta/área, support = pouca/nenhuma dano, buffa aliadas / aplica campo de status.
enum TowerRole: Int {
    case striker, blaster, support
    var nome: String {
        switch self {
        case .striker: return "Rápida"
        case .blaster: return "Área"
        case .support: return "Suporte"
        }
    }
}

/// Definição data-driven de uma torre (substitui o antigo `enum TowerKind`). O meta
/// indexa por `id` (0–20). Cada torre aplica o status do seu elemento; a matriz de
/// combos (Fase 3) faz os status reagirem. As 21 = 7 elementos × [striker, blaster,
/// support], 1 suporte por elemento.
struct TowerSpec {
    let id: Int
    let element: Element
    let role: TowerRole
    let nome: String
    let cost: Int
    let baseDamage: Double
    let cooldown: Double        // segundos entre tiros
    let range: Int              // passos de hex
    let splash: Int             // raio de área (0 = single)
    let applies: Status?        // status aplicado no acerto
    let bounty: Int             // gold por kill (economia)
    let auraDamageBonus: Double // suporte: +dano às torres vizinhas (0 = nenhum)
    let abilities: [TowerAbility]

    var icon: String { element.icon }              // disc usa o emoji do elemento
    var fullName: String { "\(nome)" }
    var subtitle: String { "\(element.nome) · \(role.nome)" }
}

enum TowerCatalog {
    static var count: Int { all.count }
    static func spec(_ id: Int) -> TowerSpec { all[id] }
    /// Ids das torres de um elemento (na ordem striker, blaster, support).
    static func ids(of e: Element) -> [Int] { all.filter { $0.element == e }.map(\.id) }

    // 21 torres. Ordem: por elemento (Element.allCases), cada um striker→blaster→support.
    static let all: [TowerSpec] = build()

    private static func build() -> [TowerSpec] {
        var out: [TowerSpec] = []
        var id = 0
        func add(_ e: Element, _ role: TowerRole, _ nome: String, cost: Int, dmg: Double,
                 cd: Double, range: Int, splash: Int = 0, applies: Status?, bounty: Int = 0,
                 aura: Double = 0, _ ab: [TowerAbility]) {
            out.append(TowerSpec(id: id, element: e, role: role, nome: nome, cost: cost,
                                 baseDamage: dmg, cooldown: cd, range: range, splash: splash,
                                 applies: applies, bounty: bounty, auraDamageBonus: aura, abilities: ab))
            id += 1
        }

        // Balanço: STRIKER (single) = cadência rápida ~0.5 + alto DPS single-target →
        // forte contra inimigos isolados/tanky (viável no Rogue). BLASTER (área) =
        // cadência lenta ~1.4 + dano por tiro menor, mas atinge vários. Diferença de
        // cadência bem perceptível (~2.8×). Balista deixou de dominar (dano reduzido).

        // 🔥 FOGO — burn
        add(.fogo, .striker, "Faísca",   cost: 35, dmg: 11, cd: 0.5, range: 2, applies: .burn, [.precisao, .cadencia])
        add(.fogo, .blaster, "Bomba",    cost: 55, dmg: 16, cd: 1.4, range: 3, splash: 1, applies: .burn, [.chamasVivas, .queimadura])
        add(.fogo, .support, "Braseiro", cost: 45, dmg: 3,  cd: 1.0, range: 2, applies: .burn, aura: 0.12, [.ressonancia, .potencia])

        // 💧 ÁGUA — wet
        add(.agua, .striker, "Jato",     cost: 32, dmg: 10, cd: 0.5, range: 2, applies: .wet, [.precisao, .perfuracao])
        add(.agua, .blaster, "Onda",     cost: 50, dmg: 13, cd: 1.4, range: 2, splash: 1, applies: .wet, [.chamasVivas, .potencia])
        add(.agua, .support, "Corrente", cost: 42, dmg: 2,  cd: 1.0, range: 2, applies: .wet, aura: 0.12, [.ressonancia, .alcance])

        // ❄️ GELO — frozen
        add(.gelo, .striker, "Estilhaço", cost: 34, dmg: 10, cd: 0.55, range: 2, applies: .frozen, [.precisao, .profundo])
        add(.gelo, .blaster, "Nevasca",   cost: 52, dmg: 12, cd: 1.5, range: 3, splash: 1, applies: .frozen, [.chamasVivas, .profundo])
        add(.gelo, .support, "Aura Gélida", cost: 46, dmg: 2, cd: 1.0, range: 3, applies: .frozen, aura: 0.10, [.ressonancia, .estilhacos])

        // 🗡️ FÍSICO — exposed (dano bruto)
        add(.fisico, .striker, "Lança",    cost: 30, dmg: 15, cd: 0.5, range: 2, applies: .exposed, [.precisao, .estilhacos])
        add(.fisico, .blaster, "Balista",  cost: 58, dmg: 13, cd: 1.5, range: 4, applies: .exposed, [.alcance, .execucao])
        add(.fisico, .support, "Estandarte", cost: 50, dmg: 2, cd: 1.0, range: 2, applies: nil, aura: 0.25, [.ressonancia, .cobranca])

        // ☠️ VENENO — poison
        add(.veneno, .striker, "Dardo",  cost: 33, dmg: 8, cd: 0.5, range: 2, applies: .poison, [.precisao, .contagio])
        add(.veneno, .blaster, "Nuvem",  cost: 50, dmg: 11, cd: 1.4, range: 2, splash: 1, applies: .poison, [.chamasVivas, .detonador])
        add(.veneno, .support, "Miasma", cost: 44, dmg: 2, cd: 1.0, range: 2, applies: .poison, aura: 0.12, [.ressonancia, .potencia])

        // 🔮 ARCANA — marked + economia
        add(.arcana, .striker, "Raio",   cost: 38, dmg: 11, cd: 0.5, range: 3, applies: .marked, bounty: 3, [.cadencia, .detonador])
        add(.arcana, .blaster, "Orbe",   cost: 54, dmg: 14, cd: 1.3, range: 3, splash: 1, applies: .marked, bounty: 3, [.chamasVivas, .cobranca])
        add(.arcana, .support, "Prisma", cost: 50, dmg: 2, cd: 1.0, range: 3, applies: .marked, bounty: 12, aura: 0.08, [.ressonancia, .cobranca])

        // 🌿 NATUREZA — rooted
        add(.natureza, .striker, "Espinho", cost: 34, dmg: 11, cd: 0.5, range: 2, applies: .rooted, [.precisao, .profundo])
        add(.natureza, .blaster, "Cipó",    cost: 50, dmg: 13, cd: 1.4, range: 2, splash: 1, applies: .rooted, [.chamasVivas, .estilhacos])
        add(.natureza, .support, "Totem",   cost: 46, dmg: 2, cd: 1.0, range: 2, applies: .rooted, aura: 0.12, [.ressonancia, .potencia])

        return out
    }
}
