-- ==========================================================
-- Merchant gold module (refactor WoW 12 / Midnight style)
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { loot = 1.5 }

local MODULE_KEY = "merchantgold"
local PIGISTE_KEY = "merchantgold"

-- ==========================================================
-- 2) Constantes / defaults
-- ==========================================================

local DEFAULT_NOON_PUBLISH_SECONDS = 12 * 3600
local DEFAULT_NOON_DELAY_MIN_SECONDS = 60
local DEFAULT_NOON_DELAY_MAX_SECONDS = 15 * 60

local DEFAULT_PHRASES = {
	"%s a fait entrer %s dans ses coffres %s.",
	"%s a équilibré les comptes pour %s %s.",
	"%s a vu l’or s’accumuler à hauteur de %s %s.",
	"%s a conclu des échanges justes pour un total de %s %s.",
	"%s a renforcé sa bourse de %s %s, sans discussion.",
	"%s a laissé les registres afficher %s %s.",
	"%s a converti le labeur en valeur : %s %s.",
	"%s a fait sonner les coffres de %s %s.",
	"%s a engrangé %s %s, la balance approuve.",
	"%s a inscrit %s %s dans les livres de comptes.",
	"%s a vu la valeur monter de %s %s.",
	"%s a transformé marchandises en %s %s.",
}

local DEFAULT_ICONS = { 6255014, 133785, 133784, 237281, 133789, 133788, 237283, 133787, 133799, 237282 }

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================
-- Tout ce qui change souvent est ici. Le reste du fichier est le "moteur".
local CFG = {
	enabled = true,

	-- Event interne (Pigiste -> Journalist.TickNow(event))
	-- (pas un event Blizzard : juste un signal interne)
	triggerEvent = "MERCHANT_GOLD_UPDATE",
	pigisteEvents = {
		MERCHANT_SHOW = true,
		MERCHANT_CLOSED = true,
		PLAYER_MONEY = true,
	},
	triggerEvents = {
		"MERCHANT_GOLD_UPDATE",
	},

	-- Publication : 1 news remplaçable par joueur (un seul slot “digest”)
	replaceKeyPrefix = "merchantgold:daily:",

	-- Publication "après midi" : si 12:00 est passé, la prochaine vente programme une news
	noonPublishSeconds = DEFAULT_NOON_PUBLISH_SECONDS,
	noonDelayMinSeconds = DEFAULT_NOON_DELAY_MIN_SECONDS,
	noonDelayMaxSeconds = DEFAULT_NOON_DELAY_MAX_SECONDS,

	-- Durée de vie (si ton Journaliste gère les TTL)
	-- (optionnel : laisse nil si tu veux le TTL standard)
	ttlSeconds = nil,

	phrases = DEFAULT_PHRASES,
	icons = DEFAULT_ICONS,

	-- On ne compte que les gains (ventes). Les dépenses (achats/réparations) sont ignorées.
	countOnlyPositiveDeltas = true,
}

-- ==========================================================
-- 3) Pigiste – collecte des événements
-- ==========================================================

do
	local Pigiste = Data.Pigiste
	local pigAPI = Data.PigisteAPI
	if not Pigiste or not pigAPI then
		return
	end

	-- -----------------------------
	-- Tick coalescé du Journaliste
	-- -----------------------------
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

	-- -----------------------------
	-- Helpers pigiste (state intel)
	-- -----------------------------
	local function DayKey(ts)
		return date("%Y-%m-%d", ts)
	end

	local function DayStart(ts)
		local d = date("*t", ts)
		d.hour, d.min, d.sec = 0, 0, 0
		return time(d)
	end

	local function RandomDelaySeconds(minSeconds, maxSeconds)
		local minv = tonumber(minSeconds) or DEFAULT_NOON_DELAY_MIN_SECONDS
		local maxv = tonumber(maxSeconds) or DEFAULT_NOON_DELAY_MAX_SECONDS
		if maxv < minv then
			minv, maxv = maxv, minv
		end
		minv = math.max(0, math.floor(minv))
		maxv = math.max(0, math.floor(maxv))
		if maxv <= minv then
			return minv
		end
		return math.random(minv, maxv)
	end

	local function EnsureMerchantDay(p, now)
		p.merchantGold = p.merchantGold or {}
		local mg = p.merchantGold

		local dk = DayKey(now)
		if mg.dayKey ~= dk then
			mg.dayKey = dk
			mg.today = 0
			mg.noonTickScheduled = nil
		end

		-- total lifetime (ne reset jamais)
		mg.total = tonumber(mg.total or 0) or 0
		mg.today = tonumber(mg.today or 0) or 0

		return mg
	end

	-- -----------------------------
	-- Écoute marchands + money
	-- -----------------------------
	local merchantOpen = false
	local lastMoney = nil

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		OnEvent = function(_, event)
			local now = pigAPI.Now()

			if event == "MERCHANT_SHOW" then
				merchantOpen = true
				lastMoney = GetMoney and GetMoney() or 0
				return
			end

			if event == "MERCHANT_CLOSED" then
				merchantOpen = false
				lastMoney = nil
				return
			end

			if event ~= "PLAYER_MONEY" or not merchantOpen then
				return
			end

			local money = GetMoney and GetMoney() or 0
			local base = lastMoney or money
			local delta = money - base
			lastMoney = money

			if delta == 0 then
				return
			end

			-- Si on veut ignorer les dépenses : ne compter que les deltas positifs (ventes)
			if CFG.countOnlyPositiveDeltas and delta <= 0 then
				return
			end

			local p = pigAPI.EnsurePlayer(pigAPI.GetMyUID())
			if not p then
				return
			end

			local mg = EnsureMerchantDay(p, now)

			mg.today = math.max(0, (tonumber(mg.today) or 0) + delta)
			mg.total = math.max(0, (tonumber(mg.total) or 0) + delta)

			p.updatedAt = now

			-- Si midi est passé : programme une publication rapide après la prochaine vente
			local last = pigAPI.GetModuleLast(p, MODULE_KEY)
			if last and C_Timer and C_Timer.After and not last.merchantGoldNoonScheduleAt then
				local dayStart = DayStart(now)
				local noonAt = dayStart + (tonumber(CFG.noonPublishSeconds) or DEFAULT_NOON_PUBLISH_SECONDS)
				if now >= noonAt then
					local delay = RandomDelaySeconds(CFG.noonDelayMinSeconds, CFG.noonDelayMaxSeconds)
					last.merchantGoldNoonScheduleAt = now + delay
					C_Timer.After(delay, function()
						TickJournalistSoon()
					end)
				end
			end

			-- Tick immédiat (coalescé)
			TickJournalistSoon()
		end,
	})
end

-- ==========================================================
-- 4) Helpers métier (purs)
-- ==========================================================

local function DayKey(ts)
	return date("%Y-%m-%d", ts)
end

local function DayStart(ts)
	local d = date("*t", ts)
	d.hour, d.min, d.sec = 0, 0, 0
	return time(d)
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

local function FormatMoney(copper)
	copper = tonumber(copper or 0) or 0
	if copper < 0 then
		copper = 0
	end

	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local copperOnly = copper % 100

	local parts = {}
	local function coin(value, atlas)
		return ("%d |A:%s:10:10:0:0|a"):format(value, atlas)
	end

	if gold > 0 then
		parts[#parts + 1] = coin(gold, "Coin-Gold")
	end
	if silver > 0 or (gold > 0 and copperOnly > 0) then
		parts[#parts + 1] = coin(silver, "Coin-Silver")
	end
	if copperOnly > 0 or #parts == 0 then
		parts[#parts + 1] = coin(copperOnly, "Coin-Copper")
	end

	return table.concat(parts, " ")
end

local function HasReplaceKey(g, rk)
	if not g or not g.news or not g.news.items then
		return false
	end
	for i = 1, #g.news.items do
		local n = g.news.items[i]
		if n and n.replaceKey == rk then
			return true
		end
	end
	return false
end

local function PeriodLabel(lastPostedAt, now)
	if not lastPostedAt or lastPostedAt <= 0 then
		return "aujourd'hui"
	end
	local delta = now - lastPostedAt
	if delta < 2 * 86400 then
		return "depuis hier"
	end
	if delta < 3 * 86400 then
		return "depuis avant-hier"
	end
	if delta < 7 * 86400 then
		return "dans la semaine"
	end
	if delta < 31 * 86400 then
		return "ce mois"
	end
	if delta < 365 * 86400 then
		return "cette année"
	end
	return "depuis la dernière fois"
end

local function AddRawNewsSafe(api, g, payload)
	if not api or type(api.AddRawNews) ~= "function" then
		return
	end

	-- Signature moderne (table payload)
	local ok = pcall(api.AddRawNews, g, payload)
	if ok then
		return true
	end

	-- Fallback signature “legacy” (si jamais)
	local text = payload.text
	local ntype = payload.type
	local icon = payload.icon
	local ts = payload.ts
	local replaceKey = payload.replaceKey
	local ttlSeconds = payload.ttlSeconds
	local replaceable = payload.replaceable
	local id = payload.id
	local removedAt = payload.removedAt

	return pcall(api.AddRawNews, g, text, ntype, icon, ts, replaceKey, ttlSeconds, replaceable, id, removedAt)
end

local function PostNews(api, g, uid, amount, now, lastPostedAt, replaceKey)
	local label = PeriodLabel(lastPostedAt, now)
	local playerName = GetPlayerDisplayNameSafe(api, uid)

	local tpl = (CFG.phrases and api.Pick and api.Pick(CFG.phrases))
		or (CFG.phrases and CFG.phrases[1])
		or "%s a gagné %s en vendant au marchand %s."

	local icon = (api.Pick and api.Pick(CFG.icons or DEFAULT_ICONS)) or (CFG.icons and CFG.icons[1]) or DEFAULT_ICONS[1]
	local msg = tpl:format(playerName, FormatMoney(amount), label)

	local removedAt = (api.GetRemovedAt and api.GetRemovedAt(MODULE_KEY, now)) or nil

	AddRawNewsSafe(api, g, {
		text = msg,
		type = MODULE_KEY,
		icon = icon,
		ts = now,

		replaceable = true,
		replaceKey = replaceKey,

		ttlSeconds = CFG.ttlSeconds,
		removedAt = removedAt,
		points = POINTS.loot or 3,
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

	local function ProcessMerchantGoldNews(g, intel, last, uid, now)
		if not CFG.enabled then
			return
		end

		-- ------------------------------------------------------
		-- A) Reset “par jour” (state module)
		-- ------------------------------------------------------
		local dk = DayKey(now)
		if last.merchantGoldDayKey ~= dk then
			last.merchantGoldDayKey = dk
			last.merchantGoldSeedPostedAt = nil
			last.merchantGoldNoonPostedAt = nil
			last.merchantGoldNoonScheduleAt = nil
		end

		-- ------------------------------------------------------
		-- B) Lecture intel
		-- ------------------------------------------------------
		local mg = intel and intel.merchantGold
		if not mg then
			return
		end

		-- Reset intel si day a changé (sécurité)
		if mg.dayKey ~= dk then
			mg.dayKey = dk
			mg.today = 0
			mg.noonTickScheduled = nil
		end

		local amount = tonumber(mg.today) or 0
		if amount <= 0 then
			return
		end

		local replaceKey = (CFG.replaceKeyPrefix or "merchantgold:daily:") .. tostring(uid)
		local hasNews = HasReplaceKey(g, replaceKey)

		-- ------------------------------------------------------
		-- C) Publication "après midi" : après 12:00, prochaine vente => news + reset
		-- ------------------------------------------------------
		local scheduleAt = tonumber(last.merchantGoldNoonScheduleAt) or 0
		local shouldNoon = scheduleAt > 0 and now >= scheduleAt and not last.merchantGoldNoonPostedAt

		if shouldNoon then
			PostNews(api, g, uid, amount, now, last.merchantGoldLastPostedAt, replaceKey)
			last.merchantGoldNoonPostedAt = now
			last.merchantGoldLastPostedAt = now
			last.merchantGoldNoonScheduleAt = nil
			mg.today = 0
			mg.noonTickScheduled = nil
			return
		end
	end

	-- Déclenchement piloté par Pigiste : le Journaliste ne devine rien.
	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessMerchantGoldNews,
	})
end
