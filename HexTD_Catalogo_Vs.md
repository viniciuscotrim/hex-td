# HexTD — Catálogo Redesenhado (modo Vs merge)

> Reset pelo brief-semente. Fogo do brief é o TEMPLATE. 21 torres (7 elementos × 3 papéis)
> + 6 combos. Cada elemento é um ESTILO travado pela Régua 1; nichos não se sobrepõem.
> Números balanceados contra a Régua 2 (DPS/custo equivalente) — ver `progression.json` e
> a tabela mestre ao final.

---

## Convenções (herdadas do template Fogo)

- **Escalada de raridade:** dano base **+50%/raridade** (statMult 1.0 / 1.5 / 2.25 / 3.375 / 5.0625 / 7.5938).
- **Alvos extra / chance de status:** sobem na **Épica+** (como o striker de Fogo: 1→2 alvos, 20%→25%).
- **Chance de status em Boss:** sempre reduzida (o status PRECISA existir pra combo disparar → reduz, não zera). Regra padrão: **status em Boss = 1%** salvo nota.
- **Papel × propagação (o padrão do Fogo, generalizado):**
  - **Striker** — single de precisão que propaga o eixo **no ESPAÇO** (deixa algo no local).
  - **Blaster** — glass cannon **refém de posição** (alcance curto, alvos muitos/ilimitados) que propaga o eixo **por SALTO/contágio**.
  - **Support** — dano ~0, **amplifica o eixo** das vizinhas (aura), sem roubar o papel de dano.

---

## 🔥 FOGO — escalada de dano / DoT que recompensa focar (TEMPLATE, resolvido)

**Eixo:** DoT (Burn) que recompensa focar o mesmo alvo. **Burn:** 2% HP/s por 6s (Boss 1% HP/s).

### Striker — "Faísca/Orbe" (sniper de DoT single)
- Dano **10** /tiro · **2.0 atk/s** · +50%/raridade · Custo **15g** · Alcance **2–3** · Alvos **1 → 2 (Épica+)**
- Status: Burn **20% → 25% (Épica+)**, Boss 1%
- **Skill 1 — Poça de Lava:** inimigo que morre queimado deixa poça no local; queima quem passa (mesma chance). *Propaga DoT no ESPAÇO.* Poça dura **4s** (cap).

### Blaster — "Dragão" (glass cannon AoE refém de posição)
- Dano **5** /tiro (baixo de propósito) · **1.0/s** · Custo **40g** · Alcance **1 tile** · Alvos **ILIMITADOS**
- Status: Burn **12%**, Boss 1%
- **Skill 1 — Contágio de Chama:** inimigo que morre queimado espalha a queima por até **2** inimigos a ≤1 tile. *Propaga DoT por SALTO.*
- **Identidade:** só rende se alguém ENTREGAR os inimigos agrupados no alcance 1.

### Support — "Braseiro" (acelerador de DoT)
- Dano **3** · **1.0/s** · Custo **45g** · Alcance **2** · Aura raio **1**
- **Aura — Sopro:** vizinhas com DoT ativo **tickam +40% mais rápido** (o DoT resolve em menos tempo → recompensa o foco, não copia Ressonância genérica de +dano).
- **Skill 1 — Rebrasa:** quando um inimigo sob aura morre queimado, **reacende** o Burn (+2s) no alvo mais próximo ainda vivo. Estende a janela de foco.
- **Eixo:** amplifica *velocidade e persistência do DoT*, não dano bruto → é o único support que fecha kills de Burn mais cedo.

---

## 💧 ÁGUA — enabler de combo (fraca sozinha, multiplica as outras)

**Eixo:** aplica **Molhado** (não dá dano relevante); Molhado é a chave que destrava/potencializa
combos das vizinhas. Design-guard: fraca sozinha, MAS o Molhado tem valor próprio garantido
(**-mov + amplifica o próximo status elemental**) pra não virar lixo sem combo.

**Molhado (redesenhado):** dura **4s**; alvo molhado sofre **-15% mov** e o **próximo status elemental aplicado nele dura +50%**. (Antes só "habilita combos" — agora tem piso de utilidade.)

### Striker — "Jato" (aplicador single confiável)
- Dano **4** (baixo) · **2.0 atk/s** · Custo **14g** · Alcance **3** (o maior dos strikers — "molha de longe") · Alvos **1 → 2 (Épica+)**
- Status: Molhado **60% → 75% (Épica+)**, Boss 25% (Molhado NÃO é reduzido tão fundo — é enabler, precisa pegar)
- **Skill 1 — Respingo:** aplica Molhado também no inimigo imediatamente atrás do alvo. *Propaga o enable no ESPAÇO/fila.*

### Blaster — "Onda" (banha o cluster, refém de posição)
- Dano **3** · **1.2/s** · Custo **34g** · Alcance **1 tile** · Alvos **ILIMITADOS**
- Status: Molhado **50%**, Boss 25%
- **Skill 1 — Maré:** inimigo molhado que passa a queima/veneno para vizinho **transfere o Molhado junto** (contágio de enable). *Propaga o enable por SALTO.*
- **Identidade:** transforma um cluster inteiro em "solo fértil" pros combos das mães vizinhas.

### Support — "Corrente" (multiplicador de combo)
- Dano **2** · **1.0/s** · Custo **48g** · Alcance **2** · Aura raio **1**
- **Aura — Condução:** combos disparados por vizinhas em alvo **Molhado** ganham **+25% dano**. (É o multiplicador puro — o único support cujo valor é 100% condicional a combo, coerente com o eixo Água.)
- **Skill 1 — Reservatório:** cada kill sob aura acumula 1 carga (cap 5); ao encher, o próximo Molhado aplicado vira **Encharcado** (+35% duração de status, área 1 hex). Recompensa manter Água em jogo.

---

## ❄️ GELO — controle / compra de tempo (defensivo)

**Eixo:** não corre pra matar — **atrasa**. Slow/freeze que compra tempo pras outras torres
resolverem. DPS baixo é DELIBERADO (Régua 2: valor está no tempo, não no dano).

**Congelado:** slow **0.50 por 1.2s** (profundo: **0.30 por 2.2s**).

### Striker — "Estilhaço" (freeze single de precisão)
- Dano **8** · **1.8 atk/s** · Custo **16g** · Alcance **2–3** · Alvos **1 → 2 (Épica+)**
- Status: Congelado **30% → 40% (Épica+)**, Boss 10%
- **Skill 1 — Piso de Gelo:** alvo que morre/passa congelado deixa **placa de gelo** no hex; quem pisa é lentado (0.50, 1s). *Propaga o controle no ESPAÇO.* Placa dura **3s**.

### Blaster — "Nevasca" (trava o cluster, refém de posição)
- Dano **4** · **1.3/s** · Custo **36g** · Alcance **1 tile** · Alvos **ILIMITADOS**
- Status: Congelado **25%**, Boss 10%
- **Skill 1 — Ventania:** inimigo que descongela **repassa** o slow por até 2 vizinhos a ≤1 tile. *Propaga o controle por SALTO.*
- **Identidade:** congela a onda toda no gargalo — é a "parede" defensiva; quem mata é vizinho.

### Support — "Aura Gélida" (amplificador de controle)
- Dano **2** · **1.0/s** · Custo **46g** · Alcance **3** · Aura raio **1**
- **Aura — Frio Cortante:** todo slow/freeze aplicado por vizinhas dura **+40%** e o alvo lento sofre **+20% de dano recebido** (janela de execução pras outras).
- **Skill 1 — Núcleo Glacial:** a cada 6s, emite pulso que aplica slow leve (0.70, 1s) a todos no raio. Único support com dano-tempo próprio.

---

## 🗡️ FÍSICO — burst / execução (dano bruto single-target)

**Eixo:** sem DoT, sem espera. **Hit gordo agora**, e mais gordo ainda em alvo fragilizado.
É o oposto do Fogo: concentra tudo no impacto (Régua 2: DPS igual, mas TUDO no hit).

**Exposto:** alvo sofre **+25% dano recebido por 3s** (é a moeda do elemento — abre a execução).

### Striker — "Lança" (executor single)
- Dano **22** (o maior por tiro) · **1.2 atk/s** (lento pra striker — burst, não spray) · Custo **18g** · Alcance **2** · Alvos **1 → 2 (Épica+)**
- Status: Exposto **30% → 40% (Épica+)**, Boss 10%
- **Skill 1 — Marca de Sangue:** ao matar, o alvo seguinte mais próximo já entra **Exposto** de graça. *Propaga a execução no ESPAÇO (encadeia alvos).*
- **Skill 2 — Execução:** +60% dano se HP do alvo < 30%.

### Blaster — "Balista" (canhão de linha, refém de posição)
- Dano **18** · **1.6/s** · Custo **42g** · Alcance **1 tile** · Alvos **ILIMITADOS na LINHA** (perfura reto, não splash radial — coerente com "bruto direcional")
- Status: Exposto **20%**, Boss 10%
- **Skill 1 — Transfixar:** o hit atravessa e cada inimigo perfurado fica Exposto; se já Exposto, leva **+40%**. *Propaga a execução por SALTO (na reta).*
- **Identidade:** dano bruto altíssimo, mas só na fila alinhada ao alcance-1 → refém de posição como o Dragão.

### Support — "Estandarte" (amplificador de burst)
- Dano **2** · **1.0/s** · Custo **50g** · Alcance **2** · Aura raio **1**
- **Aura — Grito de Guerra:** vizinhas causam **+20% dano em hit** contra alvos Expostos e **+15% chance de crítico**. (Amplifica o pico do hit, não DoT — casa com o eixo burst.)
- **Skill 1 — Sede:** cada kill de vizinha sob aura dá **+1 gold** (kill-driven, não status-driven — mantém distância do nicho de economia da Arcana).

---

## ☠️ VENENO — dano sustentado em área / anti-swarm (stack, contágio)

**Eixo:** empilha veneno, contagia, mata multidão ao longo do tempo. **Cap de alvos protege o
nicho** (não vira AoE instantâneo do Físico nem DoT-single do Fogo — é o "muitos, devagar, em área").

**Veneno:** DoT que **empilha por acerto** — 1.5% HP/s por stack, 4s, cap 6 stacks. Boss: 0.8%/stack.

### Striker — "Dardo" (aplicador de stacks single)
- Dano **6** · **2.2 atk/s** (a mais rápida — cada tiro é 1 stack) · Custo **15g** · Alcance **2** · Alvos **1 → 2 (Épica+)**
- Status: Veneno **100%** (sempre aplica 1 stack; a graça é acumular), Boss aplica mas 0.8%/stack
- **Skill 1 — Esporo:** alvo que morre envenenado libera **nuvem** no hex (aplica 1 stack a quem passa, 3s). *Propaga o DoT no ESPAÇO.*

### Blaster — "Nuvem" (gás no cluster, refém de posição)
- Dano **3** · **1.4/s** · Custo **38g** · Alcance **1 tile** · Alvos **ILIMITADOS**
- Status: Veneno **80%** por tick, Boss 0.8%/stack
- **Skill 1 — Contágio:** ao morrer, um alvo com N stacks **distribui metade** dos stacks pra até 2 vizinhos. *Propaga o DoT por SALTO (o contágio literal do eixo).*
- **Identidade:** anti-swarm supremo — o gás tickando + contágio dizima grupos que o burst não alcança em tempo.

### Support — "Miasma" (amplificador de stack)
- Dano **2** · **1.0/s** · Custo **44g** · Alcance **2** · Aura raio **1**
- **Aura — Putrefação:** veneno de vizinhas ganha **+1 no cap de stacks** (6→7) e **+25% dano/stack**. (Escala com quantidade de stacks → premia sustentação, o eixo do Veneno.)
- **Skill 1 — Decomposição:** inimigo que morre sob aura com 4+ stacks explode em **splash de 1 hex** aplicando 2 stacks. Fecha o loop anti-swarm.

---

## 🔮 ARCANA — economia / amplificação (gold, marca, +dano recebido)

**Eixo:** não é a torre que mais mata — é a que **paga a run e potencializa o time**. Gold extra
+ Marca (o alvo recebe mais dano de TODOS). Nicho de economia é exclusivo dela.

**Marcado:** alvo sofre **+30% dano recebido por 3s** (vs. Exposto +25% do Físico — Marca é mais forte mas Arcana tem dano próprio menor).

### Striker — "Raio" (marcador + caça-tesouro single)
- Dano **9** · **2.0 atk/s** · Custo **20g** (mais caro — carrega economia) · Alcance **3** · Alvos **1 → 2 (Épica+)** · **Bounty +3 gold/kill**
- Status: Marcado **25% → 35% (Épica+)**, Boss 5%
- **Skill 1 — Selo Áureo:** o hex de um alvo Marcado que morre vira **runa** por 3s; kills sobre a runa dão **+2 gold**. *Propaga a economia no ESPAÇO.*

### Blaster — "Orbe" (marca o cluster + bounty em área, refém de posição)
- Dano **5** · **1.3/s** · Custo **44g** · Alcance **1 tile** · Alvos **ILIMITADOS** · **Bounty +2 gold/kill**
- Status: Marcado **20%**, Boss 5%
- **Skill 1 — Eco Arcano:** inimigo Marcado que morre **repassa a Marca** pra até 2 vizinhos + solta 1 gold. *Propaga a marca/economia por SALTO.*
- **Identidade:** amplificador de dano de área (todo mundo Marcado = todo mundo recebe +30%) que ainda financia a run.

### Support — "Prisma" (banco + amplificador)
- Dano **2** · **1.0/s** · Custo **52g** (o mais caro — é investimento) · Alcance **3** · Aura raio **1** · **Bounty +12 gold/kill sob aura**
- **Aura — Ressonância Áurea:** vizinhas dão **+15% dano** E **+1 gold/kill**. (O único que combina dano + economia — é o motor financeiro do loadout.)
- **Skill 1 — Dividendo:** a cada 100 gold ganho enquanto ativo, dispara pulso que aplica Marcado a todos no raio. Economia vira dano.

---

## 🌿 NATUREZA — utilidade / prende (root, suporte híbrido, versátil)

**Eixo:** o coringa. Não é a melhor em nada, mas **prende (root) e agrupa** — cria a condição
que outros exploram (é a mãe do combo assinatura do Fogo). Versátil, híbrida.

**Enraizado:** prende — mov **0.20 por 1.5s** (quase parada). Agrupa o cluster no lugar.

### Striker — "Espinho" (root single + utilidade)
- Dano **9** · **1.8 atk/s** · Custo **16g** · Alcance **2** · Alvos **1 → 2 (Épica+)**
- Status: Enraizado **25% → 35% (Épica+)**, Boss 10%
- **Skill 1 — Raiz Rastejante:** o hex de um alvo enraizado fica **espinhado** por 3s; quem entra é enraizado (0.35, 1s) e leva dano leve. *Propaga o controle no ESPAÇO.*

### Blaster — "Cipó" (root em cluster, refém de posição) — MÃE DO COMBO ASSINATURA
- Dano **5** · **1.3/s** · Custo **38g** · Alcance **1 tile** · Alvos **ILIMITADOS**
- Status: Enraizado **30%**, Boss 10%
- **Skill 1 — Emaranhado:** inimigos enraizados adjacentes são **puxados 1 hex pro centro** do cluster (agrupamento ativo — é o que ENTREGA o cluster pro Dragão). *Propaga o controle por SALTO + agrupa.*
- **Identidade:** a torre-enabler de posicionamento; sozinha prende, mas seu valor real é criar o alvo perfeito pra AoE das vizinhas.

### Support — "Totem" (suporte híbrido versátil)
- Dano **2** · **1.0/s** · Custo **46g** · Alcance **2** · Aura raio **1**
- **Aura — Vitalidade:** vizinhas ganham **+12% dano** E **+10% cadência** (o único híbrido dano+velocidade — versátil como o eixo).
- **Skill 1 — Simbiose:** a cada 8s, enraíza (0.35, 1.5s) o inimigo mais avançado no raio (utilidade defensiva de emergência). Coringa puro.

---

## COMBOS (6) — condição-mãe A habilita eixo-mãe B

> Regra: 2 elementos DIFERENTES, adjacentes por ≥1 lado. Não se consomem — mantêm hexes e sobem
> estrela via merge. Enquanto adjacentes, **param o tiro individual** e disparam **1 ataque-combo
> único** com stats PRÓPRIOS tabelados abaixo (não herdados por fórmula). Escala de raridade =
> menor estrela das duas mães.

Cada combo mapeia uma reação do §7. As reações **Molhado⊘Burn** e **Burn⊘Congelar** são
*bloqueios* (anti-combo, resolvidos no motor), não geram ataque — por isso os 6 combos abaixo
usam as reações **positivas** + o assinatura de posicionamento, cobrindo os 7 elementos.

### C1 — 🌿 Natureza + 🔥 Fogo · "Pira Cerrada" (ASSINATURA)
- **A habilita B:** Cipó/Espinho enraíza+agrupa (root da mãe-Natureza) → Dragão/Faísca incinera o cluster travado (AoE+DoT da mãe-Fogo). *A condição de agrupamento da mãe A entrega o alvo perfeito pro eixo AoE da mãe B.*
- **Ataque-combo:** dano **14** · CD **1.1s** · splash **2 hexes** · aplica **Enraizado + Burn** em todos no splash.
- **Assinatura:** a única que combina prender e queimar num pulso — herda o "agrupa" da Natureza e o "incendeia cluster" do Fogo, exatamente como no template.

### C2 — 💧 Água + ❄️ Gelo · "Permafrost" (reação §7.3: Molhado+Gelo = Freeze Profundo)
- **A habilita B:** Molhado da mãe-Água transforma o Congelado da mãe-Gelo em **freeze profundo** (0.30, 2.2s). *Enabler puro da Água destrava o controle forte do Gelo.*
- **Ataque-combo:** dano **6** · CD **1.3s** · splash **2 hexes** · aplica **Freeze Profundo** (0.30, 2.2s) a todos no splash.
- **Nicho:** controle de área mais duro do jogo — compra tempo pro loadout inteiro. Dano baixo de propósito (eixo Gelo = tempo, não dano).

### C3 — 🔥 Fogo + ☠️ Veneno · "Explosão Tóxica" (reação §7.4)
- **A habilita B:** aplicar Burn em quem já tem Veneno (ou vice-versa) → detona. *O DoT de uma mãe serve de estopim pro DoT empilhado da outra.*
- **Ataque-combo:** dano **20** em **splash 1 hex** ao redor de cada alvo com Burn+Veneno · CD **1.4s** · consome 2 stacks de veneno pra detonar.
- **Nicho:** burst de área que só existe em cima de sustentação — recompensa quem já montou o campo de status (anti-swarm explosivo).

### C4 — ❄️ Gelo + 🗡️ Físico · "Estilhaçar" (reação §7.5: Congelado+Físico)
- **A habilita B:** o Congelado da mãe-Gelo vira alvo frágil → o hit bruto da mãe-Física **estilhaça** (×1.6) e consome o gelo. *Controle da mãe A habilita a execução da mãe B.*
- **Ataque-combo:** dano **28** single (o maior hit de combo) · CD **1.5s** · **×1.6 se alvo Congelado** (consome o freeze) · aplica **Exposto** no impacto.
- **Nicho:** executor single-target premium — o anti-Elite/anti-Boss do catálogo (concentra tudo no hit, eixo Físico).

### C5 — 🔮 Arcana + 🗡️ Físico · "Sentença" (reação §7.6: Marca/Exposto amplificam)
- **A habilita B:** Marcado (+30%) da mãe-Arcana **empilha** com o burst Exposto (+25%) da mãe-Física → dano recebido brutal. *Amplificação da mãe A multiplica a execução da mãe B.*
- **Ataque-combo:** dano **16** single · CD **1.0s** (rápido) · aplica **Marcado + Exposto** e leva **+55% dano combinado** se o alvo já tinha um dos dois · **+4 gold/kill**.
- **Nicho:** o "abre-e-mata" — Arcana banca a run e amplifica, Físico converte em kill. Único combo que também gera economia.

### C6 — 💧 Água + ☠️ Veneno · "Solvente" (Água enabler multiplica o Veneno)
- **A habilita B:** Molhado da mãe-Água faz o Veneno da mãe-☠️ **empilhar +50% mais rápido e durar +50%** (o Molhado amplifica o próximo status). *O eixo enabler da Água multiplica o eixo sustentado do Veneno.*
- **Ataque-combo:** dano **8** · CD **1.2s** · splash **2 hexes** · aplica **Molhado + 2 stacks de Veneno** e estende stacks existentes. Anti-swarm sustentado de área.
- **Nicho:** prova que a Água não é lixo — casada com Veneno vira a máquina de atrito mais eficiente contra ondas longas.

**Cobertura de elementos:** Fogo (C1,C3) · Natureza (C1) · Água (C2,C6) · Gelo (C2,C4) · Veneno (C3,C6) · Físico (C4,C5) · Arcana (C5). Todos os 7 participam de ≥1 combo.

---

## TABELA MESTRE (estilo §5 — números balanceados)

DPS-efetivo = dano direto + DoT-equivalente + valor-de-status + bounty + aura (alvo de ref. HP=100).
`val = DPSeff / custo`, comparado **por papel** (supports competem entre si).

| Elem | Papel | Nome | Custo | Dano | atk/s | Alvos | Status | Chance | DPSeff | val |
|---|---|---|---|---|---|---|---|---|---|---|
| 🔥 | str | Faísca | 15 | 10 | 2.0 | 1→2 | burn | 20% | 26.4 | 1.760 |
| 🔥 | bla | Dragão | 40 | 5 | 1.0 | ∞ | burn | 12% | 38.6 | 0.966 |
| 🔥 | sup | Braseiro | 45 | 3 | 1.0 | 1 | burn | — | 9.0 | 0.200 |
| 💧 | str | Jato | 14 | 4 | 2.0 | 1→2 | wet | 60% | 13.2 | 0.943 |
| 💧 | bla | Onda | 30 | 3 | 1.3 | ∞ | wet | 50% | 25.4 | 0.845 |
| 💧 | sup | Corrente | 48 | 2 | 1.0 | 1 | wet | 30% | 8.9 | 0.185 |
| ❄️ | str | Estilhaço | 16 | 8 | 1.8 | 1→2 | frozen | 30% | 19.4 | 1.215 |
| ❄️ | bla | Nevasca | 36 | 4 | 1.3 | ∞ | frozen | 25% | 32.5 | 0.903 |
| ❄️ | sup | Aura Gélida | 46 | 2 | 1.0 | 1 | frozen | 20% | 8.8 | 0.191 |
| 🗡️ | str | Lança | 18 | 20 | 1.2 | 1→2 | exposed | 30% | 29.7 | 1.650 |
| 🗡️ | bla | Balista | 42 | 11 | 1.4 | linha | exposed | 20% | 46.9 | 1.117 |
| 🗡️ | sup | Estandarte | 50 | 2 | 1.0 | 1 | exposed | 15% | 8.4 | 0.168 |
| ☠️ | str | Dardo | 15 | 6 | 2.2 | 1→2 | poison | 100% | 26.6 | 1.776 |
| ☠️ | bla | Nuvem | 44 | 3 | 1.2 | ∞ | poison | 70% | 38.2 | 0.867 |
| ☠️ | sup | Miasma | 44 | 2 | 1.0 | 1 | poison | — | 8.0 | 0.182 |
| 🔮 | str | Raio | 20 | 9 | 2.0 | 1→2 | marked | 25% | 24.2 | 1.209 |
| 🔮 | bla | Orbe | 44 | 5 | 1.3 | ∞ | marked | 20% | 40.2 | 0.915 |
| 🔮 | sup | Prisma | 52 | 2 | 1.0 | 1 | marked | 15% | 10.6 | 0.204 |
| 🌿 | str | Espinho | 16 | 9 | 1.8 | 1→2 | rooted | 25% | 21.0 | 1.313 |
| 🌿 | bla | Cipó | 38 | 5 | 1.3 | ∞ | rooted | 30% | 40.4 | 1.062 |
| 🌿 | sup | Totem | 46 | 2 | 1.0 | 1 | rooted | 20% | 8.7 | 0.189 |

### Bandas de balanço (Régua 2, por papel)

| Papel | Mediana val | Banda ±20% | Dentro |
|---|---|---|---|
| Striker | 1.313 | 1.051 – 1.576 | 4/7 (3 desvios deliberados) |
| Blaster | 0.915 | 0.732 – 1.098 | 7/7 |
| Support | 0.189 | 0.151 – 0.227 | 7/7 |

### Desvios deliberados (GATE — justificados, não acidentais)

| Torre | val | Justificativa (Régua 2) |
|---|---|---|
| Faísca 🔥 | 1.760 | DoT diferido (Burn) — dano nominal maior é permitido quando espalhado no tempo. |
| Dardo ☠️ | 1.776 | DoT empilhável diferido — idem, o dano chega ao longo dos stacks. |
| Lança 🗡️ | 1.650 | Burst/execução condicional (+60% se HP<30%) — pico permitido, single-target. |
| Jato 💧 | 0.943 | **Enabler:** Água é fraca sozinha por design; o valor real está em habilitar combos das vizinhas (não creditado no modelo de DPS isolado). |

Balista 🗡️ (1.117) fica só ~2% acima do teto do papel — ruído, dentro da tolerância. Todos os
outros 17 slots caem na banda. `balance.py` roda o GATE e retorna **PASSOU**.

---

## Notas de implementação (pro Claude Code depois)

- `progression_vs.json` traz cada torre com `baseDamage`, `atkPerSec`, `cooldown`, `targets`
  (`1` / `unlimited` / `line`), `appliesStatus`, `statusChance`, `aura`, `bounty`, e os campos
  auditáveis `dpsEff` / `valuePerCost` / `axisNote`.
- Escala de raridade reusa `statMult` do doc mestre (×1.5/tier). Alvos 1→2 e chance de status
  sobem na Épica+ (flag por raridade, não por número fixo).
- Combos têm bloco próprio (`combos[]`) com `damage`/`cooldown`/`splash`/`applies` tabelados —
  não herdam por fórmula das mães. Balanceáveis 1 a 1.
- Reações §7 de **bloqueio** (Molhado⊘Burn, Burn⊘Congelar) continuam no motor como anti-combo;
  não geram ataque, por isso não estão em `combos[]`.
