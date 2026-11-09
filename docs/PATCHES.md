# Patches

Cada patch é testado por você antes de seguirmos. Anote o que achar (bug, sensação de pilotagem, visual) e eu corrijo no patch seguinte.

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
