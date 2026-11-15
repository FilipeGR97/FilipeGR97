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
		"laps_full": 61,
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
	"monaco": {
		"name": "Circuito de Mônaco",
		"country": "Mônaco",
		"width": 11.0,
		"street": true,             # circuito de rua: guard-rail colado, prédios, porto, túnel
		"runoff": 1.4,
		"pit_side": 1,
		"pit_entry": 215.0,
		"pit_exit": 170.0,
		"pit_taper": 50.0,
		"pit_speed_kmh": 60.0,
		"ambient_c": 23.0,
		"track_c": 34.0,
		"laps_default": 5,
		"laps_full": 78,
		# traçado digitalizado do mapa oficial (19 curvas, sentido horário, 3.337 m);
		# altura: subida da Sainte Dévote ao Cassino (~42 m) e descida até o túnel
		"points": [
			[0, 0, 2], [78.7, -88.4, 4], [138.1, -140.9, 6], [165.7, -158.8, 7], [193.4, -146.4, 9], [251.4, -102.2, 15],
			[327.3, -55.2, 22], [403.3, -16.6, 29], [479.2, 15.2, 34], [541.4, 45.6, 37], [589.7, 82.9, 39], [624.3, 116, 40],
			[668.5, 110.5, 41], [696.1, 77.3, 42], [707.1, 24.9, 43], [712.7, -16.6, 44], [741.7, -33.1, 44], [817.6, -44.2, 41],
			[886.7, -55.2, 37], [930.9, -62.2, 34], [936.4, -44.2, 32], [911.5, -13.8, 29], [892.2, 13.8, 27], [881.1, 37.3, 25],
			[882.5, 56.6, 23], [895, 69.1, 22], [908.8, 62.2, 21], [919.8, 44.2, 19], [944.7, 13.8, 16], [966.8, 24.9, 14],
			[991.6, 48.3, 11], [980.6, 73.2, 9], [921.2, 114.6, 7], [845.2, 153.3, 6], [762.4, 183.7, 5], [679.5, 185.1, 5],
			[610.5, 167.1, 5], [548.3, 146.4, 5], [486.2, 118.8, 4], [444.7, 98.1, 3], [419.9, 82.9, 2], [400.5, 93.9, 2],
			[375.7, 96.7, 2], [356.3, 71.8, 2], [337, 38.7, 2], [292.8, -2.8, 2], [237.6, -40.1, 2], [189.2, -66.3, 2],
			[157.4, -71.8, 2], [124.3, -55.2, 2], [102.2, -30.4, 2], [88.4, 0, 2], [84.2, 33.1, 2], [64.9, 63.5, 2],
			[30.4, 93.9, 2], [0, 110.5, 2], [-20.7, 132.6, 2], [-30.4, 176.8, 2], [-33.1, 232, 2], [-29, 284.5, 2],
			[-33.1, 314.9, 2.5], [-55.2, 325.9, 3], [-82.9, 312.1, 4], [-113.3, 280.4, 5], [-129.8, 248.6, 6], [-121.5, 225.1, 6],
			[-93.9, 179.5, 4], [-52.5, 93.9, 3],
		],
		# [s_ini, s_fim, lado(-1 esq, 1 dir, 0 ambos), largura]: escapes reais (Sainte Dévote, Mirabeau, chicane)
		"escapes": [[150.0, 255.0, -1, 9.0], [1150.0, 1215.0, -1, 5.0], [2070.0, 2200.0, 0, 6.0]],
		"tunnels": [[1530.0, 1935.0]],
		# trechos sem prédios (vista para o porto/mar): [s_ini, s_fim, lado]
		"open": [[262.0, 560.0, 1], [1935.0, 2450.0, -1], [2120.0, 2440.0, 1], [2450.0, 2760.0, -1]],
		"bridges": [],
		"grandstands": [[0.785, 1, 80.0], [0.935, -1, 90.0]],
	},
}


static func get_data(key: String) -> Dictionary:
	if not DATA.has(key):
		key = "serra_azul"
	var d: Dictionary = DATA[key].duplicate()
	d["key"] = key
	return d


static func keys() -> Array:
	return DATA.keys()
