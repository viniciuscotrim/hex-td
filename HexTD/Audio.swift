import AVFoundation

/// Áudio do jogo: trilha em loop (toggle Música) + efeitos (toggle Som). Tudo é gerado
/// proceduralmente (WAV em Sounds/, sem áudio de terceiros). Usa pools de AVAudioPlayer
/// pra permitir efeitos sobrepostos sem estouro de latência.
final class Audio {
    static let shared = Audio()

    private(set) var soundOn = true
    private(set) var musicOn = true
    private var music: AVAudioPlayer?
    private var pools: [String: [AVAudioPlayer]] = [:]
    private var next: [String: Int] = [:]
    private var lastShoot = Date.distantPast

    // Efeitos pré-carregados (pool de 4 players cada → overlap).
    private static let sfxNames = ["shoot", "hit", "place", "upgrade", "coin", "wave", "win", "lose", "tap"]

    private init() {
        // .ambient + mixWithOthers = não interrompe música do usuário nem toca no mudo.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for name in Self.sfxNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { continue }
            let players = (0..<4).compactMap { _ -> AVAudioPlayer? in
                let p = try? AVAudioPlayer(contentsOf: url); p?.prepareToPlay(); return p
            }
            if !players.isEmpty { pools[name] = players; next[name] = 0 }
        }
    }

    /// Sincroniza com as preferências salvas (chamado no start e ao trocar os toggles).
    func configure(soundOn: Bool, musicOn: Bool) {
        self.soundOn = soundOn
        setMusic(musicOn)
    }

    // MARK: música

    func startMusic() {
        guard musicOn, music == nil,
              let url = Bundle.main.url(forResource: "music", withExtension: "wav") else { return }
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.numberOfLoops = -1
        p?.volume = 0.45
        p?.prepareToPlay(); p?.play()
        music = p
    }
    func stopMusic() { music?.stop(); music = nil }
    func setMusic(_ on: Bool) { musicOn = on; on ? startMusic() : stopMusic() }
    func setSound(_ on: Bool) { soundOn = on }

    // MARK: efeitos

    /// Toca um efeito. `shoot` é limitado (muitos tiros/seg) pra não virar ruído.
    func sfx(_ name: String) {
        guard soundOn, let pool = pools[name], !pool.isEmpty else { return }
        if name == "shoot" {
            let now = Date()
            if now.timeIntervalSince(lastShoot) < 0.06 { return }
            lastShoot = now
        }
        let i = (next[name] ?? 0) % pool.count
        next[name] = i + 1
        let p = pool[i]
        p.currentTime = 0
        p.play()
    }
}
