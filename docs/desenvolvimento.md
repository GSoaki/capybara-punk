# Friendslop Template para Godot 4.7

Template de co-op 3D em primeira pessoa para Godot 4.7.2, sem assets externos e sem dependências nativas. A geometria é greybox e o projeto é GDScript puro. O loop é o do gênero: até 8 amigos entram numa instalação gerada por seed, carregam loot com física até o van, fogem de um monstro que escuta a voz deles e tentam bater uma quota crescente.

⚠️ **Estado da validação:** no Godot 4.7.2 oficial (macOS), o teste de integração passa nas 153 verificações, sem erro de script. Uma sessão com janela e host único renderizou van, salas, loot, monstro e HUD a 120 FPS, sem travada ao iniciar a run. As armas foram exercitadas com janela por eventos de entrada simulados. Ninguém jogou o template com mouse e teclado reais, e microfone, som e dois jogadores com janela ainda não foram testados.

## Como rodar

Importe a pasta no Godot 4.7.2 (build padrão, sem .NET). Para testar sozinho, abra `Debug > Customize Run Instances`, ative 2 instâncias e rode com F5. Clique em Hospedar numa janela e Entrar na outra, com o endereço `127.0.0.1`. Também é possível abrir direto pela linha de comando:

```bash
godot --path . -- --host --name=Ana
```

```bash
godot --path . -- --join=127.0.0.1 --name=Bia
```

| Ação | Controle |
| --- | --- |
| Mover, pular, correr, agachar | WASD, Espaço, Shift, Ctrl |
| Agarrar enquanto segura, arremessar (mãos livres) | Botão esquerdo, botão direito |
| Usar a arma, arremessar cacetete ou granada | Botão esquerdo, botão direito |
| Pegar item do chão | E |
| Equipar ou guardar revólver, cacetete, granada | 1, 2, 3 |
| Recarregar, largar a arma | R, Q |
| Aproximar ou afastar o objeto | Roda do mouse |
| Usar alavanca / implantar membro, destacar membro, lanterna | E, G, F |
| Alternar câmera (1ª / 3ª pessoa), apertar para falar (opcional), pausa | V, T, Esc |

## O que vem pronto

**Sessão de rede:** host e join por ENet, roster com nome e cor, checagem de versão, e entrada permitida apenas no lobby.

**Jogador:** controlador com fôlego, agachamento, dano de queda, derrubada com empurrão, morte e espectador.

**Voz por proximidade:** captura do microfone, gate por volume ou apertar para falar, áudio 3D por jogador. Mortos falam só entre si.

**Loot físico:** cada tipo é um `PropDef` (`.tres`) com massa, valor e fragilidade. Impactos reduzem o valor e podem destruir o objeto.

**Carga cooperativa:** cada jogador aplica no máximo 350 N, então objetos acima de cerca de 35 kg só saem do chão com duas pessoas. O rack de servidor (55 kg) existe para isso. Um painel abaixo da mira mostra se o agarre foi aceito, se o jogador está ajudando alguém ou recebendo ajuda, quantos faltam e quantos dos jogadores vivos estão segurando.

**Armas e itens:** revólver, cacetete, granada de impacto e caixas de munição ficam no chão. Um de cada fica no van ao abrir a sessão e volta a cada fim de run (`lobby_items` no nó `Main`). Durante a run, mais itens são sorteados nas salas (`item_table`). As armas ferem aliados e exigem ao menos um braço. Ao morrer, o jogador solta tudo o que carrega, e o inventário é zerado no fim da run.

| Arma | Efeito | Principais valores |
| --- | --- | --- |
| Revólver | Cada tiro empurra o jogador para trás e levanta a mira. Tiros com menos de 0,45 s entre si acumulam força e abrem a dispersão. O 3.º tiro seguido tira os pés do chão, o 4.º derruba e o 5.º faz a arma escapar da mão. | 5 balas, 12 de dano, 2,5 m/s no primeiro tiro e cerca de 14 m/s de pico na rajada |
| Cacetete | Corpo a corpo fere e empurra. Arremessado com o botão direito, puxa o jogador para a frente, gira a mira e quica com rebote de 0,85. Depois de 0,3 s, também machuca quem o jogou. | 15 de dano de perto; no voo, 0,9 de dano por m/s |
| Granada de impacto | Arremessada, explode no primeiro contato com parede, chão, jogador, monstro, drone ou loot e lança jogadores, monstros, loot e itens sem parede no caminho. Não fere diretamente, mas o loot perde valor no impacto. Largada com Q, não detona. | Raio de 7 m, até 14 m/s |

Bater numa parede a mais de 11 m/s depois de ser lançado causa o mesmo dano de uma queda nessa velocidade. Os valores ficam nos `@export` de `scripts/player/loadout.gd`, editáveis no nó `Loadout` de `player.tscn`, e nas constantes de `scripts/items/world_item.gd`.

**Fase gerada:** labirinto de salas construído da mesma seed em todos os peers, com navmesh assado em runtime no servidor.

**Monstro:** patrulha, investiga barulho e persegue quem enxerga. Voz, corrida e impactos geram barulho.

**Drone de segurança:** cada run gera 2 drones, cada um com um circuito fixo de 4 salas, voado a 2 m do chão com parada de 1 s em cada ponto. Eles não enxergam, não escutam, não atacam e nunca alteram o circuito. Têm 40 de vida; armas os ferem e a granada os empurra, depois do que retomam a rota.

**Loop de partida:** lobby, run de 5 minutos, resultado e volta ao lobby. Bater a quota avança o dia e multiplica a quota por 1,35; falhar volta ao dia 1.

## Arquitetura

```text
scripts/autoload/   Settings, Net (sessão), Game (fases e quota), Voice (microfone)
scripts/net/        VoiceCodec (mu-law), VoiceOutput (buffer de jitter e playback 3D)
scripts/player/     Player, Loadout (inventário e armas)
scripts/props/      Prop, PropDef
scripts/items/      ItemDef, WorldItem (item no chão, cacetete em voo, granada), WeaponFx
scripts/world/      LevelGenerator, Monster, Drone, Lever, ExtractionZone
scripts/main.gd     Spawners e reação às fases
tests/              Teste de integração com dois processos
```

Toda a sessão acontece numa cena única, `scenes/main.tscn`, porque trocar de cena invalida os caminhos de RPC durante a partida.

## Decisões e trade-offs

**Movimento com autoridade do cliente.** Cada dono simula o próprio corpo e replica a posição a 20 Hz. O jogador sente zero atraso e o código dispensa predição e reconciliação. O custo é a confiança: um cliente modificado consegue trapacear. Entre amigos isso é aceitável; para jogo público com matchmaking, troque por rollback ou por movimento com autoridade do servidor.

**Física com autoridade do servidor.** Props são simulados só no host e ficam congelados nos clientes, o que elimina divergência e permite somar a força de vários jogadores no mesmo objeto. O custo é o atraso de um RTT ao carregar. A replicação usa o modo "on change", que não gasta banda com objetos parados e usa canal confiável para os que se movem; com perda alta de pacotes, teste o modo "always".

**Recuo no cliente, tiro no servidor.** O dono aplica o recuo na hora e prevê o gasto de munição, e o servidor valida cada tiro e faz o raycast a partir da posição que conhece. O recuo não tem atraso, e um cliente modificado continua sem conseguir atirar sem balas. Com latência alta, o recuo pode ocorrer num tiro que o servidor depois recusa, e a mira no servidor fica um pouco atrás da do jogador.

**Voz em mu-law, sem Opus.** Dá 16 kB/s por pessoa falando, no upload do cliente e por ouvinte no upload do host. Com 8 jogadores e 3 clientes falando ao mesmo tempo, o host retransmite 18 fluxos, cerca de 288 kB/s só de voz. Funciona em conexões domésticas boas e dispensa extensão nativa. Para produção, troque `encode` e `decode` em `VoiceCodec` por Opus, que costuma reduzir a banda em cerca de 5 vezes.

**ENet sem NAT traversal.** Com ENet, o host precisa abrir a porta 24565 UDP ou usar uma VPN de camada 2. Isso inviabiliza um lançamento real, em que amigos esperam entrar por convite. Para isso, integre o GodotSteam (confira a compatibilidade com o 4.7) e altere apenas `_create_host_peer` e `_create_client_peer` em `net.gd`.

**Derrubada sem ragdoll real.** Sem esqueleto no greybox, a derrubada inclina a cápsula e aplica o empurrão. Ao adicionar um personagem com `Skeleton3D`, use `PhysicalBoneSimulator3D` em `_receive_knock`.

## Como estender

| Para adicionar | Faça isto |
| --- | --- |
| Novo tipo de loot | Crie um `.tres` de `PropDef` em `resources/props/` e inclua em `loot_table` no nó `Main`. |
| Salas modeladas | Substitua `_build_room` em `level_generator.gd` por instâncias de `PackedScene`, consumindo o `rng` na mesma ordem em todos os peers. |
| Novo monstro | Crie uma cena baseada em `monster.tscn` e ajuste os `@export`. Para vários tipos, passe a cena nos dados de `_spawn_monster`. |
| Novo item usável | Siga o padrão de `Lever`: RPC `any_peer` para o servidor, que valida e decide. |
| Novo item ou arma | Crie um `.tres` de `ItemDef` em `resources/items/`, inclua em `item_table` no nó `Main` e trate o novo `Kind` em `Loadout`. |
| Regras da quota | Altere as constantes no início de `game.gd`. |

## Testes

`tests/run_smoke.sh` importa o projeto e sobe host e cliente headless conectados por ENet local. O teste cobre roster, replicação, layout idêntico entre peers, navmesh, movimento do monstro, carga solo e em dupla, zona de extração, dano por impacto, voz, armas e itens, fim de run e desconexão.

```bash
tests/run_smoke.sh /Applications/Godot.app/Contents/MacOS/Godot
```

O teste não cobre microfone real, playback de áudio, renderização, UI nem input. Esses itens exigem uma sessão com janela e, para a voz, duas máquinas ou fones.

## Exportação

Ao exportar para macOS, ative a entitlement `Audio Input` em `Codesign` e preencha `Microphone Usage Description` em `Privacy` no preset. Sem isso, o sistema bloqueia a captura.

## Limitações conhecidas

Não há áudio de efeitos, incluindo tiro e explosão, nem animação de personagem, reconexão, migração de host ou entrada durante a run. Se o host sai, a sessão termina para todos. O monstro não entra no van porque o navmesh cobre apenas a instalação.
