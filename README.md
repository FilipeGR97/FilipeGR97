# Apex GP — simulador de monopostos (regras 2026)

Simulador de corrida estilo Fórmula 1, feito na **Godot 4.7** (engine open source, renderizador Forward+/Vulkan, física Jolt).
Inspirado na pegada dos jogos de F1 da era PS2, mas com física de simulador e tecnologia atual.

## Como rodar

1. Baixe a Godot **4.7.x (Standard)**: https://godotengine.org/download (não precisa instalar, é um .exe).
2. Abra a Godot → **Importar** → selecione o arquivo `project.godot` desta pasta.
3. Aperte **F5** (ou o botão ▶ no canto superior direito).

Requisitos: placa de vídeo com Vulkan (GTX 900 ou mais nova). Testado numa GTX 1650: ~70 FPS com 20 carros em 1280×720 no preset "Alto".

## Controles

| Ação | Teclado | Controle (Xbox) |
|---|---|---|
| Acelerar / Frear | W / S (ou ↑ ↓) | Gatilho direito / esquerdo |
| Ré | Parado, segure S | Parado, segure o gatilho esquerdo |
| Direção | A / D (ou ← →) | Analógico esquerdo |
| Subir / descer marcha (câmbio manual) | E / Q | A / X ou RB / LB |
| Asa móvel (modo reta) | Espaço | B |
| Modo ultrapassagem (a menos de 1 s) | F | L3 |
| Modo ERS (recarga/normal/ataque) | R | D-pad → |
| Pedir box | P | D-pad ↑ |
| Painel de estratégia / trocar pneu do pit | Tab / PgDn | Back / D-pad ↓ |
| Balanço de freio | [ e ] | — |
| Câmera / olhar para trás | C / V | Y / R3 |

Câmeras: atrás do piloto (padrão), olhos do piloto, T-Cam, bico, perseguição perto/longe e TV.
| Voltar à pista | Backspace | — |
| Pausa | Esc | Start |

## O que tem no Patch 1

- **Física de simulador**: suspensão independente, modelo de pneu combinado (tipo Pacejka) com carga, temperatura e desgaste por pneu,
  aerodinâmica com downforce/arrasto, vácuo e ar sujo, diferencial autoblocante, freio com balanço ajustável, combustível que pesa.
- **Regras 2026**: motor a combustão ~400 kW + MGU-K 350 kW, bateria de 4 MJ com recarga na frenagem, **aerodinâmica ativa**
  (modo reta/modo curva no lugar do DRS) e **modo ultrapassagem** (energia extra a menos de 1 s do carro da frente).
- **Pneus**: Macio (C4), Médio (C3), Duro (C2), Intermediário e Chuva, com janela de temperatura e regra dos 2 compostos.
- **Pit stop** completo: pedido de box, limitador de 80 km/h, parada na garagem da equipe (2–3 s, às vezes uma parada lenta), troca de pneus.
- **Clima**: seco, chuva leve e chuva forte (pista molhada reflete, spray dos carros, menos aderência).
- **Corrida**: semáforo de largada, cronometragem por setores, delta para a melhor volta, intervalos, limites de pista com penalidade,
  bandeira quadriculada e tabela de resultado.
- **IA**: 19 adversários com traçado ideal calculado, perfil de velocidade, ultrapassagem, estratégia de pit e erros ocasionais.
- **Câmeras**: atrás do piloto (padrão, halo visto por trás), olhos do piloto, T-Cam, bico, perseguição perto/longe, TV.
- **Som por fornecedor de motor**: cada unidade de potência tem timbre próprio (sintetizado), com assobio do turbo/MGU-K, pneus, vento e zebras.
- Modos: **Corrida rápida**, **Contra o relógio**, **Treino livre**. Menu com showroom 3D e opções (gráficos, áudio, assistências).

## Estrutura

```
scenes/            menu.tscn, race.tscn
scripts/core/      game.gd (configuração, opções, controles)
scripts/data/      equipes, pneus, circuitos (edite aqui para mudar nomes/cores)
scripts/track/     gerador do circuito (malhas, colisão, traçado ideal, pit lane, cenário)
scripts/vehicle/   física do carro, modelo visual, som, IA, entrada do jogador
scripts/race/      controlador da sessão, câmeras
scripts/ui/        HUD, minimapa, menu
shaders/           asfalto, grama/brita, céu, pintura
tests/             simulação headless (IA dando voltas) para validar a física
docs/              roadmap e notas de cada patch
```

## Equipes, nomes e modelos 3D

Equipes, pilotos e patrocinadores são **fictícios** — nomes, logos e pinturas reais da F1 são marcas registradas.
Para uso pessoal você pode editar `scripts/data/teams.gd`.

O carro atual é gerado por código (provisório). Para colocar um modelo 3D de verdade, salve um `.glb` (feito no Blender, ou comprado/licenciado)
em `assets/cars/<sigla>.glb` (ex.: `vtx.glb`) ou `assets/cars/default.glb` — o jogo usa automaticamente. Detalhes em `docs/ROADMAP.md`.

## Testes automáticos

```
godot --headless --path . --fixed-fps 120 res://tests/scenarios.tscn      # 14 cenários de estresse
godot --headless --path . --fixed-fps 120 res://tests/player_test.tscn    # piloto de teclado virtual
godot --headless --path . --fixed-fps 120 res://tests/gravel_test.tscn    # sair da brita
```

## Teste automático da física (IA)

```
godot --headless --path . --fixed-fps 120 -s res://tests/sim_test.gd -- cars=8 time=200
```
Solta carros da IA na pista e imprime tempos de volta, desgaste, temperatura dos pneus, bateria e combustível.
