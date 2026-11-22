class_name Teams
## Equipes e motoristas FICTÍCIOS (marcas reais da F1 são registradas).
## Para uso pessoal você pode editar nomes/cores aqui — o jogo inteiro lê desta tabela.
##
## power / aero: multiplicadores de desempenho do carro (1.0 = referência)
## engine: chave do fornecedor de unidade de potência (define o som — ver ENGINES)

## Som: "orders" = harmônicos em múltiplos de rpm/120 (meia ordem do virabrequim); a combustão de um motor
## de N cilindros fica na ordem N. "harm" = amplitude de cada ordem. "uneven" = irregularidade de queima (V8).
## A arquitetura é só sonora (fictícia) — a potência segue o regulamento do jogo.
const ENGINES := {
	"valkyr": {"name": "Valkyr", "type": "V10 aspirado", "model": "Valkyr VK-10", "layout": "V10 a 90°", "displacement": "3,0 L", "aspiration": "Aspirado + MGU-K", "rpm_max": 19000, "power": 1.000, "sound": {"cyl": 10,
		"orders": [2.0, 5.0, 10.0, 15.0, 20.0, 30.0], "harm": [0.15, 0.30, 1.00, 0.25, 0.60, 0.35],
		"drive": 2.6, "noise": 0.16, "rasp": 0.55, "whine": 0.0, "uneven": 0.0}},
	"orion": {"name": "Orion", "type": "V6 turbo híbrido", "model": "Orion OR-6H", "layout": "V6 a 90°", "displacement": "1,6 L", "aspiration": "Turbo único + MGU-K", "rpm_max": 15000, "power": 0.995, "sound": {"cyl": 6,
		"orders": [1.0, 2.0, 3.0, 6.0, 9.0, 12.0, 18.0], "harm": [0.30, 0.35, 0.30, 1.00, 0.30, 0.50, 0.20],
		"drive": 1.8, "noise": 0.14, "rasp": 0.20, "whine": 0.35, "uneven": 0.0}},
	"kestrel": {"name": "Kestrel", "type": "V8", "model": "Kestrel KS-8", "layout": "V8 a 90°", "displacement": "2,4 L", "aspiration": "Aspirado + MGU-K", "rpm_max": 18000, "power": 0.990, "sound": {"cyl": 8,
		"orders": [1.0, 2.0, 3.0, 4.0, 8.0, 12.0, 16.0], "harm": [0.45, 0.70, 0.30, 0.60, 1.00, 0.30, 0.40],
		"drive": 3.0, "noise": 0.30, "rasp": 0.30, "whine": 0.0, "uneven": 0.35}},
	"helix": {"name": "Helix", "type": "V12", "model": "Helix HX-12", "layout": "V12 a 65°", "displacement": "3,5 L", "aspiration": "Aspirado + MGU-K", "rpm_max": 17500, "power": 0.985, "sound": {"cyl": 12,
		"orders": [2.0, 6.0, 12.0, 18.0, 24.0, 36.0], "harm": [0.10, 0.25, 1.00, 0.30, 0.60, 0.30],
		"drive": 2.2, "noise": 0.12, "rasp": 0.50, "whine": 0.0, "uneven": 0.0}},
	"eletrico": {"name": "Volta", "type": "Elétrico", "model": "Volta E-350", "layout": "Motor elétrico traseiro", "displacement": "—", "aspiration": "Bateria de alta tensão", "rpm_max": 20000, "power": 1.000, "sound": {"cyl": 0,
		"orders": [1.0], "harm": [1.0], "drive": 1.0, "noise": 0.0, "rasp": 0.0, "whine": 1.0, "uneven": 0.0}},
}

const TEAMS := [
	{"name": "Vortex Racing", "chassis": "VX-26", "nick": "Tempesta", "base": "Maranello (ITA)", "short": "VTX", "engine": "valkyr", "power": 1.000, "aero": 1.000,
		"primary": Color(0.78, 0.02, 0.04), "secondary": Color(0.03, 0.03, 0.035), "accent": Color(0.95, 0.95, 0.95),
		"style": 4, "finish": 0, "title": "CORVA",
		"drivers": [{"name": "Rafael Moretti", "code": "MRT", "num": 16, "skill": 0.985}, {"name": "Lukas Brenner", "code": "BRE", "num": 44, "skill": 0.975}]},
	{"name": "Aurora Grand Prix", "chassis": "AG-26", "nick": "Solstice", "base": "Woking (GBR)", "short": "AUR", "engine": "orion", "power": 1.000, "aero": 0.995,
		"primary": Color(1.0, 0.48, 0.0), "secondary": Color(0.1, 0.11, 0.13), "accent": Color(0.15, 0.6, 0.95),
		"style": 0, "finish": 0, "title": "ORBITAL",
		"drivers": [{"name": "Oscar Pembroke", "code": "PEM", "num": 4, "skill": 0.99}, {"name": "Mateo Ruiz", "code": "RUI", "num": 81, "skill": 0.98}]},
	{"name": "Titan Racing Team", "chassis": "TR-26", "nick": "Colossus", "base": "Milton Keynes (GBR)", "short": "TIT", "engine": "kestrel", "power": 0.998, "aero": 1.000,
		"primary": Color(0.035, 0.065, 0.2), "secondary": Color(1.0, 0.76, 0.0), "accent": Color(0.85, 0.06, 0.12),
		"style": 1, "finish": 1, "title": "TAURO",
		"drivers": [{"name": "Max Delacroix", "code": "DEL", "num": 1, "skill": 1.0}, {"name": "Kenji Mori", "code": "MRI", "num": 22, "skill": 0.965}]},
	{"name": "Silverline Motorsport", "chassis": "SM-26", "nick": "Arrow", "base": "Brackley (GBR)", "short": "SIL", "engine": "orion", "power": 0.997, "aero": 0.99,
		"primary": Color(0.015, 0.015, 0.018), "secondary": Color(0.7, 0.72, 0.75), "accent": Color(0.0, 0.62, 0.55),
		"style": 2, "finish": 0, "title": "PETRA",
		"drivers": [{"name": "Henry Ashcombe", "code": "ASH", "num": 63, "skill": 0.98}, {"name": "Luca Ferrandi", "code": "FER", "num": 12, "skill": 0.97}]},
	{"name": "Falcon Green F1", "chassis": "FG-26", "nick": "Peregrine", "base": "Silverstone (GBR)", "short": "FAL", "engine": "helix", "power": 0.99, "aero": 0.985,
		"primary": Color(0.0, 0.22, 0.15), "secondary": Color(0.94, 0.94, 0.92), "accent": Color(0.78, 0.6, 0.2),
		"style": 0, "finish": 2, "title": "TERRA OIL",
		"drivers": [{"name": "Diego Salvatierra", "code": "SAL", "num": 14, "skill": 0.975}, {"name": "Connor Blake", "code": "BLA", "num": 18, "skill": 0.955}]},
	{"name": "Onyx Grand Prix", "chassis": "OX-26", "nick": "Noir", "base": "Enstone (GBR)", "short": "ONX", "engine": "helix", "power": 0.985, "aero": 0.98,
		"primary": Color(0.02, 0.02, 0.022), "secondary": Color(0.83, 0.66, 0.26), "accent": Color(0.83, 0.66, 0.26),
		"style": 5, "finish": 0, "title": "AURUM",
		"drivers": [{"name": "Julien Marchand", "code": "MAR", "num": 10, "skill": 0.965}, {"name": "Tomás Echeverría", "code": "ECH", "num": 43, "skill": 0.955}]},
	{"name": "Corsa Bianca", "chassis": "CB-26", "nick": "Fantasma", "base": "Faenza (ITA)", "short": "COR", "engine": "valkyr", "power": 0.99, "aero": 0.975,
		"primary": Color(0.93, 0.93, 0.94), "secondary": Color(0.04, 0.07, 0.2), "accent": Color(0.8, 0.05, 0.1),
		"style": 6, "finish": 0, "title": "VISTA",
		"drivers": [{"name": "Emil Lindqvist", "code": "LIN", "num": 31, "skill": 0.96}, {"name": "Aiden Price", "code": "PRI", "num": 87, "skill": 0.955}]},
	{"name": "Nova Racing", "chassis": "NR-26", "nick": "Supernova", "base": "Kannapolis (EUA)", "short": "NOV", "engine": "kestrel", "power": 0.992, "aero": 0.978,
		"primary": Color(0.95, 0.95, 0.96), "secondary": Color(0.04, 0.04, 0.045), "accent": Color(0.85, 0.05, 0.1),
		"style": 4, "finish": 0, "title": "NORTHWIND",
		"drivers": [{"name": "Karim Nassar", "code": "NAS", "num": 6, "skill": 0.96}, {"name": "Finn O'Rourke", "code": "ORO", "num": 30, "skill": 0.958}]},
	{"name": "Granite Racing", "chassis": "GR-26", "nick": "Monolith", "base": "Grove (GBR)", "short": "GRA", "engine": "orion", "power": 0.995, "aero": 0.97,
		"primary": Color(0.02, 0.08, 0.28), "secondary": Color(0.0, 0.6, 0.95), "accent": Color(0.95, 0.95, 0.95),
		"style": 6, "finish": 0, "title": "ATLAS",
		"drivers": [{"name": "Viktor Novak", "code": "NOV", "num": 23, "skill": 0.965}, {"name": "Javier Montes", "code": "MON", "num": 55, "skill": 0.97}]},
	{"name": "Selva Racing", "chassis": "SR-26", "nick": "Jaguaré", "base": "Indaiatuba (BRA)", "short": "SEL", "engine": "helix", "power": 0.98, "aero": 0.975,
		"primary": Color(0.95, 0.95, 0.96), "secondary": Color(0.04, 0.04, 0.045), "accent": Color(0.85, 0.95, 0.05),
		"style": 7, "finish": 0, "title": "BRAVO TEL",
		"drivers": [{"name": "Caio Andrade", "code": "AND", "num": 5, "skill": 0.962}, {"name": "Felipe Rocha", "code": "ROC", "num": 27, "skill": 0.958}]},
	# homenagem à era de ouro dos anos 80/90: vermelho e branco, piloto brasileiro de capacete amarelo
	{"name": "Leggenda Racing", "chassis": "LG-88", "nick": "Saudade", "base": "São Paulo (BRA)", "short": "LEG", "engine": "helix", "power": 1.000, "aero": 1.000, "legend": true,
		"primary": Color(0.93, 0.16, 0.12), "secondary": Color(0.97, 0.97, 0.97), "accent": Color(0.04, 0.04, 0.05),
		"style": 3, "finish": 0, "title": "LUMEN",
		"drivers": [{"name": "Beto Lenda", "code": "LEN", "num": 12, "skill": 1.0, "helmet": [Color(1.0, 0.84, 0.0), Color(0.0, 0.55, 0.22), Color(0.08, 0.24, 0.72)]},
			{"name": "Henri Laval", "code": "LAV", "num": 11, "skill": 0.99, "helmet": [Color(0.95, 0.95, 0.97), Color(0.1, 0.2, 0.6), Color(0.85, 0.1, 0.1)]}]},
]


static func count() -> int:
	return TEAMS.size()


static func team(i: int) -> Dictionary:
	return TEAMS[clampi(i, 0, TEAMS.size() - 1)]


## Ficha técnica comum (regulamento 2026 do jogo): todos os carros seguem os mesmos limites.
const SPEC := {
	"peso": "768 kg (mínimo, com piloto, sem combustível)",
	"entre_eixos": "3,40 m",
	"largura": "1,90 m",
	"cambio": "8 marchas sequencial seamless + ré",
	"pneus": "18\" — 3 slicks por GP (C2/C3/C4) + intermediário + chuva",
	"potencia": "~400 kW combustão + 350 kW elétrico (MGU-K)",
	"bateria": "4 MJ (recupera até 8,5 MJ por volta)",
	"aero": "Ativa: modo curva (Z) / modo reta (X)",
}


static func engine(key: String) -> Dictionary:
	return ENGINES.get(key, ENGINES["valkyr"])
