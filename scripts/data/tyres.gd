class_name Tyres
## Compostos de pneu (estilo regulamento 2026: 3 slicks escolhidos por GP + intermediário + chuva).
##
## grip: aderência relativa no seco ideal
## wear_km: fração de vida gasta por km em ritmo normal (1/60 => ~60 km de vida)
## t_opt / t_win: temperatura ótima (°C) e largura da janela
## wet_curve: aderência relativa para pista com umidade 0.0 / 0.3 / 0.6 / 1.0

const ORDER := ["soft", "medium", "hard", "inter", "wet"]

const DATA := {
	"soft": {"name": "Macio", "code": "S", "label": "C4", "color": Color(0.95, 0.12, 0.12), "grip": 1.0, "wear_km": 1.0 / 60.0,
		"t_opt": 90.0, "t_win": 26.0, "heat": 1.12, "start_t": 70.0, "wet_curve": [1.0, 0.78, 0.55, 0.42], "slick": true},
	"medium": {"name": "Médio", "code": "M", "label": "C3", "color": Color(1.0, 0.82, 0.05), "grip": 0.978, "wear_km": 1.0 / 95.0,
		"t_opt": 95.0, "t_win": 28.0, "heat": 1.0, "start_t": 70.0, "wet_curve": [1.0, 0.78, 0.55, 0.42], "slick": true},
	"hard": {"name": "Duro", "code": "H", "label": "C2", "color": Color(0.95, 0.95, 0.95), "grip": 0.957, "wear_km": 1.0 / 140.0,
		"t_opt": 100.0, "t_win": 30.0, "heat": 0.9, "start_t": 70.0, "wet_curve": [1.0, 0.78, 0.55, 0.42], "slick": true},
	"inter": {"name": "Intermediário", "code": "I", "label": "INT", "color": Color(0.15, 0.8, 0.25), "grip": 1.0, "wear_km": 1.0 / 90.0,
		"t_opt": 80.0, "t_win": 30.0, "heat": 1.05, "start_t": 55.0, "wet_curve": [0.84, 0.90, 0.86, 0.70], "slick": false},
	"wet": {"name": "Chuva", "code": "W", "label": "WET", "color": Color(0.15, 0.45, 1.0), "grip": 1.0, "wear_km": 1.0 / 100.0,
		"t_opt": 68.0, "t_win": 30.0, "heat": 1.0, "start_t": 50.0, "wet_curve": [0.72, 0.80, 0.85, 0.84], "slick": false},
}


static func get_data(key: String) -> Dictionary:
	return DATA.get(key, DATA["medium"])


static func wet_factor(key: String, wetness: float) -> float:
	var c: Array = get_data(key)["wet_curve"]
	var xs := [0.0, 0.3, 0.6, 1.0]
	wetness = clampf(wetness, 0.0, 1.0)
	for i in 3:
		if wetness <= xs[i + 1]:
			var t: float = (wetness - xs[i]) / (xs[i + 1] - xs[i])
			return lerpf(c[i], c[i + 1], t)
	return c[3]


## Pneu ideal para uma umidade de pista.
static func best_for(wetness: float) -> String:
	if wetness < 0.2:
		return "medium"
	if wetness < 0.72:
		return "inter"
	return "wet"
