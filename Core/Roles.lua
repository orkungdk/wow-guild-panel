local ADDON, ns = ...

ns.Roles = ns.Roles or {}
local Roles = ns.Roles

local function GetConfig()
	WoWGuildeDB = WoWGuildeDB or {}
	WoWGuildeDB.Settings = WoWGuildeDB.Settings or {}
	WoWGuildeDB.Settings.RoleOptions = WoWGuildeDB.Settings.RoleOptions or {}
	local cfg = WoWGuildeDB.Settings.RoleOptions
	if cfg.officerMaxRankIndex == nil then
		cfg.officerMaxRankIndex = 1
	end
	return cfg
end

local cachedRank = nil
local cachedAt = 0

local function FindMyRankIndex()
	if not IsInGuild or not IsInGuild() then
		return nil
	end

	local n = GetNumGuildMembers and GetNumGuildMembers() or 0
	if n == 0 then
		return nil
	end

	local myGuid = UnitGUID and UnitGUID("player") or nil
	local myName, myRealm = UnitFullName and UnitFullName("player") or nil
	local myFull = myName and myName .. ((myRealm and myRealm ~= "") and ("-" .. myRealm) or "") or nil

	for i = 1, n do
		local name, _, rankIndex, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		if guid and myGuid and guid == myGuid then
			return rankIndex
		end
		if name and myFull then
			local full = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name
			if full == myFull then
				return rankIndex
			end
		end
	end

	return nil
end

function Roles.GetMyRankIndex()
	local now = time and time() or 0
	if now - cachedAt > 2 then
		if ns.RequestGuildData then
			ns.RequestGuildData()
		end
		cachedRank = FindMyRankIndex()
		cachedAt = now
	end
	return cachedRank
end

function Roles.IsGuildLeader()
	return Roles.GetMyRankIndex() == 0
end

function Roles.IsOfficer()
	local idx = Roles.GetMyRankIndex()
	if idx == nil then
		return false
	end
	local cfg = GetConfig()
	return idx <= (tonumber(cfg.officerMaxRankIndex) or 1)
end

function Roles.CanModerateNews()
	return Roles.IsOfficer()
end
