-- ==========================================================
-- Fishing harvest module (hors combat uniquement)
-- ==========================================================

local ADDON, ns = ...

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { fishingharvest = 1 }

local MODULE_KEY = "fishingharvest"
local PIGISTE_KEY = "fishingharvest"

local PHRASES = {
	"%s relève la ligne et attrape %d prises.",
	"%s revient du bord de l'eau avec %d poissons.",
	"%s garde le rythme et sort %d prises de l'eau.",
	"%s alimente les réserves avec %d poissons frais.",
	"%s poursuit la pêche et ramène %d prises.",
	"%s fait mordre et récupère %d poissons.",
	"%s remplit son panier de %d prises.",
	"%s réussit une belle session avec %d prises.",

	"%s patiente au bord de l’eau et sort %d poissons.",
	"%s laisse filer la ligne puis remonte %d prises.",
	"%s tire profit du calme et attrape %d poissons.",
	"%s continue tranquillement et ajoute %d prises.",
	"%s connaît une bonne passe et sort %d poissons.",
	"%s ramène %d prises après quelques lancers précis.",
	"%s profite du courant et récupère %d poissons.",
	"%s termine sa session avec %d prises au panier.",
	"%s garde la ligne tendue et récolte %d poissons.",
	"%s fait parler l’appât et sort %d prises.",
}

local ICONS = {
	133918, -- inv_misc_fish_01
	133920, -- inv_misc_fish_03
	4620673, -- fishing style fallback
}

local CFG = {
	enabled = true,
	spellIDs = { 131476 },
	triggerEvent = "FISHING_HARVEST_UPDATE",
	lootLinkWindowSeconds = 10,
	sequenceWindowSeconds = 20,
	pigisteEvents = {
		UNIT_SPELLCAST_SUCCEEDED = true,
		PLAYER_SOFT_TARGET_INTERACTION = true,
		UNIT_SPELLCAST_CHANNEL_STOP = true,
		CHAT_MSG_LOOT = true,
	},
	triggerEvents = {
		"FISHING_HARVEST_UPDATE",
	},
	replaceKeyPrefix = "fishingharvest:",
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

	local function FindSpellIDFromArgs(...)
		for i = 1, select("#", ...) do
			local n = tonumber((select(i, ...)))
			if n and trackedSpellIDs[n] then
				return n
			end
		end
		return nil
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

				local spellID = FindSpellIDFromArgs(...)
				if not spellID then
					return
				end
				if InCombatLockdown and InCombatLockdown() then
					return
				end

				-- Armement de la séquence: SUCCEEDED -> SOFT_TARGET_INTERACTION -> CHANNEL_STOP
				l.seqCastAt = now
				l.seqSoftAt = 0
				l.seqSpellID = spellID
				return
			end

			if eventName == "PLAYER_SOFT_TARGET_INTERACTION" then
				local castAt = tonumber(l.seqCastAt or 0) or 0
				local maxSeq = tonumber(CFG.sequenceWindowSeconds or 20) or 20
				if castAt > 0 and (now - castAt) <= maxSeq then
					l.seqSoftAt = now
				end
				return
			end

			if eventName == "UNIT_SPELLCAST_CHANNEL_STOP" then
				local unitTarget = select(1, ...)
				if unitTarget ~= "player" then
					return
				end
				local spellID = FindSpellIDFromArgs(...)
				if not spellID then
					return
				end

				local castAt = tonumber(l.seqCastAt or 0) or 0
				local softAt = tonumber(l.seqSoftAt or 0) or 0
				local maxSeq = tonumber(CFG.sequenceWindowSeconds or 20) or 20
				local seqOk = castAt > 0 and softAt >= castAt and (now - castAt) <= maxSeq

				-- reset séquence dans tous les cas
				l.seqCastAt = 0
				l.seqSoftAt = 0
				l.seqSpellID = 0

				if not seqOk then
					return
				end
				if InCombatLockdown and InCombatLockdown() then
					return
				end

				l.count = (tonumber(l.count) or 0) + 1
				l.lastSpellAt = now
				l.lastSpellID = spellID
				l.awaitingLootAt = now

				pigapi.IncCounter(p, "fishingHarvest", 1)
				pigapi.PushActivity(p, PIGISTE_KEY, { ts = now, spellID = spellID }, 200)
				p.updatedAt = now
				TickJournalistSoon()
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

	local function ProcessFishingHarvestNews(g, intel, last, uid, now)
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

		local replaceKey = (CFG.replaceKeyPrefix or "fishingharvest:") .. tostring(uid or "player")
		local msg = (api.Pick(CFG.phrases) or "%s a récupéré %d prise(s)."):format(
			GetPlayerDisplayNameSafe(api, uid),
			count
		)

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = (iconNow > 0 and iconNow) or api.Pick(CFG.icons) or 133918,
			ts = now,
			replaceKey = replaceKey,
			removedAt = api.GetRemovedAt(MODULE_KEY, now, nil, replaceKey),
			points = POINTS.fishingharvest or 1,
		})

		last.postedCount = count
		last.postedIcon = (iconNow > 0 and iconNow) or 0
		last.postedAt = now
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessFishingHarvestNews,
	})
end
