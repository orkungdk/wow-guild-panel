-- ==========================================================
-- Toys module
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { toy = 1 }

local MODULE_KEY = "toy"
local PIGISTE_KEY = "toys"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local WINDOW_SECONDS = (Data.JournalistAPI and Data.JournalistAPI.WindowSeconds) or (48 * 3600)

local PHRASES = {
	"%s 48 saatte koleksiyonuna %d oyuncak ekledi, sonuncu:\n%s.",
	"%s 48 saatte %d oyuncak biriktirdi (bunlardan biri:\n%s).",
	"%s 48 saatte %d oyuncak acti, sonuncu:\n%s.",
	"%s 48 saatte oyuncak kutusunu %d yeni parca ile doldurdu, sonuncu:\n%s.",
}

local ICONS = { 133859, 133860, 133861 }

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================
local CFG = {
	enabled = true,

	-- Events WoW écoutés par Pigiste
	pigisteEvents = {
		NEW_TOY_ADDED = true,
	},

	-- Déclenchement Journaliste (TickNow(event))
	triggerEvents = {
		"NEW_TOY_ADDED",
	},

	windowSeconds = WINDOW_SECONDS,
	phrases = PHRASES,
	icons = ICONS,
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

	-- Déclenchement "event-driven" du Journaliste (coalescé)
	local pendingTick = false
	local pendingEvent = nil

	local function TickJournalistSoon(eventName)
		if pendingTick then
			pendingEvent = pendingEvent or eventName
			return
		end

		pendingTick = true
		pendingEvent = eventName

		local function doTick()
			pendingTick = false
			local ev = pendingEvent
			pendingEvent = nil

			local Journalist = (Data and Data.Journalist) or (ns and ns.Data and ns.Data.Journalist) or nil
			if Journalist and type(Journalist.TickNow) == "function" and ev then
				Journalist.TickNow(ev)
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

		OnEvent = function(_, eventName, toyID)
			if not CFG.enabled then
				return
			end
			if not toyID then
				return
			end
			if not (C_ToyBox and C_ToyBox.GetToyInfo) then
				return
			end

			local p = pigapi.EnsurePlayer(pigapi.GetMyUID())
			if not p then
				return
			end

			local _, name, icon = C_ToyBox.GetToyInfo(toyID)
			if not name or name == "" then
				return
			end

			local quality
			if GetItemInfo then
				quality = select(3, GetItemInfo(toyID))
			end

			local l = pigapi.GetModuleLast(p, MODULE_KEY)
			l.toyID = toyID
			l.toyName = name
			l.toyIcon = icon
			l.toyAt = pigapi.Now()

			pigapi.IncCounter(p, "toysNew", 1)
			pigapi.PushActivity(p, PIGISTE_KEY, {
				ts = l.toyAt,
				name = name,
				icon = icon,
				id = toyID,
				quality = quality,
			}, 200)

			TickJournalistSoon(eventName or (CFG.triggerEvents and CFG.triggerEvents[1]))
		end,
	})
end

-- ==========================================================
-- 4) Helpers métier
-- ==========================================================

local function computeToyWindow(intel, last, now, api)
	local list = intel.activity and intel.activity.toys
	if not list then
		return
	end

	local tailTs = api.ListTailTs(list)
	local prevTail = tonumber(last.toysTailTs) or 0
	if tailTs <= prevTail then
		return
	end

	last.toysTailTs = tailTs

	local since = now - (CFG.windowSeconds or WINDOW_SECONDS)
	local count, lastEntry = api.CountSince(list, since)
	if not count or count <= 0 then
		return
	end

	local prev = tonumber(last.toysWindowCount) or 0
	if count == prev then
		return
	end
	if count == 1 and prev > 0 then
		return
	end

	return count, lastEntry
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

	local function ProcessToyNews(g, intel, last, uid, now)
		local count, lastEntry = computeToyWindow(intel, last, now, api)
		if not count or not lastEntry then
			return
		end

		local name = lastEntry.name
		if not name or name == "" then
			return
		end

		api.RemoveNewsByReplaceKey(g, "toy48")

		local msg
		if count == 1 then
			msg = ("%s obtient un nouveau jouet :\n%s."):format(GetPlayerDisplayNameSafe(api, uid), name)
		else
			msg = (api.Pick(CFG.phrases) or "%s ajoute %d jouet(s) en 48h, dernier :\n%s."):format(
				GetPlayerDisplayNameSafe(api, uid),
				count,
				name
			)
		end

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = lastEntry.icon or api.Pick(CFG.icons),
			ts = now,
			replaceKey = "toy48:" .. tostring(uid),
			removedAt = api.GetRemovedAt(MODULE_KEY, now),
			points = POINTS.toy or 1,
		})

		last.toysWindowCount = count
	end

	registry.Register(MODULE_KEY, ProcessToyNews)
end
