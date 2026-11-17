# Plano de Implementação: Pesos, Arrasto e Cyberwares

Este plano divide a implementação de [`especificacao_cyberwares_e_pesos.md`](especificacao_cyberwares_e_pesos.md) em 6 fases e 20 tarefas. Cada tarefa tem dono de arquivo, modelo, dependência e critério de aceite. O objetivo é gastar o modelo mais caro só onde um erro custa caro (física autoritativa e rede) e entregar o resto a subagentes baratos com briefings fechados, que não precisam explorar o repositório.

---

## 1. Arquitetura

Hoje `player.gd` tem 997 linhas e concentra movimento, corpo, rede e dano. Se cada implante entrar direto nele, todas as tarefas de implante disputam o mesmo arquivo e não podem rodar em paralelo. A arquitetura abaixo isola cada implante num arquivo próprio e deixa no `Player` só pontos de gancho.

### 1.1 Componentes novos

| Componente | Arquivo | Papel |
| :--- | :--- | :--- |
| `HitSource` e tabela de ruído | `scripts/autoload/game.gd` | `enum HitSource` e constantes `NOISE_*` da spec 2.2, mais `Game.noise_radius(loudness)` usado pelo monstro |
| `ImplantEffects` | `scripts/player/implant_effects.gd` | Nó filho do `Player`. Recalcula os modificadores agregados quando `body_parts_changed` dispara e cria um nó de habilidade por `ability_id` instalado |
| `ImplantAbility` | `scripts/implants/implant_ability.gd` | Classe base com ganchos virtuais: `on_landed(speed)`, `on_hit(source, damage)`, `on_exhausted()`, `on_hold_tick(prop, delta)`, `on_input(action)` |
| Habilidades | `scripts/implants/{forklift_jitter, pneumatic_valve, scanner_pulse, coil_discharge, mule_overload}.gd` | Uma por implante, cada uma num arquivo que só a sua tarefa toca |
| `ScannerOverlay` | `scripts/ui/scanner_overlay.gd` | Marcadores através de paredes, estática e visão noturna, só no cliente local |
| `PropDrag` | `scripts/props/prop_drag.gd` | Nó filho do `Prop` no servidor. Detecta `Dragging` e aplica ruído, abrasão e frenagem (spec 3.5) |
| `ImplantPool` | `scripts/loot/implant_pool.gd` | `Resource` com os implantes agrupados por raridade e `implant_chance`, exportado em `Main` |

### 1.2 Ganchos no `Player`

O `Player` ganha poucas linhas, todas na fase 4A, e depois disso nenhuma tarefa de implante volta a mexer nele:

- **Leitura de modificadores:** `server_hit` multiplica o dano por `implants.damage_mult(source)`; `_update_movement` usa `implants.move_speed_mult()` e `implants.stamina_regen_mult()`; a checagem de queda usa `get_safe_fall_speed()`, que soma `implants.fall_speed_bonus()`; `send_voice` e `_voice_frame` aplicam `implants.voice_mult()` e `implants.voice_cap()`.
- **Eventos:** sinais `landed(fall_speed)`, `hit_received(source, damage)`, `exhausted()` e `implant_action_pressed()` (tecla nova `implant_action`), repassados por `ImplantEffects` às habilidades instaladas.
- **Alvo do agarre:** `get_hold_target()` soma `implants.hold_offset()`, usado pela tremedeira da empilhadeira.

### 1.3 Regras de rede

O movimento do jogador roda no cliente dono; dano, props e monstro rodam no servidor. Toda habilidade segue a mesma divisão:

- **Eventos detectados no cliente** (aterrissagem, exaustão, tecla do scanner) viram `request_*.rpc_id(1)`. O servidor confere se o implante está instalado e aplica um limite de frequência antes de agir.
- **Efeitos no mundo** (ruído, dano, ragdoll, impulso em prop) acontecem só no servidor.
- **Efeitos visuais** (overlay, estática, visão noturna, tremedeira) acontecem só quando `is_local()`.

---

## 2. Política de modelos

| Modelo | Quando usar | Exemplos |
| :--- | :--- | :--- |
| **Haiku** | Mudanças de dados ou mecânicas, com padrão já existente para copiar e sem lógica de rede | `.tres`, enum e campos de `BodyPartDef`, renomear protótipos, cores de raridade no HUD, habilidades verdes depois que a base existir |
| **Sonnet** | Código de gameplay com rede simples, seguindo interfaces já definidas | Encanamento de `HitSource`, arrasto, barricada, habilidades roxa, azul e dourada, sorteio de loot, testes de smoke |
| **Opus (sessão principal)** | Física autoritativa, sincronização entre peers e integração de fases | Troca de órgão vital, orçamento vertical compartilhado em `Prop`, revisão e merge de cada fase |

A sessão principal já tem o contexto do código e da spec. Trabalho em Opus fica nela, sem subagente Opus, para não pagar a releitura do repositório.

**Escalonamento:** se uma tarefa Haiku falhar na revisão, ela volta uma vez para Haiku com a correção apontada; na segunda falha, sobe para Sonnet. Tarefas Sonnet que falharem duas vezes voltam para a sessão principal.

---

## 3. Fases e tarefas

**Legenda:** ∥ indica que as tarefas da mesma onda rodam em paralelo, cada uma em worktree isolado. Tarefas sem ∥ rodam em série.

### Fase 0: Dados

| ID | Tarefa | Arquivos (dono exclusivo) | Modelo | Depende de |
| :--- | :--- | :--- | :--- | :--- |
| 0A | `enum Rarity` e campos novos em `BodyPartDef` (`rarity`, `fall_speed_bonus`, `grip_jitter`, `damage_reduction`, `stamina_regen_mult`, `move_speed_mult`, `voice_noise_mult`, `ability_id`, `was_installed` fica para a 5B); criar os 5 `.tres` da spec 5; renomear os protótipos para `forklift_arm.tres` e `pneumatic_leg.tres` e atualizar `main.tscn` e `Monster.DEFAULT_BODY_PARTS`; criar 8 `PropDef` de teste em `resources/props/test/` com 3, 15, 26, 35, 54, 70, 79 e 105 kg; adicionar `enum HitSource` e constantes `NOISE_*` em `game.gd` sem usá-las ainda | `body_part_def.gd`, `resources/**`, `scenes/main.tscn`, linhas de `DEFAULT_BODY_PARTS` em `monster.gd`, bloco de constantes em `game.gd` | Haiku | — |

**Aceite:** o projeto importa sem erro de script e o smoke test atual continua verde.

### Fase 1: Infraestrutura

| ID | Tarefa | Arquivos | Modelo | Depende de |
| :--- | :--- | :--- | :--- | :--- |
| 1A ∥ | Parâmetro `source` em `server_hit` de `Player`, `Monster` e `Drone` e em todos os chamadores; monstro usa `Game.noise_radius` com teto de 45 m; teto de voz `0,15` em `send_voice` e `_voice_frame`; trocar literais de ruído pelas constantes | `monster.gd`, `drone.gd`, `loadout.gd`, `world_item.gd`, `player.gd` (só `server_hit`, `_request_fall_damage`, `send_voice`, `_voice_frame`) | Sonnet | 0A |
| 1B ∥ | Troca atômica de órgão vital com canal de 2 s, cancelamento por dano ou movimento, bloqueio de G e de remoção por aliado em `HEAD`/`TORSO` de jogador vivo; barra de progresso do canal no HUD | `player.gd` (só `server_detach_part`, `server_install_part`, `server_attach_part_from_prop`, `request_detach_part`, `request_attach_part_from_prop`, `_handle_interact`, `_handle_detach_input`), `hud.gd` | Opus (principal) | 0A |
| 1C | Testes da fase: troca de cabeça mantém `alive` e `health` nos dois peers; G não remove cabeça; raio de cada fonte de ruído | `tests/smoke_test.gd` | Sonnet | 1A, 1B |

1A e 1B tocam funções diferentes de `player.gd`; o merge é feito pela sessão principal.

### Fase 2: Carga

| ID | Tarefa | Arquivos | Modelo | Depende de |
| :--- | :--- | :--- | :--- | :--- |
| 2A | `get_load_ratio()`, `get_load_zone()` e `net_load_ratio` replicado; orçamento vertical compartilhado em `_apply_holders()`; altura do alvo por zona; `people_needed()` e `people_missing()` pela razão 1,02; gancho `on_hold_tick` chamando o `ImplantEffects` de cada carregador quando existir | `prop.gd`, `player.gd` (só `get_hold_target`) | Opus (principal) | 1C |
| 2B ∥ | Velocidade pela razão (spec 3.2), bloqueio de corrida em esforço e arrasto; rótulo de zona no painel de carga | `player.gd` (só `_update_movement`), `hud.gd` (só `carry_status` e `_update_carry`) | Sonnet | 2A |
| 2C ∥ | Testes: cada prop de teste com 1 a 4 jogadores cai na zona da tabela 3.4 | `tests/smoke_test.gd` | Sonnet | 2A |

**Ponto de atenção:** o smoke test só tem 2 peers. Os casos de 3 e 4 jogadores são testados com jogadores fictícios de grip somado (um `Player` com braços de 525 ou 700 N) ou por teste unitário de `get_load_zone()` com valores injetados. A 2C decide qual e registra no relatório.

### Fase 3: Arrasto e barricada

| ID | Tarefa | Arquivos | Modelo | Depende de |
| :--- | :--- | :--- | :--- | :--- |
| 3A ∥ | `PropDrag`: detecção de `Dragging`, ruído a cada 0,4 s, abrasão a cada 4 m, `linear_damp` ao soltar; o `Prop` cria o nó no servidor | `prop_drag.gd` (novo), 3 linhas em `prop.gd` `_ready` | Sonnet | 2A |
| 3B ∥ | Barricada: monstro empurra props até 600 N; após 4 s bloqueado, golpeia o prop (−10% do valor original e impulso) | `monster.gd` | Sonnet | 1A |
| 3C | Testes de arrasto e barricada | `tests/smoke_test.gd` | Sonnet | 3A, 3B |

### Fase 4: Implantes

| ID | Tarefa | Arquivos | Modelo | Depende de |
| :--- | :--- | :--- | :--- | :--- |
| 4A | `ImplantEffects`, `ImplantAbility`, todos os ganchos da seção 1.2 e a ação de input `implant_action`. Os atributos passivos dos 5 implantes passam a valer por dados | `implant_effects.gd`, `implant_ability.gd` (novos), `player.gd`, `project.godot` (input) | Sonnet | 2B |
| 4B ∥ | Empilhadeira (tremedeira local) e pneumática (ruído de aterrissagem e exaustão, desvio lateral no pulo assimétrico) | `forklift_jitter.gd`, `pneumatic_valve.gd` | Haiku | 4A |
| 4C ∥ | Bobina: descarga em `MONSTER` e exaustão, recarga compartilhada de 12 s, efeito em monstro, drones e aliados, ruído | `coil_discharge.gd` | Sonnet | 4A |
| 4D ∥ | Scanner: pulso com recarga no servidor, lista de alvos enviada ao dono, overlay, visão noturna, estática, ruído do pulso | `scanner_pulse.gd`, `scanner_overlay.gd` (novos) | Sonnet | 4A |
| 4E ∥ | Mão de Mula: estabilizador de impacto (−50%) e sobrecarga (aviso, repulsão, ruído) | `mule_overload.gd`, 2 linhas em `prop.gd` `_on_body_entered` | Sonnet | 4A |
| 4F | Testes dos 5 implantes | `tests/smoke_test.gd` | Sonnet | 4B a 4E |

### Fase 5: Economia e interface

| ID | Tarefa | Arquivos | Modelo | Depende de |
| :--- | :--- | :--- | :--- | :--- |
| 5A ∥ | `ImplantPool`, sorteio em dois estágios em `Main`, monstro sorteia 2 verdes ao surgir | `implant_pool.gd` (novo), `main.gd`, `main.tscn`, `monster.gd` | Sonnet | 4F |
| 5B ∥ | Lacre rompido: `was_installed` no valor salvo e no `Prop`, −25% ao remover, rótulo "lacre rompido" e cor de raridade no rótulo de mira | `player.gd` (só `server_detach_part` e `_update_hover`), `prop.gd` (só `setup`) | Sonnet | 4F |
| 5C ∥ | Cor de raridade nos cards do `BodyHudModal` e na barra do HUD | `hud.gd` | Haiku | 4F |
| 5D | Testes de sorteio e lacre | `tests/smoke_test.gd` | Sonnet | 5A, 5B |

---

## 4. Briefing dos subagentes

Cada subagente começa sem contexto. Para não gastar tokens explorando o repositório, o briefing traz tudo o que a tarefa precisa e proíbe o resto:

1. **Objetivo** em 2 ou 3 frases e a seção exata da spec, com os números copiados no próprio briefing.
2. **Arquivos e funções permitidos**, com as linhas aproximadas. Qualquer outro arquivo é proibido.
3. **Interfaces fixas:** assinaturas que a tarefa deve criar ou consumir (por exemplo, `server_hit(damage, knock, stun, source)`), para que tarefas paralelas encaixem sem conversar.
4. **Convenções do projeto:** GDScript tipado, comentários `##` em português, nada de dependência externa, servidor autoritativo.
5. **Critério de aceite** da tabela da fase.
6. **Formato do relatório:** até 150 palavras, com arquivos alterados, decisões tomadas fora do briefing e o que não foi verificado. Sem colar diff.

Tarefas paralelas usam `isolation: worktree`. A sessão principal faz o merge, lê o diff e roda o smoke test antes de liberar a onda seguinte.

---

## 5. Portões de verificação

Cada fase fecha com três checagens na sessão principal:

- **Leitura do diff:** conferir que a tarefa ficou nos arquivos permitidos e respeitou as interfaces.
- **Smoke test:** `tests/run_smoke.sh <caminho do godot>` verde, sem `SCRIPT ERROR` novo.
- **Teste em janela (fases 2, 3 e 4):** uma sessão com 2 instâncias para sentir peso, arrasto e implantes, já que o smoke test não mede sensação de jogo.

Ao fim da fase 5, uma revisão de código completa da branch (`/code-review high`) antes do merge em `main`.

---

## 6. Custo estimado

| Modelo | Tarefas | Observação |
| :--- | :--- | :--- |
| Haiku | 3 (0A, 4B, 5C) | Briefings curtos, arquivos pequenos ou novos |
| Sonnet | 15 | A maior parte do código e todos os testes |
| Opus (principal) | 2 (1B, 2A) | Mais a leitura de diff, o merge e o smoke test de cada fase |

Os maiores consumos previstos são a 2A (física de `Prop`, sensível a ajuste fino) e os testes de rede (1C, 2C, 4F), que precisam ler a estrutura de `smoke_test.gd` (cerca de 700 linhas). Para reduzir esse custo, a 1C documenta no topo do arquivo de teste os auxiliares existentes (`place`, `wait_until`, `check`, comandos host-cliente), e as tarefas de teste seguintes recebem só esse resumo.

---

## 7. Pré-requisitos e decisões pendentes

- **Binário do Godot 4.7.2:** não há `godot` no `PATH` desta máquina. Sem o caminho do executável, nenhum subagente consegue rodar o smoke test, e os portões da seção 5 viram verificação manual.
- **Valores dos props atuais:** caixa (8 kg, US$ 25–60), vaso (4 kg, US$ 70–140) e rack (55 kg, US$ 180–320) estão fora das faixas de valor das categorias 2 e 5. A 0A precisa saber se esses `.tres` são reajustados ou mantidos.
- **Branch:** o trabalho sai de `friendslop-template` numa branch própria (sugestão: `feat/cyberwares`), com um commit por fase.
