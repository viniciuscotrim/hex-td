import Foundation

/// T3 — Propagação por PAPEL. Três mecânicas distintas de spread (o coração do design).
/// Puras/testáveis: recebem posições (Hex) e devolvem os afetados; a cena aplica o efeito.
/// Números/efeitos vêm do bloco `propagation` do JSON (não hardcoded).

/// Efeito deixado NO CHÃO por um striker ao matar com status (propaga o eixo no ESPAÇO).
struct VsGroundEffect: Equatable {
    let hex: Hex
    let kind: String            // poca_lava / piso_gelo / nuvem_esporo / runa / espinhado / marca_sangue
    let status: VsStatusKind
    let chains: Bool            // phys (marca de sangue) encadeia o próximo alvo
    var until: Double
}

enum VsPropagation {
    // MARK: Striker — propaga NO ESPAÇO (deixa efeito no hex)

    /// Ao matar com status, cria o efeito de chão do elemento (dur/status/kind do config).
    static func strikerGround(element: String, at hex: Hex, now: Double, cfg: VsPropagationConfig) -> VsGroundEffect? {
        guard let g = cfg.striker[element], let st = VsStatusKind(rawValue: g.status) else { return nil }
        return VsGroundEffect(hex: hex, kind: g.kind, status: st, chains: g.chains, until: now + g.dur)
    }

    /// Inimigos que estão SOBRE um efeito de chão ativo → recebem o status daquele efeito.
    static func groundHits(_ effects: [VsGroundEffect], enemies: [(id: Int, hex: Hex)],
                           now: Double) -> [(id: Int, status: VsStatusKind)] {
        var out: [(Int, VsStatusKind)] = []
        for e in effects where e.until > now {
            for en in enemies where en.hex == e.hex { out.append((en.id, e.status)) }
        }
        return out
    }

    // MARK: Blaster — propaga por SALTO (contágio ao morrer)

    /// Ao MORRER, o blaster propaga o status por até `maxTargets` inimigos a ≤ `rangeTiles`,
    /// dos mais próximos pros mais distantes. Exclui o próprio morto.
    static func blasterSpread(fromHex: Hex, deadId: Int, candidates: [(id: Int, hex: Hex)],
                              cfg: VsPropagationConfig) -> [Int] {
        candidates
            .filter { $0.id != deadId && fromHex.distance(to: $0.hex) <= cfg.blaster.rangeTiles }
            .sorted { fromHex.distance(to: $0.hex) < fromHex.distance(to: $1.hex) }
            .prefix(cfg.blaster.maxTargets)
            .map { $0.id }
    }

    // MARK: Balista (exceção) — perfura em LINHA (não radial)

    /// Perfura em LINHA reta na direção `dir` (0..5). Cada inimigo na reta fica Exposto; se JÁ
    /// exposto, ganha +`primedBonus` de dano. NÃO é splash radial. Retorna (id, primed).
    static func balistaLine(origin: Hex, dir: Int, maxRange: Int = 10,
                            enemies: [(id: Int, hex: Hex, exposed: Bool)]) -> [(id: Int, primed: Bool)] {
        let d = Hex.directions[((dir % 6) + 6) % 6]
        var line: Set<Hex> = []
        var cur = origin
        for _ in 1...maxRange { cur = cur + d; line.insert(cur) }
        return enemies.filter { line.contains($0.hex) }.map { ($0.id, $0.exposed) }
    }
}
