-- ==========================================================
-- M+ module
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { mplus = 2.5 }

local MODULE_KEY = "mplus"
local PIGISTE_KEY = "mplus"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local WINDOW_SECONDS = (Data.JournalistAPI and Data.JournalistAPI.WindowSeconds) or (48 * 3600)
local random = math.random

local ICONS = {
	1398085,
	458968,
	237540,
	5929738,
	5929742,
}

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================
local CFG = {
	enabled = {
		each = false, -- optionnel (si tu veux 1 news par run plus tard)
		window = true, -- 1 news agrégée sur fenêtre
	},

	-- Event de déclenchement (Pigiste -> Journalist.TickNow(event))
	triggerEvent = "CHALLENGE_MODE_COMPLETED",
	pigisteEvents = {
		CHALLENGE_MODE_COMPLETED = true,
	},
	triggerEvents = {
		"CHALLENGE_MODE_COMPLETED",
	},

	-- Icône du donjon :
	-- "EJ_BUTTON"  -> FileID bouton via EJ_GetInstanceInfo(journalInstanceID) si on peut
	-- "CM_TEXTURE" -> texture via C_ChallengeMode.GetMapUIInfo(mapID)
	-- "AUTO"       -> EJ_BUTTON puis CM_TEXTURE puis fallback
	iconStrategy = "AUTO",

	-- Collecte : ce qu'on stocke par run
	collect = {
		keepSeconds = 300, -- TTL dans l'intel activity
		maxEntries = 80, -- limite locale anti-gonflette si PushActivity n'est pas dispo
	},

	-- Texte (tout ici)
	text = {
		-- ======================================================
		-- Agrégateur (plusieurs runs sur la période)
		-- ======================================================
		window = {
			minCount = 1,
			ttlSeconds = WINDOW_SECONDS,
			replaceKeyPrefix = "mplus48:",

			phrases = {
				"%s bu surecte %d Mythic+ kosusunu art arda bitirdi, kupayi masaya koymadan.",
				"%s son zamanda %d Mythic+ zindani tamamladi. Anahtarlar bunu unutmuyor.",
				"%s bu saatlerde %d Mythic+ meydan okumasini tamamladi.",
				"%s meyhanenin kayit defterine %d Mythic+ zaferi yazdirdi.",
				"%s %d Mythic+ anahtariyla yuzlesti ve ayakta geri dondu.",
				"%s bu donemde %d Mythic+ zindanini dize getirdi.",
				"%s %d Mythic+ kosusunu son portala kadar tasidi.",
				"%s son %d Mythic+ kosusundan sag cikti. Cesaret konustu.",
			},

			messageManyFallback = "%s a terminé %d donjon(s) Mythique+ sur la période.",
		},

		-- ======================================================
		-- Story “fin de donjon” (dernière run)
		-- ======================================================
		story = {
			guildSuffixText = "guild grubuyla",

			-- (heroName, charColored, guildSuffix)
			head = {
				"%s %s%s uzerinde bir Mythic+ kosusunu tamamladi. Anahtar rafa kalkti.",
				"%s %s%s uzerinde bir Mythic+ bitirdi. Korler hala sicak.",
				"%s %s%s uzerinde bir Mythic+ anahtarini gecerli kilidi. Tezgah onayliyor.",
				"%s %s%s uzerinde bir Mythic+ kosusundan geri dondu. Cesaret hala tam.",
				"%s %s%s uzerinde Mythic+ anahtarini sona kadar tasidi.",
			},

			-- (dungeonName, level, runStr, limitStr)
			runOnTime = {
				"Bu kosu %s +%d idi. Sure: %s, hedef zaman: %s. Kupalar kalkiyor.",
				"%s +%d: %s, hedef %s. Temiz ve net.",
				"Bu kosu %s +%d idi. %s surede bitti, zaman siniri %s idi. Guzel hakimiyet.",
				"%s +%d kosusu, %s surede %s oncesinde tamamlandi. Anahtar dayanamadi.",
			},

			-- (dungeonName, level, runStr, limitStr)
			runNotOnTime = {
				"Bu kosu %s +%d idi. %s surede bitti ama zaman siniri %s idi. Zafer yine de orada.",
				"%s +%d: %s. Zaman siniri %s idi ama caba tartisilmaz.",
				"%s +%d, %s surede tamamlandi. Zaman eksikti, cesaret degil.",
			},

			-- (dungeonName, level, runStr)
			runNoLimit = {
				"Bu kosu %s +%d idi, %s surede bitti. Saat tutulmadi.",
				"%s +%d: %s surede tamamlandi. Anahtar kapandi.",
				"%s +%d, %s surede son buldu. Salon yeniden sessiz.",
			},

			-- (dungeonName, level)
			runFallback = {
				"Bu kosu %s +%d idi. Anahtar gecerli.",
				"%s +%d. Kroniklere bir sayfa daha eklendi.",
				"%s +%d. Meyhane bunu konusacak.",
			},

			-- (deltaStr, finalStr)
			score = {
				"Skorda %s puanlik artış, yeni toplam %s puan.",
				"%s puan kazanildi: skor artik %s puan.",
				"Skorda +%s. Guncel toplam: %s puan.",
				"Skor %s puan yukselip %s seviyesine ulasti.",
			},

			-- (finalStr)
			scoreOnlyFinal = {
				"Guncel skor: %s puan.",
				"Skor %s puanda sabitlendi.",
				"Toplam skor artik %s puan.",
			},

			-- si non-éligible / inconnu
			scoreNotEligible = {
			"Bu kosu puan icin uygun degil ama basari yine kayitli.",
			"Skora yazilamasa da zafer yerinde duruyor.",
			},
		},
	},

	-- Fenêtre (par défaut = WindowSeconds Journaliste)
	window = {
		seconds = WINDOW_SECONDS,
	},

	-- Résolution icône
	resolve = {
		fallbackIcons = ICONS,
	},
}

-- ==========================================================
-- 3) Helpers (format / couleurs / guild / icon)
-- ==========================================================

local function FormatMS(ms)
	local v = tonumber(ms)
	if not v then
		return nil
	end
	v = math.floor(v / 1000)

	local h = math.floor(v / 3600)
	local m = math.floor((v % 3600) / 60)
	local s = math.floor(v % 60)

	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

local function FormatSeconds(sec)
	local v = tonumber(sec)
	if not v then
		return nil
	end
	v = math.floor(v)

	local h = math.floor(v / 3600)
	local m = math.floor((v % 3600) / 60)
	local s = math.floor(v % 60)

	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

local function NormalizeTimeLimitSeconds(x)
	local v = tonumber(x)
	if not v then
		return nil
	end
	-- la plupart du temps c’est en secondes (ex 1800). Si c’est énorme, on suppose ms.
	if v > 100000 then
		return math.floor(v / 1000)
	end
	return math.floor(v)
end

local function FormatScoreDelta(delta)
	local d = tonumber(delta)
	if d == nil then
		return nil
	end
	d = math.floor(d + 0.5)
	if d > 0 then
		return "+" .. tostring(d)
	end
	return tostring(d)
end

local function PickFrom(api, listOrString)
	if type(listOrString) == "string" then
		return listOrString
	end
	if type(listOrString) == "table" then
		if api and api.Pick then
			local ok, v = pcall(api.Pick, listOrString)
			if ok and v then
				return v
			end
		end
		return listOrString[random(#listOrString)]
	end
	return nil
end

local function PickFallbackIcon(api)
	if api and api.Pick and CFG.resolve and CFG.resolve.fallbackIcons then
		return api.Pick(CFG.resolve.fallbackIcons)
	end
	local list = (CFG.resolve and CFG.resolve.fallbackIcons) or ICONS
	return list and list[1] or nil
end

local function GetClassColorStr(classTag)
	if not classTag then
		return "ffffffff"
	end
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag]
	if c and c.colorStr then
		return c.colorStr
	end
	return "ffffffff"
end

local function ColorizeName(name, classTag)
	if not name or name == "" then
		return name
	end
	local colorStr = GetClassColorStr(classTag)
	return ("|c%s%s|r"):format(colorStr, name)
end

local function GetMyCharacterNameAndClassTag()
	local name, realm = UnitFullName and UnitFullName("player")
	if not name or name == "" then
		name = UnitName and UnitName("player") or nil
	end
	if realm and realm ~= "" then
		-- tu peux commenter la ligne suivante si tu veux un nom sans royaume
		-- name = ("%s-%s"):format(name, realm)
	end

	local _, classTag = UnitClass and UnitClass("player")
	return name, classTag
end

local function CountGuildiesInGroup()
	local n = 0

	-- solo
	if not IsInGroup() and not IsInRaid() then
		if IsInGuild() and UnitIsInMyGuild and UnitIsInMyGuild("player") then
			n = 1
		end
		return n, (n >= 3)
	end

	-- raid (safe)
	if IsInRaid() then
		local total = GetNumGroupMembers() or 0
		for i = 1, total do
			local unit = "raid" .. i
			if UnitExists(unit) and UnitIsInMyGuild and UnitIsInMyGuild(unit) then
				n = n + 1
			end
		end
		return n, (n >= 3)
	end

	-- party
	if IsInGuild() and UnitIsInMyGuild and UnitIsInMyGuild("player") then
		n = n + 1
	end
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) and UnitIsInMyGuild and UnitIsInMyGuild(unit) then
			n = n + 1
		end
	end

	return n, (n >= 3)
end

local function GetJournalInstanceIdFromMapId(mapId)
	-- 1) table user : journalinstanceID[mapId] => journalInstanceID
	local t = (Data and (Data.journalinstanceID or Data.journalInstanceID or Data.JournalInstanceID))
		or (ns and (ns.journalinstanceID or ns.journalInstanceID or ns.JournalInstanceID))
		or nil

	if t and mapId and t[mapId] then
		return t[mapId]
	end

	-- 2) API EJ : EJ_GetInstanceForMap(mapId) => journalInstanceID
	if mapId and type(EJ_GetInstanceForMap) == "function" then
		local jid = EJ_GetInstanceForMap(mapId)
		if jid then
			return jid
		end
	end

	return nil
end

local function ResolveMPlusDungeonAssets(mapChallengeModeID)
	if not (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then
		return nil, nil, nil, nil
	end

	local name, _, timeLimit, texture, _, uiMapId = C_ChallengeMode.GetMapUIInfo(mapChallengeModeID)

	local dungeonName = name
	local cmIcon = texture -- FileID ou string selon build
	local finalIcon = nil
	local limitSec = NormalizeTimeLimitSeconds(timeLimit)

	local strategy = CFG.iconStrategy or "AUTO"

	-- 1) EJ button (FileID) si possible
	local ejIcon = nil
	if (strategy == "EJ_BUTTON" or strategy == "AUTO") and type(EJ_GetInstanceInfo) == "function" then
		local jid = GetJournalInstanceIdFromMapId(uiMapId)
		if jid then
			local ejName, _, _, buttonFileId = EJ_GetInstanceInfo(jid)
			if ejName and ejName ~= "" then
				dungeonName = dungeonName or ejName
			end
			if type(buttonFileId) == "number" and buttonFileId > 0 then
				ejIcon = buttonFileId
			end
		end
	end

	-- 2) Choix final icône
	if strategy == "EJ_BUTTON" then
		finalIcon = ejIcon
	elseif strategy == "CM_TEXTURE" then
		finalIcon = cmIcon
	else
		finalIcon = ejIcon or cmIcon
	end

	return dungeonName, finalIcon, limitSec, uiMapId
end

local function GetPlayerDisplayNameSafe(api, uid)
	local n = api.GetPlayerDisplayName and api.GetPlayerDisplayName(uid) or nil
	if n and n ~= "" then
		return n
	end
	n = api.GetPlayerDisplayName and api.GetPlayerDisplayName() or nil
	if n and n ~= "" then
		return n
	end
	return uid and tostring(uid) or "Le joueur"
end

local function TailKey(list)
	if not list or #list == 0 then
		return ""
	end

	local e = list[#list]
	if type(e) == "table" then
		return ("%s:%s:%s"):format(tostring(e.ts or ""), tostring(e.mapID or ""), tostring(e.level or ""))
	end

	return tostring(e)
end

local function CountSince(list, since)
	if not list or #list == 0 then
		return 0
	end
	local n = 0
	for i = 1, #list do
		local e = list[i]
		local ts = (type(e) == "table") and tonumber(e.ts) or tonumber(e)
		if ts and ts >= since then
			n = n + 1
		end
	end
	return n
end

local function computeMPlusWindow(list, last, now)
	if not last then
		return
	end

	local tail = TailKey(list)
	local prevTail = tostring(last.mplusTailKey or "")
	if tail == "" or tail == prevTail then
		return
	end
	last.mplusTailKey = tail

	local since = now - (CFG.window.seconds or WINDOW_SECONDS)
	local count = CountSince(list, since)

	local prevCount = tonumber(last.mplusWindowCount) or 0
	if count <= 0 or count == prevCount then
		last.mplusWindowCount = count
		return
	end

	last.mplusWindowCount = count
	return count
end

local function GetMythicPlusScoreSafe()
	if not (C_MythicPlus and C_MythicPlus.GetSeasonBestMythicRatingFromThisExpansion) then
		return nil
	end

	local ok, bestScore = pcall(C_MythicPlus.GetSeasonBestMythicRatingFromThisExpansion)
	if ok and type(bestScore) == "number" then
		return bestScore
	end
	return nil
end

local function BuildStoryText(api, playerName, last)
	local S = CFG.text and CFG.text.story
	if not S or not last then
		return nil
	end

	local guildSuffix = ""
	if last.mplusIsGuildGroup == true then
		local gtxt = S.guildSuffixText or "en groupe de guilde"
		guildSuffix = " " .. gtxt
	end

	-- Personnage coloré
	local charName = last.mplusCharName
	local classTag = last.mplusClassTag
	local charColored = last.mplusCharColored
	if not charColored then
		if charName and charName ~= "" then
			charColored = ColorizeName(charName, classTag)
		else
			-- fallback : au pire on remet le nom joueur
			charColored = playerName
		end
	end

	-- Head
	local headTpl = PickFrom(api, S.head) or "%s a scellé un Mythique+ sur le personnage %s%s."
	local line1 = headTpl:format(playerName, charColored, guildSuffix)

	-- Run line
	local dungeonName = last.mplusDungeonName or (S.unknownDungeon or "Donjon")
	local level = tonumber(last.mplusLevel) or 0
	local runStr = FormatMS(last.mplusTimeMS)
	local limitStr = FormatSeconds(last.mplusTimeLimit)

	local line2 = nil
	if runStr and limitStr then
		if last.mplusOnTime == true then
			local tpl = PickFrom(api, S.runOnTime)
			if tpl then
				line2 = tpl:format(dungeonName, level, runStr, limitStr)
			end
		elseif last.mplusOnTime == false then
			local tpl = PickFrom(api, S.runNotOnTime)
			if tpl then
				line2 = tpl:format(dungeonName, level, runStr, limitStr)
			end
		end

		if not line2 then
			local tpl = PickFrom(api, S.runOnTime) or "C'était %s en +%d. Temps : %s / %s."
			line2 = tpl:format(dungeonName, level, runStr, limitStr)
		end
	elseif runStr then
		local tpl = PickFrom(api, S.runNoLimit)
		if tpl then
			line2 = tpl:format(dungeonName, level, runStr)
		end
	else
		local tpl = PickFrom(api, S.runFallback)
		if tpl then
			line2 = tpl:format(dungeonName, level)
		end
	end

	-- Score line
	local line3 = nil
	local deltaStr = FormatScoreDelta(last.mplusScoreDelta)
	local finalStr = nil
	if last.mplusNewScore ~= nil then
		finalStr = tostring(math.floor(tonumber(last.mplusNewScore) + 0.5))
	end

	if deltaStr and finalStr and last.mplusScoreEligible ~= false then
		local tpl = PickFrom(api, S.score) or "Gain de %s points : cote désormais à %s points."
		line3 = tpl:format(deltaStr, finalStr)
	elseif finalStr and last.mplusScoreEligible ~= false then
		local tpl = PickFrom(api, S.scoreOnlyFinal)
		if tpl then
			line3 = tpl:format(finalStr)
		end
	elseif last.mplusScoreEligible == false then
		local tpl = PickFrom(api, S.scoreNotEligible)
		if tpl then
			line3 = tpl
		end
	end

	-- Assemble
	local out = line1
	if line2 and line2 ~= "" then
		out = out .. "\n" .. line2
	end
	if line3 and line3 ~= "" then
		out = out .. "\n" .. line3
	end
	return out
end

-- ==========================================================
-- 4) Pigiste – collecte des événements
-- ==========================================================

do
	local Pigiste = Data.Pigiste
	local pigAPI = Data.PigisteAPI
	if not Pigiste or not pigAPI then
		return
	end

	-- ----------------------------------------------------------
	-- Déclenchement "event-driven" du Journaliste (coalescé)
	-- ----------------------------------------------------------
	local pendingTick = false
	local function TickJournalistSoon()
		if pendingTick then
			return
		end
		pendingTick = true

		local function doTick()
			pendingTick = false
			local Journalist = (Data and Data.Journalist) or (ns and ns.Data and ns.Data.Journalist) or nil
			if Journalist and type(Journalist.TickNow) == "function" then
				Journalist.TickNow(CFG.triggerEvent)
			end
		end

		if C_Timer and C_Timer.After then
			C_Timer.After(0, doTick)
		else
			doTick()
		end
	end

	local function GetCompletionInfoSafe()
		if not (C_ChallengeMode and C_ChallengeMode.GetCompletionInfo) then
			return nil
		end

		local ok, mapID, level, timeMS, onTime, upgrade, practice, oldScore, newScore, isMapRecord, isAffixRecord, primaryAffix, isEligibleForScore =
			pcall(C_ChallengeMode.GetCompletionInfo)

		if not ok or not mapID or not level then
			return nil
		end

		return {
			mapID = tonumber(mapID),
			level = tonumber(level),
			timeMS = tonumber(timeMS),
			onTime = (onTime == true),
			upgrade = tonumber(upgrade),
			practice = (practice == true),
			oldScore = tonumber(oldScore),
			newScore = tonumber(newScore),
			isEligibleForScore = (isEligibleForScore == true),
		}
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		OnEvent = function()
			local uid = pigAPI.GetMyUID and pigAPI.GetMyUID() or nil
			local p = pigAPI.EnsurePlayer and pigAPI.EnsurePlayer(uid) or nil
			if not p then
				return
			end

			local ts = (pigAPI.Now and pigAPI.Now()) or time()

			-- Counters
			if pigAPI.IncCounter then
				pigAPI.IncCounter(p, "mplusRuns", 1)
			else
				p.counters = p.counters or {}
				p.counters.mplusRuns = (tonumber(p.counters.mplusRuns) or 0) + 1
			end

			-- Meta "last"
			p.last = p.last or {}
			p.last[MODULE_KEY] = p.last[MODULE_KEY] or {}
			local last = p.last[MODULE_KEY]
			last.mplusAt = ts

			-- Completion info (best effort)
			local info = GetCompletionInfoSafe()

			local mapID = info and info.mapID or nil
			local level = info and info.level or nil
			local onTime = (info and info.onTime)
			local timeMS = info and info.timeMS or nil
			local oldScore = info and info.oldScore or nil
			local newScore = info and info.newScore or nil
			local eligible = (info and info.isEligibleForScore)

			-- Fallback score (si Blizzard ne fournit pas)
			if not newScore then
				newScore = GetMythicPlusScoreSafe()
			end

			-- Dungeon assets (name/icon/limit)
			local dungeonName, dungeonIcon, timeLimitSec = nil, nil, nil
			if mapID then
				dungeonName, dungeonIcon, timeLimitSec = ResolveMPlusDungeonAssets(mapID)
			end

			-- Guild group detection (>= 3 guildies)
			local guildCount, isGuildGroup = CountGuildiesInGroup()

			-- Personnage (nom + couleur de classe)
			local charName, classTag = GetMyCharacterNameAndClassTag()
			classTag = (p and p.classTag) or classTag
			local charColored = (charName and ColorizeName(charName, classTag)) or nil

			-- Stocke dans last (pour la news)
			last.mplusMapID = mapID
			last.mplusLevel = level
			last.mplusOnTime = (onTime ~= nil) and (onTime and true or false) or nil
			last.mplusTimeMS = timeMS
			last.mplusTimeLimit = timeLimitSec

			last.mplusDungeonName = (dungeonName and dungeonName ~= "") and dungeonName or last.mplusDungeonName
			last.mplusDungeonIcon = dungeonIcon or last.mplusDungeonIcon

			last.mplusOldScore = oldScore
			last.mplusNewScore = newScore
			last.mplusScoreEligible = (eligible ~= nil) and (eligible and true or false) or nil

			if oldScore and newScore and newScore >= oldScore then
				last.mplusScoreDelta = newScore - oldScore
			else
				last.mplusScoreDelta = nil
			end

			last.mplusGuildCount = guildCount
			last.mplusIsGuildGroup = isGuildGroup and true or false

			last.mplusCharName = charName
			last.mplusClassTag = classTag
			last.mplusCharColored = charColored

			-- Activity store (mêmes conventions que LFG)
			p.activity = p.activity or {}
			p.activity[MODULE_KEY] = p.activity[MODULE_KEY] or {}

			local entry = {
				ts = ts,
				level = level,
				onTime = onTime,
				mapID = mapID,
			}

			-- Utilise PushActivity si dispo, sinon push local + limite
			if pigAPI.PushActivity then
				local ok = pcall(function()
					pigAPI.PushActivity(p, MODULE_KEY, entry, CFG.collect.keepSeconds or 300)
				end)
				if not ok then
					pcall(function()
						pigAPI.PushActivity(p, MODULE_KEY, ts, CFG.collect.keepSeconds or 300)
					end)
				end
			else
				local list = p.activity[MODULE_KEY]
				list[#list + 1] = entry
				local maxN = tonumber(CFG.collect.maxEntries) or 80
				while #list > maxN do
					table.remove(list, 1)
				end
			end

			p.updatedAt = ts
			TickJournalistSoon()
		end,
	})
end

-- ==========================================================
-- 5) News processor
-- ==========================================================

do
	local registry = Data.NewsRegistry
	if not registry or not registry.Register then
		return
	end

	local api = Data.JournalistAPI
	if not api then
		return
	end

	local function ProcessMPlusNews(g, intel, last, uid, now)
		if not (CFG.enabled and CFG.enabled.window) then
			return
		end

		local list = intel.activity and intel.activity[MODULE_KEY]
		if not list or #list == 0 then
			return
		end

		local count = computeMPlusWindow(list, last, now)
		if not count then
			return
		end

		local minCount = (CFG.text and CFG.text.window and tonumber(CFG.text.window.minCount)) or 1
		if count < minCount then
			return
		end

		local playerName = GetPlayerDisplayNameSafe(api, uid)

		-- Texte : si plusieurs runs => 1 ligne agrégateur + story dernière run
		local W = (CFG.text and CFG.text.window) or {}
		local msg

		if count > 1 then
			local tpl = PickFrom(api, W.phrases)
				or W.messageManyFallback
				or "%s a terminé %d donjon(s) Mythique+ sur la période."
			msg = tpl:format(playerName, count)
		end

		local story = BuildStoryText(api, playerName, last)
		if story and story ~= "" then
			if msg then
				msg = msg .. "\n" .. story
			else
				msg = story
			end
		end

		if not msg or msg == "" then
			return
		end

		-- Icône : priorité à l’icône donjon capturée, sinon fallback
		local icon = last and last.mplusDungeonIcon or nil
		if type(icon) ~= "number" and type(icon) ~= "string" then
			icon = nil
		end

		local replaceKeyPrefix = W.replaceKeyPrefix or "mplus48:"
		local replaceKey = ("%s%s"):format(replaceKeyPrefix, tostring(uid))
		local ttlSeconds = W.ttlSeconds or (CFG.window.seconds or WINDOW_SECONDS)

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = icon or PickFallbackIcon(api),
			ts = now,
			replaceable = true,
			replaceKey = replaceKey,
			ttlSeconds = ttlSeconds,
			points = POINTS.mplus or 5,
		})
	end

	-- Déclenchement piloté par le module
	local def = {
		trigger = { events = CFG.triggerEvents },
		run = ProcessMPlusNews,
	}

	local ok = pcall(function()
		registry.Register(MODULE_KEY, def)
	end)
	if not ok then
		registry.Register(MODULE_KEY, ProcessMPlusNews)
	end
end
