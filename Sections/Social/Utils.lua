local ADDON, ns = ...

ns.Social = ns.Social or {}
ns.Social.Utils = ns.Social.Utils or {}

local SU = ns.Social.Utils

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

local function Util_ColorGradient(p, ...)
	local n = select("#", ...) / 3
	if p >= 1 then
		return select((n - 1) * 3 + 1, ...)
	end
	if p <= 0 then
		return ...
	end
	local seg, rel = math.modf(p * (n - 1))
	local r1, g1, b1 = select(seg * 3 + 1, ...)
	local r2, g2, b2 = select((seg + 1) * 3 + 1, ...)
	return r1 + (r2 - r1) * rel, g1 + (g2 - g1) * rel, b1 + (b2 - b1) * rel
end

local function Util_Clamp01(x)
	return (x < 0 and 0) or (x > 1 and 1) or x
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

local function Util_RangePick(range)
	return range[1] + (range[2] - range[1]) * math.random()
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
	tex:SetSize(size, size)

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

SU.Util_GetActiveGuildUID = Util_GetActiveGuildUID
SU.Util_ParseGuildUID = Util_ParseGuildUID
SU.Util_IsSameGuildUID = Util_IsSameGuildUID
SU.Util_ColorGradient = Util_ColorGradient
SU.Util_Clamp01 = Util_Clamp01
SU.Util_PrettyTimeAgo = Util_PrettyTimeAgo
SU.Util_RangePick = Util_RangePick
SU.Util_SetAtlasOrTexture = Util_SetAtlasOrTexture
SU.Util_IsAtlas = Util_IsAtlas
SU.Util_SetPearlIcon = Util_SetPearlIcon
SU.NormalizeText = NormalizeText
SU.IsDevMode = IsDevMode
SU.ReactionMenuSequence = ReactionMenuSequence
SU.AddReactionsSubmenu = AddReactionsSubmenu
