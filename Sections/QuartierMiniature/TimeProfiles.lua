local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.TimeProfiles = QM.TimeProfiles or { version = 1, maps = {} }
local TimeProfiles = QM.TimeProfiles

local function Clamp(v, minV, maxV)
	if v < minV then
		return minV
	end
	if v > maxV then
		return maxV
	end
	return v
end

local function F(v)
	return string.format("%.4f", tonumber(v) or 0)
end

local function DeepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, row in pairs(v) do
		out[k] = DeepCopy(row)
	end
	return out
end

local PHASE_ORDER = {
	"aube",
	"matin",
	"midi",
	"apres_midi",
	"crepuscule",
	"nuit",
}

local PHASE_LABELS = {
	aube = "Aube",
	matin = "Matin",
	midi = "Midi",
	apres_midi = "Apres-midi",
	crepuscule = "Crepuscule",
	nuit = "Nuit",
}

local DEFAULT_SETTINGS = {
	dayDurationSec = 7200,
	timelinePreset = "narrative_balanced",
}

local DEFAULT_TIMELINE = {
	{
		key = "aube",
		label = "Aube",
		share = 0.08,
		colors = {
			background = { r = 0.58, g = 0.66, b = 0.80, a = 1.0 },
			models = {
				colorTemperature = -0.20,
				lightColorR = 0.92,
				lightColorG = 0.98,
				lightColorB = 1.08,
				lightLuminance = 0.66,
			},
		},
		ai = {
			dynamism = 0.82,
			interaction = 0.78,
			autoIntentRate = 0.85,
			needsDrain = 0.90,
			needsRecovery = 1.08,
			actionWeights = {
				rest = 1.18,
				meal = 0.92,
				distraction = 0.90,
				move_place = 0.84,
				observe_nature = 1.05,
				talk = 0.90,
			},
		},
	},
	{
		key = "matin",
		label = "Matin",
		share = 0.22,
		colors = {
			background = { r = 0.70, g = 0.72, b = 0.74, a = 1.0 },
			models = {
				colorTemperature = -0.02,
				lightColorR = 1.00,
				lightColorG = 1.00,
				lightColorB = 1.00,
				lightLuminance = 1.00,
			},
		},
		ai = {
			dynamism = 1.00,
			interaction = 1.00,
			autoIntentRate = 1.00,
			needsDrain = 1.00,
			needsRecovery = 1.00,
			actionWeights = {
				rest = 0.92,
				meal = 1.08,
				distraction = 1.00,
				move_place = 1.06,
				observe_nature = 1.00,
				talk = 1.00,
			},
		},
	},
	{
		key = "midi",
		label = "Midi",
		share = 0.16,
		colors = {
			background = { r = 0.78, g = 0.75, b = 0.68, a = 1.0 },
			models = {
				colorTemperature = 0.14,
				lightColorR = 1.10,
				lightColorG = 1.02,
				lightColorB = 0.94,
				lightLuminance = 1.18,
			},
		},
		ai = {
			dynamism = 1.12,
			interaction = 1.04,
			autoIntentRate = 1.08,
			needsDrain = 1.08,
			needsRecovery = 0.98,
			actionWeights = {
				rest = 0.80,
				meal = 1.34,
				distraction = 0.96,
				move_place = 1.08,
				observe_nature = 1.02,
				talk = 1.00,
			},
		},
	},
	{
		key = "apres_midi",
		label = "Apres-midi",
		share = 0.24,
		colors = {
			background = { r = 0.74, g = 0.72, b = 0.70, a = 1.0 },
			models = {
				colorTemperature = 0.06,
				lightColorR = 1.03,
				lightColorG = 1.00,
				lightColorB = 0.98,
				lightLuminance = 1.04,
			},
		},
		ai = {
			dynamism = 1.08,
			interaction = 1.12,
			autoIntentRate = 1.10,
			needsDrain = 1.02,
			needsRecovery = 1.00,
			actionWeights = {
				rest = 0.86,
				meal = 1.00,
				distraction = 1.10,
				move_place = 1.22,
				observe_nature = 1.05,
				talk = 1.26,
			},
		},
	},
	{
		key = "crepuscule",
		label = "Crepuscule",
		share = 0.10,
		colors = {
			background = { r = 0.69, g = 0.58, b = 0.48, a = 1.0 },
			models = {
				colorTemperature = 0.20,
				lightColorR = 1.10,
				lightColorG = 0.94,
				lightColorB = 0.84,
				lightLuminance = 0.86,
			},
		},
		ai = {
			dynamism = 0.96,
			interaction = 1.18,
			autoIntentRate = 1.06,
			needsDrain = 0.96,
			needsRecovery = 1.04,
			actionWeights = {
				rest = 0.94,
				meal = 0.98,
				distraction = 1.30,
				move_place = 1.04,
				observe_nature = 1.08,
				talk = 1.34,
			},
		},
	},
	{
		key = "nuit",
		label = "Nuit",
		share = 0.20,
		colors = {
			background = { r = 0.44, g = 0.50, b = 0.64, a = 1.0 },
			models = {
				colorTemperature = -0.34,
				lightColorR = 0.84,
				lightColorG = 0.90,
				lightColorB = 1.06,
				lightLuminance = 0.52,
			},
		},
		ai = {
			dynamism = 0.74,
			interaction = 0.72,
			autoIntentRate = 0.76,
			needsDrain = 0.84,
			needsRecovery = 1.16,
			actionWeights = {
				rest = 1.44,
				meal = 0.86,
				distraction = 0.74,
				move_place = 0.72,
				observe_nature = 0.86,
				talk = 0.70,
			},
		},
	},
}

local DEFAULT_PHASE_BY_KEY = {}
for i = 1, #DEFAULT_TIMELINE do
	local row = DEFAULT_TIMELINE[i]
	DEFAULT_PHASE_BY_KEY[tostring(row.key or "")] = row
end

local function BuildDefaultMapStore()
	return {
		settings = DeepCopy(DEFAULT_SETTINGS),
		timeline = DeepCopy(DEFAULT_TIMELINE),
	}
end

local function NormalizeActionWeights(rawWeights, defaults)
	local src = type(rawWeights) == "table" and rawWeights or {}
	local def = type(defaults) == "table" and defaults or {}
	local out = {
		rest = Clamp(tonumber(src.rest) or tonumber(def.rest) or 1.0, 0.10, 4.0),
		meal = Clamp(tonumber(src.meal) or tonumber(def.meal) or 1.0, 0.10, 4.0),
		distraction = Clamp(tonumber(src.distraction) or tonumber(def.distraction) or 1.0, 0.10, 4.0),
		move_place = Clamp(tonumber(src.move_place) or tonumber(def.move_place) or 1.0, 0.10, 4.0),
		observe_nature = Clamp(tonumber(src.observe_nature) or tonumber(def.observe_nature) or 1.0, 0.10, 4.0),
		talk = Clamp(tonumber(src.talk) or tonumber(def.talk) or 1.0, 0.10, 4.0),
	}
	return out
end

local function NormalizeColors(rawColors, defaults)
	local src = type(rawColors) == "table" and rawColors or {}
	local def = type(defaults) == "table" and defaults or {}
	local bgSrc = type(src.background) == "table" and src.background or {}
	local bgDef = type(def.background) == "table" and def.background or {}
	local modelSrc = type(src.models) == "table" and src.models or {}
	local modelDef = type(def.models) == "table" and def.models or {}
	return {
		background = {
			r = Clamp(tonumber(bgSrc.r) or tonumber(bgDef.r) or 1.0, 0.0, 2.0),
			g = Clamp(tonumber(bgSrc.g) or tonumber(bgDef.g) or 1.0, 0.0, 2.0),
			b = Clamp(tonumber(bgSrc.b) or tonumber(bgDef.b) or 1.0, 0.0, 2.0),
			a = Clamp(tonumber(bgSrc.a) or tonumber(bgDef.a) or 1.0, 0.0, 1.0),
		},
		models = {
			colorTemperature = Clamp(tonumber(modelSrc.colorTemperature) or tonumber(modelDef.colorTemperature) or 0, -1.0, 1.0),
			lightColorR = Clamp(tonumber(modelSrc.lightColorR) or tonumber(modelDef.lightColorR) or 1.0, 0.0, 2.0),
			lightColorG = Clamp(tonumber(modelSrc.lightColorG) or tonumber(modelDef.lightColorG) or 1.0, 0.0, 2.0),
			lightColorB = Clamp(tonumber(modelSrc.lightColorB) or tonumber(modelDef.lightColorB) or 1.0, 0.0, 2.0),
			lightLuminance = Clamp(tonumber(modelSrc.lightLuminance) or tonumber(modelDef.lightLuminance) or 1.0, 0.0, 3.0),
		},
	}
end

local function NormalizeAi(rawAi, defaults)
	local src = type(rawAi) == "table" and rawAi or {}
	local def = type(defaults) == "table" and defaults or {}
	return {
		dynamism = Clamp(tonumber(src.dynamism) or tonumber(def.dynamism) or 1.0, 0.20, 3.0),
		interaction = Clamp(tonumber(src.interaction) or tonumber(def.interaction) or 1.0, 0.20, 3.0),
		autoIntentRate = Clamp(tonumber(src.autoIntentRate) or tonumber(def.autoIntentRate) or 1.0, 0.20, 4.0),
		needsDrain = Clamp(tonumber(src.needsDrain) or tonumber(def.needsDrain) or 1.0, 0.20, 4.0),
		needsRecovery = Clamp(tonumber(src.needsRecovery) or tonumber(def.needsRecovery) or 1.0, 0.20, 4.0),
		actionWeights = NormalizeActionWeights(src.actionWeights, def.actionWeights),
	}
end

local function FindRawPhase(rawTimeline, phaseKey, phaseIndex)
	local list = type(rawTimeline) == "table" and rawTimeline or {}
	for i = 1, #list do
		local row = list[i]
		if tostring(row and row.key or "") == phaseKey then
			return row
		end
	end
	return list[phaseIndex]
end

function TimeProfiles.GetPhaseOrder()
	return DeepCopy(PHASE_ORDER)
end

function TimeProfiles.GetPhaseLabel(phaseKey)
	local key = tostring(phaseKey or "")
	return tostring(PHASE_LABELS[key] or key)
end

function TimeProfiles.GetDefaultSettings()
	return DeepCopy(DEFAULT_SETTINGS)
end

function TimeProfiles.GetDefaultTimeline()
	return DeepCopy(DEFAULT_TIMELINE)
end

function TimeProfiles.NormalizeSettings(rawSettings)
	local src = type(rawSettings) == "table" and rawSettings or {}
	local cfg = type(QM.Config) == "table" and QM.Config or {}
	local cfgTime = type(cfg.time) == "table" and cfg.time or {}
	return {
		dayDurationSec = Clamp(
			tonumber(src.dayDurationSec) or tonumber(cfgTime.dayDurationSec) or tonumber(DEFAULT_SETTINGS.dayDurationSec) or 7200,
			60,
			86400
		),
		timelinePreset = tostring(src.timelinePreset or cfgTime.timelinePreset or DEFAULT_SETTINGS.timelinePreset or "narrative_balanced"),
	}
end

function TimeProfiles.NormalizeTimeline(rawTimeline)
	local out = {}
	for i = 1, #PHASE_ORDER do
		local phaseKey = PHASE_ORDER[i]
		local fallback = DEFAULT_PHASE_BY_KEY[phaseKey]
		local raw = FindRawPhase(rawTimeline, phaseKey, i)
		local row = {
			key = phaseKey,
			label = tostring(raw and raw.label or fallback.label or PHASE_LABELS[phaseKey] or phaseKey),
			share = Clamp(tonumber(raw and raw.share) or tonumber(fallback and fallback.share) or 0.01, 0.001, 1.0),
			colors = NormalizeColors(raw and raw.colors, fallback and fallback.colors),
			ai = NormalizeAi(raw and raw.ai, fallback and fallback.ai),
		}
		out[#out + 1] = row
	end

	local totalShare = 0
	for i = 1, #out do
		totalShare = totalShare + (tonumber(out[i].share) or 0)
	end
	if totalShare <= 0 then
		for i = 1, #out do
			out[i].share = 1 / #out
		end
	else
		for i = 1, #out do
			out[i].share = (tonumber(out[i].share) or 0) / totalShare
		end
	end
	return out
end

function TimeProfiles.EnsureMapStore(mapId)
	TimeProfiles.maps = type(TimeProfiles.maps) == "table" and TimeProfiles.maps or {}
	TimeProfiles.version = tonumber(TimeProfiles.version) or 1
	local key = tostring(mapId or "default")
	local store = type(TimeProfiles.maps[key]) == "table" and TimeProfiles.maps[key] or BuildDefaultMapStore()
	store.settings = TimeProfiles.NormalizeSettings(store.settings)
	store.timeline = TimeProfiles.NormalizeTimeline(store.timeline)
	TimeProfiles.maps[key] = store
	return store
end

function TimeProfiles.GetMapStoreCopy(mapId)
	return DeepCopy(TimeProfiles.EnsureMapStore(mapId))
end

function TimeProfiles.ResetMapToDefaults(mapId)
	TimeProfiles.maps = type(TimeProfiles.maps) == "table" and TimeProfiles.maps or {}
	local key = tostring(mapId or "default")
	TimeProfiles.maps[key] = BuildDefaultMapStore()
	return TimeProfiles.EnsureMapStore(key)
end

function TimeProfiles.BuildExportText(mapId)
	TimeProfiles.maps = type(TimeProfiles.maps) == "table" and TimeProfiles.maps or {}
	if mapId ~= nil then
		TimeProfiles.EnsureMapStore(mapId)
	end
	local entries = {}
	for key, value in pairs(TimeProfiles.maps) do
		entries[#entries + 1] = {
			keyText = tostring(key),
			store = TimeProfiles.EnsureMapStore(key),
		}
	end
	table.sort(entries, function(a, b)
		return a.keyText < b.keyText
	end)

	local sb = {}
	sb[#sb + 1] = "local ADDON, ns = ..."
	sb[#sb + 1] = ""
	sb[#sb + 1] = "ns.QuartierMiniature = ns.QuartierMiniature or {}"
	sb[#sb + 1] = "local QM = ns.QuartierMiniature"
	sb[#sb + 1] = ""
	sb[#sb + 1] = "QM.TimeProfiles = QM.TimeProfiles or {}"
	sb[#sb + 1] = ("QM.TimeProfiles.version = %s"):format(tostring(tonumber(TimeProfiles.version) or 1))
	sb[#sb + 1] = "QM.TimeProfiles.maps = {"

	for e = 1, #entries do
		local mapEntry = entries[e]
		local key = mapEntry.keyText
		local store = mapEntry.store
		sb[#sb + 1] = ("\t[%q] = {"):format(key)
		sb[#sb + 1] = "\t\tsettings = {"
		sb[#sb + 1] = ("\t\t\tdayDurationSec = %d,"):format(math.floor(tonumber(store.settings.dayDurationSec) or 7200))
		sb[#sb + 1] = ("\t\t\ttimelinePreset = %q,"):format(tostring(store.settings.timelinePreset or "narrative_balanced"))
		sb[#sb + 1] = "\t\t},"
		sb[#sb + 1] = "\t\ttimeline = {"
		local timeline = type(store.timeline) == "table" and store.timeline or {}
		for i = 1, #timeline do
			local row = timeline[i]
			local colors = row.colors or {}
			local bg = colors.background or {}
			local models = colors.models or {}
			local ai = row.ai or {}
			local weights = ai.actionWeights or {}
			sb[#sb + 1] = "\t\t\t{"
			sb[#sb + 1] = ("\t\t\t\tkey = %q,"):format(tostring(row.key or ""))
			sb[#sb + 1] = ("\t\t\t\tlabel = %q,"):format(tostring(row.label or ""))
			sb[#sb + 1] = ("\t\t\t\tshare = %s,"):format(F(row.share))
			sb[#sb + 1] = "\t\t\t\tcolors = {"
			sb[#sb + 1] = "\t\t\t\t\tbackground = {"
			sb[#sb + 1] = ("\t\t\t\t\t\tr = %s,"):format(F(bg.r))
			sb[#sb + 1] = ("\t\t\t\t\t\tg = %s,"):format(F(bg.g))
			sb[#sb + 1] = ("\t\t\t\t\t\tb = %s,"):format(F(bg.b))
			sb[#sb + 1] = ("\t\t\t\t\t\ta = %s,"):format(F(bg.a))
			sb[#sb + 1] = "\t\t\t\t\t},"
			sb[#sb + 1] = "\t\t\t\t\tmodels = {"
			sb[#sb + 1] = ("\t\t\t\t\t\tcolorTemperature = %s,"):format(F(models.colorTemperature))
			sb[#sb + 1] = ("\t\t\t\t\t\tlightColorR = %s,"):format(F(models.lightColorR))
			sb[#sb + 1] = ("\t\t\t\t\t\tlightColorG = %s,"):format(F(models.lightColorG))
			sb[#sb + 1] = ("\t\t\t\t\t\tlightColorB = %s,"):format(F(models.lightColorB))
			sb[#sb + 1] = ("\t\t\t\t\t\tlightLuminance = %s,"):format(F(models.lightLuminance))
			sb[#sb + 1] = "\t\t\t\t\t},"
			sb[#sb + 1] = "\t\t\t\t},"
			sb[#sb + 1] = "\t\t\t\tai = {"
			sb[#sb + 1] = ("\t\t\t\t\tdynamism = %s,"):format(F(ai.dynamism))
			sb[#sb + 1] = ("\t\t\t\t\tinteraction = %s,"):format(F(ai.interaction))
			sb[#sb + 1] = ("\t\t\t\t\tautoIntentRate = %s,"):format(F(ai.autoIntentRate))
			sb[#sb + 1] = ("\t\t\t\t\tneedsDrain = %s,"):format(F(ai.needsDrain))
			sb[#sb + 1] = ("\t\t\t\t\tneedsRecovery = %s,"):format(F(ai.needsRecovery))
			sb[#sb + 1] = "\t\t\t\t\tactionWeights = {"
			sb[#sb + 1] = ("\t\t\t\t\t\trest = %s,"):format(F(weights.rest))
			sb[#sb + 1] = ("\t\t\t\t\t\tmeal = %s,"):format(F(weights.meal))
			sb[#sb + 1] = ("\t\t\t\t\t\tdistraction = %s,"):format(F(weights.distraction))
			sb[#sb + 1] = ("\t\t\t\t\t\tmove_place = %s,"):format(F(weights.move_place))
			sb[#sb + 1] = ("\t\t\t\t\t\tobserve_nature = %s,"):format(F(weights.observe_nature))
			sb[#sb + 1] = ("\t\t\t\t\t\ttalk = %s,"):format(F(weights.talk))
			sb[#sb + 1] = "\t\t\t\t\t},"
			sb[#sb + 1] = "\t\t\t\t},"
			sb[#sb + 1] = "\t\t\t},"
		end
		sb[#sb + 1] = "\t\t},"
		sb[#sb + 1] = "\t},"
	end
	sb[#sb + 1] = "}"
	return table.concat(sb, "\n")
end

return TimeProfiles
