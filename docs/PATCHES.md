# Patches

Cada patch é testado por você antes de seguirmos. Anote o que achar (bug, sensação de pilotagem, visual) e eu corrijo no patch seguinte.

---

## Patch 1.5 — v0.1.5 (som fiel dos motores + ficha dos carros)

**Fonte:** `Sonsmotor/videoplayback.m4a` (gravação de perto: V6, V8, V10, V12 e H16 — o H16 foi ignorado).

| Problema relatado | Causa | Correção |
|---|---|---|
| Som não fiel | Só 2 loops por motor, perto de 11.500 rpm; o resto era o mesmo som esticado | **6–7 loops por motor** tirados das puxadas reais do vídeo, de ~6.700 a 12.000 rpm |
| Estourado na redução | Loops de alívio gravados em giro baixo eram esticados ~2x quando a redução levava o motor ao alto | Alívio cobrindo toda a faixa; esticamento máximo limitado; giro do som desliza ~60 ms em vez de saltar |
| Troca de marcha estourada / "sem sentido" | Som de troca vinha de outro motor (V8) e era tocado alto | Troca = corte curto de ignição (~70 ms) + queda de giro, como no vídeo |
| Estouro geral | Várias camadas somadas sem folga | Folga de 6 dB nas camadas + **limitador** no canal mestre; chiado de pneu/zebra só acima do limite de aderência |
| (IA) estalos ao trocar de loop | 1 voz trocando de gravação no meio do som | 2 vozes (loops pares/ímpares): a troca acontece na voz silenciosa |

Validação: áudio do jogo gravado e comparado por espectrograma com o vídeo (mesmas linhas harmônicas e
"dente de serra" de trocas); picos 0,38–0,50 sozinho e 0,62 com 20 carros, **0 amostras estouradas**
(antes 1,0); chiado na frenagem ~20 dB abaixo do motor. FPS com 20 carros: 65–69 (Patch 1.4: 62).

**Ficha de cada carro** (menu → Equipes e Carros e `docs/EQUIPES.md`): chassi fictício (código, apelido, sede),
pilotos, motor (modelo, arquitetura, cilindrada, aspiração, giro máximo), desempenho relativo e ficha de regulamento.

---

## Patch 1.4 — v0.1.4 (sons reais dos motores)

- **Motores com som gravado** a partir dos arquivos em `Sonsmotor/` (usados os `*_trocas_refinadas.mp3`, que seguram
  o giro constante — ideais para loop). Para cada motor: 2 loops "acelerando" + 2–4 loops "aliviando" (desaceleração real
  gravada), mapeados por rpm; o jogo mistura os dois mais próximos do giro e ajusta a afinação.
  V10 = Valkyr · V6 turbo híbrido = Orion · V8 = Kestrel · V12 = Helix.
- **Troca de marcha com som real** recortado das gravações do V8.
- Para trocar/adicionar sons: coloque novos mp3 em `Sonsmotor/` e rode `tools/build_engine_samples.py`
  (ajustando as janelas no topo do arquivo).
- Prévias do som gravado de dentro do jogo: `Sonsmotor/previa_no_jogo/`.

Bugs encontrados no caminho:
| Problema | Causa | Correção |
|---|---|---|
| Largada lenta e motor "picotando" (ouvido nas gravações) | Controle de tração liga/desliga, ~15 cortes por segundo | Controle proporcional suave |
| IA deixava o giro cair na largada | Soltava o acelerador no tempo de reação | Mantém o motor cheio até largar |
| Batia no limitador em 1ª na largada | Câmbio esperava a velocidade real | Sobe a marcha perto do corte (só se a roda não estiver patinando) |
| Carro rodava na grama depois de batidas | Limite de 75% no controle de tração fora do asfalto | Corte total liberado (o "preso na brita" real já tinha sido resolvido) |

Testes: 14/14 cenários (padrão e com suas opções), agora também verificando "roda nunca acima do limitador";
piloto de teclado, brita, corrida completa de 20 carros; áudio do jogo gravado e analisado por espectrograma
(tom acompanha o giro, cai nas trocas de marcha, alívio audível).

---

## Patch 1.3 — v0.1.3 (correções finais antes do Patch 2)

| Problema relatado / encontrado | Causa | Correção |
|---|---|---|
| Na chuva, carros da IA saíam da pista e nunca voltavam | A IA só se recuperava se ficasse quase parada; andando devagar fora da pista ficava perdida | IA volta para a pista se ficar fora/lenta/na contramão por alguns segundos, reposicionada fora do traçado de quem vem |
| Volante do piloto girava ao contrário | Sinal invertido na animação | Corrigido |
| Precisava pausar para trocar de câmera | Tecla tratada num evento que podia ser "comido" pela interface | **C** alterna e **1 a 7** escolhe direto, com aviso na tela |
| Todos pararam no box na volta 4 de uma corrida de 5 | Regra dos 2 compostos valia a partir de 5 voltas, forçando parada sem sentido | Regra só em corridas de **10+ voltas**; quem não cumprir é **desclassificado** de verdade; aviso faltando 3 voltas |
| Carros sempre colados | A IA de todas as equipes usava o mesmo alvo nas curvas | Aerodinâmica da equipe + talento do piloto pesam nas curvas; ritmo varia volta a volta |
| Mesmo som para todos | Só mudava o timbre | Motores **V10 (Valkyr), V6 turbo híbrido (Orion), V8 (Kestrel), V12 (Helix)** + afinação diferente por equipe |
| (encontrado nos testes, com as SUAS opções) Rodava com "Asa móvel automática" | A asa abria e não fechava quando a curva começava sem frear | Fecha ao detectar curva (força lateral/rotação/esterço); zona termina 120 m antes da frenagem; **desativada na chuva** (como na F1 real) |
| (encontrado) Pneus de chuva frios demais | Janela de temperatura irreal | Intermediário ~60 °C, chuva ~42 °C |
| (encontrado) Regra dos 2 compostos nunca desclassificava ninguém | O pneu padrão de fábrica contava como "usado" | Só contam os pneus realmente usados na corrida |

Testes: 14/14 cenários com as configurações padrão **e** com as suas (freio e asa automáticos); câmera trocando
durante a corrida (C e números); corrida de 8 voltas na chuva com 20 carros.

---

## Patch 1.2 — v0.1.2 (correções: brita, rodas disparando, chuva)

| Problema relatado / encontrado | Causa | Correção |
|---|---|---|
| Preso na brita a 2 km/h; ré dava um tranco e parava | Bug do 1.1: o motor deixou de "ver" a roda patinando, o limitador nunca cortava e as rodas disparavam | Motor volta a seguir a roda real (limitador funciona); câmbio usa a velocidade real; brita/grama seguram menos o carro |
| Depois de sair da brita o carro rodava sem parar (IA também) | Roda disparada superaquecia os pneus a 170 °C → sem aderência | Patinar na terra não esquenta o pneu; temperatura máx. 140 °C; superaquecimento tira no máx. ~15% de aderência |
| (encontrado nos testes) Rodava na chuva com slicks | ABS do 1.1 não soltava o freio abaixo de 45% e travava a traseira no molhado | ABS pode aliviar até ~8% |
| (encontrado nos testes) "Rabo de peixe" ao corrigir | Contra-esterço automático exagerado | Controle de estabilidade por guinada (tipo ESP), suave |
| (encontrado nos testes) Controle de tração fraco parado | Limite de 60% abaixo de 4 km/h | Só limita fora do asfalto |
| Carro de costas sem aviso | — | Aviso "CONTRAMÃO — Backspace" no HUD |

### Bateria de testes automáticos (`tests/scenarios.tscn`) — 14/14 OK
Batida frontal no muro a 200 km/h · raspão a 250 · brita a 150 · grama a 200 · parado de costas · parado de lado ·
queda de 3 m · capotado · zebras em alta · chuva forte com slick · sem assistências · câmbio manual + ré ·
batida traseira da IA · pit stop do jogador.
Mais: corrida completa de 2 voltas com 20 carros (seco e chuva) até o resultado, e corrida de 6 voltas com
estratégia (10 pit stops, todos cumprindo a regra dos 2 compostos). Nenhum erro de script.

Observação: sem nenhuma assistência, no teclado o carro roda bastante — é o comportamento de um F1 real
(os jogos oficiais também). Com controle ou volante fica controlável.

---

## Patch 1.1 — v0.1.1 (correções do Patch 1: pilotabilidade)

Correções do seu teste do Patch 1:

| Problema relatado | Causa encontrada | Correção |
|---|---|---|
| Carro derrapa demais, impossível ficar 5 s na pista | No teclado o acelerador ia a 100% quase instantaneamente e o controle de tração só olhava a patinagem para frente, não a traseira escorregando de lado | Acelerador progressivo no teclado; **controle de estabilidade** (corta potência quando a traseira escapa) + contra-esterço automático; direção assistida limita o esterço ao que os pneus aguentam em cada velocidade |
| Ré não funciona | A ré engatava, mas o S continuava sendo freio | Parado, **segure S** → engata a ré e o S acelera para trás (até 25 km/h); W freia/volta para a 1ª |
| Ficar preso na brita/grama | Controle de tração cortava 95% e o câmbio subia marchas com a roda patinando | Fora do asfalto o corte é limitado; câmbio decide pela velocidade real |
| Freio "não acompanha" | ABS soltava o freio muito antes do limite do pneu | ABS agora trabalha no pico de aderência (290→0 km/h em ~3 s) |
| Som de "carro parado" ao frear | RPM caía para marcha lenta quando as rodas seguravam | RPM acompanha a velocidade nas frenagens (reduções audíveis); som do motor ao aliviar mais presente |
| Guia verde/vermelho | Era só visual | Nova assistência **Freio automático (segue a linha)** em Opções |

Validado com um piloto de teclado virtual (`tests/player_test.tscn`): volta inteira sem rodar (deriva máx. ~8°, antes 39°), ré funcionando, freio automático contornando a pista só com o acelerador.

### O que testar
- Pilotar no teclado com as assistências padrão (estabilidade e direção assistida ligadas).
- Bater/sair da pista e sair de ré com S.
- Ligar "Freio automático" em Opções e dar uma volta só acelerando e esterçando.
- Desligar estabilidade/ABS/tração para sentir o carro "cru" (mais difícil, como na vida real).

---

## Patch 1 — v0.1.0 (base jogável)

### O que testar
1. **Menu**: navegar, trocar equipe/piloto (◀ ▶), ver o carro mudar de pintura, Opções salvam ao voltar.
2. **Corrida rápida (5 voltas, 19 adversários, seco)**
   - Semáforo: 5 luzes acendem, apagam → largada.
   - Pilotar com teclado e, se tiver, controle. Sentir frenagem, curvas, saída de curva.
   - Trocar câmera (C) — cockpit, T-Cam, bico, perseguição, TV.
   - Asa móvel (Espaço) nas retas (HUD mostra "DISPONÍVEL").
   - Pedir box (P), escolher pneu no painel (Tab + PgDn), ver a parada e a saída.
   - Sair da pista com as 4 rodas → aviso de limites de pista.
   - Terminar a corrida → tabela de resultado.
3. **Chuva forte**: spray, pista refletindo, aderência menor, pneu de chuva automático.
4. **Treino livre / Contra o relógio**: sai do box, volta lançada, melhor volta e delta.
5. **Desempenho**: FPS aceitável? Se não, baixe a qualidade em Opções → Gráficos.

### Limitações conhecidas (planejadas para os próximos patches)
- Modelo do carro é procedural/provisório (sem o nível de detalhe de um modelo feito por artista).
- Sem danos, safety car, bandeiras amarela/azul, volta de apresentação.
- Retrovisores ainda não refletem.
- Som sintetizado (o sistema já aceita gravações reais em `assets/audio/`).
- Apenas 1 circuito.
- Volante (G29 etc.) funciona como joystick genérico, sem force feedback.

### Validação feita antes de entregar
- Simulação headless de 8 carros: voltas limpas de ~1:34 em 5 km, sem rodadas.
- Pit stop completo testado (entrada → limitador → parada → troca de pneus → saída).
- Desempenho otimizado de ~18 para ~70 FPS com 20 carros (GTX 1650).
- Bug da câmera de cockpit "atrás/dentro do carro" corrigido (interpolação de física).
