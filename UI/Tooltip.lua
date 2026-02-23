local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
ns.Utils = ns.Utils or {}
local EventBus = ns.EventBus

-- ====== Fallbacks utiles ======
local function GetRoleAtlasSafe(role)
	return (UI and UI.GetRoleAtlas) and UI.GetRoleAtlas(role) or nil
end
local function RoleFromClassSpecSafe(tag, spec)
	return (UI and UI.RoleFromClassSpec) and UI.RoleFromClassSpec(tag, spec) or nil
end
local function FormatThousandsSafe(n)
	if ns.Utils and ns.Utils.FormatThousands then
		return ns.Utils.FormatThousands(n)
	end
	n = tonumber(n) or 0
	local s, k = tostring(n), 1
	while k ~= 0 do
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
	end
	return s
end

-- Détection stricte du profil d’addon
local function HasAddonProfile(d)
	return d and d.hasProfile == true
end

--=====================================================================
-- Utilitaires de nom, royaume
--=====================================================================
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

local function SplitNameRealm(name, defaultRealm)
	if name and name:find("%-") then
		local n, r = name:match("^(.-)%-(.+)$")
		return n or name, r or defaultRealm
	end
	return name, defaultRealm
end

local function MakeFullName(name, realm)
	if not name or name == "" then
		return nil
	end
	realm = realm or ""
	if name:find("%-") then
		return name
	end
	if realm ~= "" then
		return name .. "-" .. realm
	end
	return name
end

--=====================================================================
-- Couleur de classe
--=====================================================================
local function ColorizeByClassTagSafe(name, classTag)
	if ns.Utils and ns.Utils.ColorizeByClassTag then
		return ns.Utils.ColorizeByClassTag(name, classTag)
	end
	local C = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
	local c = C and C[classTag or ""]
	if c then
		local r = math.floor((c.r or 1) * 255 + 0.5)
		local g = math.floor((c.g or 1) * 255 + 0.5)
		local b = math.floor((c.b or 1) * 255 + 0.5)
		return ("|cff%02x%02x%02x"):format(r, g, b) .. tostring(name or "-") .. "|r"
	end
	return "|cffffffff" .. tostring(name or "-") .. "|r"
end

--=====================================================================
-- Cache de roster de guilde, avec suivi du « dernier connecté »
--=====================================================================
local GuildCache = {} -- clés: "Nom-Royaume" et "Nom", valeur: { nameFull, nameShort, realm, classTag, zone, online, isMobile, note, officernote, lastMin, lastText, index, noteLower, officerLower }

local function RequestGuildRoster()
	if ns and ns.RequestGuildData then
		ns.RequestGuildData()
	elseif C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

local function PushMemberRecord(nameFull, zone, online, isMobile, note, officernote, lastMin, lastText, index, classTag)
	if not nameFull or nameFull == "" then
		return
	end

	local nameOnly, realmMaybe = SplitNameRealm(nameFull, NormRealmLocal())
	local rec = {
		nameFull = nameFull,
		nameShort = nameOnly or nameFull,
		realm = realmMaybe or "",
		classTag = classTag or "",
		zone = zone or "",
		online = not not online,
		isMobile = not not isMobile,
		note = note or "",
		officernote = officernote or "",
		lastMin = tonumber(lastMin) or 999999,
		lastText = lastText or "-",
		index = index or 0,
	}
	rec.noteLower = rec.note:lower()
	rec.officerLower = rec.officernote:lower()

	GuildCache[nameFull] = rec
	local short = nameFull:match("^[^-]+")
	if short and not GuildCache[short] then
		GuildCache[short] = rec
	end
end

local function RefreshGuildRosterCache()
	if not IsInGuild or not IsInGuild() then
		GuildCache = {}
		return
	end
	RequestGuildRoster()
	GuildCache = {}

	local count = (GetNumGuildMembers and GetNumGuildMembers(true)) or 0
	for i = 1, count do
		-- memberName, rankName, rankIndex, level, classLoc, zone, note, officernote,
		-- online, status, classFileName, achievementPoints, achievementRank, isMobile, canSoR, reputation
		local memberName, _, _, _, _, zone, note, officernote, online, _, classFileName, _, _, isMobile =
			GetGuildRosterInfo(i)

		local lastMin, lastText = 999999, "-"
		if ns and ns.GetLastOnlineInfo then
			lastMin, lastText = ns.GetLastOnlineInfo(i)
		end

		if memberName then
			PushMemberRecord(memberName, zone, online, isMobile, note, officernote, lastMin, lastText, i, classFileName)
		end
	end
end

do
	if EventBus and EventBus.On then
		EventBus.On("PLAYER_ENTERING_WORLD", function()
			RefreshGuildRosterCache()
		end)
		EventBus.On("PLAYER_GUILD_UPDATE", function()
			RefreshGuildRosterCache()
		end)
		EventBus.On("GUILD_ROSTER_UPDATE", function()
			RefreshGuildRosterCache()
		end)
	end
	C_Timer.After(0.5, RefreshGuildRosterCache)
end

--=====================================================================
-- Tokens et candidats
--=====================================================================
local function BuildAltTokens(data)
	local tokens = {}
	local function addToken(s)
		if s and s ~= "" then
			local short = s:match("^[^-]+") or s
			table.insert(tokens, short:lower())
		end
	end
	addToken(data.pseudo)
	addToken(data.mainFull)
	return tokens
end

local function BuildExactCandidates(data)
	local out = {}
	local function addCandidate(n, r)
		if not n or n == "" then
			return
		end
		local nameOnly, realmMaybe = SplitNameRealm(n, r)
		local full = MakeFullName(nameOnly, realmMaybe)
		table.insert(out, full)
		table.insert(out, nameOnly)
	end
	addCandidate(data.pseudo, data.realm)
	addCandidate(data.mainFull, data.realm)
	return out
end

--=====================================================================
-- Selection du meilleur alt, online ou plus recent
--=====================================================================
local function FindMostRecentRosterEntry(data)
	if not data then
		return nil
	end
	local tokens = BuildAltTokens(data)
	if #tokens == 0 then
		return nil
	end

	local seen = {}
	local bestRecent

	for _, rec in pairs(GuildCache) do
		if type(rec) == "table" and not seen[rec] then
			seen[rec] = true
			local nL = rec.noteLower or ""
			local oL = rec.officerLower or ""
			local matched = false
			for _, t in ipairs(tokens) do
				if t ~= "" and (nL:find(t, 1, true) or oL:find(t, 1, true)) then
					matched = true
					break
				end
			end
			if matched then
				if (not bestRecent) or (rec.lastMin < bestRecent.lastMin) then
					bestRecent = rec
				end
			end
		end
	end

	return bestRecent
end

local function FindOnlineRosterEntry(data)
	if not data then
		return nil
	end

	-- 1, correspondance exacte online
	local exact = BuildExactCandidates(data)
	for _, key in ipairs(exact) do
		local rec = key and GuildCache[key]
		if rec and rec.online then
			return rec
		end
	end

	-- 2, alt online via notes
	local tokens = BuildAltTokens(data)
	if #tokens == 0 then
		return nil
	end

	local seen = {}
	for _, rec in pairs(GuildCache) do
		if type(rec) == "table" and not seen[rec] then
			seen[rec] = true
			if rec.online then
				local nL = rec.noteLower or ""
				local oL = rec.officerLower or ""
				for _, t in ipairs(tokens) do
					if t ~= "" and (nL:find(t, 1, true) or oL:find(t, 1, true)) then
						return rec
					end
				end
			end
		end
	end
	return nil
end

local function FindRosterEntryForProfile(data)
	if not data then
		return nil
	end
	local candidates = BuildExactCandidates(data)

	-- 1) correspondances directes, privilegie les membres online
	for _, key in ipairs(candidates) do
		local rec = key and GuildCache[key]
		if rec and rec.online then
			return rec, "exact"
		end
	end
	for _, key in ipairs(candidates) do
		local rec = key and GuildCache[key]
		if rec then
			return rec, "exact"
		end
	end

	-- 2) heuristique via notes, parmi les membres online
	for _, rec in pairs(GuildCache) do
		if type(rec) == "table" and rec.online then
			local note = rec.note or ""
			local onote = rec.officernote or ""
			for _, probe in ipairs(candidates) do
				local p = probe and probe:match("^[^-]+") or probe
				if p and p ~= "" then
					if (note:find(p, 1, true)) or (onote:find(p, 1, true)) then
						return rec, "note"
					end
				end
			end
		end
	end

	return nil
end

--=====================================================================
-- Ligne rôle
--=====================================================================
local function lineRole(role)
	local atlas = GetRoleAtlasSafe(role)
	GameTooltip:AddLine("Rol")
	if atlas then
		GameTooltip:AddLine("|A:" .. atlas .. ":16:16|a " .. (role or "-"), 1, 1, 1)
	else
		GameTooltip:AddLine(role or "-", 1, 1, 1)
	end
end

--=====================================================================
-- Tooltip principal
--=====================================================================
function UI.ShowHeroTooltip(btn, data)
	if not data then
		return
	end

	GameTooltip:SetOwner(btn, "ANCHOR_TOP")
	GameTooltip:ClearLines()

	local r, g, b = 0.8941, 0.6549, 0.1255
	if not data.online then
		r, g, b = 1, 1, 1
	end

	local pseudo = data.pseudo or ""
	GameTooltip:SetText(pseudo, r, g, b)
	if data.hasEpic then
		GameTooltip:AddLine("|A:questlog-storylineicon:16:16|a Destan paylasildi", 1, 0.82, 0, 1)
	end

	-- Récupère roster et groupe d’alts
	local rosterRec, matchKind = FindRosterEntryForProfile(data)
	local isExact = (matchKind == "exact")
	local groupBest = FindMostRecentRosterEntry(data)

	-- Met à jour l’état online depuis le roster si dispo
	if rosterRec and rosterRec.online ~= nil then
		data.online = rosterRec.online
	end

	-- ====== SANS PROFIL, on masque tout le reste ======
	if not HasAddonProfile(data) then
		GameTooltip:AddLine(
			"Bu kahraman, bilgilerini\nGuild hayati addon'u ile paylasmadi.",
			1,
			1,
			1
		)
		GameTooltip:AddLine(" ")

		local onlineRec = FindOnlineRosterEntry(data)
			or (rosterRec and isExact and rosterRec.online and rosterRec)
			or (groupBest and groupBest.online and groupBest)
			or nil

		if onlineRec then
			local coloredName = ColorizeByClassTagSafe(onlineRec.nameShort or onlineRec.nameFull, onlineRec.classTag)
			GameTooltip:AddLine(("|cff33ff33Cevrimici:|r %s"):format(coloredName))
		else
			local mostRecent = groupBest or rosterRec
			local loText = (mostRecent and mostRecent.lastText) or data.lastOnlineText or "-"
			GameTooltip:AddLine("Son giris " .. loText, 0.8, 0.8, 0.8)
		end

		GameTooltip:Show()
		return
	end

	-- ====== AVEC PROFIL, on affiche les infos détaillées ======

	-- Zone uniquement si match exact
	local zoneText
	if rosterRec and isExact then
		if rosterRec.isMobile then
			zoneText = "Mobil uygulama"
		elseif rosterRec.zone and rosterRec.zone ~= "" then
			zoneText = rosterRec.zone
		end
	end
	if not zoneText or zoneText == "" then
		zoneText = (data.zone and data.zone ~= "") and data.zone or "-"
	end
	if zoneText and zoneText ~= "" and zoneText ~= "-" then
		GameTooltip:AddLine(zoneText)
	end

	-- Infos de profil
	local mainName = data.mainFull
	if not mainName or mainName == "" then
		GameTooltip:AddLine("Ana karakter: Tanimsiz", 1, 1, 1)
	else
		if mainName:find("%-") then
			mainName = mainName:match("^(.-)%-.+$") or mainName
		end
		GameTooltip:AddLine("Ana karakter: " .. mainName, 1, 1, 1)
	end

	local clsLoc = (data.mainClassLoc and data.mainClassLoc ~= "") and data.mainClassLoc or data.classLoc
	local spec = (data.mainSpec and data.mainSpec ~= "") and data.mainSpec or data.spec
	local tag = (data.mainClassTag and data.mainClassTag ~= "") and data.mainClassTag or data.classTag
	local hasClass = (clsLoc and clsLoc ~= "") or (spec and spec ~= "")
	local clsSpec = hasClass and (clsLoc .. (spec ~= "" and (" " .. spec) or "")) or "-"
	GameTooltip:AddLine("Sinif ve uzmanlik: " .. clsSpec, 1, 1, 1)
	GameTooltip:AddLine(" ")

	local role = RoleFromClassSpecSafe(tag, spec) or "-"
	lineRole(role)

	local ilvlText = (tonumber(data.ilevel or 0) or 0) > 0 and tostring(data.ilevel) or "-"
	GameTooltip:AddLine("Esya seviyesi (ilvl)")
	GameTooltip:AddLine(ilvlText, 1, 1, 1)

	GameTooltip:AddLine("M+ puani")
	local mplusVal = tonumber(data.mplus or 0) or 0
	if mplusVal > 0 then
		GameTooltip:AddLine(FormatThousandsSafe(mplusVal) .. " puan", 1, 1, 1)
	else
		GameTooltip:AddLine("|cff9d9d9d-|r")
	end

	GameTooltip:AddLine("Basari puani")
	local achvVal = tonumber(data.achv or 0) or 0
	if achvVal > 0 then
		GameTooltip:AddLine(FormatThousandsSafe(achvVal) .. " puan", 1, 1, 1)
	else
		GameTooltip:AddLine("|cff9d9d9d-|r")
	end
	GameTooltip:AddLine(" ")

	-- Etat online, avec perso precis si possible
	local onlineRec = FindOnlineRosterEntry(data)
		or (rosterRec and isExact and rosterRec.online and rosterRec)
		or (groupBest and groupBest.online and groupBest)
		or nil

	if onlineRec then
		local coloredName = ColorizeByClassTagSafe(onlineRec.nameShort or onlineRec.nameFull, onlineRec.classTag)
		GameTooltip:AddLine(("|cff33ff33Cevrimici:|r %s"):format(coloredName))
	else
		local onlineExact = rosterRec and isExact and rosterRec.online
		local onlineGroup = groupBest and groupBest.online
		if onlineExact or onlineGroup or data.online then
			GameTooltip:AddLine("Cevrimici", 0.2, 1.0, 0.2)
		else
			local mostRecent = FindMostRecentRosterEntry(data)
			local loText = "-"
			if mostRecent and mostRecent.lastText then
				loText = mostRecent.lastText
			elseif rosterRec and isExact and rosterRec.lastText then
				loText = rosterRec.lastText
			elseif groupBest and groupBest.lastText then
				loText = groupBest.lastText
			elseif data.lastOnlineText then
				loText = data.lastOnlineText
			end
			GameTooltip:AddLine("Son giris " .. loText, 0.8, 0.8, 0.8)
		end
	end

	local settingsLines = {}
	if data then
		local enabled = data.emotesEnabled
		local sound = data.emotesSound
		if data.isSelf and ns and ns.Emotes and ns.Emotes.GetPrefs then
			local D = ns.Emotes.GetPrefs()
			if D then
				enabled = D.enabled
				sound = D.sound
			end
		end
		if enabled == false then
			if data.isSelf then
				settingsLines[#settingsLines + 1] =
					"|A:voicechat-icon-speaker-mutesilenced:10:10|a Tepkileri kapattiniz."
			else
				settingsLines[#settingsLines + 1] = ("|A:voicechat-icon-speaker-mutesilenced:10:10|a %s tepkileri kapatti."):format(
					pseudo
				)
			end
		elseif sound == false then
			if data.isSelf then
				settingsLines[#settingsLines + 1] =
					"|A:voicechat-icon-speaker-mute:10:10|a Tepki seslerini kapattiniz."
			else
				settingsLines[#settingsLines + 1] = ("|A:voicechat-icon-speaker-mute:10:10|a %s tepki seslerini kapatti."):format(
					pseudo
				)
			end
		end
	end
	if #settingsLines > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("|TInterface\\Common\\UI-TooltipDivider-Transparent:8:300:0:0|t", 1, 1, 1, false)
		for i = 1, #settingsLines do
			GameTooltip:AddLine(settingsLines[i], 0.8, 0.8, 0.8)
		end
	end

	GameTooltip:Show()
end
