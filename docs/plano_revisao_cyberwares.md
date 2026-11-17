# Plano de Revisão: Pesos, Arrasto e Cyberwares

📌 **Aplicado em 17/11/2026:** a spec foi reescrita com estas correções e com a tabela de balanceamento aprovada. A partir daqui a spec é a fonte canônica dos valores; este plano fica como registro da análise.

Este plano corrige a especificação [`especificacao_cyberwares_e_pesos.md`](especificacao_cyberwares_e_pesos.md) antes da implementação. Cada problema abaixo foi conferido contra o código da branch `friendslop-template` em 17/11/2026. Os valores dos 5 implantes ficam fora deste documento, numa tabela de balanceamento separada que aguarda aprovação; a seção 4 diz onde ela entra na spec.

---

## 1. Decisões já fechadas

- **Instalar implante nunca mata:** trocar cabeça ou tronco é uma operação atômica. O órgão antigo cai no chão como `Prop` com o valor que tinha, e o jogador continua vivo durante toda a troca.
- **Comportamento emerge da razão força/peso:** a física de mola continua sendo quem move o objeto. As zonas (folga, esforço, arrasto, imóvel) passam a ser uma classificação calculada num único lugar e consumida por HUD, velocidade, ruído e abrasão.
- **Categorias de peso derivam dos limiares:** as faixas de massa foram recalculadas a partir dos limiares 1,35 / 1,02 / 0,65, sem buracos entre categorias.

---

## 2. Problemas e soluções

### P1. Instalar órgão vital mata o jogador

**Causa no código:** `Player.server_attach_part_from_prop` chama `server_detach_part` no slot ocupado, e esse método zera a vida quando `def.vital` é verdadeiro (`scripts/player/player.gd`, bloco `if def.vital and alive`).

**Solução:** adicionar o parâmetro `lethal := true` em `server_detach_part`. O caminho de instalação passa `lethal = false` e envia o estado final do corpo num único `_sync_body_parts`, para nenhum cliente observar um corpo sem cabeça entre o detach e o install. Slots vitais exigem um canal de instalação de `2,0 s` com o jogador parado; levar dano ou se mover cancela o canal e devolve o implante ao chão. O canal é o custo da troca, no lugar da morte.

**Remoção manual de órgão vital:** a tecla G e a remoção feita por aliado deixam de aceitar `HEAD` e `TORSO` de jogador vivo. Esses slots só mudam por troca. No `Monster`, arrancar cabeça ou tronco continua letal.

**Aceite:** smoke test instala uma cabeça cibernética num jogador vivo com 100 de vida e verifica `alive == true`, `health == 100`, a cabeça orgânica como `Prop` no chão e `has_vital_parts() == true` em todos os peers.

### P2. Ruído satura em 28 m e apaga a diferença entre efeitos

**Causa no código:** `Monster._on_noise` usa `minf(loudness * 180, 28)`. Qualquer `loudness >= 0,156` já atinge o raio máximo. Hoje o tiro (`shot_noise = 0,5`), a pneumática da spec (0,35), a bobina (0,6) e a sobrecarga dourada (0,8) produzem o mesmo raio.

**Solução:** subir `max_hearing_range` para `45 m` (saturação em `0,25`) e concentrar os valores numa tabela única de constantes em `scripts/autoload/game.gd`. A voz recebe um teto próprio de `0,15` (27 m) em `Player.send_voice` e `Player._voice_frame`, que preserva o alcance atual de grito. Com a cabeça scanner o teto da voz passa a `0,20` (36 m).

| Fonte | `loudness` | Raio |
| :--- | :--- | :--- |
| Voz mínima (gate de `0,015`) | `0,015` | `2,7 m` |
| Corrida (`SPRINT_NOISE`) | `0,06` | `10,8 m` |
| Pulso do scanner | `0,08` | `14,4 m` |
| Pneumática (aterrissagem ou corrida exausta) | `0,10` | `18 m` |
| Arrasto | `0,02 – 0,12` | `3 – 22 m` |
| Voz (teto normal) | `0,15` | `27 m` |
| Descarga da bobina | `0,20` | `36 m` |
| Sobrecarga do braço dourado | `0,25` | `45 m` |
| Tiro de revólver | `0,5` | `45 m` (teto) |

**Fórmula do arrasto:** `loudness = (0,03 + 0,0009 × massa) × clamp(v_horizontal / 1,5, 0,3, 1,0)`, emitida a cada `0,4 s`. Um rack de 70 kg puxado a 1,5 m/s é ouvido a 16,7 m; puxado devagar (0,45 m/s), a 5 m. O grupo que arrasta devagar é ouvido de perto apenas.

**Aceite:** teste unitário do raio para cada linha da tabela; tiro e sobrecarga continuam no teto, pneumática e bobina ficam abaixo dele.

### P3. `server_hit` não sabe quem causou o dano

**Causa no código:** `Player.server_hit(damage, knock, stun)` recebe só números. A bobina precisa distinguir golpe do `Monster`, e a redução de dano precisa excluir queda.

**Solução:** criar `enum HitSource { GENERIC, MONSTER, WEAPON, EXPLOSION, FALL, DISCHARGE }` e adicionar `source := HitSource.GENERIC` ao fim da assinatura de `server_hit` em `Player`, `Monster` e `Drone`. Chamadores a atualizar: `Monster._try_attack` (MONSTER), `Loadout` para revólver e cacetete (WEAPON), `WorldItem` para granada (EXPLOSION) e cacetete arremessado (WEAPON), `Player._request_fall_damage` (FALL).

### P4. Zonas de força competem com a física de mola

**Causa no código:** `Prop._apply_holders` limita o vetor inteiro de cada carregador a `get_grip_force()` e puxa para o alvo individual de cada um. Com várias pessoas, parte da força se anula na horizontal, então a soma dos grips é só um limite superior. `people_needed()` usa `ceil(peso / 350)`, que equivale a razão 1,0 e contradiz os limiares 1,02 e 1,35.

**Solução:**

1. **Fonte única:** `Prop.get_load_ratio()` retorna `Σ grip_force dos carregadores / (massa × g)`. `Prop.get_load_zone()` aplica os limiares. O servidor replica `net_load_ratio` para que HUD e velocidade no cliente leiam o mesmo número.
2. **Orçamento vertical compartilhado:** a força vertical de sustentação sai de um pool com `Σ grip`. Só a sobra de cada carregador vai para a mola horizontal em direção ao alvo dele. A conta das tabelas fica exata e o cabo de guerra horizontal entre jogadores continua existindo.
3. **Altura do alvo por zona:** em folga o alvo fica na mira; em esforço o alvo desce para a altura da cintura (`0,9 m` do chão) e o `angular_damp` cai para o objeto balançar; em arrasto o alvo vertical fica no chão.
4. **HUD:** `people_needed()` e `people_missing()` passam a calcular quantos jogadores orgânicos (350 N) faltam para chegar a razão `1,02`, usando a força real de quem já segura.

**Aceite:** props de teste com 26, 35, 54, 70 e 105 kg, levantados por 1 a 4 jogadores no smoke test, caem na zona prevista pela tabela 3.2.

### P5. Velocidade de transporte ignora quem está ajudando

**Causa no código:** `Player._update_movement` aplica `clampf(1 - massa / 120, 0,45, 1,0)` a cada carregador, sem considerar a força total do grupo.

**Solução:** o multiplicador de velocidade passa a depender só de `net_load_ratio` (`r`). Correr fica bloqueado em esforço e arrasto.

| Zona | Faixa de `r` | Multiplicador de velocidade |
| :--- | :--- | :--- |
| Folga leve | `r ≥ 4,0` | `100%` |
| Folga | `1,35 ≤ r < 4,0` | `75% + 25% × (r − 1,35) / 2,65` |
| Esforço | `1,02 ≤ r < 1,35` | `55% + 20% × (r − 1,02) / 0,33` |
| Arrasto | `0,65 ≤ r < 1,02` | `25% + 20% × (r − 0,65) / 0,37` |
| Imóvel | `r < 0,65` | objeto parado; o agarre solta ao passar de `BREAK_RANGE` (5,5 m) |

O salto de 45% para 55% em `r = 1,02` é intencional: marca o momento em que o objeto sai do chão.

### P6. Efeitos do arrasto sem detecção e um degrau que não existe

**Solução por item da seção 2.4 da spec:**

- **Detecção:** o estado `Dragging` vale quando há carregadores, o prop toca o chão (contato com normal `y > 0,7`) e a velocidade horizontal passa de `0,3 m/s`. Isso cobre também props em esforço que raspam numa rampa.
- **Ruído:** usa a fórmula de arrasto do P2, emitida a cada `0,4 s` enquanto o estado `Dragging` durar.
- **Abrasão:** o valor fixo de US$ 2–6 a cada 4 m é irrelevante para objetos de US$ 280–1.300. A perda passa a ser `1,5% × (fragility / 0,05)` do valor original a cada `4 m` arrastados. Um rack (`fragility 0,05`) arrastado por 30 m perde cerca de 11%.
- **Frenagem:** `linear_damp = 4,0` enquanto o prop toca o chão sem carregadores. O Jolt não separa atrito estático de dinâmico, então o "atraso nas curvas" sai da spec.
- **Degrau da van:** o piso da van (`Van/Floor`) termina em `y = 0`, no mesmo nível do chão da fase, então o degrau não existe. O item sai da spec. Se o degrau for desejado, ele entra como tarefa de level design separada (soleira de `0,15 m`).
- **Barricada:** sai desta seção e passa a ser regra do monstro, descrita no P7.

### P7. Barricada trava o monstro para sempre

**Causa no código:** o navmesh é assado sem os props e o `Monster` (`CharacterBody3D`) não empurra corpos rígidos. Um rack numa porta prende o monstro indefinidamente.

**Solução:** o monstro empurra props que bloqueiam seu caminho com até `600 N` horizontais. Categorias 1 a 5 cedem; a categoria 6 (686 N ou mais de peso, atrito 1,0) resiste. Se o monstro ficar bloqueado por `4 s`, ele golpeia o prop: o objeto perde `10%` do valor original e recebe um impulso que o desloca. A barricada compra tempo sem virar exploit.

### P8. Arremesso de prop não fere criaturas

O jogo não aplica dano de prop em `Monster`, `Drone` ou `Player`. A spec dependia disso no braço dourado. A tabela de balanceamento removeu esse efeito, então o sistema sai do escopo desta revisão e fica registrado como backlog.

### P9. Empurrão entre jogadores não existe

`Player._push_props` só empurra props. O efeito "empurrões corpo a corpo contra outros jogadores 1,8x" do braço de empilhadeira não tem sistema de base e sai da spec.

### P10. Peso de spawn das raridades não conversa com a `loot_table`

**Causa no código:** `Main.loot_table` sorteia todos os itens no mesmo pool, onde a caixa pesa `3,0`, o vaso `1,5` e o rack `0,8`. Faixas como `0,55–0,65` não definem um valor e não têm relação com os pesos existentes.

**Solução:** sorteio em dois estágios em `Main`. Cada ponto de prop vira implante com `implant_chance = 0,08`; caso contrário, sorteia a `loot_table` comum. Implantes sorteiam primeiro a raridade e depois o item dentro dela.

| Raridade | Chance dentro de implante | Esperado por run (~38 pontos) |
| :--- | :--- | :--- |
| `GREEN` | `60%` | `1,8` |
| `BLUE` | `28%` | `0,85` |
| `PURPLE` | `9%` | `0,27` (1 a cada ~4 runs) |
| `GOLD` | `3%` | `0,09` (1 a cada ~11 runs) |

O gerador cria 19 salas com 1 a 3 pontos cada (média de 38). O campo `spawn_weight` deixa de valer para `BodyPartDef`. O `Monster` hoje nasce com os dois protótipos; ele passa a sortear 2 partes do pool `GREEN` ao surgir.

### P11. O dilema "instalar ou vender" não existe

**Causa no código:** `ExtractionZone` soma o `net_value` de qualquer `Prop` na área, e `server_detach_part` preserva o valor salvo. O grupo usa o implante a run inteira, arranca na van e vende pelo preço cheio.

**Solução:** remover um implante cibernético que já foi instalado custa `25%` do valor atual (lacre rompido). Implante achado e nunca instalado mantém o valor integral. Os campos `body_part_values` e o `Prop` gerado carregam a flag `was_installed`, e o rótulo de mira mostra "lacre rompido".

### P12. Protótipos atuais

`cyber_left_arm.tres` (280 N) e `cyber_right_leg.tres` (0,72 / 0,75) viram os implantes 1 e 2 da tabela de balanceamento. O nome dos arquivos muda para `forklift_arm.tres` e `pneumatic_leg.tres`, e `main.tscn` e `Monster.DEFAULT_BODY_PARTS` são atualizados junto.

---

## 3. Contas corrigidas

### 3.1 Massa máxima por força total

`g = 9,8 m/s²`. Massa máxima = força / (limiar × g).

| Força total | Exemplo | Folga até | Esforço até | Arrasto até |
| :--- | :--- | :--- | :--- | :--- |
| `175 N` | 1 braço orgânico | `13,2 kg` | `17,5 kg` | `27,5 kg` |
| `350 N` | 1 jogador orgânico | `26,5 kg` | `35,0 kg` | `54,9 kg` |
| `485 N` | 1 empilhadeira + 1 orgânico | `36,7 kg` | `48,5 kg` | `76,1 kg` |
| `620 N` | 2 empilhadeiras | `46,9 kg` | `62,0 kg` | `97,3 kg` |
| `700 N` | 2 jogadores orgânicos | `52,9 kg` | `70,0 kg` | `109,9 kg` |
| `825 N` | 1 braço dourado + 1 orgânico | `62,4 kg` | `82,5 kg` | `129,5 kg` |
| `1.050 N` | 3 jogadores orgânicos | `79,4 kg` | `105,0 kg` | `164,8 kg` |
| `1.175 N` | braço dourado + 1 jogador orgânico | `88,8 kg` | `117,5 kg` | `184,5 kg` |
| `1.400 N` | 4 jogadores orgânicos | `105,8 kg` | `140,1 kg` | `219,8 kg` |

### 3.2 Categorias de peso corrigidas

As faixas agora são contíguas e saem dos limites da tabela 3.1. A célula mostra a razão `r` do início ao fim da faixa, a zona resultante e o multiplicador de velocidade do P5. Valores em dólar e exemplos de referência não mudam.

| Categoria | Massa | 1 jogador (350 N) | 2 jogadores (700 N) | 3 jogadores (1.050 N) | 4 jogadores (1.400 N) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Bolso** | `0,5 – 3 kg` | Folga, `100%` (1 braço basta) | Desnecessário | Desnecessário | Desnecessário |
| **2. Médio-leve** | `3 – 15 kg` | Folga, `100% → 85%` | Folga, `100%` | Desnecessário | Desnecessário |
| **3. Pesado solo** | `15 – 35 kg` | Folga até 26,5 kg (`85% → 75%`), esforço de 26,5 a 35 kg (`75% → 55%`) | Folga, `100% → 82%` | Folga, `100% → 91%` | Desnecessário |
| **4. Carga de dupla** | `35 – 55 kg` | Arrasto, `45% → 25%` | Folga até 53 kg (`82% → 75%`), esforço de 53 a 55 kg (`75% → 72%`) | Folga, `91% → 81%` | Folga, `100% → 87%` |
| **5. Pesada** | `55 – 70 kg` | Imóvel | Esforço, `72% → 55%` | Folga, `81% → 77%` | Folga, `87% → 82%` |
| **6. Extrema** | `70 – 105 kg` | Imóvel | Arrasto, `45% → 27%` | Folga até 79 kg (`77% → 75%`), esforço de 79 a 105 kg (`75% → 55%`) | Folga, `82% → 75%` |

**Mudanças em relação à spec original:**

- **Categoria 3** sobe o teto de 32 para 35 kg, que é o limite real do esforço solo. Abaixo de 26,5 kg o objeto vai em folga.
- **Categoria 5** deixa de ser "arrastável em dupla". Com 700 N, 55 a 70 kg ficam em esforço: a dupla ergue baixo e devagar. O arrasto em dupla passa a ser a marca da categoria 6.
- **Categoria 6** termina em 105 kg, para que 3 jogadores sempre consigam erguer. Objetos acima disso ficam reservados para uma futura categoria 7 que só sai do chão com implante.
- **O rack de servidor atual (55 kg)** cai na categoria 5: um jogador não move, uma dupla ergue em esforço.

**Ressalva:** os números valem com o orçamento vertical compartilhado do P4. Sem essa mudança, a razão real de grupos de 3 ou 4 jogadores fica abaixo da tabela.

---

## 4. Roteiro de revisão da spec

| Seção da spec | Ação |
| :--- | :--- |
| 1. Contexto | Corrigir a nota de que os protótipos estão na `loot_table` e no `Monster`; citar `HitSource`, `net_load_ratio` e o novo teto de audição. |
| 2.1 Força base | Substituir pela tabela 3.1. |
| 2.2 Zonas | Manter os limiares; acrescentar a definição de `r`, a altura do alvo por zona e a tabela de velocidade do P5. |
| 2.3 Categorias | Substituir pela tabela 3.2. |
| 2.4 Arrasto | Reescrever com a detecção, ruído, abrasão e frenagem do P6; remover degrau da van e atrito estático; mover barricada para o P7. |
| 3. Raridades | Trocar `spawn_weight` pelo sorteio em dois estágios do P10; acrescentar a penalidade de lacre do P11. |
| 4. Implantes | Substituir pelos valores da tabela de balanceamento aprovada; cabeça e tronco citam o canal de troca do P1. |
| 5. Checklist | Substituir pela seção 5 deste plano. |

Depois de editar, rodar `audit_anti_chatbotese.py` e `academic_tools.py audit-all` sobre a spec.

---

## 5. Ordem de implementação

Cada fase termina com o smoke test (`tests/run_smoke.sh`) verde e um teste novo cobrindo o aceite da fase.

1. **Infraestrutura:** P1 (troca atômica e canal), P2 (tabela de ruído e teto de 45 m), P3 (`HitSource`).
2. **Carga:** P4 (razão única, pool vertical, altura por zona), P5 (velocidade), props de teste das categorias 1 a 6 com massas de borda (3, 15, 26, 35, 54, 70, 79, 105 kg).
3. **Arrasto:** P6 e P7.
4. **Implantes:** enum `Rarity` e campos novos em `BodyPartDef`; implantes verdes (P12), depois bobina, scanner e braço dourado.
5. **Economia:** P10 (sorteio em dois estágios e equipamento do monstro) e P11 (lacre rompido); HUD com cor de raridade.

---

## 6. Decisões em aberto

- **Duração do canal de troca vital:** `2,0 s` é o valor inicial. Precisa de teste com o monstro em perseguição para saber se a troca no meio da run é viável ou só no lobby.
- **Valor de `implant_chance`:** `0,08` produz cerca de 3 implantes por run. Se o loot comum ficar escasso para bater a cota, reduzir para `0,06`.
- **Categoria 7 (acima de 105 kg):** fica fora até o braço dourado estar implementado e testado.
