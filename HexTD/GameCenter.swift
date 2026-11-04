import GameKit
import SwiftUI

/// Login e estado do Game Center. Requer a capability "Game Center" habilitada no target
/// (Signing & Capabilities) e o app criado no App Store Connect com Game Center ativo.
/// Sem isso, `authenticate()` apenas falha silenciosamente e `authenticated` fica false.
final class GameCenter: NSObject, ObservableObject {
    static let shared = GameCenter()

    @Published var authenticated = false
    @Published var playerName = ""
    @Published var authInProgress = false

    /// Dispara o fluxo de login. Chamar no início do app. Idempotente.
    func authenticate() {
        guard !GKLocalPlayer.local.isAuthenticated else { syncState(); return }
        authInProgress = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] vc, _ in
            guard let self else { return }
            if let vc {                              // Game Center precisa mostrar a tela de login
                Self.topViewController()?.present(vc, animated: true)
            } else {
                self.authInProgress = false
                self.syncState()
            }
        }
    }

    private func syncState() {
        authenticated = GKLocalPlayer.local.isAuthenticated
        playerName = GKLocalPlayer.local.displayName
    }

    /// View controller no topo (pra apresentar telas nativas do Game Center a partir da SwiftUI).
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
