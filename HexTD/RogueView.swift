import SwiftUI
import SpriteKit

/// Tela do Rogue idle (torre central, estilo The Tower). Escolhe 1 torre desbloqueada,
/// ela vai pro centro e atira sozinha; o jogador compra os 6 upgrades com o gold dos
/// kills. Game over ao zerar o HP.
struct RogueView: View {
    @ObservedObject var meta: MetaProgress
    let onExit: () -> Void
    @StateObject private var model = GameModel()
    @State private var sceneID = UUID()
    @State private var showPause = false
    @State private var showGameSettings = false

    private var unlocked: [Int] { meta.unlockedIds }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteView(scene: makeScene(size: geo.size))
                    .id(sceneID).ignoresSafeArea()

                VStack(spacing: 10) {
                    hud
                    if model.rogueStarted { speedStrip }
                    Spacer()
                    if model.rogueStarted { upgradePanel }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)

                if !model.rogueStarted && !model.gameOver { startOverlay }
                if model.gameOver { gameOverCard }
                if showPause { pauseOverlay }
                if showGameSettings { SettingsView(meta: meta, onExit: { showGameSettings = false; showPause = true }) }
            }
        }
        .onAppear {
            if model.selected < 0 || !meta.isUnlocked(model.selected) {
                model.selected = unlocked.first ?? 9
            }
        }
    }

    private func makeScene(size: CGSize) -> RogueScene {
        let s = RogueScene(model: model, meta: meta, size: size)
        return s
    }

    // MARK: HUD

    private var hud: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Button { model.paused = true; showPause = true } label: {
                    Text("⏸").font(.system(size: 22, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.15)).foregroundColor(.white).clipShape(Circle())
                }
                stat("💰", "\(model.gold)", 42)
                stat("🌊", "\(model.wave)", 26)
                stat("💀", "\(model.rogueKills)", 34)
                Spacer(minLength: 2)
                Text("Rogue").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            if model.rogueStarted { hpBar }
        }
    }

    private var hpBar: some View {
        let frac = model.rogueMaxHP > 0 ? max(0, model.rogueHP / model.rogueMaxHP) : 0
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.5))
                Capsule().fill(frac > 0.35 ? Color(red: 0.35, green: 0.85, blue: 0.4)
                                           : Color(red: 0.9, green: 0.3, blue: 0.3))
                    .frame(width: g.size.width * frac)
                HStack {
                    Text("❤️ \(Int(max(0, model.rogueHP).rounded())) / \(Int(model.rogueMaxHP.rounded()))")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white).padding(.leading, 10)
                    Spacer()
                }
            }
        }
        .frame(height: 22)
    }

    private func stat(_ icon: String, _ v: String, _ w: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(icon).font(.system(size: 15))
            Text(v).font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit().frame(minWidth: w, alignment: .leading).foregroundColor(.white)
        }
        .fixedSize().padding(.horizontal, 9).padding(.vertical, 6)
        .background(.black.opacity(0.40), in: Capsule())
    }

    // MARK: velocidade (idle → acelerar)

    private func speedUnlocked(_ s: Int) -> Bool {
        switch s { case 1: return true; case 2: return meta.has2xSpeed; default: return meta.hasFastSpeed }
    }
    private var speedStrip: some View {
        HStack(spacing: 6) {
            ForEach([1, 2, 5, 10], id: \.self) { s in
                let on = speedUnlocked(s)
                Button { if on { model.speed = s } } label: {
                    Text(on ? "\(s)×" : "🔒")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .frame(minWidth: 34, minHeight: 30)
                        .background(model.speed == s ? Color(red: 0.25, green: 0.55, blue: 0.95) : .black.opacity(0.4))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                        .opacity(on ? 1 : 0.5)
                }.disabled(!on)
            }
            Spacer()
            if meta.autoUnlocked {
                Button { model.autoPlay.toggle() } label: {
                    HStack(spacing: 4) {
                        Text("🤖").font(.system(size: 13))
                        Text(model.autoPlay ? "AUTO ON" : "AUTO")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                    }
                    .frame(minHeight: 30).padding(.horizontal, 10)
                    .background(model.autoPlay ? Color(red: 0.35, green: 0.80, blue: 0.40) : .black.opacity(0.4))
                    .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: painel de upgrades (6, compra manual)

    private var upgradePanel: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(RogueUpgrade.allCases, id: \.rawValue) { u in
                let i = u.rawValue
                let cost = model.rogueCost[i]
                let can = model.gold >= cost
                Button { model.doRogueUpgrade?(i) } label: {
                    VStack(spacing: 1) {
                        Text("\(u.icon) \(u.nome)").font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                        Text(u == .regen ? String(format: "%.1f%%/s", model.rogueMult[i])
                                         : String(format: "×%.2f", model.rogueMult[i]))
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(red: 0.55, green: 0.9, blue: 1))
                        Text("Nv \(model.rogueUpg[i])").font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                        Text("💰\(cost)").font(.system(size: 12, weight: .bold))
                            .foregroundColor(can ? .yellow : .red)
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .background(can ? Color(red: 0.20, green: 0.40, blue: 0.60) : .black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }.disabled(!can)
            }
        }
    }

    // MARK: overlay de início (escolher torre)

    private var startOverlay: some View {
        VStack(spacing: 16) {
            Text("🗼 Rogue idle").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundColor(.white)
            Text("Escolha uma torre. Ela fica no centro e defende de todos os lados.\nMonstros vêm sem parar — suba os upgrades e sobreviva.")
                .font(.system(size: 14)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
            if unlocked.isEmpty {
                Text("🔒 Nenhuma torre desbloqueada. Faça Summons primeiro.")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.orange)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(unlocked, id: \.self) { id in
                            let spec = TowerCatalog.spec(id)
                            let on = model.selected == id
                            Button { model.selected = id } label: {
                                VStack(spacing: 2) {
                                    Text(spec.icon).font(.system(size: 26))
                                    Text(spec.nome).font(.system(size: 11, weight: .heavy, design: .rounded))
                                        .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                                    Text(meta.rarity(id).nome).font(.system(size: 9, weight: .bold))
                                        .foregroundColor(meta.rarity(id).color)
                                }
                                .frame(maxWidth: .infinity, minHeight: 66)
                                .background(on ? Color(red: 0.25, green: 0.55, blue: 0.95) : .black.opacity(0.45))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(spec.element.color.opacity(on ? 1 : 0.4), lineWidth: 2))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }.frame(maxHeight: 320)
                Button { model.doRogueStart?() } label: {
                    Text("▶ Começar").font(.system(size: 18, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(red: 0.35, green: 0.80, blue: 0.40))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            Button(action: onExit) {
                Text("Voltar").font(.system(size: 15, weight: .bold)).foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(24).background(.black.opacity(0.85)).clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 20)
    }

    // MARK: game over

    // MARK: — Menu de pause

    private func pauseBtn(_ title: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 50).background(color).foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("⏸ Pausado").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundColor(.white)
                pauseBtn("▶ Continuar", Color(red: 0.35, green: 0.80, blue: 0.40)) { showPause = false; model.paused = false }
                pauseBtn("⚙️ Configurações", Color(red: 0.25, green: 0.55, blue: 0.95)) { showPause = false; showGameSettings = true }
                pauseBtn("🏠 Voltar ao menu", Color(red: 0.85, green: 0.35, blue: 0.30)) { model.paused = false; onExit() }
            }
            .padding(28).frame(maxWidth: 320)
            .background(.black.opacity(0.55)).clipShape(RoundedRectangle(cornerRadius: 24)).padding(24)
        }
    }

    private var gameOverCard: some View {
        VStack(spacing: 14) {
            Text("💀 Game Over").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundColor(.white)
            Text("Sobreviveu até a onda \(model.wave)\n\(model.rogueKills) inimigos eliminados")
                .font(.system(size: 15)).foregroundColor(.white.opacity(0.75)).multilineTextAlignment(.center)
            Text("🪙 +\(model.creditsEarned) créditos").font(.system(size: 18, weight: .heavy)).foregroundColor(.yellow)
            HStack(spacing: 12) {
                Button {
                    model.reset(); model.selected = unlocked.first ?? 9; sceneID = UUID()
                } label: {
                    Text("↻ Jogar de novo").font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color(red: 0.35, green: 0.80, blue: 0.40))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button(action: onExit) {
                    Text("Menu").font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.white.opacity(0.15))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(24).background(.black.opacity(0.9)).clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 28)
    }
}
