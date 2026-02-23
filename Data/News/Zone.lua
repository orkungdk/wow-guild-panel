-- ==========================================================
-- Zone module
-- (compatible avec le Journalist actuel : state = intelProxy.last)
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { world = 0.5 }

local MODULE_KEY = "zone" -- clé NewsRegistry + module intel (PigisteAPI.GetModuleLast)
local PIGISTE_KEY = "zones" -- clé Pigiste.RegisterModule (indépendante)

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local ICONS = {
	237386,
	237382,
	237384,
	237383,
	237385,
	3193420,
	645218,
	1064187,
}

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================

local CFG = {
	enabled = true,

	-- Events de déclenchement (Pigiste -> Journalist.TickNow(event))
	triggerEvents = {
		"ZONE_CHANGED",
		"ZONE_CHANGED_NEW_AREA",
		"ZONE_CHANGED_INDOORS",
		"PLAYER_ENTERING_WORLD",
	},
	pigisteEvents = {
		ZONE_CHANGED = true,
		ZONE_CHANGED_NEW_AREA = true,
		ZONE_CHANGED_INDOORS = true,
		PLAYER_ENTERING_WORLD = true,
		PLAYER_LEAVING_WORLD = true,
	},

	zone = {
		replaceKeyPrefix = "zone:",
		ttlSeconds = nil,

		-- Si true : ne publie jamais sur PLAYER_ENTERING_WORLD (mais met à jour l’état)
		-- (on gère déjà "login/reload" via bootstrap, donc laisse false si tu veux les TP)
		suppressEnterWorld = false,

		minSecondsBetweenNews = 1,

		-- Retries zone detection after teleports/loading screens.
		maxCaptureAttempts = 12,
		captureRetryDelay = 0.25,
		enterWorldDelay = 0.8,
		eventDelay = {
			ZONE_CHANGED = 0.7,
			ZONE_CHANGED_INDOORS = 0.7,
			ZONE_CHANGED_NEW_AREA = 0.55,
		},

		message = "%s su bolgeye geliyor:\n%s.",

		phrases = {
			"%s su bolgeye geliyor:\n%s.",
			"%s explore :\n%s.",
			"%s met le cap sur :\n%s.",
			"%s traverse :\n%s.",
			"%s passe par :\n%s.",
			"%s file vers :\n%s.",
			"%s poursuit sa route vers :\n%s.",
			"%s change d’horizon pour aller vers :\n%s.",
			"%s glisse vers :\n%s.",
			"%s su siniri geciyor:\n%s.",
			"%s quitte les terres pour :\n%s.",
			"%s prend la route de :\n%s.",
			"%s s’engage vers :\n%s.",
			"%s entre dans :\n%s.",
		},

		-- Decroissance exponentielle des points par actualite (reset toutes les 1h)
		decay = {
			resetSeconds = 3600,
			factor = 0.7,
			min = 0.05,
		},
	},

	resolve = {
		fallbackIcons = ICONS,
	},
}

-- ----------------------------------------------------------
-- Points decroissants par actualite (exponentiel + reset horaire)
-- ----------------------------------------------------------
local function ComputeDecayedPoints(state, now)
	local base = tonumber(POINTS.world or 0) or 0
	if base <= 0 then
		return 0
	end
	local decayCfg = CFG.zone.decay or {}
	local resetSeconds = tonumber(decayCfg.resetSeconds or 0) or 3600
	local factor = tonumber(decayCfg.factor or 0) or 0.7
	local minPoints = tonumber(decayCfg.min or 0) or 0.05
	if resetSeconds <= 0 then
		resetSeconds = 3600
	end
	if factor <= 0 or factor >= 1 then
		factor = 0.7
	end
	local slot = math.floor((now or 0) / resetSeconds)
	if state.zoneDecaySlot ~= slot then
		state.zoneDecaySlot = slot
		state.zoneDecayCount = 0
	end
	local count = tonumber(state.zoneDecayCount or 0) or 0
	local pts = base * (factor ^ count)
	if pts < minPoints then
		pts = minPoints
	end
	state.zoneDecayCount = count + 1
	return pts
end

-- ==========================================================
-- 3) Pigiste – collecte des événements
-- ==========================================================

do
	local Pigiste = Data.Pigiste
	local pigAPI = Data.PigisteAPI
	if not Pigiste or not pigAPI then
		return
	end

	-- ----------------------------------------------------------
	-- Déclenchement "event-driven" du Journaliste (coalescé)
	-- ----------------------------------------------------------
	local pendingTick = false
	local pendingEvent = nil

	local function TickJournalistSoon(ev)
		pendingEvent = ev or pendingEvent or CFG.triggerEvents[1]
		if pendingTick then
			return
		end
		pendingTick = true

		local function doTick()
			pendingTick = false
			local e = pendingEvent
			pendingEvent = nil

			local Journalist = (Data and Data.Journalist) or (ns and ns.Data and ns.Data.Journalist) or nil
			if Journalist and type(Journalist.TickNow) == "function" then
				Journalist.TickNow(e)
			end
		end

		if C_Timer and C_Timer.After then
			C_Timer.After(0, doTick) -- regroupe les rafales
		else
			doTick()
		end
	end

	-- ----------------------------------------------------------
	-- Zone info safe (corrige multi-assign + fallback)
	-- ----------------------------------------------------------
	local function GetZoneInfoSafe()
		-- 1) API Pigiste si dispo
		if pigAPI.GetZoneInfoSafe then
			local zn, mid = pigAPI.GetZoneInfoSafe()
			if zn and zn ~= "" then
				return zn, mid
			end
		end

		-- 2) MapID -> MapInfo (souvent plus fiable après TP)
		local mid = nil
		if C_Map and C_Map.GetBestMapForUnit then
			mid = C_Map.GetBestMapForUnit("player")
			if mid and C_Map.GetMapInfo then
				local info = C_Map.GetMapInfo(mid)
				if info and info.name and info.name ~= "" then
					return info.name, mid
				end
			end
		end

		-- 3) Fallback WoW
		local zn = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or nil
		if not zn or zn == "" then
			return nil, mid
		end
		return zn, mid
	end

	-- ----------------------------------------------------------
	-- Comparateur "différence réelle" avec mapID si possible
	-- ----------------------------------------------------------
	local function DiffFromExpected(curName, curMap, expName, expMap)
		curName = tostring(curName or "")
		expName = tostring(expName or "")
		curMap = tonumber(curMap) or 0
		expMap = tonumber(expMap) or 0

		-- si pas de baseline, on accepte (login/init)
		if expName == "" and expMap == 0 then
			return true
		end

		-- si map connus des 2 côtés, map > nom
		if curMap ~= 0 and expMap ~= 0 then
			if curMap ~= expMap then
				return true
			end
			return curName ~= expName
		end

		-- sinon, on se base sur le nom
		return curName ~= expName
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		OnEvent = function(_, event, ...)
			local p = pigAPI.EnsurePlayer(pigAPI.GetMyUID())
			if not p then
				return
			end

			local state = pigAPI.GetModuleLast(p, MODULE_KEY)
			local now = pigAPI.Now()

			state.zoneLastEvent = tostring(event or "")

			-- Chaque "raffale" d'event invalide les anciens timers
			state.zoneCaptureID = (tonumber(state.zoneCaptureID) or 0) + 1
			local myCaptureID = state.zoneCaptureID

			-- Baseline attendue (zone d’avant TP) :
			-- on la pose depuis l’état (pas depuis l’API), sinon on risque de "baseliner" déjà la nouvelle zone.
			local function ArmExpectedFromState()
				if state.zoneExpectName == nil then
					state.zoneExpectName = tostring(state.zoneName or "")
				end
				if state.zoneExpectMapID == nil then
					state.zoneExpectMapID = tonumber(state.zoneMapID) or 0
				end
				state.zoneExpectAt = now
			end

			if event == "PLAYER_LEAVING_WORLD" then
				-- On marque le zoning + baseline de départ
				state.zoneZoning = true
				ArmExpectedFromState()
				return
			end

			if event == "PLAYER_ENTERING_WORLD" then
				-- ENTER_WORLD arrive souvent avant que GetZoneText / map ne soit prêt.
				-- On garde la baseline (zone d’avant) et on poll jusqu'à un vrai changement.
				state.zoneZoning = true
				ArmExpectedFromState()
			else
				-- Sur les events de zone, si on n'était pas déjà en zoning,
				-- on arme aussi la baseline depuis l’état courant.
				if not state.zoneZoning then
					state.zoneZoning = true
					ArmExpectedFromState()
				end
			end

			local function CaptureZone(attempt)
				-- vieux timer ? on ignore
				if myCaptureID ~= state.zoneCaptureID then
					return
				end

				local zoneName, mapID = GetZoneInfoSafe()
				if not zoneName or zoneName == "" then
					local maxAttempts = CFG.zone.maxCaptureAttempts or 6
					if attempt < maxAttempts and C_Timer and C_Timer.After then
						C_Timer.After(CFG.zone.captureRetryDelay or 0.25, function()
							CaptureZone(attempt + 1)
						end)
					end
					return
				end

				-- Tant que l'API renvoie la "zone attendue" (ancienne zone),
				-- on considère que c'est encore stale (loading/teleport).
				local expName = state.zoneExpectName
				local expMap = state.zoneExpectMapID
				local changed = DiffFromExpected(zoneName, mapID, expName, expMap)

				if not changed then
					local maxAttempts = CFG.zone.maxCaptureAttempts or 6
					if attempt < maxAttempts and C_Timer and C_Timer.After then
						C_Timer.After((CFG.zone.captureRetryDelay or 0.25) * (attempt + 1), function()
							CaptureZone(attempt + 1)
						end)
						return
					end
					-- Toujours pas de vrai changement -> on sort sans polluer l'état
					state.zoneZoning = false
					return
				end

				-- ✅ On a enfin une zone différente de la baseline : on commit
				state.zoneSeq = (tonumber(state.zoneSeq) or 0) + 1
				state.zoneToken = tostring(now) .. ":" .. tostring(state.zoneSeq)

				state.zoneName = tostring(zoneName)
				state.zoneMapID = tonumber(mapID) or 0
				state.zoneAt = now
				state.zoneZoning = false

				-- Baseline consommée
				state.zoneExpectName = nil
				state.zoneExpectMapID = nil
				state.zoneExpectAt = nil

				p.updatedAt = now

				TickJournalistSoon(event)
			end

			-- Scheduling
			if C_Timer and C_Timer.After then
				if event == "PLAYER_ENTERING_WORLD" then
					C_Timer.After(CFG.zone.enterWorldDelay or 0.8, function()
						CaptureZone(0)
					end)
				else
					local delay = (CFG.zone.eventDelay and CFG.zone.eventDelay[event]) or 0.2
					C_Timer.After(delay, function()
						CaptureZone(0)
					end)
				end
			else
				CaptureZone(0)
			end
		end,
	})
end

-- ==========================================================
-- 4) Helpers métier (purs)
-- ==========================================================

local function GetPlayerDisplayNameSafe(api, uid)
	local n = api.GetPlayerDisplayName and api.GetPlayerDisplayName(uid) or nil
	if n and n ~= "" then
		return n
	end
	n = api.GetPlayerDisplayName and api.GetPlayerDisplayName() or nil
	if n and n ~= "" then
		return n
	end
	return uid and tostring(uid) or "Le joueur"
end

local function PickPhrase(api, list, fallback)
	if list and api and api.Pick then
		return api.Pick(list) or fallback
	end
	return (list and list[1]) or fallback
end

local function PickIcon(api, list, fallbackList)
	if api and api.Pick then
		return api.Pick(list) or (fallbackList and api.Pick(fallbackList)) or nil
	end
	return (list and list[1]) or (fallbackList and fallbackList[1]) or nil
end

-- Détecte un vrai changement de zone en évitant :
-- - spam au login/reload (bootstrap)
-- - re-traitement (zoneToken déjà consommé)
-- - rafales (minSecondsBetweenNews)
local function computeZoneChange(state, now)
	if not state then
		return
	end

	local token = tostring(state.zoneToken or "")
	local zoneAt = tonumber(state.zoneAt) or 0
	if token == "" and zoneAt <= 0 then
		return
	end

	-- Déjà traité ?
	if token ~= "" then
		if tostring(state.zoneProcessedToken or "") == token then
			return
		end
		state.zoneProcessedToken = token
	else
		if tonumber(state.zoneProcessedAt) == zoneAt then
			return
		end
		state.zoneProcessedAt = zoneAt
	end

	local name = tostring(state.zoneName or "")
	if name == "" then
		return
	end

	local mapID = tonumber(state.zoneMapID) or 0

	-- Bootstrap : premier état vu -> on arme, on ne publie pas.
	-- (sinon tu as exactement le problème "ancienne zone" au ENTER_WORLD)
	if not state.zoneBootstrapped then
		state.zoneBootstrapped = true
		state.zonePrevName = name
		state.zonePrevMapID = mapID
		state.zonePrevAt = zoneAt
		state.zoneNewsAt = tonumber(now) or now
		return
	end

	-- Même zone ? (si mapID inconnu, on se base sur le nom)
	local prevName = tostring(state.zonePrevName or "")
	local prevMapID = tonumber(state.zonePrevMapID) or 0

	local sameName = (name == prevName)
	local sameMap
	if mapID ~= 0 and prevMapID ~= 0 then
		sameMap = (mapID == prevMapID)
	else
		sameMap = true -- map inconnue -> on ne discrimine pas
	end

	if sameName and sameMap then
		return
	end

	-- Anti rafales
	local lastNewsAt = tonumber(state.zoneNewsAt) or 0
	local minDelta = tonumber(CFG.zone.minSecondsBetweenNews) or 0
	if minDelta > 0 and (now - lastNewsAt) < minDelta then
		state.zonePrevName = name
		state.zonePrevMapID = mapID
		state.zonePrevAt = zoneAt
		return
	end

	-- Changement accepté
	state.zonePrevName = name
	state.zonePrevMapID = mapID
	state.zonePrevAt = zoneAt
	state.zoneNewsAt = now

	return name, mapID, zoneAt
end

-- ==========================================================
-- 5) News processor
-- ==========================================================

do
	local registry = Data.NewsRegistry
	if not registry or not registry.Register then
		return
	end

	local api = Data.JournalistAPI
	if not api then
		return
	end

	-- IMPORTANT :
	-- fn(g, intelProxy, journalistLast, uid, now)
	-- -> le state pigiste est dans intelProxy.last
	local function ProcessZoneNews(g, intelProxy, jlast, uid, now)
		if not CFG.enabled then
			return
		end

		local state = intelProxy and intelProxy.last or nil
		if not state then
			return
		end

		-- Option : ne jamais publier sur ENTER_WORLD
		if CFG.zone.suppressEnterWorld and tostring(state.zoneLastEvent or "") == "PLAYER_ENTERING_WORLD" then
			computeZoneChange(state, now)
			return
		end

		local zoneName, mapID, zoneAt = computeZoneChange(state, now)
		if not zoneName then
			return
		end

		local playerName = GetPlayerDisplayNameSafe(api, uid)
		local tpl = PickPhrase(api, CFG.zone.phrases, CFG.zone.message) or "%s su bolgeye geliyor:\n%s."
		local msg = tpl:format(playerName, zoneName)

		local icon = PickIcon(api, CFG.resolve.fallbackIcons, ICONS)
		local replaceKey = ("%s%s"):format(CFG.zone.replaceKeyPrefix or "zone:", tostring(uid))

		if api.RemoveNewsByReplaceKey then
			api.RemoveNewsByReplaceKey(g, replaceKey)
		end

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = icon,
			ts = now,
			replaceable = true,
			replaceKey = replaceKey,
			ttlSeconds = CFG.zone.ttlSeconds,
			points = ComputeDecayedPoints(state, now),
		})
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessZoneNews,
	})
end
