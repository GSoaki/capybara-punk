# Friendslop Template para Godot 4.7

Template de co-op 3D em primeira pessoa para Godot 4.7.2, sem assets externos e sem dependências nativas. A geometria é greybox e o projeto é GDScript puro. O loop é o do gênero: até 8 amigos entram numa instalação gerada por seed, carregam loot com física até o van, fogem de um monstro que escuta a voz deles e tentam bater uma quota crescente.

⚠️ **Estado da validação:** no Godot 4.7.2 oficial (macOS), o teste de integração passa nas 50 verificações, sem erro de script. Uma sessão com janela e host único renderizou van, salas, loot, monstro e HUD a 120 FPS, sem travada ao iniciar a run. Ninguém jogou o template com mouse e teclado reais, e microfone, som e dois jogadores com janela ainda não foram testados.

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
| Agarrar enquanto segura, arremessar | Botão esquerdo, botão direito |
| Aproximar ou afastar o objeto | Roda do mouse |
| Usar alavanca, lanterna | E, F |
| Apertar para falar (opcional), pausa | V, Esc |

## O que vem pronto

**Sessão de rede:** host e join por ENet, roster com nome e cor, checagem de versão, e entrada permitida apenas no lobby.

**Jogador:** controlador com fôlego, agachamento, dano de queda, derrubada com empurrão, morte e espectador.

**Voz por proximidade:** captura do microfone, gate por volume ou apertar para falar, áudio 3D por jogador. Mortos falam só entre si.

**Loot físico:** cada tipo é um `PropDef` (`.tres`) com massa, valor e fragilidade. Impactos reduzem o valor e podem destruir o objeto.

**Carga cooperativa:** cada jogador aplica no máximo 350 N, então objetos acima de cerca de 35 kg só saem do chão com duas pessoas. O rack de servidor (55 kg) existe para isso.

**Fase gerada:** labirinto de salas construído da mesma seed em todos os peers, com navmesh assado em runtime no servidor.

**Monstro:** patrulha, investiga barulho e persegue quem enxerga. Voz, corrida e impactos geram barulho.

**Loop de partida:** lobby, run de 5 minutos, resultado e volta ao lobby. Bater a quota avança o dia e multiplica a quota por 1,35; falhar volta ao dia 1.

## Arquitetura

```text
scripts/autoload/   Settings, Net (sessão), Game (fases e quota), Voice (microfone)
scripts/net/        VoiceCodec (mu-law), VoiceOutput (buffer de jitter e playback 3D)
scripts/player/     Player
scripts/props/      Prop, PropDef
scripts/world/      LevelGenerator, Monster, Lever, ExtractionZone
scripts/main.gd     Spawners e reação às fases
tests/              Teste de integração com dois processos
```

Toda a sessão acontece numa cena única, `scenes/main.tscn`, porque trocar de cena invalida os caminhos de RPC durante a partida.

## Decisões e trade-offs

**Movimento com autoridade do cliente.** Cada dono simula o próprio corpo e replica a posição a 20 Hz. O jogador sente zero atraso e o código dispensa predição e reconciliação. O custo é a confiança: um cliente modificado consegue trapacear. Entre amigos isso é aceitável; para jogo público com matchmaking, troque por rollback ou por movimento com autoridade do servidor.

**Física com autoridade do servidor.** Props são simulados só no host e ficam congelados nos clientes, o que elimina divergência e permite somar a força de vários jogadores no mesmo objeto. O custo é o atraso de um RTT ao carregar. A replicação usa o modo "on change", que não gasta banda com objetos parados e usa canal confiável para os que se movem; com perda alta de pacotes, teste o modo "always".

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
| Regras da quota | Altere as constantes no início de `game.gd`. |

## Testes

`tests/run_smoke.sh` importa o projeto e sobe host e cliente headless conectados por ENet local. O teste cobre roster, replicação, layout idêntico entre peers, navmesh, movimento do monstro, carga solo e em dupla, zona de extração, dano por impacto, voz, fim de run e desconexão.

```bash
tests/run_smoke.sh /Applications/Godot.app/Contents/MacOS/Godot
```

O teste não cobre microfone real, playback de áudio, renderização, UI nem input. Esses itens exigem uma sessão com janela e, para a voz, duas máquinas ou fones.

## Exportação

Ao exportar para macOS, ative a entitlement `Audio Input` em `Codesign` e preencha `Microphone Usage Description` em `Privacy` no preset. Sem isso, o sistema bloqueia a captura.

## Limitações conhecidas

Não há áudio de efeitos, animação de personagem, reconexão, migração de host nem entrada durante a run. Se o host sai, a sessão termina para todos. O monstro não entra no van porque o navmesh cobre apenas a instalação.
