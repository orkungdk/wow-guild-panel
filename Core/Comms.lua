-- WoWGuilde, Comms optimisé ANN/GET/SNAP + PATCH
local ADDON, ns = ...
local EventBus = ns.EventBus
local DB = ns.DB or {}

ns.Comms = ns.Comms or {}
local Comms = ns.Comms

local PREFIX = "WoWGuilde"
local DEFAULT_MAX_ADDON_LINE = 200
local DB_VERSION = "0.15"
local PROTO_VER = DB_VERSION
local SNAP_VER = PROTO_VER
local DEV_MODE = false
local CONTACT_TTL = 300
local TIME_SKEW_TOLERANCE = 300
local FUTURE_TS_CLAMP = 86400
local Codec = ns.Codec or {}
local EPIC_B64_PREFIX = Codec.B64_PREFIX or "b64:"
local Serialize = ns.Serialize or {}
local DumpEsc = Serialize.Escape
local SerializeKV = Serialize.KV
local LoadTable = Serialize.LoadTable
local Featured_MergeByKey
Comms.DEV_MODE = DEV_MODE
Comms._rosterReady = Comms._rosterReady or false
Comms._lastContactAt = Comms._lastContactAt or 0
Comms._maxLineByChannel = Comms._maxLineByChannel or {}
Comms._autoMaxLine = Comms._autoMaxLine or nil
local Notices = ns.CommsNotices
if Notices and Notices.SetDevMode then
	Notices.SetDevMode(DEV_MODE)
end
local function DevPrint(msg)
	if Comms and Comms.DEV_MODE then
		print("|cffffd100[WoW Guilde]|r " .. tostring(msg))
	end
end
local function EmitCommsError(kind, sender, detail)
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_COMMS_ERROR", kind, sender, detail)
	end
	DevPrint(("COMMS ERROR %s from %s: %s"):format(tostring(kind), tostring(sender or "?"), tostring(detail or "")))
end

local function GetMaxAddonLineFor(channel)
	local ch = tostring(channel or "GUILD"):upper()
	local settings = WoWGuildeDB and WoWGuildeDB.Settings and WoWGuildeDB.Settings.commsMaxLine or nil
	local override = settings and settings[ch] or nil
	local base = tonumber(override)
	if not base or base <= 0 then
		base = Comms._maxLineByChannel[ch] or DEFAULT_MAX_ADDON_LINE
	end
	if Comms._autoMaxLine and Comms._autoMaxLine > 0 then
		base = math.min(base, Comms._autoMaxLine)
	end
	return base
end

local function AutoClampMaxLine(reason)
	local cur = tonumber(Comms._autoMaxLine or 0) or 0
	local nextClamp = 200
	if cur > 0 then
		nextClamp = math.max(160, cur - 10)
	end
	if cur == 0 or nextClamp < cur then
		Comms._autoMaxLine = nextClamp
		DevPrint(("AUTO CLAMP maxLine=%d (reason=%s)"):format(nextClamp, tostring(reason or "?")))
	end
end
local NEWS_RELAY_MAX = 0
local NEWS_BATCH_MAX = 50
local NEWSREQ_BUCKETS = 12
local NEWSREQ_STAGE_SIZE = 3
local NEWSREQ_STAGE_DELAY = 1.6
local INBOX_TTL = 60
local NEWSREQ_TTL = 300
local PRUNE_INTERVAL = 30
local MAX_LUA_PAYLOAD = 200000
local MAX_LUA_SNAPSHOT = 1000000
local MAX_LUA_EPIC = 200000

local function EnsureDBSettings()
	WoWGuildeDB = WoWGuildeDB or {}
	if type(WoWGuildeDB.Settings) ~= "table" then
		WoWGuildeDB.Settings = {}
	end
	return WoWGuildeDB.Settings
end

local function ParseVersion(v)
	if v == nil then
		return nil
	end
	if type(v) == "number" then
		v = tostring(v)
	end
	v = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if v == "" then
		return nil
	end
	local parts = {}
	for num in v:gmatch("[0-9]+") do
		parts[#parts + 1] = tonumber(num) or 0
	end
	if #parts == 0 then
		return nil
	end
	return parts
end

local function CompareVersions(a, b)
	local ap = ParseVersion(a)
	local bp = ParseVersion(b)
	if not ap and not bp then
		return 0
	end
	if not ap then
		return -1
	end
	if not bp then
		return 1
	end
	local n = math.max(#ap, #bp)
	for i = 1, n do
		local av = ap[i] or 0
		local bv = bp[i] or 0
		if av ~= bv then
			return (av < bv) and -1 or 1
		end
	end
	return 0
end

local function EnsureDBVersion()
	local settings = EnsureDBSettings()
	local stored = settings.dbVersion
	local cmp = CompareVersions(stored, DB_VERSION)
	if cmp == 0 then
		settings.dbVersion = DB_VERSION
	elseif cmp < 0 then
		local oldDB = WoWGuildeDB
		local newDB = { Settings = settings, guilds = {} }
		if oldDB and type(oldDB.guilds) == "table" then
			for gid, g in pairs(oldDB.guilds) do
				local shared = type(g) == "table" and g.guildShared or nil
				local outShared = {}
				local keep = false

				if shared and type(shared.guildProgress) == "table" then
					outShared.guildProgress = shared.guildProgress
					keep = true
				end

				if shared and type(shared.guildMemberPrefs) == "table" then
					local prefsOut = {}
					for uid, prefs in pairs(shared.guildMemberPrefs) do
						if type(prefs) == "table" then
							local hasEpic = false
							local out = {}
							if prefs.epic ~= nil then
								out.epic = prefs.epic
								hasEpic = true
							end
							if prefs.biographie ~= nil then
								out.biographie = prefs.biographie
								hasEpic = true
							end
							if prefs.updatedAt ~= nil then
								out.updatedAt = prefs.updatedAt
							end
							if hasEpic then
								prefsOut[uid] = out
							end
						end
					end
					if next(prefsOut) ~= nil then
						outShared.guildMemberPrefs = prefsOut
						keep = true
					end
				end

				local outPlayers = nil
				if type(g.players) == "table" then
					outPlayers = {}
					for uid, p in pairs(g.players) do
						if type(p) == "table" and type(p.characters) == "table" then
							local outP =
								{ mainFull = tostring(p.mainFull or ""), updatedAt = p.updatedAt, characters = {} }
							for full, c in pairs(p.characters) do
								if type(c) == "table" then
									outP.characters[full] = {
										full = c.full or full,
										name = c.name,
										realm = c.realm,
										classLoc = c.classLoc,
										classTag = c.classTag,
										playerGUID = c.playerGUID,
										isMain = c.isMain,
										updatedAt = c.updatedAt,
									}
								end
							end
							if next(outP.characters) ~= nil then
								outPlayers[uid] = outP
								keep = true
							end
						end
					end
				end

				if keep then
					local outG = { guildShared = outShared }
					if outPlayers and next(outPlayers) ~= nil then
						outG.players = outPlayers
					end
					newDB.guilds[gid] = outG
				end
			end
		end
		if oldDB and type(oldDB.LFGList) == "table" then
			newDB.LFGList = oldDB.LFGList
		end
		WoWGuildeDB = newDB
		settings.dbVersion = DB_VERSION
	end
end

-- =========================
-- Utilitaires bas niveau
-- =========================
local bit = bit
local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift

local function FNV1a32(s)
	local h = 0x811C9DC5
	for i = 1, #s do
		h = bxor(h, s:byte(i))
		h = (h * 0x01000193) % 2 ^ 32
	end
	return h
end

local function Hex8(u32)
	return string.format("%08x", u32)
end

local function Now()
	return time and time() or 0
end

local function LocalFullName()
	local n, r = UnitFullName and UnitFullName("player")
	if not n then
		n = UnitName and UnitName("player") or "?"
	end
	if r and r ~= "" then
		return n .. "-" .. r
	end
	return n
end

local function IsSelfSender(sender)
	if not sender or sender == "" then
		return false
	end
	local me = LocalFullName()
	if sender == me then
		return true
	end
	local s = Ambiguate and Ambiguate(sender, "none") or sender
	local m = Ambiguate and Ambiguate(me, "none") or me
	return s == m
end

local function NormalizePeerName(name)
	if not name or name == "" then
		return ""
	end
	local n = Ambiguate and Ambiguate(name, "none") or name
	return tostring(n)
end

local function MarkDBMismatch(sender, kind, got, expected)
	local key = NormalizePeerName(sender)
	if key == "" then
		return
	end
	Comms._dbMismatchByPeer = Comms._dbMismatchByPeer or {}
	Comms._dbMismatchByPeer[key] = { at = Now(), kind = kind, got = got, expected = expected }
end

local function ClearDBMismatch(sender)
	local key = NormalizePeerName(sender)
	if key == "" then
		return
	end
	if Comms._dbMismatchByPeer then
		Comms._dbMismatchByPeer[key] = nil
	end
end

local function HasDBMismatch(target)
	local key = NormalizePeerName(target)
	if key == "" then
		return false
	end
	return Comms._dbMismatchByPeer and Comms._dbMismatchByPeer[key] ~= nil
end

local function MarkContact(sender)
	if sender and not IsSelfSender(sender) then
		Comms._lastContactAt = Now()
		Comms._hadOthers = true
	end
end

local function HasRecentContact()
	local last = Comms and Comms._lastContactAt
	if type(last) ~= "number" or last <= 0 then
		return false
	end
	return (Now() - last) < CONTACT_TTL
end

local function ToNumber(v, default)
	local n = tonumber(v)
	if n == nil then
		return default
	end
	return n
end

local function ToBool(v)
	if v == nil then
		return nil
	end
	if type(v) == "boolean" then
		return v
	end
	if type(v) == "number" then
		return v ~= 0
	end
	if type(v) == "string" then
		local s = v:lower()
		if s == "true" or s == "1" or s == "yes" then
			return true
		end
		if s == "false" or s == "0" or s == "no" then
			return false
		end
	end
	return nil
end

local function NormalizeUpdatedAt(v, fallbackNow)
	local now = Now()
	local ts = tonumber(v or 0) or 0
	if ts <= 0 then
		return fallbackNow and now or 0
	end
	if ts > now + FUTURE_TS_CLAMP then
		return now
	end
	return ts
end

local function ShouldAcceptMostRecent(incomingAt, existingAt, hasExisting)
	if not hasExisting then
		return true
	end
	local inAt = tonumber(incomingAt or 0) or 0
	local exAt = tonumber(existingAt or 0) or 0
	if inAt > 0 and exAt > 0 then
		return inAt >= exAt
	end
	if inAt > 0 and exAt <= 0 then
		return true
	end
	if inAt <= 0 and exAt > 0 then
		return false
	end
	return false
end

local function ShouldAcceptIncoming(incomingAt, existingAt)
	local inAt = tonumber(incomingAt or 0) or 0
	local exAt = tonumber(existingAt or 0) or 0
	if exAt == 0 then
		return true
	end
	if inAt == 0 then
		return true
	end
	return (inAt + TIME_SKEW_TOLERANCE) >= exAt
end

local function FeaturedUpdatedAt(v)
	if type(v) ~= "table" then
		return 0
	end
	return tonumber(v.updatedAt or v.ts or v.time or 0) or 0
end

local function BioUpdatedAtValue(v)
	if type(v) == "table" then
		return tonumber(v.updatedAt or v.createdAt or 0) or 0
	end
	if type(v) == "string" then
		local decoded = TryDecodeEpicValue(v)
		if type(decoded) == "table" then
			return tonumber(decoded.updatedAt or decoded.createdAt or 0) or 0
		end
	end
	return 0
end

local function NormalizeNewsKV(kv)
	if type(kv) ~= "table" then
		return nil
	end
	local text = kv.text
	if text == nil or text == "" then
		return nil
	end
	local typ = kv.typ or kv.type or "generic"
	local out = {
		id = tostring(kv.id or ""),
		text = tostring(text),
		typ = tostring(typ):lower(),
		title = kv.title ~= nil and tostring(kv.title) or nil,
		icon = ToNumber(kv.icon, 0) or 0,
		ts = ToNumber(kv.ts, 0) or 0,
		replaceKey = kv.replaceKey ~= nil and tostring(kv.replaceKey) or "",
		relay = ToNumber(kv.relay, 0) or 0,
		origin = kv.origin ~= nil and tostring(kv.origin) or nil,
	}
	if kv.uid ~= nil then
		local uid = tostring(kv.uid or "")
		if uid ~= "" then
			out.uid = uid
		end
	end
	if kv.points ~= nil then
		out.points = ToNumber(kv.points, 0) or 0
	end
	if out.ts <= 0 then
		out.ts = Now()
	end
	if out.id == "" then
		out.id = "news:" .. Hex8(FNV1a32(out.text .. tostring(out.ts) .. tostring(out.replaceKey)))
	end
	return out
end

local function NormalizePrefs(kv)
	if type(kv) ~= "table" then
		return nil
	end
	local out = {}
	if kv.emotesEnabled ~= nil then
		out.emotesEnabled = ToBool(kv.emotesEnabled)
	end
	if kv.emotesSound ~= nil then
		out.emotesSound = ToBool(kv.emotesSound)
	end
	if kv.raidLeader ~= nil then
		out.raidLeader = ToBool(kv.raidLeader)
	end
	if kv.epic ~= nil then
		out.epic = kv.epic
	end
	if kv.biographie ~= nil then
		out.biographie = kv.biographie
	end
	out.updatedAt = NormalizeUpdatedAt(kv.updatedAt, true)
	return out
end

local function TryDecodeEpicValue(v)
	if type(v) == "table" then
		return v
	end
	if type(v) ~= "string" or v == "" then
		return nil
	end
	local s = v
	if s:sub(1, #EPIC_B64_PREFIX) == EPIC_B64_PREFIX then
		s = s:sub(#EPIC_B64_PREFIX + 1)
	end
	local raw = B64Decode(s)
	if not raw or raw == "" then
		return nil
	end
	if LoadTable then
		local tbl = LoadTable(raw, {}, MAX_LUA_EPIC)
		if type(tbl) == "table" then
			return tbl
		end
	else
		if #raw > MAX_LUA_EPIC then
			return nil
		end
		local fn = loadstring(raw)
		if not fn then
			return nil
		end
		setfenv(fn, {})
		local ok, tbl = pcall(fn)
		if ok and type(tbl) == "table" then
			return tbl
		end
	end
	return nil
end

local function ApplyEpicVisibilityPolicy(prefs)
	if type(prefs) ~= "table" or type(prefs.biographie) ~= "table" then
		return prefs
	end
	for key, bio in pairs(prefs.biographie) do
		if bio ~= "__DELETE__" then
			local status = nil
			if type(bio) == "table" then
				status = bio.status
			else
				local decoded = TryDecodeEpicValue(bio)
				status = decoded and decoded.status or nil
			end
			if status and status ~= "published" then
				prefs.biographie[key] = "__DELETE__"
			end
		end
	end
	return prefs
end

local function MergePrefsMostRecent(incoming, existing)
	if type(incoming) ~= "table" then
		return incoming
	end
	if type(existing) ~= "table" then
		return incoming
	end
	if incoming.epic ~= nil and (type(incoming.biographie) ~= "table" or incoming.biographie["__general__"] == nil) then
		incoming.biographie = incoming.biographie or {}
		incoming.biographie["__general__"] = incoming.epic
		incoming.epic = nil
	end
	if type(incoming.biographie) == "table" and type(existing.biographie) == "table" then
		for k, v in pairs(incoming.biographie) do
			local ex = existing.biographie[k]
			local exAt = BioUpdatedAtValue(ex)
			if v == "__DELETE__" then
				if exAt > 0 then
					incoming.biographie[k] = nil
				end
			else
				local inAt = BioUpdatedAtValue(v)
				local hasExisting = ex ~= nil
				if not ShouldAcceptMostRecent(inAt, exAt, hasExisting) then
					incoming.biographie[k] = nil
				end
			end
		end
		if next(incoming.biographie) == nil then
			incoming.biographie = nil
		end
	end
	local inAt = tonumber(incoming.updatedAt or 0) or 0
	local exAt = tonumber(existing.updatedAt or 0) or 0
	if exAt > inAt then
		incoming.updatedAt = exAt
	end
	return incoming
end

local function HasOtherOnlineGuildMember()
	if HasRecentContact() then
		return true
	end
	if not IsInGuild or not IsInGuild() then
		return false
	end
	if ns.RequestGuildData then
		ns.RequestGuildData()
	end
	local n = GetNumGuildMembers and GetNumGuildMembers() or 0
	if n <= 1 and not Comms._rosterReady then
		return true
	end
	if n <= 1 then
		return false
	end
	local myGuid = UnitGUID and UnitGUID("player") or nil
	local myName, myRealm = UnitFullName and UnitFullName("player")
	local myFull = myName and (myName .. ((myRealm and myRealm ~= "") and ("-" .. myRealm) or "")) or nil
	local myShort = myName or ""
	local otherOnline = 0
	for i = 1, n do
		local name, _, _, _, _, _, _, _, online, _, _, _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
		if online or isMobile then
			if guid and myGuid and guid ~= myGuid then
				otherOnline = otherOnline + 1
			elseif name then
				local full = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name
				local short = Ambiguate and Ambiguate(full, "none") or full
				if myFull and full ~= myFull then
					otherOnline = otherOnline + 1
				elseif myShort ~= "" and short ~= myShort then
					otherOnline = otherOnline + 1
				end
			end
		end
	end
	if otherOnline > 0 then
		Comms._hadOthers = true
	end
	return otherOnline > 0
end

local function GetLocalGuildName()
	return GetGuildInfo("player")
end

local function ParseGuildUID(gid)
	if ns.Utils and ns.Utils.ParseGuildUID then
		return ns.Utils.ParseGuildUID(gid)
	end
	if type(gid) ~= "string" then
		return nil, nil
	end
	if gid:sub(1, 6) == "guild:" then
		local namePart, realmPart = gid:match("^guild:([^@]+)@(.+)$")
		if not namePart then
			namePart = gid:match("^guild:(.+)$")
		end
		return namePart, realmPart
	end
	return nil, nil
end

local function IsAcceptedGuildUID(guildUID)
	if not guildUID or guildUID == "" then
		return false
	end
	if DB and DB.GetGuildUID then
		local gid = DB:GetGuildUID()
		if gid and gid ~= "" then
			if guildUID == gid then
				return true
			end
			local gName = GetGuildInfo and GetGuildInfo("player") or nil
			if not gName or gName == "" then
				return false
			end
			local gRealm = (GetNormalizedRealmName and GetNormalizedRealmName())
				or (GetRealmName and GetRealmName())
				or nil
			local nameA, realmA = ParseGuildUID(guildUID)
			local nameB, realmB = ParseGuildUID(gid)
			if nameA and nameA == gName and (not realmA or not gRealm or realmA == gRealm) then
				return gid:sub(1, 5) == "club:"
			end
			if nameB and nameB == gName and (not realmB or not gRealm or realmB == gRealm) then
				return guildUID:sub(1, 5) == "club:"
			end
		end
	end
	return false
end

-- =========================
-- Base64, compatible WoW
-- =========================
local B64Encode = Codec.B64Encode
local B64Decode = Codec.B64Decode
local StripB64Prefix = Codec.StripB64Prefix

local function NormalizeB64Input(b64)
	if type(b64) ~= "string" then
		return b64
	end
	if StripB64Prefix then
		b64 = StripB64Prefix(b64)
	elseif EPIC_B64_PREFIX and b64:sub(1, #EPIC_B64_PREFIX) == EPIC_B64_PREFIX then
		b64 = b64:sub(#EPIC_B64_PREFIX + 1)
	end
	-- support base64url variants
	b64 = b64:gsub("%-", "+"):gsub("_", "/")
	return b64
end

local function SerializeNewsList(items)
	local sb = { "return { items = {" }
	local first = true
	for i = 1, #items do
		local it = items[i]
		if it then
			if not first then
				sb[#sb + 1] = ","
			end
			first = false
			sb[#sb + 1] = "{"
			local function addField(k, v)
				if v == nil then
					return
				end
				if type(v) == "string" then
					sb[#sb + 1] = k .. '="' .. DumpEsc(v) .. '",'
				elseif type(v) == "number" or type(v) == "boolean" then
					sb[#sb + 1] = k .. "=" .. tostring(v) .. ","
				end
			end
			addField("id", it.id)
			addField("text", it.text)
			addField("typ", it.typ or it.type)
			addField("title", it.title)
			addField("icon", it.icon)
			addField("ts", it.ts)
			addField("replaceKey", it.replaceKey)
			addField("points", it.points)
			sb[#sb + 1] = "}"
		end
	end
	sb[#sb + 1] = "} }"
	return table.concat(sb)
end

-- =========================
-- TEA 128 bits
-- =========================
local function TEAKeyFromSecret(secret, guildUID)
	local seed = tostring(secret or "") .. "|" .. tostring(guildUID or "")
	local k = {}
	local acc = FNV1a32(seed)
	for i = 1, 4 do
		acc = FNV1a32(seed .. tostring(i) .. string.char(acc % 256))
		k[i] = acc
	end
	return { k[1], k[2], k[3], k[4] }
end

local function TEAEncrypt(data, key)
	local pad = 8 - (#data % 8)
	data = data .. string.rep(string.char(pad), pad)
	local out = {}
	for i = 1, #data, 8 do
		local v0 = 0
		local v1 = 0
		for j = 0, 3 do
			v0 = v0 * 256 + data:byte(i + j)
		end
		for j = 4, 7 do
			v1 = v1 * 256 + data:byte(i + j)
		end
		local sum = 0
		local delta = 0x9E3779B9
		for _ = 1, 32 do
			sum = (sum + delta) % 2 ^ 32
			v0 = (v0 + bxor(bxor((band(v1, 0xFFFFFFFF) * 16) % 2 ^ 32, rshift(v1, 5)), v1) + (key[(sum % 4) + 1] + sum))
				% 2 ^ 32
			v1 = (
				v1
				+ bxor(bxor((band(v0, 0xFFFFFFFF) * 16) % 2 ^ 32, rshift(v0, 5)), v0)
				+ (key[band(rshift(sum, 11), 3) + 1] + sum)
			) % 2 ^ 32
		end
		out[#out + 1] = string.char(
			band(rshift(v0, 24), 255),
			band(rshift(v0, 16), 255),
			band(rshift(v0, 8), 255),
			band(v0, 255),
			band(rshift(v1, 24), 255),
			band(rshift(v1, 16), 255),
			band(rshift(v1, 8), 255),
			band(v1, 255)
		)
	end
	return table.concat(out)
end

local function TEADecrypt(data, key)
	if (#data % 8) ~= 0 then
		return nil, "len"
	end
	local out = {}
	for i = 1, #data, 8 do
		local v0 = 0
		local v1 = 0
		for j = 0, 3 do
			v0 = 0x100 * v0 + (data:byte(i + j) or 0)
		end
		for j = 4, 7 do
			v1 = 0x100 * v1 + (data:byte(i + j) or 0)
		end
		local delta = 0x9E3779B9
		local sum = (delta * 32) % 2 ^ 32
		for _ = 1, 32 do
			v1 = (
				v1
				- (
					bxor(bxor((band(v0, 0xFFFFFFFF) * 16) % 2 ^ 32, rshift(v0, 5)), v0)
					+ (key[band(rshift(sum, 11), 3) + 1] + sum)
				)
			) % 2 ^ 32
			v0 = (
				v0 - (bxor(bxor((band(v1, 0xFFFFFFFF) * 16) % 2 ^ 32, rshift(v1, 5)), v1) + (key[(sum % 4) + 1] + sum))
			) % 2 ^ 32
			sum = (sum - delta) % 2 ^ 32
		end
		out[#out + 1] = string.char(
			band(rshift(v0, 24), 255),
			band(rshift(v0, 16), 255),
			band(rshift(v0, 8), 255),
			band(v0, 255),
			band(rshift(v1, 24), 255),
			band(rshift(v1, 16), 255),
			band(rshift(v1, 8), 255),
			band(v1, 255)
		)
	end
	local s = table.concat(out)
	local pad = s:byte(#s) or 0
	if pad < 1 or pad > 8 then
		return nil, "pad"
	end
	return s:sub(1, #s - pad)
end

-- =========================
-- Secret de guilde, clé
-- =========================
local function EnsureDB()
	WoWGuildeDB = WoWGuildeDB or {}
	return WoWGuildeDB
end

local function GetGuildSecret()
	if C_Club and C_Club.GetGuildClubId then
		local clubId = C_Club.GetGuildClubId()
		if clubId then
			return "club:" .. tostring(clubId)
		end
	end
	local gname = GetGuildInfo("player") or "NoGuild"
	return gname
end

local function ExtractRealmFromSender(sender)
	if not sender or sender == "" then
		return nil
	end
	return sender:match("^[^-]+%-(.+)$")
end

local function GetLegacyGuildSecretFromUID(guildUID, sender)
	local gname = GetGuildInfo("player") or "NoGuild"
	local realm = ExtractRealmFromSender(sender)
	if not realm or realm == "" then
		realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or "UnknownRealm")
	end
	if type(guildUID) == "string" and guildUID:sub(1, 6) == "guild:" then
		local namePart, realmPart = guildUID:match("^guild:([^@]+)@(.+)$")
		if namePart and realmPart then
			gname = namePart
			realm = realmPart
		elseif guildUID:match("^guild:") then
			gname = guildUID:sub(7)
		end
	end
	return gname .. "-" .. realm
end

local function GetKeyForGuild(guildUID)
	local sec = GetGuildSecret()
	return TEAKeyFromSecret(sec, guildUID)
end

local function GetLegacyKeyForGuild(guildUID, sender)
	local sec = GetLegacyGuildSecretFromUID(guildUID, sender)
	return TEAKeyFromSecret(sec, guildUID)
end

-- Variante legacy (très ancienne) : secret = nom de guilde seul (sans realm)
local function GetVeryLegacyKeyForGuild(guildUID)
	local namePart = nil
	if guildUID and type(guildUID) == "string" then
		local parsedName = ParseGuildUID(guildUID)
		namePart = parsedName
	end
	if not namePart or namePart == "" then
		namePart = GetGuildInfo and GetGuildInfo("player") or nil
	end
	if not namePart or namePart == "" then
		namePart = "NoGuild"
	end
	return TEAKeyFromSecret(namePart, guildUID)
end

-- Variante club : si on ne peut pas lire le clubId local, utiliser celui du guildUID reçu
local function GetClubKeyFromUID(guildUID)
	if type(guildUID) ~= "string" then
		return nil
	end
	if guildUID:sub(1, 5) ~= "club:" then
		return nil
	end
	return TEAKeyFromSecret(guildUID, guildUID)
end

-- =========================
-- Compat DB root si GetGuildRoot absent
-- =========================
ns._Compat = ns._Compat or {}
local function GetOrMakeRoot()
	if DB and type(DB.GetGuildRoot) == "function" then
		local ok, root = pcall(DB.GetGuildRoot, DB)
		if ok and type(root) == "table" then
			if type(root.guildInfo) ~= "table" then
				root.guildInfo = {}
			end
			root.members = root.members or {}
			return root
		end
	end
	ns._Compat.root = ns._Compat.root or { guildInfo = { updatedAt = 0 }, members = {} }
	return ns._Compat.root
end

-- =========================
-- Cache, construction, pack
-- =========================
local cache = {} -- [guildUID] = { plain = "...", sum = "hex", ts = <number>, builtAt = <time>, b64 = "..." }
local lastDigest = {} -- [guildUID] = { sum = "hex", ts = <number>, len = <number>, lastAnn = 0, lastFull = 0 }
local lastPatch = {} -- [guildUID][uid][full] = { field = value }
local ANN_FULL_INTERVAL = 600
local SendPATCH

local function BuildPlainSnapshot(guildUID)
	local luaSrc = DB and DB.SerializeGuildSnapshot and DB:SerializeGuildSnapshot(guildUID)
		or "return { guildInfo = {}, players = {} }"
	local name, realm = UnitFullName("player")
	local ts = Now()
	local header = table.concat({
		"WG",
		SNAP_VER,
		tostring(guildUID or ""),
		tostring(ts),
		tostring(name or ""),
		tostring(realm or ""),
	}, "|")
	local plain = header .. "\n" .. luaSrc
	local sum = FNV1a32(plain)
	return plain, ts, Hex8(sum)
end

local function PackFromPlainRaw(guildUID, plain, sumHex)
	local sumNum = tonumber(sumHex, 16) or FNV1a32(plain)
	local plainWithCk = string.char(
		band(rshift(sumNum, 24), 255),
		band(rshift(sumNum, 16), 255),
		band(rshift(sumNum, 8), 255),
		band(sumNum, 255)
	) .. plain
	local key = GetKeyForGuild(guildUID)
	return TEAEncrypt(plainWithCk, key)
end

local function PackFromPlain(guildUID, plain, sumHex)
	local enc = PackFromPlainRaw(guildUID, plain, sumHex)
	return B64Encode(enc)
end

local function EnsureCache(guildUID, forceRebuild)
	local c = cache[guildUID]
	if c and not forceRebuild then
		return c
	end
	local plain, ts, sumHex = BuildPlainSnapshot(guildUID)
	c = { plain = plain, ts = ts, sum = sumHex, builtAt = Now(), enc = false }
	cache[guildUID] = c
	return c
end

-- =========================
-- SNAP pack et unpack
-- =========================
local function PackSnapshotEnc(guildUID)
	local c = EnsureCache(guildUID, true)
	if not c.enc then
		c.enc = PackFromPlainRaw(guildUID, c.plain, c.sum)
	end
	return c.enc, c.sum, #c.plain, c.ts
end

local function PackSnapshot(guildUID)
	local enc, sum, len, ts = PackSnapshotEnc(guildUID)
	return B64Encode(enc), sum, len, ts
end

local function UnpackSnapshotFromEnc(enc, guildUID, sender)
	local key = GetKeyForGuild(guildUID)
	local dec, err = TEADecrypt(enc, key)
	local usedKey = "current"
	if not dec then
		local legacyKey = GetLegacyKeyForGuild(guildUID, sender)
		dec, err = TEADecrypt(enc, legacyKey)
		usedKey = "legacy"
		if not dec then
			local veryLegacyKey = GetVeryLegacyKeyForGuild(guildUID)
			dec, err = TEADecrypt(enc, veryLegacyKey)
			usedKey = "very_legacy"
			if not dec then
				local clubKey = GetClubKeyFromUID(guildUID)
				if clubKey then
					dec, err = TEADecrypt(enc, clubKey)
					usedKey = "club_uid"
				end
				if not dec then
					DevPrint(
						("DECRYPT SNAP fail from %s (key=%s err=%s)"):format(
							tostring(sender or "?"),
							tostring(usedKey),
							tostring(err or "?")
						)
					)
					if err == "pad" or err == "len" then
						AutoClampMaxLine(err)
					end
					return nil, "decrypt:" .. tostring(err)
				end
			end
		end
	end
	if #dec < 4 then
		return nil, "short"
	end
	local cs = bor(lshift(dec:byte(1), 24), lshift(dec:byte(2), 16), lshift(dec:byte(3), 8), dec:byte(4))
	local payload = dec:sub(5)
	if FNV1a32(payload) ~= cs then
		return nil, "checksum"
	end
	local sep = payload:find("\n")
	if not sep then
		return nil, "format"
	end
	local header = payload:sub(1, sep - 1)
	local luaSrc = payload:sub(sep + 1)
	local parts = {}
	for s in header:gmatch("([^|]+)") do
		parts[#parts + 1] = s
	end
	if parts[1] ~= "WG" or parts[2] ~= SNAP_VER then
		return nil, "version"
	end
	local ts = tonumber(parts[4]) or 0
	local tbl
	if LoadTable then
		local err
		tbl, err = LoadTable(luaSrc, {}, MAX_LUA_SNAPSHOT)
		if not tbl then
			if err == "exec" then
				return nil, "exec"
			end
			if err == "type" then
				return nil, "type"
			end
			if err == "too_large" then
				return nil, "too_large"
			end
			return nil, "load:" .. tostring(err)
		end
	else
		local srcEnv = {}
		if #luaSrc > MAX_LUA_SNAPSHOT then
			return nil, "too_large"
		end
		local fn, loadErr = loadstring(luaSrc)
		if not fn then
			return nil, "load:" .. tostring(loadErr)
		end
		setfenv(fn, srcEnv)
		local ok, out = pcall(fn)
		if not ok then
			return nil, "exec"
		end
		if type(out) ~= "table" then
			return nil, "type"
		end
		tbl = out
	end
	return {
		guildInfo = type(tbl.guildInfo) == "table" and tbl.guildInfo or {},
		players = tbl.players or {},
		guildShared = type(tbl.guildShared) == "table" and tbl.guildShared or nil,
		featuredNews = type(tbl.featuredNews) == "table" and tbl.featuredNews or nil,
		timestamp = ts,
	}
end

local function UnpackSnapshot(b64, guildUID, sender)
	local enc = B64Decode(NormalizeB64Input(b64 or ""))
	return UnpackSnapshotFromEnc(enc, guildUID, sender)
end

-- =========================
-- Queue anti-throttle (envoi paced)
-- =========================
Comms._sendQ = Comms._sendQ or {}
Comms._sendPump = Comms._sendPump or false

local SEND_PACE = 0.03 -- 30ms; monte à 0.05 si tu veux ultra safe

local function RawSendAddon(line, channel, target)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		return C_ChatInfo.SendAddonMessage(PREFIX, line, channel, target)
	end
	SendAddonMessage(PREFIX, line, channel, target)
	return true
end

local function PumpSendQueue()
	if Comms._sendPump then
		return
	end
	Comms._sendPump = true

	local function step()
		if #Comms._sendQ == 0 then
			Comms._sendPump = false
			return
		end

		local job = table.remove(Comms._sendQ, 1)
		local ok = RawSendAddon(job.line, job.channel, job.target)

		-- Si l’API renvoie false (throttle), on requeue devant et on retente plus tard
		if ok == false then
			table.insert(Comms._sendQ, 1, job)
			C_Timer.After(0.10, step)
			return
		end

		C_Timer.After(SEND_PACE, step)
	end

	C_Timer.After(0, step)
end

local function QueueAddon(line, channel, target)
	Comms._sendQ[#Comms._sendQ + 1] = { line = line, channel = channel, target = target }
	PumpSendQueue()
end

function Comms.QueueGuildLine(line)
	QueueAddon(line, "GUILD")
end

local function MaxChunkBytesFromB64Limit(maxB64Len)
	local groups = math.floor((maxB64Len or 0) / 4)
	if groups <= 0 then
		return 0
	end
	local maxBytes = groups * 3
	maxBytes = math.floor(maxBytes / 8) * 8
	if maxBytes < 8 then
		return 0
	end
	return maxBytes
end

local function SendBigMessage(tag, guildUID, enc, channel, target)
	if channel == "WHISPER" then
		if target and target ~= "" and HasDBMismatch(target) then
			DevPrint(("SendBigMessage skip (db mismatch) target=%s tag=%s"):format(tostring(target), tostring(tag)))
			return
		end
		if not target or target == "" then
			return
		end
	else
		if not HasOtherOnlineGuildMember() then
			return
		end
	end

	local tagStr = tostring(tag or "")
	local gidStr = tostring(guildUID or "")
	local msgid = string.sub(Hex8(FNV1a32((enc or "") .. tostring(Now()))), 1, 8)

	-- Garde-fou anti-rafale : ignore les doublons immédiats vers la même cible.
	if channel == "WHISPER" then
		Comms._bigSendRecent = Comms._bigSendRecent or {}
		local recent = Comms._bigSendRecent
		local now = Now()
		local peer = NormalizePeerName(target)
		local sig = Hex8(FNV1a32((enc or "") .. "|" .. tagStr .. "|" .. gidStr))
		local key = table.concat({ peer, tagStr, gidStr, sig }, "|")
		local last = tonumber(recent[key] or 0) or 0
		if last > 0 and (now - last) <= 1 then
			DevPrint(
				("SendBigMessage skip (dup) %s gid=%s target=%s sig=%s"):format(
					tostring(tagStr),
					tostring(gidStr),
					tostring(target),
					tostring(sig)
				)
			)
			return
		end
		recent[key] = now
	end

	-- IMPORTANT: limite réelle ~255. On garde une marge de sécurité contre le truncation.
	local maxLen = GetMaxAddonLineFor(channel or "GUILD")
	local SAFE_MARGIN = 12
	local safeMaxLen = math.max(64, maxLen - SAFE_MARGIN)

	-- calc chunkSize/total en tenant compte des digits de total/index
	local digits = 1
	local chunkBytes, total = 0, 0

	for _ = 1, 8 do
		-- 7 champs => 6 ';' + digits(total)+digits(index)
		local overhead = #tagStr + #SNAP_VER + #gidStr + #msgid + 6 + (2 * digits)
		local maxChunkB64Len = safeMaxLen - overhead
		chunkBytes = MaxChunkBytesFromB64Limit(maxChunkB64Len)
		if chunkBytes < 8 then
			return
		end
		total = math.ceil(#enc / chunkBytes)
		local nd = #tostring(total)
		if nd == digits then
			break
		end
		digits = nd
	end

	-- garde-fou : si c’est énorme, tu vas flood pendant longtemps
	-- ajuste si tu veux, mais honnêtement au-delà de quelques centaines, c’est pas réaliste.
	if total > 800 then
		DevPrint(("SendBigMessage abort: %d chunks (payload trop gros)"):format(total))
		EmitCommsError("PAYLOAD_TOO_BIG", target or "GUILD", ("chunks=%d"):format(total))
		return
	end
	DevPrint(
		("SendBigMessage %s gid=%s msgid=%s chan=%s target=%s total=%d chunkBytes=%d maxLen=%d enclen=%d"):format(
			tostring(tagStr),
			tostring(gidStr),
			tostring(msgid),
			tostring(channel or "GUILD"),
			tostring(target or ""),
			total,
			chunkBytes,
			maxLen,
			#(enc or "")
		)
	)

	for i = 1, total do
		local s = (i - 1) * chunkBytes + 1
		local e = math.min(i * chunkBytes, #enc)
		local chunkRaw = enc:sub(s, e)
		local chunk = B64Encode(chunkRaw)

		local line = table.concat({
			tagStr,
			SNAP_VER,
			gidStr,
			msgid,
			tostring(total),
			tostring(i),
			chunk,
		}, ";")

		QueueAddon(line, channel or "GUILD", target)
	end
end

-- =========================
-- Fusion DB
-- =========================
local function MergeSnapshotIntoDB(guildUID, snap, fromWho)
	local root = GetOrMakeRoot()
	root.guildInfo = root.guildInfo or {}
	local incomingInfo = type(snap.guildInfo) == "table" and snap.guildInfo or {}
	local incomingAt = tonumber(incomingInfo.updatedAt or 0) or 0
	local existingAt = tonumber(root.guildInfo.updatedAt or 0) or 0
	if ShouldAcceptIncoming(incomingAt, existingAt) then
		for k, v in pairs(incomingInfo) do
			root.guildInfo[k] = v
		end
	end
	root.guildInfo.updatedAt = math.max(existingAt, incomingAt, tonumber(root.guildInfo.updatedAt or 0) or 0)

	if DB and type(DB.UpsertCharacterFromRemote) == "function" then
		for uid, p in pairs(snap.players or {}) do
			for full, c in pairs(p.characters or {}) do
				DB:UpsertCharacterFromRemote(guildUID, uid, c)
			end
			if DB.RecomputeMainInGuild then
				DB:RecomputeMainInGuild(guildUID, uid)
			end
		end
	else
		local root2 = GetOrMakeRoot()
		root2.players = root2.players or {}
		for uid, p in pairs(snap.players or {}) do
			local dst = root2.players[uid] or { characters = {}, mainFull = "" }
			dst.characters = dst.characters or {}
			for full, c in pairs(p.characters or {}) do
				dst.characters[full] = c
			end
			dst.mainFull = p.mainFull or dst.mainFull or ""
			dst.updatedAt = Now()
			root2.players[uid] = dst
		end
	end

	if snap.featuredNews and snap.featuredNews.byKey and WoWGuildeDB then
		WoWGuildeDB.guilds = WoWGuildeDB.guilds or {}
		local g = WoWGuildeDB.guilds[guildUID] or { guildInfo = { guildUID = guildUID }, players = {} }
		WoWGuildeDB.guilds[guildUID] = g
		g.proudNews = g.proudNews or {}
		g.proudNews.legendaryProud = g.proudNews.legendaryProud or {}
		g.proudNews.legendaryProud.byKey = g.proudNews.legendaryProud.byKey or {}
		local merged = {}
		for k, v in pairs(g.proudNews.legendaryProud.byKey or {}) do
			if type(v) == "table" then
				merged[k] = v
			end
		end
		if type(g.featuredNews) == "table" and type(g.featuredNews.byKey) == "table" then
			Featured_MergeByKey(merged, g.featuredNews.byKey)
		end
		Featured_MergeByKey(merged, snap.featuredNews.byKey)
		g.proudNews.legendaryProud.byKey = merged
		g.featuredNews = nil
	end

	if snap.guildShared and snap.guildShared.guildMemberPrefs then
		if DB and DB.UpsertGuildMemberPrefs then
			for uid, v in pairs(snap.guildShared.guildMemberPrefs) do
				if type(v) == "table" then
					local prefs = NormalizePrefs(v)
					if prefs then
						prefs.updatedAt = NormalizeUpdatedAt(v.updatedAt, false)
						prefs = ApplyEpicVisibilityPolicy(prefs)
						local existing = DB.GetGuildMemberPrefs and DB:GetGuildMemberPrefs(guildUID, uid) or nil
						prefs = MergePrefsMostRecent(prefs, existing)
						DB:UpsertGuildMemberPrefs(guildUID, uid, prefs, true)
					end
				end
			end
		elseif WoWGuildeDB then
			WoWGuildeDB.guilds = WoWGuildeDB.guilds or {}
			local g = WoWGuildeDB.guilds[guildUID] or { guildInfo = { guildUID = guildUID }, players = {} }
			WoWGuildeDB.guilds[guildUID] = g
			g.guildShared = g.guildShared or {}
			g.guildShared.guildMemberPrefs = g.guildShared.guildMemberPrefs or {}
			for uid, v in pairs(snap.guildShared.guildMemberPrefs) do
				if type(v) == "table" then
					local cur = g.guildShared.guildMemberPrefs[uid] or {}
					local prefs = NormalizePrefs(v)
					if prefs then
						prefs.updatedAt = NormalizeUpdatedAt(v.updatedAt, false)
						prefs = ApplyEpicVisibilityPolicy(prefs)
						prefs = MergePrefsMostRecent(prefs, cur)
						if prefs.emotesEnabled ~= nil then
							cur.emotesEnabled = prefs.emotesEnabled
						end
						if prefs.emotesSound ~= nil then
							cur.emotesSound = prefs.emotesSound
						end
						if prefs.biographie ~= nil then
							cur.biographie = cur.biographie or {}
							for ek, ev in pairs(prefs.biographie) do
								if ev == "__DELETE__" then
									cur.biographie[ek] = nil
								elseif type(ev) == "table" then
									local copy = {}
									for bk, bv in pairs(ev) do
										copy[bk] = bv
									end
									if not (copy.status and copy.status ~= "published") then
										cur.biographie[ek] = copy
									end
								elseif type(ev) == "string" and ev:sub(1, #EPIC_B64_PREFIX) == EPIC_B64_PREFIX then
									local epicTable = TryDecodeEpicValue(ev)
									if not (epicTable and epicTable.status and epicTable.status ~= "published") then
										cur.biographie[ek] = ev
									end
								end
							end
							if not next(cur.biographie) then
								cur.biographie = nil
							end
						end
						cur.updatedAt = NormalizeUpdatedAt(prefs.updatedAt, true)
						g.guildShared.guildMemberPrefs[uid] = cur
					end
				end
			end
		end
	end

	if snap.guildShared and snap.guildShared.guildProgress then
		if DB and DB.MergeGuildProgress then
			DB:MergeGuildProgress(guildUID, snap.guildShared.guildProgress)
		elseif WoWGuildeDB then
			WoWGuildeDB.guilds = WoWGuildeDB.guilds or {}
			local g = WoWGuildeDB.guilds[guildUID] or { guildInfo = { guildUID = guildUID }, players = {} }
			WoWGuildeDB.guilds[guildUID] = g
			g.guildShared = g.guildShared or {}
			g.guildShared.guildProgress = snap.guildShared.guildProgress
		end
	end

	if snap.guildShared and snap.guildShared.rosteur then
		if ns and ns.Rosteur and ns.Rosteur.ApplyRemote then
			ns.Rosteur.ApplyRemote(guildUID, snap.guildShared.rosteur, snap.guildShared.rosteur.updatedAt, fromWho)
		elseif WoWGuildeDB then
			WoWGuildeDB.guilds = WoWGuildeDB.guilds or {}
			local g = WoWGuildeDB.guilds[guildUID] or { guildInfo = { guildUID = guildUID }, players = {} }
			WoWGuildeDB.guilds[guildUID] = g
			g.guildShared = g.guildShared or {}
			g.guildShared.rosteur = snap.guildShared.rosteur
			if EventBus and EventBus.Emit then
				EventBus.Emit("WG_ROSTEUR_UPDATED", guildUID, snap.guildShared.rosteur, fromWho)
			end
		end
	end

	if ns and ns.Sections and ns.Sections.HerosFrame and ns.Sections.HerosFrame.Refresh then
		ns.Sections.HerosFrame.Refresh()
	end
end

-- =========================
-- Protocole léger ANN / GET / SNAP
-- =========================
-- ANN « digest léger »: "ANN;SNAP_VER;guildUID;sumHex;ts;len"
-- GET « demande ciblée »: "GET;SNAP_VER;guildUID;sumHex"
-- SNAP « envoi découpé »: "SNAP;SNAP_VER;guildUID;msgid;total;index;chunk"

local function SendANN(guildUID, sumHex, ts, len)
	if not HasOtherOnlineGuildMember() then
		return
	end
	local line =
		table.concat({ "ANN", SNAP_VER, tostring(guildUID), tostring(sumHex), tostring(ts), tostring(len) }, ";")
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(PREFIX, line, "GUILD")
	else
		SendAddonMessage(PREFIX, line, "GUILD")
	end
	Notices.SendDigestGuild()
end

local function SendGET(target, guildUID, sumHex)
	if target and target ~= "" and HasDBMismatch(target) then
		DevPrint(("SendGET skip (db mismatch) target=%s"):format(tostring(target)))
		return
	end
	if not target or target == "" then
		return
	end
	local line = table.concat({ "GET", SNAP_VER, tostring(guildUID), tostring(sumHex) }, ";")
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(PREFIX, line, "WHISPER", target)
	else
		SendAddonMessage(PREFIX, line, "WHISPER", target)
	end
	Notices.SendSnapshotRequest(target)
end

-- Réassemblage SNAP
local inbox = {}
local inboxNews = {}
local inboxNewsBatch = {}
local inboxFeat = {}
local inboxSync = {}
local respondedNewsReq = {}
local lastPrune = 0

local function PruneInboxTables()
	local now = Now()
	if now - lastPrune < PRUNE_INTERVAL then
		return
	end
	lastPrune = now

	for msgid, box in pairs(inbox) do
		if box and box.t0 and (now - box.t0) > INBOX_TTL then
			inbox[msgid] = nil
		end
	end
	for msgid, box in pairs(inboxNews) do
		if box and box.t0 and (now - box.t0) > INBOX_TTL then
			inboxNews[msgid] = nil
		end
	end
	for msgid, box in pairs(inboxNewsBatch) do
		if box and box.t0 and (now - box.t0) > INBOX_TTL then
			inboxNewsBatch[msgid] = nil
		end
	end
	for msgid, box in pairs(inboxFeat) do
		if box and box.t0 and (now - box.t0) > INBOX_TTL then
			inboxFeat[msgid] = nil
		end
	end
	for msgid, box in pairs(inboxSync) do
		if box and box.t0 and (now - box.t0) > INBOX_TTL then
			inboxSync[msgid] = nil
		end
	end
	for key, ts in pairs(respondedNewsReq) do
		if type(ts) == "number" then
			if (now - ts) > NEWSREQ_TTL then
				respondedNewsReq[key] = nil
			end
		else
			respondedNewsReq[key] = nil
		end
	end
end
local function OnSnapChunk(prefix, message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	if p[1] ~= "SNAP" then
		return
	end
	if p[2] ~= SNAP_VER then
		MarkDBMismatch(sender, "SNAP", p[2], SNAP_VER)
		Notices.VersionMismatch(sender, "SNAP", p[2], SNAP_VER)
		EmitCommsError("VERSION_MISMATCH", sender, "SNAP")
		return
	end
	ClearDBMismatch(sender)

	local guildUID, msgid = p[3], p[4]
	local total = tonumber(p[5]) or 0
	local index = tonumber(p[6]) or 0
	local chunk = p[7] or ""
	if not guildUID or not msgid or total <= 0 or index <= 0 then
		return
	end
	DevPrint(
		("SNAP chunk in sender=%s gid=%s msgid=%s idx=%d/%d len=%d"):format(
			tostring(sender or "?"),
			tostring(guildUID),
			tostring(msgid),
			index,
			total,
			#chunk
		)
	)

	if not IsAcceptedGuildUID(guildUID) then
		return
	end

	local box = inbox[msgid]
	if not box then
		box = { total = total, got = 0, guildUID = guildUID, chunks = {}, from = sender, t0 = Now() }
		inbox[msgid] = box
	end
	if not box.chunks[index] then
		local encChunk = B64Decode(NormalizeB64Input(chunk))
		if not encChunk or encChunk == "" or (#encChunk % 8) ~= 0 then
			DevPrint(
				("SNAP bad chunk sender=%s gid=%s msgid=%s idx=%d/%d len=%d"):format(
					tostring(sender or "?"),
					tostring(guildUID),
					tostring(msgid),
					index,
					total,
					#(encChunk or "")
				)
			)
			inbox[msgid] = nil
			return
		end
		box.chunks[index] = encChunk
		box.got = box.got + 1
	end
	if box.got >= box.total then
		local enc = table.concat(box.chunks, "")
		inbox[msgid] = nil

		local snap, err = UnpackSnapshotFromEnc(enc, guildUID, sender)
		if not snap then
			DevPrint(
				("SNAP decode fail sender=%s gid=%s msgid=%s err=%s enclen=%d"):format(
					tostring(sender or "?"),
					tostring(guildUID),
					tostring(msgid),
					tostring(err or "?"),
					#enc
				)
			)
			Notices.ErrorSnapshot(sender, err)
			EmitCommsError("SNAP_DECODE", sender, err)
			return
		end
		DevPrint(
			("SNAP assembled sender=%s gid=%s msgid=%s chunks=%d enclen=%d"):format(
				tostring(sender or "?"),
				tostring(guildUID),
				tostring(msgid),
				total,
				#enc
			)
		)
		MergeSnapshotIntoDB(guildUID, snap, sender)
		if EventBus and EventBus.Emit then
			EventBus.Emit("WG_SNAPSHOT_RECEIVED", guildUID, sender)
		end
		DevPrint(("SNAP reçu de %s (%s)"):format(tostring(sender), tostring(guildUID)))
		Notices.ReceiveSnapshot(sender)
	end
end

local function PackNewsPayload(guildUID, kv)
	local luaSrc = SerializeKV(kv)
	local sum = FNV1a32(luaSrc)
	local plainWithCk = string.char(
		band(rshift(sum, 24), 255),
		band(rshift(sum, 16), 255),
		band(rshift(sum, 8), 255),
		band(sum, 255)
	) .. luaSrc
	local key = GetKeyForGuild(guildUID)
	local enc = TEAEncrypt(plainWithCk, key)
	return B64Encode(enc)
end

local function PackNewsPayloadRaw(guildUID, kv)
	local luaSrc = SerializeKV(kv)
	local sum = FNV1a32(luaSrc)
	local plainWithCk = string.char(
		band(rshift(sum, 24), 255),
		band(rshift(sum, 16), 255),
		band(rshift(sum, 8), 255),
		band(sum, 255)
	) .. luaSrc
	local key = GetKeyForGuild(guildUID)
	return TEAEncrypt(plainWithCk, key)
end

local function UnpackPayloadFromEnc(enc, guildUID, sender)
	local key = GetKeyForGuild(guildUID)
	local dec, err = TEADecrypt(enc, key)
	local usedKey = "current"
	if not dec then
		local legacyKey = GetLegacyKeyForGuild(guildUID, sender)
		dec, err = TEADecrypt(enc, legacyKey)
		usedKey = "legacy"
		if not dec then
			local veryLegacyKey = GetVeryLegacyKeyForGuild(guildUID)
			dec, err = TEADecrypt(enc, veryLegacyKey)
			usedKey = "very_legacy"
			if not dec then
				local clubKey = GetClubKeyFromUID(guildUID)
				if clubKey then
					dec, err = TEADecrypt(enc, clubKey)
					usedKey = "club_uid"
				end
			end
		end
	end
	if not dec or #dec < 4 then
		DevPrint(
			("DECRYPT NEWS fail from %s (key=%s err=%s)"):format(
				tostring(sender or "?"),
				tostring(usedKey),
				tostring(err or "?")
			)
		)
		if err == "pad" or err == "len" then
			AutoClampMaxLine(err)
		end
		return nil, "decrypt"
	end
	local cs = bor(lshift(dec:byte(1), 24), lshift(dec:byte(2), 16), lshift(dec:byte(3), 8), dec:byte(4))
	local payload = dec:sub(5)
	if FNV1a32(payload) ~= cs then
		return nil, "checksum"
	end
	if LoadTable then
		local err
		local kv = nil
		kv, err = LoadTable(payload, {}, MAX_LUA_PAYLOAD)
		if not kv then
			if err == "exec" or err == "type" then
				return nil, "exec"
			end
			if err == "too_large" then
				return nil, "too_large"
			end
			return nil, "load"
		end
		return kv
	end
	if #payload > MAX_LUA_PAYLOAD then
		return nil, "too_large"
	end
	local fn = loadstring(payload)
	if not fn then
		return nil, "load"
	end
	local env = {}
	setfenv(fn, env)
	local ok, kv = pcall(fn)
	if not ok or type(kv) ~= "table" then
		return nil, "exec"
	end
	return kv
end

local function UnpackPayload(b64, guildUID, sender)
	local enc = B64Decode(NormalizeB64Input(b64 or ""))
	return UnpackPayloadFromEnc(enc, guildUID, sender)
end

local function OnNewsChunk(prefix, message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	if p[1] ~= "NEWS" then
		return
	end
	if p[2] ~= SNAP_VER then
		MarkDBMismatch(sender, "NEWS", p[2], SNAP_VER)
		Notices.VersionMismatch(sender, "NEWS", p[2], SNAP_VER)
		EmitCommsError("VERSION_MISMATCH", sender, "NEWS")
		return
	end
	ClearDBMismatch(sender)

	local guildUID, msgid = p[3], p[4]
	local total = tonumber(p[5]) or 0
	local index = tonumber(p[6]) or 0
	local chunk = p[7] or ""
	if not guildUID or not msgid or total <= 0 or index <= 0 then
		return
	end
	DevPrint(
		("NEWS chunk in sender=%s gid=%s msgid=%s idx=%d/%d len=%d"):format(
			tostring(sender or "?"),
			tostring(guildUID),
			tostring(msgid),
			index,
			total,
			#chunk
		)
	)

	if not IsAcceptedGuildUID(guildUID) then
		return
	end

	local box = inboxNews[msgid]
	if not box then
		box = { total = total, got = 0, guildUID = guildUID, chunks = {}, from = sender, t0 = Now() }
		inboxNews[msgid] = box
	end
	if not box.chunks[index] then
		local encChunk = B64Decode(NormalizeB64Input(chunk))
		if not encChunk or encChunk == "" or (#encChunk % 8) ~= 0 then
			DevPrint(
				("NEWS bad chunk sender=%s gid=%s msgid=%s idx=%d/%d len=%d"):format(
					tostring(sender or "?"),
					tostring(guildUID),
					tostring(msgid),
					index,
					total,
					#(encChunk or "")
				)
			)
			inboxNews[msgid] = nil
			return
		end
		box.chunks[index] = encChunk
		box.got = box.got + 1
	end
	if box.got >= box.total then
		local enc = table.concat(box.chunks, "")
		inboxNews[msgid] = nil
		local kvRaw, err = UnpackPayloadFromEnc(enc, guildUID, sender)
		local kv = kvRaw and NormalizeNewsKV(kvRaw) or nil
		if not kv then
			DevPrint(
				("NEWS decode fail sender=%s gid=%s msgid=%s err=%s enclen=%d"):format(
					tostring(sender or "?"),
					tostring(guildUID),
					tostring(msgid),
					tostring(err or "?"),
					#enc
				)
			)
			Notices.ErrorNews(sender, err)
			EmitCommsError("NEWS_DECODE", sender, err)
			return
		end
		DevPrint(
			("NEWS assembled sender=%s gid=%s msgid=%s chunks=%d enclen=%d"):format(
				tostring(sender or "?"),
				tostring(guildUID),
				tostring(msgid),
				total,
				#enc
			)
		)
		local added = false
		if ns and ns.Data and ns.Data.Journalist and ns.Data.Journalist.AddRemoteNews then
			added = ns.Data.Journalist.AddRemoteNews(
				kv.text,
				kv.typ,
				kv.icon,
				kv.ts,
				guildUID,
				kv.replaceKey,
				kv.id,
				kv.title,
				kv.points,
				kv.uid
			)
		end
		if added then
			if EventBus and EventBus.Emit then
				EventBus.Emit("WG_NEWS_RECEIVED", kv, guildUID, sender)
			end
			DevPrint(("NEWS reçue (%s) de %s"):format(tostring(kv.id or "?"), tostring(sender)))
			Notices.ReceiveNews(sender)
			local relay = tonumber(kv.relay or 0) or 0
			if NEWS_RELAY_MAX > 0 and relay < NEWS_RELAY_MAX and sender ~= LocalFullName() then
				Comms:SendNews(
					kv.text,
					kv.typ,
					kv.icon,
					kv.ts,
					kv.replaceKey,
					guildUID,
					kv.id,
					relay + 1,
					kv.origin or sender,
					kv.title
				)
				Notices.SendRelayNews(kv.origin or sender)
			end
		end
	end
end

local function PackNewsBatchPayload(guildUID, items)
	local luaSrc = SerializeNewsList(items or {})
	local sum = FNV1a32(luaSrc)
	local plainWithCk = string.char(
		band(rshift(sum, 24), 255),
		band(rshift(sum, 16), 255),
		band(rshift(sum, 8), 255),
		band(sum, 255)
	) .. luaSrc
	local key = GetKeyForGuild(guildUID)
	local enc = TEAEncrypt(plainWithCk, key)
	return B64Encode(enc)
end

local function PackNewsBatchPayloadRaw(guildUID, items)
	local luaSrc = SerializeNewsList(items or {})
	local sum = FNV1a32(luaSrc)
	local plainWithCk = string.char(
		band(rshift(sum, 24), 255),
		band(rshift(sum, 16), 255),
		band(rshift(sum, 8), 255),
		band(sum, 255)
	) .. luaSrc
	local key = GetKeyForGuild(guildUID)
	return TEAEncrypt(plainWithCk, key)
end

local function OnNewsBatchChunk(prefix, message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	if p[1] ~= "NEWSB" then
		return
	end
	if p[2] ~= SNAP_VER then
		MarkDBMismatch(sender, "NEWSB", p[2], SNAP_VER)
		Notices.VersionMismatch(sender, "NEWSB", p[2], SNAP_VER)
		return
	end
	ClearDBMismatch(sender)

	local guildUID, msgid = p[3], p[4]
	local total = tonumber(p[5]) or 0
	local index = tonumber(p[6]) or 0
	local chunk = p[7] or ""
	if not guildUID or not msgid or total <= 0 or index <= 0 then
		return
	end
	DevPrint(
		("NEWSB chunk in sender=%s gid=%s msgid=%s idx=%d/%d len=%d"):format(
			tostring(sender or "?"),
			tostring(guildUID),
			tostring(msgid),
			index,
			total,
			#chunk
		)
	)

	if not IsAcceptedGuildUID(guildUID) then
		return
	end

	local box = inboxNewsBatch[msgid]
	if not box then
		box = { total = total, got = 0, guildUID = guildUID, chunks = {}, from = sender, t0 = Now() }
		inboxNewsBatch[msgid] = box
	end
	if not box.chunks[index] then
		local encChunk = B64Decode(NormalizeB64Input(chunk))
		if not encChunk or encChunk == "" or (#encChunk % 8) ~= 0 then
			DevPrint(
				("NEWSB bad chunk sender=%s gid=%s msgid=%s idx=%d/%d len=%d"):format(
					tostring(sender or "?"),
					tostring(guildUID),
					tostring(msgid),
					index,
					total,
					#(encChunk or "")
				)
			)
			inboxNewsBatch[msgid] = nil
			return
		end
		box.chunks[index] = encChunk
		box.got = box.got + 1
	end
	if box.got >= box.total then
		local enc = table.concat(box.chunks, "")
		inboxNewsBatch[msgid] = nil
		local kv, err = UnpackPayloadFromEnc(enc, guildUID, sender)
		if not kv or type(kv.items) ~= "table" then
			DevPrint(
				("NEWSB decode fail sender=%s gid=%s msgid=%s err=%s enclen=%d"):format(
					tostring(sender or "?"),
					tostring(guildUID),
					tostring(msgid),
					tostring(err or "?"),
					#enc
				)
			)
			Notices.ErrorNewsBatch(sender, err)
			return
		end
		DevPrint(
			("NEWSB assembled sender=%s gid=%s msgid=%s chunks=%d enclen=%d"):format(
				tostring(sender or "?"),
				tostring(guildUID),
				tostring(msgid),
				total,
				#enc
			)
		)
		local addedCount = 0
		for i = 1, #kv.items do
			local it = kv.items[i]
			local item = it and NormalizeNewsKV(it) or nil
			if item then
				local added = ns
					and ns.Data
					and ns.Data.Journalist
					and ns.Data.Journalist.AddRemoteNews
					and ns.Data.Journalist.AddRemoteNews(
						item.text,
						item.typ,
						item.icon,
						item.ts,
						guildUID,
						item.replaceKey,
						item.id,
						item.title,
						item.points
					)
				if added then
					addedCount = addedCount + 1
				end
			end
		end
		if addedCount > 0 then
			Notices.ReceiveNewsBatch(sender, addedCount)
		end
	end
end

-- Gestion ANN et GET
local function OnLightProtocol(prefix, message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	local kind, ver = p[1], p[2]
	if ver ~= SNAP_VER then
		MarkDBMismatch(sender, kind or "?", ver, SNAP_VER)
		Notices.VersionMismatch(sender, kind or "?", ver, SNAP_VER)
		return
	end
	ClearDBMismatch(sender)

	if kind == "ANN" then
		local guildUID, sumHex, ts, len = p[3], p[4], tonumber(p[5]) or 0, tonumber(p[6]) or 0
		if not IsAcceptedGuildUID(guildUID) then
			return
		end
		Notices.ReceiveDigestAnnounce(sender)
		local have = lastDigest[guildUID]
		if not have or have.sum ~= sumHex then
			local jitter = math.random() * 0.8
			C_Timer.After(jitter, function()
				SendGET(sender, guildUID, sumHex)
			end)
		end
	elseif kind == "GET" and channel == "WHISPER" then
		local guildUID, sumHex = p[3], p[4]
		if not IsAcceptedGuildUID(guildUID) then
			return
		end
		Notices.ReceiveSnapshotRequest(sender)

		local d = lastDigest[guildUID]
		if not d or d.sum ~= sumHex then
			-- Nous n’avons pas ce digest en cache, re-annonce rapidement
			C_Timer.After(0.1, function()
				local c = EnsureCache(guildUID, true)
				lastDigest[guildUID] = { sum = c.sum, ts = c.ts, len = #c.plain, lastAnn = Now() }
				SendANN(guildUID, c.sum, c.ts, #c.plain)
			end)
			return
		end

		local ok, enc = pcall(function()
			local c = cache[guildUID]
			if not c or c.sum ~= sumHex or not c.enc then
				c = EnsureCache(guildUID, true)
				if not c.enc then
					c.enc = PackFromPlainRaw(guildUID, c.plain, c.sum)
				end
			end
			return c.enc
		end)
		if ok and enc then
			SendBigMessage("SNAP", guildUID, enc, "WHISPER", sender)
			Notices.SendSnapshot(sender)
		end
	end
end

-- =========================
-- Annonce coalescée anti spam
-- =========================
local announcePending = false
local function DoAnnounce()
	announcePending = false
	local gid = DB and DB.GetGuildUID and DB:GetGuildUID()
	if not gid then
		return
	end
	if not HasOtherOnlineGuildMember() then
		return
	end
	if DB and DB.SaveSelfProfile then
		DB:SaveSelfProfile()
	end

	-- Nouveau sync par élément
	if Comms and Comms.SYNC_ENABLED then
		local now = Now()
		if DB and DB.GetMyUID and DB.GetGuildPlayer then
			local uid = DB:GetMyUID()
			local p = uid and DB:GetGuildPlayer(gid, uid) or nil
			local name, realm = UnitFullName("player")
			realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
			local full = name and (name .. "-" .. tostring(realm or "")) or ""
			local cur = (p and p.characters and p.characters[full]) or nil
			if cur and uid then
				local fields = {
					"full",
					"name",
					"realm",
					"classLoc",
					"classTag",
					"spec",
					"specID",
					"level",
					"ilevel",
					"mplus",
					"achv",
					"isMain",
					"playerGUID",
				}
				lastPatch[gid] = lastPatch[gid] or {}
				lastPatch[gid][uid] = lastPatch[gid][uid] or {}
				local prev = lastPatch[gid][uid][full] or {}
				local snapshot = {}
				local changed = false
				for i = 1, #fields do
					local k = fields[i]
					local v = cur[k]
					snapshot[k] = v
					if v ~= prev[k] then
						changed = true
					end
				end
				if changed and Comms.Sync and Comms.Sync.AnnounceElement then
					Comms.Sync.AnnounceElement(gid, "roster", uid, cur.updatedAt or now)
					lastPatch[gid][uid][full] = snapshot
				end
			end
		end
		if Comms.Sync and Comms.Sync.AnnounceElement then
			local infoTs = nil
			if WoWGuildeDB and WoWGuildeDB.guilds and WoWGuildeDB.guilds[gid] and WoWGuildeDB.guilds[gid].guildInfo then
				infoTs = WoWGuildeDB.guilds[gid].guildInfo.updatedAt
			end
			Comms.Sync.AnnounceElement(gid, "guildinfo", "guildinfo", infoTs or now)
		end
		return
	end

	local now = Now()
	local sentPatch = false
	if DB and DB.GetMyUID and DB.GetGuildPlayer then
		local uid = DB:GetMyUID()
		local p = uid and DB:GetGuildPlayer(gid, uid) or nil
		local name, realm = UnitFullName("player")
		realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
		local full = name and (name .. "-" .. tostring(realm or "")) or ""
		local cur = (p and p.characters and p.characters[full]) or nil
		if cur and uid then
			local fields = {
				"full",
				"name",
				"realm",
				"classLoc",
				"classTag",
				"spec",
				"specID",
				"level",
				"ilevel",
				"mplus",
				"achv",
				"isMain",
				"playerGUID",
			}
			lastPatch[gid] = lastPatch[gid] or {}
			lastPatch[gid][uid] = lastPatch[gid][uid] or {}
			local prev = lastPatch[gid][uid][full] or {}
			local snapshot = {}
			local changes = {}
			for i = 1, #fields do
				local k = fields[i]
				local v = cur[k]
				snapshot[k] = v
				if v ~= prev[k] then
					changes[k] = v
				end
			end
			if next(changes) then
				changes.updatedAt = cur.updatedAt or now
				SendPATCH(gid, uid, full, changes, "ALL")
				lastPatch[gid][uid][full] = snapshot
				sentPatch = true
			end
		end
	end

	local d = lastDigest[gid] or { sum = "", ts = 0, len = 0, lastAnn = 0, lastFull = 0 }
	if now - (d.lastFull or 0) < ANN_FULL_INTERVAL then
		return
	end

	local c = EnsureCache(gid, true)
	if c.sum == d.sum and #c.plain == d.len and sentPatch then
		d.lastFull = now
		lastDigest[gid] = d
		return
	end

	if now - (d.lastAnn or 0) < 30 then
		C_Timer.After(5, function()
			if not announcePending then
				announcePending = true
				C_Timer.After(0.0, DoAnnounce)
			end
		end)
		return
	end

	lastDigest[gid] = { sum = c.sum, ts = c.ts, len = #c.plain, lastAnn = now, lastFull = now }
	SendANN(gid, c.sum, c.ts, #c.plain)
end

local function ScheduleAnnounce(delay)
	if not HasOtherOnlineGuildMember() then
		return
	end
	if announcePending then
		return
	end
	announcePending = true
	C_Timer.After(delay or 2.0, DoAnnounce)
end

local function SendNewsReqBurst(gid)
	if Comms and Comms.SYNC_ENABLED then
		return
	end
	if not gid then
		return
	end
	local now = Now()
	if Comms._lastNewsReqAt and (now - Comms._lastNewsReqAt) < 10 then
		return
	end
	Comms._lastNewsReqAt = now
	local nonce = Hex8(FNV1a32(LocalFullName() .. ":" .. tostring(Now())))
	local stages = math.max(1, math.floor(NEWSREQ_BUCKETS / NEWSREQ_STAGE_SIZE))
	for stage = 0, stages - 1 do
		C_Timer.After(stage * NEWSREQ_STAGE_DELAY, function()
			local line = table.concat({ "NEWSREQ", SNAP_VER, tostring(gid), nonce, tostring(stage) }, ";")
			if C_ChatInfo and C_ChatInfo.SendAddonMessage then
				C_ChatInfo.SendAddonMessage(PREFIX, line, "GUILD")
			else
				SendAddonMessage(PREFIX, line, "GUILD")
			end
			Notices.SendNewsReqStageGuild(stage + 1)
		end)
	end
end

-- =========================
-- PATCH ultra léger, en option
-- =========================
-- Format: "PATCH;SNAP_VER;guildUID;uid;full;b64(payload)"
-- payload = TEA(B64) d’un chunk Lua: return { ilevel = 720, lastPerso = "Rédemption", updatedAt = 1755873764 }

local function PackPatchPayload(guildUID, kv)
	local luaSrc = SerializeKV(kv)
	local sum = FNV1a32(luaSrc)
	local plainWithCk = string.char(
		band(rshift(sum, 24), 255),
		band(rshift(sum, 16), 255),
		band(rshift(sum, 8), 255),
		band(sum, 255)
	) .. luaSrc
	local key = GetKeyForGuild(guildUID)
	local enc = TEAEncrypt(plainWithCk, key)
	return B64Encode(enc)
end

local function UnpackKVPayload(b64, guildUID, sender)
	local enc = B64Decode(NormalizeB64Input(b64 or ""))
	local key = GetKeyForGuild(guildUID)
	local dec, err = TEADecrypt(enc, key)
	local usedKey = "current"
	if not dec then
		local legacyKey = GetLegacyKeyForGuild(guildUID, sender)
		dec, err = TEADecrypt(enc, legacyKey)
		usedKey = "legacy"
		if not dec then
			local veryLegacyKey = GetVeryLegacyKeyForGuild(guildUID)
			dec, err = TEADecrypt(enc, veryLegacyKey)
			usedKey = "very_legacy"
			if not dec then
				local clubKey = GetClubKeyFromUID(guildUID)
				if clubKey then
					dec, err = TEADecrypt(enc, clubKey)
					usedKey = "club_uid"
				end
			end
		end
	end
	if not dec or #dec < 4 then
		DevPrint(
			("DECRYPT PATCH/GPREF fail from %s (key=%s err=%s)"):format(
				tostring(sender or "?"),
				tostring(usedKey),
				tostring(err or "?")
			)
		)
		if err == "pad" or err == "len" then
			AutoClampMaxLine(err)
		end
		return nil
	end
	local cs = bor(lshift(dec:byte(1), 24), lshift(dec:byte(2), 16), lshift(dec:byte(3), 8), dec:byte(4))
	local payload = dec:sub(5)
	if FNV1a32(payload) ~= cs then
		return nil
	end
	if LoadTable then
		local kv = LoadTable(payload, {}, MAX_LUA_PAYLOAD)
		if type(kv) == "table" then
			return kv
		end
		return nil
	end
	if #payload > MAX_LUA_PAYLOAD then
		return nil
	end
	local fn, loadErr = loadstring(payload)
	if not fn then
		return nil
	end
	local env = {}
	setfenv(fn, env)
	local ok, kv = pcall(fn)
	if not ok or type(kv) ~= "table" then
		return nil
	end
	return kv
end

SendPATCH = function(guildUID, uid, full, kv, target)
	if target and target ~= "ALL" and HasDBMismatch(target) then
		DevPrint(("SendPATCH skip (db mismatch) target=%s"):format(tostring(target)))
		return
	end
	if target ~= "ALL" and (not target or target == "") then
		return
	end
	local payload = PackPatchPayload(guildUID, kv)
	local line = table.concat({ "PATCH", SNAP_VER, tostring(guildUID), tostring(uid), tostring(full), payload }, ";")
	if target == "ALL" then
		if not HasOtherOnlineGuildMember() then
			return
		end
		if C_ChatInfo and C_ChatInfo.SendAddonMessage then
			C_ChatInfo.SendAddonMessage(PREFIX, line, "GUILD")
		else
			SendAddonMessage(PREFIX, line, "GUILD")
		end
		Notices.SendPatchGuild(full)
	else
		if C_ChatInfo and C_ChatInfo.SendAddonMessage then
			C_ChatInfo.SendAddonMessage(PREFIX, line, "WHISPER", target)
		else
			SendAddonMessage(PREFIX, line, "WHISPER", target)
		end
		Notices.SendPatchTarget(target, full)
	end
end

local function SendGPREF(guildUID, uid, kv)
	if not HasOtherOnlineGuildMember() then
		return
	end
	if not guildUID or guildUID == "" or not uid or uid == "" or type(kv) ~= "table" then
		return
	end
	local payload = PackPatchPayload(guildUID, kv)
	local line = table.concat({ "GPREF", SNAP_VER, tostring(guildUID), tostring(uid), payload }, ";")
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(PREFIX, line, "GUILD")
	else
		SendAddonMessage(PREFIX, line, "GUILD")
	end
end

local function OnPATCH(message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	-- "PATCH;ver;guildUID;uid;full;b64"
	if p[1] ~= "PATCH" then
		return
	end
	if p[2] ~= SNAP_VER then
		MarkDBMismatch(sender, "PATCH", p[2], SNAP_VER)
		Notices.VersionMismatch(sender, "PATCH", p[2], SNAP_VER)
		EmitCommsError("VERSION_MISMATCH", sender, "PATCH")
		return
	end
	ClearDBMismatch(sender)
	local guildUID, uid, full, b64 = p[3], p[4], p[5], p[6]
	if not guildUID or not uid or not full or not b64 then
		return
	end
	if not IsAcceptedGuildUID(guildUID) then
		return
	end

	local kv = UnpackKVPayload(b64, guildUID, sender)
	if not kv then
		return
	end
	if kv.updatedAt ~= nil then
		kv.updatedAt = NormalizeUpdatedAt(kv.updatedAt, true)
	end

	if DB and type(DB.UpsertCharacterPatch) == "function" then
		DB:UpsertCharacterPatch(guildUID, uid, full, kv)
	else
		local root = GetOrMakeRoot()
		root.players = root.players or {}
		local pinfo = root.players[uid] or { characters = {} }
		pinfo.characters = pinfo.characters or {}
		local cinfo = pinfo.characters[full] or {}
		for k, v in pairs(kv) do
			cinfo[k] = v
		end
		pinfo.characters[full] = cinfo
		pinfo.updatedAt = Now()
		root.players[uid] = pinfo
	end

	if ns and ns.Sections and ns.Sections.HerosFrame and ns.Sections.HerosFrame.Refresh then
		ns.Sections.HerosFrame.Refresh()
	end
	Notices.ReceivePatch(sender, full)
end

local function OnGPREF(message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	-- "GPREF;ver;guildUID;uid;b64"
	if p[1] ~= "GPREF" then
		return
	end
	if p[2] ~= SNAP_VER then
		MarkDBMismatch(sender, "GPREF", p[2], SNAP_VER)
		Notices.VersionMismatch(sender, "GPREF", p[2], SNAP_VER)
		EmitCommsError("VERSION_MISMATCH", sender, "GPREF")
		return
	end
	ClearDBMismatch(sender)
	local guildUID, uid, b64 = p[3], p[4], p[5]
	if not guildUID or not uid or not b64 then
		return
	end
	if not IsAcceptedGuildUID(guildUID) then
		return
	end
	local kv = UnpackKVPayload(b64, guildUID, sender)
	if not kv then
		return
	end
	local prefs = NormalizePrefs(kv)
	if not prefs then
		return
	end
	prefs = ApplyEpicVisibilityPolicy(prefs)
	if DB and DB.UpsertGuildMemberPrefs then
		DB:UpsertGuildMemberPrefs(guildUID, uid, prefs, true)
	end
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_MEMBER_PREFS_RECEIVED", guildUID, uid, prefs, sender)
	end
	DevPrint(("GPREF reçu %s (%s)"):format(tostring(uid), tostring(guildUID)))
	if ns and ns.Sections and ns.Sections.HerosFrame and ns.Sections.HerosFrame.Refresh then
		ns.Sections.HerosFrame.Refresh()
	end
end

-- API pour envoyer un petit patch ciblé
function Comms:SendSmallUpdate(uid, full, changes, target)
	local gid = DB and DB.GetGuildUID and DB:GetGuildUID()
	if not gid or not uid or not full or not changes then
		return
	end
	if Comms and Comms.SYNC_ENABLED and Comms.Sync and Comms.Sync.AnnounceElement then
		Comms.Sync.AnnounceElement(gid, "roster", uid, changes.updatedAt or Now())
		return
	end
	SendPATCH(gid, uid, full, changes, target) -- target peut être « ALL » ou un nom joueur pour WHISPER
end

function Comms:SendGuildMemberPrefs(guildUIDOverride, uid, prefs)
	local gid = guildUIDOverride or (DB and DB.GetGuildUID and DB:GetGuildUID())
	if not gid or not uid or uid == "" or type(prefs) ~= "table" then
		return
	end
	if Comms and Comms.SYNC_ENABLED and Comms.Sync and Comms.Sync.AnnounceElement then
		Comms.Sync.AnnounceElement(gid, "prefs", uid, prefs.updatedAt or Now())
		return
	end
	SendGPREF(gid, uid, prefs)
end

-- =========================
-- Émotions légères (toast)
-- =========================
local function EncodeEmoteContext(ctx)
	if type(ctx) ~= "table" or not SerializeKV or not B64Encode then
		return nil
	end
	local out = {}
	local src = tostring(ctx.source or "")
	if src ~= "" then
		out.source = src
	end
	local newsType = tostring(ctx.newsType or "")
	if newsType ~= "" then
		out.newsType = newsType
	end
	local newsTypeLabel = tostring(ctx.newsTypeLabel or "")
	if newsTypeLabel ~= "" then
		out.newsTypeLabel = newsTypeLabel
	end
	local newsTitle = tostring(ctx.newsTitle or "")
	if newsTitle ~= "" then
		out.newsTitle = newsTitle
	end
	local newsIcon = ctx.newsIcon
	if newsIcon ~= nil and newsIcon ~= "" then
		out.newsIcon = newsIcon
	end
	local actorPseudo = tostring(ctx.actorPseudo or "")
	if actorPseudo ~= "" then
		out.actorPseudo = actorPseudo
	end
	if next(out) == nil then
		return nil
	end
	return B64Encode(SerializeKV(out))
end

local function DecodeEmoteContext(b64)
	if not b64 or b64 == "" or not B64Decode or not LoadTable then
		return nil
	end
	local raw = B64Decode(NormalizeB64Input(b64))
	if not raw or raw == "" then
		return nil
	end
	local okLoad, tbl = pcall(LoadTable, raw, {}, 4096)
	if not okLoad or type(tbl) ~= "table" then
		return nil
	end
	local out = {}
	local source = tostring(tbl.source or "")
	if source ~= "" then
		out.source = source
	end
	local newsType = tostring(tbl.newsType or "")
	if newsType ~= "" then
		out.newsType = newsType
	end
	local newsTypeLabel = tostring(tbl.newsTypeLabel or "")
	if newsTypeLabel ~= "" then
		out.newsTypeLabel = newsTypeLabel
	end
	local newsTitle = tostring(tbl.newsTitle or "")
	if newsTitle ~= "" then
		out.newsTitle = newsTitle
	end
	local newsIcon = tbl.newsIcon
	if newsIcon ~= nil and newsIcon ~= "" then
		out.newsIcon = newsIcon
	end
	local actorPseudo = tostring(tbl.actorPseudo or "")
	if actorPseudo ~= "" then
		out.actorPseudo = actorPseudo
	end
	if next(out) == nil then
		return nil
	end
	return out
end

local function SendEMO(target, key, context)
	if target and target ~= "" and HasDBMismatch(target) then
		DevPrint(("SendEMO skip (db mismatch) target=%s"):format(tostring(target)))
		return
	end
	local gid = DB and DB.GetGuildUID and DB:GetGuildUID()
	if not gid or not target or target == "" or not key then
		return
	end
	local from = LocalFullName()
	local ts = Now()
	local parts = { "EMO", SNAP_VER, tostring(gid), tostring(key), tostring(from), tostring(ts) }
	local ctxB64 = EncodeEmoteContext(context)
	if ctxB64 and ctxB64 ~= "" then
		parts[#parts + 1] = ctxB64
	end
	local line = table.concat(parts, ";")
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(PREFIX, line, "WHISPER", target)
	else
		SendAddonMessage(PREFIX, line, "WHISPER", target)
	end
	Notices.SendEmote(target, key)
end

local function OnEMO(message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	-- "EMO;ver;guildUID;key;from;ts"
	if p[1] ~= "EMO" then
		return
	end
	if p[2] ~= SNAP_VER then
		MarkDBMismatch(sender, "EMO", p[2], SNAP_VER)
		Notices.VersionMismatch(sender, "EMO", p[2], SNAP_VER)
		return
	end
	ClearDBMismatch(sender)
	local guildUID, key, from, ts = p[3], p[4], p[5], tonumber(p[6]) or Now()
	local context = DecodeEmoteContext(p[7])
	if not guildUID or not key then
		return
	end

	-- N’accepte que pour la guilde locale
	if not IsAcceptedGuildUID(guildUID) then
		return
	end

	from = (from and from ~= "") and from or (sender or "?")
	Notices.ReceiveEmote(from, key)
	-- Délègue vers le module Emotes pour journaliser et toaster
	if ns and ns.Emotes and ns.Emotes.Receive then
		ns.Emotes.Receive(key, from, ts, context)
	end
end

local function EnsureProudRoot(guildUID)
	if not guildUID or guildUID == "" then
		return nil
	end
	local db = EnsureDB()
	db.guilds = db.guilds or {}
	local g = db.guilds[guildUID]
	if not g then
		g = { guildInfo = { guildUID = guildUID }, players = {} }
		db.guilds[guildUID] = g
	end
	if type(g.proudNews) ~= "table" then
		g.proudNews = {}
	end
	g.proudNews.proudByCharacter = g.proudNews.proudByCharacter or {}
	g.proudNews.proudByMe = g.proudNews.proudByMe or {}
	g.proudNews.proudByCharacterMeta = g.proudNews.proudByCharacterMeta or {}
	return g.proudNews
end

Featured_MergeByKey = function(dst, src)
	if type(dst) ~= "table" or type(src) ~= "table" then
		return
	end
	for key, v in pairs(src) do
		if type(v) == "table" then
			local incoming = FeaturedUpdatedAt(v)
			local existing = FeaturedUpdatedAt(dst[key])
			local hasExisting = dst[key] ~= nil
			if ShouldAcceptMostRecent(incoming, existing, hasExisting) then
				local out = {}
				for fk, fv in pairs(v) do
					out[fk] = fv
				end
				out.updatedAt = NormalizeUpdatedAt(out.updatedAt or incoming, false)
				dst[key] = out
			end
		end
	end
end

local function EnsureFeaturedRoot(guildUID)
	if not guildUID or guildUID == "" then
		return nil
	end
	local db = EnsureDB()
	db.guilds = db.guilds or {}
	local g = db.guilds[guildUID]
	if not g then
		g = { guildInfo = { guildUID = guildUID }, players = {} }
		db.guilds[guildUID] = g
	end
	if type(g.proudNews) ~= "table" then
		g.proudNews = {}
	end
	g.proudNews.proudByCharacter = g.proudNews.proudByCharacter or {}
	g.proudNews.proudByMe = g.proudNews.proudByMe or {}
	g.proudNews.legendaryProud = g.proudNews.legendaryProud or {}
	g.proudNews.legendaryProud.byKey = g.proudNews.legendaryProud.byKey or {}
	g.proudNews.legendaryProud.meta = g.proudNews.legendaryProud.meta or {}
	if type(g.featuredNews) == "table" and type(g.featuredNews.byKey) == "table" then
		Featured_MergeByKey(g.proudNews.legendaryProud.byKey, g.featuredNews.byKey)
		g.featuredNews = nil
	end
	return g.proudNews.legendaryProud
end

local function ApplyProudUpdate(newsId, actor, proud, actorUID, guildUID, ts)
	if not newsId or newsId == "" or not actor or actor == "" then
		return
	end
	local root = EnsureProudRoot(guildUID)
	if not root then
		return
	end
	root.proudByCharacterMeta = root.proudByCharacterMeta or {}
	local byRoot = root.proudByCharacter
	local by = byRoot[newsId]
	if type(by) ~= "table" then
		by = {}
	end
	local key = (type(actorUID) == "string" and actorUID ~= "") and actorUID or actor
	local incomingAt = NormalizeUpdatedAt(ts, true)
	local meta = root.proudByCharacterMeta[newsId]
	if type(meta) ~= "table" then
		meta = {}
		root.proudByCharacterMeta[newsId] = meta
	end
	local existingAt = tonumber(meta[key] or 0) or 0
	if incomingAt <= 0 and existingAt > 0 then
		return
	end
	if existingAt > 0 and incomingAt > 0 and incomingAt < existingAt then
		return
	end
	if incomingAt <= 0 then
		incomingAt = Now()
	end
	meta[key] = incomingAt
	if proud then
		if type(actorUID) == "string" and actorUID ~= "" then
			by[key] = { name = actor }
		else
			by[key] = true
		end
	else
		by[key] = nil
	end
	if next(by) == nil then
		byRoot[newsId] = nil
	else
		byRoot[newsId] = by
	end
	if ns.Sections and ns.Sections.Social_OnProudUpdate then
		ns.Sections.Social_OnProudUpdate(newsId, actor, proud, actorUID, guildUID)
	end
	if ns.Sections and ns.Sections.Heros_OnProudUpdate then
		ns.Sections.Heros_OnProudUpdate(newsId, actor, proud, actorUID, guildUID)
	end
end

local function ApplyFeaturedUpdate(guildUID, heroKey, news, force)
	if not guildUID or guildUID == "" or not heroKey or heroKey == "" or not news then
		return
	end
	local root = EnsureFeaturedRoot(guildUID)
	if not root then
		return
	end
	local incoming = FeaturedUpdatedAt(news)
	local existing = FeaturedUpdatedAt(root.byKey[heroKey])
	local hasExisting = root.byKey[heroKey] ~= nil
	if not force and not ShouldAcceptMostRecent(incoming, existing, hasExisting) then
		return
	end
	root.meta = root.meta or {}
	if news.clear then
		root.byKey[heroKey] = nil
		root.meta[heroKey] = { ts = NormalizeUpdatedAt(news.updatedAt or incoming, true), clear = true }
	else
		news.updatedAt = NormalizeUpdatedAt(news.updatedAt or incoming, true)
		root.byKey[heroKey] = news
		root.meta[heroKey] = { ts = news.updatedAt, clear = false }
	end
	if ns.Sections then
		if ns.Sections.Heros_OnFeaturedUpdate then
			ns.Sections.Heros_OnFeaturedUpdate(guildUID, heroKey, news)
		end
		if ns.Sections.Social_OnFeaturedUpdate then
			ns.Sections.Social_OnFeaturedUpdate(guildUID, heroKey, news)
		end
	end
end

-- =========================
-- Sync distribué par élément (EANN / EREQ / EPAY)
-- =========================
local Sync = Comms.Sync or {}
Comms.Sync = Sync
Sync.ENABLED = true
Comms.SYNC_ENABLED = true
Sync.VER = SNAP_VER
Sync.REQ_TTL = 20
Sync.SENT_TTL = 8
Sync.ANN_TTL = 6
Sync.ANN_BATCH = 20
Sync.ANN_DELAY = 0.2
Sync.ANN_WINDOW = 30
Sync.ANN_TICK = 0.2
Sync.NEWSDEL_TTL = 14 * 86400

Sync.handlers = Sync.handlers or {}
Sync.lastAnnounced = Sync.lastAnnounced or {}
Sync.reqInflight = Sync.reqInflight or {}
Sync.sentInflight = Sync.sentInflight or {}
Sync.announceAllPending = false

local function EnsureGuildRootByUID(guildUID)
	if not guildUID or guildUID == "" then
		return nil
	end
	local db = EnsureDB()
	db.guilds = db.guilds or {}
	local g = db.guilds[guildUID]
	if not g then
		g = { guildInfo = { guildUID = guildUID }, players = {} }
		db.guilds[guildUID] = g
	end
	g.guildInfo = g.guildInfo or { guildUID = guildUID }
	g.players = g.players or {}
	g.guildShared = g.guildShared or {}
	g.guildShared.guildMemberPrefs = g.guildShared.guildMemberPrefs or {}
	return g
end

local function EnsureProgressRootCompat(guildUID)
	if DB and DB.EnsureGuildProgress then
		local ok, progress = pcall(DB.EnsureGuildProgress, DB, guildUID)
		if ok and type(progress) == "table" then
			return progress
		end
	end
	local g = EnsureGuildRootByUID(guildUID)
	if not g then
		return nil
	end
	g.guildShared = g.guildShared or {}
	if type(g.guildShared.guildProgress) ~= "table" then
		local schema = (ns.GuildProgress and ns.GuildProgress.Config and ns.GuildProgress.Config.schema) or 1
		g.guildShared.guildProgress = { schema = schema, groups = {}, updatedAt = 0 }
	end
	g.guildShared.guildProgress.groups = g.guildShared.guildProgress.groups or {}
	return g.guildShared.guildProgress
end

function Sync.MakeKey(typeKey, id)
	return tostring(typeKey or "") .. "|" .. tostring(id or "")
end

function Sync.ReqKey(sender, typeKey, id)
	return tostring(NormalizePeerName(sender) or "") .. "|" .. Sync.MakeKey(typeKey, id)
end

function Sync.ShouldSendRequest(sender, typeKey, id)
	local key = Sync.ReqKey(sender, typeKey, id)
	local now = Now()
	local last = Sync.reqInflight[key]
	if last and (now - last) < Sync.REQ_TTL then
		return false
	end
	Sync.reqInflight[key] = now
	return true
end

function Sync.ShouldSendPayload(sender, typeKey, id, ts, routeKey)
	local peerKey = routeKey
	if peerKey == nil or peerKey == "" then
		peerKey = NormalizePeerName(sender)
	end
	local key = tostring(peerKey or "") .. "|" .. Sync.MakeKey(typeKey, id) .. ":" .. tostring(ts or "")
	local now = Now()
	local last = Sync.sentInflight[key]
	if last and (now - last) < Sync.SENT_TTL then
		return false
	end
	Sync.sentInflight[key] = now
	return true
end

function Sync.ShouldAnnounce(typeKey, id, ts)
	local key = Sync.MakeKey(typeKey, id)
	local now = Now()
	local last = Sync.lastAnnounced[key]
	if last and last.ts == ts and (now - last.at) < Sync.ANN_TTL then
		return false
	end
	Sync.lastAnnounced[key] = { ts = ts, at = now }
	return true
end

function Sync.RegisterType(typeKey, handler)
	if not typeKey or typeKey == "" or type(handler) ~= "table" then
		return
	end
	Sync.handlers[typeKey] = handler
end

function Sync.SendAnnounce(guildUID, typeKey, id, ts)
	if not Sync.ENABLED then
		return
	end
	if not HasOtherOnlineGuildMember() then
		return
	end
	if not guildUID or guildUID == "" or not typeKey or typeKey == "" or not id then
		return
	end
	local fixedTs = NormalizeUpdatedAt(ts, true)
	if not Sync.ShouldAnnounce(typeKey, id, fixedTs) then
		return
	end
	local line =
		table.concat({ "EANN", Sync.VER, tostring(guildUID), tostring(typeKey), tostring(id), tostring(fixedTs) }, ";")
	QueueAddon(line, "GUILD")
end

function Sync.SendRequest(target, guildUID, typeKey, id)
	if not Sync.ENABLED then
		return
	end
	if target and target ~= "" and HasDBMismatch(target) then
		return
	end
	if not target or target == "" or not guildUID or guildUID == "" or not typeKey or typeKey == "" or not id then
		return
	end
	if not Sync.ShouldSendRequest(target, typeKey, id) then
		return
	end
	local line = table.concat({ "EREQ", Sync.VER, tostring(guildUID), tostring(typeKey), tostring(id) }, ";")
	QueueAddon(line, "WHISPER", target)
end

function Sync.SendPayload(target, guildUID, typeKey, id, ts, data, deleted)
	if not Sync.ENABLED then
		return
	end
	if target and target ~= "" and HasDBMismatch(target) then
		return
	end
	if not target or target == "" or not guildUID or guildUID == "" or not typeKey or typeKey == "" or not id then
		return
	end
	local fixedTs = NormalizeUpdatedAt(ts, true)
	local sendChannel = "WHISPER"
	local sendTarget = target
	local routeKey = NormalizePeerName(target)
	if typeKey == "news" then
		sendChannel = "GUILD"
		sendTarget = nil
		routeKey = "GUILD"
	end
	if not Sync.ShouldSendPayload(target, typeKey, id, fixedTs, routeKey) then
		return
	end
	local isDeleted = (deleted == true) or (type(data) == "table" and data.deleted == true)
	local kv = {
		t = tostring(typeKey),
		id = tostring(id),
		ts = fixedTs,
		data = data,
		deleted = isDeleted or nil,
	}
	local enc = PackNewsPayloadRaw(guildUID, kv)
	SendBigMessage("EPAY", guildUID, enc, sendChannel, sendTarget)
end

function Sync.AnnounceElement(guildUID, typeKey, id, ts)
	Sync.SendAnnounce(guildUID, typeKey, id, ts)
end

function Sync.AnnounceAll(guildUID, opts)
	if not Sync.ENABLED then
		return
	end
	if not HasOtherOnlineGuildMember() then
		return
	end
	local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID())
	if not gid then
		return
	end
	if Sync.announceAllPending then
		return
	end
	Sync.announceAllPending = true

	local onlyType = opts and opts.type
	local onlyTypes = opts and opts.types
	local batch = (opts and opts.batchSize) or Sync.ANN_BATCH
	local tick = (opts and opts.tick) or Sync.ANN_TICK
	local window = tonumber((opts and opts.window) or Sync.ANN_WINDOW) or 30
	if window < 0 then
		window = 0
	end
	local items = {}

	for typeKey, handler in pairs(Sync.handlers) do
		if (not onlyType or typeKey == onlyType) and (not onlyTypes or onlyTypes[typeKey] == true) then
			if handler and handler.list then
				local ok, list = pcall(handler.list, gid)
				if ok and type(list) == "table" then
					for i = 1, #list do
						local it = list[i]
						if it and it.id then
							items[#items + 1] = { typeKey = typeKey, id = it.id, ts = it.ts }
						end
					end
				end
			end
		end
	end

	if #items == 0 then
		Sync.announceAllPending = false
		return
	end

	local me = LocalFullName()
	table.sort(items, function(a, b)
		local ha = FNV1a32(tostring(me) .. "|" .. tostring(a.typeKey) .. "|" .. tostring(a.id))
		local hb = FNV1a32(tostring(me) .. "|" .. tostring(b.typeKey) .. "|" .. tostring(b.id))
		if ha == hb then
			return tostring(a.id) < tostring(b.id)
		end
		return ha < hb
	end)

	local total = #items
	local sent = 0
	local t0 = (GetTime and GetTime()) or 0
	local perTick = math.max(1, tonumber(batch) or 1)
	local dt = math.max(0.05, tonumber(tick) or 0.2)
	local function Pump()
		local now = (GetTime and GetTime()) or 0
		local elapsed = math.max(0, now - t0)
		local target = total
		if window > 0 then
			target = math.min(total, math.floor((elapsed / window) * total) + 1)
		end
		local guard = 0
		while sent < target and guard < perTick do
			sent = sent + 1
			guard = guard + 1
			local it = items[sent]
			if it then
				Sync.SendAnnounce(gid, it.typeKey, it.id, it.ts)
			end
		end
		if sent >= total then
			Sync.announceAllPending = false
			return
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(dt, Pump)
		else
			for i = sent + 1, total do
				local it = items[i]
				if it then
					Sync.SendAnnounce(gid, it.typeKey, it.id, it.ts)
				end
			end
			Sync.announceAllPending = false
		end
	end
	Pump()
end

-- ===== Handlers par type =====
function Sync.News_List(guildUID)
	local out = {}
	local g = EnsureGuildRootByUID(guildUID)
	local items = g and g.news and g.news.items or nil
	if type(items) ~= "table" then
		return out
	end

	for i = 1, #items do
		local n = items[i]
		if n and n.id then
			local ts = tonumber(n.ts or 0) or 0
			if ts <= 0 then
				ts = Now()
				n.ts = ts
			end
			out[#out + 1] = { id = n.id, ts = ts }
		end
	end

	local deleted = g and g.newsDeleted or nil
	if type(deleted) == "table" then
		local cutoff = Now() - Sync.NEWSDEL_TTL
		for id, ts in pairs(deleted) do
			local dts = tonumber(ts or 0) or 0
			if dts > 0 then
				if dts < cutoff then
					deleted[id] = nil
				else
					out[#out + 1] = { id = id, ts = dts }
				end
			else
				deleted[id] = nil
			end
		end
	end
	return out
end

function Sync.News_Get(guildUID, id)
	local g = EnsureGuildRootByUID(guildUID)
	local items = g and g.news and g.news.items or nil
	if type(items) == "table" then
		for i = 1, #items do
			local n = items[i]
			if n and n.id == id then
				local ts = tonumber(n.ts or 0) or 0
				if ts <= 0 then
					ts = Now()
					n.ts = ts
				end
				return ts,
					{
						id = n.id,
						text = n.text,
						type = n.type,
						title = n.title,
						icon = n.icon,
						ts = ts,
						replaceKey = n.replaceKey,
						removedAt = n.removedAt,
						points = n.points,
						uid = n.uid,
					}
			end
		end
	end
	if g and g.newsDeleted and g.newsDeleted[id] then
		local ts = tonumber(g.newsDeleted[id] or 0) or 0
		if ts > 0 then
			return ts, { id = id, deleted = true }
		end
	end
	return nil
end

function Sync.News_Apply(guildUID, id, data, ts, sender)
	if not data then
		return
	end
	if not id or id == "" then
		return
	end
	if data.deleted then
		local g = EnsureGuildRootByUID(guildUID)
		if g then
			g.newsDeleted = g.newsDeleted or {}
			local dts = NormalizeUpdatedAt(ts, true)
			g.newsDeleted[id] = dts
		end
		if ns and ns.Data and ns.Data.Journalist and ns.Data.Journalist.RemoveNewsById then
			ns.Data.Journalist.RemoveNewsById(guildUID, id)
		end
		return
	end
	local payload = {
		text = data.text,
		type = data.type,
		icon = data.icon,
		ts = ts or data.ts,
		replaceKey = data.replaceKey,
		noBroadcast = true,
		id = id,
		title = data.title,
		removedAt = data.removedAt,
		points = data.points,
		uid = data.uid,
		replaceable = data.replaceable,
	}
	if ns and ns.Data and ns.Data.Journalist and ns.Data.Journalist.AddRemoteNewsPayload then
		ns.Data.Journalist.AddRemoteNewsPayload(payload, guildUID)
	elseif ns and ns.Data and ns.Data.Journalist and ns.Data.Journalist.AddRawNews then
		local g = EnsureGuildRootByUID(guildUID)
		if g then
			ns.Data.Journalist.AddRawNews(g, payload)
		end
	end
	local g = EnsureGuildRootByUID(guildUID)
	if g and g.newsDeleted then
		g.newsDeleted[id] = nil
	end
end

function Sync.Prefs_List(guildUID)
	local out = {}
	local g = EnsureGuildRootByUID(guildUID)
	local prefsMap = g and g.guildShared and g.guildShared.guildMemberPrefs or nil
	if type(prefsMap) ~= "table" then
		return out
	end
	for uid, prefs in pairs(prefsMap) do
		if type(prefs) == "table" then
			local ts = tonumber(prefs.updatedAt or 0) or 0
			if ts <= 0 then
				ts = Now()
				prefs.updatedAt = ts
			end
			out[#out + 1] = { id = uid, ts = ts }
		end
	end
	return out
end

function Sync.Prefs_Get(guildUID, uid)
	local g = EnsureGuildRootByUID(guildUID)
	local prefs = g and g.guildShared and g.guildShared.guildMemberPrefs and g.guildShared.guildMemberPrefs[uid] or nil
	if type(prefs) ~= "table" then
		return nil
	end
	local ts = tonumber(prefs.updatedAt or 0) or 0
	if ts <= 0 then
		ts = Now()
		prefs.updatedAt = ts
	end
	local out = { updatedAt = ts }
	if prefs.emotesEnabled ~= nil then
		out.emotesEnabled = prefs.emotesEnabled
	end
	if prefs.emotesSound ~= nil then
		out.emotesSound = prefs.emotesSound
	end
	if prefs.raidLeader ~= nil then
		out.raidLeader = prefs.raidLeader and true or false
	end
	if prefs.epic ~= nil then
		out.epic = prefs.epic
	end
	if type(prefs.biographie) == "table" then
		local bio = {}
		for k, v in pairs(prefs.biographie) do
			if type(v) == "table" then
				local copy = {}
				for bk, bv in pairs(v) do
					copy[bk] = bv
				end
				bio[k] = copy
			else
				bio[k] = v
			end
		end
		out.biographie = bio
	end
	return ts, out
end

function Sync.Prefs_Apply(guildUID, uid, data, ts, sender)
	if type(data) ~= "table" then
		return
	end
	if not uid or uid == "" then
		return
	end
	data.updatedAt = NormalizeUpdatedAt(ts or data.updatedAt, true)
	local prefs = NormalizePrefs and NormalizePrefs(data) or data
	if not prefs then
		return
	end
	prefs = ApplyEpicVisibilityPolicy and ApplyEpicVisibilityPolicy(prefs) or prefs
	if DB and DB.UpsertGuildMemberPrefs then
		DB:UpsertGuildMemberPrefs(guildUID, uid, prefs, false)
	end
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_MEMBER_PREFS_RECEIVED", guildUID, uid, prefs, sender)
	end
	if ns and ns.Sections and ns.Sections.HerosFrame and ns.Sections.HerosFrame.Refresh then
		ns.Sections.HerosFrame.Refresh()
	end
end

function Sync.Roster_PlayerUpdatedAt(p)
	if type(p) ~= "table" then
		return 0
	end
	local ts = tonumber(p.updatedAt or 0) or 0
	local chars = p.characters
	if type(chars) == "table" then
		for _, c in pairs(chars) do
			local cts = tonumber(c and c.updatedAt or 0) or 0
			if cts > ts then
				ts = cts
			end
		end
	end
	if ts <= 0 and type(chars) == "table" and next(chars) ~= nil then
		ts = Now()
		p.updatedAt = ts
	end
	return ts
end

function Sync.Roster_List(guildUID)
	local out = {}
	local g = EnsureGuildRootByUID(guildUID)
	local players = g and g.players or nil
	if type(players) ~= "table" then
		return out
	end
	for uid, p in pairs(players) do
		if type(p) == "table" then
			local ts = Sync.Roster_PlayerUpdatedAt(p)
			if ts > 0 then
				out[#out + 1] = { id = uid, ts = ts }
			end
		end
	end
	return out
end

function Sync.Roster_Get(guildUID, uid)
	local g = EnsureGuildRootByUID(guildUID)
	local p = g and g.players and g.players[uid] or nil
	if type(p) ~= "table" then
		return nil
	end
	local ts = Sync.Roster_PlayerUpdatedAt(p)
	local out = { mainFull = p.mainFull or "", updatedAt = ts, characters = {} }
	local chars = p.characters
	if type(chars) == "table" then
		for full, c in pairs(chars) do
			if type(c) == "table" then
				out.characters[full] = {
					full = c.full or full,
					name = c.name or "",
					realm = c.realm or "",
					classLoc = c.classLoc or "",
					classTag = c.classTag or "",
					spec = c.spec or "",
					specID = tonumber(c.specID or 0) or 0,
					level = tonumber(c.level or 0) or 0,
					ilevel = tonumber(c.ilevel or 0) or 0,
					mplus = tonumber(c.mplus or 0) or 0,
					achv = tonumber(c.achv or 0) or 0,
					isMain = c.isMain and true or false,
					playerGUID = c.playerGUID or "",
					updatedAt = tonumber(c.updatedAt or 0) or 0,
				}
			end
		end
	end
	return ts, out
end

function Sync.Roster_Apply(guildUID, uid, data, ts, sender)
	if type(data) ~= "table" then
		return
	end
	if not uid or uid == "" then
		return
	end
	local g = EnsureGuildRootByUID(guildUID)
	if not g then
		return
	end
	local out =
		{ mainFull = data.mainFull or "", updatedAt = NormalizeUpdatedAt(ts or data.updatedAt, true), characters = {} }
	if type(data.characters) == "table" then
		for full, c in pairs(data.characters) do
			if type(c) == "table" then
				out.characters[full] = {
					full = c.full or full,
					name = c.name or "",
					realm = c.realm or "",
					classLoc = c.classLoc or "",
					classTag = c.classTag or "",
					spec = c.spec or "",
					specID = tonumber(c.specID or 0) or 0,
					level = tonumber(c.level or 0) or 0,
					ilevel = tonumber(c.ilevel or 0) or 0,
					mplus = tonumber(c.mplus or 0) or 0,
					achv = tonumber(c.achv or 0) or 0,
					isMain = c.isMain and true or false,
					playerGUID = c.playerGUID or "",
					updatedAt = tonumber(c.updatedAt or 0) or 0,
				}
			end
		end
	end
	if out.mainFull ~= "" and out.characters[out.mainFull] then
		for full, c in pairs(out.characters) do
			c.isMain = (full == out.mainFull)
		end
	end
	g.players[uid] = out
	g.guildInfo = g.guildInfo or {}
	g.guildInfo.updatedAt = math.max(tonumber(g.guildInfo.updatedAt or 0) or 0, out.updatedAt or 0)
	if DB and DB.DedupCharactersByPlayerGUID then
		DB:DedupCharactersByPlayerGUID(guildUID)
	end
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_GUILD_ROSTER_UPDATED")
	end
	if ns and ns.Sections and ns.Sections.HerosFrame and ns.Sections.HerosFrame.Refresh then
		ns.Sections.HerosFrame.Refresh()
	end
end

function Sync.Progress_List(guildUID)
	local out = {}
	local progress = EnsureProgressRootCompat(guildUID)
	if not progress or type(progress.groups) ~= "table" then
		return out
	end
	local byUID = {}
	for _, group in pairs(progress.groups) do
		if type(group) == "table" and type(group.byUID) == "table" then
			for uid, entry in pairs(group.byUID) do
				if type(entry) == "table" then
					local ts = tonumber(entry.updatedAt or 0) or 0
					if ts <= 0 and (entry.pointsEnc or entry.points or entry.events) then
						ts = Now()
						entry.updatedAt = ts
					end
					local cur = byUID[uid] or 0
					if ts > cur then
						byUID[uid] = ts
					end
				end
			end
		end
	end
	for uid, ts in pairs(byUID) do
		out[#out + 1] = { id = uid, ts = ts }
	end
	return out
end

function Sync.Progress_Get(guildUID, uid)
	local progress = EnsureProgressRootCompat(guildUID)
	if not progress or type(progress.groups) ~= "table" then
		return nil
	end
	local maxTs = 0
	local groupsOut = {}
	for groupKey, group in pairs(progress.groups) do
		if type(group) == "table" and type(group.byUID) == "table" then
			local entry = group.byUID[uid]
			if type(entry) == "table" then
				local ts = tonumber(entry.updatedAt or 0) or 0
				if ts <= 0 and (entry.pointsEnc or entry.points or entry.events) then
					ts = Now()
					entry.updatedAt = ts
				end
				if ts > maxTs then
					maxTs = ts
				end
				local out = { updatedAt = ts, events = tonumber(entry.events or 0) or 0 }
				if entry.pointsEnc ~= nil then
					out.pointsEnc = entry.pointsEnc
				else
					out.points = tonumber(entry.points or 0) or 0
				end
				groupsOut[groupKey] = out
			end
		end
	end
	if not next(groupsOut) then
		return nil
	end
	return maxTs, { updatedAt = maxTs, groups = groupsOut }
end

function Sync.Progress_Apply(guildUID, uid, data, ts, sender)
	if type(data) ~= "table" or type(data.groups) ~= "table" then
		return
	end
	if not uid or uid == "" then
		return
	end
	local progress = EnsureProgressRootCompat(guildUID)
	if not progress then
		return
	end
	progress.groups = progress.groups or {}

	-- retire les entrées du UID qui ne sont plus présentes
	for groupKey, group in pairs(progress.groups) do
		if type(group) == "table" and type(group.byUID) == "table" then
			if data.groups[groupKey] == nil and group.byUID[uid] ~= nil then
				group.byUID[uid] = nil
				group.updatedAt = math.max(tonumber(group.updatedAt or 0) or 0, NormalizeUpdatedAt(ts, true))
			end
		end
	end

	for groupKey, entry in pairs(data.groups) do
		if type(entry) == "table" then
			local group = progress.groups[groupKey] or { byUID = {}, updatedAt = 0 }
			group.byUID = group.byUID or {}
			local out = { events = tonumber(entry.events or 0) or 0 }
			local eTs = NormalizeUpdatedAt(entry.updatedAt or ts, true)
			out.updatedAt = eTs
			if entry.pointsEnc ~= nil then
				out.pointsEnc = entry.pointsEnc
				out.points = nil
			else
				local pts = tonumber(entry.points or 0) or 0
				if DB and DB.EncodeGuildProgressPoints then
					out.pointsEnc = DB:EncodeGuildProgressPoints(guildUID, uid, groupKey, pts)
					out.points = nil
				else
					out.points = pts
				end
			end
			group.byUID[uid] = out
			group.updatedAt = math.max(tonumber(group.updatedAt or 0) or 0, eTs)
			progress.groups[groupKey] = group
		end
	end

	progress.updatedAt = math.max(tonumber(progress.updatedAt or 0) or 0, NormalizeUpdatedAt(ts, false))
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_GUILD_PROGRESS_UPDATED", guildUID)
	end
end

function Sync.Rosteur_List(guildUID)
	local out = {}
	local g = EnsureGuildRootByUID(guildUID)
	if not g or type(g.guildShared) ~= "table" or type(g.guildShared.rosteur) ~= "table" then
		return out
	end
	local r = g.guildShared.rosteur
	local ts = tonumber(r.updatedAt or 0) or 0
	if ts <= 0 then
		ts = Now()
		r.updatedAt = ts
	end
	out[#out + 1] = { id = "state", ts = ts }
	return out
end

function Sync.Rosteur_Get(guildUID, id)
	local g = EnsureGuildRootByUID(guildUID)
	if not g or type(g.guildShared) ~= "table" or type(g.guildShared.rosteur) ~= "table" then
		return nil
	end
	local r = g.guildShared.rosteur
	local ts = tonumber(r.updatedAt or 0) or 0
	if ts <= 0 then
		ts = Now()
		r.updatedAt = ts
	end
	if ns and ns.Rosteur and ns.Rosteur.NormalizeState then
		return ts, ns.Rosteur.NormalizeState(r)
	end
	return ts, r
end

function Sync.Rosteur_Apply(guildUID, id, data, ts, sender)
	if type(data) ~= "table" then
		return
	end
	if ns and ns.Rosteur and ns.Rosteur.ApplyRemote then
		ns.Rosteur.ApplyRemote(guildUID, data, ts, sender)
		return
	end
	local g = EnsureGuildRootByUID(guildUID)
	if not g then
		return
	end
	g.guildShared = g.guildShared or {}
	g.guildShared.rosteur = data
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_ROSTEUR_UPDATED", guildUID, data, sender)
	end
end

function Sync.GuildInfo_List(guildUID)
	local out = {}
	local g = EnsureGuildRootByUID(guildUID)
	if not g or type(g.guildInfo) ~= "table" then
		return out
	end
	local ts = tonumber(g.guildInfo.updatedAt or 0) or 0
	if ts <= 0 then
		ts = Now()
		g.guildInfo.updatedAt = ts
	end
	out[#out + 1] = { id = "guildinfo", ts = ts }
	return out
end

function Sync.GuildInfo_Get(guildUID, id)
	local g = EnsureGuildRootByUID(guildUID)
	if not g or type(g.guildInfo) ~= "table" then
		return nil
	end
	local ts = tonumber(g.guildInfo.updatedAt or 0) or 0
	if ts <= 0 then
		ts = Now()
		g.guildInfo.updatedAt = ts
	end
	local info = {}
	for k, v in pairs(g.guildInfo) do
		info[k] = v
	end
	info.updatedAt = ts
	return ts, info
end

function Sync.GuildInfo_Apply(guildUID, id, data, ts, sender)
	if type(data) ~= "table" then
		return
	end
	local g = EnsureGuildRootByUID(guildUID)
	if not g then
		return
	end
	local out = {}
	for k, v in pairs(data) do
		out[k] = v
	end
	out.guildUID = guildUID
	out.updatedAt = NormalizeUpdatedAt(ts or data.updatedAt, true)
	g.guildInfo = out
end

function Sync.Featured_List(guildUID)
	local out = {}
	local root = EnsureFeaturedRoot(guildUID)
	local store = root and root.byKey or nil
	if type(store) ~= "table" and (not root or type(root.meta) ~= "table") then
		return out
	end
	local seen = {}
	local meta = root and root.meta or nil
	if type(meta) == "table" then
		for key, m in pairs(meta) do
			local ts = tonumber((type(m) == "table" and m.ts) or 0) or 0
			if ts > 0 and type(m) == "table" and m.clear == true then
				seen[key] = true
				out[#out + 1] = { id = key, ts = ts }
			end
		end
	end
	for key, v in pairs(store) do
		if type(v) == "table" then
			local ts = FeaturedUpdatedAt(v)
			if ts <= 0 then
				ts = Now()
				v.updatedAt = ts
			end
			if type(meta) == "table" then
				meta[key] = { ts = ts, clear = false }
			end
			if not seen[key] then
				out[#out + 1] = { id = key, ts = ts }
				seen[key] = true
			end
		end
	end
	return out
end

function Sync.Featured_Get(guildUID, heroKey)
	local root = EnsureFeaturedRoot(guildUID)
	local store = root and root.byKey or nil
	local v = store and store[heroKey] or nil
	if type(v) == "table" then
		local ts = FeaturedUpdatedAt(v)
		if ts <= 0 then
			ts = Now()
			v.updatedAt = ts
		end
		local out = {}
		for k, val in pairs(v) do
			out[k] = val
		end
		out.updatedAt = ts
		return ts, out
	end
	local meta = root and root.meta or nil
	if type(meta) == "table" then
		local m = meta[heroKey]
		if type(m) == "table" and m.clear == true then
			local ts = tonumber(m.ts or 0) or 0
			if ts > 0 then
				return ts, { clear = true, updatedAt = ts }
			end
		end
	end
	return nil
end

function Sync.Featured_Apply(guildUID, heroKey, data, ts, sender)
	if type(data) ~= "table" then
		return
	end
	if not heroKey or heroKey == "" then
		return
	end
	if data.clear then
		ApplyFeaturedUpdate(guildUID, heroKey, { clear = true, updatedAt = NormalizeUpdatedAt(ts, true) }, false)
		if DB and DB.UpsertLegendaryProud then
			DB:UpsertLegendaryProud(guildUID, heroKey, { updatedAt = ts }, true, false)
		end
		return
	end
	data.updatedAt = NormalizeUpdatedAt(ts or data.updatedAt, true)
	ApplyFeaturedUpdate(guildUID, heroKey, data, false)
	if DB and DB.UpsertLegendaryProud then
		DB:UpsertLegendaryProud(guildUID, heroKey, data, false, false)
	end
end

function Sync.Proud_SplitId(id)
	if type(id) ~= "string" then
		return nil, nil
	end
	local newsId, actorKey = id:match("^(.-)|(.+)$")
	if newsId and actorKey then
		return newsId, actorKey
	end
	return nil, nil
end

function Sync.Proud_List(guildUID)
	local out = {}
	local root = EnsureProudRoot(guildUID)
	if not root then
		return out
	end
	root.proudByCharacterMeta = root.proudByCharacterMeta or {}
	local meta = root.proudByCharacterMeta
	local seen = {}

	for newsId, by in pairs(meta) do
		if type(by) == "table" then
			for actorKey, ts in pairs(by) do
				local dts = tonumber(ts or 0) or 0
				if dts > 0 then
					local id = tostring(newsId) .. "|" .. tostring(actorKey)
					seen[id] = true
					out[#out + 1] = { id = id, ts = dts }
				end
			end
		end
	end

	for newsId, by in pairs(root.proudByCharacter or {}) do
		if type(by) == "table" then
			meta[newsId] = meta[newsId] or {}
			for actorKey, v in pairs(by) do
				local ts = tonumber((type(v) == "table" and v.updatedAt) or 0) or 0
				if ts <= 0 then
					ts = tonumber(meta[newsId][actorKey] or 0) or 0
				end
				if ts <= 0 then
					ts = Now()
				end
				meta[newsId][actorKey] = ts
				local id = tostring(newsId) .. "|" .. tostring(actorKey)
				if not seen[id] then
					seen[id] = true
					out[#out + 1] = { id = id, ts = ts }
				end
			end
		end
	end
	return out
end

function Sync.Proud_Get(guildUID, id)
	local newsId, actorKey = Sync.Proud_SplitId(id)
	if not newsId or not actorKey then
		return nil
	end
	local root = EnsureProudRoot(guildUID)
	if not root then
		return nil
	end
	root.proudByCharacterMeta = root.proudByCharacterMeta or {}
	local meta = root.proudByCharacterMeta
	local ts = tonumber((meta[newsId] and meta[newsId][actorKey]) or 0) or 0
	local by = root.proudByCharacter and root.proudByCharacter[newsId] or nil
	local entry = by and by[actorKey] or nil
	local proud = entry ~= nil
	if ts <= 0 and proud then
		ts = Now()
		meta[newsId] = meta[newsId] or {}
		meta[newsId][actorKey] = ts
	end
	if ts <= 0 then
		return nil
	end
	local actorName = nil
	if type(entry) == "table" and entry.name then
		actorName = entry.name
	elseif not actorKey:match("^uid:") then
		actorName = actorKey
	end
	return ts,
		{
			newsId = newsId,
			actorKey = actorKey,
			actorName = actorName,
			actorUID = actorKey:match("^uid:") and actorKey or nil,
			proud = proud,
		}
end

function Sync.Proud_Apply(guildUID, id, data, ts, sender)
	if type(data) ~= "table" then
		return
	end
	local newsId = data.newsId or (data.id and tostring(data.id)) or nil
	local actorKey = data.actorKey
	if not newsId or not actorKey then
		local nId, aKey = Sync.Proud_SplitId(id)
		newsId = newsId or nId
		actorKey = actorKey or aKey
	end
	local actorUID = data.actorUID
	local actorName = data.actorName or actorKey or sender
	local proud = data.proud == true
	if not newsId or not actorName then
		return
	end
	ApplyProudUpdate(newsId, actorName, proud, actorUID, guildUID, ts)
end

-- Enregistrement des types
Sync.RegisterType("news", { list = Sync.News_List, get = Sync.News_Get, apply = Sync.News_Apply })
Sync.RegisterType("prefs", { list = Sync.Prefs_List, get = Sync.Prefs_Get, apply = Sync.Prefs_Apply })
Sync.RegisterType("roster", { list = Sync.Roster_List, get = Sync.Roster_Get, apply = Sync.Roster_Apply })
Sync.RegisterType("rosteur", { list = Sync.Rosteur_List, get = Sync.Rosteur_Get, apply = Sync.Rosteur_Apply })
Sync.RegisterType("progress", { list = Sync.Progress_List, get = Sync.Progress_Get, apply = Sync.Progress_Apply })
Sync.RegisterType("guildinfo", { list = Sync.GuildInfo_List, get = Sync.GuildInfo_Get, apply = Sync.GuildInfo_Apply })
Sync.RegisterType("featured", { list = Sync.Featured_List, get = Sync.Featured_Get, apply = Sync.Featured_Apply })
Sync.RegisterType("proud", { list = Sync.Proud_List, get = Sync.Proud_Get, apply = Sync.Proud_Apply })

-- ===== Réception =====

function Sync.ApplyPayload(sender, guildUID, kv)
	if type(kv) ~= "table" then
		return
	end
	local typeKey = kv.t or kv.type
	local id = kv.id
	if not typeKey or not id then
		return
	end
	local handler = Sync.handlers[typeKey]
	if not handler or not handler.apply then
		return
	end
	local incomingTs = NormalizeUpdatedAt(kv.ts, true)
	local localTs = nil
	if handler.get then
		local ok, ts = pcall(handler.get, guildUID, id)
		if ok then
			localTs = ts
		end
	end
	if localTs and localTs > 0 and incomingTs > 0 and incomingTs <= localTs then
		return
	end
	local payloadData = kv.data
	if kv.deleted == true then
		if type(payloadData) ~= "table" then
			payloadData = {}
		end
		payloadData.deleted = true
	end
	handler.apply(guildUID, id, payloadData, incomingTs, sender)
end

function Sync.OnAnnounce(message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	if p[1] ~= "EANN" then
		return
	end
	if p[2] ~= Sync.VER then
		return
	end
	local guildUID, typeKey, id, ts = p[3], p[4], p[5], tonumber(p[6]) or 0
	if not IsAcceptedGuildUID(guildUID) then
		return
	end
	if not typeKey or typeKey == "" or not id or id == "" then
		return
	end
	local handler = Sync.handlers[typeKey]
	if not handler or not handler.get then
		return
	end
	local localTs, localData = handler.get(guildUID, id)
	local incomingTs = NormalizeUpdatedAt(ts, false)
	if not localTs or localTs <= 0 then
		Sync.SendRequest(sender, guildUID, typeKey, id)
		return
	end
	if incomingTs <= 0 then
		if localData ~= nil then
			Sync.SendPayload(sender, guildUID, typeKey, id, localTs, localData)
		end
		return
	end
	if incomingTs > localTs then
		Sync.SendRequest(sender, guildUID, typeKey, id)
	elseif incomingTs < localTs then
		if localData ~= nil then
			-- Mode négociation: on ré-annonce seulement la version locale plus récente.
			-- Le pair demandera explicitement le payload s'il en a besoin.
			Sync.SendAnnounce(guildUID, typeKey, id, localTs)
		end
	end
end

function Sync.OnRequest(message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	if p[1] ~= "EREQ" then
		return
	end
	if p[2] ~= Sync.VER then
		return
	end
	local guildUID, typeKey, id = p[3], p[4], p[5]
	if not IsAcceptedGuildUID(guildUID) then
		return
	end
	if not typeKey or typeKey == "" or not id or id == "" then
		return
	end
	local handler = Sync.handlers[typeKey]
	if not handler or not handler.get then
		return
	end
	local localTs, localData = handler.get(guildUID, id)
	if localTs and localData ~= nil then
		Sync.SendPayload(sender, guildUID, typeKey, id, localTs, localData)
	end
end

function Sync.OnChunk(prefix, message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	if p[1] ~= "EPAY" then
		return
	end
	if p[2] ~= Sync.VER then
		return
	end
	local guildUID, msgid = p[3], p[4]
	local total = tonumber(p[5]) or 0
	local index = tonumber(p[6]) or 0
	local chunk = p[7] or ""
	if not guildUID or not msgid or total <= 0 or index <= 0 then
		return
	end
	if not IsAcceptedGuildUID(guildUID) then
		return
	end
	local box = inboxSync[msgid]
	if not box then
		box = { total = total, got = 0, guildUID = guildUID, chunks = {}, from = sender, t0 = Now() }
		inboxSync[msgid] = box
	end
	if not box.chunks[index] then
		local encChunk = B64Decode(NormalizeB64Input(chunk))
		if not encChunk or encChunk == "" or (#encChunk % 8) ~= 0 then
			inboxSync[msgid] = nil
			return
		end
		box.chunks[index] = encChunk
		box.got = box.got + 1
	end
	if box.got >= box.total then
		local enc = table.concat(box.chunks, "")
		inboxSync[msgid] = nil
		local kv = UnpackPayloadFromEnc(enc, guildUID, sender)
		if not kv then
			return
		end
		Sync.ApplyPayload(sender, guildUID, kv)
	end
end

local function OnPROUD(message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	-- "PROUD;ver;guildUID;newsId;state;from;ts;uid"
	if p[1] ~= "PROUD" then
		return
	end
	if p[2] ~= SNAP_VER then
		MarkDBMismatch(sender, "PROUD", p[2], SNAP_VER)
		Notices.VersionMismatch(sender, "PROUD", p[2], SNAP_VER)
		EmitCommsError("VERSION_MISMATCH", sender, "PROUD")
		return
	end
	ClearDBMismatch(sender)
	local guildUID, newsId, state, from = p[3], p[4], p[5], p[6]
	if not IsAcceptedGuildUID(guildUID) then
		return
	end
	local proud = (state == "1" or state == "true")
	local actor = (from and from ~= "") and from or sender
	local ts = tonumber(p[7]) or Now()
	local actorUID = p[8]
	if type(actorUID) ~= "string" or actorUID == "" or actorUID:sub(1, 4) ~= "uid:" then
		actorUID = nil
	end
	ApplyProudUpdate(newsId, actor, proud, actorUID, guildUID, ts)
	DevPrint(("PROUD reçu %s (%s)"):format(tostring(newsId), tostring(sender)))
	Notices.ReceiveProudNews(actor, newsId)
end

local function ApplyFEATPayload(kv, guildUID, sender)
	if not kv or type(kv) ~= "table" then
		return
	end
	local heroKey = tostring(kv.heroKey or "")
	if heroKey == "" then
		return
	end
	local isClear = ToBool(kv.clear) == true
	if isClear then
		ApplyFeaturedUpdate(
			guildUID,
			heroKey,
			{ clear = true, updatedAt = NormalizeUpdatedAt(kv.updatedAt, false) },
			false
		)
		if DB and DB.UpsertLegendaryProud then
			DB:UpsertLegendaryProud(guildUID, heroKey, { updatedAt = kv.updatedAt }, true, false)
		end
		if EventBus and EventBus.Emit then
			EventBus.Emit("WG_LEGENDARY_PROUD_RECEIVED", guildUID, heroKey, { clear = true }, sender)
		end
		DevPrint(("FEAT clear %s (%s)"):format(tostring(heroKey), tostring(sender)))
	else
		local news = {
			id = tostring(kv.id or ""),
			type = tostring(kv.typ or kv.type or ""):lower(),
			title = kv.title ~= nil and tostring(kv.title) or nil,
			icon = ToNumber(kv.icon, 0) or 0,
			time = ToNumber(kv.ts, 0) or 0,
			replaceKey = kv.replaceKey ~= nil and tostring(kv.replaceKey) or "",
			note = kv.note ~= nil and tostring(kv.note) or nil,
			updatedAt = NormalizeUpdatedAt(kv.updatedAt, false),
			guildUID = guildUID,
		}
		if news.time <= 0 then
			news.time = Now()
		end
		ApplyFeaturedUpdate(guildUID, heroKey, news, false)
		if DB and DB.UpsertLegendaryProud then
			DB:UpsertLegendaryProud(guildUID, heroKey, news, false, false)
		end
		if EventBus and EventBus.Emit then
			EventBus.Emit("WG_LEGENDARY_PROUD_RECEIVED", guildUID, heroKey, news, sender)
		end
		DevPrint(("FEAT reçu %s (%s)"):format(tostring(heroKey), tostring(sender)))
	end
end

local function OnFEAT(message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	-- "FEAT;ver;guildUID;b64" OU chunked "FEAT;ver;guildUID;msgid;total;index;chunk"
	if p[1] ~= "FEAT" then
		return
	end
	if p[2] ~= SNAP_VER then
		MarkDBMismatch(sender, "FEAT", p[2], SNAP_VER)
		Notices.VersionMismatch(sender, "FEAT", p[2], SNAP_VER)
		EmitCommsError("VERSION_MISMATCH", sender, "FEAT")
		return
	end
	ClearDBMismatch(sender)
	local guildUID = p[3]
	if not guildUID then
		return
	end
	if not IsAcceptedGuildUID(guildUID) then
		return
	end

	local total = tonumber(p[5] or 0) or 0
	local index = tonumber(p[6] or 0) or 0
	if total > 0 and index > 0 then
		local msgid = p[4]
		local chunk = p[7] or ""
		if not msgid or chunk == "" then
			return
		end
		local box = inboxFeat[msgid]
		if not box then
			box = { total = total, got = 0, guildUID = guildUID, chunks = {}, from = sender, t0 = Now() }
			inboxFeat[msgid] = box
		end
		if not box.chunks[index] then
			local encChunk = B64Decode(NormalizeB64Input(chunk))
			if not encChunk or encChunk == "" or (#encChunk % 8) ~= 0 then
				DevPrint(
					("FEAT bad chunk sender=%s gid=%s msgid=%s idx=%d/%d len=%d"):format(
						tostring(sender or "?"),
						tostring(guildUID),
						tostring(msgid),
						index,
						total,
						#(encChunk or "")
					)
				)
				inboxFeat[msgid] = nil
				return
			end
			box.chunks[index] = encChunk
			box.got = box.got + 1
		end
		if box.got >= box.total then
			local enc = table.concat(box.chunks, "")
			inboxFeat[msgid] = nil
			local kv = UnpackPayloadFromEnc(enc, guildUID, sender)
			if kv then
				ApplyFEATPayload(kv, guildUID, sender)
			end
		end
		return
	end

	local b64 = p[4]
	if not b64 then
		return
	end
	local kv = UnpackPayload(b64, guildUID, sender)
	if kv then
		ApplyFEATPayload(kv, guildUID, sender)
	end
end

local function OnNEWSDEL(message, channel, sender)
	if IsSelfSender(sender) then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	-- "NEWSDEL;ver;guildUID;newsId;from;ts;uid"
	if p[1] ~= "NEWSDEL" then
		return
	end
	if p[2] ~= SNAP_VER then
		MarkDBMismatch(sender, "NEWSDEL", p[2], SNAP_VER)
		Notices.VersionMismatch(sender, "NEWSDEL", p[2], SNAP_VER)
		EmitCommsError("VERSION_MISMATCH", sender, "NEWSDEL")
		return
	end
	ClearDBMismatch(sender)
	local guildUID, newsId = p[3], p[4]
	if not IsAcceptedGuildUID(guildUID) then
		return
	end
	local ts = NormalizeUpdatedAt(tonumber(p[6]) or 0, true)
	local g = EnsureGuildRootByUID(guildUID)
	if g then
		g.newsDeleted = g.newsDeleted or {}
		g.newsDeleted[newsId] = ts
	end
	local removed = false
	if ns and ns.Data and ns.Data.JournalistAPI and ns.Data.JournalistAPI.RemoveNewsById then
		removed = ns.Data.JournalistAPI.RemoveNewsById(guildUID, newsId)
	end
	if removed and EventBus and EventBus.Emit then
		EventBus.Emit("WG_NEWS_DELETE_RECEIVED", newsId, guildUID, sender)
	end
	if removed then
		DevPrint(("NEWSDEL reçu (%s) de %s"):format(tostring(newsId), tostring(sender)))
	end
	Notices.ReceiveNewsDelete(sender)
end

-- Petite API Comms pour l’envoi d’émotion
function Comms:SendEmote(target, key, context)
	SendEMO(target, key, context)
end

local function SendNEWSDEL(guildUID, newsId)
	if not HasOtherOnlineGuildMember() then
		return
	end
	local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID())
	if not gid or not newsId or newsId == "" then
		return
	end
	local from = LocalFullName()
	local uid = DB and DB.GetMyUID and DB:GetMyUID() or ""
	local ts = Now()
	local g = EnsureGuildRootByUID(gid)
	if g then
		g.newsDeleted = g.newsDeleted or {}
		g.newsDeleted[newsId] = ts
	end
	local line = table.concat(
		{ "NEWSDEL", SNAP_VER, tostring(gid), tostring(newsId), tostring(from), tostring(ts), tostring(uid) },
		";"
	)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(PREFIX, line, "GUILD")
	else
		SendAddonMessage(PREFIX, line, "GUILD")
	end
	Notices.SendNewsDeleteGuild(newsId)
end

local function SendPROUD(guildUID, newsId, proud)
	if Comms and Comms.SYNC_ENABLED and Comms.Sync and Comms.Sync.AnnounceElement then
		local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID())
		if not gid or not newsId or newsId == "" then
			return
		end
		local from = LocalFullName()
		local uid = DB and DB.GetMyUID and DB:GetMyUID() or ""
		local ts = Now()
		local actorKey = (uid and uid ~= "") and uid or from
		ApplyProudUpdate(newsId, from, proud, uid, gid, ts)
		Comms.Sync.AnnounceElement(gid, "proud", tostring(newsId) .. "|" .. tostring(actorKey), ts)
		return
	end
	if not HasOtherOnlineGuildMember() then
		return
	end
	local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID())
	if not gid or not newsId or newsId == "" then
		return
	end
	local from = LocalFullName()
	local uid = DB and DB.GetMyUID and DB:GetMyUID() or ""
	local ts = Now()
	local state = proud and "1" or "0"
	local line = table.concat(
		{ "PROUD", SNAP_VER, tostring(gid), tostring(newsId), state, tostring(from), tostring(ts), tostring(uid) },
		";"
	)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(PREFIX, line, "GUILD")
	else
		SendAddonMessage(PREFIX, line, "GUILD")
	end
	Notices.SendProudNewsGuild(newsId)
end

function Comms:SendNewsProud(newsId, guildUIDOverride, proud)
	SendPROUD(guildUIDOverride, newsId, proud)
end

function Comms:SendProud(newsId, proud, guildUIDOverride)
	SendPROUD(guildUIDOverride, newsId, proud)
end

local function SendFEAT(guildUID, heroKey, news, clear)
	if not guildUID or guildUID == "" or not heroKey or heroKey == "" then
		return
	end
	if Comms and Comms.SYNC_ENABLED and Comms.Sync and Comms.Sync.AnnounceElement then
		local ts = Now()
		if clear then
			ApplyFeaturedUpdate(guildUID, heroKey, { clear = true, updatedAt = ts }, false)
		elseif news then
			news.updatedAt = NormalizeUpdatedAt(news.updatedAt or ts, true)
		end
		Comms.Sync.AnnounceElement(guildUID, "featured", heroKey, news and news.updatedAt or ts)
		return
	end
	if not HasOtherOnlineGuildMember() then
		return
	end
	local kv = { heroKey = heroKey }
	if clear then
		kv.clear = true
	else
		if not news then
			return
		end
		kv.id = news.id or ""
		kv.typ = news.type or ""
		kv.title = news.title or ""
		kv.icon = tonumber(news.icon or 0) or 0
		kv.ts = tonumber(news.time or 0) or 0
		kv.replaceKey = news.replaceKey or ""
		kv.note = news.note or ""
		kv.updatedAt = tonumber(news.updatedAt or 0) or 0
	end
	local payload = PackNewsPayload(guildUID, kv)
	local line = table.concat({ "FEAT", SNAP_VER, tostring(guildUID), payload }, ";")
	local maxLen = GetMaxAddonLineFor("GUILD")
	local SAFE_MARGIN = 12
	local safeMaxLen = math.max(64, maxLen - SAFE_MARGIN)
	if #line > safeMaxLen then
		local enc = PackNewsPayloadRaw(guildUID, kv)
		SendBigMessage("FEAT", guildUID, enc, "GUILD")
	else
		if C_ChatInfo and C_ChatInfo.SendAddonMessage then
			C_ChatInfo.SendAddonMessage(PREFIX, line, "GUILD")
		else
			SendAddonMessage(PREFIX, line, "GUILD")
		end
	end
	Notices.SendFeaturedNewsGuild()
end

function Comms:SendFeaturedNews(guildUIDOverride, heroKey, news, clear)
	local gid = guildUIDOverride or (DB and DB.GetGuildUID and DB:GetGuildUID())
	SendFEAT(gid, heroKey, news, clear)
end

function Comms:SendNewsDelete(newsId, guildUIDOverride)
	if Comms and Comms.SYNC_ENABLED and Comms.Sync and Comms.Sync.AnnounceElement then
		local gid = guildUIDOverride or (DB and DB.GetGuildUID and DB:GetGuildUID())
		if not gid or not newsId or newsId == "" then
			return
		end
		local g = EnsureGuildRootByUID(gid)
		if g then
			g.newsDeleted = g.newsDeleted or {}
			local ts = Now()
			g.newsDeleted[newsId] = ts
			Comms.Sync.AnnounceElement(gid, "news", newsId, ts)
		end
		return
	end
	SendNEWSDEL(guildUIDOverride, newsId)
end

function Comms:SendNews(text, typ, icon, ts, replaceKey, guildUIDOverride, id, relay, origin, title, points)
	local gid = guildUIDOverride or (DB and DB.GetGuildUID and DB:GetGuildUID())
	if Comms and Comms.SYNC_ENABLED and Comms.Sync and Comms.Sync.AnnounceElement then
		if not gid or not id or id == "" then
			return
		end
		Comms.Sync.AnnounceElement(gid, "news", id, ts or Now())
		return
	end
	if not HasOtherOnlineGuildMember() then
		return
	end
	if not gid or not text or text == "" then
		return
	end
	local kv = {
		id = id or ("news:" .. Hex8(FNV1a32(tostring(text) .. tostring(ts or "") .. tostring(replaceKey or "")))),
		text = text,
		typ = typ or "generic",
		title = title,
		icon = icon or 134400,
		ts = tonumber(ts or 0) or Now(),
		replaceKey = replaceKey or "",
		relay = tonumber(relay or 0) or 0,
		origin = origin or LocalFullName(),
	}
	if DB and DB.GetMyUID then
		kv.uid = DB:GetMyUID() or ""
	end
	if points ~= nil then
		kv.points = tonumber(points or 0) or 0
	end
	local enc = PackNewsPayloadRaw(gid, kv)
	SendBigMessage("NEWS", gid, enc, "GUILD")
	Notices.SendNewsGuild()
end

function Comms:SendNewsBatch(target, guildUIDOverride)
	if Comms and Comms.SYNC_ENABLED then
		return
	end
	local gid = guildUIDOverride or (DB and DB.GetGuildUID and DB:GetGuildUID())
	if not gid then
		return
	end
	if not (ns and ns.Data and ns.Data.Journalist and ns.Data.Journalist.GetRecentNews) then
		return
	end
	local items = ns.Data.Journalist.GetRecentNews(gid, NEWS_BATCH_MAX) or {}
	if #items == 0 then
		return
	end
	local enc = PackNewsBatchPayloadRaw(gid, items)
	SendBigMessage("NEWSB", gid, enc, "WHISPER", target)
	Notices.SendNewsBatch(target, #items)
end

-- =========================
-- API publique
-- =========================
-- N’annonce qu’un digest, le SNAP complet partira seulement aux clients qui demandent.
function Comms:BroadcastSnapshot()
	if Comms and Comms.SYNC_ENABLED and Comms.Sync and Comms.Sync.AnnounceAll then
		Comms.Sync.AnnounceAll()
		return
	end
	ScheduleAnnounce(0.2)
end

-- Envoi manuel du snapshot complet à une cible précise
function Comms:SendFullSnapshotTo(target)
	local gid = DB and DB.GetGuildUID and DB:GetGuildUID()
	if not gid or not target or target == "" then
		return
	end
	local ok, enc = pcall(function()
		local enc_, sumHex = PackSnapshotEnc(gid)
		return enc_, sumHex
	end)
	if not ok or not enc then
		Notices.ErrorSnapshot(target, "pack")
		return
	end
	SendBigMessage("SNAP", gid, enc, "WHISPER", target)
	Notices.SendSnapshot(target)
end

-- =========================
-- Événements
-- =========================
local function HandleEvent(event, ...)
	if event == "PLAYER_LOGIN" then
		EnsureDBVersion()
		if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
			C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
		else
			RegisterAddonMessagePrefix(PREFIX)
		end
		if not (Comms and Comms.SYNC_ENABLED) then
			C_Timer.After(6, function()
				local gid = DB and DB.GetGuildUID and DB:GetGuildUID()
				if gid then
					SendNewsReqBurst(gid)
				end
			end)
		end
		-- Premier ANN retardé pour laisser les DB se charger
		C_Timer.After(4, function()
			local gid = DB and DB.GetGuildUID and DB:GetGuildUID()
			if Comms and Comms.SYNC_ENABLED and Comms.Sync and Comms.Sync.AnnounceAll then
				Comms.Sync.AnnounceAll(gid)
			else
				ScheduleAnnounce(0.0)
			end
		end)
	elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
		Comms._rosterReady = true
		local nowHas = HasOtherOnlineGuildMember()
		if nowHas and not Comms._hadOthers then
			Comms._hadOthers = true
			local gid = DB and DB.GetGuildUID and DB:GetGuildUID()
			if Comms and Comms.SYNC_ENABLED and Comms.Sync and Comms.Sync.AnnounceAll then
				Comms.Sync.AnnounceAll(gid)
			else
				ScheduleAnnounce(0.0)
				SendNewsReqBurst(gid)
			end
		elseif not nowHas then
			Comms._hadOthers = false
		end
		if EventBus and EventBus.Emit then
			EventBus.Emit("WG_GUILD_ROSTER_UPDATED")
		end
		DevPrint("GUILD_ROSTER_UPDATE")
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, message, channel, sender = ...
		if prefix ~= PREFIX or type(message) ~= "string" then
			return
		end
		MarkContact(sender)

		PruneInboxTables()

		local tag = message:match("^([A-Z]+);")
		if tag == "SNAP" then
			OnSnapChunk(prefix, message, channel, sender)
		elseif tag == "NEWS" then
			OnNewsChunk(prefix, message, channel, sender)
		elseif tag == "NEWSB" then
			OnNewsBatchChunk(prefix, message, channel, sender)
		elseif tag == "EPAY" then
			Sync.OnChunk(prefix, message, channel, sender)
		elseif tag == "EANN" then
			Sync.OnAnnounce(message, channel, sender)
		elseif tag == "EREQ" then
			Sync.OnRequest(message, channel, sender)
		elseif tag == "NEWSREQ" then
			local p = {}
			for s in message:gmatch("([^;]+)") do
				p[#p + 1] = s
			end
			if p[2] ~= SNAP_VER then
				MarkDBMismatch(sender, "NEWSREQ", p[2], SNAP_VER)
				Notices.VersionMismatch(sender, "NEWSREQ", p[2], SNAP_VER)
				return
			end
			ClearDBMismatch(sender)
			local guildUID = p[3]
			local nonce = p[4] or ""
			local stage = tonumber(p[5] or 0) or 0
			if not IsAcceptedGuildUID(guildUID) then
				return
			end
			if IsSelfSender(sender) then
				return
			end
			if sender ~= LocalFullName() then
				local bucket = 0
				if nonce ~= "" then
					bucket = FNV1a32(LocalFullName() .. ":" .. nonce) % NEWSREQ_BUCKETS
				end
				local rangeStart = stage * NEWSREQ_STAGE_SIZE
				local rangeEnd = rangeStart + (NEWSREQ_STAGE_SIZE - 1)
				if bucket >= rangeStart and bucket <= rangeEnd then
					local key = tostring(sender) .. ":" .. tostring(nonce)
					if not respondedNewsReq[key] then
						respondedNewsReq[key] = Now()
						local delay = 0.2 + (math.random() * 0.8)
						C_Timer.After(delay, function()
							Comms:SendNewsBatch(sender, guildUID)
						end)
						Notices.ReceiveNewsReqStage(sender, stage + 1)
					end
				end
			end
			PruneInboxTables()
		elseif tag == "ANN" or tag == "GET" then
			PruneInboxTables()
			OnLightProtocol(prefix, message, channel, sender)
		elseif tag == "PATCH" then
			PruneInboxTables()
			OnPATCH(message, channel, sender)
		elseif tag == "GPREF" then
			PruneInboxTables()
			OnGPREF(message, channel, sender)
		elseif tag == "EMO" then
			PruneInboxTables()
			OnEMO(message, channel, sender)
		elseif tag == "PROUD" then
			PruneInboxTables()
			OnPROUD(message, channel, sender)
		elseif tag == "FEAT" then
			PruneInboxTables()
			OnFEAT(message, channel, sender)
		elseif tag == "NEWSDEL" then
			PruneInboxTables()
			OnNEWSDEL(message, channel, sender)
		elseif tag == "LFG" then
			PruneInboxTables()
			if Comms.OnLFGMessage then
				Comms.OnLFGMessage(message, channel, sender)
			end
		end
	else
		-- Coalesce et annonce légère plutôt qu’un SNAP complet
		ScheduleAnnounce(1.5)
	end
end

if EventBus and EventBus.On then
	EventBus.On("PLAYER_LOGIN", HandleEvent)
	EventBus.On("CHAT_MSG_ADDON", HandleEvent)
	EventBus.On("GUILD_ROSTER_UPDATE", HandleEvent)
	EventBus.On("PLAYER_GUILD_UPDATE", HandleEvent)
	EventBus.On("PLAYER_ENTERING_WORLD", HandleEvent)
	EventBus.On("PLAYER_EQUIPMENT_CHANGED", HandleEvent)
	EventBus.On("PLAYER_AVG_ITEM_LEVEL_UPDATE", HandleEvent)
	EventBus.On("PLAYER_TALENT_UPDATE", HandleEvent)
	EventBus.On("PLAYER_SPECIALIZATION_CHANGED", HandleEvent)
	EventBus.On("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", HandleEvent)
	EventBus.On("CHALLENGE_MODE_COMPLETED", HandleEvent)
end
