local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.TimeProfiles = QM.TimeProfiles or {}
QM.TimeProfiles.version = 1
QM.TimeProfiles.maps = {
	["village_01"] = {
		settings = {
			dayDurationSec = 7200,
			timelinePreset = "narrative_balanced",
		},
		timeline = {
			{
				key = "aube",
				label = "Aube",
				share = 0.0737,
				colors = {
					background = {
						r = 0.5800,
						g = 0.6600,
						b = 0.8000,
						a = 1.0000,
					},
					models = {
						colorTemperature = -0.3300,
						lightColorR = 0.7700,
						lightColorG = 0.8500,
						lightColorB = 1.0000,
						lightLuminance = 0.6400,
					},
				},
				ai = {
					dynamism = 0.8200,
					interaction = 0.7800,
					autoIntentRate = 0.8500,
					needsDrain = 0.9000,
					needsRecovery = 1.0800,
					actionWeights = {
						rest = 3.0000,
						meal = 1.8000,
						distraction = 0.9000,
						move_place = 0.8400,
						observe_nature = 1.0500,
						talk = 1.5000,
					},
				},
			},
			{
				key = "matin",
				label = "Matin",
				share = 0.2026,
				colors = {
					background = {
						r = 0.7000,
						g = 0.7200,
						b = 0.7400,
						a = 1.0000,
					},
					models = {
						colorTemperature = -0.0200,
						lightColorR = 1.0000,
						lightColorG = 1.0000,
						lightColorB = 1.0000,
						lightLuminance = 1.0000,
					},
				},
				ai = {
					dynamism = 1.0000,
					interaction = 1.0000,
					autoIntentRate = 1.0000,
					needsDrain = 1.0000,
					needsRecovery = 1.0000,
					actionWeights = {
						rest = 2.0000,
						meal = 1.7000,
						distraction = 0.6700,
						move_place = 1.3800,
						observe_nature = 1.0000,
						talk = 1.0000,
					},
				},
			},
			{
				key = "midi",
				label = "Midi",
				share = 0.1474,
				colors = {
					background = {
						r = 0.7800,
						g = 0.7500,
						b = 0.6800,
						a = 1.0000,
					},
					models = {
						colorTemperature = 0.1400,
						lightColorR = 1.1000,
						lightColorG = 1.0200,
						lightColorB = 0.9400,
						lightLuminance = 1.1800,
					},
				},
				ai = {
					dynamism = 1.1200,
					interaction = 1.0400,
					autoIntentRate = 1.0800,
					needsDrain = 1.0800,
					needsRecovery = 0.9800,
					actionWeights = {
						rest = 0.8000,
						meal = 4.0000,
						distraction = 0.9600,
						move_place = 1.0800,
						observe_nature = 1.0200,
						talk = 2.0900,
					},
				},
			},
			{
				key = "apres_midi",
				label = "Apres-midi",
				share = 0.3000,
				colors = {
					background = {
						r = 0.7400,
						g = 0.7200,
						b = 0.7000,
						a = 1.0000,
					},
					models = {
						colorTemperature = 0.0600,
						lightColorR = 1.0300,
						lightColorG = 1.0000,
						lightColorB = 0.9800,
						lightLuminance = 1.0400,
					},
				},
				ai = {
					dynamism = 1.0800,
					interaction = 1.1200,
					autoIntentRate = 1.1000,
					needsDrain = 1.0200,
					needsRecovery = 1.0000,
					actionWeights = {
						rest = 0.8600,
						meal = 1.0000,
						distraction = 1.1000,
						move_place = 1.2200,
						observe_nature = 1.0500,
						talk = 2.3500,
					},
				},
			},
			{
				key = "crepuscule",
				label = "Crepuscule",
				share = 0.0921,
				colors = {
					background = {
						r = 0.6900,
						g = 0.5800,
						b = 0.4800,
						a = 1.0000,
					},
					models = {
						colorTemperature = 0.2000,
						lightColorR = 1.1000,
						lightColorG = 0.9400,
						lightColorB = 0.8400,
						lightLuminance = 0.8600,
					},
				},
				ai = {
					dynamism = 0.9600,
					interaction = 1.1800,
					autoIntentRate = 1.0600,
					needsDrain = 0.9600,
					needsRecovery = 1.0400,
					actionWeights = {
						rest = 0.9400,
						meal = 0.9800,
						distraction = 2.8400,
						move_place = 1.0400,
						observe_nature = 1.0800,
						talk = 1.3400,
					},
				},
			},
			{
				key = "nuit",
				label = "Nuit",
				share = 0.1842,
				colors = {
					background = {
						r = 0.4400,
						g = 0.5000,
						b = 0.6400,
						a = 1.0000,
					},
					models = {
						colorTemperature = -0.3400,
						lightColorR = 0.8400,
						lightColorG = 0.9000,
						lightColorB = 1.0600,
						lightLuminance = 0.5200,
					},
				},
				ai = {
					dynamism = 0.7400,
					interaction = 0.7200,
					autoIntentRate = 0.7600,
					needsDrain = 0.8400,
					needsRecovery = 1.1600,
					actionWeights = {
						rest = 4.0000,
						meal = 0.8600,
						distraction = 2.1900,
						move_place = 0.7200,
						observe_nature = 0.8600,
						talk = 0.7000,
					},
				},
			},
		},
	},
}
