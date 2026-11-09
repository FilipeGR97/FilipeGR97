class_name Teams
## Equipes e motoristas FICTÍCIOS (marcas reais da F1 são registradas).
## Para uso pessoal você pode editar nomes/cores aqui — o jogo inteiro lê desta tabela.
##
## power / aero: multiplicadores de desempenho do carro (1.0 = referência)
## engine: chave do fornecedor de unidade de potência (define o som — ver ENGINES)

const ENGINES := {
	"valkyr": {"name": "Valkyr", "power": 1.000, "sound": {"harm": [0.30, 0.55, 0.20, 1.00, 0.35, 0.60, 0.15, 0.28], "drive": 2.4, "noise": 0.22, "rasp": 0.35, "whine": 0.18}},
	"orion": {"name": "Orion", "power": 0.995, "sound": {"harm": [0.45, 0.35, 0.30, 1.00, 0.55, 0.30, 0.25, 0.15], "drive": 1.8, "noise": 0.16, "rasp": 0.20, "whine": 0.26}},
	"kestrel": {"name": "Kestrel", "power": 0.990, "sound": {"harm": [0.20, 0.70, 0.15, 0.90, 0.25, 0.80, 0.10, 0.45], "drive": 3.0, "noise": 0.30, "rasp": 0.50, "whine": 0.12}},
	"helix": {"name": "Helix", "power": 0.985, "sound": {"harm": [0.55, 0.25, 0.40, 1.00, 0.20, 0.45, 0.35, 0.20], "drive": 2.1, "noise": 0.20, "rasp": 0.28, "whine": 0.32}},
}

const TEAMS := [
	{"name": "Vortex Racing", "short": "VTX", "engine": "valkyr", "power": 1.000, "aero": 1.000,
		"primary": Color(0.85, 0.05, 0.08), "secondary": Color(0.95, 0.95, 0.95), "accent": Color(0.08, 0.08, 0.1),
		"drivers": [{"name": "Rafael Moretti", "code": "MRT", "num": 16, "skill": 0.985}, {"name": "Lukas Brenner", "code": "BRE", "num": 44, "skill": 0.975}]},
	{"name": "Aurora Grand Prix", "short": "AUR", "engine": "orion", "power": 1.000, "aero": 0.995,
		"primary": Color(1.0, 0.52, 0.0), "secondary": Color(0.05, 0.1, 0.25), "accent": Color(0.2, 0.75, 1.0),
		"drivers": [{"name": "Oscar Pembroke", "code": "PEM", "num": 4, "skill": 0.99}, {"name": "Mateo Ruiz", "code": "RUI", "num": 81, "skill": 0.98}]},
	{"name": "Titan Racing Team", "short": "TIT", "engine": "kestrel", "power": 0.998, "aero": 1.000,
		"primary": Color(0.06, 0.1, 0.32), "secondary": Color(0.95, 0.15, 0.2), "accent": Color(1.0, 0.8, 0.0),
		"drivers": [{"name": "Max Delacroix", "code": "DEL", "num": 1, "skill": 1.0}, {"name": "Kenji Mori", "code": "MRI", "num": 22, "skill": 0.965}]},
	{"name": "Silverline Motorsport", "short": "SIL", "engine": "orion", "power": 0.997, "aero": 0.99,
		"primary": Color(0.72, 0.75, 0.78), "secondary": Color(0.0, 0.62, 0.55), "accent": Color(0.05, 0.05, 0.06),
		"drivers": [{"name": "Henry Ashcombe", "code": "ASH", "num": 63, "skill": 0.98}, {"name": "Luca Ferrandi", "code": "FER", "num": 12, "skill": 0.97}]},
	{"name": "Falcon Green F1", "short": "FAL", "engine": "helix", "power": 0.99, "aero": 0.985,
		"primary": Color(0.0, 0.36, 0.25), "secondary": Color(0.75, 0.95, 0.2), "accent": Color(0.95, 0.95, 0.95),
		"drivers": [{"name": "Diego Salvatierra", "code": "SAL", "num": 14, "skill": 0.975}, {"name": "Connor Blake", "code": "BLA", "num": 18, "skill": 0.955}]},
	{"name": "Azure Motorsport", "short": "AZU", "engine": "helix", "power": 0.985, "aero": 0.98,
		"primary": Color(0.1, 0.45, 0.9), "secondary": Color(1.0, 0.45, 0.75), "accent": Color(0.95, 0.95, 0.95),
		"drivers": [{"name": "Julien Marchand", "code": "MAR", "num": 10, "skill": 0.965}, {"name": "Tomás Echeverría", "code": "ECH", "num": 43, "skill": 0.955}]},
	{"name": "Corsa Bianca", "short": "COR", "engine": "valkyr", "power": 0.99, "aero": 0.975,
		"primary": Color(0.92, 0.92, 0.94), "secondary": Color(0.1, 0.1, 0.12), "accent": Color(0.85, 0.05, 0.1),
		"drivers": [{"name": "Emil Lindqvist", "code": "LIN", "num": 31, "skill": 0.96}, {"name": "Aiden Price", "code": "PRI", "num": 87, "skill": 0.955}]},
	{"name": "Nova Racing", "short": "NOV", "engine": "kestrel", "power": 0.992, "aero": 0.978,
		"primary": Color(0.95, 0.95, 1.0), "secondary": Color(0.2, 0.3, 0.9), "accent": Color(0.9, 0.1, 0.25),
		"drivers": [{"name": "Karim Nassar", "code": "NAS", "num": 6, "skill": 0.96}, {"name": "Finn O'Rourke", "code": "ORO", "num": 30, "skill": 0.958}]},
	{"name": "Granite Racing", "short": "GRA", "engine": "orion", "power": 0.995, "aero": 0.97,
		"primary": Color(0.03, 0.15, 0.45), "secondary": Color(0.0, 0.7, 1.0), "accent": Color(0.95, 0.95, 0.95),
		"drivers": [{"name": "Viktor Novak", "code": "NOV", "num": 23, "skill": 0.965}, {"name": "Javier Montes", "code": "MON", "num": 55, "skill": 0.97}]},
	{"name": "Selva Racing", "short": "SEL", "engine": "helix", "power": 0.98, "aero": 0.975,
		"primary": Color(0.12, 0.12, 0.12), "secondary": Color(0.0, 0.85, 0.25), "accent": Color(1.0, 0.85, 0.0),
		"drivers": [{"name": "Caio Andrade", "code": "AND", "num": 5, "skill": 0.962}, {"name": "Felipe Rocha", "code": "ROC", "num": 27, "skill": 0.958}]},
]


static func count() -> int:
	return TEAMS.size()


static func team(i: int) -> Dictionary:
	return TEAMS[clampi(i, 0, TEAMS.size() - 1)]


static func engine(key: String) -> Dictionary:
	return ENGINES.get(key, ENGINES["valkyr"])
