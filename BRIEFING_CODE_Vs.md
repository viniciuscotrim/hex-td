# Briefing pro Claude Code — Implementar catálogo Vs redesenhado

## Contexto (leia primeiro, nesta ordem)
1. `HexTD_MASTER.md` — doc mestre auditável do jogo (fórmulas, raridades, status, modos).
2. `HexTD_Catalogo_Vs.md` — catálogo redesenhado: 21 torres (7 elementos × 3 papéis) + 6 combos, com eixos de identidade e balanço.
3. `progression_vs.json` — fonte de verdade dos números (21 towers + 6 combos, campos auditáveis).
4. `balance.py` — script que valida DPSeff/custo por papel e roda o GATE anti-alucinação. Retorna PASSOU.

**Fonte de verdade dos coeficientes:** `progression_vs.json`. Não hardcode números; leia do JSON (mantenha o hot-reload em DEBUG que já existe pra `progression.json`).

## Regras do modo (JÁ DECIDIDAS — não rediscutir)
- Vs vertical, 2 mapas idênticos, tug-of-war central (ver §10 do MASTER).
- Spawn: jogador escolhe qual torre spawnar E o hex. Torre nasce **comum**.
- Merge: só iguais (mesmo elemento+papel+raridade). 2× funde → sobe estrela. 3× exige 2×+2×. Única via de subir raridade in-run.
- Combo: 2 torres de elementos **diferentes**, adjacentes por ≥1 lado. **Não se consomem** — mantêm hexes e continuam subindo estrela via merge. Enquanto adjacentes, **param o tiro individual** e disparam **1 ataque-combo único** com stats PRÓPRIOS do bloco `combos[]` (não herdados por fórmula das mães).

## Padrão de design (do template Fogo, generalizado — respeite ao implementar)
- **Striker** — single de precisão que propaga o eixo **no ESPAÇO** (deixa algo no hex: poça/piso/runa/espinhado).
- **Blaster** — glass cannon **alcance-1, alvos ilimitados**, propaga o eixo **por SALTO/contágio** ao morrer. Exceção: **Balista (Físico)** perfura em **LINHA**, não radial.
- **Support** — dano ~0, **amplifica o eixo** das vizinhas via aura (nunca Ressonância genérica de +dano puro).

---

# TAREFAS (execute nesta ordem — há dependências reais)

Para cada tarefa: implemente, rode os testes/build, e **só avance quando passar**. Se algo quebrar, corrija antes de seguir.

## Tarefa 1 — Carregar `progression_vs.json` no data model (destrava o resto)
Estender `TowerCatalog.swift` / `Progression.swift` pra ler os 21 towers + 6 combos do JSON novo.
- Mapear campos por torre: `id`, `element`, `role`, `name`, `cost`, `baseDamage`, `atkPerSec`, `cooldown`, `targets` (`1` / `"unlimited"` / `"line"`), `targetsEpicPlus`, `appliesStatus`, `statusChance`, `aura`, `bounty`, `dpsEff`, `valuePerCost`, `axisNote`.
- Mapear bloco `combos[]`: `id`, `mothers` (2 elementos), `name`, `damage`, `cooldown`, `splash`, `applies`, e campos opcionais (`consumes`, `critVsFrozen`, `bonusIfPrimed`, `bounty`).
- Reusar `statMult` por raridade do MASTER (×1.5/tier). Alvos 1→2 e chance de status sobem na **Épica+** (flag por raridade, não número fixo).
- Manter hot-reload DEBUG.
- **Teste:** assert de que os 21 IDs carregam e que `dpsEff` computado bate o do JSON (±0.1). Estender `ProgressionTests.swift`.
- **Aceite:** build passa; 21 torres + 6 combos instanciam sem crash.

## Tarefa 2 — Status novos/alterados no `Status.swift`
- **Molhado** redesenhado: dura 4s, aplica **-15% mov** E faz o **próximo status elemental no alvo durar +50%**. (Antes era só flag de combo — agora tem efeito próprio.)
- **Veneno** empilhável: **1.5% HP/s por stack, 4s, cap 6 stacks**; Boss 0.8%/stack. Confirmar/implementar stack + cap.
- **Regra Boss:** chance de status reduzida ao aplicar em Boss — padrão **1%**, exceção **Molhado = 25%** (é enabler; se não pega, nenhum combo dispara em Boss). Ler a chance-Boss como override, não recalcular.
- Status inalterados (já no motor): Burn, Congelado, Exposto, Marcado, Enraizado — só confirme os números batem o MASTER §7.
- **Teste:** aplicar Molhado → verificar -15% mov e que o Burn/Veneno seguinte dura +50%. Aplicar Veneno 6× → cap em 6 stacks.
- **Aceite:** status resolvem com os números do catálogo; Boss recebe chance reduzida.

## Tarefa 3 — Propagação por papel (as 3 mecânicas de spread)
Coração do design. Implementar o comportamento de propagação conforme o papel:
- **Striker — no espaço:** ao matar com status, deixar efeito no hex por N segundos (poça de lava 4s, piso de gelo 3s, nuvem de esporo 3s, runa 3s, espinhado 3s, marca de sangue encadeia alvo). Ler duração/efeito do catálogo.
- **Blaster — por salto:** ao morrer, propagar o status/efeito por até 2 inimigos a ≤1 tile (contágio de chama, ventania, contágio de stacks, eco arcano, emaranhado que puxa+agrupa, maré que transfere molhado).
- **Balista (exceção):** perfura em **linha**, cada inimigo na reta fica Exposto; se já Exposto, +40%. Não é splash radial.
- **Aceite:** cada papel propaga do jeito certo; Balista não vira AoE radial (senão rouba nicho de Fogo/Veneno).

## Tarefa 4 — Sistema de combo (o mais novo — faça isolado, é o mais arriscado)
- **Detecção de adjacência:** 2 torres de elementos diferentes compartilhando ≥1 lado de hex → combo ativo enquanto adjacentes.
- **Suprimir tiro individual** das duas mães enquanto o combo está ativo.
- **Disparar o ataque-combo** com os stats do bloco `combos[]` do JSON (damage/cooldown/splash/applies) — NÃO herdar por fórmula das mães.
- **Mães não se consomem:** continuam ocupando seus hexes e podem subir estrela via merge normalmente. Escala do combo = **menor estrela das duas mães**.
- Combos a suportar (6): Pira Cerrada (nat+fire), Permafrost (water+ice), Explosão Tóxica (fire+poison), Estilhaçar (ice+phys), Sentença (arcane+phys), Solvente (water+poison).
- **Reações de bloqueio** (Molhado⊘Burn, Burn⊘Congelar) continuam como anti-combo no motor — NÃO geram ataque, não estão em `combos[]`.
- **Teste:** posicionar par adjacente → confirmar que param tiro individual, disparam combo com stats do JSON, e que quebrar a adjacência volta ao tiro individual. Merge de uma mãe durante combo não deve crashar.
- **Aceite:** os 6 combos disparam com stats próprios; mães sobrevivem e sobem estrela.

## Tarefa 5 — Merge/spawn do modo Vs
- Spawn: escolher torre + hex; nasce **comum**.
- Merge só de iguais (elemento+papel+raridade); 2×→sobe estrela; 3× exige 2×+2×.
- Integrar com o teto de estrelas (`maxStars`) e economia do Vs (renda +8/s, gold por kill tier 1–5, envio de monstro) do MASTER §10.
- **Aceite:** loop de spawn→merge→estrela funciona no VsScene; raridade sobe só via merge.

---

# Definição de pronto (global)
- `progression_vs.json` é a única fonte de números; nada hardcoded.
- Cada elemento mantém seu eixo (Régua 1) e não duplica nicho — se durante a implementação algo forçar dois elementos a fazer a mesma coisa, PARE e sinalize antes de "consertar" mudando design.
- `balance.py` continua retornando GATE: PASSOU (se você mexer em número de torre, re-rode e confirme).
- Build no simulador (`build_sim.sh`) passa após cada tarefa.

# Decisão pendente pro dono (Cotrim) confirmar antes/durante
- **Testes por tarefa vs. só build+tela:** `ProgressionTests.swift` já existe como base. Preferência: criar testes unitários por tarefa (mais lento, mais seguro) OU só rodar `build_sim.sh` e validar visualmente. Pergunte se não estiver claro.
- **Chance de Molhado em Boss (25%):** confirmar em playtest se não fica forte demais.
- **Valores dos combos:** são coeficientes de partida; não foram validados contra a curva DPS (combos têm dinâmica condicional própria). Ajuste após playtest.
