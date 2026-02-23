local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.RouteEditor = QM.RouteEditor or {}
local RouteEditor = QM.RouteEditor

local function Clamp(v, minV, maxV)
	if v < minV then
		return minV
	end
	if v > maxV then
		return maxV
	end
	return v
end

local ENTRY_ZONE_MIN_RADIUS = 0.006
local ENTRY_ZONE_MAX_RADIUS = 0.022
local ENTRY_ZONE_DEFAULT_RADIUS = 0.010
local ENTRY_ROUTE_NEAR_DIST = 0.080
local ENTRY_ROUTE_FALLBACK_DIST = 0.220
local ROUTE_POINT_MAGNET_DIST = 0.030

local function EnsureRootStore()
	QM.Routes = QM.Routes or {}
	local s = QM.Routes
	s.version = tonumber(s.version) or 1
	if type(s.maps) ~= "table" then
		s.maps = {}
	end
	if type(s.routes) == "table" or type(s.plazas) == "table" or type(s.lieux) == "table" then
		-- Retrocompat: old flat format -> default map bucket.
		s.maps.default = s.maps.default or {}
		s.maps.default.routes = s.maps.default.routes or s.routes or {}
		s.maps.default.plazas = s.maps.default.plazas or s.plazas or {}
		s.maps.default.lieux = s.maps.default.lieux or s.lieux or {}
		if type(s.regisseuse) == "table" then
			s.maps.default.regisseuse = s.maps.default.regisseuse or s.regisseuse
		end
		s.routes = nil
		s.plazas = nil
		s.lieux = nil
		s.regisseuse = nil
	end
	return s
end

local function EnsureMapStore(mapId)
	local root = EnsureRootStore()
	local key = tostring(mapId or "default")
	root.maps[key] = root.maps[key] or {}
	local s = root.maps[key]
	if type(s.routes) ~= "table" then
		s.routes = {}
	end
	if type(s.plazas) ~= "table" then
		s.plazas = {}
	end
	if type(s.lieux) ~= "table" then
		s.lieux = {}
	end
	if type(s.pois) ~= "table" then
		s.pois = {}
	end
	if type(s.regisseuse) ~= "table" then
		s.regisseuse = nil
	end
	return s
end

local function CopyPoints(points)
	local out = {}
	if type(points) ~= "table" then
		return out
	end
	for i = 1, #points do
		local p = points[i]
		out[#out + 1] = {
			u = Clamp(tonumber(p and p.u) or 0, 0, 1),
			v = Clamp(tonumber(p and p.v) or 0, 0, 1),
		}
	end
	return out
end

local function F(v)
	return string.format("%.4f", tonumber(v) or 0)
end

local function GetEntryRadius(entry)
	return Clamp(
		tonumber(entry and (entry.radius or entry.r)) or ENTRY_ZONE_DEFAULT_RADIUS,
		ENTRY_ZONE_MIN_RADIUS,
		ENTRY_ZONE_MAX_RADIUS
	)
end

local function AppendMapExport(sb, mapKey, mapStore)
	local routes = type(mapStore and mapStore.routes) == "table" and mapStore.routes or {}
	local plazas = type(mapStore and mapStore.plazas) == "table" and mapStore.plazas or {}
	local lieux = type(mapStore and mapStore.lieux) == "table" and mapStore.lieux or {}
	local pois = type(mapStore and mapStore.pois) == "table" and mapStore.pois or {}
	local regisseuse = type(mapStore and mapStore.regisseuse) == "table" and mapStore.regisseuse or nil

	sb[#sb + 1] = ("\t\t\t[%q] = {"):format(tostring(mapKey))
	sb[#sb + 1] = "\t\t\t\troutes = {"
	for i = 1, #routes do
		local route = routes[i]
		local pts = type(route and route.points) == "table" and route.points or {}
		sb[#sb + 1] = ("\t\t\t\t\t{ id = %q, points = {"):format(tostring(route and route.id or ("route_" .. i)))
		for j = 1, #pts do
			local p = pts[j]
			sb[#sb + 1] = ("\t\t\t\t\t\t{ u = %s, v = %s },"):format(F(p and p.u), F(p and p.v))
		end
		sb[#sb + 1] = "\t\t\t\t\t} },"
	end
	sb[#sb + 1] = "\t\t\t\t},"
	sb[#sb + 1] = "\t\t\t\tplazas = {"
	for i = 1, #plazas do
		local plaza = plazas[i]
		local pts = type(plaza and plaza.points) == "table" and plaza.points or {}
		sb[#sb + 1] = ("\t\t\t\t\t{ id = %q, points = {"):format(tostring(plaza and plaza.id or ("place_" .. i)))
		for j = 1, #pts do
			local p = pts[j]
			sb[#sb + 1] = ("\t\t\t\t\t\t{ u = %s, v = %s },"):format(F(p and p.u), F(p and p.v))
		end
		sb[#sb + 1] = "\t\t\t\t\t} },"
	end
	sb[#sb + 1] = "\t\t\t\t},"
	sb[#sb + 1] = "\t\t\t\tlieux = {"
	for i = 1, #lieux do
		local lieu = lieux[i]
		local pts = type(lieu and lieu.points) == "table" and lieu.points or {}
		local entries = type(lieu and lieu.entries) == "table" and lieu.entries or {}
		local lieuType = tostring(lieu and lieu.type or "chaumiere")
		local lieuId = tostring(lieu and lieu.id or ("lieu_" .. i))
		local lieuLinkId = tostring(lieu and lieu.linkId or "")
		if lieuLinkId ~= "" then
			sb[#sb + 1] = ("\t\t\t\t\t{ id = %q, linkId = %q, type = %q, points = {"):format(
				lieuId,
				lieuLinkId,
				lieuType
			)
		else
			sb[#sb + 1] = ("\t\t\t\t\t{ id = %q, type = %q, points = {"):format(lieuId, lieuType)
		end
		for j = 1, #pts do
			local p = pts[j]
			sb[#sb + 1] = ("\t\t\t\t\t\t{ u = %s, v = %s },"):format(F(p and p.u), F(p and p.v))
		end
		if #entries > 0 then
			sb[#sb + 1] = "\t\t\t\t\t\t},"
			sb[#sb + 1] = "\t\t\t\t\t\tentries = {"
			for j = 1, #entries do
				local e = entries[j]
				local radius = GetEntryRadius(e)
				local routeId = tostring(e and e.routeId or "")
				local extra = ""
				if routeId ~= "" then
					extra = extra .. (", routeId = " .. string.format("%q", routeId))
				end
				sb[#sb + 1] = ("\t\t\t\t\t\t\t{ id = %q, u = %s, v = %s, radius = %s%s },"):format(
					tostring(e and e.id or ("entry_" .. j)),
					F(e and e.u),
					F(e and e.v),
					F(radius),
					extra
				)
			end
			sb[#sb + 1] = "\t\t\t\t\t\t},"
			sb[#sb + 1] = "\t\t\t\t\t},"
		else
			sb[#sb + 1] = "\t\t\t\t\t} },"
		end
	end
	sb[#sb + 1] = "\t\t\t\t},"
	sb[#sb + 1] = "\t\t\t\tpois = {"
	for i = 1, #pois do
		local p = pois[i]
		local extra = ""
		if type(p and p.routeId) == "string" and p.routeId ~= "" then
			extra = extra .. (", routeId = " .. string.format("%q", p.routeId))
		end
		if type(p and p.plazaId) == "string" and p.plazaId ~= "" then
			extra = extra .. (", plazaId = " .. string.format("%q", p.plazaId))
		end
		if type(p and p.lieuId) == "string" and p.lieuId ~= "" then
			extra = extra .. (", lieuId = " .. string.format("%q", p.lieuId))
		end
		sb[#sb + 1] = ("\t\t\t\t\t{ id = %q, u = %s, v = %s%s },"):format(
			tostring(p and p.id or ("poi_" .. i)),
			F(p and p.u),
			F(p and p.v),
			extra
		)
	end
	sb[#sb + 1] = "\t\t\t\t},"
	if regisseuse and tonumber(regisseuse.u) and tonumber(regisseuse.v) then
		sb[#sb + 1] = ("\t\t\t\tregisseuse = { u = %s, v = %s },"):format(F(regisseuse.u), F(regisseuse.v))
	end
	sb[#sb + 1] = "\t\t\t},"
end

local function BuildExportText(_, mapId)
	EnsureMapStore(mapId)
	local root = EnsureRootStore()
	local maps = type(root.maps) == "table" and root.maps or {}
	local mapEntries = {}
	for k, v in pairs(maps) do
		mapEntries[#mapEntries + 1] = {
			keyText = tostring(k),
			value = v,
		}
	end
	table.sort(mapEntries, function(a, b)
		return a.keyText < b.keyText
	end)

	local sb = {}
	sb[#sb + 1] = "local ADDON, ns = ..."
	sb[#sb + 1] = ""
	sb[#sb + 1] = "ns.QuartierMiniature = ns.QuartierMiniature or {}"
	sb[#sb + 1] = "local QM = ns.QuartierMiniature"
	sb[#sb + 1] = ""
	sb[#sb + 1] = "QM.Routes = QM.Routes"
	sb[#sb + 1] = "\tor {"
	sb[#sb + 1] = ("\t\tversion = %s,"):format(tostring(tonumber(root.version) or 1))
	sb[#sb + 1] = "\t\tmaps = {"
	for i = 1, #mapEntries do
		local entry = mapEntries[i]
		AppendMapExport(sb, entry.keyText, entry.value)
	end
	sb[#sb + 1] = "\t\t},"
	sb[#sb + 1] = "\t}"
	return table.concat(sb, "\n")
end

function RouteEditor.Attach(opts)
	if type(opts) ~= "table" then
		return nil
	end
	local parent = opts.parent
	local viewport = opts.viewport
	local overlayParent = opts.overlayParent or viewport
	local overlayFrameLevel = tonumber(opts.overlayFrameLevel)
	local dragger = opts.dragger
	local getCamera = opts.getCamera
	local getNpcSnapshot = type(opts.getNpcSnapshot) == "function" and opts.getNpcSnapshot or nil
	local setRegisseuseAnchor = type(opts.setRegisseuseAnchor) == "function" and opts.setRegisseuseAnchor or nil
	if not (parent and viewport and dragger and type(getCamera) == "function") then
		return nil
	end

	local E = {}
	local function GetMapId()
		if type(opts.getMapId) == "function" then
			local ok, value = pcall(opts.getMapId)
			if ok and type(value) == "string" and value ~= "" then
				return value
			end
		end
		return "default"
	end

	local activeMapId = GetMapId()
	local store = EnsureMapStore(activeMapId)
	E.mode = "route"
	E.draft = { kind = "route", points = {} }
	E.lieuType = "chaumiere"
	E.lieuLinkId = ""
	E._visElapsed = 0
	E._renderElapsed = 0
	E.showOverlayPoints = true
	E.editorOpen = false
	local shouldBlockRightClick = type(opts.shouldBlockRightClick) == "function" and opts.shouldBlockRightClick or nil

	function E:IsDevMode()
		if type(opts.isDevMode) == "function" then
			local ok, value = pcall(opts.isDevMode)
			return ok and value == true
		end
		return false
	end

	function E:IsEditorOpen()
		return E.editorOpen == true
	end

	function E:SetEditorOpen(open)
		E.editorOpen = (open == true)
		E.RefreshVisibility()
	end

	function E:ToggleEditorOpen()
		E:SetEditorOpen(not E:IsEditorOpen())
	end

	local overlay = CreateFrame("Frame", "WoWGuilde_QuartierMiniaturePathfindingOverlay", overlayParent)
	overlay:SetAllPoints(viewport)
	if overlayFrameLevel then
		overlay:SetFrameLevel(math.floor(overlayFrameLevel))
	else
		overlay:SetFrameLevel(viewport:GetFrameLevel() + 30)
	end
	overlay:EnableMouse(false)

	local linePool = {}
	local dotPool = {}
	local lineUsed = 0
	local dotUsed = 0

	local function AcquireLine()
		lineUsed = lineUsed + 1
		local line = linePool[lineUsed]
		if line then
			return line
		end
		line = overlay:CreateLine(nil, "OVERLAY", nil, 1)
		line:SetThickness(2)
		linePool[lineUsed] = line
		return line
	end

	local function AcquireDot()
		dotUsed = dotUsed + 1
		local dot = dotPool[dotUsed]
		if dot then
			return dot
		end
		dot = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
		dot:SetTexture("Interface\\Buttons\\WHITE8X8")
		dot:SetSize(6, 6)
		dotPool[dotUsed] = dot
		return dot
	end

	local function HideUnused()
		for i = lineUsed + 1, #linePool do
			linePool[i]:Hide()
		end
		for i = dotUsed + 1, #dotPool do
			dotPool[i]:Hide()
		end
	end

	local function ToScreen(u, v)
		local u1, v1, uSpan, vSpan = getCamera()
		local vw = viewport:GetWidth() or 0
		local vh = viewport:GetHeight() or 0
		if vw <= 0 or vh <= 0 or uSpan <= 0 or vSpan <= 0 then
			return nil, nil
		end
		local nx = (u - u1) / uSpan
		local ny = (v - v1) / vSpan
		local x = nx * vw
		local y = (1 - ny) * vh
		return x, y
	end

	local function DrawShape(points, closed, r, g, b, a)
		if type(points) ~= "table" then
			return
		end
		local n = #points
		if n == 0 then
			return
		end
		for i = 1, n do
			local p = points[i]
			local x, y = ToScreen(tonumber(p.u) or 0, tonumber(p.v) or 0)
			if x and y then
				local dot = AcquireDot()
				dot:ClearAllPoints()
				dot:SetSize(6, 6)
				dot:SetPoint("CENTER", overlay, "BOTTOMLEFT", x, y)
				dot:SetColorTexture(r, g, b, a)
				dot:Show()
			end
			if i < n then
				local p2 = points[i + 1]
				local x2, y2 = ToScreen(tonumber(p2.u) or 0, tonumber(p2.v) or 0)
				if x and y and x2 and y2 then
					local line = AcquireLine()
					line:SetStartPoint("BOTTOMLEFT", overlay, x, y)
					line:SetEndPoint("BOTTOMLEFT", overlay, x2, y2)
					if line.SetColorTexture then
						line:SetColorTexture(r, g, b, a)
					elseif line.SetVertexColor then
						line:SetVertexColor(r, g, b, a)
					end
					line:Show()
				end
			end
		end
		if closed and n > 2 then
			local p1 = points[1]
			local pN = points[n]
			local x1, y1 = ToScreen(tonumber(p1.u) or 0, tonumber(p1.v) or 0)
			local x2, y2 = ToScreen(tonumber(pN.u) or 0, tonumber(pN.v) or 0)
			if x1 and y1 and x2 and y2 then
				local line = AcquireLine()
				line:SetStartPoint("BOTTOMLEFT", overlay, x2, y2)
				line:SetEndPoint("BOTTOMLEFT", overlay, x1, y1)
				if line.SetColorTexture then
					line:SetColorTexture(r, g, b, a)
				elseif line.SetVertexColor then
					line:SetVertexColor(r, g, b, a)
				end
				line:Show()
			end
		end
	end

	local function DrawPoints(points, r, g, b, a, size)
		if type(points) ~= "table" then
			return
		end
		local dotSize = tonumber(size) or 8
		for i = 1, #points do
			local p = points[i]
			local x, y = ToScreen(tonumber(p and p.u) or 0, tonumber(p and p.v) or 0)
			if x and y then
				local dot = AcquireDot()
				dot:ClearAllPoints()
				dot:SetPoint("CENTER", overlay, "BOTTOMLEFT", x, y)
				dot:SetSize(dotSize, dotSize)
				dot:SetColorTexture(r, g, b, a)
				dot:Show()
			end
		end
	end

	local function DrawEntryZones(entries, r, g, b, a, extraPx)
		if type(entries) ~= "table" then
			return
		end
		local _, _, uSpan, vSpan = getCamera()
		local vw = viewport:GetWidth() or 0
		local vh = viewport:GetHeight() or 0
		local addPx = tonumber(extraPx) or 0
		if vw <= 0 or vh <= 0 or uSpan <= 0 or vSpan <= 0 then
			DrawPoints(entries, r, g, b, a, 9 + addPx)
			return
		end
		for i = 1, #entries do
			local e = entries[i]
			local x, y = ToScreen(tonumber(e and e.u) or 0, tonumber(e and e.v) or 0)
			if x and y then
				local radius = GetEntryRadius(e)
				local pxRadiusU = radius * vw / uSpan
				local pxRadiusV = radius * vh / vSpan
				local pxRadius = math.max(pxRadiusU, pxRadiusV)
				local dotSize = Clamp((pxRadius * 2) + addPx, 8, 30)
				local dot = AcquireDot()
				dot:ClearAllPoints()
				dot:SetPoint("CENTER", overlay, "BOTTOMLEFT", x, y)
				dot:SetSize(dotSize, dotSize)
				dot:SetColorTexture(r, g, b, a)
				dot:Show()
			end
		end
	end

	local function GetPoiActionRadius()
		local liveCfg = (QM and QM.Config) or {}
		local npcCfg = type(liveCfg.npc) == "table" and liveCfg.npc or {}
		return Clamp(tonumber(npcCfg.poiPickRadius) or 0.090, 0.005, 0.45)
	end

	local function DrawPoiActionRings(pois, radius, r, g, b, a, thickness, segments)
		if type(pois) ~= "table" or #pois < 1 then
			return
		end
		local ringRadius = Clamp(tonumber(radius) or 0.090, 0.001, 1.0)
		local segCount = math.max(8, math.floor(tonumber(segments) or 18))
		local twoPi = math.pi * 2
		local lineThickness = Clamp(tonumber(thickness) or 1.25, 1, 3)
		for i = 1, #pois do
			local poi = pois[i]
			local cu = tonumber(poi and poi.u)
			local cv = tonumber(poi and poi.v)
			if cu and cv then
				local prevX, prevY = nil, nil
				local firstX, firstY = nil, nil
				for seg = 0, segCount do
					local t = (seg / segCount) * twoPi
					local u = cu + (math.cos(t) * ringRadius)
					local v = cv + (math.sin(t) * ringRadius)
					local x, y = ToScreen(u, v)
					if x and y then
						if not firstX then
							firstX, firstY = x, y
						end
						if prevX and prevY then
							local line = AcquireLine()
							line:SetStartPoint("BOTTOMLEFT", overlay, prevX, prevY)
							line:SetEndPoint("BOTTOMLEFT", overlay, x, y)
							line:SetThickness(lineThickness)
							if line.SetColorTexture then
								line:SetColorTexture(r, g, b, a)
							elseif line.SetVertexColor then
								line:SetVertexColor(r, g, b, a)
							end
							line:Show()
						end
						prevX, prevY = x, y
					end
				end
				if prevX and prevY and firstX and firstY then
					local line = AcquireLine()
					line:SetStartPoint("BOTTOMLEFT", overlay, prevX, prevY)
					line:SetEndPoint("BOTTOMLEFT", overlay, firstX, firstY)
					line:SetThickness(lineThickness)
					if line.SetColorTexture then
						line:SetColorTexture(r, g, b, a)
					elseif line.SetVertexColor then
						line:SetVertexColor(r, g, b, a)
					end
					line:Show()
				end
			end
		end
	end

	local function DrawNpcDebugPaths()
		if type(getNpcSnapshot) ~= "function" then
			return
		end
		local ok, snapshot = pcall(getNpcSnapshot)
		if not ok or type(snapshot) ~= "table" then
			return
		end
			local r, g, b = 0.72, 0.30, 1.00
			for i = 1, #snapshot do
				local row = snapshot[i]
				local points = type(row and row.debugPathWaypoints) == "table" and row.debugPathWaypoints or nil
				local count = points and #points or 0
				if count > 0 then
					local activeIndex = math.max(1, math.floor(tonumber(row and row.debugPathIndex) or 1))
					local first = points[1]
					local prevU = tonumber(first and first.u)
					local prevV = tonumber(first and first.v)
					for j = 1, count do
						local p = points[j]
						local u = tonumber(p and p.u)
						local v = tonumber(p and p.v)
					local x, y = nil, nil
					if u and v then
						x, y = ToScreen(u, v)
					end
						if j > 1 and prevU and prevV and u and v then
							local x1, y1 = ToScreen(prevU, prevV)
							local x2, y2 = ToScreen(u, v)
							if x1 and y1 and x2 and y2 then
							local line = AcquireLine()
							line:SetStartPoint("BOTTOMLEFT", overlay, x1, y1)
							line:SetEndPoint("BOTTOMLEFT", overlay, x2, y2)
							line:SetThickness((j == activeIndex) and 3 or 2)
							local alpha = (j < activeIndex) and 0.35 or 0.85
							if line.SetColorTexture then
								line:SetColorTexture(r, g, b, alpha)
							elseif line.SetVertexColor then
								line:SetVertexColor(r, g, b, alpha)
							end
							line:Show()
						end
					end
					if x and y then
						local dot = AcquireDot()
						dot:ClearAllPoints()
						dot:SetPoint("CENTER", overlay, "BOTTOMLEFT", x, y)
						dot:SetSize((j == activeIndex) and 9 or 6, (j == activeIndex) and 9 or 6)
						dot:SetColorTexture(r, g, b, (j < activeIndex) and 0.40 or 0.95)
						dot:Show()
					end
					if u and v then
						prevU = u
						prevV = v
					end
				end
			end
		end
	end

	local toolbar = CreateFrame("Frame", "WoWGuilde_QMRouteToolbar", parent, "BackdropTemplate")
	toolbar:SetSize(480, 246)
	toolbar:SetPoint("TOPLEFT", parent, "TOPLEFT", 68, -108)
	toolbar:SetFrameStrata(parent:GetFrameStrata())
	toolbar:SetFrameLevel(viewport:GetFrameLevel() + 80)
	toolbar:SetMovable(true)
	toolbar:EnableMouse(true)
	toolbar:SetClampedToScreen(true)
	toolbar:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	toolbar:SetBackdropColor(0.02, 0.02, 0.02, 0.9)

	local toggleBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	toggleBtn:SetSize(96, 22)
	toggleBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -126, -20)
	toggleBtn:SetFrameStrata(parent:GetFrameStrata())
	toggleBtn:SetFrameLevel(viewport:GetFrameLevel() + 90)
	toggleBtn:SetText("Chemins")
	toggleBtn:SetScript("OnClick", function()
		if not E:IsDevMode() then
			E:SetEditorOpen(false)
			return
		end
		E:ToggleEditorOpen()
	end)

	local titleBar = CreateFrame("Frame", nil, toolbar)
	titleBar:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 6, -6)
	titleBar:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", -6, -6)
	titleBar:SetHeight(18)
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnDragStart", function()
		toolbar:StartMoving()
	end)
	titleBar:SetScript("OnDragStop", function()
		toolbar:StopMovingOrSizing()
	end)

	local title = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 2, 0)
	title:SetJustifyH("LEFT")
	title:SetText("Quartier Miniature - Outils")

	local summary = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	summary:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 12, -154)
	summary:SetJustifyH("LEFT")

	local status = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 12, -170)
	status:SetJustifyH("LEFT")

	local help1 = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help1:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 12, -186)
	help1:SetJustifyH("LEFT")

	local help2 = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help2:SetPoint("TOPLEFT", help1, "BOTTOMLEFT", 0, -2)
	help2:SetJustifyH("LEFT")

	local help3 = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help3:SetPoint("TOPLEFT", help2, "BOTTOMLEFT", 0, -2)
	help3:SetJustifyH("LEFT")

	local help4 = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help4:SetPoint("TOPLEFT", help3, "BOTTOMLEFT", 0, -2)
	help4:SetJustifyH("LEFT")

	local function CreateBtn(label, x, y, w)
		local b = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
		b:SetSize(tonumber(w) or 72, 22)
		b:SetPoint("TOPLEFT", toolbar, "TOPLEFT", x, y)
		b:SetText(label)
		return b
	end

	local routeBtn = CreateBtn("Route", 12, -34)
	local plazaBtn = CreateBtn("Place", 12, -58)
	local lieuBtn = CreateBtn("Lieu", 12, -82)
	local poiBtn = CreateBtn("POI", 12, -106)
	local regisseuseBtn = CreateBtn("Regisseuse", 12, -130, 92)
	local entryBtn = CreateBtn("Entree", 98, -106)
	local finishBtn = CreateBtn("Fin", 98, -34)
	local undoBtn = CreateBtn("Undo", 98, -58)
	local eraseBtn = CreateBtn("Gomme", 98, -82)
	local chaumiereBtn = CreateBtn("Chaumiere", 184, -34, 92)
	local taverneBtn = CreateBtn("Taverne", 184, -58, 92)
	local aubergeBtn = CreateBtn("Auberge", 184, -82, 92)
	local pointsBtn = CreateBtn("Points:ON", 184, -106, 92)
	local exportBtn = CreateBtn("Export", 282, -34, 92)
	local clearBtn = CreateBtn("Clear", 282, -58, 92)

	local lieuLinkLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lieuLinkLabel:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 282, -86)
	lieuLinkLabel:SetText("ID liaison zone")
	lieuLinkLabel:SetJustifyH("LEFT")

	local lieuLinkInput = CreateFrame("EditBox", nil, toolbar, "InputBoxTemplate")
	lieuLinkInput:SetSize(92, 20)
	lieuLinkInput:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 282, -106)
	lieuLinkInput:SetAutoFocus(false)
	lieuLinkInput:SetTextInsets(4, 4, 0, 0)
	lieuLinkInput:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	lieuLinkInput:SetScript("OnTextChanged", function(self)
		E.lieuLinkId = tostring(self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
	end)

	local lieuSelectLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lieuSelectLabel:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 380, -34)
	lieuSelectLabel:SetText("Zones")
	lieuSelectLabel:SetJustifyH("LEFT")

	local lieuListFrame = CreateFrame("Frame", nil, toolbar, "BackdropTemplate")
	lieuListFrame:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 380, -52)
	lieuListFrame:SetSize(92, 84)
	lieuListFrame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	lieuListFrame:SetBackdropColor(0, 0, 0, 0.35)

	local lieuApplyBtn = CreateBtn("Appliquer", 380, -138, 92)
	local lieuPrevBtn = CreateBtn("<", 380, -162, 44)
	local lieuNextBtn = CreateBtn(">", 428, -162, 44)
	local selectedLieuId = nil
	local lieuRows = {}
	local lieuListOffset = 0

	local exportFrame = CreateFrame("Frame", "WoWGuilde_QMRouteExport", parent, "BackdropTemplate")
	exportFrame:SetSize(760, 350)
	exportFrame:SetPoint("CENTER", parent, "CENTER", 0, 0)
	exportFrame:SetFrameStrata(parent:GetFrameStrata())
	exportFrame:SetFrameLevel(viewport:GetFrameLevel() + 120)
	exportFrame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	exportFrame:SetBackdropColor(0.01, 0.01, 0.01, 0.95)
	exportFrame:Hide()

	local exportTitle = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	exportTitle:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 12, -10)
	exportTitle:SetText("Export complet QM.Routes (coller dans Sections/QuartierMiniature/Routes.lua)")

	local closeExport = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
	closeExport:SetPoint("TOPRIGHT", exportFrame, "TOPRIGHT", 2, 2)
	closeExport:SetScript("OnClick", function()
		exportFrame:Hide()
	end)

	local exportScroll = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
	exportScroll:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 12, -36)
	exportScroll:SetPoint("BOTTOMRIGHT", exportFrame, "BOTTOMRIGHT", -34, 14)

	local exportEdit = CreateFrame("EditBox", nil, exportScroll)
	exportEdit:SetMultiLine(true)
	exportEdit:SetFontObject(ChatFontNormal)
	exportEdit:SetAutoFocus(false)
	exportEdit:EnableMouse(true)
	exportEdit:SetWidth(690)
	exportEdit:SetTextInsets(4, 4, 4, 4)
	exportEdit:SetScript("OnEscapePressed", function()
		exportFrame:Hide()
	end)
	exportEdit:SetScript("OnMouseDown", function(self)
		self:SetFocus()
	end)
	exportEdit:SetScript("OnKeyDown", function(self, key)
		if IsControlKeyDown and IsControlKeyDown() and (key == "A" or key == "a") then
			self:HighlightText()
		end
	end)
	exportEdit:SetScript("OnTextChanged", function(self)
		local textHeight = 0
		if self.GetTextHeight then
			textHeight = tonumber(self:GetTextHeight()) or 0
		elseif self.GetStringHeight then
			textHeight = tonumber(self:GetStringHeight()) or 0
		end
		if textHeight <= 0 then
			textHeight = 24
		end
		self:SetHeight(math.max(1, textHeight + 20))
	end)
	exportScroll:SetScrollChild(exportEdit)
	exportFrame:SetScript("OnShow", function()
		exportEdit:SetFocus()
		exportEdit:HighlightText()
	end)

	local UpdateStatus

	local function RefreshLieuRows()
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		local lieux = type(store and store.lieux) == "table" and store.lieux or {}
		if selectedLieuId and selectedLieuId ~= "" then
			local found = false
			for i = 1, #lieux do
				if tostring(lieux[i] and lieux[i].id or "") == selectedLieuId then
					found = true
					break
				end
			end
			if not found then
				selectedLieuId = nil
			end
		end
		for i = 1, #lieuRows do
			lieuRows[i]:Hide()
		end
		local visibleCount = 4
		local maxOffset = math.max(0, #lieux - visibleCount)
		lieuListOffset = Clamp(lieuListOffset, 0, maxOffset)
		lieuPrevBtn:SetEnabled(lieuListOffset > 0)
		lieuNextBtn:SetEnabled(lieuListOffset < maxOffset)
		for i = 1, visibleCount do
			local idx = lieuListOffset + i
			local lieu = lieux[idx]
			if not lieu then
				break
			end
			local row = lieuRows[i]
			if not row then
				row = CreateFrame("Button", nil, lieuListFrame)
				row:SetSize(84, 18)
				row:SetPoint("TOPLEFT", lieuListFrame, "TOPLEFT", 4, -((i - 1) * 20) - 3)
				row.bg = row:CreateTexture(nil, "BACKGROUND")
				row.bg:SetAllPoints(row)
				row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
				row.bg:SetVertexColor(0.2, 0.2, 0.2)
				row.bg:SetAlpha(0.16)
				row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
				row.text:SetJustifyH("LEFT")
				row:SetScript("OnClick", function(self)
					selectedLieuId = tostring(self._lieuId or "")
					local linkId = tostring(self._linkId or "")
					lieuLinkInput:SetText(linkId)
					E.lieuLinkId = linkId
					UpdateStatus()
					E.Render()
				end)
				lieuRows[i] = row
			end
			local lieuId = tostring(lieu and lieu.id or ("lieu_" .. idx))
			local linkId = tostring(lieu and lieu.linkId or lieuId)
			row._lieuId = lieuId
			row._linkId = linkId
			row.text:SetText(lieuId)
			if selectedLieuId ~= nil and selectedLieuId ~= "" and selectedLieuId == lieuId then
				row.bg:SetVertexColor(1.0, 0.82, 0.10)
				row.bg:SetAlpha(0.35)
			else
				row.bg:SetVertexColor(0.2, 0.2, 0.2)
				row.bg:SetAlpha(0.16)
			end
			row:Show()
		end
	end

	local function UpdatePointsButtonText()
		pointsBtn:SetText(E.showOverlayPoints and "Points:ON" or "Points:OFF")
	end

	local function UpdateLieuTypeButtons()
		if E.mode == "lieu" then
			chaumiereBtn:SetEnabled(E.lieuType ~= "chaumiere")
			taverneBtn:SetEnabled(E.lieuType ~= "taverne")
			aubergeBtn:SetEnabled(E.lieuType ~= "auberge")
			lieuLinkInput:Enable()
			lieuLinkInput:SetAlpha(1)
			lieuLinkLabel:SetAlpha(1)
		else
			chaumiereBtn:SetEnabled(true)
			taverneBtn:SetEnabled(true)
			aubergeBtn:SetEnabled(true)
			lieuLinkInput:Disable()
			lieuLinkInput:SetAlpha(0.55)
			lieuLinkLabel:SetAlpha(0.55)
		end
	end

	UpdateStatus = function()
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		local routesCount = (type(store and store.routes) == "table") and #store.routes or 0
		local plazasCount = (type(store and store.plazas) == "table") and #store.plazas or 0
		local lieuxCount = (type(store and store.lieux) == "table") and #store.lieux or 0
		local poiCount = (type(store and store.pois) == "table") and #store.pois or 0
		local entryCount = 0
		if type(store and store.lieux) == "table" then
			for i = 1, #store.lieux do
				local lieu = store.lieux[i]
				local entries = type(lieu and lieu.entries) == "table" and lieu.entries or {}
				entryCount = entryCount + #entries
			end
		end
		local pointsLabel = E.showOverlayPoints and "visibles" or "masques"
		summary:SetText(
			("map:%s - routes:%d - places:%d - lieux:%d - entrees:%d - poi:%d - points:%s"):format(
				activeMapId,
				routesCount,
				plazasCount,
				lieuxCount,
				entryCount,
				poiCount,
				pointsLabel
			)
		)
		local modeLabel
		if E.mode == "plaza" then
			modeLabel = "place"
		elseif E.mode == "poi" then
			modeLabel = "poi"
		elseif E.mode == "erase" then
			modeLabel = "gomme"
		elseif E.mode == "entry" then
			modeLabel = "entree"
		elseif E.mode == "regisseuse" then
			modeLabel = "regisseuse"
		elseif E.mode == "lieu" then
			modeLabel = "lieu(" .. tostring(E.lieuType) .. ")"
		else
			modeLabel = "route"
		end
		local n = (E.draft and E.draft.points and #E.draft.points) or 0
		status:SetText(("mode:%s pointsDraft:%d"):format(modeLabel, n))
		if E.mode == "erase" then
			help1:SetText("Aide 1: Maj+RClick -> gommer un segment ou un point")
			help2:SetText("Aide 2: segment touche -> supprime tout l'element")
			help3:SetText("Aide 3: point touche -> supprime uniquement le point")
			help4:SetText("Aide 4: Maj+Alt+RClick -> reset de la forme courante")
		elseif E.mode == "entry" then
			help1:SetText("Aide 1: Selectionne un lieu dans la liste a droite")
			help2:SetText("Aide 2: Maj+RClick -> cree une petite zone jonction route/batiment")
			help3:SetText("Aide 3: l'entree est refusee si aucune route n'est proche")
			help4:SetText("Aide 4: recherche auto sur tout le bord du lieu")
		elseif E.mode == "poi" then
			help1:SetText("Aide 1: Maj+RClick -> ajouter un POI (partout; snap route si proche)")
			help2:SetText("Aide 2: Bouton Fin -> finaliser la forme")
			help3:SetText("Aide 3: Maj+Ctrl+RClick -> annuler le dernier point")
			help4:SetText("Aide 4: Maj+Alt+RClick -> reset de la forme courante")
		elseif E.mode == "regisseuse" then
			help1:SetText("Aide 1: Maj+RClick -> poser le point de zone de la regisseuse")
			help2:SetText("Aide 2: un nouveau point remplace automatiquement l'ancien")
			help3:SetText("Aide 3: point sauvegarde dans Routes.lua (champ regisseuse)")
			help4:SetText("Aide 4: la regisseuse roam ensuite autour de ce point")
		else
			help1:SetText("Aide 1: Maj+RClick -> ajouter un point")
			if E.mode == "lieu" then
				help2:SetText("Aide 2: Bouton Fin -> finaliser le lieu")
			else
				help2:SetText("Aide 2: Bouton Fin -> finaliser la forme")
			end
			help3:SetText("Aide 3: Maj+Ctrl+RClick -> annuler le dernier point")
			help4:SetText("Aide 4: Maj+Alt+RClick -> reset de la forme courante")
		end
		UpdatePointsButtonText()
		UpdateLieuTypeButtons()
		RefreshLieuRows()
	end

	local function NewDraft(kind)
		if kind == "poi" then
			E.mode = "poi"
			E.draft = nil
		elseif kind == "entry" then
			E.mode = "entry"
			E.draft = nil
		elseif kind == "regisseuse" then
			E.mode = "regisseuse"
			E.draft = nil
		elseif kind == "erase" then
			E.mode = "erase"
			E.draft = nil
		elseif kind == "lieu" then
			E.mode = "lieu"
			E.draft = { kind = "lieu", points = {} }
		else
			E.mode = (kind == "plaza") and "plaza" or "route"
			E.draft = { kind = E.mode, points = {} }
		end
		UpdateStatus()
	end

	local function FinishDraft()
		if E.mode == "poi" then
			return
		end
		if not E.draft then
			return
		end
		local pts = E.draft.points or {}
		local isPlaza = E.draft.kind == "plaza"
		local isLieu = E.draft.kind == "lieu"
		local minPts = (isPlaza or isLieu) and 3 or 2
		if #pts < minPts then
			return
		end
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		local bucket = isPlaza and store.plazas or (isLieu and store.lieux or store.routes)
		local idPrefix = isPlaza and "place_" or (isLieu and "lieu_" or "route_")
		local entry = {
			id = idPrefix .. tostring(#bucket + 1),
			points = CopyPoints(pts),
		}
		if isLieu then
			entry.type = tostring(E.lieuType or "chaumiere")
			local linkId = tostring(E.lieuLinkId or ""):gsub("^%s+", ""):gsub("%s+$", "")
			if linkId == "" then
				linkId = tostring(entry.id or "")
			end
			entry.linkId = linkId
		end
		bucket[#bucket + 1] = entry
		E.draft = { kind = E.mode, points = {} }
		UpdateStatus()
	end

	local function UndoPoint()
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		if E.mode == "poi" then
			if type(store.pois) == "table" and #store.pois > 0 then
				table.remove(store.pois, #store.pois)
			end
			UpdateStatus()
			return
		end
		if E.draft and E.draft.points then
			table.remove(E.draft.points, #E.draft.points)
		end
		UpdateStatus()
	end

	local function ResetDraft()
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		if E.mode == "poi" then
			store.pois = {}
		elseif E.mode == "entry" or E.mode == "regisseuse" then
			E.draft = nil
		else
			E.draft = { kind = E.mode, points = {} }
		end
		UpdateStatus()
	end

	local function ClearMapData()
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		store.routes = {}
		store.plazas = {}
		store.lieux = {}
		store.pois = {}
		store.regisseuse = nil
		if E.mode ~= "poi" and E.mode ~= "entry" and E.mode ~= "regisseuse" then
			E.draft = { kind = E.mode, points = {} }
		else
			E.draft = nil
		end
		UpdateStatus()
	end

	local function ClosestPointOnSegment(u, v, ax, ay, bx, by)
		local dx = bx - ax
		local dy = by - ay
		local len2 = (dx * dx) + (dy * dy)
		if len2 <= 0.0000001 then
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

	local function IsPointInPolygon(points, u, v)
		if type(points) ~= "table" or #points < 3 then
			return false
		end
		local inside = false
		local n = #points
		local j = n
		for i = 1, n do
			local a = points[i]
			local b = points[j]
			local ax = tonumber(a and a.u) or 0
			local ay = tonumber(a and a.v) or 0
			local bx = tonumber(b and b.u) or 0
			local by = tonumber(b and b.v) or 0
			if (ay > v) ~= (by > v) then
				local denom = by - ay
				if math.abs(denom) < 0.000001 then
					denom = (denom < 0) and -0.000001 or 0.000001
				end
				local xAtY = ((bx - ax) * (v - ay) / denom) + ax
				if u < xAtY then
					inside = not inside
				end
			end
			j = i
		end
		return inside
	end

	local function FindContainingAreaInStore(u, v)
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		local plazas = type(store.plazas) == "table" and store.plazas or {}
		for i = 1, #plazas do
			local plaza = plazas[i]
			local points = type(plaza and plaza.points) == "table" and plaza.points or {}
			if #points >= 3 and IsPointInPolygon(points, u, v) then
				return {
					kind = "plaza",
					areaId = tostring(plaza and plaza.id or ("place_" .. i)),
				}
			end
		end
		local lieux = type(store.lieux) == "table" and store.lieux or {}
		for i = 1, #lieux do
			local lieu = lieux[i]
			local points = type(lieu and lieu.points) == "table" and lieu.points or {}
			if #points >= 3 and IsPointInPolygon(points, u, v) then
				return {
					kind = "lieu",
					areaId = tostring(lieu and lieu.id or ("lieu_" .. i)),
				}
			end
		end
		return nil
	end

	local function FindNearestRoutePointInStore(u, v, maxDist)
		local maxD = tonumber(maxDist) or 0.08
		local maxD2 = maxD * maxD
		local best = nil
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		local routes = type(store.routes) == "table" and store.routes or {}
		for i = 1, #routes do
			local route = routes[i]
			local pts = type(route and route.points) == "table" and route.points or {}
			for j = 1, #pts - 1 do
				local a = pts[j]
				local b = pts[j + 1]
				local _, px, py, d2 = ClosestPointOnSegment(
					u,
					v,
					tonumber(a and a.u) or 0,
					tonumber(a and a.v) or 0,
					tonumber(b and b.u) or 0,
					tonumber(b and b.v) or 0
				)
				if d2 <= maxD2 and (not best or d2 < best.d2) then
					best = {
						u = px,
						v = py,
						d2 = d2,
						routeId = tostring(route and route.id or ("route_" .. i)),
					}
				end
			end
		end
		return best
	end

	local function ApplyRouteMagnet(u, v)
		local pu = Clamp(tonumber(u) or 0, 0, 1)
		local pv = Clamp(tonumber(v) or 0, 0, 1)
		local hit = FindNearestRoutePointInStore(pu, pv, ROUTE_POINT_MAGNET_DIST)
		if hit then
			return Clamp(tonumber(hit.u) or pu, 0, 1), Clamp(tonumber(hit.v) or pv, 0, 1), true
		end
		return pu, pv, false
	end

	local function FindNearestAreaPointInStore(u, v, maxDist)
		local maxD = tonumber(maxDist) or 0.08
		local maxD2 = maxD * maxD
		local best = nil
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)

		local function ScanAreas(bucket, kind, fallbackPrefix)
			local areas = type(bucket) == "table" and bucket or {}
			for i = 1, #areas do
				local area = areas[i]
				local points = type(area and area.points) == "table" and area.points or {}
				local areaId = tostring(area and area.id or (fallbackPrefix .. tostring(i)))
				if #points >= 3 and IsPointInPolygon(points, u, v) then
					return {
						u = Clamp(tonumber(u) or 0, 0, 1),
						v = Clamp(tonumber(v) or 0, 0, 1),
						d2 = 0,
						kind = kind,
						areaId = areaId,
					}
				end
				for j = 1, #points do
					local a = points[j]
					local b = points[(j % #points) + 1]
					local _, px, py, d2 = ClosestPointOnSegment(
						u,
						v,
						tonumber(a and a.u) or 0,
						tonumber(a and a.v) or 0,
						tonumber(b and b.u) or 0,
						tonumber(b and b.v) or 0
					)
					if d2 <= maxD2 and (not best or d2 < best.d2) then
						best = {
							u = px,
							v = py,
							d2 = d2,
							kind = kind,
							areaId = areaId,
						}
					end
				end
			end
			return nil
		end

		local hitPlaza = ScanAreas(store.plazas, "plaza", "place_")
		if hitPlaza then
			return hitPlaza
		end
		local hitLieu = ScanAreas(store.lieux, "lieu", "lieu_")
		if hitLieu then
			return hitLieu
		end
		return best
	end

	local function AddPoiAt(u, v)
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		local pu = Clamp(tonumber(u) or 0, 0, 1)
		local pv = Clamp(tonumber(v) or 0, 0, 1)
		local entry = {
			id = "poi_" .. tostring(#store.pois + 1),
			u = pu,
			v = pv,
		}
		local area = FindContainingAreaInStore(pu, pv)
		if area then
			if area.kind == "plaza" then
				entry.plazaId = area.areaId
			elseif area.kind == "lieu" then
				entry.lieuId = area.areaId
			end
		end
		store.pois[#store.pois + 1] = entry
		return true
	end

	local function GetEraseWorldRadius()
		local _, _, uSpan, vSpan = getCamera()
		local vw = viewport:GetWidth() or 0
		local vh = viewport:GetHeight() or 0
		if vw <= 0 or vh <= 0 or uSpan <= 0 or vSpan <= 0 then
			return 0.012
		end
		local pxRadius = 12
		local unitU = uSpan / vw
		local unitV = vSpan / vh
		return math.max(unitU, unitV) * pxRadius
	end

	local function FindNearestShapeSegmentHit(u, v, maxDist)
		local maxDist2 = maxDist * maxDist
		local best = nil

		local function ScanBucket(bucket, closed)
			if type(bucket) ~= "table" then
				return
			end
			for idx = 1, #bucket do
				local entry = bucket[idx]
				local points = type(entry and entry.points) == "table" and entry.points or {}
				local n = #points
				local segCount = closed and n or (n - 1)
				if segCount > 0 then
					for j = 1, segCount do
						local nextIndex = (j < n) and (j + 1) or 1
						local a = points[j]
						local b = points[nextIndex]
						local _, _, _, d2 = ClosestPointOnSegment(
							u,
							v,
							tonumber(a and a.u) or 0,
							tonumber(a and a.v) or 0,
							tonumber(b and b.u) or 0,
							tonumber(b and b.v) or 0
						)
						if d2 <= maxDist2 and (not best or d2 < best.d2) then
							best = {
								d2 = d2,
								bucket = bucket,
								entryIndex = idx,
							}
						end
					end
				end
			end
		end

		ScanBucket(store.routes, false)
		ScanBucket(store.plazas, true)
		ScanBucket(store.lieux, true)
		return best
	end

	local function FindNearestShapePointHit(u, v, maxDist)
		local maxDist2 = maxDist * maxDist
		local best = nil

		local function ScanBucket(bucket, minPoints)
			if type(bucket) ~= "table" then
				return
			end
			for idx = 1, #bucket do
				local entry = bucket[idx]
				local points = type(entry and entry.points) == "table" and entry.points or {}
				for pointIndex = 1, #points do
					local p = points[pointIndex]
					local dx = u - (tonumber(p and p.u) or 0)
					local dy = v - (tonumber(p and p.v) or 0)
					local d2 = (dx * dx) + (dy * dy)
					if d2 <= maxDist2 and (not best or d2 < best.d2) then
						best = {
							d2 = d2,
							bucket = bucket,
							entryIndex = idx,
							pointIndex = pointIndex,
							minPoints = minPoints,
						}
					end
				end
			end
		end

		ScanBucket(store.routes, 2)
		ScanBucket(store.plazas, 3)
		ScanBucket(store.lieux, 3)
		return best
	end

	local function FindNearestPoiPointHit(u, v, maxDist)
		local maxDist2 = maxDist * maxDist
		local best = nil
		local pois = type(store.pois) == "table" and store.pois or {}
		for i = 1, #pois do
			local p = pois[i]
			local dx = u - (tonumber(p and p.u) or 0)
			local dy = v - (tonumber(p and p.v) or 0)
			local d2 = (dx * dx) + (dy * dy)
			if d2 <= maxDist2 and (not best or d2 < best.d2) then
				best = {
					d2 = d2,
					poiIndex = i,
				}
			end
		end
		return best
	end

	local function EraseAt(u, v)
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		local radius = GetEraseWorldRadius()
		local segmentHit = FindNearestShapeSegmentHit(u, v, radius)
		if segmentHit then
			table.remove(segmentHit.bucket, segmentHit.entryIndex)
			return true
		end

		local pointHit = FindNearestShapePointHit(u, v, radius)
		if pointHit then
			local entry = pointHit.bucket[pointHit.entryIndex]
			local points = entry and entry.points
			if type(points) == "table" then
				table.remove(points, pointHit.pointIndex)
				if #points < pointHit.minPoints then
					table.remove(pointHit.bucket, pointHit.entryIndex)
				end
				return true
			end
		end

		local maxDist2 = radius * radius
		local bestEntry = nil
		local lieux = type(store and store.lieux) == "table" and store.lieux or {}
		for i = 1, #lieux do
			local lieu = lieux[i]
			local entries = type(lieu and lieu.entries) == "table" and lieu.entries or {}
			for j = 1, #entries do
				local e = entries[j]
				local dx = u - (tonumber(e and e.u) or 0)
				local dy = v - (tonumber(e and e.v) or 0)
				local d2 = (dx * dx) + (dy * dy)
				local hitRadius = math.max(radius, GetEntryRadius(e))
				if d2 <= (hitRadius * hitRadius) and (not bestEntry or d2 < bestEntry.d2) then
					bestEntry = {
						d2 = d2,
						entries = entries,
						entryIndex = j,
					}
				end
			end
		end
		if bestEntry then
			table.remove(bestEntry.entries, bestEntry.entryIndex)
			return true
		end

		local poiHit = FindNearestPoiPointHit(u, v, radius)
		if poiHit then
			table.remove(store.pois, poiHit.poiIndex)
			return true
		end
		return false
	end

	local function AddLieuEntryAt(u, v)
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		local function FindSelectedLieu()
			local wantedId = tostring(selectedLieuId or "")
			local lieux = type(store and store.lieux) == "table" and store.lieux or {}
			if wantedId ~= "" then
				for i = 1, #lieux do
					local lieu = lieux[i]
					if tostring(lieu and lieu.id or "") == wantedId then
						return lieu, i
					end
				end
			end
			for i = 1, #lieux do
				local lieu = lieux[i]
				local points = type(lieu and lieu.points) == "table" and lieu.points or {}
				if #points >= 3 and IsPointInPolygon(points, u, v) then
					selectedLieuId = tostring(lieu and lieu.id or ("lieu_" .. i))
					return lieu, i
				end
			end
			return nil, nil
		end

		local lieu = select(1, FindSelectedLieu())
		if not lieu then
			status:SetText("Selectionne un lieu avant d'ajouter une entree")
			return false
		end

		local points = type(lieu.points) == "table" and lieu.points or {}
		local edgeU, edgeV = Clamp(tonumber(u) or 0, 0, 1), Clamp(tonumber(v) or 0, 0, 1)
		if #points >= 2 then
			local bestDist2 = nil
			for i = 1, #points do
				local a = points[i]
				local b = points[(i % #points) + 1]
				local _, px, py, dist2 = ClosestPointOnSegment(
					edgeU,
					edgeV,
					tonumber(a and a.u) or 0,
					tonumber(a and a.v) or 0,
					tonumber(b and b.u) or 0,
					tonumber(b and b.v) or 0
				)
				if (not bestDist2) or dist2 < bestDist2 then
					bestDist2 = dist2
					edgeU = px
					edgeV = py
				end
			end
		end
		local function FindBestJunction(maxDist)
			local bestHit = nil
			local bestEdgeU, bestEdgeV = edgeU, edgeV
			local first = FindNearestRoutePointInStore(edgeU, edgeV, maxDist)
			if first then
				bestHit = first
			end
			if #points >= 2 then
				local function TryCandidate(cu, cv)
					local hit = FindNearestRoutePointInStore(cu, cv, maxDist)
					if hit and ((not bestHit) or (tonumber(hit.d2) or math.huge) < (tonumber(bestHit.d2) or math.huge)) then
						bestHit = hit
						bestEdgeU = cu
						bestEdgeV = cv
					end
				end
				for i = 1, #points do
					local a = points[i]
					local b = points[(i % #points) + 1]
					local au = Clamp(tonumber(a and a.u) or 0, 0, 1)
					local av = Clamp(tonumber(a and a.v) or 0, 0, 1)
					local bu = Clamp(tonumber(b and b.u) or 0, 0, 1)
					local bv = Clamp(tonumber(b and b.v) or 0, 0, 1)
					TryCandidate(au, av)
					TryCandidate((au + bu) * 0.5, (av + bv) * 0.5)
				end
			end
			return bestHit, bestEdgeU, bestEdgeV
		end

		local routeHit, junctionEdgeU, junctionEdgeV = FindBestJunction(ENTRY_ROUTE_NEAR_DIST)
		if not routeHit then
			routeHit, junctionEdgeU, junctionEdgeV = FindBestJunction(ENTRY_ROUTE_FALLBACK_DIST)
		end
		if not routeHit then
			status:SetText("Entree refusee: aucune route proche du bord du lieu")
			return false
		end
		local routeU = Clamp(tonumber(routeHit.u) or junctionEdgeU, 0, 1)
		local routeV = Clamp(tonumber(routeHit.v) or junctionEdgeV, 0, 1)
		local centerU = Clamp((junctionEdgeU + routeU) * 0.5, 0, 1)
		local centerV = Clamp((junctionEdgeV + routeV) * 0.5, 0, 1)
		local dx = junctionEdgeU - routeU
		local dy = junctionEdgeV - routeV
		local dist = math.sqrt((dx * dx) + (dy * dy))
		local zoneRadius = Clamp(math.max(ENTRY_ZONE_DEFAULT_RADIUS, dist * 0.60), ENTRY_ZONE_MIN_RADIUS, ENTRY_ZONE_MAX_RADIUS)

		if type(lieu.entries) ~= "table" then
			lieu.entries = {}
		end
		lieu.entries[#lieu.entries + 1] = {
			id = "entry_" .. tostring(#lieu.entries + 1),
			u = centerU,
			v = centerV,
			radius = zoneRadius,
			routeId = tostring(routeHit.routeId or ""),
		}
		status:SetText("Entree zone creee (jonction route/batiment)")
		return true
	end

	local function CursorToWorld()
		local u1, v1, uSpan, vSpan = getCamera()
		local vw = viewport:GetWidth() or 0
		local vh = viewport:GetHeight() or 0
		if vw <= 0 or vh <= 0 or uSpan <= 0 or vSpan <= 0 then
			return nil, nil
		end
		local x, y = GetCursorPosition()
		local es = dragger:GetEffectiveScale() or 1
		x = x / es
		y = y / es
		local left = viewport:GetLeft() or 0
		local bottom = viewport:GetBottom() or 0
		local lx = Clamp(x - left, 0, vw)
		local ly = Clamp(y - bottom, 0, vh)
		local nx = Clamp(lx / vw, 0, 1)
		local nyTop = Clamp(1 - (ly / vh), 0, 1)
		local u = u1 + (nx * uSpan)
		local v = v1 + (nyTop * vSpan)
		return Clamp(u, 0, 1), Clamp(v, 0, 1)
	end

	function E.Render()
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		lineUsed = 0
		dotUsed = 0
		if E.showOverlayPoints then
			if type(store.routes) == "table" then
				for i = 1, #store.routes do
					local r = store.routes[i]
					DrawShape(r and r.points, false, 0.12, 0.85, 1.00, 0.95)
				end
			end
			if type(store.plazas) == "table" then
				for i = 1, #store.plazas do
					local p = store.plazas[i]
					DrawShape(p and p.points, true, 1.00, 0.70, 0.20, 0.95)
				end
			end
			if type(store.lieux) == "table" then
				for i = 1, #store.lieux do
					local l = store.lieux[i]
					local lId = tostring(l and l.id or ("lieu_" .. i))
					if selectedLieuId ~= nil and selectedLieuId ~= "" and lId == selectedLieuId then
						DrawShape(l and l.points, true, 1.00, 0.90, 0.18, 1.00)
					else
					local lType = tostring(l and l.type or "chaumiere")
					if lType == "taverne" then
						DrawShape(l and l.points, true, 0.96, 0.42, 0.18, 0.95)
					elseif lType == "auberge" then
						DrawShape(l and l.points, true, 0.86, 0.64, 0.12, 0.95)
					else
						DrawShape(l and l.points, true, 0.42, 0.88, 0.42, 0.95)
					end
					end
					local entries = type(l and l.entries) == "table" and l.entries or {}
					if #entries > 0 then
						if selectedLieuId ~= nil and selectedLieuId ~= "" and lId == selectedLieuId then
							DrawEntryZones(entries, 1.00, 0.95, 0.25, 0.75, 4)
						else
							DrawEntryZones(entries, 0.10, 0.88, 1.00, 0.68, 0)
						end
					end
				end
			end
			if type(store.pois) == "table" and #store.pois > 0 then
				DrawPoiActionRings(store.pois, GetPoiActionRadius(), 1.00, 0.12, 0.12, 0.35, 1.25, 20)
				DrawPoints(store.pois, 1.00, 0.10, 0.10, 1.00, 8)
			end
			if type(store.regisseuse) == "table" then
				local ru = tonumber(store.regisseuse.u)
				local rv = tonumber(store.regisseuse.v)
				if ru and rv then
					DrawPoints({
						{ u = Clamp(ru, 0, 1), v = Clamp(rv, 0, 1) },
					}, 1.00, 0.00, 1.00, 1.00, 12)
				end
			end
			if E.mode ~= "poi" and E.draft and type(E.draft.points) == "table" then
				local closed = (E.draft.kind == "plaza") or (E.draft.kind == "lieu")
				if E.draft.kind == "lieu" then
					if tostring(E.lieuType) == "taverne" then
						DrawShape(E.draft.points, closed, 0.98, 0.54, 0.28, 1.00)
					elseif tostring(E.lieuType) == "auberge" then
						DrawShape(E.draft.points, closed, 0.92, 0.70, 0.22, 1.00)
					else
						DrawShape(E.draft.points, closed, 0.56, 0.94, 0.56, 1.00)
					end
				else
					DrawShape(E.draft.points, closed, 1.00, 1.00, 0.20, 1.00)
				end
			end
		end
		DrawNpcDebugPaths()
		HideUnused()
	end

	function E.RefreshVisibility()
		local on = E:IsDevMode()
		local shown = on and E:IsEditorOpen()
		local changed = (E._shown ~= shown)
		E._shown = shown
		toggleBtn:SetShown(on)
		toggleBtn:EnableMouse(on)
		overlay:SetShown(shown)
		toolbar:SetShown(shown)
		if not shown then
			exportFrame:Hide()
		elseif changed then
			E.Render()
		end
	end

	function E.Update(elapsed)
		local dt = tonumber(elapsed) or 0
		E._visElapsed = (E._visElapsed or 0) + dt
		E._renderElapsed = (E._renderElapsed or 0) + dt
		if E._visElapsed >= 0.5 then
			E._visElapsed = 0
			E.RefreshVisibility()
		end
		if E._shown and E._renderElapsed >= 0.10 then
			E._renderElapsed = 0
			E.Render()
		end
	end

	function E:SetPointsVisible(visible)
		E.showOverlayPoints = (visible ~= false)
		UpdateStatus()
		E.Render()
	end

	function E:TogglePointsVisible()
		E:SetPointsVisible(not E.showOverlayPoints)
	end

	routeBtn:SetScript("OnClick", function()
		NewDraft("route")
		E.Render()
	end)
	plazaBtn:SetScript("OnClick", function()
		NewDraft("plaza")
		E.Render()
	end)
	lieuBtn:SetScript("OnClick", function()
		NewDraft("lieu")
		E.Render()
	end)
	poiBtn:SetScript("OnClick", function()
		NewDraft("poi")
		E.Render()
	end)
	regisseuseBtn:SetScript("OnClick", function()
		NewDraft("regisseuse")
		E.Render()
	end)
	entryBtn:SetScript("OnClick", function()
		NewDraft("entry")
		E.Render()
	end)
	eraseBtn:SetScript("OnClick", function()
		NewDraft("erase")
		E.Render()
	end)
	chaumiereBtn:SetScript("OnClick", function()
		E.lieuType = "chaumiere"
		if E.mode == "lieu" then
			NewDraft("lieu")
		else
			UpdateStatus()
		end
		E.Render()
	end)
	taverneBtn:SetScript("OnClick", function()
		E.lieuType = "taverne"
		if E.mode == "lieu" then
			NewDraft("lieu")
		else
			UpdateStatus()
		end
		E.Render()
	end)
	aubergeBtn:SetScript("OnClick", function()
		E.lieuType = "auberge"
		if E.mode == "lieu" then
			NewDraft("lieu")
		else
			UpdateStatus()
		end
		E.Render()
	end)
	finishBtn:SetScript("OnClick", function()
		FinishDraft()
		E.Render()
	end)
	undoBtn:SetScript("OnClick", function()
		UndoPoint()
		E.Render()
	end)
	pointsBtn:SetScript("OnClick", function()
		E:TogglePointsVisible()
	end)
	exportBtn:SetScript("OnClick", function()
		activeMapId = GetMapId()
		exportEdit:SetText(BuildExportText(nil, activeMapId))
		exportFrame:Show()
		exportEdit:SetFocus()
		exportEdit:HighlightText()
	end)
	clearBtn:SetScript("OnClick", function()
		ClearMapData()
		E.Render()
	end)
	lieuPrevBtn:SetScript("OnClick", function()
		lieuListOffset = math.max(0, (lieuListOffset or 0) - 1)
		UpdateStatus()
	end)
	lieuNextBtn:SetScript("OnClick", function()
		lieuListOffset = (lieuListOffset or 0) + 1
		UpdateStatus()
	end)
	local function ApplySelectedLieuLink()
		local zoneId = tostring(selectedLieuId or "")
		if zoneId == "" then
			status:SetText("Selectionne une zone")
			return false
		end
		activeMapId = GetMapId()
		store = EnsureMapStore(activeMapId)
		local lieux = type(store and store.lieux) == "table" and store.lieux or {}
		local nextLinkId = tostring(lieuLinkInput:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if nextLinkId == "" then
			status:SetText("ID liaison requis")
			return false
		end
		for i = 1, #lieux do
			local lieu = lieux[i]
			local lieuId = tostring(lieu and lieu.id or "")
			if lieuId == zoneId then
				lieu.linkId = nextLinkId
				E.lieuLinkId = nextLinkId
				status:SetText("Zone liee: " .. zoneId .. " -> " .. nextLinkId)
				UpdateStatus()
				E.Render()
				return true
			end
		end
		status:SetText("Zone introuvable")
		return false
	end

	lieuApplyBtn:SetScript("OnClick", function()
		ApplySelectedLieuLink()
	end)

	lieuLinkInput:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		ApplySelectedLieuLink()
	end)
	lieuLinkInput:SetScript("OnEditFocusLost", function()
		ApplySelectedLieuLink()
	end)

	dragger:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown")
	dragger:HookScript("OnMouseDown", function(_, button)
		if shouldBlockRightClick then
			local ok, blocked = pcall(shouldBlockRightClick, button)
			if ok and blocked and E.mode ~= "regisseuse" then
				return
			end
		end
		if button ~= "RightButton" or not E:IsDevMode() or not E:IsEditorOpen() then
			return
		end
		local hasShift = IsShiftKeyDown and IsShiftKeyDown()
		if not hasShift then
			return
		end
		if IsControlKeyDown and IsControlKeyDown() then
			UndoPoint()
			E.Render()
			return
		end
		if IsAltKeyDown and IsAltKeyDown() then
			ResetDraft()
			E.Render()
			return
		end
		local u, v = CursorToWorld()
		if not (u and v) then
			return
		end
		if E.mode == "poi" then
			if AddPoiAt(u, v) then
				UpdateStatus()
				E.Render()
			end
			return
		end
		if E.mode == "entry" then
			if AddLieuEntryAt(u, v) then
				UpdateStatus()
				E.Render()
			end
			return
		end
		if E.mode == "regisseuse" then
			activeMapId = GetMapId()
			store = EnsureMapStore(activeMapId)
			store.regisseuse = { u = Clamp(u, 0, 1), v = Clamp(v, 0, 1) }
			if type(setRegisseuseAnchor) ~= "function" then
				UpdateStatus()
				status:SetText("Point regisseuse place (runtime indisponible)")
				E.Render()
				return
			end
			local ok, resultOrErr = setRegisseuseAnchor(u, v)
			UpdateStatus()
			if ok then
				status:SetText("Point regisseuse defini (remplacement auto)")
			else
				local reason = tostring(resultOrErr or "erreur")
				status:SetText("Regisseuse: " .. reason)
			end
			E.Render()
			return
		end
		if E.mode == "erase" then
			if EraseAt(u, v) then
				UpdateStatus()
				E.Render()
			end
			return
		end
		if not E.draft then
			NewDraft(E.mode)
		end
		if E.mode == "route" then
			u, v = ApplyRouteMagnet(u, v)
		end
		E.draft.points[#E.draft.points + 1] = { u = u, v = v }
		UpdateStatus()
		E.Render()
	end)

	UpdateStatus()
	E.RefreshVisibility()
	E.Render()
	return E
end
