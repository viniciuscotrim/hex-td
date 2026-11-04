import GameKit

/// Mensagens trocadas na partida PvP (ações do jogador remoto). Coordenadas são as do
/// SUL do REMETENTE; no meu device elas são espelhadas pro NORTE.
enum PvPMsg: Codable {
    case hello(UInt64)            // handshake: contribuição pra seed compartilhada
    case place(Int, Int, Int)     // q, r, specId
    case upgrade(Int, Int)        // q, r
    case priority(Int, Int, Bool) // q, r, prioriza o meio?
    case send                     // enviou um monstro pra mim
    case state(Int, Int)          // vidas, onda (sincroniza HUD/fim)
    case quit
}

/// Sessão PvP via Game Center (GKMatch 1×1). Faz matchmaking, handshake de seed e troca de
/// mensagens de ação. A partida em si roda determinística nos dois lados a partir da seed.
final class PvPSession: NSObject, ObservableObject, GKMatchDelegate, GKMatchmakerViewControllerDelegate {
    @Published var connected = false
    @Published var ready = false
    @Published var failed: String?
    @Published var opponentName = ""

    private(set) var seed: UInt64 = 0
    private(set) var isHost = false
    private var match: GKMatch?
    private var myHello: UInt64 = 0
    private var gotHello = false

    var onMessage: ((PvPMsg) -> Void)?
    var onReady: (() -> Void)?

    /// Apresenta a tela nativa de matchmaking (encontra 1 oponente).
    func startMatchmaking() {
        guard GKLocalPlayer.local.isAuthenticated else { failed = "Entre no Game Center primeiro."; return }
        let req = GKMatchRequest()
        req.minPlayers = 2; req.maxPlayers = 2
        guard let vc = GKMatchmakerViewController(matchRequest: req) else { failed = "Matchmaking indisponível."; return }
        vc.matchmakerDelegate = self
        GameCenter.topViewController()?.present(vc, animated: true)
    }

    func send(_ msg: PvPMsg) {
        guard let match, let data = try? JSONEncoder().encode(msg) else { return }
        try? match.sendData(toAllPlayers: data, with: .reliable)
    }

    func leave() { send(.quit); match?.disconnect(); match = nil }

    // MARK: GKMatchmakerViewControllerDelegate
    func matchmakerViewControllerWasCancelled(_ vc: GKMatchmakerViewController) {
        vc.dismiss(animated: true); failed = "Cancelado."
    }
    func matchmakerViewController(_ vc: GKMatchmakerViewController, didFailWithError error: Error) {
        vc.dismiss(animated: true); failed = error.localizedDescription
    }
    func matchmakerViewController(_ vc: GKMatchmakerViewController, didFind match: GKMatch) {
        vc.dismiss(animated: true)
        self.match = match; match.delegate = self
        connected = true
        opponentName = match.players.first?.displayName ?? "Oponente"
        // handshake: cada lado manda um número; seed = XOR, host = maior número.
        myHello = UInt64.random(in: 1...UInt64.max)
        send(.hello(myHello))
    }

    // MARK: GKMatchDelegate
    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let msg = try? JSONDecoder().decode(PvPMsg.self, from: data) else { return }
        if case let .hello(theirs) = msg {
            guard !gotHello else { return }
            gotHello = true
            seed = myHello ^ theirs
            isHost = myHello > theirs
            DispatchQueue.main.async { self.ready = true; self.onReady?() }
            return
        }
        DispatchQueue.main.async { self.onMessage?(msg) }
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        if state == .disconnected { DispatchQueue.main.async { self.failed = "Oponente saiu." } }
    }
}
