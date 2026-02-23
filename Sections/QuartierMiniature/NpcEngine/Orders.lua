local ADDON, ns = ...

ns.QuartierMiniatureNpcEngine = ns.QuartierMiniatureNpcEngine or {}
ns.QuartierMiniatureNpcEngine.Modules = ns.QuartierMiniatureNpcEngine.Modules or {}
local Modules = ns.QuartierMiniatureNpcEngine.Modules

function Modules.InstallOrders(ctx, moduleEnv)
	if type(ctx) ~= "table" or type(moduleEnv) ~= "table" then
		return nil
	end
	setfenv(1, moduleEnv)

function PickWeightedAutoOrder(candidates)
	if type(candidates) ~= "table" or #candidates < 1 then
		return nil
	end
	local totalWeight = 0
	for i = 1, #candidates do
		local w = tonumber(candidates[i] and candidates[i].weight) or 0
		if w > 0 then
			totalWeight = totalWeight + w
		end
	end
	if totalWeight <= NAV_EPS then
		return nil
	end
	local roll = math.random() * totalWeight
	local accum = 0
	for i = 1, #candidates do
		local entry = candidates[i]
		local w = tonumber(entry and entry.weight) or 0
		if w > 0 then
			accum = accum + w
			if roll <= accum then
				return entry
			end
		end
	end
	return candidates[#candidates]
end

function BuildNpcAutoOrderCandidates(npc)
	local out = {}
	if not npc then
		return out
	end
	local isNightPhase = IsNightPhase()
	local needs = type(npc.needs) == "table" and npc.needs or {}
	local fatigueReserve = Clamp(tonumber(needs.fatigue) or 0, 0, 100)
	local faimReserve = Clamp(tonumber(needs.faim) or 0, 0, 100)
	local distractionReserve = Clamp(tonumber(needs.distraction) or 0, 0, 100)
	local lowNeedsMax = 20
	local restTriggered = fatigueReserve <= lowNeedsMax
	local mealTriggered = faimReserve <= lowNeedsMax
	local distractionTriggered = distractionReserve <= lowNeedsMax
	local function AddCandidate(weight, entry)
		if type(entry) ~= "table" then
			return
		end
		local w = tonumber(weight) or 0
		local purpose = tostring(entry.purpose or "")
		if purpose ~= "" then
			if not IsPurposeAllowedNow(purpose) then
				return
			end
			local purposeWeight = GetTimeActionWeight(purpose)
			w = w * purposeWeight
		end
		if w <= NAV_EPS then
			return
		end
		entry.weight = w
		out[#out + 1] = entry
	end

	-- Small talk auto: trigger short conversations naturally when a valid nearby
	-- partner is available and auto-social is enabled.
	if NPC_AUTO_SOCIAL_ENABLED and type(FindEncounterCandidate) == "function" then
		local partner = FindEncounterCandidate(npc)
		if partner and partner ~= npc then
			local partnerId = tostring(partner.persistentId or "")
			if partnerId ~= "" then
				local socialReserve = Clamp(tonumber(needs.social) or 100, 0, 100)
				local urgency = 1.0 + ((100 - socialReserve) / 100) * 1.1
				AddCandidate(0.42 * urgency, {
					kind = "talk",
					partnerId = partnerId,
				})
			end
		end
	end

	-- Night rule: prioritize going home to sleep even when fatigue reserve is still high.
	-- This ensures "nuit => au dodo" behavior expected by game design.
	if isNightPhase then
		local nightRestTarget = Npc_FindLieuTargetPoint(npc, "chaumiere")
		if nightRestTarget then
			local nightUrgency = 1.35 + ((100 - fatigueReserve) / 100) * 1.65
			AddCandidate(2.80 * nightUrgency, {
				kind = "lieu_pause",
				lieuType = "chaumiere",
				purpose = "rest",
				targetU = nightRestTarget.u,
				targetV = nightRestTarget.v,
				nightForced = true,
			})
			return out
		end
	end

	local restTarget = restTriggered and Npc_FindLieuTargetPoint(npc, "chaumiere") or nil
	if restTriggered and restTarget then
		AddCandidate(1.00, {
			kind = "lieu_pause",
			lieuType = "chaumiere",
			purpose = "rest",
			targetU = restTarget.u,
			targetV = restTarget.v,
		})
	end

	local aubergeTarget = mealTriggered and Npc_FindLieuTargetPoint(npc, "auberge") or nil
	if mealTriggered and aubergeTarget then
		AddCandidate(1.00, {
			kind = "lieu_pause",
			lieuType = "auberge",
			purpose = "meal",
			targetU = aubergeTarget.u,
			targetV = aubergeTarget.v,
		})
	end

	local taverneTarget = distractionTriggered and Npc_FindLieuTargetPoint(npc, "taverne") or nil
	if distractionTriggered and taverneTarget then
		AddCandidate(1.00, {
			kind = "lieu_pause",
			lieuType = "taverne",
			purpose = "distraction",
			targetU = taverneTarget.u,
			targetV = taverneTarget.v,
		})
	end

	-- Besoins automatiques uniquement en zone 0..20%.
	if restTriggered or mealTriggered or distractionTriggered then
		return out
	end

	-- PNJ sans tache: choisir une place (pas un lieu/maison) et s'y deplacer.
	local moveTargetU, moveTargetV = nil, nil
	if navCache.hasPlazas then
		local nu = tonumber(npc.u) or 0.5
		local nv = tonumber(npc.v) or 0.5
		local plaza = nil
		local plazaDist = nil
		for i = 1, #navCache.plazas do
			local cand = navCache.plazas[i]
			if tostring(cand and cand.zoneGroup or "plaza") == "plaza" then
				local dist = select(1, DistancePointToPlaza(cand, nu, nv))
				if dist and ((not plazaDist) or dist < plazaDist) then
					plazaDist = dist
					plaza = cand
				end
			end
		end
		if plaza then
			for _ = 1, 24 do
				local u, v = PickRandomPointInPlaza(plaza)
				local zoneKey = select(1, GetZoneKeyAtPoint(u, v))
				if
					IsPointWalkable(u, v)
					and IsZoneEntryAllowed(npc, zoneKey, true)
					and Dist2Points(u, v, npc.u, npc.v) >= 0.0008
				then
					moveTargetU, moveTargetV = u, v
					break
				end
			end
			if not (moveTargetU and moveTargetV) then
				local cu = Clamp(tonumber(plaza.centerU) or 0.5, 0, 1)
				local cv = Clamp(tonumber(plaza.centerV) or 0.5, 0, 1)
				local key = select(1, GetZoneKeyAtPoint(cu, cv))
				if IsPointWalkable(cu, cv) and IsZoneEntryAllowed(npc, key, true) then
					moveTargetU, moveTargetV = cu, cv
				end
			end
		end
	end
	if not (moveTargetU and moveTargetV) then
		moveTargetU = nil
		moveTargetV = nil
	end
	if moveTargetU and moveTargetV then
		AddCandidate(1.00, {
			kind = "lieu_pause",
			lieuType = "",
			purpose = "move_place",
			targetU = moveTargetU,
			targetV = moveTargetV,
			waitSeconds = 0,
		})
	end

	-- PNJ sans tache: variante se promener vers un POI.
	-- Cooldown + distance mini pour forcer un vrai rapprochement.
	if navCache.hasPois and (tonumber(npc.poiVisitCooldown) or 0) <= 0 then
		local nu = tonumber(npc.u) or 0.5
		local nv = tonumber(npc.v) or 0.5
		local poiCandidates = {}
		local poiCount = #navCache.pois
		if poiCount > 0 then
			local scanMax = math.min(poiCount, math.max(8, math.min(NPC_POI_SCAN_MAX_PER_ROLL, 24)))
			local idx = math.floor(tonumber(npcSpatial.poiScanCursor) or 1)
			if idx < 1 or idx > poiCount then
				idx = 1
			end
			local maxD2 = NPC_POI_PICK_RADIUS * NPC_POI_PICK_RADIUS
			local minApproach2 = NPC_POI_OBSERVE_MIN_APPROACH * NPC_POI_OBSERVE_MIN_APPROACH
			for _ = 1, scanMax do
				local poi = navCache.pois[idx]
				local pu = tonumber(poi and poi.u)
				local pv = tonumber(poi and poi.v)
				if pu and pv then
					local d2 = Dist2Points(pu, pv, nu, nv)
					if d2 <= maxD2 and d2 >= math.max(0.00005, minApproach2) then
						local poiId = tostring(poi and poi.id or ("poi_" .. tostring(idx)))
						local score = d2 * GetNpcPoiRepeatPenalty(npc, poiId) * RandRange(0.92, 1.20)
						poiCandidates[#poiCandidates + 1] = {
							u = pu,
							v = pv,
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
			AddCandidate(1.00, {
				kind = "lieu_pause",
				lieuType = "",
				purpose = "observe_nature",
				targetU = bestPoi.u,
				targetV = bestPoi.v,
				poiId = bestPoi.poiId,
				waitSeconds = RandRange(NPC_POI_CONTEMPLATE_MIN, NPC_POI_CONTEMPLATE_MAX),
			})
		end
	end

	return out
end

function MakeManualTargetKey(u, v)
	return string.format("%.4f:%.4f", Clamp(tonumber(u) or 0, 0, 1), Clamp(tonumber(v) or 0, 0, 1))
end

function PushWaypoint(out, u, v, minStep2)
	if type(out) ~= "table" then
		return
	end
	local pu = Clamp(tonumber(u) or 0.5, 0, 1)
	local pv = Clamp(tonumber(v) or 0.5, 0, 1)
	local last = out[#out]
	if last then
		local lim2 = tonumber(minStep2) or 0
		if Dist2Points(last.u, last.v, pu, pv) <= lim2 then
			return
		end
	end
	out[#out + 1] = { u = pu, v = pv }
end

manualPathAuxCache = {
	signature = nil,
	nodesByKey = nil,
	edgesByKey = nil,
	plazaNodesByIndex = nil,
}

function SegmentIntersectsSegment(ax, ay, bx, by, cx, cy, dx, dy)
	local rX = bx - ax
	local rY = by - ay
	local sX = dx - cx
	local sY = dy - cy
	local rxs = (rX * sY) - (rY * sX)
	local qpxr = ((cx - ax) * rY) - ((cy - ay) * rX)
	if math.abs(rxs) <= NAV_EPS and math.abs(qpxr) <= NAV_EPS then
		local rr = (rX * rX) + (rY * rY)
		if rr <= NAV_EPS then
			return false
		end
		local t0 = (((cx - ax) * rX) + ((cy - ay) * rY)) / rr
		local t1 = t0 + (((sX * rX) + (sY * rY)) / rr)
		local tMin = math.min(t0, t1)
		local tMax = math.max(t0, t1)
		return (tMax >= 0) and (tMin <= 1)
	end
	if math.abs(rxs) <= NAV_EPS then
		return false
	end
	local t = (((cx - ax) * sY) - ((cy - ay) * sX)) / rxs
	local u = (((cx - ax) * rY) - ((cy - ay) * rX)) / rxs
	return t >= 0 and t <= 1 and u >= 0 and u <= 1
end

function SegmentIntersectionParams(ax, ay, bx, by, cx, cy, dx, dy)
	local rX = bx - ax
	local rY = by - ay
	local sX = dx - cx
	local sY = dy - cy
	local rxs = (rX * sY) - (rY * sX)
	if math.abs(rxs) <= NAV_EPS then
		return false
	end
	local t = (((cx - ax) * sY) - ((cy - ay) * sX)) / rxs
	local u = (((cx - ax) * rY) - ((cy - ay) * rX)) / rxs
	if t < -NAV_EPS or t > (1 + NAV_EPS) or u < -NAV_EPS or u > (1 + NAV_EPS) then
		return false
	end
	t = Clamp(t, 0, 1)
	u = Clamp(u, 0, 1)
	local ix = ax + (rX * t)
	local iy = ay + (rY * t)
	return true, t, u, ix, iy
end

function SegmentTouchesPlaza(seg, plaza, tol)
	if not (seg and plaza) then
		return false
	end
	local threshold = tonumber(tol) or 0
	if IsPointInPlaza(plaza, seg.ax, seg.ay) or IsPointInPlaza(plaza, seg.bx, seg.by) then
		return true
	end
	if threshold > 0 then
		local da = select(1, DistancePointToPlaza(plaza, seg.ax, seg.ay))
		local db = select(1, DistancePointToPlaza(plaza, seg.bx, seg.by))
		if (da and da <= threshold) or (db and db <= threshold) then
			return true
		end
	end
	local midU = (seg.ax + seg.bx) * 0.5
	local midV = (seg.ay + seg.by) * 0.5
	if IsPointInPlaza(plaza, midU, midV) then
		return true
	end
	local points = plaza.points
	local n = points and #points or 0
	if n < 2 then
		return false
	end
	for i = 1, n do
		local a = points[i]
		local b = points[(i % n) + 1]
		if SegmentIntersectsSegment(seg.ax, seg.ay, seg.bx, seg.by, a.u, a.v, b.u, b.v) then
			return true
		end
	end
	return false
end

function EnsureManualPathAuxCache()
	local signature = tostring(navCache and navCache.signature or "")
	if
		manualPathAuxCache.signature == signature
		and type(manualPathAuxCache.nodesByKey) == "table"
		and type(manualPathAuxCache.edgesByKey) == "table"
		and type(manualPathAuxCache.plazaNodesByIndex) == "table"
	then
		return manualPathAuxCache
	end

	local nodesByKey = {}
	local edgesByKey = {}
	local plazaNodesByIndex = {}
	local connectDist = math.max(NPC_ROUTE_WALK_HALF_WIDTH * 1.85, NPC_PLAZA_TO_ROUTE_DIST * 0.95, 0.010)
	local plazaFactor = NPC_MANUAL_PATH_PLAZA_FACTOR

	local function EnsureGraphNode(key, u, v, refNode)
		local graphKey = tostring(key or "")
		if graphKey == "" then
			return nil
		end
		local node = nodesByKey[graphKey]
		if node then
			return node
		end
		if type(refNode) == "table" then
			node = refNode
		else
			node = {
				key = graphKey,
				u = Clamp(tonumber(u) or 0.5, 0, 1),
				v = Clamp(tonumber(v) or 0.5, 0, 1),
			}
		end
		nodesByKey[graphKey] = node
		return node
	end

	local function AddGraphEdgeByKeys(fromKey, toKey, cost)
		local aKey = tostring(fromKey or "")
		local bKey = tostring(toKey or "")
		local c = tonumber(cost) or math.huge
		if aKey == "" or bKey == "" or aKey == bKey or c <= NAV_EPS or c >= math.huge then
			return
		end
		local list = edgesByKey[aKey]
		if not list then
			list = {}
			edgesByKey[aKey] = list
		end
		for i = 1, #list do
			local edge = list[i]
			if edge and edge.key == bKey then
				if c < (tonumber(edge.cost) or math.huge) then
					edge.cost = c
				end
				return
			end
		end
		list[#list + 1] = {
			key = bKey,
			cost = c,
		}
	end

	local function AddGraphEdgeUndirected(nodeA, nodeB, cost)
		local a = nodeA and EnsureGraphNode(nodeA.key, nodeA.u, nodeA.v, nodeA) or nil
		local b = nodeB and EnsureGraphNode(nodeB.key, nodeB.u, nodeB.v, nodeB) or nil
		if not (a and b) then
			return
		end
		AddGraphEdgeByKeys(a.key, b.key, cost)
		AddGraphEdgeByKeys(b.key, a.key, cost)
	end

	local function AddNodePlaza(node, plazaIndex)
		local gNode = node and EnsureGraphNode(node.key, node.u, node.v, node) or nil
		if not gNode then
			return
		end
		local nodeKey = tostring(node and node.key or "")
		if nodeKey == "" or not plazaIndex then
			return
		end
		local list = plazaNodesByIndex[plazaIndex]
		if not list then
			list = {}
			plazaNodesByIndex[plazaIndex] = list
		end
		for i = 1, #list do
			local existing = list[i]
			if existing and tostring(existing.key or "") == nodeKey then
				return
			end
		end
		list[#list + 1] = gNode
	end

	for key, node in pairs(navCache.nodes or {}) do
		EnsureGraphNode(key, node and node.u, node and node.v, node)
	end

	-- Base graph: explicit route segments.
	for segIndex = 1, #navCache.segments do
		local seg = navCache.segments[segIndex]
		if seg and seg.nodeA and seg.nodeB and seg.len and seg.len > NAV_EPS then
			AddGraphEdgeUndirected(seg.nodeA, seg.nodeB, seg.len)
		end
	end

	-- Implicit route junctions (crossing segments without authored shared points).
	if #navCache.segments > 1 then
		for i = 1, #navCache.segments - 1 do
			local segA = navCache.segments[i]
			if segA and segA.nodeA and segA.nodeB and segA.len and segA.len > NAV_EPS then
				for j = i + 1, #navCache.segments do
					local segB = navCache.segments[j]
					if segB and segB.nodeA and segB.nodeB and segB.len and segB.len > NAV_EPS then
						local hit, tA, tB = SegmentIntersectionParams(
							segA.ax,
							segA.ay,
							segA.bx,
							segA.by,
							segB.ax,
							segB.ay,
							segB.bx,
							segB.by
						)
						if hit then
							local hopA0 = segA.len * tA
							local hopA1 = segA.len * (1 - tA)
							local hopB0 = segB.len * tB
							local hopB1 = segB.len * (1 - tB)
							local ix = segA.ax + ((segA.bx - segA.ax) * tA)
							local iy = segA.ay + ((segA.by - segA.ay) * tA)
							local ixKey = string.format("ix:%.4f:%.4f", ix, iy)
							local ixNode = EnsureGraphNode(ixKey, ix, iy, nil)
							AddGraphEdgeUndirected(ixNode, segA.nodeA, hopA0)
							AddGraphEdgeUndirected(ixNode, segA.nodeB, hopA1)
							AddGraphEdgeUndirected(ixNode, segB.nodeA, hopB0)
							AddGraphEdgeUndirected(ixNode, segB.nodeB, hopB1)
						end
					end
				end
			end
		end
	end

	-- Near-junction stitching: connect route endpoints that are visually connected
	-- but not authored with exactly matching coordinates.
	local routeNodeList = {}
	for _, node in pairs(navCache.nodes or {}) do
		if type(node) == "table" then
			routeNodeList[#routeNodeList + 1] = node
		end
	end
	local junctionDist = NPC_MANUAL_PATH_JUNCTION_DIST
	local strictDist = junctionDist * 0.65
	for i = 1, #routeNodeList - 1 do
		local nodeA = routeNodeList[i]
		local aLinks = #((nodeA and nodeA.links) or {})
		for j = i + 1, #routeNodeList do
			local nodeB = routeNodeList[j]
			local bLinks = #((nodeB and nodeB.links) or {})
			local d =
				math.sqrt(Dist2Points(nodeA and nodeA.u, nodeA and nodeA.v, nodeB and nodeB.u, nodeB and nodeB.v))
			if d > NAV_EPS and d <= junctionDist then
				-- Endpoints and simple junctions can bridge over a larger gap; complex
				-- interior nodes require a tighter proximity to avoid accidental shortcuts.
				if
					(d <= strictDist or aLinks <= 2 or bLinks <= 2)
					and IsSegmentOnStrictNetwork(
						nodeA and nodeA.u,
						nodeA and nodeA.v,
						nodeB and nodeB.u,
						nodeB and nodeB.v
					)
				then
					AddGraphEdgeUndirected(nodeA, nodeB, d * NPC_MANUAL_PATH_JUNCTION_PENALTY)
				end
			end
		end
	end

	-- Determine which route nodes belong to each plaza/lieu.
	if navCache.hasPlazas then
		for segIndex = 1, #navCache.segments do
			local seg = navCache.segments[segIndex]
			if seg and seg.nodeA and seg.nodeB then
				for plazaIndex = 1, #navCache.plazas do
					local plaza = navCache.plazas[plazaIndex]
					if SegmentTouchesPlaza(seg, plaza, connectDist) then
						AddNodePlaza(seg.nodeA, plazaIndex)
						AddNodePlaza(seg.nodeB, plazaIndex)
					end
				end
			end
		end

		for _, node in pairs(navCache.nodes or {}) do
			local nu = tonumber(node and node.u)
			local nv = tonumber(node and node.v)
			if nu and nv then
				for plazaIndex = 1, #navCache.plazas do
					local plaza = navCache.plazas[plazaIndex]
					local dist = select(1, DistancePointToPlaza(plaza, nu, nv))
					if dist and dist <= connectDist then
						AddNodePlaza(node, plazaIndex)
					end
				end
			end
		end
	end

	-- Add walk edges inside plazas/lieux, but only locally to avoid large
	-- straight shortcuts across a whole place.
	for plazaIndex = 1, #navCache.plazas do
		local nodes = plazaNodesByIndex[plazaIndex]
		if type(nodes) == "table" and #nodes > 1 then
			for a = 1, #nodes - 1 do
				local nodeA = nodes[a]
				for b = a + 1, #nodes do
					local nodeB = nodes[b]
					local d = math.sqrt(Dist2Points(nodeA.u, nodeA.v, nodeB.u, nodeB.v))
					if
						d > NAV_EPS
						and d <= NPC_MANUAL_PATH_PLAZA_EDGE_MAX_DIST
						and IsSegmentOnStrictNetwork(nodeA.u, nodeA.v, nodeB.u, nodeB.v)
					then
						AddGraphEdgeUndirected(nodeA, nodeB, d * plazaFactor)
					end
				end
			end
		end
	end

	-- Stitch consecutive plazas together when they are close enough and connected
	-- on the strict walk network. This enables natural traversal across multiple
	-- adjacent places without forcing a route segment hop in between.
	if navCache.hasPlazas and #navCache.plazas > 1 then
		local linkMaxDist = NPC_MANUAL_PATH_PLAZA_LINK_MAX_DIST
		local linkMaxDist2 = linkMaxDist * linkMaxDist
		for a = 1, #navCache.plazas - 1 do
			local nodesA = plazaNodesByIndex[a]
			if type(nodesA) == "table" and #nodesA > 0 then
				local plazaA = navCache.plazas[a]
				local aCenterU = tonumber(plazaA and plazaA.centerU) or 0.5
				local aCenterV = tonumber(plazaA and plazaA.centerV) or 0.5
				for b = a + 1, #navCache.plazas do
					local nodesB = plazaNodesByIndex[b]
					if type(nodesB) == "table" and #nodesB > 0 then
						local plazaB = navCache.plazas[b]
						local bCenterU = tonumber(plazaB and plazaB.centerU) or 0.5
						local bCenterV = tonumber(plazaB and plazaB.centerV) or 0.5
						local centerD2 = Dist2Points(aCenterU, aCenterV, bCenterU, bCenterV)
						-- Early reject for distant plazas.
						if centerD2 <= ((linkMaxDist * 8) * (linkMaxDist * 8)) then
							local bestA, bestB, bestD2 = nil, nil, math.huge
							for i = 1, #nodesA do
								local na = nodesA[i]
								local au = tonumber(na and na.u)
								local av = tonumber(na and na.v)
								if au and av then
									for j = 1, #nodesB do
										local nb = nodesB[j]
										local bu = tonumber(nb and nb.u)
										local bv = tonumber(nb and nb.v)
										if bu and bv then
											local d2 = Dist2Points(au, av, bu, bv)
											if d2 <= linkMaxDist2 and d2 < bestD2 then
												if IsSegmentOnStrictNetwork(au, av, bu, bv) then
													bestA = na
													bestB = nb
													bestD2 = d2
												end
											end
										end
									end
								end
							end
							if bestA and bestB and bestD2 < math.huge then
								local edgeCost = math.sqrt(bestD2) * NPC_MANUAL_PATH_PLAZA_LINK_PENALTY
								AddGraphEdgeUndirected(bestA, bestB, edgeCost)
							end
						end
					end
				end
			end
		end
	end

	manualPathAuxCache.signature = signature
	manualPathAuxCache.nodesByKey = nodesByKey
	manualPathAuxCache.edgesByKey = edgesByKey
	manualPathAuxCache.plazaNodesByIndex = plazaNodesByIndex
	return manualPathAuxCache
end

function BuildGraphNodePath(startNode, endNode)
	if not (startNode and endNode) then
		return nil, nil
	end
	local startKey = tostring(startNode.key or "")
	local endKey = tostring(endNode.key or "")
	if startKey == "" or endKey == "" then
		return nil, nil
	end
	if startKey == endKey then
		return { startNode }, 0
	end

	local open = {
		[startKey] = startNode,
	}
	local closed = {}
	local cameFrom = {}
	local gScore = {
		[startKey] = 0,
	}
	local fScore = {
		[startKey] = math.sqrt(Dist2Points(startNode.u, startNode.v, endNode.u, endNode.v)),
	}
	local auxCache = EnsureManualPathAuxCache()
	local nodesByKey = auxCache and auxCache.nodesByKey or nil
	local edgesByKey = auxCache and auxCache.edgesByKey or nil
	if type(nodesByKey) ~= "table" or type(edgesByKey) ~= "table" then
		return nil, nil
	end
	if not nodesByKey[startKey] then
		nodesByKey[startKey] = startNode
	end
	if not nodesByKey[endKey] then
		nodesByKey[endKey] = endNode
	end

	local maxIterations = math.max(64, (#navCache.segments * 10))
	local iter = 0
	while iter < maxIterations do
		iter = iter + 1

		local currentKey, currentNode, currentScore = nil, nil, nil
		for key, node in pairs(open) do
			local score = tonumber(fScore[key]) or math.huge
			if (not currentScore) or score < currentScore then
				currentKey = key
				currentNode = node
				currentScore = score
			end
		end
		if not currentNode then
			return nil, nil
		end
		if currentKey == endKey then
			local path = {}
			local walkKey = currentKey
			while walkKey do
				local node = nodesByKey[walkKey]
				if walkKey == startKey then
					node = startNode
				elseif walkKey == endKey then
					node = endNode
				end
				if not node then
					return nil, nil
				end
				path[#path + 1] = node
				walkKey = cameFrom[walkKey]
			end
			for i = 1, math.floor(#path * 0.5) do
				local j = (#path - i) + 1
				path[i], path[j] = path[j], path[i]
			end
			return path, tonumber(gScore[currentKey]) or 0
		end

		open[currentKey] = nil
		closed[currentKey] = true

		local edges = edgesByKey[currentKey]
		if type(edges) == "table" then
			for i = 1, #edges do
				local edge = edges[i]
				local neighborKey = tostring(edge and edge.key or "")
				local neighbor = neighborKey ~= "" and nodesByKey[neighborKey] or nil
				local edgeCost = tonumber(edge and edge.cost) or math.huge
				if neighbor and not closed[neighborKey] and edgeCost < math.huge then
					local tentative = (tonumber(gScore[currentKey]) or math.huge) + edgeCost
					if tentative < (tonumber(gScore[neighborKey]) or math.huge) then
						cameFrom[neighborKey] = currentKey
						gScore[neighborKey] = tentative
						local h = math.sqrt(Dist2Points(neighbor.u, neighbor.v, endNode.u, endNode.v))
						fScore[neighborKey] = tentative + h
						open[neighborKey] = neighbor
					end
				end
			end
		end
	end
	return nil, nil
end

function BuildManualOrderWaypoints(fromU, fromV, targetU, targetV)
	local tu = Clamp(tonumber(targetU) or 0.5, 0, 1)
	local tv = Clamp(tonumber(targetV) or 0.5, 0, 1)
	local fu = Clamp(tonumber(fromU) or tu, 0, 1)
	local fv = Clamp(tonumber(fromV) or tv, 0, 1)

	if not navCache.hasRoutes then
		if not IsSegmentOnStrictNetwork(fu, fv, tu, tv) then
			return nil
		end
		return {
			{ u = tu, v = tv },
		}
	end

	local auxCache = EnsureManualPathAuxCache()
	local plazaNodesByIndex = auxCache and auxCache.plazaNodesByIndex or nil

	local function ResolvePlazaIndexAtPoint(u, v)
		if not navCache.hasPlazas then
			return nil
		end
		for i = 1, #navCache.plazas do
			if IsPointInPlaza(navCache.plazas[i], u, v) then
				return i
			end
		end
		return nil
	end

	local function AddNodeOption(list, node, cost, entryU, entryV)
		if type(list) ~= "table" or type(node) ~= "table" then
			return
		end
		local key = tostring(node.key or "")
		local c = tonumber(cost) or math.huge
		if key == "" or c >= math.huge then
			return
		end
		for i = 1, #list do
			local opt = list[i]
			if opt and opt.key == key then
				if c < (tonumber(opt.cost) or math.huge) then
					opt.cost = c
					opt.node = node
					opt.entryU = entryU
					opt.entryV = entryV
				end
				return
			end
		end
		list[#list + 1] = {
			key = key,
			node = node,
			cost = c,
			entryU = entryU,
			entryV = entryV,
		}
	end

	local function BuildRouteAnchor(u, v)
		local near = FindNearestRoutePoint(u, v, 2.0, nil)
		if not near then
			return nil
		end
		local seg = navCache.segments[near.segIndex or 0]
		if not (seg and seg.len and seg.len > NAV_EPS and seg.nodeA and seg.nodeB) then
			return nil
		end
		local t = Clamp(tonumber(near.t) or 0.5, 0, 1)
		local px = Clamp(tonumber(near.px) or u, 0, 1)
		local py = Clamp(tonumber(near.py) or v, 0, 1)
		if not IsSegmentOnStrictNetwork(u, v, px, py) then
			return nil
		end
		local baseDist = math.sqrt(Dist2Points(u, v, px, py))
		return {
			seg = seg,
			segIndex = near.segIndex,
			t = t,
			px = px,
			py = py,
			baseDist = baseDist,
			optA = {
				node = seg.nodeA,
				cost = baseDist + (t * seg.len),
			},
			optB = {
				node = seg.nodeB,
				cost = baseDist + ((1 - t) * seg.len),
			},
		}
	end

	local function AddPlazaOptions(list, u, v, plazaIndex)
		local idx = plazaIndex or ResolvePlazaIndexAtPoint(u, v)
		if not idx then
			return nil
		end
		local nodes = plazaNodesByIndex and plazaNodesByIndex[idx] or nil
		if type(nodes) ~= "table" or #nodes < 1 then
			return idx
		end
		local ranked = {}
		for i = 1, #nodes do
			local node = nodes[i]
			local key = tostring(node and node.key or "")
			if key ~= "" then
				ranked[#ranked + 1] = {
					key = key,
					node = node,
					d2 = Dist2Points(u, v, node.u, node.v),
				}
			end
		end
		table.sort(ranked, function(a, b)
			return (tonumber(a and a.d2) or math.huge) < (tonumber(b and b.d2) or math.huge)
		end)
		local used = {}
		local maxPick = math.min(#ranked, NPC_MANUAL_PATH_MAX_PLAZA_ANCHORS)
		for i = 1, #ranked do
			if maxPick <= 0 then
				break
			end
			local row = ranked[i]
			if row and not used[row.key] then
				used[row.key] = true
				if IsSegmentOnStrictNetwork(u, v, row.node and row.node.u, row.node and row.node.v) then
					local dist = math.sqrt(tonumber(row.d2) or 0)
					AddNodeOption(list, row.node, dist * NPC_MANUAL_PATH_PLAZA_FACTOR, u, v)
					maxPick = maxPick - 1
				end
			end
		end
		return idx
	end

	local startPlazaIndex = ResolvePlazaIndexAtPoint(fu, fv)
	local endPlazaIndex = ResolvePlazaIndexAtPoint(tu, tv)
	local startOptions = {}
	local endOptions = {}

	local startAnchor = BuildRouteAnchor(fu, fv)
	local endAnchor = BuildRouteAnchor(tu, tv)
	if startAnchor then
		AddNodeOption(
			startOptions,
			startAnchor.optA and startAnchor.optA.node,
			startAnchor.optA and startAnchor.optA.cost,
			startAnchor.px,
			startAnchor.py
		)
		AddNodeOption(
			startOptions,
			startAnchor.optB and startAnchor.optB.node,
			startAnchor.optB and startAnchor.optB.cost,
			startAnchor.px,
			startAnchor.py
		)
	end
	if endAnchor then
		AddNodeOption(
			endOptions,
			endAnchor.optA and endAnchor.optA.node,
			endAnchor.optA and endAnchor.optA.cost,
			endAnchor.px,
			endAnchor.py
		)
		AddNodeOption(
			endOptions,
			endAnchor.optB and endAnchor.optB.node,
			endAnchor.optB and endAnchor.optB.cost,
			endAnchor.px,
			endAnchor.py
		)
	end

	AddPlazaOptions(startOptions, fu, fv, startPlazaIndex)
	AddPlazaOptions(endOptions, tu, tv, endPlazaIndex)

	local best = nil
	local function SetBest(totalCost, nodes, meta)
		if (not best) or totalCost < best.totalCost then
			best = {
				totalCost = totalCost,
				nodes = nodes,
				meta = meta,
			}
		end
	end

	if startAnchor and endAnchor and startAnchor.segIndex == endAnchor.segIndex then
		local sameSegCost = startAnchor.baseDist
			+ (math.abs(startAnchor.t - endAnchor.t) * (tonumber(startAnchor.seg and startAnchor.seg.len) or 0))
			+ endAnchor.baseDist
		SetBest(sameSegCost, {}, { sameSeg = true, startAnchor = startAnchor, endAnchor = endAnchor })
	end

	for i = 1, #startOptions do
		local sOpt = startOptions[i]
		for j = 1, #endOptions do
			local eOpt = endOptions[j]
			if sOpt and eOpt and sOpt.node and eOpt.node then
				local nodePath, pathCost
				if sOpt.key == eOpt.key then
					nodePath, pathCost = { sOpt.node }, 0
				else
					nodePath, pathCost = BuildGraphNodePath(sOpt.node, eOpt.node)
				end
				if nodePath and pathCost then
					SetBest(
						(tonumber(sOpt.cost) or 0) + pathCost + (tonumber(eOpt.cost) or 0),
						nodePath,
						{ startOpt = sOpt, endOpt = eOpt }
					)
				end
			end
		end
	end

	if not best then
		return nil
	end

	local minStep2 = (math.max(NPC_SOCIAL_POST_TALK_ZONE_REACH * 0.45, 0.0025)) ^ 2
	local waypoints = {}
	local meta = best.meta or {}
	if meta.sameSeg and meta.startAnchor then
		PushWaypoint(waypoints, meta.startAnchor.px, meta.startAnchor.py, minStep2)
	elseif meta.startOpt and meta.startOpt.entryU and meta.startOpt.entryV then
		PushWaypoint(waypoints, meta.startOpt.entryU, meta.startOpt.entryV, minStep2)
	end
	if type(best.nodes) == "table" then
		for i = 1, #best.nodes do
			local node = best.nodes[i]
			PushWaypoint(waypoints, node and node.u, node and node.v, minStep2)
		end
	end
	if meta.sameSeg and meta.endAnchor then
		PushWaypoint(waypoints, meta.endAnchor.px, meta.endAnchor.py, minStep2)
	elseif meta.endOpt and meta.endOpt.entryU and meta.endOpt.entryV then
		PushWaypoint(waypoints, meta.endOpt.entryU, meta.endOpt.entryV, minStep2)
	end
	PushWaypoint(waypoints, tu, tv, minStep2)
	if #waypoints < 1 then
		waypoints[1] = { u = tu, v = tv }
	end
	return waypoints
end

function SmoothManualOrderWaypoints(points)
	if type(points) ~= "table" or #points < 2 then
		return points
	end
	local out = {}
	local minStep2 = (math.max(NPC_SOCIAL_POST_TALK_ZONE_REACH * 0.25, 0.0015)) ^ 2
	local smoothStep = math.max(NPC_MANUAL_PATH_SMOOTH_STEP, 0.004)
	local first = points[1]
	PushWaypoint(out, first and first.u, first and first.v, minStep2)
	for i = 1, #points - 1 do
		local a = points[i]
		local b = points[i + 1]
		local ax = Clamp(tonumber(a and a.u) or 0.5, 0, 1)
		local ay = Clamp(tonumber(a and a.v) or 0.5, 0, 1)
		local bx = Clamp(tonumber(b and b.u) or ax, 0, 1)
		local by = Clamp(tonumber(b and b.v) or ay, 0, 1)
		local segLen = math.sqrt(Dist2Points(ax, ay, bx, by))
		if segLen > NAV_EPS then
			local stepCount = math.floor(segLen / smoothStep)
			if stepCount > 0 then
				for s = 1, stepCount do
					local t = s / (stepCount + 1)
					local iu = ax + ((bx - ax) * t)
					local iv = ay + ((by - ay) * t)
					if IsPointOnStrictNetwork(iu, iv) then
						PushWaypoint(out, iu, iv, minStep2)
					end
				end
			end
		end
		PushWaypoint(out, bx, by, minStep2)
	end
	return out
end

function ReduceWaypointCount(points, maxPoints)
	if type(points) ~= "table" then
		return points
	end
	local total = #points
	local maxCount = math.max(2, math.floor(tonumber(maxPoints) or total))
	if total <= maxCount then
		return points
	end
	local out = {}
	out[1] = points[1]
	local middleSlots = maxCount - 2
	if middleSlots > 0 then
		for i = 1, middleSlots do
			local t = i / (middleSlots + 1)
			local srcIndex = 1 + math.floor(t * (total - 2))
			srcIndex = math.max(2, math.min(total - 1, srcIndex))
			out[#out + 1] = points[srcIndex]
		end
	end
	out[#out + 1] = points[total]
	return out
end

function FindNearestWaypointIndex(points, u, v, startIndex)
	if type(points) ~= "table" or #points < 1 then
		return 1
	end
	local from = math.max(1, math.floor(tonumber(startIndex) or 1))
	if from > #points then
		from = #points
	end
	local pu = Clamp(tonumber(u) or 0.5, 0, 1)
	local pv = Clamp(tonumber(v) or 0.5, 0, 1)
	local bestI, bestD2 = from, math.huge
	for i = from, #points do
		local p = points[i]
		local d2 = Dist2Points(p and p.u, p and p.v, pu, pv)
		if d2 < bestD2 then
			bestD2 = d2
			bestI = i
		end
	end
	return bestI
end

function Npc_ApplyManualWaypointTarget(npc, order, targetU, targetV, targetKind, minTimer)
	if not (npc and type(order) == "table") then
		return
	end
	local tu = Clamp(tonumber(targetU) or (tonumber(npc.u) or 0.5), 0, 1)
	local tv = Clamp(tonumber(targetV) or (tonumber(npc.v) or 0.5), 0, 1)
	local targetKey = MakeManualTargetKey(tu, tv)
	if order.freeMove == true then
		order.pathWaypoints = {
			{
				u = tu,
				v = tv,
			},
		}
		order.pathIndex = 1
		order.pathLastDist2 = nil
		order.pathTargetKey = targetKey
		order.pathNavSignature = navCache.signature
		order.pathCheckAt = NowSec()
		npc.zoneShiftTargetU = tu
		npc.zoneShiftTargetV = tv
		npc.zoneShiftTargetKind = targetKind
		npc.zoneShiftTimer = math.max(tonumber(npc.zoneShiftTimer) or 0, tonumber(minTimer) or 24)
		return
	end
	local needsRebuild = false
	if type(order.pathWaypoints) ~= "table" or #order.pathWaypoints < 1 then
		needsRebuild = true
	elseif tostring(order.pathNavSignature or "") ~= tostring(navCache.signature or "") then
		needsRebuild = true
	elseif tostring(order.pathTargetKey or "") ~= targetKey then
		needsRebuild = true
	end
	if needsRebuild then
		local rebuilt = BuildManualOrderWaypoints(npc.u, npc.v, tu, tv)
		if type(rebuilt) == "table" and #rebuilt > 0 then
			order.pathWaypoints =
				ReduceWaypointCount(SmoothManualOrderWaypoints(rebuilt), NPC_MANUAL_PATH_MAX_POINTS)
			order.pathIndex = FindNearestWaypointIndex(order.pathWaypoints, npc.u, npc.v, 1)
			order.pathLastDist2 = nil
		elseif type(order.pathWaypoints) ~= "table" or #order.pathWaypoints < 1 then
			-- If a walk graph exists but no path is found, keep target unresolved
			-- instead of forcing a direct-line fallback.
			npc.zoneShiftTargetU = nil
			npc.zoneShiftTargetV = nil
			npc.zoneShiftTargetKind = nil
			npc.zoneShiftTimer = 0
			order.pathWaypoints = nil
			order.pathIndex = nil
			order.pathLastDist2 = nil
			order.pathTargetKey = targetKey
			order.pathNavSignature = navCache.signature
			order.pathCheckAt = NowSec()
			return
		end
		order.pathTargetKey = targetKey
		order.pathNavSignature = navCache.signature
		order.pathCheckAt = NowSec()
	end

	local points = order.pathWaypoints
	if type(points) ~= "table" or #points < 1 then
		return
	end

	local idx = math.floor(tonumber(order.pathIndex) or 1)
	if idx < 1 then
		idx = 1
	elseif idx > #points then
		idx = #points
	end

	local reach = math.max(NPC_SOCIAL_POST_TALK_ZONE_REACH * 1.05, 0.010)
	local reach2 = reach * reach
	local wp = points[idx]
	local guard = 0
	while wp and idx < #points do
		if Dist2Points(npc.u, npc.v, wp.u, wp.v) > reach2 then
			break
		end
		idx = idx + 1
		wp = points[idx]
		guard = guard + 1
		if guard > 24 then
			break
		end
	end
	if not wp then
		wp = {
			u = tu,
			v = tv,
		}
		idx = #points
	end
	order.pathIndex = idx

	local wu = Clamp(tonumber(wp.u) or tu, 0, 1)
	local wv = Clamp(tonumber(wp.v) or tv, 0, 1)
	if not IsPointOnStrictNetwork(wu, wv) then
		local fallback = BuildManualOrderWaypoints(npc.u, npc.v, tu, tv)
		if type(fallback) == "table" and #fallback > 0 then
			order.pathWaypoints =
				ReduceWaypointCount(SmoothManualOrderWaypoints(fallback), NPC_MANUAL_PATH_MAX_POINTS)
			order.pathIndex = FindNearestWaypointIndex(order.pathWaypoints, npc.u, npc.v, 1)
			local fp = order.pathWaypoints[order.pathIndex or 1]
			wu = Clamp(tonumber(fp and fp.u) or tu, 0, 1)
			wv = Clamp(tonumber(fp and fp.v) or tv, 0, 1)
		else
			return
		end
	end
	local now = NowSec()
	local waypointDist2 = Dist2Points(npc.u, npc.v, wu, wv)
	local checkAt = tonumber(order.pathCheckAt) or now
	if (now - checkAt) >= NPC_MANUAL_PATH_REPLAN_INTERVAL then
		local prevDist2 = tonumber(order.pathLastDist2)
		local blocked = prevDist2 and waypointDist2 > (reach2 * 2.2) and waypointDist2 >= (prevDist2 * 0.995)
		if blocked and NPC_MANUAL_PATH_REALTIME_REPLAN then
			local rebuilt = BuildManualOrderWaypoints(npc.u, npc.v, tu, tv)
			if type(rebuilt) == "table" and #rebuilt > 0 then
				order.pathWaypoints =
					ReduceWaypointCount(SmoothManualOrderWaypoints(rebuilt), NPC_MANUAL_PATH_MAX_POINTS)
				order.pathIndex = FindNearestWaypointIndex(order.pathWaypoints, npc.u, npc.v, 1)
				local rp = order.pathWaypoints[order.pathIndex or 1]
				wu = Clamp(tonumber(rp and rp.u) or tu, 0, 1)
				wv = Clamp(tonumber(rp and rp.v) or tv, 0, 1)
				waypointDist2 = Dist2Points(npc.u, npc.v, wu, wv)
			end
		end
		order.pathLastDist2 = waypointDist2
		order.pathCheckAt = now
	end

	npc.zoneShiftTargetU = wu
	npc.zoneShiftTargetV = wv
	npc.zoneShiftTargetKind = targetKind
	npc.zoneShiftTimer = math.max(tonumber(npc.zoneShiftTimer) or 0, tonumber(minTimer) or 24)
end

function Npc_ResolveZoneShiftPath(npc)
	if not npc or type(npc.manualOrder) == "table" then
		return false
	end
	local goalU = tonumber(npc.zoneShiftGoalU) or tonumber(npc.zoneShiftTargetU)
	local goalV = tonumber(npc.zoneShiftGoalV) or tonumber(npc.zoneShiftTargetV)
	if not (goalU and goalV) then
		return false
	end
	npc.zoneShiftGoalU = goalU
	npc.zoneShiftGoalV = goalV
	local targetKey = MakeManualTargetKey(goalU, goalV)
	local needsRebuild = false
	if type(npc.zoneShiftPathWaypoints) ~= "table" or #npc.zoneShiftPathWaypoints < 1 then
		needsRebuild = true
	elseif tostring(npc.zoneShiftPathNavSignature or "") ~= tostring(navCache.signature or "") then
		needsRebuild = true
	elseif tostring(npc.zoneShiftPathTargetKey or "") ~= targetKey then
		needsRebuild = true
	end
	if needsRebuild then
		local rebuilt = BuildManualOrderWaypoints(npc.u, npc.v, goalU, goalV)
		if type(rebuilt) ~= "table" or #rebuilt < 1 then
			npc.zoneShiftPathWaypoints = nil
			npc.zoneShiftPathIndex = nil
			npc.zoneShiftPathTargetKey = targetKey
			npc.zoneShiftPathNavSignature = navCache.signature
			npc.zoneShiftTargetU = goalU
			npc.zoneShiftTargetV = goalV
			return true
		end
		npc.zoneShiftPathWaypoints =
			ReduceWaypointCount(SmoothManualOrderWaypoints(rebuilt), NPC_ZONE_SHIFT_PATH_MAX_POINTS)
		npc.zoneShiftPathIndex = FindNearestWaypointIndex(npc.zoneShiftPathWaypoints, npc.u, npc.v, 1)
		npc.zoneShiftPathTargetKey = targetKey
		npc.zoneShiftPathNavSignature = navCache.signature
	end
	local points = npc.zoneShiftPathWaypoints
	if type(points) ~= "table" or #points < 1 then
		npc.zoneShiftTargetU = goalU
		npc.zoneShiftTargetV = goalV
		return true
	end
	local idx = math.max(1, math.floor(tonumber(npc.zoneShiftPathIndex) or 1))
	if idx > #points then
		idx = #points
	end
	local reach = math.max(NPC_SOCIAL_POST_TALK_ZONE_REACH * 1.05, 0.010)
	local reach2 = reach * reach
	local wp = points[idx]
	local guard = 0
	while wp and idx < #points and Dist2Points(npc.u, npc.v, wp.u, wp.v) <= reach2 do
		idx = idx + 1
		wp = points[idx]
		guard = guard + 1
		if guard > 24 then
			break
		end
	end
	npc.zoneShiftPathIndex = idx
	local active = points[idx]
	if active then
		npc.zoneShiftTargetU = Clamp(tonumber(active.u) or goalU, 0, 1)
		npc.zoneShiftTargetV = Clamp(tonumber(active.v) or goalV, 0, 1)
	else
		npc.zoneShiftTargetU = goalU
		npc.zoneShiftTargetV = goalV
	end
	return true
end

function Npc_AdvanceZoneShiftPath(npc)
	if not npc then
		return false
	end
	local points = npc.zoneShiftPathWaypoints
	if type(points) ~= "table" or #points < 1 then
		return false
	end
	local idx = math.max(1, math.floor(tonumber(npc.zoneShiftPathIndex) or 1)) + 1
	if idx <= #points then
		npc.zoneShiftPathIndex = idx
		local wp = points[idx]
		npc.zoneShiftTargetU = Clamp(tonumber(wp and wp.u) or (tonumber(npc.zoneShiftGoalU) or 0.5), 0, 1)
		npc.zoneShiftTargetV = Clamp(tonumber(wp and wp.v) or (tonumber(npc.zoneShiftGoalV) or 0.5), 0, 1)
		return true
	end
	local goalU = tonumber(npc.zoneShiftGoalU)
	local goalV = tonumber(npc.zoneShiftGoalV)
	if goalU and goalV then
		local curU = tonumber(npc.zoneShiftTargetU)
		local curV = tonumber(npc.zoneShiftTargetV)
		if curU and curV and Dist2Points(curU, curV, goalU, goalV) <= (NAV_EPS * NAV_EPS) then
			return false
		end
		npc.zoneShiftPathIndex = #points
		npc.zoneShiftTargetU = goalU
		npc.zoneShiftTargetV = goalV
		return true
	end
	return false
end

TryJoinConversation = function(source, target, conversationGroupId, orderSource)
	if not (source and target) then
		return false, "npc_not_found"
	end
	if source == target then
		return false, "same_npc"
	end
	if not IsSocialPartnerValid(source, target) then
		return false, "invalid_partner"
	end
	local gid = tostring(conversationGroupId or "")
	if gid == "" then
		gid = tostring(target.conversationGroupId or "")
	end
	local targetState = tostring(target.behaviorState or "")
	if gid == "" or not IsConversationState(targetState) then
		return false, "target_not_in_conversation"
	end
	local members = GetConversationMembers(gid)
	local alreadyInGroup = false
	for i = 1, #members do
		if members[i] == source then
			alreadyInGroup = true
			break
		end
	end
	if (not alreadyInGroup) and #members >= NPC_CONVERSATION_MAX_PARTICIPANTS then
		return false, "conversation_full"
	end
	local talkSource = tostring(orderSource or "player")
	if talkSource == "" then
		talkSource = "player"
	end
	local sx = tonumber(source.u) or 0.5
	local sy = tonumber(source.v) or 0.5
	local tx = tonumber(target.u) or sx
	local ty = tonumber(target.v) or sy
	local triggerDist = math.max(NPC_SOCIAL_ENCOUNTER_RADIUS * 1.15, NPC_SOCIAL_APPROACH_STOP_DIST * 1.55)
	local triggerDist2 = triggerDist * triggerDist
	local nearEnough = Dist2Points(sx, sy, tx, ty) <= triggerDist2

	Npc_BreakCurrentSocialLink(source)
	Npc_ClearZoneShiftTarget(source)
	if nearEnough then
		if Npc_BeginDiscussionPair(source, target, RandRange(NPC_SOCIAL_DISCUSS_MIN, NPC_SOCIAL_DISCUSS_MAX), talkSource, gid) then
			source.manualOrder = nil
			RebindConversationMembers(gid)
			return true, "ok"
		end
	end
	source.approachSource = talkSource
	source.behaviorState = "approach"
	source.behaviorPartner = target
	source.conversationGroupId = gid
	source.behaviorTimer = RandRange(8.0, 14.0)
	source.behaviorCooldown = 0
	source.duoTargetU = nil
	source.duoTargetV = nil
	source.manualOrder = nil
	RebindConversationMembers(gid)
	return true, "ok"
end

OrderNpcTalkWith = function(selector, targetSelector, forceImmediate, sourceTag)
	local source = FindNpcBySelector and select(1, FindNpcBySelector(selector)) or nil
	local target = FindNpcBySelector and select(1, FindNpcBySelector(targetSelector)) or nil
	if not (source and target) then
		return false, "npc_not_found"
	end
	if source == target then
		return false, "same_npc"
	end

	local sourceId = tostring(source.persistentId or "")
	local targetId = tostring(target.persistentId or "")
	if sourceId == "" or targetId == "" then
		return false, "invalid_id"
	end
	local orderSource = tostring(sourceTag or "player")
	if orderSource == "" then
		orderSource = "player"
	end
	if orderSource == "player" then
		PurgeNpcAutoOrdersForPlayer(source)
		PurgeNpcAutoOrdersForPlayer(target)
	end
	local sourceBusy = (type(source.manualOrder) == "table") or (GetNpcManualOrderQueueSize(source) > 0)
	if (forceImmediate ~= true) and sourceBusy then
		return EnqueueNpcManualOrder(source, {
			kind = "talk",
			partnerId = targetId,
			requestedAt = NowSec(),
			source = orderSource,
		})
	end
	if orderSource == "player" then
		Npc_ForceImmediatePlayerOrderState(source)
		Npc_ForceImmediatePlayerOrderState(target)
	end

	Npc_BreakCurrentSocialLink(source)
	Npc_BreakCurrentSocialLink(target)
	Npc_ClearZoneShiftTarget(source)
	Npc_ClearZoneShiftTarget(target)

	local sourceU = tonumber(source.u) or 0.5
	local sourceV = tonumber(source.v) or 0.5
	local targetU = tonumber(target.u) or 0.5
	local targetV = tonumber(target.v) or 0.5
	-- Point final de discussion force sur le PNJ cible (ancre).
	local meetU, meetV = targetU, targetV
	local zoneKey = select(1, GetZoneKeyAtPoint(meetU, meetV))
	if not (IsPointWalkable(meetU, meetV) and IsZoneEntryAllowed(source, zoneKey, true)) then
		meetU, meetV = nil, nil
	end
	if not meetU or not meetV then
		return false, "no_meet_point"
	end

	local expiresAt = (NowSec()) + 48
	local talkGroupId = GenerateConversationGroupId()
	source.manualOrder = {
		kind = "talk",
		partnerId = targetId,
		talkRole = "approach",
		meetU = meetU,
		meetV = meetV,
		talkGroupId = talkGroupId,
		expiresAt = expiresAt,
		source = orderSource,
	}
	target.manualOrder = {
		kind = "talk",
		partnerId = sourceId,
		talkRole = "anchor",
		holdPosition = true,
		holdU = targetU,
		holdV = targetV,
		meetU = meetU,
		meetV = meetV,
		talkGroupId = talkGroupId,
		expiresAt = expiresAt,
		source = orderSource,
	}

	Npc_ApplyManualWaypointTarget(source, source.manualOrder, meetU, meetV, "manual_talk", 24)
	Npc_ClearZoneShiftTarget(target)
	return true, "ok"
end

GetNpcConversationJoinInfo = function(sourceSelector, targetSelector)
	local source = FindNpcBySelector and select(1, FindNpcBySelector(sourceSelector)) or nil
	local target = FindNpcBySelector and select(1, FindNpcBySelector(targetSelector)) or nil
	if not (source and target) or source == target then
		return {
			canJoin = false,
			isConversation = false,
			count = 0,
			maxCount = NPC_CONVERSATION_MAX_PARTICIPANTS,
		}
	end
	local groupId, members = GetConversationGroupIdForNpc(target)
	if not groupId then
		return {
			canJoin = false,
			isConversation = false,
			count = 0,
			maxCount = NPC_CONVERSATION_MAX_PARTICIPANTS,
		}
	end
	local count = #members
	local alreadyIn = false
	for i = 1, count do
		if members[i] == source then
			alreadyIn = true
			break
		end
	end
	return {
		canJoin = alreadyIn or (count < NPC_CONVERSATION_MAX_PARTICIPANTS),
		isConversation = true,
		count = count,
		maxCount = NPC_CONVERSATION_MAX_PARTICIPANTS,
		alreadyInConversation = alreadyIn,
		groupId = groupId,
	}
end

OrderNpcJoinConversation = function(selector, targetSelector, forceImmediate, sourceTag)
	local source = FindNpcBySelector and select(1, FindNpcBySelector(selector)) or nil
	local target = FindNpcBySelector and select(1, FindNpcBySelector(targetSelector)) or nil
	if not (source and target) then
		return false, "npc_not_found"
	end
	if source == target then
		return false, "same_npc"
	end
	local targetId = tostring(target.persistentId or "")
	if targetId == "" then
		return false, "invalid_id"
	end
	local orderSource = tostring(sourceTag or "player")
	if orderSource == "" then
		orderSource = "player"
	end
	local joinInfo = GetNpcConversationJoinInfo(selector, targetSelector)
	if not joinInfo.isConversation then
		return false, "target_not_in_conversation"
	end
	if (not joinInfo.alreadyInConversation) and (joinInfo.count >= NPC_CONVERSATION_MAX_PARTICIPANTS) then
		return false, "conversation_full"
	end
	if orderSource == "player" then
		-- Ordre joueur: priorite forte, on ecrase l'intention courante.
		PurgeNpcAutoOrdersForPlayer(source)
		Npc_ForceImmediatePlayerOrderState(source)
	else
		local sourceBusy = (type(source.manualOrder) == "table") or (GetNpcManualOrderQueueSize(source) > 0)
		if (forceImmediate ~= true) and sourceBusy then
			return EnqueueNpcManualOrder(source, {
				kind = "join_talk",
				partnerId = targetId,
				groupId = tostring(joinInfo.groupId or ""),
				requestedAt = NowSec(),
				source = orderSource,
			})
		end
	end
	local now = NowSec()
	local groupId = tostring(joinInfo.groupId or "")
	local targetU = tonumber(target.u) or 0.5
	local targetV = tonumber(target.v) or 0.5
	source.manualOrder = {
		kind = "join_talk",
		partnerId = targetId,
		groupId = groupId,
		meetU = targetU,
		meetV = targetV,
		meetRefreshAt = now,
		expiresAt = now + 48,
		source = orderSource,
	}
	Npc_ApplyManualWaypointTarget(source, source.manualOrder, targetU, targetV, "manual_talk", 24)
	return true, "ok"
end

function OrderNpcGoToLieuType(selector, lieuType, purpose)
	local npc = FindNpcBySelector and select(1, FindNpcBySelector(selector)) or nil
	if not npc then
		return false, "npc_not_found"
	end
	local wantedType = NormalizeLieuType(lieuType)
	if wantedType == "" then
		return false, "invalid_lieu_type"
	end

	local target = Npc_FindLieuTargetPoint(npc, wantedType, {
		allowFullFallback = false,
	})
	if not target then
		return false, "no_lieu_target"
	end
	PurgeNpcAutoOrdersForPlayer(npc)
	local entry = {
		kind = "lieu_pause",
		lieuType = wantedType,
		purpose = tostring(purpose or "rest"),
		targetU = target.u,
		targetV = target.v,
		expiresAt = (NowSec()) + 96,
		source = "player",
		requestedAt = NowSec(),
	}
	if not IsPurposeAllowedNow(entry.purpose) then
		return false, "purpose_blocked_by_time_phase"
	end
	if type(npc.manualOrder) == "table" or GetNpcManualOrderQueueSize(npc) > 0 then
		return EnqueueNpcManualOrder(npc, entry)
	end
	Npc_ForceImmediatePlayerOrderState(npc)
	npc.manualOrder = entry
	Npc_ApplyManualWaypointTarget(npc, npc.manualOrder, target.u, target.v, "manual_lieu", 36)
	return true, "ok"
end

function OrderNpcGoToPoint(selector, targetU, targetV, purpose, lieuType, waitSeconds)
	local npc = FindNpcBySelector and select(1, FindNpcBySelector(selector)) or nil
	if not npc then
		return false, "npc_not_found"
	end

	local tu = Clamp(tonumber(targetU) or 0.5, 0, 1)
	local tv = Clamp(tonumber(targetV) or 0.5, 0, 1)
	local requestedLieuType = NormalizeLieuType(lieuType)
	local forcedWaitSeconds = Clamp(tonumber(waitSeconds) or 0, 0, 600)
	if tostring(purpose or "") == "wait" and forcedWaitSeconds <= 0 then
		forcedWaitSeconds = 180
	end
	local zoneKey = select(1, GetZoneKeyAtPoint(tu, tv))
	if not (IsPointWalkable(tu, tv) and IsZoneEntryAllowed(npc, zoneKey, true)) then
		if requestedLieuType ~= "" then
			local fallback = Npc_FindLieuTargetPoint(npc, requestedLieuType, {
				allowFullFallback = false,
			})
			if not fallback then
				return false, "invalid_target"
			end
			tu = Clamp(tonumber(fallback.u) or tu, 0, 1)
			tv = Clamp(tonumber(fallback.v) or tv, 0, 1)
		else
			return false, "invalid_target"
		end
	end
	if requestedLieuType ~= "" then
		local clickedLieu, clickedIndex = GetLieuAtPoint(tu, tv)
		local isFull = select(1, IsLieuAtCapacityForNpc(clickedLieu, npc))
		if isFull then
			local fallback = Npc_FindLieuTargetPoint(npc, requestedLieuType, {
				excludeLieuId = GetLieuStableId(clickedLieu, clickedIndex),
				allowFullFallback = false,
			})
			if fallback then
				tu = Clamp(tonumber(fallback.u) or tu, 0, 1)
				tv = Clamp(tonumber(fallback.v) or tv, 0, 1)
			end
		end
	end
	PurgeNpcAutoOrdersForPlayer(npc)
	local entry = {
		kind = "lieu_pause",
		lieuType = requestedLieuType,
		purpose = tostring(purpose or "rest"),
		targetU = tu,
		targetV = tv,
		waitSeconds = forcedWaitSeconds,
		expiresAt = (NowSec()) + 96,
		source = "player",
		requestedAt = NowSec(),
	}
	if not IsPurposeAllowedNow(entry.purpose) then
		return false, "purpose_blocked_by_time_phase"
	end
	if type(npc.manualOrder) == "table" or GetNpcManualOrderQueueSize(npc) > 0 then
		return EnqueueNpcManualOrder(npc, entry)
	end
	Npc_ForceImmediatePlayerOrderState(npc)
	npc.manualOrder = entry
	Npc_ApplyManualWaypointTarget(npc, npc.manualOrder, tu, tv, "manual_lieu", 36)
	return true, "ok"
end

TryStartNextQueuedOrder = function(npc)
	if not npc or type(npc.manualOrder) == "table" then
		return false
	end
	local queueSize = GetNpcManualOrderQueueSize(npc)
	if queueSize < 1 then
		return false
	end
	local maxAttempts = math.min(queueSize, NPC_INTENT_QUEUE_MAX)
	for _ = 1, maxAttempts do
		local queued = PopNpcManualOrder(npc)
		if type(queued) == "table" then
			local kind = tostring(queued.kind or "")
			if kind == "talk" then
				local sourceId = tostring(npc.persistentId or "")
				local partnerId = tostring(queued.partnerId or "")
				local queuedSource = tostring(queued.source or "player")
				if queuedSource == "" then
					queuedSource = "player"
				end
				if sourceId ~= "" and partnerId ~= "" and sourceId ~= partnerId then
					local ok = OrderNpcTalkWith(sourceId, partnerId, true, queuedSource)
					if ok then
						return true
					end
				end
			elseif kind == "join_talk" then
				local sourceId = tostring(npc.persistentId or "")
				local partnerId = tostring(queued.partnerId or "")
				local queuedSource = tostring(queued.source or "player")
				if queuedSource == "" then
					queuedSource = "player"
				end
				if sourceId ~= "" and partnerId ~= "" and sourceId ~= partnerId then
					local ok = OrderNpcJoinConversation(sourceId, partnerId, true, queuedSource)
					if ok then
						return true
					end
				end
			elseif kind == "lieu_pause" and IsPurposeAllowedNow(tostring(queued.purpose or "")) then
				local tu = Clamp(tonumber(queued.targetU) or (tonumber(npc.u) or 0.5), 0, 1)
				local tv = Clamp(tonumber(queued.targetV) or (tonumber(npc.v) or 0.5), 0, 1)
				local wantedType = tostring(queued.lieuType or "")
				local queuedSource = tostring(queued.source or "player")
					local zoneKey = select(1, GetZoneKeyAtPoint(tu, tv))
					if not (IsPointWalkable(tu, tv) and IsZoneEntryAllowed(npc, zoneKey, true)) then
						if wantedType ~= "" then
							local fallback = Npc_FindLieuTargetPoint(npc, wantedType, { allowFullFallback = false })
							if fallback then
								tu = Clamp(tonumber(fallback.u) or tu, 0, 1)
								tv = Clamp(tonumber(fallback.v) or tv, 0, 1)
							end
						elseif queuedSource == "auto_poi" and tostring(queued.purpose or "") ~= "observe_nature" then
						-- POI libre hors zone marchable: rabattre vers le point marchable le plus proche.
						local nearRoute =
							FindNearestRoutePoint(tu, tv, math.max(0.02, NPC_POI_PICK_RADIUS * 1.5), nil)
						local nearPlaza = FindNearestPlaza(tu, tv, math.max(0.02, NPC_POI_PICK_RADIUS * 1.5))
						local routeD2 = nearRoute and tonumber(nearRoute.dist2) or math.huge
						local plazaD = nearPlaza and tonumber(nearPlaza.dist) or math.huge
						local plazaD2 = (plazaD < math.huge) and (plazaD * plazaD) or math.huge
						if routeD2 <= plazaD2 and nearRoute then
							tu = Clamp(tonumber(nearRoute.px) or tu, 0, 1)
							tv = Clamp(tonumber(nearRoute.py) or tv, 0, 1)
						elseif nearPlaza then
							tu = Clamp(tonumber(nearPlaza.u) or tu, 0, 1)
							tv = Clamp(tonumber(nearPlaza.v) or tv, 0, 1)
						end
					end
				end
				local finalZoneKey = select(1, GetZoneKeyAtPoint(tu, tv))
				if
					(IsPointWalkable(tu, tv) and IsZoneEntryAllowed(npc, finalZoneKey, true))
					or (
						(queuedSource == "auto" or queuedSource == "auto_poi")
						and tostring(queued.purpose or "") == "observe_nature"
					)
				then
					Npc_BreakCurrentSocialLink(npc)
					Npc_ClearZoneShiftTarget(npc)
					npc.manualOrder = {
						kind = "lieu_pause",
						lieuType = wantedType,
						purpose = tostring(queued.purpose or "rest"),
						targetU = tu,
						targetV = tv,
						waitSeconds = Clamp(tonumber(queued.waitSeconds) or 0, 0, 600),
						expiresAt = (NowSec()) + 96,
						source = queuedSource,
						freeMove = ((queuedSource == "auto" or queuedSource == "auto_poi") and tostring(
							queued.purpose or ""
						) == "observe_nature"),
					}
					Npc_ApplyManualWaypointTarget(npc, npc.manualOrder, tu, tv, "manual_lieu", 36)
					return true
				end
			end
		end
	end
	return false
end

function TryEnqueueNpcAutoOrder(npc)
	if not (npc and NPC_AUTO_INTENT_ENABLED) then
		return false
	end
	local autoQueued = GetNpcManualOrderQueueSizeBySource(npc, "auto")
	if autoQueued > NPC_AUTO_INTENT_MAX_QUEUE then
		RemoveNpcManualOrderQueueBySource(npc, "auto")
		autoQueued = 0
	end
	if type(npc.manualOrder) == "table" then
		return false
	end
	if GetNpcManualOrderQueueSize(npc) > 0 then
		return false
	end
	if autoQueued >= NPC_AUTO_INTENT_MAX_QUEUE then
		return false
	end
	local candidates = BuildNpcAutoOrderCandidates(npc)
	local picked = PickWeightedAutoOrder(candidates)
	if type(picked) ~= "table" then
		return false
	end
	local entry = {
		kind = tostring(picked.kind or ""),
		requestedAt = NowSec(),
		source = "auto",
	}
	if entry.kind ~= "lieu_pause" and entry.kind ~= "talk" then
		return false
	end
	if entry.kind == "talk" then
		entry.partnerId = tostring(picked.partnerId or "")
		if entry.partnerId == "" then
			return false
		end
		return EnqueueNpcManualOrder(npc, entry)
	end
	if entry.kind == "lieu_pause" then
		entry.lieuType = tostring(picked.lieuType or "")
		entry.purpose = tostring(picked.purpose or "rest")
		if not IsPurposeAllowedNow(entry.purpose) then
			return false
		end
		entry.poiId = tostring(picked.poiId or "")
		entry.nightForced = (picked.nightForced == true)
		entry.targetU = Clamp(tonumber(picked.targetU) or (tonumber(npc.u) or 0.5), 0, 1)
		entry.targetV = Clamp(tonumber(picked.targetV) or (tonumber(npc.v) or 0.5), 0, 1)
		entry.waitSeconds = Clamp(tonumber(picked.waitSeconds) or 0, 0, 600)
		local needs = type(npc and npc.needs) == "table" and npc.needs or {}
		local reserveValue = 100
		if actionRules and type(actionRules.GetReserveForPurpose) == "function" then
			reserveValue = Clamp(tonumber(actionRules.GetReserveForPurpose(needs, entry.purpose)) or 100, 0, 100)
		end
		local targetLieu = select(1, GetLieuAtPoint(entry.targetU, entry.targetV))
		local targetLieuType = string.lower(tostring(targetLieu and targetLieu.lieuType or ""))
		local canStart = true
		if actionRules and type(actionRules.CanAutoStartAction) == "function" then
			canStart = actionRules.CanAutoStartAction({
				source = entry.source,
				purpose = entry.purpose,
				reserve = reserveValue,
				targetLieuType = targetLieuType,
				orderLieuType = entry.lieuType,
			}) == true
		end
		if entry.nightForced == true and entry.purpose == "rest" then
			canStart = true
		end
		if not canStart then
			return false
		end
		local zoneKey = select(1, GetZoneKeyAtPoint(entry.targetU, entry.targetV))
		if not (IsPointWalkable(entry.targetU, entry.targetV) and IsZoneEntryAllowed(npc, zoneKey, true)) then
			if
				tostring(entry.source or "") == "auto"
				and tostring(entry.lieuType or "") == ""
				and entry.purpose == "observe_nature"
			then
				-- observe_nature auto: cible POI libre, hors contraintes de route.
				elseif
					tostring(entry.source or "") == "auto"
					and tostring(entry.lieuType or "") == ""
					and entry.purpose == "move_place"
				then
					return false
				else
					local fallback = Npc_FindLieuTargetPoint(npc, entry.lieuType, { allowFullFallback = false })
				if fallback then
					entry.targetU = Clamp(tonumber(fallback.u) or entry.targetU, 0, 1)
					entry.targetV = Clamp(tonumber(fallback.v) or entry.targetV, 0, 1)
				else
					return false
				end
			end
		end
		local queued = EnqueueNpcManualOrder(npc, entry)
		if queued and entry.purpose == "observe_nature" and tostring(entry.source or "") == "auto" then
			RegisterNpcRecentPoi(npc, entry.poiId)
			npc.poiVisitCooldown = RandRange(NPC_POI_COOLDOWN_MIN, NPC_POI_COOLDOWN_MAX)
		end
		return queued
	end
	return false
end

function UpdateNpcAutoOrderTimer(npc, dt)
	if not (npc and NPC_AUTO_INTENT_ENABLED) then
		return
	end
	local timer = (tonumber(npc.autoOrderRollIn) or GetNextNpcAutoIntentDelay()) - (tonumber(dt) or 0)
	if timer > 0 then
		npc.autoOrderRollIn = timer
		return
	end
	-- Rythme fixe: une tentative toutes les 5-12s.
	npc.autoOrderRollIn = GetNextNpcAutoIntentDelay()
	if type(npc.manualOrder) == "table" or GetNpcManualOrderQueueSize(npc) > 0 then
		return
	end
	local behaviorState = tostring(Npc_GetSocialState(npc) or "walk")
	local inZonePause = (tostring(npc.zoneRoutineStep or "") == "pause")
		and ((tonumber(npc.zoneRoutinePause) or 0) > 0.20)
	if
		behaviorState == "discussion"
		or behaviorState == "approach"
		or behaviorState == "self_pause"
		or inZonePause
	then
		return
	end
	TryEnqueueNpcAutoOrder(npc)
end


end

return Modules
