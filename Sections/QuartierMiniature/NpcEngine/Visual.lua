local ADDON, ns = ...

ns.QuartierMiniatureNpcEngine = ns.QuartierMiniatureNpcEngine or {}
ns.QuartierMiniatureNpcEngine.Modules = ns.QuartierMiniatureNpcEngine.Modules or {}
local Modules = ns.QuartierMiniatureNpcEngine.Modules

function Modules.InstallVisual(ctx, moduleEnv)
	if type(ctx) ~= "table" or type(moduleEnv) ~= "table" then
		return nil
	end
	setfenv(1, moduleEnv)

	local function GetEpochNow()
		local serverNow = (GetServerTime and GetServerTime()) or nil
		if serverNow then
			return math.max(0, tonumber(serverNow) or 0)
		end
		return math.max(0, tonumber(time and time() or 0) or 0)
	end

	function Npc_ApplyRouteState(npc, segIndex, t, dir, snapToSegment)
		local seg = navCache.segments[segIndex or 0]
		if not seg then
			return false
		end
		npc.navMode = "route"
		npc.routeSegIndex = segIndex
		npc.routeT = Clamp(tonumber(t) or 0.5, 0, 1)
		npc.routeDir = ((tonumber(dir) or 1) < 0) and -1 or 1
		npc.plazaIndex = nil
		npc.plazaHeading = nil
		npc.plazaTurnIn = nil
		npc.transition = nil
		npc.transitionSpeed = nil
		npc.tx = nil
		npc.ty = nil
		npc.speed = RandRange(NPC_SPEED_MIN, NPC_SPEED_MAX)
		npc.switchCooldown = NPC_PROX_SWITCH_COOLDOWN
		Npc_ResetSocialState(npc, false)
		if snapToSegment ~= false then
			npc.u = seg.ax + ((seg.bx - seg.ax) * npc.routeT)
			npc.v = seg.ay + ((seg.by - seg.ay) * npc.routeT)
		end
		return true
	end

	function Npc_ApplyPlazaState(npc, plazaIndex, u, v, snapToPos)
		local plaza = navCache.plazas[plazaIndex or 0]
		if not plaza then
			return false
		end
		npc.navMode = "plaza"
		npc.plazaIndex = plazaIndex
		npc.plazaHeading = RandRange(0, math.pi * 2)
		npc.plazaTurnIn = RandRange(0.8, 2.4)
		npc.routeSegIndex = nil
		npc.routeT = nil
		npc.routeDir = nil
		npc.transition = nil
		npc.transitionSpeed = nil
		npc.tx = nil
		npc.ty = nil
		npc.speed = RandRange(NPC_SPEED_MIN * 0.65, NPC_SPEED_MAX * 0.95)
		npc.switchCooldown = NPC_PROX_SWITCH_COOLDOWN
		Npc_ResetSocialState(npc, false)
		if snapToPos ~= false then
			npc.u = Clamp(tonumber(u) or plaza.centerU, 0, 1)
			npc.v = Clamp(tonumber(v) or plaza.centerV, 0, 1)
		end
		return true
	end

	function Npc_StartTransition(npc, targetU, targetV, payload)
		local tu = Clamp(tonumber(targetU) or npc.u or 0.5, 0, 1)
		local tv = Clamp(tonumber(targetV) or npc.v or 0.5, 0, 1)
		npc.navMode = "transition"
		npc.transition = {
			u = tu,
			v = tv,
			payload = payload,
		}
		local baseSpeed = tonumber(npc.speed) or RandRange(NPC_SPEED_MIN, NPC_SPEED_MAX)
		npc.transitionSpeed = math.max(NPC_SPEED_MIN * 1.15, baseSpeed * NPC_TRANSITION_SPEED_FACTOR)
		return true
	end

	function Npc_PickPlazaPoint(plaza, sampleU, sampleV)
		local su = tonumber(sampleU)
		local sv = tonumber(sampleV)
		if su and sv then
			local _, hitU, hitV = DistancePointToPlaza(plaza, su, sv)
			if hitU and hitV then
				return hitU, hitV
			end
		end
		return PickRandomPointInPlaza(plaza)
	end

	function Npc_ChooseRouteFromNode(npc, node, currentSegIndex)
		if not (node and type(node.links) == "table" and #node.links > 0) then
			return false
		end
		local pick = nil
		if #node.links == 1 then
			pick = node.links[1]
		else
			for _ = 1, 8 do
				local cand = node.links[math.random(1, #node.links)]
				if cand and cand.segIndex and (cand.segIndex ~= currentSegIndex or #node.links <= 1) then
					pick = cand
					break
				end
			end
			if not pick then
				pick = node.links[math.random(1, #node.links)]
			end
		end
		if not pick or not navCache.segments[pick.segIndex] then
			return false
		end
		npc.routeSegIndex = pick.segIndex
		npc.routeT = pick.t
		npc.routeDir = pick.dir
		npc.speed = RandRange(NPC_SPEED_MIN, NPC_SPEED_MAX)
		return true
	end

	Npc_EnterRouteMode = function(npc, opts)
		if not navCache.hasRoutes then
			return false
		end
		opts = type(opts) == "table" and opts or nil
		local segIndex = tonumber(opts and opts.segIndex) or math.random(1, #navCache.segments)
		local seg = navCache.segments[segIndex]
		if not seg then
			return false
		end
		local t = Clamp(tonumber(opts and opts.t) or math.random(), 0, 1)
		local dir = ((tonumber(opts and opts.dir) or ((math.random() < 0.5) and -1 or 1)) < 0) and -1 or 1
		local targetU = seg.ax + ((seg.bx - seg.ax) * t)
		local targetV = seg.ay + ((seg.by - seg.ay) * t)
		local smooth = true
		if opts and opts.smooth ~= nil then
			smooth = opts.smooth == true
		end
		if smooth and type(npc.u) == "number" and type(npc.v) == "number" then
			return Npc_StartTransition(npc, targetU, targetV, {
				kind = "route",
				segIndex = segIndex,
				t = t,
				dir = dir,
			})
		end
		return Npc_ApplyRouteState(npc, segIndex, t, dir, true)
	end

	Npc_EnterPlazaMode = function(npc, opts)
		if not navCache.hasPlazas then
			return false
		end
		opts = type(opts) == "table" and opts or nil
		local plazaIndex = tonumber(opts and opts.plazaIndex) or math.random(1, #navCache.plazas)
		local plaza = navCache.plazas[plazaIndex]
		if not plaza then
			return false
		end
		local u, v = Npc_PickPlazaPoint(plaza, opts and opts.u, opts and opts.v)
		local smooth = true
		if opts and opts.smooth ~= nil then
			smooth = opts.smooth == true
		end
		if smooth and type(npc.u) == "number" and type(npc.v) == "number" then
			return Npc_StartTransition(npc, u, v, {
				kind = "plaza",
				plazaIndex = plazaIndex,
				u = u,
				v = v,
			})
		end
		return Npc_ApplyPlazaState(npc, plazaIndex, u, v, true)
	end

	function Npc_EnterAnyNavMode(npc, opts)
		if navCache.hasRoutes and navCache.hasPlazas then
			if math.random() < 0.70 then
				if Npc_EnterRouteMode(npc, opts) then
					return true
				end
				return Npc_EnterPlazaMode(npc, opts)
			end
			if Npc_EnterPlazaMode(npc, opts) then
				return true
			end
			return Npc_EnterRouteMode(npc, opts)
		end
		if navCache.hasRoutes then
			return Npc_EnterRouteMode(npc, opts)
		end
		if navCache.hasPlazas then
			return Npc_EnterPlazaMode(npc, opts)
		end
		return false
	end

	function RefreshNavigationCache(force)
		if not force and navRefreshElapsed < 0.35 then
			return
		end
		navRefreshElapsed = 0
		local routesRoot = ns and ns.QuartierMiniature and ns.QuartierMiniature.Routes or nil
		local mapId = GetActiveMapId()
		local store = nil
		if type(routesRoot) == "table" and type(routesRoot.maps) == "table" then
			store = routesRoot.maps[mapId]
		else
			-- Retrocompat: old flat format.
			store = routesRoot
		end
		local signature = mapId .. "|" .. BuildRoutesSignature(store)
		if not force and signature == navCache.signature then
			return
		end
		local rebuilt = BuildNavigationFromStore(store)
		rebuilt.signature = signature
		navCache = rebuilt
		npcSpatial.dirty = true
		npcSpatial.poiScanCursor = 1
		for i = 1, #npcPool do
			local npc = npcPool[i]
			npc.navMode = nil
			npc.routeSegIndex = nil
			npc.plazaIndex = nil
			npc.transition = nil
			npc.transitionSpeed = nil
			npc.walkHeading = nil
			npc.walkTurnIn = nil
			npc.walkDesiredHeading = nil
			npc.walkDesiredIn = nil
			npc.walkTurnRate = nil
			npc.walkSpeedTarget = nil
			npc.waitTimer = 0
			npc.tx = nil
			npc.ty = nil
			npc.switchCooldown = 0
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
			npc.lastSelfPauseZoneKey = nil
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
			npc.manualOrder = nil
			npc.manualOrderQueue = {}
			npc.autoOrderRollIn = GetNextNpcAutoIntentDelay()
			npc.poiVisitRollIn = RandRange(NPC_POI_ROLL_MIN, NPC_POI_ROLL_MAX)
			npc.poiVisitCooldown = 0
		end
	end

	function Npc_UpdateFreeMove(npc, dt)
		if type(npc.tx) ~= "number" or type(npc.ty) ~= "number" then
			Npc_PickTarget(npc)
		end
		if type(npc.speed) ~= "number" then
			npc.speed = RandRange(NPC_SPEED_MIN, NPC_SPEED_MAX)
		end
		local dx = npc.tx - npc.u
		local dy = npc.ty - npc.v
		local dist = math.sqrt((dx * dx) + (dy * dy))
		if dist < 0.001 then
			Npc_PickTarget(npc)
			return
		end
		local step = npc.speed * dt
		if step >= dist then
			npc.u = npc.tx
			npc.v = npc.ty
			Npc_PickTarget(npc)
			return
		end
		local inv = 1 / dist
		npc.u = npc.u + (dx * inv * step)
		npc.v = npc.v + (dy * inv * step)
	end

	Npc_UpdateTransition = function(npc, dt)
		local tr = npc.transition
		if type(tr) ~= "table" then
			return false
		end
		local dx = (tonumber(tr.u) or npc.u or 0) - (tonumber(npc.u) or 0)
		local dy = (tonumber(tr.v) or npc.v or 0) - (tonumber(npc.v) or 0)
		local dist = math.sqrt((dx * dx) + (dy * dy))
		local speed =
			math.max(NPC_SPEED_MIN * 1.15, tonumber(npc.transitionSpeed) or tonumber(npc.speed) or NPC_SPEED_MIN)
		local step = speed * dt
		if dist < 0.0005 or step >= dist then
			npc.u = tonumber(tr.u) or npc.u
			npc.v = tonumber(tr.v) or npc.v
			local payload = tr.payload
			npc.transition = nil
			npc.transitionSpeed = nil
			if type(payload) == "table" then
				if payload.kind == "route" then
					return Npc_ApplyRouteState(npc, payload.segIndex, payload.t, payload.dir, true)
				elseif payload.kind == "plaza" then
					return Npc_ApplyPlazaState(npc, payload.plazaIndex, payload.u, payload.v, true)
				end
			end
			npc.navMode = nil
			return true
		end
		local inv = 1 / math.max(dist, NAV_EPS)
		npc.u = npc.u + (dx * inv * step)
		npc.v = npc.v + (dy * inv * step)
		return true
	end

	function Npc_UpdateRouteMove(npc, dt)
		local seg = navCache.segments[npc.routeSegIndex or 0]
		if not seg then
			return Npc_EnterRouteMode(npc)
		end
		local remaining = math.max(0, (npc.speed or NPC_SPEED_MIN) * dt)
		local loops = 0
		while remaining > NAV_EPS and loops < 10 do
			loops = loops + 1
			seg = navCache.segments[npc.routeSegIndex or 0]
			if not (seg and seg.len and seg.len > NAV_EPS) then
				return Npc_EnterRouteMode(npc)
			end
			local t = Clamp(tonumber(npc.routeT) or 0, 0, 1)
			local dir = (npc.routeDir and npc.routeDir < 0) and -1 or 1
			local distToNode = (dir > 0) and ((1 - t) * seg.len) or (t * seg.len)

			if remaining < distToNode then
				local dT = remaining / seg.len
				npc.routeT = t + (dir * dT)
				remaining = 0
			else
				npc.routeT = (dir > 0) and 1 or 0
				remaining = remaining - distToNode
				local atU = (dir > 0) and seg.bx or seg.ax
				local atV = (dir > 0) and seg.by or seg.ay
				npc.u = atU
				npc.v = atV

				local routeInfo = (seg.routeIndex and navCache.routes[seg.routeIndex]) or nil
				local nextOrder = (dir > 0) and ((seg.routeOrder or 0) + 1) or ((seg.routeOrder or 0) - 1)
				local nextSegIndex = routeInfo and routeInfo.segments and routeInfo.segments[nextOrder] or nil
				if nextSegIndex then
					npc.routeSegIndex = nextSegIndex
					npc.routeT = (dir > 0) and 0 or 1
					npc.routeDir = dir
				else
					local switched = false
					if (tonumber(npc.switchCooldown) or 0) <= 0 and navCache.hasPlazas and math.random() < 0.22 then
						local nearPlaza = FindNearestPlaza(atU, atV, NPC_ROUTE_TO_PLAZA_DIST)
						if
							nearPlaza
							and Npc_EnterPlazaMode(npc, {
								plazaIndex = nearPlaza.plazaIndex,
								u = nearPlaza.u,
								v = nearPlaza.v,
								smooth = true,
							})
						then
							switched = true
						end
					end
					if
						not switched
						and (tonumber(npc.switchCooldown) or 0) <= 0
						and navCache.hasRoutes
						and math.random() < 0.18
					then
						local nearest = FindNearestRoutePoint(atU, atV, NPC_ROUTE_TO_ROUTE_DIST, npc.routeSegIndex)
						if nearest then
							local newDir = (math.random() < 0.5) and -1 or 1
							if
								Npc_EnterRouteMode(
									npc,
									{ segIndex = nearest.segIndex, t = nearest.t, dir = newDir, smooth = true }
								)
							then
								switched = true
							end
						end
					end
					if switched then
						remaining = 0
					else
						npc.routeDir = -dir
						remaining = 0
					end
				end
			end
		end

		seg = navCache.segments[npc.routeSegIndex or 0]
		if seg then
			local t = Clamp(tonumber(npc.routeT) or 0, 0, 1)
			npc.u = seg.ax + ((seg.bx - seg.ax) * t)
			npc.v = seg.ay + ((seg.by - seg.ay) * t)
		end
		return true
	end

	function Npc_UpdatePlazaMove(npc, dt)
		local plaza = navCache.plazas[npc.plazaIndex or 0]
		if not plaza then
			return Npc_EnterPlazaMode(npc)
		end

		local move = math.max(0, (npc.speed or NPC_SPEED_MIN) * dt)
		npc.plazaTurnIn = (tonumber(npc.plazaTurnIn) or 0) - dt
		if npc.plazaTurnIn <= 0 then
			npc.plazaHeading = RandRange(0, math.pi * 2)
			npc.plazaTurnIn = RandRange(0.7, 2.3)
		end

		local loops = 0
		while move > NAV_EPS and loops < 12 do
			loops = loops + 1
			local step = math.min(0.01, move)
			local heading = tonumber(npc.plazaHeading) or 0
			local nx = npc.u + (math.cos(heading) * step)
			local ny = npc.v + (math.sin(heading) * step)
			if IsPointInPlaza(plaza, nx, ny) then
				npc.u = nx
				npc.v = ny
				move = move - step
			else
				npc.plazaHeading = heading + RandRange(0.8, 2.4)
				npc.plazaTurnIn = RandRange(0.3, 0.9)
				if navCache.hasRoutes and math.random() < 0.15 then
					local nearRoute = FindNearestRoutePoint(npc.u, npc.v, NPC_PLAZA_TO_ROUTE_DIST, nil)
					if nearRoute then
						local dir = (math.random() < 0.5) and -1 or 1
						if
							Npc_EnterRouteMode(npc, {
								segIndex = nearRoute.segIndex,
								t = nearRoute.t,
								dir = dir,
								smooth = true,
							})
						then
							return true
						end
					end
				end
				move = move - (step * 0.25)
			end
		end

		if not IsPointInPlaza(plaza, npc.u, npc.v) then
			local _, hitU, hitV = DistancePointToPlaza(plaza, npc.u, npc.v)
			if hitU and hitV then
				npc.u = hitU
				npc.v = hitV
			else
				local u, v = PickRandomPointInPlaza(plaza)
				npc.u = u
				npc.v = v
			end
		end

		if navCache.hasRoutes and (tonumber(npc.switchCooldown) or 0) <= 0 and math.random() < 0.28 then
			local nearest = FindNearestRoutePoint(npc.u, npc.v, NPC_PLAZA_TO_ROUTE_DIST, nil)
			if nearest then
				local dir = (math.random() < 0.5) and -1 or 1
				if
					Npc_EnterRouteMode(npc, { segIndex = nearest.segIndex, t = nearest.t, dir = dir, smooth = true })
				then
					return true
				end
			end
		end
		return true
	end

	function SetNpcDisplayName(npc, rawName, fallbackIndex)
		if not npc then
			return
		end
		local name = TrimNpcName(rawName) or BuildFallbackName(fallbackIndex)
		npc.displayName = name
	end

	function SetNpcNeeds(npc, rawNeeds)
		if not npc then
			return
		end
		npc.needs = BuildNpcNeeds(rawNeeds)
		npc.needsSpeedFactor = 1
	end

	function QueuePersistedActivityRestore(npc, persisted)
		if type(npc) ~= "table" then
			return
		end
		local activity = type(persisted) == "table" and type(persisted.activity) == "table" and persisted.activity
			or nil
		if type(activity) ~= "table" then
			npc._persistActivity = nil
			return
		end
		local kind = tostring(activity.kind or "")
		local remainingSec = tonumber(activity.remainingSec)
		if (kind ~= "self_pause" and kind ~= "discussion") or not remainingSec or remainingSec <= 0 then
			npc._persistActivity = nil
			return
		end
		npc._persistActivity = {
			kind = kind,
			remainingSec = Clamp(remainingSec, 0.1, 900),
			purpose = tostring(activity.purpose or ""),
			partnerId = tostring(activity.partnerId or ""),
			source = tostring(activity.source or "player"),
			groupId = tostring(activity.groupId or ""),
			lockRemainingSec = Clamp(tonumber(activity.lockRemainingSec) or 0, 0, 900),
		}
	end

	function QueuePersistedIntentRestore(npc, persisted)
		if type(npc) ~= "table" then
			return
		end
		local intent = type(persisted) == "table" and type(persisted.intent) == "table" and persisted.intent or nil
		if type(intent) ~= "table" then
			npc._persistIntent = nil
			return
		end
		local function CopyIntent(raw)
			if type(raw) ~= "table" then
				return nil
			end
			local kind = tostring(raw.kind or "")
			if kind ~= "lieu_pause" and kind ~= "talk" and kind ~= "join_talk" then
				return nil
			end
			local remainingSec = Clamp(tonumber(raw.remainingSec) or 0, 0, 7200)
			if remainingSec <= 0 then
				return nil
			end
			local out = {
				kind = kind,
				source = tostring(raw.source or "player"),
				remainingSec = remainingSec,
			}
			if kind == "lieu_pause" then
				local tu = tonumber(raw.targetU)
				local tv = tonumber(raw.targetV)
				if not (tu and tv) then
					return nil
				end
				out.targetU = Clamp(tu, 0, 1)
				out.targetV = Clamp(tv, 0, 1)
				out.purpose = tostring(raw.purpose or "rest")
				out.lieuType = tostring(raw.lieuType or "")
				out.waitSeconds = Clamp(tonumber(raw.waitSeconds) or 0, 0, 600)
				out.freeMove = raw.freeMove == true
			else
				out.partnerId = tostring(raw.partnerId or "")
				if out.partnerId == "" then
					return nil
				end
				out.groupId = tostring(raw.groupId or "")
			end
			return out
		end
		local restored = {
			active = CopyIntent(intent.active),
			queue = {},
		}
		local queue = type(intent.queue) == "table" and intent.queue or {}
		for i = 1, #queue do
			local item = CopyIntent(queue[i])
			if item then
				restored.queue[#restored.queue + 1] = item
			end
		end
		if restored.active or #restored.queue > 0 then
			npc._persistIntent = restored
		else
			npc._persistIntent = nil
		end
	end

	function ApplyPersistedActivityRestore()
		local byId = {}
		for i = 1, #npcPool do
			local npc = npcPool[i]
			local id = tostring(npc and npc.persistentId or "")
			if id ~= "" then
				byId[id] = npc
			end
		end

		for i = 1, #npcPool do
			local npc = npcPool[i]
			local activity = type(npc) == "table" and type(npc._persistActivity) == "table" and npc._persistActivity
				or nil
			if activity and activity.kind == "self_pause" then
				Npc_BreakCurrentSocialLink(npc)
				Npc_ClearManualOrder(npc, true)
				ClearNpcManualOrderQueue(npc)
				npc.behaviorState = "self_pause"
				npc.behaviorPartner = nil
				npc.conversationGroupId = nil
				npc.behaviorTimer = Clamp(tonumber(activity.remainingSec) or 1.0, 0.2, 900)
				npc.behaviorCooldown = 0
				npc.pausePurpose = tostring(activity.purpose or "")
				if npc.pausePurpose == "rest" or npc.pausePurpose == "meal" or npc.pausePurpose == "distraction" then
					npc.essentialPausePurpose = npc.pausePurpose
					npc.essentialPauseTarget =
						math.max(NPC_NEEDS_ESSENTIAL.holdMax, essentialNeeds.GetTarget(npc, npc.pausePurpose))
					npc.essentialPauseBoost = NPC_NEEDS_ESSENTIAL.recoverBoost
					npc.essentialPauseSource = tostring(activity.source or "player")
					local lockRemaining = Clamp(tonumber(activity.lockRemainingSec) or 0, 0, 900)
					if lockRemaining > 0 then
						npc.essentialPauseLockUntil = NowSec() + lockRemaining
					else
						npc.essentialPauseLockUntil = nil
					end
				else
					npc.essentialPausePurpose = nil
					npc.essentialPauseTarget = nil
					npc.essentialPauseBoost = nil
					npc.essentialPauseSource = nil
					npc.essentialPauseLockUntil = nil
				end
			end
		end

		local paired = {}
		for i = 1, #npcPool do
			local npc = npcPool[i]
			local activity = type(npc) == "table" and type(npc._persistActivity) == "table" and npc._persistActivity
				or nil
			if activity and activity.kind == "discussion" then
				local sourceId = tostring(npc.persistentId or "")
				local partnerId = tostring(activity.partnerId or "")
				if sourceId ~= "" and partnerId ~= "" and sourceId ~= partnerId then
					local keyA = sourceId < partnerId and sourceId or partnerId
					local keyB = sourceId < partnerId and partnerId or sourceId
					local pairKey = keyA .. "|" .. keyB
					if not paired[pairKey] then
						paired[pairKey] = true
						local partner = byId[partnerId]
						if partner then
							local partnerActivity = type(partner._persistActivity) == "table"
									and partner._persistActivity
								or nil
							local groupId = tostring(activity.groupId or "")
							if groupId == "" then
								groupId = tostring(partnerActivity and partnerActivity.groupId or "")
							end
							local sourceTag = tostring(activity.source or "")
							if sourceTag == "" then
								sourceTag = tostring(partnerActivity and partnerActivity.source or "player")
							end
							if sourceTag == "" then
								sourceTag = "player"
							end
							local talkFor = Clamp(
								math.max(
									tonumber(activity.remainingSec) or 0,
									tonumber(partnerActivity and partnerActivity.remainingSec) or 0
								),
								0.2,
								180
							)
							Npc_BreakCurrentSocialLink(npc)
							Npc_BreakCurrentSocialLink(partner)
							Npc_ClearManualOrder(npc, true)
							Npc_ClearManualOrder(partner, true)
							ClearNpcManualOrderQueue(npc)
							ClearNpcManualOrderQueue(partner)
							local ok = Npc_BeginDiscussionPair(
								npc,
								partner,
								talkFor,
								sourceTag,
								groupId ~= "" and groupId or nil
							)
							if not ok then
								npc.behaviorState = "self_pause"
								npc.behaviorTimer = Clamp(talkFor * 0.50, 0.6, 30.0)
								npc.behaviorPartner = nil
								npc.conversationGroupId = nil
								partner.behaviorState = "self_pause"
								partner.behaviorTimer = Clamp(talkFor * 0.50, 0.6, 30.0)
								partner.behaviorPartner = nil
								partner.conversationGroupId = nil
							end
						end
					end
				end
			end
		end

		for i = 1, #npcPool do
			local npc = npcPool[i]
			if type(npc) == "table" then
				npc._persistActivity = nil
			end
		end
	end

	function ApplyPersistedIntentRestore()
		local byId = {}
		for i = 1, #npcPool do
			local npc = npcPool[i]
			local id = tostring(npc and npc.persistentId or "")
			if id ~= "" then
				byId[id] = npc
			end
		end

		local function InflateIntent(npc, src)
			if type(src) ~= "table" then
				return nil
			end
			local kind = tostring(src.kind or "")
			local remainingSec = Clamp(tonumber(src.remainingSec) or 0, 0, 7200)
			if remainingSec <= 0 then
				return nil
			end
			local entry = {
				kind = kind,
				source = tostring(src.source or "player"),
				expiresAt = NowSec() + remainingSec,
			}
			if kind == "lieu_pause" then
				local tu = Clamp(tonumber(src.targetU) or 0.5, 0, 1)
				local tv = Clamp(tonumber(src.targetV) or 0.5, 0, 1)
				local zoneKey = select(1, GetZoneKeyAtPoint(tu, tv))
				if not (IsPointWalkable(tu, tv) and IsZoneEntryAllowed(npc, zoneKey, true)) then
					local wanted = NormalizeLieuType(src.lieuType)
						if wanted ~= "" then
							local fallback = Npc_FindLieuTargetPoint(npc, wanted, { allowFullFallback = false })
						if fallback then
							tu = Clamp(tonumber(fallback.u) or tu, 0, 1)
							tv = Clamp(tonumber(fallback.v) or tv, 0, 1)
						else
							return nil
						end
					else
						return nil
					end
				end
				entry.targetU = tu
				entry.targetV = tv
				entry.purpose = tostring(src.purpose or "rest")
				entry.lieuType = tostring(src.lieuType or "")
				entry.waitSeconds = Clamp(tonumber(src.waitSeconds) or 0, 0, 600)
				entry.freeMove = src.freeMove == true
				if not IsPurposeAllowedNow(entry.purpose) then
					return nil
				end
			elseif kind == "talk" then
				local partnerId = tostring(src.partnerId or "")
				if partnerId == "" or partnerId == tostring(npc.persistentId or "") or not byId[partnerId] then
					return nil
				end
				entry.partnerId = partnerId
				entry.requestedAt = NowSec()
				entry.groupId = tostring(src.groupId or "")
			elseif kind == "join_talk" then
				local partnerId = tostring(src.partnerId or "")
				if partnerId == "" or partnerId == tostring(npc.persistentId or "") or not byId[partnerId] then
					return nil
				end
				entry.partnerId = partnerId
				entry.groupId = tostring(src.groupId or "")
				entry.requestedAt = NowSec()
			else
				return nil
			end
			return entry
		end

		for i = 1, #npcPool do
			local npc = npcPool[i]
			local bag = type(npc) == "table" and type(npc._persistIntent) == "table" and npc._persistIntent or nil
			if bag then
				npc.manualOrderQueue = type(npc.manualOrderQueue) == "table" and npc.manualOrderQueue or {}
				local queueOut = {}
				for q = 1, #npc.manualOrderQueue do
					queueOut[#queueOut + 1] = npc.manualOrderQueue[q]
				end
				local hadRestoredActivity = tostring(Npc_GetSocialState(npc) or "walk") ~= "walk"
				if (not hadRestoredActivity) and type(npc.manualOrder) ~= "table" then
					local active = InflateIntent(npc, bag.active)
					if active then
						if tostring(active.kind or "") == "lieu_pause" then
							npc.manualOrder = active
							Npc_ApplyManualWaypointTarget(
								npc,
								npc.manualOrder,
								npc.manualOrder.targetU,
								npc.manualOrder.targetV,
								"manual_lieu",
								36
							)
						else
							table.insert(queueOut, 1, active)
						end
					end
				end
				local queue = type(bag.queue) == "table" and bag.queue or {}
				for q = 1, #queue do
					local item = InflateIntent(npc, queue[q])
					if item then
						queueOut[#queueOut + 1] = item
					end
				end
				if #queueOut > NPC_INTENT_QUEUE_MAX then
					local trimmed = {}
					for k = 1, NPC_INTENT_QUEUE_MAX do
						trimmed[#trimmed + 1] = queueOut[k]
					end
					queueOut = trimmed
				end
				npc.manualOrderQueue = queueOut
				if type(npc.manualOrder) ~= "table" and #npc.manualOrderQueue > 0 then
					TryStartNextQueuedOrder(npc)
				end
			end
		end

		for i = 1, #npcPool do
			local npc = npcPool[i]
			if type(npc) == "table" then
				npc._persistIntent = nil
			end
		end
	end

	function BuildPersistedNpcLookup()
		local empty = { bySlot = {}, byId = {} }
		local emptyMeta = {
			updatedAt = 0,
			updatedAtServer = 0,
			signature = "",
		}
		if not (NpcPersistence and type(NpcPersistence.LoadNpcs) == "function") then
			return empty, false, emptyMeta
		end
		local savedList, sameSignature, meta = NpcPersistence.LoadNpcs(GetActiveMapId(), navCache.signature)
		local bySlot = {}
		local byId = {}
		if type(savedList) == "table" then
			for i = 1, #savedList do
				local row = savedList[i]
				if type(row) == "table" then
					bySlot[i] = row
					local id = tostring(row.id or "")
					if id ~= "" then
						byId[id] = row
					end
				end
			end
		end
		return {
			bySlot = bySlot,
			byId = byId,
		},
			sameSignature == true,
			{
				updatedAt = tonumber(type(meta) == "table" and meta.updatedAt or 0) or 0,
				updatedAtServer = tonumber(type(meta) == "table" and meta.updatedAtServer or 0) or 0,
				signature = tostring(type(meta) == "table" and meta.signature or ""),
			}
	end

	function GetUniqueNpcName(usedNames, rawName, fallbackIndex)
		local baseName = TrimNpcName(rawName) or BuildFallbackName(fallbackIndex)
		if not usedNames[baseName] then
			usedNames[baseName] = true
			return baseName
		end
		for i = 2, 200 do
			local candidate = baseName .. " " .. tostring(i)
			if not usedNames[candidate] then
				usedNames[candidate] = true
				return candidate
			end
		end
		local fallback = BuildFallbackName(fallbackIndex) .. " " .. tostring(math.random(100, 999))
		usedNames[fallback] = true
		return fallback
	end

	function SaveNpcPersistence()
		if NpcPersistence and type(NpcPersistence.SaveNpcs) == "function" then
			local savedAt = NpcPersistence.SaveNpcs(GetActiveMapId(), navCache.signature, npcPool)
			SetBootstrapPersistenceEpoch(savedAt)
			npcPersistenceTimer = NPC_PERSIST_SAVE_INTERVAL
			npcPersistenceMapId = tostring(GetActiveMapId() or "default")
			return
		end
		WoWGuildeDB = WoWGuildeDB or {}
		WoWGuildeDB.QuartierMiniature = WoWGuildeDB.QuartierMiniature or {}
		local root = WoWGuildeDB.QuartierMiniature
		root.npcState = root.npcState or { version = 1, maps = {} }
		root.npcState.maps = root.npcState.maps or {}
		local mapId = tostring(GetActiveMapId() or "default")
		local entry = root.npcState.maps[mapId] or {}
		entry.signature = tostring(navCache and navCache.signature or "")
		entry.updatedAt = GetEpochNow()
		entry.updatedAtServer = entry.updatedAt
		SetBootstrapPersistenceEpoch(entry.updatedAtServer)
		entry.npcs = {}
		for i = 1, #npcPool do
			local npc = npcPool[i]
			if type(npc) == "table" then
				entry.npcs[#entry.npcs + 1] = {
					id = tostring(npc.persistentId or ("npc_" .. tostring(i))),
					name = tostring(npc.displayName or ""),
				}
			end
		end
		root.npcState.maps[mapId] = entry
		npcPersistenceTimer = NPC_PERSIST_SAVE_INTERVAL
		npcPersistenceMapId = tostring(GetActiveMapId() or "default")
	end

	function UpdateNpcNeeds(npc, dt)
		if not (npc and NPC_NEEDS_ENABLED) then
			return
		end
		if type(npc.needs) ~= "table" then
			npc.needs = BuildNpcNeeds(nil)
		end
		local needs = npc.needs
		local stateName = Npc_GetSocialState(npc)
		local moving = (tonumber(npc.speed) or 0) > (NPC_SPEED_MIN * 0.35)
		local inZonePause = (tostring(npc.zoneRoutineStep or "") == "pause")
			and ((tonumber(npc.zoneRoutinePause) or 0) > 0.10)
		local essentialPurpose = tostring(npc.essentialPausePurpose or "")
		local essentialBoost = Clamp(tonumber(npc.essentialPauseBoost) or NPC_NEEDS_ESSENTIAL.recoverBoost, 1.0, 40.0)
		local timeNeedsDrain = GetTimeNeedsDrainFactor()
		local timeNeedsRecovery = GetTimeNeedsRecoveryFactor()
		if stateName ~= "self_pause" then
			npc.essentialPausePurpose = nil
			npc.essentialPauseTarget = nil
			npc.essentialPauseBoost = nil
			npc.essentialPauseLockUntil = nil
			npc.essentialPauseSource = nil
			npc.essentialPauseRollPurpose = nil
			npc.essentialPauseRollPercent = nil
			npc.pausePurpose = nil
			essentialPurpose = ""
		end
		local faimPauseGain = math.max(NPC_NEEDS_FAIM_RECOVER_PAUSE, NPC_NEEDS_FAIM_RISE * 1.35)
		local distractionPauseGain = math.max(NPC_NEEDS_DISTRACTION_RECOVER_PAUSE, NPC_NEEDS_DISTRACTION_RISE * 1.35)
		local inLieu, lieuIndex = GetLieuAtPoint(npc.u, npc.v)
		local inLieuType = inLieu and string.lower(tostring(inLieu.lieuType or "")) or ""
		local nightHomeSleep = IsNightPhase() and inLieuType == "chaumiere"
		npc.currentLieuType = inLieu and tostring(inLieu.lieuType or "") or nil
		npc.currentLieuId = inLieu and tostring(inLieu.id or ("lieu_" .. tostring(lieuIndex or 0))) or nil

		-- Need gauges now represent "reserve" (100 = full, 0 = empty):
		-- they drain over time and recover through matching activities.
		local social = (tonumber(needs.social) or 0) - (NPC_NEEDS_SOCIAL_RISE * dt * timeNeedsDrain)
		if stateName == "discussion" or stateName == "duo_walk" then
			social = social + (NPC_NEEDS_SOCIAL_RECOVER_TALK * dt * timeNeedsRecovery)
		end
		if stateName == "discussion" then
			local bonusTotal = Clamp(tonumber(npc.discussionSocialBonusTotal) or 0, 0, 100)
			local bonusApplied = Clamp(tonumber(npc.discussionSocialBonusApplied) or 0, 0, 100)
			if bonusTotal > bonusApplied then
				local bonusDuration = math.max(0.10, tonumber(npc.discussionSocialBonusDuration) or 1.0)
				local bonusRate = bonusTotal / bonusDuration
				local bonusStep = math.min(bonusTotal - bonusApplied, math.max(0, bonusRate * (tonumber(dt) or 0)))
				if bonusStep > 0 then
					social = social + bonusStep
					npc.discussionSocialBonusApplied = bonusApplied + bonusStep
				end
			end
		end
		if inLieu and (inLieuType == "auberge" or inLieuType == "chaumiere" or inLieuType == "taverne") then
			local inLieuCount = CountNpcsInLieu(inLieu, nil)
			if inLieuCount >= NPC_NEEDS_SOCIAL_LIEU_GROUP_MIN_COUNT then
				social = social + (NPC_NEEDS_SOCIAL_RECOVER_LIEU_GROUP * dt * timeNeedsRecovery)
			end
		end

		local fatigueDelta = moving and -(NPC_NEEDS_FATIGUE_RISE_MOVE * timeNeedsDrain)
			or (NPC_NEEDS_FATIGUE_RECOVER_REST * timeNeedsRecovery)
		if stateName == "self_pause" and essentialPurpose == "rest" and inLieuType == "chaumiere" then
			fatigueDelta = math.max(fatigueDelta, NPC_NEEDS_FATIGUE_RECOVER_REST * essentialBoost * timeNeedsRecovery)
			if nightHomeSleep then
				-- Keep sleep active all night while inside home.
				npc.behaviorTimer = math.max(tonumber(npc.behaviorTimer) or 0, 1.25)
				npc.essentialPauseLockUntil = math.max(tonumber(npc.essentialPauseLockUntil) or 0, (NowSec()) + 1.5)
			end
		end
		local fatigue = (tonumber(needs.fatigue) or 0) + (fatigueDelta * dt)
		local faim = (tonumber(needs.faim) or 0) - (NPC_NEEDS_FAIM_RISE * dt * timeNeedsDrain)
		local distraction = (tonumber(needs.distraction) or 0) - (NPC_NEEDS_DISTRACTION_RISE * dt * timeNeedsDrain)

		if stateName == "self_pause" then
			if essentialPurpose == "distraction" and inLieuType == "taverne" then
				distraction = distraction + (distractionPauseGain * dt * 1.25 * essentialBoost * timeNeedsRecovery)
			elseif essentialPurpose == "meal" and inLieuType == "auberge" then
				faim = faim + (faimPauseGain * dt * 1.35 * essentialBoost * timeNeedsRecovery)
			elseif essentialPurpose == "rest" and inLieuType == "chaumiere" then
				fatigue = fatigue + (NPC_NEEDS_FATIGUE_RECOVER_REST * dt * 0.35 * essentialBoost * timeNeedsRecovery)
			end
		elseif inZonePause then
			faim = faim + (faimPauseGain * dt * 0.95 * timeNeedsRecovery)
			distraction = distraction + (distractionPauseGain * dt * 0.90 * timeNeedsRecovery)
		elseif stateName == "discussion" then
			distraction = distraction + (distractionPauseGain * dt * 0.45 * timeNeedsRecovery)
		end

		needs.social = Clamp(social, 0, 100)
		needs.fatigue = Clamp(fatigue, 0, 100)
		needs.faim = Clamp(faim, 0, 100)
		needs.distraction = Clamp(distraction, 0, 100)

		-- Fin de pause essentielle des que le seuil de reserve est atteint.
		if
			stateName == "self_pause"
			and (essentialPurpose == "rest" or essentialPurpose == "distraction" or essentialPurpose == "meal")
		then
			local lockUntil = tonumber(npc.essentialPauseLockUntil) or 0
			local now = NowSec()
			local lockActive = lockUntil > now
			local source = tostring(npc.essentialPauseSource or "auto")
			if essentialPurpose == "rest" then
				local reserve = Clamp(tonumber(needs.fatigue) or 0, 0, 100)
				local canStop = false
				if actionRules and type(actionRules.ShouldStopByCompletion) == "function" then
					canStop = actionRules.ShouldStopByCompletion({
						npc = npc,
						source = source,
						purpose = "rest",
						reserve = reserve,
						lockActive = lockActive,
					}) == true
				else
					canStop = (source == "player") and (reserve >= 100)
						or ShouldStopEssentialPauseByReserve(npc, "rest", reserve)
				end
				local keepSleepingTonight = nightHomeSleep
					and stateName == "self_pause"
					and essentialPurpose == "rest"
					and inLieuType == "chaumiere"
				if (not keepSleepingTonight) and (((not lockActive) and canStop) or reserve >= 100) then
					npc.behaviorTimer = math.min(tonumber(npc.behaviorTimer) or 0, 0.55)
					essentialNeeds.ResetTarget(npc, "rest")
					npc.essentialPausePurpose = nil
					npc.essentialPauseTarget = nil
					npc.essentialPauseBoost = nil
					npc.essentialPauseLockUntil = nil
					npc.essentialPauseSource = nil
					npc.essentialPauseRollPurpose = nil
					npc.essentialPauseRollPercent = nil
				end
			elseif essentialPurpose == "meal" then
				local reserve = Clamp(tonumber(needs.faim) or 0, 0, 100)
				local canStop = false
				if actionRules and type(actionRules.ShouldStopByCompletion) == "function" then
					canStop = actionRules.ShouldStopByCompletion({
						npc = npc,
						source = source,
						purpose = "meal",
						reserve = reserve,
						lockActive = lockActive,
					}) == true
				else
					canStop = (source == "player") and (reserve >= 100)
						or ShouldStopEssentialPauseByReserve(npc, "meal", reserve)
				end
				if ((not lockActive) and canStop) or reserve >= 100 then
					npc.behaviorTimer = math.min(tonumber(npc.behaviorTimer) or 0, 0.55)
					essentialNeeds.ResetTarget(npc, "meal")
					npc.essentialPausePurpose = nil
					npc.essentialPauseTarget = nil
					npc.essentialPauseBoost = nil
					npc.essentialPauseLockUntil = nil
					npc.essentialPauseSource = nil
					npc.essentialPauseRollPurpose = nil
					npc.essentialPauseRollPercent = nil
				end
			else
				local reserve = Clamp(tonumber(needs.distraction) or 0, 0, 100)
				local canStop = false
				if actionRules and type(actionRules.ShouldStopByCompletion) == "function" then
					canStop = actionRules.ShouldStopByCompletion({
						npc = npc,
						source = source,
						purpose = "distraction",
						reserve = reserve,
						lockActive = lockActive,
					}) == true
				else
					canStop = (source == "player") and (reserve >= 100)
						or ShouldStopEssentialPauseByReserve(npc, "distraction", reserve)
				end
				if ((not lockActive) and canStop) or reserve >= 100 then
					npc.behaviorTimer = math.min(tonumber(npc.behaviorTimer) or 0, 0.55)
					essentialNeeds.ResetTarget(npc, "distraction")
					npc.essentialPausePurpose = nil
					npc.essentialPauseTarget = nil
					npc.essentialPauseBoost = nil
					npc.essentialPauseLockUntil = nil
					npc.essentialPauseSource = nil
					npc.essentialPauseRollPurpose = nil
					npc.essentialPauseRollPercent = nil
				end
			end
		end

		local fatigueReserveRatio = needs.fatigue / 100
		local fatigueDrainRatio = 1 - fatigueReserveRatio
		npc.needsSpeedFactor = Clamp(1 - (fatigueDrainRatio * NPC_NEEDS_FATIGUE_SPEED_PENALTY), 0.25, 1.0)

		local socialUrgencyLow = Clamp(100 - NPC_NEEDS_SOCIAL_URGENCY, 0, 100)
		if needs.social <= socialUrgencyLow and (tonumber(npc.behaviorCooldown) or 0) > 0.40 then
			npc.behaviorCooldown = RandRange(0.08, 0.38)
		end
		local distractionPauseLow = Clamp(100 - NPC_NEEDS_DISTRACTION_PAUSE, 0, 100)
		if
			math.min(tonumber(needs.faim) or 0, tonumber(needs.distraction) or 0)
				<= math.min(distractionPauseLow, 20)
			and stateName == "walk"
			and (tonumber(npc.selfPauseCooldown) or 0) > 0.50
		then
			npc.selfPauseCooldown = RandRange(0.06, 0.28)
		end
	end

	function InitNpcs()
		RefreshNavigationCache(true)
		local persistedLookup, persistedCanRestorePosition, persistedMeta = BuildPersistedNpcLookup()
		local persistedUpdatedAt = tonumber(type(persistedMeta) == "table" and persistedMeta.updatedAtServer or 0) or 0
		if persistedUpdatedAt <= 0 then
			persistedUpdatedAt = tonumber(type(persistedMeta) == "table" and persistedMeta.updatedAt or 0) or 0
		end
		if persistedUpdatedAt <= 0 then
			persistedUpdatedAt = GetEpochNow()
		end
		SetBootstrapPersistenceEpoch(persistedUpdatedAt)
		local playerHeroName = TrimNpcName(UnitName and UnitName("player") or nil) or NPC_PLAYER_HERO_NAME_FALLBACK
		local playerHeroAtlas = PickValidNpcAtlas()
		local routeRegieU, routeRegieV = nil, nil
		do
			local routesRoot = ns and ns.QuartierMiniature and ns.QuartierMiniature.Routes or nil
			local mapId = GetActiveMapId()
			local mapStore = nil
			if type(routesRoot) == "table" and type(routesRoot.maps) == "table" then
				mapStore = routesRoot.maps[mapId]
			else
				mapStore = routesRoot
			end
			local regie = type(mapStore) == "table" and mapStore.regisseuse or nil
			local ru = tonumber(regie and regie.u)
			local rv = tonumber(regie and regie.v)
			if ru and rv then
				routeRegieU = Clamp(ru, 0, 1)
				routeRegieV = Clamp(rv, 0, 1)
			end
		end
		if UnitRace and UnitSex then
			local _, raceFile = UnitRace("player")
			local sex = UnitSex("player")
			local sexKey = (sex == 3) and "female" or "male"
			local src = ns and ns.Data and ns.Data.SessionPresenceAtlas or nil
			local bucket = type(src) == "table" and type(src[sexKey]) == "table" and src[sexKey] or nil
			local atlas = bucket and raceFile and tostring(bucket[raceFile] or "") or ""
			if atlas ~= "" and IsAtlasUsable(atlas) then
				playerHeroAtlas = atlas
			end
		end
		if not IsAtlasUsable(playerHeroAtlas) then
			playerHeroAtlas = NPC_FALLBACK_ATLAS
		end
		local usedNames = {}
		for i = 1, NPC_COUNT do
			local isPlayerHero = (i == 1)
			local isRegisseuse = (i == 2)
			local persisted = nil
			if isPlayerHero then
				persisted = persistedLookup.byId[NPC_PLAYER_HERO_ID] or persistedLookup.bySlot[i]
			elseif isRegisseuse then
				persisted = persistedLookup.byId[NPC_REGISSEUSE_ID] or persistedLookup.bySlot[i]
			else
				persisted = persistedLookup.bySlot[i]
			end
			local atlas = playerHeroAtlas
			if isPlayerHero then
				atlas = playerHeroAtlas
			elseif isRegisseuse then
				atlas = PickValidNpcAtlas()
			else
				local persistedAtlas = tostring(persisted and persisted.portraitAtlas or "")
				if persistedAtlas ~= "" and IsAtlasUsable(persistedAtlas) then
					atlas = persistedAtlas
				else
					atlas = PickValidNpcAtlas()
				end
			end
			local frameNpc = CreateNpcVisual(atlas)
			local persistedId = persisted and tostring(persisted.id or "") or ""
			if persistedId == "" then
				if isPlayerHero then
					persistedId = NPC_PLAYER_HERO_ID
				elseif isRegisseuse then
					persistedId = NPC_REGISSEUSE_ID
				else
					persistedId = "npc_" .. tostring(i)
				end
			end
			local npc = {
				persistentId = persistedId,
				portraitAtlas = atlas,
				portraitUnit = isPlayerHero and "player" or nil,
				portraitTexturePath = isRegisseuse and NPC_REGISSEUSE_PORTRAIT_TEXTURE or nil,
				portraitFlipX = false,
				frame = frameNpc,
				renderHeightOrder = i,
				u = RandomWorldCoord(),
				v = RandomWorldCoord(),
				tx = 0.5,
				ty = 0.5,
				speed = RandRange(NPC_SPEED_MIN, NPC_SPEED_MAX),
				navMode = nil,
				transition = nil,
				transitionSpeed = nil,
				walkHeading = nil,
				walkTurnIn = nil,
				walkDesiredHeading = nil,
				walkDesiredIn = nil,
				walkTurnRate = nil,
				walkSpeedTarget = nil,
				waitTimer = 0,
				switchCooldown = 0,
				behaviorState = "walk",
				behaviorPartner = nil,
				conversationGroupId = nil,
				behaviorTimer = 0,
				behaviorCooldown = RandRange(0.25, NPC_SOCIAL_COOLDOWN_MAX * 0.60),
				encounterRollIn = RandRange(NPC_SOCIAL_ENCOUNTER_CHECK_MIN, NPC_SOCIAL_ENCOUNTER_CHECK_MAX),
				duoTargetU = nil,
				duoTargetV = nil,
				pauseLookHeading = nil,
				currentSelfPauseZoneKey = nil,
				lastSelfPauseZoneKey = nil,
				disengageFromU = nil,
				disengageFromV = nil,
				disengagePartner = nil,
				lastTalkPartner = nil,
				lastTalkCooldown = 0,
				zoneKey = nil,
				prevZoneKey = nil,
				zoneKind = nil,
				zoneActionCount = 0,
				zoneMoveHopCount = 0,
				plazaRoamRetargetIn = RandRange(NPC_PLAZA_ROAM_RETARGET_MIN * 0.5, NPC_PLAZA_ROAM_RETARGET_MAX),
				longWalkTargetU = nil,
				longWalkTargetV = nil,
				longWalkRetargetIn = RandRange(NPC_LONG_GOAL_RETARGET_MIN * 0.5, NPC_LONG_GOAL_RETARGET_MAX),
				selfPauseCooldown = RandRange(0.8, NPC_SELF_PAUSE_COOLDOWN_MAX * 0.55),
				zoneShiftTargetU = nil,
				zoneShiftTargetV = nil,
				zoneShiftGoalU = nil,
				zoneShiftGoalV = nil,
				zoneShiftTargetKind = nil,
				zoneShiftPathWaypoints = nil,
				zoneShiftPathIndex = nil,
				zoneShiftPathTargetKey = nil,
				zoneShiftPathNavSignature = nil,
				zoneShiftTimer = 0,
				zoneRoutineZoneKey = nil,
				zoneRoutineActionCount = 0,
				zoneRoutineStep = "move",
				zoneRoutinePause = 0,
				zoneRoutineTargetU = nil,
				zoneRoutineTargetV = nil,
				zoneRoutineTargetTtl = 0,
				manualOrder = nil,
				manualOrderQueue = {},
				autoOrderRollIn = GetNextNpcAutoIntentDelay(),
				poiVisitRollIn = RandRange(NPC_POI_ROLL_MIN, NPC_POI_ROLL_MAX),
				poiVisitCooldown = 0,
				severeBlockIterations = 0,
				severeBlockEscalation = 0,
				lastSevereBlockAt = 0,
				_presenceKnown = false,
				_presenceState = nil,
				_presenceProgress = 0,
				_presenceLastRenderAt = 0,
				_presenceInsideStable = nil,
				_presencePendingInside = nil,
				_presencePendingTimer = 0,
				playable = not isRegisseuse,
				isRegisseuse = isRegisseuse == true,
				regieCenterU = nil,
				regieCenterV = nil,
				regieRadius = isRegisseuse and 0.040 or nil,
				regieTargetU = nil,
				regieTargetV = nil,
				regieWait = 0,
				regieSpeed = isRegisseuse and (NPC_SPEED_MIN * 0.78) or nil,
			}
			if isRegisseuse then
				npc.portraitFlipX = false
				ApplyNpcPortraitFlip(npc.frame, false)
			elseif persisted and persisted.portraitFlipX ~= nil then
				npc.portraitFlipX = persisted.portraitFlipX == true
				ApplyNpcPortraitFlip(npc.frame, npc.portraitFlipX == true)
			else
				RollNpcPortraitFlip(npc)
			end
			ApplyNpcPortraitSource(npc)

			if isPlayerHero then
				local heroName = playerHeroName
				if usedNames[heroName] then
					heroName = GetUniqueNpcName(usedNames, heroName, i)
				else
					usedNames[heroName] = true
				end
				SetNpcDisplayName(npc, heroName, i)
			elseif isRegisseuse then
				local guideName = NPC_REGISSEUSE_NAME
				if usedNames[guideName] then
					guideName = GetUniqueNpcName(usedNames, guideName, i)
				else
					usedNames[guideName] = true
				end
				SetNpcDisplayName(npc, guideName, i)
			else
				local uniqueName = GetUniqueNpcName(usedNames, persisted and persisted.name or nil, i)
				SetNpcDisplayName(npc, uniqueName, i)
			end
			if isRegisseuse then
				npc.needs = {
					social = 100,
					fatigue = 100,
					faim = 100,
					distraction = 100,
				}
				npc.needsSpeedFactor = 1
			else
				SetNpcNeeds(npc, persisted and persisted.needs or nil)
			end
			QueuePersistedActivityRestore(npc, persisted)
			QueuePersistedIntentRestore(npc, persisted)

			local restoredPosition = false
			if persistedCanRestorePosition then
				local pu = tonumber(persisted and persisted.u)
				local pv = tonumber(persisted and persisted.v)
				if pu and pv then
					local u = Clamp(pu, 0, 1)
					local v = Clamp(pv, 0, 1)
					if IsPointWalkable(u, v) then
						npc.u = u
						npc.v = v
						restoredPosition = true
					end
				end
			end

			if navCache.hasRoutes or navCache.hasPlazas then
				if not restoredPosition then
					local u, v = PickNpcSpawnPoint()
					npc.u = u
					npc.v = v
				end
				if isRegisseuse then
					if routeRegieU and routeRegieV then
						npc.regieCenterU = routeRegieU
						npc.regieCenterV = routeRegieV
					else
						local persistedCenterU = tonumber(persisted and persisted.regieCenterU)
						local persistedCenterV = tonumber(persisted and persisted.regieCenterV)
						if persistedCenterU and persistedCenterV then
							npc.regieCenterU = Clamp(persistedCenterU, 0, 1)
							npc.regieCenterV = Clamp(persistedCenterV, 0, 1)
						else
							npc.regieCenterU = Clamp(tonumber(npc.u) or 0.5, 0, 1)
							npc.regieCenterV = Clamp(tonumber(npc.v) or 0.5, 0, 1)
						end
					end
					npc.regieRadius = Clamp(tonumber(persisted and persisted.regieRadius) or 0.040, 0.015, 0.090)
				end
				npc.navMode = "walkable"
				npc.walkHeading = nil
				npc.walkTurnIn = nil
				npc.walkDesiredHeading = nil
				npc.walkDesiredIn = nil
				npc.walkTurnRate = nil
				npc.walkSpeedTarget = nil
				npc.waitTimer = RandRange(0, NPC_WAIT_MAX * 0.45)
				npc.speed = RandRange(NPC_SPEED_MIN * 0.65, NPC_SPEED_MAX * 0.90)
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
				npc.lastSelfPauseZoneKey = nil
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
				npc.zoneShiftTargetKind = nil
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
			elseif not Npc_EnterAnyNavMode(npc, { smooth = true }) then
				Npc_PickTarget(npc)
			end
			npcPool[#npcPool + 1] = npc
		end
		ApplyPersistedActivityRestore()
		ApplyPersistedIntentRestore()
		npcPersistenceTimer = NPC_PERSIST_SAVE_INTERVAL
		npcPersistenceMapId = tostring(GetActiveMapId() or "default")
		npcSpatial.dirty = true
		npcSpatial.poiScanCursor = 1
	end

	function ReloadNpcPoolFromPersistence()
		local persistedLookup, persistedCanRestorePosition, persistedMeta = BuildPersistedNpcLookup()
		local persistedUpdatedAt = tonumber(type(persistedMeta) == "table" and persistedMeta.updatedAtServer or 0) or 0
		if persistedUpdatedAt <= 0 then
			persistedUpdatedAt = tonumber(type(persistedMeta) == "table" and persistedMeta.updatedAt or 0) or 0
		end
		if persistedUpdatedAt <= 0 then
			persistedUpdatedAt = GetEpochNow()
		end
		SetBootstrapPersistenceEpoch(persistedUpdatedAt)
		local playerHeroName = TrimNpcName(UnitName and UnitName("player") or nil) or NPC_PLAYER_HERO_NAME_FALLBACK
		local playerHeroAtlas = PickValidNpcAtlas()
		local routeRegieU, routeRegieV = nil, nil
		do
			local routesRoot = ns and ns.QuartierMiniature and ns.QuartierMiniature.Routes or nil
			local mapId = GetActiveMapId()
			local mapStore = nil
			if type(routesRoot) == "table" and type(routesRoot.maps) == "table" then
				mapStore = routesRoot.maps[mapId]
			else
				mapStore = routesRoot
			end
			local regie = type(mapStore) == "table" and mapStore.regisseuse or nil
			local ru = tonumber(regie and regie.u)
			local rv = tonumber(regie and regie.v)
			if ru and rv then
				routeRegieU = Clamp(ru, 0, 1)
				routeRegieV = Clamp(rv, 0, 1)
			end
		end
		if UnitRace and UnitSex then
			local _, raceFile = UnitRace("player")
			local sex = UnitSex("player")
			local sexKey = (sex == 3) and "female" or "male"
			local src = ns and ns.Data and ns.Data.SessionPresenceAtlas or nil
			local bucket = type(src) == "table" and type(src[sexKey]) == "table" and src[sexKey] or nil
			local atlas = bucket and raceFile and tostring(bucket[raceFile] or "") or ""
			if atlas ~= "" and IsAtlasUsable(atlas) then
				playerHeroAtlas = atlas
			end
		end
		if not IsAtlasUsable(playerHeroAtlas) then
			playerHeroAtlas = NPC_FALLBACK_ATLAS
		end
		local usedNames = {}
		for i = 1, #npcPool do
			local npc = npcPool[i]
			local isPlayerHero = tostring(npc and npc.persistentId or "") == NPC_PLAYER_HERO_ID or i == 1
			local isRegisseuse = tostring(npc and npc.persistentId or "") == NPC_REGISSEUSE_ID or i == 2
			local persisted = nil
			if isPlayerHero then
				persisted = persistedLookup.byId[NPC_PLAYER_HERO_ID] or persistedLookup.bySlot[i]
			elseif isRegisseuse then
				persisted = persistedLookup.byId[NPC_REGISSEUSE_ID] or persistedLookup.bySlot[i]
			else
				persisted = persistedLookup.bySlot[i]
			end
			if persisted and tostring(persisted.id or "") ~= "" then
				if isPlayerHero then
					npc.persistentId = NPC_PLAYER_HERO_ID
				elseif isRegisseuse then
					npc.persistentId = NPC_REGISSEUSE_ID
				else
					npc.persistentId = tostring(persisted.id)
				end
			elseif type(npc.persistentId) ~= "string" or npc.persistentId == "" then
				if isPlayerHero then
					npc.persistentId = NPC_PLAYER_HERO_ID
				elseif isRegisseuse then
					npc.persistentId = NPC_REGISSEUSE_ID
				else
					npc.persistentId = "npc_" .. tostring(i)
				end
			end

			if isPlayerHero then
				SetNpcDisplayName(npc, playerHeroName, i)
				npc.portraitAtlas = playerHeroAtlas
				npc.portraitUnit = "player"
				npc.portraitTexturePath = nil
				npc.playable = true
				npc.isRegisseuse = false
				ApplyNpcPortraitSource(npc)
				usedNames[playerHeroName] = true
			elseif isRegisseuse then
				SetNpcDisplayName(npc, NPC_REGISSEUSE_NAME, i)
				npc.portraitUnit = nil
				npc.portraitTexturePath = NPC_REGISSEUSE_PORTRAIT_TEXTURE
				npc.portraitFlipX = false
				ApplyNpcPortraitSource(npc)
				npc.playable = false
				npc.isRegisseuse = true
				npc.needs = {
					social = 100,
					fatigue = 100,
					faim = 100,
					distraction = 100,
				}
				npc.needsSpeedFactor = 1
				usedNames[NPC_REGISSEUSE_NAME] = true
			else
				npc.portraitUnit = nil
				npc.portraitTexturePath = nil
				local persistedAtlas = tostring(persisted and persisted.portraitAtlas or "")
				if persistedAtlas ~= "" and IsAtlasUsable(persistedAtlas) then
					npc.portraitAtlas = persistedAtlas
				elseif not IsAtlasUsable(npc.portraitAtlas) then
					npc.portraitAtlas = PickValidNpcAtlas()
				end
				if persisted and persisted.portraitFlipX ~= nil then
					npc.portraitFlipX = persisted.portraitFlipX == true
					ApplyNpcPortraitFlip(npc.frame, npc.portraitFlipX == true)
				end
				npc.playable = true
				npc.isRegisseuse = false
				local uniqueName = GetUniqueNpcName(usedNames, persisted and persisted.name or npc.displayName, i)
				SetNpcDisplayName(npc, uniqueName, i)
				ApplyNpcPortraitSource(npc)
			end
			if not isRegisseuse then
				SetNpcNeeds(npc, persisted and persisted.needs or npc.needs)
			end
			QueuePersistedActivityRestore(npc, persisted)
			QueuePersistedIntentRestore(npc, persisted)

			local restoredPosition = false
			if persistedCanRestorePosition then
				local pu = tonumber(persisted and persisted.u)
				local pv = tonumber(persisted and persisted.v)
				if pu and pv then
					local u = Clamp(pu, 0, 1)
					local v = Clamp(pv, 0, 1)
					if IsPointWalkable(u, v) then
						npc.u = u
						npc.v = v
						restoredPosition = true
					end
				end
			end
			if (not restoredPosition) and (navCache.hasRoutes or navCache.hasPlazas) then
				local u, v = PickNpcSpawnPoint()
				npc.u = u
				npc.v = v
			end
			if isRegisseuse then
				if routeRegieU and routeRegieV then
					npc.regieCenterU = routeRegieU
					npc.regieCenterV = routeRegieV
				else
					local persistedCenterU = tonumber(persisted and persisted.regieCenterU)
					local persistedCenterV = tonumber(persisted and persisted.regieCenterV)
					if persistedCenterU and persistedCenterV then
						npc.regieCenterU = Clamp(persistedCenterU, 0, 1)
						npc.regieCenterV = Clamp(persistedCenterV, 0, 1)
					else
						npc.regieCenterU = Clamp(tonumber(npc.u) or 0.5, 0, 1)
						npc.regieCenterV = Clamp(tonumber(npc.v) or 0.5, 0, 1)
					end
				end
				npc.regieRadius = Clamp(
					tonumber(persisted and persisted.regieRadius) or tonumber(npc.regieRadius) or 0.040,
					0.015,
					0.090
				)
				npc.regieTargetU = nil
				npc.regieTargetV = nil
				npc.regieWait = 0
				npc.regieSpeed =
					Clamp(tonumber(npc.regieSpeed) or (NPC_SPEED_MIN * 0.78), NPC_SPEED_MIN * 0.4, NPC_SPEED_MAX * 0.8)
			end
			npc.manualOrder = nil
			npc.manualOrderQueue = {}
			npc.autoOrderRollIn = GetNextNpcAutoIntentDelay()
			npc.poiVisitRollIn = RandRange(NPC_POI_ROLL_MIN, NPC_POI_ROLL_MAX)
			npc.poiVisitCooldown = 0
			npc.severeBlockIterations = 0
			npc.severeBlockEscalation = 0
			npc.lastSevereBlockAt = 0
		end
		ApplyPersistedActivityRestore()
		ApplyPersistedIntentRestore()
		npcPersistenceMapId = tostring(GetActiveMapId() or "default")
		npcSpatial.dirty = true
		npcSpatial.poiScanCursor = 1
	end
end

return Modules
