-- ==========================================================
-- Session presence module (refactor CFG + moteur)
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { connection = 0.25 }

local MODULE_KEY = "session"
local PIGISTE_KEY = "presence"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local PRESENCE_ATLAS = {
	male = {
		Human = "raceicon128-human-male",
		Orc = "raceicon128-orc-male",
		Dwarf = "raceicon128-dwarf-male",
		NightElf = "raceicon128-nightelf-male",
		Scourge = "raceicon128-scourge-male",
		Tauren = "raceicon128-tauren-male",
		Gnome = "raceicon128-gnome-male",
		Troll = "raceicon128-troll-male",
		Goblin = "raceicon128-goblin-male",
		BloodElf = "raceicon128-bloodelf-male",
		Draenei = "raceicon128-draenei-male",
		Worgen = "raceicon128-worgen-male",
		Pandaren = "raceicon128-pandaren-male",
		Nightborne = "raceicon128-nightborne-male",
		HighmountainTauren = "raceicon128-highmountaintauren-male",
		VoidElf = "raceicon128-voidelf-male",
		LightforgedDraenei = "raceicon128-lightforgeddraenei-male",
		ZandalariTroll = "raceicon128-zandalaritroll-male",
		KulTiran = "raceicon128-kultiran-male",
		DarkIronDwarf = "raceicon128-darkirondwarf-male",
		Vulpera = "raceicon128-vulpera-male",
		MagharOrc = "raceicon128-magharorc-male",
		Mechagnome = "raceicon128-mechagnome-male",
		Dracthyr = "raceicon128-dracthyr-male",
	},
	female = {
		Human = "raceicon128-human-female",
		Orc = "raceicon128-orc-female",
		Dwarf = "raceicon128-dwarf-female",
		NightElf = "raceicon128-nightelf-female",
		Scourge = "raceicon128-scourge-female",
		Tauren = "raceicon128-tauren-female",
		Gnome = "raceicon128-gnome-female",
		Troll = "raceicon128-troll-female",
		Goblin = "raceicon128-goblin-female",
		BloodElf = "raceicon128-bloodelf-female",
		Draenei = "raceicon128-draenei-female",
		Worgen = "raceicon128-worgen-female",
		Pandaren = "raceicon128-pandaren-female",
		Nightborne = "raceicon128-nightborne-female",
		HighmountainTauren = "raceicon128-highmountaintauren-female",
		VoidElf = "raceicon128-voidelf-female",
		LightforgedDraenei = "raceicon128-lightforgeddraenei-female",
		ZandalariTroll = "raceicon128-zandalaritroll-female",
		KulTiran = "raceicon128-kultiran-female",
		DarkIronDwarf = "raceicon128-darkirondwarf-female",
		Vulpera = "raceicon128-vulpera-female",
		MagharOrc = "raceicon128-magharorc-female",
		Mechagnome = "raceicon128-mechagnome-female",
		Dracthyr = "raceicon128-dracthyr-female",
	},
}

-- Expose atlas pool for reuse in other modules (e.g. map NPC avatars).
Data.SessionPresenceAtlas = PRESENCE_ATLAS

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================

local CFG = {
	enabled = true,

	-- Event interne (Pigiste -> Journalist.TickNow(event))
	-- On évite d’attacher la logique NewsRegistry à un event Blizzard.
	triggerEvent = "WGW_PRESENCE_LOGIN",
	pigisteEvents = {
		PLAYER_ENTERING_WORLD = true,
		PLAYER_LOGIN = true,
		PLAYER_GUILD_UPDATE = true,
		GUILD_ROSTER_UPDATE = true,
		PLAYER_LOGOUT = true,
	},
	triggerEvents = {
		"WGW_PRESENCE_LOGIN",
	},

	ttlSeconds = 300, -- durée de la news présence

	replaceKeyPrefix = "presence:",

	-- Type de news (on conserve ton comportement existant)
	newsType = "connection",

	-- Fallback icônes si atlas indisponible
	fallbackIcons = { 136488, 136489, 136490 },

	-- Nettoyage DB (si removedAt est stocké sur les news)
	cleanup = {
		enabled = true,
		global = true, -- purge cross-guild (DB)
		globalMinInterval = 15, -- sec (évite de boucler en permanence)
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
				-- Compat : TickNow(event?) ou TickNow()
				local ok = pcall(Journalist.TickNow, CFG.triggerEvent)
				if not ok then
					pcall(Journalist.TickNow)
				end
			end
		end

		if C_Timer and C_Timer.After then
			C_Timer.After(0, doTick)
		else
			doTick()
		end
	end

	-- ----------------------------------------------------------
	-- État de login (car EnsurePlayer peut être prêt après login)
	-- ----------------------------------------------------------
	local pendingLoginAt = nil
	local pendingConfirmed = false

	local function applyLoginAt(p, ts)
		local L = pigapi.GetModuleLast(p, MODULE_KEY)
		L.loginAt = ts
		L.logoutAt = 0
		L.reloadAt = 0

		p.updatedAt = ts

		-- Déclenche le traitement news (filtré sur CFG.triggerEvent)
		TickJournalistSoon()
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		OnEvent = function(_, event, ...)
			local now = pigapi.Now()

			if event == "PLAYER_LOGIN" then
				-- Sécurité : si reload, on ignore (sera traité dans ENTERING_WORLD)
				if IsReloadingUI and IsReloadingUI() then
					return
				end
				pendingLoginAt = now
				pendingConfirmed = false
				return
			end

			if event == "PLAYER_ENTERING_WORLD" then
				local isInitialLogin, isReloadingUI = ...

				if isReloadingUI then
					local p = pigapi.EnsurePlayer(pigapi.GetMyUID())
					if not p then
						return
					end
					local L = pigapi.GetModuleLast(p, MODULE_KEY)
					L.reloadAt = now
					p.updatedAt = now

					pendingLoginAt = nil
					pendingConfirmed = false
					return
				end

				if not isInitialLogin then
					return
				end

				local p = pigapi.EnsurePlayer(pigapi.GetMyUID())
				if not p then
					-- On attend une mise à jour de guilde/roster pour confirmer
					pendingLoginAt = pendingLoginAt or now
					pendingConfirmed = true
					return
				end

				applyLoginAt(p, pendingLoginAt or now)
				pendingLoginAt = nil
				pendingConfirmed = false
				return
			end

			-- Si le login initial n’était pas encore “applicable”, on retente
			if pendingLoginAt and pendingConfirmed then
				local p = pigapi.EnsurePlayer(pigapi.GetMyUID())
				if p then
					applyLoginAt(p, pendingLoginAt)
					pendingLoginAt = nil
					pendingConfirmed = false
				end
			end

			if event == "PLAYER_LOGOUT" then
				local p = pigapi.EnsurePlayer(pigapi.GetMyUID())
				if not p then
					return
				end
				local L = pigapi.GetModuleLast(p, MODULE_KEY)

				if IsReloadingUI and IsReloadingUI() then
					L.reloadAt = now
					p.updatedAt = now
					return
				end

				L.logoutAt = now
				p.updatedAt = now
			end
		end,
	})
end

-- ==========================================================
-- 4) Helpers métier (purs)
-- ==========================================================

local function startsWith(s, p)
	return type(s) == "string" and type(p) == "string" and s:sub(1, #p) == p
end

local function getPresenceAtlas()
	if not UnitRace or not UnitSex then
		return nil
	end
	local _, raceFile = UnitRace("player")
	local sex = UnitSex("player")
	local sexKey = (sex == 3) and "female" or "male"

	local t = PRESENCE_ATLAS[sexKey]
	return (t and raceFile and t[raceFile]) or nil
end

local function GetPlayerDisplayNameSafe(api, uid)
	local n = api and api.GetPlayerDisplayName and api.GetPlayerDisplayName(uid) or nil
	if n and n ~= "" then
		return n
	end
	n = api and api.GetPlayerDisplayName and api.GetPlayerDisplayName() or nil
	if n and n ~= "" then
		return n
	end
	return uid and tostring(uid) or "Le joueur"
end

local function buildPresenceMessage(api)
	local playerRaw = (UnitName and UnitName("player")) or GetPlayerDisplayNameSafe(api)
	local classTag = (UnitClass and select(2, UnitClass("player"))) or nil
	local playerColored = playerRaw

	if ns.Utils and ns.Utils.ColorizeByClassTag then
		playerColored = ns.Utils.ColorizeByClassTag(playerRaw, classTag)
	end

	local note = api and api.GetMyPublicNote and api.GetMyPublicNote() or nil
	local account, isMain = playerRaw, false

	if ns.Utils and ns.Utils.ParsePseudo then
		account, isMain = ns.Utils.ParsePseudo(note, playerRaw)
	end

	if isMain then
		return ("%s ana karakteriyle baglandi."):format(account)
	end
	return ("%s %s ile baglandi."):format(account, playerColored)
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

	local lastGlobalCleanupAt = 0

	local function removeNewsByReplaceKey(g, rk)
		if api.RemoveNewsByReplaceKey then
			api.RemoveNewsByReplaceKey(g, rk)
			return
		end
		if not g or not g.news or not g.news.items then
			return
		end
		for i = #g.news.items, 1, -1 do
			local n = g.news.items[i]
			if n and n.replaceKey == rk then
				table.remove(g.news.items, i)
			end
		end
	end

	local function cleanupPresenceLocal(g, uid, now)
		if not g or not g.news or not g.news.items then
			return
		end
		local prefix = (CFG.replaceKeyPrefix or "presence:") .. tostring(uid)

		for i = #g.news.items, 1, -1 do
			local n = g.news.items[i]
			if n and n.replaceKey and startsWith(n.replaceKey, prefix) then
				local removedAt = tonumber(n.removedAt or 0) or 0
				if removedAt > 0 and removedAt <= now then
					table.remove(g.news.items, i)
				end
			end
		end
	end

	local function cleanupPresenceEverywhere(now)
		if not CFG.cleanup.enabled or not CFG.cleanup.global then
			return
		end
		local minInt = tonumber(CFG.cleanup.globalMinInterval) or 15
		if lastGlobalCleanupAt > 0 and (now - lastGlobalCleanupAt) < minInt then
			return
		end
		lastGlobalCleanupAt = now

		if not WoWGuildeDB or not WoWGuildeDB.guilds then
			return
		end
		for _, g in pairs(WoWGuildeDB.guilds) do
			if g and g.news and g.news.items then
				for i = #g.news.items, 1, -1 do
					local n = g.news.items[i]
					if n and n.replaceKey and n.replaceKey:match("^presence:") then
						local removedAt = tonumber(n.removedAt or 0) or 0
						if removedAt > 0 and removedAt <= now then
							table.remove(g.news.items, i)
						end
					end
				end
			end
		end
	end

	local function setRemovedAtOnExisting(g, rk, removedAt)
		if not g or not g.news or not g.news.items then
			return
		end
		for i = #g.news.items, 1, -1 do
			local n = g.news.items[i]
			if n and n.replaceKey == rk then
				n.removedAt = removedAt
				return
			end
		end
	end

	local function addPresenceNewsCompat(g, msg, icon, ts, rk, removedAt)
		-- 1) Signature moderne (table) si dispo
		if api.AddRawNews then
			local ok, res = pcall(api.AddRawNews, g, {
				text = msg,
				type = CFG.newsType or "connection",
				icon = icon,
				ts = ts,
				replaceable = true,
				replaceKey = rk,
				ttlSeconds = CFG.ttlSeconds,
				removedAt = removedAt, -- utile à ton cleanup manuel
				points = POINTS.connection or 1,
			})
			if ok then
				return res
			end
		end

		-- 2) Signature legacy (comme ton code original)
		if api.AddRawNews then
			-- g, text, type, icon, ts, replaceKey, ..., removedAt
			return api.AddRawNews(g, msg, CFG.newsType or "connection", icon, ts, rk, nil, nil, nil, removedAt)
		end
	end

	local function ProcessPresenceNews(g, intel, last, uid, now)
		if not CFG.enabled then
			return
		end

		-- compat : certains registres passent last, d’autres s’appuient sur intel.last
		local L = last or (intel and intel.last) or nil
		if not L then
			return
		end

		cleanupPresenceLocal(g, uid, now)
		cleanupPresenceEverywhere(now)

		local loginAt = tonumber(L.loginAt) or 0
		local logoutAt = tonumber(L.logoutAt) or 0
		local announced = tonumber(L.presenceAnnouncedLoginAt) or 0

		if loginAt <= 0 then
			return
		end
		if logoutAt > 0 then
			return
		end
		if announced == loginAt then
			return
		end

		local rk = (CFG.replaceKeyPrefix or "presence:") .. tostring(uid)
		local msg = buildPresenceMessage(api)

		local icon = getPresenceAtlas()
		if not icon and api.Pick then
			icon = api.Pick(CFG.fallbackIcons or { 136488, 136489, 136490 })
		end

		-- Remplace l’éventuelle news précédente
		removeNewsByReplaceKey(g, rk)

		local removedAt = nil
		if api.GetRemovedAt then
			removedAt = api.GetRemovedAt(MODULE_KEY, loginAt, CFG.ttlSeconds)
		else
			removedAt = loginAt + (tonumber(CFG.ttlSeconds) or 300)
		end

		local added = addPresenceNewsCompat(g, msg, icon, loginAt, rk, removedAt)

		-- Garantit removedAt pour ton cleanup manuel
		if type(added) == "table" then
			added.removedAt = removedAt
		else
			setRemovedAtOnExisting(g, rk, removedAt)
		end

		L.presenceAnnouncedLoginAt = loginAt
	end

	-- ----------------------------------------------------------
	-- Registry (compat nouvelle/ancienne signature)
	-- ----------------------------------------------------------
	local ok = pcall(registry.Register, MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessPresenceNews,
	})
	if not ok then
		-- Ancien registre : registry.Register(key, fn)
		registry.Register(MODULE_KEY, ProcessPresenceNews)
	end
end
