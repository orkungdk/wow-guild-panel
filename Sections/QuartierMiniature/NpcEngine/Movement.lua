local ADDON, ns = ...

ns.QuartierMiniatureNpcEngine = ns.QuartierMiniatureNpcEngine or {}
ns.QuartierMiniatureNpcEngine.Modules = ns.QuartierMiniatureNpcEngine.Modules or {}
local Modules = ns.QuartierMiniatureNpcEngine.Modules

function Modules.InstallMovement(ctx, moduleEnv)
	if type(ctx) ~= "table" or type(moduleEnv) ~= "table" then
		return nil
	end
	setfenv(1, moduleEnv)

function Npc_ProcessManualOrder(npc)
	if not npc then
		return
	end
	local order = npc.manualOrder
	if type(order) ~= "table" then
		return
	end

	local now = NowSec()
	local expiresAt = tonumber(order.expiresAt)
	if expiresAt and expiresAt > 0 and expiresAt <= now then
		Npc_ClearManualOrder(npc, true)
		return
	end

	local kind = tostring(order.kind or "")
	if kind == "join_talk" then
		local partnerId = tostring(order.partnerId or "")
		local partner = FindNpcBySelector and select(1, FindNpcBySelector(partnerId)) or nil
		if not partner or partner == npc then
			Npc_ClearManualOrder(npc, true)
			return
		end
		local groupId = tostring(order.groupId or partner.conversationGroupId or "")
		if groupId == "" then
			Npc_ClearManualOrder(npc, true)
			return
		end
		local members = GetConversationMembers(groupId)
		local alreadyIn = false
		for i = 1, #members do
			if members[i] == npc then
				alreadyIn = true
				break
			end
		end
		if (not alreadyIn) and #members >= NPC_CONVERSATION_MAX_PARTICIPANTS then
			Npc_ClearManualOrder(npc, true)
			return
		end
		local bestPartner = PickConversationPartnerForNpc(npc, groupId) or partner
		local meetU = tonumber(bestPartner and bestPartner.u) or tonumber(partner.u) or 0.5
		local meetV = tonumber(bestPartner and bestPartner.v) or tonumber(partner.v) or 0.5
		local pathU = meetU
		local pathV = meetV
		if #members >= 1 then
			local sumU, sumV = 0, 0
			for i = 1, #members do
				sumU = sumU + (tonumber(members[i] and members[i].u) or meetU)
				sumV = sumV + (tonumber(members[i] and members[i].v) or meetV)
			end
			meetU = sumU / #members
			meetV = sumV / #members
		end
		local now = NowSec()
		local shouldRetarget = (not order.meetU) or (not order.meetV)
		local prevU = tonumber(order.meetU)
		local prevV = tonumber(order.meetV)
		local refreshAt = tonumber(order.meetRefreshAt) or 0
		if (not shouldRetarget) and now >= refreshAt and prevU and prevV then
			local refreshDist2 = math.max((NPC_SOCIAL_POST_TALK_ZONE_REACH * 2.0) ^ 2, 0.00025)
			shouldRetarget = Dist2Points(prevU, prevV, meetU, meetV) > refreshDist2
		end
		if shouldRetarget then
			order.meetU, order.meetV = meetU, meetV
			order.meetRefreshAt = now + 0.35
		end
		Npc_ApplyManualWaypointTarget(
			npc,
			order,
			pathU,
			pathV,
			"manual_talk",
			24
		)

		local pairDist2 = math.huge
		for i = 1, #members do
			local m = members[i]
			if m and m ~= npc then
				local dx = (tonumber(m.u) or meetU) - (tonumber(npc.u) or meetU)
				local dy = (tonumber(m.v) or meetV) - (tonumber(npc.v) or meetV)
				local d2 = (dx * dx) + (dy * dy)
				if d2 < pairDist2 then
					pairDist2 = d2
					bestPartner = m
				end
			end
		end
		local triggerDist = math.max(NPC_SOCIAL_ENCOUNTER_RADIUS * 1.15, NPC_SOCIAL_APPROACH_STOP_DIST * 1.55)
		local triggerDist2 = triggerDist * triggerDist
		if pairDist2 <= triggerDist2 then
			local talkSource = tostring(order.source or "player")
			TryJoinConversation(npc, bestPartner or partner, groupId, talkSource)
			Npc_ClearManualOrder(npc, true)
			return
		end
		return
	end

	if kind == "talk" then
		local partnerId = tostring(order.partnerId or "")
		local partner = FindNpcBySelector and select(1, FindNpcBySelector(partnerId)) or nil
		if not partner or partner == npc then
			Npc_ClearManualOrder(npc, true)
			return
		end

		local partnerOrder = partner.manualOrder
		if type(partnerOrder) ~= "table" or tostring(partnerOrder.kind or "") ~= "talk" then
			Npc_ClearManualOrder(npc, true)
			return
		end
		if tostring(partnerOrder.partnerId or "") ~= tostring(npc.persistentId or "") then
			Npc_ClearManualOrder(npc, true)
			return
		end
		local npcHoldPosition = (order.holdPosition == true) or (tostring(order.talkRole or "") == "anchor")
		local partnerHoldPosition = (partnerOrder.holdPosition == true)
			or (tostring(partnerOrder.talkRole or "") == "anchor")
		if npcHoldPosition then
			Npc_ClearZoneShiftTarget(npc)
		end

		if IsSocialPartnerValid(npc, partner) and partner.behaviorPartner == npc then
			local s = Npc_GetSocialState(npc)
			if s == "approach" or s == "discussion" or s == "duo_walk" then
				Npc_ClearManualOrder(npc, true)
				Npc_ClearManualOrder(partner, true)
				return
			end
		end

		local meetU = tonumber(order.meetU) or tonumber(partnerOrder.meetU)
		local meetV = tonumber(order.meetV) or tonumber(partnerOrder.meetV)
		if not (meetU and meetV) then
			local anchorNpc, moverNpc = partner, npc
			local anchorOrder = partnerOrder
			if npcHoldPosition and not partnerHoldPosition then
				anchorNpc, moverNpc = npc, partner
				anchorOrder = order
			end
			local anchorU = tonumber(anchorOrder and anchorOrder.holdU)
				or tonumber(anchorNpc and anchorNpc.u)
				or 0.5
			local anchorV = tonumber(anchorOrder and anchorOrder.holdV)
				or tonumber(anchorNpc and anchorNpc.v)
				or 0.5
			local zoneKey = select(1, GetZoneKeyAtPoint(anchorU, anchorV))
			if IsPointWalkable(anchorU, anchorV) and IsZoneEntryAllowed(moverNpc, zoneKey, true) then
				meetU, meetV = anchorU, anchorV
			end
			if not meetU or not meetV then
				Npc_ClearManualOrder(npc, true)
				Npc_ClearManualOrder(partner, true)
				return
			end
			order.meetU, order.meetV = meetU, meetV
			partnerOrder.meetU, partnerOrder.meetV = meetU, meetV
		end

		if npcHoldPosition then
			Npc_ClearZoneShiftTarget(npc)
		else
			Npc_ApplyManualWaypointTarget(npc, order, meetU, meetV, "manual_talk", 24)
		end

		local pairDx = (tonumber(partner.u) or 0.5) - (tonumber(npc.u) or 0.5)
		local pairDy = (tonumber(partner.v) or 0.5) - (tonumber(npc.v) or 0.5)
		local pairDist2 = (pairDx * pairDx) + (pairDy * pairDy)
		local meetReach = math.max(NPC_SOCIAL_POST_TALK_ZONE_REACH * 1.8, 0.012)
		local meetReach2 = meetReach * meetReach
		local aMeetDx = (tonumber(npc.u) or meetU) - meetU
		local aMeetDy = (tonumber(npc.v) or meetV) - meetV
		local bMeetDx = (tonumber(partner.u) or meetU) - meetU
		local bMeetDy = (tonumber(partner.v) or meetV) - meetV
		local bothAtMeet = ((aMeetDx * aMeetDx) + (aMeetDy * aMeetDy)) <= meetReach2
			and ((bMeetDx * bMeetDx) + (bMeetDy * bMeetDy)) <= meetReach2
		local triggerDist = math.max(NPC_SOCIAL_ENCOUNTER_RADIUS * 1.15, NPC_SOCIAL_APPROACH_STOP_DIST * 1.55)
		local triggerDist2 = triggerDist * triggerDist

		if bothAtMeet or pairDist2 <= triggerDist2 then
			local talkSource = tostring(order.source or "player")
			local talkGroupId = tostring(order.talkGroupId or partnerOrder.talkGroupId or "")
			Npc_BreakCurrentSocialLink(npc)
			Npc_BreakCurrentSocialLink(partner)
			if
				Npc_BeginDiscussionPair(
					npc,
					partner,
					RandRange(NPC_SOCIAL_DISCUSS_MIN, NPC_SOCIAL_DISCUSS_MAX),
					talkSource,
					talkGroupId
				)
			then
				Npc_ClearManualOrder(npc, true)
				Npc_ClearManualOrder(partner, true)
				return
			end
			if Npc_BeginApproachPair(npc, partner, talkSource) then
				Npc_ClearManualOrder(npc, true)
				Npc_ClearManualOrder(partner, true)
				return
			end
		end
		return
	end

	if kind == "lieu_pause" then
		local targetU = tonumber(order.targetU)
		local targetV = tonumber(order.targetV)
		if not (targetU and targetV) then
			Npc_ClearManualOrder(npc, true)
			return
		end

		local waypointU, waypointV = targetU, targetV
		local usesEntryGate = false
		local targetLieu, targetLieuIndex = GetLieuAtPoint(targetU, targetV)
		local orderLieuType = NormalizeLieuType(order.lieuType)
			if targetLieu and orderLieuType ~= "" then
				local nowCheck = NowSec()
				local nextCheckAt = tonumber(order.capacityRecheckAt) or 0
				if nowCheck >= nextCheckAt then
					order.capacityRecheckAt = nowCheck + 0.45
					local isFull = select(1, IsLieuAtCapacityForNpc(targetLieu, npc))
					if isFull then
						local alt = Npc_FindLieuTargetPoint(npc, orderLieuType, {
							excludeLieuId = GetLieuStableId(targetLieu, targetLieuIndex),
							allowFullFallback = false,
						})
						if alt then
							order.targetU = Clamp(tonumber(alt.u) or targetU, 0, 1)
							order.targetV = Clamp(tonumber(alt.v) or targetV, 0, 1)
							order.entryPassed = nil
							order.entryU = nil
							order.entryV = nil
							order.entryR = nil
							order.pathWaypoints = nil
							order.pathIndex = nil
							order.pathLastDist2 = nil
							order.pathCheckAt = 0
							targetU = tonumber(order.targetU) or targetU
							targetV = tonumber(order.targetV) or targetV
							targetLieu, targetLieuIndex = GetLieuAtPoint(targetU, targetV)
							waypointU, waypointV = targetU, targetV
						else
							-- Capacity is strict for lieux: if full and no alternative, abort
							-- this stop and let the NPC resume normal wandering behavior.
							Npc_BreakCurrentSocialLink(npc)
							Npc_ClearManualOrder(npc, true)
							Npc_RequestZoneExit(npc)
							npc.autoOrderRollIn = 0
							return
						end
					end
				end
			end
		local entries = targetLieu and targetLieu.entries
		if type(entries) == "table" and #entries > 0 then
			local npcLieu, npcLieuIndex = GetLieuAtPoint(npc.u, npc.v)
			local insideTargetLieu = (npcLieu and targetLieu and npcLieuIndex == targetLieuIndex)
			if insideTargetLieu then
				order.entryPassed = true
				order.entryU = nil
				order.entryV = nil
				order.entryR = nil
			end
			if (not insideTargetLieu) and order.entryPassed ~= true then
				local entryU = tonumber(order.entryU)
				local entryV = tonumber(order.entryV)
				local entryR = tonumber(order.entryR)
				if not (entryU and entryV) then
					local fromU = tonumber(npc.u) or targetU
					local fromV = tonumber(npc.v) or targetV
					local bestDist2 = nil
					for i = 1, #entries do
						local e = entries[i]
						local eu = tonumber(e and e.u)
						local ev = tonumber(e and e.v)
						local er = Clamp(tonumber(e and (e.radius or e.r)) or 0.010, 0.004, 0.040)
						if eu and ev then
							local ex = eu - fromU
							local ey = ev - fromV
							local d2 = (ex * ex) + (ey * ey)
							if (not bestDist2) or d2 < bestDist2 then
								bestDist2 = d2
								entryU = eu
								entryV = ev
								entryR = er
							end
						end
					end
					order.entryU = entryU
					order.entryV = entryV
					order.entryR = entryR
				end
				if entryU and entryV then
					waypointU = entryU
					waypointV = entryV
					usesEntryGate = true
				end
			end
		end

		Npc_ApplyManualWaypointTarget(npc, order, waypointU, waypointV, "manual_lieu", 36)
		local orderSource = tostring(order.source or "auto")
		if
			orderSource == "player" and (not tonumber(npc.zoneShiftTargetU) or not tonumber(npc.zoneShiftTargetV))
		then
			local near = FindNearestRoutePoint(npc.u, npc.v, 2.0, nil)
			if near and tonumber(near.px) and tonumber(near.py) then
				npc.u = Clamp(tonumber(near.px) or npc.u, 0, 1)
				npc.v = Clamp(tonumber(near.py) or npc.v, 0, 1)
				Npc_EnsureWalkablePosition(npc)
			end
			order.pathWaypoints = nil
			order.pathIndex = nil
			order.pathLastDist2 = nil
			order.pathCheckAt = 0
			Npc_ApplyManualWaypointTarget(npc, order, waypointU, waypointV, "manual_lieu", 48)
		end

		local dx = waypointU - (tonumber(npc.u) or waypointU)
		local dy = waypointV - (tonumber(npc.v) or waypointV)
		local reach = math.max(NPC_SOCIAL_POST_TALK_ZONE_REACH * 1.8, 0.014)
		local entryReach = reach
		if usesEntryGate then
			entryReach = math.max(reach, Clamp(tonumber(order.entryR) or 0.010, 0.004, 0.040))
		end
		if ((dx * dx) + (dy * dy)) <= (entryReach * entryReach) then
			if usesEntryGate then
				order.entryPassed = true
				order.entryU = nil
				order.entryV = nil
				order.entryR = nil
				return
			end
				if targetLieu and orderLieuType ~= "" then
					local isFull = select(1, IsLieuAtCapacityForNpc(targetLieu, npc))
					if isFull then
						local alt = Npc_FindLieuTargetPoint(npc, orderLieuType, {
							excludeLieuId = GetLieuStableId(targetLieu, targetLieuIndex),
							allowFullFallback = false,
						})
						if alt then
							order.targetU = Clamp(tonumber(alt.u) or targetU, 0, 1)
							order.targetV = Clamp(tonumber(alt.v) or targetV, 0, 1)
							order.entryPassed = nil
							order.entryU = nil
							order.entryV = nil
							order.entryR = nil
							order.pathWaypoints = nil
							order.pathIndex = nil
							order.pathLastDist2 = nil
							order.pathCheckAt = 0
						else
							-- Strict lieu capacity reached at destination and no fallback:
							-- cancel pause and continue roaming.
							Npc_BreakCurrentSocialLink(npc)
							Npc_ClearManualOrder(npc, true)
							Npc_RequestZoneExit(npc)
							npc.autoOrderRollIn = 0
						end
						return
					end
				end
			local zoneKey = select(1, GetZoneKeyAtPoint(targetU, targetV))
			local purpose = tostring(order.purpose or "")
			if not IsPurposeAllowedNow(purpose) then
				Npc_BreakCurrentSocialLink(npc)
				Npc_ClearManualOrder(npc, true)
				return
			end
			local isPointTravelOnly = (orderLieuType == "") and (purpose == "walk" or purpose == "wait")
			local targetLieuType = string.lower(tostring(targetLieu and targetLieu.lieuType or ""))
			local needs = type(npc and npc.needs) == "table" and npc.needs or {}
			local reserveValue = 100
			if actionRules and type(actionRules.GetReserveForPurpose) == "function" then
				reserveValue = Clamp(tonumber(actionRules.GetReserveForPurpose(needs, purpose)) or 100, 0, 100)
			end
			local shouldInterrupt = false
			if not isPointTravelOnly then
				if orderSource == "player" then
					if actionRules and type(actionRules.ShouldPlayerInterrupt) == "function" then
						shouldInterrupt = actionRules.ShouldPlayerInterrupt({
							source = orderSource,
							purpose = purpose,
							reserve = reserveValue,
							targetLieuType = targetLieuType,
							orderLieuType = orderLieuType,
						}) == true
					end
				else
					if actionRules and type(actionRules.ShouldAutoInterrupt) == "function" then
						shouldInterrupt = actionRules.ShouldAutoInterrupt({
							source = orderSource,
							purpose = purpose,
							reserve = reserveValue,
							targetLieuType = targetLieuType,
							orderLieuType = orderLieuType,
						}) == true
					end
				end
			end
			if shouldInterrupt then
				Npc_BreakCurrentSocialLink(npc)
				Npc_ClearManualOrder(npc, true)
				Npc_RequestZoneExit(npc)
				return
			end
			local forcedWaitSeconds = Clamp(tonumber(order.waitSeconds) or 0, 0, 600)
			if purpose == "walk" and forcedWaitSeconds <= 0 then
				Npc_BreakCurrentSocialLink(npc)
				Npc_ClearManualOrder(npc, true)
				if TryStartNextQueuedOrder then
					TryStartNextQueuedOrder(npc)
				end
				return
			end
			if purpose == "move_place" then
				npc.essentialPausePurpose = nil
				npc.essentialPauseTarget = nil
				npc.essentialPauseBoost = nil
				npc.essentialPauseLockUntil = nil
				npc.essentialPauseSource = nil
				npc.essentialPauseRollPurpose = nil
				npc.essentialPauseRollPercent = nil
				Npc_BreakCurrentSocialLink(npc)
				Npc_ClearManualOrder(npc, true)
				return
			end
			local pauseMin = NPC_SELF_PAUSE_MIN * 2.00
			local pauseMax = NPC_SELF_PAUSE_MAX * 2.80
			if purpose == "rest" then
				pauseMin = NPC_SELF_PAUSE_MIN * 2.60
				pauseMax = NPC_SELF_PAUSE_MAX * 3.80
			elseif purpose == "meal" then
				pauseMin = NPC_SELF_PAUSE_MIN * 2.40
				pauseMax = NPC_SELF_PAUSE_MAX * 3.40
			elseif purpose == "distraction" then
				pauseMin = NPC_SELF_PAUSE_MIN * 2.20
				pauseMax = NPC_SELF_PAUSE_MAX * 3.20
			end
			if forcedWaitSeconds > 0 then
				pauseMin = forcedWaitSeconds
				pauseMax = forcedWaitSeconds
			end

			local actionSpec = actionRules and actionRules.GetActionSpec and actionRules.GetActionSpec(purpose)
				or nil
			local essentialTarget = nil
			if forcedWaitSeconds <= 0 and (purpose == "rest" or purpose == "distraction" or purpose == "meal") then
				essentialTarget = math.max(NPC_NEEDS_ESSENTIAL.holdMax, essentialNeeds.GetTarget(npc, purpose))
				if orderSource == "player" then
					-- Evite une sortie quasi instantanee juste apres l'ordre manuel.
					local lockMin = tonumber(actionSpec and actionSpec.playerMinLockSec) or 8.0
					local lockMax = tonumber(actionSpec and actionSpec.playerMaxLockSec) or 12.0
					pauseMin = math.max(pauseMin, lockMin)
					pauseMax = math.max(pauseMax, lockMax)
				end
				local requiredHold = essentialNeeds.EstimateRecoverySeconds(npc, purpose, essentialTarget)
				if requiredHold > 0 then
					local withMargin = requiredHold + NPC_NEEDS_ESSENTIAL.holdMargin
					pauseMin = math.max(pauseMin, withMargin)
					pauseMax = math.max(pauseMax, withMargin + RandRange(0.4, 1.4))
				end
			end
			pauseMin = Clamp(pauseMin, 0.2, 240.0)
			pauseMax = Clamp(pauseMax, pauseMin, 300.0)

			if purpose == "rest" or purpose == "distraction" or purpose == "meal" then
				npc.essentialPausePurpose = purpose
				npc.essentialPauseTarget = essentialTarget or essentialNeeds.GetTarget(npc, purpose)
				npc.essentialPauseBoost = NPC_NEEDS_ESSENTIAL.recoverBoost
				npc.essentialPauseSource = orderSource
				if orderSource == "player" then
					local now = NowSec()
					local lockMin = tonumber(actionSpec and actionSpec.playerMinLockSec) or 8.0
					local lockMax = tonumber(actionSpec and actionSpec.playerMaxLockSec) or 12.0
					npc.essentialPauseLockUntil = now + math.max(lockMin, math.min(lockMax, pauseMin))
				else
					npc.essentialPauseLockUntil = nil
				end
			else
				npc.essentialPausePurpose = nil
				npc.essentialPauseTarget = nil
				npc.essentialPauseBoost = nil
				npc.essentialPauseLockUntil = nil
				npc.essentialPauseSource = nil
			end

			Npc_BreakCurrentSocialLink(npc)
			local pauseFor = RandRange(pauseMin, pauseMax)
			local beganPause = false
			if forcedWaitSeconds > 0 then
				-- Ordre joueur explicite: forcer une attente immobile a destination.
				pauseFor = Clamp(forcedWaitSeconds, 0.2, 600)
				npc.behaviorState = "self_pause"
				npc.behaviorPartner = nil
				npc.conversationGroupId = nil
				npc.behaviorTimer = pauseFor
				npc.behaviorCooldown = 0
				npc.duoTargetU = nil
				npc.duoTargetV = nil
				npc.selfPauseCooldown = 0
				npc.selfPauseIgnoreEdge = true
				npc.currentSelfPauseZoneKey = zoneKey
				if zoneKey then
					npc.lastSelfPauseZoneKey = zoneKey
				end
				npc.pauseLookHeading =
					WrapAngle((tonumber(npc.walkHeading) or RandRange(0, TWO_PI)) + RandRange(-0.12, 0.12))
				beganPause = true
			else
				local forcePauseForPlayer = (orderSource == "player")
					and (purpose == "rest" or purpose == "meal" or purpose == "distraction")
				beganPause = Npc_BeginSelfPause(npc, nil, pauseFor, zoneKey, {
					forceZoneAction = forcePauseForPlayer,
					ignoreEdge = true,
				})
			end
			if beganPause then
				local pausePurpose = tostring(purpose or "")
				npc.pausePurpose = (pausePurpose ~= "") and pausePurpose or nil
				Npc_ClearManualOrder(npc, true)
			end
		end
		return
	end

	Npc_ClearManualOrder(npc, true)
end

function CancelNpcOrder(selector)
	local npc = FindNpcBySelector and select(1, FindNpcBySelector(selector)) or nil
	if not npc then
		return false, "npc_not_found"
	end
	local order = npc.manualOrder
	if type(order) == "table" and tostring(order.kind or "") == "talk" then
		local partnerId = tostring(order.partnerId or "")
		local partner = FindNpcBySelector and select(1, FindNpcBySelector(partnerId)) or nil
		if partner and type(partner.manualOrder) == "table" then
			if tostring(partner.manualOrder.kind or "") == "talk" then
				if tostring(partner.manualOrder.partnerId or "") == tostring(npc.persistentId or "") then
					Npc_ClearManualOrder(partner, true)
					ClearNpcManualOrderQueue(partner)
				end
			end
		end
	end
	Npc_ClearManualOrder(npc, true)
	ClearNpcManualOrderQueue(npc)
	return true, "ok"
end

function CancelNpcIntent(selector, intentIndex)
	local npc = FindNpcBySelector and select(1, FindNpcBySelector(selector)) or nil
	if not npc then
		return false, "npc_not_found"
	end
	local idx = math.max(1, math.floor(tonumber(intentIndex) or 1))
	if idx <= 1 then
		local order = type(npc.manualOrder) == "table" and npc.manualOrder or nil
		if not order then
			return false, "current_not_cancelable"
		end
		if tostring(order.kind or "") == "talk" then
			local partnerId = tostring(order.partnerId or "")
			local partner = FindNpcBySelector and select(1, FindNpcBySelector(partnerId)) or nil
			if partner and type(partner.manualOrder) == "table" then
				if tostring(partner.manualOrder.kind or "") == "talk" then
					if tostring(partner.manualOrder.partnerId or "") == tostring(npc.persistentId or "") then
						Npc_ClearManualOrder(partner, true)
					end
				end
			end
		end
		Npc_ClearManualOrder(npc, true)
		TryStartNextQueuedOrder(npc)
		return true, "ok"
	end

	local queue = type(npc.manualOrderQueue) == "table" and npc.manualOrderQueue or nil
	if not queue or #queue < 1 then
		return false, "queue_empty"
	end
	local queueIndex = idx - 1
	if queueIndex < 1 or queueIndex > #queue then
		return false, "intent_out_of_range"
	end
	table.remove(queue, queueIndex)
	return true, "ok"
end

function Npc_BreakSocialPair(npc, partner)
	if IsSocialPartnerValid(npc, partner) and partner.behaviorPartner == npc then
		Npc_ResetSocialState(partner, true)
	end
	Npc_ResetSocialState(npc, true)
end

function Npc_BeginDisengage(npc, fromU, fromV, partnerRef)
	if not npc then
		return
	end
	npc.behaviorState = "disengage"
	npc.behaviorPartner = nil
	npc.conversationGroupId = nil
	npc.behaviorTimer = RandRange(NPC_SOCIAL_DISENGAGE_MIN, NPC_SOCIAL_DISENGAGE_MAX)
	npc.disengageFromU = tonumber(fromU)
	npc.disengageFromV = tonumber(fromV)
	npc.disengagePartner = partnerRef
	npc.pauseLookHeading = nil
	npc.currentSelfPauseZoneKey = nil
	npc.duoTargetU = nil
	npc.duoTargetV = nil
end

function Npc_EndDiscussionPair(npc, partner)
	local groupId = tostring(npc and npc.conversationGroupId or "")
	if groupId ~= "" then
		local members = GetConversationMembers(groupId)
		if #members > 2 then
			local partnerRef = IsSocialPartnerValid(npc, partner) and partner or nil
			local fromU = tonumber(partnerRef and partnerRef.u) or tonumber(npc and npc.u) or 0.5
			local fromV = tonumber(partnerRef and partnerRef.v) or tonumber(npc and npc.v) or 0.5
			Npc_SetCommunicationCooldown(npc, NPC_SOCIAL_POST_TALK_COOLDOWN_MIN, NPC_SOCIAL_POST_TALK_COOLDOWN_MAX)
			npc.lastTalkPartner = partnerRef
			npc.lastTalkCooldown =
				RandRange(NPC_SOCIAL_REPEAT_PARTNER_COOLDOWN_MIN, NPC_SOCIAL_REPEAT_PARTNER_COOLDOWN_MAX)
			Npc_BeginDisengage(npc, fromU, fromV, partnerRef)
			RebindConversationMembers(groupId)
			return
		end
	end
	local partnerRef = IsSocialPartnerValid(npc, partner) and partner or nil
	local au = tonumber(npc and npc.u) or 0.5
	local av = tonumber(npc and npc.v) or 0.5
	local bu = tonumber(partnerRef and partnerRef.u) or au
	local bv = tonumber(partnerRef and partnerRef.v) or av
	Npc_BreakSocialPair(npc, partnerRef)
	Npc_SetCommunicationCooldown(npc, NPC_SOCIAL_POST_TALK_COOLDOWN_MIN, NPC_SOCIAL_POST_TALK_COOLDOWN_MAX)
	npc.lastTalkPartner = partnerRef
	npc.lastTalkCooldown = RandRange(NPC_SOCIAL_REPEAT_PARTNER_COOLDOWN_MIN, NPC_SOCIAL_REPEAT_PARTNER_COOLDOWN_MAX)
	Npc_BeginDisengage(npc, bu, bv, partnerRef)
	if partnerRef then
		Npc_SetCommunicationCooldown(
			partnerRef,
			NPC_SOCIAL_POST_TALK_COOLDOWN_MIN,
			NPC_SOCIAL_POST_TALK_COOLDOWN_MAX
		)
		partnerRef.lastTalkPartner = npc
		partnerRef.lastTalkCooldown =
			RandRange(NPC_SOCIAL_REPEAT_PARTNER_COOLDOWN_MIN, NPC_SOCIAL_REPEAT_PARTNER_COOLDOWN_MAX)
		Npc_BeginDisengage(partnerRef, au, av, npc)
		Npc_RequestPostDiscussionZoneShift(npc, partnerRef)
	end
end

function FindEncounterCandidate(npc)
	if not IsAutoSocialEligible(npc) then
		return nil
	end
	local bestNpc, bestD2 = nil, (NPC_SOCIAL_ENCOUNTER_RADIUS * NPC_SOCIAL_ENCOUNTER_RADIUS)
	local minD2 = NPC_SOCIAL_ENCOUNTER_MIN_DIST * NPC_SOCIAL_ENCOUNTER_MIN_DIST
	local nu = tonumber(npc and npc.u) or 0.5
	local nv = tonumber(npc and npc.v) or 0.5
	ForEachNpcInRadius(nu, nv, NPC_SOCIAL_ENCOUNTER_RADIUS, function(other)
		if other == npc or (other.navMode ~= "walkable") then
			return false
		end
		local stateName = Npc_GetSocialState(other)
		if stateName ~= "walk" or (tonumber(other.behaviorCooldown) or 0) > 0 then
			return false
		end
		if not IsAutoSocialEligible(other) then
			return false
		end
		local pairCooldownA = (npc.lastTalkPartner == other) and ((tonumber(npc.lastTalkCooldown) or 0) > 0)
		local pairCooldownB = (other.lastTalkPartner == npc) and ((tonumber(other.lastTalkCooldown) or 0) > 0)
		if pairCooldownA or pairCooldownB then
			return false
		end
		local dx = (tonumber(other.u) or 0) - nu
		local dy = (tonumber(other.v) or 0) - nv
		local d2 = (dx * dx) + (dy * dy)
		if d2 >= minD2 and d2 <= bestD2 then
			bestD2 = d2
			bestNpc = other
		end
		return false
	end)
	return bestNpc
end

behaviorRunner = nil
do
	local routines = ns and ns.QuartierMiniature and ns.QuartierMiniature.NpcMovementRoutines
	if type(routines) == "table" and type(routines.CreateRunner) == "function" then
		behaviorRunner = routines.CreateRunner({
			Clamp = Clamp,
			RandRange = RandRange,
			WrapAngle = WrapAngle,
			ApproachAngle = ApproachAngle,
			AngleFromVector = AngleFromVector,
			FindPlazaEdgeInfoAtPoint = FindPlazaEdgeInfoAtPoint,
			BuildSelfPauseZoneKey = BuildSelfPauseZoneKey,
			FindEncounterCandidate = FindEncounterCandidate,
			Npc_BeginSelfPause = Npc_BeginSelfPause,
			Npc_BeginApproachPair = Npc_BeginApproachPair,
			Npc_BeginDuoWalkPair = Npc_BeginDuoWalkPair,
			Npc_BeginDiscussionPair = Npc_BeginDiscussionPair,
			Npc_BreakSocialPair = Npc_BreakSocialPair,
			Npc_EndDiscussionPair = Npc_EndDiscussionPair,
			Npc_ResetSocialState = Npc_ResetSocialState,
			IsGlobalTalkLocked = IsGlobalTalkLocked,
			IsSocialPartnerValid = IsSocialPartnerValid,
			AreNpcsInSameConversation = AreNpcsInSameConversation,
			PickSocialWalkTarget = PickSocialWalkTarget,
			Npc_PickLongWalkTarget = Npc_PickLongWalkTarget,
			Npc_PickCurrentPlazaWalkPoint = Npc_PickCurrentPlazaWalkPoint,
			Npc_PickCurrentRouteWalkPoint = Npc_PickCurrentRouteWalkPoint,
			Npc_PickCurrentRoutePoiPoint = Npc_PickCurrentRoutePoiPoint,
			Npc_ShouldLeaveZone = Npc_ShouldLeaveZone,
			Npc_RequestZoneExit = Npc_RequestZoneExit,
			Npc_ResolveZoneShiftPath = Npc_ResolveZoneShiftPath,
			Npc_AdvanceZoneShiftPath = Npc_AdvanceZoneShiftPath,
			NPC_ZONE_ROUTINE_ACTIONS = NPC_ZONE_ROUTINE_ACTIONS,
			NPC_ZONE_ROUTINE_PAUSE_MIN = NPC_ZONE_ROUTINE_PAUSE_MIN,
			NPC_ZONE_ROUTINE_PAUSE_MAX = NPC_ZONE_ROUTINE_PAUSE_MAX,
			NPC_ZONE_ROUTINE_TTL_MIN = NPC_ZONE_ROUTINE_TTL_MIN,
			NPC_ZONE_ROUTINE_TTL_MAX = NPC_ZONE_ROUTINE_TTL_MAX,
			NPC_SELF_PAUSE_CHANCE = NPC_SELF_PAUSE_CHANCE,
			NPC_SELF_PAUSE_EDGE_MAX_DIST = NPC_SELF_PAUSE_EDGE_MAX_DIST,
			NPC_SELF_PAUSE_EDGE_MIN_DIST = NPC_SELF_PAUSE_EDGE_MIN_DIST,
			NPC_SELF_PAUSE_COOLDOWN_MIN = NPC_SELF_PAUSE_COOLDOWN_MIN,
			NPC_SELF_PAUSE_COOLDOWN_MAX = NPC_SELF_PAUSE_COOLDOWN_MAX,
			NPC_SELF_PAUSE_MIN = NPC_SELF_PAUSE_MIN,
			NPC_SELF_PAUSE_MAX = NPC_SELF_PAUSE_MAX,
			NPC_SOCIAL_ENCOUNTER_NEAR_MAX = NPC_SOCIAL_ENCOUNTER_NEAR_MAX,
			NPC_SOCIAL_ENCOUNTER_PROC_CHANCE = NPC_SOCIAL_ENCOUNTER_PROC_CHANCE,
			NPC_SOCIAL_ENCOUNTER_CHECK_MIN = NPC_SOCIAL_ENCOUNTER_CHECK_MIN,
			NPC_SOCIAL_ENCOUNTER_CHECK_MAX = NPC_SOCIAL_ENCOUNTER_CHECK_MAX,
			NPC_SOCIAL_ENCOUNTER_SAME_DIR_BLOCK_DELTA = NPC_SOCIAL_ENCOUNTER_SAME_DIR_BLOCK_DELTA,
			NPC_SOCIAL_ENCOUNTER_RADIUS = NPC_SOCIAL_ENCOUNTER_RADIUS,
			NPC_SOCIAL_APPROACH_STOP_DIST = NPC_SOCIAL_APPROACH_STOP_DIST,
			NPC_SOCIAL_DUO_WALK_CHANCE = NPC_SOCIAL_DUO_WALK_CHANCE,
			NPC_SOCIAL_DUO_WALK_MIN = NPC_SOCIAL_DUO_WALK_MIN,
			NPC_SOCIAL_DUO_WALK_MAX = NPC_SOCIAL_DUO_WALK_MAX,
			NPC_SOCIAL_DUO_TARGET_RADIUS = NPC_SOCIAL_DUO_TARGET_RADIUS,
			NPC_SOCIAL_DUO_TARGET_REACH = NPC_SOCIAL_DUO_TARGET_REACH,
			NPC_SOCIAL_DUO_SEPARATION = NPC_SOCIAL_DUO_SEPARATION,
			NPC_AUTO_SOCIAL_ENABLED = NPC_AUTO_SOCIAL_ENABLED,
			NPC_AUTO_SOCIAL_MAX_RESERVE = NPC_AUTO_SOCIAL_MAX_RESERVE,
			NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MIN = NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MIN,
			NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MAX = NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MAX,
			NPC_SOCIAL_DISCUSS_PREFERRED_DIST = NPC_SOCIAL_DISCUSS_PREFERRED_DIST,
			NPC_SOCIAL_DISCUSS_MIN_DIST = NPC_SOCIAL_DISCUSS_MIN_DIST,
			NPC_SOCIAL_DISCUSS_MIN = NPC_SOCIAL_DISCUSS_MIN,
			NPC_SOCIAL_DISCUSS_MAX = NPC_SOCIAL_DISCUSS_MAX,
			NPC_SOCIAL_DISENGAGE_MIN_DIST = NPC_SOCIAL_DISENGAGE_MIN_DIST,
			NPC_SOCIAL_POST_TALK_ZONE_REACH = NPC_SOCIAL_POST_TALK_ZONE_REACH,
			NPC_LONG_GOAL_MIN_DIST = NPC_LONG_GOAL_MIN_DIST,
			NPC_LONG_GOAL_MAX_DIST = NPC_LONG_GOAL_MAX_DIST,
			NPC_LONG_GOAL_RETARGET_MIN = NPC_LONG_GOAL_RETARGET_MIN,
			NPC_LONG_GOAL_RETARGET_MAX = NPC_LONG_GOAL_RETARGET_MAX,
			NPC_LONG_GOAL_REACH = NPC_LONG_GOAL_REACH,
			NPC_POI_PICK_CHANCE = NPC_POI_PICK_CHANCE,
			NPC_POI_PICK_RADIUS = NPC_POI_PICK_RADIUS,
			NPC_POI_NEAR_RADIUS = NPC_POI_NEAR_RADIUS,
			NPC_POI_PAUSE_MULT_MIN = NPC_POI_PAUSE_MULT_MIN,
			NPC_POI_PAUSE_MULT_MAX = NPC_POI_PAUSE_MULT_MAX,
			NPC_PLAZA_ROAM_RETARGET_MIN = NPC_PLAZA_ROAM_RETARGET_MIN,
			NPC_PLAZA_ROAM_RETARGET_MAX = NPC_PLAZA_ROAM_RETARGET_MAX,
			NPC_PERSONAL_SPACE = NPC_PERSONAL_SPACE,
			NPC_SPEED_MIN = NPC_SPEED_MIN,
			NPC_SPEED_MAX = NPC_SPEED_MAX,
			PI = PI,
			NAV_EPS = NAV_EPS,
		})
	end
end

function Npc_ForceNewActionAfterSevereBlock(npc)
	if not npc then
		return false
	end
	local now = NowSec()
	local lastAt = tonumber(npc.lastSevereBlockAt) or 0
	local escalation = 1
	if lastAt > 0 and (now - lastAt) <= 6.0 then
		escalation = math.max(0, tonumber(npc.severeBlockEscalation) or 0) + 1
	end
	npc.lastSevereBlockAt = now
	npc.severeBlockEscalation = escalation
	npc.severeBlockIterations = 0
	local activeOrder = type(npc.manualOrder) == "table" and npc.manualOrder or nil
	local activeOrderSource = tostring(activeOrder and activeOrder.source or "")
	local activeOrderKind = tostring(activeOrder and activeOrder.kind or "")
	local activeOrderTargetU = tonumber(activeOrder and activeOrder.targetU)
	local activeOrderTargetV = tonumber(activeOrder and activeOrder.targetV)
	local shouldRecoverPlayerOrder = activeOrder
		and activeOrderSource == "player"
		and activeOrderKind == "lieu_pause"
		and activeOrderTargetU
		and activeOrderTargetV
	Npc_BreakCurrentSocialLink(npc)
	if shouldRecoverPlayerOrder then
		npc.waitTimer = 0
		npc.behaviorState = "walk"
		npc.behaviorPartner = nil
		npc.conversationGroupId = nil
		npc.behaviorTimer = 0
		npc.behaviorCooldown = 0
		if escalation >= 2 then
			local near = FindNearestRoutePoint(npc.u, npc.v, 2.0, nil)
			if near and tonumber(near.px) and tonumber(near.py) then
				npc.u = Clamp(tonumber(near.px) or npc.u, 0, 1)
				npc.v = Clamp(tonumber(near.py) or npc.v, 0, 1)
			end
			Npc_EnsureWalkablePosition(npc)
			npc.severeBlockEscalation = 0
		end
		activeOrder.pathWaypoints = nil
		activeOrder.pathIndex = nil
		activeOrder.pathLastDist2 = nil
		activeOrder.pathCheckAt = 0
		Npc_ApplyManualWaypointTarget(npc, activeOrder, activeOrderTargetU, activeOrderTargetV, "manual_lieu", 48)
		if tonumber(npc.zoneShiftTargetU) and tonumber(npc.zoneShiftTargetV) then
			return true
		end
		-- Keep the player order alive and retry quickly on next updates.
		npc.autoOrderRollIn = 0
		return false
	end
	Npc_ClearManualOrder(npc, true)
	ClearNpcManualOrderQueue(npc)
	npc.waitTimer = 0
	if escalation >= 2 then
		local near = FindNearestRoutePoint(npc.u, npc.v, 2.0, nil)
		if near and tonumber(near.px) and tonumber(near.py) then
			npc.u = Clamp(tonumber(near.px) or npc.u, 0, 1)
			npc.v = Clamp(tonumber(near.py) or npc.v, 0, 1)
		elseif navCache.hasRoutes or navCache.hasPlazas then
			local u, v = PickNpcSpawnPoint()
			npc.u, npc.v = u, v
		end
		Npc_EnsureWalkablePosition(npc)
		npc.severeBlockEscalation = 0
	end
	npc.autoOrderRollIn = 0
	if TryEnqueueNpcAutoOrder(npc) then
		return true
	end
	Npc_RequestZoneExit(npc)
	return false
end

-- Keep walkable wander under Lua upvalue limits by routing dependencies through one context table.
WANDER_CTX = {
	Clamp = Clamp,
	RandRange = RandRange,
	WrapAngle = WrapAngle,
	ApproachAngle = ApproachAngle,
	AngleFromVector = AngleFromVector,
	IsRepulsionIgnoredPair = IsRepulsionIgnoredPair,
	Npc_GetSocialState = Npc_GetSocialState,
	Npc_ResetSocialState = Npc_ResetSocialState,
	IsSocialPartnerValid = IsSocialPartnerValid,
	AreNpcsInSameConversation = AreNpcsInSameConversation,
	Npc_BeginApproachPair = Npc_BeginApproachPair,
	Npc_BeginDiscussionPair = Npc_BeginDiscussionPair,
	Npc_BeginDuoWalkPair = Npc_BeginDuoWalkPair,
	Npc_BeginSelfPause = Npc_BeginSelfPause,
	Npc_BreakSocialPair = Npc_BreakSocialPair,
	Npc_EndDiscussionPair = Npc_EndDiscussionPair,
	IsGlobalTalkLocked = IsGlobalTalkLocked,
	FindEncounterCandidate = FindEncounterCandidate,
	PickSocialWalkTarget = PickSocialWalkTarget,
	Npc_ShouldLeaveZone = Npc_ShouldLeaveZone,
	Npc_RequestZoneExit = Npc_RequestZoneExit,
	Npc_ForceNewActionAfterSevereBlock = Npc_ForceNewActionAfterSevereBlock,
	behaviorRunner = behaviorRunner,
	FindPlazaEdgeInfoAtPoint = FindPlazaEdgeInfoAtPoint,
	BuildSelfPauseZoneKey = BuildSelfPauseZoneKey,
	IsPointWalkable = IsPointWalkable,
	IsSegmentOnStrictNetwork = IsSegmentOnStrictNetwork,
	IsCrowdSpaceFree = IsCrowdSpaceFree,
	Npc_EnsureWalkablePosition = Npc_EnsureWalkablePosition,
	npcPool = npcPool,
	NAV_EPS = NAV_EPS,
	PI = PI,
	TWO_PI = TWO_PI,
	NPC_WALK_TURN_RATE = NPC_WALK_TURN_RATE,
	NPC_SPEED_MIN = NPC_SPEED_MIN,
	NPC_SPEED_MAX = NPC_SPEED_MAX,
	NPC_SOCIAL_COOLDOWN_MAX = NPC_SOCIAL_COOLDOWN_MAX,
	NPC_SELF_PAUSE_COOLDOWN_MAX = NPC_SELF_PAUSE_COOLDOWN_MAX,
	NPC_CROWD_SENSE = NPC_CROWD_SENSE,
	NPC_SELF_PAUSE_CHANCE = NPC_SELF_PAUSE_CHANCE,
	NPC_SELF_PAUSE_EDGE_MAX_DIST = NPC_SELF_PAUSE_EDGE_MAX_DIST,
	NPC_SELF_PAUSE_EDGE_MIN_DIST = NPC_SELF_PAUSE_EDGE_MIN_DIST,
	NPC_SELF_PAUSE_COOLDOWN_MIN = NPC_SELF_PAUSE_COOLDOWN_MIN,
	NPC_SELF_PAUSE_MIN = NPC_SELF_PAUSE_MIN,
	NPC_SELF_PAUSE_MAX = NPC_SELF_PAUSE_MAX,
	NPC_SOCIAL_ENCOUNTER_NEAR_MAX = NPC_SOCIAL_ENCOUNTER_NEAR_MAX,
	NPC_SOCIAL_ENCOUNTER_PROC_CHANCE = NPC_SOCIAL_ENCOUNTER_PROC_CHANCE,
	NPC_SOCIAL_ENCOUNTER_CHECK_MIN = NPC_SOCIAL_ENCOUNTER_CHECK_MIN,
	NPC_SOCIAL_ENCOUNTER_CHECK_MAX = NPC_SOCIAL_ENCOUNTER_CHECK_MAX,
	NPC_SOCIAL_ENCOUNTER_SAME_DIR_BLOCK_DELTA = NPC_SOCIAL_ENCOUNTER_SAME_DIR_BLOCK_DELTA,
	NPC_SOCIAL_ENCOUNTER_RADIUS = NPC_SOCIAL_ENCOUNTER_RADIUS,
	NPC_SOCIAL_APPROACH_STOP_DIST = NPC_SOCIAL_APPROACH_STOP_DIST,
	NPC_SOCIAL_DUO_WALK_CHANCE = NPC_SOCIAL_DUO_WALK_CHANCE,
	NPC_SOCIAL_DUO_WALK_MIN = NPC_SOCIAL_DUO_WALK_MIN,
	NPC_SOCIAL_DUO_WALK_MAX = NPC_SOCIAL_DUO_WALK_MAX,
	NPC_SOCIAL_DISCUSS_PREFERRED_DIST = NPC_SOCIAL_DISCUSS_PREFERRED_DIST,
	NPC_SOCIAL_DISCUSS_MIN_DIST = NPC_SOCIAL_DISCUSS_MIN_DIST,
	NPC_SOCIAL_DISCUSS_MIN = NPC_SOCIAL_DISCUSS_MIN,
	NPC_SOCIAL_DISCUSS_MAX = NPC_SOCIAL_DISCUSS_MAX,
	NPC_SOCIAL_DUO_TARGET_RADIUS = NPC_SOCIAL_DUO_TARGET_RADIUS,
	NPC_SOCIAL_DUO_TARGET_REACH = NPC_SOCIAL_DUO_TARGET_REACH,
	NPC_SOCIAL_DUO_SEPARATION = NPC_SOCIAL_DUO_SEPARATION,
	NPC_PERSONAL_SPACE = NPC_PERSONAL_SPACE,
	NPC_SOCIAL_POST_TALK_ZONE_REACH = NPC_SOCIAL_POST_TALK_ZONE_REACH,
	NPC_WALK_DESIRED_JITTER = NPC_WALK_DESIRED_JITTER,
	NPC_WAIT_NEAR_CHANCE = NPC_WAIT_NEAR_CHANCE,
	NPC_WAIT_MIN = NPC_WAIT_MIN,
	NPC_WAIT_MAX = NPC_WAIT_MAX,
	NPC_CROWD_MIN_SPEED_FACTOR = NPC_CROWD_MIN_SPEED_FACTOR,
	NPC_WALK_SPEED_BLEND = NPC_WALK_SPEED_BLEND,
	NPC_WALK_LOOK_AHEAD = NPC_WALK_LOOK_AHEAD,
	NPC_REVERSE_CHANCE = NPC_REVERSE_CHANCE,
	NPC_WALK_STEP = NPC_WALK_STEP,
	NPC_SEVERE_BLOCK_MAX_ITERATIONS = NPC_SEVERE_BLOCK_MAX_ITERATIONS,
}

function Npc_UpdateWalkableWander(npc, dt)
	local C = WANDER_CTX
	local Clamp = C.Clamp
	local RandRange = C.RandRange
	local WrapAngle = C.WrapAngle
	local ApproachAngle = C.ApproachAngle
	local AngleFromVector = C.AngleFromVector
	local IsRepulsionIgnoredPair = C.IsRepulsionIgnoredPair
	local Npc_GetSocialState = C.Npc_GetSocialState
	local Npc_ResetSocialState = C.Npc_ResetSocialState
	local IsSocialPartnerValid = C.IsSocialPartnerValid
	local Npc_BeginApproachPair = C.Npc_BeginApproachPair
	local Npc_BeginDiscussionPair = C.Npc_BeginDiscussionPair
	local Npc_BeginDuoWalkPair = C.Npc_BeginDuoWalkPair
	local Npc_BeginSelfPause = C.Npc_BeginSelfPause
	local Npc_BreakSocialPair = C.Npc_BreakSocialPair
	local Npc_EndDiscussionPair = C.Npc_EndDiscussionPair
	local FindEncounterCandidate = C.FindEncounterCandidate
	local PickSocialWalkTarget = C.PickSocialWalkTarget
	local behaviorRunner = C.behaviorRunner
	local FindPlazaEdgeInfoAtPoint = C.FindPlazaEdgeInfoAtPoint
	local BuildSelfPauseZoneKey = C.BuildSelfPauseZoneKey
	local IsPointWalkable = C.IsPointWalkable
	local IsCrowdSpaceFree = C.IsCrowdSpaceFree
	local Npc_EnsureWalkablePosition = C.Npc_EnsureWalkablePosition
	local npcPool = C.npcPool
	local NAV_EPS = C.NAV_EPS
	local PI = C.PI
	local TWO_PI = C.TWO_PI
	NPC_WALK_TURN_RATE = C.NPC_WALK_TURN_RATE
	NPC_SPEED_MIN = C.NPC_SPEED_MIN
	NPC_SPEED_MAX = C.NPC_SPEED_MAX
	NPC_SOCIAL_COOLDOWN_MAX = C.NPC_SOCIAL_COOLDOWN_MAX
	NPC_SELF_PAUSE_COOLDOWN_MAX = C.NPC_SELF_PAUSE_COOLDOWN_MAX
	NPC_CROWD_SENSE = C.NPC_CROWD_SENSE
	NPC_SELF_PAUSE_CHANCE = C.NPC_SELF_PAUSE_CHANCE
	NPC_SELF_PAUSE_EDGE_MAX_DIST = C.NPC_SELF_PAUSE_EDGE_MAX_DIST
	NPC_SELF_PAUSE_EDGE_MIN_DIST = C.NPC_SELF_PAUSE_EDGE_MIN_DIST
	NPC_SELF_PAUSE_COOLDOWN_MIN = C.NPC_SELF_PAUSE_COOLDOWN_MIN
	NPC_SELF_PAUSE_MIN = C.NPC_SELF_PAUSE_MIN
	NPC_SELF_PAUSE_MAX = C.NPC_SELF_PAUSE_MAX
	NPC_SOCIAL_ENCOUNTER_NEAR_MAX = C.NPC_SOCIAL_ENCOUNTER_NEAR_MAX
	NPC_SOCIAL_ENCOUNTER_PROC_CHANCE = C.NPC_SOCIAL_ENCOUNTER_PROC_CHANCE
	NPC_SOCIAL_ENCOUNTER_CHECK_MIN = C.NPC_SOCIAL_ENCOUNTER_CHECK_MIN
	NPC_SOCIAL_ENCOUNTER_CHECK_MAX = C.NPC_SOCIAL_ENCOUNTER_CHECK_MAX
	NPC_SOCIAL_ENCOUNTER_RADIUS = C.NPC_SOCIAL_ENCOUNTER_RADIUS
	NPC_SOCIAL_APPROACH_STOP_DIST = C.NPC_SOCIAL_APPROACH_STOP_DIST
	NPC_SOCIAL_DUO_WALK_CHANCE = C.NPC_SOCIAL_DUO_WALK_CHANCE
	NPC_SOCIAL_DUO_WALK_MIN = C.NPC_SOCIAL_DUO_WALK_MIN
	NPC_SOCIAL_DUO_WALK_MAX = C.NPC_SOCIAL_DUO_WALK_MAX
	NPC_SOCIAL_DISCUSS_MIN = C.NPC_SOCIAL_DISCUSS_MIN
	NPC_SOCIAL_DISCUSS_MAX = C.NPC_SOCIAL_DISCUSS_MAX
	NPC_SOCIAL_DUO_TARGET_RADIUS = C.NPC_SOCIAL_DUO_TARGET_RADIUS
	NPC_SOCIAL_DUO_TARGET_REACH = C.NPC_SOCIAL_DUO_TARGET_REACH
	NPC_SOCIAL_DUO_SEPARATION = C.NPC_SOCIAL_DUO_SEPARATION
	NPC_PERSONAL_SPACE = C.NPC_PERSONAL_SPACE
	NPC_SOCIAL_POST_TALK_ZONE_REACH = C.NPC_SOCIAL_POST_TALK_ZONE_REACH
	NPC_WALK_DESIRED_JITTER = C.NPC_WALK_DESIRED_JITTER
	NPC_WAIT_NEAR_CHANCE = C.NPC_WAIT_NEAR_CHANCE
	NPC_WAIT_MIN = C.NPC_WAIT_MIN
	NPC_WAIT_MAX = C.NPC_WAIT_MAX
	NPC_CROWD_MIN_SPEED_FACTOR = C.NPC_CROWD_MIN_SPEED_FACTOR
	NPC_WALK_SPEED_BLEND = C.NPC_WALK_SPEED_BLEND
	NPC_WALK_LOOK_AHEAD = C.NPC_WALK_LOOK_AHEAD
	NPC_REVERSE_CHANCE = C.NPC_REVERSE_CHANCE
	NPC_WALK_STEP = C.NPC_WALK_STEP

	if npc.navMode ~= "walkable" then
		npc.navMode = "walkable"
		npc.transition = nil
		npc.transitionSpeed = nil
		npc.walkHeading = RandRange(0, TWO_PI)
		npc.walkDesiredHeading = npc.walkHeading
		npc.walkDesiredIn = RandRange(0.8, 2.1)
		npc.walkTurnRate = RandRange(NPC_WALK_TURN_RATE * 0.85, NPC_WALK_TURN_RATE * 1.15)
		npc.walkSpeedTarget = RandRange(NPC_SPEED_MIN * 0.75, NPC_SPEED_MAX * 0.90)
		npc.speed = npc.walkSpeedTarget
		npc.waitTimer = 0
		npc.behaviorState = "walk"
		npc.behaviorPartner = nil
		npc.conversationGroupId = nil
		npc.behaviorTimer = 0
		npc.behaviorCooldown = RandRange(0.25, NPC_SOCIAL_COOLDOWN_MAX * 0.60)
		npc.encounterRollIn = RandRange(NPC_SOCIAL_ENCOUNTER_CHECK_MIN, NPC_SOCIAL_ENCOUNTER_CHECK_MAX)
		npc.duoTargetU = nil
		npc.duoTargetV = nil
		npc.pauseLookHeading = nil
		npc.currentSelfPauseZoneKey = nil
		npc.disengageFromU = nil
		npc.disengageFromV = nil
		npc.disengagePartner = nil
		npc.lastTalkPartner = nil
		npc.lastTalkCooldown = 0
		npc.zoneKey = nil
		npc.prevZoneKey = nil
		npc.zoneKind = nil
		npc.zoneActionCount = 0
		npc.zoneMoveHopCount = 0
		npc.plazaRoamRetargetIn = RandRange(NPC_PLAZA_ROAM_RETARGET_MIN * 0.5, NPC_PLAZA_ROAM_RETARGET_MAX)
		npc.longWalkTargetU = nil
		npc.longWalkTargetV = nil
		npc.longWalkRetargetIn = RandRange(NPC_LONG_GOAL_RETARGET_MIN * 0.5, NPC_LONG_GOAL_RETARGET_MAX)
		npc.selfPauseCooldown = RandRange(0.8, NPC_SELF_PAUSE_COOLDOWN_MAX * 0.55)
		npc.zoneShiftTargetU = nil
		npc.zoneShiftTargetV = nil
		npc.zoneShiftGoalU = nil
		npc.zoneShiftGoalV = nil
		npc.zoneShiftTargetKind = nil
		npc.zoneShiftPathWaypoints = nil
		npc.zoneShiftPathIndex = nil
		npc.zoneShiftPathTargetKey = nil
		npc.zoneShiftPathNavSignature = nil
		npc.zoneShiftTimer = 0
		npc.zoneRoutineZoneKey = nil
		npc.zoneRoutineActionCount = 0
		npc.zoneRoutineStep = "move"
		npc.zoneRoutinePause = 0
		npc.zoneRoutineTargetU = nil
		npc.zoneRoutineTargetV = nil
		npc.zoneRoutineTargetTtl = 0
		npc.manualOrder = nil
		npc.manualOrderQueue = {}
		npc.autoOrderRollIn = GetNextNpcAutoIntentDelay()
		npc.poiVisitRollIn = RandRange(NPC_POI_ROLL_MIN, NPC_POI_ROLL_MAX)
		npc.poiVisitCooldown = 0
		npc.severeBlockIterations = 0
		npc.severeBlockEscalation = 0
		npc.lastSevereBlockAt = 0
	end

	Npc_EnsureWalkablePosition(npc)
	Npc_UpdateZoneTracking(npc)

	local heading = WrapAngle(tonumber(npc.walkHeading) or RandRange(0, TWO_PI))
	local desiredHeading = WrapAngle(tonumber(npc.walkDesiredHeading) or heading)
	local desiredIn = (tonumber(npc.walkDesiredIn) or 0) - dt
	local turnRate = Clamp(tonumber(npc.walkTurnRate) or NPC_WALK_TURN_RATE, 0.25, 10)
	local speed = Clamp(tonumber(npc.speed) or NPC_SPEED_MIN, 0, NPC_SPEED_MAX)
	local targetSpeed = Clamp(tonumber(npc.walkSpeedTarget) or speed, 0, NPC_SPEED_MAX)
	local waitTimer = math.max(0, (tonumber(npc.waitTimer) or 0) - dt)
	npc.behaviorCooldown = math.max(0, (tonumber(npc.behaviorCooldown) or 0) - dt)
	npc.lastTalkCooldown = math.max(0, (tonumber(npc.lastTalkCooldown) or 0) - dt)
	if npc.lastTalkCooldown <= 0 then
		npc.lastTalkPartner = nil
		npc.lastTalkCooldown = 0
	end
	npc.behaviorTimer = math.max(0, (tonumber(npc.behaviorTimer) or 0) - dt)
	npc.selfPauseCooldown = math.max(0, (tonumber(npc.selfPauseCooldown) or 0) - dt)
	npc.poiVisitCooldown = math.max(0, (tonumber(npc.poiVisitCooldown) or 0) - dt)
	npc.encounterRollIn = math.max(
		0,
		(tonumber(npc.encounterRollIn) or RandRange(NPC_SOCIAL_ENCOUNTER_CHECK_MIN, NPC_SOCIAL_ENCOUNTER_CHECK_MAX))
			- dt
	)
	npc.zoneShiftTimer = math.max(0, (tonumber(npc.zoneShiftTimer) or 0) - dt)
	if npc.zoneShiftTimer <= 0 then
		Npc_ClearZoneShiftTarget(npc)
	end
	local behaviorState = Npc_GetSocialState(npc)
	local partner = npc.behaviorPartner
	local manualOrderActive = type(npc.manualOrder) == "table"
	local manualOrder = manualOrderActive and npc.manualOrder or nil
	local manualOrderKind = tostring(manualOrder and manualOrder.kind or "")
	local manualTalkAnchor = manualOrderKind == "talk"
		and (
			(manualOrder and manualOrder.holdPosition == true)
			or (tostring(manualOrder and manualOrder.talkRole or "") == "anchor")
		)
	if NPC_COLLISIONS_ENABLED then
		UpdateNpcRouteHint(npc, dt, false)
	end

	local sepX, sepY = 0, 0
	local nearCount = 0
	local nearest = math.huge
	local routePassActive = false
	local routeMeanSideSum = 0
	local routeMeanWeight = 0
	local routeMeanNx = 0
	local routeMeanNy = 0
	if (not manualOrderActive) and NPC_COLLISIONS_ENABLED then
		local crowdSense2 = NPC_CROWD_SENSE * NPC_CROWD_SENSE
		ForEachNpcInRadius(npc.u, npc.v, NPC_CROWD_SENSE, function(other)
			if other == npc then
				return false
			end
			if IsRepulsionIgnoredPair(npc, other) then
				-- Social pair (approach/discussion/duo_walk): skip mutual crowd repulsion.
				return false
			end
			local ou = tonumber(other and other.u)
			local ov = tonumber(other and other.v)
			if not ou or not ov then
				return false
			end
			local dx = npc.u - ou
			local dy = npc.v - ov
			local d2 = (dx * dx) + (dy * dy)
			if d2 > crowdSense2 then
				return false
			end
			nearCount = nearCount + 1
			if d2 > NAV_EPS then
				local d = math.sqrt(d2)
				if d < nearest then
					nearest = d
				end
				local w = 1 - (d / NPC_CROWD_SENSE)
				w = w * w
				local usedRoutePass = false
				local _, rtx, rty, rnx, rny, oppositeDir, sameDir = GetSharedRoutePairInfo(npc, other)
				local routeHalf = math.max(NPC_ROUTE_WALK_HALF_WIDTH, NPC_PERSONAL_SPACE * 1.45)
					+ (NPC_CROWD_EXPAND_MAX_BONUS * 0.85)

				if rtx and rty and rnx and rny then
					local relX = ou - npc.u
					local relY = ov - npc.v
					local along = (relX * rtx) + (relY * rty)
					local side = (relX * rnx) + (relY * rny)
					local passWindow = math.max(NPC_CROWD_SENSE * 1.10, routeHalf * 8.0)
					if math.abs(along) <= passWindow then
						routeMeanSideSum = routeMeanSideSum + (side * w)
						routeMeanWeight = routeMeanWeight + w
						routeMeanNx = routeMeanNx + (rnx * w)
						routeMeanNy = routeMeanNy + (rny * w)
						local sideSign = GetRoutePassSideSign(npc, other)
						local sideNeed = Clamp(1 - (math.abs(side) / math.max(NAV_EPS, routeHalf * 0.92)), 0, 1)
						local lateralScale = (oppositeDir and 2.05 or 1.45) * (0.60 + sideNeed)
						sepX = sepX + (rnx * sideSign * w * lateralScale)
						sepY = sepY + (rny * sideSign * w * lateralScale)
						usedRoutePass = oppositeDir or sameDir
						if oppositeDir or sameDir then
							routePassActive = true
						end
					end
				end
				if not usedRoutePass then
					sepX = sepX + ((dx / d) * w)
					sepY = sepY + ((dy / d) * w)
				else
					sepX = sepX + ((dx / d) * w * 0.16)
					sepY = sepY + ((dy / d) * w * 0.16)
				end
			else
				nearest = 0
				sepX = sepX + RandRange(-1, 1)
				sepY = sepY + RandRange(-1, 1)
			end
			return false
		end)
	end
	if nearest == math.huge then
		nearest = nil
	end
	if routeMeanWeight > NAV_EPS then
		local nx = routeMeanNx / routeMeanWeight
		local ny = routeMeanNy / routeMeanWeight
		local nn = math.sqrt((nx * nx) + (ny * ny))
		if nn > NAV_EPS then
			nx = nx / nn
			ny = ny / nn
			local routeHalfBase = math.max(NPC_ROUTE_WALK_HALF_WIDTH, NPC_PERSONAL_SPACE * 1.45)
			local meanSide = routeMeanSideSum / routeMeanWeight
			local axisT = Clamp(-meanSide / math.max(NAV_EPS, routeHalfBase), -1, 1)
			sepX = sepX + (nx * axisT * 0.92)
			sepY = sepY + (ny * axisT * 0.92)
			routePassActive = true
		end
	end

	local timeMods = BuildTimeBehaviorModifiers()
	local timeDynamismFactor = Clamp(tonumber(timeMods and timeMods.dynamism) or 1.0, 0.20, 3.0)
	if behaviorRunner and behaviorRunner.Update then
		local routineEnv = {
			dt = dt,
			nearCount = nearCount,
			behaviorState = behaviorState,
			partner = partner,
			desiredHeading = desiredHeading,
			desiredIn = desiredIn,
			waitTimer = waitTimer,
			targetSpeed = targetSpeed,
			directedMove = false,
			timeModifiers = timeMods,
		}
		behaviorRunner.Update(npc, routineEnv)
		behaviorState = routineEnv.behaviorState or behaviorState
		partner = routineEnv.partner
		desiredHeading = routineEnv.desiredHeading or desiredHeading
		desiredIn = routineEnv.desiredIn or desiredIn
		waitTimer = routineEnv.waitTimer or waitTimer
		targetSpeed = routineEnv.targetSpeed or targetSpeed
		npc.directedMove = routineEnv.directedMove == true
	else
		npc.directedMove = false
	end
	local isDirectedWalk = (behaviorState == "walk") and (npc.directedMove == true)
	local lowCpuAgent = NPC_LOW_CPU_MODE and not manualOrderActive
	if manualOrderActive then
		if manualTalkAnchor then
			waitTimer = math.max(waitTimer, 0.25)
			desiredIn = math.min(desiredIn, 0.20)
			targetSpeed = 0
			local partnerId = tostring(manualOrder and manualOrder.partnerId or "")
			local talkPartner = FindNpcBySelector and select(1, FindNpcBySelector(partnerId)) or nil
			if talkPartner and talkPartner ~= npc then
				local faceHeading = AngleFromVector(
					(tonumber(talkPartner.u) or tonumber(npc.u) or 0.5) - (tonumber(npc.u) or 0.5),
					(tonumber(talkPartner.v) or tonumber(npc.v) or 0.5) - (tonumber(npc.v) or 0.5)
				)
				if faceHeading then
					desiredHeading = faceHeading
				end
			end
		else
			waitTimer = 0
			desiredIn = 0
			local tu = tonumber(npc.zoneShiftTargetU) or tonumber(manualOrder and manualOrder.targetU)
			local tv = tonumber(npc.zoneShiftTargetV) or tonumber(manualOrder and manualOrder.targetV)
			local toward = (tu and tv) and AngleFromVector(tu - npc.u, tv - npc.v) or nil
			if toward then
				local delta = math.abs(ShortestAngleDelta(heading, toward))
				if delta >= (PI * 0.55) then
					-- Ordre manuel en sens inverse: demi-tour immediat.
					heading = toward
					desiredHeading = toward
				else
					desiredHeading = toward
				end
			end
			local travelSpeedFactor = 0.96
			if actionRules and type(actionRules.GetTravelSpeedFactor) == "function" then
				local configured = tonumber(actionRules.GetTravelSpeedFactor(manualOrder and manualOrder.purpose))
				if configured then
					travelSpeedFactor = Clamp(configured, 0.55, 1.20)
				end
			elseif actionRules and type(actionRules.GetActionSpec) == "function" then
				local spec = actionRules.GetActionSpec(manualOrder and manualOrder.purpose)
				local configured = tonumber(spec and spec.travelSpeedFactor)
				if configured then
					travelSpeedFactor = Clamp(configured, 0.55, 1.20)
				end
			end
			targetSpeed = math.max(targetSpeed, NPC_SPEED_MAX * travelSpeedFactor * timeDynamismFactor)
		end
	end

	if behaviorState == "walk" and desiredIn <= 0 and not npc.directedMove then
		local jitter = NPC_WALK_DESIRED_JITTER
		if nearCount > 0 then
			jitter = jitter * 0.55
		end
		desiredHeading = WrapAngle(heading + RandRange(-jitter, jitter))
		desiredIn = RandRange(0.70, 2.00)
	end

	if nearCount > 0 and behaviorState ~= "discussion" and behaviorState ~= "self_pause" then
		local sepHeading = AngleFromVector(sepX, sepY)
		if sepHeading then
			local pressure = nearest and Clamp((NPC_CROWD_SENSE - nearest) / NPC_CROWD_SENSE, 0, 1) or 0.25
			local steerWeight = isDirectedWalk and 0.45 or 0.95
			desiredHeading =
				ApproachAngle(desiredHeading, WrapAngle(sepHeading), (0.22 + (pressure * steerWeight)) * PI)
			if isDirectedWalk then
				desiredIn = math.min(desiredIn, RandRange(0.18, 0.55))
			else
				desiredIn = math.min(desiredIn, RandRange(0.14, 0.45))
			end
		end
	end

	if nearest then
		if nearest <= NPC_PERSONAL_SPACE then
			local minFactor = isDirectedWalk and 0.72 or 0.40
			if routePassActive then
				minFactor = math.max(minFactor, 1.05)
			end
			targetSpeed = math.min(targetSpeed, NPC_SPEED_MIN * minFactor)
			if
				not isDirectedWalk
				and not routePassActive
				and waitTimer <= 0
				and math.random() < (NPC_WAIT_NEAR_CHANCE + 0.20)
			then
				waitTimer = RandRange(NPC_WAIT_MIN, NPC_WAIT_MAX)
			end
		else
			local crowdT =
				Clamp((nearest - NPC_PERSONAL_SPACE) / math.max(0.0001, NPC_CROWD_SENSE - NPC_PERSONAL_SPACE), 0, 1)
			local crowdSpeedFactor = NPC_CROWD_MIN_SPEED_FACTOR + ((1 - NPC_CROWD_MIN_SPEED_FACTOR) * crowdT)
			if isDirectedWalk then
				crowdSpeedFactor = math.max(crowdSpeedFactor, 0.78)
			end
			targetSpeed = math.min(targetSpeed, NPC_SPEED_MAX * crowdSpeedFactor)
		end
	end
	if routePassActive then
		waitTimer = 0
		targetSpeed = math.max(targetSpeed, NPC_SPEED_MIN * 1.10)
		if not isDirectedWalk then
			desiredIn = math.min(desiredIn, RandRange(0.08, 0.24))
		end
	end

	if waitTimer > 0 and not manualOrderActive then
		targetSpeed = 0
		desiredIn = math.min(desiredIn, 0.20)
	end

	local speedRoll = Clamp(dt * 0.24, 0, 0.22)
	if
		behaviorState == "walk"
		and waitTimer <= 0
		and not isDirectedWalk
		and not manualOrderActive
		and math.random() < speedRoll
	then
		targetSpeed = RandRange(NPC_SPEED_MIN * 0.60, NPC_SPEED_MAX * 0.92) * Clamp(timeDynamismFactor, 0.70, 1.45)
	end
	local needSpeedFactor = Clamp(tonumber(npc.needsSpeedFactor) or 1, 0.25, 1.0)
	if manualOrderActive and not manualTalkAnchor then
		targetSpeed = math.max(targetSpeed, NPC_SPEED_MAX * 0.94 * timeDynamismFactor)
	else
		targetSpeed = math.min(targetSpeed, NPC_SPEED_MAX * needSpeedFactor * Clamp(timeDynamismFactor, 0.70, 1.45))
	end
	local speedBlend = Clamp(dt * NPC_WALK_SPEED_BLEND, 0, 1)
	speed = speed + ((targetSpeed - speed) * speedBlend)

	if
		NPC_IDLE_FAST_PATH
		and lowCpuAgent
		and behaviorState == "walk"
		and waitTimer > 0
		and targetSpeed <= NAV_EPS
		and not isDirectedWalk
	then
		heading = ApproachAngle(heading, desiredHeading, turnRate * dt)
		npc.walkHeading = heading
		npc.walkDesiredHeading = desiredHeading
		npc.walkDesiredIn = desiredIn
		npc.walkTurnRate = turnRate
		npc.walkSpeedTarget = 0
		npc.speed = 0
		npc.waitTimer = waitTimer
		npc.behaviorState = Npc_GetSocialState(npc)
		return true
	end

	if behaviorState == "discussion" or behaviorState == "self_pause" then
		heading = ApproachAngle(heading, desiredHeading, turnRate * dt)
		npc.walkHeading = heading
		npc.walkDesiredHeading = desiredHeading
		npc.walkDesiredIn = desiredIn
		npc.walkTurnRate = turnRate
		npc.walkSpeedTarget = 0
		npc.speed = 0
		if behaviorState == "discussion" then
			npc.waitTimer = math.max(waitTimer, 0.14)
		else
			npc.waitTimer = math.max(waitTimer, 0.20)
		end
		npc.behaviorState = behaviorState
		return true
	end

	if manualTalkAnchor then
		heading = ApproachAngle(heading, desiredHeading, turnRate * dt)
		npc.walkHeading = heading
		npc.walkDesiredHeading = desiredHeading
		npc.walkDesiredIn = desiredIn
		npc.walkTurnRate = turnRate
		npc.walkSpeedTarget = 0
		npc.speed = 0
		npc.waitTimer = math.max(waitTimer, 0.20)
		npc.behaviorState = "walk"
		return true
	end

	local lookAhead = NPC_WALK_LOOK_AHEAD + (speed * 0.22)
	local aheadX = npc.u + (math.cos(heading) * lookAhead)
	local aheadY = npc.v + (math.sin(heading) * lookAhead)
	local forwardCrowdSpace = isDirectedWalk and (NPC_PERSONAL_SPACE * 0.72) or (NPC_PERSONAL_SPACE * 0.90)
	if
		(
			manualOrder
			and manualOrder.freeMove == true
			and (not IsCrowdSpaceFree(npc, aheadX, aheadY, forwardCrowdSpace))
		)
		or (
			not (manualOrder and manualOrder.freeMove == true)
			and (
				(not IsPointWalkable(aheadX, aheadY))
				or (not C.IsSegmentOnStrictNetwork(npc.u, npc.v, aheadX, aheadY))
				or (not IsCrowdSpaceFree(npc, aheadX, aheadY, forwardCrowdSpace))
			)
		)
	then
		local found = false
		local probeOffsets
		if manualOrderActive then
			probeOffsets = { 0.08, -0.08, 0.16, -0.16, 0.28, -0.28, 0.42, -0.42, 0.60, -0.60, 0.84, -0.84 }
		else
			probeOffsets = { 0.12, -0.12, 0.24, -0.24, 0.40, -0.40, 0.62, -0.62, 0.90, -0.90, 1.20, -1.20 }
		end
		local maxProbeChecks = #probeOffsets
		if lowCpuAgent and not manualOrderActive then
			maxProbeChecks = math.min(maxProbeChecks, NPC_LOW_CPU_PROBE_COUNT)
		end
		for i = 1, maxProbeChecks do
			local h = WrapAngle(heading + probeOffsets[i])
			local tx = npc.u + (math.cos(h) * lookAhead)
			local ty = npc.v + (math.sin(h) * lookAhead)
			if
				(
					(manualOrder and manualOrder.freeMove == true)
					and IsCrowdSpaceFree(npc, tx, ty, forwardCrowdSpace)
				)
				or (
					not (manualOrder and manualOrder.freeMove == true)
					and IsPointWalkable(tx, ty)
					and C.IsSegmentOnStrictNetwork(npc.u, npc.v, tx, ty)
					and IsCrowdSpaceFree(npc, tx, ty, forwardCrowdSpace)
				)
			then
				desiredHeading = h
				if manualOrderActive then
					desiredIn = 0
				else
					desiredIn = RandRange(0.25, 0.65)
				end
				found = true
				break
			end
		end
		if not found then
			if manualOrderActive then
				local tu = tonumber(npc.zoneShiftTargetU)
				local tv = tonumber(npc.zoneShiftTargetV)
				local toward = (tu and tv) and AngleFromVector(tu - npc.u, tv - npc.v) or nil
				if toward then
					desiredHeading = ApproachAngle(heading, toward, PI * 0.90)
				else
					desiredHeading = WrapAngle(heading + 0.85)
				end
				desiredIn = 0
			else
				if math.random() < NPC_REVERSE_CHANCE then
					desiredHeading = WrapAngle(heading + PI + RandRange(-0.22, 0.22))
				else
					local sign = (math.random() < 0.5) and -1 or 1
					desiredHeading = WrapAngle(heading + (sign * RandRange(0.85, 1.35)))
				end
				desiredIn = RandRange(0.18, 0.42)
			end
		end
	end

	heading = ApproachAngle(heading, desiredHeading, turnRate * dt)

	local remaining = math.max(0, speed * dt)
	local severeBlockThisUpdate = false
	local loops = 0
	local maxMoveLoops = lowCpuAgent and NPC_LOW_CPU_MOVE_MAX_LOOPS or 24
	while remaining > NAV_EPS and loops < maxMoveLoops do
		loops = loops + 1
		local step = math.min(NPC_WALK_STEP, remaining)
		local nx = npc.u + (math.cos(heading) * step)
		local ny = npc.v + (math.sin(heading) * step)
		local moveCrowdSpace = isDirectedWalk and (NPC_PERSONAL_SPACE * 0.70) or (NPC_PERSONAL_SPACE * 0.85)
		if
			((manualOrder and manualOrder.freeMove == true) and IsCrowdSpaceFree(npc, nx, ny, moveCrowdSpace))
			or (
				not (manualOrder and manualOrder.freeMove == true)
				and IsPointWalkable(nx, ny)
				and C.IsSegmentOnStrictNetwork(npc.u, npc.v, nx, ny)
				and IsCrowdSpaceFree(npc, nx, ny, moveCrowdSpace)
			)
		then
			npc.u = nx
			npc.v = ny
			remaining = remaining - step
		else
			local recovered = false
			local rescueOffsets
			if manualOrderActive then
				rescueOffsets = { 0.08, -0.08, 0.18, -0.18, 0.32, -0.32, 0.48, -0.48, 0.68, -0.68, 0.92, -0.92 }
			else
				rescueOffsets = { 0.10, -0.10, 0.22, -0.22, 0.38, -0.38, 0.58, -0.58, 0.82, -0.82, 1.10, -1.10 }
			end
			local maxRescueChecks = #rescueOffsets
			if lowCpuAgent and not manualOrderActive then
				maxRescueChecks = math.min(maxRescueChecks, NPC_LOW_CPU_RESCUE_COUNT)
			end
			for i = 1, maxRescueChecks do
				local h2 = WrapAngle(heading + rescueOffsets[i])
				local tx = npc.u + (math.cos(h2) * step)
				local ty = npc.v + (math.sin(h2) * step)
				if
					(
						(manualOrder and manualOrder.freeMove == true)
						and IsCrowdSpaceFree(npc, tx, ty, moveCrowdSpace)
					)
					or (
						not (manualOrder and manualOrder.freeMove == true)
						and IsPointWalkable(tx, ty)
						and C.IsSegmentOnStrictNetwork(npc.u, npc.v, tx, ty)
						and IsCrowdSpaceFree(npc, tx, ty, moveCrowdSpace)
					)
				then
					heading = ApproachAngle(heading, h2, turnRate * dt * 2.4)
					desiredHeading = heading
					if manualOrderActive then
						desiredIn = 0
					else
						desiredIn = RandRange(0.20, 0.60)
					end
					npc.u = tx
					npc.v = ty
					remaining = remaining - step
					recovered = true
					break
				end
			end
			if not recovered then
				severeBlockThisUpdate = true
				if manualOrderActive then
					local tu = tonumber(npc.zoneShiftTargetU)
					local tv = tonumber(npc.zoneShiftTargetV)
					local toward = (tu and tv) and AngleFromVector(tu - npc.u, tv - npc.v) or nil
					if toward then
						heading = ApproachAngle(heading, toward, turnRate * dt * 3.2)
					else
						heading = WrapAngle(heading + 0.62)
					end
					desiredHeading = heading
					desiredIn = 0
					remaining = remaining - (step * 0.25)
					speed = math.max(NPC_SPEED_MIN * 0.92, speed * 0.95)
				else
					if math.random() < NPC_REVERSE_CHANCE then
						heading = WrapAngle(heading + PI + RandRange(-0.18, 0.18))
					else
						local sign = (math.random() < 0.5) and -1 or 1
						heading = WrapAngle(heading + (sign * RandRange(0.75, 1.10)))
					end
					desiredHeading = heading
					desiredIn = RandRange(0.25, 0.55)
					remaining = remaining - (step * 0.5)
					speed = math.max(NPC_SPEED_MIN * 0.55, speed * 0.82)
					if waitTimer <= 0 and math.random() < (NPC_WAIT_NEAR_CHANCE * 0.5) then
						waitTimer = RandRange(NPC_WAIT_MIN * 0.5, NPC_WAIT_MAX * 0.85)
					end
				end
			end
		end
	end

	if severeBlockThisUpdate then
		npc.severeBlockIterations = math.max(0, tonumber(npc.severeBlockIterations) or 0) + 1
		if npc.severeBlockIterations >= (tonumber(C.NPC_SEVERE_BLOCK_MAX_ITERATIONS) or 3) then
			C.Npc_ForceNewActionAfterSevereBlock(npc)
			return true
		end
	elseif (tonumber(npc.severeBlockIterations) or 0) > 0 then
		npc.severeBlockIterations = 0
		npc.severeBlockEscalation = 0
	end

	npc.walkHeading = heading
	npc.walkDesiredHeading = desiredHeading
	npc.walkDesiredIn = desiredIn
	npc.walkTurnRate = turnRate
	npc.walkSpeedTarget = targetSpeed
	npc.speed = speed
	npc.waitTimer = waitTimer
	npc.behaviorState = Npc_GetSocialState(npc)
	return true
end

Npc_EnterRouteMode = nil
Npc_EnterPlazaMode = nil
Npc_UpdateTransition = nil

function Npc_PickTarget(npc)
	npc.tx = RandomWorldCoord()
	npc.ty = RandomWorldCoord()
	npc.speed = RandRange(NPC_SPEED_MIN, NPC_SPEED_MAX)
end

function CreateNpcVisual(atlasName)
	local holder = CreateFrame("Frame", nil, npcLayer)
	holder:SetSize(NPC_BASE_SIZE, NPC_BASE_SIZE)
	holder:EnableMouse(false)

	local shadow = holder:CreateTexture(nil, "BACKGROUND", nil, 1)
	shadow:SetSize(NPC_SHADOW_W, NPC_SHADOW_H)
	shadow:SetPoint("CENTER", holder, "CENTER", 0, NPC_SHADOW_OFFSET_Y)
	shadow:SetAtlas("GarrFollower-Shadow")
	shadow:SetAlpha(0.85)

	local iconHost = CreateFrame("Frame", nil, holder)
	iconHost:SetSize(NPC_ICON_SIZE, NPC_ICON_SIZE)
	iconHost:SetPoint("CENTER", holder, "CENTER", 0, 0)

	local icon = iconHost:CreateTexture(nil, "ARTWORK", nil, 1)
	icon:SetAllPoints(iconHost)
	local iconAtlas = IsAtlasUsable(atlasName) and atlasName or NPC_FALLBACK_ATLAS
	icon:SetAtlas(iconAtlas)

	local mask = iconHost:CreateMaskTexture(nil, "ARTWORK")
	mask:SetAllPoints(iconHost)
	mask:SetTexture(
		"Interface\\CharacterFrame\\TempPortraitAlphaMask",
		"CLAMPTOBLACKADDITIVE",
		"CLAMPTOBLACKADDITIVE"
	)
	icon:AddMaskTexture(mask)

	local ringHost = CreateFrame("Frame", nil, holder)
	ringHost:SetAllPoints(holder)
	ringHost:SetFrameLevel(iconHost:GetFrameLevel() + 5)

	local ring = ringHost:CreateTexture(nil, "OVERLAY", nil, 1)
	ring:SetSize(NPC_RING_W, NPC_RING_H)
	ring:SetPoint("CENTER", ringHost, "CENTER", NPC_RING_OFFSET_X, NPC_RING_OFFSET_Y)
	ring:SetAtlas("Map_Faction_Ring")
	ring:SetAlpha(1)
	ring:SetDrawLayer("OVERLAY", 7)

	local ringTint = ringHost:CreateTexture(nil, "OVERLAY", nil, 2)
	ringTint:SetSize(NPC_RING_W, NPC_RING_H)
	ringTint:SetPoint("CENTER", ringHost, "CENTER", NPC_RING_OFFSET_X, NPC_RING_OFFSET_Y)
	ringTint:SetAtlas("Map_Faction_Ring")
	ringTint:SetBlendMode("ADD")
	ringTint:SetAlpha(0)
	ringTint:SetDrawLayer("OVERLAY", 7)

	local selectedMoodFxBg = ringHost:CreateTexture(nil, "OVERLAY", nil, 6)
	selectedMoodFxBg:SetSize(22, 25)
	selectedMoodFxBg:SetPoint(
		"CENTER",
		ringHost,
		"BOTTOM",
		NPC_RING_OFFSET_X,
		math.floor((NPC_RING_H * 0.18) + NPC_RING_OFFSET_Y + 54)
	)
	selectedMoodFxBg:SetAtlas("UF-SoulShard-Holder")
	selectedMoodFxBg:SetAlpha(0)
	selectedMoodFxBg:Hide()

	local selectedMoodFx = ringHost:CreateTexture(nil, "OVERLAY", nil, 7)
	selectedMoodFx:SetSize(15, 20)
	selectedMoodFx:SetPoint(
		"CENTER",
		ringHost,
		"BOTTOM",
		NPC_RING_OFFSET_X,
		math.floor((NPC_RING_H * 0.18) + NPC_RING_OFFSET_Y + 55)
	)
	selectedMoodFx:SetAtlas("UF-SoulShard-Icon")
	selectedMoodFx:SetAlpha(0)
	if selectedMoodFx.SetDesaturated then
		selectedMoodFx:SetDesaturated(true)
	end
	selectedMoodFx:Hide()

	holder._iconHost = iconHost
	holder._icon = icon
	holder._ringHost = ringHost
	holder._shadow = shadow
	holder._ring = ring
	holder._ringTint = ringTint
	holder._selectedMoodFxBg = selectedMoodFxBg
	holder._selectedMoodFx = selectedMoodFx

	return holder
end

function ApplyNpcPortraitSource(npc)
	if type(npc) ~= "table" then
		return
	end
	local icon = npc.frame and npc.frame._icon or nil
	if not icon then
		return
	end
	local texturePath = tostring(npc.portraitTexturePath or "")
	if texturePath ~= "" then
		icon:SetTexture(texturePath)
		icon:SetTexCoord(0, 1, 0, 1)
		ApplyNpcPortraitFlip(npc.frame, npc.portraitFlipX == true)
		return
	end
	local unit = tostring(npc.portraitUnit or "")
	if unit ~= "" and SetPortraitTexture then
		icon:SetTexture(nil)
		icon:SetTexCoord(0, 1, 0, 1)
		SetPortraitTexture(icon, unit)
	else
		local atlas = tostring(npc.portraitAtlas or "")
		if not IsAtlasUsable(atlas) then
			atlas = NPC_FALLBACK_ATLAS
		end
		icon:SetAtlas(atlas)
	end
	ApplyNpcPortraitFlip(npc.frame, npc.portraitFlipX == true)
end

function Npc_UpdateRegisseuseRoam(npc, dt)
	if type(npc) ~= "table" then
		return
	end
	local u = Clamp(tonumber(npc.u) or 0.5, 0, 1)
	local v = Clamp(tonumber(npc.v) or 0.5, 0, 1)
	local centerU = Clamp(tonumber(npc.regieCenterU) or u, 0, 1)
	local centerV = Clamp(tonumber(npc.regieCenterV) or v, 0, 1)
	local radius = Clamp(tonumber(npc.regieRadius) or 0.040, 0.015, 0.090)
	local speed = Clamp(tonumber(npc.regieSpeed) or (NPC_SPEED_MIN * 0.80), NPC_SPEED_MIN * 0.40, NPC_SPEED_MAX * 0.80)

	npc.regieWait = math.max(0, (tonumber(npc.regieWait) or 0) - dt)
	local targetU = tonumber(npc.regieTargetU)
	local targetV = tonumber(npc.regieTargetV)
	local needTarget = not (targetU and targetV)
	if not needTarget then
		local reach2 = (0.0035 * 0.0035)
		needTarget = Dist2Points(u, v, targetU, targetV) <= reach2
	end
	if npc.regieWait > 0 then
		needTarget = false
	end
	if needTarget then
		local pickedU, pickedV = nil, nil
		for _ = 1, 28 do
			local ang = RandRange(0, TWO_PI)
			local r = RandRange(radius * 0.25, radius)
			local cu = Clamp(centerU + (math.cos(ang) * r), 0, 1)
			local cv = Clamp(centerV + (math.sin(ang) * r), 0, 1)
			local zoneKey = select(1, GetZoneKeyAtPoint(cu, cv))
			local inLieu = (GetLieuAtPoint(cu, cv) ~= nil)
			if IsPointWalkable(cu, cv) and IsZoneEntryAllowed(npc, zoneKey, true) and not inLieu then
				pickedU, pickedV = cu, cv
				break
			end
		end
		npc.regieTargetU = pickedU or centerU
		npc.regieTargetV = pickedV or centerV
		targetU = npc.regieTargetU
		targetV = npc.regieTargetV
	end

	if npc.regieWait <= 0 and targetU and targetV then
		local dx = targetU - u
		local dy = targetV - v
		local dist = math.sqrt((dx * dx) + (dy * dy))
		if dist > 1e-6 then
			local step = math.min(dist, speed * dt)
			local nx = u + ((dx / dist) * step)
			local ny = v + ((dy / dist) * step)
			if IsPointWalkable(nx, ny) and (GetLieuAtPoint(nx, ny) == nil) then
				npc.u = Clamp(nx, 0, 1)
				npc.v = Clamp(ny, 0, 1)
			end
			local heading = AngleFromVector(dx, dy)
			if heading then
				npc.walkHeading = heading
			end
		else
			npc.regieWait = RandRange(0.9, 2.4)
		end
	end
	npc.behaviorState = "walk"
end

function SetNpcVisualHeight(frameNpc, level)
	if not frameNpc then
		return
	end
	local base = math.max(1, math.floor(tonumber(level) or (npcLayer:GetFrameLevel() + 1)))
	frameNpc:SetFrameLevel(base)
	local iconHost = frameNpc._iconHost
	if iconHost then
		iconHost:SetFrameLevel(base + 2)
	end
	local ringHost = frameNpc._ringHost
	if ringHost then
		ringHost:SetFrameLevel(base + 6)
	end
end

function UpdateNpcRingColor(npc)
	if not npc or not npc.frame or not npc.frame._ring then
		return
	end
	local ring = npc.frame._ring
	local ringTint = npc.frame._ringTint
	local selectedMoodFxBg = npc.frame._selectedMoodFxBg
	local selectedMoodFx = npc.frame._selectedMoodFx
	ring:SetVertexColor(1, 1, 1, 1)
	local selectedId = tostring(state and state._selectedNpcId or "")
	local isSelected = selectedId ~= "" and (tostring(npc.persistentId or "") == selectedId)
	if ring.SetDesaturated then
		ring:SetDesaturated(not isSelected)
	end
	if ringTint then
		ringTint:SetAlpha(0)
	end
	if selectedMoodFx then
		if isSelected then
			local needs = type(npc.needs) == "table" and npc.needs or {}
			local social = Clamp(tonumber(needs.social) or 50, 0, 100)
			local fatigue = Clamp(tonumber(needs.fatigue) or 50, 0, 100)
			local faim = Clamp(tonumber(needs.faim) or 50, 0, 100)
			local distraction = Clamp(tonumber(needs.distraction) or 50, 0, 100)
			local avg = (social + fatigue + faim + distraction) * 0.25
			local r, g
			if avg <= 50 then
				r = 1
				g = avg / 50
			else
				r = 1 - ((avg - 50) / 50)
				g = 1
			end
			selectedMoodFx:SetVertexColor(Clamp(r, 0, 1), Clamp(g, 0, 1), 0.18, 0.92)
			selectedMoodFx:SetAlpha(1)
			selectedMoodFx:Show()
			if selectedMoodFxBg then
				selectedMoodFxBg:SetAlpha(1)
				selectedMoodFxBg:Show()
			end
		else
			selectedMoodFx:SetAlpha(0)
			selectedMoodFx:Hide()
			if selectedMoodFxBg then
				selectedMoodFxBg:SetAlpha(0)
				selectedMoodFxBg:Hide()
			end
		end
	end
end


end

return Modules
