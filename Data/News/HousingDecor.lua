-- ==========================================================
-- Housing decor collection module
-- Trigger: HOUSE_DECOR_ADDED_TO_CHEST
-- Info source: NEW_HOUSING_ITEM_ACQUIRED
-- ==========================================================

local ADDON, ns = ...

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { housingdecor = 1 }

local MODULE_KEY = "housingdecor"
local PIGISTE_KEY = "housingdecor"

local PHRASES_ONE_WITH_LAST = {
	"%s a récupéré un objet de logis : %s.",
	"%s ajoute un premier objet de logis au coffre : %s.",
	"%s inaugure la collection du logis avec : %s.",
	"%s met la main sur un nouvel objet de logis : %s.",
	"%s enrichit son logis avec un nouvel élément : %s.",
	"%s commence l’aménagement du logis avec : %s.",
	"%s obtient une nouvelle pièce pour son intérieur : %s.",
}

local PHRASES_WITHOUT_LAST = {
	"%s a récupéré %d objets de logis.",
	"%s a ajouté %d objets au coffre du logis.",
	"%s continue de remplir le coffre du logis avec %d objets.",
	"%s complète les réserves du logis avec %d objets.",
	"%s enrichit son intérieur de %d objets de logis.",
	"%s fait progresser la collection du logis de %d objets.",
	"%s met de côté %d nouveaux objets pour le logis.",
	"%s ajoute %d pièces supplémentaires au coffre du logis.",
}

local PHRASES_ONE_NO_LAST = {
	"%s a récupéré un objet de logis.",
	"%s a ajouté un objet au coffre du logis.",
	"%s met la main sur un nouvel objet pour le logis.",
	"%s enrichit son intérieur d’un objet de logis.",
	"%s ajoute une nouvelle pièce à son logis.",
}

local PHRASES_ONE_NO_LAST = {
	"%s a récupéré un objet de logis.",
	"%s a ajouté un objet au coffre du logis.",
	"%s met la main sur un nouvel objet pour le logis.",
	"%s enrichit son intérieur d’un objet de logis.",
	"%s ajoute une nouvelle pièce à son logis.",
}

local CFG = {
	enabled = true,
	triggerEvent = "HOUSE_DECOR_ADDED_TO_CHEST",
	pigisteEvents = {
		HOUSE_DECOR_ADDED_TO_CHEST = true,
		NEW_HOUSING_ITEM_ACQUIRED = true,
	},
	triggerEvents = {
		"HOUSE_DECOR_ADDED_TO_CHEST",
	},
	infoEvent = "NEW_HOUSING_ITEM_ACQUIRED",
	infoMaxAgeSeconds = 10,
	windowSeconds = (Data.JournalistAPI and Data.JournalistAPI.WindowSeconds) or (48 * 3600),
	phrasesWithLast = PHRASES_WITH_LAST,
	phrasesWithoutLast = PHRASES_WITHOUT_LAST,
	phrasesOneWithLast = PHRASES_ONE_WITH_LAST,
	phrasesOneNoLast = PHRASES_ONE_NO_LAST,
}

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

	local function ResolveDecorItemFromArgs(...)
		-- Event attendu:
		-- Arg1 = itemID (important), Arg2 = itemName, Arg3 = iconFileID (souvent string)
		local rawId = select(1, ...)
		local rawName = select(2, ...)
		local rawIcon = select(3, ...)

		local itemID = tonumber(rawId) or 0
		local itemName = (type(rawName) == "string" and rawName ~= "") and rawName or nil
		local icon = tonumber(rawIcon) or 0

		if itemID <= 0 then
			-- Fallback de sécurité si la signature change.
			local argsCount = select("#", ...)
			for i = 1, argsCount do
				local v = select(i, ...)
				local n = tonumber(v)
				if n and n > 0 then
					itemID = n
					break
				end
			end
		end

		if itemID > 0 and (not itemName or icon <= 0) then
			if GetItemInfoInstant then
				local _, _, _, _, iconInstant = GetItemInfoInstant(itemID)
				if icon <= 0 then
					icon = tonumber(iconInstant) or 0
				end
			end
			if pigapi.GetItemInfoSafe then
				local nameSafe, _, iconSafe = pigapi.GetItemInfoSafe(nil, itemID)
				if (not itemName or itemName == "") and nameSafe and nameSafe ~= "" then
					itemName = nameSafe
				end
				if icon <= 0 then
					icon = tonumber(iconSafe) or 0
				end
			end
		end

		return itemID, itemName, icon
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,
		OnEvent = function(_, eventName, ...)
			if not CFG.enabled then
				return
			end

			local p = pigapi.EnsurePlayer(pigapi.GetMyUID())
			if not p then
				return
			end

			local now = pigapi.Now()
			local l = pigapi.GetModuleLast(p, MODULE_KEY)
			local itemID, itemName, icon = ResolveDecorItemFromArgs(...)

			if eventName == CFG.infoEvent then
				-- On ne publie rien ici: on stocke les infos pour le vrai trigger.
				l.pendingItemID = itemID
				l.pendingItemName = itemName
				l.pendingItemIcon = icon
				l.pendingAt = now
				p.updatedAt = now
				return
			end

			if eventName ~= CFG.triggerEvent then
				return
			end

			local pendingAt = tonumber(l.pendingAt or 0) or 0
			local maxAge = tonumber(CFG.infoMaxAgeSeconds or 10) or 10
			if pendingAt > 0 and (now - pendingAt) <= maxAge then
				-- NEW_HOUSING_ITEM_ACQUIRED est la source d'info prioritaire.
				if (tonumber(l.pendingItemID or 0) or 0) > 0 then
					itemID = tonumber(l.pendingItemID) or 0
				end
				if l.pendingItemName and l.pendingItemName ~= "" then
					itemName = l.pendingItemName
				end
				if (tonumber(l.pendingItemIcon or 0) or 0) > 0 then
					icon = tonumber(l.pendingItemIcon) or 0
				end
			end

			l.count = (tonumber(l.count) or 0) + 1
			l.lastAt = now
			l.lastItemID = itemID
			l.lastItemName = itemName
			l.lastItemIcon = icon
			l.pendingAt = 0
			l.pendingItemID = 0
			l.pendingItemName = nil
			l.pendingItemIcon = 0

			pigapi.IncCounter(p, "housingDecorAdded", 1)
			pigapi.PushActivity(p, PIGISTE_KEY, {
				ts = now,
				itemID = itemID,
				name = itemName,
				icon = icon,
			}, 200)

			p.updatedAt = now
			TickJournalistSoon()
		end,
	})
end

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

	local function ProcessHousingDecorNews(g, intel, last, uid, now)
		local list = intel.activity and intel.activity.housingdecor
		if not list or #list == 0 then
			return
		end

		local since = now - (CFG.windowSeconds or (48 * 3600))
		local count = 0
		local latestTs = 0
		local latestEntry = nil
		for i = 1, #list do
			local entry = list[i]
			if type(entry) == "table" and entry.ts and entry.ts >= since then
				count = count + 1
				if entry.ts >= latestTs then
					latestTs = entry.ts
					latestEntry = entry
				end
			end
		end

		if count <= 0 or not latestEntry then
			return
		end

		local prevCount = tonumber(last.lastCount or 0) or 0
		local prevLatestTs = tonumber(last.lastLatestTs or 0) or 0
		if count == prevCount and latestTs == prevLatestTs then
			return
		end

		local playerName = GetPlayerDisplayNameSafe(api, uid)
		local itemName = tostring(latestEntry.name or "")
		local msg
		if count <= 1 then
			if itemName ~= "" then
				msg = (api.Pick(CFG.phrasesOneWithLast) or "%s a récupéré un objet de logis : %s."):format(
					playerName,
					itemName
				)
			else
				msg = (api.Pick(CFG.phrasesOneNoLast) or "%s a récupéré un objet de logis."):format(playerName)
			end
		else
			if itemName ~= "" then
				msg = (
					api.Pick(CFG.phrasesWithLast) or "%s a récupéré %d objets de logis, dont le dernier était : %s."
				):format(playerName, count, itemName)
			else
				msg = (api.Pick(CFG.phrasesWithoutLast) or "%s a récupéré %d objets de logis."):format(
					playerName,
					count
				)
			end
		end

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = ((tonumber(latestEntry.icon or 0) or 0) > 0) and (tonumber(latestEntry.icon or 0) or 0) or nil,
			ts = latestTs,
			replaceKey = ("housingdecor:%s"):format(tostring(uid or "player")),
			removedAt = api.GetRemovedAt(MODULE_KEY, latestTs),
			points = POINTS.housingdecor or 1,
		})

		last.lastCount = count
		last.lastLatestTs = latestTs
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessHousingDecorNews,
	})
end
