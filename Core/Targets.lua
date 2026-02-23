local ADDON, ns = ...

ns.Targets = ns.Targets or {}
local Targets = ns.Targets

local function Trim(s)
	return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function RequestGuildRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

local function BuildRosterIndex(force)
	local now = GetTime and GetTime() or 0
	Targets._rosterByFull = Targets._rosterByFull or {}
	Targets._rosterByShort = Targets._rosterByShort or {}
	Targets._rosterByAlias = Targets._rosterByAlias or {}
	Targets._rosterBuiltAt = Targets._rosterBuiltAt or 0
	if not force and (now - Targets._rosterBuiltAt) < 2 then
		return
	end
	RequestGuildRoster()
	wipe(Targets._rosterByFull)
	wipe(Targets._rosterByShort)
	wipe(Targets._rosterByAlias)
	local n = GetNumGuildMembers and GetNumGuildMembers() or 0
	for i = 1, n do
		local name, _, _, _, _, zone, note, officernote, online, _, classTag, _, _, isMobile, _, _, guid =
			GetGuildRosterInfo(i)
		if name and name ~= "" then
			local full = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name
			local rec = {
				name = name,
				index = i,
				online = not not online,
				isMobile = not not isMobile,
				zone = zone or "",
				classTag = classTag,
				guid = guid,
				note = note,
				officernote = officernote,
			}
			Targets._rosterByFull[full] = rec
			if Ambiguate then
				Targets._rosterByShort[Ambiguate(full, "none")] = full
			end
			if ns.Utils and ns.Utils.AliasFromNote and ns.Utils.PseudoKey then
				local alias = ns.Utils.AliasFromNote(note)
				if alias and alias ~= "" then
					local k = ns.Utils.PseudoKey(alias)
					if k ~= "" then
						local bucket = Targets._rosterByAlias[k]
						if not bucket then
							bucket = {}
							Targets._rosterByAlias[k] = bucket
						end
						bucket[#bucket + 1] = full
					end
				end
			end
		end
	end
	ns.DB = ns.DB or {}
	ns.DB._RosterByFull = Targets._rosterByFull
	ns.DB._RosterByShort = Targets._rosterByShort
	Targets._rosterBuiltAt = now
end

local function ResolveFromCandidates(candidates)
	if not candidates or #candidates == 0 then
		return nil, false, nil
	end
	BuildRosterIndex(false)
	local roster = Targets._rosterByFull or {}
	for _, full in ipairs(candidates) do
		local r = roster[full]
		if r and (r.online or r.isMobile) then
			return full, true, r
		end
	end
	for _, full in ipairs(candidates) do
		local r = roster[full]
		if r then
			return full, false, r
		end
	end
	return candidates[1], false, nil
end

local function CandidatesFromData(d)
	local list, seen = {}, {}
	local function add(x)
		x = Trim(x)
		if x ~= "" and not seen[x] then
			seen[x] = true
			list[#list + 1] = x
		end
	end
	add(d and d.rosterFull or "")
	add(d and d.mainFull or "")
	if d and d.pseudo and d.pseudo ~= "" then
		if d.realm and d.realm ~= "" and not d.pseudo:find("%-") then
			add(("%s-%s"):format(d.pseudo, d.realm))
		else
			add(d.pseudo)
		end
	end
	return list
end

local function CandidatesFromUID(guildUID, uid)
	local list, seen = {}, {}
	local function add(x)
		x = Trim(x)
		if x ~= "" and not seen[x] then
			seen[x] = true
			list[#list + 1] = x
		end
	end
	if ns.DB and ns.DB.GetGuildPlayerCharacters then
		local chars = ns.DB:GetGuildPlayerCharacters(guildUID, uid) or {}
		for full in pairs(chars) do
			add(full)
		end
	end
	if ns.DB and ns.DB.GetGuildPlayerMain then
		add(ns.DB:GetGuildPlayerMain(guildUID, uid))
	end

	-- Fallback "même héros": on étend par alias de note pour couvrir
	-- les actualités émises sur un autre personnage du même joueur.
	BuildRosterIndex(false)
	if ns.Utils and ns.Utils.PseudoKey and ns.Utils.PSEUDO_CACHE and Targets._rosterByAlias then
		local aliasKeys = {}
		local function addAliasFromFull(full)
			if not full or full == "" then
				return
			end
			local cache = ns.Utils.PSEUDO_CACHE
			local rec = cache[full]
			if not rec and Ambiguate then
				rec = cache[Ambiguate(full, "none")]
			end
			local alias = rec and rec.alias
			if alias and alias ~= "" then
				local k = ns.Utils.PseudoKey(alias)
				if k ~= "" then
					aliasKeys[k] = true
				end
			end
		end
		for i = 1, #list do
			addAliasFromFull(list[i])
		end
		for aliasKey in pairs(aliasKeys) do
			local bucket = Targets._rosterByAlias[aliasKey]
			if type(bucket) == "table" then
				for i = 1, #bucket do
					add(bucket[i])
				end
			end
		end
	end

	return list
end

function Targets.ResolveForData(d)
	return ResolveFromCandidates(CandidatesFromData(d))
end

function Targets.ResolveForUID(guildUID, uid)
	return ResolveFromCandidates(CandidatesFromUID(guildUID, uid))
end

function Targets.ResolveForFull(full)
	if not full or full == "" then
		return nil, false, nil
	end
	return ResolveFromCandidates({ full })
end

function Targets.IsGuildMember(full)
	if not full or full == "" then
		return false
	end
	BuildRosterIndex(false)
	local roster = Targets._rosterByFull or {}
	if roster[full] then
		return true
	end
	if Ambiguate then
		local short = Ambiguate(full, "none")
		if roster[short] then
			return true
		end
		if Targets._rosterByShort and Targets._rosterByShort[short] then
			return true
		end
	end
	return false
end
