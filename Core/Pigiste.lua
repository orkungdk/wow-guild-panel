local ADDON, ns = ...
local EventBus = ns.EventBus

ns.Data = ns.Data or {}
local Pigiste = {}
ns.Data.Pigiste = Pigiste

-- =========================================================
-- Pigiste : utilitaires et identifiants joueur/guilde
-- =========================================================

local function Now()
	return time and time() or 0
end

local cached = {
	name = nil,
	realm = nil,
	full = nil,
	uid = nil,
	guildUID = nil,
	guildRootUID = nil,
	guildRoot = nil,
}

local function EnsureModules(p)
	p.modules = p.modules or {}
	return p.modules
end

local function GetModuleLast(p, key)
	if not p or not key then
		return nil
	end
	local modules = EnsureModules(p)
	modules[key] = modules[key] or {}
	return modules[key]
end

local function MigrateLegacyLast(p)
	if not p or type(p.last) ~= "table" then
		return
	end
	if p.last._wgMigrated then
		return
	end

	local legacy = p.last
	local modules = EnsureModules(p)
	local function isOnlyMigrated(t)
		local k = next(t)
		if k == nil then
			return true
		end
		if k ~= "_wgMigrated" then
			return false
		end
		return next(t, k) == nil
	end

	local function move(fromKey, moduleKey, toKey)
		if legacy[fromKey] ~= nil then
			modules[moduleKey] = modules[moduleKey] or {}
			modules[moduleKey][toKey] = legacy[fromKey]
			legacy[fromKey] = nil
		end
	end

	move("zoneName", "zone", "zoneName")
	move("zoneMapID", "zone", "zoneMapID")
	move("zoneAt", "zone", "zoneAt")

	move("specID", "spec", "specID")
	move("specName", "spec", "specName")
	move("specIcon", "spec", "specIcon")
	move("specAt", "spec", "specAt")

	move("ilvl", "itemlevel", "ilvl")
	move("ilvlOverall", "itemlevel", "ilvlOverall")
	move("ilvlFull", "itemlevel", "ilvlFull")
	move("ilvlAt", "itemlevel", "ilvlAt")
	move("ilvlByChar", "itemlevel", "ilvlByChar")

	move("level", "level", "level")
	move("levelAt", "level", "levelAt")

	move("honorLevel", "honorlevel", "honorLevel")
	move("honorAt", "honorlevel", "honorAt")

	move("deathAt", "deaths", "deathAt")
	move("lfgAt", "lfg", "lfgAt")
	move("pvpAt", "pvpkills", "pvpAt")

	move("lootItemID", "loot", "lootItemID")
	move("lootName", "loot", "lootName")
	move("lootIcon", "loot", "lootIcon")
	move("lootAt", "loot", "lootAt")
	move("lootQuality", "loot", "lootQuality")

	move("mountID", "mount", "mountID")
	move("mountName", "mount", "mountName")
	move("mountIcon", "mount", "mountIcon")
	move("mountAt", "mount", "mountAt")

	move("toyID", "toy", "toyID")
	move("toyName", "toy", "toyName")
	move("toyIcon", "toy", "toyIcon")
	move("toyAt", "toy", "toyAt")

	move("transmogItemID", "transmog", "transmogItemID")
	move("transmogAt", "transmog", "transmogAt")

	move("mplusAt", "mplus", "mplusAt")
	move("mplusMapID", "mplus", "mplusMapID")
	move("mplusLevel", "mplus", "mplusLevel")
	move("mplusOnTime", "mplus", "mplusOnTime")

	move("bossKillAt", "dungeonboss", "bossKillAt")
	move("bossID", "dungeonboss", "bossID")
	move("bossName", "dungeonboss", "bossName")

	move("loginAt", "session", "loginAt")
	move("logoutAt", "session", "logoutAt")
	move("reloadAt", "session", "reloadAt")
	move("presenceAnnouncedLoginAt", "session", "presenceAnnouncedLoginAt")

	move("merchantGoldDayKey", "merchantgold", "merchantGoldDayKey")
	move("merchantGoldToday", "merchantgold", "merchantGoldToday")
	move("merchantGoldTotal", "merchantgold", "merchantGoldTotal")
	move("merchantGoldFirstSaleAt", "merchantgold", "merchantGoldFirstSaleAt")

	move("merchantItemsDayKey", "merchantitems", "merchantItemsDayKey")
	move("merchantItemsToday", "merchantitems", "merchantItemsToday")
	move("merchantItemsFirstSaleAt", "merchantitems", "merchantItemsFirstSaleAt")

	legacy._wgMigrated = true
	if isOnlyMigrated(legacy) then
		p.last = nil
	end
end

local function FetchGuildUID()
	if ns.DB and ns.DB.GetGuildUID then
		return ns.DB:GetGuildUID()
	end
	return nil
end

local function FetchMyUID()
	if ns.DB and ns.DB.GetMyUID then
		return ns.DB:GetMyUID()
	end
	local name, realm = UnitFullName("player")
	if not name then
		return nil
	end
	realm = realm or GetRealmName() or "UnknownRealm"
	return "char:" .. name .. "-" .. realm
end

local function RefreshIdentity()
	local name, realm = UnitFullName("player")
	if not name or name == "" then
		cached.name = nil
		cached.realm = nil
		cached.full = nil
	else
		realm = realm or GetRealmName() or "UnknownRealm"
		cached.name = name
		cached.realm = realm
		cached.full = name .. "-" .. realm
	end
	cached.uid = nil
end

local function RefreshGuild()
	cached.guildUID = nil
	cached.guildRootUID = nil
	cached.guildRoot = nil
end

local function GetGuildUID()
	if cached.guildUID == nil then
		cached.guildUID = FetchGuildUID() or false
	end
	return cached.guildUID ~= false and cached.guildUID or nil
end

local function GetMyUID()
	if cached.uid == nil then
		cached.uid = FetchMyUID() or false
	end
	return cached.uid ~= false and cached.uid or nil
end

local function EnsureGuildIntel()
	WoWGuildeDB = WoWGuildeDB or {}
	WoWGuildeDB.guilds = WoWGuildeDB.guilds or {}

	local guildUID = GetGuildUID()
	if not guildUID or guildUID == "" then
		return nil
	end

	local g
	if cached.guildRoot and cached.guildRootUID == guildUID then
		g = cached.guildRoot
	else
		g = WoWGuildeDB.guilds[guildUID]
		if not g then
			g = { guildInfo = { guildUID = guildUID }, players = {} }
			WoWGuildeDB.guilds[guildUID] = g
		end
		if type(g.guildInfo) ~= "table" then
			g.guildInfo = { guildUID = guildUID }
		end
		cached.guildRoot = g
		cached.guildRootUID = guildUID
	end
	g.statistics = g.statistics or { players = {}, updatedAt = 0 }
	return g
end

-- =========================================================
-- Pigiste : structure et initialisation
-- =========================================================

local function EnsurePlayer(uid)
	if not uid or uid == "" then
		return nil
	end
	local g = EnsureGuildIntel()
	if not g then
		return nil
	end
	local p = g.statistics.players[uid]
	if not p then
		p = {
			counters = {},
			windows = { counts = {}, last = {}, openAt = {}, seconds = {} },
			achievements = { list = {}, interesting = {} },
			comms = { bySender = {}, top = {} },
			kills = { byType = {}, top = {} },
			activity = {
				transmog = {},
				mounts = {},
				toys = {},
				loot = {},
				lfg = {},
				pvpKills = {},
				mplus = {},
				bossKills = {},
				guildMessages = {},
				officerMessages = {},
			},
			updatedAt = 0,
		}
		g.statistics.players[uid] = p
	else
		p.counters = p.counters or {}
		p.windows = p.windows or {}
		p.windows.counts = p.windows.counts or {}
		p.windows.last = p.windows.last or {}
		p.windows.openAt = p.windows.openAt or {}
		p.windows.seconds = p.windows.seconds or {}
		p.achievements = p.achievements or { list = {}, interesting = {} }
		p.achievements.list = p.achievements.list or {}
		p.achievements.interesting = p.achievements.interesting or {}
		p.comms = p.comms or { bySender = {}, top = {} }
		p.comms.bySender = p.comms.bySender or {}
		p.comms.top = p.comms.top or {}
		p.kills = p.kills or { byType = {}, top = {} }
		p.kills.byType = p.kills.byType or {}
		p.kills.top = p.kills.top or {}
		p.activity = p.activity or {}
		p.activity.transmog = p.activity.transmog or {}
		p.activity.mounts = p.activity.mounts or {}
		p.activity.toys = p.activity.toys or {}
		p.activity.loot = p.activity.loot or {}
		p.activity.lfg = p.activity.lfg or {}
		p.activity.pvpKills = p.activity.pvpKills or {}
		p.activity.mplus = p.activity.mplus or {}
		p.activity.bossKills = p.activity.bossKills or {}
		p.activity.guildMessages = p.activity.guildMessages or {}
		p.activity.officerMessages = p.activity.officerMessages or {}
	end
	EnsureModules(p)
	MigrateLegacyLast(p)
	return p
end

-- =========================================================
-- Pigiste : helpers d'enregistrement
-- =========================================================

local function IncCounter(p, key, delta)
	if not p or not key then
		return
	end
	local cur = tonumber(p.counters[key] or 0) or 0
	p.counters[key] = cur + (delta or 1)
	p.updatedAt = Now()
end

local function GetAverageItemLevelSafe()
	if not GetAverageItemLevel then
		return nil
	end
	local _, overall = GetAverageItemLevel()
	overall = tonumber(overall or 0) or 0
	if overall <= 0 then
		return nil
	end
	return overall
end

local function GetSpecInfoSafe()
	if not GetSpecialization or not GetSpecializationInfo then
		return nil
	end
	local spec = GetSpecialization()
	if not spec then
		return nil
	end
	local specID, name = GetSpecializationInfo(spec)
	if not specID or not name then
		return nil
	end
	return specID, name
end

local function GetZoneInfoSafe()
	local zoneName = nil
	if GetRealZoneText then
		zoneName = GetRealZoneText()
	end
	if not zoneName or zoneName == "" then
		zoneName = GetZoneText and GetZoneText() or nil
	end
	if not zoneName or zoneName == "" then
		zoneName = GetSubZoneText and GetSubZoneText() or nil
	end
	if not zoneName or zoneName == "" then
		return nil
	end
	local mapID = nil
	if C_Map and C_Map.GetBestMapForUnit then
		mapID = C_Map.GetBestMapForUnit("player")
	end
	return zoneName, mapID
end

local function GetPVPKillsSafe()
	if C_PvP and C_PvP.GetLifetimeStats then
		local stats = C_PvP.GetLifetimeStats()
		if stats and stats.honorableKills then
			return tonumber(stats.honorableKills) or 0
		end
	end
	if GetPVPLifetimeStats then
		local hk = select(1, GetPVPLifetimeStats())
		hk = tonumber(hk or 0) or 0
		if hk > 0 then
			return hk
		end
	end
	return nil
end

local function GetCurrentSeason()
	return ns.Data and ns.Data.Seasons and ns.Data.Seasons.current or nil
end

local function IsCurrentDungeonInstance(instanceID)
	if not instanceID or instanceID <= 0 then
		return false
	end
	local s = GetCurrentSeason()
	return s and s.dungeons and s.dungeons[instanceID] == true or false
end

local function IsCurrentRaidInstance(instanceID)
	if not instanceID or instanceID <= 0 then
		return false
	end
	local s = GetCurrentSeason()
	return s and s.raids and s.raids[instanceID] == true or false
end

local function IsCurrentMPlusMap(mapID)
	if not mapID or mapID <= 0 then
		return false
	end
	local s = GetCurrentSeason()
	return s and s.mplus and s.mplus[mapID] == true or false
end

local function GetInstanceContext()
	if not GetInstanceInfo then
		return nil, nil
	end
	local instanceName, instanceType, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
	return instanceType, instanceName, instanceID, difficultyID, difficultyName
end

local function GetRaidDifficultyKey(difficultyID)
	difficultyID = tonumber(difficultyID or 0) or 0
	if difficultyID == 14 then
		return "normal"
	end
	if difficultyID == 15 then
		return "heroic"
	end
	if difficultyID == 16 then
		return "mythic"
	end
	if difficultyID == 3 or difficultyID == 4 then
		return "normal"
	end
	if difficultyID == 5 or difficultyID == 6 then
		return "heroic"
	end
	return nil
end

local function PushLimited(list, item, max)
	list[#list + 1] = item
	if #list > max then
		table.remove(list, 1)
	end
end

local function PushActivity(p, key, entry, max)
	if not p or not key then
		return
	end
	p.activity = p.activity or {}
	local list = p.activity[key]
	if not list then
		list = {}
		p.activity[key] = list
	end
	list[#list + 1] = entry
	if max and #list > max then
		table.remove(list, 1)
	end
end

local function PruneActivity(list, maxAgeSeconds, maxItems)
	if not list or #list == 0 then
		return
	end
	local now = Now()
	if maxAgeSeconds and maxAgeSeconds > 0 then
		for i = #list, 1, -1 do
			local entry = list[i]
			local ts = nil
			if type(entry) == "table" then
				ts = entry.ts
			elseif type(entry) == "number" then
				ts = entry
			end
			if ts and (now - ts) > maxAgeSeconds then
				table.remove(list, i)
			end
		end
	end
	if maxItems and #list > maxItems then
		local extra = #list - maxItems
		for _ = 1, extra do
			table.remove(list, 1)
		end
	end
end

local function PruneAllActivities(g, maxAgeSeconds)
	if not g or not g.statistics or not g.statistics.players then
		return
	end
	local chatWindowSeconds = 48 * 3600
	for _, p in pairs(g.statistics.players) do
		if p and p.activity then
			PruneActivity(p.activity.loot, maxAgeSeconds)
			PruneActivity(p.activity.mounts, maxAgeSeconds)
			PruneActivity(p.activity.toys, maxAgeSeconds)
			PruneActivity(p.activity.transmog, maxAgeSeconds)
			PruneActivity(p.activity.lfg, maxAgeSeconds)
			PruneActivity(p.activity.pvpKills, maxAgeSeconds)
			PruneActivity(p.activity.mplus, maxAgeSeconds)
			PruneActivity(p.activity.bossKills, maxAgeSeconds)
			PruneActivity(p.activity.guildMessages, chatWindowSeconds)
			PruneActivity(p.activity.officerMessages, chatWindowSeconds)
		end
	end
end

local function PruneGuildIntel(g, maxAgeSeconds)
	if not g or not g.statistics or not g.statistics.players then
		return
	end
	local now = Now()
	local cutoff = now - (tonumber(maxAgeSeconds) or 0)
	for uid, p in pairs(g.statistics.players) do
		if p then
			local updatedAt = tonumber(p.updatedAt or 0) or 0
			if cutoff > 0 and updatedAt > 0 and updatedAt < cutoff then
				g.statistics.players[uid] = nil
			end
		end
	end
	PruneAllActivities(g, maxAgeSeconds)
end

local function IsSelfSender(sender)
	if not sender or sender == "" then
		return false
	end
	local name, realm = UnitName("player")
	if not name or name == "" then
		return false
	end
	if sender == name then
		return true
	end
	realm = realm or GetRealmName() or ""
	if realm ~= "" and sender == (name .. "-" .. realm) then
		return true
	end
	local full = UnitFullName and UnitFullName("player") or nil
	if full and sender == full then
		return true
	end
	return false
end

local function ExtractItemLink(message)
	if not message or message == "" then
		return nil
	end
	return message:match("|Hitem:%d+.-|h%[[^%]]+%]|h")
end

local function MakeLootPattern(globalString)
	if not globalString or globalString == "" then
		return nil
	end
	local pattern = globalString:gsub("%%s", "\001"):gsub("%%d", "\002")
	pattern = pattern:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
	pattern = pattern:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
	return "^" .. pattern .. "$"
end

local LOOT_SELF_PATTERN = MakeLootPattern(LOOT_ITEM_SELF)
local LOOT_SELF_MULTI_PATTERN = MakeLootPattern(LOOT_ITEM_SELF_MULTIPLE)

local function IsSelfLootMessage(message)
	if not message or message == "" then
		return false
	end
	if LOOT_SELF_PATTERN and message:match(LOOT_SELF_PATTERN) then
		return true
	end
	if LOOT_SELF_MULTI_PATTERN and message:match(LOOT_SELF_MULTI_PATTERN) then
		return true
	end
	return false
end

local function GetItemInfoSafe(itemLink, itemID)
	local name, quality, icon = nil, nil, nil
	if itemLink and GetItemInfo then
		name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(itemLink)
	end
	if not name and itemLink then
		name = itemLink:match("%[(.+)%]")
	end
	if not quality and itemID and C_Item and C_Item.GetItemQualityByID then
		quality = C_Item.GetItemQualityByID(itemID)
	end
	if not icon and itemID and C_Item and C_Item.GetItemIconByID then
		icon = C_Item.GetItemIconByID(itemID)
	end
	return name, quality, icon
end

local function ResolveTransmogFromSource(sourceID)
	if not sourceID or not C_TransmogCollection or not C_TransmogCollection.GetAppearanceSourceInfo then
		return nil, nil
	end
	local info = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
	if type(info) == "table" then
		return info.itemID, info.icon
	end
	local _, _, _, icon, _, _, _, itemID = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
	return itemID, icon
end

-- =========================================================
-- Pigiste : hooks de frames et enregistrement fenêtre
-- =========================================================

function Pigiste.TrackFrameOpen(frameName, key)
	local frame = _G[frameName]
	if not frame or frame._wgIntelHooked then
		return false
	end
	frame._wgIntelHooked = true
	frame:HookScript("OnShow", function()
		local p = EnsurePlayer(GetMyUID())
		if not p then
			return
		end
		local counts = p.windows.counts
		local last = p.windows.last
		local wkey = key or frameName
		counts[wkey] = (tonumber(counts[wkey] or 0) or 0) + 1
		last[wkey] = Now()
		p.updatedAt = Now()
		p.windows.openAt[wkey] = Now()
	end)
	frame:HookScript("OnHide", function()
		local p = EnsurePlayer(GetMyUID())
		if not p then
			return
		end
		local wkey = key or frameName
		local start = tonumber((p.windows.openAt and p.windows.openAt[wkey]) or 0) or 0
		if start > 0 then
			local dur = Now() - start
			p.windows.openAt[wkey] = nil
			p.windows.seconds[wkey] = (tonumber(p.windows.seconds[wkey] or 0) or 0) + dur
		end
	end)
	return true
end

local pendingFrames = {}
function Pigiste.RegisterFrameHook(frameName, key, addonName)
	if Pigiste.TrackFrameOpen(frameName, key) then
		return
	end
	pendingFrames[#pendingFrames + 1] = { frameName = frameName, key = key, addon = addonName }
end

function Pigiste.ResolveFrameHooks(addonName)
	for i = #pendingFrames, 1, -1 do
		local item = pendingFrames[i]
		if not addonName or item.addon == addonName then
			if Pigiste.TrackFrameOpen(item.frameName, item.key) then
				table.remove(pendingFrames, i)
			end
		end
	end
end

-- =========================================================
-- Pigiste : API publique et modules d'evenements
-- =========================================================

function Pigiste.GetMyProfile()
	return EnsurePlayer(GetMyUID())
end

function Pigiste.RegisterModule(name, mod)
	if not name or not mod then
		return
	end
	mod.name = name
	if mod.events and mod.OnEvent and EventBus and EventBus.On then
		for event in pairs(mod.events) do
			EventBus.On(event, function(evt, ...)
				mod:OnEvent(evt, ...)
			end)
		end
	end
	if mod.OnInit then
		mod:OnInit()
	end
end

-- Cache identite/guilde
Pigiste.RegisterModule("identity", {
	events = {
		PLAYER_LOGIN = true,
		PLAYER_ENTERING_WORLD = true,
		PLAYER_GUILD_UPDATE = true,
		GUILD_ROSTER_UPDATE = true,
	},
	OnEvent = function(self)
		RefreshIdentity()
		RefreshGuild()
	end,
})

ns.Data.PigisteAPI = ns.Data.PigisteAPI or {}
local PigisteAPI = ns.Data.PigisteAPI
PigisteAPI.Now = Now
PigisteAPI.GetGuildUID = GetGuildUID
PigisteAPI.GetMyUID = GetMyUID
PigisteAPI.RefreshIdentity = RefreshIdentity
PigisteAPI.RefreshGuild = RefreshGuild
PigisteAPI.EnsureGuildIntel = EnsureGuildIntel
PigisteAPI.EnsurePlayer = EnsurePlayer
PigisteAPI.IncCounter = IncCounter
PigisteAPI.PushLimited = PushLimited
PigisteAPI.PushActivity = PushActivity
PigisteAPI.PruneActivity = PruneActivity
PigisteAPI.PruneAllActivities = PruneAllActivities
PigisteAPI.PruneGuildIntel = PruneGuildIntel
PigisteAPI.GetModuleLast = GetModuleLast
PigisteAPI.GetAverageItemLevelSafe = GetAverageItemLevelSafe
PigisteAPI.GetSpecInfoSafe = GetSpecInfoSafe
PigisteAPI.GetZoneInfoSafe = GetZoneInfoSafe
PigisteAPI.GetPVPKillsSafe = GetPVPKillsSafe
PigisteAPI.GetCurrentSeason = GetCurrentSeason
PigisteAPI.IsCurrentDungeonInstance = IsCurrentDungeonInstance
PigisteAPI.IsCurrentRaidInstance = IsCurrentRaidInstance
PigisteAPI.IsCurrentMPlusMap = IsCurrentMPlusMap
PigisteAPI.GetInstanceContext = GetInstanceContext
PigisteAPI.GetRaidDifficultyKey = GetRaidDifficultyKey
PigisteAPI.IsSelfSender = IsSelfSender
PigisteAPI.ExtractItemLink = ExtractItemLink
PigisteAPI.IsSelfLootMessage = IsSelfLootMessage
PigisteAPI.GetItemInfoSafe = GetItemInfoSafe
PigisteAPI.ResolveTransmogFromSource = ResolveTransmogFromSource
PigisteAPI.RegisterFrameHook = Pigiste.RegisterFrameHook
PigisteAPI.ResolveFrameHooks = Pigiste.ResolveFrameHooks

return Pigiste
