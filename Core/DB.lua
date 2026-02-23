-- Core/DB.lua
local ADDON, ns = ...
ns.DB = ns.DB or {}

local DB = ns.DB

local function EnsureDB()
	WoWGuildeDB = WoWGuildeDB or {}
	return WoWGuildeDB
end

-- ==========
-- Utilitaires
-- ==========
local function Now()
	return time and time() or 0
end

local function NormRealm(r)
	return (GetNormalizedRealmName and GetNormalizedRealmName()) or r or (GetRealmName() or "UnknownRealm")
end

local function Ensure(t, k)
	t[k] = t[k] or {}
	return t[k]
end

-- "Player-1315-0A88E120" → "Player-1315"
local function ExtractPlayerBaseFromGUID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	return guid:match("^(Player%-%d+)%-.+$")
end

-- FNV-1a 32 bits, sortie hex 8
local function FNV1a32_hex(s)
	local hash = 0x811C9DC5
	for i = 1, #s do
		hash = bit.bxor(hash, s:byte(i))
		hash = (hash * 0x01000193) % 2 ^ 32
	end
	return string.format("%08x", hash)
end

local PROGRESS_SALT = "WG:gp:v1"
local function ProgressKey(guildUID, uid, groupKey)
	return FNV1a32_hex(
		PROGRESS_SALT
			.. "|"
			.. tostring(guildUID or "")
			.. "|"
			.. tostring(uid or "")
			.. "|"
			.. tostring(groupKey or "")
	)
end

local function EncodeProgressPoints(guildUID, uid, groupKey, points)
	local keyHex = ProgressKey(guildUID, uid, groupKey)
	local key = tonumber(keyHex, 16) or 0
	local raw = math.floor((tonumber(points or 0) or 0) * 100 + 0.5)
	local enc = bit.bxor(raw, key)
	local chk = FNV1a32_hex(PROGRESS_SALT .. "|" .. tostring(enc) .. "|" .. keyHex)
	return "p:" .. string.format("%x", enc) .. "|" .. chk
end

local function DecodeProgressPoints(guildUID, uid, groupKey, enc)
	if type(enc) == "number" then
		return enc, true
	end
	if type(enc) ~= "string" then
		return nil, false
	end
	if enc:sub(1, 2) ~= "p:" then
		local n = tonumber(enc)
		if n then
			return n, true
		end
		return nil, false
	end
	local payload = enc:sub(3)
	local hex, chk = payload:match("^([0-9a-fA-F]+)|([0-9a-fA-F]+)$")
	if not hex or not chk then
		return nil, false
	end
	local keyHex = ProgressKey(guildUID, uid, groupKey)
	local expected = FNV1a32_hex(PROGRESS_SALT .. "|" .. tostring(tonumber(hex, 16) or 0) .. "|" .. keyHex)
	if chk:lower() ~= expected then
		return nil, false
	end
	local key = tonumber(keyHex, 16) or 0
	local encNum = tonumber(hex, 16) or 0
	local raw = bit.bxor(encNum, key)
	return raw / 100, true
end

-- Empreinte 128 bits hex sur 2 passes salées
local PEPPER_A = "WGv1:a"
local PEPPER_B = "WGv1:b"
local function UID128_hex(s)
	local a = FNV1a32_hex(PEPPER_A .. "|" .. s)
	local b = FNV1a32_hex(PEPPER_B .. "|" .. s)
	-- Re-hash pour allonger et brasser
	local c = FNV1a32_hex(PEPPER_A .. "|" .. s .. "|" .. b)
	local d = FNV1a32_hex(PEPPER_B .. "|" .. s .. "|" .. a)
	return a .. b .. c .. d -- 32 hex chars, 128 bits
end

-- Normalisation BattleTag "Polo#1234" → "polo#1234"
local function NormalizeBattleTag(bt)
	bt = tostring(bt or "")
	bt = bt:match("^%s*(.-)%s*$")
	return bt:lower()
end

-- Récupère BattleTag du joueur local si connecté, sinon ""
local function GetMyBattleTag()
	if BNConnected and BNConnected() and BNGetInfo then
		local _, battleTag = BNGetInfo()
		return tostring(battleTag or "")
	end
	return ""
end

-- Construit un UID stable, et un UID de secours si BattleTag inconnu
-- Retourne uid, fallback_uid, used_fallback (bool)
local function BuildUserUID()
	local guid = UnitGUID("player") or ""
	local base = ExtractPlayerBaseFromGUID(guid) or "Player-0"
	local btag = NormalizeBattleTag(GetMyBattleTag())

	local fallback_seed
	if guid ~= "" then
		fallback_seed = "guid|" .. guid
	else
		local name, realm = UnitFullName("player")
		fallback_seed = "name|" .. tostring(name or "") .. "-" .. tostring(realm or "")
	end
	local fallback_uid = "uid:" .. UID128_hex(fallback_seed)
	if btag == "" then
		return fallback_uid, fallback_uid, true
	end
	local strong_uid = "uid:" .. UID128_hex("base|" .. base .. "|btag|" .. btag)
	return strong_uid, fallback_uid, false
end

function DB:GetMyUID()
	local uid, fallback_uid, used_fallback = BuildUserUID()
	return used_fallback and fallback_uid or uid
end

-- ==========
-- Racine guilde
-- ==========
local function EnsureGuildRoot(guildUID)
	local db = EnsureDB()
	db.guilds = db.guilds or {}
	local g = Ensure(db.guilds, guildUID)
	if type(g.guildInfo) ~= "table" then
		g.guildInfo = {}
	end
	g.players = g.players or {} -- clés = uid:xxxxxxxx...
	return g
end

local function EnsureGuildShared(guildUID)
	local g = EnsureGuildRoot(guildUID)
	if type(g.guildShared) ~= "table" then
		g.guildShared = {}
	end
	g.guildShared.guildMemberPrefs = g.guildShared.guildMemberPrefs or {}
	return g.guildShared
end

local function EnsureGuildProgress(guildUID)
	local shared = EnsureGuildShared(guildUID)
	if type(shared.guildProgress) ~= "table" then
		local schema = (ns.GuildProgress and ns.GuildProgress.Config and ns.GuildProgress.Config.schema) or 1
		shared.guildProgress = { schema = schema, groups = {}, updatedAt = 0 }
	end
	shared.guildProgress.groups = shared.guildProgress.groups or {}
	shared.guildProgress._guildUID = guildUID
	return shared.guildProgress
end

local BIO_GENERAL_KEY = "__general__"
local Codec = ns.Codec or {}
local EPIC_B64_PREFIX = Codec.B64_PREFIX or "b64:"
local B64Encode = Codec.B64Encode
local B64Decode = Codec.B64Decode
local Serialize = ns.Serialize or {}
local DumpEsc = Serialize.Escape
local SerializeValue = Serialize.Value
local SerializeTable = Serialize.Table
local DeserializeTable = Serialize.Deserialize or Serialize.LoadTable

local function EncodeBioField(v)
	if type(v) ~= "string" or v == "" then
		return v
	end
	if v:sub(1, #EPIC_B64_PREFIX) == EPIC_B64_PREFIX then
		return v
	end
	return EPIC_B64_PREFIX .. B64Encode(v)
end

local function DecodeBioField(v)
	if type(v) ~= "string" or v == "" then
		return v
	end
	if v:sub(1, #EPIC_B64_PREFIX) ~= EPIC_B64_PREFIX then
		return v
	end
	local raw = B64Decode(v:sub(#EPIC_B64_PREFIX + 1))
	if not raw or raw == "" then
		return v
	end
	return raw
end

local function NormalizeBioForStorage(bio)
	if type(bio) ~= "table" then
		return bio
	end
	local out = {}
	for k, v in pairs(bio) do
		out[k] = v
	end
	out.title = EncodeBioField(out.title)
	out.md = EncodeBioField(out.md)
	return out
end

local function NormalizeBioValueForStorage(v)
	if type(v) == "table" then
		return NormalizeBioForStorage(v)
	end
	if type(v) == "string" and v:sub(1, #EPIC_B64_PREFIX) == EPIC_B64_PREFIX then
		local raw = B64Decode(v:sub(#EPIC_B64_PREFIX + 1))
		local tbl = raw and DeserializeTable(raw) or nil
		if type(tbl) == "table" then
			return NormalizeBioForStorage(tbl)
		end
	end
	return v
end

local function EncodeBioFieldsInPlace(bio)
	if type(bio) ~= "table" then
		return false
	end
	local changed = false
	local titleEnc = EncodeBioField(bio.title)
	if titleEnc ~= bio.title then
		bio.title = titleEnc
		changed = true
	end
	local mdEnc = EncodeBioField(bio.md)
	if mdEnc ~= bio.md then
		bio.md = mdEnc
		changed = true
	end
	return changed
end

local function BioUpdatedAt(v)
	if type(v) == "table" then
		return tonumber(v.updatedAt or v.createdAt or 0) or 0
	end
	if type(v) == "string" then
		local decoded = DecodeBioValueForRead(v)
		if type(decoded) == "table" then
			return tonumber(decoded.updatedAt or decoded.createdAt or 0) or 0
		end
	end
	return 0
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

local function FeaturedUpdatedAt(v)
	if type(v) ~= "table" then
		return 0
	end
	return tonumber(v.updatedAt or v.ts or v.time or 0) or 0
end

local function DecodeBioForRead(bio)
	if type(bio) ~= "table" then
		return bio
	end
	local out = {}
	for k, v in pairs(bio) do
		out[k] = v
	end
	out.title = DecodeBioField(out.title)
	out.md = DecodeBioField(out.md)
	return out
end

local function DecodeBioValueForRead(v)
	if type(v) == "table" then
		return DecodeBioForRead(v)
	end
	if type(v) == "string" and v:sub(1, #EPIC_B64_PREFIX) == EPIC_B64_PREFIX then
		local raw = B64Decode(v:sub(#EPIC_B64_PREFIX + 1))
		local tbl = raw and DeserializeTable(raw) or nil
		if type(tbl) == "table" then
			return DecodeBioForRead(tbl)
		end
	end
	return v
end

local function DecodePrefsForRead(prefs)
	if type(prefs) ~= "table" then
		return prefs
	end
	local out = {}
	for k, v in pairs(prefs) do
		out[k] = v
	end
	if type(out.biographie) == "table" then
		local bio = {}
		for k, v in pairs(out.biographie) do
			bio[k] = DecodeBioValueForRead(v)
		end
		out.biographie = bio
	end
	return out
end

local function IsSelfUID(uid)
	local strong_uid, fallback_uid, used_fallback = BuildUserUID()
	if used_fallback then
		return uid == fallback_uid
	end
	return uid == strong_uid or uid == fallback_uid
end

local function ShouldDeleteOtherBioEntry(bio)
	if bio == "__DELETE__" then
		return false
	end
	local status = nil
	if type(bio) == "table" then
		status = bio.status
	elseif type(bio) == "string" and bio:sub(1, #EPIC_B64_PREFIX) == EPIC_B64_PREFIX then
		local decoded = DecodeBioValueForRead(bio)
		if type(decoded) == "table" then
			status = decoded.status
		end
	end
	return status and status ~= "published"
end

local function MigrateBiographies(guildUID, uid)
	if not guildUID or guildUID == "" or not uid or uid == "" then
		return
	end
	local gRoot = EnsureGuildRoot(guildUID)
	local shared = EnsureGuildShared(guildUID)
	local prefs = shared.guildMemberPrefs[uid] or {}
	local changed = false

	if type(prefs.biographie) ~= "table" then
		prefs.biographie = {}
	end

	if type(prefs.epic) == "table" and prefs.biographie[BIO_GENERAL_KEY] == nil then
		local normalized = NormalizeBioForStorage(prefs.epic)
		prefs.biographie[BIO_GENERAL_KEY] = normalized
		prefs.epic = nil
		changed = true
	end

	for k, v in pairs(prefs.biographie) do
		if type(v) == "table" then
			if EncodeBioFieldsInPlace(v) then
				changed = true
			end
		elseif type(v) == "string" and v:sub(1, #EPIC_B64_PREFIX) == EPIC_B64_PREFIX then
			local decoded = DecodeBioValueForRead(v)
			if type(decoded) == "table" then
				prefs.biographie[k] = NormalizeBioForStorage(decoded)
				changed = true
			end
		end
	end

	local p = gRoot.players and gRoot.players[uid] or nil
	if p and p.characters then
		for full, c in pairs(p.characters) do
			if c and type(c.bio) == "table" then
				local incoming = c.bio
				local existing = prefs.biographie[full]
				if not existing then
					prefs.biographie[full] = NormalizeBioForStorage(incoming)
					c.bio = nil
					changed = true
				else
					local inAt = tonumber(incoming.updatedAt or incoming.createdAt or 0) or 0
					local exAt = BioUpdatedAt(existing)
					if inAt > exAt then
						prefs.biographie[full] = NormalizeBioForStorage(incoming)
						c.bio = nil
						changed = true
					end
				end
			end
		end
	end

	if changed then
		prefs.updatedAt = Now()
		shared.guildMemberPrefs[uid] = prefs
	end
end

function DB:GetGuildUID()
	if C_Club and C_Club.GetGuildClubId then
		local clubId = C_Club.GetGuildClubId()
		if clubId then
			return "club:" .. tostring(clubId)
		end
	end
	return nil
end

-- ==========
-- Main via note publique « • Main »
-- ==========
local function GetMyPublicNote()
	local name, realm = UnitFullName("player")
	local myFull = name .. "-" .. (realm or GetRealmName())

	local num = GetNumGuildMembers() or 0
	for i = 1, num do
		local fullName, _, _, _, _, _, note = GetGuildRosterInfo(i)
		if fullName == myFull then
			return tostring(note or "")
		end
	end
	return ""
end
local function IsMainFromNote(note)
	note = tostring(note or ""):lower()
	note = note:gsub("%s+", " ")
	note = note:gsub("\194\160", " ") -- remplace l’insécable U+00A0 par un espace normal
	return note:find("main") ~= nil
end
-- ==========
-- Collecte perso courant
-- ==========
local function GetSpecInfoSafe()
	if GetSpecialization and GetSpecializationInfo then
		local idx = GetSpecialization()
		if idx then
			local specID, specName = GetSpecializationInfo(idx)
			return tonumber(specID or 0) or 0, tostring(specName or "")
		end
	end
	return 0, ""
end

local function GetILevelSafe()
	if GetAverageItemLevel then
		local cur = select(2, GetAverageItemLevel())
		if cur then
			return math.floor(cur + 0.5)
		end
	end
	return 0
end

local function GetMPlusSafe()
	if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
		local s = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
		if s and s.currentSeasonScore then
			return math.floor(s.currentSeasonScore + 0.5)
		end
	end
	return 0
end

local function GetAchvSafe()
	if GetTotalAchievementPoints then
		return tonumber(GetTotalAchievementPoints()) or 0
	end
	return 0
end

local function BuildSelfCharacterRecord()
	local name, realm = UnitFullName("player")
	realm = realm or NormRealm()

	local classLoc, classTag = UnitClass("player")
	local level = UnitLevel and UnitLevel("player") or 0
	local specID, specName = GetSpecInfoSafe()
	local rec = {
		full = tostring(name or "") .. "-" .. tostring(realm or ""),
		name = tostring(name or ""),
		realm = tostring(realm or ""),
		classLoc = tostring(classLoc or ""),
		classTag = tostring(classTag or ""),
		spec = tostring(specName or ""),
		specID = tonumber(specID or 0) or 0,
		level = tonumber(level or 0) or 0,
		ilevel = tonumber(GetILevelSafe() or 0) or 0,
		mplus = tonumber(GetMPlusSafe() or 0) or 0,
		achv = tonumber(GetAchvSafe() or 0) or 0,
		isMain = IsMainFromNote(GetMyPublicNote()),
		playerGUID = tostring(UnitGUID("player") or ""),
		updatedAt = Now(),
	}
	return rec
end

-- ==========
-- Modèle « guilds → players(UID) → characters »
-- ==========
local function EnsurePlayerInGuild(gRoot, uid)
	local p = gRoot.players[uid]
	if not p then
		p = { characters = {}, mainFull = "", updatedAt = Now() }
		gRoot.players[uid] = p
	end
	return p
end
-- Après EnsurePlayerInGuild(...)
local function ForceUniqueMain(p, mainFull)
	if not p then
		return
	end
	for full, c in pairs(p.characters or {}) do
		c.isMain = (full == mainFull)
	end
	p.mainFull = mainFull or ""
	p.updatedAt = Now()
end
-- Fusionne deux UID d’un même joueur dans une guilde, utile quand on passe du fallback au strong UID
local function MergePlayerUIDInGuild(gRoot, oldUID, newUID)
	if oldUID == newUID then
		return
	end
	local oldP = gRoot.players[oldUID]
	if not oldP then
		return
	end
	local newP = EnsurePlayerInGuild(gRoot, newUID)

	-- Fusion des personnages
	newP.characters = newP.characters or {}
	for full, c in pairs(oldP.characters or {}) do
		local dst = newP.characters[full]
		if not dst or (tonumber(c.updatedAt or 0) > tonumber(dst.updatedAt or 0)) then
			newP.characters[full] = c
		end
	end

	-- Main, on garde un main marqué, sinon le plus récent
	local marked = newP.mainFull
	if (not marked or marked == "") and (oldP.mainFull and oldP.mainFull ~= "") then
		newP.mainFull = oldP.mainFull
	end

	newP.updatedAt = Now()
	gRoot.players[oldUID] = nil
end

function DB:RecomputeMainInGuild(guildUID, uid)
	local gRoot = EnsureGuildRoot(guildUID)
	local p = gRoot.players[uid]
	if not p then
		return
	end

	local marked, newestFull, newestTime = nil, nil, -1
	for full, c in pairs(p.characters or {}) do
		if c.isMain then
			marked = full
		end
		local t = tonumber(c.updatedAt or 0) or 0
		if t > newestTime then
			newestTime, newestFull = t, full
		end
	end

	-- choisi le main
	local finalMain = marked or newestFull or p.mainFull or ""

	-- 🔥 reset tous les autres à false
	for full, c in pairs(p.characters or {}) do
		c.isMain = (full == finalMain)
	end

	p.mainFull = finalMain
	p.updatedAt = Now()
end

function DB:ComputeMarkedMainOnly(guildUID, uid)
	local gRoot = EnsureGuildRoot(guildUID)
	local p = gRoot.players[uid]
	if not p then
		return ""
	end

	local marked = ""
	for full, c in pairs(p.characters or {}) do
		if c.isMain then
			marked = full
			break
		end
	end

	p.mainFull = marked or ""
	p.updatedAt = Now()
	return p.mainFull
end

function DB:SaveSelfIntoGuildModel()
	local guildUID = self:GetGuildUID()
	if not guildUID then
		return
	end
	local gRoot = EnsureGuildRoot(guildUID)

	gRoot.guildInfo.guildUID = guildUID
	gRoot.guildInfo.guildName = GetGuildInfo("player") or gRoot.guildInfo.guildName or ""
	gRoot.guildInfo.realm = NormRealm() or gRoot.guildInfo.realm or ""
	gRoot.guildInfo.updatedAt = Now()

	-- Calcule UID
	local uid, fallback_uid, used_fallback = BuildUserUID()

	-- Si on a déjà des données sous l’UID de secours, fusionne vers l’UID fort
	if not used_fallback and gRoot.players[fallback_uid] then
		MergePlayerUIDInGuild(gRoot, fallback_uid, uid)
	end

	-- Point d’écriture
	local targetUID = used_fallback and fallback_uid or uid
	local p = EnsurePlayerInGuild(gRoot, targetUID)

	local rec = BuildSelfCharacterRecord()
	if rec.full == "" then
		return
	end

	-- Écrit la fiche personnage (sans écraser les champs customs)
	local cur = p.characters[rec.full] or {}
	cur.full = rec.full
	cur.name = rec.name
	cur.realm = rec.realm
	cur.classLoc = rec.classLoc
	cur.classTag = rec.classTag
	cur.spec = rec.spec
	cur.specID = rec.specID
	cur.level = rec.level
	cur.ilevel = rec.ilevel
	cur.mplus = rec.mplus
	cur.achv = rec.achv
	cur.isMain = rec.isMain and true or false
	cur.playerGUID = rec.playerGUID -- local, non sensible, OK à partager
	cur.updatedAt = Now()
	p.characters[rec.full] = cur

	-- Main, uniquement si la note publique du perso courant dit "Main"
	if rec.isMain then
		ForceUniqueMain(p, rec.full)
	else
		-- On ne casse rien, on recalcule juste à partir des "true" existants
		self:ComputeMarkedMainOnly(guildUID, targetUID)
	end

	p.updatedAt = Now()
	self:DedupCharactersByPlayerGUID(guildUID)
end

-- Import réseau d’un personnage, la clé de joueur est un UID
function DB:UpsertCharacterFromRemote(guildUID, uid, charRecord)
	if not guildUID or not uid or type(charRecord) ~= "table" then
		return
	end
	local gRoot = EnsureGuildRoot(guildUID)
	local p = EnsurePlayerInGuild(gRoot, uid)

	local full = tostring(charRecord.full or "")
	if full == "" then
		local name, realm = tostring(charRecord.name or ""), tostring(charRecord.realm or "")
		if name ~= "" and realm ~= "" then
			full = name .. "-" .. realm
		end
	end
	if full == "" then
		return
	end

	local cur = p.characters[full] or {}
	cur.full = full
	local function setIfNonEmpty(key, value)
		if type(value) == "string" and value ~= "" then
			cur[key] = value
		elseif cur[key] == nil then
			cur[key] = ""
		end
	end
	local function setIfPositive(key, value)
		local n = tonumber(value or 0) or 0
		if n > 0 then
			cur[key] = n
		elseif cur[key] == nil then
			cur[key] = 0
		end
	end

	setIfNonEmpty("name", tostring(charRecord.name or ""))
	setIfNonEmpty("realm", tostring(charRecord.realm or ""))
	setIfNonEmpty("classLoc", tostring(charRecord.classLoc or ""))
	setIfNonEmpty("classTag", tostring(charRecord.classTag or ""))
	setIfNonEmpty("spec", tostring(charRecord.spec or ""))

	setIfPositive("specID", charRecord.specID)
	setIfPositive("level", charRecord.level)
	setIfPositive("ilevel", charRecord.ilevel)
	setIfPositive("mplus", charRecord.mplus)
	setIfPositive("achv", charRecord.achv)

	if charRecord.isMain ~= nil then
		cur.isMain = charRecord.isMain and true or false
	elseif cur.isMain == nil then
		cur.isMain = false
	end
	setIfNonEmpty("playerGUID", tostring(charRecord.playerGUID or ""))
	if charRecord.bio ~= nil then
		cur.bio = charRecord.bio
	end
	local incomingAt = tonumber(charRecord.updatedAt or 0) or 0
	cur.updatedAt = incomingAt > 0 and incomingAt or Now()

	p.characters[full] = cur

	if cur.isMain then
		ForceUniqueMain(p, full)
	else
		self:ComputeMarkedMainOnly(guildUID, uid)
	end

	p.updatedAt = math.max(tonumber(p.updatedAt or 0) or 0, cur.updatedAt or 0)
	gRoot.guildInfo.updatedAt = math.max(tonumber(gRoot.guildInfo.updatedAt or 0) or 0, cur.updatedAt or 0)
	self:DedupCharactersByPlayerGUID(guildUID)
end

-- Patch ciblé d’un personnage (mise à jour partielle)
function DB:UpsertCharacterPatch(guildUID, uid, full, kv)
	if not guildUID or not uid or not full or type(kv) ~= "table" then
		return
	end
	local gRoot = EnsureGuildRoot(guildUID)
	local p = EnsurePlayerInGuild(gRoot, uid)

	local cur = p.characters[full] or {}
	cur.full = full
	if kv.name ~= nil then
		cur.name = tostring(kv.name or "")
	end
	if kv.realm ~= nil then
		cur.realm = tostring(kv.realm or "")
	end
	if kv.classLoc ~= nil then
		cur.classLoc = tostring(kv.classLoc or "")
	end
	if kv.classTag ~= nil then
		cur.classTag = tostring(kv.classTag or "")
	end
	if kv.spec ~= nil then
		cur.spec = tostring(kv.spec or "")
	end
	if kv.specID ~= nil then
		cur.specID = tonumber(kv.specID or 0) or 0
	end
	if kv.level ~= nil then
		cur.level = tonumber(kv.level or 0) or 0
	end
	if kv.ilevel ~= nil then
		cur.ilevel = tonumber(kv.ilevel or 0) or 0
	end
	if kv.mplus ~= nil then
		cur.mplus = tonumber(kv.mplus or 0) or 0
	end
	if kv.achv ~= nil then
		cur.achv = tonumber(kv.achv or 0) or 0
	end
	if kv.bio ~= nil then
		if kv.bio == "__DELETE__" then
			cur.bio = nil
		elseif type(kv.bio) == "table" then
			local shared = EnsureGuildShared(guildUID)
			local prefs = shared.guildMemberPrefs[uid] or {}
			if type(prefs.biographie) ~= "table" then
				prefs.biographie = {}
			end
			prefs.biographie[full] = NormalizeBioForStorage(kv.bio)
			prefs.updatedAt = Now()
			shared.guildMemberPrefs[uid] = prefs
			cur.bio = nil
		else
			cur.bio = nil
		end
	end
	if kv.playerGUID ~= nil then
		cur.playerGUID = tostring(kv.playerGUID or "")
	end
	if kv.updatedAt ~= nil then
		cur.updatedAt = tonumber(kv.updatedAt or 0) or 0
	else
		cur.updatedAt = Now()
	end
	if kv.isMain ~= nil then
		cur.isMain = kv.isMain and true or false
	end

	p.characters[full] = cur

	if kv.isMain ~= nil then
		if cur.isMain then
			ForceUniqueMain(p, full)
		else
			self:ComputeMarkedMainOnly(guildUID, uid)
		end
	end

	p.updatedAt = math.max(tonumber(p.updatedAt or 0) or 0, cur.updatedAt or 0)
	gRoot.guildInfo.updatedAt = math.max(tonumber(gRoot.guildInfo.updatedAt or 0) or 0, cur.updatedAt or 0)
	self:DedupCharactersByPlayerGUID(guildUID)
end

-- ==========
-- Lecture
-- ==========
function DB:GetGuildPlayers(guildUID)
	local gid = guildUID or self:GetGuildUID()
	if not gid or gid == "" then
		return nil
	end
	local gRoot = EnsureGuildRoot(gid)
	return gRoot and gRoot.players or nil
end

function DB:GetGuildPlayer(guildUID, uid)
	local gid = guildUID or self:GetGuildUID()
	if not gid or gid == "" then
		return nil
	end
	local gRoot = EnsureGuildRoot(gid)
	return gRoot and gRoot.players and gRoot.players[uid] or nil
end

function DB:GetGuildMemberPrefs(guildUID, uid)
	local gid = guildUID or self:GetGuildUID()
	if not gid or gid == "" or not uid or uid == "" then
		return nil
	end
	self:SanitizeOtherDrafts(gid)
	MigrateBiographies(gid, uid)
	local shared = EnsureGuildShared(gid)
	local prefs = shared.guildMemberPrefs and shared.guildMemberPrefs[uid] or nil
	return DecodePrefsForRead(prefs)
end

function DB:GetGuildRaidLeaderUID(guildUID)
	local gid = guildUID or self:GetGuildUID()
	if not gid or gid == "" then
		return nil
	end
	local shared = EnsureGuildShared(gid)
	local prefsMap = shared and shared.guildMemberPrefs or nil
	if type(prefsMap) ~= "table" then
		return nil
	end
	local bestUID = nil
	local bestAt = -1
	for uid, prefs in pairs(prefsMap) do
		if
			type(uid) == "string"
			and uid:sub(1, 4) == "uid:"
			and type(prefs) == "table"
			and prefs.raidLeader == true
		then
			local ts = tonumber(prefs.updatedAt or 0) or 0
			if ts > bestAt then
				bestUID = uid
				bestAt = ts
			end
		end
	end
	return bestUID
end

function DB:SetGuildRaidLeaderUID(guildUID, raidLeaderUID)
	local gid = guildUID or self:GetGuildUID()
	if not gid or gid == "" or not raidLeaderUID or raidLeaderUID == "" then
		return false, {}
	end
	local shared = EnsureGuildShared(gid)
	local prefsMap = shared.guildMemberPrefs or {}
	shared.guildMemberPrefs = prefsMap
	local existingTarget = prefsMap[raidLeaderUID]
	if type(existingTarget) ~= "table" then
		-- RL can only be assigned to members with an existing addon profile.
		return false, {}
	end
	local changed = {}
	local now = Now()

	for uid, prefs in pairs(prefsMap) do
		if uid ~= raidLeaderUID and type(prefs) == "table" and prefs.raidLeader == true then
			prefs.raidLeader = false
			prefs.updatedAt = now
			changed[#changed + 1] = uid
		end
	end

	local target = prefsMap[raidLeaderUID]
	if target.raidLeader ~= true then
		target.raidLeader = true
		target.updatedAt = now
		changed[#changed + 1] = raidLeaderUID
	end

	if changed[1] then
		local gRoot = EnsureGuildRoot(gid)
		gRoot.guildInfo.updatedAt = now
	end
	return true, changed
end

function DB:SanitizeOtherDrafts(guildUID, force)
	local gid = guildUID or self:GetGuildUID()
	if not gid or gid == "" then
		return
	end
	self._draftsSanitized = self._draftsSanitized or {}
	if not force and self._draftsSanitized[gid] then
		return
	end
	local shared = EnsureGuildShared(gid)
	local prefsMap = shared and shared.guildMemberPrefs or nil
	if type(prefsMap) ~= "table" then
		self._draftsSanitized[gid] = true
		return
	end
	local changed = false
	for uid, prefs in pairs(prefsMap) do
		if type(prefs) == "table" and not IsSelfUID(uid) then
			local dirty = false
			if prefs.epic ~= nil and ShouldDeleteOtherBioEntry(prefs.epic) then
				prefs.epic = nil
				dirty = true
			end
			if type(prefs.biographie) == "table" then
				for k, v in pairs(prefs.biographie) do
					if ShouldDeleteOtherBioEntry(v) then
						prefs.biographie[k] = nil
						dirty = true
					end
				end
				if dirty and not next(prefs.biographie) then
					prefs.biographie = nil
				end
			end
			if dirty then
				prefs.updatedAt = Now()
				changed = true
			end
		end
	end
	if changed then
		local gRoot = EnsureGuildRoot(gid)
		gRoot.guildInfo.updatedAt = Now()
	end
	self._draftsSanitized[gid] = true
end

function DB:GetGuildPlayerCharacters(guildUID, uid)
	local p = self:GetGuildPlayer(guildUID, uid)
	if not p then
		return {}
	end
	MigrateBiographies(guildUID or self:GetGuildUID(), uid)
	return p.characters or {}
end

function DB:UpsertGuildMemberPrefs(guildUID, uid, prefs, force)
	if not guildUID or guildUID == "" or not uid or uid == "" or type(prefs) ~= "table" then
		return
	end
	local shared = EnsureGuildShared(guildUID)
	local cur = shared.guildMemberPrefs[uid] or {}
	local incomingAt = tonumber(prefs.updatedAt or 0) or 0
	local existingAt = tonumber(cur.updatedAt or 0) or 0
	if not force and existingAt > 0 and incomingAt > 0 and incomingAt < existingAt then
		return
	end
	if prefs.emotesEnabled ~= nil then
		cur.emotesEnabled = prefs.emotesEnabled and true or false
	end
	if prefs.emotesSound ~= nil then
		cur.emotesSound = prefs.emotesSound and true or false
	end
	if prefs.raidLeader ~= nil then
		cur.raidLeader = prefs.raidLeader and true or false
	end
	if prefs.epic ~= nil then
		if type(cur.biographie) ~= "table" then
			cur.biographie = {}
		end
		if prefs.epic == "__DELETE__" then
			local exAt = BioUpdatedAt(cur.biographie[BIO_GENERAL_KEY])
			if ShouldAcceptMostRecent(incomingAt, exAt, cur.biographie[BIO_GENERAL_KEY] ~= nil) then
				cur.biographie[BIO_GENERAL_KEY] = nil
			end
		elseif type(prefs.epic) == "table" then
			local inAt = BioUpdatedAt(prefs.epic)
			local exAt = BioUpdatedAt(cur.biographie[BIO_GENERAL_KEY])
			if ShouldAcceptMostRecent(inAt > 0 and inAt or incomingAt, exAt, cur.biographie[BIO_GENERAL_KEY] ~= nil) then
				cur.biographie[BIO_GENERAL_KEY] = NormalizeBioForStorage(prefs.epic)
			end
		elseif type(prefs.epic) == "string" and prefs.epic:sub(1, #EPIC_B64_PREFIX) == EPIC_B64_PREFIX then
			local decoded = DecodeBioValueForRead(prefs.epic)
			if type(decoded) == "table" then
				local inAt = BioUpdatedAt(decoded)
				local exAt = BioUpdatedAt(cur.biographie[BIO_GENERAL_KEY])
				if ShouldAcceptMostRecent(inAt > 0 and inAt or incomingAt, exAt, cur.biographie[BIO_GENERAL_KEY] ~= nil) then
					cur.biographie[BIO_GENERAL_KEY] = NormalizeBioForStorage(decoded)
				end
			else
				local exAt = BioUpdatedAt(cur.biographie[BIO_GENERAL_KEY])
				if ShouldAcceptMostRecent(incomingAt, exAt, cur.biographie[BIO_GENERAL_KEY] ~= nil) then
					cur.biographie[BIO_GENERAL_KEY] = prefs.epic
				end
			end
		end
	end
	if prefs.biographie ~= nil then
		if prefs.biographie == "__DELETE__" then
			local exAt = tonumber(cur.updatedAt or 0) or 0
			if ShouldAcceptMostRecent(incomingAt, exAt, cur.biographie ~= nil) then
				cur.biographie = nil
			end
		elseif type(prefs.biographie) == "table" then
			cur.biographie = cur.biographie or {}
			for k, v in pairs(prefs.biographie) do
				if v == "__DELETE__" then
					local exAt = BioUpdatedAt(cur.biographie[k])
					if ShouldAcceptMostRecent(incomingAt, exAt, cur.biographie[k] ~= nil) then
						cur.biographie[k] = nil
					end
				elseif type(v) == "table" then
					local inAt = BioUpdatedAt(v)
					local exAt = BioUpdatedAt(cur.biographie[k])
					if ShouldAcceptMostRecent(inAt > 0 and inAt or incomingAt, exAt, cur.biographie[k] ~= nil) then
						cur.biographie[k] = NormalizeBioForStorage(v)
					end
				elseif type(v) == "string" and v:sub(1, #EPIC_B64_PREFIX) == EPIC_B64_PREFIX then
					local decoded = DecodeBioValueForRead(v)
					if type(decoded) == "table" then
						local inAt = BioUpdatedAt(decoded)
						local exAt = BioUpdatedAt(cur.biographie[k])
						if ShouldAcceptMostRecent(inAt > 0 and inAt or incomingAt, exAt, cur.biographie[k] ~= nil) then
							cur.biographie[k] = NormalizeBioForStorage(decoded)
						end
					else
						local exAt = BioUpdatedAt(cur.biographie[k])
						if ShouldAcceptMostRecent(incomingAt, exAt, cur.biographie[k] ~= nil) then
							cur.biographie[k] = v
						end
					end
				else
					local exAt = BioUpdatedAt(cur.biographie[k])
					if ShouldAcceptMostRecent(incomingAt, exAt, cur.biographie[k] ~= nil) then
						cur.biographie[k] = v
					end
				end
			end
		end
	end
	cur.updatedAt = incomingAt > 0 and incomingAt or Now()
	shared.guildMemberPrefs[uid] = cur
end

function DB:EnsureGuildProgress(guildUID)
	local gid = guildUID or self:GetGuildUID()
	if not gid then
		return nil
	end
	return EnsureGuildProgress(gid)
end

function DB:EncodeGuildProgressPoints(guildUID, uid, groupKey, points)
	return EncodeProgressPoints(guildUID, uid, groupKey, points)
end

function DB:DecodeGuildProgressPoints(guildUID, uid, groupKey, entry)
	if type(entry) ~= "table" then
		return nil
	end
	local enc = entry.pointsEnc or entry.points
	local points, ok = DecodeProgressPoints(guildUID, uid, groupKey, enc)
	if not ok then
		return nil
	end
	return points
end

function DB:ResetGuildProgressForUID(guildUID, uid, reason)
	if not guildUID or guildUID == "" or not uid or uid == "" then
		return false
	end
	local progress = EnsureGuildProgress(guildUID)
	if not progress or type(progress.groups) ~= "table" then
		return false
	end
	local changed = false
	for groupKey, group in pairs(progress.groups) do
		if type(group) == "table" and type(group.byUID) == "table" then
			if group.byUID[uid] ~= nil then
				group.byUID[uid] = nil
				group.updatedAt = Now()
				changed = true
			end
		end
	end
	if changed then
		progress.updatedAt = Now()
		if ns.EventBus and ns.EventBus.Emit then
			ns.EventBus.Emit("WG_GUILD_PROGRESS_RESET", guildUID, uid, reason or "invalid")
			ns.EventBus.Emit("WG_GUILD_PROGRESS_UPDATED", guildUID)
		end
	end
	return changed
end

function DB:AddGuildProgressPoints(guildUID, uid, groupKey, points, eventTs)
	if not guildUID or guildUID == "" or not uid or uid == "" or not groupKey then
		return false
	end
	local pts = tonumber(points or 0) or 0
	if pts <= 0 then
		return false
	end
	local progress = EnsureGuildProgress(guildUID)
	if not progress then
		return false
	end
	progress.groups = progress.groups or {}
	local group = progress.groups[groupKey] or { byUID = {}, updatedAt = 0 }
	local entry = group.byUID[uid] or { points = 0, events = 0, updatedAt = 0 }
	local current = tonumber(entry.points or 0) or 0
	if entry.pointsEnc then
		local decoded, ok = DecodeProgressPoints(guildUID, uid, groupKey, entry.pointsEnc)
		if ok and decoded then
			current = decoded
		else
			self:ResetGuildProgressForUID(guildUID, uid, "invalid_points")
			entry = { points = 0, events = 0, updatedAt = 0 }
			current = 0
		end
	end
	local newPoints = current + pts
	entry.pointsEnc = EncodeProgressPoints(guildUID, uid, groupKey, newPoints)
	entry.points = nil
	entry.events = (tonumber(entry.events or 0) or 0) + 1
	entry.updatedAt = tonumber(eventTs or 0) or Now()
	group.byUID[uid] = entry
	group.updatedAt = math.max(tonumber(group.updatedAt or 0) or 0, entry.updatedAt)
	progress.groups[groupKey] = group
	progress.updatedAt = math.max(tonumber(progress.updatedAt or 0) or 0, entry.updatedAt)
	return true
end

function DB:MergeGuildProgress(guildUID, incoming)
	if not guildUID or guildUID == "" or type(incoming) ~= "table" then
		return false
	end
	local progress = EnsureGuildProgress(guildUID)
	if not progress then
		return false
	end
	local changed = false
	local incomingGroups = type(incoming.groups) == "table" and incoming.groups or {}
	progress.groups = progress.groups or {}

	for groupKey, gIn in pairs(incomingGroups) do
		if type(gIn) == "table" then
			local gOut = progress.groups[groupKey] or { byUID = {}, updatedAt = 0 }
			gOut.byUID = gOut.byUID or {}
			local incomingByUID = type(gIn.byUID) == "table" and gIn.byUID or {}
			for uid, v in pairs(incomingByUID) do
				if type(v) == "table" then
					local cur = gOut.byUID[uid] or { points = 0, events = 0, updatedAt = 0 }
					if cur.pointsEnc then
						local decoded, ok = DecodeProgressPoints(guildUID, uid, groupKey, cur.pointsEnc)
						if ok and decoded then
							cur.points = decoded
						end
					end
					local inPoints = tonumber(v.points or 0) or 0
					local inEvents = tonumber(v.events or 0) or 0
					local inUpdated = tonumber(v.updatedAt or 0) or 0
					local curPoints = tonumber(cur.points or 0) or 0
					local curEvents = tonumber(cur.events or 0) or 0
					local curUpdated = tonumber(cur.updatedAt or 0) or 0

					local newPoints = math.max(curPoints, inPoints)
					local newEvents = math.max(curEvents, inEvents)
					local newUpdated = math.max(curUpdated, inUpdated)

					if newPoints ~= curPoints or newEvents ~= curEvents or newUpdated ~= curUpdated then
						local out = { points = newPoints, events = newEvents, updatedAt = newUpdated }
						out.pointsEnc = EncodeProgressPoints(guildUID, uid, groupKey, newPoints)
						out.points = nil
						gOut.byUID[uid] = out
						changed = true
					end
				end
			end
			gOut.updatedAt = math.max(tonumber(gOut.updatedAt or 0) or 0, tonumber(gIn.updatedAt or 0) or 0)
			progress.groups[groupKey] = gOut
		end
	end

	local incomingUpdated = tonumber(incoming.updatedAt or 0) or 0
	progress.updatedAt = math.max(tonumber(progress.updatedAt or 0) or 0, incomingUpdated)

	if changed and ns.EventBus and ns.EventBus.Emit then
		ns.EventBus.Emit("WG_GUILD_PROGRESS_UPDATED", guildUID)
	end

	return changed
end

function DB:UpsertLegendaryProud(guildUID, heroKey, news, clear, force)
	if not guildUID or guildUID == "" or not heroKey or heroKey == "" then
		return
	end
	local gRoot = EnsureGuildRoot(guildUID)
	gRoot.proudNews = gRoot.proudNews or {}
	gRoot.proudNews.legendaryProud = gRoot.proudNews.legendaryProud or {}
	gRoot.proudNews.legendaryProud.byKey = gRoot.proudNews.legendaryProud.byKey or {}
	local store = gRoot.proudNews.legendaryProud.byKey
	local existing = store[heroKey]
	local existingAt = FeaturedUpdatedAt(existing)
	local incomingAt = FeaturedUpdatedAt(news)
	if clear then
		if force or ShouldAcceptMostRecent(incomingAt, existingAt, existing ~= nil) then
			store[heroKey] = nil
		end
		return
	end
	if type(news) ~= "table" then
		return
	end
	if not force and not ShouldAcceptMostRecent(incomingAt, existingAt, existing ~= nil) then
		return
	end
	store[heroKey] = {
		id = news.id,
		type = news.type,
		title = news.title,
		icon = news.icon,
		time = news.time,
		replaceKey = news.replaceKey,
		note = news.note,
		updatedAt = incomingAt,
		guildUID = news.guildUID,
	}
end

function DB:GetGuildPlayerMain(guildUID, uid)
	local p = self:GetGuildPlayer(guildUID, uid)
	return p and p.mainFull or ""
end

-- Dedoublonne les personnages avec le meme playerGUID (rename) dans une guilde.
function DB:DedupCharactersByPlayerGUID(guildUID)
	local gid = guildUID or self:GetGuildUID()
	if not gid or gid == "" then
		return
	end
	local gRoot = EnsureGuildRoot(gid)
	if not gRoot or not gRoot.players then
		return
	end

	local best = {}
	for uid, p in pairs(gRoot.players) do
		local characters = p and p.characters
		if type(characters) == "table" then
			for full, c in pairs(characters) do
				local guid = c and c.playerGUID
				if guid and guid ~= "" then
					local ts = tonumber(c.updatedAt or 0) or 0
					local cur = best[guid]
					if not cur or ts > cur.ts then
						best[guid] = { uid = uid, full = full, ts = ts }
					end
				end
			end
		end
	end

	for uid, p in pairs(gRoot.players) do
		local characters = p and p.characters
		if type(characters) == "table" then
			local changed = false
			for full, c in pairs(characters) do
				local guid = c and c.playerGUID
				if guid and guid ~= "" then
					local keep = best[guid]
					if keep and (keep.uid ~= uid or keep.full ~= full) then
						characters[full] = nil
						changed = true
					end
				end
			end
			if changed then
				if next(characters) == nil then
					gRoot.players[uid] = nil
				else
					if p.mainFull and p.mainFull ~= "" and not characters[p.mainFull] then
						self:RecomputeMainInGuild(gid, uid)
					end
					p.updatedAt = Now()
				end
			end
		end
	end
end

-- Supprime les personnages trop anciens dans le modele guilde (par updatedAt).
function DB:PruneOldCharacters(guildUID, maxAgeSeconds)
	local gid = guildUID or self:GetGuildUID()
	if not gid or gid == "" then
		return
	end
	local gRoot = EnsureGuildRoot(gid)
	if not gRoot or not gRoot.players then
		return
	end
	local now = Now()
	local cutoff = now - (tonumber(maxAgeSeconds) or 0)
	if cutoff <= 0 then
		return
	end

	for uid, p in pairs(gRoot.players) do
		local characters = p and p.characters
		if type(characters) == "table" then
			local changed = false
			for full, c in pairs(characters) do
				local updatedAt = tonumber(c and c.updatedAt or 0) or 0
				if updatedAt > 0 and updatedAt < cutoff then
					characters[full] = nil
					changed = true
				end
			end
			if changed then
				if next(characters) == nil then
					gRoot.players[uid] = nil
				else
					if p.mainFull and p.mainFull ~= "" and not characters[p.mainFull] then
						self:RecomputeMainInGuild(gid, uid)
					end
					p.updatedAt = Now()
				end
			end
		end
	end
end

-- Supprime les joueurs qui ne sont plus dans la guilde (roster local).
function DB:PrunePlayersNotInGuildRoster(guildUID)
	local gid = guildUID or self:GetGuildUID()
	if not gid or gid == "" then
		return
	end
	if not IsInGuild or not IsInGuild() then
		return
	end
	local num = GetNumGuildMembers and GetNumGuildMembers() or 0
	if num <= 0 then
		return
	end
	local gRoot = EnsureGuildRoot(gid)
	if not gRoot or not gRoot.players then
		return
	end

	local roster = {}
	local rosterShort = {}
	for i = 1, num do
		local name = GetGuildRosterInfo(i)
		if name and name ~= "" then
			local full = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name
			roster[full] = true
			if Ambiguate then
				rosterShort[Ambiguate(full, "none")] = true
			end
		end
	end
	if next(roster) == nil then
		return
	end

	local removedUIDs = {}
	for uid, p in pairs(gRoot.players) do
		local hasRosterChar = false
		local characters = p and p.characters
		if type(characters) == "table" then
			for full in pairs(characters) do
				if roster[full] then
					hasRosterChar = true
					break
				end
			end
		end
		if not hasRosterChar then
			removedUIDs[uid] = true
		end
	end

	local deleteDelay = 7 * 86400
	local now = Now()
	local shared = gRoot.guildShared
	if shared and type(shared.guildMemberPrefs) == "table" then
		for uid, prefs in pairs(shared.guildMemberPrefs) do
			if removedUIDs[uid] then
				shared.guildMemberPrefs[uid] = nil
			elseif type(prefs) == "table" and type(prefs.biographie) == "table" then
				local hasRosterChar = false
				local p = gRoot.players and gRoot.players[uid]
				local characters = p and p.characters
				if type(characters) == "table" then
					for full in pairs(characters) do
						if roster[full] then
							hasRosterChar = true
							break
						end
					end
				else
					for full in pairs(prefs.biographie) do
						if full ~= "__general__" and roster[full] then
							hasRosterChar = true
							break
						end
					end
				end

				local changed = false
				local toRemove = {}
				for full, bio in pairs(prefs.biographie) do
					if type(bio) == "table" then
						local shouldSchedule = false
						if full == "__general__" then
							shouldSchedule = not hasRosterChar
						else
							shouldSchedule = not roster[full]
						end
						local delAt = tonumber(bio.deletedAt or 0) or 0
						if shouldSchedule then
							if delAt <= 0 then
								bio.deletedAt = now + deleteDelay
								changed = true
							elseif delAt <= now then
								toRemove[full] = true
								changed = true
							end
						else
							if delAt > 0 then
								bio.deletedAt = nil
								changed = true
							end
						end
					end
				end
				for full in pairs(toRemove) do
					prefs.biographie[full] = nil
				end
				if changed then
					if next(prefs.biographie) == nil then
						prefs.biographie = nil
					end
					prefs.updatedAt = Now()
				end
			end
		end
	end

	for uid, p in pairs(gRoot.players) do
		local characters = p and p.characters
		if type(characters) == "table" then
			local pruned = false
			for full in pairs(characters) do
				if not roster[full] then
					local prefs = shared and shared.guildMemberPrefs and shared.guildMemberPrefs[uid]
					local bio = prefs and prefs.biographie and prefs.biographie[full]
					local delAt = tonumber(bio and bio.deletedAt or 0) or 0
					if delAt > 0 and delAt <= now then
						characters[full] = nil
						pruned = true
					end
				end
			end
			if pruned then
				if next(characters) == nil then
					if not (shared and shared.guildMemberPrefs and shared.guildMemberPrefs[uid] and shared.guildMemberPrefs[uid].biographie) then
						gRoot.players[uid] = nil
						removedUIDs[uid] = true
					end
				else
					if p.mainFull and p.mainFull ~= "" and not characters[p.mainFull] then
						self:RecomputeMainInGuild(gid, uid)
					end
					p.updatedAt = Now()
				end
			end
		end
	end

	for uid in pairs(removedUIDs) do
		gRoot.players[uid] = nil
	end

	if gRoot.statistics and type(gRoot.statistics.players) == "table" then
		for uid in pairs(gRoot.statistics.players) do
			if removedUIDs[uid] then
				gRoot.statistics.players[uid] = nil
			end
		end
	end

	local function KeepActorKey(key)
		if type(key) ~= "string" or key == "" then
			return false
		end
		if key:sub(1, 4) == "uid:" then
			return not removedUIDs[key]
		end
		local full = key
		if key:sub(1, 5) == "full:" then
			full = key:sub(6)
		end
		if full == "" then
			return false
		end
		if roster[full] then
			return true
		end
		if Ambiguate and rosterShort[Ambiguate(full, "none")] then
			return true
		end
		return false
	end

	if gRoot.proudNews then
		local proud = gRoot.proudNews
		if proud.legendaryProud and type(proud.legendaryProud.byKey) == "table" then
			for k in pairs(proud.legendaryProud.byKey) do
				if not KeepActorKey(k) then
					proud.legendaryProud.byKey[k] = nil
				end
			end
		end
		if type(proud.proudByCharacter) == "table" then
			for newsId, by in pairs(proud.proudByCharacter) do
				if type(by) == "table" then
					for k in pairs(by) do
						if not KeepActorKey(k) then
							by[k] = nil
						end
					end
					if next(by) == nil then
						proud.proudByCharacter[newsId] = nil
					end
				end
			end
		end
	end

	if gRoot.featuredNews and type(gRoot.featuredNews.byKey) == "table" then
		for k in pairs(gRoot.featuredNews.byKey) do
			if not KeepActorKey(k) then
				gRoot.featuredNews.byKey[k] = nil
			end
		end
	end
end

-- ==========
-- Sérialisation, modèle guilde → UID → persos
-- ==========
local function SortedKeys(t)
	local keys = {}
	for k in pairs(t or {}) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		local ta, tb = type(a), type(b)
		if ta == tb then
			return tostring(a) < tostring(b)
		end
		return ta < tb
	end)
	return keys
end

local function DumpTable(t, sb)
	sb[#sb + 1] = "{"
	local first = true
	for _, k in ipairs(SortedKeys(t)) do
		local v = t[k]
		if not first then
			sb[#sb + 1] = ","
		end
		first = false
		local key = type(k) == "string" and ('["' .. DumpEsc(k) .. '"]') or ("[" .. tostring(k) .. "]")
		if type(v) == "string" then
			sb[#sb + 1] = key .. '="' .. DumpEsc(v) .. '"'
		elseif type(v) == "number" or type(v) == "boolean" then
			sb[#sb + 1] = key .. "=" .. tostring(v)
		elseif type(v) == "table" then
			sb[#sb + 1] = key .. "="
			DumpTable(v, sb)
		else
			sb[#sb + 1] = key .. '=""'
		end
	end
	sb[#sb + 1] = "}"
end

local function CopyGuildProgressForSnapshot(progress, guildUID)
	if type(progress) ~= "table" then
		return nil
	end
	local out = {
		schema = tonumber(progress.schema or 1) or 1,
		updatedAt = tonumber(progress.updatedAt or 0) or 0,
		groups = {},
	}
	local groups = type(progress.groups) == "table" and progress.groups or {}
	for key, group in pairs(groups) do
		if type(group) == "table" then
			local gOut = { updatedAt = tonumber(group.updatedAt or 0) or 0, byUID = {} }
			local byUID = type(group.byUID) == "table" and group.byUID or {}
			for uid, v in pairs(byUID) do
				if type(v) == "table" then
					local points, ok = DecodeProgressPoints(guildUID or "", uid, key, v.pointsEnc or v.points)
					if not ok then
						points = tonumber(v.points or 0) or 0
					end
					gOut.byUID[uid] = {
						points = points or 0,
						events = tonumber(v.events or 0) or 0,
						updatedAt = tonumber(v.updatedAt or 0) or 0,
					}
				end
			end
			out.groups[key] = gOut
		end
	end
	return out
end

local function CopyRosteurForSnapshot(rosteur)
	if type(rosteur) ~= "table" then
		return nil
	end
	local out = {
		version = tonumber(rosteur.version or 1) or 1,
		phase = tostring(rosteur.phase or "idle"),
		updatedAt = tonumber(rosteur.updatedAt or 0) or 0,
		seasonName = tostring(rosteur.seasonName or ""),
		activeRosterId = rosteur.activeRosterId,
		lockedAt = tonumber(rosteur.lockedAt or 0) or 0,
		lockedByUID = rosteur.lockedByUID,
		prep = { signups = {} },
		rosters = {},
		createTargetsByTemplate = {},
	}
	if type(rosteur.createTargetsByTemplate) == "table" then
		for key, value in pairs(rosteur.createTargetsByTemplate) do
			if type(value) == "table" then
				out.createTargetsByTemplate[tostring(key)] = {
					TANK = 2,
					HEAL = math.max(0, math.floor(tonumber(value.HEAL or 0) or 0)),
					DPS = math.max(0, math.floor(tonumber(value.DPS or 0) or 0)),
				}
			end
		end
	end
	if type(rosteur.prep) == "table" then
		out.prep.startedAt = tonumber(rosteur.prep.startedAt or 0) or 0
		out.prep.startedByUID = rosteur.prep.startedByUID
		if type(rosteur.prep.signups) == "table" then
			for full, v in pairs(rosteur.prep.signups) do
				if type(v) == "table" then
					local rolesOut = {}
					if type(v.roles) == "table" then
						for role, enabled in pairs(v.roles) do
							if enabled then
								rolesOut[role] = true
							end
						end
					end
					out.prep.signups[full] = {
						full = v.full or full,
						role = v.role,
						roles = rolesOut,
						uid = v.uid,
						name = v.name,
						classTag = v.classTag,
						spec = v.spec,
						specID = v.specID,
						heroFull = v.heroFull,
						heroName = v.heroName,
						updatedAt = tonumber(v.updatedAt or 0) or 0,
					}
				end
			end
		end
	end
	if type(rosteur.rosters) == "table" then
		for i = 1, #rosteur.rosters do
			local r = rosteur.rosters[i]
			if type(r) == "table" then
				local rOut = {
					id = r.id,
					name = r.name,
					createdAt = tonumber(r.createdAt or 0) or 0,
					createdByUID = r.createdByUID,
					targets = type(r.targets) == "table" and {} or nil,
					groups = { TANK = {}, HEAL = {}, DPS = {} },
				}
				if type(r.targets) == "table" then
					for k, v in pairs(r.targets) do
						rOut.targets[k] = tonumber(v or 0) or 0
					end
				end
				if type(r.groups) == "table" then
					for _, role in ipairs({ "TANK", "HEAL", "DPS" }) do
						local list = r.groups[role]
						if type(list) == "table" then
							for j = 1, #list do
								local e = list[j]
								if type(e) == "table" then
									rOut.groups[role][#rOut.groups[role] + 1] = {
										id = e.id,
										full = e.full,
										name = e.name,
										classTag = e.classTag,
										uid = e.uid,
										isPU = e.isPU and true or false,
									}
								end
							end
						end
					end
				end
				out.rosters[#out.rosters + 1] = rOut
			end
		end
	end
	return out
end

function DB:SerializeGuildSnapshot(guildUID)
	local gid = guildUID or self:GetGuildUID()
	if not gid then
		return "return {}"
	end
	local gRoot = EnsureGuildRoot(gid)

	local copy = {
		guildInfo = {},
		players = {},
		featuredNews = { byKey = {} },
		guildShared = { guildMemberPrefs = {} },
	}
	for k, v in pairs(gRoot.guildInfo or {}) do
		copy.guildInfo[k] = v
	end

	for uid, p in pairs(gRoot.players or {}) do
		local pOut = { mainFull = p.mainFull or "", updatedAt = tonumber(p.updatedAt or 0) or 0, characters = {} }
		local mainFull = tostring(p.mainFull or "")

		for full, c in pairs(p.characters or {}) do
			local isMainOut = (full == mainFull)
			pOut.characters[full] = {
				full = full,
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
				isMain = isMainOut, -- ← on exporte une seule vérité
				playerGUID = c.playerGUID or "",
				updatedAt = tonumber(c.updatedAt or 0) or 0,
			}
			-- bios migrées vers guildMemberPrefs.biographie
		end

		copy.players[uid] = pOut
	end

	if gRoot.guildShared and gRoot.guildShared.guildMemberPrefs then
		for uid, v in pairs(gRoot.guildShared.guildMemberPrefs) do
			if type(v) == "table" then
				local out = {
					emotesEnabled = v.emotesEnabled,
					emotesSound = v.emotesSound,
					raidLeader = v.raidLeader,
					updatedAt = tonumber(v.updatedAt or 0) or 0,
				}
				if type(v.biographie) == "table" then
					local bio = {}
					for ek, ev in pairs(v.biographie) do
						local normalized = NormalizeBioValueForStorage(ev)
						if type(normalized) == "table" then
							local copy = {}
							for bk, bv in pairs(normalized) do
								copy[bk] = bv
							end
							bio[ek] = copy
						elseif type(normalized) == "string" then
							bio[ek] = normalized
						end
					end
					out.biographie = bio
				elseif type(v.epic) == "table" then
					local normalized = NormalizeBioForStorage(v.epic)
					local bio = {}
					for ek, ev in pairs(normalized) do
						bio[ek] = ev
					end
					out.biographie = { [BIO_GENERAL_KEY] = bio }
				end
				copy.guildShared.guildMemberPrefs[uid] = out
			end
		end
	end

	if gRoot.guildShared and gRoot.guildShared.guildProgress then
		local progressOut = CopyGuildProgressForSnapshot(gRoot.guildShared.guildProgress, gid)
		if progressOut then
			copy.guildShared.guildProgress = progressOut
		end
	end

	if gRoot.guildShared and gRoot.guildShared.rosteur then
		local rosteurOut = CopyRosteurForSnapshot(gRoot.guildShared.rosteur)
		if rosteurOut then
			copy.guildShared.rosteur = rosteurOut
		end
	end

	local featuredByKey = nil
	if gRoot.proudNews and gRoot.proudNews.legendaryProud and gRoot.proudNews.legendaryProud.byKey then
		featuredByKey = gRoot.proudNews.legendaryProud.byKey
	elseif gRoot.featuredNews and gRoot.featuredNews.byKey then
		featuredByKey = gRoot.featuredNews.byKey
	end

	if featuredByKey then
		for k, v in pairs(featuredByKey) do
			if type(v) == "table" then
				local out = {}
				for fk, fv in pairs(v) do
					out[fk] = fv
				end
				copy.featuredNews.byKey[k] = out
			end
		end
	end

	local sb = { "return " }
	DumpTable(copy, sb)
	return table.concat(sb)
end

-- ==========
-- Entrée publique
-- ==========
function DB:SaveSelfProfile()
	self:SaveSelfIntoGuildModel()
end

return DB
