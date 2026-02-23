-- ==========================================================
-- LFG module
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { pve = 2 }

local MODULE_KEY = "lfg"
local PIGISTE_KEY = "lfg"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local WINDOW_SECONDS = (Data.JournalistAPI and Data.JournalistAPI.WindowSeconds) or (48 * 3600)

-- Fallback si on ne peut pas résoudre l’icône spécifique de l’instance
local ICONS = { 236382, 236385, 236388 }

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================
-- Tout ce qui change souvent est ici. Le reste du fichier est le "moteur".
local CFG = {
	enabled = {
		window = true, -- 1 news agrégée sur 48h
	},

	-- Event de déclenchement (Pigiste -> Journalist.TickNow(event))
	triggerEvent = "LFG_COMPLETION_REWARD",
	pigisteEvents = {
		LFG_COMPLETION_REWARD = true,
	},
	triggerEvents = {
		"LFG_COMPLETION_REWARD",
	},

	-- Stratégie icône instance :
	-- "LFG"      -> Interface\\LFGFrame\\LFGIcon-<textureFilename>.blp via GetLFGDungeonInfo(lfgID)
	-- "EJ_BUTTON"-> FileID bouton via EJ_GetInstanceInfo(journalInstanceID) (si possible)
	-- "AUTO"     -> tente EJ_BUTTON puis LFG puis fallback
	iconStrategy = "AUTO",

	-- Ligne instance dans le texte (ajoutée sur une nouvelle ligne)
	includeInstanceLine = true,
	instanceLineFormat = "%s", -- ou "Instance : %s"

	-- Règles de la fenêtre deux jours
	window = {
		seconds = WINDOW_SECONDS,
		minCount = 1, -- dès la première complétion
		ttlSeconds = WINDOW_SECONDS,
		replaceKeyPrefix = "lfg48:",

		-- Phrases SINGULIER (playerName)
		messageOne = {
			"%s est revenu victorieux d’un donjon terminé avec des alliés rencontrés sur le moment.\n(LFG)",
			"%s a terminé un donjon aux côtés de joueurs qu’il ne connaissait pas.\n(LFG)",
			"%s a mené à bien un donjon avec un groupe formé pour l’occasion.\n(LFG)",
			"%s a vaincu les dangers d’un donjon avec des compagnons d’un jour.\n(LFG)",
			"%s est sorti vainqueur d’un donjon accompli avec des alliés inconnus.\n(LFG)",
			"%s a terminé un donjon malgré un groupe composé de parfaits inconnus.\n(LFG)",
			"%s a survécu et triomphé d’un donjon réalisé avec un groupe improvisé.\n(LFG)",
			"%s a complété un donjon avec des alliés rencontrés en chemin.\n(LFG)",
		},

		-- Fallback simple pluriel (playerName, count)
		messageMany = "%s a terminé %d donjon(s) en groupe automatique sur deux jours.\n(LFG)",

		-- Phrases PLURIEL (playerName, count)
		phrases = {
			"%s a terminé %d donjons en quarante-huit heures avec des alliés inconnus.\n(LFG)",
			"%s a enchaîné %d donjons avec des groupes formés sur le moment.\n(LFG)",
			"%s a accompli %d donjons aux côtés de joueurs rencontrés pour l’occasion.\n(LFG)",
			"%s est sorti victorieux de %d donjons malgré des groupes éphémères.\n(LFG)",
			"%s a partagé %d victoires en donjon avec des compagnons d’un jour.\n(LFG)",
			"%s a affronté et terminé %d donjons avec des alliés qu’il ne connaissait pas.\n(LFG)",
			"%s a survécu à %d donjons réalisés avec des groupes improvisés.\n(LFG)",
			"%s a refermé les portes de %d donjons après des combats menés avec des inconnus.\n(LFG)",
			"%s a complété %d donjons avec des alliés rencontrés uniquement pour ces combats.\n(LFG)",
			"%s a remporté %d victoires en donjon avec des groupes formés à la volée.\n(LFG)",
		},
	},

	-- Résolution icône (fallbacks)
	resolve = {
		fallbackIcons = ICONS,
	},
}

-- ==========================================================
-- 3) Helpers instance (nom + icône)
-- ==========================================================

local function GetJournalInstanceIdFromMapId(mapId)
	-- 1) table user : journalinstanceID[mapId] => journalInstanceID
	local t = (Data and (Data.journalinstanceID or Data.journalInstanceID or Data.JournalInstanceID))
		or (ns and (ns.journalinstanceID or ns.journalInstanceID or ns.JournalInstanceID))
		or nil

	if t and mapId and t[mapId] then
		return t[mapId]
	end

	-- 2) API EJ si dispo : EJ_GetInstanceForMap(mapId) => journalInstanceID
	if mapId and type(EJ_GetInstanceForMap) == "function" then
		local jid = EJ_GetInstanceForMap(mapId)
		if jid then
			return jid
		end
	end

	return nil
end

local function ResolveInstanceIconAndName(strategy)
	-- GetInstanceInfo() -> name, ..., instanceMapId, lfgID
	local instName, _, _, _, _, _, _, instanceMapId, lfgID = GetInstanceInfo()

	local nameFromLFG, iconFromLFG = nil, nil
	local iconFromEJ = nil

	-- ---------------------------
	-- EJ (FileID bouton)
	-- ---------------------------
	if (strategy == "EJ_BUTTON" or strategy == "AUTO") and type(EJ_GetInstanceInfo) == "function" then
		local jid = GetJournalInstanceIdFromMapId(instanceMapId)
		if jid then
			-- EJ_GetInstanceInfo(journalInstanceID) -> name, description, bgImage, buttonImage, loreImage, ...
			local ejName, _, _, buttonFileId = EJ_GetInstanceInfo(jid)
			if ejName and ejName ~= "" then
				-- On garde ejName comme "nom le plus officiel" si besoin
				instName = instName or ejName
			end
			if type(buttonFileId) == "number" and buttonFileId > 0 then
				iconFromEJ = buttonFileId
			end
		end
	end

	-- ---------------------------
	-- LFG (chemin Interface\\LFGFrame\\LFGIcon-*.blp)
	-- ---------------------------
	if (strategy == "LFG" or strategy == "AUTO") and lfgID and type(GetLFGDungeonInfo) == "function" then
		-- GetLFGDungeonInfo(lfgID) -> ... textureFilename ...
		local lfgName, _, _, _, _, _, _, _, _, _, textureFilename = GetLFGDungeonInfo(lfgID)
		if lfgName and lfgName ~= "" then
			nameFromLFG = lfgName
		end
		if textureFilename and textureFilename ~= "" then
			iconFromLFG = ("Interface\\LFGFrame\\LFGIcon-%s.blp"):format(textureFilename)
		end
	end

	-- ---------------------------
	-- Nom fallback propre
	-- ---------------------------
	local finalName = nameFromLFG or instName
	if not finalName or finalName == "" then
		finalName = (type(GetRealZoneText) == "function" and GetRealZoneText())
			or (type(GetMinimapZoneText) == "function" and GetMinimapZoneText())
			or nil
	end

	-- ---------------------------
	-- Icône final
	-- ---------------------------
	local finalIcon = iconFromEJ or iconFromLFG -- AUTO préfère EJ si possible, sinon LFG
	return finalName, finalIcon, instanceMapId, lfgID
end

-- ==========================================================
-- 4) Pigiste – collecte des événements
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
			C_Timer.After(0, doTick) -- prochain frame
		else
			doTick()
		end
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		-- LFG_COMPLETION_REWARD : args variables selon versions; on n'en dépend pas ici.
		OnEvent = function()
			local uid = pigAPI.GetMyUID and pigAPI.GetMyUID() or nil
			local p = pigAPI.EnsurePlayer and pigAPI.EnsurePlayer(uid) or nil
			if not p then
				return
			end

			local ts = (pigAPI.Now and pigAPI.Now()) or time()

			-- Counters & meta
			if pigAPI.IncCounter then
				pigAPI.IncCounter(p, "lfgRuns", 1)
			else
				p.counters = p.counters or {}
				p.counters.lfgRuns = (tonumber(p.counters.lfgRuns) or 0) + 1
			end

			-- last[module]
			p.last = p.last or {}
			p.last[MODULE_KEY] = p.last[MODULE_KEY] or {}
			local last = p.last[MODULE_KEY]
			last.lfgAt = ts

			-- ------------------------------------------------------
			-- Capture instance (nom + icône) pour l'actu
			-- ------------------------------------------------------
			local instName, instIcon, instMapId, lfgID = ResolveInstanceIconAndName(CFG.iconStrategy or "AUTO")
			last.lfgInstanceName = instName
			last.lfgInstanceIcon = instIcon
			last.lfgInstanceMapId = instMapId
			last.lfgLfgID = lfgID

			-- Intel "activité" (on garde la compat avec tes modules existants)
			p.activity = p.activity or {}
			p.activity.lfg = p.activity.lfg or {}

			-- Si ton pigAPI a PushActivity, on l'utilise. Sinon on push une entrée simple.
			if pigAPI.PushActivity then
				pigAPI.PushActivity(p, "lfg", ts, 300)
			else
				local entry = { ts = ts }
				local list = p.activity.lfg
				list[#list + 1] = entry
				-- limite simple
				if #list > 200 then
					table.remove(list, 1)
				end
			end

			p.updatedAt = ts

			TickJournalistSoon()
		end,
	})
end

-- ==========================================================
-- 5) Helpers métier (purs)
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

local function PickFrom(api, listOrString)
	if type(listOrString) == "string" then
		return listOrString
	end
	if type(listOrString) == "table" then
		if api and api.Pick then
			local ok, v = pcall(api.Pick, listOrString)
			if ok and v then
				return v
			end
		end
		return listOrString[1]
	end
	return nil
end

local function PickFallbackIcon(api)
	if api and api.Pick and CFG.resolve and CFG.resolve.fallbackIcons then
		return api.Pick(CFG.resolve.fallbackIcons)
	end
	local list = (CFG.resolve and CFG.resolve.fallbackIcons) or ICONS
	return list and list[1] or nil
end

local function TailKey(list)
	if not list or #list == 0 then
		return ""
	end
	local e = list[#list]
	if type(e) == "table" then
		local ts = tonumber(e.ts) or 0
		return tostring(ts)
	end
	return tostring(e)
end

local function CountSince(list, since)
	if not list or #list == 0 then
		return 0
	end
	local n = 0
	for i = 1, #list do
		local e = list[i]
		local ts = (type(e) == "table") and tonumber(e.ts) or tonumber(e)
		if ts and ts >= since then
			n = n + 1
		end
	end
	return n
end

-- Fenêtre : retourne count uniquement si changement pertinent.
local function computeLfgWindow(list, last, now)
	if not last then
		return
	end

	local tail = TailKey(list)
	local prevTail = tostring(last.lfgTailKey or "")
	if tail == "" or tail == prevTail then
		return
	end
	last.lfgTailKey = tail

	local seconds = (CFG.window and CFG.window.seconds) or WINDOW_SECONDS
	local since = now - seconds
	local count = CountSince(list, since)

	local prevCount = tonumber(last.lfgWindowCount) or 0
	if count <= 0 or count == prevCount then
		last.lfgWindowCount = count
		return
	end

	last.lfgWindowCount = count
	return count
end

-- ==========================================================
-- 6) News processor
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

	local function ProcessLFGNews(g, intel, last, uid, now)
		if not (CFG.enabled and CFG.enabled.window) then
			return
		end
		if not intel then
			return
		end

		local list = intel.activity and intel.activity.lfg
		if not list or #list == 0 then
			return
		end

		local count = computeLfgWindow(list, last, now)
		if not count then
			return
		end

		if count < (tonumber(CFG.window.minCount) or 1) then
			return
		end

		local playerName = GetPlayerDisplayNameSafe(api, uid)

		-- Nom + icône instance capturés à l’event
		local instanceName = last and last.lfgInstanceName or nil
		local instanceIcon = last and last.lfgInstanceIcon or nil
		if type(instanceIcon) ~= "string" and type(instanceIcon) ~= "number" then
			instanceIcon = nil
		end

		-- Message
		local msg
		if count == 1 then
			local tpl = PickFrom(api, CFG.window.messageOne)
				or "%s a terminé un donjon via l'outil de recherche en deux jours.\n(LFG)"
			msg = tpl:format(playerName)
		else
			local tpl = PickFrom(api, CFG.window.phrases)
				or CFG.window.messageMany
				or "%s a terminé %d donjon(s) via l'outil de recherche en deux jours.\n(LFG)"
			msg = tpl:format(playerName, count)
		end

		-- Ajoute la ligne instance (nouvelle ligne)
		if CFG.includeInstanceLine and instanceName and instanceName ~= "" then
			local fmt = CFG.instanceLineFormat or "%s"
			msg = msg .. "\n" .. fmt:format(instanceName)
		end

		local replaceKey = ("%s%s"):format(CFG.window.replaceKeyPrefix or "lfg48:", tostring(uid))

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = instanceIcon or PickFallbackIcon(api),
			ts = now,
			replaceable = true,
			replaceKey = replaceKey,
			ttlSeconds = CFG.window.ttlSeconds or ((CFG.window and CFG.window.seconds) or WINDOW_SECONDS),
			points = POINTS.pve or 3,
		})
	end

	-- Déclenchement piloté par le module : le Journaliste ne devine rien.
	local def = {
		trigger = { events = CFG.triggerEvents },
		run = ProcessLFGNews,
	}

	-- Compat : certains anciens registries attendent (key, fn)
	local ok = pcall(function()
		registry.Register(MODULE_KEY, def)
	end)
	if not ok then
		registry.Register(MODULE_KEY, ProcessLFGNews)
	end
end
