local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.NpcMovementRoutines = QM.NpcMovementRoutines or {}

function QM.NpcMovementRoutines.CreateRunner(api)
	if type(api) ~= "table" then
		return nil
	end

	local Clamp = assert(api.Clamp)
	local RandRange = assert(api.RandRange)
	local WrapAngle = assert(api.WrapAngle)
	local ApproachAngle = assert(api.ApproachAngle)
	local AngleFromVector = assert(api.AngleFromVector)
	local FindPlazaEdgeInfoAtPoint = assert(api.FindPlazaEdgeInfoAtPoint)
	local BuildSelfPauseZoneKey = assert(api.BuildSelfPauseZoneKey)
	local FindEncounterCandidate = assert(api.FindEncounterCandidate)
	local Npc_BeginSelfPause = assert(api.Npc_BeginSelfPause)
	local Npc_BeginApproachPair = assert(api.Npc_BeginApproachPair)
	local Npc_BeginDuoWalkPair = assert(api.Npc_BeginDuoWalkPair)
	local Npc_BeginDiscussionPair = assert(api.Npc_BeginDiscussionPair)
	local Npc_BreakSocialPair = assert(api.Npc_BreakSocialPair)
	local Npc_EndDiscussionPair = assert(api.Npc_EndDiscussionPair)
	local Npc_ResetSocialState = assert(api.Npc_ResetSocialState)
	local IsGlobalTalkLocked = assert(api.IsGlobalTalkLocked)
	local IsSocialPartnerValid = assert(api.IsSocialPartnerValid)
	local AreNpcsInSameConversation = api.AreNpcsInSameConversation
	if type(AreNpcsInSameConversation) ~= "function" then
		AreNpcsInSameConversation = function(a, b)
			return (a and b) and (a.behaviorPartner == b) and (b.behaviorPartner == a)
		end
	end
	local PickSocialWalkTarget = assert(api.PickSocialWalkTarget)
	local Npc_PickLongWalkTarget = assert(api.Npc_PickLongWalkTarget)
	local Npc_PickCurrentPlazaWalkPoint = assert(api.Npc_PickCurrentPlazaWalkPoint)
	local Npc_PickCurrentRouteWalkPoint = assert(api.Npc_PickCurrentRouteWalkPoint)
	local Npc_PickCurrentRoutePoiPoint = assert(api.Npc_PickCurrentRoutePoiPoint)
	local Npc_ShouldLeaveZone = assert(api.Npc_ShouldLeaveZone)
	local Npc_RequestZoneExit = assert(api.Npc_RequestZoneExit)
	local Npc_ResolveZoneShiftPath = api.Npc_ResolveZoneShiftPath
	local Npc_AdvanceZoneShiftPath = api.Npc_AdvanceZoneShiftPath

	local NPC_SELF_PAUSE_CHANCE = assert(api.NPC_SELF_PAUSE_CHANCE)
	local NPC_SELF_PAUSE_EDGE_MAX_DIST = assert(api.NPC_SELF_PAUSE_EDGE_MAX_DIST)
	local NPC_SELF_PAUSE_EDGE_MIN_DIST = assert(api.NPC_SELF_PAUSE_EDGE_MIN_DIST)
	local NPC_SELF_PAUSE_COOLDOWN_MIN = assert(api.NPC_SELF_PAUSE_COOLDOWN_MIN)
	local NPC_SELF_PAUSE_COOLDOWN_MAX = assert(api.NPC_SELF_PAUSE_COOLDOWN_MAX)
	local NPC_SELF_PAUSE_MIN = assert(api.NPC_SELF_PAUSE_MIN)
	local NPC_SELF_PAUSE_MAX = assert(api.NPC_SELF_PAUSE_MAX)
	local NPC_SOCIAL_ENCOUNTER_NEAR_MAX = assert(api.NPC_SOCIAL_ENCOUNTER_NEAR_MAX)
	local NPC_SOCIAL_ENCOUNTER_PROC_CHANCE = assert(api.NPC_SOCIAL_ENCOUNTER_PROC_CHANCE)
	local NPC_SOCIAL_ENCOUNTER_CHECK_MIN = assert(api.NPC_SOCIAL_ENCOUNTER_CHECK_MIN)
	local NPC_SOCIAL_ENCOUNTER_CHECK_MAX = assert(api.NPC_SOCIAL_ENCOUNTER_CHECK_MAX)
	local NPC_SOCIAL_ENCOUNTER_SAME_DIR_BLOCK_DELTA = assert(api.NPC_SOCIAL_ENCOUNTER_SAME_DIR_BLOCK_DELTA)
	local NPC_SOCIAL_ENCOUNTER_RADIUS = assert(api.NPC_SOCIAL_ENCOUNTER_RADIUS)
	local NPC_SOCIAL_APPROACH_STOP_DIST = assert(api.NPC_SOCIAL_APPROACH_STOP_DIST)
	local NPC_SOCIAL_DUO_WALK_CHANCE = assert(api.NPC_SOCIAL_DUO_WALK_CHANCE)
	local NPC_SOCIAL_DUO_WALK_MIN = assert(api.NPC_SOCIAL_DUO_WALK_MIN)
	local NPC_SOCIAL_DUO_WALK_MAX = assert(api.NPC_SOCIAL_DUO_WALK_MAX)
	local NPC_SOCIAL_DUO_TARGET_RADIUS = assert(api.NPC_SOCIAL_DUO_TARGET_RADIUS)
	local NPC_SOCIAL_DUO_TARGET_REACH = assert(api.NPC_SOCIAL_DUO_TARGET_REACH)
	local NPC_SOCIAL_DUO_SEPARATION = assert(api.NPC_SOCIAL_DUO_SEPARATION)
	local NPC_SOCIAL_DISCUSS_PREFERRED_DIST = assert(api.NPC_SOCIAL_DISCUSS_PREFERRED_DIST)
	local NPC_SOCIAL_DISCUSS_MIN_DIST = assert(api.NPC_SOCIAL_DISCUSS_MIN_DIST)
	local NPC_SOCIAL_DISCUSS_MIN = assert(api.NPC_SOCIAL_DISCUSS_MIN)
	local NPC_SOCIAL_DISCUSS_MAX = assert(api.NPC_SOCIAL_DISCUSS_MAX)
	local NPC_AUTO_SOCIAL_ENABLED = api.NPC_AUTO_SOCIAL_ENABLED == true
	local NPC_AUTO_SOCIAL_MAX_RESERVE = Clamp(tonumber(api.NPC_AUTO_SOCIAL_MAX_RESERVE) or 70, 0, 100)
	local NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MIN = Clamp(tonumber(api.NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MIN) or 0.04, 0, 1)
	local NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MAX = Clamp(
		tonumber(api.NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MAX) or 0.22,
		NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MIN,
		1
	)
	local NPC_SOCIAL_DISENGAGE_MIN_DIST = assert(api.NPC_SOCIAL_DISENGAGE_MIN_DIST)
	local NPC_SOCIAL_POST_TALK_ZONE_REACH = assert(api.NPC_SOCIAL_POST_TALK_ZONE_REACH)
	local NPC_LONG_GOAL_MIN_DIST = assert(api.NPC_LONG_GOAL_MIN_DIST)
	local NPC_LONG_GOAL_MAX_DIST = assert(api.NPC_LONG_GOAL_MAX_DIST)
	local NPC_LONG_GOAL_RETARGET_MIN = assert(api.NPC_LONG_GOAL_RETARGET_MIN)
	local NPC_LONG_GOAL_RETARGET_MAX = assert(api.NPC_LONG_GOAL_RETARGET_MAX)
	local NPC_LONG_GOAL_REACH = assert(api.NPC_LONG_GOAL_REACH)
	local NPC_POI_PICK_CHANCE = assert(api.NPC_POI_PICK_CHANCE)
	local NPC_POI_PICK_RADIUS = assert(api.NPC_POI_PICK_RADIUS)
	local NPC_POI_NEAR_RADIUS = assert(api.NPC_POI_NEAR_RADIUS)
	local NPC_POI_PAUSE_MULT_MIN = assert(api.NPC_POI_PAUSE_MULT_MIN)
	local NPC_POI_PAUSE_MULT_MAX = assert(api.NPC_POI_PAUSE_MULT_MAX)
	local NPC_PLAZA_ROAM_RETARGET_MIN = assert(api.NPC_PLAZA_ROAM_RETARGET_MIN)
	local NPC_PLAZA_ROAM_RETARGET_MAX = assert(api.NPC_PLAZA_ROAM_RETARGET_MAX)
	local NPC_PERSONAL_SPACE = assert(api.NPC_PERSONAL_SPACE)
	local NPC_SPEED_MIN = assert(api.NPC_SPEED_MIN)
	local NPC_SPEED_MAX = assert(api.NPC_SPEED_MAX)
	local PI = assert(api.PI)
	local NAV_EPS = assert(api.NAV_EPS)

	local routines = {}

	local function AngleDeltaAbs(a, b)
		local delta = ((a - b + PI) % (PI * 2)) - PI
		return math.abs(delta)
	end

	local function IsSameDirectionTalkBlocked(a, b)
		local ha = tonumber(a and (a.walkHeading or a.walkDesiredHeading))
		local hb = tonumber(b and (b.walkHeading or b.walkDesiredHeading))
		if not ha or not hb then
			return false
		end
		local sa = tonumber(a and a.speed) or 0
		local sb = tonumber(b and b.speed) or 0
		if sa <= (NPC_SPEED_MIN * 0.25) or sb <= (NPC_SPEED_MIN * 0.25) then
			return false
		end
		return AngleDeltaAbs(ha, hb) <= NPC_SOCIAL_ENCOUNTER_SAME_DIR_BLOCK_DELTA
	end

	local function SetSoftCooldown(npc, minFactor, maxFactor)
		if not npc then
			return
		end
		local lo = math.max(0.15, NPC_SOCIAL_ENCOUNTER_CHECK_MIN * (tonumber(minFactor) or 1.0))
		local hi = math.max(lo + 0.05, NPC_SOCIAL_ENCOUNTER_CHECK_MAX * (tonumber(maxFactor) or 1.0))
		npc.behaviorCooldown = math.max(tonumber(npc.behaviorCooldown) or 0, RandRange(lo, hi))
	end

	local function GetAutoSocialTriggerChance(npc)
		local reserve = Clamp(
			tonumber(npc and npc.needs and npc.needs.social) or 100,
			0,
			100
		)
		if reserve > NPC_AUTO_SOCIAL_MAX_RESERVE then
			return 0
		end
		local needFactor = 1 - (reserve / math.max(1, NPC_AUTO_SOCIAL_MAX_RESERVE))
		local dynamic = NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MIN
			+ ((NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MAX - NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MIN) * needFactor)
		local legacyFloor = Clamp(NPC_SOCIAL_ENCOUNTER_PROC_CHANCE * 0.22, 0, 1)
		return Clamp(math.max(dynamic, legacyFloor), 0, 1)
	end

	local function SoftAbortInteraction(npc, partner)
		if IsSocialPartnerValid(npc, partner) and partner.behaviorPartner == npc then
			Npc_ResetSocialState(partner, true)
			SetSoftCooldown(partner, 1.8, 3.4)
		end
		Npc_ResetSocialState(npc, true)
		SetSoftCooldown(npc, 1.6, 3.0)
	end

	local ZONE_ACTIONS_PER_ZONE = math.max(1, math.floor(tonumber(api.NPC_ZONE_ROUTINE_ACTIONS) or 2))
	local ZONE_ACTION_PAUSE_MIN = Clamp(tonumber(api.NPC_ZONE_ROUTINE_PAUSE_MIN) or 1.8, 0.2, 30)
	local ZONE_ACTION_PAUSE_MAX = Clamp(
		tonumber(api.NPC_ZONE_ROUTINE_PAUSE_MAX) or 4.8,
		ZONE_ACTION_PAUSE_MIN,
		60
	)
	local ZONE_TARGET_TTL_MIN = Clamp(tonumber(api.NPC_ZONE_ROUTINE_TTL_MIN) or 5.5, 0.5, 60)
	local ZONE_TARGET_TTL_MAX = Clamp(
		tonumber(api.NPC_ZONE_ROUTINE_TTL_MAX) or 12.0,
		ZONE_TARGET_TTL_MIN,
		90
	)

	local function GetCurrentZoneRoutineKey(npc)
		local key = npc and npc.zoneKey
		if type(key) == "string" and key ~= "" then
			return key
		end
		local kind = npc and npc.zoneKind
		if type(kind) == "string" and kind ~= "" then
			return "kind:" .. kind
		end
		return "none"
	end

	local function ResetZoneRoutineState(npc, zoneKey)
		if not npc then
			return
		end
		npc.zoneRoutineZoneKey = zoneKey or GetCurrentZoneRoutineKey(npc)
		npc.zoneRoutineActionCount = 0
		npc.zoneRoutineStep = "move"
		npc.zoneRoutinePause = 0
		npc.zoneRoutineTargetU = nil
		npc.zoneRoutineTargetV = nil
		npc.zoneRoutineTargetTtl = 0
		npc.zoneRoutineTargetIsPoi = nil
	end

	local function PickActionTargetInCurrentZone(npc)
		if npc and npc.zoneKind == "plaza" then
			local pu, pv = Npc_PickCurrentPlazaWalkPoint(npc)
			if pu and pv then
				return pu, pv, false
			end
		end
		if npc and npc.zoneKind == "route" then
			local triedPoiFirst = false
			if math.random() < NPC_POI_PICK_CHANCE then
				triedPoiFirst = true
				local poiU, poiV = Npc_PickCurrentRoutePoiPoint(npc, NPC_POI_PICK_RADIUS, true)
				if poiU and poiV then
					return poiU, poiV, true
				end
			end
			local ru, rv = Npc_PickCurrentRouteWalkPoint(npc)
			if ru and rv then
				return ru, rv, false
			end
			if not triedPoiFirst then
				local poiU, poiV = Npc_PickCurrentRoutePoiPoint(npc, NPC_POI_PICK_RADIUS, true)
				if poiU and poiV then
					return poiU, poiV, true
				end
			end
		end
		local minDist = math.max(NPC_LONG_GOAL_MIN_DIST * 0.45, NPC_SOCIAL_POST_TALK_ZONE_REACH * 2.0)
		local maxDist = math.max(minDist + 0.04, NPC_LONG_GOAL_MAX_DIST * 0.70)
		local lu, lv = Npc_PickLongWalkTarget(npc, minDist, maxDist)
		return lu, lv, false
	end

	local function UpdateZonePatrolRoutine(npc, env)
		local dynFactor = Clamp(tonumber(env and env.timeDynamismMultiplier) or 1.0, 0.20, 3.0)
		local zoneKey = GetCurrentZoneRoutineKey(npc)
		if npc.zoneRoutineZoneKey ~= zoneKey then
			ResetZoneRoutineState(npc, zoneKey)
		end

		local actionCount = math.max(0, math.floor(tonumber(npc.zoneRoutineActionCount) or 0))
		if actionCount >= ZONE_ACTIONS_PER_ZONE then
			if Npc_RequestZoneExit(npc) then
				SetSoftCooldown(npc, 0.7, 1.3)
				ResetZoneRoutineState(npc, nil)
			else
				npc.zoneRoutineActionCount = 0
				npc.zoneRoutineStep = "move"
			end
			return
		end

		if npc.zoneRoutineStep == "pause" then
			local pauseLeft = math.max(0, (tonumber(npc.zoneRoutinePause) or 0) - env.dt)
			npc.zoneRoutinePause = pauseLeft
			env.targetSpeed = 0
			env.waitTimer = math.max(env.waitTimer, 0.24)
			env.desiredIn = math.min(env.desiredIn, 0.10)
			if pauseLeft <= 0 then
				if actionCount >= ZONE_ACTIONS_PER_ZONE then
					if Npc_RequestZoneExit(npc) then
						SetSoftCooldown(npc, 0.7, 1.3)
						ResetZoneRoutineState(npc, nil)
					else
						npc.zoneRoutineActionCount = 0
					end
				else
					npc.zoneRoutineStep = "move"
					npc.zoneRoutineTargetU = nil
					npc.zoneRoutineTargetV = nil
					npc.zoneRoutineTargetTtl = 0
					npc.zoneRoutineTargetIsPoi = nil
				end
			end
			return
		end

		npc.zoneRoutineStep = "move"
		npc.zoneRoutineTargetTtl = math.max(0, (tonumber(npc.zoneRoutineTargetTtl) or 0) - env.dt)

		local targetU = tonumber(npc.zoneRoutineTargetU)
		local targetV = tonumber(npc.zoneRoutineTargetV)
		if targetU and targetV then
			local dx = targetU - (tonumber(npc.u) or targetU)
			local dy = targetV - (tonumber(npc.v) or targetV)
			local reach = NPC_LONG_GOAL_REACH * 1.15
			if ((dx * dx) + (dy * dy)) <= (reach * reach) then
				local reachedPoi = (npc.zoneRoutineTargetIsPoi and true) or false
				if (not reachedPoi) and npc.zoneKind == "route" then
					local _, _, poiDist = Npc_PickCurrentRoutePoiPoint(npc, NPC_POI_NEAR_RADIUS, false)
					reachedPoi = tonumber(poiDist) ~= nil
				end
				npc.zoneRoutineTargetU = nil
				npc.zoneRoutineTargetV = nil
				npc.zoneRoutineTargetTtl = 0
				npc.zoneRoutineTargetIsPoi = nil
				npc.zoneRoutineActionCount = actionCount + 1
				npc.zoneRoutineStep = "pause"
				local pauseFor = RandRange(ZONE_ACTION_PAUSE_MIN, ZONE_ACTION_PAUSE_MAX)
				if reachedPoi then
					pauseFor = pauseFor * RandRange(NPC_POI_PAUSE_MULT_MIN, NPC_POI_PAUSE_MULT_MAX)
				end
				npc.zoneRoutinePause = pauseFor
				env.targetSpeed = 0
				env.waitTimer = math.max(env.waitTimer, 0.24)
				env.desiredIn = math.min(env.desiredIn, 0.10)
				return
			end
		end

		if (not targetU) or (not targetV) or (tonumber(npc.zoneRoutineTargetTtl) or 0) <= 0 then
			local nu, nv, isPoi = PickActionTargetInCurrentZone(npc)
			if nu and nv then
				npc.zoneRoutineTargetU = nu
				npc.zoneRoutineTargetV = nv
				npc.zoneRoutineTargetTtl = RandRange(ZONE_TARGET_TTL_MIN, ZONE_TARGET_TTL_MAX)
				npc.zoneRoutineTargetIsPoi = isPoi and true or nil
				targetU, targetV = nu, nv
			else
				if Npc_RequestZoneExit(npc) then
					SetSoftCooldown(npc, 0.7, 1.3)
					ResetZoneRoutineState(npc, nil)
				else
					npc.zoneRoutineStep = "pause"
					npc.zoneRoutinePause = RandRange(0.50, 1.10)
					npc.zoneRoutineActionCount = actionCount + 1
					npc.zoneRoutineTargetIsPoi = nil
				end
				return
			end
		end

		local gx = targetU - (tonumber(npc.u) or targetU)
		local gy = targetV - (tonumber(npc.v) or targetV)
		local toward = AngleFromVector(gx, gy)
		if toward then
			env.desiredHeading = toward
			env.desiredIn = math.min(env.desiredIn, 0.18)
			env.waitTimer = 0
			env.targetSpeed = math.max(
				env.targetSpeed,
				RandRange(NPC_SPEED_MIN * 0.86, NPC_SPEED_MAX * 0.88) * dynFactor
			)
			env.targetSpeed = math.min(env.targetSpeed, NPC_SPEED_MAX * 0.92 * Clamp(dynFactor, 0.70, 1.35))
			env.directedMove = true
		end
	end

	routines.self_pause = function(npc, env)
		local edgeInfo = FindPlazaEdgeInfoAtPoint(npc.u, npc.v, NPC_SELF_PAUSE_EDGE_MAX_DIST * 1.8)
		local ignoreEdge = (npc and npc.selfPauseIgnoreEdge == true) or false
		if npc.behaviorTimer <= 0 then
			npc.selfPauseIgnoreEdge = nil
			Npc_ResetSocialState(npc, true)
			npc.selfPauseCooldown = RandRange(NPC_SELF_PAUSE_COOLDOWN_MIN, NPC_SELF_PAUSE_COOLDOWN_MAX)
			env.behaviorState = "walk"
		elseif (not ignoreEdge) and not edgeInfo then
			npc.selfPauseIgnoreEdge = nil
			Npc_ResetSocialState(npc, false)
			npc.selfPauseCooldown = RandRange(NPC_SELF_PAUSE_COOLDOWN_MIN * 0.6, NPC_SELF_PAUSE_COOLDOWN_MAX * 0.9)
			env.behaviorState = "walk"
		else
			local holdHeading = tonumber(npc.pauseLookHeading) or tonumber(env.desiredHeading)
			if (not holdHeading) and edgeInfo then
				local cx = tonumber(edgeInfo.centerU)
				local cy = tonumber(edgeInfo.centerV)
				if cx and cy then
					holdHeading = AngleFromVector(cx - (tonumber(npc.u) or cx), cy - (tonumber(npc.v) or cy))
				end
			end
			if not holdHeading then
				holdHeading = tonumber(npc.walkHeading) or 0
			end
			if math.random() < Clamp(env.dt * 0.30, 0, 0.16) then
				holdHeading = WrapAngle(holdHeading + RandRange(-0.18, 0.18))
				npc.pauseLookHeading = holdHeading
			end
			env.desiredHeading = holdHeading
			env.targetSpeed = 0
			env.waitTimer = math.max(env.waitTimer, 0.20)
			env.desiredIn = math.min(env.desiredIn, 0.08)
		end
	end

	routines.approach = function(npc, env)
		local partner = env.partner
		if not IsSocialPartnerValid(npc, partner) or (not AreNpcsInSameConversation(npc, partner)) then
			Npc_ResetSocialState(npc, true)
			env.behaviorState = "walk"
			env.partner = npc.behaviorPartner
			return
		end

		local dx = (tonumber(partner.u) or 0) - (tonumber(npc.u) or 0)
		local dy = (tonumber(partner.v) or 0) - (tonumber(npc.v) or 0)
		local dist2 = (dx * dx) + (dy * dy)
		local dist = (dist2 > NAV_EPS) and math.sqrt(dist2) or 0
		if npc.behaviorTimer <= 0 or dist > (NPC_SOCIAL_ENCOUNTER_RADIUS * 1.9) then
			Npc_BreakSocialPair(npc, partner)
			env.behaviorState = "walk"
			env.partner = npc.behaviorPartner
		elseif dist < NPC_SOCIAL_DISCUSS_MIN_DIST then
			-- Still too close: finish "approach" by spacing out before any talk state.
			local away = AngleFromVector(-dx, -dy)
			if away then
				env.desiredHeading = away
			end
			env.desiredIn = math.min(env.desiredIn, 0.16)
			env.waitTimer = 0
			env.targetSpeed = math.max(env.targetSpeed, RandRange(NPC_SPEED_MIN * 0.72, NPC_SPEED_MAX * 0.82))
			env.targetSpeed = math.min(env.targetSpeed, NPC_SPEED_MAX * 0.86)
		elseif dist <= NPC_SOCIAL_APPROACH_STOP_DIST and dist >= (NPC_SOCIAL_DISCUSS_MIN_DIST * 1.04) then
			if IsGlobalTalkLocked() then
				Npc_BreakSocialPair(npc, partner)
				env.behaviorState = "walk"
				env.partner = nil
				return
			end
				if math.random() < NPC_SOCIAL_DUO_WALK_CHANCE then
					if Npc_BeginDuoWalkPair(npc, partner, RandRange(NPC_SOCIAL_DUO_WALK_MIN, NPC_SOCIAL_DUO_WALK_MAX)) then
						env.behaviorState = "duo_walk"
						env.partner = npc.behaviorPartner
					else
						SoftAbortInteraction(npc, partner)
						env.behaviorState = "walk"
						env.partner = nil
					end
				else
					if
						Npc_BeginDiscussionPair(
							npc,
							partner,
							RandRange(NPC_SOCIAL_DISCUSS_MIN, NPC_SOCIAL_DISCUSS_MAX),
							"auto"
						)
					then
						env.behaviorState = "discussion"
						env.partner = npc.behaviorPartner
					else
						SoftAbortInteraction(npc, partner)
						env.behaviorState = "walk"
						env.partner = nil
					end
				end
		else
			local toward = AngleFromVector(dx, dy)
			if toward then
				env.desiredHeading = toward
			end
			env.desiredIn = math.min(env.desiredIn, 0.18)
			local dT = Clamp(
				(dist - NPC_SOCIAL_DISCUSS_MIN_DIST) / math.max(0.0001, NPC_SOCIAL_ENCOUNTER_RADIUS - NPC_SOCIAL_DISCUSS_MIN_DIST),
				0,
				1
			)
			local maxApproachSpeed = (NPC_SPEED_MIN * 0.48) + ((NPC_SPEED_MAX * 0.85) - (NPC_SPEED_MIN * 0.48)) * dT
			env.targetSpeed = math.max(env.targetSpeed, RandRange(NPC_SPEED_MIN * 0.42, maxApproachSpeed))
			env.targetSpeed = math.min(env.targetSpeed, maxApproachSpeed)
			if dist <= (NPC_SOCIAL_DISCUSS_MIN_DIST * 1.12) then
				env.targetSpeed = math.min(env.targetSpeed, NPC_SPEED_MIN * 0.32)
				env.waitTimer = math.max(env.waitTimer, 0.06)
			end
		end
	end

	routines.duo_walk = function(npc, env)
		local partner = env.partner
		if not IsSocialPartnerValid(npc, partner) or partner.behaviorPartner ~= npc then
			Npc_ResetSocialState(npc, true)
			env.behaviorState = "walk"
			env.partner = npc.behaviorPartner
			return
		end

		local dx = (tonumber(partner.u) or 0) - (tonumber(npc.u) or 0)
		local dy = (tonumber(partner.v) or 0) - (tonumber(npc.v) or 0)
		local dist2 = (dx * dx) + (dy * dy)
		local dist = (dist2 > NAV_EPS) and math.sqrt(dist2) or 0
		if npc.behaviorTimer <= 0 or dist > (NPC_SOCIAL_ENCOUNTER_RADIUS * 2.2) then
			Npc_BreakSocialPair(npc, partner)
			env.behaviorState = "walk"
			env.partner = npc.behaviorPartner
			return
		end

		local centerU = ((tonumber(npc.u) or 0.5) + (tonumber(partner.u) or 0.5)) * 0.5
		local centerV = ((tonumber(npc.v) or 0.5) + (tonumber(partner.v) or 0.5)) * 0.5
		local targetU = tonumber(npc.duoTargetU) or tonumber(partner.duoTargetU)
		local targetV = tonumber(npc.duoTargetV) or tonumber(partner.duoTargetV)
		if not targetU or not targetV then
			targetU, targetV = PickSocialWalkTarget(centerU, centerV, NPC_SOCIAL_DUO_TARGET_RADIUS, npc)
		else
			local cdx = targetU - centerU
			local cdy = targetV - centerV
			local cDist2 = (cdx * cdx) + (cdy * cdy)
			if cDist2 <= (NPC_SOCIAL_DUO_TARGET_REACH * NPC_SOCIAL_DUO_TARGET_REACH) then
				targetU, targetV = PickSocialWalkTarget(centerU, centerV, NPC_SOCIAL_DUO_TARGET_RADIUS, npc)
			end
		end
		if not targetU or not targetV then
			SoftAbortInteraction(npc, partner)
			env.behaviorState = "walk"
			env.partner = nil
			return
		end
		npc.duoTargetU, npc.duoTargetV = targetU, targetV
		partner.duoTargetU, partner.duoTargetV = targetU, targetV

		local towardTarget = AngleFromVector(targetU - (tonumber(npc.u) or 0), targetV - (tonumber(npc.v) or 0))
		if towardTarget then
			env.desiredHeading = towardTarget
		end
		env.desiredIn = math.min(env.desiredIn, 0.20)
		env.waitTimer = 0
		env.targetSpeed = math.max(env.targetSpeed, RandRange(NPC_SPEED_MIN * 0.85, NPC_SPEED_MAX * 0.82))
		env.targetSpeed = math.min(env.targetSpeed, NPC_SPEED_MAX * 0.90)

		if dist < NPC_SOCIAL_DUO_SEPARATION then
			local away = AngleFromVector(-dx, -dy)
			if away then
				env.desiredHeading = ApproachAngle(env.desiredHeading, away, PI * 0.60)
			end
			env.targetSpeed = math.min(env.targetSpeed, NPC_SPEED_MAX * 0.55)
		elseif dist > (NPC_SOCIAL_DUO_SEPARATION * 2.0) then
			local towardMate = AngleFromVector(dx, dy)
			if towardMate then
				env.desiredHeading = towardMate
			end
			env.targetSpeed = math.max(env.targetSpeed, NPC_SPEED_MIN * 0.95)
		end
	end

	routines.discussion = function(npc, env)
		local partner = env.partner
		if not IsSocialPartnerValid(npc, partner) or (not AreNpcsInSameConversation(npc, partner)) then
			Npc_ResetSocialState(npc, true)
			env.behaviorState = "walk"
			env.partner = npc.behaviorPartner
			return
		end

		local dx = (tonumber(partner.u) or 0) - (tonumber(npc.u) or 0)
		local dy = (tonumber(partner.v) or 0) - (tonumber(npc.v) or 0)
		local dist2 = (dx * dx) + (dy * dy)
		local dist = (dist2 > NAV_EPS) and math.sqrt(dist2) or 0
		if npc.behaviorTimer <= 0 then
			Npc_EndDiscussionPair(npc, partner)
			env.behaviorState = npc.behaviorState or "walk"
			env.partner = npc.behaviorPartner
		else
			if dist < NPC_SOCIAL_DISCUSS_MIN_DIST then
				local away = AngleFromVector(-dx, -dy)
				if away then
					env.desiredHeading = away
				end
				env.targetSpeed = math.max(NPC_SPEED_MIN * 0.60, math.min(env.targetSpeed, NPC_SPEED_MAX * 0.72))
				env.waitTimer = 0
				env.desiredIn = math.min(env.desiredIn, 0.16)
			elseif dist > (NPC_SOCIAL_DISCUSS_PREFERRED_DIST * 1.22) then
				local toward = AngleFromVector(dx, dy)
				if toward then
					env.desiredHeading = toward
				end
				env.targetSpeed = math.max(NPC_SPEED_MIN * 0.52, math.min(env.targetSpeed, NPC_SPEED_MAX * 0.64))
				env.waitTimer = 0
				env.desiredIn = math.min(env.desiredIn, 0.18)
			else
				local toward = AngleFromVector(dx, dy)
				if toward then
					env.desiredHeading = toward
				end
				env.targetSpeed = 0
				env.waitTimer = math.max(env.waitTimer, 0.14)
				env.desiredIn = math.min(env.desiredIn, 0.10)
			end
		end
	end

	routines.disengage = function(npc, env)
		if npc.behaviorTimer <= 0 then
			Npc_ResetSocialState(npc, false)
			env.behaviorState = "walk"
			env.partner = nil
			return
		end

		local sourceU = tonumber(npc.disengageFromU)
		local sourceV = tonumber(npc.disengageFromV)
		local sourcePartner = npc.disengagePartner
		if IsSocialPartnerValid(npc, sourcePartner) then
			sourceU = tonumber(sourcePartner.u) or sourceU
			sourceV = tonumber(sourcePartner.v) or sourceV
		end
		if not sourceU or not sourceV then
			Npc_ResetSocialState(npc, false)
			env.behaviorState = "walk"
			env.partner = nil
			return
		end

		local ux = (tonumber(npc.u) or sourceU) - sourceU
		local vy = (tonumber(npc.v) or sourceV) - sourceV
		local dist2 = (ux * ux) + (vy * vy)
		local minDist = math.max(NPC_SOCIAL_DISENGAGE_MIN_DIST, NPC_SOCIAL_DISCUSS_MIN_DIST * 1.08)
		if dist2 >= (minDist * minDist) then
			npc.disengageFromU = nil
			npc.disengageFromV = nil
			npc.disengagePartner = nil
			Npc_ResetSocialState(npc, false)
			env.behaviorState = "walk"
			env.partner = nil
			return
		end

		local away = AngleFromVector(ux, vy)
		if not away then
			away = WrapAngle((tonumber(npc.walkHeading) or env.desiredHeading) + PI + RandRange(-0.45, 0.45))
		end
		env.desiredHeading = away
		env.desiredIn = math.min(env.desiredIn, 0.16)
		env.waitTimer = 0
		env.targetSpeed = math.max(env.targetSpeed, RandRange(NPC_SPEED_MIN * 0.92, NPC_SPEED_MAX * 0.78))
		env.targetSpeed = math.min(env.targetSpeed, NPC_SPEED_MAX * 0.84)
	end

	routines.walk = function(_, _)
		-- Routine volontairement vide: le déplacement "normal" reste dans la boucle principale.
	end

	local runner = {}

	function runner.Update(npc, env)
		local timeMods = type(env and env.timeModifiers) == "table" and env.timeModifiers or nil
		local timeDynamism = Clamp(tonumber(timeMods and timeMods.dynamism) or 1.0, 0.20, 3.0)
		local timeInteraction = Clamp(tonumber(timeMods and timeMods.interaction) or 1.0, 0.20, 3.0)
		env.timeDynamismMultiplier = timeDynamism
		local behaviorState = env.behaviorState
		local partner = env.partner
		local manualOrderActive = type(npc and npc.manualOrder) == "table"
		if manualOrderActive and behaviorState ~= "walk" then
			Npc_ResetSocialState(npc, false)
			behaviorState = "walk"
			partner = nil
			env.behaviorState = behaviorState
			env.partner = partner
		end
		local zoneShiftActive = (tonumber(npc.zoneShiftTargetU) ~= nil) and (tonumber(npc.zoneShiftTargetV) ~= nil)
		local zoneRoutineKey = GetCurrentZoneRoutineKey(npc)
		if npc.zoneRoutineZoneKey ~= zoneRoutineKey then
			ResetZoneRoutineState(npc, zoneRoutineKey)
		end
		local inZonePause = (npc.zoneRoutineStep == "pause") and ((tonumber(npc.zoneRoutinePause) or 0) > 0.25)

		if
			behaviorState == "walk"
			and npc.selfPauseCooldown <= 0
			and env.waitTimer <= 0
			and env.nearCount <= 2
			and (not zoneShiftActive)
			and inZonePause
			and math.random() < Clamp(env.dt * NPC_SELF_PAUSE_CHANCE * 0.18 * timeInteraction, 0, 0.14)
		then
			local edgeInfo = FindPlazaEdgeInfoAtPoint(npc.u, npc.v, NPC_SELF_PAUSE_EDGE_MAX_DIST)
			if edgeInfo and edgeInfo.dist >= NPC_SELF_PAUSE_EDGE_MIN_DIST then
				local zoneKey = BuildSelfPauseZoneKey(edgeInfo)
				if zoneKey and zoneKey == npc.lastSelfPauseZoneKey then
					npc.selfPauseCooldown = RandRange(
						NPC_SELF_PAUSE_COOLDOWN_MIN * 0.6,
						NPC_SELF_PAUSE_COOLDOWN_MAX * 0.9
					)
					local sign = (math.random() < 0.5) and -1 or 1
					env.desiredHeading = WrapAngle((tonumber(npc.walkHeading) or env.desiredHeading) + (sign * RandRange(0.90, 1.80)))
					env.desiredIn = math.min(env.desiredIn, 0.25)
					env.waitTimer = 0
					env.targetSpeed = math.max(env.targetSpeed, RandRange(NPC_SPEED_MIN * 0.90, NPC_SPEED_MAX * 0.95))

					if
						NPC_AUTO_SOCIAL_ENABLED
						and (not IsGlobalTalkLocked())
						and npc.behaviorCooldown <= 0
						and math.random() < Clamp(math.max(0.06, GetAutoSocialTriggerChance(npc)) * timeInteraction, 0, 1)
					then
						local altCandidate = FindEncounterCandidate(npc)
						if altCandidate then
							if Npc_BeginApproachPair(npc, altCandidate, "auto") then
								behaviorState = "approach"
								partner = npc.behaviorPartner
							else
								SetSoftCooldown(npc, 1.0, 2.0)
							end
						end
					end
				else
					if Npc_BeginSelfPause(npc, edgeInfo, RandRange(NPC_SELF_PAUSE_MIN, NPC_SELF_PAUSE_MAX), zoneKey) then
						behaviorState = "self_pause"
						partner = nil
					else
						SetSoftCooldown(npc, 1.2, 2.4)
					end
				end
			end
		end

		if
			behaviorState == "walk"
			and NPC_AUTO_SOCIAL_ENABLED
			and (not IsGlobalTalkLocked())
			and npc.behaviorCooldown <= 0
			and env.waitTimer <= 0
			and env.nearCount <= math.max(1, math.floor(NPC_SOCIAL_ENCOUNTER_NEAR_MAX * 0.5))
			and npc.encounterRollIn <= 0
			and (not zoneShiftActive)
			then
				local candidate = FindEncounterCandidate(npc)
				npc.encounterRollIn = RandRange(
					NPC_SOCIAL_ENCOUNTER_CHECK_MIN * 1.8,
					NPC_SOCIAL_ENCOUNTER_CHECK_MAX * 3.2
				)
				local talkChance = Clamp(GetAutoSocialTriggerChance(npc) * timeInteraction, 0, 1)
				if not inZonePause then
					talkChance = talkChance * 0.75
				end
				if candidate and IsSameDirectionTalkBlocked(npc, candidate) then
					npc.behaviorCooldown = math.max(npc.behaviorCooldown, RandRange(1.6, 3.4))
				elseif candidate and math.random() < talkChance then
					if Npc_BeginApproachPair(npc, candidate, "auto") then
						behaviorState = "approach"
						partner = npc.behaviorPartner
					else
						SetSoftCooldown(npc, 1.0, 2.2)
					end
			elseif candidate then
				npc.behaviorCooldown = math.max(npc.behaviorCooldown, RandRange(0.9, 2.2))
			end
		end

		env.behaviorState = behaviorState
		env.partner = partner

		local routine = routines[behaviorState] or routines.walk
		routine(npc, env)

		behaviorState = env.behaviorState
		if behaviorState ~= "walk" then
			return
		end

		local targetU = tonumber(npc.zoneShiftTargetU)
		local targetV = tonumber(npc.zoneShiftTargetV)
		if targetU and targetV then
			if (not manualOrderActive) and type(Npc_ResolveZoneShiftPath) == "function" then
				Npc_ResolveZoneShiftPath(npc)
				targetU = tonumber(npc.zoneShiftTargetU)
				targetV = tonumber(npc.zoneShiftTargetV)
			end
			if targetU and targetV then
				npc.zoneRoutineTargetU = nil
				npc.zoneRoutineTargetV = nil
				npc.zoneRoutineTargetTtl = 0
				npc.zoneRoutineTargetIsPoi = nil
				npc.zoneRoutineStep = "move"

				local dx = targetU - (tonumber(npc.u) or targetU)
				local dy = targetV - (tonumber(npc.v) or targetV)
				local dist2 = (dx * dx) + (dy * dy)
				local reach2 = NPC_SOCIAL_POST_TALK_ZONE_REACH * NPC_SOCIAL_POST_TALK_ZONE_REACH
				if dist2 <= reach2 then
					local advanced = false
					if (not manualOrderActive) and type(Npc_AdvanceZoneShiftPath) == "function" then
						advanced = Npc_AdvanceZoneShiftPath(npc) == true
						if advanced then
							targetU = tonumber(npc.zoneShiftTargetU)
							targetV = tonumber(npc.zoneShiftTargetV)
							if targetU and targetV then
								dx = targetU - (tonumber(npc.u) or targetU)
								dy = targetV - (tonumber(npc.v) or targetV)
								dist2 = (dx * dx) + (dy * dy)
							else
								advanced = false
							end
						end
					end
					if not advanced then
						npc.zoneShiftTargetU = nil
						npc.zoneShiftTargetV = nil
						npc.zoneShiftGoalU = nil
						npc.zoneShiftGoalV = nil
						npc.zoneShiftPathWaypoints = nil
						npc.zoneShiftPathIndex = nil
						npc.zoneShiftPathTargetKey = nil
						npc.zoneShiftPathNavSignature = nil
						npc.zoneShiftTargetKind = nil
						npc.zoneShiftTimer = 0
						return
					end
				end
				local towardTarget = AngleFromVector(dx, dy)
				if towardTarget then
					env.desiredHeading = towardTarget
					env.desiredIn = 0
					env.waitTimer = 0
					if manualOrderActive then
						env.targetSpeed = math.max(env.targetSpeed, NPC_SPEED_MAX * 0.98 * timeDynamism)
					else
						env.targetSpeed = math.max(
							env.targetSpeed,
							RandRange(NPC_SPEED_MIN * 0.92, NPC_SPEED_MAX * 0.90) * timeDynamism
						)
						env.targetSpeed = math.min(
							env.targetSpeed,
							NPC_SPEED_MAX * 0.95 * Clamp(timeDynamism, 0.70, 1.35)
						)
					end
					env.directedMove = true
				end
				return
			end
		end

		if manualOrderActive then
			env.waitTimer = math.max(env.waitTimer, 0.35)
			env.desiredIn = math.min(env.desiredIn, 0.10)
			env.targetSpeed = 0
			env.directedMove = true
			return
		end

		UpdateZonePatrolRoutine(npc, env)
	end

	return runner
end
