class_name EngineSamples
## GERADO por tools/build_engine_samples.py a partir de Sonsmotor/*_refinadas.mp3 — não editar à mão.
## Para cada motor: loops gravados 'on' (acelerando) e 'off' (aliviando) e o rpm que cada um representa.

const SHIFT_COUNT := 4

const DATA := {
	"valkyr": {
		"on": [
			{"file": "on_0.wav", "rpm": 11289.0},
			{"file": "on_1.wav", "rpm": 11500.0},
		],
		"off": [
			{"file": "off_0.wav", "rpm": 11289.0},
			{"file": "off_1.wav", "rpm": 11500.0},
		],
	},
	"orion": {
		"on": [
			{"file": "on_0.wav", "rpm": 11482.0},
			{"file": "on_1.wav", "rpm": 11500.0},
		],
		"off": [
			{"file": "off_0.wav", "rpm": 2989.0},
			{"file": "off_1.wav", "rpm": 4349.0},
			{"file": "off_2.wav", "rpm": 6937.0},
			{"file": "off_3.wav", "rpm": 10131.0},
		],
	},
	"kestrel": {
		"on": [
			{"file": "on_0.wav", "rpm": 9710.0},
			{"file": "on_1.wav", "rpm": 11500.0},
		],
		"off": [
			{"file": "off_0.wav", "rpm": 6405.0},
			{"file": "off_1.wav", "rpm": 7677.0},
		],
	},
	"helix": {
		"on": [
			{"file": "on_0.wav", "rpm": 11083.0},
			{"file": "on_1.wav", "rpm": 11500.0},
		],
		"off": [
			{"file": "off_0.wav", "rpm": 10266.0},
			{"file": "off_1.wav", "rpm": 10697.0},
		],
	},
}
