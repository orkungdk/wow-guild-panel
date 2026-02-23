local ADDON, ns = ...

ns.QuartierMiniatureNpcEngine = ns.QuartierMiniatureNpcEngine or {}
ns.QuartierMiniatureNpcEngine.Modules = ns.QuartierMiniatureNpcEngine.Modules or {}
local Modules = ns.QuartierMiniatureNpcEngine.Modules

function Modules.InstallNavigation(ctx, moduleEnv)
	if type(ctx) ~= "table" or type(moduleEnv) ~= "table" then
		return nil
	end
	setfenv(1, moduleEnv)

function NpcSpatialBuild()
	npcSpatial.cells = {}
	npcSpatial.enabled = true
	npcSpatial.cellSize = Clamp(tonumber(npcSpatial.cellSize) or NPC_SPATIAL_GRID_CELL, 0.015, 0.20)
	for i = 1, #npcPool do
		NpcSpatialAttach(npcPool[i])
	end
	npcSpatial.dirty = false
end

function ForEachNpcInRadius(u, v, radius, callback)
	if type(callback) ~= "function" then
		return false
	end
	local limit = math.max(0, tonumber(radius) or 0)
	if limit <= NAV_EPS then
		return false
	end
	if not npcSpatial.enabled then
		for i = 1, #npcPool do
			if callback(npcPool[i]) == true then
				return true
			end
		end
		return false
	end

	local cellSize = tonumber(npcSpatial.cellSize) or NPC_SPATIAL_GRID_CELL
	if cellSize <= NAV_EPS then
		for i = 1, #npcPool do
			if callback(npcPool[i]) == true then
				return true
			end
		end
		return false
	end

	local cu = Clamp(tonumber(u) or 0.5, 0, 1)
	local cv = Clamp(tonumber(v) or 0.5, 0, 1)
	local cx = math.floor(cu / cellSize)
	local cy = math.floor(cv / cellSize)
	local span = math.max(1, math.ceil(limit / cellSize))
	for x = cx - span, cx + span do
		for y = cy - span, cy + span do
			local key = NpcSpatialCellKey(x, y)
			local cell = npcSpatial.cells[key]
			if type(cell) == "table" then
				for i = 1, #cell do
					if callback(cell[i]) == true then
						return true
					end
				end
			end
		end
	end
	return false
end

function NormalizePoint(raw)
	return {
		u = Clamp(tonumber(raw and raw.u) or 0.5, 0, 1),
		v = Clamp(tonumber(raw and raw.v) or 0.5, 0, 1),
	}
end

function NodeKey(u, v)
	return string.format("%.4f:%.4f", u, v)
end

function BuildRoutesSignature(store)
	if type(store) ~= "table" then
		return "nil"
	end
	local parts = {
		"v:",
		tostring(tonumber(store.version) or 0),
	}
	local routes = type(store.routes) == "table" and store.routes or {}
	local plazas = type(store.plazas) == "table" and store.plazas or {}
	local lieux = type(store.lieux) == "table" and store.lieux or {}
	local pois = type(store.pois) == "table" and store.pois or {}
	parts[#parts + 1] = ";r:" .. tostring(#routes)
	for i = 1, #routes do
		local points = type(routes[i] and routes[i].points) == "table" and routes[i].points or {}
		parts[#parts + 1] = "|rp:" .. tostring(#points)
		for j = 1, #points do
			local p = points[j]
			parts[#parts + 1] = string.format(",%.4f,%.4f", tonumber(p and p.u) or 0, tonumber(p and p.v) or 0)
		end
	end
	parts[#parts + 1] = ";p:" .. tostring(#plazas)
	for i = 1, #plazas do
		local points = type(plazas[i] and plazas[i].points) == "table" and plazas[i].points or {}
		parts[#parts + 1] = "|pp:" .. tostring(#points)
		for j = 1, #points do
			local p = points[j]
			parts[#parts + 1] = string.format(",%.4f,%.4f", tonumber(p and p.u) or 0, tonumber(p and p.v) or 0)
		end
	end
	parts[#parts + 1] = ";l:" .. tostring(#lieux)
	for i = 1, #lieux do
		local lieu = lieux[i]
		local points = type(lieu and lieu.points) == "table" and lieu.points or {}
		parts[#parts + 1] = "|lp:" .. tostring(#points) .. ":" .. tostring(lieu and lieu.type or "chaumiere")
		for j = 1, #points do
			local p = points[j]
			parts[#parts + 1] = string.format(",%.4f,%.4f", tonumber(p and p.u) or 0, tonumber(p and p.v) or 0)
		end
		local entries = type(lieu and lieu.entries) == "table" and lieu.entries or {}
		parts[#parts + 1] = "|le:" .. tostring(#entries)
		for j = 1, #entries do
			local e = entries[j]
			local er = Clamp(tonumber(e and (e.radius or e.r)) or 0.010, 0.004, 0.040)
			parts[#parts + 1] = string.format(
				",%s,%.4f,%.4f,%.4f",
				tostring(e and e.id or ("entry_" .. j)),
				tonumber(e and e.u) or 0,
				tonumber(e and e.v) or 0,
				er
			)
		end
	end
	parts[#parts + 1] = ";o:" .. tostring(#pois)
	for i = 1, #pois do
		local p = pois[i]
		local routeId = tostring(p and p.routeId or "")
		local plazaId = tostring(p and p.plazaId or "")
		local lieuId = tostring(p and p.lieuId or "")
		parts[#parts + 1] = string.format(
			"|op:%.4f,%.4f,%s,%s,%s",
			tonumber(p and p.u) or 0,
			tonumber(p and p.v) or 0,
			routeId,
			plazaId,
			lieuId
		)
	end
	return table.concat(parts, "")
end

function BuildNavigationFromStore(store)
	local nav = {
		signature = "nil",
		segments = {},
		routeGrid = nil,
		nodes = {},
		routes = {},
		plazas = {},
		lieux = {},
		pois = {},
		hasRoutes = false,
		hasPlazas = false,
		hasLieux = false,
		hasPois = false,
	}
	local routeIdToIndex = {}

	local function EnsureNode(u, v)
		local key = NodeKey(u, v)
		local node = nav.nodes[key]
		if node then
			return node
		end
		node = {
			key = key,
			u = u,
			v = v,
			links = {},
		}
		nav.nodes[key] = node
		return node
	end

	if type(store) == "table" then
		local routes = type(store.routes) == "table" and store.routes or {}
		for i = 1, #routes do
			local points = type(routes[i] and routes[i].points) == "table" and routes[i].points or {}
			local routeInfo = {
				id = tostring(routes[i] and routes[i].id or ("route_" .. i)),
				segments = {},
			}
			local routeIndex = #nav.routes + 1
			local prev = nil
			for j = 1, #points do
				local p = NormalizePoint(points[j])
				if prev then
					local dx = p.u - prev.u
					local dy = p.v - prev.v
					local len = math.sqrt((dx * dx) + (dy * dy))
					if len > NAV_EPS then
						local nodeA = EnsureNode(prev.u, prev.v)
						local nodeB = EnsureNode(p.u, p.v)
						local segIndex = #nav.segments + 1
						local order = #routeInfo.segments + 1
						nav.segments[segIndex] = {
							ax = prev.u,
							ay = prev.v,
							bx = p.u,
							by = p.v,
							len = len,
							routeIndex = routeIndex,
							routeOrder = order,
							nodeA = nodeA,
							nodeB = nodeB,
						}
						routeInfo.segments[order] = segIndex
						nodeA.links[#nodeA.links + 1] = {
							segIndex = segIndex,
							t = 0,
							dir = 1,
						}
						nodeB.links[#nodeB.links + 1] = {
							segIndex = segIndex,
							t = 1,
							dir = -1,
						}
					end
				end
				prev = p
			end
			if #routeInfo.segments > 0 then
				nav.routes[routeIndex] = routeInfo
				routeIdToIndex[routeInfo.id] = routeIndex
			end
		end

		local function BuildRouteGrid()
			if #nav.segments < 1 then
				nav.routeGrid = nil
				return
			end
			local cellSize = Clamp(NPC_ROUTE_WALK_HALF_WIDTH * 2.6, 0.020, 0.080)
			local pad = math.max(NPC_ROUTE_WALK_HALF_WIDTH * 1.8, 0.018)
			local cells = {}
			for segIndex = 1, #nav.segments do
				local seg = nav.segments[segIndex]
				if seg then
					local minU = Clamp(math.min(seg.ax, seg.bx) - pad, 0, 1)
					local maxU = Clamp(math.max(seg.ax, seg.bx) + pad, 0, 1)
					local minV = Clamp(math.min(seg.ay, seg.by) - pad, 0, 1)
					local maxV = Clamp(math.max(seg.ay, seg.by) + pad, 0, 1)
					local x1 = math.floor(minU / cellSize)
					local x2 = math.floor(maxU / cellSize)
					local y1 = math.floor(minV / cellSize)
					local y2 = math.floor(maxV / cellSize)
					for x = x1, x2 do
						for y = y1, y2 do
							local key = tostring(x) .. ":" .. tostring(y)
							local list = cells[key]
							if not list then
								list = {}
								cells[key] = list
							end
							list[#list + 1] = segIndex
						end
					end
				end
			end
			nav.routeGrid = {
				cellSize = cellSize,
				cells = cells,
			}
		end

		BuildRouteGrid()

		local function ClosestPointOnSegLocal(u, v, ax, ay, bx, by)
			local dx = bx - ax
			local dy = by - ay
			local len2 = (dx * dx) + (dy * dy)
			if len2 <= NAV_EPS then
				local ox = u - ax
				local oy = v - ay
				return 0, ax, ay, (ox * ox) + (oy * oy)
			end
			local t = ((u - ax) * dx + (v - ay) * dy) / len2
			t = Clamp(t, 0, 1)
			local px = ax + (dx * t)
			local py = ay + (dy * t)
			local ox = u - px
			local oy = v - py
			return t, px, py, (ox * ox) + (oy * oy)
		end

		local pois = type(store.pois) == "table" and store.pois or {}
		for i = 1, #pois do
			local raw = pois[i]
			local p = NormalizePoint(raw)
			local forcedRouteIndex = routeIdToIndex[tostring(raw and raw.routeId or "")]
			local best = nil
			for segIndex = 1, #nav.segments do
				local seg = nav.segments[segIndex]
				if (not forcedRouteIndex) or seg.routeIndex == forcedRouteIndex then
					local t, px, py, dist2 = ClosestPointOnSegLocal(p.u, p.v, seg.ax, seg.ay, seg.bx, seg.by)
					if not best or dist2 < best.dist2 then
						best = {
							segIndex = segIndex,
							routeIndex = seg.routeIndex,
							t = t,
							u = px,
							v = py,
							dist2 = dist2,
						}
					end
				end
			end
			nav.pois[#nav.pois + 1] = {
				id = tostring(raw and raw.id or ("poi_" .. i)),
				u = best and best.u or p.u,
				v = best and best.v or p.v,
				segIndex = best and best.segIndex or nil,
				routeIndex = best and best.routeIndex or nil,
				t = best and best.t or nil,
			}
		end

		local function AppendAreaPolygon(rawPoints, zoneGroup, areaId, lieuType)
			local points = type(rawPoints) == "table" and rawPoints or {}
			if #points < 3 then
				return nil
			end
			local poly = {}
			local minU, maxU = 1, 0
			local minV, maxV = 1, 0
			local sumU, sumV = 0, 0
			for j = 1, #points do
				local p = NormalizePoint(points[j])
				poly[#poly + 1] = p
				minU = math.min(minU, p.u)
				maxU = math.max(maxU, p.u)
				minV = math.min(minV, p.v)
				maxV = math.max(maxV, p.v)
				sumU = sumU + p.u
				sumV = sumV + p.v
			end
			return {
				points = poly,
				minU = minU,
				maxU = maxU,
				minV = minV,
				maxV = maxV,
				centerU = sumU / #poly,
				centerV = sumV / #poly,
				zoneGroup = zoneGroup or "plaza",
				id = areaId,
				lieuType = lieuType,
			}
		end

		local plazas = type(store.plazas) == "table" and store.plazas or {}
		for i = 1, #plazas do
			local plaza = plazas[i]
			local area = AppendAreaPolygon(
				plaza and plaza.points,
				"plaza",
				tostring(plaza and plaza.id or ("place_" .. i)),
				nil
			)
			if area then
				nav.plazas[#nav.plazas + 1] = area
			end
		end

		local lieux = type(store.lieux) == "table" and store.lieux or {}
		for i = 1, #lieux do
			local lieu = lieux[i]
			local area = AppendAreaPolygon(
				lieu and lieu.points,
				"lieu",
				tostring(lieu and lieu.id or ("lieu_" .. i)),
				tostring(lieu and lieu.type or "chaumiere")
			)
			if area then
				local rawEntries = type(lieu and lieu.entries) == "table" and lieu.entries or {}
				local entries = {}
				for j = 1, #rawEntries do
					local rawEntry = rawEntries[j]
					local p = NormalizePoint(rawEntry)
					entries[#entries + 1] = {
						id = tostring(rawEntry and rawEntry.id or ("entry_" .. j)),
						u = p.u,
						v = p.v,
						radius = Clamp(
							tonumber(rawEntry and (rawEntry.radius or rawEntry.r)) or 0.010,
							0.004,
							0.040
						),
					}
				end
				area.entries = entries
				nav.lieux[#nav.lieux + 1] = area
				-- Lieux are also walkable areas for pathing and zone actions.
				nav.plazas[#nav.plazas + 1] = area
			end
		end
	end

	nav.hasRoutes = (#nav.segments > 0)
	nav.hasPlazas = (#nav.plazas > 0)
	nav.hasLieux = (#nav.lieux > 0)
	nav.hasPois = (#nav.pois > 0)
	return nav
end

function IsPointOnSegment(u, v, ax, ay, bx, by, tol)
	local dx = bx - ax
	local dy = by - ay
	local len2 = (dx * dx) + (dy * dy)
	if len2 <= NAV_EPS then
		return false
	end
	local t = ((u - ax) * dx + (v - ay) * dy) / len2
	if t < 0 or t > 1 then
		return false
	end
	local px = ax + (dx * t)
	local py = ay + (dy * t)
	local ox = u - px
	local oy = v - py
	local threshold = (tol or 0.001)
	return ((ox * ox) + (oy * oy)) <= (threshold * threshold)
end

function ClosestPointOnSegment(u, v, ax, ay, bx, by)
	local dx = bx - ax
	local dy = by - ay
	local len2 = (dx * dx) + (dy * dy)
	if len2 <= NAV_EPS then
		local ox = u - ax
		local oy = v - ay
		return 0, ax, ay, (ox * ox) + (oy * oy)
	end
	local t = ((u - ax) * dx + (v - ay) * dy) / len2
	t = Clamp(t, 0, 1)
	local px = ax + (dx * t)
	local py = ay + (dy * t)
	local ox = u - px
	local oy = v - py
	return t, px, py, (ox * ox) + (oy * oy)
end

function IsPointInPlaza(plaza, u, v)
	if not plaza then
		return false
	end
	if u < plaza.minU or u > plaza.maxU or v < plaza.minV or v > plaza.maxV then
		return false
	end
	local points = plaza.points
	local n = points and #points or 0
	if n < 3 then
		return false
	end

	for i = 1, n do
		local a = points[i]
		local b = points[(i % n) + 1]
		if IsPointOnSegment(u, v, a.u, a.v, b.u, b.v, 0.0015) then
			return true
		end
	end

	local inside = false
	local j = n
	for i = 1, n do
		local pi = points[i]
		local pj = points[j]
		local yi = pi.v
		local yj = pj.v
		local intersects = ((yi > v) ~= (yj > v))
		if intersects then
			local denom = yj - yi
			if math.abs(denom) < NAV_EPS then
				denom = (denom < 0) and -NAV_EPS or NAV_EPS
			end
			local xAtY = ((pj.u - pi.u) * (v - yi) / denom) + pi.u
			if u < xAtY then
				inside = not inside
			end
		end
		j = i
	end
	return inside
end

function PickRandomPointInPlaza(plaza)
	if not plaza then
		return RandomWorldCoord(), RandomWorldCoord()
	end
	for _ = 1, 48 do
		local u = RandRange(plaza.minU, plaza.maxU)
		local v = RandRange(plaza.minV, plaza.maxV)
		if IsPointInPlaza(plaza, u, v) then
			return u, v
		end
	end
	return plaza.centerU, plaza.centerV
end

function DistancePointToPlaza(plaza, u, v)
	if not plaza then
		return nil, nil, nil
	end
	if IsPointInPlaza(plaza, u, v) then
		return 0, u, v
	end
	local points = plaza.points
	local n = points and #points or 0
	if n < 3 then
		return nil, nil, nil
	end
	local bestDist2 = math.huge
	local bestU, bestV = nil, nil
	for i = 1, n do
		local a = points[i]
		local b = points[(i % n) + 1]
		local _, px, py, dist2 = ClosestPointOnSegment(u, v, a.u, a.v, b.u, b.v)
		if dist2 < bestDist2 then
			bestDist2 = dist2
			bestU, bestV = px, py
		end
	end
	return math.sqrt(bestDist2), bestU, bestV
end

function IsPointInAnyPlaza(u, v, exceptIndex)
	if not navCache.hasPlazas then
		return false
	end
	local pu = tonumber(u)
	local pv = tonumber(v)
	if not pu or not pv then
		return false
	end
	for i = 1, #navCache.plazas do
		if (not exceptIndex) or i ~= exceptIndex then
			if IsPointInPlaza(navCache.plazas[i], pu, pv) then
				return true
			end
		end
	end
	return false
end

function FindPlazaEdgeInfoAtPoint(u, v, maxEdgeDist)
	if not navCache.hasPlazas then
		return nil
	end
	local maxDist = tonumber(maxEdgeDist) or NPC_SELF_PAUSE_EDGE_MAX_DIST
	local best = nil
	for i = 1, #navCache.plazas do
		local plaza = navCache.plazas[i]
		if IsPointInPlaza(plaza, u, v) then
			local points = plaza.points
			local n = points and #points or 0
			if n >= 3 then
				local bestDist2 = math.huge
				local edgeU, edgeV = nil, nil
				for j = 1, n do
					local a = points[j]
					local b = points[(j % n) + 1]
					local _, px, py, dist2 = ClosestPointOnSegment(u, v, a.u, a.v, b.u, b.v)
					if dist2 < bestDist2 then
						bestDist2 = dist2
						edgeU, edgeV = px, py
					end
				end
				local dist = math.sqrt(bestDist2)
				if dist <= maxDist and (not best or dist < best.dist) then
					best = {
						plazaIndex = i,
						dist = dist,
						edgeU = edgeU,
						edgeV = edgeV,
						centerU = plaza.centerU,
						centerV = plaza.centerV,
					}
				end
			end
		end
	end
	return best
end

function BuildSelfPauseZoneKey(edgeInfo)
	if type(edgeInfo) ~= "table" then
		return nil
	end
	local plazaIndex = tonumber(edgeInfo.plazaIndex) or 0
	local edgeU = tonumber(edgeInfo.edgeU)
	local edgeV = tonumber(edgeInfo.edgeV)
	if not edgeU or not edgeV then
		return tostring(plazaIndex)
	end
	local cell = NPC_SELF_PAUSE_ZONE_CELL
	local qx = math.floor((edgeU / cell) + 0.5)
	local qy = math.floor((edgeV / cell) + 0.5)
	return tostring(plazaIndex) .. ":" .. tostring(qx) .. ":" .. tostring(qy)
end

function FindNearestRoutePoint(u, v, maxDist, excludeSegIndex)
	local maxDist2 = maxDist * maxDist
	local best = nil
	local function ScanSegment(segIndex)
		if segIndex == excludeSegIndex then
			return
		end
		local seg = navCache.segments[segIndex]
		if not seg then
			return
		end
		local t, px, py, dist2 = ClosestPointOnSegment(u, v, seg.ax, seg.ay, seg.bx, seg.by)
		if dist2 <= maxDist2 and (not best or dist2 < best.dist2) then
			best = {
				segIndex = segIndex,
				t = t,
				px = px,
				py = py,
				dist2 = dist2,
			}
		end
	end

	local grid = navCache.routeGrid
	local checkedWithGrid = false
	if type(grid) == "table" and type(grid.cells) == "table" then
		local cellSize = tonumber(grid.cellSize) or 0
		local limit = tonumber(maxDist) or 0
		if cellSize > NAV_EPS and limit > 0 and limit < 0.50 then
			checkedWithGrid = true
			local cx = math.floor(Clamp(u, 0, 1) / cellSize)
			local cy = math.floor(Clamp(v, 0, 1) / cellSize)
			local span = math.max(1, math.ceil(limit / cellSize) + 1)
			local seen = {}
			for x = cx - span, cx + span do
				for y = cy - span, cy + span do
					local key = tostring(x) .. ":" .. tostring(y)
					local list = grid.cells[key]
					if type(list) == "table" then
						for i = 1, #list do
							local segIndex = list[i]
							if segIndex and not seen[segIndex] then
								seen[segIndex] = true
								ScanSegment(segIndex)
							end
						end
					end
				end
			end
		end
	end
	if not best or not checkedWithGrid then
		for i = 1, #navCache.segments do
			ScanSegment(i)
		end
	end
	return best
end

function Npc_PickCurrentRoutePoiPoint(npc, maxDist, allowFar)
	if not (npc and navCache.hasPois) then
		return nil, nil, nil
	end
	local key = npc.zoneKey
	if type(key) ~= "string" then
		return nil, nil, nil
	end
	local routeIndex = tonumber(string.match(key, "^route:(%d+)$"))
	if not routeIndex then
		return nil, nil, nil
	end
	local nu = tonumber(npc.u) or 0.5
	local nv = tonumber(npc.v) or 0.5
	local maxD = Clamp(tonumber(maxDist) or NPC_POI_PICK_RADIUS, 0.005, 1.0)
	local maxD2 = maxD * maxD
	local best = nil
	local routePois = nil
	for i = 1, #navCache.pois do
		local poi = navCache.pois[i]
		if poi.routeIndex == routeIndex then
			if not routePois then
				routePois = {}
			end
			routePois[#routePois + 1] = poi
			local dx = (tonumber(poi.u) or 0) - nu
			local dy = (tonumber(poi.v) or 0) - nv
			local d2 = (dx * dx) + (dy * dy)
			if d2 <= maxD2 and (not best or d2 < best.d2) then
				best = {
					u = poi.u,
					v = poi.v,
					d2 = d2,
				}
			end
		end
	end
	if best then
		return best.u, best.v, math.sqrt(best.d2)
	end
	if allowFar and routePois and #routePois > 0 then
		local pick = routePois[math.random(1, #routePois)]
		return tonumber(pick.u), tonumber(pick.v), nil
	end
	return nil, nil, nil
end

function FindNearestPlaza(u, v, maxDist)
	local best = nil
	for i = 1, #navCache.plazas do
		local p = navCache.plazas[i]
		local dist, hitU, hitV = DistancePointToPlaza(p, u, v)
		if dist and dist <= maxDist and (not best or dist < best.dist) then
			best = {
				plazaIndex = i,
				dist = dist,
				u = hitU,
				v = hitV,
			}
		end
	end
	return best
end

function FindNearestRoutePointOutsidePlazas(u, v, maxDist, exceptPlazaIndex)
	if not navCache.hasRoutes then
		return nil
	end
	local best = nil
	local maxDist2 = (maxDist or NPC_PLAZA_TO_ROUTE_DIST) ^ 2
	for i = 1, #navCache.segments do
		local seg = navCache.segments[i]
		local t, px, py, dist2 = ClosestPointOnSegment(u, v, seg.ax, seg.ay, seg.bx, seg.by)
		if dist2 <= maxDist2 then
			if not IsPointInAnyPlaza(px, py, exceptPlazaIndex) then
				if (not best) or dist2 < best.dist2 then
					best = {
						segIndex = i,
						t = t,
						px = px,
						py = py,
						dist2 = dist2,
					}
				end
			end
		end
	end
	return best
end

function GetRouteCrowdExpansion(u, v, ignoreNpc)
	if NPC_CROWD_EXPAND_MAX_BONUS <= NAV_EPS then
		return 0
	end
	local sense2 = NPC_CROWD_EXPAND_SENSE_RADIUS * NPC_CROWD_EXPAND_SENSE_RADIUS
	local near = 0
	for i = 1, #npcPool do
		local other = npcPool[i]
		if other ~= ignoreNpc then
			local ou = tonumber(other and other.u)
			local ov = tonumber(other and other.v)
			if ou and ov then
				local dx = u - ou
				local dy = v - ov
				if ((dx * dx) + (dy * dy)) <= sense2 then
					near = near + 1
				end
			end
		end
	end
	local over = near - NPC_CROWD_EXPAND_THRESHOLD
	if over <= 0 then
		return 0
	end
	local denom = math.max(1, (NPC_SOCIAL_ENCOUNTER_NEAR_MAX + 2) - NPC_CROWD_EXPAND_THRESHOLD)
	local t = Clamp(over / denom, 0, 1)
	return NPC_CROWD_EXPAND_MAX_BONUS * t
end

function IsPointWalkable(u, v, extraRouteTol, ignoreNpc)
	if type(u) ~= "number" or type(v) ~= "number" then
		return false
	end
	if u < 0 or u > 1 or v < 0 or v > 1 then
		return false
	end
	if navCache.hasPlazas then
		for i = 1, #navCache.plazas do
			if IsPointInPlaza(navCache.plazas[i], u, v) then
				return true
			end
		end
	end
	if navCache.hasRoutes then
		local extra = Clamp(tonumber(extraRouteTol) or 0, 0, 0.10)
		local baseTol = math.max(NPC_ROUTE_WALK_HALF_WIDTH, NPC_PERSONAL_SPACE * 1.45)
		local tol = baseTol + extra + GetRouteCrowdExpansion(u, v, ignoreNpc)
		return FindNearestRoutePoint(u, v, tol, nil) ~= nil
	end
	return false
end

function IsPointOnStrictNetwork(u, v)
	if type(u) ~= "number" or type(v) ~= "number" then
		return false
	end
	if u < 0 or u > 1 or v < 0 or v > 1 then
		return false
	end
	if navCache.hasPlazas then
		for i = 1, #navCache.plazas do
			if IsPointInPlaza(navCache.plazas[i], u, v) then
				return true
			end
		end
	end
	if navCache.hasRoutes then
		local strictTol = math.max(NPC_ROUTE_WALK_HALF_WIDTH * 0.55, 0.003)
		return FindNearestRoutePoint(u, v, strictTol, nil) ~= nil
	end
	return false
end

function IsSegmentOnStrictNetwork(ax, ay, bx, by)
	local x1 = tonumber(ax)
	local y1 = tonumber(ay)
	local x2 = tonumber(bx)
	local y2 = tonumber(by)
	if not (x1 and y1 and x2 and y2) then
		return false
	end
	if not (IsPointOnStrictNetwork(x1, y1) and IsPointOnStrictNetwork(x2, y2)) then
		return false
	end
	local dx = x2 - x1
	local dy = y2 - y1
	local dist = math.sqrt((dx * dx) + (dy * dy))
	if dist <= NAV_EPS then
		return true
	end
	local samples =
		math.max(2, math.min(24, math.floor(dist / math.max(NPC_MANUAL_PATH_SMOOTH_STEP * 0.65, 0.006))))
	local requiredEntryByLieu = nil
	local prevLieuIndex = nil
	local hasLieux = navCache.hasLieux and #navCache.lieux > 0
	if hasLieux then
		for j = 1, #navCache.lieux do
			if IsPointInPlaza(navCache.lieux[j], x1, y1) then
				prevLieuIndex = j
				break
			end
		end
	end
	for i = 1, samples do
		local t = i / (samples + 1)
		local u = x1 + ((x2 - x1) * t)
		local v = y1 + ((y2 - y1) * t)
		if not IsPointOnStrictNetwork(u, v) then
			return false
		end
		if hasLieux then
			local lieuIndex = nil
			for j = 1, #navCache.lieux do
				if IsPointInPlaza(navCache.lieux[j], u, v) then
					lieuIndex = j
					break
				end
			end
			if lieuIndex ~= prevLieuIndex then
				if not requiredEntryByLieu then
					requiredEntryByLieu = {}
				end
				if prevLieuIndex then
					requiredEntryByLieu[prevLieuIndex] = true
				end
				if lieuIndex then
					requiredEntryByLieu[lieuIndex] = true
				end
			end
			prevLieuIndex = lieuIndex
		end
	end
	if hasLieux then
		local endLieuIndex = nil
		for j = 1, #navCache.lieux do
			if IsPointInPlaza(navCache.lieux[j], x2, y2) then
				endLieuIndex = j
				break
			end
		end
		if endLieuIndex ~= prevLieuIndex then
			if not requiredEntryByLieu then
				requiredEntryByLieu = {}
			end
			if prevLieuIndex then
				requiredEntryByLieu[prevLieuIndex] = true
			end
			if endLieuIndex then
				requiredEntryByLieu[endLieuIndex] = true
			end
		end
	end
	if requiredEntryByLieu then
		for lieuIndex in pairs(requiredEntryByLieu) do
			local lieu = navCache.lieux[lieuIndex]
			local entries = type(lieu and lieu.entries) == "table" and lieu.entries or nil
			local entryPassed = false
			if entries and #entries > 0 then
				for i = 1, #entries do
					local entry = entries[i]
					local eu = tonumber(entry and entry.u)
					local ev = tonumber(entry and entry.v)
					if eu and ev then
						local entryRadius =
							Clamp(tonumber(entry and (entry.radius or entry.r)) or 0.010, 0.004, 0.040)
						local entryTol = math.max(entryRadius, 0.006)
						local _, _, _, dist2 = ClosestPointOnSegment(eu, ev, x1, y1, x2, y2)
						if dist2 <= (entryTol * entryTol) then
							entryPassed = true
							break
						end
					end
				end
			end
			if not entryPassed then
				return false
			end
		end
	end
	return true
end

function PickRandomWalkablePoint()
	for _ = 1, 80 do
		local tryPlaza = navCache.hasPlazas and (not navCache.hasRoutes or math.random() < 0.45)
		if tryPlaza then
			local plaza = navCache.plazas[math.random(1, #navCache.plazas)]
			local u, v = PickRandomPointInPlaza(plaza)
			if IsPointWalkable(u, v) then
				return u, v
			end
		elseif navCache.hasRoutes then
			local seg = navCache.segments[math.random(1, #navCache.segments)]
			if seg and seg.len and seg.len > NAV_EPS then
				local t = math.random()
				local cx = seg.ax + ((seg.bx - seg.ax) * t)
				local cy = seg.ay + ((seg.by - seg.ay) * t)
				local nx = -(seg.by - seg.ay) / seg.len
				local ny = (seg.bx - seg.ax) / seg.len
				local off = RandRange(-NPC_ROUTE_WALK_HALF_WIDTH, NPC_ROUTE_WALK_HALF_WIDTH)
				local u = cx + (nx * off)
				local v = cy + (ny * off)
				if IsPointWalkable(u, v) then
					return u, v
				end
				if IsPointWalkable(cx, cy) then
					return cx, cy
				end
			end
		end
	end
	return RandomWorldCoord(), RandomWorldCoord()
end

function GetNearestNpcDist2(u, v)
	local best = math.huge
	for i = 1, #npcPool do
		local other = npcPool[i]
		local ou = tonumber(other and other.u)
		local ov = tonumber(other and other.v)
		if ou and ov then
			local dx = u - ou
			local dy = v - ov
			local d2 = (dx * dx) + (dy * dy)
			if d2 < best then
				best = d2
			end
		end
	end
	return best
end

function PickNpcSpawnPoint()
	local wantsWalkable = navCache.hasRoutes or navCache.hasPlazas
	local minDist2 = NPC_SPAWN_MIN_DIST * NPC_SPAWN_MIN_DIST
	local bestU, bestV, bestDist2 = nil, nil, -1

	for _ = 1, 220 do
		local u, v
		if navCache.hasPlazas then
			local plaza = navCache.plazas[math.random(1, #navCache.plazas)]
			u, v = PickRandomPointInPlaza(plaza)
		elseif wantsWalkable then
			u, v = PickRandomWalkablePoint()
		else
			u, v = RandomWorldCoord(), RandomWorldCoord()
		end

		if (not wantsWalkable) or IsPointWalkable(u, v) then
			local nearestDist2 = GetNearestNpcDist2(u, v)
			if nearestDist2 >= minDist2 then
				return u, v
			end
			if nearestDist2 > bestDist2 then
				bestU, bestV, bestDist2 = u, v, nearestDist2
			end
		end
	end

	if bestU and bestV then
		return bestU, bestV
	end
	if navCache.hasPlazas then
		local plaza = navCache.plazas[math.random(1, #navCache.plazas)]
		return PickRandomPointInPlaza(plaza)
	end
	if wantsWalkable then
		return PickRandomWalkablePoint()
	end
	return RandomWorldCoord(), RandomWorldCoord()
end

function Npc_EnsureWalkablePosition(npc)
	if IsPointWalkable(npc.u, npc.v) then
		return true
	end

	local bestU, bestV, bestDist2 = nil, nil, math.huge
	if navCache.hasRoutes then
		local nearest = FindNearestRoutePoint(npc.u, npc.v, 10, nil)
		if nearest then
			bestU = nearest.px
			bestV = nearest.py
			bestDist2 = nearest.dist2
		end
	end
	if navCache.hasPlazas then
		for i = 1, #navCache.plazas do
			local d, pu, pv = DistancePointToPlaza(navCache.plazas[i], npc.u, npc.v)
			if d and pu and pv then
				local d2 = d * d
				if d2 < bestDist2 then
					bestDist2 = d2
					bestU = pu
					bestV = pv
				end
			end
		end
	end
	if bestU and bestV then
		npc.u = bestU
		npc.v = bestV
		return true
	end
	local u, v = PickRandomWalkablePoint()
	npc.u = u
	npc.v = v
	return IsPointWalkable(u, v)
end

PI = math.pi
TWO_PI = PI * 2

function WrapAngle(a)
	a = a % TWO_PI
	if a < 0 then
		a = a + TWO_PI
	end
	return a
end

function ShortestAngleDelta(fromA, toA)
	return ((toA - fromA + PI) % TWO_PI) - PI
end

function ApproachAngle(fromA, toA, maxStep)
	local delta = ShortestAngleDelta(fromA, toA)
	if delta > maxStep then
		delta = maxStep
	elseif delta < -maxStep then
		delta = -maxStep
	end
	return WrapAngle(fromA + delta)
end

function AngleFromVector(x, y)
	if math.abs(x) <= NAV_EPS and math.abs(y) <= NAV_EPS then
		return nil
	end
	if math.atan2 then
		return math.atan2(y, x)
	end
	if math.abs(x) <= NAV_EPS then
		return (y >= 0) and (PI * 0.5) or (-PI * 0.5)
	end
	local a = math.atan(y / x)
	if x < 0 then
		if y >= 0 then
			a = a + PI
		else
			a = a - PI
		end
	end
	return a
end

function IsRepulsionIgnoredPair(selfNpc, otherNpc)
	if not selfNpc or not otherNpc or selfNpc == otherNpc then
		return false
	end
	local stateName = selfNpc.behaviorState
	if stateName ~= "discussion" and stateName ~= "duo_walk" then
		return false
	end
	if (selfNpc.behaviorPartner == otherNpc) and (otherNpc.behaviorPartner == selfNpc) then
		return true
	end
	return AreNpcsInSameConversation(selfNpc, otherNpc)
end

function ClearNpcRouteHint(npc)
	if not npc then
		return
	end
	npc.routeHintSegIndex = nil
	npc.routeHintT = nil
	npc.routeHintDist2 = nil
	npc.routeHintTx = nil
	npc.routeHintTy = nil
	npc.routeHintNx = nil
	npc.routeHintNy = nil
	npc.routeHintRefreshIn = 0
end

function UpdateNpcRouteHint(npc, dt, forceRefresh)
	if not npc then
		return
	end
	if not navCache.hasRoutes then
		ClearNpcRouteHint(npc)
		return
	end

	local refreshIn = (tonumber(npc.routeHintRefreshIn) or 0) - (tonumber(dt) or 0)
	if (not forceRefresh) and refreshIn > 0 and tonumber(npc.routeHintSegIndex) then
		npc.routeHintRefreshIn = refreshIn
		return
	end
	npc.routeHintRefreshIn = RandRange(0.06, 0.14)

	local nu = tonumber(npc.u)
	local nv = tonumber(npc.v)
	if not nu or not nv then
		ClearNpcRouteHint(npc)
		return
	end

	local hintRadius = NPC_ROUTE_WALK_HALF_WIDTH * 2.8
	local near = FindNearestRoutePoint(nu, nv, hintRadius, nil)
	local seg = near and navCache.segments[near.segIndex or 0] or nil
	if not (near and seg and seg.len and seg.len > NAV_EPS) then
		ClearNpcRouteHint(npc)
		return
	end

	local tx = (seg.bx - seg.ax) / seg.len
	local ty = (seg.by - seg.ay) / seg.len
	npc.routeHintSegIndex = near.segIndex
	npc.routeHintT = near.t
	npc.routeHintDist2 = near.dist2
	npc.routeHintTx = tx
	npc.routeHintTy = ty
	npc.routeHintNx = -ty
	npc.routeHintNy = tx
end

function GetRoutePassSideSign(a, b)
	local aId = tostring(a and a.persistentId or "")
	local bId = tostring(b and b.persistentId or "")
	if aId ~= "" and bId ~= "" and aId ~= bId then
		return (aId < bId) and 1 or -1
	end
	local ai = tonumber(a and a.renderHeightOrder) or 0
	local bi = tonumber(b and b.renderHeightOrder) or 0
	if ai ~= bi then
		return (ai < bi) and 1 or -1
	end
	return 1
end

function GetSharedRoutePairInfo(a, b)
	if not navCache.hasRoutes then
		return nil
	end
	local segA = tonumber(a and a.routeHintSegIndex)
	local segB = tonumber(b and b.routeHintSegIndex)
	if not segA or not segB or segA ~= segB then
		return nil
	end
	local passHalfWidth = math.max(NPC_ROUTE_WALK_HALF_WIDTH, NPC_PERSONAL_SPACE * 1.45)
	local maxHintDist2 = (passHalfWidth * 3.2) ^ 2
	if (tonumber(a and a.routeHintDist2) or math.huge) > maxHintDist2 then
		return nil
	end
	if (tonumber(b and b.routeHintDist2) or math.huge) > maxHintDist2 then
		return nil
	end
	local tx = tonumber(a and a.routeHintTx)
	local ty = tonumber(a and a.routeHintTy)
	local nx = tonumber(a and a.routeHintNx)
	local ny = tonumber(a and a.routeHintNy)
	if not (tx and ty and nx and ny) then
		return nil
	end
	local ha = tonumber(a and (a.walkHeading or a.walkDesiredHeading))
	local hb = tonumber(b and (b.walkHeading or b.walkDesiredHeading))
	if not ha or not hb then
		return nil
	end
	local delta = math.abs(ShortestAngleDelta(ha, hb))
	local oppositeDir = delta >= NPC_ROUTE_OPPOSITE_MIN_DELTA
	local sameDir = delta <= 0.70
	return segA, tx, ty, nx, ny, oppositeDir, sameDir
end

function IsCrowdSpaceFree(selfNpc, testU, testV, minDist)
	if not NPC_COLLISIONS_ENABLED then
		return true
	end
	local lim = tonumber(minDist) or NPC_PERSONAL_SPACE
	local lim2 = lim * lim
	local pairLim2 = NPC_SOCIAL_PAIR_SOFT_MIN_DIST * NPC_SOCIAL_PAIR_SOFT_MIN_DIST
	local pairDiscussLim2 = NPC_SOCIAL_DISCUSS_SOFT_MIN_DIST * NPC_SOCIAL_DISCUSS_SOFT_MIN_DIST
	local queryRadius = math.max(lim, NPC_SOCIAL_PAIR_SOFT_MIN_DIST, NPC_SOCIAL_DISCUSS_SOFT_MIN_DIST)
	local blocked = ForEachNpcInRadius(testU, testV, queryRadius, function(other)
		if other == selfNpc then
			return false
		end
		if IsRepulsionIgnoredPair(selfNpc, other) then
			-- Keep social pairs close, but still avoid true overlap.
			local ou = tonumber(other and other.u)
			local ov = tonumber(other and other.v)
			if ou and ov then
				local dx = testU - ou
				local dy = testV - ov
				local softLimit2 = pairLim2
				if (selfNpc.behaviorState == "discussion") or (other.behaviorState == "discussion") then
					softLimit2 =
						math.max(pairDiscussLim2, NPC_SOCIAL_DISCUSS_MIN_DIST * NPC_SOCIAL_DISCUSS_MIN_DIST)
				end
				if ((dx * dx) + (dy * dy)) < softLimit2 then
					return true
				end
			end
			return false
		end

		local ou = tonumber(other and other.u)
		local ov = tonumber(other and other.v)
		if not ou or not ov then
			return false
		end
		local dx = testU - ou
		local dy = testV - ov
		local activeLim2 = lim2
		local _, _, _, _, _, oppositeDir, sameDir = GetSharedRoutePairInfo(selfNpc, other)
		if oppositeDir or sameDir then
			local passFactor = oppositeDir and NPC_ROUTE_OPPOSITE_PASS_FACTOR or 0.76
			local passLim = math.max(NPC_PERSONAL_SPACE * 0.72, lim * passFactor)
			activeLim2 = passLim * passLim
		end
		if ((dx * dx) + (dy * dy)) < activeLim2 then
			return true
		end
		return false
	end)
	return not blocked
end

function TryRelocateNpcNearby(npc, baseU, baseV, awayX, awayY)
	if not npc then
		return false
	end
	local bu = Clamp(tonumber(baseU) or tonumber(npc.u) or 0.5, 0, 1)
	local bv = Clamp(tonumber(baseV) or tonumber(npc.v) or 0.5, 0, 1)
	local minDist = math.max(NPC_PERSONAL_SPACE * NPC_CROWD_RELOCATE_MIN_DIST_FACTOR, NPC_PERSONAL_SPACE * 0.40)
	local steer = AngleFromVector(tonumber(awayX) or 0, tonumber(awayY) or 0)
	for pass = 1, 6 do
		local radius = (pass / 6) * NPC_CROWD_RELOCATE_MAX_RADIUS
		for _ = 1, 12 do
			local a
			if steer then
				a = WrapAngle(steer + RandRange(-1.25, 1.25))
			else
				a = RandRange(0, TWO_PI)
			end
			local du = math.cos(a) * radius
			local dv = math.sin(a) * radius
			local tu = Clamp(bu + du, 0, 1)
			local tv = Clamp(bv + dv, 0, 1)
			if
				IsPointWalkable(tu, tv, NPC_CROWD_EXPAND_MAX_BONUS * 0.75, npc)
				and IsCrowdSpaceFree(npc, tu, tv, minDist)
			then
				npc.u, npc.v = tu, tv
				return true
			end
		end
	end
	return false
end

function Npc_GetSocialState(npc)
	local stateName = npc and npc.behaviorState
	if
		stateName == "approach"
		or stateName == "discussion"
		or stateName == "duo_walk"
		or stateName == "self_pause"
		or stateName == "disengage"
	then
		return stateName
	end
	return "walk"
end

function Npc_ResetSocialState(npc, withCooldown)
	if not npc then
		return
	end
	npc.behaviorState = "walk"
	npc.behaviorPartner = nil
	npc.behaviorTimer = 0
	npc.duoTargetU = nil
	npc.duoTargetV = nil
	npc.approachSource = nil
	npc.discussionSocialBonusTotal = nil
	npc.discussionSocialBonusApplied = nil
	npc.discussionSocialBonusDuration = nil
	npc.discussionSocialBonusSource = nil
	npc.discussionSocialBonusPartnerId = nil
	npc.pauseLookHeading = nil
	npc.selfPauseIgnoreEdge = nil
	npc.pausePurpose = nil
	npc.currentSelfPauseZoneKey = nil
	npc.disengageFromU = nil
	npc.disengageFromV = nil
	npc.disengagePartner = nil
	npc.conversationGroupId = nil
	if withCooldown then
		npc.behaviorCooldown = RandRange(NPC_SOCIAL_COOLDOWN_MIN, NPC_SOCIAL_COOLDOWN_MAX)
	else
		npc.behaviorCooldown = math.max(0, tonumber(npc.behaviorCooldown) or 0)
	end
end

function Npc_ClearZoneShiftTarget(npc)
	if not npc then
		return
	end
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
end

function Npc_SetCommunicationCooldown(npc, minV, maxV)
	if not npc then
		return
	end
	local lo = Clamp(tonumber(minV) or NPC_SOCIAL_COOLDOWN_MIN, 0, 180)
	local hi = Clamp(tonumber(maxV) or lo, lo, 240)
	npc.behaviorCooldown = RandRange(lo, hi)
end

function IsGlobalTalkLocked()
	return (npcGlobalTalkLock or 0) > 0
end

function TriggerGlobalTalkLock(duration)
	local d = Clamp(tonumber(duration) or NPC_GLOBAL_TALK_LOCK_DURATION, 0, 900)
	if d > 0 then
		npcGlobalTalkLock = d
	end
end

function GetZoneKeyAtPoint(u, v)
	local pu = tonumber(u)
	local pv = tonumber(v)
	if not pu or not pv then
		return nil, nil, nil, nil
	end
	if navCache.hasPlazas then
		for i = 1, #navCache.plazas do
			if IsPointInPlaza(navCache.plazas[i], pu, pv) then
				return "plaza:" .. tostring(i), "plaza", i, nil
			end
		end
	end
	if navCache.hasRoutes then
		local near = FindNearestRoutePoint(pu, pv, NPC_ROUTE_WALK_HALF_WIDTH * 1.15, nil)
		if near then
			local seg = navCache.segments[near.segIndex or 0]
			local routeIndex = (seg and seg.routeIndex) or near.segIndex
			return "route:" .. tostring(routeIndex), "route", nil, routeIndex
		end
	end
	return nil, nil, nil, nil
end

function GetLieuAtPoint(u, v)
	local pu = tonumber(u)
	local pv = tonumber(v)
	if not pu or not pv or not navCache.hasLieux then
		return nil
	end
	for i = 1, #navCache.lieux do
		local lieu = navCache.lieux[i]
		if IsPointInPlaza(lieu, pu, pv) then
			return lieu, i
		end
	end
	return nil
end

function CountNpcsInLieu(lieu, ignoreNpc)
	if type(lieu) ~= "table" then
		return 0
	end
	local count = 0
	for i = 1, #npcPool do
		local other = npcPool[i]
		if other ~= ignoreNpc then
			local ou = tonumber(other and other.u)
			local ov = tonumber(other and other.v)
			if ou and ov and IsPointInPlaza(lieu, ou, ov) then
				count = count + 1
			end
		end
	end
	return count
end

function CountNpcsInZone(zoneKey, ignoreNpc)
	if type(zoneKey) ~= "string" or zoneKey == "" then
		return 0
	end
	local count = 0
	for i = 1, #npcPool do
		local other = npcPool[i]
		if other ~= ignoreNpc then
			local otherKey = other.zoneKey
			if type(otherKey) ~= "string" or otherKey == "" then
				otherKey = select(1, GetZoneKeyAtPoint(other.u, other.v))
				other.zoneKey = otherKey
			end
			if otherKey == zoneKey then
				count = count + 1
			end
		end
	end
	return count
end

function IsZoneEntryAllowed(npc, zoneKey, allowCurrent)
	if type(zoneKey) ~= "string" or zoneKey == "" then
		return true
	end
	if npc then
		if not allowCurrent and npc.prevZoneKey and zoneKey == npc.prevZoneKey then
			return false
		end
		if allowCurrent and npc.zoneKey and zoneKey == npc.zoneKey then
			return true
		end
	end
	return CountNpcsInZone(zoneKey, npc) < NPC_MAX_PER_ZONE
end

function Npc_UpdateZoneTracking(npc)
	if not npc then
		return
	end
	local zoneKey, zoneKind = GetZoneKeyAtPoint(npc.u, npc.v)
	if zoneKey ~= npc.zoneKey then
		npc.prevZoneKey = npc.zoneKey
		npc.zoneKey = zoneKey
		npc.zoneKind = zoneKind
		npc.zoneActionCount = 0
		npc.zoneMoveHopCount = 0
	else
		npc.zoneKind = zoneKind
	end
end

function Npc_RegisterZoneAction(npc)
	if not npc then
		return false
	end
	Npc_UpdateZoneTracking(npc)
	local maxActions = NPC_MAX_ACTIONS_PER_ZONE
	local current = tonumber(npc.zoneActionCount) or 0
	if current >= maxActions then
		return false
	end
	npc.zoneActionCount = current + 1
	return true
end

function Npc_ShouldLeaveZone(npc)
	if not npc then
		return false
	end
	Npc_UpdateZoneTracking(npc)
	local maxActions = NPC_MAX_ACTIONS_PER_ZONE
	if essentialNeeds.IsAllGreen(npc) then
		maxActions = math.max(1, math.floor(maxActions * 0.66))
	end
	return (tonumber(npc.zoneActionCount) or 0) >= maxActions
end

function Npc_GetZoneKindAtPoint(u, v)
	local _, zoneKind = GetZoneKeyAtPoint(u, v)
	return zoneKind
end

function PickRandomRouteWalkPoint(npc)
	if not navCache.hasRoutes then
		return nil, nil
	end
	for _ = 1, 80 do
		local seg = navCache.segments[math.random(1, #navCache.segments)]
		if seg and seg.len and seg.len > NAV_EPS then
			local t = math.random()
			local cx = seg.ax + ((seg.bx - seg.ax) * t)
			local cy = seg.ay + ((seg.by - seg.ay) * t)
			local nx = -(seg.by - seg.ay) / seg.len
			local ny = (seg.bx - seg.ax) / seg.len
			local off = RandRange(-NPC_ROUTE_WALK_HALF_WIDTH, NPC_ROUTE_WALK_HALF_WIDTH)
			local u = cx + (nx * off)
			local v = cy + (ny * off)
			local zoneKey = select(1, GetZoneKeyAtPoint(u, v))
			if IsPointWalkable(u, v) and IsZoneEntryAllowed(npc, zoneKey, false) then
				return u, v
			end
			local centerKey = select(1, GetZoneKeyAtPoint(cx, cy))
			if IsPointWalkable(cx, cy) and IsZoneEntryAllowed(npc, centerKey, false) then
				return cx, cy
			end
		end
	end
	return nil, nil
end

function PickRandomPlazaWalkPoint(npc)
	if not navCache.hasPlazas then
		return nil, nil
	end
	for _ = 1, 36 do
		local plaza = navCache.plazas[math.random(1, #navCache.plazas)]
		if plaza then
			local u, v = PickRandomPointInPlaza(plaza)
			local zoneKey = select(1, GetZoneKeyAtPoint(u, v))
			if IsPointWalkable(u, v) and IsZoneEntryAllowed(npc, zoneKey, false) then
				return u, v
			end
		end
	end
	return nil, nil
end

function PickRandomPlazaWalkPointExcept(npc, excludedPlazaIndex)
	if not navCache.hasPlazas then
		return nil, nil
	end
	local excluded = tonumber(excludedPlazaIndex)
	if excluded and #navCache.plazas <= 1 then
		return nil, nil
	end
	local tries = math.max(48, #navCache.plazas * 14)
	for _ = 1, tries do
		local idx = math.random(1, #navCache.plazas)
		if (not excluded) or idx ~= excluded then
			local plaza = navCache.plazas[idx]
			if plaza then
				local u, v = PickRandomPointInPlaza(plaza)
				local zoneKey = select(1, GetZoneKeyAtPoint(u, v))
				if IsPointWalkable(u, v) and IsZoneEntryAllowed(npc, zoneKey, false) then
					return u, v
				end
			end
		end
	end
	return nil, nil
end

function Npc_PickCurrentPlazaWalkPoint(npc)
	if not (npc and navCache.hasPlazas) then
		return nil, nil
	end
	local key = npc.zoneKey
	if type(key) ~= "string" then
		return nil, nil
	end
	local idx = tonumber(string.match(key, "^plaza:(%d+)$"))
	local plaza = idx and navCache.plazas[idx] or nil
	if not plaza then
		return nil, nil
	end
	for _ = 1, 36 do
		local u, v = PickRandomPointInPlaza(plaza)
		if IsPointWalkable(u, v) and IsZoneEntryAllowed(npc, key, true) then
			return u, v
		end
	end
	return nil, nil
end

function Npc_PickCurrentRouteWalkPoint(npc)
	if not (npc and navCache.hasRoutes) then
		return nil, nil
	end
	local key = npc.zoneKey
	if type(key) ~= "string" then
		return nil, nil
	end
	local routeIndex = tonumber(string.match(key, "^route:(%d+)$"))
	local route = routeIndex and navCache.routes[routeIndex] or nil
	if not (route and type(route.segments) == "table" and #route.segments > 0) then
		return nil, nil
	end
	for _ = 1, 60 do
		local segIndex = route.segments[math.random(1, #route.segments)]
		local seg = segIndex and navCache.segments[segIndex] or nil
		if seg and seg.len and seg.len > NAV_EPS then
			local t = math.random()
			local cx = seg.ax + ((seg.bx - seg.ax) * t)
			local cy = seg.ay + ((seg.by - seg.ay) * t)
			local nx = -(seg.by - seg.ay) / seg.len
			local ny = (seg.bx - seg.ax) / seg.len
			local routeHalf = math.max(NPC_ROUTE_WALK_HALF_WIDTH, NPC_PERSONAL_SPACE * 1.45)
			local off = RandRange(-routeHalf, routeHalf)
			local u = cx + (nx * off)
			local v = cy + (ny * off)
			if IsPointWalkable(u, v) and IsZoneEntryAllowed(npc, key, true) then
				return u, v
			end
			if IsPointWalkable(cx, cy) and IsZoneEntryAllowed(npc, key, true) then
				return cx, cy
			end
		end
	end
	return nil, nil
end

function Npc_AssignZoneShiftTarget(npc, targetKind, avoidCurrentPlaza)
	if not npc then
		return false
	end
	local kind = (targetKind == "route" or targetKind == "plaza") and targetKind or nil
	if not kind then
		return false
	end
	local currentU = tonumber(npc.u) or 0.5
	local currentV = tonumber(npc.v) or 0.5
	local currentPlazaIndex = nil
	if navCache.hasPlazas then
		for i = 1, #navCache.plazas do
			if IsPointInPlaza(navCache.plazas[i], currentU, currentV) then
				currentPlazaIndex = i
				break
			end
		end
	end
	local targetU, targetV = nil, nil
	if kind == "plaza" then
		local near = FindNearestPlaza(currentU, currentV, NPC_ROUTE_TO_PLAZA_DIST * 4.5)
		if near and ((not avoidCurrentPlaza) or (near.plazaIndex ~= currentPlazaIndex)) then
			local nearPlaza = near.plazaIndex and navCache.plazas[near.plazaIndex] or nil
			if nearPlaza then
				for _ = 1, 20 do
					local tu, tv = PickRandomPointInPlaza(nearPlaza)
					local nearKey = select(1, GetZoneKeyAtPoint(tu, tv))
					if IsZoneEntryAllowed(npc, nearKey, false) then
						targetU, targetV = tu, tv
						break
					end
				end
			end
		end
		if not targetU or not targetV then
			targetU, targetV = PickRandomPlazaWalkPointExcept(
				npc,
				(avoidCurrentPlaza and currentPlazaIndex) and currentPlazaIndex or nil
			)
			if ((not avoidCurrentPlaza) or not currentPlazaIndex) and ((not targetU) or not targetV) then
				targetU, targetV = PickRandomPlazaWalkPoint(npc)
			end
		end
	else
		local near =
			FindNearestRoutePointOutsidePlazas(currentU, currentV, NPC_PLAZA_TO_ROUTE_DIST * 6.0, currentPlazaIndex)
		if not near then
			near = FindNearestRoutePointOutsidePlazas(
				currentU,
				currentV,
				NPC_PLAZA_TO_ROUTE_DIST * 12.0,
				currentPlazaIndex
			)
		end
		if not near then
			near = FindNearestRoutePoint(currentU, currentV, NPC_PLAZA_TO_ROUTE_DIST * 6.0, nil)
		end
		if near then
			local nearKey = select(1, GetZoneKeyAtPoint(near.px, near.py))
			if IsZoneEntryAllowed(npc, nearKey, false) then
				targetU, targetV = near.px, near.py
			end
		end
		if not targetU or not targetV then
			-- Fallback: keep trying farther route samples for large plazas.
			for _ = 1, 3 do
				targetU, targetV = PickRandomRouteWalkPoint(npc)
				if targetU and targetV then
					break
				end
			end
		end
	end
	if not targetU or not targetV or not IsPointWalkable(targetU, targetV) then
		return false
	end
	local dx = targetU - currentU
	local dy = targetV - currentV
	if ((dx * dx) + (dy * dy)) <= ((NPC_SOCIAL_POST_TALK_ZONE_REACH * 1.2) ^ 2) then
		return false
	end
	npc.zoneShiftTargetU = targetU
	npc.zoneShiftTargetV = targetV
	npc.zoneShiftGoalU = targetU
	npc.zoneShiftGoalV = targetV
	npc.zoneShiftTargetKind = kind
	npc.zoneShiftPathWaypoints = nil
	npc.zoneShiftPathIndex = nil
	npc.zoneShiftPathTargetKey = nil
	npc.zoneShiftPathNavSignature = nil
	npc.zoneShiftTimer = RandRange(NPC_SOCIAL_POST_TALK_ZONE_SWITCH_MIN, NPC_SOCIAL_POST_TALK_ZONE_SWITCH_MAX)
	return true
end


end

return Modules
