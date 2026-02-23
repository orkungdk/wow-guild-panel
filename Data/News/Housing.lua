-- ==========================================================
-- Housing module (toggle strict via HOUSE_EDITOR_MODE_CHANGED)
-- ==========================================================

local ADDON, ns = ...

local Data = ns and ns.Data
if not Data then
	return
end
local POINTS = { housing = 1 }

local MODULE_KEY = "housing"
local PIGISTE_KEY = "housing"

local START_PHRASES = {
	"%s ouvre les portes de son logis et commence l’agencement.",
	"%s retrousse ses manches et se met à organiser son intérieur.",
	"%s allume les lanternes et passe en mode aménagement.",
	"%s entre dans son logis avec l’œil du décorateur.",
	"%s prépare son espace et entame la mise en place.",
	"%s ouvre l’atelier et réfléchit à l’ordre des choses.",
	"%s observe les murs et commence à façonner l’espace.",
	"%s ouvre les portes de son logis et commence l’agencement.",
	"%s retrousse ses manches et se met à organiser son intérieur.",
	"%s allume les lanternes et passe en mode aménagement.",
	"%s entre dans son logis avec l’œil du décorateur.",
	"%s prépare son espace et entame la mise en place.",
	"%s ouvre l’atelier et réfléchit à l’ordre des choses.",
	"%s observe les murs et commence à façonner l’espace.",
}

local STOP_PHRASES = {
	"%s termine l’aménagement de son logis après %s et %d objets disposés.",
	"%s referme l’atelier après %s de mise en ordre et %d objets posés.",
	"%s prend du recul sur son œuvre après %s et %d éléments installés.",
	"%s achève l’agencement du lieu en %s avec %d objets en place.",
	"%s quitte le mode décoration après %s et %d pièces soigneusement rangées.",
	"%s laisse son logis en ordre après %s de travail et %d objets disposés.",
	"%s éteint les lanternes après %s et %d éléments ajoutés à l’ensemble.",
	"%s conclut l’aménagement de son logis après %s et %d objets disposés.",
	"%s prend du recul et quitte l’atelier après %s et %d éléments en place.",
	"%s referme la session d’agencement après %s et %d objets installés.",
	"%s estime le travail accompli après %s et %d pièces positionnées.",
	"%s termine les ajustements du logis après %s et %d objets rangés.",
	"%s achève l’organisation de l’espace après %s et %d éléments posés.",
	"%s laisse l’intérieur en ordre après %s et %d objets soigneusement placés.",
	"%s met fin à l’aménagement après %s et %d objets intégrés à l’ensemble.",
	"%s quitte le logis satisfait après %s de travail et %d objets disposés.",
	"%s s’éloigne de l’atelier après %s et %d éléments trouvant leur place.",
	"%s referme les portes après %s et %d objets désormais en harmonie.",
	"%s termine la mise en place du logis après %s et %d pièces ajoutées.",
	"%s juge l’agencement suffisant après %s et %d objets installés.",
	"%s achève la session en laissant %d objets en place après %s.",
	"%s quitte le mode décoration après %s et %d objets correctement alignés.",
}

local STOP_PHRASES_EMPTY = {
	"%s a rapidement arrêté de ranger son intérieur.",
	"%s referme l’atelier sans rien poser cette fois.",
	"%s quitte le mode décoration après un court passage.",
	"%s a fait un tour rapide dans son logis, puis s’est arrêté.",

	"%s jette un dernier regard et renonce à l’agencement.",
	"%s entre, observe, puis décide de ne rien changer.",
	"%s ressort de son logis sans avoir déplacé quoi que ce soit.",
	"%s abandonne l’idée d’aménager pour aujourd’hui.",
	"%s ferme l’atelier avant même de commencer.",
	"%s estime que l’intérieur peut attendre.",
	"%s fait quelques pas, soupire, et quitte le mode décoration.",
	"%s renonce à réorganiser son logis pour le moment.",
	"%s regarde autour de lui et décide d’en rester là.",
	"%s ressort sans avoir touché au moindre objet.",
	"%s quitte l’atelier sans modifier l’agencement.",
	"%s interrompt la session avant d’avoir posé quoi que ce soit.",
	"%s juge que le logis se portera bien ainsi.",
	"%s repart sans rien changer à l’ordre établi.",
}

local ICONS = {
	7252953,
	1001489,
	1001491,
}

local CFG = {
	enabled = true,
	triggerEvent = "HOUSING_MODE_UPDATE",
	pigisteEvents = {
		HOUSE_EDITOR_MODE_CHANGED = true,
		HOUSING_DECOR_PLACE_SUCCESS = true,
	},
	triggerEvents = {
		"HOUSING_MODE_UPDATE",
	},
	replaceKeyPrefix = "housing:",
	phrasesStart = START_PHRASES,
	phrasesStop = STOP_PHRASES,
	phrasesStopEmpty = STOP_PHRASES_EMPTY,
	icons = ICONS,
}

do
	local Pigiste = Data.Pigiste
	local pigapi = Data.PigisteAPI
	if not Pigiste or not pigapi then
		return
	end

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

	local function ToggleState(p, l, now)
		local wasActive = not not l.modeActive
		local active = not wasActive
		l.modeActive = active
		l.transitionSeq = (tonumber(l.transitionSeq) or 0) + 1
		l.transitionAt = now

		if active then
			l.modeStartAt = now
			l.sessionPlaced = 0
			l.lastTransition = "start"
			p.updatedAt = now
			TickJournalistSoon()
			return
		end

		local duration = 0
		local startedAt = tonumber(l.modeStartAt or 0) or 0
		if startedAt > 0 and now >= startedAt then
			duration = now - startedAt
		end
		l.modeStartAt = 0
		l.lastDuration = duration
		l.lastTransition = "stop"
		l.lastSessionPlaced = tonumber(l.sessionPlaced or 0) or 0
		l.sessionPlaced = 0
		l.lastStopAt = now

		pigapi.PushActivity(p, PIGISTE_KEY, { ts = now, duration = duration, placed = l.lastSessionPlaced }, 200)
		p.updatedAt = now
		TickJournalistSoon()
	end

	Pigiste.RegisterModule(PIGISTE_KEY, {
		events = CFG.pigisteEvents,
		OnEvent = function(_, eventName, ...)
			if not CFG.enabled then
				return
			end
			local p = pigapi.EnsurePlayer(pigapi.GetMyUID())
			if not p then
				return
			end
			local now = pigapi.Now()
			local l = pigapi.GetModuleLast(p, MODULE_KEY)

			if eventName == "HOUSING_DECOR_PLACE_SUCCESS" then
				if l.modeActive then
					l.sessionPlaced = (tonumber(l.sessionPlaced) or 0) + 1
					p.updatedAt = now
				end
				return
			end

			if eventName ~= "HOUSE_EDITOR_MODE_CHANGED" then
				return
			end
			ToggleState(p, l, now)
		end,
	})
end

do
	local registry = Data.NewsRegistry
	if not registry or not registry.Register then
		return
	end

	local api = Data.JournalistAPI
	if not api then
		return
	end

	local function GetPlayerDisplayNameSafe(apiRef, uid)
		local n = apiRef and apiRef.GetPlayerDisplayName and apiRef.GetPlayerDisplayName(uid) or nil
		if n and n ~= "" then
			return n
		end
		n = apiRef and apiRef.GetPlayerDisplayName and apiRef.GetPlayerDisplayName() or nil
		if n and n ~= "" then
			return n
		end
		return uid and tostring(uid) or "Le joueur"
	end

	local function FormatDurationWords(totalSeconds)
		local sec = math.max(0, math.floor(tonumber(totalSeconds or 0) or 0))
		local h = math.floor(sec / 3600)
		local m = math.floor((sec % 3600) / 60)

		if h > 0 then
			local m10 = math.floor(m / 10) * 10
			if m10 > 0 then
				return ("%d %s %d %s"):format(h, (h > 1) and "heures" or "heure", m10, "minutes")
			end
			return ("%d %s"):format(h, (h > 1) and "heures" or "heure")
		end

		if m > 0 then
			return ("%d %s"):format(m, (m > 1) and "minutes" or "minute")
		end

		return ("%d %s"):format(sec, (sec > 1) and "secondes" or "seconde")
	end

	local function ProcessHousingNews(g, intel, last, uid, now)
		local moduleState = intel and intel.last or nil
		local seq = tonumber(moduleState and moduleState.transitionSeq or 0) or 0
		if seq <= 0 then
			return
		end

		local postedSeq = tonumber(last.postedSeq or 0) or 0
		if seq <= postedSeq then
			return
		end

		local transition = tostring(moduleState and moduleState.lastTransition or "")
		local duration = tonumber(moduleState and moduleState.lastDuration or 0) or 0
		local placed = tonumber(moduleState and moduleState.lastSessionPlaced or 0) or 0
		local replaceKey = (CFG.replaceKeyPrefix or "housing:") .. tostring(uid or "player")

		local msg
		if transition == "start" then
			msg = (api.Pick(CFG.phrasesStart) or "%s entre en mode housing."):format(GetPlayerDisplayNameSafe(api, uid))
		else
			if placed <= 0 then
				msg = (api.Pick(CFG.phrasesStopEmpty) or "%s a rapidement arrêté de ranger son intérieur."):format(
					GetPlayerDisplayNameSafe(api, uid)
				)
			else
				local durationText = FormatDurationWords(duration)
				msg = (api.Pick(CFG.phrasesStop) or "%s termine sa session housing (%s, %d objets posés)."):format(
					GetPlayerDisplayNameSafe(api, uid),
					durationText,
					placed
				)
			end
		end

		local icon = api.Pick(CFG.icons) or 136025

		api.AddRawNews(g, {
			text = msg,
			type = MODULE_KEY,
			icon = icon,
			ts = now,
			replaceKey = replaceKey,
			removedAt = api.GetRemovedAt(MODULE_KEY, now, nil, replaceKey),
			points = POINTS.housing or 1,
		})

		last.postedSeq = seq
		last.postedAt = now
	end

	registry.Register(MODULE_KEY, {
		trigger = { events = CFG.triggerEvents },
		run = ProcessHousingNews,
	})
end
