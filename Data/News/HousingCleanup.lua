-- ==========================================================
-- Housing cleanup contribution module
-- Trigger: SPELL_UPDATE_COOLDOWN on tracked spells
-- ==========================================================

local ADDON, ns = ...

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { housingcleanup = 1 }

local MODULE_KEY = "housingcleanup"
local PIGISTE_KEY = "housingcleanup"

local CFG = {
	enabled = true,
	traceEventArgs = true,
	triggerEvent = "HOUSING_CLEANUP_UPDATE",
	pigisteEvents = {
		SPELL_UPDATE_COOLDOWN = true,
	},
	triggerEvents = {
		"HOUSING_CLEANUP_UPDATE",
	},
	replaceKeyPrefix = "housingcleanup:",
	icon = 655994, -- Placeholder en attendant l'icone definitive
	minTriggerCooldownSeconds = 2,
	spells = {
		[1250066] = 1,
		[1254681] = 20,
		[1252225] = 5,
		[1263790] = 5,
		[1279762] = 1,
		[1278046] = 1,
	},
	phrases = {
		"%s participe à la bonne tenue de l’île du Logis et du Quartier et gagne +%d points de contribution pour un total de %d points.",
		"%s aide au nettoyage de l’île du Logis et du Quartier et obtient +%d points de contribution portant son total à %d points.",
		"%s renforce l’ordre de l’île du Logis et du Quartier et reçoit +%d points de contribution pour un total de %d points.",
		"%s contribue à l’équilibre du Quartier et engrange +%d points de contribution pour atteindre %d points.",
		"%s veille à la prospérité de l’île du Logis et gagne +%d points de contribution pour un total désormais fixé à %d points.",
		"%s soutient les efforts communs du Quartier et ajoute +%d points de contribution portant son total à %d points.",
		"%s entretient l’harmonie de l’île et reçoit +%d points de contribution ce qui élève son total à %d points.",
		"%s participe à l’embellissement du Logis et cumule +%d points de contribution pour un total de %d points.",
		"%s prend part aux travaux du Quartier et gagne +%d points de contribution portant son total à %d points.",
		"%s œuvre pour la stabilité du Logis et obtient +%d points de contribution pour atteindre %d points.",
	},
}

do
	local Pigiste = Data.Pigiste
	local pigapi = Data.PigisteAPI
	if not Pigiste or not pigapi then
		return
	end

	local pendingTick = false

	local function DebugPrintRawEvent(eventName, ...)
		if not CFG.traceEventArgs then
			return
		end
		local t = (GetTimePreciseSec and GetTimePreciseSec()) or (GetTime and GetTime()) or 0
	end

	local function TickJournalistSoon()
		if pendingTick then
			return
		end
		pendingTick = true

		local function doTick()
			pendingTick = false
			local Journalist = (Data and Data.Journalist) or (ns and ns.Data and ns.Data.Journalist) or nil
			if Journalist and type(Journalist.TickNow) == "function" then
				Journalist.TickNow(CFG.triggerEvent)
			end
		end

		if C_Timer and C_Timer.After then
			C_Timer.After(0, doTick)
		else
			doTick()
		end
	end

	local function GetSpellCooldownSafe(spellID)
		if C_Spell and C_Spell.GetSpellCooldown then
			local info = C_Spell.GetSpellCooldown(spellID)
			if type(info) == "table" then
				return tonumber(info.startTime) or 0, tonumber(info.duration) or 0, tonumber(info.isEnabled) or 1
			end
		end
		if GetSpellCooldown then
			local start, duration, enabled = GetSpellCooldown(spellID)
			return tonumber(start) or 0, tonumber(duration) or 0, tonumber(enabled) or 1
		end
		return 0, 0, 0
	end

	local function SafeToNumber(v, default)
		local n = tonumber(v)
		if type(n) ~= "number" then
			return default or 0
		end
		return n
	end

	local function SafeLt(a, b)
		local ok, res = pcall(function()
			return a < b
		end)
		return ok and (res == true)
	end

	local function SafeLe(a, b)
		local ok, res = pcall(function()
			return a <= b
		end)
		return ok and (res == true)
	end

	local function SnapshotSpell(spellID)
		local start, duration, enabled = GetSpellCooldownSafe(spellID)
		start = SafeToNumber(start, 0)
		duration = SafeToNumber(duration, 0)
		enabled = SafeToNumber(enabled, 1)
		if SafeLt(start, 0) then
			start = 0
		end
		if SafeLt(duration, 0) then
			duration = 0
		end
		return {
			start = start,
			duration = duration,
			enabled = enabled,
		}
	end

	local function IsNewCooldown(previous, current)
		if not previous then
			return false
		end
		local currentDuration = SafeToNumber(current.duration, 0)
		local minDuration = SafeToNumber(CFG.minTriggerCooldownSeconds, 2)
		if SafeLt(currentDuration, minDuration) then
			return false
		end
		local currentStart = SafeToNumber(current.start, 0)
		if SafeLe(currentStart, 0) then
			return false
		end
		if SafeToNumber(current.enabled, 1) == 0 then
			return false
		end
		local prevStart = SafeToNumber(previous.start, 0)
		local prevDuration = SafeToNumber(previous.duration, 0)
		local nowStart = currentStart
		local nowDuration = currentDuration
		return (nowStart ~= prevStart) or (nowDuration ~= prevDuration)
	end

	local function InitBaselineIfNeeded(last)
		last.spellState = last.spellState or {}
		last.lastArgAtBySpell = last.lastArgAtBySpell or {}
		if last._cooldownBaselineReady then
			return
		end
		for spellID in pairs(CFG.spells) do
			last.spellState[spellID] = SnapshotSpell(spellID)
		end
		last._cooldownBaselineReady = true
	end

	local function AddContribution(p, l, now, spellID, points)
		local gain = tonumber(points) or 0
		if gain <= 0 then
			return false
		end
		l.totalPoints = (tonumber(l.totalPoints) or 0) + gain
		l.lastDeltaPoints = gain
		l.lastTriggerAt = now
		l.lastHitCount = 1
		l.lastSpellID = spellID
		l.seq = (tonumber(l.seq) or 0) + 1

		pigapi.IncCounter(p, "housingCleanupContribution", gain)
		pigapi.PushActivity(p, PIGISTE_KEY, {
			ts = now,
			delta = gain,
			total = l.totalPoints,
			spellID = spellID,
		}, 200)
		p.updatedAt = now
		TickJournalistSoon()
		return true
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,
		OnEvent = function(_, eventName, ...)
			if not CFG.enabled then
				return
			end
			if eventName ~= "SPELL_UPDATE_COOLDOWN" then
				return
			end
			DebugPrintRawEvent(eventName, ...)

			local p = pigapi.EnsurePlayer(pigapi.GetMyUID())
			if not p then
				return
			end

			local now = pigapi.Now()
			local l = pigapi.GetModuleLast(p, MODULE_KEY)
			InitBaselineIfNeeded(l)

			-- Source fiable: arg1 de SPELL_UPDATE_COOLDOWN (vu en /eventtrace).
			local argSpellID = tonumber((select(1, ...))) or 0
			if argSpellID > 0 and CFG.spells[argSpellID] then
				local lastArgAt = tonumber(l.lastArgAtBySpell[argSpellID] or 0) or 0
				if lastArgAt == 0 or (now - lastArgAt) >= 0.20 then
					l.lastArgAtBySpell[argSpellID] = now
					AddContribution(p, l, now, argSpellID, CFG.spells[argSpellID])
					return
				end
			end

			local deltaPoints = 0
			local hitCount = 0
			for spellID, points in pairs(CFG.spells) do
				local prev = l.spellState and l.spellState[spellID] or nil
				local snap = SnapshotSpell(spellID)
				if IsNewCooldown(prev, snap) then
					deltaPoints = deltaPoints + (tonumber(points) or 0)
					hitCount = hitCount + 1
					l.lastSpellID = spellID
				end
				l.spellState[spellID] = snap
			end

			if deltaPoints <= 0 then
				return
			end

			if hitCount > 0 then
				l.lastHitCount = hitCount
			end
			AddContribution(p, l, now, l.lastSpellID, deltaPoints)
		end,
	})
end

do
	local registry = Data.NewsRegistry
	if not registry or not registry.Register then
		return
	end

	local api = Data.JournalistAPI
	if not api then
		return
	end

	local function GetPlayerDisplayNameSafe(apiRef, uid)
		local n = apiRef and apiRef.GetPlayerDisplayName and apiRef.GetPlayerDisplayName(uid) or nil
		if n and n ~= "" then
			return n
		end
		n = apiRef and apiRef.GetPlayerDisplayName and apiRef.GetPlayerDisplayName() or nil
		if n and n ~= "" then
			return n
		end
		return uid and tostring(uid) or "Le joueur"
	end

	local function ProcessHousingCleanupNews(g, intel, last, uid, now)
		local moduleState = intel and intel.last or nil
		local seq = tonumber(moduleState and moduleState.seq or 0) or 0
		if seq <= 0 then
			return
		end

		local postedSeq = tonumber(last.postedSeq or 0) or 0
		if seq <= postedSeq then
			return
		end

		local total = tonumber(moduleState and moduleState.totalPoints or 0) or 0
		local delta = tonumber(moduleState and moduleState.lastDeltaPoints or 0) or 0
		if total <= 0 or delta <= 0 then
			return
		end

		local replaceKey = (CFG.replaceKeyPrefix or "housingcleanup:") .. tostring(uid or "player")
		local msg = (
			api.Pick(CFG.phrases)
			or "%s participe a la bonne tenue de l'ile du Logis et du Quartier : +%d points de contribution (total : %d)."
		):format(GetPlayerDisplayNameSafe(api, uid), delta, total)

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = tonumber(CFG.icon) or 134400,
			ts = now,
			replaceKey = replaceKey,
			removedAt = api.GetRemovedAt(MODULE_KEY, now, nil, replaceKey),
			points = delta > 0 and delta or (POINTS.housingcleanup or 1),
		})

		last.postedSeq = seq
		last.postedTotal = total
		last.postedAt = now
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessHousingCleanupNews,
	})
end
