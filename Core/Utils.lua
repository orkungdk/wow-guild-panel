local ADDON, ns = ...
ns.Utils = ns.Utils or {}
local Utils = ns.Utils

function Utils.Trim(s)
	s = tostring(s or "")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Utils.BaseName(fullName)
	return (tostring(fullName or "")):gsub("%-.+$", "")
end

function Utils.PseudoKey(pseudo)
	local k = Utils.Trim(pseudo or ""):lower()
	return (k:gsub("%s+", " "))
end

function Utils.ParsePseudo(note, charName)
	local src = Utils.Trim(note or "")
	if src == "" then
		return Utils.BaseName(charName), false
	end
	local firstSeg = src:match("([^,]+)") or src
	local pseudo = Utils.Trim(firstSeg:match("^(.-)•") or firstSeg)
	pseudo = pseudo:gsub("%s+", " ")
	if pseudo == "" then
		pseudo = Utils.BaseName(charName)
	end
	local isMain = firstSeg:lower():find("main", 1, true) ~= nil
	return pseudo, isMain
end

function Utils.FormatThousands(n)
	n = tonumber(n) or 0
	local s = tostring(math.floor(n + 0.5))
	local k
	repeat
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
	until k == 0
	return s
end

function Utils.FormatAchvText(points)
	points = tonumber(points) or 0
	if points == 0 then
		return "-"
	end
	return ("%s points"):format(Utils.FormatThousands(points))
end

function Utils.GetClassColorHexSafe(classTag)
	local C = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
	local c = C and C[classTag or ""]
	if c then
		local r = math.floor((c.r or 1) * 255 + 0.5)
		local g = math.floor((c.g or 1) * 255 + 0.5)
		local b = math.floor((c.b or 1) * 255 + 0.5)
		return ("|cff%02x%02x%02x"):format(r, g, b)
	end
	return "|cffffffff"
end

function Utils.ColorizeByClassTag(name, classTag)
	return Utils.GetClassColorHexSafe(classTag) .. tostring(name or "-") .. "|r"
end

function Utils.FormatDate(ts)
	local t = date("*t", ts or time())
	if not t then
		return ""
	end
	local months = {
		"janvier",
		"fevrier",
		"mars",
		"avril",
		"mai",
		"juin",
		"juillet",
		"aout",
		"septembre",
		"octobre",
		"novembre",
		"decembre",
	}
	local month = months[tonumber(t.month) or 0] or ""
	return ("%d %s %d"):format(tonumber(t.day) or 0, month, tonumber(t.year) or 0)
end

function Utils.AppendDateSuffix(text, ts)
	local dateStr = Utils.FormatDate(ts)
	if dateStr == "" then
		return text or ""
	end
	local body = tostring(text or "")
	if body == "" then
		return dateStr
	end
	if body:sub(-1) == "." then
		return body:sub(1, -2) .. " le " .. dateStr .. "."
	end
	return body .. " le " .. dateStr
end

function Utils.RelativeDateLabel(ts)
	local t = date("*t", ts or time())
	local now = date("*t", time())
	if not t or not now then
		return "aujourd'hui"
	end
	if t.year == now.year and t.yday == now.yday then
		if t.hour < 12 then
			return "plus tôt dans la journée"
		end
		return "aujourd'hui"
	end
	if t.year == now.year and t.yday == (now.yday - 1) then
		return "hier"
	end
	if t.year == now.year and t.yday == (now.yday - 2) then
		return "avant-hier"
	end
	local dayDiff = (time() - (ts or time())) / 86400
	if dayDiff < 7 then
		return "dans la semaine"
	end
	if dayDiff < 14 then
		return "la semaine derniere"
	end
	if t.year == now.year and t.month == now.month then
		return "ce mois"
	end
	if t.year == now.year then
		return "dans l'annee"
	end
	return "il y a longtemps"
end

function Utils.ReplaceNewsTags(text, ts)
	local body = tostring(text or "")
	if body == "" then
		return body
	end
	if body:find("{DateRelative}", 1, true) then
		body = body:gsub("{DateRelative}", Utils.RelativeDateLabel(ts))
	end
	return body
end

function Utils.FormatDateLabel(ts)
	local dateStr = Utils.FormatDate(ts)
	if dateStr == "" then
		return ""
	end
	local t = date("*t", ts or time())
	local now = date("*t", time())
	if t and now and t.year == now.year and t.yday == now.yday then
		return "aujourd'hui, le " .. dateStr
	end
	return "le " .. dateStr
end

function Utils.SafeHooksecurefunc(target, name, func)
	if type(hooksecurefunc) ~= "function" or type(func) ~= "function" then
		return false
	end

	local handler = geterrorhandler and geterrorhandler() or function(err)
		return err
	end
	local function wrapped(...)
		return xpcall(func, handler, ...)
	end

	if type(target) == "string" then
		if type(_G[target]) ~= "function" then
			return false
		end
		hooksecurefunc(target, wrapped)
		return true
	end

	if type(target) == "table" and type(name) == "string" then
		if type(target[name]) ~= "function" then
			return false
		end
		hooksecurefunc(target, name, wrapped)
		return true
	end

	return false
end

function Utils.GetActiveGuildUID()
	if ns.DB and ns.DB.GetGuildUID then
		return ns.DB:GetGuildUID()
	end
	return nil
end

function Utils.ParseGuildUID(gid)
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

function Utils.IsSameGuildUID(gid, activeGid)
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
	local nameA, realmA = Utils.ParseGuildUID(gid)
	local nameB, realmB = Utils.ParseGuildUID(activeGid)
	if nameA and nameA == gName and (not realmA or not gRealm or realmA == gRealm) then
		return activeGid:sub(1, 5) == "club:"
	end
	if nameB and nameB == gName and (not realmB or not gRealm or realmB == gRealm) then
		return gid:sub(1, 5) == "club:"
	end
	return false
end

function Utils.PrettyTimeAgo(t)
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

function Utils.IsAtlas(name)
	return type(name) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
end

function Utils.SetAtlasOrTexture(tex, atlasName, fallbackTexture)
	if tex and type(atlasName) == "string" and Utils.IsAtlas(atlasName) then
		tex:SetAtlas(atlasName, true)
	elseif tex and fallbackTexture then
		tex:SetTexture(fallbackTexture)
	end
end

function Utils.SetPearlIcon(tex, icon, size)
	if not tex then
		return
	end
	if size then
		tex:SetSize(size, size)
	end

	if Utils.IsAtlas(icon) then
		tex:SetAtlas(icon, false)
		tex:SetTexCoord(0, 1, 0, 1)
	else
		tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_Orb_05")
		tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
end

function Utils.NormalizeText(s)
	s = tostring(s or "")
	s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
	s = s:gsub("|r", "")
	s = s:gsub("|T.-|t", "")
	s = s:gsub("|A:.-|a", "")
	return s
end

function Utils.IsDevMode()
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
