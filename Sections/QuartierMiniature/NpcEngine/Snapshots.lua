local ADDON, ns = ...

ns.QuartierMiniatureNpcEngine = ns.QuartierMiniatureNpcEngine or {}
ns.QuartierMiniatureNpcEngine.Modules = ns.QuartierMiniatureNpcEngine.Modules or {}
local Modules = ns.QuartierMiniatureNpcEngine.Modules

function Modules.InstallSnapshots(ctx, moduleEnv)
	if type(ctx) ~= "table" or type(moduleEnv) ~= "table" then
		return nil
	end
	setfenv(1, moduleEnv)

function FindNpcBySelector(selector)
	if type(selector) == "number" then
		local index = math.floor(selector)
		if index >= 1 and index <= #npcPool then
			return npcPool[index], index
		end
	end
	if type(selector) == "string" and selector ~= "" then
		for i = 1, #npcPool do
			local npc = npcPool[i]
			if tostring(npc.persistentId or "") == selector then
				return npc, i
			end
		end
	end
	return nil, nil
end

function SetNpcName(selector, newName)
	local npc, index = FindNpcBySelector(selector)
	if not npc then
		return false, nil, "npc_not_found"
	end
	local isPlayerHero = tostring(npc.persistentId or "") == NPC_PLAYER_HERO_ID
		or tostring(npc.portraitUnit or "") == "player"
		or index == 1
	if npc.isRegisseuse == true or isPlayerHero then
		return false, npc.displayName, "rename_forbidden"
	end
	local normalized = TrimNpcName(newName)
	if not normalized then
		return false, npc.displayName, "invalid_name"
	end
	SetNpcDisplayName(npc, normalized, index)
	SaveNpcPersistence()
	return true, npc.displayName, nil
end

function AppendNpcIntent(list, maxCount, label, icon, isCurrent, source, meta)
	if type(list) ~= "table" then
		return
	end
	local cap = math.max(1, math.floor(tonumber(maxCount) or NPC_INTENT_QUEUE_MAX))
	if #list >= cap then
		return
	end
	local text = tostring(label or "")
	if text == "" then
		return
	end
	local tex = icon
	if type(tex) == "string" then
		tex = tex:gsub("^%s+", ""):gsub("%s+$", "")
		if tex == "" then
			tex = nil
		end
	elseif type(tex) == "number" then
		local fileId = math.floor(tex + 0.5)
		tex = fileId > 0 and fileId or nil
	else
		tex = nil
	end
	if tex == nil then
		tex = INTENT_ICON_DEFAULT
	end
	local row = {
		label = text,
		icon = tex,
		current = isCurrent == true,
		source = tostring(source or "auto"),
	}
	if type(meta) == "table" then
		for k, v in pairs(meta) do
			row[k] = v
		end
	end
	list[#list + 1] = row
end

function GetNpcIntentFromOrder(order)
	if type(order) ~= "table" then
		return nil, nil
	end
	if actionRules and type(actionRules.GetIntentLabelIcon) == "function" then
		local label, icon = actionRules.GetIntentLabelIcon(order)
		local iconOk = (type(icon) == "string" and icon ~= "") or type(icon) == "number"
		if type(label) == "string" and label ~= "" and iconOk then
			return label, icon
		end
	end
	local source = tostring(order.source or "")
	local kind = tostring(order.kind or "")
	local purpose = tostring(order.purpose or "")
	if kind == "talk" then
		return "Discuter", INTENT_ICON_TALK
	end
	if kind == "join_talk" then
		return "Rejoindre discussion", INTENT_ICON_TALK
	end
	if kind == "lieu_pause" then
		if source == "auto_poi" then
			return "Observer la nature", INTENT_ICON_NATURE
		end
		if purpose == "observe_nature" then
			return "Observer la nature", INTENT_ICON_NATURE
		end
		if purpose == "move_place" and source == "auto" then
			return "Aller sur la place", INTENT_ICON_MOVE
		end
		if purpose == "rest" then
			return "Attendre", INTENT_ICON_REST
		end
		if purpose == "meal" then
			return "Manger a l'auberge", INTENT_ICON_DISTRACTION
		end
		if purpose == "distraction" then
			return "Se distraire", INTENT_ICON_DISTRACTION
		end
		return "Se deplacer", INTENT_ICON_MOVE
	end
	return "Action", INTENT_ICON_DEFAULT
end

function GetNpcIntentFromBehavior(npc)
	local stateName = tostring(Npc_GetSocialState(npc) or "walk")
	if stateName == "discussion" then
		if actionRules and type(actionRules.GetActiveLabelIcon) == "function" then
			local label, icon = actionRules.GetActiveLabelIcon("talk", npc)
			local iconOk = (type(icon) == "string" and icon ~= "") or type(icon) == "number"
			if type(label) == "string" and label ~= "" and iconOk then
				return label, icon
			end
		end
		return "Discussion", INTENT_ICON_TALK
	end
	if stateName == "approach" then
		return "Approcher", INTENT_ICON_MOVE
	end
	if stateName == "duo_walk" then
		return "Balade duo", INTENT_ICON_MOVE
	end
	if stateName == "self_pause" then
		local pausePurpose = tostring((npc and (npc.essentialPausePurpose or npc.pausePurpose)) or "")
		if actionRules and type(actionRules.GetActiveLabelIcon) == "function" then
			local label, icon = actionRules.GetActiveLabelIcon(pausePurpose, npc)
			local iconOk = (type(icon) == "string" and icon ~= "") or type(icon) == "number"
			if type(label) == "string" and label ~= "" and iconOk then
				return label, icon
			end
		end
		return "Pause", INTENT_ICON_PAUSE
	end
	if stateName == "disengage" then
		return "S'eloigner", INTENT_ICON_MOVE
	end
	if actionRules and type(actionRules.GetActiveLabelIcon) == "function" then
		local label, icon = actionRules.GetActiveLabelIcon("walk", npc)
		local iconOk = (type(icon) == "string" and icon ~= "") or type(icon) == "number"
		if type(label) == "string" and label ~= "" and iconOk then
			return label, icon
		end
	end
	return "Se promener", INTENT_ICON_MOVE
end

function BuildNpcIntentions(npc, maxCount)
	local out = {}
	local cap = math.max(1, math.floor(tonumber(maxCount) or NPC_INTENT_QUEUE_MAX))
	local function AddIntent(label, icon, isCurrent, source, meta)
		AppendNpcIntent(out, cap, label, icon, isCurrent, source, meta)
	end

	local order = type(npc and npc.manualOrder) == "table" and npc.manualOrder or nil
	if order then
		local label, icon = GetNpcIntentFromOrder(order)
		AddIntent(label, icon, true, tostring(order.source or "player"), {
			cancelable = true,
			slotType = "manual",
			kind = tostring(order.kind or ""),
			purpose = tostring(order.purpose or ""),
		})
	else
		local label, icon = GetNpcIntentFromBehavior(npc)
		AddIntent(label, icon, true, "state", {
			cancelable = false,
			slotType = "state",
		})
	end

	local queue = type(npc and npc.manualOrderQueue) == "table" and npc.manualOrderQueue or nil
	if queue then
		for i = 1, #queue do
			local entry = queue[i]
			local label, icon = GetNpcIntentFromOrder(entry)
			AddIntent(label, icon, false, tostring(entry and entry.source or "player"), {
				cancelable = true,
				slotType = "queue",
				queueIndex = i,
				kind = tostring(entry and entry.kind or ""),
				purpose = tostring(entry and entry.purpose or ""),
			})
			if #out >= cap then
				return out
			end
		end
	end

	return out
end

function BuildNpcSnapshotRow(npc, index, includeDebugPaths)
	if type(npc) ~= "table" then
		return nil
	end
	local withDebugPaths = includeDebugPaths == true
	local needs = type(npc.needs) == "table" and npc.needs or {}
	local order = type(npc.manualOrder) == "table" and npc.manualOrder or nil
	local orderKind = tostring(order and order.kind or "")
	local orderPurpose = tostring(order and order.purpose or "")
	local orderSource = tostring(order and order.source or "")
	local pathWaypoints = nil
	local pathIndex = 1
	if withDebugPaths then
		pathWaypoints = {}
		pathIndex = tonumber(order and order.pathIndex) or 1
		if type(order) == "table" and type(order.pathWaypoints) == "table" then
			for j = 1, #order.pathWaypoints do
				local p = order.pathWaypoints[j]
				pathWaypoints[#pathWaypoints + 1] = {
					u = Clamp(tonumber(p and p.u) or 0.5, 0, 1),
					v = Clamp(tonumber(p and p.v) or 0.5, 0, 1),
				}
			end
		end
	end
	return {
		index = index,
		id = tostring(npc.persistentId or ("npc_" .. tostring(index))),
		name = npc.displayName or BuildFallbackName(index),
		portraitAtlas = tostring(npc.portraitAtlas or NPC_FALLBACK_ATLAS),
		portraitUnit = (type(npc.portraitUnit) == "string" and npc.portraitUnit ~= "") and npc.portraitUnit or nil,
		isPlayerHero = tostring(npc.persistentId or "") == NPC_PLAYER_HERO_ID
			or tostring(npc.portraitUnit or "") == "player"
			or index == 1,
		playable = npc.isRegisseuse ~= true,
		isRegisseuse = npc.isRegisseuse == true,
		u = tonumber(npc.u) or 0.5,
		v = tonumber(npc.v) or 0.5,
		currentLieuId = (type(npc.currentLieuId) == "string" and npc.currentLieuId ~= "") and npc.currentLieuId or nil,
		currentLieuType = (type(npc.currentLieuType) == "string" and npc.currentLieuType ~= "")
				and npc.currentLieuType
			or nil,
		behaviorState = Npc_GetSocialState(npc),
		orderKind = orderKind,
		orderPurpose = orderPurpose,
		orderSource = orderSource,
		orderQueueCount = GetNpcManualOrderQueueSize(npc),
		intentions = BuildNpcIntentions(npc, NPC_INTENT_QUEUE_MAX),
		debugPathWaypoints = pathWaypoints,
		debugPathIndex = math.max(1, math.floor(pathIndex)),
		needs = {
			social = tonumber(needs.social) or 0,
			fatigue = tonumber(needs.fatigue) or 0,
			faim = tonumber(needs.faim) or 0,
			distraction = tonumber(needs.distraction) or 0,
		},
	}
end

function GetNpcSnapshot(includeDebugPaths)
	local out = {}
	for i = 1, #npcPool do
		local npc = npcPool[i]
		out[#out + 1] = BuildNpcSnapshotRow(npc, i, includeDebugPaths == true)
	end
	return out
end

function SetTimeContext(ctx)
	currentTimeContext = NormalizeTimeContext(ctx)
	return true
end

function GetTimeContext()
	return NormalizeTimeContext(currentTimeContext)
end

SyncBaseSize()
InitNpcs()

__runtime = {
	RenderAll = Npc_RenderAll,
	UpdateAndRender = Npc_UpdateAndRender,
	StepSimulation = function(elapsed, opts)
		if type(StepSimulation) == "function" then
			return StepSimulation(elapsed, opts)
		end
		if type(Npc_UpdateAndRender) == "function" then
			return Npc_UpdateAndRender(elapsed, opts)
		end
		return false
	end,
	FlushPersistenceNow = function()
		if type(SaveNpcPersistence) == "function" then
			SaveNpcPersistence()
			return true
		end
		return false
	end,
	GetBootstrapPersistenceEpoch = function()
		if type(GetBootstrapPersistenceEpoch) == "function" then
			return tonumber(GetBootstrapPersistenceEpoch()) or 0
		end
		return 0
	end,
	BeginVirtualClock = function(baseNowSec)
		if type(BeginVirtualClock) == "function" then
			return BeginVirtualClock(baseNowSec)
		end
		return 0
	end,
	EndVirtualClock = function()
		if type(EndVirtualClock) == "function" then
			return EndVirtualClock()
		end
		return false
	end,
	ApplyApproximateOfflineDays = function(dayCount, opts)
		if type(ApplyApproximateOfflineDays) == "function" then
			return ApplyApproximateOfflineDays(dayCount, opts)
		end
		return false, 0
	end,
	ApplyApproximateOfflineSeconds = function(elapsedSec, opts)
		if type(ApplyApproximateOfflineSeconds) == "function" then
			return ApplyApproximateOfflineSeconds(elapsedSec, opts)
		end
		return false, 0
	end,
	SetSelectedNpc = function(selector)
		local id = tostring(selector or "")
		if id == "" then
			state._selectedNpcId = nil
		else
			state._selectedNpcId = id
		end
		return true
	end,
	SetNpcName = SetNpcName,
	SetTimeContext = SetTimeContext,
	GetTimeContext = GetTimeContext,
	GetNpcSnapshot = GetNpcSnapshot,
	GetNpcPickerSnapshot = function()
		local out = {}
		for i = 1, #npcPool do
			local npc = npcPool[i]
			local inLieu = type(npc and npc.currentLieuId) == "string" and tostring(npc.currentLieuId) ~= ""
			if not inLieu then
				out[#out + 1] = {
					id = tostring(npc and npc.persistentId or ("npc_" .. tostring(i))),
					name = (npc and npc.displayName) or BuildFallbackName(i),
					u = tonumber(npc and npc.u) or 0.5,
					v = tonumber(npc and npc.v) or 0.5,
					isPlayerHero = tostring(npc and npc.persistentId or "") == NPC_PLAYER_HERO_ID
						or tostring(npc and npc.portraitUnit or "") == "player"
						or i == 1,
					playable = not (npc and npc.isRegisseuse == true),
					isRegisseuse = npc and npc.isRegisseuse == true or false,
				}
			end
		end
		return out
	end,
	GetNpcDetailSnapshot = function(selector, includeDebugPaths)
		local npc, index = FindNpcBySelector(selector)
		if not (npc and index) then
			return nil
		end
		return BuildNpcSnapshotRow(npc, index, includeDebugPaths == true)
	end,
	OrderTalkWith = OrderNpcTalkWith,
	OrderJoinConversation = OrderNpcJoinConversation,
	GetConversationJoinInfo = GetNpcConversationJoinInfo,
	OrderGoToLieuType = OrderNpcGoToLieuType,
	OrderGoToPoint = OrderNpcGoToPoint,
	SetRegisseuseAnchor = function(selector, targetU, targetV, radius)
		local regisseuse = nil
		if selector ~= nil then
			local selected = FindNpcBySelector and select(1, FindNpcBySelector(selector)) or nil
			if selected and selected.isRegisseuse == true then
				regisseuse = selected
			end
		end
		if not regisseuse then
			for i = 1, #npcPool do
				local npc = npcPool[i]
				if npc and npc.isRegisseuse == true then
					regisseuse = npc
					break
				end
			end
		end
		if not regisseuse then
			return false, "regisseuse_not_found"
		end
		local u = tonumber(targetU)
		local v = tonumber(targetV)
		if not (u and v) then
			return false, "invalid_position"
		end
		u = Clamp(u, 0, 1)
		v = Clamp(v, 0, 1)
		if not IsPointWalkable(u, v) then
			return false, "invalid_position"
		end
		regisseuse.regieCenterU = u
		regisseuse.regieCenterV = v
		regisseuse.regieRadius = Clamp(
			tonumber(radius) or tonumber(regisseuse.regieRadius) or 0.040,
			0.015,
			0.090
		)
		regisseuse.regieTargetU = nil
		regisseuse.regieTargetV = nil
		regisseuse.regieWait = 0
		if type(regisseuse.manualOrder) ~= "table" then
			regisseuse.zoneShiftTargetU = nil
			regisseuse.zoneShiftTargetV = nil
			regisseuse.zoneShiftGoalU = nil
			regisseuse.zoneShiftGoalV = nil
			regisseuse.zoneShiftPathWaypoints = nil
			regisseuse.zoneShiftPathIndex = nil
		end
		SaveNpcPersistence()
		return true, {
			u = regisseuse.regieCenterU,
			v = regisseuse.regieCenterV,
			radius = regisseuse.regieRadius,
		}
	end,
	CancelNpcIntent = CancelNpcIntent,
	CancelNpcOrder = CancelNpcOrder,
}

end

return Modules
