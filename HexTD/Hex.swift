import CoreGraphics

/// Coordenada axial de hexágono (pointy-top). q = coluna, r = linha.
/// Distância/vizinhos usam a forma "cube" derivada — ver `distance`.
struct Hex: Hashable {
    let q: Int
    let r: Int

    static let directions: [Hex] = [
        Hex(q: 1, r: 0), Hex(q: 1, r: -1), Hex(q: 0, r: -1),
        Hex(q: -1, r: 0), Hex(q: -1, r: 1), Hex(q: 0, r: 1)
    ]

    func neighbor(_ i: Int) -> Hex { self + Hex.directions[i] }
    var neighbors: [Hex] { Hex.directions.map { self + $0 } }

    static func + (a: Hex, b: Hex) -> Hex { Hex(q: a.q + b.q, r: a.r + b.r) }

    /// Distância em passos de hex (métrica cube).
    func distance(to o: Hex) -> Int {
        let dq = q - o.q, dr = r - o.r
        return (abs(dq) + abs(dr) + abs(dq + dr)) / 2
    }
}

/// Layout pointy-top: converte hex axial ↔ ponto de tela, dado `size` do hex
/// (raio do centro ao vértice) e uma origem em pixels.
struct HexLayout {
    let size: CGFloat
    let origin: CGPoint

    func center(of h: Hex) -> CGPoint {
        let x = size * (sqrt(3.0) * CGFloat(h.q) + sqrt(3.0) / 2 * CGFloat(h.r))
        let y = size * (1.5 * CGFloat(h.r))
        return CGPoint(x: origin.x + x, y: origin.y + y)
    }

    /// Vértices do polígono hexagonal (pointy-top) em torno do centro.
    func corners(of h: Hex) -> [CGPoint] {
        let c = center(of: h)
        return (0..<6).map { i in
            let angle = CGFloat.pi / 180 * (60 * CGFloat(i) - 30)
            return CGPoint(x: c.x + size * cos(angle), y: c.y + size * sin(angle))
        }
    }
}
