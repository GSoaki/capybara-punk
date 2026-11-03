# Catálogo Arquivo por Arquivo — Capybara Punk

Este documento cataloga **todos os arquivos do repositório** (`project.godot`, layouts de áudio, 22 scripts `.gd`, 9 cenas `.tscn`, 16 resources `.tres`, 2 arquivos de teste e 5 arquivos de documentação/configuração). Foi projetado como referência exata para desenvolvedores e agentes de IA.

---

## Sumário Rápido por Categoria

1. [Configuração Raiz e Áudio (5 arquivos)](#1-configuração-raiz-e-áudio)
2. [Autoloads — Singletons Globais (4 scripts)](#2-autoloads--singletons-globais)
3. [Orquestrador Principal (1 script + 1 cena)](#3-orquestrador-principal)
4. [Jogador, Corpo Modular e Inventário (4 scripts + 1 cena)](#4-jogador-corpo-modular-e-inventário)
5. [Props (Loot Físico) e Itens de Mundo (5 scripts + 2 cenas)](#5-props-loot-físico-e-itens-de-mundo)
6. [Mundo, Geração Procedural e Inimigos (5 scripts + 2 cenas)](#6-mundo-geração-procedural-e-inimigos)
7. [Rede / VoIP Auxiliar e Interface UI (5 scripts + 3 cenas)](#7-rede--voip-auxiliar-e-interface-ui)
8. [Catálogo de Resources `.tres` (16 arquivos)](#8-catálogo-de-resources-tres)
9. [Testes Automatizados (2 arquivos)](#9-testes-automatizados)

---

## 1. Configuração Raiz e Áudio

### `project.godot`
- **Tipo**: Configuração principal do motor Godot (`config_version=5`, Godot 4.7 Forward Plus).
- **Responsabilidade**: Define cena principal (`res://scenes/main.tscn`), habilita captura de microfone (`audio/driver/enable_input=true`), registra os 4 Autoloads, mapeia as 22 ações de input, nomeia as 6 camadas de física 3D e seleciona `Jolt Physics` e `d3d12`.
- **Autoloads Registrados** (ordem de inicialização):
  1. `Settings` -> `*res://scripts/autoload/settings.gd`
  2. `Net` -> `*res://scripts/autoload/net.gd`
  3. `Game` -> `*res://scripts/autoload/game.gd`
  4. `Voice` -> `*res://scripts/autoload/voice.gd`
- **Mapa de Ações de Input (22 ações)**:
  - Movimentação: `move_forward` (`W`), `move_back` (`S`), `move_left` (`A`), `move_right` (`D`), `jump` (`Espaço`), `sprint` (`Shift`), `crouch` (`Ctrl`).
  - Interação e Corpo: `interact` (`E`), `detach_part` (`G`), `body_hud` (`I`), `flashlight` (`F`), `toggle_camera` (`V`).
  - Mãos e Armas: `grab` (`Botão Esq. Mouse`), `throw` (`Botão Dir. Mouse`), `hold_further` (`Roda Cima`), `hold_nearer` (`Roda Baixo`), `reload` (`R`), `drop_item` (`Q`).
  - Hotbar (5 Slots): `slot_1` (`1`), `slot_2` (`2`), `slot_3` (`3`), `slot_4` (`4`), `slot_5` (`5`).
  - Sistema e Voz: `push_to_talk` (`T`), `pause` (`Esc`), `spectate_next` (`Botão Esq. Mouse`).
- **Camadas de Física 3D**:
  - Layer 1 (`bit 1`): `world` | Layer 2 (`bit 2`): `players` | Layer 3 (`bit 4`): `props` | Layer 4 (`bit 8`): `interact` | Layer 5 (`bit 16`): `monsters` | Layer 6 (`bit 32`): `items`.

### `default_bus_layout.tres`
- **Tipo**: `AudioBusLayout`.
- **Responsabilidade**: Configura a cadeia de áudio para VoIP sem retorno (eco) local:
  - Bus `0` (`Master`): Saída principal.
  - Bus `1` (`Mic`): `mute = true`, `send = &"Master"`, contém no índice `0` um efeito `AudioEffectCapture` (`resource_name = "Capture"`). O autoload `Voice` lê os buffers deste efeito.
  - Bus `2` (`Voice`): `mute = false`, `send = &"Master"`. Usado pelos nós `VoiceOutput` (`AudioStreamPlayer3D`) de cada jogador para reprodução 3D.

### `.editorconfig`, `.gitattributes`, `.gitignore` e `icon.svg`
- **Responsabilidade**: Padronização de indentação com tabs em `.gd`, normalização LF de quebras de linha no Git, exclusão da pasta `.godot/` e arquivos `.uid` gerados localmente, e ícone padrão do projeto.

---

## 2. Autoloads — Singletons Globais

### `scripts/autoload/settings.gd`
- **Classe**: `extends Node` (Singleton global `Settings`).
- **Autoridade de Rede**: Local (cada instância lê e grava seu próprio `user://settings.cfg`).
- **Responsabilidade**: Armazena e persiste preferências do usuário entre sessões via `ConfigFile`.
- **Propriedades**:
  - `PATH := "user://settings.cfg"`
  - `player_name := "Jogador"` (seção `[player]`, chave `"name"`)
  - `last_address := "127.0.0.1"` (seção `[net]`, chave `"address"`)
  - `mouse_sensitivity := 0.0025` (seção `[input]`, chave `"sensitivity"`)
  - `voice_enabled := true`, `voice_push_to_talk := false`, `voice_gate := 0.015` (seção `[voice]`)
- **Métodos Públicos**:
  - `save() -> void`: Persiste todas as propriedades em `user://settings.cfg`.

### `scripts/autoload/net.gd`
- **Classe**: `extends Node` (Singleton global `Net`).
- **Autoridade de Rede**: Servidor (`1`) gerencia o `roster` oficial e aceita/rejeita conexões; clientes recebem via RPC.
- **Responsabilidade**: Ciclo de vida da conexão ENet (`host`, `join`, `leave`), validação de versão e fase ao entrar, manutenção do dicionário `roster` (nome e cor de cada `peer_id`) e utilitário `sender_id()`.
- **Constantes e Estado**:
  - `GAME_VERSION := "0.1.0"`, `DEFAULT_PORT := 24565`, `MAX_PLAYERS := 8`, `PALETTE: Array[Color]` (8 cores distintas).
  - `roster: Dictionary` (`peer_id: int -> {"name": String, "color": Color}`).
  - `in_session: bool`.
- **Sinais**:
  - `roster_changed`
  - `player_joined(peer_id: int)`
  - `player_left(peer_id: int)`
  - `session_started`
  - `session_ended(reason: String)`
- **Métodos Públicos e RPCs**:
  - `host(port: int = DEFAULT_PORT) -> Error`: Cria servidor ENet, registra o peer `1` no `roster` e emite `session_started`.
  - `join(address: String, port: int = DEFAULT_PORT) -> Error`: Inicia conexão cliente ENet; ao conectar dispara `_on_connected_to_server()`.
  - `leave(reason: String = "") -> void`: Troca para `OfflineMultiplayerPeer`, limpa `roster` e emite `session_ended(reason)`.
  - `sender_id() -> int`: Retorna `multiplayer.get_remote_sender_id()` ou `multiplayer.get_unique_id()` quando o valor é `0` (chamada local no host).
  - `@rpc("any_peer", "call_remote", "reliable") _register(player_name: String, version: String)`: Executado no servidor; rejeita se `version != GAME_VERSION` ou `Game.phase != Game.Phase.LOBBY`; caso contrário adiciona ao `roster`, sincroniza e chama `Game.send_state_to(sender)`.
  - `@rpc("authority", "call_local", "reliable") _sync_roster(new_roster: Dictionary)`: Atualiza `roster` nos clientes e emite `session_started` na primeira sincronização.
  - `@rpc("authority", "call_remote", "reliable") _reject(reason: String)`: Define a mensagem de erro no cliente antes da desconexão pelo host.
- **Gotcha para IA**: Para integrar Steam Networking (GodotSteam), basta substituir `_create_host_peer` e `_create_client_peer` mantendo o resto intacto.

### `scripts/autoload/game.gd`
- **Classe**: `extends Node` (Singleton global `Game`).
- **Autoridade de Rede**: Servidor (`1`) executa a máquina de estados e timers; clientes recebem atualizações por RPC.
- **Responsabilidade**: Controla fases da partida (`LOBBY`, `RUN`, `RESULTS`), dias, cálculo de quota, tempo restante, registro global de nós `Player`, opção de desativar inimigos e emissão de barulho para os monstros no servidor.
- **Constantes e Estado**:
  - `enum Phase { LOBBY, RUN, RESULTS }`
  - `RUN_SECONDS := 300.0`, `RESULTS_SECONDS := 6.0`, `BASE_QUOTA := 300`, `QUOTA_GROWTH := 1.35`.
  - `phase`, `day`, `quota`, `collected`, `time_left`, `last_success`, `last_collected`, `last_quota`, `enemies_disabled`.
  - `players: Dictionary` (`peer_id: int -> Player`).
- **Sinais**:
  - `state_changed`
  - `run_started(level_seed: int)`
  - `run_ended(success: bool)`
  - `enemies_disabled_changed(disabled: bool)`
  - `noise_emitted(origin: Vector3, loudness: float)` (emitido apenas no servidor).
- **Métodos Públicos e RPCs**:
  - `local_player() -> Player`: Retorna o `Player` do `multiplayer.get_unique_id()`.
  - `register_player(player: Player)` / `unregister_player(player: Player)`.
  - `pull_lever() -> void` (Servidor): Inicia a run se estiver em `LOBBY` (sorteia seed e chama `_begin_run.rpc`) ou encerra a run se estiver em `RUN` (`end_run()`).
  - `end_run() -> void` (Servidor): Verifica se `collected >= quota`, avança o dia/multiplica a quota por `1.35` (ou reseta para dia 1 / `300`), muda para `RESULTS` por `6.0s` e chama `_finish_run.rpc`.
  - `set_collected(value: int) -> void` (Servidor): Chamado pela `ExtractionZone`; se o valor mudou, atualiza todos os peers.
  - `check_all_dead() -> void` (Servidor): Se nenhum `Player` em `players` estiver `alive`, chama `end_run()`.
  - `emit_noise(origin: Vector3, loudness: float) -> void`: Emite `noise_emitted` se estiver no servidor.
  - `set_enemies_disabled(disabled: bool) -> void`: Alterna inimigos localmente (fora de sessão), aplica no servidor ou envia `request_set_enemies_disabled.rpc_id(1, disabled)`.
  - RPCs: `request_set_enemies_disabled`, `_sync_enemies_disabled`, `_receive_state`, `_begin_run`, `_finish_run`.

### `scripts/autoload/voice.gd`
- **Classe**: `extends Node` (Singleton global `Voice`).
- **Autoridade de Rede**: Local (captura o microfone da máquina local e entrega ao `Game.local_player()`).
- **Responsabilidade**: Lê frames estéreo do `AudioEffectCapture` no bus `Mic`, converte para mono `16 kHz` em fatias de `640` amostras (`40 ms`, `FRAME_SAMPLES = 16000 / 25`), aplica gate de volume (com hold de `0.3s`) ou Push-to-Talk (`T`), codifica em Mu-law via `VoiceCodec.encode()` e chama `player.send_voice()`.
- **Propriedades**:
  - `mic_level: float` (RMS atual, lido pelo `HUD`).
  - `transmitting: bool` (se o gate/PTT está aberto).
- **Métodos Públicos**:
  - `start() -> void`: Ignora se headless ou `not Settings.voice_enabled`; cria `AudioStreamPlayer` com `AudioStreamMicrophone` no bus `&"Mic"` e ativa `_process`.
  - `stop() -> void`: Para captura e zera buffers ao sair da sessão ou desligar o microfone no menu de pausa.

---

## 3. Orquestrador Principal

### `scripts/main.gd` e `scenes/main.tscn`
- **Classe**: `class_name Main extends Node3D`.
- **Autoridade de Rede**: Todos os peers mantêm a cena; apenas o servidor invoca `.spawn()` nos `MultiplayerSpawner` e gerencia o ciclo de vida das entidades da run.
- **Responsabilidade**: Cena única da sessão. Conecta as funções customizadas de spawn aos 5 `MultiplayerSpawner`, interpreta argumentos de linha de comando (`_apply_command_line`), abre/fecha o portão da van (`$Van/Gate`), dispara a geração de nível e popula a fase após o bake do navmesh.
- **Propriedades `@export` (configuradas em `scenes/main.tscn`)**:
  - `loot_table: Array[PropDef]` -> `[crate.tres, vase.tres, server_rack.tres, cyber_left_arm.tres, cyber_right_leg.tres]`.
  - `monster_count := 1`, `drone_count := 2`, `drone_patrol_length := 4`.
  - `lobby_items: Array[ItemDef]` -> `[revolver.tres, ammo.tres, baton.tres, grenade.tres]`.
  - `item_table: Array[ItemDef]` -> `[revolver.tres, baton.tres, grenade.tres, ammo.tres]`.
- **Hierarquia de Nós em `scenes/main.tscn`**:
  - `WorldEnvironment` (ambiente escuro cyberpunk com fog), `MenuCamera` (`Camera3D`).
  - `Level` (`NavigationRegion3D` com `scripts/world/level_generator.gd`).
  - `Van` (`Node3D`): Geometria CSG (`Floor`, `Ceiling`, `WallBack`, `WallLeft`, `WallRight`, `FrontLeft`, `FrontRight`, `Gate`), `Lamp` (`OmniLight3D`), `LobbyItemSpot` (`Marker3D`), `SpawnPoints` (`P1`..`P8`), `Lever` (`StaticBody3D` na layer `4`/`bit 8`) e `ExtractionZone` (`Area3D` com `collision_mask = 4`).
  - Containers de entidades: `Players`, `Props`, `Monsters`, `Items`, `Drones` e `WeaponFx`.
  - Spawners: `PlayerSpawner`, `PropSpawner`, `MonsterSpawner`, `ItemSpawner`, `DroneSpawner`.
  - `UI` (`CanvasLayer`): Instâncias de `HUD`, `PauseMenu` e `MainMenu`.
- **Métodos Públicos**:
  - `spawn_point(index: int) -> Vector3`: Retorna a posição global de `P1`..`P8` no van.
  - `spawn_prop(def: PropDef, at: Vector3, node_name: String = "", custom_value: int = -1) -> Prop`: Instancia um `Prop` via `$PropSpawner.spawn(...)` no servidor.
  - `spawn_item(def: ItemDef, at: Vector3, velocity := Vector3.ZERO, active := false, amount := -1, thrower := 0) -> WorldItem`: Instancia um `WorldItem` via `$ItemSpawner.spawn(...)` no servidor.
  - `apply_enemies_disabled(disabled: bool) -> void`: Remove monstros/drones ativos ou os recria se reativado durante a `RUN`.
- **Argumentos de Linha de Comando Suportados (`--` após os argumentos do Godot)**:
  - `--host`, `--join=IP`, `--port=N`, `--name=Nome`, `--no-enemies` / `--disable-enemies`, `--smoke=host|client`.

---

## 4. Jogador, Corpo Modular e Inventário

### `scripts/player/player.gd` e `scenes/player.tscn`
- **Classe**: `class_name Player extends CharacterBody3D`.
- **Autoridade de Rede**: **Híbrida** — `set_multiplayer_authority(peer_id)` em `_enter_tree()`. O cliente dono controla movimento, câmera, lanterna, distância do objeto segurado e recuo. O servidor controla `health`, `alive`, `body_parts` e `body_part_values`.
- **Responsabilidade**: Controlador de personagem em 1ª e 3ª pessoa, física de locomoção, stamina, dano de queda e de batida em parede (`_check_wall_slam`), agarre de `Prop`, cirurgia de membros corporais (em si, aliados ou monstros), modo espectador pós-morte e roteamento de pacotes de voz.
- **Hierarquia de Nós em `scenes/player.tscn`**:
  - `Player` (`collision_layer = 2`, `collision_mask = 13`):
    - `Collider` (`CapsuleShape3D` duplicado em `_ready()` para permitir alturas individuais em pé `1.8m`, agachado `1.1m` e rastejando sem pernas `0.8m`).
    - `Visuals` (`Node3D`): Contém `Rig` (`PlayerRig`) e as 6 malhas (`HeadMesh` com `Visor`, `Torso`, `LeftArm`, `RightArm`, `LeftLeg`, `RightLeg`), que são reparentadas para os `BoneAttachment3D` da `Rig` em `_ready()`.
    - `Head` (`Node3D`): Contém `Camera3D`, `Flashlight` (`SpotLight3D`), `InteractRay` (`RayCast3D` de `3.5m` com `collision_mask = 63`) e `Hand` (`MeshInstance3D` do item equipado).
    - `NameLabel` (`Label3D`), `VoiceOutput` (`AudioStreamPlayer3D` no bus `&"Voice"`), `Loadout` (`Node`) e `Sync` (`MultiplayerSynchronizer` a `20 Hz`).
- **Propriedades Sincronizadas (`MultiplayerSynchronizer`)**:
  - `net_position`, `net_yaw`, `net_pitch` (modo `ALWAYS`).
  - `net_hold_distance`, `net_crouching`, `net_sprinting`, `net_knocked`, `net_flashlight`, `net_holding`, `Loadout:net_equipped` (modo `ON_CHANGE`).
- **Sinais**:
  - `body_parts_changed`: Emitido quando `_sync_body_parts` atualiza os membros instalados (ouvido pelo `Loadout` para desequipar armas caso o jogador fique sem braços).
- **Métodos Públicos e RPCs**:
  - Consultas corporais: `has_body_part(slot)`, `get_body_part_def(slot)`, `get_arm_count()`, `get_leg_count()`, `has_vital_parts()`, `get_grip_force()`, `can_hold_props()`, `get_leg_speed_multiplier()`, `get_leg_jump_multiplier()`, `get_body_summary()`, `resolve_install_slot(part_def)`, `get_aimed_slot(world_hit_point)`, `get_removable_slot_at(world_hit_point)`, `get_next_self_detach_slot()`.
  - Ações do dono: `try_grab(prop)`, `release_grab(throw)`, `can_act()`, `apply_recoil(impulse, stagger, pitch_kick, yaw_kick)`, `knock_down(seconds)`, `set_third_person(enabled)`, `send_voice(packet)`.
  - Ações do servidor: `server_detach_part(slot, drop_pos)`, `server_install_part(def, custom_value, explicit_slot)`, `server_attach_part_from_prop(prop, explicit_slot)`, `server_hit(damage, knock, stun)`, `server_revive(spawn_position)`.
  - RPCs Cliente -> Servidor: `request_detach_part(slot)`, `request_attach_part_from_prop(prop_path)`, `_request_fall_damage(speed)`.
  - RPCs Servidor -> Clientes (usam `"any_peer"` + checagem `Net.sender_id() == 1` pois a autoridade do nó `Player` é o cliente): `_sync_body_parts(new_parts)`, `_sync_vitals(new_health, is_alive)`, `_receive_knock(knock, stun)`, `_revive(spawn_position)`, `grab_lost()`.
  - RPC de Voz: `@rpc("any_peer", "call_remote", "unreliable_ordered", 1) _voice_frame(packet)`.

### `scripts/player/player_rig.gd`
- **Classe**: `class_name PlayerRig extends Node3D`.
- **Autoridade de Rede**: Local em cada peer (anima visualmente com base nas propriedades `net_*` do `Player` ou `Monster` pai).
- **Responsabilidade**: Constrói programaticamente um `Skeleton3D` de 6 ossos (`Torso`, `Head`, `LeftArm`, `RightArm`, `LeftLeg`, `RightLeg`), move as malhas para `BoneAttachment3D`, cria 6 `PhysicalBone3D` sob um `PhysicalBoneSimulator3D` e alterna entre animação procedural de mola/inércia (`update_pose`) e ragdoll físico (`start_ragdoll` / `stop_ragdoll`).
- **Métodos Públicos**:
  - `setup_rig(slot_meshes: Dictionary, owner_rid: RID) -> void`: Inicializa esqueleto, attachments, reparenta malhas e configura exceções de colisão entre os ossos físicos e o `owner_rid`.
  - `start_ragdoll(player: CharacterBody3D, impulse: Vector3 = Vector3.ZERO) -> void`: Liga `PhysicalBoneSimulator3D` apenas para os ossos presentes (`has_body_part(slot)`) e aplica impulso linear/angular.
  - `stop_ragdoll() -> void`: Desliga simulação física e reseta ângulos das molas para uma leve inclinação de recuperação.
  - `refresh_active_parts(player: CharacterBody3D) -> void`: Atualiza `collision_mask` (`5` ou `0`) dos ossos físicos conforme membros são instalados ou removidos.
  - `update_pose(delta, player, crouching, sprinting, holding, aim_pitch, voice_level) -> void`: Calcula passada, inclinação de tronco, balanço de braços (ou postura de segurar `Prop`), movimento de fala na cabeça e integra as molas com `_step_spring()`.

### `scripts/player/body_part_def.gd`
- **Classe**: `class_name BodyPartDef extends PropDef`.
- **Responsabilidade**: Define os metadados de um membro corporal modular (orgânico ou cibernético). Por herdar de `PropDef`, todo recurso `.tres` de membro é simultaneamente um tipo de `Prop` físico no mundo.
- **Enum e Constantes**:
  - `enum Slot { HEAD, TORSO, LEFT_ARM, RIGHT_ARM, LEFT_LEG, RIGHT_LEG }`
  - `ALL_SLOTS: Array[Slot]`
- **Propriedades `@export` Adicionais (além de `PropDef`)**:
  - `slot: Slot`, `is_cybernetic: bool`, `grip_force: float`, `leg_speed_factor: float`, `leg_jump_factor: float`, `vital: bool`.
- **Métodos Estáticos**:
  - `slot_name(p_slot: Slot) -> String`
  - `is_arm_slot(p_slot: Slot) -> bool`
  - `is_leg_slot(p_slot: Slot) -> bool`
  - `pair_slot(p_slot: Slot) -> int` (retorna o slot do lado oposto para braços e pernas, ou `-1` para cabeça e tronco).

### `scripts/player/loadout.gd`
- **Classe**: `class_name Loadout extends Node`.
- **Autoridade de Rede**: Híbrida — herda a autoridade do `Player` pai (cliente dono). O dono seleciona slots, prevê munição/arremesso e aplica recuo; o servidor valida cada ação (`_is_valid_request`, `_is_valid_use`), executa raycasts/spawns e sincroniza o estado autoritativo via `_sync_state`.
- **Responsabilidade**: Gerencia a hotbar de 5 slots (`SLOT_COUNT = 5`), onde o slot 1 inicia com a `Lanterna`, e implementa a mecânica completa do Revólver (com recuo acumulativo em rajada), Cacetete (melee + arremesso com avanço corporal) e Granada de impacto.
- **Estado Principal**:
  - `slot_kinds: Array[int]` (5 posições com `ItemDef.Kind`), `slot_amounts: Array[int]` (balas no tambor do revólver ou quantidade de munição no pente), `active_slot: int` (`-1` = mãos livres, `0..4` = slot ativo).
  - `reloading: bool`, `recoil_stack: int`, `net_equipped: ItemDef.Kind`.
- **Mecânica de Recuo do Revólver (`_fire` / `_apply_recoil`)**:
  - Tiros com intervalo menor que `recoil_window` (`0.45s`) incrementam `recoil_stack` e aumentam a dispersão (`recoil_spread * recoil_stack`) e a força (`recoil_force * pow(1.25, stack - 1)`).
  - No `3º` tiro seguido (`lift_stack = 3`): adiciona impulso vertical (`lift_force = 2.0`), tirando os pés do chão.
  - No `4º` tiro seguido (`knockdown_stack = 4`): derruba o atirador em ragdoll por `0.9s` (`player.knock_down(0.9)`).
  - No `5º` tiro seguido (`fumble_stack = 5`): o revólver escapa da mão (`_drop_slot`) voando para trás.
- **Métodos Públicos e RPCs**:
  - Utilitários estáticos: `Loadout.make_mesh(def: ItemDef) -> BoxMesh`, `Loadout.def_of(kind: ItemDef.Kind) -> ItemDef`.
  - Consultas: `find_slot(kind)`, `find_empty_slot()`, `get_slot_kind(index)`, `get_slot_amount(index)`, `slot_title(index)`, `slot_detail(index)`, `owns(kind)`, `can_store_object(obj)`, `can_take(def)`, `hud_text()`.
  - Entrada do dono: `select_slot(index)`, `equip(kind)`, `toggle_flashlight()`, `use_primary()`, `use_secondary()`, `reload()`, `drop_equipped()`, `try_take(item)`.
  - Servidor: `server_accept(item)`, `server_drop_all()`, `server_reset()`.
  - RPCs Cliente -> Servidor: `_request_take`, `_request_fire`, `_request_reload`, `_request_melee`, `_request_throw`, `_request_drop`.
  - RPCs Servidor -> Dono / Remotos: `_sync_state`, `_item_taken`, `_play_kick`.

---

## 5. Props (Loot Físico) e Itens de Mundo

### `scripts/props/prop_def.gd`
- **Classe**: `class_name PropDef extends Resource`.
- **Responsabilidade**: Classe base de dados para qualquer objeto físico carregável e vendável na zona de extração.
- **Propriedades `@export`**:
  - `display_name := "Objeto"`, `size := Vector3(0.5, 0.5, 0.5)`, `color := Color.WHITE`, `mass := 5.0`, `min_value := 20`, `max_value := 60`, `impact_threshold := 6.0`, `fragility := 0.1`, `spawn_weight := 1.0`.

### `scripts/props/prop.gd` e `scenes/prop.tscn`
- **Classe**: `class_name Prop extends RigidBody3D`.
- **Autoridade de Rede**: Servidor (`1`). Clientes mantêm `freeze = true` (`FREEZE_MODE_KINEMATIC`).
- **Responsabilidade**: Simula um item de loot ou membro corporal no mundo (`collision_layer = 4`, `collision_mask = 23`), soma forças de múltiplos jogadores segurando (`holders`), calcula quantas pessoas faltam para erguer (`people_needed()`, `people_missing()`), reduz `net_value` em impactos acima de `def.impact_threshold` e destrói o objeto se o valor chegar a `<= 0`.
- **Propriedades Sincronizadas (`MultiplayerSynchronizer` em `scenes/prop.tscn`)**:
  - `net_position`, `net_rotation`, `net_value`, `net_holder_ids` (todas com `spawn = true`, `ON_CHANGE`).
- **Métodos Públicos e RPCs**:
  - `setup(data: Dictionary) -> void`: Inicializa `def`, `name`, `net_value`, `position` e `mass` antes de entrar na árvore.
  - `people_needed() -> int` / `people_missing() -> int`: Usados pelo `HUD` para mostrar quantos aliados são necessários.
  - `@rpc("any_peer", "call_local", "reliable") request_grab()`: Valida distância (`<= 4.5m`) e `player.can_hold_props()` no servidor; se recusado, envia `player.grab_lost.rpc_id(id)`.
  - `@rpc("any_peer", "call_local", "reliable") request_release(throw: bool)`: Remove do dicionário `holders` e, se `throw == true`, aplica impulso escalonado pela força dos braços do jogador.
  - `@rpc("any_peer", "call_local", "unreliable") request_push(impulse: Vector3)`: Aplica empurrão quando um jogador esbarra no prop caminhando.
  - `@rpc("authority", "call_local", "reliable") _show_loss(amount: int)`: Cria um `Label3D` flutuante vermelho `-$X` com tween de fade-out.

### `scripts/items/item_def.gd`
- **Classe**: `class_name ItemDef extends Resource`.
- **Responsabilidade**: Dados de um item inventariável no `Loadout`.
- **Enum e Propriedades `@export`**:
  - `enum Kind { NONE, REVOLVER, BATON, GRENADE, AMMO, FLASHLIGHT }`
  - `kind`, `display_name`, `size`, `color`, `mass`, `amount`, `bounce`, `spawn_weight`.

### `scripts/items/world_item.gd` e `scenes/item.tscn`
- **Classe**: `class_name WorldItem extends RigidBody3D`.
- **Autoridade de Rede**: Servidor (`1`). Clientes mantêm `freeze = true` (`FREEZE_MODE_KINEMATIC`).
- **Responsabilidade**: Representa um `ItemDef` no mundo (`collision_layer = 32`). Possui dois estados controlados por `net_active`:
  - **Inativo (`net_active == false`, `IDLE_MASK = 5`)**: Item repousando no chão; pode ser pego com `E` (`can_take() == true`).
  - **Ativo (`net_active == true`, `ACTIVE_MASK = 23`)**: Projétil arremessado pelo servidor. Possui imunidade de `0.3s` (`THROWER_GRACE`) para quem o lançou:
    - Se for `BATON`: Gira no ar (`BATON_SPIN`), quica nas paredes (`bounce = 0.85`), causa dano proporcional à velocidade (`speed * 0.9`) e knockback em qualquer entidade com `server_hit` (incluindo o próprio atirador após `0.3s`!) e volta a ficar inativo quando desacelera (`< 1.0 m/s` por `0.25s`) ou após `8.0s`.
    - Se for `GRENADE`: No primeiro contato físico (`_on_body_entered`), agenda `_explode.call_deferred()`, que dispara `weapon_fx.blast.rpc`, emite barulho (`0.6`) e empurra todos os jogadores, monstros, drones, props e itens em um raio de `7.0m` que não tenham parede (`layer 1`) bloqueando a linha de visão.
- **Propriedades Sincronizadas (`scenes/item.tscn`)**:
  - `net_position`, `net_rotation`, `net_active` (`spawn = true`, `ON_CHANGE`).

### `scripts/items/weapon_fx.gd`
- **Classe**: `class_name WeaponFx extends Node3D`.
- **Autoridade de Rede**: Servidor dispara as RPCs `"authority"`; todos os peers não-headless renderizam as malhas e luzes temporárias.
- **Responsabilidade**: Efeitos visuais efêmeros de combate (fica como filho direto de `Main` para sobreviver à destruição da granada ou arma que originou o efeito).
- **RPCs**:
  - `@rpc("authority", "call_local", "unreliable") shot(from: Vector3, to: Vector3, hit_entity: bool)`: Cria traçante amarelo, esfera de impacto (vermelha se atingiu entidade) e `OmniLight3D` rápida.
  - `@rpc("authority", "call_local", "reliable") blast(center: Vector3, radius: float)`: Cria esfera ciano expansiva com `Tween` e flash de luz de explosão.

---

## 6. Mundo, Geração Procedural e Inimigos

### `scripts/world/level_generator.gd`
- **Classe**: `class_name LevelGenerator extends NavigationRegion3D`.
- **Autoridade de Rede**: Todos os peers executam `generate(level_seed)` deterministicamente; apenas o servidor assa o `NavigationMesh` (`bake_navigation_mesh(true)`) e usa as listas de spawn.
- **Responsabilidade**: Gera um labirinto de salas `5x4` (`ROOM_SIZE = 12.0m`, `ROOM_HEIGHT = 3.5m`) conectado à porta da van (`FACILITY_START_Z = -5.0`).
- **Algoritmo**:
  1. `_carve_maze(rng)`: Busca em profundidade (DFS) a partir da sala de entrada (`Vector2i(columns / 2, 0)`), garantindo conectividade perfeita e identificando a sala mais profunda para o `monster_spot`.
  2. `_add_extra_doors(rng)`: Abre paredes adicionais com probabilidade `extra_door_chance` (`0.2`), criando loops para rotas de fuga.
  3. `_build_room(cell, material, rng)`: Constrói piso, teto, paredes/portas (`StaticBody3D` + `BoxMesh`), pilares opcionais (`30%`), lâmpadas `OmniLight3D` (`50%`) e popula `patrol_spots`, `item_spots` e `prop_spots`.
  4. Calcula `layout_signature` (string binária de todas as aberturas) usada pelo `smoke_test.gd` para provar que host e cliente geraram o mesmo mapa.
- **Sinais**:
  - `navigation_ready`: Emitido no servidor assim que `bake_finished` conclui.

### `scripts/world/monster.gd` e `scenes/monster.tscn`
- **Classe**: `class_name Monster extends CharacterBody3D`.
- **Autoridade de Rede**: Servidor (`1`). Clientes desativam `collision_mask = 0` e interpolam `net_position` e `net_yaw`.
- **Responsabilidade**: Inimigo principal com IA de 3 estados (`ROAM`, `INVESTIGATE`, `CHASE`) baseada em `NavigationAgent3D`, percepção visual por raycast (`vision_range = 14.0m`) e auditiva via `Game.noise_emitted` (`hearing_gain = 180.0`, `max_hearing_range = 28.0m`), e corpo modular completo de 6 membros (`PlayerRig`).
- **Corpo Modular do Monstro**:
  - Nasce por padrão com `cyber_left_arm.tres` no braço esquerdo e `cyber_right_leg.tres` na perna direita (jogadores corajosos podem roubar os implantes do monstro durante a partida!).
  - Perder pernas reduz a velocidade do monstro (`100%` com 2 pernas, `58%` com 1 perna, `28%` sem pernas).
  - Perder braços reduz o dano de ataque (`100%` com 2 braços, `70%` com 1 braço, `35%` sem braços).
  - Remover a cabeça ou o tronco (`vital == true`) mata o monstro instantaneamente (`queue_free()`).
- **Propriedades Sincronizadas (`scenes/monster.tscn`)**:
  - `net_position`, `net_yaw` (`ALWAYS`), `net_stunned`, `net_chasing`, `net_attacking` (`ON_CHANGE`).

### `scripts/world/drone.gd` e `scenes/drone.tscn`
- **Classe**: `class_name Drone extends CharacterBody3D`.
- **Autoridade de Rede**: Servidor (`1`). Clientes zeram `collision_layer` e `collision_mask` e interpolam `net_position` e `net_yaw`.
- **Responsabilidade**: Robô voador de patrulha (`hover_height = 2.0m`, `patrol_speed = 2.5 m/s`, `max_health = 40`). Segue um circuito fechado de 4 salas (`_waypoints`) consultando `NavigationServer3D.map_get_path` projetado no chão e parando `1.0s` em cada ponto. Não enxerga, não escuta barulho e não ataca: funciona como obstáculo luminoso (`Searchlight`) e alvo físico que retoma a rota após ser empurrado por tiros ou granadas (`server_hit`).

### `scripts/world/lever.gd`
- **Classe**: `class_name Lever extends StaticBody3D`.
- **Autoridade de Rede**: Qualquer peer solicita uso via RPC; o servidor executa.
- **Responsabilidade**: Alavanca na parede interna da van (`collision_layer = 8` / `interact`).
- **Métodos e RPCs**:
  - `get_prompt() -> String`: Retorna `"Iniciar expedição"` no `LOBBY`, `"Encerrar e partir"` na `RUN`, ou `"Aguarde"` em `RESULTS`.
  - `@rpc("any_peer", "call_local", "reliable") request_use()`: No servidor, chama `Game.pull_lever()`.

### `scripts/world/extraction_zone.gd`
- **Classe**: `class_name ExtractionZone extends Area3D`.
- **Autoridade de Rede**: Servidor (`1`).
- **Responsabilidade**: Zona demarcada em amarelo no piso da van (`collision_mask = 4`, detectando apenas `Prop`). A cada `0.25s` durante a fase `RUN`, soma `body.net_value` de todos os `Prop` sobrepostos e atualiza `Game.set_collected(total)`.

---

## 7. Rede / VoIP Auxiliar e Interface UI

### `scripts/net/voice_codec.gd`
- **Classe**: `class_name VoiceCodec extends RefCounted`.
- **Responsabilidade**: Codec estático de áudio Mu-law (`MU = 255.0`) a `16000 Hz` sem dependências externas.
- **Métodos Estáticos**:
  - `encode(samples: PackedFloat32Array) -> PackedByteArray`: Comprime cada amostra float `[-1.0, 1.0]` em 1 byte `[0..255]`.
  - `decode(data: PackedByteArray) -> PackedFloat32Array`: Descomprime usando tabela de lookup `_decode_table` pré-calculada de 256 entradas.
  - `rms(samples: PackedFloat32Array) -> float`: Calcula a raiz do valor quadrático médio (volume do frame).

### `scripts/net/voice_output.gd`
- **Classe**: `class_name VoiceOutput extends AudioStreamPlayer3D`.
- **Responsabilidade**: Reproduz a voz recebida de um jogador no espaço 3D usando `AudioStreamGenerator` (`mix_rate = 16000`, `buffer_length = 0.25s`).
- **Controle de Jitter**:
  - Acumula amostras em `_queue` até atingir `PREBUFFER_SAMPLES` (`1280` amostras = `80 ms`) antes de liberar o playback (`_buffering = false`).
  - Se a fila acumular mais que `MAX_QUEUED_SAMPLES` (`8000` amostras = `500 ms`), descarta o áudio antigo mantendo apenas as últimas `1280` amostras para cortar atraso acumulado.

### `scripts/ui/hud.gd` e `scenes/ui/hud.tscn`
- **Classe**: `extends Control`.
- **Responsabilidade**: Interface principal durante a sessão. Constrói dinamicamente por código dois grandes componentes visuais em `_ready()` e atualiza tudo em `_process()`:
  1. **Hotbar de 5 Slots (`%HudBar` / `_build_hud_bar`)**: Exibe `[1]` a `[5]`, cor do item (`swatch`), nome (`slot_title`) e estado/munição (`slot_detail`), destacando o slot ativo com borda dourada.
  2. **Modal de Diagnóstico Corporal (`%BodyHudModal` / `_build_body_hud_modal`)**: Alternado com a tecla `I` (`player.body_hud_open`). Exibe os 6 slots em layout anatômico (Cabeça no topo; Braço Esq., Tronco e Braço Dir. no meio; Perna Esq. e Perna Dir. na base), diferenciando visualmente `ORGÂNICO` (verde), `CYBER` (ciano) e `AUSENTE` (vermelho), além do resumo total de Força de Pegada (`N`), Velocidade (`%`) e Impulso de Pulo (`%`).
  3. **Painel Cooperativo de Carga (`%CarryPanel` / `_update_carry`)**: Mostra se o jogador está segurando sozinho, ajudando ou sendo ajudado por aliados, quantos jogadores faltam (`people_missing()`) e blocos coloridos (`%CarryPips`) para cada jogador vivo segurando o `Prop`.
  4. **Indicadores Gerais**: `%Objective` (dia, quota, valor coletado e cronômetro), `%Banner` (resultado da run), `%Roster` (lista de jogadores com tags `(falando)` ou `(morto)`), `%Prompt` (`hover_text` da mira), `%BodyStatus`, `%HealthBar`, `%StaminaBar` e `%MicBar`.

### `scripts/ui/main_menu.gd` e `scenes/ui/main_menu.tscn`
- **Classe**: `extends Control`.
- **Responsabilidade**: Menu inicial exibido antes de entrar em uma sessão. Permite editar nome (`%NameEdit`), IP (`%AddressEdit`), alternar `%DisableEnemies` (`Game.set_enemies_disabled`), hospedar (`%HostButton` -> `Net.host()`) ou conectar (`%JoinButton` -> `Net.join()`), e exibe mensagens de erro/desconexão em `%Status`.

### `scripts/ui/pause_menu.gd` e `scenes/ui/pause_menu.tscn`
- **Classe**: `extends Control`.
- **Responsabilidade**: Menu sobreposto acionado por `Esc` durante a sessão (`Main._unhandled_input`). Permite ajustar sensibilidade do mouse (`%Sensitivity`), ligar/desligar microfone (`%Mic`), alternar Push-to-Talk (`%PushToTalk`), ativar/desativar inimigos em tempo real (`%DisableEnemies`), voltar ao jogo (`%Resume`) ou encerrar/sair da sessão (`%Leave` -> `Net.leave()`). Salva automaticamente `Settings.save()` ao ser fechado.

---

## 8. Catálogo de Resources `.tres`

### 8.1. Membros Corporais (`resources/body_parts/*.tres` — tipo `BodyPartDef`)

| Arquivo | Nome (`display_name`) | Slot (`enum`) | Tipo | `vital` | `grip_force` | `leg_speed` | `leg_jump` | Massa | Valor (`min..max`) | `impact_threshold` | `fragility` | `spawn_weight` |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `organic_head.tres` | Cabeça Orgânica | `HEAD (0)` | Orgânico | `true` | `0 N` | `0.0` | `0.0` | `4.5 kg` | `$120..$180` | `5.5 m/s` | `0.15` | `0.4` |
| `organic_torso.tres` | Tronco Orgânico | `TORSO (1)` | Orgânico | `true` | `0 N` | `0.0` | `0.0` | `18.0 kg` | `$180..$260` | `7.5 m/s` | `0.10` | `0.3` |
| `organic_left_arm.tres` | Braço Esq. Orgânico | `LEFT_ARM (2)` | Orgânico | `false` | `175 N` | `0.0` | `0.0` | `3.5 kg` | `$60..$100` | `6.5 m/s` | `0.12` | `0.8` |
| `organic_right_arm.tres` | Braço Dir. Orgânico | `RIGHT_ARM (3)` | Orgânico | `false` | `175 N` | `0.0` | `0.0` | `3.5 kg` | `$60..$100` | `6.5 m/s` | `0.12` | `0.8` |
| `organic_left_leg.tres` | Perna Esq. Orgânica | `LEFT_LEG (4)` | Orgânico | `false` | `0 N` | `0.50` | `0.50` | `6.0 kg` | `$75..$120` | `7.0 m/s` | `0.10` | `0.8` |
| `organic_right_leg.tres` | Perna Dir. Orgânica | `RIGHT_LEG (5)` | Orgânico | `false` | `0 N` | `0.50` | `0.50` | `6.0 kg` | `$75..$120` | `7.0 m/s` | `0.10` | `0.8` |
| `cyber_left_arm.tres` | Braço Hidráulico Esq. | `LEFT_ARM (2)` | **Cyber** | `false` | **`280 N`** | `0.0` | `0.0` | `8.5 kg` | `$160..$250` | `9.0 m/s` | `0.06` | `0.6` |
| `cyber_right_leg.tres` | Perna Booster Dir. | `RIGHT_LEG (5)` | **Cyber** | `false` | `0 N` | **`0.72`** | **`0.75`** | `9.0 kg` | `$170..$260` | `9.0 m/s` | `0.06` | `0.6` |

### 8.2. Itens e Armas (`resources/items/*.tres` — tipo `ItemDef`)

| Arquivo | Nome (`display_name`) | `Kind` | `amount` | Massa | `bounce` | `spawn_weight` | Uso Principal |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `flashlight.tres` | Lanterna | `FLASHLIGHT (5)` | `1` | `0.4 kg` | `0.20` | `0.4` | Vem no Slot 1; tecla `F` ou clique esq. liga/desliga luz |
| `revolver.tres` | Revólver | `REVOLVER (1)` | `5` (tambor) | `1.2 kg` | `0.15` | `0.5` | Tiro hitscan (`12` dano) com recuo acumulativo em rajada |
| `baton.tres` | Cacetete | `BATON (2)` | `1` | `1.5 kg` | `0.85` | `0.5` | Clique esq.: golpe melee (`15` dano) / Clique dir.: arremesso quicante |
| `grenade.tres` | Granada de impacto | `GRENADE (3)` | `1` | `0.6 kg` | `0.35` | `1.0` | Clique esq./dir.: arremessa e explode no 1º impacto (raio `7m`) |
| `ammo.tres` | Munição | `AMMO (4)` | `5` (balas) | `0.5 kg` | `0.10` | `3.0` | Ocupa slot na hotbar e abastece recarga (`R`) do Revólver |

### 8.3. Loot Físico (`resources/props/*.tres` — tipo `PropDef`)

| Arquivo | Nome (`display_name`) | Tamanho (`size`) | Massa | Pessoas p/ Erguer (`350 N`) | Valor (`min..max`) | `impact_threshold` | `fragility` | `spawn_weight` |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `crate.tres` | Caixa | `(0.6, 0.5, 0.6)` | `8.0 kg` | `1` jogador | `$25..$60` | `7.0 m/s` | `0.08` | `3.0` |
| `vase.tres` | Vaso antigo | `(0.35, 0.7, 0.35)` | `4.0 kg` | `1` jogador | `$70..$140` | `3.0 m/s` (muito frágil) | `0.30` | `1.5` |
| `server_rack.tres` | Rack de servidor | `(0.9, 1.6, 0.9)` | **`55.0 kg`** | **`2` jogadores** (ou 1 com 2 braços cyber) | `$180..$320` | `8.0 m/s` | `0.05` | `0.8` |

---

## 9. Testes Automatizados

### `tests/smoke_test.gd`
- **Classe**: `extends Node` (instanciado dinamicamente por `Main._apply_command_line()` quando `--smoke=host` ou `--smoke=client` é passado).
- **Responsabilidade**: Executa uma bateria completa de testes de integração real entre dois processos Godot headless conectados por ENet.
- **Cobertura (`run_host()` + `run_client()`)**:
  1. `test_codec()`: Roundtrip de áudio Mu-law (`VoiceCodec.encode` / `decode` com erro `< 0.02`).
  2. Conexão ENet, sincronização de `roster` e replicação de movimento do cliente para o host.
  3. Coleta de itens no lobby, acionamento da `Lever`, transição para `RUN` e geração determinística do nível (`LAYOUT=` idêntico).
  4. Assamento do `NavigationMesh`, spawn de `Props`, `Monster` (com rig de 6 ossos e destaque/reinstalação de braço) e `Drones`.
  5. Carga física solo (`crate` de `8 kg` sobe) e carga cooperativa em dupla (`server_rack` de `55 kg` não sobe com 1 pessoa, avisa no HUD, e sobe quando o cliente ajuda).
  6. Recusa de agarre fora de alcance (`grab_lost` + aviso no HUD).
  7. Contabilização de valor na `ExtractionZone` e perda de valor por impacto no `vase.tres`.
  8. Ragdoll esquelético ao receber `server_hit` e modularidade completa do corpo (destaque de membro vira `Prop`, implante de 1 e 2 braços hidráulicos elevando a força para `455 N` e `560 N`, implante de 2 pernas booster, abertura do modal `[I]`, perda dos 2 braços bloqueando `can_hold_props()`, e câmera em 3ª pessoa).
  9. Transmissão de voz convertida em barulho (`Game.noise_emitted`) no servidor.
  10. `test_drones_host()`: Voo na altitude, patrulha em circuito fechado ignorando jogador/barulho, recuperação após stun e destruição.
  11. `test_weapons_host()` / `test_weapons_client()`: Invariante de que membros (`BodyPartDef`) não entram no `Loadout`, coleta e disparo do Revólver, recuo isolado vs rajada de 5 tiros (derrubada + arma escapando da mão), recarga consumindo pente de munição, golpe melee e arremesso de Cacetete (com lurch e rebote ferindo o próprio atirador após `0.3s`), Granada largada (`Q`, não detona) vs arremessada (explode no impacto e empurra monstro, host, cliente, loot, item e drone), perda dos braços desequipando arma, e morte soltando todo o inventário no chão.
  12. Toggle `Game.set_enemies_disabled(true/false)` em tempo de execução, morte de toda a equipe encerrando a run, revive completo no retorno ao lobby e desconexão limpa.

### `tests/run_smoke.sh`
- **Tipo**: Script Bash de automação de CI/teste local.
- **Responsabilidade**: Recebe o caminho do binário do Godot (ou usa `godot` do `PATH`), roda `--headless --path . --import`, sobe em paralelo o processo `--smoke=host` e `--smoke=client` em uma porta aleatória (`25000..25999`), exibe todas as linhas `PASS`/`FAIL`/`DONE`, lista eventuais `ERROR`/`WARNING` da engine, compara as assinaturas `LAYOUT=` dos dois peers e retorna código de saída `0` somente se ambos passarem sem falhas.
