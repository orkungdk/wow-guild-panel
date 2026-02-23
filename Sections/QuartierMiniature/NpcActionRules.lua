local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.NpcActionRules = QM.NpcActionRules or {}

local function DeepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, row in pairs(v) do
		out[k] = DeepCopy(row)
	end
	return out
end

local function MergeInto(dst, src)
	if type(dst) ~= "table" or type(src) ~= "table" then
		return dst
	end
	for k, row in pairs(src) do
		if type(row) == "table" and type(dst[k]) == "table" then
			MergeInto(dst[k], row)
		else
			dst[k] = row
		end
	end
	return dst
end

-- Catalogue d'icones par categorie.
-- Chaque categorie peut contenir:
-- - ids = { ... } (fileIDs)
-- - textures = { ... } (paths fallback)
-- - choices = { ... } (mix libre number/string)
-- - ou directement une liste legacy { ... } (mix number/string)
-- Un item est choisi au hasard puis conserve pour le meme contexte.
local BUILTIN_ICON_CATEGORIES = {
	DEFAULT = {
		ids = { "7636525" },
		textures = { "Interface\\ICONS\\INV_Misc_QuestionMark" },
	},
	TALK = {
		ids = { "2056011" },
		textures = { "Interface\\ICONS\\INV_Misc_GroupNeedMore" },
	},
	REST = {
		ids = { "136090" },
		textures = { "Interface\\ICONS\\Spell_Nature_Sleep" },
	},
	MEAL = {
		ids = { "134062" },
		textures = { "Interface\\ICONS\\INV_Misc_Food_64" },
	},
	DISTRACTION = {
		ids = { "132792" },
		textures = { "Interface\\ICONS\\INV_Drink_05" },
	},
	NATURE = {
		ids = { "236764" },
		textures = { "Interface\\ICONS\\INV_Misc_Flower_02" },
	},
	MOVE = {
		ids = { "132219" },
		textures = { "Interface\\ICONS\\Ability_Rogue_Sprint" },
	},
	PAUSE = {
		ids = { "310843" },
		textures = { "Interface\\ICONS\\Spell_Nature_Sleep" },
	},
}

local BUILTIN_ACTION_SPECS = {
	rest = {
		label = "Se reposer",
		iconKey = "REST",
		travelLabel = "Aller se reposer",
		travelIconKey = "REST",
		activeLabel = "Est en train de se reposer",
		activeIconKey = "REST",
		travelSpeedFactor = 0.86,
		reserveKey = "fatigue",
		startThreshold = 20,
		stopRollMinPercent = 80,
		stopRollMaxPercent = 100,
		chancePerPointAboveMin = 0.05,
		playerMinLockSec = 8,
		playerMaxLockSec = 12,
		autoCanInterrupt = true,
		playerCanInterrupt = false,
		requiresLieuType = "chaumiere",
	},
	meal = {
		label = "Manger",
		iconKey = "MEAL",
		travelLabel = "Aller manger",
		travelIconKey = "MEAL",
		activeLabel = "Est en train de manger",
		activeIconKey = "MEAL",
		travelSpeedFactor = 0.95,
		reserveKey = "faim",
		startThreshold = 20,
		stopRollMinPercent = 80,
		stopRollMaxPercent = 100,
		chancePerPointAboveMin = 0.05,
		playerMinLockSec = 8,
		playerMaxLockSec = 12,
		autoCanInterrupt = true,
		playerCanInterrupt = false,
		requiresLieuType = "auberge",
	},
	distraction = {
		label = "S'amuser",
		iconKey = "DISTRACTION",
		travelLabel = "Aller s'amuser",
		travelIconKey = "DISTRACTION",
		activeLabel = "Est en train de s'amuser",
		activeIconKey = "DISTRACTION",
		travelSpeedFactor = 1.00,
		reserveKey = "distraction",
		startThreshold = 20,
		stopRollMinPercent = 80,
		stopRollMaxPercent = 100,
		chancePerPointAboveMin = 0.05,
		playerMinLockSec = 8,
		playerMaxLockSec = 12,
		autoCanInterrupt = true,
		playerCanInterrupt = false,
		requiresLieuType = "taverne",
	},
	observe_nature = {
		label = "Observer la nature",
		iconKey = "NATURE",
		travelLabel = "Aller observer la nature",
		travelIconKey = "NATURE",
		activeLabel = "Est en train d'observer la nature",
		activeIconKey = "NATURE",
		reserveKey = nil,
		stopRollMinPercent = 80,
		stopRollMaxPercent = 100,
		chancePerPointAboveMin = 0.05,
		autoCanInterrupt = false,
		playerCanInterrupt = false,
	},
	move_place = {
		label = "Se promener",
		iconKey = "MOVE",
		travelLabel = "Aller se promener",
		travelIconKey = "MOVE",
		activeLabel = "Est en train de se promener",
		activeIconKey = "MOVE",
		travelSpeedFactor = 0.92,
		reserveKey = nil,
		stopRollMinPercent = 80,
		stopRollMaxPercent = 100,
		chancePerPointAboveMin = 0.05,
		autoCanInterrupt = true,
		playerCanInterrupt = true,
	},
	se_promener = {
		label = "Se promener",
		iconKey = "MOVE",
		travelLabel = "Aller se promener",
		travelIconKey = "MOVE",
		activeLabel = "Est en train de se promener",
		activeIconKey = "MOVE",
		travelSpeedFactor = 0.92,
		reserveKey = nil,
		stopRollMinPercent = 80,
		stopRollMaxPercent = 100,
		chancePerPointAboveMin = 0.05,
		autoCanInterrupt = true,
		playerCanInterrupt = true,
	},
	aller_ici = {
		label = "Aller ici",
		iconKey = "MOVE",
		travelLabel = "Aller ici",
		travelIconKey = "MOVE",
		activeLabel = "Est en train de se deplacer ici",
		activeIconKey = "MOVE",
		travelSpeedFactor = 0.96,
		reserveKey = nil,
		autoCanInterrupt = true,
		playerCanInterrupt = true,
	},
	aller_ici_et_attendre = {
		label = "Aller ici et attendre",
		iconKey = "PAUSE",
		travelLabel = "Aller ici et attendre",
		travelIconKey = "MOVE",
		activeLabel = "Est en train d'attendre ici",
		activeIconKey = "PAUSE",
		travelSpeedFactor = 0.92,
		reserveKey = nil,
		autoCanInterrupt = true,
		playerCanInterrupt = true,
	},
	lieu_pause = {
		label = "Action lieu",
		iconKey = "MOVE",
	},
	talk = {
		label = "Discuter",
		iconKey = "TALK",
		travelLabel = "Aller discuter",
		travelIconKey = "TALK",
		activeLabel = "Est en train de discuter",
		activeIconKey = "TALK",
	},
	approach = {
		label = "Approcher",
		iconKey = "MOVE",
	},
	duo_walk = {
		label = "Balade duo",
		iconKey = "MOVE",
	},
	self_pause = {
		label = "Pause",
		iconKey = "PAUSE",
	},
	disengage = {
		label = "S'eloigner",
		iconKey = "MOVE",
	},
	walk = {
		label = "Se promener",
		iconKey = "MOVE",
		travelLabel = "Aller ici",
		travelIconKey = "MOVE",
		activeLabel = "Est en train de se promener",
		activeIconKey = "MOVE",
		travelSpeedFactor = 0.96,
	},
	route = {
		label = "Route",
		iconKey = "MOVE",
	},
	plaza = {
		label = "Place",
		iconKey = "MOVE",
	},
	discussion = {
		label = "Discussion",
		iconKey = "TALK",
	},
}

function QM.NpcActionRules.GetBuiltinActionSpecs()
	return DeepCopy(BUILTIN_ACTION_SPECS)
end

function QM.NpcActionRules.GetBuiltinIconCategories()
	return DeepCopy(BUILTIN_ICON_CATEGORIES)
end

function QM.NpcActionRules.CreateRunner(api)
	if type(api) ~= "table" then
		return nil
	end

	local Clamp = assert(api.Clamp)
	local RandomRoll = type(api.RandomRoll) == "function" and api.RandomRoll or function()
		return math.random()
	end
	local icons = type(api.icons) == "table" and api.icons or {}

	local DEFAULT_MIN = Clamp(tonumber(api.defaultThreshold) or tonumber(api.defaultMinRollPercent) or 80, 0, 100)
	local DEFAULT_MAX =
		Clamp(tonumber(api.forceCompletePercent) or tonumber(api.defaultMaxRollPercent) or 100, DEFAULT_MIN, 100)
	local DEFAULT_CHANCE_PER_POINT = Clamp(tonumber(api.defaultChancePerPoint) or 0.05, 0, 1)

	local actionSpecs = DeepCopy(BUILTIN_ACTION_SPECS)
	MergeInto(actionSpecs, api.actionSpecs)
	local iconCategories = DeepCopy(BUILTIN_ICON_CATEGORIES)
	if type(api.iconCategories) == "table" then
		MergeInto(iconCategories, api.iconCategories)
	end
	local function HasCategoryEntries(category)
		if type(category) ~= "table" then
			return false
		end
		if type(category.ids) == "table" and #category.ids > 0 then
			return true
		end
		if type(category.choices) == "table" and #category.choices > 0 then
			return true
		end
		if type(category.textures) == "table" and #category.textures > 0 then
			return true
		end
		return #category > 0
	end
	if type(icons) == "table" then
		for key, value in pairs(icons) do
			local k = tostring(key or "")
			if k ~= "" and not HasCategoryEntries(iconCategories[k]) then
				if type(value) == "table" then
					iconCategories[k] = DeepCopy(value)
				elseif type(value) == "string" or type(value) == "number" then
					iconCategories[k] = { value }
				end
			end
		end
	end

	local function NormalizePurpose(v)
		return string.lower(tostring(v or ""))
	end

	local function ResolvePurpose(v)
		local p = NormalizePurpose(v)
		if p == "move_place" then
			return "se_promener"
		end
		if p == "wait" then
			return "aller_ici_et_attendre"
		end
		return p
	end

	local function NormalizeIconValue(v)
		if type(v) == "number" then
			local n = math.floor(v + 0.5)
			if n > 0 then
				return n
			end
			return nil
		end
		if type(v) ~= "string" then
			return nil
		end
		local s = v:gsub("^%s+", ""):gsub("%s+$", "")
		if s == "" then
			return nil
		end
		if s:match("^%d+$") then
			local n = math.floor(tonumber(s) or 0)
			if n > 0 then
				return n
			end
			return nil
		end
		return s
	end

	local function PickRandomFromChoices(choices, cacheBag, cacheKey)
		if type(choices) ~= "table" then
			return NormalizeIconValue(choices)
		end
		if type(cacheBag) == "table" and cacheKey and cacheBag[cacheKey] ~= nil then
			return cacheBag[cacheKey]
		end
		local pool = {}
		for i = 1, #choices do
			local value = NormalizeIconValue(choices[i])
			if value ~= nil then
				pool[#pool + 1] = value
			end
		end
		if #pool == 0 then
			return nil
		end
		local roll = Clamp(tonumber(RandomRoll()) or 0, 0, 0.999999)
		local idx = math.floor(roll * #pool) + 1
		local picked = pool[idx]
		if type(cacheBag) == "table" and cacheKey then
			cacheBag[cacheKey] = picked
		end
		return picked
	end

	local function PickFromCategory(category, cacheBag, cacheKey)
		if type(category) ~= "table" then
			return PickRandomFromChoices(category, cacheBag, cacheKey)
		end
		local hasStructuredKeys = (type(category.ids) == "table")
			or (type(category.textures) == "table")
			or (type(category.choices) == "table")
		if not hasStructuredKeys then
			return PickRandomFromChoices(category, cacheBag, cacheKey)
		end
		if type(category.ids) == "table" and #category.ids > 0 then
			local picked =
				PickRandomFromChoices(category.ids, cacheBag, cacheKey and (tostring(cacheKey) .. ":ids") or "ids")
			if picked ~= nil then
				return picked
			end
		end
		if type(category.choices) == "table" and #category.choices > 0 then
			local picked = PickRandomFromChoices(
				category.choices,
				cacheBag,
				cacheKey and (tostring(cacheKey) .. ":choices") or "choices"
			)
			if picked ~= nil then
				return picked
			end
		end
		if type(category.textures) == "table" and #category.textures > 0 then
			local picked = PickRandomFromChoices(
				category.textures,
				cacheBag,
				cacheKey and (tostring(cacheKey) .. ":textures") or "textures"
			)
			if picked ~= nil then
				return picked
			end
		end
		return nil
	end

	local function ResolveIconCandidate(raw, cacheBag, cacheKey)
		if type(raw) == "table" then
			return PickFromCategory(raw, cacheBag, cacheKey)
		end
		if type(raw) == "string" then
			local key = raw:gsub("^%s+", ""):gsub("%s+$", "")
			if key ~= "" and type(iconCategories[key]) == "table" then
				local categoryKey = cacheKey and (tostring(cacheKey) .. ":" .. key) or ("cat:" .. key)
				return PickFromCategory(iconCategories[key], cacheBag, categoryKey)
			end
		end
		return NormalizeIconValue(raw)
	end

	local function Icon(raw, fallback, cacheBag, cacheKey)
		local resolved = ResolveIconCandidate(raw, cacheBag, cacheKey)
		if resolved ~= nil then
			return resolved
		end
		return ResolveIconCandidate(fallback, cacheBag, cacheKey and (tostring(cacheKey) .. ":fallback") or "fallback")
	end

	local function GetRule(purpose)
		return actionSpecs[ResolvePurpose(purpose)]
	end

	local function GetTravelLabelIcon(spec, fallbackLabel, fallbackIconKey, cacheBag, cacheKey)
		if type(spec) ~= "table" then
			return tostring(fallbackLabel or ""), Icon(fallbackIconKey, "DEFAULT", cacheBag, cacheKey)
		end
		local label = tostring(spec.travelLabel or spec.label or fallbackLabel or "")
		local icon = Icon(
			spec.travelIconChoices
				or spec.travelIconIds
				or spec.travelIconId
				or spec.travelIconKey
				or spec.iconChoices
				or spec.iconIds
				or spec.iconId
				or spec.iconKey
				or fallbackIconKey,
			"DEFAULT",
			cacheBag,
			cacheKey
		)
		return label, icon
	end

	local function BuildActiveLabelIcon(spec, fallbackLabel, fallbackIconKey, cacheBag, cacheKey)
		if type(spec) ~= "table" then
			return tostring(fallbackLabel or ""), Icon(fallbackIconKey, "DEFAULT", cacheBag, cacheKey)
		end
		local label = tostring(spec.activeLabel or spec.label or fallbackLabel or "")
		local icon = Icon(
			spec.activeIconChoices
				or spec.activeIconIds
				or spec.activeIconId
				or spec.activeIconKey
				or spec.iconChoices
				or spec.iconIds
				or spec.iconId
				or spec.iconKey
				or fallbackIconKey,
			"DEFAULT",
			cacheBag,
			cacheKey
		)
		return label, icon
	end

	local function GetReserveFromNeeds(needs, reserveKey)
		if type(needs) ~= "table" then
			return 100
		end
		if reserveKey == "fatigue" then
			return Clamp(tonumber(needs.fatigue) or 0, 0, 100)
		end
		if reserveKey == "faim" then
			return Clamp(tonumber(needs.faim) or 0, 0, 100)
		end
		if reserveKey == "distraction" then
			return Clamp(tonumber(needs.distraction) or 0, 0, 100)
		end
		return 100
	end

	local function GetStopBounds(spec)
		local minPercent =
			Clamp(tonumber(spec.stopRollMinPercent) or tonumber(spec.minCompletePercent) or DEFAULT_MIN, 0, 100)
		local maxPercent = Clamp(
			tonumber(spec.stopRollMaxPercent) or tonumber(spec.forceCompletePercent) or DEFAULT_MAX,
			minPercent,
			100
		)
		return minPercent, maxPercent
	end

	local function CanRollStopAtPercent(spec, percent)
		local p = math.floor(tonumber(percent) or 0)
		local minPercent, maxPercent = GetStopBounds(spec)
		if p >= maxPercent then
			return true
		end
		if p < minPercent then
			return false
		end
		local chance =
			Clamp((p - minPercent) * (tonumber(spec.chancePerPointAboveMin) or DEFAULT_CHANCE_PER_POINT), 0, 1)
		return RandomRoll() <= chance
	end

	local runner = {}

	function runner.GetActionSpec(purpose)
		local spec = GetRule(purpose)
		if type(spec) ~= "table" then
			return nil
		end
		return spec
	end

	function runner.GetAllActionSpecs()
		return DeepCopy(actionSpecs)
	end

	function runner.GetReserveForPurpose(npcNeeds, purpose)
		local spec = GetRule(purpose)
		if type(spec) ~= "table" then
			return 100
		end
		return GetReserveFromNeeds(npcNeeds, spec.reserveKey)
	end

	function runner.GetTravelSpeedFactor(purpose)
		local spec = GetRule(purpose)
		if type(spec) ~= "table" then
			return nil
		end
		local v = tonumber(spec.travelSpeedFactor)
		if not v then
			return nil
		end
		return Clamp(v, 0.25, 2.0)
	end

	function runner.GetActiveLabelIcon(purpose, context)
		local spec = GetRule(purpose)
		if type(spec) ~= "table" then
			return nil, nil
		end
		local cacheBag = nil
		if type(context) == "table" then
			context._actionRuleIconCache = type(context._actionRuleIconCache) == "table"
					and context._actionRuleIconCache
				or {}
			cacheBag = context._actionRuleIconCache
		end
		local cacheKey = "active:" .. tostring(ResolvePurpose(purpose))
		local label, icon = BuildActiveLabelIcon(spec, nil, "DEFAULT", cacheBag, cacheKey)
		if label == "" or icon == nil then
			return nil, nil
		end
		return label, icon
	end

	function runner.CanAutoStartAction(ctx)
		if type(ctx) ~= "table" then
			return true
		end
		if tostring(ctx.source or "auto") == "player" then
			return true
		end
		local spec = GetRule(ctx.purpose)
		if type(spec) ~= "table" or spec.autoCanInterrupt ~= true then
			return true
		end
		local reserve = Clamp(tonumber(ctx.reserve) or 0, 0, 100)
		local minPercent = select(1, GetStopBounds(spec))
		if reserve <= minPercent then
			return true
		end
		return not CanRollStopAtPercent(spec, reserve)
	end

	function runner.ShouldAutoInterrupt(ctx)
		if type(ctx) ~= "table" then
			return false
		end
		local spec = GetRule(ctx.purpose)
		if type(spec) ~= "table" or spec.autoCanInterrupt ~= true then
			return false
		end
		local reserve = Clamp(tonumber(ctx.reserve) or 0, 0, 100)
		local _, maxPercent = GetStopBounds(spec)
		if reserve >= maxPercent then
			return true
		end
		return CanRollStopAtPercent(spec, reserve)
	end

	function runner.ShouldPlayerInterrupt(ctx)
		if type(ctx) ~= "table" then
			return false
		end
		local spec = GetRule(ctx.purpose)
		if type(spec) ~= "table" or spec.playerCanInterrupt ~= true then
			return false
		end
		local reserve = Clamp(tonumber(ctx.reserve) or 0, 0, 100)
		local _, maxPercent = GetStopBounds(spec)
		if reserve >= maxPercent then
			return true
		end
		return CanRollStopAtPercent(spec, reserve)
	end

	function runner.ShouldStopByCompletion(ctx)
		if type(ctx) ~= "table" then
			return false
		end
		local npc = ctx.npc
		if type(npc) ~= "table" then
			return false
		end
		local purpose = ResolvePurpose(ctx.purpose)
		local spec = GetRule(purpose)
		if type(spec) ~= "table" then
			return false
		end
		local reserve = Clamp(tonumber(ctx.reserve) or 0, 0, 100)
		local minPercent, maxPercent = GetStopBounds(spec)
		local source = tostring(ctx.source or "auto")
		local lockActive = ctx.lockActive == true
		local currentPercent = math.floor(reserve + 0.0001)

		if currentPercent >= maxPercent then
			npc._actionRuleLastPurpose = nil
			npc._actionRuleLastPercent = nil
			return true
		end
		if lockActive then
			return false
		end
		if source == "player" and spec.playerCanInterrupt ~= true then
			return false
		end
		if source ~= "player" and spec.autoCanInterrupt ~= true then
			return false
		end
		if currentPercent < minPercent then
			npc._actionRuleLastPurpose = purpose
			npc._actionRuleLastPercent = currentPercent
			return false
		end

		if tostring(npc._actionRuleLastPurpose or "") ~= purpose then
			npc._actionRuleLastPurpose = purpose
			npc._actionRuleLastPercent = currentPercent
			return false
		end

		local lastPercent = math.floor(tonumber(npc._actionRuleLastPercent) or currentPercent)
		if currentPercent <= lastPercent then
			return false
		end

		for p = math.max(minPercent + 1, lastPercent + 1), currentPercent do
			local chance =
				Clamp((p - minPercent) * (tonumber(spec.chancePerPointAboveMin) or DEFAULT_CHANCE_PER_POINT), 0, 1)
			if RandomRoll() <= chance then
				npc._actionRuleLastPercent = p
				return true
			end
		end
		npc._actionRuleLastPercent = currentPercent
		return false
	end

	function runner.GetIntentLabelIcon(order)
		if type(order) ~= "table" then
			return nil, nil
		end
		local source = tostring(order.source or "")
		local kind = NormalizePurpose(order.kind)
		local purpose = ResolvePurpose(order.purpose)

		if kind == "talk" then
			local spec = GetRule("talk")
			local cacheBag = nil
			if type(order) == "table" then
				cacheBag = type(order._actionRuleIconCache) == "table" and order._actionRuleIconCache or {}
				order._actionRuleIconCache = cacheBag
			end
			return GetTravelLabelIcon(spec, "Aller discuter", "MOVE", cacheBag, "travel:talk")
		end

		if kind == "lieu_pause" then
			local cacheBag = nil
			if type(order) == "table" then
				cacheBag = type(order._actionRuleIconCache) == "table" and order._actionRuleIconCache or {}
				order._actionRuleIconCache = cacheBag
			end
			if source == "auto_poi" or purpose == "observe_nature" then
				local spec = GetRule("observe_nature")
				return GetTravelLabelIcon(spec, "Aller observer la nature", "MOVE", cacheBag, "travel:observe_nature")
			end
			local spec = GetRule(purpose)
			if type(spec) == "table" then
				return GetTravelLabelIcon(spec, "Se deplacer", "MOVE", cacheBag, "travel:" .. tostring(purpose))
			end
			local waitSeconds = tonumber(order.waitSeconds) or 0
			if waitSeconds > 0 then
				local waitSpec = GetRule("aller_ici_et_attendre")
				if type(waitSpec) == "table" then
					return GetTravelLabelIcon(waitSpec, "Aller ici et attendre", "MOVE", cacheBag, "travel:wait")
				end
				return "Aller ici et attendre", Icon("MOVE", "DEFAULT", cacheBag, "travel:wait")
			end
			local goSpec = GetRule("aller_ici")
			if type(goSpec) == "table" then
				return GetTravelLabelIcon(goSpec, "Aller ici", "MOVE", cacheBag, "travel:walk")
			end
			return "Aller ici", Icon("MOVE", "DEFAULT", cacheBag, "travel:walk")
		end

		return nil, nil
	end

	return runner
end
