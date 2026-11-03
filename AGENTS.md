# AGENTS.md — Guia de Engenharia de Contexto (Capybara Punk)

Este arquivo é o ponto de entrada universal para qualquer agente de IA (Claude Code, Codex, GitHub Copilot, Gemini, Cursor, Windsurf, etc.) e para desenvolvedores trabalhando no repositório **Capybara Punk**. Leia estas diretrizes antes de explorar ou modificar qualquer código.

---

## 1. Visão Geral e Stack Tecnológica

- **Projeto**: Capybara Punk (Cyberpunk Friendslop) — jogo co-op 3D em primeira/terceira pessoa (1–8 jogadores) de infiltração, coleta de loot físico, cirurgia corporal modular e extração.
- **Engine**: Godot `4.7` (`config_version=5`, Forward Plus, driver `d3d12` no Windows).
- **Motor de Física**: `Jolt Physics` 3D (gravidade padrão `9.8 m/s²`).
- **Linguagem**: GDScript 2.0 puro e estaticamente tipado (`:=`, tipos explícitos em parâmetros e retornos). Zero dependências nativas (GDExtension) e zero assets 3D externos (toda geometria e malhas são greybox procedurais via `CSGBox3D`, `BoxMesh`, `SphereMesh`).
- **Rede / VoIP**: `ENetMultiplayerPeer` (porta UDP `24565`) + VoIP espacial 3D em Mu-law 8-bit a `16 kHz` (`16 kB/s` por locutor no canal 1 `unreliable_ordered`).

---

## 2. Invariantes Arquiteturais Inegociáveis

1. **Arquitetura de Cena Única (`res://scenes/main.tscn`)**:
   - **NUNCA** chame `get_tree().change_scene_to_file()` ou `change_scene_to_packed()`.
   - Toda a sessão ocorre dentro de `scenes/main.tscn` (`scripts/main.gd`). Trocar a cena raiz destrói os `NodePath` usados pelas RPCs ativas e pelos 5 `MultiplayerSpawner` (`PlayerSpawner`, `PropSpawner`, `MonsterSpawner`, `ItemSpawner`, `DroneSpawner`).
2. **Modelo Híbrido de Autoridade Multiplayer**:
   - **Movimento do Jogador e Recuo de Armas (Autoridade do Cliente Dono)**: Cada nó `Player` recebe `set_multiplayer_authority(name.to_int())` em `_enter_tree()`. O dono simula sua física (`move_and_slide()`), stamina, postura e recuo imediato de armas, replicando `net_*` a `20 Hz` via `MultiplayerSynchronizer`.
   - **Mundo, Loot, Itens no Chão, IA, Vida e Cirurgia (Autoridade do Servidor)**: `Game`, `Prop`, `WorldItem`, `Monster`, `Drone`, `ExtractionZone` e `Lever` são decididos estritamente pelo host (`multiplayer.is_server()`). Nos clientes (`not multiplayer.is_server()`), todo `RigidBody3D` (`Prop` e `WorldItem`) fica congelado com `freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC` e `freeze = true`, interpolando suavemente para `net_position` e `net_rotation`.
3. **Separação Estrita entre `Prop` (Mãos / Membros) e `WorldItem` (Inventário)**:
   - **`Prop` (`PropDef` e `BodyPartDef`)**: Objetos de loot físico e membros corporais (orgânicos ou cibernéticos). São carregados fisicamente com as mãos (`grab` / botão esquerdo do mouse) usando força cooperativa por mola (`Prop.holders`) e **NUNCA** entram nos 5 slots da barra de inventário (`Loadout`).
   - **`WorldItem` (`ItemDef`)**: Armas e utilitários (`REVOLVER`, `BATON`, `GRENADE`, `AMMO`, `FLASHLIGHT`). Ocupam os 5 slots do `Loadout` (`slot_1` a `slot_5`) quando pegos do chão e voltam a ser `WorldItem` quando largados (`Q`) ou arremessados (`throw` / botão direito).
4. **Identificação de Remetente em RPCs (`Net.sender_id()`)**:
   - Em RPCs marcadas com `"call_local"`, `multiplayer.get_remote_sender_id()` retorna `0` quando chamadas localmente pelo próprio host. **SEMPRE** use `Net.sender_id()` para obter o `peer_id` real (`1` para o host ou o ID remoto do cliente) ao validar permissões no servidor.
5. **Segurança no Passo de Física (Jolt Physics)**:
   - Nunca destrua corpos, crie nós ou dispare explosões/mortes diretamente dentro de callbacks de sinal de física como `body_entered`. Use `call_deferred()` (ex.: `_explode.call_deferred()`, `_strike.call_deferred()`) ou `set_deferred("disabled", ...)` para evitar erros fatais de bloqueio do servidor de física.

---

## 3. Camadas de Colisão 3D (Physics Layers & Masks)

Configuradas em `project.godot`:

| Layer | Bit (Valor) | Nome | Quem habita esta camada (`collision_layer`) |
| :---: | :---: | :--- | :--- |
| **1** | `1` | `world` | Paredes, pisos, tetos do `LevelGenerator` e geometria da `Van` |
| **2** | `2` | `players` | `Player` (`CharacterBody3D`) |
| **3** | `4` | `props` | `Prop` (loot físico e membros corporais soltos) |
| **4** | `8` | `interact` | `Lever` (alavanca da van) |
| **5** | `16` | `monsters` | `Monster` e `Drone` (`CharacterBody3D`) |
| **6** | `32` | `items` | `WorldItem` (armas, munição e granadas no mundo) |

**Máscaras Combinadas Frequentes**:
- `Player.collision_mask = 13` (`1 + 4 + 8`: mundo, props, interact).
- `Player/Head/InteractRay.collision_mask = 63` (`1..32`: enxerga todas as 6 camadas a até `3.5 m`).
- `Prop.collision_mask = 23` (`1 + 2 + 4 + 16`: mundo, players, props, monsters) | `ExtractionZone.collision_mask = 4` (apenas `props`).
- `WorldItem.IDLE_MASK = 5` (`1 + 4`: mundo e props quando parado) | `WorldItem.ACTIVE_MASK = 23` (`1 + 2 + 4 + 16`: atinge mundo, players, props e monstros quando em voo/arremessado).
- `Loadout.SHOT_MASK = 23` (tiro atinge mundo, players, props e monstros) | `Loadout.MELEE_MASK = 22` (`2 + 4 + 16`: esfera melee atinge players, props e monstros, com raycast na layer `1` para impedir acerto através de parede).
- `PhysicalBone3D.collision_mask = 5` (`1 + 4`: ossos em ragdoll colidem com o mundo e props quando ativos).

---

## 4. Mapa do Repositório e Documentação Detalhada

```text
capybara-punk/
├── AGENTS.md                        # Este guia universal para agentes de IA
├── README.md                        # Game Design Document (GDD) do projeto
├── project.godot                    # Configuração da engine, Autoloads, Inputs e Physics Layers
├── default_bus_layout.tres          # Buses de áudio: Master, Mic (mudo + Capture) e Voice
├── docs/
│   ├── desenvolvimento.md           # Guia rápido de execução, controles, armas e decisões
│   ├── arquitetura.md               # Diagramas Mermaid e fluxos profundos de subsistemas
│   └── catalogo-arquivos.md         # Documentação arquivo por arquivo (todos os 57 arquivos)
├── scripts/
│   ├── main.gd                      # Orquestrador da cena única e dos 5 MultiplayerSpawner
│   ├── autoload/                    # Singletons: Settings, Net, Game, Voice
│   ├── player/                      # Player, Loadout (5 slots + armas), PlayerRig (Skeleton3D), BodyPartDef
│   ├── props/                       # Prop (loot cooperativo) e PropDef
│   ├── items/                       # ItemDef, WorldItem (item/projétil) e WeaponFx
│   ├── world/                       # LevelGenerator, Monster, Drone, Lever, ExtractionZone
│   ├── net/                         # VoiceCodec (Mu-law) e VoiceOutput (jitter buffer 3D)
│   └── ui/                          # HUD (5 slots + modal corporal [I] + carry pips), MainMenu, PauseMenu
├── scenes/                          # Cenas .tscn (main, player, monster, drone, prop, item e ui/*)
├── resources/                       # Dados .tres (8 body_parts, 5 items, 3 props)
└── tests/                           # smoke_test.gd (integração host+client) e run_smoke.sh
```

- Para entender **fluxos de dados, estados de rede, VoIP e rig esquelética**, consulte [`docs/arquitetura.md`](docs/arquitetura.md).
- Para consultar **assinaturas, nós, sinais, RPCs e propriedades de cada arquivo**, consulte [`docs/catalogo-arquivos.md`](docs/catalogo-arquivos.md).

---

## 5. Convenções de GDScript, RPCs e Testes

- **Nomenclatura e Contratos**:
  - `net_*`: Propriedades sincronizadas pelo `MultiplayerSynchronizer` (ex.: `net_position`, `net_yaw`, `net_holder_ids`).
  - `server_*`: Funções executadas exclusivamente no servidor (ex.: `server_hit`, `server_detach_part`, `server_accept`). Qualquer entidade que receba dano/impulso deve implementar `server_hit(damage: int, knock: Vector3, stun := 1.5) -> void`.
  - `request_*` / `_request_*`: RPCs `"any_peer"` enviadas pelo cliente para solicitar uma ação ao servidor (`rpc_id(1, ...)`). Devem sempre validar `multiplayer.is_server()`, se o remetente (`Net.sender_id()`) está vivo, distância máxima e se vetores recebidos são finitos (`is_finite()`).
  - `_sync_*`: RPCs enviadas pelo servidor para atualizar clientes. **Atenção**: Em nós cuja `multiplayer_authority` pertence ao cliente dono (`Player` e `Loadout`), o servidor (`1`) não é a autoridade do nó; portanto, RPCs enviadas pelo servidor nesses nós devem usar `@rpc("any_peer", "call_local", "reliable")` e verificar no início `if Net.sender_id() != 1: return`.
- **Manutenção do Smoke Test (`tests/smoke_test.gd`)**:
  - O teste roda dois processos em paralelo (`run_host()` e `run_client()`) sincronizados por etapas via `_ready_for_client.rpc("etapa")` no host e `await _wait_command("etapa")` no cliente. Nunca altere a ordem desses comandos em um lado sem atualizar o outro.
- **Idioma**: Comentários, docstrings (`##`), strings de UI e respostas ao desenvolvedor devem ser sempre em **Português**.
- **Validação Estática e Testes**:
  - Após alterar qualquer `.gd` ou `.tscn`, valide a sintaxe e importação com o Godot em modo headless:
    ```bash
    godot --headless --path . --import --quit
    ```
  - Para rodar a suíte completa de integração multiplayer (host + cliente headless via ENet, >90 asserções cobrindo rede, geração de mapa, navmesh, monstro, drones, carga em dupla, cirurgia de membros, armas e VoIP):
    ```bash
    bash tests/run_smoke.sh /caminho/para/godot
    ```
