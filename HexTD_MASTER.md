# HexTD — Documento Mestre (auditável)

Tower Defense hexagonal (SwiftUI + SpriteKit, iOS 17). Motor único, quatro modos:
**Campanha**, **Rogue** ("The Tower", idle), **Endless** e **Vs** (contra IA ou PvP online).
Todo número abaixo é lido direto do código. Fonte de verdade dos coeficientes de balanço:
`Progression.swift` + `progression.json` (bundle, com hot-reload em DEBUG).

---

## 1. Roda elemental (7 elementos)

Ordem cíclica (é a cadeia de força): **Fogo → Água → Gelo → Físico → Veneno → Arcana → Natureza →** (volta a Fogo).

Regra (`Element.multiplier(against:)`): cada elemento é **2×** contra o **anterior** no ciclo e **0.5×** contra o **próximo**; **1×** no resto. 1 forte + 1 fraco por elemento, sem par mútuo.

| Atacante | Vence (2×) | Perde p/ (0.5×) |
|---|---|---|
| 🔥 Fogo | Natureza | Água |
| 💧 Água | Fogo | Gelo |
| ❄️ Gelo | Água | Físico |
| 🗡️ Físico | Gelo | Veneno |
| ☠️ Veneno | Físico | Arcana |
| 🔮 Arcana | Veneno | Natureza |
| 🌿 Natureza | Arcana | Fogo |

O multiplicador elemental é aplicado por **último** na cadeia de dano (compõe multiplicativamente com habilidades/combos).

---

## 2. Raridades (6 tiers)

`Rarity`: cinza → verde → azul → roxa → laranja → vermelha.

| Tier | Nome | statMult (×dano base) | Slots de habilidade | Custo p/ subir (cards) |
|---|---|---|---|---|
| 0 | Comum (cinza) | **1.00** | 0 | 3 |
| 1 | Incomum (verde) | **1.50** | 0 | 6 |
| 2 | Rara (azul) | **2.25** | 1 (slot 1) | 12 |
| 3 | Épica (roxa) | **3.375** | 1 | 24 |
| 4 | Lendária (laranja) | **5.0625** | 2 (slot 2) | 48 |
| 5 | Mítica (vermelha) | **7.59375** | 2 | — (máx) |

**statMult** = `∏(1+bᵢ)` para i=1..tier, com `statBonuses = [0.50, 0.50, 0.50, 0.50, 0.50]` → cada salto de raridade é **+50%** de stat base (1.5ˣ).

**Slots de habilidade**: slot 1 libera na **Rara (azul)**, slot 2 na **Lendária (laranja)**. Comum/Incomum = 0 habilidades.

---

## 3. Fórmulas de progressão (coeficientes auditáveis)

Todos os coeficientes vêm de `progression.json`:

```json
{
  "hp0": 22, "rHP": 1.11, "kHP": 0.15, "pHP": 10,
  "dano0": 5, "rDano": 1.06, "kDano": 0.15, "pDano": 10,
  "gold0": 4, "goldA": 0.42,
  "statBonuses": [0.50, 0.50, 0.50, 0.50, 0.50],
  "upgradeCostGrowth": 1.5, "upgradeEffectStep": 0.25,
  "elementalAdvantage": 2.0, "elementalNeutral": 1.0, "elementalDisadvantage": 0.5,
  "rogueVariance": 0.02
}
```

**Amortecimento por patamar** (comum a HP e dano): `d(n) = 1 / (1 + k · ⌊n/P⌋)` — cai em degraus a cada `P` waves.

1. **HP do inimigo na wave n**: `HP(n) = hp0 · rHP^(n · d(n))`, com `k=kHP=0.15, P=pHP=10`.
   Ex.: HP(1)≈24 · HP(5)≈34 · HP(10)≈55 · HP(20)≈117.
2. **Dano de contato na wave n**: `Dano(n) = dano0 · rDano^(n · d(n))`, com `k=kDano=0.15, P=pDano=10`. Escala mais devagar que o HP.
3. **Gold por kill (base)**: `Gold(n) = gold0 · n^goldA = 4 · n^0.42` (sublinear).
4. **Stat de raridade**: `Stat = Stat0 · ∏(1+bᵢ)` (ver §2).
5. **Upgrade in-run** (gold, reseta por partida):
   - Custo do nível `lvl` (1-based): `base · upgradeCostGrowth^(lvl-1) = cost · 1.5^(lvl-1)`.
   - Efeito acumulado no nível `lvl` (0 = recém-colocada): `1 + upgradeEffectStep · lvl = 1 + 0.25·lvl`.
6. **Modificador elemental**: 2.0 (vantagem) / 1.0 (neutro) / 0.5 (desvantagem).
7. **Rogue**: `r` recebe variância determinística por seed: `r ± rogueVariance` (±0.02).

---

## 4. Stats in-run de uma torre (fórmulas exatas)

Para uma torre de spec S no nível `lvl` (1 = recém-colocada):

- **Dano** = `S.baseDamage · (1 + 0.25·(lvl-1)) · rarityMult · auraMult`
- **Cadência** (s entre tiros) = `S.cooldown · 0.9^(lvl-1) · (Cadência? 0.80 : 1)`
- **Alcance** (hexes) = `S.range + (lvl≥3 ? 1 : 0) + (Alcance? 1 : 0)`
- **Splash** (raio) = `S.splash + (S.splash>0 e lvl≥4 ? 1 : 0) + (Chamas Vivas? 1 : 0)`
- **Custo de upgrade** = `S.cost · 1.5^(lvl-1)`, disponível até `lvl < maxStars`
- **Valor de venda** = `60%` do total gasto

`auraMult` = soma das auras de **suportes** vizinhos (Ressonância / auraDamageBonus).

### Teto de estrelas (maxStars)
`maxStars(id) = baseMaxStars + tierDeRaridade + ⌊cardLevel/8⌋`, com `baseMaxStars = 2`.

| Raridade | Teto in-run |
|---|---|
| Comum | 2★ |
| Incomum | 3★ |
| Rara | 4★ |
| Épica | 5★ |
| Lendária | 6★ |
| Mítica | 7★ (+ Paragon: +1★ a cada 8 níveis de card, até nv.100) |

---

## 5. Catálogo das 21 torres (7 elementos × 3 papéis)

Papéis: **striker** (rápida, single) · **blaster** (lenta, área) · **support** (dano ~0, aura de status/dano).

| id | Elem | Papel | Nome | Custo | Dano | CD | Alc | Splash | Aplica | Bounty | Aura | Habilidades |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 🔥 | striker | Faísca | 35 | 11 | 0.50 | 2 | — | Burn | — | — | Precisão, Cadência |
| 1 | 🔥 | blaster | Bomba | 55 | 16 | 1.40 | 3 | 1 | Burn | — | — | Chamas Vivas, Queimadura |
| 2 | 🔥 | support | Braseiro | 45 | 3 | 1.00 | 2 | — | Burn | — | 0.12 | Ressonância, Potência |
| 3 | 💧 | striker | Jato | 32 | 10 | 0.50 | 2 | — | Molhado | — | — | Precisão, Perfuração |
| 4 | 💧 | blaster | Onda | 50 | 13 | 1.40 | 2 | 1 | Molhado | — | — | Chamas Vivas, Potência |
| 5 | 💧 | support | Corrente | 42 | 2 | 1.00 | 2 | — | Molhado | — | 0.12 | Ressonância, Alcance |
| 6 | ❄️ | striker | Estilhaço | 34 | 10 | 0.55 | 2 | — | Congelado | — | — | Precisão, Cong. Profundo |
| 7 | ❄️ | blaster | Nevasca | 52 | 12 | 1.50 | 3 | 1 | Congelado | — | — | Chamas Vivas, Cong. Profundo |
| 8 | ❄️ | support | Aura Gélida | 46 | 2 | 1.00 | 3 | — | Congelado | — | 0.10 | Ressonância, Estilhaços |
| 9 | 🗡️ | striker | Lança | 30 | 15 | 0.50 | 2 | — | Exposto | — | — | Precisão, Estilhaços |
| 10 | 🗡️ | blaster | Balista | 58 | 13 | 1.50 | 4 | — | Exposto | — | — | Alcance, Execução |
| 11 | 🗡️ | support | Estandarte | 50 | 2 | 1.00 | 2 | — | — | — | 0.25 | Ressonância, Cobrança |
| 12 | ☠️ | striker | Dardo | 33 | 8 | 0.50 | 2 | — | Veneno | — | — | Precisão, Contágio |
| 13 | ☠️ | blaster | Nuvem | 50 | 11 | 1.40 | 2 | 1 | Veneno | — | — | Chamas Vivas, Detonador |
| 14 | ☠️ | support | Miasma | 44 | 2 | 1.00 | 2 | — | Veneno | — | 0.12 | Ressonância, Potência |
| 15 | 🔮 | striker | Raio | 38 | 11 | 0.50 | 3 | — | Marcado | 3 | — | Cadência, Detonador |
| 16 | 🔮 | blaster | Orbe | 54 | 14 | 1.30 | 3 | 1 | Marcado | 3 | — | Chamas Vivas, Cobrança |
| 17 | 🔮 | support | Prisma | 50 | 2 | 1.00 | 3 | — | Marcado | 12 | 0.08 | Ressonância, Cobrança |
| 18 | 🌿 | striker | Espinho | 34 | 11 | 0.50 | 2 | — | Enraizado | — | — | Precisão, Cong. Profundo |
| 19 | 🌿 | blaster | Cipó | 50 | 13 | 1.40 | 2 | 1 | Enraizado | — | — | Chamas Vivas, Estilhaços |
| 20 | 🌿 | support | Totem | 46 | 2 | 1.00 | 2 | — | Enraizado | — | 0.12 | Ressonância, Potência |

**Balanço de papel**: strikers ~CD 0.50 (single, alto DPS single-target); blasters ~CD 1.4–1.5 (área, dano/tiro menor). Diferença de cadência ~2.8×. `bounty` de Arcana = economia (gold extra por kill).

---

## 6. Habilidades (14 — paleta reutilizável)

Cada torre tem 2 habilidades fixas (ver §5), liberadas pela raridade: slot 1 na **Rara**, slot 2 na **Lendária**. Constantes de `TowerAbility.Tuning`:

| Habilidade | Efeito | Número exato |
|---|---|---|
| 🎯 Precisão | Chance de crítico | 25% de chance, dano ×2.0 |
| ➶ Perfuração | Atinge o 2º alvo no alcance | 60% do dano no 2º |
| ⚡ Cadência | Dispara mais rápido | cooldown ×0.80 (~+25% cadência) |
| 🔭 Alcance | +alcance | +1 hex |
| 💀 Execução | +dano em alvo com pouca vida | +60% se HP < 30% |
| 🔥 Queimadura | Reforça o burn (DoT) | DoT ×1.6 |
| 💥 Chamas Vivas | +raio de splash | +1 |
| 🧊 Cong. Profundo | Lentidão mais forte/longa | fator 0.30, dur 2.2s |
| 🩸 Estilhaços | Alvo lento/congelado sofre + | +25% de qualquer torre |
| 🧪 Potência | Status mais fortes/longos | ×1.5 força e duração |
| ☣️ Contágio | Burn/veneno contagia vizinho | 60% da potência |
| 💣 Detonador | Alvo com 2+ status explode | 60% do dano em área (mín. 2 status) |
| 💰 Cobrança | +gold por acerto e por kill | +1/acerto, +12 bônus/kill |
| 🌀 Ressonância | Aura de +dano nas vizinhas | +15%, raio 1 |

---

## 7. Status e combos

7 status (aplicados pelo elemento da torre): **Burn** (🔥 fogo), **Molhado** (💧 água), **Congelado** (❄️ gelo), **Veneno** (☠️), **Exposto** (🗡️ físico), **Marcado** (🔮 arcana), **Enraizado** (🌿 natureza).

Constantes de `Status.T`:

| Status | Efeito | Número |
|---|---|---|
| Burn | DoT | 40% do dano/s por 2.5s |
| Veneno | DoT (empilha por acerto) | 25% do dano/s por 3.0s |
| Molhado | habilita combos | 3.5s |
| Congelado | lentidão | fator 0.50 por 1.2s (ou profundo: 0.30 por 2.2s) |
| Enraizado | prende (lento) | fator 0.35 por 1.2s |
| Exposto | +dano recebido | ×1.25 por 3.0s |
| Marcado | +dano recebido | ×1.30 por 3.0s |

### Núcleo de combos (6 reações)
1. **Molhado ⊘ Burn** — aplicar burn em quem está molhado falha; molhado apaga fogo existente.
2. **Burn ⊘ Congelar** — congelar quem tem burn falha (o fogo impede).
3. **Molhado + Gelo = Congelamento Profundo** — congelar quem está molhado consome o molhado e aplica freeze forte (fator 0.30, 2.2s).
4. **Burn + Veneno = Explosão Tóxica** — aplicar um no inimigo que já tem o outro → **120%** do dano em área nos vizinhos.
5. **Congelado + Físico = Estilhaçar** — hit físico em congelado → **×1.6** de dano e consome o gelo.
6. **Marcado / Exposto amplificam** — o próximo dano recebido é ×1.30 (marcado) / ×1.25 (exposto).

---

## 8. Arquétipos de inimigo

Cada onda spawna **grupos** de um tipo sorteado por peso.

| Tipo | Grupo | HP (×base) | Tamanho | Resist. área | Gold (tier) | Peso |
|---|---|---|---|---|---|---|
| Swarm | 6 | 0.35 | 0.70 | 1.00 | **1** | 35 |
| Trio | 3 | 1.40 | 0.85 | 1.00 (sofre +40% de combo) | **2** | 25 |
| Duo | 2 | 2.20 | 1.05 | 0.55 | **3** | 25 |
| Elite 💪 | 1 | 6.00 | 1.50 | 0.30 | **4** | 12 |
| Boss 👑 | 1 | 12–16 | 1.5–2.0 | 0.35 | **5** | (a cada 5 ondas) |

**Gold por inimigo = tier 1…5** (menor→Boss), em **todos os mapas**. Na Campanha/Endless/Rogue o tier multiplica a base `Gold(n)=4·n^0.42`; no Vs é o valor direto 1…5 (o Vs tem renda passiva). Boss custa **5 vidas** ao vazar (Campanha/Endless: `exitDamage`); Boss no Vs tira **3 vidas**.

---

## 9. Modos de jogo

### Campanha (150 fases, `Campaign.make(i)`), com `t = i/149`:
- Colunas `6 + round(2t)` (6→8), Linhas `9 + round(7t)` (9→16), obstáculos 8%.
- Seed curada `1001 + i`. Onda-alvo `4 + round(16t)` (4→20). Vidas 10, Gold inicial **130**.
- `hpScale = (0.5 + 11.5t) · 3.0` (1.5 → 36). Complexidade de caminho `min(1, 0.1 + 0.95t)`.
- Boss a cada 5 ondas. Inimigos/onda `1.5 + t` (×). Velocidade ×0.85.
- **Elemento dominante rotaciona** por fase (`i % 7`) → 65% dos inimigos são desse elemento.

### Rogue ("The Tower", idle): seed nil, alvo onda 15, Gold 130, `hpScale 1.35`, boss a cada 5, complexidade 0.8. HP com variância de seed (±0.02 no `r`).

### Endless: seed nil, infinito (sem alvo), Gold 130, `hpScale 1.0`, sem boss. Recorde de onda salvo.

### Comuns a Campanha/Endless/Rogue (motor `GameScene`):
- `toSpawn = round((6 + w) · enemyCountMult)`; intervalo de spawn `max(0.30, 0.85 − 0.02·w)`.
- Velocidade do inimigo `(1.1 + 0.02·w) · (boss? 0.55) · enemySpeedMult`.
- Intermissão entre ondas: 8s (auto-inicia; antecipar dá bônus de gold).

---

## 10. Modo Vs (yin-yang, contra IA ou PvP)

**Tabuleiro**: oval de hexes **uniformes** que preenche a tela, dividido por uma **linha Norte/Sul**. **Norte = IA/remoto**, **Sul = você**. Estética yin-yang (curva S como lane neutra).

**Lane neutra**: **5 hexes** no centro (miolo da curva S). Monstros nascem ali **oscilando de lado** a cada spawn e descem em direção ao jogador.

**Deflexão (cabo de guerra)**:
- Morto pelo **último hit** no miolo → **teleporta pro início da lane do adversário** (vida cheia).
- Se atravessar o miolo sem morrer → vai pra lane de **quem causou menos dano**.
- Na lane lateral, só o dono defende; se o monstro chegar na base, aquele lado perde vida(s).

**Colocação livre**: qualquer hex construível do **seu território** (sul). Loadout de **5 torres distintas** (regra: **sem repetir** — cada torre ocupa 1 hex). Cada torre tem **prioridade de alvo** alternável: **meio** (ataque) ou **própria lane** (defesa). Alcance = `rangeHex · hexSize · √3` (mesma proporção dos outros mapas).

**Dificuldade / economia**:
- **HP** = `enemyHP(w) · 2.2 · 1.06^w` (base do Rogue × multiplicador composto por onda) × `hpMult` do tipo.
- Onda nova a cada **8s**; grupos por onda = `2 + w/2`; **boss a cada 5 ondas** (Boss Vs: HP ×16, tira 3 vidas).
- **Renda passiva +8 gold/s** + **gold por kill = tier 1…5**. Gold/vidas iniciais: **160 / 10**.
- **Botão "Enviar monstro"**: custo **100**, **+50 por uso** (por lado); spawna um monstro aleatório (sem boss) direto na lane do adversário. O Auto também aciona quando tem gold sobrando.
- **Vitória**: last-stand (quem zera as vidas primeiro perde). **+50 créditos** por vitória.

**IA do Vs** (também disponível como Auto pro jogador): loadout **próprio** (5 torres distintas, variadas, preferindo diferir do jogador); escolhe por **compScore** = poder × diversidade de elemento × equilíbrio área/single × sinergia de combo (fogo+veneno ×1.3, água/gelo ×1.2) e **anti-combo** (fogo⊘água/gelo ×0.55); pode **vender+trocar** uma torre nível-1 (trava por hex → sem loop); equilibra prioridades (metade ataca o meio, metade defende).

### PvP (Vs Jogador — Game Center)
- Login Game Center no launch (requer capability **Game Center** habilitada + app no App Store Connect).
- Matchmaking nativo 1×1 → handshake de **seed compartilhada** → partida determinística.
- Norte = jogador remoto (IA desligada). Sincroniza: colocação/upgrade/prioridade de torre (espelhadas sul↔norte por `(q,r) → (q+r, −r)`), envio de monstro, vidas/onda. Spawn central semeado (igual nos dois lados).
- **Status:** primeira versão; a deflexão do monstro central é resolvida localmente (pode divergir) — próximo passo é torná-la autoritativa pelo host. Precisa de teste com 2 aparelhos.

---

## 11. Rogue "The Tower" — 6 upgrades

Torre central fixa (HP próprio, regenera, morre no contato). `baseMaxHP = 250`, `baseRangePts = 110`, regen base `0.4%/s` do HP máx.

| # | Upgrade | Efeito por nível | Custo base |
|---|---|---|---|
| 0 | ⚔️ Dano | +30% (`1 + 0.30·lvl`) | 30 |
| 1 | ⚡ Vel. Ataque | cadência `cooldown · 0.92^lvl` | 34 |
| 2 | ❤️ HP Máx. | +25% (`1 + 0.25·lvl`) | 40 |
| 3 | ➕ HP/s | `0.4% + 0.2%·lvl` do HP máx/s | 34 |
| 4 | 🎯 Distância | +22 pts/lvl (`110 + range·22 + lvl·22`) | 30 |
| 5 | 🎲 Crítico 2× | +6%/lvl, teto 75% | 55 |

Custo do próximo nível: `baseCost[i] · 1.55^lvl`. Blaster (Balista) atira **multi-alvo** (+2 alvos).

---

## 12. Meta-economia (créditos, summons, cards)

**Créditos** (moeda de summon, ganha jogando; teto diário **4000/dia**, reset **12:34**):
- Campanha (vitória): **10** × (vidas restantes / 10).
- Rogue (vitória): **20** × (vidas restantes / 10).
- Endless: **1 por onda** sobrevivida.
- **Vs (vitória): 50.**

**Summons** (gastam créditos, dão cards):
| Summon | Custo | Cards | Observação |
|---|---|---|---|
| Básico | 100 | 1–10 | 5 grátis/dia (cooldown 10min) |
| Avançado | 400 | 7–20 | 1 grátis/dia |
| Elemental | 200 | 3–6 | só do elemento escolhido |

**Cards → Raridade**: custo por salto = 3 / 6 / 12 / 24 / 48 (ver §2).
**Paragon** (nível de card 0–100): só evolui **após a Mítica**; custo por nível = `1 + ⌊lvl/6⌋` cards; cada **8 níveis** = **+1★** no teto in-run.

---

## 13. Apêndice — constantes rápidas

- Vidas máximas: **10**. Reset diário: **12:34**.
- statBonuses: `[0.5, 0.5, 0.5, 0.5, 0.5]` → raridades ×1.0/1.5/2.25/3.375/5.0625/7.59375.
- upgrade in-run: efeito `+0.25/nível`, custo `×1.5/nível`.
- elemental: 2.0 / 1.0 / 0.5.
- crítico: 25% ×2.0. Perfuração: 60%. Cadência: ×0.80. Execução: +60% (<30% HP). Potência: ×1.5. Ressonância: +15%. Detonador: 60% (2+ status). Contágio: 60%. Estilhaços: +25%.
- combos: explosão 120%, estilhaçar ×1.6, marcado ×1.30, exposto ×1.25, freeze profundo 0.30/2.2s.
- gold por inimigo: **1 / 2 / 3 / 4 / 5** (swarm / trio / duo / elite / boss).
- Vs: HP `enemyHP(w)·2.2·1.06^w`, renda +8/s, envio 100 (+50/uso), vitória +50 créditos.

*Fonte: `Progression.swift`, `progression.json`, `Rarity.swift`, `TowerCatalog.swift`, `Abilities.swift`, `Status.swift`, `Elements.swift`, `Modes.swift`, `MetaProgress.swift`, `GameScene.swift`, `RogueScene.swift`, `VsScene.swift`.*
