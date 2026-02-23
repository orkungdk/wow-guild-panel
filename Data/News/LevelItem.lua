-- ==========================================================
-- ItemLevel module
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { gear = 2 }

local MODULE_KEY = "itemlevel"
local PIGISTE_KEY = "itemlevel"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local ICONS = { 1030905, 1085608, 1030901, 1030911, 1030901, 1030903, 1455684 }

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================
local CFG = {
	enabled = true,

	triggerEvents = {
		"PLAYER_EQUIPMENT_CHANGED",
		"PLAYER_LOGIN",
	},
	pigisteEvents = {
		PLAYER_EQUIPMENT_CHANGED = true,
		PLAYER_LOGIN = true,
	},

	minFloorGain = 0.1,

	-- Ignore les "sauts" absurdes (déséquip/rééquip, swap violent, bug)
	-- Si gain >= maxFloorGain => on seed (maj baseline) mais PAS de news.
	maxFloorGain = 50,

	-- Snapshot des slots équipés pour choisir l'icône de l'objet "responsable"
	trackSlots = true,

	news = {
		type = "gear",
		ttlSeconds = nil,
		idPrefix = "itemlevel:",
		replaceKeyPrefix = "itemlevel:",

		-- Message unique, conditionné au genre du perso (pronoms)
		-- args: (pseudoJoueur, persoColoréSansServeur, gain, ilvlFormat)
		messages = {
			male = {
				"%s est revenu de %s avec un équipement reforgé : +%d niveaux d’objet, désormais à %s.",
				"%s a fait parler la forge après %s : %d niveaux d’objet gagnés, pour atteindre %s.",
				"À la sortie de %s, %s a frappé l’enclume : +%d niveaux d’objet, le portant à %s.",
				"%s a tiré récompense de %s : %d niveaux d’objet de plus, maintenant à %s.",
				"Les braises chantent encore : %s gagne %d niveaux d’objet grâce à %s, atteignant %s.",
			},

			female = {
				"%s est revenue de %s avec un équipement reforgé : +%d niveaux d’objet, désormais à %s.",
				"%s a fait parler la forge après %s : %d niveaux d’objet gagnés, pour atteindre %s.",
				"À la sortie de %s, %s a frappé l’enclume : +%d niveaux d’objet, la portant à %s.",
				"%s a tiré récompense de %s : %d niveaux d’objet de plus, maintenant à %s.",
				"Les braises chantent encore : %s gagne %d niveaux d’objet grâce à %s, atteignant %s.",
			},

			neutral = {
				"%s est revenu de %s avec un équipement reforgé : +%d niveaux d’objet, désormais à %s.",
				"%s a fait parler la forge après %s : %d niveaux d’objet gagnés, pour atteindre %s.",
				"À la sortie de %s, %s a frappé l’enclume : +%d niveaux d’objet, le portant à %s.",
				"%s a tiré récompense de %s : %d niveaux d’objet de plus, maintenant à %s.",
				"Les braises chantent encore : %s gagne %d niveaux d’objet grâce à %s, atteignant %s.",
			},
		},
	},

	resolve = {
		fallbackIcons = ICONS,
		useFormatIlvl = true,
		useClassColor = true,
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

	local pendingTick = false
	local pendingEvent = nil

	local function TickJournalistSoon(eventName)
		pendingEvent = eventName or pendingEvent
		if pendingTick then
			return
		end
		pendingTick = true

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

	local function MakeFullNameSafe()
		local name, realm = nil, nil

		if UnitFullName then
			name, realm = UnitFullName("player")
		end
		if not name or name == "" then
			if UnitName then
				name = UnitName("player")
			end
		end
		if not realm or realm == "" then
			if GetRealmName then
				realm = GetRealmName()
			end
		end

		name = tostring(name or "")
		realm = tostring(realm or "")

		if name == "" then
			return ""
		end
		if realm == "" then
			return name
		end
		return name .. "-" .. realm
	end

	-- Slots utiles (ignore chemise/tabard)
	local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

	local function GetItemIlvlFromLink(link)
		if not link or link == "" then
			return 0
		end
		if C_Item and C_Item.GetDetailedItemLevelInfo then
			return tonumber(C_Item.GetDetailedItemLevelInfo(link) or 0) or 0
		end
		if GetDetailedItemLevelInfo then
			return tonumber(GetDetailedItemLevelInfo(link) or 0) or 0
		end
		local ilvl = select(4, GetItemInfo(link))
		return tonumber(ilvl or 0) or 0
	end

	local function GetItemIconFromIDorLink(itemID, link)
		local icon = nil
		itemID = tonumber(itemID or 0) or 0
		if itemID > 0 and C_Item and C_Item.GetItemIconByID then
			icon = C_Item.GetItemIconByID(itemID)
		end
		if not icon and itemID > 0 and GetItemIcon then
			icon = GetItemIcon(itemID)
		end
		if not icon and link and link ~= "" then
			icon = select(10, GetItemInfo(link))
		end
		return icon
	end

	local function SnapshotEquippedSlots()
		local out = {}
		if not CFG.trackSlots then
			return out
		end
		if not GetInventoryItemLink or not GetInventoryItemID then
			return out
		end

		for i = 1, #EQUIP_SLOTS do
			local slot = EQUIP_SLOTS[i]
			local link = GetInventoryItemLink("player", slot)
			if link then
				local itemID = GetInventoryItemID("player", slot)
				local ilvl = GetItemIlvlFromLink(link)
				local icon = GetItemIconFromIDorLink(itemID, link)
				out[slot] = { itemID = itemID, ilvl = ilvl, icon = icon }
			end
		end
		return out
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		OnEvent = function(_, eventName, ...)
			if not CFG.enabled then
				return
			end

			local p = pigAPI.EnsurePlayer(pigAPI.GetMyUID())
			if not p then
				return
			end

			local overall = pigAPI.GetAverageItemLevelSafe and pigAPI.GetAverageItemLevelSafe() or nil
			overall = tonumber(overall or 0) or 0
			if overall <= 0 then
				return
			end

			local full = MakeFullNameSafe()
			if full == "" then
				return
			end

			local classTag = nil
			if UnitClass then
				classTag = select(2, UnitClass("player"))
			end

			local sex = nil
			if UnitSex then
				sex = tonumber(UnitSex("player") or 0) or nil -- 2=male, 3=female (retail)
			end

			local charName = ""
			if UnitName then
				charName = tostring(UnitName("player") or "")
			end

			local ts = pigAPI.Now()

			local changedSlot = nil
			if eventName == "PLAYER_EQUIPMENT_CHANGED" then
				local slotId = ...
				changedSlot = tonumber(slotId or 0) or nil
			end

			local l = pigAPI.GetModuleLast(p, MODULE_KEY)
			l.ilvlOverall = overall
			l.ilvl = overall -- compat
			l.ilvlFull = full
			l.charName = charName -- SANS serveur (pour la news)
			l.classTag = classTag
			l.sex = sex
			l.ilvlAt = ts
			l.event = eventName

			l.changedSlot = changedSlot
			l.slots = SnapshotEquippedSlots()

			if changedSlot and l.slots and l.slots[changedSlot] then
				l.changedItemID = l.slots[changedSlot].itemID
				l.changedItemIcon = l.slots[changedSlot].icon
				l.changedItemIlvl = l.slots[changedSlot].ilvl
			else
				l.changedItemID = nil
				l.changedItemIcon = nil
				l.changedItemIlvl = nil
			end

			p.updatedAt = ts
			TickJournalistSoon(eventName)
		end,
	})
end

-- ==========================================================
-- 4) Helpers métier (purs)
-- ==========================================================

local function GetModuleIntelLast(intel)
	if type(intel) ~= "table" then
		return nil
	end

	if type(intel.last) == "table" and (intel.last.ilvlOverall or intel.last.ilvlFull or intel.last.ilvlAt) then
		return intel.last
	end
	if type(intel.last) == "table" and type(intel.last[MODULE_KEY]) == "table" then
		return intel.last[MODULE_KEY]
	end
	if type(intel[MODULE_KEY]) == "table" then
		return intel[MODULE_KEY]
	end
	if type(intel.modules) == "table" and type(intel.modules[MODULE_KEY]) == "table" then
		return intel.modules[MODULE_KEY]
	end

	return nil
end

local function CopySlotsSnapshot(slots)
	if type(slots) ~= "table" then
		return nil
	end
	local out = {}
	for slot, s in pairs(slots) do
		if type(s) == "table" then
			out[slot] = { itemID = s.itemID, ilvl = s.ilvl, icon = s.icon }
		end
	end
	return out
end

local function SeedBaseline(last, full, ilvl, mlast)
	last.ilvlByChar = last.ilvlByChar or {}
	last.ilvlByChar[full] = ilvl

	if mlast and type(mlast.slots) == "table" then
		last.slotSnapByChar = last.slotSnapByChar or {}
		last.slotSnapByChar[full] = CopySlotsSnapshot(mlast.slots)
	end
end

local function GetIlvlGain(intel, last)
	local mlast = GetModuleIntelLast(intel)
	if not mlast then
		return
	end

	local ilvl = tonumber(mlast.ilvlOverall or mlast.ilvl) or 0
	if ilvl <= 0 then
		return
	end

	local full = tostring(mlast.ilvlFull or "")
	if full == "" then
		return
	end

	last.ilvlByChar = last.ilvlByChar or {}
	local prev = tonumber(last.ilvlByChar[full]) or 0

	if prev <= 0 then
		SeedBaseline(last, full, ilvl, mlast)
		return
	end

	if ilvl <= prev then
		SeedBaseline(last, full, ilvl, mlast)
		return
	end

	local gain = math.floor(ilvl) - math.floor(prev)

	if CFG.maxFloorGain and gain >= (tonumber(CFG.maxFloorGain) or 50) then
		SeedBaseline(last, full, ilvl, mlast)
		return
	end

	if gain < (tonumber(CFG.minFloorGain) or 2) then
		return
	end

	return ilvl, full, gain, mlast
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

local function ResolveNames(api, intel, uid)
	local mainName = nil
	if api then
		if api.GetCachedAlias then
			mainName = api.GetCachedAlias()
		end
		if (not mainName or mainName == "") and api.GetMyPublicNote then
			local note = api.GetMyPublicNote()
			if ns.Utils and ns.Utils.AliasFromNote then
				mainName = ns.Utils.AliasFromNote(note)
			elseif ns.Utils and ns.Utils.ParsePseudo then
				mainName = ns.Utils.ParsePseudo(note, "")
			end
		end
		if not mainName or mainName == "" then
			mainName = GetPlayerDisplayNameSafe(api, uid)
		end
	end
	mainName = tostring(mainName or "Le joueur")

	-- Perso SANS serveur (charName) + couleur classe si dispo
	local mlast = GetModuleIntelLast(intel) or {}
	local charName = tostring(mlast.charName or "")

	-- fallback si jamais charName vide : on tente de retirer "-Realm" de ilvlFull
	if charName == "" then
		local full = tostring(mlast.ilvlFull or "")
		charName = full:match("^([^%-]+)") or full
	end

	local classTag = mlast.classTag
	local coloredChar = (charName ~= "" and charName) or mainName
	if CFG.resolve.useClassColor and ns.Utils and ns.Utils.ColorizeByClassTag and classTag then
		coloredChar = ns.Utils.ColorizeByClassTag(coloredChar, classTag)
	end

	return mainName, coloredChar
end

local function FormatIlvlSafe(api, ilvl)
	ilvl = tonumber(ilvl or 0) or 0
	if ilvl <= 0 then
		return tostring(ilvl)
	end
	if CFG.resolve.useFormatIlvl and api and api.FormatIlvl then
		return api.FormatIlvl(ilvl)
	end
	return tostring(math.floor(ilvl + 0.5))
end

local function PickFallbackIcon(api)
	if api and api.Pick then
		return api.Pick(CFG.resolve.fallbackIcons or ICONS)
	end
	local t = CFG.resolve.fallbackIcons or ICONS
	return t and t[1] or nil
end

local function PickUpgradeIconSmart(api, intel, last, full, mlast)
	mlast = mlast or GetModuleIntelLast(intel) or {}
	local slots = type(mlast.slots) == "table" and mlast.slots or nil

	-- 1) Slot réellement changé
	local cs = tonumber(mlast.changedSlot or 0) or 0
	if cs > 0 and slots and slots[cs] and slots[cs].icon then
		return slots[cs].icon
	end

	-- 2) Icône directe capturée
	local direct = tonumber(mlast.changedItemIcon or 0) or 0
	if direct > 0 then
		return direct
	end

	-- 3) Diff snapshot (utile sur LOGIN)
	local prev = last.slotSnapByChar and last.slotSnapByChar[full] or nil
	if slots and prev then
		local bestIcon, bestDelta = nil, 0
		for slot, cur in pairs(slots) do
			local curIlvl = tonumber(cur and cur.ilvl) or 0
			local prevIlvl = tonumber(prev[slot] and prev[slot].ilvl) or 0
			local d = curIlvl - prevIlvl
			local icon = cur and cur.icon
			if d > bestDelta and (tonumber(icon or 0) or 0) > 0 then
				bestDelta = d
				bestIcon = icon
			end
		end
		if bestIcon then
			return bestIcon
		end
	end

	return PickFallbackIcon(api)
end

local function AddRawNewsCompat(api, g, payload)
	if not api or type(api.AddRawNews) ~= "function" then
		return
	end

	-- Signature moderne
	if type(payload) == "table" then
		local ok = pcall(api.AddRawNews, g, payload)
		if ok then
			return
		end
	end

	-- Legacy positionnel
	local text = payload and payload.text or nil
	local ntype = payload and payload.type or nil
	local icon = payload and payload.icon or nil
	local ts = payload and payload.ts or nil
	local id = payload and payload.id or nil
	local replaceable = payload and payload.replaceable or nil
	local replaceKey = payload and payload.replaceKey or nil
	local ttlSeconds = payload and payload.ttlSeconds or nil
	local removedAt = payload and payload.removedAt or nil

	pcall(api.AddRawNews, g, text, ntype, icon, ts, id, replaceable, replaceKey, ttlSeconds, removedAt)
end

local function PickGenderedMessage(mlast, api)
	local function pick(listOrStr)
		if type(listOrStr) == "table" then
			if api and api.Pick then
				return api.Pick(listOrStr)
			end
			if #listOrStr > 0 then
				return listOrStr[math.random(1, #listOrStr)]
			end
			return nil
		end
		return listOrStr
	end

	local sex = tonumber(mlast and mlast.sex or 0) or 0
	-- retail: 2=male, 3=female ; sinon neutral
	if sex == 3 then
		return pick((CFG.news.messages and CFG.news.messages.female) or CFG.news.message)
	end
	if sex == 2 then
		return pick((CFG.news.messages and CFG.news.messages.male) or CFG.news.message)
	end
	return pick((CFG.news.messages and CFG.news.messages.neutral) or CFG.news.message)
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

	local function ProcessItemLevelNews(g, intel, last, uid, now)
		if not CFG.enabled then
			return
		end

		local ilvl, full, gain, mlast = GetIlvlGain(intel, last)
		if not ilvl then
			return
		end

		local mainName, coloredChar = ResolveNames(api, intel, uid)

		local tpl = PickGenderedMessage(mlast, api)
			or "%s a augmenté avec %s son niveau d'objet de %d niveaux, le faisant passer maintenant à %s de niveau d'objet."

		local ilvlStr = FormatIlvlSafe(api, ilvl)
		local msg = tpl:format(mainName, coloredChar, tonumber(gain or 0) or 0, ilvlStr)

		-- Remplacement PAR PERSONNAGE (uid + full) => Astiraïs ≠ Rédemption
		-- (la news n'affiche pas le serveur, mais la clé reste stable)
		local baseKey = ("%s%s:%s"):format(CFG.news.replaceKeyPrefix or "itemlevel:", tostring(uid), tostring(full))
		local newsId = baseKey

		local icon = PickUpgradeIconSmart(api, intel, last, full, mlast)

		local payload = {
			text = msg,
			type = CFG.news.type or "gear",
			icon = icon,
			ts = now,
			replaceable = true,
			replaceKey = baseKey,
			id = newsId,
			ttlSeconds = CFG.news.ttlSeconds,
			removedAt = (api.GetRemovedAt and api.GetRemovedAt(MODULE_KEY, now)) or nil,
			points = POINTS.gear or 3,
		}

		AddRawNewsCompat(api, g, payload)

		-- Seed/update baseline
		SeedBaseline(last, full, ilvl, mlast)
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessItemLevelNews,
	})
end
