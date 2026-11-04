import SwiftUI

/// Prêmio anexado a uma mensagem de Inbox (§inbox). Codable auto-sintetizado.
enum InboxReward: Codable {
    case advancedSummons(Int)   // N invocações avançadas
    case credits(Int)
}

/// Mensagem da Inbox: comunicação + prêmio opcional coletável (ex.: de códigos).
struct InboxMessage: Codable, Identifiable {
    var id = UUID()
    var title: String
    var body: String
    var reward: InboxReward? = nil
    var claimed: Bool = false
    var read: Bool = false
}

/// Progressão META, persistente entre runs (§6 meta / §7 banco de cards). Guarda por
/// torre (indexada por id 0–20 do `TowerCatalog`): raridade + cards acumulados +
/// nível de card (Paragon). Cards são ganhos jogando; gastos aqui pra subir raridade,
/// habilidades e o teto de estrelas in-run.
final class MetaProgress: ObservableObject {
    @Published private(set) var rarityRaw: [Int]
    @Published private(set) var cards: [Int]
    @Published private(set) var cardLevelRaw: [Int]      // Paragon 0–100 (§4): teto de estrelas
    @Published private(set) var campaignUnlocked: Int    // maior fase liberada (0-based)
    @Published private(set) var endlessBest: Int         // maior onda alcançada no Endless
    @Published private(set) var loadoutRaw: [Int]        // até 5 ids escolhidos p/ a Campanha
    @Published private(set) var unlockedRaw: [Bool]      // torres desbloqueadas (ganharam ≥1 carta)
    @Published private(set) var credits: Int             // moeda ganha jogando (gasta em Summon)
    // Configurações
    @Published private(set) var soundOn: Bool
    @Published private(set) var musicOn: Bool
    @Published private(set) var frameLimit: Int          // 30 / 60 / 120
    // Inbox & códigos
    @Published private(set) var inbox: [InboxMessage]
    @Published private(set) var redeemedCodes: [String]
    // Features liberadas por código
    @Published private(set) var aiUnlocked: Bool        // COTRIMAIMODE → Auto ON
    @Published private(set) var speedUnlocked: Bool      // COTRIMSPEEDMODE → 5×/10×
    @Published private(set) var godMode: Bool            // COTRIMGODMODEON → tudo + summons ilimitados

    static let maxLives = 10
    static let speed2xCampaignPhase = 20                 // 2× libera ao chegar na fase 20
    // Limites diários (reset às 12:34, §daily)
    @Published private(set) var creditsToday: Int
    @Published private(set) var capDayStart: Date
    @Published private(set) var freeAdvDay: Date?          // dia em que o avançado grátis foi pego
    @Published private(set) var freeBasicDay: Date?        // dia dos básicos grátis atuais
    @Published private(set) var freeBasicCount: Int        // básicos grátis já pegos hoje
    @Published private(set) var lastBasicClaim: Date?      // pra cooldown de 10min

    static let dailyCreditCap = 10 * 400                   // = 10 summons avançados/dia
    static let freeBasicPerDay = 5
    static let basicCooldown: TimeInterval = 600           // 10 min entre básicos grátis
    static let resetHour = 12, resetMinute = 34            // reset diário às 12:34

    /// Início do "dia de jogo": o 12:34 mais recente (ontem ou hoje).
    static func dayStart(_ date: Date = Date()) -> Date {
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day], from: date)
        c.hour = resetHour; c.minute = resetMinute; c.second = 0
        let today = cal.date(from: c) ?? date
        return date >= today ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
    }

    static let cardLevelMax = 100
    static let baseMaxStars = 2                          // teto base (Comum); +1 por tier de raridade
    static let starsPerLevels = 8                        // +1 estrela a cada 8 níveis de card
    static let loadoutSize = 5
    static let defaultLoadout: [Int] = []                // começa vazio — nada desbloqueado

    private static let key = "hextd.meta.v2"             // v2 = 21 torres data-driven
    private static let keyV1 = "hextd.meta.v1"           // v1 = 4 torres (migração)
    private static var count: Int { TowerCatalog.count }
    // Mapa v1(lança,fogo,gelo,arcana) → id do catálogo novo (Lança, Faísca, Estilhaço, Prisma).
    private static let v1Map = [9, 0, 6, 17]

    private struct Save: Codable {
        var rarity: [Int]; var cards: [Int]
        var campaignUnlocked: Int?; var endlessBest: Int?
        var cardLevel: [Int]?; var loadout: [Int]?; var credits: Int?
        var unlocked: [Bool]?
        var soundOn: Bool?; var musicOn: Bool?; var frameLimit: Int?
        var inbox: [InboxMessage]?; var redeemedCodes: [String]?
        var creditsToday: Int?; var capDayStart: Date?
        var freeAdvDay: Date?; var freeBasicDay: Date?
        var freeBasicCount: Int?; var lastBasicClaim: Date?
        var aiUnlocked: Bool?; var speedUnlocked: Bool?; var godMode: Bool?
    }

    init() {
        rarityRaw = Array(repeating: 0, count: Self.count)
        cards = Array(repeating: 0, count: Self.count)
        cardLevelRaw = Array(repeating: 0, count: Self.count)
        campaignUnlocked = 0; endlessBest = 0
        loadoutRaw = Self.defaultLoadout
        unlockedRaw = Array(repeating: false, count: Self.count)
        credits = 0
        soundOn = true; musicOn = true; frameLimit = 60
        inbox = []; redeemedCodes = []
        aiUnlocked = false; speedUnlocked = false; godMode = false
        creditsToday = 0; capDayStart = Self.dayStart()
        freeAdvDay = nil; freeBasicDay = nil; freeBasicCount = 0; lastBasicClaim = nil

        if let s = Self.load(Self.key), s.rarity.count == Self.count {
            rarityRaw = s.rarity; cards = s.cards
            campaignUnlocked = s.campaignUnlocked ?? 0
            endlessBest = s.endlessBest ?? 0
            credits = s.credits ?? 0
            soundOn = s.soundOn ?? true; musicOn = s.musicOn ?? true
            frameLimit = s.frameLimit ?? 60
            inbox = s.inbox ?? []; redeemedCodes = s.redeemedCodes ?? []
            aiUnlocked = s.aiUnlocked ?? false; speedUnlocked = s.speedUnlocked ?? false
            godMode = s.godMode ?? false
            creditsToday = s.creditsToday ?? 0
            capDayStart = s.capDayStart ?? Self.dayStart()
            freeAdvDay = s.freeAdvDay; freeBasicDay = s.freeBasicDay
            freeBasicCount = s.freeBasicCount ?? 0; lastBasicClaim = s.lastBasicClaim
            if let cl = s.cardLevel, cl.count == Self.count { cardLevelRaw = cl }
            if let lo = s.loadout { loadoutRaw = Array(lo.prefix(Self.loadoutSize)) }
            if let u = s.unlocked, u.count == Self.count { unlockedRaw = u }
            else { for i in 0..<Self.count where cards[i] > 0 || rarityRaw[i] > 0 { unlockedRaw[i] = true } }
        } else if let old = Self.load(Self.keyV1), old.rarity.count == Self.v1Map.count {
            // Migração best-effort: carrega o progresso das 4 torres antigas.
            for (oldIdx, newId) in Self.v1Map.enumerated() where newId < Self.count {
                rarityRaw[newId] = old.rarity[oldIdx]
                cards[newId] = old.cards[oldIdx]
                if let cl = old.cardLevel, oldIdx < cl.count { cardLevelRaw[newId] = cl[oldIdx] }
            }
            campaignUnlocked = old.campaignUnlocked ?? 0
            endlessBest = old.endlessBest ?? 0
            save()   // grava já no formato v2
        }
    }

    private static func load(_ key: String) -> Save? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Save.self, from: data)
    }

    func isStageUnlocked(_ i: Int) -> Bool { i <= campaignUnlocked }

    func unlockStage(_ i: Int) {
        guard i > campaignUnlocked else { return }
        campaignUnlocked = i; save()
    }

    func recordEndless(_ wave: Int) {
        guard wave > endlessBest else { return }
        endlessBest = wave; save()
    }

    func rarity(_ id: Int) -> Rarity { Rarity(rawValue: rarityRaw[id]) ?? .cinza }
    func cardCount(_ id: Int) -> Int { cards[id] }
    func statMult(_ id: Int) -> Double { rarity(id).statMult }

    // MARK: — Desbloqueio (§unlock): torre libera ao ganhar a 1ª carta (permanente)
    func isUnlocked(_ id: Int) -> Bool { unlockedRaw[id] || godMode }
    var unlockedIds: [Int] { godMode ? Array(0..<Self.count) : (0..<Self.count).filter { unlockedRaw[$0] } }
    var hasAnyUnlocked: Bool { godMode || unlockedRaw.contains(true) }

    // MARK: — Features liberadas por código
    var autoUnlocked: Bool {
        #if DEBUG
        return true   // build pessoal (device Debug): Auto disponível em todas as fases
        #else
        return aiUnlocked || godMode
        #endif
    }
    var has2xSpeed: Bool {
        #if DEBUG
        return true   // build pessoal: todas as velocidades liberadas
        #else
        return godMode || speedUnlocked || campaignUnlocked + 1 >= Self.speed2xCampaignPhase
        #endif
    }
    var hasFastSpeed: Bool {   // 5×/10×
        #if DEBUG
        return true
        #else
        return godMode || speedUnlocked
        #endif
    }
    /// Adiciona carta(s) e desbloqueia a torre.
    private func grantCard(_ id: Int, _ n: Int = 1) {
        cards[id] += n
        if n > 0 { unlockedRaw[id] = true }
    }

    /// Só p/ o harness de teste: desbloqueia tudo (não salva).
    func debugUnlockAll() { for i in unlockedRaw.indices { unlockedRaw[i] = true } }
    func debugSetLoadout(_ ids: [Int]) { loadoutRaw = Array(ids.prefix(Self.loadoutSize)) }

    // MARK: — Partida da Campanha em andamento (salvar/retomar via menu de pause)
    private func runKey(_ stage: Int) -> String { "hextd.run.\(stage)" }
    func saveRun(_ r: RunSave) {
        if let data = try? JSONEncoder().encode(r) { UserDefaults.standard.set(data, forKey: runKey(r.stage)) }
    }
    func loadRun(stage: Int) -> RunSave? {
        guard let data = UserDefaults.standard.data(forKey: runKey(stage)),
              let r = try? JSONDecoder().decode(RunSave.self, from: data) else { return nil }
        return r
    }
    func hasRun(stage: Int) -> Bool { UserDefaults.standard.data(forKey: runKey(stage)) != nil }
    func clearRun(stage: Int) { UserDefaults.standard.removeObject(forKey: runKey(stage)) }

    /// Reset COMPLETO da progressão: volta tudo ao estado de conta nova (torres, cards,
    /// campanha, créditos, códigos, features, limites diários). Preferências de áudio/FPS
    /// são mantidas. Apaga também o save v1 pra não re-migrar.
    func resetProgress() {
        rarityRaw = Array(repeating: 0, count: Self.count)
        cards = Array(repeating: 0, count: Self.count)
        cardLevelRaw = Array(repeating: 0, count: Self.count)
        campaignUnlocked = 0; endlessBest = 0
        loadoutRaw = Self.defaultLoadout
        unlockedRaw = Array(repeating: false, count: Self.count)
        credits = 0
        inbox = []; redeemedCodes = []
        aiUnlocked = false; speedUnlocked = false; godMode = false
        creditsToday = 0; capDayStart = Self.dayStart()
        freeAdvDay = nil; freeBasicDay = nil; freeBasicCount = 0; lastBasicClaim = nil
        UserDefaults.standard.removeObject(forKey: Self.keyV1)
        save()
    }

    // MARK: — Paragon (nível de card → teto de estrelas in-run, §4)

    func cardLevel(_ id: Int) -> Int { cardLevelRaw[id] }

    /// Teto de estrelas in-run: RARIDADE define o teto base (+1 por tier) e o Paragon
    /// (pós-Mítica) soma por cima (+1 a cada 8 níveis). Assim uma torre Épica já sobe
    /// além de 2★ dentro da partida, sem depender de Paragon.
    ///   Comum 2 · Incomum 3 · Rara 4 · Épica 5 · Lendária 6 · Mítica 7 (+Paragon).
    func maxStars(_ id: Int) -> Int {
        Self.baseMaxStars + rarity(id).rawValue + cardLevel(id) / Self.starsPerLevels
    }

    /// Custo em cards pra subir 1 nível de card (nil = já no máximo). Cresce devagar.
    func cardLevelCost(_ id: Int) -> Int? {
        let lvl = cardLevel(id)
        return lvl >= Self.cardLevelMax ? nil : 1 + lvl / 6
    }

    /// Paragon só evolui depois da torre chegar em Mítica (§paragon).
    func paragonUnlocked(_ id: Int) -> Bool { rarity(id) == .vermelha }

    func canLevelCard(_ id: Int) -> Bool {
        guard rarity(id) == .vermelha, let cost = cardLevelCost(id) else { return false }
        return cards[id] >= cost
    }

    func levelUpCard(_ id: Int) {
        guard rarity(id) == .vermelha, let cost = cardLevelCost(id), cards[id] >= cost else { return }
        cards[id] -= cost
        cardLevelRaw[id] += 1
        save()
    }

    /// Torre tem cards suficientes pra algum upgrade agora (raridade OU Paragon).
    func canAnyUpgrade(_ id: Int) -> Bool { canUpgrade(id) || canLevelCard(id) }

    /// Habilidades liberadas pela raridade atual (§4/§5): os primeiros N slots da
    /// torre, onde N = `abilitySlots` do tier.
    func abilities(_ id: Int) -> [TowerAbility] {
        Array(TowerCatalog.spec(id).abilities.prefix(rarity(id).abilitySlots))
    }

    func canUpgrade(_ id: Int) -> Bool {
        guard let cost = rarity(id).upgradeCost else { return false }
        return cards[id] >= cost
    }

    func upgradeRarity(_ id: Int) {
        guard let cost = rarity(id).upgradeCost, cards[id] >= cost,
              rarityRaw[id] + 1 < Rarity.allCases.count else { return }
        cards[id] -= cost
        rarityRaw[id] += 1
        save()
    }

    func award(_ id: Int, _ n: Int) {
        guard n > 0 else { return }
        grantCard(id, n)
        save()
    }

    // MARK: — Loadout da Campanha (5 torres, escolhidas antes da fase)

    func inLoadout(_ id: Int) -> Bool { loadoutRaw.contains(id) }
    var loadoutFull: Bool { loadoutRaw.count >= Self.loadoutSize }
    var loadoutReady: Bool { !loadoutRaw.isEmpty }   // pode jogar com ≥1 torre

    /// Alterna uma torre no loadout (remove se já está; adiciona se há espaço e desbloqueada).
    func toggleLoadout(_ id: Int) {
        if let idx = loadoutRaw.firstIndex(of: id) { loadoutRaw.remove(at: idx) }
        else if loadoutRaw.count < Self.loadoutSize && isUnlocked(id) { loadoutRaw.append(id) }
        save()
    }

    // MARK: — Créditos & Summon (§economia)

    /// Tipos de invocação. Preços: Básico = 10 vitórias de campanha (ou 5 rogue);
    /// Avançado = 40 campanha (ou 20 rogue). Endless: 10 ondas = 1 partida.
    enum Summon: CaseIterable {
        case basico, avancado
        var nome: String { self == .basico ? "Básico" : "Avançado" }
        var cost: Int { self == .basico ? 100 : 400 }
        var range: ClosedRange<Int> { self == .basico ? 1...10 : 7...20 }
        var desc: String { self == .basico ? "1–10 cartas" : "7–20 cartas" }
    }
    static let creditsCampaignWin = 10
    static let creditsRogueWin = 20

    /// Adiciona créditos respeitando o teto diário (§daily). Retorna quanto foi de fato
    /// creditado (pode ser < n se bateu o teto do dia).
    @discardableResult
    func addCredits(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        let day = Self.dayStart()
        if capDayStart != day { capDayStart = day; creditsToday = 0 }
        let grant = min(n, max(0, Self.dailyCreditCap - creditsToday))
        credits += grant; creditsToday += grant
        save()
        return grant
    }

    /// Créditos ainda ganháveis hoje (pro HUD/telas).
    var creditsRemainingToday: Int {
        capDayStart == Self.dayStart() ? max(0, Self.dailyCreditCap - creditsToday) : Self.dailyCreditCap
    }

    func canSummon(_ s: Summon) -> Bool { godMode || credits >= s.cost }

    /// Sorteia as cartas de uma invocação (cada carta → torre aleatória).
    private func rollSummon(_ s: Summon) -> [(Int, Int)] {
        var got: [Int: Int] = [:]
        for _ in 0..<Int.random(in: s.range) {
            let id = Int.random(in: 0..<Self.count)
            grantCard(id); got[id, default: 0] += 1
        }
        return got.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Gasta créditos e invoca. Retorna as cartas, ou nil se não tem créditos.
    func summon(_ s: Summon) -> [(Int, Int)]? {
        guard godMode || credits >= s.cost else { return nil }
        if !godMode { credits -= s.cost }
        let r = rollSummon(s)
        save()
        return r
    }

    #if DEBUG
    /// DEBUG: concede `count` invocações do tipo `s` SEM custo (grátis, ignora créditos).
    /// Usado por harness (env var) pra popular a coleção em testes. Retorna o agregado.
    @discardableResult
    func debugGrantSummons(_ s: Summon, count: Int) -> [(Int, Int)] {
        var got: [Int: Int] = [:]
        for _ in 0..<max(0, count) {
            for (id, n) in rollSummon(s) { got[id, default: 0] += n }
        }
        save()
        return got.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
    #endif

    // Summon Elemental: só cartas do elemento escolhido. Custo = 2 básicos.
    static let elementalCost = 2 * 100
    static let elementalRange = 3...6

    var canSummonElement: Bool { godMode || credits >= Self.elementalCost }

    func summonElement(_ e: Element) -> [(Int, Int)]? {
        let ids = TowerCatalog.ids(of: e)
        guard (godMode || credits >= Self.elementalCost), !ids.isEmpty else { return nil }
        if !godMode { credits -= Self.elementalCost }
        var got: [Int: Int] = [:]
        for _ in 0..<Int.random(in: Self.elementalRange) {
            let id = ids.randomElement()!
            grantCard(id); got[id, default: 0] += 1
        }
        save()
        return got.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    // MARK: — Summons grátis diários (§daily)

    /// Avançado grátis: 1 por dia (reset 12:34), não cumulativo. God mode = ilimitado.
    var freeAdvancedAvailable: Bool { godMode || freeAdvDay != Self.dayStart() }

    func claimFreeAdvanced() -> [(Int, Int)]? {
        guard freeAdvancedAvailable else { return nil }
        if !godMode { freeAdvDay = Self.dayStart() }
        let r = rollSummon(.avancado)
        save()
        return r
    }

    private var basicCountToday: Int { freeBasicDay == Self.dayStart() ? freeBasicCount : 0 }
    private var lastBasicToday: Date? { freeBasicDay == Self.dayStart() ? lastBasicClaim : nil }

    /// Básicos grátis restantes hoje (5/dia).
    var freeBasicRemaining: Int { max(0, Self.freeBasicPerDay - basicCountToday) }

    /// Básico grátis disponível agora? 1º é imediato; do 2º ao 5º, 10min após o anterior.
    var freeBasicAvailable: Bool {
        if godMode { return true }
        let c = basicCountToday
        guard c < Self.freeBasicPerDay else { return false }
        if c == 0 { return true }
        guard let last = lastBasicToday else { return true }
        return Date() >= last.addingTimeInterval(Self.basicCooldown)
    }

    /// Quando o próximo básico grátis libera (nil = já disponível ou esgotado).
    var nextBasicAt: Date? {
        let c = basicCountToday
        guard c > 0, c < Self.freeBasicPerDay, let last = lastBasicToday else { return nil }
        let at = last.addingTimeInterval(Self.basicCooldown)
        return at > Date() ? at : nil
    }

    func claimFreeBasic() -> [(Int, Int)]? {
        guard freeBasicAvailable else { return nil }
        if !godMode {
            let day = Self.dayStart()
            if freeBasicDay != day { freeBasicDay = day; freeBasicCount = 0 }
            freeBasicCount += 1
            lastBasicClaim = Date()
        }
        let r = rollSummon(.basico)
        save()
        return r
    }

    /// Próximo reset diário (12:34 de amanhã em relação ao dia de jogo atual).
    var nextDailyReset: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Self.dayStart()) ?? Date()
    }

    // MARK: — Configurações

    func setSound(_ on: Bool) { soundOn = on; save() }
    func setMusic(_ on: Bool) { musicOn = on; save() }
    func setFrameLimit(_ fps: Int) { frameLimit = fps; save() }

    // MARK: — Inbox & códigos (§inbox)

    var unreadInbox: Int { inbox.filter { !$0.read }.count }

    func markInboxRead() {
        guard unreadInbox > 0 else { return }
        for i in inbox.indices { inbox[i].read = true }
        save()
    }

    func addInbox(title: String, body: String, reward: InboxReward? = nil) {
        inbox.insert(InboxMessage(title: title, body: body, reward: reward), at: 0)
        save()
    }

    /// Coleta o prêmio de uma mensagem. Retorna as cartas ganhas (pra exibir).
    @discardableResult
    func claim(_ id: UUID) -> [(Int, Int)] {
        guard let i = inbox.firstIndex(where: { $0.id == id }),
              let reward = inbox[i].reward, !inbox[i].claimed else { return [] }
        inbox[i].claimed = true
        var result: [(Int, Int)] = []
        switch reward {
        case .credits(let c): credits += c
        case .advancedSummons(let n):
            var got: [Int: Int] = [:]
            for _ in 0..<n {
                for _ in 0..<Int.random(in: Summon.avancado.range) {
                    let tid = Int.random(in: 0..<Self.count)
                    grantCard(tid); got[tid, default: 0] += 1
                }
            }
            result = got.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        }
        save()
        return result
    }

    private func save() {
        let s = Save(rarity: rarityRaw, cards: cards,
                     campaignUnlocked: campaignUnlocked, endlessBest: endlessBest,
                     cardLevel: cardLevelRaw, loadout: loadoutRaw, credits: credits,
                     unlocked: unlockedRaw,
                     soundOn: soundOn, musicOn: musicOn, frameLimit: frameLimit,
                     inbox: inbox, redeemedCodes: redeemedCodes,
                     creditsToday: creditsToday, capDayStart: capDayStart,
                     freeAdvDay: freeAdvDay, freeBasicDay: freeBasicDay,
                     freeBasicCount: freeBasicCount, lastBasicClaim: lastBasicClaim,
                     aiUnlocked: aiUnlocked, speedUnlocked: speedUnlocked, godMode: godMode)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
