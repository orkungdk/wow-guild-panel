-- ==========================================================
-- Ore harvest module (hors combat uniquement)
-- ==========================================================

local ADDON, ns = ...

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { oreharvest = 1 }

local MODULE_KEY = "oreharvest"
local PIGISTE_KEY = "oreharvest"

local PHRASES = {
	"%s damardan %d maden cikariyor.",
	"%s ceplerini %d madenle dolduruyor.",
	"%s kazmaya devam edip %d maden topluyor.",
	"%s kayayi oyup %d maden cikartiyor.",
	"%s stoklarini %d maden daha ekleyerek tamamliyor.",
	"%s madenden %d madenle geri donuyor.",
	"%s damara vurup %d maden elde ediyor.",
	"%s dovme stokunu %d madenle zenginlestiriyor.",
	"%s aletini sallayip duvardan %d maden kurtariyor.",
	"%s kayayi cokturtup %d maden topluyor.",
	"%s damari kaziyip %d maden cikartiyor.",
	"%s sabirla tastan %d maden cikariyor.",
	"%s zaten agir olan canta icine %d maden daha ekliyor.",
	"%s calismaya devam edip %d ek maden topluyor.",
	"%s her vurusla %d maden kopariyor.",
	"%s damarla ugrasip %d maden bir araya topluyor.",
	"%s kazmayi konusturup %d maden elde ediyor.",
	"%s bu turu %d maden rezerviyle bitiriyor.",
}

local ICONS = {
	132775, -- inv_ore_copper_01
	237288, -- inv_ore_saronite_01
	4622270, -- mining style fallback
}

local CFG = {
	enabled = true,
	spellIDs = {
		2575,
		158754,
		195122,
		265839,
		265843,
		265845,
		265851,
		265853,
		366260,
		265841,
		2576,
		3564,
		10248,
		29354,
		50310,
		74517,
		102161,
		265837,
		265847,
		265849,
		309835,
	},
	triggerEvent = "ORE_HARVEST_UPDATE",
	lootLinkWindowSeconds = 10,
	pigisteEvents = {
		UNIT_SPELLCAST_SUCCEEDED = true,
		CHAT_MSG_LOOT = true,
	},
	triggerEvents = {
		"ORE_HARVEST_UPDATE",
	},
	replaceKeyPrefix = "oreharvest:",
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

				local spellID = FindTrackedSpellIDFromArgs(...)
				if not spellID then
					return
				end
				if InCombatLockdown and InCombatLockdown() then
					return
				end

				l.count = (tonumber(l.count) or 0) + 1
				l.lastSpellAt = now
				l.lastSpellID = spellID
				l.awaitingLootAt = now

				pigapi.IncCounter(p, "oreHarvest", 1)
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

	local function ProcessOreHarvestNews(g, intel, last, uid, now)
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

		local replaceKey = (CFG.replaceKeyPrefix or "oreharvest:") .. tostring(uid or "player")
		local msg = (api.Pick(CFG.phrases) or "%s a extrait %d minerai(s)."):format(
			GetPlayerDisplayNameSafe(api, uid),
			count
		)

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = (iconNow > 0 and iconNow) or api.Pick(CFG.icons) or 132775,
			ts = now,
			replaceKey = replaceKey,
			removedAt = api.GetRemovedAt(MODULE_KEY, now, nil, replaceKey),
			points = POINTS.oreharvest or 1,
		})

		last.postedCount = count
		last.postedIcon = (iconNow > 0 and iconNow) or 0
		last.postedAt = now
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessOreHarvestNews,
	})
end
