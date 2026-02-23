-- ==========================================================
-- Herb harvest module (hors combat uniquement)
-- ==========================================================

local ADDON, ns = ...

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { herbharvest = 1 }

local MODULE_KEY = "herbharvest"
local PIGISTE_KEY = "herbharvest"

local PHRASES = {
	"%s cueille %d plantes avec soin.",
	"%s remplit sa besace de %d plantes fraîches.",
	"%s poursuit la cueillette et récolte %d plantes.",
	"%s herborise calmement et récupère %d plantes.",
	"%s entretient ses réserves avec %d plantes supplémentaires.",
	"%s fait le tour des herbes et en cueille %d.",
	"%s revient des champs avec %d plantes.",
	"%s ajoute %d plantes à son stock d’alchimie.",

	"%s s’attarde dans les hautes herbes et cueille %d plantes.",
	"%s récolte %d plantes en suivant les senteurs.",
	"%s complète sa besace avec %d plantes de plus.",
	"%s glisse %d plantes fraîches entre ses fioles.",
	"%s prélève %d plantes choisies avec attention.",
	"%s enrichit ses réserves naturelles de %d plantes.",
	"%s ramasse %d plantes encore couvertes de rosée.",
	"%s termine sa tournée d’herbes avec %d plantes.",
	"%s prend le temps et cueille %d plantes supplémentaires.",
	"%s revient au calme avec %d plantes en poche.",
}

local ICONS = {
	134183, -- inv_misc_herb_11
	134184, -- inv_misc_herb_12
	237301, -- herb style fallback
}

local CFG = {
	enabled = true,
	spellIDs = {
		2366,
		265821,
		441327,
		28695,
		2368,
		265835,
		265829,
		3570,
		366252,
		74519,
		265825,
		11993,
		265819,
		50300,
		110413,
		309780,
		471009,
		195114,
		265823,
		158745,
		265827,
		265831,
		265834,
	},
	triggerEvent = "HERB_HARVEST_UPDATE",
	lootLinkWindowSeconds = 10,
	initiativeGuardSpellID = 2366,
	initiativeGuardWindowSeconds = 0.35,
	pigisteEvents = {
		UNIT_SPELLCAST_SUCCEEDED = true,
		CHAT_MSG_LOOT = true,
		NEIGHBORHOOD_INITIATIVE_UPDATED = true,
	},
	triggerEvents = {
		"HERB_HARVEST_UPDATE",
	},
	replaceKeyPrefix = "herbharvest:",
	phrases = PHRASES,
	icons = ICONS,
}

do
	local Pigiste = Data.Pigiste
	local pigapi = Data.PigisteAPI
	if not Pigiste or not pigapi then
		return
	end

	local pendingTick = false
	local trackedSpellIDs = {}
	do
		local src = CFG.spellIDs
		if type(src) ~= "table" or #src == 0 then
			src = { tonumber(CFG.spellID) or 0 }
		end
		for i = 1, #src do
			local n = tonumber(src[i]) or 0
			if n > 0 then
				trackedSpellIDs[n] = true
			end
		end
	end

	local function FindTrackedSpellIDFromArgs(...)
		for i = 1, select("#", ...) do
			local n = tonumber((select(i, ...)))
			if n and trackedSpellIDs[n] then
				return n
			end
		end
		return nil
	end

	local function SelectBestLootFromMessage(message)
		if type(message) ~= "string" or message == "" then
			return nil, 0, -1
		end

		local bestLink, bestIcon, bestQuality = nil, 0, -1
		for itemLink in message:gmatch("(|Hitem:[^|]+|h%[[^%]]+%]|h)") do
			local itemID = tonumber(itemLink:match("item:(%d+)")) or 0
			local quality = -1
			local icon = 0

			if pigapi.GetItemInfoSafe then
				local _, q, i = pigapi.GetItemInfoSafe(itemLink, itemID)
				quality = tonumber(q) or -1
				icon = tonumber(i) or 0
			end
			if icon <= 0 and GetItemInfoInstant then
				local _, _, _, _, iconInstant = GetItemInfoInstant(itemLink or itemID)
				icon = tonumber(iconInstant) or 0
			end

			if quality > bestQuality then
				bestQuality = quality
				bestIcon = icon
				bestLink = itemLink
			end
		end

		return bestLink, bestIcon, bestQuality
	end

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

	local function ClearPendingHerbCast(lastState)
		lastState.pendingHerbSpellID = 0
		lastState.pendingHerbCastAt = 0
		lastState.pendingHerbSeq = (tonumber(lastState.pendingHerbSeq) or 0) + 1
	end

	local function CommitHerbCast(p, l, spellID, now)
		l.count = (tonumber(l.count) or 0) + 1
		l.lastSpellAt = now
		l.lastSpellID = spellID
		l.awaitingLootAt = now

		pigapi.IncCounter(p, "herbHarvest", 1)
		pigapi.PushActivity(p, PIGISTE_KEY, { ts = now, spellID = spellID }, 200)
		p.updatedAt = now
		TickJournalistSoon()
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

			if eventName == "UNIT_SPELLCAST_SUCCEEDED" then
				local unitTarget = select(1, ...)
				if unitTarget ~= "player" then
					return
				end

				local spellID = FindTrackedSpellIDFromArgs(...)
				if not spellID then
					return
				end
				if InCombatLockdown and InCombatLockdown() then
					return
				end

				local guardedSpellID = tonumber(CFG.initiativeGuardSpellID or 2366) or 2366
				local guardWindow = tonumber(CFG.initiativeGuardWindowSeconds or 0.35) or 0.35
				if spellID == guardedSpellID and guardWindow > 0 then
					local seq = (tonumber(l.pendingHerbSeq) or 0) + 1
					l.pendingHerbSeq = seq
					l.pendingHerbSpellID = spellID
					l.pendingHerbCastAt = now

					if C_Timer and C_Timer.After then
						C_Timer.After(guardWindow, function()
							if (tonumber(l.pendingHerbSeq) or 0) ~= seq then
								return
							end

							local pendingSpellID = tonumber(l.pendingHerbSpellID or 0) or 0
							local pendingCastAt = tonumber(l.pendingHerbCastAt or 0) or 0
							local initiativeAt = tonumber(l.lastInitiativeEventAt or 0) or 0

							ClearPendingHerbCast(l)

							if pendingSpellID <= 0 or pendingCastAt <= 0 then
								return
							end
							if initiativeAt >= pendingCastAt and (initiativeAt - pendingCastAt) <= guardWindow then
								return
							end

							CommitHerbCast(p, l, pendingSpellID, pigapi.Now())
						end)
					else
						CommitHerbCast(p, l, spellID, now)
					end
					return
				end

				CommitHerbCast(p, l, spellID, now)
				return
			end

			if eventName == "NEIGHBORHOOD_INITIATIVE_UPDATED" then
				l.lastInitiativeEventAt = now
				local guardWindow = tonumber(CFG.initiativeGuardWindowSeconds or 0.35) or 0.35
				local pendingCastAt = tonumber(l.pendingHerbCastAt or 0) or 0
				if pendingCastAt > 0 and (now - pendingCastAt) <= guardWindow then
					ClearPendingHerbCast(l)
				end
				return
			end

			if eventName == "CHAT_MSG_LOOT" then
				local message = select(1, ...)
				if not (message and pigapi.IsSelfLootMessage and pigapi.IsSelfLootMessage(message)) then
					return
				end
				local castTs = tonumber(l.awaitingLootAt or 0) or 0
				local windowSec = tonumber(CFG.lootLinkWindowSeconds or 10) or 10
				if castTs <= 0 or (now - castTs) > windowSec then
					return
				end

				local itemLink, icon = SelectBestLootFromMessage(message)
				if not itemLink then
					return
				end
				local itemID = tonumber(itemLink:match("item:(%d+)")) or 0

				if icon and icon > 0 then
					l.lastLootIcon = icon
					l.lastLootItemID = itemID
					l.lastLootAt = now
					p.updatedAt = now
					TickJournalistSoon()
				end
			end
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

	local function ProcessHerbHarvestNews(g, intel, last, uid, now)
		local moduleState = intel and intel.last or nil
		local count = tonumber(moduleState and moduleState.count or 0) or 0
		if count <= 0 then
			return
		end

		local posted = tonumber(last.postedCount or 0) or 0
		local iconNow = tonumber(moduleState and moduleState.lastLootIcon or 0) or 0
		local iconPosted = tonumber(last.postedIcon or 0) or 0
		local shouldRefreshIcon = (count == posted) and (iconNow > 0) and (iconNow ~= iconPosted)
		if count < posted or (count == posted and not shouldRefreshIcon) then
			return
		end

		local replaceKey = (CFG.replaceKeyPrefix or "herbharvest:") .. tostring(uid or "player")
		local msg = (api.Pick(CFG.phrases) or "%s a récolté %d plante(s)."):format(
			GetPlayerDisplayNameSafe(api, uid),
			count
		)

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = (iconNow > 0 and iconNow) or api.Pick(CFG.icons) or 134183,
			ts = now,
			replaceKey = replaceKey,
			removedAt = api.GetRemovedAt(MODULE_KEY, now, nil, replaceKey),
			points = POINTS.herbharvest or 1,
		})

		last.postedCount = count
		last.postedIcon = (iconNow > 0 and iconNow) or 0
		last.postedAt = now
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessHerbHarvestNews,
	})
end
