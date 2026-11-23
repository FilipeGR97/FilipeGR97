# Roadmap

Ordem pensada para ter sempre algo jogável, priorizando o que mais aproxima de um simulador de F1 real.

## Patch 2 — sensação de pilotagem e corrida (✅ entregue: ajuste, danos de asa/pneu, bandeiras, VSC, retrovisores)
- Ajustes de física a partir do seu feedback (frenagem, sobre/subesterço, zebras, pneus).
- Volta de apresentação + largada parada com grid organizado.
- Bandeiras: amarela, azul (retardatários), quadriculada animada.
- Danos: asa dianteira, furo de pneu, perda de aerodinâmica.
- Safety Car e Virtual Safety Car.
- Retrovisores funcionando.
- Setup do carro na garagem: asa, altura, molas, barras, câmber, pressão, diferencial, relações.

## Patch 3 — pistas e IA (✅ entregue: Mônaco, circuito de rua, IA que aprende a pista)
- Circuito de Mônaco (traçado oficial, 19 curvas, túnel, porto, prédios).
- Modo "circuito de rua" no gerador de pistas (guard-rail colado, calçada, cidade, mar).
- IA nova: freia e faz curva no limite real do carro, aprende cada curva, defende por dentro, ataca freando mais tarde.

## Patch 4 — categorias e visual (✅ entregue: V10/Lenda/Elétrico, Leggenda, cockpit com mãos, capacete, patrocinadores, luz)

## Patch 5 — visual estilo F1 2006 (✅ entregue: céu de foto, asfalto/brita reais, câmera clássica, pneus com letreiro, público 3D, árvores, capacete pintado, luvas, volante, retrovisor fluido)

## Patch 6 — carros e pinturas (✅ entregue: pinturas realistas por equipe, acabamento fosco/brilhante/metálico, adesivos de detalhe, rodas com aro/calota/porca)

## Patch 7 — modelos 3D reais (✅ entregue: carro 2026 com modelo CC-BY repintado; 7.1: MP4/5 na Lenda, capacete e luvas CC-BY; 7.2: checkup geral, código sem nenhum aviso do Godot)

## Patch 8 — fim de semana completo
- Treinos livres 1–3, Classificação Q1/Q2/Q3 (eliminação), Sprint, Corrida.
- Parc fermé, escolha de pneus por sessão (alocação de jogos).
- Rádio da equipe (mensagens de estratégia, "box box").
- Clima dinâmico (chuva começando/parando, pista secando por traçado).

## Patch 9 — conteúdo
- Mais circuitos (alta velocidade, travado, noturno).
- Modelos 3D de verdade para os carros (.glb) — via Blender ou modelos licenciados.
  O pipeline já existe: `assets/cars/<sigla>.glb` substitui o carro procedural.
- Sons gravados por motor (`assets/audio/<motor>_on.ogg` / `_off.ogg`).
- Personalização de pintura e capacete.

## Patch 10+ — modos de longo prazo
- Campeonato (temporada completa com pontos).
- Modo carreira (contratos, desenvolvimento do carro, regras de orçamento).
- Replays e câmera de TV com corte automático.
- Force feedback para volantes, telemetria (gráficos de volta).
- Multiplayer (avaliar depois que o single player estiver sólido).
