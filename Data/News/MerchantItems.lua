-- ==========================================================
-- Merchant items module (refactor v12-style) — SOLD ICONS + D-1 recap
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

local EventBus = ns.EventBus

local MODULE_KEY = "merchantitems"
local PIGISTE_KEY = "merchantitems"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local QUALITIES = { 4, 3, 2, 1, 0 }
local QUALITY_LABELS = {
	[4] = "epik",
	[3] = "nadir",
	[2] = "sira disi",
	[1] = "sıradan",
	[0] = "dusuk",
}

local QUALITY_ATLAS = {
	[4] = "ui-frame-cypherchoice-portrait-fx-back-epic",
	[3] = "ui-frame-cypherchoice-portrait-fx-back-rare",
	[2] = "ui-frame-cypherchoice-portrait-fx-back-uncommon",
	[1] = "ui-frame-cypherchoice-portrait-fx-back-white",
	[0] = "ui-frame-cypherchoice-portrait-fx-back-white",
}

-- Fallback uniquement (si on n'arrive pas à résoudre une icône vendue)
local ICONS_FALLBACK = { 133784, 133785, 133786 }

local PHRASES = {
	"Paralar el degistirdi.",
	"Anlasma tamam, terazi dengede.",
	"Islem bozuk para sesleriyle mühurlendi.",
	"Altin konustu, is bitti.",
	"Satis tamam, herkes payini aldi.",
	"Tezgah bu satisi onayliyor.",
	"Anlasma tartismasiz kapandi.",
	"Degisim tamam, kupa yerine dönebilir.",
	"Tuccar gulusuyor, satis yapildi.",
	"Kayitlar temiz bir islem yaziyor.",
	"Altin el degistiriyor, yol devam ediyor.",
	"Anlasma sorunsuz tamamlandi.",
}

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================
-- Tout ce qui change souvent est ici. Le reste du fichier est le "moteur".
local CFG = {
	enabled = true,

	-- Événement interne utilisé pour déclencher le Journaliste (Pigiste -> Journalist.TickNow(event))
	triggerEvent = "MERCHANT_ITEMS_UPDATED",
	pigisteEvents = {
		MERCHANT_SHOW = true,
		MERCHANT_CLOSED = true,
	},
	triggerEvents = {
		"MERCHANT_ITEMS_UPDATED",
	},

	-- ReplaceKey : news quotidienne remplaçable (une seule ligne "vivante")
	replaceKey = "merchantitems:daily",

	-- Publication "après midi" : si 12:00 est passé, la prochaine vente programme une news
	noonPublishSeconds = 12 * 3600, -- 12:00
	noonDelayMinSeconds = 60, -- 1 min
	noonDelayMaxSeconds = 15 * 60, -- 15 min

	-- TTL (optionnel) : laisse nil pour TTL standard du Journaliste
	ttlSeconds = nil,

	-- Qualités suivies
	qualities = QUALITIES,
	qualityLabels = QUALITY_LABELS,
	qualityAtlas = QUALITY_ATLAS,

	-- Textes / visuels
	phrases = PHRASES,
	iconsFallback = ICONS_FALLBACK,

	-- Buckets : combien de jours max conservés en mémoire (sécurité)
	keepDays = 7,
}

-- ==========================================================
-- 2.8) Helpers techniques (compat & wrappers)
-- ==========================================================

local function SafeHooksecurefunc(a, b, c)
	local safe = ns and ns.Utils and ns.Utils.SafeHooksecurefunc
	if type(safe) == "function" then
		return safe(a, b, c)
	end

	if not hooksecurefunc then
		return
	end

	if type(a) == "table" and type(b) == "string" and type(c) == "function" then
		if type(a[b]) == "function" then
			hooksecurefunc(a, b, c)
		end
		return
	end

	if type(a) == "string" and type(b) == "function" then
		if type(_G[a]) == "function" then
			hooksecurefunc(a, b)
		end
		return
	end
end

local function GetPlayerDisplayNameSafe(api, uid)
	local n = api and api.GetPlayerDisplayName and api.GetPlayerDisplayName(uid) or nil
	if n and n ~= "" then
		return n
	end
	n = api and api.GetPlayerDisplayName and api.GetPlayerDisplayName() or nil
	if n and n ~= "" then
		return n
	end
	return uid and tostring(uid) or "Le joueur"
end

local function GetContainerItemLinkSafe(bag, slot)
	if C_Container and C_Container.GetContainerItemLink then
		return C_Container.GetContainerItemLink(bag, slot)
	end
	if GetContainerItemLink then
		return GetContainerItemLink(bag, slot)
	end
	return nil
end

local function GetContainerItemInfoSafe(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info then
			return {
				itemID = tonumber(info.itemID) or 0,
				stackCount = tonumber(info.stackCount) or 1,
				quality = info.quality,
			}
		end
		return nil
	end

	if GetContainerItemInfo then
		local _, stackCount, _, itemQuality, _, _, _, _, _, itemIDLegacy = GetContainerItemInfo(bag, slot)
		return {
			itemID = tonumber(itemIDLegacy) or 0,
			stackCount = tonumber(stackCount) or 1,
			quality = itemQuality,
		}
	end

	return nil
end

local function GetCursorItemLinkSafe()
	if not GetCursorInfo then
		return nil, 0
	end
	local kind, itemID, itemLink = GetCursorInfo()
	if kind ~= "item" then
		return nil, 0
	end
	local id = tonumber(itemID) or 0
	local link = itemLink
	if (not link or link == "") and id > 0 and C_Item and C_Item.GetItemLink then
		link = C_Item.GetItemLink(id)
	end
	return link, id
end

local function GetItemQualitySafe(pigapi, itemLink, itemID, fallbackQuality)
	local q = fallbackQuality
	if q == nil and pigapi and pigapi.GetItemInfoSafe then
		local _, qq = pigapi.GetItemInfoSafe(itemLink, itemID)
		q = qq
	end
	q = tonumber(q) or 0
	if CFG.qualityLabels[q] == nil then
		return nil
	end
	return q
end

local function GetItemIconFileIDSafe(itemLink, itemID)
	-- Best: GetItemInfoInstant (ne dépend pas du cache)
	if GetItemInfoInstant then
		local _, _, _, _, icon = GetItemInfoInstant(itemLink or itemID or 0)
		icon = tonumber(icon) or 0
		if icon > 0 then
			return icon
		end
	end

	-- Retail fallback
	if itemID and itemID > 0 and C_Item and C_Item.GetItemIconByID then
		local icon = C_Item.GetItemIconByID(itemID)
		icon = tonumber(icon) or 0
		if icon > 0 then
			return icon
		end
	end

	return 0
end

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

local function getDayKey(ts)
	return date("%Y-%m-%d", ts)
end

local function getDayStart(ts)
	local d = date("*t", ts)
	d.hour = 0
	d.min = 0
	d.sec = 0
	return time(d)
end

local function getYesterdayKey(ts)
	local d = date("*t", ts)
	d.hour = 0
	d.min = 0
	d.sec = 0
	d.day = d.day - 1
	return date("%Y-%m-%d", time(d))
end

local function EnsureCountsTable(t)
	t = t or {}
	t[0] = tonumber(t[0]) or 0
	t[1] = tonumber(t[1]) or 0
	t[2] = tonumber(t[2]) or 0
	t[3] = tonumber(t[3]) or 0
	t[4] = tonumber(t[4]) or 0
	return t
end

local function EnsureIconCountsTable(t)
	t = t or {}
	return t
end

local function totalCount(counts)
	local total = 0
	for i = 1, #CFG.qualities do
		local q = CFG.qualities[i]
		total = total + (tonumber(counts[q]) or 0)
	end
	return total
end

local function qualityLine(q, count)
	local atlas = CFG.qualityAtlas[q]
	local tex = atlas and ("|A:%s:10:10:0:0|a "):format(atlas) or ""
	local label = CFG.qualityLabels[q] or ""
	local plural = (count > 1) and "s" or ""
	return ("%s%d objet%s %s"):format(tex, count, plural, label)
end

local function dayLabelForKey(bucketKey, now)
	local todayKey = getDayKey(now)
	if bucketKey == todayKey then
		return "aujourd'hui"
	end
	if bucketKey == getYesterdayKey(now) then
		return "hier"
	end
	return ("le %s"):format(bucketKey)
end

local function HasReplaceKey(api, g, rk)
	if api and api.HasReplaceKey then
		local ok, res = pcall(api.HasReplaceKey, g, rk)
		if ok then
			return res and true or false
		end
	end
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

local function RemoveByReplaceKey(api, g, rk)
	if api and api.RemoveNewsByReplaceKey then
		pcall(api.RemoveNewsByReplaceKey, g, rk)
		return
	end
	if api and api.RemoveByReplaceKey then
		pcall(api.RemoveByReplaceKey, g, rk)
		return
	end
end

local function AddRawNewsCompat(api, g, payload)
	if api and api.AddRawNews then
		local ok = pcall(api.AddRawNews, g, payload)
		if ok then
			return true
		end
	end

	if api and api.AddRawNews then
		local text = payload.text
		local typeKey = payload.type
		local icon = payload.icon
		local ts = payload.ts
		local replaceKey = payload.replaceKey
		local ttl = payload.ttlSeconds
		local replaceable = payload.replaceable
		local id = payload.id
		local removedAt = payload.removedAt

		pcall(api.AddRawNews, g, text, typeKey, icon, ts, replaceKey, ttl, replaceable, id, removedAt)
		return true
	end

	return false
end

local function GetRemovedAtCompat(api, typeKey, now)
	if api and api.GetRemovedAt then
		local ok, res = pcall(api.GetRemovedAt, typeKey, now)
		if ok then
			return res
		end
	end
	return nil
end

-- ==========================================================
-- 2.9) Buckets (accumulation jour -> post J+1)
-- ==========================================================

local function EnsureMerchantRoot(intel)
	intel.merchantitems = intel.merchantitems or {}
	local mi = intel.merchantitems
	mi.buckets = mi.buckets or {}
	return mi
end

local function EnsureBucket(mi, dayKey)
	local b = mi.buckets[dayKey]
	if not b then
		b = {
			dayKey = dayKey,
			counts = EnsureCountsTable(nil),
			iconCounts = EnsureIconCountsTable(nil), -- [iconFileID] = totalQty
			firstSaleAt = nil,
			updatedAt = nil,
		}
		mi.buckets[dayKey] = b
	else
		b.counts = EnsureCountsTable(b.counts)
		b.iconCounts = EnsureIconCountsTable(b.iconCounts)
	end
	return b
end

local function CleanupOldBuckets(mi, now)
	local keepDays = tonumber(CFG.keepDays) or 7
	if keepDays <= 0 then
		return
	end
	local cutoffStart = getDayStart(now) - (keepDays * 86400)

	for k, b in pairs(mi.buckets) do
		if type(b) == "table" then
			local dk = b.dayKey or k
			local ts = nil
			-- essaye de reconstruire un timestamp à partir de la clé
			if type(dk) == "string" then
				local y, m, d = dk:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
				if y and m and d then
					ts =
						time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0, min = 0, sec = 0 })
				end
			end
			if ts and ts < cutoffStart then
				mi.buckets[k] = nil
			end
		end
	end
end

local function PickRandomIconFromCounts(api, iconCounts)
	-- iconCounts : [iconFileID] = qty
	local total = 0
	for icon, qty in pairs(iconCounts or {}) do
		icon = tonumber(icon) or 0
		qty = tonumber(qty) or 0
		if icon > 0 and qty > 0 then
			total = total + qty
		end
	end

	if total <= 0 then
		-- fallback
		return (api and api.Pick and api.Pick(CFG.iconsFallback))
			or (CFG.iconsFallback and CFG.iconsFallback[1])
			or 133784
	end

	local r = math.random(1, total)
	local acc = 0
	for icon, qty in pairs(iconCounts) do
		icon = tonumber(icon) or 0
		qty = tonumber(qty) or 0
		if icon > 0 and qty > 0 then
			acc = acc + qty
			if r <= acc then
				return icon
			end
		end
	end

	-- ultra fallback
	return (api and api.Pick and api.Pick(CFG.iconsFallback)) or (CFG.iconsFallback and CFG.iconsFallback[1]) or 133784
end

-- ==========================================================
-- 3) Pigiste – collecte des événements
-- ==========================================================

do
	local Pigiste = Data.Pigiste
	local pigapi = Data.PigisteAPI
	if not Pigiste or not pigapi then
		return
	end

	local merchantOpen = false
	local hooked = false

	-- Tick coalescé
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

	local function EnsureNoonScheduleState(last, now)
		local dayKey = getDayKey(now)
		if last.merchantItemsNoonDayKey ~= dayKey then
			last.merchantItemsNoonDayKey = dayKey
			last.merchantItemsNoonScheduleAt = nil
			last.merchantItemsNoonPostedAt = nil
			last._merchantItemsNoonToken = (tonumber(last._merchantItemsNoonToken) or 0) + 1
			last._merchantItemsNoonArmedFor = nil
		end
	end

	local function ArmNoonTimer(last, now)
		if not (C_Timer and C_Timer.After) then
			return
		end

		local scheduleAt = tonumber(last.merchantItemsNoonScheduleAt) or 0
		if scheduleAt <= 0 then
			return
		end

		-- si déjà posté pour ce scheduleAt, inutile de ré-armer
		if last.merchantItemsNoonPostedAt and tonumber(last.merchantItemsNoonPostedAt) >= scheduleAt then
			return
		end

		if last._merchantItemsNoonArmedFor == scheduleAt then
			return
		end

		last._merchantItemsNoonArmedFor = scheduleAt
		local token = tonumber(last._merchantItemsNoonToken) or 0
		local delay = scheduleAt - now
		if delay < 0 then
			delay = 0
		end

		C_Timer.After(delay, function()
			if (tonumber(last._merchantItemsNoonToken) or 0) ~= token then
				return
			end
			TickJournalistSoon()
		end)
	end

	local function RecordDelta(quality, deltaCount, iconFileID)
		local p = pigapi.EnsurePlayer(pigapi.GetMyUID())
		if not p then
			return
		end

		local now = pigapi.Now()
		local dayKey = getDayKey(now)

		local mi = EnsureMerchantRoot(p)
		CleanupOldBuckets(mi, now)

		local b = EnsureBucket(mi, dayKey)

		if not b.firstSaleAt and deltaCount > 0 then
			b.firstSaleAt = now
		end

		b.counts = EnsureCountsTable(b.counts)
		b.counts[quality] = math.max(0, (tonumber(b.counts[quality]) or 0) + (tonumber(deltaCount) or 0))

		-- iconCounts (pondéré par quantité)
		local icon = tonumber(iconFileID) or 0
		if icon > 0 then
			b.iconCounts = EnsureIconCountsTable(b.iconCounts)
			local cur = tonumber(b.iconCounts[icon]) or 0
			local nextv = cur + (tonumber(deltaCount) or 0)
			if nextv <= 0 then
				b.iconCounts[icon] = nil
			else
				b.iconCounts[icon] = nextv
			end
		end

		b.updatedAt = now

		-- timers/schedule
		local last = pigapi.GetModuleLast(p, MODULE_KEY)
		EnsureNoonScheduleState(last, now)
		local dayStart = getDayStart(now)
		local noonAt = dayStart + (tonumber(CFG.noonPublishSeconds) or 12 * 3600)
		if now >= noonAt and not last.merchantItemsNoonScheduleAt and not last.merchantItemsNoonPostedAt then
			local delay = RandomDelaySeconds(CFG.noonDelayMinSeconds, CFG.noonDelayMaxSeconds)
			last.merchantItemsNoonScheduleAt = now + delay
			ArmNoonTimer(last, now)
		end

		p.updatedAt = now
		TickJournalistSoon()
	end

	local function handleSellFromBagSlot(bag, slot)
		if not merchantOpen or bag == nil or slot == nil then
			return
		end

		local itemLink = GetContainerItemLinkSafe(bag, slot)
		if not itemLink then
			return
		end

		local info = GetContainerItemInfoSafe(bag, slot) or {}
		local itemID = tonumber(info.itemID) or 0
		local count = tonumber(info.stackCount) or 1
		local quality = GetItemQualitySafe(pigapi, itemLink, itemID, info.quality)
		if not quality then
			return
		end

		local icon = GetItemIconFileIDSafe(itemLink, itemID)
		RecordDelta(quality, count, icon)
	end

	local function handleSellFromCursor()
		if not merchantOpen then
			return
		end

		local itemLink, itemID = GetCursorItemLinkSafe()
		if not itemLink then
			return
		end

		local quality = GetItemQualitySafe(pigapi, itemLink, itemID, nil)
		if not quality then
			return
		end

		local icon = GetItemIconFileIDSafe(itemLink, itemID)
		RecordDelta(quality, 1, icon)
	end

	local function handleBuyback(slot)
		if not merchantOpen or not slot then
			return
		end
		if not GetBuybackItemLink then
			return
		end

		local itemLink = GetBuybackItemLink(slot)
		if not itemLink then
			return
		end

		local qty = 1
		if GetBuybackItemInfo then
			local _, _, _, quantity = GetBuybackItemInfo(slot)
			qty = tonumber(quantity) or 1
		end

		local itemID = 0
		if GetItemInfoInstant then
			itemID = tonumber(select(1, GetItemInfoInstant(itemLink)) or 0) or 0
		end

		local quality = GetItemQualitySafe(pigapi, itemLink, itemID, nil)
		if not quality then
			return
		end

		local icon = GetItemIconFileIDSafe(itemLink, itemID)
		RecordDelta(quality, -qty, icon)
	end

	local function hookMerchantTracking()
		if hooked then
			return
		end
		hooked = true

		if C_Container and C_Container.UseContainerItem then
			SafeHooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
				handleSellFromBagSlot(bag, slot)
			end)
		elseif UseContainerItem then
			SafeHooksecurefunc("UseContainerItem", function(bag, slot)
				handleSellFromBagSlot(bag, slot)
			end)
		end

		if SellCursorItem then
			SafeHooksecurefunc("SellCursorItem", function()
				handleSellFromCursor()
			end)
		end

		if BuybackItem then
			SafeHooksecurefunc("BuybackItem", function(slot)
				handleBuyback(slot)
			end)
		end
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		OnInit = function()
			if IsLoggedIn and IsLoggedIn() then
				hookMerchantTracking()
			elseif EventBus and EventBus.On then
				EventBus.On("PLAYER_LOGIN", function()
					hookMerchantTracking()
				end)
			else
				hookMerchantTracking()
			end
		end,

		OnEvent = function(_, event)
			if event == "MERCHANT_SHOW" then
				merchantOpen = true
				return
			end
			if event == "MERCHANT_CLOSED" then
				merchantOpen = false
				return
			end
		end,
	})
end

-- ==========================================================
-- 4) Helpers métier (purs)
-- ==========================================================

local function BuildMessage(api, playerName, bucketKey, counts, now)
	local label = dayLabelForKey(bucketKey, now)

	local lines = {}
	for i = 1, #CFG.qualities do
		local q = CFG.qualities[i]
		local count = tonumber(counts[q] or 0) or 0
		if count > 0 then
			lines[#lines + 1] = qualityLine(q, count)
		end
	end
	if #lines == 0 then
		return nil
	end

	lines[#lines + 1] = (api and api.Pick and api.Pick(CFG.phrases))
		or (CFG.phrases and CFG.phrases[1])
		or "Vente parfaitement exécutée."

	return ("%s a fait tourner le comptoir %s :\n%s"):format(playerName, label, table.concat(lines, "\n"))
end

local function RemoveBucket(intel, bucketKey)
	if not intel or not intel.merchantitems or not intel.merchantitems.buckets then
		return
	end
	intel.merchantitems.buckets[bucketKey] = nil
end

local function PostNewsFromBucket(api, g, uid, intel, now, last, bucketKey, bucket)
	local counts = EnsureCountsTable(bucket and bucket.counts or nil)
	if totalCount(counts) <= 0 then
		return false
	end

	local playerName = GetPlayerDisplayNameSafe(api, uid)
	local msg = BuildMessage(api, playerName, bucketKey, counts, now)
	if not msg then
		return false
	end

	-- Une seule ligne vivante (remplace la précédente)
	RemoveByReplaceKey(api, g, CFG.replaceKey)

	local icon = PickRandomIconFromCounts(api, bucket and bucket.iconCounts or nil)

	local payload = {
		text = msg,
		type = MODULE_KEY,
		icon = icon,
		ts = now,

		replaceable = true,
		replaceKey = CFG.replaceKey,

		ttlSeconds = CFG.ttlSeconds,
		removedAt = GetRemovedAtCompat(api, MODULE_KEY, now),
		points = POINTS.loot or 3,
	}

	AddRawNewsCompat(api, g, payload)

	-- Reset : bucket consommé => compteur revient à 0 pour cette période
	RemoveBucket(intel, bucketKey)

	return true
end

-- ==========================================================
-- 5) News processor (récap J-1 au schedule)
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

	local function ProcessMerchantItemsNews(g, intel, last, uid, now)
		if not CFG.enabled or not intel then
			return
		end

		-- reset / jour
		local todayKey = getDayKey(now)
		if last.merchantItemsNoonDayKey ~= todayKey then
			last.merchantItemsNoonDayKey = todayKey
			last.merchantItemsNoonScheduleAt = nil
			last.merchantItemsNoonPostedAt = nil
			last._merchantItemsNoonToken = (tonumber(last._merchantItemsNoonToken) or 0) + 1
			last._merchantItemsNoonArmedFor = nil
		end

		local scheduleAt = tonumber(last.merchantItemsNoonScheduleAt) or 0
		local alreadyPosted = last.merchantItemsNoonPostedAt
			and tonumber(last.merchantItemsNoonPostedAt) >= scheduleAt

		-- On poste uniquement à partir du schedule (même si en retard), et une fois
		if scheduleAt <= 0 or now < scheduleAt or alreadyPosted then
			return
		end

		-- On publie le bucket d'aujourd'hui (après midi)
		local bucketKey = todayKey

		local mi = EnsureMerchantRoot(intel)
		CleanupOldBuckets(mi, now)

		local bucket = mi.buckets and mi.buckets[bucketKey] or nil
		if not bucket then
			-- rien à publier
			last.merchantItemsNoonPostedAt = now
			last.merchantItemsNoonScheduleAt = nil
			return
		end

		local counts = EnsureCountsTable(bucket.counts)
		if totalCount(counts) <= 0 then
			-- bucket vide => consume quand même
			RemoveBucket(intel, bucketKey)
			last.merchantItemsNoonPostedAt = now
			last.merchantItemsNoonScheduleAt = nil
			return
		end

		-- Optionnel : s'assurer qu'il y a déjà une ligne vivante ou pas — peu importe, on replace
		-- local hasNews = HasReplaceKey(api, g, CFG.replaceKey)

		if PostNewsFromBucket(api, g, uid, intel, now, last, bucketKey, bucket) then
			last.merchantItemsNoonPostedAt = now
			last.merchantItemsNoonScheduleAt = nil
		else
			-- évite spam de tentatives
			last.merchantItemsNoonPostedAt = now
			last.merchantItemsNoonScheduleAt = nil
		end
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessMerchantItemsNews,
	})
end
