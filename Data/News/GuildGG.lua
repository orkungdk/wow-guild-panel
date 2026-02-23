-- ==========================================================
-- Guild GG module (messages "gg" uniquement)
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end

local POINTS = { guildgg = 0.1 }

local MODULE_KEY = "guildgg"
local PIGISTE_KEY = "guildgg"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local WINDOW_SECONDS = (Data.JournalistAPI and Data.JournalistAPI.WindowSeconds) or (48 * 3600)

local ICONS = {
	1445240,
}

-- ==========================================================
-- 2.5) Configuration
-- ==========================================================

local CFG = {
	enabled = true,

	-- Event de déclenchement
	triggerEvent = "CHAT_MSG_GUILD",
	pigisteEvents = {
		CHAT_MSG_GUILD = true,
	},
	triggerEvents = {
		"CHAT_MSG_GUILD",
	},

	-- On ne compte QUE tes propres messages.
	selfOnly = true,

	-- Fenêtre d’affichage (TTL)
	window = {
		ttlSeconds = WINDOW_SECONDS,
	},

	phrases = {
		"%s adresse ses félicitations !",
		"%s félicite chaleureusement le groupe.",
		"%s envoie ses félicitations bien méritées.",
		"%s partage ses félicitations.",
		"%s applaudit la performance !",
		"%s salue la victoire avec des félicitations.",
	},
}

-- ==========================================================
-- 3) Pigiste – collecte
-- ==========================================================

do
	local Pigiste = Data.Pigiste
	local pigapi = Data.PigisteAPI
	if not Pigiste or not pigapi then
		return
	end

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

		-- WoW: CHAT_MSG_GUILD(message, sender, ...)
		OnEvent = function(_, _, message, sender)
			if not sender or sender == "" then
				return
			end
			if CFG.selfOnly and pigapi.IsSelfSender and not pigapi.IsSelfSender(sender) then
				return
			end
			if not message or message == "" then
				return
			end
			if not tostring(message):lower():find("gg", 1, true) then
				return
			end

			local p = pigapi.EnsurePlayer(pigapi.GetMyUID())
			if not p then
				return
			end

			local ts = pigapi.Now()
			local l = pigapi.GetModuleLast(p, MODULE_KEY)
			l.guildGGAt = ts
			l.guildGGPending = (tonumber(l.guildGGPending or 0) or 0) + 1

			p.updatedAt = ts

			-- Création immédiate de l'actu (sans attendre le TickNow)
			TickJournalistSoon()
		end,
	})
end

-- ==========================================================
-- 4) Helpers
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

local function PickIcon(api)
	if api and api.Pick then
		return api.Pick(ICONS)
	end
	if type(ICONS) == "table" and #ICONS > 0 then
		return ICONS[1]
	end
	return nil
end

local function PickPhrase(api)
	local phrases = CFG.phrases
	if api and api.Pick and type(phrases) == "table" then
		return api.Pick(phrases)
	end
	return (type(phrases) == "table" and phrases[1]) or "%s lance un GG !"
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

	local function AddRawNewsCompat(g, payload)
		local ok = pcall(api.AddRawNews, g, payload)
		if ok then
			return
		end
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

	local function ProcessGuildGGNews(g, intel, last, uid, now)
		if not CFG.enabled then
			return
		end
		local src = intel and intel.last or nil
		if not src or not src.guildGGAt then
			return
		end
		local pending = tonumber(src.guildGGPending or 0) or 0
		local elapsed = tonumber(src.guildGGAt or 0) or 0
		if pending <= 0 or elapsed <= 0 or now < elapsed then
			return
		end
		src.guildGGPending = 0
		last.guildGGPublishedAt = now

		local playerName = GetPlayerDisplayNameSafe(api, uid)
		local msg = (PickPhrase(api) or "%s lance un GG !"):format(playerName)

		local replaceKey = ("guildgg48:%s"):format(tostring(uid))
		AddRawNewsCompat(g, {
			text = msg,
			type = MODULE_KEY,
			icon = PickIcon(api),
			ts = now,
			replaceable = true,
			replaceKey = replaceKey,
			ttlSeconds = tonumber(CFG.window.ttlSeconds) or WINDOW_SECONDS,
			points = POINTS.guildgg or 0.1,
		})
	end

	local function RegisterCompat(registryRef, key, def)
		local ok = pcall(registryRef.Register, key, def)
		if ok then
			return
		end
		if type(def) == "function" then
			registryRef.Register(key, def)
		elseif type(def) == "table" and type(def.run) == "function" then
			registryRef.Register(key, def.run)
		end
	end

	RegisterCompat(registry, MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessGuildGGNews,
	})
end
