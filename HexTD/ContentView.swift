import SwiftUI
import SpriteKit

/// Motor único, três portas de entrada (GDD §2). No M1 os três modos usam o
/// mesmo gerador; a curadoria de Campanha e o leaderboard do Endless vêm depois.
enum Mode: String { case campanha = "Campanha", rogue = "Rogue", endless = "Endless", vs = "Vs IA" }

struct ContentView: View {
    enum Screen { case menu, campaign, loadout, armory, summon, settings, game, vsPvP }
    @State private var screen: Screen = .menu
    @State private var activeMode: Mode = .endless
    @State private var activeStage: Int? = nil     // índice de fase (Campanha); nil nos outros
    @State private var runToken = UUID()
    @StateObject private var meta = MetaProgress()

    private var activeConfig: GameConfig {
        if let s = activeStage { return Campaign.stages[s] }
        return activeMode == .rogue ? .rogue : .endless
    }

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.11, blue: 0.16).ignoresSafeArea()
            switch screen {
            case .menu:
                MenuView(meta: meta,
                         onCampaign: { screen = .campaign },
                         onRogue:    { activeStage = nil; activeMode = .rogue; start() },
                         onEndless:  { activeStage = nil; activeMode = .endless; start() },
                         onVs:       { activeStage = nil; activeMode = .vs; start() },
                         onPvP:      { screen = .vsPvP },
                         onArmory:   { screen = .armory },
                         onSummon:   { screen = .summon },
                         onSettings: { screen = .settings })
            case .campaign:
                CampaignView(meta: meta, onExit: { screen = .menu },
                             onPick: { i in
                                 activeStage = i
                                 // Fase com partida salva → retoma direto; senão, escolhe loadout.
                                 if meta.hasRun(stage: i) { activeMode = .campanha; start() }
                                 else { screen = .loadout }
                             })
            case .loadout:
                LoadoutView(meta: meta, stage: activeStage ?? 0,
                            onExit: { screen = .campaign },
                            onPlay: { meta.clearRun(stage: activeStage ?? 0); activeMode = .campanha; start() })
            case .armory:
                ArmoryView(meta: meta, onExit: { screen = .menu })
            case .summon:
                SummonView(meta: meta, onExit: { screen = .menu })
            case .vsPvP:
                VsPvPFlow(meta: meta, onExit: { screen = .menu })
            case .settings:
                SettingsView(meta: meta, onExit: { screen = .menu })
            case .game:
                if activeMode == .vs {
                    VsFlowV3(meta: meta, onExit: { screen = .menu })   // loadout de 5 → partida v3
                        .id(runToken)
                } else if activeMode == .rogue {
                    RogueView(meta: meta, onExit: { screen = .menu })
                        .id(runToken)
                } else {
                    GameView(config: activeConfig, mode: activeMode, stage: activeStage, meta: meta,
                             onExit: { screen = activeStage != nil ? .campaign : .menu },
                             onNext: campaignNext)
                        .id(runToken)
                }
            }
        }
        // Harness de teste: HEXTD_AUTOTEST=1 entra direto no Endless (a cena liga
        // auto-mode + 10× em didMove). Sem a env var, comportamento normal.
        .onAppear {
            Audio.shared.configure(soundOn: meta.soundOn, musicOn: meta.musicOn)
            GameCenter.shared.authenticate()   // login Game Center (necessário pro PvP)
            if ProcessInfo.processInfo.environment["HEXTD_CAMPTEST"] != nil, screen == .menu {
                meta.debugUnlockAll(); meta.debugSetLoadout([0, 3, 6, 12, 17])  // sem Físico
                activeStage = Int(ProcessInfo.processInfo.environment["HEXTD_STAGE"] ?? "0") ?? 0
                activeMode = .campanha; start()
            } else if ProcessInfo.processInfo.environment["HEXTD_AUTOTEST"] != nil, screen == .menu {
                activeStage = nil
                activeMode = ProcessInfo.processInfo.environment["HEXTD_ROGUE"] != nil ? .rogue : .endless
                start()
            }
            if ProcessInfo.processInfo.environment["HEXTD_ARMORY"] != nil, screen == .menu {
                screen = .armory   // harness: abre a Armory direto pra inspeção
            }
            if ProcessInfo.processInfo.environment["HEXTD_CAMPAIGN"] != nil, screen == .menu {
                screen = .campaign
            }
            if ProcessInfo.processInfo.environment["HEXTD_LOADOUT"] != nil, screen == .menu {
                activeStage = 0; screen = .loadout
            }
            if ProcessInfo.processInfo.environment["HEXTD_SUMMON"] != nil, screen == .menu {
                meta.addCredits(500); screen = .summon
            }
            #if DEBUG
            if let n = ProcessInfo.processInfo.environment["HEXTD_GIVEADV"], let c = Int(n), screen == .menu {
                meta.debugGrantSummons(.avancado, count: c)   // concede c avançados grátis
            }
            #endif
            if ProcessInfo.processInfo.environment["HEXTD_SETTINGS"] != nil, screen == .menu {
                screen = .settings
            }
            if ProcessInfo.processInfo.environment["HEXTD_UNLOCKTEST"] != nil, screen == .menu {
                _ = meta.claimFreeBasic(); _ = meta.claimFreeBasic(); _ = meta.claimFreeBasic()
                screen = .loadout
            }
            if ProcessInfo.processInfo.environment["HEXTD_ROGUE"] != nil, screen == .menu {
                activeStage = nil; activeMode = .rogue; start()   // boss a cada 5 ondas
            }
        }
    }

    private func start() { runToken = UUID(); screen = .game }

    /// Vitória → próxima fase passa pela seleção de loadout (escolha antes de entrar).
    private func campaignNext() {
        if let s = activeStage, s + 1 < Campaign.count {
            activeStage = s + 1; screen = .loadout
        } else {
            screen = .campaign   // acabou a Campanha
        }
    }
}

struct MenuView: View {
    @ObservedObject var meta: MetaProgress
    let onCampaign: () -> Void
    let onRogue: () -> Void
    let onEndless: () -> Void
    let onVs: () -> Void
    let onPvP: () -> Void
    let onArmory: () -> Void
    let onSummon: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                topIcon("⚙️", action: onSettings)
            }.padding(.horizontal, 16).padding(.top, 6)
            Spacer()
            menuStack
            Spacer()
        }
    }

    private func topIcon(_ icon: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Text(icon).font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12)).clipShape(Circle())
                if badge > 0 {
                    Text("\(badge)").font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
                        .padding(4).background(Circle().fill(.red)).offset(x: 4, y: -4)
                }
            }
        }
    }

    private var menuStack: some View {
        VStack(spacing: 20) {
            Text("⬡ HEX TD").font(.system(size: 50, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text("🪙 \(meta.credits) créditos")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(.black.opacity(0.4), in: Capsule())
            VStack(spacing: 14) {
                modeButton("Campanha", subtitle: "\(min(meta.campaignUnlocked + 1, Campaign.count))/\(Campaign.count) fases", action: onCampaign)
                modeButton("Rogue", subtitle: "idle · torre central · sobreviva", action: onRogue)
                modeButton("Endless", subtitle: meta.endlessBest > 0 ? "recorde: onda \(meta.endlessBest)" : "sobreviva o máximo", action: onEndless)
                modeButton("⚔️ Vs IA", subtitle: "dispute contra a IA · quem sobrevive mais", action: onVs)
                modeButton("👥 Vs Jogador", subtitle: "PvP online · Game Center", action: onPvP)
                HStack(spacing: 12) {
                    outlineButton("✨ Summon", action: onSummon)
                    outlineButton("🗼 Torres", action: onArmory)
                }
            }.padding(.top, 8)
        }.padding()
    }

    private func outlineButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(maxWidth: 144, minHeight: 52)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.4), lineWidth: 2))
                .foregroundColor(.white)
        }
    }

    private func modeButton(_ title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 23, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 12, weight: .medium)).opacity(0.8)
            }
            .frame(maxWidth: 300, minHeight: 64)
            .background(Color(red: 0.25, green: 0.55, blue: 0.95))
            .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

/// Cabeçalho padrão de tela: voltar + título.
struct NavHeader: View {
    let title: String
    let onExit: () -> Void
    var body: some View {
        HStack {
            Button(action: onExit) {
                Text("←").font(.system(size: 24, weight: .bold))
                    .frame(width: 44, height: 44).background(.white.opacity(0.15))
                    .foregroundColor(.white).clipShape(Circle())
            }
            Spacer()
            Text(title).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundColor(.white)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }
}

/// Configurações: som, música e limite de FPS (30/60/120).
struct SettingsView: View {
    @ObservedObject var meta: MetaProgress
    let onExit: () -> Void
    @State private var confirmReset = false
    @State private var didReset = false

    var body: some View {
        VStack(spacing: 16) {
            NavHeader(title: "Configurações", onExit: onExit)
            toggleRow("🔊 Som", meta.soundOn) { meta.setSound($0); Audio.shared.setSound($0); if $0 { Audio.shared.sfx("tap") } }
            toggleRow("🎵 Música", meta.musicOn) { meta.setMusic($0); Audio.shared.setMusic($0) }
            VStack(alignment: .leading, spacing: 8) {
                Text("Limite de FPS").font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                HStack(spacing: 8) {
                    ForEach([30, 60, 120], id: \.self) { fps in
                        let on = meta.frameLimit == fps
                        Button { meta.setFrameLimit(fps) } label: {
                            Text("\(fps)").font(.system(size: 17, weight: .heavy, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(on ? Color(red: 0.25, green: 0.55, blue: 0.95) : .black.opacity(0.4))
                                .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding(14).background(.black.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()

            VStack(spacing: 8) {
                Button { confirmReset = true } label: {
                    Text("🗑️ Resetar progressão").font(.system(size: 16, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(red: 0.80, green: 0.25, blue: 0.25))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if didReset {
                    Text("✅ Progressão zerada.").font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    Text("Apaga torres, cards, campanha e créditos. Áudio e FPS são mantidos.")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            }
        }.padding(.horizontal, 16).padding(.top, 8)
        .alert("Resetar progressão?", isPresented: $confirmReset) {
            Button("Cancelar", role: .cancel) {}
            Button("Resetar tudo", role: .destructive) { meta.resetProgress(); didReset = true }
        } message: {
            Text("Isso apaga TODA a sua progressão (torres, cards, campanha e créditos). Não dá pra desfazer.")
        }
    }

    private func toggleRow(_ label: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { on }, set: set)) {
            Text(label).font(.system(size: 17, weight: .bold)).foregroundColor(.white)
        }
        .tint(Color(red: 0.35, green: 0.80, blue: 0.40))
        .padding(14).background(.black.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Menu de Summon (§economia): gasta créditos (ganhos jogando) pra invocar cartas
/// de torre aleatórias. Básico (100 = 10 vitórias camp / 5 rogue) rende 1–10 cartas;
/// Avançado (400 = 40 camp / 20 rogue) rende 7–20.
struct SummonView: View {
    @ObservedObject var meta: MetaProgress
    let onExit: () -> Void
    @State private var result: [(Int, Int)] = []
    @State private var lastLabel: String = ""
    @State private var elemPick: Element = .fisico   // elemento escolhido no Elemental

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onExit) {
                    Text("←").font(.system(size: 24, weight: .bold))
                        .frame(width: 44, height: 44).background(.white.opacity(0.15))
                        .foregroundColor(.white).clipShape(Circle())
                }
                Spacer()
                Text("Summon").font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("🪙 \(meta.credits)").font(.system(size: 15, weight: .bold))
                    .foregroundColor(.yellow).frame(minWidth: 44)
            }
            if meta.godMode {
                Text("😇 God Mode — summons ilimitados")
                    .font(.system(size: 12, weight: .heavy)).foregroundColor(.yellow)
            } else {
                Text("Ganháveis hoje: 🪙 \(meta.creditsRemainingToday) / \(MetaProgress.dailyCreditCap)")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.55))
            }
            ScrollView {
                VStack(spacing: 14) {
                    freeSection
                    summonCard(.basico)
                    summonCard(.avancado)
                    elementalCard
                    if !result.isEmpty { resultView }
                }
            }
        }.padding(.horizontal, 16).padding(.top, 8)
    }

    // Summons grátis diários (§daily): avançado 1×/dia, básico 5×/dia (10min entre cada).
    private var freeSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: 10) {
                Text("🎁 Grátis diário").font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                freeRow("Avançado grátis", sub: "1 por dia",
                        available: meta.freeAdvancedAvailable,
                        until: meta.nextDailyReset,
                        color: Color(red: 0.55, green: 0.35, blue: 0.90)) {
                    if let r = meta.claimFreeAdvanced() { result = r; lastLabel = "Avançado grátis" }
                }
                freeRow("Básico grátis (\(meta.freeBasicRemaining)/\(MetaProgress.freeBasicPerDay))",
                        sub: meta.freeBasicRemaining > 0 ? "10min entre cada" : "esgotado — volta no reset",
                        available: meta.freeBasicAvailable,
                        until: meta.nextBasicAt ?? meta.nextDailyReset,
                        color: Color(red: 0.25, green: 0.55, blue: 0.95)) {
                    if let r = meta.claimFreeBasic() { result = r; lastLabel = "Básico grátis" }
                }
            }
            .padding(12).background(.black.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func freeRow(_ title: String, sub: String, available: Bool, until: Date,
                         color: Color, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                Text(sub).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            if available {
                Button(action: action) {
                    Text("Coletar").font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 16).frame(minHeight: 40)
                        .background(color).foregroundColor(.white).clipShape(Capsule())
                }
            } else {
                Text("⏳ \(timeString(until: until))").font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }

    private func timeString(until date: Date) -> String {
        let s = max(0, Int(date.timeIntervalSinceNow))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%dh%02dm", h, m) : String(format: "%02d:%02d", m, sec)
    }

    private func summonCard(_ s: MetaProgress.Summon) -> some View {
        let can = meta.canSummon(s)
        return VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.nome).font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(s.desc).font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Text("🪙 \(s.cost)").font(.system(size: 18, weight: .bold))
                    .foregroundColor(can ? .yellow : .red)
            }
            Button { if let r = meta.summon(s) { result = r; lastLabel = s.nome } } label: {
                Text("Invocar ✨").font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(can ? Color(red: 0.55, green: 0.35, blue: 0.90) : Color.white.opacity(0.12))
                    .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
            }.disabled(!can)
        }
        .padding(14).background(.black.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // Summon Elemental: só cartas do elemento escolhido (3–6). Custo = 2 básicos.
    private var elementalCard: some View {
        let can = meta.canSummonElement
        return VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Elemental").font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(MetaProgress.elementalRange.lowerBound)–\(MetaProgress.elementalRange.upperBound) cartas do elemento escolhido")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Text("🪙 \(MetaProgress.elementalCost)").font(.system(size: 18, weight: .bold))
                    .foregroundColor(can ? .yellow : .red)
            }
            HStack(spacing: 6) {
                ForEach(Element.allCases, id: \.self) { e in
                    let on = elemPick == e
                    Button { elemPick = e } label: {
                        Text(e.icon).font(.system(size: 19))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(e.color.opacity(on ? 0.6 : 0.18))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(e.color.opacity(on ? 1 : 0.3), lineWidth: on ? 3 : 2))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Button {
                if let r = meta.summonElement(elemPick) { result = r; lastLabel = "Elemental \(elemPick.nome)" }
            } label: {
                Text("Invocar \(elemPick.icon) ✨").font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(can ? Color(red: 0.55, green: 0.35, blue: 0.90) : Color.white.opacity(0.12))
                    .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
            }.disabled(!can)
        }
        .padding(14).background(.black.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var resultView: some View {
        VStack(spacing: 8) {
            Text("Cartas obtidas — \(lastLabel)")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            ScrollView {
                let cols = [GridItem(.adaptive(minimum: 72), spacing: 10)]
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(result, id: \.0) { pair in
                        let spec = TowerCatalog.spec(pair.0)
                        VStack(spacing: 2) {
                            Text(spec.icon).font(.system(size: 24))
                            Text(spec.nome).font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                            Text("🃏 +\(pair.1)").font(.system(size: 11, weight: .heavy))
                                .foregroundColor(.green)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(spec.element.color.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(12).background(.black.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Seleção de fase da Campanha (GDD §3): fases curadas, desbloqueio sequencial.
struct CampaignView: View {
    @ObservedObject var meta: MetaProgress
    let onExit: () -> Void
    let onPick: (Int) -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: onExit) {
                    Text("←").font(.system(size: 24, weight: .bold))
                        .frame(width: 44, height: 44).background(.white.opacity(0.15))
                        .foregroundColor(.white).clipShape(Circle())
                }
                Spacer()
                Text("Campanha").font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            Text("\(min(meta.campaignUnlocked + 1, Campaign.count))/\(Campaign.count) fases")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.6))
            ScrollView {
                let cols = [GridItem(.adaptive(minimum: 62), spacing: 12)]
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(0..<Campaign.count, id: \.self) { i in
                        let unlocked = meta.isStageUnlocked(i)
                        let done = i < meta.campaignUnlocked
                        let dom = Element.allCases[i % Element.allCases.count]   // elemento tema
                        Button { if unlocked { onPick(i) } } label: {
                            ZStack(alignment: .topTrailing) {
                                Text("\(i + 1)")
                                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                                    .frame(width: 62, height: 62)
                                    .background(unlocked ? Color(red: 0.25, green: 0.55, blue: 0.95) : Color.gray.opacity(0.3))
                                    .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(alignment: .bottomLeading) {
                                        Text(dom.icon).font(.system(size: 13)).padding(3).opacity(unlocked ? 1 : 0.5)
                                    }
                                if done { Text("⭐️").font(.system(size: 15)).offset(x: 4, y: -4) }
                                else if !unlocked { Text("🔒").font(.system(size: 13)).offset(x: 3, y: -3) }
                            }
                        }.disabled(!unlocked)
                    }
                }.padding(.vertical, 4)
            }
        }.padding(.horizontal, 16).padding(.top, 8)
    }
}

/// Seleção de loadout da Campanha: escolher 5 das 21 torres ANTES de entrar na fase.
/// Só essas 5 ficam disponíveis in-run (o Endless usa todas). Mostra a raridade de
/// cada torre pra ajudar a escolher as mais evoluídas.
struct LoadoutView: View {
    @ObservedObject var meta: MetaProgress
    let stage: Int
    let onExit: () -> Void
    let onPlay: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onExit) {
                    Text("←").font(.system(size: 24, weight: .bold))
                        .frame(width: 44, height: 44).background(.white.opacity(0.15))
                        .foregroundColor(.white).clipShape(Circle())
                }
                Spacer()
                VStack(spacing: 0) {
                    Text("Loadout").font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("Fase \(stage + 1)").font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            let dom = Element.allCases[stage % Element.allCases.count]
            HStack(spacing: 6) {
                Text("Inimigos:").font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                Text("\(dom.icon) \(dom.nome)").font(.system(size: 14, weight: .heavy)).foregroundColor(dom.color)
            }
            Text("Escolha até \(MetaProgress.loadoutSize) torres · \(meta.loadoutRaw.count)/\(MetaProgress.loadoutSize)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(meta.loadoutReady ? .green : .white.opacity(0.7))
            HStack(spacing: 5) {
                Text("⭐").font(.system(size: 11))
                Text("Recomendadas: vantagem contra \(dom.nome)")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.yellow.opacity(0.9))
            }
            if !meta.hasAnyUnlocked {
                Spacer()
                VStack(spacing: 8) {
                    Text("🔒 Nenhuma torre desbloqueada").font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Use os Summons grátis pra desbloquear torres.")
                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(Element.allCases, id: \.self) { e in
                            let ids = TowerCatalog.ids(of: e).filter { meta.isUnlocked($0) }
                            let recommended = e.multiplier(against: dom) > 1.0
                            if !ids.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Text(e.icon).font(.system(size: 16))
                                        Text(e.nome).font(.system(size: 14, weight: .heavy, design: .rounded))
                                            .foregroundColor(e.color)
                                        if recommended {
                                            Text("⭐ recomendada").font(.system(size: 10, weight: .heavy))
                                                .foregroundColor(.yellow)
                                        }
                                        Spacer()
                                    }
                                    HStack(spacing: 8) {
                                        ForEach(ids, id: \.self) { id in chip(id, recommended: recommended) }
                                    }
                                }
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }
            Button(action: onPlay) {
                Text("Jogar  ▶").font(.system(size: 20, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(meta.loadoutReady ? Color(red: 0.35, green: 0.80, blue: 0.40)
                                                  : Color.gray.opacity(0.4))
                    .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 16))
            }.disabled(!meta.loadoutReady)
        }.padding(.horizontal, 16).padding(.top, 8)
    }

    private func chip(_ id: Int, recommended: Bool = false) -> some View {
        let spec = TowerCatalog.spec(id)
        let on = meta.inLoadout(id)
        let r = meta.rarity(id)
        // Não deixa adicionar além de 5 (mas sempre deixa remover as marcadas).
        let selectable = on || !meta.loadoutFull
        return Button { meta.toggleLoadout(id) } label: {
            VStack(spacing: 2) {
                Text(spec.icon).font(.system(size: 22))
                Text(spec.nome).font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                Text(r.nome).font(.system(size: 8, weight: .semibold)).foregroundColor(r.color)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .opacity(selectable ? 1 : 0.4)
            .background(on ? Color(red: 0.25, green: 0.55, blue: 0.95) : .black.opacity(0.4))
            .overlay(alignment: .topTrailing) {
                if on { Text("✓").font(.system(size: 12, weight: .heavy)).foregroundColor(.white)
                    .padding(3).background(Circle().fill(.green)).offset(x: 3, y: -3) }
            }
            .overlay(alignment: .topLeading) {
                if recommended { Text("⭐").font(.system(size: 11))
                    .padding(2).offset(x: 1, y: 1) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // Recomendada (vantagem elemental): anel dourado brilhante, mesmo sem estar no loadout.
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(recommended ? Color.yellow : .white.opacity(on ? 0.9 : 0.2),
                        lineWidth: recommended ? 2.5 : 2))
            .shadow(color: recommended ? Color.yellow.opacity(0.6) : .clear, radius: 5)
        }.disabled(!selectable)
    }
}

/// Tela de loadout meta (GDD §4/§6/§7): gasta cards pra subir a raridade de cada
/// torre. A raridade escolhida aqui é levada pra dentro da run (multiplica stats).
struct ArmoryView: View {
    @ObservedObject var meta: MetaProgress
    let onExit: () -> Void
    @State private var filter: Element? = nil     // nil = todos os elementos
    @State private var upgradableOnly = false     // só torres com cards p/ upgrade

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onExit) {
                    Text("←").font(.system(size: 24, weight: .bold))
                        .frame(width: 44, height: 44).background(.white.opacity(0.15))
                        .foregroundColor(.white).clipShape(Circle())
                }
                Spacer()
                Text("Torres").font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            filterBar
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(filter.map { [$0] } ?? Element.allCases, id: \.self) { e in
                        let ids = TowerCatalog.ids(of: e).filter { !upgradableOnly || meta.canAnyUpgrade($0) }
                        if !ids.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Text(e.icon).font(.system(size: 20))
                                    Text(e.nome).font(.system(size: 17, weight: .heavy, design: .rounded))
                                        .foregroundColor(e.color)
                                    Spacer()
                                }
                                ForEach(ids, id: \.self) { id in row(id) }
                            }
                        }
                    }
                }
            }
        }.padding(.horizontal, 16).padding(.top, 8)
    }

    // Barra de filtro: 7 elementos (toca/limpa) + seta ⬆︎ = só torres upgradáveis.
    private var filterBar: some View {
        HStack(spacing: 5) {
            ForEach(Element.allCases, id: \.self) { e in
                let on = filter == e
                Button { filter = (filter == e) ? nil : e } label: {
                    Text(e.icon).font(.system(size: 20))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(on ? e.color.opacity(0.55) : .black.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(e.color.opacity(on ? 1 : 0.25), lineWidth: 2))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            Button { upgradableOnly.toggle() } label: {
                Text("⬆︎").font(.system(size: 19, weight: .heavy))
                    .frame(width: 44, height: 40)
                    .background(upgradableOnly ? Color(red: 0.35, green: 0.80, blue: 0.40) : .black.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(upgradableOnly ? 0.9 : 0.25), lineWidth: 2))
                    .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func row(_ id: Int) -> some View {
        let spec = TowerCatalog.spec(id)
        let r = meta.rarity(id)
        let cards = meta.cardCount(id)
        let cost = r.upgradeCost
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(spec.icon).font(.system(size: 30))
                    .frame(width: 54, height: 54)
                    .background(r.color.opacity(0.30))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(r.color, lineWidth: 2))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(spec.nome).font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(spec.role.nome) · ⚔️\(Int(spec.baseDamage)) · 🎯\(spec.range)\(spec.splash > 0 ? " · 💥" : "")")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
                    Text("\(r.nome) · ×\(String(format: "%.2f", r.statMult)) · 🃏\(cards)")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(r.color)
                }
                Spacer()
            }
            paragonRow(id)
            VStack(spacing: 6) {
                ForEach(Array(spec.abilities.enumerated()), id: \.offset) { idx, a in
                    abilityRow(a, slot: idx, unlocked: r.abilitySlots > idx)
                }
            }
            if let cost {
                Button { meta.upgradeRarity(id) } label: {
                    Text(cards >= cost ? "Subir → \(r.next!.nome)  🃏\(cost)" : "🃏 \(cards)/\(cost)")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(cards >= cost ? r.next!.color : Color.white.opacity(0.12))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                }.disabled(cards < cost)
            } else {
                Text("Mítica — tier máximo").font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(r.color.opacity(0.25)).foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(12).background(.black.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// Paragon (§4): nível de card 0–100 subido com cards; define o teto de estrelas
    /// in-run (nível/4, piso 4). Quanto mais alto, mais o gold sobe a torre na partida.
    private func paragonRow(_ id: Int) -> some View {
        let lvl = meta.cardLevel(id)
        let stars = meta.maxStars(id)
        let cost = meta.cardLevelCost(id)
        let cards = meta.cardCount(id)
        return VStack(spacing: 8) {
            HStack {
                Text("Paragon").font(.system(size: 12, weight: .bold)).foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("nível \(lvl)/\(MetaProgress.cardLevelMax)")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Text("· teto ★\(stars)")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.yellow)
            }
            // Barra de progresso do nível de card.
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(Color.yellow.opacity(0.85))
                        .frame(width: g.size.width * CGFloat(lvl) / CGFloat(MetaProgress.cardLevelMax))
                }
            }.frame(height: 6)
            if !meta.paragonUnlocked(id) {
                Text("🔒 Evolui só após a Mítica").font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(.white.opacity(0.08)).foregroundColor(.white.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if let cost {
                Button { meta.levelUpCard(id) } label: {
                    Text(cards >= cost ? "★ Subir nível  🃏\(cost)" : "🃏 \(cards)/\(cost)")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(cards >= cost ? Color(red: 0.98, green: 0.72, blue: 0.20)
                                                  : Color.white.opacity(0.12))
                        .foregroundColor(cards >= cost ? .black : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }.disabled(cards < cost)
            } else {
                Text("Paragon máximo — teto ★\(stars)").font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(.yellow.opacity(0.2)).foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(10).background(.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Linha de habilidade na Armory (§5): liberada mostra ícone+descrição em cor;
    /// bloqueada fica esmaecida e indica a raridade que a libera.
    private func abilityRow(_ a: TowerAbility, slot: Int, unlocked: Bool) -> some View {
        let unlockR = TowerAbility.unlockRarity(slot: slot)
        return HStack(spacing: 8) {
            Text(unlocked ? a.icon : "🔒").font(.system(size: 16)).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.nome).font(.system(size: 13, weight: .bold))
                    .foregroundColor(unlocked ? .white : .white.opacity(0.45))
                Text(unlocked ? a.desc : "Libera na raridade \(unlockR.nome)")
                    .font(.system(size: 10)).foregroundColor(.white.opacity(unlocked ? 0.6 : 0.35))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background((unlocked ? unlockR.color.opacity(0.16) : Color.white.opacity(0.04)),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}

struct GameView: View {
    let config: GameConfig
    let mode: Mode
    let stage: Int?
    @ObservedObject var meta: MetaProgress
    let onExit: () -> Void
    let onNext: () -> Void
    @StateObject private var model = GameModel()
    @State private var sceneID = UUID()
    @State private var pickElement: Element = .fisico   // elemento aberto no seletor
    @State private var showPause = false
    @State private var showGameSettings = false
    @State private var showSavePrompt = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteView(scene: makeScene(size: geo.size))
                    .id(sceneID).ignoresSafeArea()

                VStack(spacing: 10) {
                    hud
                    controlStrip
                    Spacer()
                    if model.waveReady && model.inspect == nil { startWaveButton }
                    if let insp = model.inspect { inspectPanel(insp) }
                    else { towerBar }
                }.padding(.horizontal, 14).padding(.vertical, 8)

                if model.won { victoryCard }
                else if model.gameOver { gameOverCard }
                if showPause { pauseOverlay }
                if showGameSettings {
                    SettingsView(meta: meta, onExit: { showGameSettings = false; showPause = true })
                }
                if showSavePrompt { savePromptCard }
            }
        }
        .onChange(of: model.won) { _, won in
            if won, let s = stage { meta.unlockStage(s + 1); meta.clearRun(stage: s) }  // vitória: libera próxima + apaga o save
        }
        .onAppear {
            // Seleciona uma torre válida no início: loadout na Campanha, desbloqueada no resto.
            let first = mode == .campanha ? meta.loadoutRaw.first : meta.unlockedIds.first
            if let first { model.selected = first; pickElement = TowerCatalog.spec(first).element }
            #if DEBUG
            model.autoPlay = true   // build pessoal: já entra com Auto ligado em toda fase
            #endif
        }
    }

    private var title: String {
        if let s = stage { return "Fase \(s + 1)" }
        return mode.rawValue
    }

    private var hud: some View {
        HStack(spacing: 7) {
            Button { model.paused = true; showPause = true } label: {
                Text("⏸").font(.system(size: 22, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.15)).foregroundColor(.white).clipShape(Circle())
            }
            stat("💰", "\(model.gold)", valueWidth: 36)
            stat("❤️", "\(model.lives)", valueWidth: 22)
            stat("🌊", config.targetWave.map { "\(model.wave)/\($0)" } ?? "\(model.wave)", valueWidth: 28)
            Spacer(minLength: 2)
            Text(title).font(.system(size: 12, weight: .semibold))
                .lineLimit(1).foregroundColor(.white.opacity(0.55))
                .layoutPriority(-1)          // cede espaço p/ os stats, trunca se faltar
        }
    }

    // Pílula de stat: dígitos monoespaçados + largura reservada → nunca quebra
    // linha nem "oscila" quando o valor muda de tamanho.
    private func stat(_ icon: String, _ v: String, valueWidth: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(icon).font(.system(size: 15))
            Text(v)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit().lineLimit(1)
                .frame(minWidth: valueWidth, alignment: .leading)
                .foregroundColor(.white)
        }
        .fixedSize()
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.black.opacity(0.40), in: Capsule())
    }

    // Ferramentas de teste: velocidade da simulação + IA que joga sozinha.
    /// Velocidade `s` liberada? 1× sempre; 2× via campanha 20 (ou código); 5×/10× só código/god.
    private func speedUnlocked(_ s: Int) -> Bool {
        switch s {
        case 1:      return true
        case 2:      return meta.has2xSpeed
        default:     return meta.hasFastSpeed   // 5× e 10×
        }
    }

    private var controlStrip: some View {
        HStack(spacing: 6) {
            ForEach([1, 2, 5, 10], id: \.self) { s in
                let unlocked = speedUnlocked(s)
                Button {
                    if unlocked { model.speed = s }
                } label: {
                    Text(unlocked ? "\(s)×" : "🔒")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .frame(minWidth: 36, minHeight: 32)
                        .background(model.speed == s ? Color(red: 0.25, green: 0.55, blue: 0.95)
                                                     : .black.opacity(0.4))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                        .opacity(unlocked ? 1 : 0.5)
                }
                .disabled(!unlocked)
            }
            Spacer(minLength: 4)
            if meta.autoUnlocked {
                Button { model.autoPlay.toggle() } label: {
                    HStack(spacing: 4) {
                        Text("🤖").font(.system(size: 14))
                        Text(model.autoPlay ? "AUTO ON" : "AUTO")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                    .frame(minHeight: 32).padding(.horizontal, 12)
                    .background(model.autoPlay ? Color(red: 0.35, green: 0.80, blue: 0.40)
                                               : .black.opacity(0.4))
                    .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var startWaveButton: some View {
        Button { model.doStartWave?() } label: {
            HStack(spacing: 8) {
                Text("▶ Iniciar onda \(model.wave + 1)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                if model.waveBonus > 0 {
                    Text("+💰\(model.waveBonus)")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.22)).clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(red: 0.35, green: 0.80, blue: 0.40))
            .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // Campanha usa só as 5 torres do loadout; Endless usa o seletor completo (21).
    @ViewBuilder private var towerBar: some View {
        if mode == .campanha { campaignBar } else { elementPicker }
    }

    // Barra da Campanha: as 5 torres escolhidas no loadout.
    private var campaignBar: some View {
        HStack(spacing: 8) {
            ForEach(meta.loadoutRaw, id: \.self) { id in
                let spec = TowerCatalog.spec(id)
                let on = model.selected == id
                Button { model.selected = id } label: {
                    VStack(spacing: 1) {
                        Text(spec.icon).font(.system(size: 22))
                        Text(spec.nome).font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                        Text("💰\(spec.cost)").font(.system(size: 11, weight: .bold))
                            .foregroundColor(model.gold >= spec.cost ? .white : .red)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(on ? Color(red: 0.25, green: 0.55, blue: 0.95) : .black.opacity(0.4))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(spec.element.color.opacity(on ? 1 : 0.4), lineWidth: 2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // Seletor in-run (Endless): linha de 7 elementos → 3 torres do elemento aberto.
    private var elementPicker: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Element.allCases, id: \.self) { e in
                    let on = pickElement == e
                    Button {
                        pickElement = e
                        if let first = TowerCatalog.ids(of: e).first(where: { meta.isUnlocked($0) }) { model.selected = first }
                    } label: {
                        Text(e.icon).font(.system(size: 19))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(on ? e.color.opacity(0.55) : .black.opacity(0.4))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(e.color.opacity(on ? 1 : 0.3), lineWidth: 2))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach(TowerCatalog.ids(of: pickElement).filter { meta.isUnlocked($0) }, id: \.self) { id in
                    let spec = TowerCatalog.spec(id)
                    let on = model.selected == id
                    Button { model.selected = id } label: {
                        VStack(spacing: 1) {
                            Text(spec.role.nome).font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.75))
                            Text(spec.nome).font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                            Text("💰\(spec.cost)").font(.system(size: 11, weight: .bold))
                                .foregroundColor(model.gold >= spec.cost ? .white : .red)
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(on ? Color(red: 0.25, green: 0.55, blue: 0.95) : .black.opacity(0.4))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(on ? 0.9 : 0.2), lineWidth: 2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    // Painel de inspeção in-run (GDD §6): upgrade/venda da torre selecionada.
    private func inspectPanel(_ i: TowerInspect) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(i.icon).font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(i.name)").font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("★ \(i.level)/\(i.maxLevel)")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(i.element.color.opacity(0.35)).clipShape(Capsule())
                            .foregroundColor(.white)
                    }
                    HStack(spacing: 6) {
                        Text(i.rarity.nome).font(.system(size: 11, weight: .bold))
                            .foregroundColor(i.rarity.color)
                        Text(i.trait).font(.system(size: 11)).foregroundColor(.white.opacity(0.65))
                    }
                }
                Spacer()
                Button { model.doDeselect?() } label: {
                    Text("✕").font(.system(size: 18, weight: .bold)).foregroundColor(.white.opacity(0.7))
                        .frame(width: 34, height: 34).background(.white.opacity(0.12)).clipShape(Circle())
                }
            }
            HStack(spacing: 8) {
                miniStat("⚔️", String(format: "%.0f", i.damage))
                miniStat("🎯", "\(i.range)")
                miniStat(i.element.icon, i.element.nome)
            }
            if !i.abilities.isEmpty {
                HStack(spacing: 6) {
                    ForEach(i.abilities, id: \.self) { a in
                        HStack(spacing: 4) {
                            Text(a.icon).font(.system(size: 12))
                            Text(a.nome).font(.system(size: 11, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(i.element.color.opacity(0.30), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 10) {
                if let cost = i.upgradeCost {
                    Button { model.doUpgrade?() } label: {
                        Text("⬆︎ Upgrade  💰\(cost)")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(model.gold >= cost ? Color(red: 0.25, green: 0.55, blue: 0.95)
                                                           : Color.gray.opacity(0.4))
                            .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                    }.disabled(model.gold < cost)
                } else {
                    Text("★ máx (\(i.maxLevel))").font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(.white.opacity(0.1)).foregroundColor(.white.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button { model.doSell?() } label: {
                    Text("Vender  💰\(i.sellValue)")
                        .font(.system(size: 15, weight: .bold))
                        .frame(minWidth: 120, minHeight: 46)
                        .background(Color(red: 0.85, green: 0.35, blue: 0.30))
                        .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(12).background(.black.opacity(0.55)).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func miniStat(_ icon: String, _ v: String) -> some View {
        HStack(spacing: 4) { Text(icon).font(.system(size: 14)); Text(v)
            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white) }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(.white.opacity(0.08)).clipShape(Capsule())
    }

    private var rewardBlock: some View {
        VStack(spacing: 4) {
            Text("Créditos ganhos").font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("🪙 +\(model.creditsEarned)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.yellow)
        }
    }

    private var replayButton: some View {
        Button("Jogar de novo") { model.reset(); sceneID = UUID() }
            .font(.system(size: 20, weight: .bold))
            .padding(.horizontal, 28).padding(.vertical, 12)
            .background(Color(red: 0.25, green: 0.55, blue: 0.95))
            .foregroundColor(.white).clipShape(Capsule())
    }

    private var victoryCard: some View {
        VStack(spacing: 18) {
            Text(model.message).font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            rewardBlock
            if stage != nil, (stage! + 1) < Campaign.stages.count {
                Button("Próxima fase →") { onNext() }
                    .font(.system(size: 20, weight: .bold))
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Color(red: 0.35, green: 0.80, blue: 0.40))
                    .foregroundColor(.white).clipShape(Capsule())
            } else if stage == nil {
                replayButton
            }
            Button("Menu", action: onExit).foregroundColor(.white.opacity(0.7))
        }
        .padding(40).background(.black.opacity(0.72)).clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var gameOverCard: some View {
        VStack(spacing: 18) {
            Text(model.message).font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            if config.targetWave == nil && meta.endlessBest > 0 {
                Text("Recorde: onda \(meta.endlessBest)").font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            rewardBlock
            replayButton
            Button("Menu", action: onExit).foregroundColor(.white.opacity(0.7))
        }
        .padding(40).background(.black.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: — Menu de pause

    private func pauseButton(_ title: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(color).foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("⏸ Pausado").font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                pauseButton("▶ Continuar", Color(red: 0.35, green: 0.80, blue: 0.40)) {
                    showPause = false; model.paused = false
                }
                pauseButton("⚙️ Configurações", Color(red: 0.25, green: 0.55, blue: 0.95)) {
                    showPause = false; showGameSettings = true
                }
                pauseButton("🏠 Voltar ao menu", Color(red: 0.85, green: 0.35, blue: 0.30)) {
                    if stage != nil { showSavePrompt = true }   // Campanha → pergunta salvar
                    else { model.paused = false; onExit() }      // Endless → sai direto
                }
            }
            .padding(28).frame(maxWidth: 320)
            .background(.black.opacity(0.55)).clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(24)
        }
    }

    private var savePromptCard: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Salvar progresso?").font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Você continua esta fase de onde parou.")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                pauseButton("💾 Salvar e sair", Color(red: 0.35, green: 0.80, blue: 0.40)) { saveAndExit() }
                pauseButton("🗑 Sair sem salvar", Color(red: 0.85, green: 0.35, blue: 0.30)) {
                    if let s = stage { meta.clearRun(stage: s) }
                    model.paused = false; onExit()
                }
                Button("Cancelar") { showSavePrompt = false }
                    .font(.system(size: 14)).foregroundColor(.white.opacity(0.7)).padding(.top, 2)
            }
            .padding(26).frame(maxWidth: 320)
            .background(.black.opacity(0.85)).clipShape(RoundedRectangle(cornerRadius: 22))
            .padding(24)
        }
    }

    private func saveAndExit() {
        if let s = stage {
            let run = RunSave(stage: s, gold: model.gold, lives: model.lives, wave: model.wave,
                              loadout: meta.loadoutRaw, towers: model.towerSnapshot?() ?? [])
            meta.saveRun(run)
        }
        model.paused = false; onExit()
    }

    private func makeScene(size: CGSize) -> GameScene {
        var rng: RandomNumberGenerator
        if let seed = config.seed { rng = SeededGenerator(seed: seed) }
        else { rng = SystemRandomNumberGenerator() }
        let map = HexMap.generate(cols: config.cols, rows: config.rows,
                                  obstacleRatio: config.obstacleRatio,
                                  complexity: config.pathComplexity, rng: &rng)
        let s = size == .zero ? CGSize(width: 390, height: 800) : size
        // Campanha com partida salva → retoma (torres/gold/vidas/onda). Senão, novo jogo.
        let resume = (mode == .campanha ? stage : nil).flatMap { meta.loadRun(stage: $0) }
        // Campanha: restringe as torres ao loadout (o salvo, se retomando); outros = nil.
        let campaignTowers = mode == .campanha ? Set(resume?.loadout ?? meta.loadoutRaw) : nil
        return GameScene(map: map, model: model, meta: meta, config: config,
                         campaignTowers: campaignTowers, size: s, resume: resume)
    }
}
