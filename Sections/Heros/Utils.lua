local ADDON, ns = ...

ns.Heros = ns.Heros or {}
ns.Heros.Utils = ns.Heros.Utils or {}

local HU = ns.Heros.Utils

local function GetMPlusRank(score)
	score = tonumber(score or 0) or 0
	local prettyScore = (ns.Utils and ns.Utils.FormatThousands) and ns.Utils.FormatThousands(score) or tostring(score)
	local sex = UnitSex and UnitSex("player") or 2
	local isFemale = (sex == 3)
	if score <= 0 then
		return "|cff9d9d9d-|r"
	elseif score < 1000 then
		return (isFemale and "|cffffffffAzeroth kesifcisi|r (%s)" or "|cffffffffAzeroth kesifcisi|r (%s)"):format(prettyScore)
	elseif score < 1500 then
		return (isFemale and "|cff1eff00Azeroth maceracisi|r (%s)" or "|cff1eff00Azeroth maceracisi|r (%s)"):format(prettyScore)
	elseif score < 2000 then
		return (isFemale and "|cff0070ddAzeroth veteran|r (%s)" or "|cff0070ddAzeroth veteran|r (%s)"):format(prettyScore)
	elseif score < 2500 then
		return (isFemale and "|cffa335eeAzeroth sampiyonu|r (%s)" or "|cffa335eeAzeroth sampiyonu|r (%s)"):format(prettyScore)
	elseif score < 3000 then
		return (isFemale and "|cffff8000Azeroth kahramani|r (%s)" or "|cffff8000Azeroth kahramani|r (%s)"):format(prettyScore)
	else
		return (isFemale and "|cffe6cc80Azeroth efsanesi|r (%s)" or "|cffe6cc80Azeroth efsanesi|r (%s)"):format(prettyScore)
	end
end

local function RequestGuildRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

local function GetClassColorHex(classTag)
	local palette = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
	local c = palette and palette[classTag or ""]
	if c then
		return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
	end
	return "|cffffffff"
end

local function KeyForPseudo(pseudo)
	return (ns.Utils and ns.Utils.PseudoKey and ns.Utils.PseudoKey(pseudo)) or pseudo
end

local function FullNameForData(d)
	if not d then
		return ""
	end

	if d.online and d.rosterFull and d.rosterFull ~= "" then
		return d.rosterFull
	elseif d.mainFull and d.mainFull ~= "" then
		return d.mainFull
	elseif d.pseudo and d.pseudo ~= "" then
		if d.realm and d.realm ~= "" and not d.pseudo:find("%-") then
			return ("%s-%s"):format(d.pseudo, d.realm)
		end
		return d.pseudo
	end

	return ""
end

local function ResolveLiveCharacterForData(d)
	if ns.Targets and ns.Targets.ResolveForData then
		local full, online, rec = ns.Targets.ResolveForData(d)
		if full and full ~= "" then
			return full, online, rec
		end
	end
	local fallback = FullNameForData(d)
	if fallback ~= "" then
		return fallback, false, nil
	end
	return nil, false, nil
end

local function ResolveLiveCharacterForUID(guildUID, uid)
	if ns.Targets and ns.Targets.ResolveForUID then
		local full, online, rec = ns.Targets.ResolveForUID(guildUID, uid)
		if full and full ~= "" then
			return full, online, rec
		end
	end
	return nil, false, nil
end

local function ResolveLiveCharacterForFull(full)
	if ns.Targets and ns.Targets.ResolveForFull then
		local live, online, rec = ns.Targets.ResolveForFull(full)
		if live and live ~= "" then
			return live, online, rec
		end
	end
	if full and full ~= "" then
		return full, false, nil
	end
	return nil, false, nil
end

local function Util_GetActiveGuildUID()
	if ns.Utils and ns.Utils.GetActiveGuildUID then
		return ns.Utils.GetActiveGuildUID()
	end
	if ns.DB and ns.DB.GetGuildUID then
		return ns.DB:GetGuildUID()
	end
	return nil
end

local function Util_ParseGuildUID(gid)
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

local function Util_IsSameGuildUID(gid, activeGid)
	if ns.Utils and ns.Utils.IsSameGuildUID then
		return ns.Utils.IsSameGuildUID(gid, activeGid)
	end
	if not gid or not activeGid then
		return false
	end
	if gid == activeGid then
		return true
	end
	local gName = GetGuildInfo and GetGuildInfo("player") or nil
	if not gName or gName == "" then
		return false
	end
	local gRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or nil
	local nameA, realmA = Util_ParseGuildUID(gid)
	local nameB, realmB = Util_ParseGuildUID(activeGid)
	if nameA and nameA == gName and (not realmA or not gRealm or realmA == gRealm) then
		return activeGid:sub(1, 5) == "club:"
	end
	if nameB and nameB == gName and (not realmB or not gRealm or realmB == gRealm) then
		return gid:sub(1, 5) == "club:"
	end
	return false
end

local function Util_PrettyTimeAgo(t)
	if ns.Utils and ns.Utils.PrettyTimeAgo then
		return ns.Utils.PrettyTimeAgo(t)
	end
	local d = time() - (t or time())
	if d < 60 then
		return "\n" .. d .. " saniye once"
	elseif d < 3600 then
		return "\n" .. math.floor(d / 60) .. " dakika once"
	elseif d < 86400 then
		return "\n" .. math.floor(d / 3600) .. " saat once"
	elseif d < 2592000 then
		return "\n" .. math.floor(d / 86400) .. " gun once"
	else
		return "\n" .. math.floor(d / 2592000) .. " ay once"
	end
end

local function Util_SetAtlasOrTexture(tex, atlasName, fallbackTexture)
	if ns.Utils and ns.Utils.SetAtlasOrTexture then
		return ns.Utils.SetAtlasOrTexture(tex, atlasName, fallbackTexture)
	end
	if
		tex
		and type(atlasName) == "string"
		and C_Texture
		and C_Texture.GetAtlasInfo
		and C_Texture.GetAtlasInfo(atlasName)
	then
		tex:SetAtlas(atlasName, true)
	elseif tex and fallbackTexture then
		tex:SetTexture(fallbackTexture)
	end
end

local function Util_IsAtlas(name)
	if ns.Utils and ns.Utils.IsAtlas then
		return ns.Utils.IsAtlas(name)
	end
	return type(name) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
end

local function Util_SetPearlIcon(tex, icon, size)
	if ns.Utils and ns.Utils.SetPearlIcon then
		return ns.Utils.SetPearlIcon(tex, icon, size)
	end
	if not tex then
		return
	end
	if size then
		tex:SetSize(size, size)
	end

	if Util_IsAtlas(icon) then
		tex:SetAtlas(icon, false)
		tex:SetTexCoord(0, 1, 0, 1)
	else
		tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_Orb_05")
		tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
end

local function NormalizeText(s)
	if ns.Utils and ns.Utils.NormalizeText then
		return ns.Utils.NormalizeText(s)
	end
	s = tostring(s or "")
	s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
	s = s:gsub("|r", "")
	s = s:gsub("|T.-|t", "")
	s = s:gsub("|A:.-|a", "")
	return s
end

local function IsDevMode()
	if ns.Utils and ns.Utils.IsDevMode then
		return ns.Utils.IsDevMode()
	end
	if ns and ns.Comms and ns.Comms.DEV_MODE ~= nil then
		return ns.Comms.DEV_MODE == true
	end
	if ns and ns.DEV_MODE ~= nil then
		return ns.DEV_MODE == true
	end
	if ns and ns.Prefs and ns.Prefs.GetSocial then
		return ns.Prefs.GetSocial("devMode", false) == true
	end
	return false
end

local function ReactionMenuSequence()
	if ns.Reactions and ns.Reactions.Sequence then
		return ns.Reactions.Sequence()
	end
	return {}
end

local function AddReactionsSubmenu(root, targetFull, isTest)
	if ns.Reactions and ns.Reactions.AddSubmenu then
		return ns.Reactions.AddSubmenu(root, targetFull, isTest)
	end
	return false
end

local function NeedsElision(s)
	s = tostring(s or ""):gsub("^%s+", "")
	local first = s:sub(1, 1):lower()
	if first == "" then
		return false
	end
	return first:find("[aeiouyàâäéèêëîïôöùûüÿ]") ~= nil
end

HU.GetMPlusRank = GetMPlusRank
HU.RequestGuildRoster = RequestGuildRoster
HU.GetClassColorHex = GetClassColorHex
HU.KeyForPseudo = KeyForPseudo
HU.FullNameForData = FullNameForData
HU.Util_GetActiveGuildUID = Util_GetActiveGuildUID
HU.Util_ParseGuildUID = Util_ParseGuildUID
HU.Util_IsSameGuildUID = Util_IsSameGuildUID
HU.Util_PrettyTimeAgo = Util_PrettyTimeAgo
HU.Util_SetAtlasOrTexture = Util_SetAtlasOrTexture
HU.NeedsElision = NeedsElision
HU.Util_IsAtlas = Util_IsAtlas
HU.Util_SetPearlIcon = Util_SetPearlIcon
HU.NormalizeText = NormalizeText
HU.IsDevMode = IsDevMode
HU.ReactionMenuSequence = ReactionMenuSequence
HU.AddReactionsSubmenu = AddReactionsSubmenu
HU.ResolveLiveCharacterForData = ResolveLiveCharacterForData
HU.ResolveLiveCharacterForUID = ResolveLiveCharacterForUID
HU.ResolveLiveCharacterForFull = ResolveLiveCharacterForFull
