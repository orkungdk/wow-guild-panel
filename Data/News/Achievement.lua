-- ==========================================================
-- Achievements module
-- ==========================================================

local ADDON, ns = ...

-- ==========================================================
-- 1) Bootstrap & identité
-- ==========================================================

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { achievement = 5 }

local MODULE_KEY = "achievement"
local PIGISTE_KEY = "achievements"

-- ==========================================================
-- 2) Constantes
-- ==========================================================

local WINDOW_SECONDS = (Data.JournalistAPI and Data.JournalistAPI.WindowSeconds) or (48 * 3600)

-- News "par HF" (non remplaçable, durée standard)
local MODULE_KEY_EACH = "achievement_each"

local ICONS = { 134059, 134063, 134064 }

-- ==========================================================
-- 2.5) Configurateur (power-ups)
-- ==========================================================
-- Tout ce qui change souvent est ici. Le reste du fichier est le "moteur".
local CFG = {
	-- Activation des deux sorties
	enabled = {
		each = true, -- 1 news par HF
		window = false, -- 1 news agrégée 48h
	},

	-- Event de déclenchement (piloté par Pigiste -> Journalist.TickNow(event))
	triggerEvent = "ACHIEVEMENT_EARNED",
	pigisteEvents = {
		ACHIEVEMENT_EARNED = true,
	},
	triggerEvents = {
		"ACHIEVEMENT_EARNED",
	},

	-- Règles de la fenêtre 48h
	window = {
		seconds = WINDOW_SECONDS, -- durée de la fenêtre d'analyse
		minCount = 3, -- déclenchement à partir du 3e HF dans la fenêtre
		ttlSeconds = WINDOW_SECONDS, -- péremption max de la news agrégée
		replaceKeyPrefix = "achievement48:", -- remplaçable par joueur (prefix + uid)

		-- Fallback si phrases bos ise
		message = "%s son 2 gunde %d basari tamamladi. Ozet:\n%s.",

		-- Phrases (kisa bar hikayeleri): (playerName, count, display)
		phrases = {
			"%s 48 saat icinde %d kez kadere meydan okudu. Ozellikle su basari konusuluyor:\n%s.",
			"%s iki gunde destanina %d satir ekledi. En cok bu satir dikkat cekti:\n%s.",
			"%s 48 saatte %d basari yigdi, kronikler hala sayiyor. Ozet:\n%s.",
			"%s iki gunde tarihe %d kez iz birakti. Meyhaneler su basaridan bahsediyor:\n%s.",
			"%s 48 saatte %d yuksek basari demirledi, duvarlari titreten ise su oldu:\n%s.",
			"%s iki gunde imkansizin sinirlarini %d kez zorlayip, en cok su basariyla anildi:\n%s.",
			"%s iki gunde destanina %d yeni bolum ekledi. Sarkiya donusen bolum:\n%s.",
			"%s iki gunde kaderin ipinde %d iz birakti. Ozet:\n%s.",
			"%s 48 saatte %d kahramanlik hikayesi yazdi, eskilerin hala güldüğü ise su:\n%s.",
			"%s iki gunde %d basari kazandi. Arsivler en azindan bunu kabul ediyor:\n%s.",
		},
	},

	-- Règles news "par HF"
	each = {
		-- TTL standard : laisse nil pour utiliser le TTL par défaut du Journaliste
		ttlSeconds = nil,
		idPrefix = "achievement:",

		-- Fallback si phrases bos ise
		message = "%s su basariyi tamamladi:\n%s.",

		-- Phrases (bar cumleleri): (playerName, display)
		phrases = {
			"Meyhaneci yemin ediyor, %s destanina su satiri ekledi:\n%s.",
			"Odadaki fisiltida %s icin yeni bir satir eklendiginden bahsediliyor:\n%s.",
			"%s masaya yeni bir kup koydu. Adi da su:\n%s.",
			"Kayit defterleri sallandi, %s su basariyi kazandiginda:\n%s.",
			"%s bu pargamentte kara harflerle yazilan yeni bir basari imzaladi:\n%s.",
			"Mudahimlar baslarini salliyor, %s yine su basariyla vurdu:\n%s.",
			"Meyhanenin bir kosesinden biri bagirdi, %s basardi:\n%s.",
			"Yazici goz kirpmadan not dustu: %s simdi su basariya sahip:\n%s.",
			"%s kendi destanina bir kup daha ekledi:\n%s.",
		},
	},

	-- Choix du HF mis en avant dans la news 48h (on scanne toute la fenêtre)
	highlight = {
		-- Ordre de priorité : tour de force > points > récent
		preferFeat = true,
		preferPoints = true,
		preferRecent = true,
	},

	-- Résolution icône/lien (icône du HF uniquement)
	resolve = {
		useResolveAchievementInfo = false, -- pas de reinterpretation
	},
}

local function GetAchievementInfoSafe(id)
	if not id then
		return
	end

	local name, points, flags, icon
	local t = { GetAchievementInfo(id) }

	-- Compat: certaines versions renvoient (id, name, points, ...).
	if type(t[1]) == "number" and type(t[2]) == "string" then
		name = t[2]
		points = t[3]
		flags = t[9]
		icon = t[10]
	else
		name = t[1]
		points = t[2]
		flags = t[8]
		icon = t[9]
	end

	if C_AchievementInfo and C_AchievementInfo.GetAchievementInfo then
		local info = C_AchievementInfo.GetAchievementInfo(id)
		if info then
			name = info.name or name
			points = info.points or points
			flags = info.flags or flags
			icon = info.iconFileID or info.icon
		end
	end

	icon = tonumber(icon) or 0
	return name, points, icon, flags
end

-- ==========================================================
-- 3) Pigiste – collecte des événements
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
				-- Journaliste doit filtrer sur l'event (trigger.events côté NewsRegistry)
				Journalist.TickNow(CFG.triggerEvent)
			end
		end

		if C_Timer and C_Timer.After then
			-- 0 = prochain frame : regroupe les rafales
			C_Timer.After(0, doTick)
		else
			doTick()
		end
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,

		OnEvent = function(_, _, id)
			if not id then
				return
			end

			local name, points, icon, flags = GetAchievementInfoSafe(id)

			local isFeat = false
			if flags and ACHIEVEMENT_FLAGS_FEAT_OF_STRENGTH and bit and bit.band then
				isFeat = bit.band(flags, ACHIEVEMENT_FLAGS_FEAT_OF_STRENGTH) > 0
			end

			local p = pigAPI.EnsurePlayer(pigAPI.GetMyUID())
			if not p then
				return
			end

			-- (sécurité) structure attendue
			p.achievements = p.achievements or {}
			p.achievements.list = p.achievements.list or {}
			p.achievements.interesting = p.achievements.interesting or {}

			local ts = pigAPI.Now()
			local entry = {
				id = tonumber(id) or 0,
				name = tostring(name or ""),
				points = tonumber(points or 0) or 0,
				isFeat = isFeat and true or false,
				icon = icon,
				ts = ts,
			}

			pigAPI.PushLimited(p.achievements.list, entry, 50)

			if entry.points >= 10 or entry.isFeat then
				pigAPI.PushLimited(p.achievements.interesting, entry, 25)
				pigAPI.IncCounter(p, "achievements_interesting", 1)
			end

			pigAPI.IncCounter(p, "achievements_total", 1)

			-- Méta (debug/trace)
			local lAgg = pigAPI.GetModuleLast(p, MODULE_KEY)
			lAgg.achievementAt = ts

			local lEach = pigAPI.GetModuleLast(p, MODULE_KEY_EACH)
			lEach.achievementAt = ts

			p.updatedAt = ts

			-- Déclenche immédiatement le traitement news (filtré sur CFG.triggerEvent)
			TickJournalistSoon()
		end,
	})
end

-- ==========================================================
-- 4) Helpers métier (purs)
-- ==========================================================

local function GetPlayerDisplayNameSafe(api, uid)
	-- Ton JournalistAPI courant expose GetPlayerDisplayName() sans uid.
	-- On tente les deux signatures (compat).
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

local function MakeTailKey(list)
	if not list or #list == 0 then
		return ""
	end
	local e = list[#list]
	if type(e) == "table" then
		local ts = tonumber(e.ts) or 0
		local id = tonumber(e.id) or 0
		return ("%s:%s"):format(tostring(ts), tostring(id))
	end
	return tostring(e)
end

-- Choisit un HF à mettre en avant parmi ceux de la fenêtre.
-- Priorité configurable : feat > points > récent.
local function PickWindowHighlight(list, since)
	local best = nil
	local bestFeat = false
	local bestPoints = -1
	local bestTs = -1

	if not list or #list == 0 then
		return nil
	end

	for i = 1, #list do
		local e = list[i]
		if type(e) == "table" then
			local ts = tonumber(e.ts) or 0
			if ts >= since then
				local feat = e.isFeat and true or false
				local points = tonumber(e.points) or 0

				local better = false

				if CFG.highlight.preferFeat and feat ~= bestFeat then
					better = feat
				elseif CFG.highlight.preferPoints and points ~= bestPoints then
					better = points > bestPoints
				elseif CFG.highlight.preferRecent then
					better = ts > bestTs
				end

				if better then
					best = e
					bestFeat = feat
					bestPoints = points
					bestTs = ts
				end
			end
		end
	end

	return best
end

-- Fenêtre : retourne (count, highlightEntry) uniquement si changement pertinent.
local function computeAchievementWindow(api, intel, last, now)
	local list = intel.achievements and intel.achievements.list
	if not list or #list == 0 then
		return
	end

	local tailKey = MakeTailKey(list)
	local prevTailKey = tostring(last.achvTailKey or "")
	if tailKey == "" or tailKey == prevTailKey then
		return
	end
	last.achvTailKey = tailKey

	local since = now - (CFG.window.seconds or WINDOW_SECONDS)

	local count = 0
	for i = 1, #list do
		local e = list[i]
		if type(e) == "table" then
			local ts = tonumber(e.ts) or 0
			if ts >= since then
				count = count + 1
			end
		end
	end

	local prevCount = tonumber(last.achvWindowCount) or 0
	if count <= 0 or count == prevCount then
		last.achvWindowCount = count
		return
	end
	last.achvWindowCount = count

	local highlight = PickWindowHighlight(list, since)
	if not highlight then
		return
	end

	return count, highlight
end

-- News "par HF" : récupère toutes les entrées nouvelles depuis le dernier passage.
-- Robuste aux HF multiples dans la même seconde.
local function collectNewAchievementEntries(intel, last, now)
	local list = intel.achievements and intel.achievements.list
	if not list or #list == 0 then
		return
	end

	local prevTs = tonumber(last.achvEachLastTs) or nil
	local prevId = tonumber(last.achvEachLastId) or nil

	local out = {}
	local foundMarker = false

	if prevTs and prevId then
		for i = #list, 1, -1 do
			local e = list[i]
			if type(e) == "table" then
				local ts = tonumber(e.ts) or 0
				local id = tonumber(e.id) or 0
				if ts == prevTs and id == prevId then
					foundMarker = true
					break
				end
				out[#out + 1] = e
			end
		end
	else
		-- Premier run : on évite le spam, mais on accepte un HF tout frais.
		local tail = list[#list]
		if type(tail) == "table" then
			last.achvEachLastTs = tonumber(tail.ts) or 0
			last.achvEachLastId = tonumber(tail.id) or 0
			local nowTs = tonumber(now or 0) or 0
			local tailTs = tonumber(tail.ts) or 0
			if nowTs > 0 and tailTs > 0 and (nowTs - tailTs) <= 5 then
				out[#out + 1] = tail
				return out
			end
		end
		return
	end

	if not foundMarker then
		-- Marqueur perdu (liste tronquée) : pas de spam.
		local tail = list[#list]
		if type(tail) == "table" then
			last.achvEachLastTs = tonumber(tail.ts) or 0
			last.achvEachLastId = tonumber(tail.id) or 0
		end
		return
	end

	if #out == 0 then
		return
	end

	-- out est inversé : on remet dans l'ordre chronologique.
	for i = 1, math.floor(#out / 2) do
		out[i], out[#out - i + 1] = out[#out - i + 1], out[i]
	end

	-- Met à jour le marqueur sur la queue actuelle
	local tail = list[#list]
	if type(tail) == "table" then
		last.achvEachLastTs = tonumber(tail.ts) or 0
		last.achvEachLastId = tonumber(tail.id) or 0
	end

	return out
end

local function ResolveDisplayAndIcon(_, entry)
	local achId = tonumber(entry and entry.id) or 0

	local link = nil
	if achId > 0 and GetAchievementLink then
		link = GetAchievementLink(achId)
	end

	local name, icon = nil, nil
	name = entry and entry.name
	icon = tonumber(entry and entry.icon) or 0

	-- Utilise uniquement l'icône liée au HF (pas de fallback aléatoire)
	if achId > 0 and (not icon or icon == 0) then
		local achName, _, achIcon = GetAchievementInfoSafe(achId)
		if (not name or name == "") and achName and achName ~= "" then
			name = achName
			if type(entry) == "table" then
				entry.name = achName
			end
		end
		icon = tonumber(achIcon) or 0
		if type(entry) == "table" then
			entry.icon = achIcon
		end
	end

	local display = link or name or (achId > 0 and tostring(achId)) or ""
	if display == "" then
		return nil, nil, nil
	end

	if not icon or icon == 0 then
		icon = tonumber(entry and entry.icon) or 0
	end
	return achId, display, icon
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

	-- ----------------------------------------------------------
	-- A) News "par HF"
	-- ----------------------------------------------------------
	local function ProcessAchievementEachNews(g, intel, last, uid, now)
		if not CFG.enabled.each then
			return
		end

		local entries = collectNewAchievementEntries(intel, last, now)
		if not entries then
			return
		end

		local playerName = GetPlayerDisplayNameSafe(api, uid)
		local tpl = (CFG.each.phrases and api.Pick and api.Pick(CFG.each.phrases))
			or (CFG.each.phrases and CFG.each.phrases[1])
			or CFG.each.message
			or "%s a accompli ce Haut fait :\n%s."

		for i = 1, #entries do
			local entry = entries[i]
			local achId, display, icon = ResolveDisplayAndIcon(api, entry)
			if achId and display then
				local msg = tpl:format(playerName, display)
				local eventTs = tonumber(entry.ts) or now

				local newsId = ("%s%s:%s:%s"):format(
					CFG.each.idPrefix or "achievement:",
					tostring(uid),
					tostring(achId),
					tostring(eventTs)
				)

				api.AddRawNews(g, {
					text = msg,
					type = MODULE_KEY_EACH,
					icon = icon,
					ts = eventTs,
					replaceable = false,
					id = newsId,
					ttlSeconds = CFG.each.ttlSeconds, -- nil => TTL standard du Journaliste
					points = POINTS.achievement or 5,
				})
			end
		end
	end

	-- ----------------------------------------------------------
	-- B) News "48h" agrégée
	-- ----------------------------------------------------------
	local function ProcessAchievementNews(g, intel, last, uid, now)
		if not CFG.enabled.window then
			return
		end

		local count, highlight = computeAchievementWindow(api, intel, last, now)
		if not count or not highlight then
			return
		end

		if count < (tonumber(CFG.window.minCount) or 3) then
			return
		end

		local playerName = GetPlayerDisplayNameSafe(api, uid)

		-- IMPORTANT : highlight choisi dans toute la fenêtre
		local _, display, icon = ResolveDisplayAndIcon(api, highlight)
		if not display then
			return
		end

		local tpl = (CFG.window.phrases and api.Pick and api.Pick(CFG.window.phrases))
			or (CFG.window.phrases and CFG.window.phrases[1])
			or CFG.window.message
			or "%s a accompli %d HF dans les 2 derniers jours. Dont :\n%s."

		local msg = tpl:format(playerName, count, display)

		local replaceKey = ("%s%s"):format(CFG.window.replaceKeyPrefix or "achievement48:", tostring(uid))

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = icon,
			ts = now,
			replaceable = true,
			replaceKey = replaceKey,
			ttlSeconds = CFG.window.ttlSeconds or (CFG.window.seconds or WINDOW_SECONDS),
			points = POINTS.achievement or 5,
		})
	end

	-- Déclenchement piloté par le module : le Journaliste ne devine rien.
	registry.Register(MODULE_KEY_EACH, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessAchievementEachNews,
	})

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessAchievementNews,
	})
end
