# Patches

Cada patch é testado por você antes de seguirmos. Anote o que achar (bug, sensação de pilotagem, visual) e eu corrijo no patch seguinte.

---

## Patch 7 — v0.7.0 (modelo 3D real no carro 2026)

### Modelos enviados — checagem de licença
| Modelo | Resultado |
|---|---|
| Ferrari SF90 2019 (VeCarz, CC BY 4.0) | ✅ **em uso** como carro da categoria 2026 |
| McLaren MP4/5 1989 (VeCarz, CC BY 4.0) | ✅ liberado — falta a versão glTF/GLB (o arquivo veio em .blend) |
| Capacete (Fabianmml, CC BY) | ✅ liberado — próximo passo |
| Aston Martin AMR25 | ❌ texturas da Force India do jogo da Codemasters |
| McLaren MCL60 | ❌ reenvio de modelo de outro autor |
| Ferrari F2008 | ⚠️ conversão de mod de jogo antigo |
| Luva (HandPGlove) | ⚠️ autor não identificado; mão aberta sem esqueleto (não segura o volante) |

### Carro 2026 novo
- Formato real de F1 moderno (halo, sidepods esculpidos, asas com vários elementos, suspensão, assoalho).
- **Repintado com as nossas equipes**: onde era a pintura original, entra a pintura da equipe (mesmos estilos do
  Patch 6); carbono, metal e detalhes do modelo continuam.
- **Sem marcas reais**: logos originais escondidos; nos mesmos lugares entram os patrocinadores fictícios e o número.
- Rodas, volante, mãos e capacete do jogo encaixados no modelo; câmeras e retrovisores ajustados.
- Crédito no menu e em `assets/CREDITOS.md` (exigência da licença).

### Correções
- Câmera **Bico** (tecla 4) ficava dentro do bico no carro novo (tela escura) — agora fica em cima dele.
- Textos de patrocinador não projetam mais sombra (custo menor com 20 carros).

---

## Patch 6 — v0.6.0 (carros e pinturas)

Inspirado no nível de detalhe dos carros de referência (cor, acabamento, adesivos) — feito no nosso modelo:
os 3 modelos enviados vieram extraídos dos jogos da EA/Codemasters (nomes internos "gp21", "RBRWHEEL10"...),
então serviram só de referência visual e não entram no jogo.

### Pinturas novas (cores que existem de verdade, patrocinadores fictícios)
| Equipe | Pintura | Acabamento | Patrocinador |
|---|---|---|---|
| Vortex | vermelho em cima, preto embaixo, filete branco | brilhante | CORVA |
| Aurora | laranja papaia e grafite, detalhe azul | brilhante | ORBITAL |
| Titan | azul-marinho com lâmina vermelha e amarela | **fosco** com textura | TAURO |
| Silverline | preto com campo de estrelas prateadas em degradê e faixa verde-petróleo | brilhante | PETRA |
| Falcon | verde inglês com faixa creme e dourado | **metálico** | TERRA OIL |
| **Onyx** (era Azure) | todo preto com filetes dourados | brilhante | AURUM |
| Corsa Bianca | branco que vira azul-marinho em degradê de pontos | brilhante | VISTA |
| Nova | branco em cima, preto embaixo, filete vermelho | brilhante | NORTHWIND |
| Granite | azul-escuro que vira azul-claro em pontos | brilhante | ATLAS |
| Selva | branco, preto e amarelo fluorescente | brilhante | BRAVO TEL |
| Leggenda | vermelho e branco com a seta | brilhante | LUMEN |

Sem rosa e sem verde-limão.

### Detalhes
- **Adesivos** projetados na carroceria: placa de inspeção, seta de resgate, aviso de alta tensão, tira técnica,
  quadriculado na tampa do motor, fornecedor de pneus no bico, parafusos nas placas das asas.
- **Rodas**: borda do aro usinada, **calota de carbono** (2026/elétrico) ou **aro de raios prateado**
  (V10/Lenda) e **porca central** na cor de destaque da equipe — acabou o "buraco preto" no meio da roda.

### Testes
14/14 cenários, corridas em Serra Azul e Mônaco (Lenda) sem erros; FPS igual ao Patch 5.1 (medido lado a lado).

---

## Patch 5.1 — v0.5.1 (motores da gravação nova)

- **V12, V8 e V6** refeitos a partir da gravação "F1 sons dos motores" (volta onboard de cada motor):
  som mais cheio e brilhante, mais perto de um carro de verdade.
- **Trocas de marcha gravadas** (V12/V8/V6): a subida toca o corte real da troca e a redução toca o "blip"
  real, afinados pelo giro do momento. Volume da troca controlado (sem "subida" de volume).
- **V10 mantido como no Patch 5** — o V10 gerado da gravação nova ficou estranho na troca e "piava" na
  última marcha, então voltou ao anterior (que você aprovou).
- Tons agudos isolados aparados nos motores novos (o que virava "piado" no giro máximo).
- Ferramentas: `tools/build_engine_samples.py --fonte 2` (nova gravação, trocas) e `tools/engine_loop_fix.py`
  (acha e refaz automaticamente loops com timbre fora da curva).

**Teste:** escolha equipes com V12 (Falcon, Onyx, Selva, Leggenda), V8 (Titan, Nova) e V6 (Aurora, Silverline,
Granite) e diga qual motor ficou bom ou ruim — consigo voltar qualquer um para a versão anterior na hora.

---

## Patch 5 — v0.5.0 (visual estilo F1 2006 + som sem estouro)

Baseado no vídeo de referência (F1 2006 com mod, Silverstone): enquadramento, pista, cockpit, rodas e piloto.

### Câmera
- **Nova câmera "Clássica"** (tecla **8**): alta, logo atrás do capacete — vê o capacete embaixo, as mãos no
  volante, as rodas dianteiras e a suspensão, como nos jogos de 2006. No V10 e no Lenda (sem halo) fica igual ao vídeo.

### Pista e cenário
- **Céu de foto 360°** (nuvens de verdade) com o sol da foto alinhado à luz do jogo; céus próprios para chuva
  leve (nuvens carregadas) e chuva forte (nublado).
- **Asfalto com textura real**, trilho de borracha mais escuro e **marcas de pneu** no traçado; faixas brancas nítidas.
- **Zebras pintadas** com grão do asfalto e sujeira de borracha; **brita** com textura de cascalho real.
- **Grama** mais escura e natural, com **listras de corte** largas.
- **Arquibancadas novas**: degraus de concreto, cadeiras coloridas por setor, cobertura com pilares e
  **público sentado em 3D** (milhares de torcedores com camisetas de cores variadas).
- **Árvores de verdade** (copa de folhas recortadas, não mais "bolas") e **mata contínua no horizonte**.
- Texturas e céus: Poly Haven, licença CC0 (ver `assets/CREDITOS.md`).

### Carro e piloto
- **Pneus com letreiro na lateral** (marca fictícia VELTRA CORSA R1) e faixa do composto pintada.
- **Capacete pintado** com desenho gráfico e contorno (setas como no vídeo, faixa central, diagonais; o do
  Beto Lenda com as faixas da homenagem), verniz brilhante.
- **Luvas** de couro claro acolchoadas, punho longo com velcro na cor da equipe, palma de camurça; braços
  dentro do cockpit (de cima só aparecem as luvas).
- **Volante estilo 2006**: botões redondos coloridos com aro de alumínio, seletores, manoplas de camurça,
  carbono em sarja; LCD verde no V10, tela colorida no 2026, volante simples no Lenda.
- Pintura do carro sem serrilhado nas bordas das cores; equipe prateada com **pintura metálica**.

### Correções
- **Retrovisores pretos** na câmera nova e **com atraso** (atualizavam a 30 fps): agora uma câmera traseira
  atualizada **todo quadro**, mesma posição interpolada da câmera principal — fluido, sem defasagem.
- **Som estourado/chiado** em curvas e freadas: a mistura passava ~3 dB do limitador o tempo todo (ele vivia
  "apertando"). Agora há folga e o limitador só pega picos raros (medido: 16,6% → 0% do tempo no teto).
  Volume médio ~2,7 dB menor — se quiser, suba o Volume geral.
- Pneu cantando virou um **guincho tonal** (antes era ruído de banda larga = chiado).
- **Zebra** com baques graves (~38 por segundo a 180 km/h, como na referência) e **"tum" de lombada** ao subir
  na zebra em velocidade.
- **Motores V6, V8 e V12**: trechos gravados com timbre fora da curva (o som "trocava de motor" ao acelerar)
  foram refeitos a partir dos vizinhos bons; V6 equalizado para o brilho de um carro 2026. V10 intacto.

### Testes
14/14 cenários (padrão e sua configuração), pilotagem (deriva máx 7,1°, 0 rodadas), brita, corridas de
20 carros em Serra Azul e Mônaco. Gravação de áudio: 0 amostras estouradas.

---

## Patch 4 — v0.4.0 (categorias, visual e IA no 100%)

### IA no 100% (você dava volta nela)
- A IA já pilotava no limite do que o controle dela consegue (~1:26–1:27 na Serra Azul); forçar mais só fazia
  ela rodar. Agora, de **90 a 100**, a equipe "otimiza o carro": até **+5% de aderência e +3% de potência**,
  e a IA usa esse ganho: no 100% ela vira **1:25.2** sem rodar (antes 1:27.4).
- "100%" agora é 100% (a escala parava em 0,99).
- O jogo **grava suas voltas** em `voltas.csv` (pasta de dados do jogo) com o melhor tempo da IA na mesma
  corrida — para calibrar a dificuldade com os seus tempos reais.

### Categorias de carro (Corrida → Categoria)
| Categoria | Física | Som | Visual |
|---|---|---|---|
| **F1 2026** | híbrido 400+350 kW, asa ativa | V6/V8/V10/V12 por equipe | halo, 18" |
| **Clássico V10** (anos 2000) | ~930 cv, 640 kg, muita asa, sem híbrido | V10 | bico alto com pilones, asa alta, pneus com sulcos, rodas 13" |
| **Lenda** (fim dos 80/90) | 730 cv, 600 kg, pouca asa | V12 / V10 / V8 | sem halo, santantônio, bico baixo, asa traseira enorme, pneus de perfil alto |
| **Elétrico** (estilo Fórmula E) | 350 kW, 1 marcha, regeneração | zumbido elétrico + inversor | para-lamas, asa baixa, pneus com desenho; painel mostra **bateria** |

Tempos da IA na Serra Azul: V10 1:21.6 · 2026 1:27.0 · Lenda 1:29.4 · Elétrico 1:50.6.

### Equipe Leggenda (homenagem à era de ouro)
Pintura vermelha e branca com a "seta" no sidepod, piloto brasileiro **Beto Lenda #12** com **capacete amarelo
com faixas verde e azul**, motor V12. Disponível em todas as categorias.

### Cockpit, piloto e carro
- **Volante novo**: corpo de carbono, manoplas emborrachadas, tela com a marcha, LEDs de troca, botões,
  seletores rotativos e borboletas. Visível na câmera "olhos do piloto" e na "atrás do piloto".
- **Luvas** segurando as manoplas (dedos envolvendo, polegar por cima) e **braços** com o macacão da equipe
  que dobram o cotovelo quando o volante gira (cinemática inversa).
- **Capacete** de verdade: casco, viseira escura, faixa/listra nas cores do piloto, spoiler, HANS.
- **Patrocinadores fictícios** (VOLTEX, ZENTRA, BRAVO TEL, AXION...) no sidepod, asa traseira, tampa do motor,
  bico e asa dianteira.
- Tamanho conferido com o regulamento 2026: entre-eixos 3,40 m, largura 1,90 m, rodas 18".

### Visual e som
- Iluminação nova: tonemapping AgX, sol mais forte e baixo, sombras de contato (SSAO) mais marcadas,
  luz indireta em tela (SSIL) no gráfico Alto/Ultra, mais contraste.
- Árvores com copa irregular e coníferas (no lugar das "árvores-pirulito").
- **Zebra**: batidas rítmicas (uma por nervura, acompanham a velocidade), baque grave + estalo + chocalho,
  mais forte quanto mais rodas em cima. Gravação conferida: 0 estouros.

### Testes
14/14 cenários (padrão e sua configuração), pilotagem, brita, Mônaco, corridas de 20 carros em todas as
categorias (Elétrico: 0 toques fortes; 2026 e V10 como antes; Lenda com mais contato na largada, como a época).

---

## Patch 3 — v0.3.0 (Mônaco + IA que aprende a pista)

### Circuito de Mônaco
- Traçado digitalizado do mapa oficial: **3.337 m, 19 curvas, sentido horário** — Sainte Dévote, subida do
  Beau Rivage, Massenet, Cassino, Mirabeau, **grampo do Grand Hotel** (raio ~10 m, o mais lento do ano),
  Portier, **túnel**, chicane do porto, Tabac, piscina, Rascasse e Anthony Noghes.
- Altimetria real: sobe ~42 m da Sainte Dévote até o Cassino e desce até o túnel.
- **Modo circuito de rua** (novo no gerador de pistas): guard-rail colado na pista, calçada, quarteirões de
  prédios em tons pastel, **mar/porto** com reflexo e ondas, túnel com teto, iluminação e luz própria,
  áreas de escape só onde existem de verdade (Sainte Dévote, Mirabeau, chicane), pit lane curto (60 km/h).
- Menu: opção **Distância total** nas voltas (Mônaco = 78 voltas, Serra Azul = 61).

### IA nova (o que você percebeu estava certo)
Medimos: a IA antiga dava **1:32.6** na Serra Azul, mas o carro dela aguenta **1:26** — ela deixava ~6 s por
volta na mesa porque seguia o perfil conservador da linha guia (o vermelho da linha).
- **Conhecimento da pista**: cada trecho tem um fator de ritmo aprendido (como o simulador das equipes):
  onde dá, a IA freia depois e contorna mais rápido que a linha guia; onde o carro não aguenta, alivia.
  Vem pré-treinado para cada pista (`data/ai/*.json`) e continua se ajustando na corrida (se escorrega numa
  curva, alivia naquela curva nas voltas seguintes).
- **Direção corrigida**: a IA compensava duas vezes a deriva do carro e não dava ao pneu dianteiro o ângulo
  que ele precisa — abria nas curvas no limite. Agora limita o esterço ao que a frente aguenta (como a sua
  assistência de direção).
- **Pneu frio** (largada, saída do box): a IA respeita a aderência menor.
- **Defesa**: com alguém colado atrás antes de uma frenagem, fecha a porta por dentro — um movimento só.
- **Ataque**: escolhe o lado de **dentro** da próxima curva e, emparelhada, **freia mais tarde** para completar.
- Cada piloto tem agressividade própria (os mais habilidosos defendem/atacam mais).
- **Distância de segurança recalculada a cada passo** + frenagem de emergência ao ver o carro da frente
  frear (antes era 20×/s com a velocidade "velha" do líder — com a IA freando mais forte isso dava batida
  traseira). Na chuva a distância aumenta (freia-se menos).
- **Dificuldade reescalonada**: 100 = limite do carro; 85–95 ≈ 1–2,5 s mais lenta que o limite.

### Correções encontradas
- O prédio dos boxes era uma caixa reta de 345 m; numa reta de box curva (Mônaco) a ponta **invadia a pista**
  (batida "invisível"). Agora é feito em segmentos que acompanham a reta.
- Câmeras de TV de circuito de rua ficavam dentro dos prédios.

### Testes feitos
- IA na Serra Azul: 1:32.6 (antiga) → **1:26.1** no limite; dificuldade ~95% ≈ 1:28, ~85% ≈ 1:29.
- Corridas com 20 carros: Serra Azul seco (3 danos leves de asa, nenhum VSC), Serra Azul **chuva forte**
  (nenhum VSC, 1 dano leve — antes eram 4 VSCs em 3 voltas), Mônaco (1–2 danos leves, sem carro parado).
- 14/14 cenários (configuração padrão e a sua), teste de pilotagem e da brita.

### Ferramentas novas (dev)
`tests/ai_lab.gd` (ritmo/limpeza da IA, `learn` treina a pista), `tests/car_limits.gd` (frenagem máxima real),
`tests/skidpad.gd` (aderência lateral).

### O que testar
- Corrida em **Mônaco** (Corrida rápida → Circuito). Repare no túnel, no porto e nos prédios.
- Corrida na Serra Azul com dificuldade 85–95 no modo manual: a IA deve andar no seu ritmo, defender e atacar.
- Se ficar difícil demais, baixe a dificuldade (a escala mudou).

---

## Patch 2.1 — v0.2.1 (correções do box)

| Problema relatado | Causa | Correção |
|---|---|---|
| Depois do pneu furado, no box o carro deu ré até a entrada do box | Durante o atendimento o piloto automático segura o freio; com o carro parado, o câmbio automático engatava a **ré** (regra do "segure S") e o freio virava acelerador de ré | Ré automática só para o jogador **fora** do box; no atendimento o carro fica em **ponto morto** e travado; sai em 1ª |
| Carro "estacionado atravessado" na pit lane, batida e dano na asa | Dentro do box não existia recuperação: um carro atingido ali ficava parado para sempre | Recuperação dentro do box (recoloca alinhado após 3 s); o piloto automático **espera atrás** de carro parado na faixa em vez de bater |
| (encontrado) Companheiro de equipe usando a mesma vaga | Dois carros da equipe iam para a vaga ao mesmo tempo | **Fila no box**: o segundo carro espera 9 m atrás até a vaga liberar (como na F1 real) |
| (encontrado) Atendimento não começava se o carro parasse um pouco depois da marca | Tolerância de 2,5 m | A equipe atende mesmo com o carro um pouco além da marca |
| (encontrado) IA com pneu furado andava no ritmo normal e rodava | — | IA com furo anda devagar até o box; com asa quebrada alivia conforme o dano |

Testes: jogador com pneu furado entrando no box (para na marca, atende em ponto morto, sai para a frente);
dois carros da mesma equipe chegando juntos (fila funcionando, nenhum contato); 14/14 cenários nas duas configurações.

---

## Patch 2 — v0.2.0 (corrida de verdade: ajuste, danos, bandeiras, VSC, retrovisores)

### Novidades
- **Ajuste do carro** (Corrida/Treino → *Ajuste do carro*): asa dianteira e traseira, molas, barras estabilizadoras,
  diferencial e balanço de freio, com pré-ajustes (*Baixa pressão*, *Equilibrado*, *Alta pressão*, *Chuva*).
  Mostra o efeito na pressão aerodinâmica, no arrasto e no equilíbrio. Fica salvo.
- **Danos**: batidas fortes de frente quebram a **asa dianteira** (perde pressão na frente, o carro sai de frente
  e fica mais lento); impactos laterais fortes podem **furar um pneu**. O visual da asa entorta/solta.
  O **pit stop conserta** (+6,5 s para trocar o bico). A IA também quebra e vai ao box.
- **Bandeiras**: **amarela** no setor com carro parado/batido (a IA alivia); **azul** para retardatário
  quando o líder chega (a IA abre caminho; você recebe o aviso).
- **Virtual Safety Car**: entra com carro parado na pista ou acidente forte. Todos andam num ritmo limitado;
  o HUD mostra sua diferença para o limite (verde/vermelho). Acima do limite por 3 s = **+5 s**.
  Asa móvel desligada durante o VSC.
- **Retrovisores funcionando** nas câmeras de 1ª pessoa (opção para desligar em Opções → Gráficos).

- **Som com qualidade de estúdio**: os loops passam por limpeza espectral (ruído/ambiente/artefatos de
  compressão do vídeo −3 a −7 dB entre os harmônicos), equalização (corpo nos graves, presença), excitador que
  reconstrói os agudos cortados pela compressão (6–16 kHz) e **estéreo** natural (correlação 0,8) no seu motor.
  Pulsação mantida em 7–11% (motor real: 10–14%), 0 estouros.
- Detecção de batida por **impulso de contato** real (muros e carros; chão não conta) e ponto do choque
  (bico → asa; lateral/roda → furo). VSC só com carro parado > 6 s ou batida muito forte, com intervalo de 60 s.

### O que testar
- Ajuste do carro: compare *Baixa pressão* e *Alta pressão* (velocidade final × curvas).
- Bata de frente num muro: aviso de dano, carro saindo de frente; vá ao box e veja o conserto.
- Pare o carro no meio da pista numa corrida: bandeira amarela e VSC.
- Seja retardatário (dificuldade alta, corrida longa): bandeira azul.
- Olhe os retrovisores na câmera atrás do piloto.

### Deixado para o Patch 2.1+
Safety Car com carro físico e fila, volta de apresentação, danos de suspensão/assoalho, telemetria.

---

## Patch 1.7 — v0.1.7 (ajuste fino 7ª/8ª)

- Encontrados **tons estranhos** (sons de fundo do vídeo — outro carro/eco) dentro dos loops de giro alto
  (V10 9,4–11,3 mil rpm, V8 e V12): não seguiam o motor e desafinavam/batiam justamente na 7ª/8ª.
  Removidos com filtros estreitos que preservam a série harmônica real de cada motor.
- Micro-variação de afinação reduzida (podia soar como "vibrato" com o giro estável).
- Descartado: o limitador do áudio não era o problema (atua em 0,01% das amostras).
- Medições: pulsação na 7ª/8ª 6–8%, aspereza dentro da faixa do vídeo real, 0 estouros.

---

## Patch 1.6 — v0.1.6 (7ª/8ª marcha sem "na na na" + seu motor em destaque)

| Problema relatado | Causa encontrada (medida) | Correção |
|---|---|---|
| 7ª e 8ª: som "na na na na" | Loops de só 0,33 s; com o giro quase parado (reta longa) a repetição virava pulso (~3x/s). Medido: 37–65% de repetição a cada 0,34 s; no vídeo real 8–17% | Loops de **1–2 s** costurados de vários trechos do vídeo no mesmo giro, com fase alinhada nas emendas e volume nivelado; micro-variação viva de afinação/volume |
| V6 pulsando | Assobio sintético de turbo "batendo" com os harmônicos gravados | Removido nos motores com gravação (o turbo real já está no som) |
| Som baixo em 7ª/8ª | Mistura longa entre dois loops (som "oco") + camadas com folga demais | Mistura só na faixa central entre loops; **seu motor +5 a +8 dB** |
| Quero ouvir o meu motor, os outros abafados | — | Adversários −5 dB e com filtro de abafamento por distância |

Medições: pulsação do motor na 8ª **6–10%** (antes 20–27%; vídeo real 10–14%), picos 0,71, **0 estouros**,
inclusive com 20 carros. Nova ferramenta de teste `-- dyno` (bancada: motor em giro fixo, carro parado).

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
