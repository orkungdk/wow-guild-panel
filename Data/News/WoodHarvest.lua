-- ==========================================================
-- Wood harvest module (hors combat uniquement)
-- ==========================================================

local ADDON, ns = ...

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { woodharvest = 1 }

local MODULE_KEY = "woodharvest"
local PIGISTE_KEY = "woodharvest"

local PHRASES = {
	"%s baltasini savurup %d odun topluyor.",
	"%s atese yaklasik %d guzel yarilmis odun ekliyor.",
	"%s kesmeye devam edip kenara %d odun ayiriyor.",
	"%s baltayi sarkiya cevirip %d odun topluyor.",
	"%s acele etmeden odunlari yariyor ve %d odun istifliyor.",
	"%s odunlari isleyip meyhaneye %d odun getiriyor.",
	"%s govdeye vurup %d odun cikartiyor.",
	"%s yeni kestigi %d odunla atesi besliyor.",
	"%s isi surdurup stoğa %d odun ekliyor.",
	"%s oduna yuklenip %d odun daha cikartiyor.",
	"%s odunu biciyor ve %d kuru odun topluyor.",
	"%s gelecekteki ates icin %d taze kesilmis odun hazirliyor.",
	"%s isi ileri tasiyip %d odun daha sayiyor.",
	"%s yine baltayi kaldirip yiginı %d odunla tamamliyor.",
}

local ICONS = {
	4549121, -- profession tree/wood style
	236272, -- axe
}

local CFG = {
	enabled = true,
	spellIDs = { 1239682 },
	triggerEvent = "WOOD_HARVEST_UPDATE",
	lootLinkWindowSeconds = 10,
	pigisteEvents = {
		UNIT_SPELLCAST_SUCCEEDED = true,
		CHAT_MSG_LOOT = true,
	},
	triggerEvents = {
		"WOOD_HARVEST_UPDATE",
	},
	replaceKeyPrefix = "woodharvest:",
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

				-- Tolérance API: selon versions, le spellID peut arriver à différentes positions.
				local spellID = FindTrackedSpellIDFromArgs(...)
				if not spellID then
					return
				end
				-- Exigence: ne compter QUE hors combat.
				if InCombatLockdown and InCombatLockdown() then
					return
				end

				l.count = (tonumber(l.count) or 0) + 1
				l.lastSpellAt = now
				l.lastSpellID = spellID
				l.awaitingLootAt = now

				pigapi.IncCounter(p, "woodHarvest", 1)
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

	local function ProcessWoodHarvestNews(g, intel, last, uid, now)
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

		local replaceKey = (CFG.replaceKeyPrefix or "woodharvest:") .. tostring(uid or "player")
		local msg = (api.Pick(CFG.phrases) or "%s a récolté %d fois hors combat."):format(
			GetPlayerDisplayNameSafe(api, uid),
			count
		)

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = (iconNow > 0 and iconNow) or api.Pick(CFG.icons) or 134063,
			ts = now,
			replaceKey = replaceKey,
			removedAt = api.GetRemovedAt(MODULE_KEY, now, nil, replaceKey),
			points = POINTS.woodharvest or 1,
		})

		last.postedCount = count
		last.postedIcon = (iconNow > 0 and iconNow) or 0
		last.postedAt = now
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessWoodHarvestNews,
	})
end
