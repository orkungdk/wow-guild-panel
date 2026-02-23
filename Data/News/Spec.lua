-- ==========================================================
-- Spec module
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { spec = 0.5 }

local MODULE_KEY = "spec"
local PIGISTE_KEY = "specs"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local FALLBACK_ICON = 136116

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================
-- Tout ce qui change souvent est ici. Le reste du fichier est le "moteur".
local CFG = {
	enabled = true,

	-- Event de déclenchement (Pigiste -> Journalist.TickNow(event))
	triggerEvent = "PLAYER_SPECIALIZATION_CHANGED",
	pigisteEvents = {
		PLAYER_SPECIALIZATION_CHANGED = true,
		PLAYER_LOGIN = true,
		PLAYER_ENTERING_WORLD = true,
	},
	triggerEvents = {
		"PLAYER_SPECIALIZATION_CHANGED",
	},

	-- Capture baseline au login (sans news)
	baselineEvents = {
		PLAYER_LOGIN = true,
		PLAYER_ENTERING_WORLD = true, -- parfois plus fiable que LOGIN selon l'UI
	},

	-- News
	news = {
		-- TTL standard : nil => TTL par défaut du Journaliste
		ttlSeconds = nil,

		-- Clé de remplacement (1 news "spé" par joueur)
		replaceKeyPrefix = "spec:",

		-- Fallback si phrases bos ise
		message = "%s artik su rolde uzmanlasiyor:\n%s.",

		-- Phrases: (playerName, specName)
		phrases = {
			"%s artik su rolde uzmanlasiyor:\n%s.",
			"%s yol degistirip su uzmanliga odaklaniyor:\n%s.",
			"%s yeni bir uzmanlik benimsedi:\n%s.",
			"%s sanatini inceltiyor ve su rolde uzmanlasiyor:\n%s.",
			"%s disiplinini su yonde yogunlastiriyor:\n%s.",
			"%s uygulamasini su uzmanliga dogru kaydiriyor:\n%s.",
			"%s yeni bir uzmanliga geciyor:\n%s.",
			"%s rolunu su alanda uzmanlasarak yeniden tanimliyor:\n%s.",
			"%s su uzmanlikta kendini gelistirmeyi seciyor:\n%s.",
			"%s icgudusunu dinleyip su rolde uzmanlasiyor:\n%s.",
			"%s tamamen su uzmanliga kendini adiyor:\n%s.",
			"%s bilgisini su yonde yeniden sekillendiriyor:\n%s.",
		},
	},
	-- Résolution icône
	resolve = {
		fallbackIcon = FALLBACK_ICON,
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
	-- Helpers Pigiste
	-- ----------------------------------------------------------
	local function GetSpecIconSafe(specID)
		if not specID then
			return nil
		end

		-- Retail: GetSpecializationInfoByID existe normalement.
		if type(GetSpecializationInfoByID) == "function" then
			-- id, name, description, icon, background, role, classFile, className = GetSpecializationInfoByID(specID)
			local _, _, _, icon = GetSpecializationInfoByID(specID)
			if icon and icon ~= "" and icon ~= 0 then
				return icon
			end
		end

		-- Fallback (si ton pigAPI fournit déjà l'icône, on la garde côté Pigiste)
		return nil
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

	-- Capture baseline (login) avec retry léger si l'info spé n'est pas prête
	local function CaptureBaselineWithRetry(triesLeft)
		triesLeft = tonumber(triesLeft) or 0

		local specID, specName = pigAPI.GetSpecInfoSafe and pigAPI.GetSpecInfoSafe() or nil, nil
		if type(specID) == "table" then
			-- au cas où pigAPI renvoie (specID,name) via table
			specName = specID.name
			specID = specID.id
		end
		if not specName and pigAPI.GetSpecInfoSafe then
			specID, specName = pigAPI.GetSpecInfoSafe()
		end

		if not specID or not specName or specName == "" then
			if triesLeft > 0 and C_Timer and C_Timer.After then
				C_Timer.After(1, function()
					CaptureBaselineWithRetry(triesLeft - 1)
				end)
			end
			return
		end

		local uid = pigAPI.GetMyUID and pigAPI.GetMyUID() or nil
		local p = uid and pigAPI.EnsurePlayer and pigAPI.EnsurePlayer(uid) or nil
		if not p then
			return
		end

		local ts = pigAPI.Now and pigAPI.Now() or time()
		local icon = GetSpecIconSafe(specID)

		-- Stockage "intel" lisible
		p.spec = p.spec or {}
		p.spec.current = {
			id = tonumber(specID) or 0,
			name = tostring(specName or ""),
			icon = icon,
			ts = ts,
		}

		-- Stockage module state (baseline = "seen", pas de "pending")
		local l = pigAPI.GetModuleLast(p, MODULE_KEY)
		l.seenSpecID = tonumber(specID) or 0
		l.seenSpecName = tostring(specName or "")
		l.seenSpecIcon = icon
		l.seenSpecAt = ts

		l.pendingSpecID = nil
		l.pendingSpecName = nil
		l.pendingSpecIcon = nil
		l.pendingSpecAt = nil

		p.updatedAt = ts
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		OnEvent = function(_, event, unitTarget)
			-- PLAYER_SPECIALIZATION_CHANGED: payload = unitTarget
			if event == CFG.triggerEvent and unitTarget ~= "player" then
				return
			end

			-- Baseline (login/entering world) : on initialise "seen" sans publier de news
			if CFG.baselineEvents and CFG.baselineEvents[event] then
				CaptureBaselineWithRetry(3)
				return
			end

			-- Changement de spé : on enregistre "pending" + tick journaliste
			local specID, specName = pigAPI.GetSpecInfoSafe and pigAPI.GetSpecInfoSafe() or nil, nil
			if type(specID) == "table" then
				specName = specID.name
				specID = specID.id
			end
			if not specName and pigAPI.GetSpecInfoSafe then
				specID, specName = pigAPI.GetSpecInfoSafe()
			end

			if not specID or not specName or specName == "" then
				return
			end

			local uid = pigAPI.GetMyUID and pigAPI.GetMyUID() or nil
			local p = uid and pigAPI.EnsurePlayer and pigAPI.EnsurePlayer(uid) or nil
			if not p then
				return
			end

			local ts = pigAPI.Now and pigAPI.Now() or time()
			local icon = GetSpecIconSafe(specID)

			-- Intel lisible
			p.spec = p.spec or {}
			p.spec.current = {
				id = tonumber(specID) or 0,
				name = tostring(specName or ""),
				icon = icon,
				ts = ts,
			}

			-- Module state : pending (NE PAS toucher seen ici, sinon le processor ne verra pas le delta)
			local l = pigAPI.GetModuleLast(p, MODULE_KEY)
			l.pendingSpecID = tonumber(specID) or 0
			l.pendingSpecName = tostring(specName or "")
			l.pendingSpecIcon = icon
			l.pendingSpecAt = ts

			-- Trace/debug éventuel
			l.specAt = ts

			p.updatedAt = ts

			-- Déclenche le traitement news (filtré sur CFG.triggerEvent)
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

-- Retourne (specID, specName, specIcon, eventTs) si changement pertinent
local function GetPendingSpecChange(intel, last)
	if not intel or not last then
		return
	end

	local pendingID = tonumber(last.pendingSpecID) or 0
	local pendingName = tostring(last.pendingSpecName or "")
	if pendingID <= 0 or pendingName == "" then
		return
	end

	local seenID = tonumber(last.seenSpecID) or 0
	-- Si baseline non initialisée, on la pose sans publier (sécurité)
	if seenID <= 0 then
		last.seenSpecID = pendingID
		last.seenSpecName = pendingName
		last.seenSpecIcon = last.pendingSpecIcon
		last.seenSpecAt = last.pendingSpecAt
		last.pendingSpecID, last.pendingSpecName, last.pendingSpecIcon, last.pendingSpecAt = nil, nil, nil, nil
		return
	end

	-- Pas de changement
	if pendingID == seenID then
		last.pendingSpecID, last.pendingSpecName, last.pendingSpecIcon, last.pendingSpecAt = nil, nil, nil, nil
		return
	end

	local icon = last.pendingSpecIcon
	local ts = tonumber(last.pendingSpecAt) or nil

	return pendingID, pendingName, icon, ts
end

local function PickPhrase(api, phrases, fallback)
	if phrases and api and api.Pick then
		local p = api.Pick(phrases)
		if p and p ~= "" then
			return p
		end
	end
	if phrases and phrases[1] then
		return phrases[1]
	end
	return fallback
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

	local function ProcessSpecNews(g, intel, last, uid, now)
		if not CFG.enabled then
			return
		end

		local specID, specName, specIcon, eventTs = GetPendingSpecChange(intel, last)
		if not specID then
			return
		end

		local playerName = GetPlayerDisplayNameSafe(api, uid)
		local tpl = PickPhrase(api, CFG.news.phrases, CFG.news.message or "%s passe en spécialisation :\n%s.")
		local msg = tpl:format(playerName, specName)

		local icon = specIcon or (CFG.resolve and CFG.resolve.fallbackIcon) or FALLBACK_ICON
		local ts = eventTs or now

		local replaceKey = ("%s%s"):format(CFG.news.replaceKeyPrefix or "spec:", tostring(uid))

		-- (compat) si ton API a une suppression explicite, on la fait avant (sinon replaceKey suffit)
		if api.RemoveNewsByReplaceKey then
			api.RemoveNewsByReplaceKey(g, replaceKey)
		end

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = icon,
			ts = ts,
			replaceable = true,
			replaceKey = replaceKey,
			ttlSeconds = (CFG.news and CFG.news.ttlSeconds) or nil,
			id = ("%s:%s:%s:%s"):format(MODULE_KEY, tostring(uid), tostring(specID), tostring(ts or now)),
			points = POINTS.spec or 3,
		})

		-- Commit: on considère cette spé comme "vue/publiée"
		last.seenSpecID = tonumber(specID) or 0
		last.seenSpecName = tostring(specName or "")
		last.seenSpecIcon = specIcon
		last.seenSpecAt = ts

		-- Clear pending
		last.pendingSpecID, last.pendingSpecName, last.pendingSpecIcon, last.pendingSpecAt = nil, nil, nil, nil
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessSpecNews,
	})
end
