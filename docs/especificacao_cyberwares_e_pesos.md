# Especificação de Design e Implementação: Pesos, Arrasto e Cyberwares (Capivara Punk)

Este documento define o balanceamento físico de carga (categorias de peso, força de pegada e arrasto) e os **5 implantes cibernéticos iniciais**, distribuídos em quatro raridades (**Verde, Azul, Roxa e Dourada**). Ele é o guia de implementação no projeto Godot 4.7.2 `capybara-punk`. As decisões e a análise que levaram a esta versão estão em [`plano_revisao_cyberwares.md`](plano_revisao_cyberwares.md).

---

## 1. Contexto do Projeto e Base Existente no Código

O projeto é um *extraction co-op* em primeira pessoa com física autoritativa no servidor. As regras deste documento se apoiam nos sistemas abaixo.

* **Corpo modular (`scripts/player/body_part_def.gd`, `scripts/player/player.gd`, `scripts/world/monster.gd`):** jogadores e monstros têm 6 slots (`HEAD`, `TORSO`, `LEFT_ARM`, `RIGHT_ARM`, `LEFT_LEG`, `RIGHT_LEG`). `BodyPartDef` herda de `PropDef`, então qualquer membro removido existe no mundo como `Prop` físico com massa, valor e desgaste por impacto.
* **Atributos orgânicos (`resources/body_parts/organic_*.tres`):** cada braço orgânico tem `grip_force = 175.0` (`350 N` no par). Cada perna orgânica tem `leg_speed_factor = 0.5` e `leg_jump_factor = 0.5`, e os fatores das duas pernas se somam. Cabeça e tronco têm `vital = true`.
* **Protótipos atuais:** `cyber_left_arm.tres` (280 N) e `cyber_right_leg.tres` (0,72 / 0,75) estão na `loot_table` de `main.tscn` e em `Monster.DEFAULT_BODY_PARTS`. Eles são substituídos pelos implantes 1 e 2 da seção 5 (ver "Migração dos Protótipos" na seção 6).
* **Carga física (`scripts/props/prop.gd`):** `_apply_holders()` aplica, por carregador, uma mola em direção ao alvo de mira limitada a `get_grip_force()`. `ExtractionZone` soma o `net_value` de todo `Prop` dentro da van, inclusive membros.
* **Ruído (`scripts/autoload/game.gd`, `scripts/world/monster.gd`):** `Game.emit_noise(origin, loudness)` alerta o `Monster` dentro de `loudness × hearing_gain` (`hearing_gain = 180`), limitado por `max_hearing_range`.
* **Dano (`Player.server_hit`, `Monster.server_hit`, `Drone.server_hit`):** monstro causa `34` de dano por golpe; jogador tem `100` de vida; drones têm `40`. Queda e batida em parede acima de `11 m/s` (`SAFE_FALL_SPEED`) causam dano pelo mesmo `server_hit`.
* **Armas (`scripts/player/loadout.gd`):** o revólver acumula `recoil_stack` (3.º tiro tira do chão, 4.º derruba, 5.º derruba a arma). O arremesso de prop já escala com a pegada: `throw_scale = clamp(grip / 350, 0.35, 2.0)`.

---

## 2. Infraestrutura Compartilhada

Os implantes e o arrasto dependem de quatro mudanças de base. Elas vêm antes de qualquer implante.

### 2.1 Troca de Órgão Vital

Instalar um implante nunca mata. Quando o slot de destino é `HEAD` ou `TORSO`, a instalação:

1. Exige um canal de `2,0 s` com o jogador parado. Levar dano ou se mover cancela o canal e devolve o implante ao chão.
2. Chama `server_detach_part(slot, drop_pos, lethal = false)`, que remove o órgão antigo sem tocar na vida.
3. Envia o corpo final num único `_sync_body_parts`, para nenhum peer observar o jogador sem cabeça ou tronco.

O órgão antigo cai como `Prop` com o valor que tinha. A tecla G e a remoção feita por aliado não aceitam `HEAD` nem `TORSO` de jogador vivo. No `Monster`, arrancar cabeça ou tronco continua letal.

### 2.2 Tabela de Ruído

`max_hearing_range` passa de `28 m` para `45 m` (saturação em `loudness = 0,25`). Todos os valores ficam como constantes em `scripts/autoload/game.gd`. A voz tem teto próprio de `0,15` aplicado em `Player.send_voice` e `Player._voice_frame`.

| Fonte | `loudness` | Raio |
| :--- | :--- | :--- |
| Voz mínima (gate `0,015`) | `0,015` | `2,7 m` |
| Corrida (`SPRINT_NOISE`) | `0,06` | `10,8 m` |
| Pulso do scanner (implante 3) | `0,08` | `14,4 m` |
| Pneumática (implante 2) | `0,10` | `18 m` |
| Arrasto (seção 3.5) | `0,02 – 0,12` | `3 – 22 m` |
| Voz, teto normal | `0,15` | `27 m` |
| Voz, teto com cabeça scanner | `0,20` | `36 m` |
| Descarga da bobina (implante 4) | `0,20` | `36 m` |
| Sobrecarga do braço dourado (implante 5) | `0,25` | `45 m` |
| Tiro de revólver (`shot_noise`) | `0,5` | `45 m` (teto) |

### 2.3 Origem do Dano

`server_hit(damage, knock, stun, source := HitSource.GENERIC)` em `Player`, `Monster` e `Drone`, com `enum HitSource { GENERIC, MONSTER, WEAPON, EXPLOSION, FALL, DISCHARGE }`. Chamadores: `Monster._try_attack` (`MONSTER`), revólver e cacetete em `Loadout` e `WorldItem` (`WEAPON`), granada (`EXPLOSION`), `Player._request_fall_damage` (`FALL`), descarga da bobina (`DISCHARGE`).

### 2.4 Penalidade de Lacre Rompido

Remover um implante cibernético que já foi instalado reduz seu valor atual em `25%`. Implante achado e nunca instalado mantém o valor integral. A flag `was_installed` acompanha `body_part_values` e o `Prop` gerado, e o rótulo de mira mostra "lacre rompido". Sem essa regra, o grupo usa o implante a run inteira e vende pelo preço cheio na van.

---

## 3. Força, Categorias de Peso e Arrasto

### 3.1 Razão de Carga

A **razão de carga** `r` é a única medida de quanto um grupo consegue com um objeto:

$$r = \frac{\sum \text{grip\_force dos carregadores}}{m \cdot g}, \quad g = 9{,}8\ \text{m/s}^2$$

`Prop.get_load_ratio()` calcula `r` no servidor e replica em `net_load_ratio`. HUD, velocidade, ruído, abrasão e `people_needed()` / `people_missing()` leem esse valor e nenhum outro.

Para a soma valer na prática, `_apply_holders()` passa a usar um **orçamento vertical compartilhado**: a sustentação contra a gravidade sai de um pool com `Σ grip_force`, e apenas a sobra de cada carregador alimenta a mola horizontal em direção ao alvo dele. Assim o cabo de guerra horizontal continua existindo e a força vertical bate com a conta.

### 3.2 Zonas de Transporte

| Zona | Faixa de `r` | Comportamento | Velocidade dos carregadores |
| :--- | :--- | :--- | :--- |
| **Folga** | `r ≥ 1,35` | Objeto sobe até a mira e acompanha as curvas | `r ≥ 4`: `100%`; abaixo: `75% + 25% × (r − 1,35) / 2,65` |
| **Esforço** | `1,02 ≤ r < 1,35` | A base do objeto sobe no máximo `0,5 m` acima dos pés de quem carrega; `angular_damp` reduzido para o objeto balançar; sem corrida | `55% + 20% × (r − 1,02) / 0,33` |
| **Arrasto** | `0,65 ≤ r < 1,02` | O grupo alivia até 90% da força total contra o peso (no máximo 97% do peso), sem suspender o objeto, e puxa na horizontal com a pegada inteira; o objeto raspa e sofre os efeitos da seção 3.5; sem corrida | `25% + 20% × (r − 0,65) / 0,37` |
| **Imóvel** | `r < 0,65` | O objeto não sai do lugar; o agarre solta ao passar de `BREAK_RANGE` (5,5 m) | Sem penalidade |

O salto de `45%` para `55%` em `r = 1,02` marca o momento em que o objeto sai do chão. A fórmula substitui a penalidade atual `clampf(1 - massa / 120, 0,45, 1,0)` em `Player._update_movement`.

`people_missing()` informa quantos jogadores orgânicos (`350 N`) faltam para o grupo atual chegar a `r = 1,02`.

### 3.3 Massa Máxima por Força

Massa máxima = força / (limiar × g).

| Força total | Exemplo | Folga até | Esforço até | Arrasto até |
| :--- | :--- | :--- | :--- | :--- |
| `175 N` | 1 braço orgânico | `13,2 kg` | `17,5 kg` | `27,5 kg` |
| `350 N` | 1 jogador orgânico | `26,5 kg` | `35,0 kg` | `54,9 kg` |
| `485 N` | Empilhadeira + braço orgânico | `36,7 kg` | `48,5 kg` | `76,1 kg` |
| `620 N` | 2 empilhadeiras | `46,9 kg` | `62,0 kg` | `97,3 kg` |
| `700 N` | 2 jogadores orgânicos | `52,9 kg` | `70,0 kg` | `109,9 kg` |
| `825 N` | Braço dourado + braço orgânico | `62,4 kg` | `82,5 kg` | `129,5 kg` |
| `1.050 N` | 3 jogadores orgânicos | `79,4 kg` | `105,0 kg` | `164,8 kg` |
| `1.175 N` | Braço dourado + braço orgânico + 1 jogador orgânico | `88,8 kg` | `117,5 kg` | `184,5 kg` |
| `1.400 N` | 4 jogadores orgânicos | `105,8 kg` | `140,1 kg` | `219,8 kg` |

### 3.4 As 6 Categorias de Peso

As faixas são contíguas e derivam da tabela 3.3. Cada célula mostra a zona e a velocidade do início ao fim da faixa de massa.

| Categoria | Massa | 1 jogador (350 N) | 2 jogadores (700 N) | 3 jogadores (1.050 N) | 4 jogadores (1.400 N) | Valor | Exemplos (anotação) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Bolso** | `0,5 – 3 kg` | Folga, `100%` (1 braço basta) | — | — | — | `$10 – $45` | Armas leves, papéis, livros, fones |
| **2. Médio-leve** | `3 – 15 kg` | Folga, `100% → 85%` | Folga, `100%` | — | — | `$50 – $130` | Videogames, caixas de som, computadores |
| **3. Pesado solo** | `15 – 35 kg` | Folga até 26,5 kg (`85% → 75%`); esforço de 26,5 a 35 kg (`75% → 55%`) | Folga, `100% → 82%` | Folga, `100% → 91%` | — | `$140 – $260` | Ar-condicionado compacto, servidores menores |
| **4. Carga de dupla** | `35 – 55 kg` | Arrasto, `45% → 25%` | Folga até 53 kg (`82% → 75%`); esforço de 53 a 55 kg (`75% → 72%`) | Folga, `91% → 81%` | Folga, `100% → 87%` | `$280 – $450` | Racks médios, condensadoras, cofres |
| **5. Pesada** | `55 – 70 kg` | Imóvel | Esforço, `72% → 55%` | Folga, `81% → 77%` | Folga, `87% → 82%` | `$480 – $700` | Servidores industriais, rack de servidor atual (55 kg) |
| **6. Extrema** | `70 – 105 kg` | Imóvel | Arrasto, `45% → 27%` | Folga até 79 kg (`77% → 75%`); esforço de 79 a 105 kg (`75% → 55%`) | Folga, `82% → 75%` | `$750 – $1.300` | Reatores corporativos, contêineres blindados, máquinas médicas |

Objetos acima de `105 kg` ficam reservados para uma futura categoria 7, que só sai do chão com implante.

### 3.5 Efeitos do Arrasto

O estado `Dragging` vale quando o prop tem carregadores, toca o chão (contato com normal `y > 0,7`) e se move a mais de `0,3 m/s` na horizontal. Enquanto ele durar, o servidor aplica os efeitos abaixo.

1. **Ruído contínuo:** a cada `0,4 s`, `Game.emit_noise(global_position, loudness)` com `loudness = (0,03 + 0,0009 × massa) × clamp(v_horizontal / 1,5, 0,3, 1,0)`. Um objeto de 70 kg puxado a `1,5 m/s` é ouvido a `16,7 m`; puxado a `0,45 m/s`, a `5 m`. Arrastar devagar é a forma de não chamar o monstro.
2. **Abrasão:** a cada `4 m` arrastados, o objeto perde `1,5% × (fragility / 0,05)` do valor original e mostra `-$X`. Um rack (`fragility 0,05`) arrastado por 30 m perde cerca de 11%.
3. **Frenagem:** sem carregadores e em contato com o chão, o prop recebe `linear_damp = 4,0` e para logo ao ser solto.

### 3.6 Barricada e Monstro

Props bloqueando o caminho do `Monster` recebem um empurrão de até `600 N` horizontais. As categorias 1 a 5 cedem; a categoria 6 resiste (peso de 686 N ou mais com atrito 1,0). Se o monstro ficar bloqueado por `4 s`, ele golpeia o prop: o objeto perde `10%` do valor original e recebe um impulso que o tira do caminho. A barricada compra tempo sem prender o monstro para sempre.

---

## 4. Sistema de Raridades

`BodyPartDef` ganha `enum Rarity { GREEN, BLUE, PURPLE, GOLD }`. A cor aparece no HUD, no `BodyHudModal` e no rótulo de mira.

| Raridade | Identificador | Cor | Chance dentro de implante | Esperado por run | Papel na progressão |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Verde** | `GREEN` | `#4CAF50` | `60%` | `1,8` | Melhora atributos básicos com falhas barulhentas ou brutas |
| **Azul** | `BLUE` | `#29B6F6` | `28%` | `0,85` | Ferramentas sensoriais que trocam informação por exposição sonora |
| **Roxa** | `PURPLE` | `#AB47BC` | `9%` | `0,27` | Combate e sobrevivência com risco direto para o grupo |
| **Dourada** | `GOLD` | `#FFB300` | `3%` | `0,09` | Protótipos que quebram a escala de peso e disputam espaço com a cota |

**Sorteio em dois estágios (`Main`):** cada ponto de prop vira implante com `implant_chance = 0,08`; caso contrário, sorteia a `loot_table` comum. Implante sorteia primeiro a raridade e depois o item dentro dela. O gerador cria 19 salas com 1 a 3 pontos cada, média de 38 pontos por run, o que dá cerca de 3 implantes por run, um roxo a cada ~4 runs e um dourado a cada ~11. `spawn_weight` deixa de valer para `BodyPartDef`.

**Equipamento do monstro:** o `Monster` sorteia 2 partes do pool `GREEN` ao surgir, em vez dos protótipos fixos.

---

## 5. Os 5 Implantes Cibernéticos Iniciais

### Resumo

| Implante | Raridade | Slot | Massa | Valor | Arquivo |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Braço de Empilhadeira | `GREEN` | Braço | `9,5 kg` | `$140 – $200` | `forklift_arm.tres` |
| Pernas Pneumáticas | `GREEN` | Perna | `9,0 kg` | `$150 – $210` | `pneumatic_leg.tres` |
| Cabeça Scanner | `BLUE` | `HEAD` (vital) | `5,5 kg` | `$280 – $380` | `scanner_head.tres` |
| Tronco de Bobina | `PURPLE` | `TORSO` (vital) | `18,0 kg` | `$450 – $620` | `coil_torso.tres` |
| Mão de Mula | `GOLD` | Braço | `7,0 kg` | `$800 – $1.100` | `mule_arm.tres` |

Braços e pernas são instalados em qualquer lado via `resolve_install_slot`. Cabeça e tronco seguem a troca da seção 2.1.

### Implante 1: Braço de Empilhadeira Recondicionado

* **Atributos:** `grip_force = 310.0`. Com um braço orgânico, o jogador soma `485 N`; com dois desses, `620 N`.
* **Capacidade:** sozinho, com um braço desses, carrega a categoria 3 inteira em folga, ergue até `48,5 kg` e arrasta até `76 kg`. Com dois, ergue a categoria 4 inteira e o início da categoria 5 até `62 kg`.
* **Arremesso:** sem bônus próprio. A fórmula existente já rende `1,39x` com `485 N`.
* **Efeito colateral:** a hidráulica não tem ajuste fino. Correndo (`net_sprinting`) com um objeto de `fragility ≥ 0,2` ou de até `3 kg`, o alvo do agarre treme `±0,15 m`, e o objeto bate em quinas e paredes.
* **Notas técnicas:** substitui `cyber_left_arm.tres`. Adicionar `grip_jitter` em `BodyPartDef` e aplicar o deslocamento em `Player.get_hold_target()`.

### Implante 2: Pernas de Mola Pneumática

* **Atributos:** `leg_speed_factor = 0.60` e `leg_jump_factor = 0.65` por perna; `fall_speed_bonus = 2.5` por perna.
* **Capacidade:** com o par, velocidade `1,2x` (corrida a `8,4 m/s`, contra `5,2 m/s` do monstro em perseguição), pulo de `1,82 m` (orgânico: `1,08 m`) e queda segura até `16 m/s`, cerca de `13 m` de altura (orgânico: `6,2 m`). Com uma pneumática e uma orgânica: `1,1x`, pulo de `1,43 m` e queda segura de `13,5 m/s`.
* **Efeito colateral:** a válvula não tem silenciador. Aterrissar acima de `4 m/s` ou correr com a estamina abaixo de `25` emite `Game.emit_noise(global_position, 0.10)`, ouvido a `18 m`. Com uma perna só, o impulso do pulo desvia `0,6 m/s` na horizontal para o lado da perna orgânica.
* **Notas técnicas:** substitui `cyber_right_leg.tres`. Adicionar `fall_speed_bonus` em `BodyPartDef`; `SAFE_FALL_SPEED` passa a ser lido por um método que soma o bônus das pernas. Checagem de aterrissagem e exaustão em `Player._local_physics()`, com o ruído pedido ao servidor.

### Implante 3: Cabeça de Scanner Corporativo

* **Atributos:** órgão vital, instalado pela troca de `2,0 s`.
* **Visão noturna passiva:** ilumina o ambiente só para o jogador local, sem lanterna e sem facho visível para os outros.
* **Pulso de scanner:** acionado por tecla. Por `4 s`, mostra através de paredes, num raio de `14 m`, o contorno dos `Prop`s com `net_value ≥ 120`, do `Monster` e dos `Drone`s. Recarga de `20 s`.
* **Efeito colateral:** o pulso emite `0,08`, ouvido a `14,4 m`: quem aparece no scanner também escuta o jogador. O alto-falante de auditoria multiplica a voz por `1,35` antes do teto, que sobe para `0,20` (`36 m`). Qualquer `_stagger_timer` ou `_knock_timer` enche o visor de estática por `1,5 s`, cortando a visão noturna.
* **Notas técnicas:** overlay e marcadores visíveis só quando `is_local()`, em `HUD` ou `Player`. Multiplicador de voz em `Player.send_voice()` e `Player._voice_frame()`. O pulso e a recarga ficam no servidor, que envia ao cliente a lista de alvos detectados.

### Implante 4: Tronco de Bobina Eletromagnética

* **Atributos:** órgão vital, instalado pela troca de `2,0 s`. Reduz em `25%` o dano de origem `MONSTER`, `WEAPON` e `EXPLOSION` (queda não entra). `stamina_regen` `+40%`. Velocidade de caminhada e corrida `−10%`.
* **Capacidade:** o golpe do monstro cai de `34` para `26`; o jogador morre no 4.º golpe em vez do 3.º.
* **Descarga:** dispara ao receber golpe de origem `MONSTER` ou ao zerar a estamina correndo, com recarga de `12 s` compartilhada pelos dois gatilhos. Num raio de `3 m`: `Monster` recebe `20` de dano e `2,2 s` de ragdoll; `Drone`s recebem `15` de dano e ficam parados `4 s`. Todo dano da descarga usa origem `DISCHARGE`.
* **Efeito colateral:** a descarga atinge todos os aliados no mesmo raio de `3 m` com `1,2 s` de ragdoll (`_receive_knock`), e eles largam o que estiverem carregando. Emite `0,20`, ouvido a `36 m`.
* **Notas técnicas:** campos `damage_reduction`, `stamina_regen_mult`, `move_speed_mult` e `ability_id` em `BodyPartDef`. Gatilho em `Player.server_hit()` (filtrando `source`) e checagem de exaustão em `_update_movement()` com pedido ao servidor.

### Implante 5: Braço Protótipo de Repulsão Gravitacional ("Mão de Mula")

* **Atributos:** `grip_force = 650.0`. Com um braço orgânico, `825 N`; com dois desses, `1.300 N`.
* **Capacidade:** sozinho, carrega a categoria 4 em folga, a categoria 5 em folga até `62 kg` e em esforço até `70 kg`, e a categoria 6 em esforço até `82,5 kg` e em arrasto até `105 kg`. Com mais um jogador orgânico (`1.175 N`), a categoria 6 inteira sai do chão.
* **Estabilizador de carga:** enquanto este braço segura um `Prop`, a perda de valor por impacto em `Prop._on_body_entered` cai `50%`.
* **Arremesso:** usa a fórmula existente, que chega ao teto de `2,0x` com `825 N`. Sem multiplicador extra.
* **Efeito colateral:** segurar um objeto de `40 kg` ou mais por mais de `8 s` inicia um aviso sonoro acelerado de `1,5 s`. Se o objeto não for solto até o fim do aviso, o braço lança o `Prop` para a frente, o jogador cai com `knock_down(1.0)` e o ruído `0,25` alcança `45 m`.
* **Economia:** pela regra de lacre rompido (2.4), arrancar o braço para vender reduz o valor para `$600 – $825`. Isso ainda cobre sozinho as cotas dos dias 1 a 3 (`300`, `405`, `547`).
* **Notas técnicas:** redução de dano de impacto em `Prop._on_body_entered` quando algum carregador tem `ability_id = MULE`. Timer de sobrecarga no servidor em `Prop._apply_holders()`, contado por carregador.

---

## 6. Ordem de Implementação

Cada fase termina com `tests/run_smoke.sh` verde e um teste novo cobrindo o critério da fase.

1. **Infraestrutura:** troca de órgão vital (2.1), tabela de ruído (2.2) e `HitSource` (2.3). Critério: instalar cabeça cibernética num jogador vivo mantém `alive == true` e `health == 100` em todos os peers; o raio de cada fonte bate com a tabela 2.2.
2. **Carga:** razão `r` e orçamento vertical compartilhado (3.1), zonas e velocidade (3.2), `people_needed()` e `people_missing()`. Criar `PropDef`s de teste com `3`, `15`, `26`, `35`, `54`, `70`, `79` e `105 kg`. Critério: com 1 a 4 jogadores, cada prop cai na zona prevista pela tabela 3.4.
3. **Arrasto e monstro:** efeitos da seção 3.5 e barricada (3.6).
4. **Implantes:** enum `Rarity` e campos novos em `BodyPartDef` (`fall_speed_bonus`, `grip_jitter`, `damage_reduction`, `stamina_regen_mult`, `move_speed_mult`, `voice_noise_mult`, `ability_id`). Ordem: implantes 1 e 2 (substituindo os protótipos), 4, 3 e 5.
5. **Economia e interface:** sorteio em dois estágios e equipamento do monstro (4), lacre rompido (2.4), cor de raridade no HUD e no rótulo de mira, overlay do scanner e efeito de estática.

### Migração dos Protótipos

`cyber_left_arm.tres` vira `forklift_arm.tres` e `cyber_right_leg.tres` vira `pneumatic_leg.tres`. Atualizar as referências em `scenes/main.tscn` (`loot_table`) e em `Monster.DEFAULT_BODY_PARTS`; depois da fase 5, o monstro deixa de usar caminhos fixos.

---

## 7. Decisões em Aberto

* **Canal de troca vital:** `2,0 s` é o valor inicial. Precisa de teste com o monstro em perseguição para saber se a troca durante a run é viável ou se ela acontece, na prática, só no lobby.
* **`implant_chance`:** `0,08` produz cerca de 3 implantes por run. Se o loot comum ficar escasso para bater a cota, reduzir para `0,06`.
* **Categoria 7 (acima de 105 kg):** fica fora até o braço dourado estar implementado e testado.
* **Dano de prop arremessado em criaturas:** fora do escopo; nenhum implante depende dele.
