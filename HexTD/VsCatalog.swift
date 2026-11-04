import Foundation

/// Catálogo do modo Vs redesenhado (merge). Fonte de verdade = `progression_vs.json` (21
/// torres + 6 combos). Foundation-only de propósito → testável isolado por linha de comando,
/// sem depender de SpriteKit/SwiftUI. O motor comum (Campanha/Endless/Rogue) NÃO é tocado:
/// este catálogo é exclusivo do Vs.
///
/// Regras (do briefing): alvos 1→2 e chance de status sobem na Épica+ (flag por raridade,
/// não número fixo). `statMult` de raridade = ×1.5/tier (mesma do MASTER).

/// Modo de alvo: `1` (single) / `"unlimited"` (blaster AoE) / `"line"` (Balista perfura).
enum VsTargetMode: Equatable, Codable {
    case count(Int)
    case unlimited
    case line

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) { self = .count(n); return }
        switch try c.decode(String.self) {
        case "unlimited": self = .unlimited
        case "line":      self = .line
        default:          self = .count(1)
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .count(let n): try c.encode(n)
        case .unlimited:    try c.encode("unlimited")
        case .line:         try c.encode("line")
        }
    }
}

struct VsTowerSpec: Codable, Equatable {
    let id: String
    let element: String        // fire/water/ice/phys/poison/arcane/nature
    let emoji: String
    let role: String           // striker/blaster/support
    let name: String
    let cost: Int
    let baseDamage: Double
    let atkPerSec: Double
    let cooldown: Double
    let targets: VsTargetMode
    let targetsEpicPlus: Int?  // striker: 1→2 na Épica+
    let appliesStatus: String?
    let statusChance: Double
    let aura: String?
    let bounty: Int?
    let dpsEff: Double
    let valuePerCost: Double
    let axisNote: String

    /// Alvos efetivos por raridade (tier 0..5). Sobe pro `targetsEpicPlus` na Épica (tier≥3).
    func targetsFor(tier: Int) -> VsTargetMode {
        if case .count = targets, let ep = targetsEpicPlus, tier >= VsCatalog.epicTier {
            return .count(ep)
        }
        return targets
    }
    /// Chance de status efetiva: +25% (relativo) na Épica+, sem passar de 1.0.
    func statusChanceFor(tier: Int) -> Double {
        tier >= VsCatalog.epicTier ? min(1.0, statusChance * 1.25) : statusChance
    }
    /// Dano base já escalado pela raridade (×1.5/tier).
    func damageFor(tier: Int) -> Double { baseDamage * VsCatalog.statMult(tier: tier) }
}

struct VsCombo: Codable, Equatable {
    let id: String
    let mothers: [String]      // 2 elementos
    let name: String
    let reaction: String?
    let damage: Double
    let cooldown: Double
    let splash: Int
    let applies: [String]
    let consumes: String?
    let critVsFrozen: Double?
    let bonusIfPrimed: Double?
    let bounty: Int?
    let note: String?

    /// Chave normalizada do par (independente da ordem) → casar mães adjacentes.
    var pairKey: Set<String> { Set(mothers) }
}

/// Números de status do Vs (auditáveis no JSON `statusConfig`). NÃO hardcode em código.
struct VsStatusConfig: Codable, Equatable {
    struct Burn: Codable, Equatable { let pctHPPerSec: Double; let dur: Double; let bossPctHPPerSec: Double }
    struct Wet: Codable, Equatable { let dur: Double; let moveMult: Double; let nextStatusDurMult: Double }
    struct Frozen: Codable, Equatable { let slowMult: Double; let dur: Double; let deepSlowMult: Double; let deepDur: Double }
    struct DmgUp: Codable, Equatable { let dmgMult: Double; let dur: Double }   // exposed / marked
    struct Poison: Codable, Equatable { let pctHPPerSecPerStack: Double; let dur: Double; let cap: Int; let bossPctHPPerSecPerStack: Double }
    struct Rooted: Codable, Equatable { let moveMult: Double; let dur: Double }
    struct BossChance: Codable, Equatable { let `default`: Double; let wet: Double }
    let burn: Burn; let wet: Wet; let frozen: Frozen; let exposed: DmgUp
    let poison: Poison; let marked: DmgUp; let rooted: Rooted; let bossChance: BossChance
}

/// Config de propagação por papel (T3) — auditável no JSON.
struct VsPropagationConfig: Codable, Equatable {
    struct Ground: Codable, Equatable { let kind: String; let dur: Double; let status: String; let chains: Bool }
    struct Blaster: Codable, Equatable { let maxTargets: Int; let rangeTiles: Int }
    struct Balista: Codable, Equatable { let applies: String; let primedBonus: Double }
    let striker: [String: Ground]   // por elemento
    let blaster: Blaster
    let balista: Balista
}

enum VsCatalog {
    static let epicTier = 3                        // Épica = tier 3 (Comum..Mítica = 0..5)
    static let rarityStatMult: [Double] = [1.0, 1.5, 2.25, 3.375, 5.0625, 7.59375]
    static func statMult(tier: Int) -> Double { rarityStatMult[max(0, min(tier, rarityStatMult.count - 1))] }

    private(set) static var towers: [VsTowerSpec] = []
    private(set) static var combos: [VsCombo] = []
    private(set) static var status: VsStatusConfig?
    private(set) static var propagation: VsPropagationConfig?
    private static var byId: [String: VsTowerSpec] = [:]
    private static var comboByPair: [Set<String>: VsCombo] = [:]

    static func spec(_ id: String) -> VsTowerSpec? { byId[id] }
    /// Combo do par de elementos (ordem irrelevante), se existir.
    static func combo(_ a: String, _ b: String) -> VsCombo? { comboByPair[Set([a, b])] }

    private struct Payload: Codable {
        let towers: [VsTowerSpec]; let combos: [VsCombo]
        let statusConfig: VsStatusConfig; let propagation: VsPropagationConfig
    }

    /// Decodifica de Data (usado pelo runtime E pelos testes).
    static func decode(_ data: Data) throws -> (towers: [VsTowerSpec], combos: [VsCombo],
                                                status: VsStatusConfig, prop: VsPropagationConfig) {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        return (p.towers, p.combos, p.statusConfig, p.propagation)
    }

    private static func apply(_ t: [VsTowerSpec], _ c: [VsCombo], _ s: VsStatusConfig, _ p: VsPropagationConfig) {
        towers = t; combos = c; status = s; propagation = p
        byId = Dictionary(uniqueKeysWithValues: t.map { ($0.id, $0) })
        comboByPair = Dictionary(uniqueKeysWithValues: c.map { ($0.pairKey, $0) })
    }

    /// Instala conteúdo já decodificado (usado pelos testes, que não têm bundle).
    static func install(towers t: [VsTowerSpec], combos c: [VsCombo],
                        status s: VsStatusConfig, prop p: VsPropagationConfig) {
        apply(t, c, s, p)
    }

    /// Carrega do bundle (se existir). Chamar no início do app. Idempotente.
    @discardableResult
    static func load() -> Bool {
        guard let url = Bundle.main.url(forResource: "progression_vs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? decode(data) else { return false }
        apply(parsed.towers, parsed.combos, parsed.status, parsed.prop)
        reload()
        return true
    }

    #if DEBUG
    private static var devMTime: Date?
    static var devOverrideURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("progression_vs.json")
    }
    /// Hot-reload de dev: coloque `progression_vs.json` no Documents do app pra tunar a quente.
    static func reload() {
        let url = devOverrideURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let m = attrs[.modificationDate] as? Date, m != devMTime,
              let data = try? Data(contentsOf: url),
              let parsed = try? decode(data) else { return }
        apply(parsed.towers, parsed.combos, parsed.status, parsed.prop); devMTime = m
    }
    #else
    static func reload() {}
    #endif
}
