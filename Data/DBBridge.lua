local ADDON, ns = ...

ns.Data = ns.Data or {}
local Data = ns.Data
local DB = ns.DB or {}

local function DB_GetPlayers(guildUID)
	if not DB or not DB.GetGuildPlayers then
		return nil
	end

	-- 1. Essai sur l’UID fourni
	if guildUID then
		local p = DB:GetGuildPlayers(guildUID)
		if p and next(p) then
			return p
		end
	end

	-- 2. Essai sur l’UID « canonique » détecté côté client
	if DB.GetGuildUID then
		local canon = DB:GetGuildUID()
		if canon then
			local p = DB:GetGuildPlayers(canon)
			if p and next(p) then
				return p
			end
		end
	end

	-- 3. Dernier recours, on balaie toutes les racines connues
	if _G.WoWGuildeDB and _G.WoWGuildeDB.guilds then
		-- On essaie d’abord de matcher le nom de guilde et le royaume actuels
		local curName = GetGuildInfo("player")
		local curRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
		for _, g in pairs(_G.WoWGuildeDB.guilds) do
			local m = g.guildInfo or {}
			if g.players and next(g.players) and m.guildName == curName and m.realm == curRealm then
				return g.players
			end
		end
		-- Sinon, la première racine peuplée
		for _, g in pairs(_G.WoWGuildeDB.guilds) do
			if g.players and next(g.players) then
				return g.players
			end
		end
	end

	return nil
end

local function FindPlayerByGUID(guildUID, playerGUID)
	if not playerGUID or playerGUID == "" then
		return nil
	end
	local players = DB_GetPlayers(guildUID)
	if not players then
		return nil
	end
	for uid, p in pairs(players) do
		for full, c in pairs(p.characters or {}) do
			if c.playerGUID == playerGUID then
				return uid, p, full, c
			end
		end
	end
	return nil
end

local function FindPlayerByFull(guildUID, full)
	if not full or full == "" then
		return nil
	end
	local players = DB_GetPlayers(guildUID)
	if not players then
		return nil
	end
	for uid, player in pairs(players) do
		if player.characters and player.characters[full] then
			return uid, player, full, player.characters[full]
		end
	end
	return nil
end

local function GetMainClassSpecFromDB(guildUID, mainFull)
	if not guildUID or not mainFull or mainFull == "" then
		return "", "", ""
	end
	local _, _, _, char = FindPlayerByFull(guildUID, mainFull)
	if char then
		return char.classLoc or "", char.classTag or "", char.spec or ""
	end
	return "", "", ""
end

local function AggregateForPlayer(guildUID, player, rosterFull)
	local classLoc, classTag, spec = "", "", ""
	local pickUpdated = -1
	local base = nil

	if player.mainFull and player.mainFull ~= "" then
		local _, _, _, mainChar = FindPlayerByFull(guildUID, player.mainFull)
		if mainChar then
			base = {
				mplus = tonumber(mainChar.mplus or 0) or 0,
				achv = tonumber(mainChar.achv or 0) or 0,
				ilevel = tonumber(mainChar.ilevel or 0) or 0,
				classLoc = mainChar.classLoc or "",
				classTag = mainChar.classTag or "",
				spec = mainChar.spec or "",
				updatedAt = tonumber(mainChar.updatedAt or 0) or 0,
				mainFull = player.mainFull,
				realm = mainChar.realm or "",
				isMain = (player.mainFull == rosterFull),
			}
		end
	end

	if base then
		return base
	end

	local bestM, bestA, bestI = 0, 0, 0
	local match = player.characters and player.characters[rosterFull] or nil
	if match then
		classLoc = match.classLoc or classLoc
		classTag = match.classTag or classTag
		spec = match.spec or spec
		pickUpdated = tonumber(match.updatedAt or 0) or pickUpdated
	end

	for _, c in pairs(player.characters or {}) do
		local m = tonumber(c.mplus or 0) or 0
		if m > bestM then
			bestM = m
		end
		local a = tonumber(c.achv or 0) or 0
		if a > bestA then
			bestA = a
		end
		local il = tonumber(c.ilevel or 0) or 0
		if il > bestI then
			bestI = il
		end

		local upd = tonumber(c.updatedAt or 0) or 0
		if not match and upd > pickUpdated then
			classLoc = c.classLoc or classLoc
			classTag = c.classTag or classTag
			spec = c.spec or spec
			pickUpdated = upd
		end
	end

	return {
		mplus = bestM,
		achv = bestA,
		ilevel = bestI,
		classLoc = classLoc,
		classTag = classTag,
		spec = spec,
		updatedAt = pickUpdated,
		mainFull = player.mainFull or "",
		realm = "",
		isMain = (player.mainFull == rosterFull),
	}
end

function Data.ResolvePlayerUID(guildUID, full, playerGUID)
	if playerGUID and playerGUID ~= "" then
		local _uid, _p = FindPlayerByGUID(guildUID, playerGUID)
		if _p then
			return _uid, _p
		end
	end
	if full and full ~= "" then
		local _uid, _p = FindPlayerByFull(guildUID, full)
		if _p then
			return _uid, _p
		end
	end
	return nil, nil
end

function Data.GetDBAggregateForRosterEntry(guildUID, rosterName, classDisplayName, classFileName, playerGUID)
	local rosterFull = ns.FullFromRosterName(rosterName)
	local uid, player = nil, nil

	do
		local _uid, _p = FindPlayerByGUID(guildUID, playerGUID)
		if _p then
			uid, player = _uid, _p
		end
	end

	if not player and rosterFull ~= "" then
		local _uid, _p = FindPlayerByFull(guildUID, rosterFull)
		if _p then
			uid, player = _uid, _p
		end
	end

	if not player then
		return nil
	end

	local rec = AggregateForPlayer(guildUID, player, rosterFull)

	if classDisplayName and classDisplayName ~= "" then
		rec.classLoc = classDisplayName
	end
	if classFileName and classFileName ~= "" then
		rec.classTag = classFileName
	end
	return rec
end

function Data.GetMainClassSpecFromDB(guildUID, mainFull)
	return GetMainClassSpecFromDB(guildUID, mainFull)
end
