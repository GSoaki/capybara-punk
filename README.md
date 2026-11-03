# GAME DESIGN DOCUMENT (GDD)
# [WORKING TITLE] — Cyberpunk Friendslop
**Versão:** 0.1  
**Gênero:** Cooperative Multiplayer / Extraction / Heist / Comedy Horror  
**Ambientação:** Cyberpunk / Sci-Fi Dystopia  
**Jogadores:** 1–4 (proposta inicial)  
**Plataformas:** PC (proposta inicial)  
**Perspectiva:** Primeira pessoa  
**Modelo de jogo:** Sessões cooperativas com missões independentes e progressão persistente.

Documentação técnica e guia AI-First do projeto:
- **Guia para Agentes de IA (Context Engineering):** [AGENTS.md](AGENTS.md)
- **Como rodar, controles e mecânicas implementadas:** [docs/desenvolvimento.md](docs/desenvolvimento.md)
- **Arquitetura dos subsistemas e diagramas de fluxo:** [docs/arquitetura.md](docs/arquitetura.md)
- **Catálogo completo arquivo por arquivo:** [docs/catalogo-arquivos.md](docs/catalogo-arquivos.md)

---
# 1. High Concept
Em um futuro cyberpunk decadente, um grupo de indivíduos endividados acaba nas mãos de um ripperdoc extremamente duvidoso, que os mantém presos a uma dívida médica praticamente impagável.
Para quitar suas dívidas, os jogadores são enviados para realizar serviços ilegais em diferentes regiões da cidade: roubar implantes experimentais, invadir instalações corporativas, recuperar HDDs com informações sigilosas, sequestrar equipamentos e coletar tecnologias raras.
O problema é que os jogadores não são mercenários profissionais. São apenas pessoas desesperadas, equipadas com tecnologia questionável e obrigadas a trabalhar juntas para sobreviver.
O dinheiro obtido nas missões pode ser utilizado para pagar a dívida, adquirir equipamentos e realizar modificações corporais cibernéticas nos próprios jogadores ou em seus amigos.
**Afinal, o que poderia dar errado ao instalar um braço hidráulico experimental no seu amigo?**
# 2. Visão do Produto
Um jogo cooperativo focado em experiências emergentes e momentos engraçados entre amigos, utilizando missões de infiltração, exploração, coleta e extração em ambientes cyberpunk.
A experiência deve incentivar:
- Cooperação e comunicação entre jogadores.
- Improvisação diante de situações inesperadas.
- Risco versus recompensa.
- Progressão individual e coletiva.
- Personalização visual e funcional dos personagens.
- Situações absurdas causadas por implantes, equipamentos e interações físicas.
O jogo não deve exigir que os jogadores sejam extremamente habilidosos. Parte da diversão deve surgir justamente dos erros, acidentes e decisões ruins do grupo.
# 3. Pilares de Design
## 3.1. Cooperative Chaos
A cooperação é essencial, mas não precisa ser organizada.
Os jogadores devem ter motivos para trabalhar juntos, mas também devem conseguir causar problemas uns aos outros de maneira divertida.
Exemplos:
- Um jogador precisa carregar um objeto pesado enquanto outro protege o caminho.
- Um jogador hackeia uma porta enquanto os outros tentam impedir que inimigos se aproximem.
- Um implante apresenta defeito no pior momento possível.
- Um jogador acidentalmente ativa um alarme e compromete toda a operação.
## 3.2. Risk and Reward
Quanto maior o risco assumido, maior pode ser a recompensa.
Os jogadores precisam decidir constantemente:
- Continuar explorando ou retornar à extração?
- Pegar mais um item ou garantir o que já foi coletado?
- Investir em equipamentos ou pagar a dívida?
- Realizar uma missão segura ou aceitar um contrato extremamente perigoso?
## 3.3. Cybernetic Progression
A progressão deve ser tangível e visual.
O jogador começa relativamente limitado e passa a adquirir modificações corporais que alteram sua aparência, suas capacidades e a maneira como interage com o mundo.
Os implantes devem ser interessantes não apenas por seus benefícios, mas também pelos efeitos colaterais e possibilidades de interação.
## 3.4. Emergent Gameplay
As missões devem possuir sistemas que interajam entre si, permitindo situações que não foram necessariamente planejadas pelos desenvolvedores.
Física, inimigos, equipamentos, implantes, alarmes e ambientes devem criar oportunidades para momentos imprevisíveis.
# 4. Core Gameplay Loop
O jogo é dividido em três grandes momentos:
### 4.1. Preparation — Preparação
Os jogadores retornam ao esconderijo ou clínica do ripperdoc.
Atividades:
- Consultar novas missões.
- Comprar equipamentos.
- Instalar ou remover implantes.
- Personalizar personagens.
- Dividir equipamentos entre os jogadores.
- Consultar a dívida acumulada.
### 4.2. Heist — Execução da missão
Os jogadores são enviados para uma localização com um objetivo específico.
Atividades:
- Explorar o ambiente.
- Localizar objetivos e itens valiosos.
- Resolver obstáculos.
- Evitar ou enfrentar ameaças.
- Administrar recursos.
- Decidir quando abandonar a missão.
Os jogadores precisam transportar os itens até um ponto de extração para garantir a recompensa.
### 4.3. Debriefing — Retorno
Após a missão, o grupo recebe os resultados.
Atividades:
- Converter itens coletados em dinheiro.
- Calcular recompensas e penalidades.
- Atualizar a dívida.
- Comprar novos equipamentos e implantes.
- Preparar a próxima missão.
**Loop resumido:**
Preparação → Contrato → Infiltração → Coleta → Extração → Recompensa → Upgrades → Nova missão.
# 5. Sistema de Dívida
A dívida é o principal elemento de progressão e motivação narrativa.
Todos os jogadores começam devendo uma quantia ao ripperdoc, que pode ser compartilhada entre o grupo ou individualizada.
A dívida deve funcionar como uma pressão constante, sem transformar o jogo em uma experiência excessivamente punitiva.
## 5.1. Dívida inicial
Cada personagem possui uma dívida médica inicial.
Possíveis componentes:
- Procedimentos cirúrgicos anteriores.
- Implantes instalados.
- Medicamentos e tratamentos.
- Taxas administrativas absurdas.
- Juros abusivos.
- Serviços adicionais cobrados pelo ripperdoc.
## 5.2. Pagamentos
Ao concluir missões, o grupo recebe dinheiro.
Os jogadores podem escolher entre:
- Amortizar a dívida.
- Comprar equipamentos.
- Instalar novos implantes.
- Guardar dinheiro para compras futuras.
## 5.3. Consequências da dívida
O não pagamento pode gerar consequências progressivas.
Exemplos:
- Aumento dos juros.
- Cobrança de taxas adicionais.
- Bloqueio de determinados serviços.
- Contratos mais arriscados impostos pelo ripperdoc.
- Equipamentos fornecidos como garantia da dívida.
O ripperdoc deve ser uma presença recorrente e potencialmente antagonista, sempre encontrando novas maneiras de lucrar com os jogadores.
# 6. Sistema de Missões
As missões são contratos independentes, com objetivos, recompensas, dificuldades e ambientes variados.
Cada missão deve ter:
- Localização.
- Objetivo principal.
- Objetivos secundários opcionais.
- Recompensa estimada.
- Nível de risco.
- Ameaças específicas.
- Condições de extração.
## 6.1. Tipos de missão
### A. Implant Retrieval
Recuperar implantes raros em instalações médicas, laboratórios clandestinos ou clínicas abandonadas.
Exemplos:
- Roubar um protótipo de braço hidráulico.
- Recuperar um conjunto de olhos experimentais.
- Encontrar um implante cerebral em um laboratório contaminado.
### B. Data Extraction
Infiltrar instalações corporativas para roubar informações.
Exemplos:
- Roubar HDDs de servidores corporativos.
- Recuperar dados de um computador isolado.
- Copiar informações sem disparar alarmes.
- Roubar um dispositivo físico de armazenamento.
### C. Corporate Infiltration
Invadir instalações protegidas para recuperar equipamentos ou objetos específicos.
Exemplos:
- Invadir um escritório corporativo.
- Recuperar uma maleta de tecnologia experimental.
- Sabotar um equipamento.
- Desativar um sistema de segurança.
### D. Black Market Delivery
Transportar mercadorias ilegais de um ponto até outro.
Exemplos:
- Transportar órgãos artificiais.
- Entregar implantes sem identificação.
- Transportar uma caixa com conteúdo desconhecido.
- Recuperar uma carga interceptada.
### E. Salvage Operation
Explorar locais abandonados em busca de materiais valiosos.
Exemplos:
- Recuperar componentes de robôs.
- Coletar equipamentos de uma fábrica desativada.
- Encontrar peças de implantes em uma instalação destruída.
## 6.2. Objetivos secundários
Além do objetivo principal, as missões podem apresentar oportunidades opcionais.
Exemplos:
- Roubar equipamentos adicionais.
- Encontrar documentos secretos.
- Recuperar itens de valor.
- Completar objetivos sem ativar alarmes.
- Extrair todos os jogadores vivos.
Esses objetivos aumentam o valor da recompensa, incentivando exploração e decisões arriscadas.
# 7. Ambientes e Level Design
Os mapas devem ser compactos, densos e reutilizáveis, com diferentes possibilidades de exploração.
A intenção não é criar mundos abertos, mas sim instalações com múltiplos caminhos, obstáculos e oportunidades de improvisação.
Possíveis ambientes:
- **Corporate Offices:** escritórios, salas de servidores, laboratórios e corredores de segurança.
- **Underground Clinics:** clínicas clandestinas, depósitos de órgãos artificiais e salas cirúrgicas.
- **Industrial Facilities:** fábricas automatizadas, depósitos e linhas de produção.
- **Abandoned Districts:** prédios comerciais abandonados, apartamentos e estabelecimentos ilegais.
- **Black Market:** depósitos de contrabandistas, mercados clandestinos e esconderijos.
Cada ambiente deve possuir identidade visual e mecânicas próprias.
# 8. Ameaças e Inimigos
Os inimigos devem funcionar como obstáculos à execução dos contratos.
Não é necessário que todos sejam extremamente perigosos. Alguns podem ser ameaças diretas, enquanto outros geram situações imprevisíveis.
Categorias iniciais:
- **Security Drones:** robôs de segurança que patrulham instalações.
- **Corporate Guards:** guardas humanos que investigam sons e atividades suspeitas.
- **Malfunctioning Robots:** máquinas defeituosas com comportamentos imprevisíveis.
- **Cyberpsychos:** indivíduos com modificações corporais extremas e comportamento agressivo.
- **Experimental Creatures:** resultados de experimentos ilegais que escaparam do controle.
Cada inimigo deve possuir comportamentos identificáveis, permitindo que os jogadores aprendam a lidar com as ameaças.
# 9. Equipamentos
Os jogadores podem comprar e levar equipamentos para facilitar as missões.
Categorias:
**Infiltração**
- Lockpick eletrônico.
- Dispositivo de hacking.
- EMP portátil.
- Scanner de segurança.
**Utilitários**
- Lanterna.
- Detector de movimento.
- Câmera portátil.
- Dispositivo de comunicação.
**Transporte**
- Mochilas.
- Caixas de transporte.
- Equipamentos de carga.
- Carrinhos improvisados.
**Defesa**
- Armas improvisadas.
- Armas de choque.
- Dispositivos de distração.
- Equipamentos de proteção.
Os equipamentos devem possuir limitações para incentivar escolhas e especialização entre os jogadores.
# 10. Cybernetic Augmentations
Um dos principais diferenciais do jogo será o sistema de implantes.
Os jogadores podem instalar modificações corporais que alteram atributos, capacidades e interações físicas.
Os implantes devem ser visualmente perceptíveis e, sempre que possível, alterar diretamente o gameplay.
## 10.1. Categorias de implantes
**Arms**
- Braço hidráulico: aumenta a força e capacidade de carregar objetos.
- Braço mecânico: permite interagir com objetos a uma distância maior.
- Braço elétrico: permite aplicar descargas em inimigos.
- Braço defeituoso: possui força excessiva e controle limitado.
**Legs**
- Pernas hidráulicas: aumentam a velocidade.
- Jump boosters: permitem saltos maiores.
- Pernas magnéticas: permitem escalar determinadas superfícies.
**Eyes**
- Visão térmica.
- Visão noturna.
- Scanner de objetos valiosos.
- Zoom óptico.
**Brain**
- Aumento da velocidade de hacking.
- Capacidade de detectar dispositivos eletrônicos.
- Melhoria na comunicação.
- Processamento acelerado.
**Torso**
- Armadura subcutânea.
- Sistema de armazenamento adicional.
- Gerador de energia portátil.
## 10.2. Implantes experimentais
Alguns implantes podem possuir efeitos colaterais ou comportamentos inesperados.
Exemplos:
- Braço que ocasionalmente trava.
- Pernas que ativam impulsos involuntariamente.
- Olhos que apresentam interferência visual.
- Implante cerebral que emite sons aleatórios.
- Sistema de força que não consegue controlar a intensidade dos movimentos.
A ideia é que os upgrades possam gerar tanto vantagens quanto situações engraçadas.
# 11. Multiplayer e Interação entre Jogadores
O multiplayer é o coração da experiência.
O jogo deve incentivar interações físicas e cooperação, mas também permitir que os jogadores causem problemas uns aos outros.
Possíveis interações:
- Carregar um amigo ferido.
- Arrastar um jogador inconsciente.
- Roubar equipamentos de outro jogador.
- Empurrar ou derrubar amigos.
- Ajudar alguém a alcançar locais elevados.
- Compartilhar implantes ou equipamentos.
- Utilizar habilidades de implantes em outros jogadores.
Uma possibilidade interessante é permitir que implantes sejam instalados em outros membros do grupo, criando situações em que um jogador pode melhorar ou prejudicar deliberadamente o personagem de outro.
# 12. Falha e Morte
As missões precisam apresentar riscos reais.
Possíveis consequências:
- Perder itens que não foram extraídos.
- Perder equipamentos levados à missão.
- Receber penalidades financeiras.
- Ficar temporariamente incapacitado.
- Precisar pagar pelo tratamento de um jogador ferido.
- Adquirir implantes defeituosos ou consequências de procedimentos malfeitos.
A morte permanente não precisa estar presente na primeira versão. É interessante testar inicialmente um sistema de incapacitação e recuperação para evitar frustração excessiva.
# 13. Direção de Arte
**Estilo visual:** Cyberpunk industrial, decadente e exagerado.
Referências:
- Cyberpunk 2077.
- REPO.
- Lethal Company.
- Ambientes industriais e instalações corporativas.
Características visuais:
- Neon e iluminação artificial.
- Ambientes escuros e sujos.
- Instalações corporativas excessivamente limpas.
- Clínicas clandestinas improvisadas.
- Implantes corporais exagerados.
- Equipamentos baratos e visualmente desgastados.
O contraste entre a tecnologia avançada e a precariedade da vida dos personagens deve ser uma característica importante.
# 14. Direção de Áudio
O áudio deve contribuir para a atmosfera e para o humor.
**Ambientação:**
- Sons industriais.
- Ventilação e máquinas.
- Ruídos eletrônicos.
- Alarmes corporativos.
- Rádio com interferência.
**Gameplay:**
- Sons de passos.
- Sons específicos para implantes.
- Alertas de segurança.
- Sons de equipamentos defeituosos.
- Feedback sonoro para coleta e extração.
**Música:**
- Synthwave.
- Dark Electronic.
- Industrial Techno.
- Ambient Cyberpunk.
# 15. Interface e UX
A interface deve ser funcional e relativamente minimalista.
Elementos principais:
- HUD com saúde e status dos implantes.
- Inventário.
- Indicador de objetivos.
- Informações sobre a dívida.
- Interface de equipamentos.
- Terminal de contratos.
- Interface de extração.
A clínica do ripperdoc deve funcionar como o hub principal, centralizando a maior parte das interações entre missões.
# 16. Progressão
A progressão deve acontecer em três dimensões:
**Individual**
- Implantes.
- Personalização.
- Equipamentos.
- Melhorias de atributos.
**Coletiva**
- Dívida compartilhada.
- Equipamentos do grupo.
- Desbloqueio de contratos.
- Melhorias na base.
**Conteúdo**
- Novos ambientes.
- Novos tipos de missão.
- Novos inimigos.
- Novos implantes e equipamentos.
A progressão deve abrir possibilidades de gameplay, e não apenas aumentar números.
# 17. Escopo Inicial — MVP
O primeiro objetivo deve ser validar se o loop de gameplay é divertido.
Não é necessário implementar todo o universo planejado antes de testar a experiência multiplayer.
## Conteúdo mínimo proposto
**Multiplayer**
- 1 a 4 jogadores.
- Sistema de lobby.
- Comunicação por voz.
- Interações físicas básicas.
**Hub**
- Uma clínica do ripperdoc.
- Terminal de contratos.
- Loja de equipamentos.
- Sistema básico de dívida.
- Instalação de implantes.
**Missões**
- 1 mapa.
- 2 tipos de contrato.
- 2 ou 3 variações de objetivos.
- Sistema de extração.
**Inimigos**
- 1 inimigo de patrulha.
- 1 ameaça agressiva.
**Equipamentos**
- Lanterna.
- Dispositivo de hacking.
- Ferramenta de abertura de portas.
- Um equipamento de defesa.
**Implantes**
- Braço hidráulico.
- Pernas aprimoradas.
- Visão noturna.
- Um implante experimental com efeito colateral.
**Progressão**
- Dinheiro.
- Dívida.
- Compra de equipamentos.
- Instalação de implantes.
# 18. Referências
## Lethal Company
Referência para:
- Loop de exploração e extração.
- Cooperação e comunicação.
- Situações emergentes.
- Gerenciamento de risco.
- Humor derivado de falhas.
## REPO
Referência para:
- Interações físicas.
- Física de objetos.
- Caos cooperativo.
- Coleta e transporte de itens.
## Gambling With Your Friends
Referência para:
- Experiências sociais.
- Interações entre amigos.
- Humor e situações inesperadas.
- Sistemas que incentivam decisões arriscadas.
## Cyberpunk 2077
Referência para:
- Ambientação.
- Design de implantes.
- Estética visual.
- Arquitetura e identidade do universo.
# 19. Principais Questões em Aberto
Os seguintes pontos precisam ser definidos pelo time durante o desenvolvimento:
1. **Estrutura da dívida:** individual ou compartilhada entre todos os jogadores?
2. **Morte:** os jogadores podem morrer permanentemente ou apenas ficar incapacitados?
3. **Estrutura das missões:** mapas fixos com variações ou geração procedural?
4. **Combate:** o foco será evitar inimigos ou será possível enfrentá-los diretamente?
5. **Implantes:** todos os jogadores podem utilizar todos os implantes ou existirão especializações?
6. **Interação entre jogadores:** até que ponto será permitido prejudicar os amigos?
7. **Progressão:** existe um objetivo final para quitar a dívida ou o jogo funciona em um ciclo contínuo?
---
**Resumo da experiência desejada:**
Um grupo de amigos endividados, com corpos parcialmente modificados e equipamentos duvidosos, invadindo instalações corporativas para roubar tecnologia, sobreviver a ameaças e conseguir dinheiro suficiente para não ter seus implantes confiscados pelo próprio médico.
O sucesso depende do grupo. O fracasso também. E, provavelmente, alguém vai acabar com três braços.
