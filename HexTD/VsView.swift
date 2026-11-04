import SwiftUI
import SpriteKit

/// Engine do Vs (3 lanes): UMA cena, dois lados, 5 slots por lado que cobrem as duas lanes.
final class VsEngine: ObservableObject {
    let playerModel = GameModel()
    let aiModel = GameModel()
    let state = VsState()
    let scene: VsScene

    init(meta: MetaProgress, loadout: [Int], pvp: PvPSession? = nil) {
        scene = VsScene(meta: meta, playerModel: playerModel, aiModel: aiModel,
                        state: state, loadout: loadout, size: CGSize(width: 390, height: 680))
        scene.pvp = pvp
        scene.pvpSeed = pvp?.seed ?? 0
    }
}

/// Fluxo do Vs: primeiro escolhe 5 torres (loadout), depois entra na partida.
struct VsView: View {
    @ObservedObject var meta: MetaProgress
    let onExit: () -> Void
    var pvp: PvPSession? = nil
    @State private var loadout: [Int] = []
    @State private var started = false

    var body: some View {
        if started {
            VsMatchView(meta: meta, loadout: loadout, pvp: pvp, onExit: onExit)
        } else {
            VsLoadoutStep(meta: meta, loadout: $loadout, onExit: onExit,
                          onStart: { started = true })
        }
    }
}

/// Fluxo PvP: login no Game Center → procurar oponente → (conectado) escolhe torres e joga.
struct VsPvPFlow: View {
    @ObservedObject var meta: MetaProgress
    let onExit: () -> Void
    @StateObject private var session = PvPSession()
    @ObservedObject private var gc = GameCenter.shared

    var body: some View {
        if session.ready {
            VsView(meta: meta, onExit: onExit, pvp: session)
        } else {
            lobby
        }
    }

    private var lobby: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: { session.leave(); onExit() }) {
                    Text("✕").font(.system(size: 20, weight: .bold)).frame(width: 40, height: 40)
                        .background(.white.opacity(0.15)).foregroundColor(.white).clipShape(Circle())
                }
                Spacer()
            }.padding(.horizontal, 14).padding(.top, 6)
            Spacer()
            Text("⚔️ Vs Jogador").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundColor(.white)
            if gc.authenticated {
                Text("🎮 \(gc.playerName)").font(.system(size: 14, weight: .bold)).foregroundColor(.green)
                if session.connected {
                    ProgressView().tint(.white)
                    Text("Conectando à partida…").font(.system(size: 14)).foregroundColor(.white.opacity(0.8))
                } else {
                    Button { session.startMatchmaking() } label: {
                        Text("🔍 Procurar oponente").font(.system(size: 18, weight: .heavy, design: .rounded))
                            .frame(maxWidth: 280, minHeight: 52)
                            .background(Color(red: 0.25, green: 0.55, blue: 0.95))
                            .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            } else {
                Text("Entre no Game Center pra jogar contra outro jogador.")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
                Button { gc.authenticate() } label: {
                    Text("🎮 Entrar no Game Center").font(.system(size: 17, weight: .heavy, design: .rounded))
                        .frame(maxWidth: 280, minHeight: 52)
                        .background(Color(red: 0.35, green: 0.80, blue: 0.40))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            if let f = session.failed {
                Text(f).font(.system(size: 12)).foregroundColor(.red.opacity(0.9)).multilineTextAlignment(.center)
            }
            Spacer()
        }
    }
}

/// Passo de loadout do Vs: escolha até 5 torres (você põe qualquer uma nos 5 slots, pode repetir).
private struct VsLoadoutStep: View {
    @ObservedObject var meta: MetaProgress
    @Binding var loadout: [Int]
    let onExit: () -> Void
    let onStart: () -> Void
    @State private var pick: Set<Int> = []

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onExit) {
                    Text("✕").font(.system(size: 20, weight: .bold)).frame(width: 40, height: 40)
                        .background(.white.opacity(0.15)).foregroundColor(.white).clipShape(Circle())
                }
                Spacer()
                Text("⚔️ Vs IA — escolha 5 torres").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(.white)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            Text("\(pick.count)/5 · você coloca qualquer uma nos 5 slots (pode repetir)")
                .font(.system(size: 12, weight: .bold)).foregroundColor(pick.count == 5 ? .green : .white.opacity(0.7))
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Element.allCases, id: \.self) { e in
                        let ids = TowerCatalog.ids(of: e).filter { meta.isUnlocked($0) }
                        if !ids.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(e.icon).font(.system(size: 15))
                                    Text(e.nome).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(e.color)
                                    Spacer()
                                }
                                HStack(spacing: 8) { ForEach(ids, id: \.self) { chip($0) } }
                            }
                        }
                    }
                }.padding(.vertical, 4)
            }
            Button {
                loadout = Array(pick); onStart()
            } label: {
                Text(pick.isEmpty ? "Escolha ao menos 1" : "Começar  ▶")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(pick.isEmpty ? Color.gray.opacity(0.4) : Color(red: 0.35, green: 0.80, blue: 0.40))
                    .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 16))
            }.disabled(pick.isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .onAppear { pick = Set(meta.loadoutRaw.prefix(5)) }   // pré-preenche com o loadout salvo
    }

    private func chip(_ id: Int) -> some View {
        let spec = TowerCatalog.spec(id)
        let on = pick.contains(id)
        let full = pick.count >= 5 && !on
        return Button {
            if on { pick.remove(id) } else if pick.count < 5 { pick.insert(id) }
        } label: {
            VStack(spacing: 1) {
                Text(spec.role.nome).font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.7))
                Text(spec.icon).font(.system(size: 18))
                Text(spec.nome).font(.system(size: 10, weight: .bold)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                Text(meta.rarity(id).nome).font(.system(size: 8, weight: .semibold)).foregroundColor(meta.rarity(id).color)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .opacity(full ? 0.4 : 1)
            .background(on ? Color(red: 0.25, green: 0.55, blue: 0.95) : .black.opacity(0.4))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(on ? 0.9 : 0.2), lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }.disabled(full)
    }
}

/// A partida em si.
private struct VsMatchView: View {
    @ObservedObject var meta: MetaProgress
    let loadout: [Int]
    let onExit: () -> Void
    @StateObject private var engine: VsEngine
    @ObservedObject private var state: VsState   // observa a onda/fim direto (senão não atualiza)

    init(meta: MetaProgress, loadout: [Int], pvp: PvPSession? = nil, onExit: @escaping () -> Void) {
        self.meta = meta; self.loadout = loadout; self.onExit = onExit
        let e = VsEngine(meta: meta, loadout: loadout, pvp: pvp)
        _engine = StateObject(wrappedValue: e)
        _state = ObservedObject(wrappedValue: e.state)
    }

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.11, blue: 0.16).ignoresSafeArea()
            VStack(spacing: 6) {
                topBar
                VsNorthHUD(model: engine.aiModel, state: engine.state)   // leitura do oponente
                lifeBars
                SpriteView(scene: engine.scene)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 1))
                VsControls(model: engine.playerModel, state: engine.state, loadout: loadout, meta: meta,
                           onBuy: { creep, el in engine.scene.buyCreep(creep, element: el, from: .player) })
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            if state.finished { resultOverlay }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onExit) {
                Text("✕").font(.system(size: 20, weight: .bold)).frame(width: 40, height: 40)
                    .background(.white.opacity(0.15)).foregroundColor(.white).clipShape(Circle())
            }
            Spacer()
            Text("⚔️ Vs IA · onda \(state.wave)").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundColor(.white)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
    }

    private var lifeBars: some View {
        HStack(spacing: 10) {
            VsLifePill(model: engine.playerModel, label: "Você", income: state.playerIncome,
                       tint: Color(red: 0.30, green: 0.75, blue: 0.45))
            VsLifePill(model: engine.aiModel, label: "IA 🤖", income: state.aiIncome,
                       tint: Color(red: 0.92, green: 0.35, blue: 0.35))
        }
    }

    private var resultOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(state.playerWon ? "🏆 Você venceu!" : "🤖 A IA venceu")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(state.playerWon ? Color(red: 0.35, green: 0.80, blue: 0.40) : Color(red: 0.92, green: 0.30, blue: 0.32))
                Text("Onda \(state.wave)").font(.system(size: 16, weight: .bold)).foregroundColor(.white.opacity(0.8))
                if state.playerWon && state.creditsEarned > 0 {
                    Text("🪙 +\(state.creditsEarned) créditos").font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.yellow)
                }
                Button(action: onExit) {
                    Text("Voltar ao menu").font(.system(size: 18, weight: .heavy, design: .rounded))
                        .frame(maxWidth: 260, minHeight: 52)
                        .background(Color(red: 0.25, green: 0.55, blue: 0.95)).foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }.padding(28)
        }
    }
}

private struct VsLifePill: View {
    @ObservedObject var model: GameModel
    let label: String
    let income: Int
    let tint: Color
    var body: some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(tint)
            Spacer(minLength: 2)
            Text("❤️\(max(0, model.lives))").font(.system(size: 13, weight: .bold)).foregroundColor(.white).monospacedDigit()
            Text("💰\(model.gold)").font(.system(size: 12, weight: .bold)).foregroundColor(.yellow).monospacedDigit()
            Text("📈\(income)/s").font(.system(size: 11, weight: .heavy)).foregroundColor(.cyan).monospacedDigit()
        }
        .padding(.horizontal, 9).padding(.vertical, 6).frame(maxWidth: .infinity)
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// HUD de leitura do NORTE: torres do oponente (elemento+papel), renda passiva e onda.
private struct VsNorthHUD: View {
    @ObservedObject var model: GameModel
    @ObservedObject var state: VsState
    var body: some View {
        HStack(spacing: 6) {
            Text("🤖").font(.system(size: 13))
            HStack(spacing: 3) {
                if state.aiTowers.isEmpty {
                    Text("montando…").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                } else {
                    ForEach(state.aiTowers) { t in
                        Text(t.icon).font(.system(size: 14))
                    }
                }
            }
            Spacer(minLength: 2)
            Text("📈\(state.aiIncome)/s").font(.system(size: 11, weight: .heavy)).foregroundColor(.cyan).monospacedDigit()
            Text("🌊\(state.wave)").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.8)).monospacedDigit()
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color(red: 0.35, green: 0.15, blue: 0.18).opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// Barra das 5 torres do loadout: escolha uma e toque num slot pra colocar (pode repetir);
/// toque numa torre sua pra dar upgrade. Botão Auto On liga a IA no seu lado.
private struct VsControls: View {
    @ObservedObject var model: GameModel
    @ObservedObject var state: VsState
    let loadout: [Int]
    @ObservedObject var meta: MetaProgress
    let onBuy: (VsCreep, Element?) -> Void
    @State private var pickElemFor: Bool = false   // Elemental → escolher elemento

    var body: some View {
        VStack(spacing: 6) {
            // MERCADO DE CREEPS: enviar é INVESTIMENTO (custo → renda passiva permanente).
            HStack(spacing: 5) {
                creepButton(.corredor); creepButton(.tanque); creepButton(.enxame)
                Button { pickElemFor.toggle() } label: { creepLabel(.elemental) }
                Spacer(minLength: 2)
                Button { model.autoPlay.toggle() } label: {
                    Text(model.autoPlay ? "🤖ON" : "🤖").font(.system(size: 12, weight: .heavy, design: .rounded))
                        .frame(minHeight: 44).padding(.horizontal, 8)
                        .background(model.autoPlay ? Color(red: 0.35, green: 0.80, blue: 0.40) : .black.opacity(0.4))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }
            if pickElemFor {   // escolha do elemento do creep Elemental
                HStack(spacing: 4) {
                    ForEach(Element.allCases, id: \.self) { e in
                        Button { onBuy(.elemental, e); pickElemFor = false } label: {
                            Text(e.icon).font(.system(size: 18)).frame(maxWidth: .infinity, minHeight: 34)
                                .background(e.color.opacity(0.45)).clipShape(RoundedRectangle(cornerRadius: 8))
                                .opacity(model.gold >= VsCreep.elemental.cost ? 1 : 0.4)
                        }.disabled(model.gold < VsCreep.elemental.cost)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(loadout, id: \.self) { id in
                    let spec = TowerCatalog.spec(id)
                    let on = model.selected == id
                    let used = state.playerPlaced.contains(id)      // já em campo → não repete
                    Button { if !used { model.selected = id } } label: {
                        VStack(spacing: 1) {
                            Text(used ? "em campo" : spec.role.nome)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(used ? .green : .white.opacity(0.75))
                            Text(spec.icon).font(.system(size: 18))
                            Text(spec.nome).font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                            Text("💰\(spec.cost)").font(.system(size: 10, weight: .bold))
                                .foregroundColor(model.gold >= spec.cost ? .white : .red)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .opacity(used ? 0.45 : 1)
                        .background(on ? Color(red: 0.25, green: 0.55, blue: 0.95) : .black.opacity(0.4))
                        .overlay(alignment: .topTrailing) {
                            if used { Text("✓").font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
                                .padding(2).background(Circle().fill(.green)).offset(x: 2, y: -2) }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(on ? 0.95 : 0.2), lineWidth: 2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }.disabled(used)
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
    }

    private func creepButton(_ c: VsCreep) -> some View {
        Button { onBuy(c, nil) } label: { creepLabel(c) }.disabled(model.gold < c.cost)
    }
    private func creepLabel(_ c: VsCreep) -> some View {
        let ok = model.gold >= c.cost
        return VStack(spacing: 0) {
            Text(c.icon).font(.system(size: 16))
            Text("💰\(c.cost)").font(.system(size: 9, weight: .bold)).foregroundColor(ok ? .white : .red)
            Text("+\(c.income)/s").font(.system(size: 8, weight: .heavy)).foregroundColor(.cyan)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(ok ? Color(red: 0.85, green: 0.35, blue: 0.55).opacity(0.75) : .black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
