local ADDON, ns = ...

ns.QuartierMiniatureNpcEngine = ns.QuartierMiniatureNpcEngine or {}
ns.QuartierMiniatureNpcEngine.Modules = ns.QuartierMiniatureNpcEngine.Modules or {}
local Modules = ns.QuartierMiniatureNpcEngine.Modules

function Modules.InstallOfflineSim(ctx, moduleEnv)
	if type(ctx) ~= "table" or type(moduleEnv) ~= "table" then
		return nil
	end
	setfenv(1, moduleEnv)

	local function ClampNeed(v)
		return Clamp(tonumber(v) or 0, 0, 100)
	end

	local function NormalizeDays(dayCount)
		local raw = math.floor(tonumber(dayCount) or 0)
		if raw < 0 then
			return 0
		end
		return raw
	end

	local function GetLowestNeedKey(needs)
		local values = {
			social = ClampNeed(needs and needs.social),
			fatigue = ClampNeed(needs and needs.fatigue),
			faim = ClampNeed(needs and needs.faim),
			distraction = ClampNeed(needs and needs.distraction),
		}
		local bestKey, bestValue = "faim", values.faim
		if values.fatigue < bestValue then
			bestKey = "fatigue"
			bestValue = values.fatigue
		end
		if values.distraction < bestValue then
			bestKey = "distraction"
			bestValue = values.distraction
		end
		if values.social < bestValue then
			bestKey = "social"
			bestValue = values.social
		end
		return bestKey, values
	end

	local function ResetNpcTransientState(npc)
		if not npc then
			return
		end
		Npc_BreakCurrentSocialLink(npc)
		Npc_ClearManualOrder(npc, true)
		ClearNpcManualOrderQueue(npc)
		Npc_ClearZoneShiftTarget(npc)
		npc.waitTimer = 0
		npc.switchCooldown = 0
		npc.behaviorTimer = 0
		npc.behaviorCooldown = 0
		npc.walkLieuExitRetryAt = 0
		npc.selfPauseCooldown = RandRange(NPC_SELF_PAUSE_COOLDOWN_MIN * 0.25, NPC_SELF_PAUSE_COOLDOWN_MAX * 0.45)
		npc.zoneRoutineStep = "move"
		npc.zoneRoutinePause = 0
		npc.zoneRoutineTargetU = nil
		npc.zoneRoutineTargetV = nil
		npc.zoneRoutineTargetTtl = 0
		npc.zoneRoutineTargetIsPoi = nil
		npc.essentialPausePurpose = nil
		npc.essentialPauseTarget = nil
		npc.essentialPauseBoost = nil
		npc.essentialPauseLockUntil = nil
		npc.essentialPauseSource = nil
		npc.essentialPauseRollPurpose = nil
		npc.essentialPauseRollPercent = nil
		npc.lastTalkPartner = nil
		npc.lastTalkCooldown = 0
		npc.autoOrderRollIn = GetNextNpcAutoIntentDelay()
		npc.poiVisitRollIn = RandRange(NPC_POI_ROLL_MIN, NPC_POI_ROLL_MAX)
		npc.poiVisitCooldown = 0
		npc.severeBlockIterations = 0
		npc.severeBlockEscalation = 0
		npc.lastSevereBlockAt = 0
	end

	local function ApplyApproxNeeds(npc, days)
		if not (npc and NPC_NEEDS_ENABLED) then
			return "move_place"
		end
		npc.needs = BuildNpcNeeds(npc.needs)
		local needs = npc.needs
		local drainDays = Clamp(days, 1, 120)
		needs.social = ClampNeed((needs.social or 0) - (2.2 * drainDays))
		needs.fatigue = ClampNeed((needs.fatigue or 0) - (4.8 * drainDays))
		needs.faim = ClampNeed((needs.faim or 0) - (6.2 * drainDays))
		needs.distraction = ClampNeed((needs.distraction or 0) - (4.2 * drainDays))
		local lowestKey = GetLowestNeedKey(needs)
		local purpose = "move_place"
		if lowestKey == "faim" then
			purpose = "meal"
			needs.faim = ClampNeed(needs.faim + 72)
			needs.fatigue = ClampNeed(needs.fatigue + 9)
		elseif lowestKey == "fatigue" then
			purpose = "rest"
			needs.fatigue = ClampNeed(needs.fatigue + 76)
			needs.social = ClampNeed(needs.social + 8)
		elseif lowestKey == "distraction" then
			purpose = "distraction"
			needs.distraction = ClampNeed(needs.distraction + 74)
			needs.social = ClampNeed(needs.social + 16)
		elseif lowestKey == "social" then
			purpose = "social"
			needs.social = ClampNeed(needs.social + 64)
			needs.distraction = ClampNeed(needs.distraction + 22)
		end
		npc.needsSpeedFactor = Clamp(0.35 + ((needs.fatigue / 100) * 0.65), 0.25, 1.0)
		return purpose
	end

	local function PickApproxTarget(npc, purpose)
		local wantedType = ""
		if purpose == "meal" then
			wantedType = "auberge"
		elseif purpose == "rest" then
			wantedType = "chaumiere"
		elseif purpose == "distraction" or purpose == "social" then
			wantedType = "taverne"
		end
		if wantedType ~= "" then
			local best = Npc_FindLieuTargetPoint(npc, wantedType, {
				allowFullFallback = false,
			})
			if best and IsPointWalkable(best.u, best.v) then
				return Clamp(tonumber(best.u) or 0.5, 0, 1), Clamp(tonumber(best.v) or 0.5, 0, 1)
			end
		end
		if navCache.hasRoutes or navCache.hasPlazas then
			local su, sv = PickNpcSpawnPoint()
			if su and sv and IsPointWalkable(su, sv) then
				return Clamp(tonumber(su) or 0.5, 0, 1), Clamp(tonumber(sv) or 0.5, 0, 1)
			end
		end
		local cu = Clamp(tonumber(npc and npc.u) or 0.5, 0, 1)
		local cv = Clamp(tonumber(npc and npc.v) or 0.5, 0, 1)
		if IsPointWalkable(cu, cv) then
			return cu, cv
		end
		return nil, nil
	end

	local function PickLongFallbackTarget(npc)
		local lieux = {
			"auberge",
			"taverne",
			"chaumiere",
		}
		for _ = 1, 4 do
			local idx = math.random(1, #lieux)
			local wanted = lieux[idx]
				local best = Npc_FindLieuTargetPoint(npc, wanted, {
					allowFullFallback = false,
				})
			if best and IsPointWalkable(best.u, best.v) then
				return Clamp(tonumber(best.u) or 0.5, 0, 1), Clamp(tonumber(best.v) or 0.5, 0, 1)
			end
		end
		if navCache.hasRoutes or navCache.hasPlazas then
			local su, sv = PickNpcSpawnPoint()
			if su and sv and IsPointWalkable(su, sv) then
				return Clamp(tonumber(su) or 0.5, 0, 1), Clamp(tonumber(sv) or 0.5, 0, 1)
			end
		end
		local cu = Clamp(tonumber(npc and npc.u) or 0.5, 0, 1)
		local cv = Clamp(tonumber(npc and npc.v) or 0.5, 0, 1)
		if IsPointWalkable(cu, cv) then
			return cu, cv
		end
		return nil, nil
	end

	local function ApplyApproxNeedsSeconds(npc, seconds, mode)
		if not (npc and NPC_NEEDS_ENABLED) then
			return "move_place"
		end
		npc.needs = BuildNpcNeeds(npc.needs)
		local needs = npc.needs
		local sec = Clamp(tonumber(seconds) or 0, 60, 12 * 60 * 60)
		local isLong = tostring(mode or "") == "long"

		local drainMult = isLong and 0.55 or 0.75
		needs.social = ClampNeed((needs.social or 0) - (NPC_NEEDS_SOCIAL_RISE * sec * drainMult))
		needs.fatigue = ClampNeed((needs.fatigue or 0) - (NPC_NEEDS_FATIGUE_RISE_MOVE * sec * drainMult))
		needs.faim = ClampNeed((needs.faim or 0) - (NPC_NEEDS_FAIM_RISE * sec * drainMult))
		needs.distraction = ClampNeed((needs.distraction or 0) - (NPC_NEEDS_DISTRACTION_RISE * sec * drainMult))

		local lowestKey = GetLowestNeedKey(needs)
		local purpose = "move_place"
		if lowestKey == "faim" then
			purpose = "meal"
			needs.faim = ClampNeed(needs.faim + (NPC_NEEDS_FAIM_RECOVER_PAUSE * sec * 0.55))
			needs.social = ClampNeed(needs.social + (NPC_NEEDS_SOCIAL_RECOVER_LIEU_GROUP * sec * 0.25))
		elseif lowestKey == "fatigue" then
			purpose = "rest"
			needs.fatigue = ClampNeed(needs.fatigue + (NPC_NEEDS_FATIGUE_RECOVER_REST * sec * 0.70))
		elseif lowestKey == "distraction" then
			purpose = "distraction"
			needs.distraction = ClampNeed(needs.distraction + (NPC_NEEDS_DISTRACTION_RECOVER_PAUSE * sec * 0.65))
			needs.social = ClampNeed(needs.social + (NPC_NEEDS_SOCIAL_RECOVER_LIEU_GROUP * sec * 0.20))
		elseif lowestKey == "social" then
			purpose = "social"
			needs.social = ClampNeed(needs.social + (NPC_NEEDS_SOCIAL_RECOVER_TALK * sec * 0.45))
			needs.distraction = ClampNeed(needs.distraction + (NPC_NEEDS_DISTRACTION_RECOVER_PAUSE * sec * 0.20))
		end

		if isLong then
			-- Keep long absences stable: avoid extreme depletion while preserving variation.
			needs.social = ClampNeed(needs.social + RandRange(4, 18))
			needs.fatigue = ClampNeed(needs.fatigue + RandRange(8, 24))
			needs.faim = ClampNeed(needs.faim + RandRange(6, 20))
			needs.distraction = ClampNeed(needs.distraction + RandRange(5, 18))
		end
		npc.needsSpeedFactor = Clamp(0.35 + ((needs.fatigue / 100) * 0.65), 0.25, 1.0)
		return purpose
	end

	local function RecenterRegisseuse(npc)
		if not npc then
			return
		end
		local centerU = Clamp(tonumber(npc.regieCenterU) or tonumber(npc.u) or 0.5, 0, 1)
		local centerV = Clamp(tonumber(npc.regieCenterV) or tonumber(npc.v) or 0.5, 0, 1)
		npc.regieCenterU = centerU
		npc.regieCenterV = centerV
		npc.regieRadius = Clamp(tonumber(npc.regieRadius) or 0.040, 0.015, 0.090)
		npc.regieTargetU = nil
		npc.regieTargetV = nil
		npc.regieWait = 0
		local placed = false
		for _ = 1, 24 do
			local angle = RandRange(0, TWO_PI)
			local r = npc.regieRadius * math.sqrt(math.random())
			local u = Clamp(centerU + (math.cos(angle) * r), 0, 1)
			local v = Clamp(centerV + (math.sin(angle) * r), 0, 1)
			if IsPointWalkable(u, v) then
				npc.u = u
				npc.v = v
				placed = true
				break
			end
		end
		if not placed then
			if IsPointWalkable(centerU, centerV) then
				npc.u = centerU
				npc.v = centerV
			else
				Npc_EnsureWalkablePosition(npc)
			end
		end
	end

	function StepSimulation(elapsed, opts)
		local dt = tonumber(elapsed) or 0
		if dt <= 0 then
			return false
		end
		AdvanceVirtualClock(dt)
		Npc_UpdateAndRender(dt, opts)
		return true
	end

	function ApplyApproximateOfflineSeconds(elapsedSec, opts)
		local seconds = math.max(0, tonumber(elapsedSec) or 0)
		if seconds <= 0 then
			return false, 0
		end
		local mode = tostring((type(opts) == "table" and opts.mode) or "average")
		AdvanceVirtualClock(seconds)
		RefreshNavigationCache(false)
		for i = 1, #npcPool do
			local npc = npcPool[i]
			if type(npc) == "table" then
				ResetNpcTransientState(npc)
				if npc.isRegisseuse == true then
					RecenterRegisseuse(npc)
					npc.needs = {
						social = 100,
						fatigue = 100,
						faim = 100,
						distraction = 100,
					}
					npc.needsSpeedFactor = 1
				else
					local purpose = ApplyApproxNeedsSeconds(npc, seconds, mode)
					local u, v = nil, nil
					if mode == "long" then
						u, v = PickLongFallbackTarget(npc)
					else
						u, v = PickApproxTarget(npc, purpose)
					end
					if u and v then
						npc.u = u
						npc.v = v
					else
						Npc_EnsureWalkablePosition(npc)
					end
					npc.behaviorState = "walk"
					npc.behaviorPartner = nil
					npc.conversationGroupId = nil
					npc.pausePurpose = nil
					-- Placeholder for future integration: replay deferred user requests after long absence.
					if mode == "long" then
						npc.pendingOfflineUserResolution = true
					end
				end
				npc.u = Clamp(tonumber(npc.u) or 0.5, 0, 1)
				npc.v = Clamp(tonumber(npc.v) or 0.5, 0, 1)
				Npc_EnsureWalkablePosition(npc)
				Npc_UpdateZoneTracking(npc)
				NpcSpatialReindex(npc)
			end
		end
		npcSpatial.dirty = true
		if type(opts) == "table" and opts.persist == true then
			SaveNpcPersistence()
		end
		return true, seconds
	end

	function ApplyApproximateOfflineDays(dayCount, opts)
		local days = NormalizeDays(dayCount)
		if days <= 0 then
			return false, 0
		end
		AdvanceVirtualClock(days * 24 * 60 * 60)
		RefreshNavigationCache(false)
		for i = 1, #npcPool do
			local npc = npcPool[i]
			if type(npc) == "table" then
				ResetNpcTransientState(npc)
				if npc.isRegisseuse == true then
					RecenterRegisseuse(npc)
					npc.needs = {
						social = 100,
						fatigue = 100,
						faim = 100,
						distraction = 100,
					}
					npc.needsSpeedFactor = 1
				else
					local purpose = ApplyApproxNeeds(npc, days)
					local u, v = PickApproxTarget(npc, purpose)
					if u and v then
						npc.u = u
						npc.v = v
					else
						Npc_EnsureWalkablePosition(npc)
					end
					npc.behaviorState = "walk"
					npc.behaviorPartner = nil
					npc.conversationGroupId = nil
					npc.pausePurpose = nil
				end
				npc.u = Clamp(tonumber(npc.u) or 0.5, 0, 1)
				npc.v = Clamp(tonumber(npc.v) or 0.5, 0, 1)
				Npc_EnsureWalkablePosition(npc)
				Npc_UpdateZoneTracking(npc)
				NpcSpatialReindex(npc)
			end
		end
		npcSpatial.dirty = true
		if type(opts) == "table" and opts.persist == true then
			SaveNpcPersistence()
		end
		return true, days
	end
end

return Modules
