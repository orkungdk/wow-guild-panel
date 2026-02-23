-- ==========================================================
-- Guild chat module (EPIC TIERS)
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { guildchat = 0.7 }

local MODULE_KEY = "guildchat"
local PIGISTE_KEY = "guildChat"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local DEFAULT_WINDOW_SECONDS = (Data.JournalistAPI and Data.JournalistAPI.WindowSeconds) or (48 * 3600)

local PHRASES_TIERS = {
	-- ----------------------------------------------------------
	-- LOW — sohbet yeni aciliyor
	-- ----------------------------------------------------------
	low = {
		"%s iki gunde %d mesajla guild sohbetine renk katti.",
		"%s iki gunde guild sohbetinde %d kez soz aldi.",
		"%s guild kanalini %d mesajla canlandirdi.",
		"%s guild tezgahinda %d kelime birakti.",
		"%s ortamdaki dedikoduya %d mesajla katildi.",
		"%s ortak sohbete %d yorum ekledi.",
	},

	-- ----------------------------------------------------------
	-- MEDIUM — artik kulak kabartiliyor
	-- ----------------------------------------------------------
	medium = {
		"%s iki gunde %d mesajla guildi titretti.",
		"%s iki gunde %d mesajla onemli bir ses haline geldi.",
		"%s guild hayatina %d mudahale ile ritim kattı.",
		"%s tartismalari %d mesajla hareketlendirdi.",
		"%s tezgahi %d kez soz alarak acik tuttu.",
		"%s guildde %d mesajla bircok sohbeti yonlendirdi.",
	},

	-- ----------------------------------------------------------
	-- HIGH — herkes dinliyor, bardaklar bekliyor
	-- ----------------------------------------------------------
	high = {
		"%s iki gunde %d mesajla guild kanalini kasirdi.",
		"%s guildde %d mesajla tum dikkati uzerine topladi.",
		"%s iki gunde %d mesajla guild kanalini sel gibi doldurdu.",
		"%s %d mudahale ile herkesi ekranda tuttu.",
		"%s %d mesajla yan sohbetleri susturdu.",
		"%s %d mesajla kanali tamamen ele gecirdi.",
	},

	-- ----------------------------------------------------------
	-- LEGENDARY — artik hikaye yaziliyor
	-- ----------------------------------------------------------
	legendary = {
		"%s iki gunde %d mesajla kanal efsanesi oldu.",
		"%s iki gunde %d mesajla guild tarihine iz birakti.",
		"%s %d mesajla guild kanalini tam bir destana cevirdi.",
		"%s %d mesajla tum meyhaneyi uykusuz birakti.",
		"%s %d mesajla kanali yasayan bir kronik haline getirdi.",
		"%s konustu, guild dinledi: iki gunde %d mesaj.",
		"%s %d mesajla adini kayitlara yazdirdi.",
	},
}

local ICONS = {
	4549168,
	4549169,
	4549170,
	4549171,
	4549172,
	4549173,
	1506450,
}

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================
-- Tout ce qui change souvent est ici. Le reste du fichier est le "moteur".
local CFG = {
	enabled = {
		window = true, -- 1 news agrégée 48h
	},

	-- Event de déclenchement (Pigiste -> Journalist.TickNow(event))
	triggerEvent = "CHAT_MSG_GUILD",
	pigisteEvents = {
		CHAT_MSG_GUILD = true,
	},
	triggerEvents = {
		"CHAT_MSG_GUILD",
	},

	-- On ne compte QUE tes propres messages (cohérent avec GetPlayerDisplayName()).
	selfOnly = true,

	-- Clé d'activité utilisée par pigapi.PushActivity(...)
	activityKey = "guildMessages",
	activityMaxLen = 400,

	-- Fenêtre + anti-spam (publish seulement si assez de nouveaux messages)
	window = {
		seconds = DEFAULT_WINDOW_SECONDS,
		minCount = 5, -- minimum de messages dans la fenêtre pour publier
		pendingMin = 5, -- minimum de nouveaux messages depuis la dernière publication
		ttlSeconds = DEFAULT_WINDOW_SECONDS,
		replaceKeyPrefix = "guildchat48:", -- remplaçable par joueur (prefix + uid)

		-- Fallbacks
		messageSingle = "%s 48 saat icinde bir mesaj birakti.",
		message = "%s 48 saat icinde %d mesajla cok konuskan davrandi.",
	},
	decay = {
		resetSeconds = 3600,
		factor = 0.7,
		min = 0.1,
	},

	tiers = {
		-- bornes inclusives : < lowMax => low, < mediumMax => medium, < highMax => high, sinon legendary
		lowMax = 15,
		mediumMax = 40,
		highMax = 80,
	},

	resolve = {
		fallbackIcons = ICONS,
		phrasesByTier = PHRASES_TIERS,
	},
}

-- ==========================================================
-- 3) Pigiste – collecte des événements
-- ==========================================================

do
	local Pigiste = Data.Pigiste
	local pigapi = Data.PigisteAPI
	if not Pigiste or not pigapi then
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

	local function ComputeDecayedPoints(state, now)
		local base = tonumber(POINTS.guildchat or 0) or 0
		if base <= 0 then
			return 0
		end
		local decayCfg = CFG.decay or {}
		local resetSeconds = tonumber(decayCfg.resetSeconds or 0) or 3600
		local factor = tonumber(decayCfg.factor or 0) or 0.7
		local minPoints = tonumber(decayCfg.min or 0) or 0.1
		if resetSeconds <= 0 then
			resetSeconds = 3600
		end
		if factor <= 0 or factor >= 1 then
			factor = 0.7
		end
		local slot = math.floor((now or 0) / resetSeconds)
		if state.guildChatDecaySlot ~= slot then
			state.guildChatDecaySlot = slot
			state.guildChatDecayCount = 0
		end
		local count = tonumber(state.guildChatDecayCount or 0) or 0
		local pts = base * (factor ^ count)
		if pts < minPoints then
			pts = minPoints
		end
		state.guildChatDecayCount = count + 1
		return pts
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		-- WoW: CHAT_MSG_GUILD(message, sender, ...)
		OnEvent = function(_, _, message, sender)
			if not sender or sender == "" then
				return
			end
			if message and tostring(message):lower():find("gg", 1, true) then
				return
			end

			if CFG.selfOnly and pigapi.IsSelfSender and not pigapi.IsSelfSender(sender) then
				return
			end

			local uid = pigapi.GetMyUID()
			local p = pigapi.EnsurePlayer(uid)
			if not p then
				return
			end

			-- (sécurité) structure attendue
			p.comms = p.comms or {}
			p.comms.bySender = p.comms.bySender or {}
			p.activity = p.activity or {}
			p.counters = p.counters or {}

			local ts = pigapi.Now()

			-- Compte "par sender" (debug / stats simples)
			local prev = tonumber(p.comms.bySender[sender]) or 0
			p.comms.bySender[sender] = prev + 1

			p.comms.lastSender = sender
			p.comms.lastAt = ts

			-- Compteurs + activité (base pour la fenêtre 48h)
			pigapi.IncCounter(p, "guildMessages", 1)
			if pigapi.PushActivity then
				pigapi.PushActivity(p, CFG.activityKey, ts, CFG.activityMaxLen)
			end

			-- Méta
			local l = pigapi.GetModuleLast(p, MODULE_KEY)
			l.guildChatAt = ts
			l.guildChatDecayPoints = ComputeDecayedPoints(l, ts)

			p.updatedAt = ts

			-- Déclenche immédiatement le traitement news
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

local function ListTailTsSafe(list)
	if type(list) ~= "table" or #list == 0 then
		return 0
	end
	local last = list[#list]
	if type(last) == "table" then
		return tonumber(last.ts) or 0
	end
	return tonumber(last) or 0
end

local function CountSinceSafe(list, since)
	if type(list) ~= "table" or #list == 0 then
		return 0
	end
	local c = 0
	for i = 1, #list do
		local v = list[i]
		local ts = (type(v) == "table") and (tonumber(v.ts) or 0) or (tonumber(v) or 0)
		if ts >= since then
			c = c + 1
		end
	end
	return c
end

local function PickTier(count)
	local lowMax = tonumber(CFG.tiers.lowMax) or 15
	local mediumMax = tonumber(CFG.tiers.mediumMax) or 40
	local highMax = tonumber(CFG.tiers.highMax) or 80

	if count < lowMax then
		return "low"
	elseif count < mediumMax then
		return "medium"
	elseif count < highMax then
		return "high"
	end
	return "legendary"
end

-- Fenêtre : retourne count uniquement si changement pertinent + anti-spam (pendingMin).
local function computeGuildChatWindow(api, intel, last, now)
	local key = CFG.activityKey or "guildMessages"
	local list = intel.activity and intel.activity[key]

	local tailTs = (api.ListTailTs and api.ListTailTs(list)) or ListTailTsSafe(list)
	local prevTailTs = tonumber(last.guildChatTailTs) or 0
	if tailTs <= prevTailTs then
		return
	end

	last.guildChatTailTs = tailTs

	local seconds = tonumber(CFG.window.seconds) or DEFAULT_WINDOW_SECONDS
	local since = now - seconds

	local count = (api.CountSince and api.CountSince(list, since)) or CountSinceSafe(list, since)

	-- pending = nombre de nouveaux messages depuis dernière publication
	local prevTotal = tonumber(last.guildChatTotal) or 0
	local total = tonumber(intel.counters and intel.counters.guildMessages or 0) or 0
	if total > prevTotal then
		last.guildChatTotal = total
		last.guildChatPending = (tonumber(last.guildChatPending) or 0) + (total - prevTotal)
	end

	local minCount = tonumber(CFG.window.minCount) or 5
	local pendingMin = tonumber(CFG.window.pendingMin) or 5

	if count < minCount then
		return
	end
	if (tonumber(last.guildChatPending) or 0) < pendingMin then
		return
	end

	-- reset pending après publication
	last.guildChatPending = 0

	-- évite de republier à l'identique si le count n'a pas bougé
	local prevCount = tonumber(last.guildChatCount) or 0
	if count == prevCount then
		return
	end
	last.guildChatCount = count

	return count
end

local function PickIcon(api)
	if api and api.Pick and CFG.resolve.fallbackIcons then
		return api.Pick(CFG.resolve.fallbackIcons)
	end
	local icons = CFG.resolve.fallbackIcons or ICONS
	if type(icons) == "table" and #icons > 0 then
		return icons[1]
	end
	return nil
end

local function BuildMessage(api, playerName, count)
	if count == 1 then
		return (CFG.window.messageSingle or "%s 48 saat icinde bir mesaj birakti."):format(playerName)
	end

	local tier = PickTier(count)
	local bucket = CFG.resolve.phrasesByTier and CFG.resolve.phrasesByTier[tier] or nil

	local tpl = (bucket and api.Pick and api.Pick(bucket))
		or (bucket and bucket[1])
		or CFG.window.message
		or "%s 48 saat icinde %d mesajla cok konuskan davrandi."

	return tpl:format(playerName, count)
end

local function AddRawNewsCompat(api, g, payload)
	-- Nouveau format (table)
	local ok = pcall(api.AddRawNews, g, payload)
	if ok then
		return
	end

	-- Legacy (signature ancienne : best-effort)
	pcall(
		api.AddRawNews,
		g,
		payload.text,
		payload.type,
		payload.icon,
		payload.ts,
		payload.replaceKey,
		payload.id,
		nil,
		nil,
		payload.ttlSeconds,
		payload.removedAt
	)
end

local function RegisterCompat(registry, key, def)
	-- Nouveau format (table avec trigger/run)
	local ok = pcall(registry.Register, key, def)
	if ok then
		return
	end
	-- Ancien format (function)
	if type(def) == "function" then
		registry.Register(key, def)
	elseif type(def) == "table" and type(def.run) == "function" then
		registry.Register(key, def.run)
	end
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

	local function ProcessGuildChatNews(g, intel, last, uid, now)
		if not (CFG.enabled and CFG.enabled.window) then
			return
		end

		local count = computeGuildChatWindow(api, intel, last, now)
		if not count then
			return
		end

		local playerName = GetPlayerDisplayNameSafe(api, uid)
		local msg = BuildMessage(api, playerName, count)

		local replaceKey = ("%s%s"):format(CFG.window.replaceKeyPrefix or "guildchat48:", tostring(uid))
		local removedAt = (api.GetRemovedAt and api.GetRemovedAt(MODULE_KEY, now)) or nil

		AddRawNewsCompat(api, g, {
			text = msg,
			type = MODULE_KEY,
			icon = PickIcon(api),
			ts = now,
			replaceable = true,
			replaceKey = replaceKey,
			ttlSeconds = tonumber(CFG.window.ttlSeconds) or tonumber(CFG.window.seconds) or DEFAULT_WINDOW_SECONDS,
			removedAt = removedAt,
			points = tonumber((last and last.guildChatDecayPoints) or 0) or (POINTS.guildchat or 0.7),
		})
	end

	-- Déclenchement piloté par le module
	RegisterCompat(registry, MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessGuildChatNews,
	})
end
