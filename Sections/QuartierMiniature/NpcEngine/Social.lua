local ADDON, ns = ...

ns.QuartierMiniatureNpcEngine = ns.QuartierMiniatureNpcEngine or {}
ns.QuartierMiniatureNpcEngine.Modules = ns.QuartierMiniatureNpcEngine.Modules or {}
local Modules = ns.QuartierMiniatureNpcEngine.Modules

function Modules.InstallSocial(ctx, moduleEnv)
	if type(ctx) ~= "table" or type(moduleEnv) ~= "table" then
		return nil
	end
	setfenv(1, moduleEnv)

function Npc_RequestPostDiscussionZoneShift(a, b)
	if not (navCache.hasRoutes and navCache.hasPlazas) then
		return false
	end

	local first, second = a, b
	if math.random() < 0.5 then
		first, second = b, a
	end

	local function TryAssignShift(npc)
		if not npc then
			return false
		end
		return Npc_AssignZoneShiftTarget(npc, "plaza", true) or Npc_AssignZoneShiftTarget(npc, "route")
	end

	if TryAssignShift(first) then
		return true
	end
	return TryAssignShift(second)
end

function Npc_RequestZoneExit(npc)
	if not npc then
		return false
	end
	return Npc_AssignZoneShiftTarget(npc, "plaza", true) or Npc_AssignZoneShiftTarget(npc, "route")
end

function IsSocialPartnerValid(npc, partner)
	if not npc or not partner or partner == npc then
		return false
	end
	if type(partner) ~= "table" then
		return false
	end
	if not partner.frame then
		return false
	end
	return true
end

GenerateConversationGroupId = function()
	npcConversationSerial = npcConversationSerial + 1
	local nowMs = math.floor(NowSec() * 1000)
	return "conv_" .. tostring(nowMs) .. "_" .. tostring(npcConversationSerial)
end

IsConversationState = function(stateName)
	return stateName == "discussion" or stateName == "approach"
end

IsNpcInConversationState = function(npc)
	local stateName = tostring(npc and npc.behaviorState or "")
	return IsConversationState(stateName)
end

GetConversationMembers = function(groupId)
	local members = {}
	local gid = tostring(groupId or "")
	if gid == "" then
		return members
	end
	for i = 1, #npcPool do
		local other = npcPool[i]
		if other and tostring(other.conversationGroupId or "") == gid and IsNpcInConversationState(other) then
			members[#members + 1] = other
		end
	end
	return members
end

GetConversationGroupIdForNpc = function(npc)
	if not npc then
		return nil
	end
	local gid = tostring(npc.conversationGroupId or "")
	if gid ~= "" and IsNpcInConversationState(npc) then
		local members = GetConversationMembers(gid)
		if #members >= 2 then
			return gid, members
		end
	end
	return nil, nil
end

AreNpcsInSameConversation = function(a, b)
	if not (a and b) or a == b then
		return false
	end
	local ag = tostring(a.conversationGroupId or "")
	local bg = tostring(b.conversationGroupId or "")
	if ag == "" or bg == "" or ag ~= bg then
		return false
	end
	return IsNpcInConversationState(a) and IsNpcInConversationState(b)
end

PickConversationPartnerForNpc = function(npc, groupId)
	if not npc then
		return nil
	end
	local gid = tostring(groupId or npc.conversationGroupId or "")
	if gid == "" then
		return nil
	end
	local best, bestD2 = nil, math.huge
	local nu = tonumber(npc.u) or 0.5
	local nv = tonumber(npc.v) or 0.5
	local members = GetConversationMembers(gid)
	for i = 1, #members do
		local other = members[i]
		if other ~= npc and IsSocialPartnerValid(npc, other) then
			local ou = tonumber(other.u) or nu
			local ov = tonumber(other.v) or nv
			local dx = ou - nu
			local dy = ov - nv
			local d2 = (dx * dx) + (dy * dy)
			if d2 < bestD2 then
				best = other
				bestD2 = d2
			end
		end
	end
	return best
end

EnsureConversationPartner = function(npc)
	if not npc or not IsNpcInConversationState(npc) then
		return
	end
	local partner = npc.behaviorPartner
	if IsSocialPartnerValid(npc, partner) and AreNpcsInSameConversation(npc, partner) then
		return
	end
	npc.behaviorPartner = PickConversationPartnerForNpc(npc)
end

RebindConversationMembers = function(groupId)
	local members = GetConversationMembers(groupId)
	for i = 1, #members do
		EnsureConversationPartner(members[i])
	end
end

function GetNpcSocialReserve(npc)
	local needs = type(npc and npc.needs) == "table" and npc.needs or nil
	return Clamp(tonumber(needs and needs.social) or 100, 0, 100)
end

function IsAutoSocialEligible(npc)
	return GetNpcSocialReserve(npc) <= NPC_AUTO_SOCIAL_MAX_RESERVE
end

function Npc_PrepareDiscussionSocialBonus(a, b, sourceTag, durationSec)
	local source = tostring(sourceTag or "auto")
	local duration = math.max(0.10, tonumber(durationSec) or 1.0)
	local function ApplyOne(npc, partner)
		if type(npc) ~= "table" then
			return
		end
		local partnerId = tostring(partner and partner.persistentId or "")
		if partnerId == "" then
			return
		end
		local gainTotal = 0
		if source == "player" then
			local lastPartnerId = tostring(npc.lastPlayerSocialGainPartnerId or "")
			npc.lastPlayerSocialGainPartnerId = partnerId
			if lastPartnerId == partnerId then
				gainTotal = 0
			else
				gainTotal = RandRange(NPC_SOCIAL_BONUS_PLAYER_MIN, NPC_SOCIAL_BONUS_PLAYER_MAX)
			end
		else
			gainTotal = RandRange(NPC_SOCIAL_BONUS_AUTO_MIN, NPC_SOCIAL_BONUS_AUTO_MAX)
		end
		npc.discussionSocialBonusTotal = gainTotal
		npc.discussionSocialBonusApplied = 0
		npc.discussionSocialBonusDuration = duration
		npc.discussionSocialBonusSource = source
		npc.discussionSocialBonusPartnerId = partnerId
	end
	ApplyOne(a, b)
	ApplyOne(b, a)
end

function Npc_BeginApproachPair(a, b, sourceTag, conversationGroupId)
	if not IsSocialPartnerValid(a, b) then
		return false
	end
	if not Npc_RegisterZoneAction(a) then
		Npc_RequestZoneExit(a)
		return false
	end
	if not Npc_RegisterZoneAction(b) then
		Npc_RequestZoneExit(b)
		return false
	end
	local groupId = tostring(conversationGroupId or a.conversationGroupId or b.conversationGroupId or "")
	if groupId == "" then
		groupId = GenerateConversationGroupId()
	end

	a.behaviorState = "approach"
	a.behaviorPartner = b
	a.conversationGroupId = groupId
	a.behaviorTimer = RandRange(2.0, 5.0)
	a.behaviorCooldown = 0
	a.duoTargetU = nil
	a.duoTargetV = nil
	a.approachSource = tostring(sourceTag or a.approachSource or "auto")

	b.behaviorState = "approach"
	b.behaviorPartner = a
	b.conversationGroupId = groupId
	b.behaviorTimer = RandRange(2.0, 5.0)
	b.behaviorCooldown = 0
	b.duoTargetU = nil
	b.duoTargetV = nil
	b.approachSource = tostring(sourceTag or b.approachSource or "auto")
	return true
end

function Npc_BeginDiscussionPair(a, b, duration, sourceTag, conversationGroupId)
	if not IsSocialPartnerValid(a, b) then
		return false
	end
	local discussionSource = tostring(sourceTag or a.approachSource or b.approachSource or "auto")
	if discussionSource ~= "player" then
		if (not IsAutoSocialEligible(a)) or (not IsAutoSocialEligible(b)) then
			return false
		end
	end
	if not Npc_RegisterZoneAction(a) then
		Npc_RequestZoneExit(a)
		return false
	end
	if not Npc_RegisterZoneAction(b) then
		Npc_RequestZoneExit(b)
		return false
	end
	local talkFor = tonumber(duration) or RandRange(NPC_SOCIAL_DISCUSS_MIN, NPC_SOCIAL_DISCUSS_MAX)
	if NPC_SOCIAL_DISCUSS_VARIANCE > 0 then
		local jitter = 1 + RandRange(-NPC_SOCIAL_DISCUSS_VARIANCE, NPC_SOCIAL_DISCUSS_VARIANCE)
		talkFor = talkFor * jitter
	end
	if discussionSource == "player" and math.random() < NPC_SOCIAL_DISCUSS_LONG_CHANCE then
		talkFor = talkFor * RandRange(NPC_SOCIAL_DISCUSS_LONG_MULT_MIN, NPC_SOCIAL_DISCUSS_LONG_MULT_MAX)
	end
	if discussionSource == "player" then
		talkFor = Clamp(talkFor, NPC_SOCIAL_DISCUSS_MIN, NPC_SOCIAL_DISCUSS_MAX)
	else
		talkFor = Clamp(talkFor, NPC_SOCIAL_AUTO_SMALLTALK_MIN, NPC_SOCIAL_AUTO_SMALLTALK_MAX)
	end
	local groupId = tostring(conversationGroupId or a.conversationGroupId or b.conversationGroupId or "")
	if groupId == "" then
		groupId = GenerateConversationGroupId()
	end

	a.behaviorState = "discussion"
	a.behaviorPartner = b
	a.conversationGroupId = groupId
	a.behaviorTimer = talkFor
	a.behaviorCooldown = 0
	a.duoTargetU = nil
	a.duoTargetV = nil
	a.approachSource = nil

	b.behaviorState = "discussion"
	b.behaviorPartner = a
	b.conversationGroupId = groupId
	b.behaviorTimer = talkFor
	b.behaviorCooldown = 0
	b.duoTargetU = nil
	b.duoTargetV = nil
	b.approachSource = nil
	Npc_PrepareDiscussionSocialBonus(a, b, discussionSource, talkFor)
	TriggerGlobalTalkLock(NPC_GLOBAL_TALK_LOCK_DURATION)
	return true
end

function PickSocialWalkTarget(baseU, baseV, radius, npc)
	local ru = Clamp(tonumber(baseU) or 0.5, 0, 1)
	local rv = Clamp(tonumber(baseV) or 0.5, 0, 1)
	local rr = Clamp(tonumber(radius) or NPC_SOCIAL_DUO_TARGET_RADIUS, 0.005, 0.40)
	for _ = 1, 40 do
		local a = RandRange(0, math.pi * 2)
		local d = RandRange(rr * 0.2, rr)
		local u = Clamp(ru + (math.cos(a) * d), 0, 1)
		local v = Clamp(rv + (math.sin(a) * d), 0, 1)
		local zoneKey = select(1, GetZoneKeyAtPoint(u, v))
		if IsPointWalkable(u, v) and IsZoneEntryAllowed(npc, zoneKey, false) then
			return u, v
		end
	end
	local u, v = PickRandomWalkablePoint()
	local zoneKey = select(1, GetZoneKeyAtPoint(u, v))
	if IsZoneEntryAllowed(npc, zoneKey, false) then
		return u, v
	end
	return nil, nil
end

function Npc_PickLongWalkTarget(npc, minDist, maxDist)
	local baseU = tonumber(npc and npc.u) or 0.5
	local baseV = tonumber(npc and npc.v) or 0.5
	local minD = Clamp(tonumber(minDist) or NPC_LONG_GOAL_MIN_DIST, 0, 1.5)
	local maxD = Clamp(tonumber(maxDist) or NPC_LONG_GOAL_MAX_DIST, minD + 0.01, 1.8)
	local minD2 = minD * minD
	local maxD2 = maxD * maxD
	if navCache.hasPlazas and math.random() < NPC_LONG_GOAL_PLAZA_BIAS then
		for _ = 1, 72 do
			local u, v = PickRandomPlazaWalkPoint(npc)
			if u and v then
				local dx = u - baseU
				local dy = v - baseV
				local d2 = (dx * dx) + (dy * dy)
				if d2 >= minD2 and d2 <= maxD2 then
					return u, v
				end
			end
		end
	end
	for _ = 1, 120 do
		local u, v = PickRandomWalkablePoint()
		local dx = u - baseU
		local dy = v - baseV
		local d2 = (dx * dx) + (dy * dy)
		local zoneKey = select(1, GetZoneKeyAtPoint(u, v))
		if d2 >= minD2 and d2 <= maxD2 and IsZoneEntryAllowed(npc, zoneKey, false) then
			return u, v
		end
	end
	return nil, nil
end

function Npc_BeginDuoWalkPair(a, b, duration)
	if not IsSocialPartnerValid(a, b) then
		return false
	end
	if not Npc_RegisterZoneAction(a) then
		Npc_RequestZoneExit(a)
		return false
	end
	if not Npc_RegisterZoneAction(b) then
		Npc_RequestZoneExit(b)
		return false
	end
	local duoFor = Clamp(tonumber(duration) or RandRange(NPC_SOCIAL_DUO_WALK_MIN, NPC_SOCIAL_DUO_WALK_MAX), 0.5, 80)
	local midU = ((tonumber(a.u) or 0.5) + (tonumber(b.u) or 0.5)) * 0.5
	local midV = ((tonumber(a.v) or 0.5) + (tonumber(b.v) or 0.5)) * 0.5
	local tu, tv = PickSocialWalkTarget(midU, midV, NPC_SOCIAL_DUO_TARGET_RADIUS, a)
	if not tu or not tv then
		return false
	end

	a.behaviorState = "duo_walk"
	a.behaviorPartner = b
	a.behaviorTimer = duoFor
	a.behaviorCooldown = 0
	a.duoTargetU = tu
	a.duoTargetV = tv

	b.behaviorState = "duo_walk"
	b.behaviorPartner = a
	b.behaviorTimer = duoFor
	b.behaviorCooldown = 0
	b.duoTargetU = tu
	b.duoTargetV = tv
	return true
end

function Npc_BeginSelfPause(npc, edgeInfo, duration, zoneKey, options)
	if not npc then
		return false
	end
	local forceZoneAction = type(options) == "table" and options.forceZoneAction == true
	local ignoreEdge = type(options) == "table" and options.ignoreEdge == true
	if forceZoneAction then
		Npc_UpdateZoneTracking(npc)
		npc.zoneActionCount = (tonumber(npc.zoneActionCount) or 0) + 1
	else
		if not Npc_RegisterZoneAction(npc) then
			Npc_RequestZoneExit(npc)
			return false
		end
	end
	local pauseFor = Clamp(tonumber(duration) or RandRange(NPC_SELF_PAUSE_MIN, NPC_SELF_PAUSE_MAX), 0.2, 600)
	npc.behaviorState = "self_pause"
	npc.behaviorPartner = nil
	npc.conversationGroupId = nil
	npc.behaviorTimer = pauseFor
	npc.behaviorCooldown = 0
	npc.duoTargetU = nil
	npc.duoTargetV = nil
	npc.selfPauseCooldown = 0
	npc.selfPauseIgnoreEdge = ignoreEdge and true or nil
	npc.currentSelfPauseZoneKey = zoneKey
	if zoneKey then
		npc.lastSelfPauseZoneKey = zoneKey
	end

	local lookHeading = nil
	if edgeInfo then
		local cx = tonumber(edgeInfo.centerU)
		local cy = tonumber(edgeInfo.centerV)
		if cx and cy then
			lookHeading = AngleFromVector(cx - (tonumber(npc.u) or cx), cy - (tonumber(npc.v) or cy))
		end
	end
	if not lookHeading then
		lookHeading = tonumber(npc.walkHeading) or RandRange(0, TWO_PI)
	end
	npc.pauseLookHeading = WrapAngle(lookHeading + RandRange(-0.25, 0.25))
	return true
end

function GetNpcManualOrderQueue(npc)
	if not npc then
		return nil
	end
	if type(npc.manualOrderQueue) ~= "table" then
		npc.manualOrderQueue = {}
	end
	return npc.manualOrderQueue
end

function GetNpcManualOrderQueueSize(npc)
	local queue = type(npc and npc.manualOrderQueue) == "table" and npc.manualOrderQueue or nil
	return queue and #queue or 0
end

function GetNpcManualOrderQueueSizeBySource(npc, sourceTag)
	local queue = type(npc and npc.manualOrderQueue) == "table" and npc.manualOrderQueue or nil
	if not queue or #queue < 1 then
		return 0
	end
	local wanted = tostring(sourceTag or "")
	if wanted == "" then
		return #queue
	end
	local count = 0
	for i = 1, #queue do
		local entrySource = tostring(queue[i] and queue[i].source or "player")
		if entrySource == wanted then
			count = count + 1
		end
	end
	return count
end

function EnqueueNpcManualOrder(npc, entry)
	if not npc or type(entry) ~= "table" then
		return false, "invalid_order"
	end
	local queue = GetNpcManualOrderQueue(npc)
	if not queue then
		return false, "queue_unavailable"
	end
	if #queue >= NPC_INTENT_QUEUE_MAX then
		return false, "queue_full"
	end
	queue[#queue + 1] = entry
	return true, "queued"
end

function PopNpcManualOrder(npc)
	local queue = type(npc and npc.manualOrderQueue) == "table" and npc.manualOrderQueue or nil
	if not queue or #queue < 1 then
		return nil
	end
	local entry = queue[1]
	table.remove(queue, 1)
	return entry
end

function ClearNpcManualOrderQueue(npc)
	if not npc then
		return
	end
	npc.manualOrderQueue = {}
end

function Npc_ClearManualOrder(npc, clearShiftTarget)
	if not npc then
		return
	end
	npc.manualOrder = nil
	if clearShiftTarget then
		Npc_ClearZoneShiftTarget(npc)
	end
end

function RemoveNpcManualOrderQueueBySource(npc, sourceTag)
	local queue = type(npc and npc.manualOrderQueue) == "table" and npc.manualOrderQueue or nil
	if not queue or #queue < 1 then
		return 0
	end
	local wanted = tostring(sourceTag or "")
	if wanted == "" then
		return 0
	end
	local kept = {}
	local removed = 0
	for i = 1, #queue do
		local entry = queue[i]
		local entrySource = tostring(entry and entry.source or "player")
		if entrySource == wanted then
			removed = removed + 1
		else
			kept[#kept + 1] = entry
		end
	end
	npc.manualOrderQueue = kept
	return removed
end

function PurgeNpcAutoOrdersForPlayer(npc)
	if not npc then
		return 0
	end
	local removed = RemoveNpcManualOrderQueueBySource(npc, "auto")
	removed = removed + RemoveNpcManualOrderQueueBySource(npc, "auto_poi")
	local order = type(npc.manualOrder) == "table" and npc.manualOrder or nil
	if order then
		local orderSource = tostring(order.source or "player")
		local orderPurpose = tostring(order.purpose or "")
		if orderSource == "auto" or orderSource == "auto_poi" or orderPurpose == "move_place" then
			Npc_ClearManualOrder(npc, true)
			removed = removed + 1
		end
	end
	if removed > 0 then
		npc.waitTimer = 0
		npc.zoneRoutineStep = "move"
		npc.zoneRoutinePause = 0
		npc.zoneRoutineTargetU = nil
		npc.zoneRoutineTargetV = nil
		npc.zoneRoutineTargetTtl = 0
		npc.zoneRoutineTargetIsPoi = nil
	end
	local stateName = tostring(Npc_GetSocialState(npc) or "walk")
	if stateName == "self_pause" and type(npc.manualOrder) ~= "table" then
		Npc_ResetSocialState(npc, false)
		Npc_ClearManualOrder(npc, true)
	end
	return removed
end

function Npc_ForceImmediatePlayerOrderState(npc)
	if not npc then
		return
	end
	local partner = npc.behaviorPartner
	if IsSocialPartnerValid(npc, partner) and partner.behaviorPartner == npc then
		Npc_ResetSocialState(partner, true)
	end
	Npc_ResetSocialState(npc, false)
	ClearNpcManualOrderQueue(npc)
	Npc_ClearManualOrder(npc, true)
	Npc_ClearZoneShiftTarget(npc)
	npc.waitTimer = 0
	npc.behaviorCooldown = 0
	npc.selfPauseCooldown = 0
	npc.zoneRoutineStep = "move"
	npc.zoneRoutinePause = 0
	npc.zoneRoutineTargetU = nil
	npc.zoneRoutineTargetV = nil
	npc.zoneRoutineTargetTtl = 0
	npc.zoneRoutineTargetIsPoi = nil
	npc.walkLieuExitRetryAt = 0
end

function Npc_BreakCurrentSocialLink(npc)
	if not npc then
		return
	end
	local partner = npc.behaviorPartner
	if IsSocialPartnerValid(npc, partner) and partner.behaviorPartner == npc then
		Npc_ResetSocialState(partner, true)
	end
	Npc_ResetSocialState(npc, false)
end

function NormalizeLieuType(rawType)
	local t = string.lower(tostring(rawType or ""))
	if t == "restaurant" then
		return "auberge"
	end
	return t
end

function GetLieuCapacityByType(rawType)
	local t = NormalizeLieuType(rawType)
	if t == "chaumiere" then
		return 2
	end
	if t == "auberge" then
		return 5
	end
	if t == "taverne" then
		return 3
	end
	return nil
end

function IsLieuAtCapacityForNpc(lieu, npc)
	if type(lieu) ~= "table" then
		return false, 0, nil
	end
	local cap = GetLieuCapacityByType(lieu and lieu.lieuType)
	if not cap then
		return false, 0, nil
	end
	local count = CountNpcsInLieu(lieu, npc)
	local inside = IsPointInPlaza(lieu, tonumber(npc and npc.u) or 0.5, tonumber(npc and npc.v) or 0.5)
	if inside then
		return false, count, cap
	end
	return count >= cap, count, cap
end

function GetLieuStableId(lieu, index)
	local id = tostring(lieu and lieu.id or "")
	if id ~= "" then
		return id
	end
	return "lieu_" .. tostring(index or 0)
end

function Npc_FindLieuTargetPoint(npc, wantedType, opts)
	if not navCache.hasLieux then
		return nil
	end
	opts = type(opts) == "table" and opts or {}
	local wanted = NormalizeLieuType(wantedType)
	local excludeLieuId = tostring(opts.excludeLieuId or "")
	local allowFullFallback = opts.allowFullFallback == true
	local nu = tonumber(npc and npc.u) or 0.5
	local nv = tonumber(npc and npc.v) or 0.5
	local bestLieu, bestDist, bestIndex = nil, nil, nil
	local bestFullLieu, bestFullDist, bestFullIndex = nil, nil, nil
	for i = 1, #navCache.lieux do
		local lieu = navCache.lieux[i]
		local lieuId = GetLieuStableId(lieu, i)
		local lieuType = NormalizeLieuType(lieu and lieu.lieuType)
		if (excludeLieuId == "" or lieuId ~= excludeLieuId) and (wanted == "" or lieuType == wanted) then
			local dist = select(1, DistancePointToPlaza(lieu, nu, nv))
			if dist then
				local full = select(1, IsLieuAtCapacityForNpc(lieu, npc))
				if not full then
					if (not bestDist) or dist < bestDist then
						bestDist = dist
						bestLieu = lieu
						bestIndex = i
					end
				elseif allowFullFallback then
					if (not bestFullDist) or dist < bestFullDist then
						bestFullDist = dist
						bestFullLieu = lieu
						bestFullIndex = i
					end
				end
			end
		end
	end
	if not bestLieu and allowFullFallback then
		bestLieu = bestFullLieu
		bestDist = bestFullDist
		bestIndex = bestFullIndex
	end
	if not bestLieu then
		return nil
	end

	for _ = 1, 36 do
		local u, v = PickRandomPointInPlaza(bestLieu)
		local zoneKey = select(1, GetZoneKeyAtPoint(u, v))
		if IsPointWalkable(u, v) and IsZoneEntryAllowed(npc, zoneKey, true) then
			return {
				lieu = bestLieu,
				lieuId = GetLieuStableId(bestLieu, bestIndex),
				u = u,
				v = v,
			}
		end
	end
	return {
		lieu = bestLieu,
		lieuId = GetLieuStableId(bestLieu, bestIndex),
		u = Clamp(tonumber(bestLieu.centerU) or 0.5, 0, 1),
		v = Clamp(tonumber(bestLieu.centerV) or 0.5, 0, 1),
	}
end

function Dist2Points(au, av, bu, bv)
	local dx = (tonumber(au) or 0) - (tonumber(bu) or 0)
	local dy = (tonumber(av) or 0) - (tonumber(bv) or 0)
	return (dx * dx) + (dy * dy)
end

function GetNpcPoiRepeatPenalty(npc, poiId)
	local pid = tostring(poiId or "")
	if pid == "" then
		return 1.0
	end
	if pid == tostring(npc and npc.poiRecent1 or "") then
		return 6.0
	end
	if pid == tostring(npc and npc.poiRecent2 or "") then
		return 3.2
	end
	if pid == tostring(npc and npc.poiRecent3 or "") then
		return 1.8
	end
	return 1.0
end

function RegisterNpcRecentPoi(npc, poiId)
	if not npc then
		return
	end
	local pid = tostring(poiId or "")
	if pid == "" then
		return
	end
	if pid == tostring(npc.poiRecent1 or "") then
		return
	end
	npc.poiRecent3 = npc.poiRecent2
	npc.poiRecent2 = npc.poiRecent1
	npc.poiRecent1 = pid
end

function PickDiversePoiCandidate(candidates)
	if type(candidates) ~= "table" or #candidates < 1 then
		return nil
	end
	table.sort(candidates, function(a, b)
		return (tonumber(a and a.score) or math.huge) < (tonumber(b and b.score) or math.huge)
	end)
	local topN = math.min(#candidates, 4)
	local totalWeight = 0
	for i = 1, topN do
		local score = math.max(0.000001, tonumber(candidates[i] and candidates[i].score) or 1.0)
		local weight = 1.0 / score
		candidates[i]._pickWeight = weight
		totalWeight = totalWeight + weight
	end
	if totalWeight <= 0 then
		return candidates[1]
	end
	local roll = math.random() * totalWeight
	local accum = 0
	for i = 1, topN do
		accum = accum + (tonumber(candidates[i] and candidates[i]._pickWeight) or 0)
		if roll <= accum then
			return candidates[i]
		end
	end
	return candidates[topN]
end

function GetNextNpcAutoIntentDelay()
	local rate = GetTimeAutoIntentRate()
	return RandRange(NPC_AUTO_INTENT_INTERVAL_MIN, NPC_AUTO_INTENT_INTERVAL_MAX) / math.max(0.20, rate)
end


end

return Modules
