local ADDON, ns = ...

ns.QuartierMiniatureNpcEngine = ns.QuartierMiniatureNpcEngine or {}
ns.QuartierMiniatureNpcEngine.Modules = ns.QuartierMiniatureNpcEngine.Modules or {}
local Modules = ns.QuartierMiniatureNpcEngine.Modules

function Modules.InstallPersistence(ctx, moduleEnv)
	if type(ctx) ~= "table" or type(moduleEnv) ~= "table" then
		return nil
	end
	setfenv(1, moduleEnv)

function EnforceNpcSeparation()
	if not NPC_COLLISIONS_ENABLED then
		return
	end
	local count = #npcPool
	if count < 2 then
		return
	end

	local vw = viewport:GetWidth() or 0
	local vh = viewport:GetHeight() or 0
	local uSpan = state.uSpan or 1
	local vSpan = state.vSpan or 1
	if vw <= 1 or vh <= 1 or uSpan <= NAV_EPS or vSpan <= NAV_EPS then
		return
	end

	local minPx = NPC_MIN_SEPARATION_PX
	local minPx2 = minPx * minPx
	local uPerPx = uSpan / vw
	local vPerPx = vSpan / vh
	local needsWalkable = navCache.hasRoutes or navCache.hasPlazas

	local maxPasses = ((state and state.dragging) and 2) or 4
	for _ = 1, maxPasses do
		local moved = false
		for i = 1, count - 1 do
			local a = npcPool[i]
			local au = tonumber(a and a.u)
			local av = tonumber(a and a.v)
			if au and av then
				for j = i + 1, count do
					local b = npcPool[j]
					local bu = tonumber(b and b.u)
					local bv = tonumber(b and b.v)
					if bu and bv then
						local dxPx = (au - bu) * vw / uSpan
						local dyPx = (av - bv) * vh / vSpan
						local d2 = (dxPx * dxPx) + (dyPx * dyPx)
						if d2 < minPx2 then
							local pairIsSocial = IsRepulsionIgnoredPair(a, b)
							local _, _, _, routeNx, routeNy, routeOppositeDir, routeSameDir =
								GetSharedRoutePairInfo(a, b)
							local pairMinPx = minPx
							if pairIsSocial then
								local isDiscussionPair = (a.behaviorState == "discussion")
									or (b.behaviorState == "discussion")
								if isDiscussionPair then
									pairMinPx = math.max(minPx * 0.94, math.max(NPC_RING_W, NPC_RING_H) * 0.96)
								else
									pairMinPx = math.max(
										18,
										math.min(minPx * 0.62, math.max(NPC_RING_W, NPC_RING_H) * 0.72)
									)
								end
							elseif routeOppositeDir then
								pairMinPx = math.max(14, minPx * NPC_ROUTE_OPPOSITE_PASS_FACTOR)
							elseif routeSameDir then
								pairMinPx = math.max(12, minPx * 0.76)
							end
							local pairMinPx2 = pairMinPx * pairMinPx
							if d2 < pairMinPx2 then
								local dist = (d2 > NAV_EPS) and math.sqrt(d2) or 0
								local nxPx, nyPx
								local usedRouteLateral = false
								if (routeOppositeDir or routeSameDir) and routeNx and routeNy then
									local lateralSign = GetRoutePassSideSign(a, b)
									local routeNxPx = (routeNx * vw) / math.max(uSpan, NAV_EPS)
									local routeNyPx = (routeNy * vh) / math.max(vSpan, NAV_EPS)
									local routeNorm = math.sqrt((routeNxPx * routeNxPx) + (routeNyPx * routeNyPx))
									if routeNorm > NAV_EPS then
										nxPx = (routeNxPx / routeNorm) * lateralSign
										nyPx = (routeNyPx / routeNorm) * lateralSign
										dist = math.abs((dxPx * nxPx) + (dyPx * nyPx))
										usedRouteLateral = true
									end
								end
								if (not usedRouteLateral) and dist > NAV_EPS then
									nxPx = dxPx / dist
									nyPx = dyPx / dist
								elseif not usedRouteLateral then
									local aRand = RandRange(0, TWO_PI)
									nxPx = math.cos(aRand)
									nyPx = math.sin(aRand)
								end

								local pushPx = (pairMinPx - dist) * 0.5
								local pushU = nxPx * pushPx * uPerPx
								local pushV = nyPx * pushPx * vPerPx
								local candAu = Clamp(au + pushU, 0, 1)
								local candAv = Clamp(av + pushV, 0, 1)
								local candBu = Clamp(bu - pushU, 0, 1)
								local candBv = Clamp(bv - pushV, 0, 1)

								if needsWalkable then
									if IsPointWalkable(candAu, candAv) then
										a.u, a.v = candAu, candAv
									end
									if IsPointWalkable(candBu, candBv) then
										b.u, b.v = candBu, candBv
									end
									Npc_EnsureWalkablePosition(a)
									Npc_EnsureWalkablePosition(b)
								else
									a.u, a.v = candAu, candAv
									b.u, b.v = candBu, candBv
								end

								local ndxPx = ((tonumber(a.u) or au) - (tonumber(b.u) or bu)) * vw / uSpan
								local ndyPx = ((tonumber(a.v) or av) - (tonumber(b.v) or bv)) * vh / vSpan
								local nd2 = (ndxPx * ndxPx) + (ndyPx * ndyPx)
								if nd2 < (pairMinPx2 * 0.55) then
									local emergencyPushPx = pairMinPx * NPC_EMERGENCY_SEPARATION_MULT
									local forceAU =
										Clamp((tonumber(a.u) or au) + (nxPx * emergencyPushPx * uPerPx), 0, 1)
									local forceAV =
										Clamp((tonumber(a.v) or av) + (nyPx * emergencyPushPx * vPerPx), 0, 1)
									local forceBU =
										Clamp((tonumber(b.u) or bu) - (nxPx * emergencyPushPx * uPerPx), 0, 1)
									local forceBV =
										Clamp((tonumber(b.v) or bv) - (nyPx * emergencyPushPx * vPerPx), 0, 1)
									local movedA, movedB = false, false

									if needsWalkable then
										if IsPointWalkable(forceAU, forceAV) then
											a.u, a.v = forceAU, forceAV
											movedA = true
										end
										if IsPointWalkable(forceBU, forceBV) then
											b.u, b.v = forceBU, forceBV
											movedB = true
										end
									else
										a.u, a.v = forceAU, forceAV
										b.u, b.v = forceBU, forceBV
										movedA, movedB = true, true
									end

									if not movedA then
										if not TryRelocateNpcNearby(a, au, av, nxPx, nyPx) then
											a.u, a.v = au, av
										end
									end
									if not movedB then
										if not TryRelocateNpcNearby(b, bu, bv, -nxPx, -nyPx) then
											b.u, b.v = bu, bv
										end
									end
									Npc_ResetSocialState(a, true)
									Npc_ResetSocialState(b, true)
								end

								au = tonumber(a.u) or au
								av = tonumber(a.v) or av
								bu = tonumber(b.u) or bu
								bv = tonumber(b.v) or bv
								moved = true
							end
						end
					end
				end
			end
		end
		if not moved then
			break
		end
	end
end

Npc_RenderAll = function()
	SyncBaseSize()
	local now = NowSec()
	local draggingMap = state and state.dragging == true
	local doHeavyVisual = not draggingMap
	if (not doHeavyVisual) and now > 0 then
		local lastHeavy = tonumber(state._npcLastHeavyVisualAt) or 0
		if (now - lastHeavy) >= 0.15 then
			doHeavyVisual = true
			state._npcLastHeavyVisualAt = now
		end
	end
	local vw = viewport:GetWidth() or 0
	local vh = viewport:GetHeight() or 0
	if vw <= 0 or vh <= 0 then
		return
	end
	local u1 = state.u1 or 0
	local v1 = state.v1 or 0
	local uSpan = state.uSpan or 1
	local vSpan = state.vSpan or 1
	local selectedId = tostring(state and state._selectedNpcId or "")
	if uSpan <= 0 or vSpan <= 0 then
		return
	end

	for i = 1, #npcPool do
		local npc = npcPool[i]
		local renderNow = now
		if renderNow <= 0 then
			renderNow = (tonumber(npc._presenceLastRenderAt) or 0) + 0.016
		end
		local visualDt = Clamp(renderNow - (tonumber(npc._presenceLastRenderAt) or renderNow), 0.004, 0.20)
		npc._presenceLastRenderAt = renderNow
		local rawInLieu = (GetLieuAtPoint(npc.u, npc.v) ~= nil)
		local stableInLieu = npc._presenceInsideStable
		if stableInLieu == nil then
			stableInLieu = rawInLieu
			npc._presenceInsideStable = stableInLieu
			npc._presencePendingInside = nil
			npc._presencePendingTimer = 0
		elseif rawInLieu ~= stableInLieu then
			if npc._presencePendingInside ~= rawInLieu then
				npc._presencePendingInside = rawInLieu
				npc._presencePendingTimer = 0
			else
				npc._presencePendingTimer =
					Clamp((tonumber(npc._presencePendingTimer) or 0) + visualDt, 0, NPC_LIEU_PRESENCE_SWITCH_DEBOUNCE * 4)
				if npc._presencePendingTimer >= NPC_LIEU_PRESENCE_SWITCH_DEBOUNCE then
					stableInLieu = rawInLieu
					npc._presenceInsideStable = stableInLieu
					npc._presencePendingInside = nil
					npc._presencePendingTimer = 0
				end
			end
		else
			npc._presencePendingInside = nil
			npc._presencePendingTimer = 0
		end
		local presenceVisible = UpdateNpcLieuPresenceVisual(npc, stableInLieu == true, visualDt)
		local nx = (npc.u - u1) / uSpan
		local ny = (npc.v - v1) / vSpan
		if (not presenceVisible) or nx < -0.15 or nx > 1.15 or ny < -0.15 or ny > 1.15 then
			npc.frame:Hide()
		else
			local x = nx * vw
			local y = (1 - ny) * vh
			local baseLevel = npcLayer:GetFrameLevel() + 1
			local order = tonumber(npc.renderHeightOrder) or i
			local frameLevel = baseLevel + (order * 8)
			if selectedId ~= "" and tostring(npc.persistentId or "") == selectedId then
				frameLevel = baseLevel + ((#npcPool + 6) * 8)
			end
			if type(npc.portraitUnit) == "string" and npc.portraitUnit ~= "" then
				ApplyNpcPortraitSource(npc)
			end
			SetNpcVisualHeight(npc.frame, frameLevel)
			UpdateNpcRingColor(npc)
			npc.frame:ClearAllPoints()
			npc.frame:SetPoint("CENTER", npcLayer, "BOTTOMLEFT", x, y)
			npc.frame:Show()
		end
	end
end

Npc_UpdateAndRender = function(elapsed, opts)
	SyncBaseSize()
	local dt = tonumber(elapsed) or 0
	local runtimeOpts = type(opts) == "table" and opts or nil
	local shouldRender = not (runtimeOpts and runtimeOpts.render == false)
	local shouldPersist = not (runtimeOpts and runtimeOpts.persist == false)
	navRefreshElapsed = navRefreshElapsed + dt
	npcGlobalTalkLock = math.max(0, (tonumber(npcGlobalTalkLock) or 0) - dt)
	local lowCpuStride = NPC_LOW_CPU_MODE and math.max(1, NPC_LOW_CPU_NPC_STRIDE) or 1
	if lowCpuStride > 1 then
		npcLowCpuPhase = (npcLowCpuPhase % lowCpuStride) + 1
	else
		npcLowCpuPhase = 1
	end

	local activeMapId = tostring(GetActiveMapId() or "default")
	if activeMapId ~= npcPersistenceMapId then
		RefreshNavigationCache(true)
		ReloadNpcPoolFromPersistence()
		npcPersistenceTimer = 0
		npcSeparationTimer = 0
	else
		RefreshNavigationCache(false)
	end

	if NPC_COLLISIONS_ENABLED and navCache.hasRoutes then
		for i = 1, #npcPool do
			UpdateNpcRouteHint(npcPool[i], dt, false)
		end
	end

	if npcSpatial.dirty or not npcSpatial.enabled then
		NpcSpatialBuild()
	end
	local zoneCounts = {}
	for i = 1, #npcPool do
		local npc = npcPool[i]
		local isRegisseuse = npc and npc.isRegisseuse == true
		local manualOrderActive = type(npc.manualOrder) == "table"
		local queuedOrderActive = GetNpcManualOrderQueueSize(npc) > 0
		local forcedActive = manualOrderActive
			or queuedOrderActive
			or (tonumber(npc.zoneShiftTargetU) ~= nil and tonumber(npc.zoneShiftTargetV) ~= nil)
		-- Keep needs progression real-time even when movement simulation is skipped in low-CPU stride.
		if not isRegisseuse then
			UpdateNpcNeeds(npc, dt)
			UpdateNpcAutoOrderTimer(npc, dt)
		end
		if (not isRegisseuse) and NPC_LEGACY_AUTO_POI_ROLL_ENABLED and navCache.hasPois and type(npc.manualOrder) ~= "table" then
			local stateName = tostring(Npc_GetSocialState(npc) or "walk")
			local inZonePause = (tostring(npc.zoneRoutineStep or "") == "pause")
				and ((tonumber(npc.zoneRoutinePause) or 0) > 0.10)
			if stateName == "walk" and not inZonePause then
				local poiRoll = (tonumber(npc.poiVisitRollIn) or RandRange(NPC_POI_ROLL_MIN, NPC_POI_ROLL_MAX))
					- (tonumber(dt) or 0)
				if poiRoll <= 0 then
					npc.poiVisitRollIn = RandRange(NPC_POI_ROLL_MIN, NPC_POI_ROLL_MAX)
					local canQueuePoi = (GetNpcManualOrderQueueSize(npc) == 0)
						and ((tonumber(npc.waitTimer) or 0) <= 0)
						and ((tonumber(npc.poiVisitCooldown) or 0) <= 0)
						and (math.random() <= NPC_POI_PICK_CHANCE)
					if canQueuePoi then
						local nu = tonumber(npc.u) or 0.5
						local nv = tonumber(npc.v) or 0.5
						local maxD = Clamp(NPC_POI_PICK_RADIUS, 0.005, 1.0)
						local maxD2 = maxD * maxD
						local routeKey = tostring(npc.zoneKey or "")
						local routeIndex = tonumber(string.match(routeKey, "^route:(%d+)$"))
						local poiCandidates = {}
						local poiCount = #navCache.pois
						if poiCount > 0 then
							local scanMax = math.min(poiCount, NPC_POI_SCAN_MAX_PER_ROLL)
							local idx = math.floor(tonumber(npcSpatial.poiScanCursor) or 1)
							if idx < 1 or idx > poiCount then
								idx = 1
							end
							for _ = 1, scanMax do
								local poi = navCache.pois[idx]
								local pu = tonumber(poi and poi.u)
								local pv = tonumber(poi and poi.v)
								if pu and pv then
									local dx = pu - nu
									local dy = pv - nv
									local d2 = (dx * dx) + (dy * dy)
									if d2 <= maxD2 then
										local poiId = tostring(poi and poi.id or ("poi_" .. tostring(idx)))
										local score = d2
										if routeIndex and tonumber(poi and poi.routeIndex) == routeIndex then
											score = score * 0.55
										end
										score = score * GetNpcPoiRepeatPenalty(npc, poiId) * RandRange(0.92, 1.20)
										poiCandidates[#poiCandidates + 1] = {
											u = pu,
											v = pv,
											d2 = d2,
											score = score,
											poiId = poiId,
										}
									end
								end
								idx = idx + 1
								if idx > poiCount then
									idx = 1
								end
							end
							npcSpatial.poiScanCursor = idx
						end
						local bestPoi = PickDiversePoiCandidate(poiCandidates)
						if bestPoi then
							local waitSeconds = RandRange(NPC_POI_CONTEMPLATE_MIN, NPC_POI_CONTEMPLATE_MAX)
							local queued = EnqueueNpcManualOrder(npc, {
								kind = "lieu_pause",
								lieuType = "",
								purpose = "observe_nature",
								targetU = bestPoi.u,
								targetV = bestPoi.v,
								poiId = bestPoi.poiId,
								waitSeconds = waitSeconds,
								expiresAt = (NowSec()) + 48,
								source = "auto_poi",
							})
							if queued then
								RegisterNpcRecentPoi(npc, bestPoi.poiId)
								npc.poiVisitCooldown = RandRange(NPC_POI_COOLDOWN_MIN, NPC_POI_COOLDOWN_MAX)
							else
								npc.poiVisitRollIn = npc.poiVisitRollIn + RandRange(0.6, 1.6)
							end
						else
							npc.poiVisitRollIn = npc.poiVisitRollIn + RandRange(0.6, 1.6)
						end
					end
				else
					npc.poiVisitRollIn = poiRoll
				end
			end
		end
		local shouldSimulate = true
		if lowCpuStride > 1 and not forcedActive then
			local slot = ((i - 1) % lowCpuStride) + 1
			if slot ~= npcLowCpuPhase then
				shouldSimulate = false
			end
		end

		if shouldSimulate then
			npc.switchCooldown = math.max(0, (tonumber(npc.switchCooldown) or 0) - dt)
			if isRegisseuse then
				Npc_ProcessManualOrder(npc)
				local currentState = tostring(Npc_GetSocialState(npc) or "walk")
				local inSocialState = (currentState == "approach")
					or (currentState == "discussion")
					or (currentState == "duo_walk")
					or (currentState == "disengage")
					or (currentState == "self_pause")
				if type(npc.manualOrder) == "table" then
					local orderKind = tostring(npc.manualOrder.kind or "")
					-- Keep anchor talk orders stable: no autonomous roam/wander while discussion order resolves.
					if orderKind == "talk" then
						Npc_ClearZoneShiftTarget(npc)
					elseif navCache.hasRoutes or navCache.hasPlazas then
						if not Npc_UpdateWalkableWander(npc, dt) then
							Npc_UpdateRegisseuseRoam(npc, dt)
						end
					else
						Npc_UpdateRegisseuseRoam(npc, dt)
					end
				elseif inSocialState then
					-- After manual talk starts, keep social state alive instead of forcing roam immediately.
					if navCache.hasRoutes or navCache.hasPlazas then
						if not Npc_UpdateWalkableWander(npc, dt) then
							Npc_UpdateRegisseuseRoam(npc, dt)
						end
					else
						Npc_UpdateRegisseuseRoam(npc, dt)
					end
				else
					npc.manualOrderQueue = {}
					Npc_ClearZoneShiftTarget(npc)
					Npc_UpdateRegisseuseRoam(npc, dt)
				end
			else
				local canStartQueuedOrder = (type(npc.manualOrder) ~= "table")
					and (tostring(Npc_GetSocialState(npc) or "walk") == "walk")
					and not (
						tostring(npc.zoneRoutineStep or "") == "pause"
						and ((tonumber(npc.zoneRoutinePause) or 0) > 0.10)
					)
				if canStartQueuedOrder then
					TryStartNextQueuedOrder(npc)
				end
				Npc_ProcessManualOrder(npc)
				local currentState = tostring(Npc_GetSocialState(npc) or "walk")
					local isFreeWalk = (currentState == "walk")
						and type(npc.manualOrder) ~= "table"
						and GetNpcManualOrderQueueSize(npc) == 0
					local insideLieuData = GetLieuAtPoint(npc.u, npc.v)
					local insideLieu = (insideLieuData ~= nil)
					if
						isFreeWalk
						and insideLieu
						and (tonumber(npc.zoneShiftTargetU) == nil and tonumber(npc.zoneShiftTargetV) == nil)
					then
						local now = NowSec()
						local nextExitTryAt = tonumber(npc.walkLieuExitRetryAt) or 0
						if now >= nextExitTryAt then
							local insideType = string.lower(tostring(insideLieuData and insideLieuData.lieuType or ""))
							local keepSleepingTonight = IsNightPhase() and insideType == "chaumiere"
							if keepSleepingTonight then
								npc.behaviorState = "self_pause"
								npc.essentialPausePurpose = "rest"
								npc.essentialPauseTarget = math.max(
									NPC_NEEDS_ESSENTIAL.holdMax,
									essentialNeeds.GetTarget(npc, "rest")
								)
								npc.essentialPauseBoost = NPC_NEEDS_ESSENTIAL.recoverBoost
								npc.essentialPauseSource = "auto"
								npc.essentialPauseLockUntil = now + 1.8
								npc.behaviorTimer = math.max(tonumber(npc.behaviorTimer) or 0, 2.0)
								npc.walkLieuExitRetryAt = now + 1.0
							else
								if Npc_RequestZoneExit(npc) then
									npc.walkLieuExitRetryAt = now + 0.70
								else
									npc.walkLieuExitRetryAt = now + 0.35
								end
							end
						end
					else
						npc.walkLieuExitRetryAt = 0
					end
				if navCache.hasRoutes or navCache.hasPlazas then
					if not Npc_UpdateWalkableWander(npc, dt) then
						Npc_UpdateFreeMove(npc, dt)
					end
				else
					Npc_UpdateFreeMove(npc, dt)
				end
			end
			npc.u = Clamp(npc.u, 0, 1)
			npc.v = Clamp(npc.v, 0, 1)
			Npc_UpdateZoneTracking(npc)
			NpcSpatialReindex(npc)
		else
			-- Minimal timer drain for NPCs skipped this tick in low-CPU mode.
			npc.switchCooldown = math.max(0, (tonumber(npc.switchCooldown) or 0) - (dt * 0.35))
			npc.waitTimer = math.max(0, (tonumber(npc.waitTimer) or 0) - dt)
			npc.poiVisitCooldown = math.max(0, (tonumber(npc.poiVisitCooldown) or 0) - (dt * 0.35))
		end

		local key = npc.zoneKey
		if type(key) == "string" and key ~= "" then
			zoneCounts[key] = (zoneCounts[key] or 0) + 1
		end
	end
	for i = 1, #npcPool do
		local npc = npcPool[i]
		local key = npc.zoneKey
		if
			type(key) == "string"
			and key ~= ""
			and (zoneCounts[key] or 0) > NPC_MAX_PER_ZONE
			and not npc.zoneShiftTargetU
			and not npc.zoneShiftTargetV
		then
			Npc_RequestZoneExit(npc)
		end
	end

	-- Separation/collision volontairement desactivee.

	for i = 1, #npcPool do
		local npc = npcPool[i]
		npc.u = Clamp(npc.u, 0, 1)
		npc.v = Clamp(npc.v, 0, 1)
	end
	if shouldPersist then
		npcPersistenceTimer = npcPersistenceTimer - dt
		if npcPersistenceTimer <= 0 then
			SaveNpcPersistence()
		end
	end
	if shouldRender then
		Npc_RenderAll()
	end
end


end

return Modules
