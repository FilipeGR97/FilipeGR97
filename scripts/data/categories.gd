class_name Categories
## Categorias de carro (escolhidas no menu). Cada uma muda física, modelo 3D e som.
## Valores de física são do "carro médio"; equipes ainda variam por potência/aero.
##
## ice_kw / mguk_kw: potência do motor a combustão / elétrico (kW)
## mass: massa sem combustível com piloto (kg)
## cla_z/cda_z: downforce/arrasto em modo curva; cla_x/cda_x: modo reta (só com asa ativa)
## mu: aderência base dos pneus; gears: relações (índice = marcha + 1)
## engine: motor de todos os carros ("" = motor da própria equipe); electric = som/ERS de carro elétrico
## model: variação do modelo 3D; ai_k: ajuste do ritmo da IA (o conhecimento foi treinado no F1 2026)

const ORDER := ["f1_2026", "v10", "lenda", "eletrico"]

const DATA := {
	"f1_2026": {
		"name": "F1 2026 (híbrido)", "short": "2026",
		"desc": "Regras atuais: V6 turbo híbrido 400 + 350 kW, asa ativa, modo ultrapassagem, halo.",
		"ice_kw": 400.0, "mguk_kw": 350.0, "mass": 768.0,
		"cla_z": 4.0, "cda_z": 1.35, "cla_x": 2.5, "cda_x": 0.97, "active_aero": true, "mu": 1.8,
		"gears": [-14.0, 0.0, 17.6, 14.6, 12.2, 10.15, 8.5, 7.15, 6.0, 5.05],
		"engine": "", "electric": false, "model": "2026", "ai_k": 1.0, "profile_mu": 1.5,
	},
	"v10": {
		"name": "Clássico V10 (anos 2000)", "short": "V10",
		"desc": "A era dos V10 de 19 mil rpm: ~930 cv, sem híbrido, carro leve e muita pressão aerodinâmica.",
		"ice_kw": 690.0, "mguk_kw": 0.0, "mass": 640.0,
		"cla_z": 4.5, "cda_z": 1.32, "cla_x": 4.5, "cda_x": 1.32, "active_aero": false, "mu": 1.72,
		"gears": [-13.0, 0.0, 16.2, 13.4, 11.4, 9.75, 8.45, 7.4, 6.55, 5.85],
		"engine": "valkyr", "electric": false, "model": "v10", "ai_k": 1.0, "profile_mu": 1.47,
	},
	"lenda": {
		"name": "Lenda (fim dos anos 80/90)", "short": "Lenda",
		"desc": "Carros baixos sem halo, pneus de perfil alto, pouca asa e muito braço. V12 e V10 aspirados.",
		"ice_kw": 545.0, "mguk_kw": 0.0, "mass": 600.0,
		"cla_z": 2.7, "cda_z": 1.12, "cla_x": 2.7, "cda_x": 1.12, "active_aero": false, "mu": 1.68,
		"gears": [-12.0, 0.0, 15.0, 12.2, 10.3, 8.8, 7.6, 6.7, 6.0, 5.45],
		"engine": "lenda", "electric": false, "model": "lenda", "ai_k": 0.97, "profile_mu": 1.38,
	},
	"eletrico": {
		"name": "Elétrico (estilo Fórmula E)", "short": "Elétrico",
		"desc": "Motor elétrico de 350 kW, uma marcha só, regeneração forte na frenagem e pouca asa.",
		"ice_kw": 0.0, "mguk_kw": 350.0, "mass": 860.0,
		"cla_z": 1.7, "cda_z": 0.85, "cla_x": 1.7, "cda_x": 0.85, "active_aero": false, "mu": 1.62,
		"gears": [-6.0, 0.0, 5.4, 5.4, 5.4, 5.4, 5.4, 5.4, 5.4, 5.4],
		"engine": "eletrico", "electric": true, "model": "eletrico", "ai_k": 0.94, "profile_mu": 1.3,
	},
}


static func get_data(key: String) -> Dictionary:
	return DATA.get(key, DATA["f1_2026"])


## Motor (som) que um carro usa nesta categoria.
static func engine_for(cat_key: String, team: Dictionary) -> String:
	var e := String(get_data(cat_key)["engine"])
	if e == "":
		return String(team["engine"])
	if e == "lenda":
		# era clássica: V12 para a equipe lenda; demais alternam V12 / V10 / V8
		var own := String(team["engine"])
		if team.get("legend", false):
			return "helix"
		return {"orion": "valkyr", "kestrel": "kestrel", "valkyr": "valkyr", "helix": "helix"}.get(own, "valkyr")
	return e
