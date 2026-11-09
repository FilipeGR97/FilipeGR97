class_name Tracks
## Definição dos circuitos. Pontos de controle [x, z, altura] em metros (spline Catmull-Rom fechada).
## O primeiro ponto é a linha de chegada; o carro anda do ponto 0 para o ponto 1.

const DATA := {
	"serra_azul": {
		"name": "Autódromo Serra Azul",
		"country": "Brasil (fictício)",
		"width": 14.0,
		"pit_side": 1,              # 1 = lado direito do sentido de corrida, -1 = esquerdo
		"pit_entry": 380.0,         # metros ANTES da linha de chegada
		"pit_exit": 420.0,          # metros DEPOIS da linha
		"pit_speed_kmh": 80.0,
		"ambient_c": 27.0,
		"track_c": 38.0,
		"laps_default": 5,
		"points": [
			[0, 0, 0], [380, 0, 0], [570, 4, 0.5], [640, 30, 1.0], [665, 110, 2.0], [650, 230, 3.5],
			[600, 330, 5.0], [610, 430, 6.0], [700, 500, 7.0], [900, 520, 8.5], [1150, 520, 9.5],
			[1260, 560, 10.0], [1280, 660, 10.0], [1230, 760, 9.5], [1120, 790, 9.0], [1050, 740, 8.5],
			[900, 700, 7.5], [760, 760, 6.5], [620, 720, 5.5], [480, 780, 4.5], [340, 760, 3.8],
			[200, 820, 3.0], [40, 830, 2.4], [-120, 800, 1.8], [-260, 740, 1.2], [-380, 640, 0.8],
			[-430, 500, 0.5], [-420, 360, 0.3], [-470, 300, 0.2], [-460, 220, 0.1], [-560, 120, 0.0],
			[-560, 30, 0.0], [-480, 0, 0.0], [-300, 0, 0.0],
		],
		# pontos (fração da volta) para pórticos/pontes publicitárias
		"bridges": [0.31, 0.62],
		"grandstands": [[0.0, -1, 260.0], [0.115, -1, 120.0], [0.30, 1, 140.0], [0.50, -1, 120.0], [0.92, -1, 140.0]],
	},
}


static func get_data(key: String) -> Dictionary:
	return DATA.get(key, DATA["serra_azul"])


static func keys() -> Array:
	return DATA.keys()
