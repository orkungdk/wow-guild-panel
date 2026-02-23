-- ==========================================================
-- Distance module (points/km + 5 tiers)
-- - Échantillonnage léger en “continu” (ticker) uniquement quand tu bouges
-- - Anti-jitter + anti-teleport
-- - Archivage “hier” au changement de jour (minuit) + reset today
-- - Publication après midi (delay random) + heartbeat fiable
-- - Points = km / 100  (ex: 320 km => 3.2 points)
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end

local MODULE_KEY = "distance"
local PIGISTE_KEY = "distance"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local DAY_SECONDS = 24 * 3600

local ICONS = {
	132296, -- boots
	348567, -- mount/hoof-ish
	571558, -- travel
	538536, -- sprint-ish
	135788, -- run/boot
}

-- ⚠️ UnitPosition renvoie des unités “jeu” (souvent des yards).
-- Si tu veux des mètres réels, mets 0.9144.
local UNIT_TO_METERS = 1.0 -- 0.9144

-- Ticker “continu” (léger) : 1 sample/sec quand tu bouges
local TICK_SECONDS = 1.0

-- Filtrage bruit / téléport / chargement
local MIN_STEP_METERS = 0.75 -- ignore micro-jitter
local MAX_STEP_METERS = 120.0 -- au-delà => saut (portail/chargement)

-- Heartbeat NewsRegistry (permet de publier même sans rebouger)
local NEWS_HEARTBEAT_SECONDS = 30

-- Points: 1 km = 0.01 points
local POINTS_PER_KM = 1 / 100

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================

local CFG = {
	enabled = true,

	-- Events utilisés pour init / start-stop ticker / changements de zone
	pigisteEvents = {
		PLAYER_ENTERING_WORLD = true,
		PLAYER_STARTED_MOVING = true,
		PLAYER_STOPPED_MOVING = true,
		ZONE_CHANGED = true,
		ZONE_CHANGED_NEW_AREA = true,
		PLAYER_LOGOUT = true,
	},

	-- Fenêtre / publication
	window = {
		seconds = DAY_SECONDS,
		ttlSeconds = DAY_SECONDS,
		replaceKeyPrefix = "distance:",
		label = "hier",

		-- Publication après midi : random delay dès que l’horloge a passé 12:00
		noonPublishSeconds = 12 * 3600, -- 12:00
		noonDelayMinSeconds = 60, -- 1 min
		noonDelayMaxSeconds = 15 * 60, -- 15 min
	},

	-- 5 niveaux : marcher -> marathon
	tiers = {
		{
			minMeters = 250,
			icons = ICONS,
			phrases = {
				"%s a juste marché %s %s. Tranquille, pépouze.",
				"%s a pris l’air : %s %s. Les bottes sont contentes.",
				"%s a fait une petite balade de %s %s. Ça compte.",
				"%s a ajouté %s %s au compteur. Sans forcer.",
				"%s a déroulé %s %s. Le sol a noté.",
			},
		},
		{
			minMeters = 2000,
			icons = ICONS,
			phrases = {
				"%s a bien marché : %s %s. Ça commence à faire.",
				"%s a tracé %s %s, l’air de rien.",
				"%s a marché %s %s. Les semelles applaudissent.",
				"%s a fait chauffer le chemin sur %s %s.",
				"%s a pris la tangente sur %s %s. Hop.",
			},
		},
		{
			minMeters = 8000,
			icons = ICONS,
			phrases = {
				"%s est passé en mode footing : %s %s. On entend le souffle.",
				"%s a trotiné un bon moment : %s %s. Volontairement.",
				"%s a filé %s %s. Le décor défile encore.",
				"%s a fait %s %s à bon rythme. Ça trotte !",
				"%s a trotiné sur %s %s comme si c’était rien.",
			},
		},
		{
			minMeters = 21000, -- semi-marathon-ish
			icons = ICONS,
			phrases = {
				"%s a quasi signé un semi-marathon : %s %s. Respect aux mollets.",
				"%s a transformé %s %s en longue sortie. Ses pieds demandent une pause.",
				"%s a tenu la distance : %s %s. Mental d’acier, lacets serrés.",
				"%s a courru %s %s. Même la carte dit “ok wow”.",
				"%s a fait une sacrée sortie : %s %s. Ça sent l’endurance.",
			},
		},
		{
			minMeters = 42195, -- marathon
			icons = ICONS,
			phrases = {
				"%s a fait un marathon (oui, vraiment) : %s %s. Légendaire.",
				"%s a bouclé une distance de marathon : %s %s. Ses bottes sont en feu…",
				"%s a couru la distance d’un marathon : %s %s. On sort les médailles.",
				"%s a transformé la journée en marathon : %s %s. Rien que ça.",
				"%s a signé le marathon : %s %s. La route s’incline.",
			},
		},
	},
}

-- ==========================================================
-- 3) Helpers métier (purs)
-- ==========================================================

local function RandomDelaySeconds(minSeconds, maxSeconds)
	local minv = tonumber(minSeconds) or 60
	local maxv = tonumber(maxSeconds) or (15 * 60)
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

local function FormatDistance(meters)
	meters = tonumber(meters or 0) or 0
	if meters < 1000 then
		return ("%d m"):format(math.floor(meters))
	end

	local km = meters / 1000
	if km < 10 then
		return ("%.1f km"):format(km)
	end
	if km < 100 then
		return ("%.1f km"):format(km)
	end
	return ("%d km"):format(math.floor(km + 0.5))
end

local function ComputePointsFromMeters(meters)
	meters = tonumber(meters or 0) or 0
	local km = meters / 1000
	local pts = km * POINTS_PER_KM
	-- arrondi à 2 décimales (1 km => 0.01)
	return math.floor(pts * 100 + 0.5) / 100
end

local function PickTier(meters)
	meters = tonumber(meters or 0) or 0
	local best = nil
	local tiers = CFG.tiers or {}
	for i = 1, #tiers do
		local t = tiers[i]
		local minM = tonumber(t and t.minMeters) or 0
		if meters >= minM then
			if (not best) or minM > (tonumber(best.minMeters) or 0) then
				best = t
			end
		end
	end
	return best
end

-- ==========================================================
-- 4) Pigiste – collecte (ticker léger)
-- ==========================================================

do
	local Pigiste = Data.Pigiste
	local pigAPI = Data.PigisteAPI
	if not Pigiste or not pigAPI then
		return
	end

	local function GetPlayerPosition()
		if not UnitPosition then
			return
		end
		local x, y, z, mapID = UnitPosition("player")
		if not x or not y then
			return
		end
		return mapID, x, y, z
	end

	local function StopTicker(d)
		if d and d._ticker and d._ticker.Cancel then
			d._ticker:Cancel()
		end
		d._ticker = nil

		if d and d._tickerFrame then
			d._tickerFrame:SetScript("OnUpdate", nil)
			d._tickerFrame = nil
		end
	end

	local function StartTicker(d, cb)
		if not d or d._ticker or d._tickerFrame then
			return
		end

		if C_Timer and C_Timer.NewTicker then
			d._ticker = C_Timer.NewTicker(TICK_SECONDS, cb)
			return
		end

		if CreateFrame then
			local f = CreateFrame("Frame")
			f._acc = 0
			f:SetScript("OnUpdate", function(_, elapsed)
				f._acc = (f._acc or 0) + (tonumber(elapsed) or 0)
				if f._acc >= TICK_SECONDS then
					f._acc = 0
					cb()
				end
			end)
			d._tickerFrame = f
		end
	end

	local function EnsureDailyReset(d, now)
		local dayKey = math.floor((tonumber(now) or 0) / DAY_SECONDS)
		if d.dayKey ~= dayKey then
			-- archive "hier" si on avait déjà un jour précédent
			if d.dayKey ~= nil then
				d.yesterdayDayKey = d.dayKey
				d.yesterdayMeters = tonumber(d.todayMeters) or 0
			end

			d.dayKey = dayKey
			d.todayMeters = 0
			d.startedAt = now
			d.updatedAt = now

			-- reset last pos (sera fixée au prochain sample)
			d.lastX, d.lastY, d.lastMapID = nil, nil, nil
		end
	end

	local function Sample(p, d, now)
		local mapID, x, y = GetPlayerPosition()
		if not mapID or not x or not y then
			return
		end

		EnsureDailyReset(d, now)

		if not d.lastX or not d.lastY or d.lastMapID ~= mapID then
			d.lastX = x
			d.lastY = y
			d.lastMapID = mapID
			d.startedAt = d.startedAt or now
			return
		end

		local dx = x - d.lastX
		local dy = y - d.lastY
		local delta = math.sqrt(dx * dx + dy * dy) * UNIT_TO_METERS

		d.lastX = x
		d.lastY = y
		d.lastMapID = mapID

		if delta < MIN_STEP_METERS then
			return
		end

		if delta > MAX_STEP_METERS then
			return
		end

		d.todayMeters = (tonumber(d.todayMeters) or 0) + delta
		d.updatedAt = now

		-- champ de déclenchement pour NewsRegistry
		local l = pigAPI.GetModuleLast(p, MODULE_KEY)
		l.distanceAt = now

		p.updatedAt = now
	end

	local function RefreshTickerState(p, d)
		if not CFG.enabled then
			StopTicker(d)
			return
		end

		local moving = (IsPlayerMoving and IsPlayerMoving()) or false
		if moving then
			StartTicker(d, function()
				local _now = pigAPI.Now()
				Sample(p, d, _now)
			end)
		else
			StopTicker(d)
		end
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		OnEvent = function(...)
			local event = select(1, ...)
			if type(event) ~= "string" then
				event = nil
			end

			local p = pigAPI.EnsurePlayer(pigAPI.GetMyUID())
			if not p then
				return
			end

			p.distance = p.distance or {}
			local d = p.distance
			local now = pigAPI.Now()

			if event == "PLAYER_LOGOUT" then
				StopTicker(d)
				return
			end

			EnsureDailyReset(d, now)

			-- sample immédiat
			Sample(p, d, now)

			-- start/stop ticker
			RefreshTickerState(p, d)
		end,
	})
end

-- ==========================================================
-- 5) News processor (points/km + "hier")
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

	local function GetDistanceAt(intel)
		if not intel then
			return nil
		end
		if intel.last and intel.last.distanceAt then
			return intel.last.distanceAt
		end
		return intel.distanceAt
	end

	local function ProcessDistanceNews(g, intel, last, uid, now)
		if not CFG.enabled then
			return
		end

		local dist = intel and intel.distance
		if not dist then
			return
		end

		now = tonumber(now) or 0
		local dayKey = math.floor(now / DAY_SECONDS)

		-- reset schedule chaque nouveau jour (le schedule concerne la journée en cours)
		if last.distanceScheduleDayKey ~= dayKey then
			last.distanceScheduleDayKey = dayKey
			last.distanceScheduleAt = nil
		end

		-- On publie "hier" (archivé au reset journalier)
		local yKey = tonumber(dist.yesterdayDayKey)
		local yMeters = tonumber(dist.yesterdayMeters) or 0
		if not yKey or yKey >= dayKey then
			return
		end

		-- gate après midi
		local dayStart = dayKey * DAY_SECONDS
		local noonAt = dayStart + (tonumber(CFG.window.noonPublishSeconds) or 12 * 3600)
		if now < noonAt then
			return
		end

		-- schedule random delay (une fois)
		if not last.distanceScheduleAt then
			local delay = RandomDelaySeconds(CFG.window.noonDelayMinSeconds, CFG.window.noonDelayMaxSeconds)
			last.distanceScheduleAt = now + delay
		end

		if now < (tonumber(last.distanceScheduleAt) or 0) then
			return
		end

		-- Anti-spam : 1 news max par "hier"
		if last.distancePostedYesterdayKey == yKey then
			return
		end

		local tier = PickTier(yMeters)
		if not tier then
			return
		end

		local playerName = (api.GetPlayerDisplayName and api.GetPlayerDisplayName(uid))
			or (api.GetPlayerDisplayName and api.GetPlayerDisplayName())
			or tostring(uid)

		local phr = tier.phrases or {}
		local phrase = (api.Pick and api.Pick(phr)) or phr[1] or "%s a marché %s %s."

		local msg = phrase:format(playerName, FormatDistance(yMeters), CFG.window.label or "")

		local icons = tier.icons or ICONS
		local icon = (api.Pick and api.Pick(icons)) or ICONS[1]

		local points = ComputePointsFromMeters(yMeters)

		api.AddRawNews(g, {
			text = msg,
			type = "world",
			icon = icon,
			ts = now,
			replaceable = true,
			replaceKey = (CFG.window.replaceKeyPrefix or "distance:") .. tostring(uid),
			ttlSeconds = CFG.window.ttlSeconds,
			points = points,
		})

		-- Marque comme publié + purge "hier" (on garde today intact)
		last.distancePostedYesterdayKey = yKey
		dist.yesterdayDayKey = nil
		dist.yesterdayMeters = 0
	end

	-- Trigger robuste :
	-- - run quand distanceAt change (mouvement)
	-- - + heartbeat toutes les 30s
	local function TriggerDistance(intel, last, uid, now)
		if not CFG.enabled then
			return false
		end

		local dist = intel and intel.distance
		if not dist then
			return false
		end

		now = tonumber(now) or 0

		local distanceAt = GetDistanceAt(intel)
		if distanceAt and distanceAt ~= last._seenDistanceAt then
			last._seenDistanceAt = distanceAt
			return true
		end

		local hb = tonumber(last._hbAt) or 0
		if (now - hb) >= NEWS_HEARTBEAT_SECONDS then
			last._hbAt = now
			return true
		end

		return false
	end

	registry.Register(MODULE_KEY, {
		trigger = TriggerDistance,
		run = ProcessDistanceNews,
	})
end
