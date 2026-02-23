local ADDON, ns = ...

ns.GuildProgress = ns.GuildProgress or {}
local GP = ns.GuildProgress

local EventBus = ns.EventBus
local DB = ns.DB
local Comms = ns.Comms

local function Now()
	return time and time() or 0
end

local EnsureProgressRoot

local function IsDevMode()
	if ns and ns.Utils and ns.Utils.IsDevMode then
		return ns.Utils.IsDevMode()
	end
	if ns and ns.Comms and ns.Comms.DEV_MODE ~= nil then
		return ns.Comms.DEV_MODE == true
	end
	if ns and ns.DEV_MODE ~= nil then
		return ns.DEV_MODE == true
	end
	return false
end

local function DevLog(msg)
	if IsDevMode() and print then
		print("|cffffd100[WoW Guilde]|r GP " .. tostring(msg or ""))
	end
end

local function LogPoints(kind, data)
	if not data then
		return
	end
	GP._debugPoints = GP._debugPoints or { order = {}, max = 60 }
	local buf = GP._debugPoints
	buf.order[#buf.order + 1] = data
	if #buf.order > (tonumber(buf.max) or 60) then
		table.remove(buf.order, 1)
	end
end

local function ResolveUIDForSender(guildUID, senderFull, senderUID)
	if type(senderUID) == "string" and senderUID ~= "" then
		return senderUID
	end
	if ns and ns.Data and ns.Data.ResolvePlayerUID then
		local uid = ns.Data.ResolvePlayerUID(guildUID, senderFull, nil)
		if uid and uid ~= "" then
			return uid
		end
	end
	return nil
end

local function ExtractUIDFromReplaceKey(replaceKey)
	if type(replaceKey) ~= "string" or replaceKey == "" then
		return nil
	end
	local uid = replaceKey:match("(uid:[0-9a-fA-F]+)")
	if uid and uid ~= "" then
		return uid
	end
	return nil
end

local function IsProgressEmpty(progress)
	if not progress or type(progress.groups) ~= "table" then
		return true
	end
	for _, group in pairs(progress.groups) do
		if type(group) == "table" and type(group.byUID) == "table" then
			for _, entry in pairs(group.byUID) do
				if entry and (entry.pointsEnc or entry.points or entry.events) then
					return false
				end
			end
		end
	end
	return true
end

local function GetActiveAddonUsers(guildUID)
	local cache = GP._addonActiveCache
	local now = Now()
	if cache and cache.at and (now - cache.at) < 60 then
		return cache.count or 1
	end
	local progress = EnsureProgressRoot(guildUID)
	if not progress or type(progress.groups) ~= "table" then
		GP._addonActiveCache = { count = 1, at = now }
		return 1
	end
	local cfg = GP.Config or {}
	local windowDays = tonumber((cfg.addonActive and cfg.addonActive.windowDays) or 14) or 14
	local windowSeconds = windowDays * 86400
	local cutoff = now - windowSeconds
	local seen = {}
	local count = 0
	for _, group in pairs(progress.groups) do
		if type(group) == "table" and type(group.byUID) == "table" then
			for uid, entry in pairs(group.byUID) do
				if not seen[uid] and type(entry) == "table" then
					local updatedAt = tonumber(entry.updatedAt or 0) or 0
					if updatedAt >= cutoff then
						seen[uid] = true
						count = count + 1
					end
				end
			end
		end
	end
	if count <= 0 then
		count = 1
	end
	GP._addonActiveCache = { count = count, at = now }
	return count
end

-- =========================================================
-- Config
-- =========================================================
GP.Config = GP.Config
	or {
		schema = 1,
		defaultPoints = 6,
		seenMax = 1400,
		scale = {
			min = 0.35,
			max = 2.5,
			floor = 0.25,
			exponent = 0.5,
		},
		roster = {
			windowDays = 14,
			reference = 20,
			minFactor = 0.35,
			maxFactor = 1.25,
		},
		global = {
			target = 10000,
		},
		addonActive = {
			windowDays = 14,
			reference = 20,
			minFactor = 0.35,
			maxFactor = 2.5,
		},
		security = {
			maxPerEvent = 6,
			pointsHashKey = "pointsHash",
			pointsTolerance = 0.01,
		},
		groups = {
			{
				key = "quests",
				label = "Quetes",
				target = 2000,
				color = { 0.25, 0.60, 0.95 },
				types = { "quest", "questdaily", "worldquest" },
			},
			{
				key = "world",
				label = "Monde",
				target = 1400,
				color = { 0.20, 0.70, 0.55 },
				types = { "world" },
			},
			{
				key = "progression",
				label = "Progression",
				target = 2800,
				color = { 0.95, 0.80, 0.20 },
				types = { "achievement", "level", "gear", "spec" },
			},
			{
				key = "combat",
				label = "Combat",
				target = 2800,
				color = { 0.85, 0.20, 0.20 },
				types = { "pve", "raid", "mplus", "cibles", "pvp", "death" },
			},
			{
				key = "loot",
				label = "Butin",
				target = 2200,
				color = { 0.90, 0.60, 0.10 },
				types = { "loot", "woodharvest", "herbharvest", "fishingharvest", "oreharvest" },
			},
			{
				key = "collections",
				label = "Collections",
				target = 2000,
				color = { 0.70, 0.52, 0.90 },
				types = { "mount", "toy", "transmog", "collection", "housing", "housingcleanup", "housingdecor" },
			},
			{
				key = "communications",
				label = "Communications",
				target = 1700,
				color = { 0.55, 0.75, 0.95 },
				types = { "connection", "guild", "guildchat", "social" },
			},
			{
				key = "divers",
				label = "Divers",
				target = 1200,
				color = { 0.72, 0.72, 0.72 },
				types = { "generic" },
			},
		},
	}

local CFG = GP.Config

local function BuildIndexes()
	if CFG._typeToGroup and CFG._groupsByKey then
		return
	end
	local typeToGroup = {}
	local groupsByKey = {}
	for i = 1, #CFG.groups do
		local group = CFG.groups[i]
		if group and group.key then
			groupsByKey[group.key] = group
			if type(group.types) == "table" then
				for _, typ in ipairs(group.types) do
					typeToGroup[tostring(typ):lower()] = group.key
				end
			end
		end
	end
	CFG._typeToGroup = typeToGroup
	CFG._groupsByKey = groupsByKey
end

BuildIndexes()

local function Clamp(v, a, b)
	if v < a then
		return a
	end
	if v > b then
		return b
	end
	return v
end

local function HashStringFNV1a(s)
	local hash = 0x811C9DC5
	for i = 1, #s do
		hash = bit.bxor(hash, s:byte(i))
		hash = (hash * 0x01000193) % 2 ^ 32
	end
	return string.format("%08x", hash)
end

local function HashPointsTable(tbl)
	if type(tbl) ~= "table" then
		return "00000000"
	end
	local keys = {}
	for k in pairs(tbl) do
		keys[#keys + 1] = tostring(k)
	end
	table.sort(keys)
	local sb = {}
	for i = 1, #keys do
		local k = keys[i]
		local v = tbl[k]
		sb[#sb + 1] = k .. "=" .. tostring(v) .. ";"
	end
	return HashStringFNV1a(table.concat(sb))
end

local function GetSettings()
	WoWGuildeDB = WoWGuildeDB or {}
	WoWGuildeDB.Settings = WoWGuildeDB.Settings or {}
	return WoWGuildeDB.Settings
end

local function ValidatePointsTable()
	local settings = GetSettings()
	local key = CFG.security and CFG.security.pointsHashKey or "pointsHash"
	local current = HashPointsTable(ns.Data and ns.Data.NewsPoints or {})
	local previous = settings[key]
	if previous and previous ~= current then
		-- Mismatch => on signale, mais on stocke le nouveau hash pour éviter un reset en boucle
		settings[key] = current
		return false, current, previous
	end
	settings[key] = current
	return true, current, previous
end

local function ValidateMyProgress(guildUID, uid)
	if not guildUID or not uid then
		return
	end
	local progress = EnsureProgressRoot(guildUID)
	if not progress or type(progress.groups) ~= "table" then
		return
	end
	for groupKey, group in pairs(progress.groups) do
		if type(group) == "table" and type(group.byUID) == "table" then
			local entry = group.byUID[uid]
			if entry and entry.pointsEnc and DB and DB.DecodeGuildProgressPoints then
				local ok = DB:DecodeGuildProgressPoints(guildUID, uid, groupKey, entry) ~= nil
				if not ok then
					if DB and DB.ResetGuildProgressForUID then
						DB:ResetGuildProgressForUID(guildUID, uid, "invalid_points")
					end
					return
				end
			end
		end
	end
end

local function GetRecentHeroCount()
	local cache = GP._rosterCache
	local now = Now()
	if cache and cache.at and (now - cache.at) < 60 then
		return cache.count or 1
	end

	if not IsInGuild or not IsInGuild() then
		GP._rosterCache = { count = 1, at = now }
		return 1
	end

	if ns and ns.RequestGuildData then
		ns.RequestGuildData()
	end

	local num = GetNumGuildMembers and GetNumGuildMembers() or 0
	if num <= 0 then
		GP._rosterCache = { count = 1, at = now }
		return 1
	end

	local windowDays = (CFG.roster and CFG.roster.windowDays) or 14
	local windowMinutes = (tonumber(windowDays) or 14) * 24 * 60

	local seen = {}
	local recentCount = 0

	for i = 1, num do
		local name, _, _, _, _, _, note, _, online = GetGuildRosterInfo(i)
		if name then
			local lastMinutes = 999999
			if online then
				lastMinutes = 0
			elseif ns and ns.GetLastOnlineInfo then
				local mins = ns.GetLastOnlineInfo(i)
				if type(mins) == "number" then
					lastMinutes = mins
				end
			end

			if online or (lastMinutes <= windowMinutes) then
				local pseudo = name
				if ns and ns.Utils and ns.Utils.ParsePseudo then
					pseudo = (select(1, ns.Utils.ParsePseudo(note, name))) or name
				end
				local key = pseudo
				if ns and ns.Utils and ns.Utils.PseudoKey then
					key = ns.Utils.PseudoKey(pseudo)
				end
				key = tostring(key or "")
				if key ~= "" and not seen[key] then
					seen[key] = true
					recentCount = recentCount + 1
				end
			end
		end
	end

	if recentCount <= 0 then
		recentCount = 1
	end

	GP._rosterCache = { count = recentCount, at = now }
	return recentCount
end

-- =========================================================
-- Progress roots
-- =========================================================
EnsureProgressRoot = function(guildUID)
	if DB and DB.EnsureGuildProgress then
		return DB:EnsureGuildProgress(guildUID)
	end
	WoWGuildeDB = WoWGuildeDB or {}
	WoWGuildeDB.guilds = WoWGuildeDB.guilds or {}
	if not guildUID or guildUID == "" then
		return nil
	end
	local g = WoWGuildeDB.guilds[guildUID]
	if not g then
		g = { guildInfo = { guildUID = guildUID }, players = {} }
		WoWGuildeDB.guilds[guildUID] = g
	end
	g.guildShared = g.guildShared or {}
	g.guildShared.guildProgress = g.guildShared.guildProgress or { schema = CFG.schema, groups = {}, updatedAt = 0 }
	return g.guildShared.guildProgress
end

local function GetGroupPoints(progress, groupKey)
	local g = progress and progress.groups and progress.groups[groupKey]
	if not g or type(g.byUID) ~= "table" then
		return 0
	end
	local total = 0
	for uid, v in pairs(g.byUID) do
		if type(v) == "table" then
			local points = nil
			if DB and DB.DecodeGuildProgressPoints then
				points = DB:DecodeGuildProgressPoints(progress and progress._guildUID or "", uid, groupKey, v)
				if points == nil and v.pointsEnc and DB.ResetGuildProgressForUID then
					DB:ResetGuildProgressForUID(progress and progress._guildUID or "", uid, "invalid_points")
				end
			end
			if points == nil then
				points = tonumber(v.points or 0) or 0
			end
			total = total + points
		end
	end
	return total
end

-- =========================================================
-- Seen cache (local, non partagé)
-- =========================================================
local seenCache = {}

local function EnsureSeen(guildUID)
	if not guildUID or guildUID == "" then
		return nil
	end
	local entry = seenCache[guildUID]
	if not entry then
		entry = { map = {}, order = {} }
		seenCache[guildUID] = entry
	end
	return entry
end

local function MarkSeen(guildUID, newsId, ts)
	if not guildUID or not newsId or newsId == "" then
		return false
	end
	local entry = EnsureSeen(guildUID)
	if not entry then
		return false
	end
	local map = entry.map
	local last = tonumber(map[newsId] or 0) or 0
	local nowTs = tonumber(ts or 0) or 0
	if nowTs <= 0 then
		nowTs = Now()
	end
	if last > 0 and nowTs <= last then
		return false
	end
	map[newsId] = nowTs
	local order = entry.order
	order[#order + 1] = { id = newsId, ts = nowTs }
	local max = tonumber(CFG.seenMax or 0) or 0
	if max > 0 and #order > max then
		local old = table.remove(order, 1)
		if old and map[old.id] == old.ts then
			map[old.id] = nil
		end
	end
	return true
end

-- =========================================================
-- API publique
-- =========================================================
function GP.GetGroupKeyForType(typ)
	if not typ or typ == "" then
		return "divers"
	end
	BuildIndexes()
	local key = tostring(typ):lower()
	local group = CFG._typeToGroup[key]
	if not group and ns and ns.Data and ns.Data.NewsMeta then
		local meta = ns.Data.NewsMeta[key]
		if type(meta) == "table" and type(meta.type) == "string" then
			local metaType = tostring(meta.type):lower()
			group = CFG._typeToGroup[metaType]
		end
	end
	return group or "divers"
end

function GP.GetGroupConfig(key)
	BuildIndexes()
	return CFG._groupsByKey[key]
end

function GP.GetCurrentGroupPoints(guildUID, groupKey)
	local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID()) or nil
	if not gid or not groupKey then
		return 0
	end
	local progress = EnsureProgressRoot(gid)
	return GetGroupPoints(progress, groupKey)
end

function GP.GetTypePoints(typ)
	local key = tostring(typ or ""):lower()
	if ns.Data and ns.Data.NewsPoints and ns.Data.NewsPoints[key] ~= nil then
		return tonumber(ns.Data.NewsPoints[key]) or 0
	end
	return tonumber((CFG.typePoints and CFG.typePoints[key]) or CFG.defaultPoints) or 0
end

function GP.GetRosterFactor()
	local cfg = CFG.roster or {}
	local ref = tonumber(cfg.reference or 0) or 0
	if ref <= 0 then
		return 1, GetRecentHeroCount()
	end
	local count = GetRecentHeroCount()
	local raw = (count > 0) and (count / ref) or 1
	local minFactor = tonumber(cfg.minFactor or 0) or 0.35
	local maxFactor = tonumber(cfg.maxFactor or 0) or 1.25
	return Clamp(raw, minFactor, maxFactor), count
end

function GP.ComputeScale(groupKey, currentPoints, targetOverride)
	local group = GP.GetGroupConfig(groupKey) or {}
	local target = tonumber(targetOverride or group.target or 0) or 0
	if target <= 0 then
		return 1
	end
	local scaleCfg = CFG.scale or {}
	local floor = tonumber(scaleCfg.floor or 0) or 0.25
	local exponent = tonumber(scaleCfg.exponent or 0) or 0.5
	local minScale = tonumber(scaleCfg.min or 0) or 0.35
	local maxScale = tonumber(scaleCfg.max or 0) or 2.5
	local denom = math.max(tonumber(currentPoints or 0) or 0, target * floor)
	local raw = (target / denom) ^ exponent
	return Clamp(raw, minScale, maxScale)
end

local function RoundPoints(v)
	if v == nil then
		return 0
	end
	local n = tonumber(v) or 0
	-- Garde 2 décimales pour les valeurs faibles (0.25, 1.5, etc.)
	return math.floor(n * 100 + 0.5) / 100
end

local function GetMaxAllowedPoints(base)
	local b = tonumber(base or 0) or 0
	if b <= 0 then
		return 0
	end
	local scaleCfg = CFG.scale or {}
	local rosterCfg = CFG.roster or {}
	local addonCfg = CFG.addonActive or {}
	local maxScale = tonumber(scaleCfg.max or 0) or 2.5
	local maxRoster = tonumber(rosterCfg.maxFactor or 0) or 1.25
	local maxAddon = tonumber(addonCfg.maxFactor or 0) or 2.5
	return b * maxScale * maxRoster * maxAddon
end

function GP.ComputePointsForNews(typ, groupKey, currentPoints, baseOverride)
	local base = baseOverride
	if base == nil then
		base = GP.GetTypePoints(typ)
	end
	base = tonumber(base or 0) or 0
	if base <= 0 then
		return 0, 0
	end
	local rosterFactor = GP.GetRosterFactor()
	local activeAddonCount = GetActiveAddonUsers((DB and DB.GetGuildUID and DB:GetGuildUID()) or nil)
	local addonCfg = CFG.addonActive or {}
	local addonRef = tonumber(addonCfg.reference or 0) or 0
	local addonMin = tonumber(addonCfg.minFactor or 0) or 0.35
	local addonMax = tonumber(addonCfg.maxFactor or 0) or 2.5
	local addonFactor = 1
	if addonRef > 0 then
		local raw = addonRef / math.max(1, activeAddonCount)
		addonFactor = Clamp(raw, addonMin, addonMax)
	end
	local groupCfg = GP.GetGroupConfig(groupKey) or {}
	local effectiveTarget = tonumber(groupCfg.target or 0) or 0
	if effectiveTarget > 0 then
		effectiveTarget = effectiveTarget * rosterFactor
	end
	local scale = GP.ComputeScale(groupKey, currentPoints, effectiveTarget)
	local pts = RoundPoints(base * scale * rosterFactor * addonFactor)
	if pts <= 0 then
		return 0, scale
	end
	return pts, scale
end

function GP.GetSummary(guildUID)
	local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID()) or nil
	if not gid then
		return nil
	end
	local progress = EnsureProgressRoot(gid)
	if not progress then
		return nil
	end

	local rosterFactor, recentHeroes = GP.GetRosterFactor()
	local groups = {}
	local totalPointsRaw = 0
	for i = 1, #CFG.groups do
		local groupCfg = CFG.groups[i]
		local key = groupCfg.key
		local points = GetGroupPoints(progress, key)
		local baseTarget = tonumber(groupCfg.target or 0) or 0
		local target = math.floor((baseTarget * rosterFactor) + 0.5)
		if baseTarget > 0 and target < 1 then
			target = 1
		end
		local ratio = (target > 0) and (points / target) or 0
		totalPointsRaw = totalPointsRaw + points
		groups[#groups + 1] = {
			key = key,
			label = groupCfg.label,
			points = points,
			target = target,
			ratio = ratio,
			color = groupCfg.color,
		}
	end

	local globalTarget = tonumber((CFG.global and CFG.global.target) or 0) or 0
	if globalTarget <= 0 then
		globalTarget = 10000
	end
	local totalRatio = (globalTarget > 0) and (totalPointsRaw / globalTarget) or 0
	local shareDenom = totalPointsRaw > 0 and totalPointsRaw or 1
	for i = 1, #groups do
		local g = groups[i]
		g.share = (g.points or 0) / shareDenom
	end
	return {
		guildUID = gid,
		rosterFactor = rosterFactor,
		recentHeroes = recentHeroes,
		totalPoints = totalPointsRaw,
		totalTarget = globalTarget,
		totalPointsRaw = totalPointsRaw,
		totalTargetRaw = globalTarget,
		totalRatio = totalRatio,
		groups = groups,
	}
end

local function EmitUpdate(guildUID)
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_GUILD_PROGRESS_UPDATED", guildUID)
	end
end

local broadcastPending = false
local progressPending = {}
local progressPendingAll = false
local function ScheduleBroadcast(uid, ts, forceAll)
	if uid and uid ~= "" then
		local cur = tonumber(progressPending[uid] or 0) or 0
		local nextTs = tonumber(ts or 0) or 0
		if nextTs > cur then
			progressPending[uid] = nextTs
		elseif cur == 0 and nextTs > 0 then
			progressPending[uid] = nextTs
		else
			progressPending[uid] = cur
		end
	elseif forceAll == true then
		progressPendingAll = true
	end

	if broadcastPending then
		return
	end
	broadcastPending = true
	if C_Timer and C_Timer.After then
		C_Timer.After(0.6, function()
			broadcastPending = false
			local gid = DB and DB.GetGuildUID and DB:GetGuildUID()
			if Comms and Comms.SYNC_ENABLED and Comms.Sync and Comms.Sync.AnnounceElement and gid then
				if progressPendingAll then
					Comms.Sync.AnnounceAll(gid, { type = "progress" })
				else
					for pUid, pTs in pairs(progressPending) do
						Comms.Sync.AnnounceElement(gid, "progress", pUid, pTs)
					end
				end
			elseif Comms and Comms.BroadcastSnapshot then
				Comms:BroadcastSnapshot()
			end
			progressPending = {}
			progressPendingAll = false
		end)
	else
		broadcastPending = false
		if Comms and Comms.BroadcastSnapshot then
			Comms:BroadcastSnapshot()
		end
	end
end

function GP.AddPoints(guildUID, uid, groupKey, points, eventTs)
	local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID()) or nil
	if not gid or not uid or uid == "" or not groupKey then
		return false
	end
	local pts = tonumber(points or 0) or 0
	if pts <= 0 then
		return false
	end
	local ts = tonumber(eventTs or 0) or Now()
	if DB and DB.AddGuildProgressPoints then
		DB:AddGuildProgressPoints(gid, uid, groupKey, pts, ts)
	else
		local progress = EnsureProgressRoot(gid)
		if not progress then
			return false
		end
		progress.groups = progress.groups or {}
		local group = progress.groups[groupKey] or { byUID = {}, updatedAt = 0 }
		local entry = group.byUID[uid] or { points = 0, events = 0, updatedAt = 0 }
		entry.points = (tonumber(entry.points or 0) or 0) + pts
		entry.events = (tonumber(entry.events or 0) or 0) + 1
		entry.updatedAt = ts
		group.byUID[uid] = entry
		group.updatedAt = math.max(tonumber(group.updatedAt or 0) or 0, ts)
		progress.groups[groupKey] = group
		progress.updatedAt = math.max(tonumber(progress.updatedAt or 0) or 0, ts)
	end
	EmitUpdate(gid)
	ScheduleBroadcast(uid, ts)
	return true
end

function GP.AddPointsForNews(item, guildUID)
	if not item or not item.id then
		return false
	end
	local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID()) or nil
	if not gid then
		return false
	end
	local uid = (DB and DB.GetMyUID and DB:GetMyUID()) or nil
	if not uid then
		return false
	end
	local ts = tonumber(item.ts or 0) or Now()
	if not MarkSeen(gid, tostring(item.id), ts) then
		return false
	end
	local typ = tostring(item.type or item.typ or "generic"):lower()
	local groupKey = GP.GetGroupKeyForType(typ)
	local progress = EnsureProgressRoot(gid)
	local currentPoints = GetGroupPoints(progress, groupKey)
	local base = item.points
	local expectedBase = (ns.Data and ns.Data.NewsPoints and ns.Data.NewsPoints[typ]) or nil
	if expectedBase ~= nil and base ~= nil then
		local tol = tonumber((CFG.security and CFG.security.pointsTolerance) or 0) or 0.01
		local diff = math.abs((tonumber(base) or 0) - (tonumber(expectedBase) or 0))
		if diff > tol then
			if DB and DB.ResetGuildProgressForUID then
				DB:ResetGuildProgressForUID(gid, uid, "points_mismatch")
			end
			DevLog(
				("reject points_mismatch type=%s base=%s expected=%s"):format(
					tostring(typ),
					tostring(base),
					tostring(expectedBase)
				)
			)
			return false
		end
	end
	if base == nil then
		base = expectedBase
	end
	local pts = GP.ComputePointsForNews(typ, groupKey, currentPoints, base)
	local maxAllowed = GetMaxAllowedPoints(base)
	if maxAllowed > 0 and pts > (maxAllowed + 0.01) then
		if DB and DB.ResetGuildProgressForUID then
			DB:ResetGuildProgressForUID(gid, uid, "max_per_event")
		end
		DevLog(("reject max_per_event pts=%.2f max=%.2f uid=%s"):format(pts, maxAllowed, tostring(uid)))
		return false
	end
	if pts <= 0 then
		DevLog(("reject pts<=0 type=%s base=%s"):format(tostring(typ), tostring(base)))
		return false
	end
	item.points = base
	LogPoints("local", {
		ts = ts,
		guildUID = gid,
		uid = uid,
		groupKey = groupKey,
		typ = typ,
		itemId = item.id,
		replaceKey = item.replaceKey,
		base = base,
		points = pts,
	})
	return GP.AddPoints(gid, uid, groupKey, pts, ts)
end

function GP.AddPointsForRemoteNews(kv, guildUID, sender, senderUID)
	if type(kv) ~= "table" or not kv.id then
		return false
	end
	local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID()) or nil
	if not gid then
		return false
	end
	local uid = ResolveUIDForSender(gid, sender, kv.uid or senderUID)
	if not uid then
		DevLog(("skip remote: uid not found sender=%s"):format(tostring(sender or "?")))
		return false
	end
	local myUID = DB and DB.GetMyUID and DB:GetMyUID() or nil
	if myUID and uid == myUID then
		return false
	end
	local ts = tonumber(kv.ts or 0) or Now()
	if not MarkSeen(gid, tostring(kv.id), ts) then
		return false
	end
	local typ = tostring(kv.typ or kv.type or "generic"):lower()
	local groupKey = GP.GetGroupKeyForType(typ)
	local pts = tonumber(kv.points or 0) or 0
	if pts <= 0 then
		local base = (ns.Data and ns.Data.NewsPoints and ns.Data.NewsPoints[typ]) or nil
		local progress = EnsureProgressRoot(gid)
		local currentPoints = GetGroupPoints(progress, groupKey)
		if GP.ComputePointsForNews then
			pts = GP.ComputePointsForNews(typ, groupKey, currentPoints, base)
		end
	end
	local expectedBase = (ns.Data and ns.Data.NewsPoints and ns.Data.NewsPoints[typ]) or nil
	local maxAllowed = GetMaxAllowedPoints(expectedBase)
	if maxAllowed > 0 and pts > (maxAllowed + 0.01) then
		if DB and DB.ResetGuildProgressForUID then
			DB:ResetGuildProgressForUID(gid, uid, "max_per_event")
		end
		DevLog(("reject remote max_per_event pts=%.2f max=%.2f uid=%s"):format(pts, maxAllowed, tostring(uid)))
		return false
	end
	if pts <= 0 then
		DevLog(("reject remote pts<=0 type=%s sender=%s"):format(tostring(typ), tostring(sender or "?")))
		return false
	end
	LogPoints("remote", {
		ts = ts,
		guildUID = gid,
		uid = uid,
		groupKey = groupKey,
		typ = typ,
		itemId = kv.id,
		replaceKey = kv.replaceKey,
		base = expectedBase,
		points = pts,
		sender = sender,
	})
	return GP.AddPoints(gid, uid, groupKey, pts, ts)
end

function GP.GetDebugPoints()
	if not GP._debugPoints or type(GP._debugPoints.order) ~= "table" then
		return {}
	end
	return GP._debugPoints.order
end

function GP.RebuildFromNews(guildUID, opts)
	local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID()) or nil
	if not gid then
		return false, "no_guild"
	end
	local g = WoWGuildeDB and WoWGuildeDB.guilds and WoWGuildeDB.guilds[gid]
	if not g or not g.news or type(g.news.items) ~= "table" then
		return false, "no_news"
	end
	local items = g.news.items
	if #items == 0 then
		return false, "empty"
	end
	local progress = EnsureProgressRoot(gid)
	if not progress then
		return false, "no_progress"
	end
	if opts and opts.clear then
		progress.groups = {}
		progress.updatedAt = 0
	end
	local added = 0
	for i = 1, #items do
		local it = items[i]
		if it and it.id and it.type then
			local uid = it.uid or ExtractUIDFromReplaceKey(it.replaceKey)
			local pts = tonumber(it.points or 0) or 0
			if uid and pts > 0 then
				local groupKey = GP.GetGroupKeyForType(tostring(it.type or "generic"):lower())
				if groupKey and DB and DB.AddGuildProgressPoints then
					DB:AddGuildProgressPoints(gid, uid, groupKey, pts, it.ts)
					added = added + 1
				end
			end
		end
	end
	progress.rebuiltAt = Now()
	EmitUpdate(gid)
	ScheduleBroadcast(nil, nil, true)
	return true, added
end

-- =========================================================
-- Events
-- =========================================================
if EventBus and EventBus.On then
	EventBus.On("WG_NEWS_CREATED", function(_, item, guildUID, noBroadcast)
		if noBroadcast == true then
			return
		end
		GP.AddPointsForNews(item, guildUID)
	end)

	EventBus.On("WG_NEWS_RECEIVED", function(_, kv, guildUID, sender)
		GP.AddPointsForRemoteNews(kv, guildUID, sender, kv and kv.uid)
	end)

	EventBus.On("PLAYER_LOGIN", function()
		local ok = true
		local current, previous
		ok, current, previous = ValidatePointsTable()
		if not ok then
			local gid = DB and DB.GetGuildUID and DB:GetGuildUID()
			local uid = DB and DB.GetMyUID and DB:GetMyUID()
			if gid and uid and DB and DB.ResetGuildProgressForUID then
				DB:ResetGuildProgressForUID(gid, uid, "points_table_changed")
			end
			if print then
				print(
					("|cffffd100[WoW Guilde]|r Points table changed (%s -> %s). Reset applied."):format(
						tostring(previous or "nil"),
						tostring(current or "nil")
					)
				)
			end
		end
		local gid = DB and DB.GetGuildUID and DB:GetGuildUID()
		local uid = DB and DB.GetMyUID and DB:GetMyUID()
		if gid and uid then
			ValidateMyProgress(gid, uid)
		end
		if gid then
			local progress = EnsureProgressRoot(gid)
			if progress and IsProgressEmpty(progress) and not progress.rebuiltAt then
				local okRebuild, info = GP.RebuildFromNews(gid, { clear = true })
				if IsDevMode() and print then
					print(
						("|cffffd100[WoW Guilde]|r GP rebuild=%s info=%s"):format(
							tostring(okRebuild),
							tostring(info or "")
						)
					)
				end
			end
		end
	end)
end
