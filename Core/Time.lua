local ADDON, ns = ...

local function MinutesFromYMDH(y, mo, d, h)
	y = y or 0
	mo = mo or 0
	d = d or 0
	h = h or 0
	return (y * 525600) + (mo * 43200) + (d * 1440) + (h * 60)
end

local function FormatLastOnline(y, mo, d, h)
	if y and y > 0 then
		return ("|cff9d9d9d%d yil once|r"):format(y)
	elseif mo and mo > 0 then
		return ("|cff9d9d9d%d ay once|r"):format(mo)
	elseif d and d > 0 then
		return ("|cff9d9d9d%d gun once|r"):format(d)
	elseif h and h > 0 then
		return ("|cff9d9d9d%d saat once|r"):format(h)
	else
		return "|cff9d9d9d1 saatten az once|r"
	end
end

local function RequestGuildData()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

local function GetLastOnlineInfo(index)
	local y, mo, d, h = GetGuildRosterLastOnline(index)
	if y ~= nil then
		return MinutesFromYMDH(y, mo, d, h), FormatLastOnline(y, mo, d, h)
	end
	return 999999, "-"
end

local function NormRealmLocal(r)
	if GetNormalizedRealmName then
		local nrn = GetNormalizedRealmName()
		if nrn and nrn ~= "" then
			return nrn
		end
	end
	if r and r ~= "" then
		return r
	end
	if GetRealmName then
		local rn = GetRealmName()
		if rn and rn ~= "" then
			return rn
		end
	end
	return "UnknownRealm"
end

local function SplitNameRealm(rosterName)
	local n, realm = tostring(rosterName or ""):match("^(.-)%-(.+)$")
	if not n then
		n = tostring(rosterName or "")
		realm = NormRealmLocal()
	end
	return n, realm
end

local function FullFromRosterName(rosterName)
	local n, r = SplitNameRealm(rosterName)
	if n == "" then
		return ""
	end
	return n .. "-" .. r
end

ns.MinutesFromYMDH = MinutesFromYMDH
ns.FormatLastOnline = FormatLastOnline
ns.RequestGuildData = RequestGuildData
ns.GetLastOnlineInfo = GetLastOnlineInfo
ns.SplitNameRealm = SplitNameRealm
ns.FullFromRosterName = FullFromRosterName
