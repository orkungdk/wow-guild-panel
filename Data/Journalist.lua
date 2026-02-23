local ADDON, ns = ...
local EventBus = ns.EventBus

ns.Data = ns.Data or {}
local Journalist = {}
ns.Data.Journalist = Journalist

ns.Data.NewsRegistry = ns.Data.NewsRegistry or { order = {}, items = {} }
local NewsRegistry = ns.Data.NewsRegistry

-- Register accepte :
-- 1) function: Register("achievement", fn)
-- 2) table: Register("achievement", { run=fn, trigger=..., meta=... })
--
-- trigger peut être :
-- - nil / absent : run toujours (comportement actuel)
-- - table : { intelField="achievementAt" }  -> run quand intel.last.achievementAt change
--           { everySeconds=5 }              -> run max toutes les X secondes
--           { always=true }                 -> run toujours
-- - function(intelProxy, last, uid, now) -> true/false (contrôle total par le module)
function NewsRegistry.Register(key, def)
	if not key or key == "" or not def then
		return
	end

	local entry = def
	if type(def) == "function" then
		entry = { run = def }
	elseif type(def) == "table" then
		-- accepte { fn=... } ou { run=... }
		entry.run = entry.run or entry.fn
	end

	if type(entry) ~= "table" or type(entry.run) ~= "function" then
		return
	end

	if not NewsRegistry.items[key] then
		NewsRegistry.order[#NewsRegistry.order + 1] = key
	end

	entry.key = key
	NewsRegistry.items[key] = entry
end

-- =========================================================
-- Journaliste : utilitaires et helpers de base
-- =========================================================

local GetPlayerDisplayName
local AddRawNews
local GetNewsTTLSeconds
local GetNewsMeta

local function Now()
	return time and time() or 0
end

local function Pick(list)
	if not list or #list == 0 then
		return nil
	end
	return list[math.random(#list)]
end

local function FormatDuration(sec)
	sec = math.floor(tonumber(sec or 0) or 0)
	if sec < 60 then
		return sec .. "s"
	end
	local m = math.floor(sec / 60)
	if m < 60 then
		return m .. " min"
	end
	local h = math.floor(m / 60)
	local mm = m % 60
	if mm == 0 then
		return h .. "h"
	end
	return h .. "h" .. string.format("%02d", mm)
end

local function FormatIlvl(v)
	v = tonumber(v or 0) or 0
	if v <= 0 then
		return "0"
	end
	return tostring(math.floor(v))
end

local function GetNewsTitle(typ)
	if not typ or typ == "" then
		return "Actualité"
	end
	local map = {
		achievement = "Basarilar",
		mount = "Binek",
		toy = "Oyuncak",
		transmog = "Gorunum",
		connection = "Baglanti",
		guild = "Guild",
		guildchat = "Guild mesaji",
		pve = "Zindanlar",
		cible = "Hedefler",
		cibles = "Hedefler",
		raid = "Raid",
		mplus = "Mythic+",
		loot = "Ganimet",
		woodharvest = "Odun toplama",
		herbharvest = "Bitki toplama",
		fishingharvest = "Balikcilik",
		oreharvest = "Maden toplama",
		housing = "Konut",
		housingcleanup = "Ada bakimi",
		housingdecor = "Konut esyalari",
		collection = "Koleksiyon",
		world = "Dunya",
		quest = "Gorevler",
		questdaily = "Gunluk gorevler",
		worldquest = "Kesifler",
		level = "Seviye",
		gear = "Ekipman",
		spec = "Uzmanlik",
		death = "Olumler",
		pvp = "PvP",
		social = "Sosyal",
		generic = "Diger",
	}
	return map[typ] or "Actualite"
end

GetNewsMeta = function(key)
	local meta = ns.Data and ns.Data.NewsMeta or {}
	if key and meta[key] then
		local v = meta[key]
		if type(v) == "table" then
			return v
		end
		if type(v) == "string" then
			return { title = v }
		end
	end
	return nil
end

local function GetMetaKey(typ, replaceKey)
	local meta = ns.Data and ns.Data.NewsMeta or {}
	if replaceKey and replaceKey ~= "" then
		local prefix = replaceKey:match("^([^:]+)")
		if prefix and meta[prefix] ~= nil then
			return prefix
		end
	end
	if type(typ) == "string" then
		if meta[typ] ~= nil then
			return typ
		end
		local lower = typ:lower()
		if meta[lower] ~= nil then
			return lower
		end
	end
	return nil
end

GetNewsTTLSeconds = function(key, replaceKey)
	local cfg = ns.Data and ns.Data.NewsTTL or {}
	local daySeconds = tonumber(cfg.daySeconds or 86400) or 86400
	local monthDays = tonumber(cfg.monthDays or 30) or 30
	local function toSeconds(value)
		return (tonumber(value) or 0) * daySeconds
	end
	local function toMonths(value)
		return (tonumber(value) or 0) * monthDays * daySeconds
	end
	local function resolveTTLValue(value)
		if type(value) == "table" then
			if value.seconds then
				return tonumber(value.seconds) or 0
			end
			if value.minutes then
				return (tonumber(value.minutes) or 0) * 60
			end
			if value.hours then
				return (tonumber(value.hours) or 0) * 3600
			end
			if value.days then
				return toSeconds(value.days)
			end
			if value.months then
				return toMonths(value.months)
			end
			return 0
		end
		local asNumber = tonumber(value)
		if asNumber then
			return toSeconds(asNumber)
		end
		return 0
	end

	if replaceKey and replaceKey:find("^presence:") then
		local ttl = resolveTTLValue(cfg.session)
		return ttl > 0 and ttl or 60
	end

	if key and cfg[key .. "_seconds"] then
		local ttl = tonumber(cfg[key .. "_seconds"]) or 0
		if ttl > 0 then
			return ttl
		end
	end
	if key and cfg[key] then
		local ttl = resolveTTLValue(cfg[key])
		if ttl > 0 then
			return ttl
		end
	end
	if cfg.default then
		local ttl = resolveTTLValue(cfg.default)
		if ttl > 0 then
			return ttl
		end
	end
	return 14 * daySeconds
end

local function GetRemovedAt(key, ts, ttlOverride, replaceKey)
	local createdAt = tonumber(ts or 0) or 0
	if createdAt <= 0 then
		createdAt = Now()
	end
	local ttl = tonumber(ttlOverride or 0) or 0
	if ttl <= 0 then
		ttl = GetNewsTTLSeconds(key, replaceKey)
	end
	if ttl <= 0 then
		local cfg = ns.Data and ns.Data.NewsTTL or {}
		local daySeconds = tonumber(cfg.daySeconds or 86400) or 86400
		ttl = 14 * daySeconds
	end
	return createdAt + ttl
end

local function GetAchievementNameIconSafe(id)
	if not id or not GetAchievementInfo then
		return nil, nil
	end
	local name, _, _, _, _, _, _, flags, icon = GetAchievementInfo(id)
	if
		(not name or name == "" or not icon or icon == 0)
		and C_AchievementInfo
		and C_AchievementInfo.GetAchievementInfo
	then
		local info = C_AchievementInfo.GetAchievementInfo(id)
		if info then
			name = name ~= "" and name or info.name
			icon = (icon and icon ~= 0) and icon or info.iconFileID or info.icon
		end
	end
	local function hasFeatFlag(v)
		if not v or not ACHIEVEMENT_FLAGS_FEAT_OF_STRENGTH then
			return false
		end
		if bit and bit.band then
			return bit.band(v, ACHIEVEMENT_FLAGS_FEAT_OF_STRENGTH) > 0
		end
		if bit32 and bit32.band then
			return bit32.band(v, ACHIEVEMENT_FLAGS_FEAT_OF_STRENGTH) > 0
		end
		return false
	end
	if icon and flags and hasFeatFlag(icon) and not hasFeatFlag(flags) then
		icon, flags = flags, icon
	end
	return name, icon
end

local function ResolveAchievementInfo(entry)
	if not entry then
		return nil, nil
	end

	-- Support legacy numeric entries that only store the achievement id.
	if type(entry) == "number" or type(entry) == "string" then
		local id = tonumber(entry)
		local achName, achIcon = GetAchievementNameIconSafe(id)
		if achName or achIcon then
			return achName or tostring(id), achIcon
		end
		return tostring(entry), nil
	end

	if not entry.id then
		return entry.name or nil, entry.icon or nil
	end

	local id = tonumber(entry.id)
	if not id then
		return entry.name, entry.icon
	end

	local name = entry.name
	local icon = entry.icon
	local needsName = (not name or name == "" or tostring(name) == tostring(id))
	local needsIcon = (not icon or icon == 0)
	if (needsName or needsIcon) and GetAchievementInfo then
		local achName, achIcon = GetAchievementNameIconSafe(id)
		if needsName and achName and achName ~= "" then
			name = achName
			entry.name = achName
		end
		if needsIcon and achIcon and achIcon ~= 0 then
			icon = achIcon
			entry.icon = achIcon
		end
	end
	return name, icon
end

local WINDOW_SECONDS = 48 * 3600

local function CountSince(list, since)
	if not list or #list == 0 then
		return 0, nil
	end
	local count = 0
	local last = nil
	for i = 1, #list do
		local entry = list[i]
		local ts = entry
		if type(entry) == "table" then
			ts = entry.ts
		end
		if ts and ts >= since then
			count = count + 1
			last = entry
		end
	end
	return count, last
end

local function MapRaidDifficultyKey(difficultyID)
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

local function CountSinceTypeFlagDifficultyKey(list, since, instanceType, isCurrent, diffKey)
	if not list or #list == 0 then
		return 0, nil
	end
	local count = 0
	local last = nil
	for i = 1, #list do
		local entry = list[i]
		if type(entry) == "table" then
			local ts = entry.ts
			local matchCurrent = (entry.isCurrent == isCurrent)
			if isCurrent == true and entry.isCurrent == nil then
				matchCurrent = true
			end
			local entryKey = entry.difficultyKey or MapRaidDifficultyKey(entry.difficultyID)
			if ts and ts >= since and entry.instanceType == instanceType and matchCurrent and entryKey == diffKey then
				count = count + 1
				last = entry
			end
		end
	end
	return count, last
end

local function ListTailTs(list)
	if not list or #list == 0 then
		return 0
	end
	local entry = list[#list]
	if type(entry) == "table" then
		return tonumber(entry.ts or 0) or 0
	end
	return tonumber(entry or 0) or 0
end

local function GetGuildUID()
	if ns.DB and ns.DB.GetGuildUID then
		return ns.DB:GetGuildUID()
	end
	return nil
end

local function GetMyUID()
	if ns.DB and ns.DB.GetMyUID then
		return ns.DB:GetMyUID()
	end
	return nil
end

local function GetMyPublicNote()
	local name, realm = UnitFullName("player")
	if not name then
		return ""
	end
	local myFull = name .. "-" .. (realm or GetRealmName() or "")
	local num = GetNumGuildMembers() or 0
	for i = 1, num do
		local fullName, _, _, _, _, _, note = GetGuildRosterInfo(i)
		if fullName == myFull then
			return tostring(note or "")
		end
	end
	return ""
end

local function ContainsDoNotTrackTag(text)
	if type(text) ~= "string" or text == "" then
		return false
	end
	if text:find("%[%s*[dD][nN][dD]%s*%]") then
		return true
	end
	if text:find("%[%s*[dD][nN][tT]%s*%]") then
		return true
	end
	return false
end

local function PayloadContainsDoNotTrackTag(value, seen)
	local vt = type(value)
	if vt == "string" then
		return ContainsDoNotTrackTag(value)
	end
	if vt ~= "table" then
		return false
	end
	seen = seen or {}
	if seen[value] then
		return false
	end
	seen[value] = true
	for k, v in pairs(value) do
		if PayloadContainsDoNotTrackTag(k, seen) or PayloadContainsDoNotTrackTag(v, seen) then
			return true
		end
	end
	return false
end

local function GetCachedAlias()
	if not (ns.Utils and ns.Utils.PSEUDO_CACHE) then
		return nil
	end
	local name, realm = UnitFullName("player")
	if not name or name == "" then
		return nil
	end
	local full = name .. "-" .. (realm or GetRealmName() or "")
	local rec = ns.Utils.PSEUDO_CACHE[full] or ns.Utils.PSEUDO_CACHE[name]
	if rec and rec.alias and rec.alias ~= "" then
		return rec.alias
	end
	return nil
end

GetPlayerDisplayName = function()
	local name = UnitName and UnitName("player") or nil
	local alias = GetCachedAlias()
	if not alias or alias == "" then
		local note = GetMyPublicNote()
		if ns.Utils and ns.Utils.AliasFromNote then
			alias = ns.Utils.AliasFromNote(note)
		elseif ns.Utils and ns.Utils.ParsePseudo then
			alias = (ns.Utils.ParsePseudo(note, name))
		end
	end
	if alias and alias ~= "" then
		return alias
	end
	if not name or name == "" then
		local full = UnitFullName and UnitFullName("player") or nil
		if full then
			return full
		end
		return "Le joueur"
	end
	return name
end

-- =========================================================
-- Journaliste : accès et stockage des news
-- =========================================================

local function EnsureGuildRoot(guildUID)
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
	if type(g.guildInfo) ~= "table" then
		g.guildInfo = { guildUID = guildUID }
	end
	g.news = g.news or { items = {}, updatedAt = 0, nextId = 0, lastClean = 0 }
	if type(g.newsAnalyste) ~= "table" then
		g.newsAnalyste = { modules = {} }
	end
	return g
end

local function EnsureJournalistModules(g)
	if not g then
		return nil
	end
	if type(g.newsAnalyste) ~= "table" then
		g.newsAnalyste = {}
	end
	g.newsAnalyste.modules = g.newsAnalyste.modules or {}
	return g.newsAnalyste.modules
end

local function GetJournalistModuleLast(g, key)
	if not g or not key then
		return nil
	end
	local modules = EnsureJournalistModules(g)
	modules[key] = modules[key] or {}
	return modules[key]
end

local function RemoveNewsByReplaceKey(g, replaceKey)
	if not g or not g.news or not g.news.items or not replaceKey or replaceKey == "" then
		return
	end
	for i = #g.news.items, 1, -1 do
		local n = g.news.items[i]
		if n and n.replaceKey == replaceKey then
			table.remove(g.news.items, i)
		end
	end
end

local function RemoveNewsById(guildUID, id)
	if not guildUID or not id or id == "" then
		return false
	end
	local g = EnsureGuildRoot(guildUID)
	if not g or not g.news or not g.news.items then
		return false
	end
	local removed = false
	for i = #g.news.items, 1, -1 do
		local n = g.news.items[i]
		if n and n.id == id then
			table.remove(g.news.items, i)
			removed = true
		end
	end
	if removed then
		g.news.updatedAt = Now()
		if ns.Data and ns.Data.NewsFeed and ns.Data.NewsFeed.RemoveById then
			ns.Data.NewsFeed.RemoveById(id)
		end
		if EventBus and EventBus.Emit then
			EventBus.Emit("WG_NEWS_REMOVED", id, guildUID)
		end
		if ns and ns.Comms and ns.Comms.DEV_MODE then
			print("|cffffd100[WoW Guilde]|r NEWS supprimée " .. tostring(id))
		end
	end
	return removed
end

-- =========================================================
-- Journaliste : creation et nettoyage des actualites
-- =========================================================

AddRawNews = function(g, textOrPayload, typ, icon, ts, replaceKey, noBroadcast, idOverride, title, removedAtOverride)
	if not g or not g.news then
		return
	end

	-- Nouveau format : AddRawNews(g, { text=..., type=..., icon=..., ts=..., replaceable=..., replaceKey=..., ttlSeconds=..., removedAt=... })
	local payload = nil
	if type(textOrPayload) == "table" then
		payload = textOrPayload
	else
		payload = {
			text = textOrPayload,
			type = typ,
			icon = icon,
			ts = ts,
			replaceKey = replaceKey,
			noBroadcast = noBroadcast,
			id = idOverride,
			title = title,
			removedAt = removedAtOverride,
		}
	end

	-- Garde-fou global: si un élément du payload contient [DND] ou [DNT],
	-- on ignore complètement cette actu.
	if PayloadContainsDoNotTrackTag(payload) then
		return false
	end

	local text = payload.text
	if type(text) ~= "string" or text == "" then
		return
	end

	local news = g.news
	local createdAt = tonumber(payload.ts) or Now()
	local pType = payload.type
	local pIcon = payload.icon
	local pTitle = payload.title
	local pId = payload.id
	local pReplaceKey = payload.replaceKey
	local pReplaceable = payload.replaceable
	local pTtlSeconds = payload.ttlSeconds
	local pRemovedAt = payload.removedAt
	local pUID = payload.uid
	if not pUID and payload.noBroadcast ~= true then
		pUID = GetMyUID()
	end

	-- Neutralité: le module décide explicitement.
	-- Rétro-compat: si replaceable non fourni, on garde le comportement historique (replaceKey => remplaçable).
	local isReplaceable
	if pReplaceable == nil then
		isReplaceable = (type(pReplaceKey) == "string" and pReplaceKey ~= "")
	else
		isReplaceable = (pReplaceable == true) and (type(pReplaceKey) == "string" and pReplaceKey ~= "")
	end

	-- Dédup / mise à jour par id
	local existingIndex = nil
	local existingItem = nil
	if pId and news.items then
		for i = #news.items, 1, -1 do
			local n = news.items[i]
			if n and n.id == pId then
				existingIndex = i
				existingItem = n
				break
			end
		end
	end

	-- Remplacement UNIQUEMENT si explicitement remplaçable
	if isReplaceable then
		if pReplaceKey and pReplaceKey ~= "" then
			-- Supprime uniquement les autres items avec la même replaceKey
			for i = #news.items, 1, -1 do
				local n = news.items[i]
				if n and n.replaceKey == pReplaceKey and (not existingItem or n.id ~= existingItem.id) then
					table.remove(news.items, i)
				end
			end
		end
	else
		pReplaceKey = "" -- pas de replaceKey stocké si non remplaçable (évite toute confusion)
	end

	-- Si on a déjà cet ID, on garde le plus récent
	if existingItem then
		local existingTs = tonumber(existingItem.ts) or 0
		if createdAt <= existingTs then
			return false
		end
	end

	-- ID
	local nid = pId
	if not nid then
		news.nextId = (tonumber(news.nextId or 0) or 0) + 1
		nid = ("jrnl:%d:%d"):format(createdAt, news.nextId)
	end

	-- Péremption : le module peut fournir removedAt ou ttlSeconds.
	-- Rétro-compat: si rien fourni, fallback sur GetRemovedAt() (ancien comportement).
	local removedAt = 0
	if pRemovedAt then
		removedAt = tonumber(pRemovedAt) or 0
	elseif pTtlSeconds then
		local ttl = tonumber(pTtlSeconds) or 0
		removedAt = (ttl > 0) and (createdAt + ttl) or 0
	else
		removedAt = GetRemovedAt(pType, createdAt, nil, pReplaceKey)
	end

	-- Type + title : on respecte ce que donne le module, avec fallback meta/title existant.
	local metaKey = GetMetaKey(pType, pReplaceKey)
	local meta = metaKey and GetNewsMeta(metaKey) or GetNewsMeta(pType)

	local resolvedType = pType
	if type(meta) == "table" and type(meta.type) == "string" and (not resolvedType or resolvedType == "") then
		resolvedType = meta.type
	end
	if type(resolvedType) == "string" then
		resolvedType = resolvedType:lower()
	end

	local resolvedTitle = pTitle
	if not resolvedTitle or resolvedTitle == "" then
		resolvedTitle = (meta and type(meta.title) == "string" and meta.title) or GetNewsTitle(resolvedType)
	end

	-- Points: désormais définis directement par chaque module news.

	local points = tonumber(payload.points or 0) or 0

	local item = {
		id = nid,
		text = text,
		type = resolvedType or "generic",
		title = resolvedTitle,
		icon = pIcon or 134400,
		ts = createdAt,
		removedAt = removedAt,
		replaceKey = pReplaceKey or "",
		points = points,
		uid = pUID,
	}

	-- Mise à jour si même ID déjà présent
	if existingItem and existingIndex then
		news.items[existingIndex] = item
		news.updatedAt = Now()

		if ns.Data and ns.Data.NewsFeed then
			if ns.Data.NewsFeed.RemoveById then
				ns.Data.NewsFeed.RemoveById(nid)
			end
			if ns.Data.NewsFeed.Add then
				ns.Data.NewsFeed.Add(
					item.text,
					item.type,
					item.icon,
					item.ts,
					item.id,
					nil,
					g.guildInfo and g.guildInfo.guildUID or nil,
					item.replaceKey,
					item.title,
					item.removedAt,
					item.uid
				)
			end
		end

		if EventBus and EventBus.Emit then
			EventBus.Emit(
				"WG_NEWS_CREATED",
				item,
				g.guildInfo and g.guildInfo.guildUID or nil,
				payload.noBroadcast == true
			)
		end

		if ns and ns.Comms and ns.Comms.DEV_MODE then
			print("|cffffd100[WoW Guilde]|r NEWS maj " .. tostring(item.id))
		end

		return true
	end

	news.items[#news.items + 1] = item
	if #news.items > 300 then
		table.remove(news.items, 1)
	end

	news.updatedAt = Now()

	if ns.Data and ns.Data.NewsFeed and ns.Data.NewsFeed.Add then
		ns.Data.NewsFeed.Add(
			item.text,
			item.type,
			item.icon,
			item.ts,
			item.id,
			nil,
			g.guildInfo and g.guildInfo.guildUID or nil,
			item.replaceKey,
			item.title,
			item.removedAt,
			item.uid
		)
	end

	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_NEWS_CREATED", item, g.guildInfo and g.guildInfo.guildUID or nil, payload.noBroadcast == true)
	end

	if ns and ns.Comms and ns.Comms.DEV_MODE then
		print("|cffffd100[WoW Guilde]|r NEWS créée " .. tostring(item.id))
	end

	if not payload.noBroadcast and ns.Comms and ns.Comms.SendNews then
		ns.Comms:SendNews(
			item.text,
			item.type,
			item.icon,
			item.ts,
			item.replaceKey,
			g.guildInfo and g.guildInfo.guildUID or nil,
			item.id,
			0,
			nil,
			item.title,
			item.points
		)
	end

	return true
end

local function CleanupAgedNews(g, maxAge)
	if not g or not g.news or not g.news.items then
		return
	end
	local now = Now()
	if g.news.lastClean and now - g.news.lastClean < 60 then
		return
	end
	local cutoff = now - (maxAge or 14 * 86400)
	for i = #g.news.items, 1, -1 do
		local n = g.news.items[i]
		if n and n.ts and n.ts < cutoff then
			if ns.Data and ns.Data.NewsFeed and ns.Data.NewsFeed.RemoveById then
				ns.Data.NewsFeed.RemoveById(n.id)
			end
			table.remove(g.news.items, i)
		end
	end
	g.news.lastClean = now
end

local function CleanupExpiredNewsEverywhere(now)
	if not WoWGuildeDB or not WoWGuildeDB.guilds then
		return
	end
	for _, g in pairs(WoWGuildeDB.guilds) do
		if g and g.news and g.news.items then
			for i = #g.news.items, 1, -1 do
				local n = g.news.items[i]
				local removedAt = n and tonumber(n.removedAt or 0) or 0
				if removedAt > 0 and removedAt <= now then
					if ns.Data and ns.Data.NewsFeed and ns.Data.NewsFeed.RemoveById then
						ns.Data.NewsFeed.RemoveById(n.id)
					end
					table.remove(g.news.items, i)
				end
			end
		end
	end
end

local function PruneProudForGuild(g)
	if not g or not g.news or not g.news.items then
		return
	end
	if not g.proudNews then
		return
	end
	local keep = {}
	for i = 1, #g.news.items do
		local n = g.news.items[i]
		if n and n.id then
			keep[n.id] = true
		end
	end

	local function pruneStore(key)
		local t = g.proudNews and g.proudNews[key]
		if type(t) ~= "table" then
			return
		end
		local changed = false
		for id in pairs(t) do
			if not keep[id] then
				t[id] = nil
				changed = true
			end
		end
	end

	pruneStore("proudByMe")
	pruneStore("proudByCharacter")
	pruneStore("proudByCharacterMeta")
end

ns.Data.JournalistAPI = ns.Data.JournalistAPI or {}
local JournalistAPI = ns.Data.JournalistAPI
JournalistAPI.Pick = Pick
JournalistAPI.FormatIlvl = FormatIlvl
JournalistAPI.FormatDuration = FormatDuration
JournalistAPI.GetPlayerDisplayName = GetPlayerDisplayName
JournalistAPI.GetMyPublicNote = GetMyPublicNote
JournalistAPI.GetCachedAlias = GetCachedAlias
JournalistAPI.ResolveAchievementInfo = ResolveAchievementInfo
JournalistAPI.RemoveNewsByReplaceKey = RemoveNewsByReplaceKey
JournalistAPI.AddRawNews = AddRawNews
JournalistAPI.GetRemovedAt = GetRemovedAt
JournalistAPI.CountSince = CountSince
JournalistAPI.ListTailTs = ListTailTs
JournalistAPI.CountSinceTypeFlagDifficultyKey = CountSinceTypeFlagDifficultyKey
JournalistAPI.WindowSeconds = WINDOW_SECONDS
JournalistAPI.RemoveNewsById = RemoveNewsById
JournalistAPI.AddRemoteNewsPayload = Journalist.AddRemoteNewsPayload

-- =========================================================
-- Journaliste : orchestration
-- =========================================================

ns.Data.JournalistProcessorOrder = {
	"windowtime",
	"killtype",
	"deaths",
	"mplusmilestone",
	"mplus",
	"dungeonboss",
	"raidboss",
	"loot",
	"merchantgold",
	"merchantitems",
	"woodharvest",
	"herbharvest",
	"fishingharvest",
	"oreharvest",
	"housing",
	"housingcleanup",
	"housingdecor",
	"epiccollectibles",
	"achievement",
	"level",
	"itemlevel",
	"spec",
	"zone",
	"mount",
	"toy",
	"transmog",
	"lfg",
	"pvpkills",
	"guildchat",
	"guildgg",
	"honorlevel",
	"session",
}

local function MakeIntelModuleProxy(intel, moduleKey)
	if not intel then
		return nil
	end
	local pigapi = ns.Data and ns.Data.PigisteAPI
	local moduleLast
	if pigapi and pigapi.GetModuleLast then
		moduleLast = pigapi.GetModuleLast(intel, moduleKey)
	else
		intel.last = intel.last or {}
		moduleLast = intel.last
	end
	return setmetatable({ last = moduleLast }, { __index = intel })
end

local function RunRegisteredNews(g, intel, uid, now, eventName)
	local registry = ns.Data and ns.Data.NewsRegistry
	if not registry or not registry.items then
		return false
	end

	local function EventMatches(trigger, eventName)
		if not eventName or eventName == "" then
			return false
		end
		if type(trigger) ~= "table" then
			return false
		end
		local ev = trigger.events
		if not ev then
			return false
		end
		if type(ev) == "string" then
			return ev == eventName
		end
		if type(ev) == "table" then
			-- accepte { "A", "B" } ou { A=true, B=true }
			if ev[eventName] == true then
				return true
			end
			for i = 1, #ev do
				if ev[i] == eventName then
					return true
				end
			end
		end
		return false
	end

	local function ShouldRun(def, intelProxy, last, uid, now, eventName)
		-- legacy : registry.items[key] = function(...)
		if type(def) == "function" then
			return true, def
		end
		if type(def) ~= "table" or type(def.run) ~= "function" then
			return false, nil
		end

		local trig = def.trigger

		-- aucun trigger => run toujours (legacy)
		if trig == nil then
			return true, def.run
		end

		-- event-driven : ne run que si l'event matche
		if type(trig) == "table" and trig.events then
			if eventName and EventMatches(trig, eventName) then
				return true, def.run
			end
			-- neutralité : pas d'event => on ne force pas l'exécution
			-- (si tu veux un fallback, le module peut ajouter trig.everySeconds)
		end

		-- fallback optionnel (si un module le demande explicitement)
		if type(trig) == "table" and trig.everySeconds then
			local every = tonumber(trig.everySeconds) or 0
			if every > 0 then
				local prev = tonumber(last._lastRunAt) or 0
				if prev == 0 or (now - prev) >= every then
					return true, def.run
				end
			end
		end

		-- trigger custom (contrôle total)
		if type(trig) == "function" then
			return trig(intelProxy, last, uid, now, eventName) == true, def.run
		end

		-- sinon : ne run pas
		return false, def.run
	end

	local order = ns.Data and ns.Data.JournalistProcessorOrder
	local ran = false
	local used = nil

	local function RunKey(key)
		local def = registry.items[key]
		if not def then
			return
		end
		local last = GetJournalistModuleLast(g, key)
		local intelProxy = MakeIntelModuleProxy(intel, key)

		local ok, fn = ShouldRun(def, intelProxy, last, uid, now, eventName)
		if not ok or not fn then
			return
		end

		fn(g, intelProxy, last, uid, now)
		last._lastRunAt = now
		ran = true
	end

	if order and #order > 0 then
		used = {}
		for i = 1, #order do
			local key = order[i]
			if registry.items[key] then
				RunKey(key)
				used[key] = true
			end
		end
	end

	local regOrder = registry.order
	if regOrder and #regOrder > 0 then
		for i = 1, #regOrder do
			local key = regOrder[i]
			if (not used or not used[key]) and registry.items[key] then
				RunKey(key)
			end
		end
	end

	return ran
end

local function NormalizeNewsItems(g)
	if not g or not g.news or not g.news.items then
		return 0
	end
	local changed = 0
	for i = 1, #g.news.items do
		local n = g.news.items[i]
		if n then
			if n.replaceKey == nil then
				n.replaceKey = ""
				changed = changed + 1
			elseif type(n.replaceKey) ~= "string" then
				n.replaceKey = tostring(n.replaceKey)
				changed = changed + 1
			end
			if n.id ~= nil and type(n.id) ~= "string" then
				n.id = tostring(n.id)
				changed = changed + 1
			end
			if n.type ~= nil and type(n.type) ~= "string" then
				n.type = tostring(n.type)
				changed = changed + 1
			end
			local typ = (n.type and tostring(n.type):lower()) or ""
			local metaKey = GetMetaKey(typ, n.replaceKey)
			local meta = metaKey and GetNewsMeta(metaKey) or GetNewsMeta(typ)
			if meta and type(meta) == "table" and type(meta.type) == "string" and meta.type ~= "" then
				local resolvedType = tostring(meta.type):lower()
				if resolvedType ~= "" and resolvedType ~= typ then
					n.type = resolvedType
					typ = resolvedType
					changed = changed + 1
				end
			elseif typ == "" then
				n.type = "generic"
				typ = "generic"
				changed = changed + 1
			end
			if not n.title or n.title == "" then
				local resolvedTitle = (meta and type(meta.title) == "string" and meta.title) or GetNewsTitle(typ)
				if resolvedTitle and resolvedTitle ~= "" then
					n.title = resolvedTitle
					changed = changed + 1
				end
			end
			if n.ts ~= nil and type(n.ts) ~= "number" then
				n.ts = tonumber(n.ts) or n.ts
			end
			if n.removedAt ~= nil and type(n.removedAt) ~= "number" then
				n.removedAt = tonumber(n.removedAt) or n.removedAt
			end
			if n.points ~= nil and type(n.points) ~= "number" then
				n.points = tonumber(n.points) or n.points
			end
		end
	end
	if changed > 0 then
		g.news.updatedAt = Now()
	end
	return changed
end

local function DedupNewsById(g)
	if not g or not g.news or not g.news.items then
		return 0
	end
	local items = g.news.items
	local bestIndexById = {}
	local bestTsById = {}
	for i = 1, #items do
		local n = items[i]
		if n and n.id then
			local id = n.id
			local ts = tonumber(n.ts) or 0
			local bestTs = bestTsById[id]
			if not bestTs or ts > bestTs or (ts == bestTs and i > bestIndexById[id]) then
				bestTsById[id] = ts
				bestIndexById[id] = i
			end
		end
	end
	local removed = 0
	local newItems = {}
	for i = 1, #items do
		local n = items[i]
		if n and n.id and bestIndexById[n.id] == i then
			newItems[#newItems + 1] = n
		else
			if n and n.id and ns.Data and ns.Data.NewsFeed and ns.Data.NewsFeed.RemoveById then
				ns.Data.NewsFeed.RemoveById(n.id)
			end
			removed = removed + 1
		end
	end
	if removed > 0 then
		g.news.items = newItems
		g.news.updatedAt = Now()
	end
	return removed
end

local function ExtractNewsUID(news)
	if type(news) ~= "table" then
		return nil
	end

	local uid = news.uid
	if type(uid) == "string" and uid ~= "" then
		if uid:sub(1, 4) == "uid:" then
			return uid
		end
		local extracted = uid:match("(uid:[%w]+)")
		if extracted and extracted ~= "" then
			return extracted
		end
	end

	local rk = news.replaceKey
	if type(rk) == "string" and rk ~= "" then
		local extracted = rk:match("(uid:[%w]+)")
		if extracted and extracted ~= "" then
			return extracted
		end
	end

	return nil
end

local function CleanupNewsForMissingGuildPlayers(g)
	if not g or not g.news or type(g.news.items) ~= "table" then
		return 0
	end

	local players = type(g.players) == "table" and g.players or nil
	if not players then
		return 0
	end

	local removed = 0
	for i = #g.news.items, 1, -1 do
		local n = g.news.items[i]
		local uid = ExtractNewsUID(n)
		if uid and players[uid] == nil then
			if n and n.id and ns.Data and ns.Data.NewsFeed and ns.Data.NewsFeed.RemoveById then
				ns.Data.NewsFeed.RemoveById(n.id)
			end
			table.remove(g.news.items, i)
			removed = removed + 1
		end
	end

	if removed > 0 then
		g.news.updatedAt = Now()
	end
	return removed
end

local function PublishStoredNews()
	local guildUID = GetGuildUID()
	if not guildUID then
		return
	end
	if publishedGuildUID == guildUID then
		return
	end
	local g = EnsureGuildRoot(guildUID)
	if not g or not g.news or not g.news.items then
		return
	end
	NormalizeNewsItems(g)
	DedupNewsById(g)
	CleanupNewsForMissingGuildPlayers(g)
	if not (ns.Data and ns.Data.NewsFeed and ns.Data.NewsFeed.Add) then
		return
	end

	local now = Now()
	local addedIds = {}
	local myUID = GetMyUID()
	local addedPresence = false
	for i = 1, #g.news.items do
		local n = g.news.items[i]
		if n and n.id and n.text then
			if n.replaceKey and n.replaceKey:match("^presence:") then
				if n.removedAt and n.removedAt > now then
					ns.Data.NewsFeed.Add(
						n.text,
						n.type,
						n.icon,
						n.ts,
						n.id,
						nil,
						guildUID,
						n.replaceKey,
						n.title,
						n.removedAt,
						n.uid
					)
					addedIds[n.id] = true
					if myUID and n.replaceKey == ("presence:" .. tostring(myUID)) then
						addedPresence = true
					end
				end
			else
				-- Evite de republier un ancien statut de presence au reload.
				ns.Data.NewsFeed.Add(
					n.text,
					n.type,
					n.icon,
					n.ts,
					n.id,
					nil,
					guildUID,
					n.replaceKey,
					n.title,
					n.removedAt,
					n.uid
				)
				addedIds[n.id] = true
			end
		end
	end
	if not addedPresence and myUID and WoWGuildeDB and WoWGuildeDB.guilds then
		local rk = "presence:" .. tostring(myUID)
		for _, other in pairs(WoWGuildeDB.guilds) do
			if other and other.news and other.news.items then
				for i = 1, #other.news.items do
					local n = other.news.items[i]
					if n and n.id and n.text and n.replaceKey == rk then
						local removedAt = tonumber(n.removedAt or 0) or 0
						if removedAt > now and not addedIds[n.id] then
							ns.Data.NewsFeed.Add(
								n.text,
								n.type,
								n.icon,
								n.ts,
								n.id,
								nil,
								guildUID,
								n.replaceKey,
								n.title,
								n.removedAt,
								n.uid
							)
							addedIds[n.id] = true
							addedPresence = true
						end
					end
				end
			end
			if addedPresence then
				break
			end
		end
	end
	publishedGuildUID = guildUID
end

local lastGuildRetryAt = nil
local function PruneRosterOnce()
	if not (ns.DB and ns.DB.PrunePlayersNotInGuildRoster) then
		return
	end
	local gid = GetGuildUID()
	if not gid then
		return
	end
	ns.DB:PrunePlayersNotInGuildRoster(gid)
end

local function ProcessJournalist(eventName, ...)
	local argsN = select("#", ...)
	local args = argsN > 0 and { ... } or nil
	local guildUID = GetGuildUID()
	if not guildUID then
		if IsInGuild and IsInGuild() and C_Timer and C_Timer.After then
			local now = Now()
			if not lastGuildRetryAt or (now - lastGuildRetryAt) > 1 then
				lastGuildRetryAt = now
				C_Timer.After(1, function()
					if argsN > 0 then
						ProcessJournalist(eventName, unpack(args, 1, argsN))
					else
						ProcessJournalist(eventName)
					end
				end)
			end
		end
		return
	end

	if publishedGuildUID ~= guildUID then
		PublishStoredNews()
	end

	local uid = GetMyUID()
	if not uid then
		return
	end

	local g = EnsureGuildRoot(guildUID)
	if not g then
		return
	end

	PublishStoredNews()

	local intel = g.statistics and g.statistics.players and g.statistics.players[uid]
	if not intel then
		return
	end

	local pigapi = ns.Data and ns.Data.PigisteAPI
	if pigapi and pigapi.EnsurePlayer then
		intel = pigapi.EnsurePlayer(uid) or intel
	end

	local now = Now()

	EnsureJournalistModules(g)
	RunRegisteredNews(g, intel, uid, now, eventName) -- <- eventName transmis

	CleanupNewsForMissingGuildPlayers(g)
	CleanupAgedNews(g, 14 * 86400)
	CleanupExpiredNewsEverywhere(now)
	PruneProudForGuild(g)

	-- ... (ton reste inchangé)
	if ns.Data and ns.Data.PigisteAPI and ns.Data.PigisteAPI.PruneGuildIntel then
		local cfg = ns.Data and ns.Data.NewsTTL or {}
		local daySeconds = tonumber(cfg.daySeconds or 86400) or 86400
		local retentionDays = tonumber(cfg.dataRetentionDays or 14) or 14
		ns.Data.PigisteAPI.PruneGuildIntel(g, retentionDays * daySeconds)
		if ns.DB and ns.DB.PruneOldCharacters then
			ns.DB:PruneOldCharacters(guildUID, retentionDays * daySeconds)
		end
	end
end

-- =========================================================
-- Journaliste : publication et cycle de vie
-- =========================================================

local publishedGuildUID = nil
local pendingRosterPrune = false
local function HandleEvent(event)
	if event == "PLAYER_LOGIN" then
		PublishStoredNews()
		ProcessJournalist()
		pendingRosterPrune = true
		if C_GuildInfo and C_GuildInfo.GuildRoster then
			C_GuildInfo.GuildRoster()
		elseif GuildRoster then
			GuildRoster()
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(1, function()
				ProcessJournalist()
			end)
		end
	elseif event == "GUILD_ROSTER_UPDATE" then
		if pendingRosterPrune then
			pendingRosterPrune = false
		end
		PruneRosterOnce()
		ProcessJournalist(event)
	else
		ProcessJournalist()
	end
end

if EventBus and EventBus.On then
	EventBus.On("PLAYER_LOGIN", HandleEvent)
	EventBus.On("PLAYER_ENTERING_WORLD", HandleEvent)
	EventBus.On("GUILD_ROSTER_UPDATE", HandleEvent)
end

local ticker
local function StartLive()
	if ticker then
		return
	end
	ticker = C_Timer.NewTicker(5, function()
		ProcessJournalist()
	end)
	ProcessJournalist()
end

local function StopLive()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

function Journalist.Publish()
	PublishStoredNews()
end

function Journalist.StartLive()
	StartLive()
end

function Journalist.StopLive()
	StopLive()
end

function Journalist.TickNow(eventName, ...)
	ProcessJournalist(eventName, ...)
end

function Journalist.AddRemoteNews(text, typ, icon, ts, guildUID, replaceKey, id, title, points, uid)
	local gid = guildUID or GetGuildUID()
	if not gid then
		return
	end
	local g = EnsureGuildRoot(gid)
	if not g then
		return
	end
	return AddRawNews(g, {
		text = text,
		type = typ,
		icon = icon,
		ts = ts,
		replaceKey = replaceKey,
		noBroadcast = true,
		id = id,
		title = title,
		points = points,
		uid = uid,
	})
end

function Journalist.AddRemoteNewsPayload(payload, guildUID)
	if type(payload) ~= "table" then
		return
	end
	local gid = guildUID or GetGuildUID()
	if not gid then
		return
	end
	local g = EnsureGuildRoot(gid)
	if not g then
		return
	end
	payload.noBroadcast = true
	return AddRawNews(g, payload)
end

function Journalist.GetRecentNews(guildUID, limit)
	local gid = guildUID or GetGuildUID()
	if not gid then
		return {}
	end
	local g = EnsureGuildRoot(gid)
	if not g or not g.news or not g.news.items then
		return {}
	end
	local items = g.news.items
	local max = tonumber(limit or 0) or 0
	if max <= 0 then
		max = 50
	end
	local start = #items - max + 1
	if start < 1 then
		start = 1
	end
	local out = {}
	for i = start, #items do
		local n = items[i]
		if n and n.id and n.text then
			out[#out + 1] = {
				id = n.id,
				text = n.text,
				typ = n.type,
				title = n.title,
				icon = n.icon,
				ts = n.ts,
				replaceKey = n.replaceKey,
				points = n.points,
				uid = n.uid,
			}
		end
	end
	return out
end

return Journalist
