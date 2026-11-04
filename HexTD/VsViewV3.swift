import SwiftUI
import SpriteKit
import Combine

final class VsV3Engine: ObservableObject {
    let state = VsV3State()
    let scene: VsSceneV3
    private var cancellable: AnyCancellable?
    init(meta: MetaProgress, loadout: [String]) {
        let palette = loadout.isEmpty ? VsCatalog.towers.prefix(5).map { $0.id } : loadout   // as 5 do loadout
        scene = VsSceneV3(meta: meta, state: state, palette: palette,
                          size: CGSize(width: 390, height: 680))
        // encaminha as mudanças do state pro engine → a View observa SÓ o engine (@StateObject estável)
        // e re-renderiza quando o state muda. Sem isto, o binding se perdia e o HUD/vitória travavam.
        cancellable = state.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
}

/// Loadout salvo (reaproveitado entre partidas) via UserDefaults.
enum VsLoadoutStore {
    private static let key = "hextd.vs.loadout"
    static func save(_ ids: [String]) { UserDefaults.standard.set(ids, forKey: key) }
    static func load() -> [String]? {
        guard let ids = UserDefaults.standard.stringArray(forKey: key) else { return nil }
        let valid = ids.filter { VsCatalog.spec($0) != nil }
        return valid.count == 5 ? valid : nil     // só reaproveita se ainda tem 5 válidas
    }
}

/// Fluxo do Vs v3: escolhe um LOADOUT de 5 torres (salvo e reaproveitado), depois joga com elas.
struct VsFlowV3: View {
    @ObservedObject var meta: MetaProgress
    let onExit: () -> Void
    @State private var loadout: [String]? = VsLoadoutStore.load()   // já vem preenchido se houver salvo
    @State private var runId = 0

    var body: some View {
        if let lo = loadout {
            VsViewV3(meta: meta, loadout: lo, onExit: onExit, onRestart: { runId += 1 },
                     onChangeLoadout: { loadout = nil })
                .id(runId)
        } else {
            VsLoadoutView(onExit: onExit, onStart: { VsLoadoutStore.save($0); loadout = $0; runId += 1 })
        }
    }
}

/// Modo Vs v3 (spawn/merge + combate redesenhado). Toque num hex do seu lado (sul) pra spawnar
/// a torre selecionada (nasce Comum); toque numa igual pra FUNDIR (sobe estrela).
struct VsViewV3: View {
    @ObservedObject var meta: MetaProgress
    let loadout: [String]
    let onExit: () -> Void
    let onRestart: () -> Void
    let onChangeLoadout: () -> Void
    @StateObject private var engine: VsV3Engine
    private var state: VsV3State { engine.state }   // fonte única (a View observa o engine, estável)
    @State private var selected: String
    @State private var auto = false

    init(meta: MetaProgress, loadout: [String], onExit: @escaping () -> Void,
         onRestart: @escaping () -> Void = {}, onChangeLoadout: @escaping () -> Void = {}) {
        self.meta = meta; self.loadout = loadout; self.onExit = onExit
        self.onRestart = onRestart; self.onChangeLoadout = onChangeLoadout
        _engine = StateObject(wrappedValue: VsV3Engine(meta: meta, loadout: loadout))   // criado 1× só
        _selected = State(initialValue: loadout.first ?? "fire_str")
    }

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.11, blue: 0.16).ignoresSafeArea()
            VStack(spacing: 6) {
                topBar
                lifeBars
                SpriteView(scene: engine.scene)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 1))
                palette
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            if !state.bossBanner.isEmpty { bossBanner }
            if state.finished { resultOverlay }
        }
    }

    private var bossBanner: some View {
        VStack(spacing: 8) {
            Text("⚠️ ONDA DE BOSS").font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.yellow).tracking(2)
            Text(state.bossBanner).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundColor(.white)
            Text(state.bossBannerDesc).font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85)).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 26).padding(.vertical, 20)
        .background(Color(red: 0.5, green: 0.08, blue: 0.12).opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.yellow.opacity(0.8), lineWidth: 2))
        .shadow(radius: 12)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state.bossBanner)
    }

    private var topBar: some View {
        HStack {
            Button(action: onExit) {
                Text("✕").font(.system(size: 20, weight: .bold)).frame(width: 40, height: 40)
                    .background(.white.opacity(0.15)).foregroundColor(.white).clipShape(Circle())
            }
            Spacer()
            Text("⚔️ onda \(state.wave)\(state.waveElementIcon.isEmpty ? "" : " · 70% \(state.waveElementIcon)")").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundColor(.white)
            Spacer()
            Button {
                auto.toggle(); engine.scene.playerAuto = auto
            } label: {
                HStack(spacing: 3) {
                    Text("🤖").font(.system(size: 13))
                    Text(auto ? "ON" : "AUTO").font(.system(size: 11, weight: .heavy, design: .rounded))
                }
                .frame(height: 40).padding(.horizontal, 9)
                .background(auto ? Color(red: 0.35, green: 0.80, blue: 0.40) : .white.opacity(0.15))
                .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var lifeBars: some View {
        HStack(spacing: 10) {
            pill("Você", "❤️\(state.playerLives)  💰\(state.playerGold)", Color(red:0.3,green:0.75,blue:0.45))
            pill("IA 🤖", "❤️\(state.aiLives)", Color(red:0.92,green:0.35,blue:0.35))
        }
    }
    private func pill(_ l: String, _ v: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(l).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(tint)
            Spacer(minLength: 2)
            Text(v).font(.system(size: 13, weight: .bold)).foregroundColor(.white).monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity)
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }

    private var palette: some View {
        VStack(spacing: 6) {
            Text("Toque hex vazio: construir · torre→igual: FUNDIR (⭐) · toque a torre: VENDER 💰")
                .font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.55))
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 6) {
                ForEach(loadout.compactMap { VsCatalog.spec($0) }, id: \.id) { spec in
                    let on = selected == spec.id
                    Button { select(spec.id) } label: {
                        VStack(spacing: 2) {
                            Text(VsElemIcon.icon(spec.element)).font(.system(size: 20))
                            Text(spec.name).font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.65)
                            Text(spec.role == "striker" ? "▲" : spec.role == "blaster" ? "⬢" : "■")
                                .font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.7))
                            Text("💰\(spec.cost)").font(.system(size: 11, weight: .bold))
                                .foregroundColor(state.playerGold >= spec.cost ? .white : .red)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(on ? Color(red:0.25,green:0.55,blue:0.95) : .black.opacity(0.45))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(on ? 0.95 : 0.2), lineWidth: on ? 3 : 2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(10).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
    }

    private func select(_ id: String) { selected = id; engine.scene.selectedSpec = id }

    private var resultOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(state.playerWon ? "🏆" : "💀").font(.system(size: 52))
                Text(state.playerWon ? "VITÓRIA!" : "DERROTA")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(state.playerWon ? Color(red:0.35,green:0.85,blue:0.45) : Color(red:0.92,green:0.3,blue:0.32))
                Text(state.playerWon ? "Você derrotou a IA! 🤖💥" : "A IA passou por suas defesas.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.85))
                Text("❤️ Você \(state.playerLives)   ·   🤖 IA \(state.aiLives)   ·   Onda \(state.wave)")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.7)).monospacedDigit()
                if state.playerWon && state.creditsEarned > 0 {
                    Text("🪙 +\(state.creditsEarned) créditos").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundColor(.yellow)
                }
                Button(action: onRestart) {
                    Text("🔁 Jogar de novo").font(.system(size: 18, weight: .heavy, design: .rounded))
                        .frame(maxWidth: 260, minHeight: 52).background(Color(red:0.30,green:0.72,blue:0.42))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Button(action: onChangeLoadout) {
                    Text("🎛️ Trocar loadout").font(.system(size: 16, weight: .heavy, design: .rounded))
                        .frame(maxWidth: 260, minHeight: 46).background(.white.opacity(0.16))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Button(action: onExit) {
                    Text("Voltar ao menu").font(.system(size: 18, weight: .heavy, design: .rounded))
                        .frame(maxWidth: 260, minHeight: 52).background(Color(red:0.25,green:0.55,blue:0.95))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }.padding(28)
        }
        .onAppear { VsLog.write("RESULT OVERLAY onAppear won=\(state.playerWon) finished=\(state.finished)") }
    }
}

/// Ícone/cor por elemento (string do catálogo).
enum VsElemIcon {
    static func icon(_ el: String) -> String {
        switch el { case "fire": "🔥"; case "water": "💧"; case "ice": "❄️"; case "phys": "🗡️"
                    case "poison": "☠️"; case "arcane": "🔮"; default: "🌿" }
    }
    static func color(_ el: String) -> Color {
        switch el { case "fire": .orange; case "water": .blue; case "ice": .cyan; case "phys": .gray
                    case "poison": .green; case "arcane": .purple; default: Color(red:0.2,green:0.65,blue:0.4) }
    }
}

/// Seleção de LOADOUT: escolha 5 das 21 torres antes da partida.
struct VsLoadoutView: View {
    let onExit: () -> Void
    let onStart: ([String]) -> Void
    @State private var picked: [String] = VsLoadoutStore.load() ?? []   // pré-preenche com o salvo
    private let cap = 5
    private let order = ["fire","water","ice","phys","poison","arcane","nature"]

    var body: some View {
        ZStack {
            Color(red:0.10,green:0.11,blue:0.16).ignoresSafeArea()
            VStack(spacing: 10) {
                HStack {
                    Button(action: onExit) {
                        Text("✕").font(.system(size: 20, weight: .bold)).frame(width: 40, height: 40)
                            .background(.white.opacity(0.15)).foregroundColor(.white).clipShape(Circle())
                    }
                    Spacer()
                    Text("⚔️ Loadout Vs").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(.white)
                    Spacer()
                    Text("\(picked.count)/\(cap)").font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(picked.count == cap ? Color(red:0.35,green:0.85,blue:0.45) : .yellow)
                        .frame(width: 44)
                }
                Text("Escolha 5 torres pra levar pra batalha").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(order, id: \.self) { el in
                            VStack(spacing: 5) {
                                HStack(spacing: 5) {
                                    Text(VsElemIcon.icon(el)).font(.system(size: 15))
                                    Rectangle().fill(VsElemIcon.color(el).opacity(0.4)).frame(height: 1)
                                }
                                HStack(spacing: 8) {
                                    ForEach(VsCatalog.towers.filter { $0.element == el }, id: \.id) { spec in cell(spec) }
                                }
                            }
                        }
                    }.padding(.vertical, 4)
                }
                Button { if picked.count == cap { onStart(picked) } } label: {
                    Text(picked.count == cap ? "Começar ⚔️" : "Escolha mais \(cap - picked.count)")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(picked.count == cap ? Color(red:0.30,green:0.72,blue:0.42) : .white.opacity(0.12))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                }.disabled(picked.count != cap)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private func cell(_ spec: VsTowerSpec) -> some View {
        let idx = picked.firstIndex(of: spec.id)
        let on = idx != nil
        return Button { toggle(spec.id) } label: {
            VStack(spacing: 1) {
                Text(spec.role == "striker" ? "▲ Rápida" : spec.role == "blaster" ? "⬢ Área" : "■ Suporte")
                    .font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.7))
                Text(spec.name).font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.65)
                Text("💰\(spec.cost)").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(on ? VsElemIcon.color(spec.element).opacity(0.55) : .black.opacity(0.4))
            .overlay(alignment: .topTrailing) {
                if let i = idx {
                    Text("\(i+1)").font(.system(size: 10, weight: .heavy)).foregroundColor(.black)
                        .frame(width: 16, height: 16).background(.white).clipShape(Circle()).padding(3)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(on ? .white : .white.opacity(0.2), lineWidth: on ? 2.5 : 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
    }
    private func toggle(_ id: String) {
        if let i = picked.firstIndex(of: id) { picked.remove(at: i) }
        else if picked.count < cap { picked.append(id) }
    }
}
