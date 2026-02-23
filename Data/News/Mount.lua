-- ==========================================================
-- Mounts module
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { mount = 1 }

local MODULE_KEY = "mount"
local PIGISTE_KEY = "mounts"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local PHRASES = {
	"%s yeni bir binek elde etti:\n%s.",
	"%s ahirina yeni bir binek ekledi:\n%s.",
	"%s yeni bir binek acti:\n%s.",
	"%s yeni bir at/yoldas sahiplendi:\n%s.",
}

local ICONS = { 132261, 132264, 132267 }

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================
local CFG = {
	enabled = true,

	-- Events WoW écoutés par Pigiste
	pigisteEvents = {
		NEW_MOUNT_ADDED = true,
	},

	-- Déclenchement Journaliste (TickNow(event))
	triggerEvents = {
		"NEW_MOUNT_ADDED",
	},

	windowSeconds = (Data.JournalistAPI and Data.JournalistAPI.WindowSeconds) or (48 * 3600),

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

		OnEvent = function(_, eventName, mountID)
			if not CFG.enabled then
				return
			end
			if not mountID then
				return
			end
			if not (C_MountJournal and C_MountJournal.GetMountInfoByID) then
				return
			end

			local p = pigapi.EnsurePlayer(pigapi.GetMyUID())
			if not p then
				return
			end

			local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
			if not name or name == "" then
				return
			end

			local now = pigapi.Now()

			local l = pigapi.GetModuleLast(p, MODULE_KEY)
			l.mountID = mountID
			l.mountName = name
			l.mountIcon = icon
			l.mountAt = now

			pigapi.IncCounter(p, "mountsNew", 1)
			pigapi.PushActivity(p, PIGISTE_KEY, { ts = now, name = name, icon = icon, id = mountID }, 200)

			TickJournalistSoon(eventName or (CFG.triggerEvents and CFG.triggerEvents[1]))
		end,
	})
end

-- ==========================================================
-- 4) Helpers métier
-- ==========================================================

local function getMountWindow(api, now)
	return now - (CFG.windowSeconds or (api and api.WindowSeconds) or (48 * 3600))
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

	local function ProcessMountNews(g, intel, last, uid, now)
		local list = intel.activity and intel.activity.mounts
		if not list or #list == 0 then
			return
		end

		local since = getMountWindow(api, now)
		local lastTs = tonumber(last.mountsLastTs) or 0
		local maxTs = lastTs

		for i = 1, #list do
			local entry = list[i]
			if type(entry) == "table" and entry.ts and entry.ts > lastTs and entry.ts >= since then
				local name = entry.name
				if name and name ~= "" then
					local msg = (api.Pick(CFG.phrases) or "%s obtient une nouvelle monture :\n%s."):format(
						GetPlayerDisplayNameSafe(api, uid),
						name
					)

					api.AddRawNews(g, {
						text = msg,
						type = MODULE_KEY,
						icon = entry.icon or api.Pick(CFG.icons),
						ts = entry.ts,
						replaceKey = ("mount:%s:%s"):format(tostring(uid), tostring(entry.ts)),
						removedAt = api.GetRemovedAt(MODULE_KEY, entry.ts),
						points = POINTS.mount or 1,
					})

					if entry.ts > maxTs then
						maxTs = entry.ts
					end
				end
			end
		end

		if maxTs > lastTs then
			last.mountsLastTs = maxTs
		end
	end

	registry.Register(MODULE_KEY, ProcessMountNews)
end
