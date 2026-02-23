-- ==========================================================
-- Deaths module (incremental – 1h reset, 5 levels, no cause tracking)
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end

local MODULE_KEY = "deaths"
local PIGISTE_KEY = "deaths"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local RESET_SECONDS = 3600 -- points + niveau reset après 1h

-- 5 niveaux de points : -0.5 -> -0.1, puis -0.1 au-delà
local POINTS_BY_DEATH_INDEX = { -0.5, -0.4, -0.3, -0.2, -0.1 }

-- ==========================================================
-- 2.5) Configuration
-- ==========================================================

local CFG = {
	enabled = true,

	-- Event unique fiable
	triggerEvent = "PLAYER_DEAD",
	pigisteEvents = {
		PLAYER_DEAD = true,
	},
	triggerEvents = {
		"PLAYER_DEAD",
	},

	-- Fenêtre (reset 1h)
	window = {
		seconds = RESET_SECONDS,
		minCount = 1,
		ttlSeconds = RESET_SECONDS,
		replaceKeyPrefix = "deaths1h:",
	},

	-- Type de news
	newsType = "death",

	-- 5 niveaux de phrases : de trébucher à hécatombe (léger, jamais vindicatif)
	levels = {
		-- 1) Trébucher
		{
			phrases = {
				"%s a trébuché hors de ce monde %d fois sur la dernière heure.",
				"%s a connu un petit revers mortel %d fois sur la dernière heure.",
				"%s est mort %d fois sur la dernière heure sans que cela n’inquiète qui que ce soit.",
				"%s a perdu pied %d fois sur la dernière heure.",
				"%s a fait quelques erreurs fatales %d fois sur la dernière heure.",
			},
		},

		-- 2) Glissade
		{
			phrases = {
				"%s glisse doucement vers le cimetière avec %d morts sur la dernière heure.",
				"%s enchaîne les morts rapides avec %d passages en une heure.",
				"%s a succombé %d fois sur la dernière heure.",
				"%s a connu une série de morts légères %d fois sur la dernière heure.",
				"%s n’a pas tenu longtemps %d fois sur la dernière heure.",
			},
		},

		-- 3) Chute
		{
			phrases = {
				"%s accumule les morts avec %d décès sur la dernière heure.",
				"%s tombe un peu trop souvent avec %d morts sur la dernière heure.",
				"%s a connu plusieurs fins malheureuses... %d fois sur la dernière heure.",
				"%s a payé cher ses choix... %d fois sur la dernière heure.",
				"%s a enchaîné les morts... %d fois sur la dernière heure.",
			},
		},

		-- 4) Carnage (gentil)
		{
			phrases = {
				"%s multiplie les morts avec %d décès sur la dernière heure.",
				"%s a vécu une heure mouvementée avec %d morts.",
				"%s est mort à répétition avec %d décès sur la dernière heure.",
				"%s a sérieusement testé sa survie %d fois sur la dernière heure.",
				"%s a eu bien du mal à rester en vie... %d fois sur la dernière heure.",
			},
		},

		-- 5) Hécatombe
		{
			phrases = {
				"%s traverse une véritable hécatombe avec %d morts sur la dernière heure.",
				"%s a connu une heure particulièrement meurtrière avec %d décès.",
				"%s a accumulé un nombre impressionnant de morts avec %d décès sur la dernière heure.",
				"%s semble avoir défié la mort %d fois sur la dernière heure.",
				"%s a transformé l’heure écoulée en hécatombe légère avec %d morts.",
			},
		},
	},



	-- Mélange d’icônes (pick aléatoire à chaque update)
	icons = {
		237542,  -- Ability_Rogue_FeignDeath? (varie selon build)
		1392565, -- Artifact
		1390947,
		2021574,
		5852177,
		132285,  -- INV_Misc_Bone_HumanSkull_01
		136187,  -- Spell_Shadow_RaiseDead
		132331,  -- INV_Misc_Bone_01
		136178,  -- Spell_Shadow_DeathCoil
		135973,  -- Ability_Hunter_MarkedForDeath (varie)
	},
}

-- ==========================================================
-- 3) Pigiste – collecte des morts
-- ==========================================================

do
	local Pigiste = Data.Pigiste
	local pigAPI = Data.PigisteAPI
	if not Pigiste or not pigAPI then
		return
	end

	-- Déclenchement coalescé du journaliste
	local pendingTick = false
	local function TickJournalistSoon()
		if pendingTick then
			return
		end
		pendingTick = true

		local function doTick()
			pendingTick = false
			local Journalist = Data.Journalist
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

		OnEvent = function(_, event)
			if event ~= CFG.triggerEvent then
				return
			end

			local p = pigAPI.EnsurePlayer(pigAPI.GetMyUID())
			if not p then
				return
			end

			local ts = pigAPI.Now()

			-- compteur simple (stats globales module)
			pigAPI.IncCounter(p, MODULE_KEY, 1)

			-- stockage minimal (timeline)
			p.deaths = p.deaths or {}
			p.deaths.list = p.deaths.list or {}
			p.deaths.seq = (tonumber(p.deaths.seq) or 0) + 1

			local entry = {
				ts = ts,
				seq = p.deaths.seq,
			}

			-- conserve un historique raisonnable
			pigAPI.PushLimited(p.deaths.list, entry, 180)

			local l = pigAPI.GetModuleLast(p, MODULE_KEY)
			l.deathAt = ts
			p.updatedAt = ts

			TickJournalistSoon()
		end,
	})
end

-- ==========================================================
-- 4) Helpers métier
-- ==========================================================

local function GetPlayerDisplayNameSafe(api, uid)
	local n = api.GetPlayerDisplayName and api.GetPlayerDisplayName(uid) or nil
	if n and n ~= "" then
		return n
	end
	return uid and tostring(uid) or "Le joueur"
end

local function Pick(list, api)
	if api and api.Pick and type(list) == "table" then
		return api.Pick(list)
	end
	return list and list[1] or 134400
end

local function TailKey(list)
	if not list or #list == 0 then
		return ""
	end
	local e = list[#list]
	return ("%s:%s"):format(tostring(tonumber(e.ts) or 0), tostring(tonumber(e.seq) or 0))
end

local function ComputeWindowCount(list, now, seconds)
	local since = now - seconds
	local count = 0

	for i = #list, 1, -1 do
		local e = list[i]
		if e.ts >= since then
			count = count + 1
		else
			break
		end
	end

	return count
end

local function DeathPenaltyForIndex(i)
	if i <= 1 then
		return POINTS_BY_DEATH_INDEX[1]
	elseif i == 2 then
		return POINTS_BY_DEATH_INDEX[2]
	elseif i == 3 then
		return POINTS_BY_DEATH_INDEX[3]
	elseif i == 4 then
		return POINTS_BY_DEATH_INDEX[4]
	else
		return POINTS_BY_DEATH_INDEX[5]
	end
end

local function TotalPenaltyForCount(count)
	local total = 0
	for i = 1, count do
		total = total + DeathPenaltyForIndex(i)
	end
	return total
end

local function LevelIndexForCount(count)
	if count <= 1 then return 1 end
	if count == 2 then return 2 end
	if count == 3 then return 3 end
	if count == 4 then return 4 end
	return 5
end

-- ==========================================================
-- 5) News processor (incrémental + points cumulés sur 1h)
-- ==========================================================

do
	local registry = Data.NewsRegistry
	local api = Data.JournalistAPI
	if not registry or not registry.Register or not api then
		return
	end

	local function ProcessDeaths(g, intel, last, uid, now)
		if not CFG.enabled then
			return
		end

		local list = intel.deaths and intel.deaths.list
		if not list or #list == 0 then
			return
		end

		-- anti-double (une mort => une update)
		local tk = TailKey(list)
		if tk == tostring(last.deathTailKey or "") then
			return
		end
		last.deathTailKey = tk

		local count = ComputeWindowCount(list, now, CFG.window.seconds)
		if count < CFG.window.minCount then
			return
		end

		local lvl = LevelIndexForCount(count)
		local levelCfg = CFG.levels[lvl] or CFG.levels[1]

		local playerName = GetPlayerDisplayNameSafe(api, uid)
		local tpl = Pick(levelCfg.phrases, api)
		local icon = Pick(CFG.icons, api)

		local msg = tpl and tpl:format(playerName, count) or nil
		if not msg or msg == "" then
			return
		end

		local points = TotalPenaltyForCount(count)

		api.AddRawNews(g, {
			text = msg,
			type = CFG.newsType,
			icon = icon,
			ts = now,

			-- incrémental : on remplace la même actu pendant 1h
			replaceable = true,
			replaceKey = CFG.window.replaceKeyPrefix .. tostring(uid),
			ttlSeconds = CFG.window.ttlSeconds,

			-- points négatifs cumulés sur la fenêtre (reset via TTL + fenêtre 1h)
			points = points,
		})
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessDeaths,
	})
end
