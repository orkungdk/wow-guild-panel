-- ==========================================================
-- Epic Collectibles module (Transmog only)
-- News agrégée + purge 48h + icône aléatoire parmi les loots
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { transmog = 1 }

local MODULE_KEY = "transmog"
local PIGISTE_KEY = "transmog"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local FALLBACK_ICONS = { 134400, 132761, 133135 }

local WINDOW_SECONDS = (Data.JournalistAPI and Data.JournalistAPI.WindowSeconds) or (48 * 3600)

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================

local CFG = {
	enabled = true,

	-- Events WoW écoutés par Pigiste
	pigisteEvents = {
		CHAT_MSG_LOOT = true,
		TRANSMOG_COLLECTION_SOURCE_ADDED = true, -- arg1 = sourceID
		TRANSMOG_COSMETIC_COLLECTION_SOURCE_ADDED = true, -- arg1 = sourceID
		TRANSMOG_COLLECTION_UPDATED = true, -- pas toujours de sourceID
	},

	-- Déclenchement Journaliste (TickNow(event))
	triggerEvents = {
		"TRANSMOG_COLLECTION_SOURCE_ADDED",
		"TRANSMOG_COSMETIC_COLLECTION_SOURCE_ADDED",
		"TRANSMOG_COLLECTION_UPDATED",
	},

	window = {
		seconds = WINDOW_SECONDS,
	},

	store = {
		maxEntries = 120,
	},

	-- News remplaçable (id stable)
	each = {
		ttlSeconds = nil,
		idPrefix = "transmog:",
		replaceable = true,
	},

	-- Filtre qualité :
	-- garde 4 (= épique) par défaut, mets 0 si tu veux TOUT compter
	filter = {
		minQuality = 0,
		-- si qualité inconnue (cache pas prêt), on ignore (false) ou on compte quand même (true)
		treatUnknownQualityAsOk = false,
	},

	phrases = {
		"%s 48 saatte %d gorunum%s acti, en yenisi:\n%s.",
		"Terziler fisildiyor: %s 48 saatte %d gorunum%s topladi, son parca:\n%s.",
		"%s son iki gunde gardrobunu genisletti: %d gorunum%s, bunlardan biri:\n%s.",
		"Kumas masasinda %s icin iki gunde %d gorunum%s eklendiginden bahsediliyor. En cok konusulan:\n%s.",
		"%s 48 saatte %d gorunum%s ile kafalari cevirdi, en son eklenen:\n%s.",
		"Igneler bos durmadi: %s 48 saatte %d gorunum%s kazandi, ozet:\n%s.",
		"%s iki gunde dolabina %d gorunum%s daha ekledi. Bakislar su parca uzerinde:\n%s.",
		"Arka odada %s icin son zamanlarda %d gorunum%s topladigi konusuluyor. En cok begenilen:\n%s.",
		"%s 48 saatte modaya %d gorunum%s soktu, zirvede duran:\n%s.",
		"Meyhane aynalari dogruluyor: %s 48 saatte %d gorunum%s kazandi. En cok konusulan:\n%s.",
		"%s iki gunde destanina %d gorunum%s daha dikti, bunlardan biri:\n%s.",
		"Tezgahta da podyumda da %s icin 48 saatte %d gorunum%s kaptigi biliniyor. En son parca:\n%s.",
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
	local pendingEvent = nil
	local recentSources = {}

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

	-- ----------------------------------------------------------
	-- Helpers "collecte"
	-- ----------------------------------------------------------
	local function GetItemInfoSafe(itemID)
		if not itemID or itemID <= 0 or not GetItemInfo then
			return nil, nil, nil, nil
		end
		local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
		return name, link, quality, icon
	end

	local function GetTransmogSourceInfoSafe(sourceID)
		if not sourceID or sourceID <= 0 then
			return nil
		end
		if not C_TransmogCollection or not C_TransmogCollection.GetSourceInfo then
			return nil
		end
		local ok, info = pcall(C_TransmogCollection.GetSourceInfo, sourceID)
		if not ok then
			return nil
		end
		return info
	end

	local function ResolveSourceFromItem(itemID, itemLink)
		if not C_TransmogCollection or not C_TransmogCollection.GetItemInfo then
			return nil
		end
		local function try(arg)
			if not arg then
				return nil
			end
			local ok, a, b = pcall(C_TransmogCollection.GetItemInfo, arg)
			if not ok then
				return nil
			end
			if type(a) == "table" then
				local src = tonumber(a.sourceID or a.sourceId or a.source) or 0
				local app = tonumber(a.appearanceID or a.appearanceId) or 0
				if src > 0 then
					return src, app
				end
			end
			local app = tonumber(a) or 0
			local src = tonumber(b) or 0
			if src > 0 then
				return src, app
			end
			return nil
		end
		return try(itemLink) or try(itemID)
	end

	local function IsSourceCollected(sourceID)
		if not sourceID or sourceID <= 0 or not C_TransmogCollection or not C_TransmogCollection.GetSourceInfo then
			return nil
		end
		local ok, info = pcall(C_TransmogCollection.GetSourceInfo, sourceID)
		if not ok or type(info) ~= "table" then
			return nil
		end
		if info.isCollected ~= nil then
			return info.isCollected and true or false
		end
		if info.collected ~= nil then
			return info.collected and true or false
		end
		return nil
	end

	local function PruneByWindow(list, cutoff)
		if not list or #list == 0 then
			return false
		end
		local w = 1
		for i = 1, #list do
			local e = list[i]
			local ts = tonumber(e and e.ts) or 0
			if ts >= cutoff then
				list[w] = e
				w = w + 1
			end
		end
		for i = w, #list do
			list[i] = nil
		end
		return true
	end

	local function PushTransmog(p, sourceID, now)
		if not p then
			return false
		end

		p.epiccollectibles = p.epiccollectibles or {}
		p.epiccollectibles.list = p.epiccollectibles.list or {}

		local entry = {
			kind = "transmog",
			ref = tonumber(sourceID) or 0,
			ts = tonumber(now) or pigAPI.Now(),

			itemID = nil,
			name = "",
			quality = 0,
			icon = nil,
		}

		-- best effort : resolve à la collecte
		local info = GetTransmogSourceInfoSafe(entry.ref)
		if info then
			entry.itemID = tonumber(info.itemID) or nil
			if info.name and info.name ~= "" then
				entry.name = tostring(info.name)
			end
			if info.quality then
				entry.quality = tonumber(info.quality) or 0
			end

			if entry.itemID then
				local _, _, q, ic = GetItemInfoSafe(entry.itemID)
				if (not entry.quality or entry.quality == 0) and q then
					entry.quality = tonumber(q) or 0
				end
				if ic then
					entry.icon = ic
				end
			end
		end

		pigAPI.PushLimited(p.epiccollectibles.list, entry, (CFG.store and CFG.store.maxEntries) or 120)
		pigAPI.IncCounter(p, "epiccollectibles_transmog_total", 1)

		-- purge immédiate 48h
		local cutoff = (entry.ts or now) - (CFG.window and CFG.window.seconds or WINDOW_SECONDS)
		PruneByWindow(p.epiccollectibles.list, cutoff)

		local last = pigAPI.GetModuleLast(p, MODULE_KEY)
		last.collectibleAt = entry.ts
		p.updatedAt = entry.ts

		return true
	end

	local function MarkRecentSource(sourceID, now)
		if sourceID and sourceID > 0 then
			recentSources[sourceID] = tonumber(now) or pigAPI.Now()
		end
	end

	local function IsRecentSource(sourceID, now)
		if not sourceID or sourceID <= 0 then
			return false
		end
		local t = recentSources[sourceID]
		if not t then
			return false
		end
		return (tonumber(now) or pigAPI.Now()) - t < 6
	end

	local function ScheduleLootTransmogCheck(p, itemID, itemLink)
		if not p or not itemID or itemID <= 0 then
			return
		end
		local state = {
			itemID = itemID,
			link = itemLink,
			attempts = 0,
			sourceID = nil,
			wasCollected = nil,
		}

		local function step()
			state.attempts = state.attempts + 1
			if not state.sourceID then
				state.sourceID = ResolveSourceFromItem(state.itemID, state.link)
			end
			local sourceID = state.sourceID
			if sourceID and sourceID > 0 then
				local collected = IsSourceCollected(sourceID)
				if state.wasCollected == nil and collected ~= nil then
					state.wasCollected = collected and true or false
				elseif state.wasCollected == false and collected == true then
					local now = pigAPI.Now()
					if not IsRecentSource(sourceID, now) then
						local pushed = PushTransmog(p, sourceID, now)
						if pushed then
							MarkRecentSource(sourceID, now)
							TickJournalistSoon("TRANSMOG_COLLECTION_SOURCE_ADDED")
						end
					end
					return
				end
			end

			if state.attempts < 4 and C_Timer and C_Timer.After then
				C_Timer.After(0.4, step)
			end
		end

		if C_Timer and C_Timer.After then
			C_Timer.After(0.1, step)
		else
			step()
		end
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		OnEvent = function(_, eventName, arg1)
			if not CFG.enabled then
				return
			end

			if eventName == "CHAT_MSG_LOOT" then
				if not (pigAPI.IsSelfLootMessage and pigAPI.ExtractItemLink) then
					return
				end
				local msg = tostring(arg1 or "")
				if not pigAPI.IsSelfLootMessage(msg) then
					return
				end
				local itemLink = pigAPI.ExtractItemLink(msg)
				if not itemLink then
					return
				end
				local itemID = tonumber(itemLink:match("item:(%d+)")) or 0
				if itemID <= 0 then
					return
				end
				local uid = pigAPI.GetMyUID()
				local p = pigAPI.EnsurePlayer(uid)
				if not p then
					return
				end
				ScheduleLootTransmogCheck(p, itemID, itemLink)
				return
			end

			if
				eventName ~= "TRANSMOG_COLLECTION_SOURCE_ADDED"
				and eventName ~= "TRANSMOG_COSMETIC_COLLECTION_SOURCE_ADDED"
				and eventName ~= "TRANSMOG_COLLECTION_UPDATED"
			then
				return
			end

			local uid = pigAPI.GetMyUID()
			local p = pigAPI.EnsurePlayer(uid)
			if not p then
				return
			end

			local now = pigAPI.Now()
			if eventName == "TRANSMOG_COLLECTION_UPDATED" then
				-- Pas toujours de sourceID : on force juste un tick pour rafraîchir.
				TickJournalistSoon(eventName)
				return
			end

			local sourceID = tonumber(arg1) or 0
			if sourceID <= 0 then
				return
			end

			if IsRecentSource(sourceID, now) then
				return
			end

			local pushed = PushTransmog(p, sourceID, now)
			if pushed then
				MarkRecentSource(sourceID, now)
				TickJournalistSoon(eventName)
			end
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

local function GetItemInfoSafe(itemID)
	if not itemID or itemID <= 0 or not GetItemInfo then
		return nil, nil, nil, nil
	end
	local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
	return name, link, quality, icon
end

local function GetTransmogSourceInfoSafe(sourceID)
	if not sourceID or sourceID <= 0 then
		return nil
	end
	if not C_TransmogCollection or not C_TransmogCollection.GetSourceInfo then
		return nil
	end
	local ok, info = pcall(C_TransmogCollection.GetSourceInfo, sourceID)
	if not ok then
		return nil
	end
	return info
end

local function PruneByWindow(list, cutoff)
	if not list or #list == 0 then
		return false
	end
	local w = 1
	for i = 1, #list do
		local e = list[i]
		local ts = tonumber(e and e.ts) or 0
		if ts >= cutoff then
			list[w] = e
			w = w + 1
		end
	end
	for i = w, #list do
		list[i] = nil
	end
	return true
end

local function IsQualityOk(q)
	local minQ = (CFG.filter and CFG.filter.minQuality) or 0
	if minQ <= 0 then
		return true
	end
	if not q or q == 0 then
		return (CFG.filter and CFG.filter.treatUnknownQualityAsOk) or false
	end
	return tonumber(q) >= minQ
end

local function ResolveEntryDisplayIconQuality(api, entry)
	if type(entry) ~= "table" then
		return nil, nil, nil
	end

	local icon = entry.icon
	local quality = tonumber(entry.quality) or 0
	local display = nil

	local sourceID = tonumber(entry.ref) or 0
	local info = GetTransmogSourceInfoSafe(sourceID)
	if info then
		local itemID = tonumber(info.itemID) or tonumber(entry.itemID) or 0
		local name = (info.name and info.name ~= "" and tostring(info.name)) or (entry.name ~= "" and entry.name) or nil
		if (not quality or quality == 0) and info.quality then
			quality = tonumber(info.quality) or quality
		end

		if itemID > 0 then
			local iName, link, iq, ic = GetItemInfoSafe(itemID)
			display = link or iName or name or tostring(sourceID)
			if (not icon or icon == 0) and ic then
				icon = ic
			end
			if (not quality or quality == 0) and iq then
				quality = tonumber(iq) or quality
			end
		else
			display = name or tostring(sourceID)
		end
	else
		-- fallback minimal
		display = (entry.name ~= "" and entry.name) or tostring(sourceID)
	end

	if (not icon or icon == 0) and api.Pick then
		icon = api.Pick(FALLBACK_ICONS)
	end

	return display, icon, quality
end

local function Plural(n)
	return (tonumber(n) or 0) > 1 and "s" or ""
end

-- ==========================================================
-- 5) News processor (1 news remplaçable)
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

	local function ProcessTransmogWindowNews(g, intel, last, uid, now)
		local list = intel.epiccollectibles and intel.epiccollectibles.list
		if not list then
			return
		end

		-- purge DB : tout ce qui sort de la fenêtre disparaît
		local cutoff = now - (CFG.window and CFG.window.seconds or WINDOW_SECONDS)
		PruneByWindow(list, cutoff)

		local tailTs = api.ListTailTs and api.ListTailTs(list) or 0

		-- agrégation : compte + icônes + plus récente
		local count = 0
		local candidates = {}
		local latestTs = 0

		for i = 1, #list do
			local e = list[i]
			if type(e) == "table" and tostring(e.kind or "") == "transmog" then
				local ts = tonumber(e.ts) or 0
				if ts >= cutoff then
					if ts > latestTs then
						latestTs = ts
					end
					local display, icon, q = ResolveEntryDisplayIconQuality(api, e)
					if display and IsQualityOk(q) then
						count = count + 1
						candidates[#candidates + 1] = { display = display, icon = icon }
					end
				end
			end
		end

		local newsId = ("%s%s"):format((CFG.each and CFG.each.idPrefix) or "transmog:", tostring(uid))

		-- rien à afficher => tenter de supprimer la news existante
		if count <= 0 then
			if api.RemoveById then
				api.RemoveById(g, newsId)
			elseif api.AddRawNews and api.GetRemovedAt then
				api.AddRawNews(g, {
					id = newsId,
					type = MODULE_KEY,
					removedAt = now,
				})
			end
			return
		end

		local prevTail = tonumber(last.transmogTailTs) or 0
		if tailTs <= prevTail then
			return
		end
		last.transmogTailTs = tailTs

		local playerName = GetPlayerDisplayNameSafe(api, uid)
		local tpl = (api.Pick and api.Pick(CFG.phrases)) or CFG.phrases[1]
		local pick = nil
		if #candidates > 0 then
			pick = (api.Pick and api.Pick(candidates)) or candidates[math.random(1, #candidates)]
		end
		local pickedDisplay = (pick and pick.display) or "une nouvelle apparence"

		local msg = tpl:format(playerName, count, Plural(count), pickedDisplay)

		local icon = (pick and pick.icon and pick.icon ~= 0 and pick.icon)
			or ((api.Pick and api.Pick(FALLBACK_ICONS)) or FALLBACK_ICONS[1])

		local newsTs = (latestTs > 0 and latestTs) or now

		local payload = {
			text = msg,
			type = MODULE_KEY,
			icon = icon,
			ts = newsTs,

			id = newsId,
			replaceable = (CFG.each and CFG.each.replaceable) ~= false,
			replaceKey = newsId,
			ttlSeconds = CFG.each and CFG.each.ttlSeconds or nil,
			points = POINTS.transmog or 1,
		}

		api.AddRawNews(g, payload)
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessTransmogWindowNews,
	})
end
