local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.DayCycle = QM.DayCycle or {}
local DayCycle = QM.DayCycle

local function Clamp(v, minV, maxV)
	if v < minV then
		return minV
	end
	if v > maxV then
		return maxV
	end
	return v
end

local function Lerp(a, b, t)
	return a + ((b - a) * t)
end

local function CopyTable(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, row in pairs(v) do
		out[k] = CopyTable(row)
	end
	return out
end

local PHASE_INDEX_BY_KEY = {
	aube = 1,
	matin = 2,
	midi = 3,
	apres_midi = 4,
	crepuscule = 5,
	nuit = 6,
}

local FICTIONAL_START_HOUR = 5

local function BuildEffectivePhase(currentRow, nextRow, blend)
	local rowA = type(currentRow) == "table" and currentRow or {}
	local rowB = type(nextRow) == "table" and nextRow or rowA
	local t = Clamp(tonumber(blend) or 0, 0, 1)

	local colorsA = type(rowA.colors) == "table" and rowA.colors or {}
	local colorsB = type(rowB.colors) == "table" and rowB.colors or {}
	local bgA = type(colorsA.background) == "table" and colorsA.background or {}
	local bgB = type(colorsB.background) == "table" and colorsB.background or {}
	local modelsA = type(colorsA.models) == "table" and colorsA.models or {}
	local modelsB = type(colorsB.models) == "table" and colorsB.models or {}

	local aiA = type(rowA.ai) == "table" and rowA.ai or {}
	local aiB = type(rowB.ai) == "table" and rowB.ai or {}
	local wA = type(aiA.actionWeights) == "table" and aiA.actionWeights or {}
	local wB = type(aiB.actionWeights) == "table" and aiB.actionWeights or {}

	return {
		colors = {
			background = {
				r = Lerp(tonumber(bgA.r) or 1, tonumber(bgB.r) or 1, t),
				g = Lerp(tonumber(bgA.g) or 1, tonumber(bgB.g) or 1, t),
				b = Lerp(tonumber(bgA.b) or 1, tonumber(bgB.b) or 1, t),
				a = Lerp(tonumber(bgA.a) or 1, tonumber(bgB.a) or 1, t),
			},
			models = {
				colorTemperature = Lerp(
					tonumber(modelsA.colorTemperature) or 0,
					tonumber(modelsB.colorTemperature) or 0,
					t
				),
				lightColorR = Lerp(tonumber(modelsA.lightColorR) or 1, tonumber(modelsB.lightColorR) or 1, t),
				lightColorG = Lerp(tonumber(modelsA.lightColorG) or 1, tonumber(modelsB.lightColorG) or 1, t),
				lightColorB = Lerp(tonumber(modelsA.lightColorB) or 1, tonumber(modelsB.lightColorB) or 1, t),
				lightLuminance = Lerp(
					tonumber(modelsA.lightLuminance) or 1,
					tonumber(modelsB.lightLuminance) or 1,
					t
				),
			},
		},
		ai = {
			dynamism = Lerp(tonumber(aiA.dynamism) or 1, tonumber(aiB.dynamism) or 1, t),
			interaction = Lerp(tonumber(aiA.interaction) or 1, tonumber(aiB.interaction) or 1, t),
			autoIntentRate = Lerp(tonumber(aiA.autoIntentRate) or 1, tonumber(aiB.autoIntentRate) or 1, t),
			needsDrain = Lerp(tonumber(aiA.needsDrain) or 1, tonumber(aiB.needsDrain) or 1, t),
			needsRecovery = Lerp(tonumber(aiA.needsRecovery) or 1, tonumber(aiB.needsRecovery) or 1, t),
			actionWeights = {
				rest = Lerp(tonumber(wA.rest) or 1, tonumber(wB.rest) or 1, t),
				meal = Lerp(tonumber(wA.meal) or 1, tonumber(wB.meal) or 1, t),
				distraction = Lerp(tonumber(wA.distraction) or 1, tonumber(wB.distraction) or 1, t),
				move_place = Lerp(tonumber(wA.move_place) or 1, tonumber(wB.move_place) or 1, t),
				observe_nature = Lerp(tonumber(wA.observe_nature) or 1, tonumber(wB.observe_nature) or 1, t),
				talk = Lerp(tonumber(wA.talk) or 1, tonumber(wB.talk) or 1, t),
			},
		},
	}
end

local function BuildTimeText(dayProgress01)
	local progress = Clamp(tonumber(dayProgress01) or 0, 0, 1)
	local hourFloat = (FICTIONAL_START_HOUR + (progress * 24)) % 24
	local hour = math.floor(hourFloat)
	local minute = math.floor((hourFloat - hour) * 60 + 0.0001)
	if minute >= 60 then
		minute = minute - 60
		hour = (hour + 1) % 24
	end
	return string.format("%02d:%02d", hour, minute)
end

function DayCycle.CreateRuntime(opts)
	opts = type(opts) == "table" and opts or {}
	local getMapId = type(opts.getMapId) == "function" and opts.getMapId or function()
		return "default"
	end
	local timeProfiles = opts.timeProfiles or QM.TimeProfiles
	if not (type(timeProfiles) == "table" and type(timeProfiles.EnsureMapStore) == "function") then
		return nil
	end

	local blendTailRatio = Clamp(tonumber(opts.blendTailRatio) or 0.20, 0.01, 0.49)
	local clockSec = 0
	local timeScale = Clamp(tonumber(opts.timeScale) or 1.0, 0.01, 20.0)
	local paused = opts.paused == true
	local mapId = tostring(opts.mapId or getMapId() or "default")
	local stateCache = nil

	local function ResolveState()
		local store = timeProfiles.EnsureMapStore(mapId)
		local settings = type(store.settings) == "table" and store.settings or {}
		local timeline = type(store.timeline) == "table" and store.timeline or {}
		if #timeline <= 0 then
			return nil
		end

		local dayDurationSec = Clamp(tonumber(settings.dayDurationSec) or tonumber(opts.dayDurationSec) or 7200, 60, 86400)
		local currentClock = clockSec
		if currentClock < 0 then
			currentClock = 0
		end
		if currentClock >= dayDurationSec then
			currentClock = currentClock % dayDurationSec
		end

		local currentIndex = #timeline
		local currentStart = 0
		local currentDuration = dayDurationSec
		local acc = 0
		for i = 1, #timeline do
			local row = timeline[i]
			local segDuration = math.max(0.001, dayDurationSec * Clamp(tonumber(row and row.share) or 0, 0.0001, 1.0))
			local segEnd = acc + segDuration
			if currentClock < segEnd or i == #timeline then
				currentIndex = i
				currentStart = acc
				currentDuration = segDuration
				break
			end
			acc = segEnd
		end

		local row = timeline[currentIndex]
		local nextIndex = (currentIndex % #timeline) + 1
		local rowNext = timeline[nextIndex]
		local inPhaseSec = currentClock - currentStart
		local phaseProgress = Clamp(inPhaseSec / math.max(0.001, currentDuration), 0, 1)
		local blendStart = 1.0 - blendTailRatio
		local blend = 0
		if phaseProgress >= blendStart then
			blend = Clamp((phaseProgress - blendStart) / math.max(0.001, blendTailRatio), 0, 1)
		end

		local dayProgress01 = Clamp(currentClock / math.max(0.001, dayDurationSec), 0, 1)
		local clockProgressMidnight01 = (dayProgress01 + (FICTIONAL_START_HOUR / 24)) % 1
		local clockMinuteOfDay = math.floor((clockProgressMidnight01 * 1440) + 0.5) % 1440

		stateCache = {
			mapId = mapId,
			dayDurationSec = dayDurationSec,
			clockSec = currentClock,
			dayProgress01 = dayProgress01,
			clockProgressMidnight01 = clockProgressMidnight01,
			clockMinuteOfDay = clockMinuteOfDay,
			phaseKey = tostring(row and row.key or "aube"),
			phaseLabel = tostring(row and row.label or "Aube"),
			phaseIndex = currentIndex,
			nextPhaseKey = tostring(rowNext and rowNext.key or "aube"),
			nextPhaseLabel = tostring(rowNext and rowNext.label or "Aube"),
			phaseProgress01 = phaseProgress,
			phaseBlend01 = blend,
			timeText = BuildTimeText(currentClock / math.max(0.001, dayDurationSec)),
			effective = BuildEffectivePhase(row, rowNext, blend),
		}
		return stateCache
	end

	local E = {}

	function E:GetMapId()
		return mapId
	end

	function E:SetMapId(nextMapId)
		local nextId = tostring(nextMapId or "default")
		if nextId == mapId then
			return E:GetState()
		end
		mapId = nextId
		clockSec = 0
		stateCache = nil
		return E:GetState()
	end

	function E:SetPaused(flag)
		paused = flag == true
		return paused
	end

	function E:IsPaused()
		return paused == true
	end

	function E:SetTimeScale(nextScale)
		timeScale = Clamp(tonumber(nextScale) or timeScale, 0.01, 20.0)
		return timeScale
	end

	function E:GetTimeScale()
		return timeScale
	end

	function E:SetClockSeconds(nextClockSec)
		local state = E:GetState()
		if not state then
			return false
		end
		local duration = math.max(60, tonumber(state.dayDurationSec) or 7200)
		clockSec = tonumber(nextClockSec) or clockSec
		if clockSec < 0 then
			clockSec = 0
		end
		if clockSec >= duration then
			clockSec = clockSec % duration
		end
		stateCache = nil
		E:GetState()
		return true
	end

	function E:SetPhase(phaseKey, progress)
		local wanted = tostring(phaseKey or "")
		if wanted == "" then
			wanted = "aube"
		end
		local store = timeProfiles.EnsureMapStore(mapId)
		local settings = type(store.settings) == "table" and store.settings or {}
		local timeline = type(store.timeline) == "table" and store.timeline or {}
		if #timeline <= 0 then
			return false
		end
		local dayDurationSec = Clamp(tonumber(settings.dayDurationSec) or tonumber(opts.dayDurationSec) or 7200, 60, 86400)
		local targetIndex = PHASE_INDEX_BY_KEY[wanted]
		if not targetIndex then
			for i = 1, #timeline do
				if tostring(timeline[i] and timeline[i].key or "") == wanted then
					targetIndex = i
					break
				end
			end
		end
		if not targetIndex then
			targetIndex = 1
		end

		local acc = 0
		for i = 1, #timeline do
			local row = timeline[i]
			local segDuration = dayDurationSec * Clamp(tonumber(row and row.share) or 0, 0.0001, 1.0)
			if i < targetIndex then
				acc = acc + segDuration
			elseif i == targetIndex then
				local ratio = Clamp(tonumber(progress) or 0, 0, 1)
				clockSec = acc + (segDuration * ratio)
				stateCache = nil
				E:GetState()
				return true
			end
		end
		return false
	end

	function E:GetClockSeconds()
		return tonumber(clockSec) or 0
	end

	function E:Update(dt)
		if not paused then
			clockSec = (tonumber(clockSec) or 0) + (math.max(0, tonumber(dt) or 0) * timeScale)
		end
		stateCache = nil
		return E:GetState()
	end

	function E:GetState()
		if stateCache then
			return stateCache
		end
		return ResolveState()
	end

	function E:GetStateCopy()
		return CopyTable(E:GetState())
	end

	E:GetState()
	return E
end

return DayCycle
