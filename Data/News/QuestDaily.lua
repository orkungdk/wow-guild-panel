-- ==========================================================
-- Daily Quests module (robuste QUEST_TURNED_IN)
-- - Fix: IsQuestDaily/Repeatable souvent false au moment du turn-in
-- - Solution: cache meta via QUEST_ACCEPTED + QUEST_LOG_UPDATE
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { questdaily = 0.5 }

local MODULE_KEY = "questdaily"
local PIGISTE_KEY = "questdaily"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local FALLBACK_ICONS = {
	236677,
	236678,
	236672,
	236674,
	236675,
	236676,
	236680,
	236673,
	236679,
}

-- Enum.QuestFrequency values (fallback numeric)
-- 0 = Default, 1 = Daily, 2 = Weekly  (via C_QuestLog.GetInfo().frequency)
local QF_DEFAULT = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Default) or 0
local QF_DAILY = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Daily) or 1
local QF_WEEKLY = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Weekly) or 2
-- WoW 12+ expose d'autres fréquences (ex: 3 = "autre/periodic")
local QF_OTHER = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Other) or 3

-- ==========================================================
-- 2.2) Cache meta quêtes (session)
-- ==========================================================

ns._QuestDailyMetaCache = ns._QuestDailyMetaCache or { items = {}, lastScanAt = 0, pendingScan = false }
local QCache = ns._QuestDailyMetaCache

local function NowSafe()
	if Data and Data.PigisteAPI and Data.PigisteAPI.Now then
		return Data.PigisteAPI.Now()
	end
	return time and time() or 0
end

local function PruneCache(maxItems, maxAgeSeconds)
	maxItems = tonumber(maxItems or 800) or 800
	maxAgeSeconds = tonumber(maxAgeSeconds or (6 * 3600)) or (6 * 3600)

	local items = QCache.items
	if type(items) ~= "table" then
		return
	end

	local now = NowSafe()

	-- prune age
	for qid, meta in pairs(items) do
		local seenAt = tonumber(meta and meta.seenAt) or 0
		if seenAt > 0 and (now - seenAt) > maxAgeSeconds then
			items[qid] = nil
		end
	end

	-- prune count (simple: if too big, drop oldest by linear scan)
	local count = 0
	for _ in pairs(items) do
		count = count + 1
	end
	if count <= maxItems then
		return
	end

	-- build list
	local arr = {}
	for qid, meta in pairs(items) do
		arr[#arr + 1] = { qid = qid, seenAt = tonumber(meta and meta.seenAt) or 0 }
	end
	table.sort(arr, function(a, b)
		return (a.seenAt or 0) < (b.seenAt or 0)
	end)

	local toDrop = count - maxItems
	for i = 1, toDrop do
		local it = arr[i]
		if it and it.qid then
			items[it.qid] = nil
		end
	end
end

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================

local CFG = {
	enabled = true,
	debug = false,

	counter = {
		-- "day" = compteur qui reset chaque jour (local)
		-- "window" = compteur sur une fenêtre glissante (ex: 24h)
		mode = "day",
		windowSeconds = 24 * 3600,
	},

	-- Event de déclenchement (Pigiste -> Journalist.TickNow(event))
	triggerEvent = "QUEST_TURNED_IN",

	-- Pigiste events: on écoute aussi ACCEPTED + LOG_UPDATE pour cacher la meta
	pigisteEvents = {
		QUEST_TURNED_IN = true,
		QUEST_ACCEPTED = true,
		QUEST_LOG_UPDATE = true,
	},

	-- Events "Journalist trigger"
	triggerEvents = {
		"QUEST_TURNED_IN",
	},

	each = {
		replaceKeyPrefix = "questdaily:",
		ttlSeconds = nil,

		message = "%s %d gunluk gorev tamamladi, sonuncu:\n%s.",

		phrases = {
			"%s %d gunluk gorev tamamladi, sonuncu:\n%s.",
			"%s %d gunluk gorevi bitirdi, en son teslim edilen:\n%s.",
			"%s %d gunluk gorevi teslim etti, en sonu:\n%s.",
			"%s %d gunluk gorevi onaylatti, son gorev:\n%s.",
		},
	},

	resolve = {
		fallbackIcons = FALLBACK_ICONS,
	},

	filter = {
		acceptDaily = true,
		acceptRepeatable = true,
		acceptWorldQuest = false, -- passe à true si tu veux compter les WQ (souvent “journalières” côté joueur)
	},
}

-- ==========================================================
-- 3) Helpers (WoW API safe) + meta-cache
-- ==========================================================
local function IsTaskQuestHard(questID)
	if not questID or questID <= 0 then
		return false
	end

	-- 1) Le plus fiable : les Task/World Quests ont souvent un "time left"
	if C_TaskQuest and C_TaskQuest.GetQuestTimeLeftSeconds then
		local ok, seconds = pcall(C_TaskQuest.GetQuestTimeLeftSeconds, questID)
		if ok and type(seconds) == "number" and seconds > 0 then
			return true
		end
	end

	-- 2) Souvent dispo : "IsActive" pour les task quests
	if C_TaskQuest and C_TaskQuest.IsActive then
		local ok, active = pcall(C_TaskQuest.IsActive, questID)
		if ok and active == true then
			return true
		end
	end

	return false
end

local function pcall_bool(fn, ...)
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, res = pcall(fn, ...)
	if not ok then
		return false, nil
	end
	return true, res
end

local function GetQuestTitleSafe(questID)
	if not questID or questID <= 0 then
		return nil
	end

	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
		if ok and title and title ~= "" then
			return title
		end
	end

	if C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
		local ok, title = pcall(C_TaskQuest.GetQuestInfoByQuestID, questID)
		if ok and title and title ~= "" then
			return title
		end
	end

	return nil
end

local function GetQuestLogIndexSafe(questID)
	if not questID or questID <= 0 then
		return nil
	end

	if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
		local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
		if ok and idx and idx > 0 then
			return idx
		end
	end

	if GetQuestLogIndexByID then
		local ok, idx = pcall(GetQuestLogIndexByID, questID)
		if ok and idx and idx > 0 then
			return idx
		end
	end

	return nil
end

local function GetQuestInfoByIndexSafe(questLogIndex)
	if not questLogIndex or questLogIndex <= 0 then
		return nil
	end
	if C_QuestLog and C_QuestLog.GetInfo then
		local ok, info = pcall(C_QuestLog.GetInfo, questLogIndex)
		if ok and type(info) == "table" then
			return info
		end
	end
	return nil
end

local function IsWorldQuestSafe(questID)
	if not questID or questID <= 0 then
		return false
	end
	if C_QuestLog then
		if C_QuestLog.IsQuestWorldQuest then
			local ok, wq = pcall(C_QuestLog.IsQuestWorldQuest, questID)
			if ok then
				return wq == true
			end
		end
		if C_QuestLog.IsWorldQuest then
			local ok, wq = pcall(C_QuestLog.IsWorldQuest, questID)
			if ok then
				return wq == true
			end
		end
	end
	return false
end

local function IsRepeatableSafe(questID)
	if not questID or questID <= 0 then
		return false
	end
	if C_QuestLog then
		if C_QuestLog.IsQuestRepeatable then
			local ok, rep = pcall(C_QuestLog.IsQuestRepeatable, questID)
			if ok then
				return rep == true
			end
		end
		if C_QuestLog.IsRepeatableQuest then
			local ok, rep = pcall(C_QuestLog.IsRepeatableQuest, questID)
			if ok then
				return rep == true
			end
		end
	end
	return false
end

-- Build/refresh meta for a questID (best-effort)
local function RefreshQuestMeta(questID, hintQuestLogIndex)
	questID = tonumber(questID or 0) or 0
	if questID <= 0 then
		return nil
	end

	local now = NowSafe()

	local meta = QCache.items[questID] or {}
	meta.questID = questID
	meta.seenAt = now

	-- title
	meta.title = GetQuestTitleSafe(questID) or meta.title

	-- HARD LOCK world quest / task (fail-safe)
	local isTaskHard = IsTaskQuestHard(questID)

	meta.isTask = isTaskHard or (meta.isTask == true)
	meta.isWorldQuest = IsWorldQuestSafe(questID) or (meta.isWorldQuest == true)

	-- quest log info (frequency, isTask, isBounty, etc.)
	local idx = tonumber(hintQuestLogIndex or 0) or 0
	if idx <= 0 then
		idx = GetQuestLogIndexSafe(questID) or 0
	end
	if idx > 0 then
		local info = GetQuestInfoByIndexSafe(idx)
		if info then
			meta.frequency = tonumber(info.frequency or meta.frequency or QF_DEFAULT) or QF_DEFAULT
			meta.isTask = (info.isTask == true) or (meta.isTask == true)
			meta.isBounty = (info.isBounty == true) or (meta.isBounty == true)
			-- Note: info.isTask == true => souvent “task/world quest style”
			-- info.frequency 1=Daily 2=Weekly (si c’est un vrai entry questlog)
			meta.title = (info.title and info.title ~= "" and info.title) or meta.title
		end
	end

	-- repeatable (souvent faux au turn-in si quest déjà retirée -> on garde cache true si déjà connu)
	local rep = IsRepeatableSafe(questID)
	meta.isRepeatable = rep or (meta.isRepeatable == true)

	-- daily/weekly via frequency (plus fiable que IsQuestDaily au turn-in)
	local freq = tonumber(meta.frequency or QF_DEFAULT) or QF_DEFAULT
	-- On traite toute fréquence non-default comme "récurrente"
	-- (WoW 12 peut renvoyer 3 pour certaines journalières)
	if freq ~= QF_DEFAULT and freq ~= QF_WEEKLY then
		meta.isDaily = true
	end
	meta.isDaily = (freq == QF_DAILY) or (freq == QF_OTHER) or (meta.isDaily == true)
	meta.isWeekly = (freq == QF_WEEKLY) or (meta.isWeekly == true)

	-- fallback: si Blizzard te donne encore IsQuestDaily/Weekly (quand encore présent dans log), on prend
	if C_QuestLog then
		if C_QuestLog.IsQuestDaily then
			local ok, d = pcall_bool(C_QuestLog.IsQuestDaily, questID)
			if ok then
				meta.isDaily = (d == true) or (meta.isDaily == true)
			end
		end
		if C_QuestLog.IsQuestWeekly then
			local ok, w = pcall_bool(C_QuestLog.IsQuestWeekly, questID)
			if ok then
				meta.isWeekly = (w == true) or (meta.isWeekly == true)
			end
		end
	end

	QCache.items[questID] = meta
	PruneCache(800, 6 * 3600)
	return meta
end

local function ScanQuestLog()
	-- scan complet (questlog pas énorme) mais THROTTLED + coalescé
	if not C_QuestLog then
		return
	end

	local num = 0
	if C_QuestLog.GetNumQuestLogEntries then
		local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
		if ok and n then
			num = tonumber(n) or 0
		end
	end
	if num <= 0 and GetNumQuestLogEntries then
		local ok, n = pcall(GetNumQuestLogEntries)
		if ok and n then
			num = tonumber(n) or 0
		end
	end
	if num <= 0 then
		return
	end

	local now = NowSafe()
	QCache.lastScanAt = now

	for i = 1, num do
		local info = GetQuestInfoByIndexSafe(i)
		if info and type(info) == "table" and info.questID and info.questID > 0 and not info.isHeader then
			RefreshQuestMeta(info.questID, i)
		end
	end
end

local function ScheduleScanQuestLog(delay)
	delay = tonumber(delay or 0.15) or 0.15
	if QCache.pendingScan then
		return
	end
	QCache.pendingScan = true

	local function doScan()
		QCache.pendingScan = false

		-- throttle hard: max 1 scan / 1.0s
		local now = NowSafe()
		local last = tonumber(QCache.lastScanAt or 0) or 0
		if last > 0 and (now - last) < 1.0 then
			return
		end

		ScanQuestLog()
	end

	if C_Timer and C_Timer.After then
		C_Timer.After(delay, doScan)
	else
		doScan()
	end
end

local function IsDailyQuestByMeta(meta)
	if type(meta) ~= "table" then
		return false
	end

	-- 🚫 Jamais une World Quest (expédition)
	if meta.isWorldQuest == true then
		return false
	end

	-- 🚫 Weekly de type world
	if meta.isWeekly == true and meta.isWorldQuest == true then
		return false
	end

	-- ✅ Journalière classique (PRIORITÉ ABSOLUE)
	if meta.isDaily == true then
		return true
	end

	-- ✅ Weekly non-world (quêtes de hub, scénarios)
	if meta.isWeekly == true then
		return true
	end

	-- ✅ Repeatable NON world
	if meta.isRepeatable == true then
		return true
	end

	return false
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

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		-- QUEST_ACCEPTED(questLogIndex, questID)
		-- QUEST_LOG_UPDATE()
		-- QUEST_TURNED_IN(questID, xpReward, moneyReward)
		OnEvent = function(_, event, ...)
			if event == "QUEST_LOG_UPDATE" then
				ScheduleScanQuestLog(0.15)
				return
			end

			if event == "QUEST_ACCEPTED" then
				local questLogIndex, questID = ...
				questID = tonumber(questID or 0) or 0
				if questID > 0 then
					RefreshQuestMeta(questID, tonumber(questLogIndex or 0) or 0)
				end
				-- Optionnel : scan léger après accept
				ScheduleScanQuestLog(0.25)
				return
			end

			if event ~= "QUEST_TURNED_IN" then
				return
			end

			local questID = ...
			questID = tonumber(questID or 0) or 0
			if questID <= 0 then
				return
			end

			-- Refresh meta (peut échouer si retirée du log -> on garde ce qu'on a)
			local meta = RefreshQuestMeta(questID, nil) or QCache.items[questID]

			-- Debug ultra parlant
			if CFG.debug or (ns and ns.Comms and ns.Comms.DEV_MODE) then
				local freq = meta and tonumber(meta.frequency or QF_DEFAULT) or QF_DEFAULT
				local title = meta and meta.title or "?"
				print(
					"|cffffd100[WoW Guilde]|r QUEST_TURNED_IN",
					tostring(questID),
					("title=%q"):format(tostring(title)),
					"freq=" .. tostring(freq),
					"daily=" .. tostring(meta and meta.isDaily == true),
					"weekly=" .. tostring(meta and meta.isWeekly == true),
					"repeatable=" .. tostring(meta and meta.isRepeatable == true),
					"world=" .. tostring(meta and meta.isWorldQuest == true),
					"task=" .. tostring(meta and meta.isTask == true)
				)
			end
			if CFG.debug or (ns and ns.Comms and ns.Comms.DEV_MODE) then
				print(
					"[QUESTDAILY PASS?]",
					questID,
					meta and meta.title or "?",
					"isTask=",
					tostring(meta and meta.isTask == true),
					"isWQ=",
					tostring(meta and meta.isWorldQuest == true),
					"isDaily=",
					tostring(meta and meta.isDaily == true),
					"isWeekly=",
					tostring(meta and meta.isWeekly == true),
					"isRep=",
					tostring(meta and meta.isRepeatable == true),
					"freq=",
					tostring(meta and meta.frequency or QF_DEFAULT)
				)
			end

			if not IsDailyQuestByMeta(meta) then
				return
			end

			local uid = pigAPI.GetMyUID()
			local p = pigAPI.EnsurePlayer(uid)
			if not p then
				return
			end

			local ts = pigAPI.Now()
			local title = (meta and meta.title) or GetQuestTitleSafe(questID) or "Une quête journalière"

			p.questdaily = p.questdaily or {}
			p.questdaily.list = p.questdaily.list or {}

			local entry = {
				questID = questID,
				title = title,
				ts = ts,
			}

			if pigAPI.PushLimited then
				pigAPI.PushLimited(p.questdaily.list, entry, 80)
			else
				p.questdaily.list[#p.questdaily.list + 1] = entry
				if #p.questdaily.list > 80 then
					table.remove(p.questdaily.list, 1)
				end
			end

			p.last = p.last or {}
			p.last.questDailyAt = ts

			local l = pigAPI.GetModuleLast(p, MODULE_KEY)
			l.questID = questID
			l.questTitle = title
			l.questAt = ts

			p.updatedAt = ts

			TickJournalistSoon()
		end,
	})

	-- petit scan au chargement pour initialiser le cache
	ScheduleScanQuestLog(0.35)
end

-- ==========================================================
-- 5) Helpers métier (purs)
-- ==========================================================

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

local function PickIcon(api)
	if api and api.Pick and CFG.resolve.fallbackIcons then
		return api.Pick(CFG.resolve.fallbackIcons)
	end
	local icons = CFG.resolve.fallbackIcons or FALLBACK_ICONS
	if type(icons) == "table" and #icons > 0 then
		return icons[1]
	end
	return nil
end

local function MakeEntryKey(entry)
	if type(entry) ~= "table" then
		return ""
	end
	local ts = tonumber(entry.ts) or 0
	local qid = tonumber(entry.questID) or 0
	return ("%s:%s"):format(tostring(ts), tostring(qid))
end

local function CollectNewEntries(intel, last)
	local list = intel and intel.questdaily and intel.questdaily.list or nil
	if type(list) ~= "table" or #list == 0 then
		return nil
	end

	last = last or {}

	local lastKey = tostring(last.questDailyTailKey or "")
	local startIdx = 1
	if lastKey ~= "" then
		for i = #list, 1, -1 do
			if MakeEntryKey(list[i]) == lastKey then
				startIdx = i + 1
				break
			end
		end
	end

	if startIdx > #list then
		return nil
	end

	local out = {}
	for i = startIdx, #list do
		out[#out + 1] = list[i]
	end

	last.questDailyTailKey = MakeEntryKey(list[#list])
	return out, last
end

-- ==========================================================
-- 6) News processor
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

	local function ProcessQuestDailyNews(g, intel, last, uid, now)
		if not CFG.enabled then
			return
		end

		local entries, last2 = CollectNewEntries(intel, last)
		if not entries then
			return
		end

		-- copie back last (si ton framework attend in-place)
		if type(last) == "table" and type(last2) == "table" then
			for k, v in pairs(last2) do
				last[k] = v
			end
		end

		local list = intel and intel.questdaily and intel.questdaily.list or nil
		if type(list) ~= "table" or #list == 0 then
			return
		end

		-- on ne publie que la plus récente (sinon tu remplaces 5 fois d'affilée)
		local entry = entries[#entries]
		local lastTs = tonumber(entry.ts) or now
		local lastTitle = entry.title or "Une quête journalière"

		-- compteur
		local count = 0
		local mode = CFG.counter and CFG.counter.mode or "day"
		if mode == "window" then
			local w = tonumber(CFG.counter and CFG.counter.windowSeconds) or (24 * 3600)
			local cutoff = lastTs - w
			for i = #list, 1, -1 do
				local ts = tonumber(list[i] and list[i].ts) or 0
				if ts <= 0 or ts < cutoff then
					break
				end
				count = count + 1
			end
		else
			-- mode "day" : même jour que la dernière quête (local)
			local dref = date("*t", lastTs)
			for i = #list, 1, -1 do
				local ts = tonumber(list[i] and list[i].ts) or 0
				if ts <= 0 then
					break
				end
				local d = date("*t", ts)
				if d.year ~= dref.year or d.yday ~= dref.yday then
					break
				end
				count = count + 1
			end
		end

		local playerName = GetPlayerDisplayNameSafe(api, uid)

		-- template (ATTENTION: maintenant il faut 3 args: name, count, title)
		local tpl = (CFG.each.phrases and api.Pick and api.Pick(CFG.each.phrases))
			or (CFG.each.phrases and CFG.each.phrases[1])
			or CFG.each.message
			or "%s a terminé %d quêtes journalières — dernière :\n%s."

		local msg = tpl:format(playerName, count, lastTitle)

		-- ✅ replaceKey STABLE: 1 actu par joueur (remplacée)
		local replaceKey = ("%s%s"):format(CFG.each.replaceKeyPrefix or "questdaily:", tostring(uid))

		api.AddRawNews(g, {
			text = msg,
			type = "questdaily",
			icon = PickIcon(api),
			ts = lastTs,
			replaceable = true,
			replaceKey = replaceKey,
			ttlSeconds = CFG.each.ttlSeconds,
			points = POINTS.questdaily or 6,
		})
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessQuestDailyNews,
	})
end
