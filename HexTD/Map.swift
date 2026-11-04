import Foundation

/// Mapa hex gerado por constraint (GDD §3): caminho sempre-para-frente do topo
/// à base (uma célula por linha), obstáculos nos tiles fora dele. Sem WFC — MVP.
struct HexMap {
    let cols: Int
    let rows: Int
    private(set) var cells: Set<Hex>          // todos os hexes do tabuleiro
    private(set) var blocked: Set<Hex>        // obstáculos (não pisável, não construível)
    let entrance: Hex
    let exit: Hex
    private(set) var path: [Hex]              // rota entrada→saída que os inimigos seguem

    /// Hexes onde dá pra construir torre: livres e fora do caminho.
    var buildable: Set<Hex> {
        cells.subtracting(blocked).subtracting(path).subtracting([entrance, exit])
    }

    func isPath(_ h: Hex) -> Bool { pathSet.contains(h) }
    private let pathSet: Set<Hex>

    // MARK: geração

    /// `complexity` (0..1) escala com a dificuldade: baixo = caminho fino/simples
    /// (iniciante), alto = serpentina que ocupa ~2/3 do tabuleiro. Sempre vertical
    /// (topo→base) e sempre avançando — nunca sobe de volta ao spawn.
    static func generate(cols: Int, rows: Int, obstacleRatio: Double = 0.12,
                         complexity: Double = 0.9,
                         rng: inout RandomNumberGenerator) -> HexMap {
        func qStart(_ r: Int) -> Int { -(r / 2) }
        func hexAt(row r: Int, frac f: Double) -> Hex {
            let c = min(max(Int((f * Double(cols - 1)).rounded()), 0), cols - 1)
            return Hex(q: qStart(r) + c, r: r)
        }
        func fx(_ h: Hex) -> Double { Double(h.q) + Double(h.r) / 2.0 }

        var all: [Hex] = []
        for r in 0..<rows {
            for q in qStart(r)..<(qStart(r) + cols) { all.append(Hex(q: q, r: r)) }
        }
        let cellSet = Set(all)
        let topRow = rows - 1, botRow = 0

        // Fecha o mapa a partir de um caminho pronto: entrada/saída nas pontas,
        // obstáculos nos tiles fora do caminho.
        func build(_ path: [Hex]) -> HexMap {
            let entrance = path.first!, exit = path.last!
            let pathSet = Set(path)
            var blocked = Set<Hex>()
            let candidates = all.filter { !pathSet.contains($0) && $0 != entrance && $0 != exit }
            let target = Int(Double(all.count) * obstacleRatio)
            for h in candidates.shuffled(using: &rng).prefix(target) { blocked.insert(h) }
            return HexMap(cols: cols, rows: rows, cells: cellSet, blocked: blocked,
                          entrance: entrance, exit: exit, path: path, pathSet: pathSet)
        }

        // ── ALTA COMPLEXIDADE: 3 estilos de caminho p/ variar os mapas ───────
        // Todos respeitam a adjacência (col ±1 na horizontal, mesma-col na queda)
        // e SÓ descem (inimigo sempre avança). Estilo escolhido pela seed.
        if complexity >= 0.35 {
            func hexPath(_ cr: [(Int, Int)]) -> HexMap { build(cr.map { Hex(q: qStart($0.1) + $0.0, r: $0.1) }) }
            let style = Int.random(in: 0..<3, using: &rng)
            var cr: [(Int, Int)] = []

            if style == 0 {
                // Serpentina cheia: varreduras de largura total, bandas de `drop`.
                let drop = complexity >= 0.7 ? 2 : 3
                var r = topRow, right = Bool.random(using: &rng)
                while r >= botRow {
                    for c in (right ? Array(0..<cols) : Array((0..<cols).reversed())) { cr.append((c, r)) }
                    let edge = right ? cols - 1 : 0
                    var rr = r - 1, s = 0
                    while rr >= botRow && s < drop - 1 { cr.append((edge, rr)); rr -= 1; s += 1 }
                    r = rr; right.toggle()
                }
            } else if style == 1 {
                // Serpentina PARCIAL: cada varredura para numa coluna aleatória → irregular.
                var r = topRow
                var c = Int.random(in: 0..<cols, using: &rng)
                var right = Bool.random(using: &rng)
                cr.append((c, r))
                while r > botRow {
                    let target = right ? Int.random(in: c..<cols, using: &rng)
                                       : Int.random(in: 0...c, using: &rng)
                    while c != target { c += target > c ? 1 : -1; cr.append((c, r)) }
                    let drop = Int.random(in: 1...2, using: &rng)
                    var s = 0
                    while r > botRow && s < drop { r -= 1; cr.append((c, r)); s += 1 }
                    right.toggle()
                }
            } else {
                // DENTES verticais: desce em colunas, saltos horizontais curtos entre elas.
                var r = topRow
                var c = Bool.random(using: &rng) ? 0 : cols - 1
                var right = c == 0
                cr.append((c, r))
                while r > botRow {
                    let tooth = Int.random(in: 2...4, using: &rng)
                    var s = 0
                    while r > botRow && s < tooth { r -= 1; cr.append((c, r)); s += 1 }
                    if r == botRow { break }
                    let gap = Int.random(in: 1...3, using: &rng)
                    var g = 0
                    while g < gap {
                        let nc = c + (right ? 1 : -1)
                        if nc < 0 || nc >= cols { break }
                        c = nc; cr.append((c, r)); g += 1
                    }
                    if c == 0 { right = true } else if c == cols - 1 { right = false }
                }
            }
            return hexPath(cr)
        }

        // ── BAIXA COMPLEXIDADE: descida fina, uma célula por linha ───────────
        for _ in 0..<40 {
            let entrance = hexAt(row: topRow, frac: Double.random(in: 0.35...0.65, using: &rng))
            var cur = entrance
            var tx = fx(entrance)
            var path = [cur]
            var ok = true
            for r in stride(from: topRow - 1, through: botRow, by: -1) {
                tx += Double.random(in: -0.6...0.6, using: &rng)
                tx = min(max(tx, 0.6), Double(cols) - 1.6)
                let a = Hex(q: cur.q, r: r), b = Hex(q: cur.q + 1, r: r)
                let cands = [a, b].filter { cellSet.contains($0) }
                guard let next = cands.min(by: { abs(fx($0) - tx) < abs(fx($1) - tx) }) else { ok = false; break }
                cur = next; path.append(cur)
            }
            guard ok, path.count == rows else { continue }
            return build(path)
        }
        // Fallback: descida reta.
        var cur = hexAt(row: topRow, frac: 0.5); var path = [cur]
        for r in stride(from: topRow - 1, through: botRow, by: -1) {
            let a = Hex(q: cur.q, r: r), b = Hex(q: cur.q + 1, r: r)
            cur = cellSet.contains(a) ? a : b; path.append(cur)
        }
        return build(path)
    }
}
