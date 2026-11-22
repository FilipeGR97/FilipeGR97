class_name EngineSamples
## GERADO por tools/build_engine_samples.py (Sonsmotor/videoplayback.m4a e motores_v12_v10_v8_v6.m4a) — não editar à mão.
## Para cada motor: loops gravados 'on' (acelerando) e 'off' (aliviando) e o rpm que cada um representa.

const SHIFT_COUNT := 0

const DATA := {
	"orion": {
		"on": [
			{"file": "on_0.wav", "rpm": 7136.4},
			{"file": "on_1.wav", "rpm": 7686.4},
			{"file": "on_2.wav", "rpm": 8278.8},
			{"file": "on_3.wav", "rpm": 8916.8},
			{"file": "on_4.wav", "rpm": 9604.0},
			{"file": "on_5.wav", "rpm": 10344.2},
			{"file": "on_6.wav", "rpm": 11141.4},
			{"file": "on_7.wav", "rpm": 12000.0},
		],
		"off": [
			{"file": "off_0.wav", "rpm": 7136.4},
			{"file": "off_1.wav", "rpm": 8278.8},
			{"file": "off_2.wav", "rpm": 10344.2},
			{"file": "off_3.wav", "rpm": 12000.0},
		],
		"up": [
			{"file": "up_0.wav", "rpm": 11878.0},
			{"file": "up_1.wav", "rpm": 11837.7},
			{"file": "up_2.wav", "rpm": 8915.5},
			{"file": "up_3.wav", "rpm": 8052.3},
			{"file": "up_4.wav", "rpm": 10026.1},
			{"file": "up_5.wav", "rpm": 8749.6},
		],
		"down": [
			{"file": "down_0.wav", "rpm": 11827.0},
			{"file": "down_1.wav", "rpm": 11824.5},
			{"file": "down_2.wav", "rpm": 11234.3},
			{"file": "down_3.wav", "rpm": 6253.1},
			{"file": "down_4.wav", "rpm": 10579.9},
			{"file": "down_5.wav", "rpm": 10347.3},
		],
	},
	"kestrel": {
		"on": [
			{"file": "on_0.wav", "rpm": 8563.5},
			{"file": "on_1.wav", "rpm": 8986.4},
			{"file": "on_2.wav", "rpm": 9430.1},
			{"file": "on_3.wav", "rpm": 9895.8},
			{"file": "on_4.wav", "rpm": 10384.4},
			{"file": "on_5.wav", "rpm": 10897.2},
			{"file": "on_6.wav", "rpm": 11435.3},
			{"file": "on_7.wav", "rpm": 12000.0},
		],
		"off": [
			{"file": "off_0.wav", "rpm": 8563.5},
			{"file": "off_1.wav", "rpm": 9430.1},
			{"file": "off_2.wav", "rpm": 10897.2},
			{"file": "off_3.wav", "rpm": 12000.0},
		],
		"up": [
			{"file": "up_0.wav", "rpm": 11862.9},
			{"file": "up_1.wav", "rpm": 12242.8},
			{"file": "up_2.wav", "rpm": 12196.1},
			{"file": "up_3.wav", "rpm": 11816.0},
			{"file": "up_4.wav", "rpm": 12153.1},
			{"file": "up_5.wav", "rpm": 12251.7},
		],
		"down": [
			{"file": "down_0.wav", "rpm": 9987.2},
			{"file": "down_1.wav", "rpm": 9983.4},
			{"file": "down_2.wav", "rpm": 11481.1},
			{"file": "down_3.wav", "rpm": 11303.8},
			{"file": "down_4.wav", "rpm": 11216.2},
			{"file": "down_5.wav", "rpm": 10141.5},
		],
	},
	"valkyr": {
		"on": [
			{"file": "on_0.wav", "rpm": 7882.3},
			{"file": "on_1.wav", "rpm": 8370.1},
			{"file": "on_2.wav", "rpm": 8888.0},
			{"file": "on_3.wav", "rpm": 9438.0},
			{"file": "on_4.wav", "rpm": 10022.0},
			{"file": "on_5.wav", "rpm": 10642.2},
			{"file": "on_6.wav", "rpm": 11300.7},
			{"file": "on_7.wav", "rpm": 12000.0},
		],
		"off": [
			{"file": "off_0.wav", "rpm": 7882.3},
			{"file": "off_1.wav", "rpm": 8888.0},
			{"file": "off_2.wav", "rpm": 10642.2},
			{"file": "off_3.wav", "rpm": 12000.0},
		],
	},
	"helix": {
		"on": [
			{"file": "on_0.wav", "rpm": 8631.4},
			{"file": "on_1.wav", "rpm": 9047.4},
			{"file": "on_2.wav", "rpm": 9483.5},
			{"file": "on_3.wav", "rpm": 9940.5},
			{"file": "on_4.wav", "rpm": 10419.6},
			{"file": "on_5.wav", "rpm": 10921.8},
			{"file": "on_6.wav", "rpm": 11448.2},
			{"file": "on_7.wav", "rpm": 12000.0},
		],
		"off": [
			{"file": "off_0.wav", "rpm": 8631.4},
			{"file": "off_1.wav", "rpm": 9483.5},
			{"file": "off_2.wav", "rpm": 10921.8},
			{"file": "off_3.wav", "rpm": 12000.0},
		],
		"up": [
			{"file": "up_0.wav", "rpm": 8906.8},
			{"file": "up_1.wav", "rpm": 7253.3},
			{"file": "up_2.wav", "rpm": 11205.3},
			{"file": "up_3.wav", "rpm": 10283.3},
			{"file": "up_4.wav", "rpm": 11987.4},
			{"file": "up_5.wav", "rpm": 11000.4},
		],
		"down": [
			{"file": "down_0.wav", "rpm": 6613.1},
			{"file": "down_1.wav", "rpm": 6972.1},
			{"file": "down_2.wav", "rpm": 11102.8},
			{"file": "down_3.wav", "rpm": 7035.5},
			{"file": "down_4.wav", "rpm": 9478.9},
			{"file": "down_5.wav", "rpm": 11833.9},
		],
	},
}
