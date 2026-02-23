-- ==========================================================
-- Level module
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { level = 3 }

local MODULE_KEY = "level"
local PIGISTE_KEY = "levelups"
local COUNTER_KEY = "levelUps"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local DEFAULT_PHRASES = {
	"%s franchit le niveau %d. Que les chopes se lèvent.",
	"%s atteint le niveau %d. La légende s’épaissit.",
	"%s s’élève au niveau %d. Les anciens acquiescent.",
	"%s passe niveau %d. Un pas de plus vers la gloire.",
	"%s gagne le niveau %d. Le chemin s’ouvre.",
	"%s accède au niveau %d. Les chroniques s’ajoutent.",
	"%s atteint le niveau %d. Les regards se tournent.",
	"%s grimpe au niveau %d. La route applaudit.",
	"%s touche le niveau %d. Le destin prend note.",
	"%s passe le seuil du niveau %d. Rien ne l’arrête.",
}

local DEFAULT_ICONS = {
	1357797,
	895887,
	895886,
	628675,
	7514184,
	525026,
	895886,
	879931,
	3636839,
	3565447,
}

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================
-- Tout ce qui change souvent est ici. Le reste du fichier est le "moteur".
local CFG = {
	enabled = true,

	-- Event de déclenchement (Pigiste -> Journalist.TickNow(event))
	triggerEvent = "PLAYER_LEVEL_UP",
	pigisteEvents = {
		PLAYER_LEVEL_UP = true,
	},
	triggerEvents = {
		"PLAYER_LEVEL_UP",
	},

	-- News unique (remplaçable) : conserve uniquement le dernier niveau atteint
	each = {
		replaceKeyPrefix = "level:", -- prefix + uid
		idPrefix = "level:", -- idPrefix + uid (stable)
		ttlSeconds = nil, -- nil => TTL standard du Journaliste

		-- Fallback si phrases est vide
		message = "%s passe niveau %d.",

		phrases = DEFAULT_PHRASES,
	},

	-- Résolution icône (fallbacks)
	resolve = {
		fallbackIcons = DEFAULT_ICONS,
	},
}

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

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		OnEvent = function(_, _, level)
			level = tonumber(level or 0) or 0
			if level <= 0 then
				return
			end

			local p = pigAPI.EnsurePlayer(pigAPI.GetMyUID())
			if not p then
				return
			end

			local ts = pigAPI.Now()

			-- structure attendue
			p.levelups = p.levelups or {}
			p.levelups.list = p.levelups.list or {}

			-- on garde un petit historique : robuste et utile
			local entry = {
				level = level,
				ts = ts,
			}
			if pigAPI.PushLimited then
				pigAPI.PushLimited(p.levelups.list, entry, 20)
			else
				p.levelups.list[#p.levelups.list + 1] = entry
				if #p.levelups.list > 20 then
					table.remove(p.levelups.list, 1)
				end
			end

			-- compat éventuelle avec d’autres modules / anciens codes
			p.last = p.last or {}
			p.last.level = level
			p.last.levelAt = ts

			pigAPI.IncCounter(p, COUNTER_KEY, 1)

			-- Méta (debug/trace)
			local l = pigAPI.GetModuleLast(p, MODULE_KEY)
			l.level = level
			l.levelAt = ts

			p.updatedAt = ts

			-- Déclenche immédiatement le traitement news (filtré sur CFG.triggerEvent)
			TickJournalistSoon()
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

local function MakeTailKey(list)
	if not list or #list == 0 then
		return ""
	end
	local e = list[#list]
	if type(e) == "table" then
		local ts = tonumber(e.ts) or 0
		local lvl = tonumber(e.level) or 0
		return ("%s:%s"):format(tostring(ts), tostring(lvl))
	end
	return tostring(e)
end

-- Récupère toutes les entrées nouvelles depuis le dernier passage.
-- Robuste aux doublons / événements regroupés.
local function collectNewLevelEntries(intel, last)
	local list = intel.levelups and intel.levelups.list
	if not list or #list == 0 then
		return
	end

	local tailKey = MakeTailKey(list)
	local prevTailKey = tostring(last.levelTailKey or "")

	-- Premier run : on marque, pas de publication (évite spam)
	if prevTailKey == "" then
		last.levelTailKey = tailKey
		return
	end

	if tailKey == "" or tailKey == prevTailKey then
		return
	end

	-- marqueur précis (ts+level) pour remonter depuis la fin
	local prevTs, prevLvl = prevTailKey:match("^(%d+):(%d+)$")
	prevTs = tonumber(prevTs or 0) or 0
	prevLvl = tonumber(prevLvl or 0) or 0

	local out = {}
	local foundMarker = false

	for i = #list, 1, -1 do
		local e = list[i]
		if type(e) == "table" then
			local ts = tonumber(e.ts) or 0
			local lvl = tonumber(e.level) or 0
			if ts == prevTs and lvl == prevLvl then
				foundMarker = true
				break
			end
			out[#out + 1] = e
		end
	end

	-- marqueur perdu (liste tronquée) : pas de spam, on resynchronise
	if not foundMarker then
		last.levelTailKey = tailKey
		return
	end

	if #out == 0 then
		last.levelTailKey = tailKey
		return
	end

	-- out inversé : remettre dans l'ordre chronologique
	for i = 1, math.floor(#out / 2) do
		out[i], out[#out - i + 1] = out[#out - i + 1], out[i]
	end

	-- mise à jour marqueur
	last.levelTailKey = tailKey

	return out
end

local function PickIcon(api)
	if api and api.Pick then
		return api.Pick(CFG.resolve.fallbackIcons or DEFAULT_ICONS)
	end
	local icons = CFG.resolve.fallbackIcons or DEFAULT_ICONS
	return icons and icons[1] or nil
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

	local function ProcessLevelNews(g, intel, last, uid, now)
		if not CFG.enabled then
			return
		end

		local entries = collectNewLevelEntries(intel, last)
		if not entries then
			return
		end

		-- On conserve uniquement le dernier niveau atteint (news remplaçable)
		local e = entries[#entries]
		if type(e) ~= "table" then
			return
		end

		local level = tonumber(e.level) or 0
		if level <= 0 then
			return
		end

		local playerName = GetPlayerDisplayNameSafe(api, uid)

		local tpl = (CFG.each.phrases and api.Pick and api.Pick(CFG.each.phrases))
			or (CFG.each.phrases and CFG.each.phrases[1])
			or CFG.each.message
			or "%s passe niveau %d."

		local msg = tpl:format(playerName, level)

		local replaceKey = ("%s%s"):format(CFG.each.replaceKeyPrefix or "level:", tostring(uid))
		local newsId = ("%s%s"):format(CFG.each.idPrefix or "level:", tostring(uid))

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = PickIcon(api),
			ts = tonumber(e.ts) or now,
			replaceable = true,
			replaceKey = replaceKey,
			id = newsId,
			ttlSeconds = CFG.each.ttlSeconds, -- nil => TTL standard du Journaliste
			points = POINTS.level or 5,
		})

		-- trace / compat : dernier niveau publié
		last.levelLast = level
		last.levelLastAt = tonumber(e.ts) or now
	end

	-- Déclenchement piloté par le module : le Journaliste ne devine rien.
	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessLevelNews,
	})
end
