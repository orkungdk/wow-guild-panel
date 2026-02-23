-- ==========================================================
-- Dungeon Boss module (WoW 12) — agrégateur 48h par difficulté
-- Fix : pas d’écrasement (replaceKey inclut current/legacy + difficulté)
-- Style : CFG + moteur (comme Achievements)
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

local MODULE_KEY = "dungeonboss"
local PIGISTE_KEY = "bossKills" -- activité stockée dans intel.activity[PIGISTE_KEY]

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local ICONS = { 1117878, 1546415, 342917, 1113442, 236400, 4254081, 1546411, 254651, 254094 }
local WINDOW_SECONDS = 48 * 3600

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================
-- Tout ce qui change souvent est ici. Le reste du fichier est le "moteur".
local CFG = {
	enabled = {
		window = true, -- 1 news agrégée 48h, par (current/legacy + difficulté)
	},

	-- Event de déclenchement (Pigiste -> Journalist.TickNow(event))
	triggerEvent = "BOSS_KILL",
	pigisteEvents = {
		BOSS_KILL = true,
	},
	triggerEvents = {
		"BOSS_KILL",
	},

	-- Fenêtre 48h
	window = {
		seconds = WINDOW_SECONDS,
		minCount = 1, -- déclenche dès le 1er kill (mets 2/3 si tu veux)
		ttlSeconds = WINDOW_SECONDS,
		replaceKeyPrefix = "dungeonboss48:",

		appendLastBossCurrent = true, -- ajoute "Dernier : Boss (Instance)." seulement pour current
	},

	-- Phrases (tavernier) : (playerName, count)
	phrases = {
		current = {
			normal = {
				"%s a fait tomber %d chef(s) de donjon.\n(Normal)",
				"%s a nettoyé %d boss de donjon sans se presser.\n(Normal)",
				"%s a vidé %d salles de donjon, méthodiquement.\n(Normal)",
				"%s a réglé le sort de %d chefs de donjon.\n(Normal)",
				"%s a traversé %d donjons et leurs maîtres.\n(Normal)",
				"%s a terminé %d affaires en donjon.\n(Normal)",
			},

			heroic = {
				"%s a tué héroïquement %d chef(s) de donjon.\n(Héroïque)",
				"%s a mené %d boss au tapis, version Héroïque.\n(Héroïque)",
				"%s a imposé sa loi à %d chefs de donjon.\n(Héroïque)",
				"%s a survécu à %d affrontements héroïques.\n(Héroïque)",
				"%s a gravé %d victoires en donjon héroïque.\n(Héroïque)",
				"%s a fait plier %d boss sous la pression.\n(Héroïque)",
			},

			mythic = {
				"%s a tué magistralement %d chef(s) de donjon.\n(Mythique)",
				"%s a signé %d exécutions propres en Mythique.\n(Mythique)",
				"%s a réglé %d problèmes que d’autres évitent.\n(Mythique)",
				"%s a survécu à %d épreuves mythiques.\n(Mythique)",
				"%s a laissé %d boss sans appel.\n(Mythique)",
				"%s a fait taire %d donjons mythiques.\n(Mythique)",
			},

			mythicplus = {
				"%s a tué magistralement %d chef(s) de donjon.\nGloire à %s !\n(Mythique+)",
				"%s a empilé %d boss en Mythique+.\nQue les clés tremblent.\n(Mythique+)",
				"%s a survécu à %d combats en Mythique+.\nHonneur à %s.\n(Mythique+)",
				"%s a dompté %d boss sous la pression des clés.\n%s en témoigne.\n(Mythique+)",
				"%s a laissé %d donjons derrière lui.\n%s n’a pas cédé.\n(Mythique+)",
				"%s a prouvé %d fois que la clé était méritée.\n%s était au rendez-vous.\n(Mythique+)",
			},
		},
		legacy = {
			normal = {
				"%s a tué %d ancien(s) chef(s) de donjon dernièrement.\n(Normal)",
				"%s a ressorti %d vieux noms des archives.\n(Normal)",
				"%s a balayé %d donjons d’un autre temps.\n(Normal)",
				"%s a rappelé à %d anciens boss pourquoi ils étaient oubliés.\n(Normal)",
			},

			heroic = {
				"%s a tué héroïquement %d ancien(s) chef(s) de donjon dernièrement.\n(Héroïque)",
				"%s a réveillé %d défis d’un autre âge.\n(Héroïque)",
				"%s a survécu à %d souvenirs héroïques.\n(Héroïque)",
				"%s a mis fin à %d légendes poussiéreuses.\n(Héroïque)",
			},

			mythic = {
				"%s a tué magistralement %d ancien(s) chef(s) de donjon dernièrement.\n(Mythique)",
				"%s a affronté %d vestiges mythiques.\n(Mythique)",
				"%s a prouvé que %d donjons n’avaient plus de secrets.\n(Mythique)",
				"%s a fermé %d chapitres que le temps avait laissés ouverts.\n(Mythique)",
			},

			mythicplus = {
				"%s a tué magistralement %d ancien(s) chef(s) de donjon dernièrement.\n(Mythique+)",
				"%s a poussé %d souvenirs jusqu’au bout.\n(Mythique+)",
				"%s a rappelé à %d donjons qu’ils n’étaient pas prêts.\n(Mythique+)",
				"%s a fait revivre %d cauchemars… pour eux.\n(Mythique+)",
			},
		},
	},

	-- Résolution icônes (fallback)
	resolve = {
		fallbackIcons = ICONS,
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

	-- Déclenchement "event-driven" du Journaliste (coalescé)
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

		OnEvent = function(_, _, bossID, bossName)
			local p = pigAPI.EnsurePlayer(pigAPI.GetMyUID())
			if not p then
				return
			end

			local now = pigAPI.Now()

			-- Compteur simple
			pigAPI.IncCounter(p, PIGISTE_KEY, 1)

			-- Méta "last"
			local l = pigAPI.GetModuleLast(p, MODULE_KEY)
			l.bossKillAt = now
			l.bossID = tonumber(bossID or 0) or 0
			l.bossName = tostring(bossName or "")

			-- Contexte instance (compat : garde-fous)
			local instanceType, instanceName, instanceID, difficultyID, difficultyName = nil, nil, nil, nil, nil
			if type(pigAPI.GetInstanceContext) == "function" then
				instanceType, instanceName, instanceID, difficultyID, difficultyName = pigAPI.GetInstanceContext()
			end

			-- On ne log que les donjons (party). (BOSS_KILL peut aussi exister en raid)
			if instanceType == "party" then
				local isCurrent = true
				if type(pigAPI.IsCurrentDungeonInstance) == "function" then
					isCurrent = pigAPI.IsCurrentDungeonInstance(instanceID) and true or false
				end

				-- Stocke l'activité
				pigAPI.PushActivity(p, PIGISTE_KEY, {
					ts = now,

					instanceType = instanceType,
					instanceName = tostring(instanceName or ""),
					instanceID = tonumber(instanceID or 0) or 0,

					isCurrent = isCurrent,

					difficultyID = tonumber(difficultyID or 0) or 0,
					difficultyName = tostring(difficultyName or ""),

					bossID = tonumber(bossID or 0) or 0,
					bossName = tostring(bossName or ""),
				}, 300)
			end

			p.updatedAt = now

			-- Traitement news immédiat (filtré sur CFG.triggerEvent)
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

local function GetDungeonDifficultyKey(difficultyID)
	difficultyID = tonumber(difficultyID or 0) or 0
	if difficultyID == 1 then
		return "normal", "Normal"
	end
	if difficultyID == 2 then
		return "heroic", "Héroïque"
	end
	if difficultyID == 23 then
		return "mythic", "Mythique"
	end
	if difficultyID == 8 then
		return "mythicplus", "Mythique+"
	end
	return "normal", "Normal"
end

local function MakeBossMarker(e)
	-- Marker robuste (évite les collisions si plusieurs kills même seconde)
	if type(e) ~= "table" then
		return ""
	end
	local ts = tonumber(e.ts) or 0
	local bossID = tonumber(e.bossID) or 0
	local instID = tonumber(e.instanceID) or 0
	local diffID = tonumber(e.difficultyID) or 0
	local cur = (e.isCurrent == false) and 0 or 1
	return ("%s:%s:%s:%s:%s"):format(ts, bossID, instID, diffID, cur)
end

-- Récupère les nouvelles entrées depuis le dernier marker, sans spam au 1er run.
local function collectNewBossEntries(intel, last)
	local list = intel.activity and intel.activity[PIGISTE_KEY]
	if not list or #list == 0 then
		return
	end

	local prevMarker = tostring(last.dbossMarker or "")
	if prevMarker == "" then
		-- Premier run : on set le marker et on sort (pas de spam)
		last.dbossMarker = MakeBossMarker(list[#list])
		return
	end

	-- On remonte jusqu'à retrouver l'ancien marker
	local out = {}
	local found = false
	for i = #list, 1, -1 do
		local e = list[i]
		if type(e) == "table" then
			if MakeBossMarker(e) == prevMarker then
				found = true
				break
			end
			out[#out + 1] = e
		end
	end

	-- Marker perdu (liste tronquée) : pas de spam
	if not found then
		last.dbossMarker = MakeBossMarker(list[#list])
		return
	end

	-- Rien de nouveau
	if #out == 0 then
		last.dbossMarker = MakeBossMarker(list[#list])
		return
	end

	-- out est inversé : remettre chrono
	for i = 1, math.floor(#out / 2) do
		out[i], out[#out - i + 1] = out[#out - i + 1], out[i]
	end

	-- Met à jour le marker sur la queue actuelle
	last.dbossMarker = MakeBossMarker(list[#list])

	return out, list
end

local function AppendLastBoss(msg, bossName, instanceName, allow)
	if not allow then
		return msg
	end

	local name = tostring(bossName or "")
	local inst = tostring(instanceName or "")
	if name == "" and inst == "" then
		return msg
	end

	local suffix = name ~= "" and name or inst
	if name ~= "" and inst ~= "" then
		suffix = ("%s (%s)"):format(name, inst)
	end

	return msg .. "\nDernier : " .. suffix .. "."
end

local function PickPhrase(api, bucket, isLegacy, diffKey, playerName, count)
	local side = isLegacy and "legacy" or "current"
	local pool = bucket and bucket[side] and bucket[side][diffKey]

	if pool and type(pool) == "table" and #pool > 0 then
		local tpl = (api.Pick and api.Pick(pool)) or pool[1]
		-- mythicplus current peut inclure %s bonus (Gloire à %s)
		-- On tente d’abord 3 args (player, count, player), sinon 2.
		local ok, res = pcall(function()
			return tpl:format(playerName, count, playerName)
		end)
		if ok and res then
			return res
		end
		return tpl:format(playerName, count)
	end

	-- fallback ultra safe
	return ("%s a tué %d chef(s) de donjon."):format(playerName, count)
end

-- Compte les kills depuis "sinceTs" pour un groupe (current/legacy + diffKey), et renvoie aussi le dernier entry du groupe
local function CountSince(list, sinceTs, wantCurrent, diffKey)
	if not list or #list == 0 then
		return 0, nil
	end

	local count, lastEntry = 0, nil
	for i = 1, #list do
		local e = list[i]
		if type(e) == "table" and e.ts and e.ts >= sinceTs and e.instanceType == "party" then
			local isCurrent = (e.isCurrent ~= false)
			if isCurrent == wantCurrent then
				local key = GetDungeonDifficultyKey(e.difficultyID)
				if key == diffKey then
					count = count + 1
					lastEntry = e
				end
			end
		end
	end
	return count, lastEntry
end

local function GetGroupKey(isLegacy, diffKey)
	return ("%s:%s"):format(isLegacy and "legacy" or "current", tostring(diffKey or "normal"))
end

local function PickIcon(api)
	if api and api.Pick and CFG.resolve and CFG.resolve.fallbackIcons then
		return api.Pick(CFG.resolve.fallbackIcons)
	end
	return ICONS[1]
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

	local function ProcessDungeonBossNews(g, intel, last, uid, now)
		if not CFG.enabled.window then
			return
		end

		local entries, list = collectNewBossEntries(intel, last)
		if not entries or not list then
			return
		end

		local windowSeconds = CFG.window.seconds or api.WindowSeconds or WINDOW_SECONDS
		local since = now - windowSeconds

		-- Groupes à re-check : uniquement ceux touchés par les nouvelles entrées
		local touched = {}
		for i = 1, #entries do
			local e = entries[i]
			if type(e) == "table" and e.ts and e.ts >= since and e.instanceType == "party" then
				local isLegacy = (e.isCurrent == false)
				local diffKey = GetDungeonDifficultyKey(e.difficultyID)
				local gk = GetGroupKey(isLegacy, diffKey)
				touched[gk] = { isLegacy = isLegacy, diffKey = diffKey }
			end
		end

		-- Rien de pertinent dans la fenêtre
		local hasAny = false
		for _ in pairs(touched) do
			hasAny = true
			break
		end
		if not hasAny then
			return
		end

		local playerName = GetPlayerDisplayNameSafe(api, uid)

		for gk, info in pairs(touched) do
			local isLegacy = info.isLegacy
			local diffKey = info.diffKey

			local wantCurrent = not isLegacy
			local count, lastEntry = CountSince(list, since, wantCurrent, diffKey)

			local minCount = tonumber(CFG.window.minCount) or 1
			if count < minCount or not lastEntry then
				-- Mets quand même à jour la trace pour éviter les oscillations
				last["dbossCount:" .. gk] = count
			else
				local prevCount = tonumber(last["dbossCount:" .. gk] or 0) or 0
				if count ~= prevCount then
					local replaceKey = ("%s%s:%s"):format(
						CFG.window.replaceKeyPrefix or "dungeonboss48:",
						tostring(uid),
						gk
					)

					-- Compat : si l'API expose un remove, on peut nettoyer avant (sinon replaceable suffit)
					if api.RemoveNewsByReplaceKey then
						api.RemoveNewsByReplaceKey(g, replaceKey)
					end

					local msg = PickPhrase(api, CFG.phrases, isLegacy, diffKey, playerName, count)

					msg = AppendLastBoss(
						msg,
						lastEntry.bossName,
						lastEntry.instanceName,
						(not isLegacy) and (CFG.window.appendLastBossCurrent ~= false)
					)

					api.AddRawNews(g, {
						text = msg,
						type = MODULE_KEY,
						icon = PickIcon(api),
						ts = now,

						replaceable = true,
						replaceKey = replaceKey,

						ttlSeconds = CFG.window.ttlSeconds or windowSeconds,
						removedAt = (api.GetRemovedAt and api.GetRemovedAt(MODULE_KEY, now)) or nil,
						points = POINTS.pve or 3,
					})

					last["dbossCount:" .. gk] = count
				end
			end
		end
	end

	-- Déclenchement piloté par le module : le Journaliste ne devine rien.
	local ok = pcall(function()
		registry.Register(MODULE_KEY, {
			trigger = { events = CFG.triggerEvents },
			run = ProcessDungeonBossNews,
		})
	end)

	-- Fallback si ton NewsRegistry est encore sur l'ancienne signature
	if not ok then
		registry.Register(MODULE_KEY, ProcessDungeonBossNews)
	end
end
