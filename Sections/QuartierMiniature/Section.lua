local ADDON, ns = ...
ns.Sections = ns.Sections or {}
local Sections = ns.Sections

function Sections.QuartierMiniature(parent)
	local f = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureSection", parent)
	f:SetAllPoints(parent)
	f:Hide()

	local viewport = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureViewport", f)
	viewport:SetAllPoints(f)
	viewport:SetClipsChildren(true)
	viewport:EnableMouse(true)
	viewport:EnableMouseWheel(true)

	local mapLayer = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureMapLayer", viewport)
	mapLayer:SetAllPoints(viewport)
	mapLayer:SetFrameLevel(viewport:GetFrameLevel() + 1)

	local chromeLayer = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureChromeLayer", viewport)
	chromeLayer:SetAllPoints(viewport)
	chromeLayer:SetFrameLevel(mapLayer:GetFrameLevel() + 20)
	chromeLayer:EnableMouse(false)

	local hudLayer = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureHUDLayer", f)
	hudLayer:SetAllPoints(f)
	hudLayer:SetFrameStrata(f:GetFrameStrata())
	hudLayer:SetFrameLevel((chromeLayer:GetFrameLevel() or 1) + 30)
	hudLayer:EnableMouse(false)

	local backgroundLayer = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureBackgroundLayer", mapLayer)
	backgroundLayer:SetAllPoints(viewport)
	backgroundLayer:SetFrameLevel(mapLayer:GetFrameLevel() + 1)
	backgroundLayer:EnableMouse(false)

	local models3DLayer = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureModels3DLayer", mapLayer)
	models3DLayer:SetAllPoints(viewport)
	models3DLayer:SetFrameLevel(mapLayer:GetFrameLevel() + 6)
	models3DLayer:EnableMouse(false)

	local models3DHoverLayer = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureModels3DHoverLayer", mapLayer)
	models3DHoverLayer:SetAllPoints(viewport)
	models3DHoverLayer:SetFrameLevel(mapLayer:GetFrameLevel() + 8)
	models3DHoverLayer:EnableMouse(false)

	local npcLayerHost = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureNpcLayerHost", mapLayer)
	npcLayerHost:SetAllPoints(viewport)
	npcLayerHost:SetFrameLevel(mapLayer:GetFrameLevel() + 10)
	npcLayerHost:EnableMouse(false)

	local pathfindingLayer = CreateFrame("Frame", "WoWGuilde_QuartierMiniaturePathfindingLayer", mapLayer)
	pathfindingLayer:SetAllPoints(viewport)
	pathfindingLayer:SetFrameLevel(mapLayer:GetFrameLevel() + 12)
	pathfindingLayer:EnableMouse(false)

	local shadowOverlayLayer = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureShadowOverlayLayer", viewport)
	shadowOverlayLayer:SetAllPoints(viewport)
	shadowOverlayLayer:SetFrameLevel(mapLayer:GetFrameLevel() + 500)
	shadowOverlayLayer:EnableMouse(false)

	local cfg = (ns.QuartierMiniature and ns.QuartierMiniature.Config) or {}
	local currentBaseW = tonumber(cfg.mapWidth) or 1360
	local currentBaseH = tonumber(cfg.mapHeight) or 784
	local currentTexPath = cfg.backgroundPath
		or "Interface\\AddOns\\WoWGuilde\\Media\\MiniGames\\QuartierMiniature\\LittleVillage_Background_01.tga"
	local currentMapId = nil
	local nineCfg = cfg.nineSlice or {}
	local zoomCfg = cfg.zoom or {}
	local npcCfg = cfg.npc or {}
	local timeCfg = cfg.time or {}
	local inspectorCfg = (type(npcCfg.inspector) == "table") and npcCfg.inspector or {}
	local npcUpdateStep = Clamp(tonumber(npcCfg.updateStep) or 0.040, 0.010, 0.120)
	local npcMaxCatchupSteps = math.max(1, math.floor(tonumber(npcCfg.maxCatchupSteps) or 2))
	local inspectorRefreshStep = Clamp(tonumber(inspectorCfg.refreshInterval) or 0.20, 0.04, 1.50)
	local function GetActiveMapId()
		local liveCfg = (ns.QuartierMiniature and ns.QuartierMiniature.Config) or cfg
		local id = liveCfg and liveCfg.mapId or nil
		if type(id) ~= "string" or id == "" then
			return "default"
		end
		return id
	end
	local function GetActiveMapConfig()
		local liveCfg = (ns.QuartierMiniature and ns.QuartierMiniature.Config) or cfg
		local mapId = GetActiveMapId()
		local maps = type(liveCfg.maps) == "table" and liveCfg.maps or nil
		local mapCfg = (maps and type(maps[mapId]) == "table") and maps[mapId] or nil
		local w = tonumber(mapCfg and mapCfg.mapWidth) or tonumber(liveCfg.mapWidth) or 1360
		local h = tonumber(mapCfg and mapCfg.mapHeight) or tonumber(liveCfg.mapHeight) or 784
		local tex = mapCfg and mapCfg.backgroundPath or liveCfg.backgroundPath
		if type(tex) ~= "string" or tex == "" then
			tex = "Interface\\AddOns\\WoWGuilde\\Media\\MiniGames\\QuartierMiniature\\LittleVillage_Background_01.tga"
		end
		return mapId, w, h, tex
	end
	local function RefreshMapAssets(force)
		local mapId, w, h, tex = GetActiveMapConfig()
		if
			not force
			and mapId == currentMapId
			and w == currentBaseW
			and h == currentBaseH
			and tex == currentTexPath
		then
			return false
		end
		currentMapId = mapId
		currentBaseW = w
		currentBaseH = h
		currentTexPath = tex
		return true
	end
	local zoomMinFactor = tonumber(zoomCfg.minFactor) or 1.0
	local zoomMaxFactor = tonumber(zoomCfg.maxFactor) or 2.0
	local zoomWheelFactor = tonumber(zoomCfg.wheelFactor) or 1.08
	if zoomMinFactor < 1 then
		zoomMinFactor = 1
	end
	if zoomMaxFactor < zoomMinFactor then
		zoomMaxFactor = zoomMinFactor
	end

	local canvas = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureCanvas", backgroundLayer)
	canvas:SetAllPoints(viewport)

	local mapBg = canvas:CreateTexture(nil, "BACKGROUND")
	mapBg:SetAllPoints(canvas)
	mapBg:SetTexture(currentTexPath)
	local MAP_BG_DEFAULT_R, MAP_BG_DEFAULT_G, MAP_BG_DEFAULT_B, MAP_BG_DEFAULT_A = 0.702, 0.702, 0.702, 1
	mapBg:SetVertexColor(MAP_BG_DEFAULT_R, MAP_BG_DEFAULT_G, MAP_BG_DEFAULT_B, MAP_BG_DEFAULT_A)

	-- Ordre des couches (bas -> haut):
	-- 1) Fond (canvas/mapBg)
	-- 2) Modeles 3D
	-- 3) Modeles 3D Hover (survol lieux)
	-- 4) PNJ
	-- 5) Ombre "collections-background-shadow-large"
	local innerShadow =
		shadowOverlayLayer:CreateTexture("WoWGuilde_QuartierMiniatureShadowOverlayTexture", "ARTWORK", nil, 1)
	innerShadow:SetAllPoints(shadowOverlayLayer)
	innerShadow:SetAtlas("collections-background-shadow-large")
	innerShadow:SetAlpha(0.95)

	local panelNineSlice
	local panelPieces = {}

	local function CopyTextureStyle(srcTex, dstTex, alpha)
		if not (srcTex and dstTex) then
			return
		end
		local atlas = srcTex.GetAtlas and srcTex:GetAtlas() or nil
		if atlas and atlas ~= "" and dstTex.SetAtlas then
			dstTex:SetAtlas(atlas)
		else
			local tex = srcTex.GetTexture and srcTex:GetTexture() or nil
			if tex and dstTex.SetTexture then
				dstTex:SetTexture(tex)
			end
			if srcTex.GetTexCoord and dstTex.SetTexCoord then
				local l, r, t, b = srcTex:GetTexCoord()
				dstTex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
			end
		end
		if srcTex.GetVertexColor and dstTex.SetVertexColor then
			local vr, vg, vb, va = srcTex:GetVertexColor()
			dstTex:SetVertexColor(vr or 1, vg or 1, vb or 1, (va or 1) * (alpha or 1))
		elseif dstTex.SetAlpha then
			dstTex:SetAlpha(alpha or 1)
		end
		if srcTex.GetBlendMode and dstTex.SetBlendMode then
			dstTex:SetBlendMode(srcTex:GetBlendMode() or "BLEND")
		end
		dstTex:Show()
	end

	local function GetSourceNineSlice()
		local srcInset = _G.WoWGuilde_MainFrameInset
		local srcNine = srcInset and srcInset.NineSlice or nil
		if srcNine then
			return srcNine
		end
		local mainFrame = _G.WoWGuilde_MainFrame
		return mainFrame and mainFrame.Inset and mainFrame.Inset.NineSlice or nil
	end

	local function EnsurePiece(name, layer, subLevel)
		local p = panelPieces[name]
		if p then
			return p
		end
		p = panelNineSlice:CreateTexture(nil, layer or "OVERLAY", nil, subLevel or 0)
		panelPieces[name] = p
		return p
	end

	local function SafeSize(srcPiece, fallbackW, fallbackH)
		if srcPiece and srcPiece.GetSize then
			local w, h = srcPiece:GetSize()
			if w and h and w > 0 and h > 0 then
				return w, h
			end
		end
		return fallbackW, fallbackH
	end

	local function ApplyInspiredNineSlice()
		if not panelNineSlice then
			return
		end
		local srcNine = GetSourceNineSlice()
		if not srcNine then
			panelNineSlice:Hide()
			return
		end
		panelNineSlice:Show()
		local alpha = tonumber(nineCfg.alpha) or 1

		local srcTL = srcNine.TopLeftCorner
		local srcTR = srcNine.TopRightCorner
		local srcBL = srcNine.BottomLeftCorner
		local srcBR = srcNine.BottomRightCorner
		local srcTop = srcNine.TopEdge
		local srcBottom = srcNine.BottomEdge
		local srcLeft = srcNine.LeftEdge
		local srcRight = srcNine.RightEdge
		local srcCenter = srcNine.Center

		local tl = EnsurePiece("TopLeftCorner", "OVERLAY", 3)
		local tr = EnsurePiece("TopRightCorner", "OVERLAY", 3)
		local bl = EnsurePiece("BottomLeftCorner", "OVERLAY", 3)
		local br = EnsurePiece("BottomRightCorner", "OVERLAY", 3)
		local top = EnsurePiece("TopEdge", "OVERLAY", 2)
		local bottom = EnsurePiece("BottomEdge", "OVERLAY", 2)
		local left = EnsurePiece("LeftEdge", "OVERLAY", 2)
		local right = EnsurePiece("RightEdge", "OVERLAY", 2)
		local center = EnsurePiece("Center", "OVERLAY", 1)

		CopyTextureStyle(srcTL, tl, alpha)
		CopyTextureStyle(srcTR, tr, alpha)
		CopyTextureStyle(srcBL, bl, alpha)
		CopyTextureStyle(srcBR, br, alpha)
		CopyTextureStyle(srcTop, top, alpha)
		CopyTextureStyle(srcBottom, bottom, alpha)
		CopyTextureStyle(srcLeft, left, alpha)
		CopyTextureStyle(srcRight, right, alpha)
		CopyTextureStyle(srcCenter, center, alpha)

		local tlw, tlh = SafeSize(srcTL, 28, 28)
		local trw, trh = SafeSize(srcTR, 28, 28)
		local blw, blh = SafeSize(srcBL, 28, 28)
		local brw, brh = SafeSize(srcBR, 28, 28)
		local _, topH = SafeSize(srcTop, 28, 16)
		local _, bottomH = SafeSize(srcBottom, 28, 16)
		local leftW = select(1, SafeSize(srcLeft, 16, 28))
		local rightW = select(1, SafeSize(srcRight, 16, 28))

		tl:ClearAllPoints()
		tl:SetPoint("TOPLEFT", panelNineSlice, "TOPLEFT", 0, 0)
		tl:SetSize(tlw, tlh)

		tr:ClearAllPoints()
		tr:SetPoint("TOPRIGHT", panelNineSlice, "TOPRIGHT", 0, 0)
		tr:SetSize(trw, trh)

		bl:ClearAllPoints()
		bl:SetPoint("BOTTOMLEFT", panelNineSlice, "BOTTOMLEFT", 0, 0)
		bl:SetSize(blw, blh)

		br:ClearAllPoints()
		br:SetPoint("BOTTOMRIGHT", panelNineSlice, "BOTTOMRIGHT", 0, 0)
		br:SetSize(brw, brh)

		top:ClearAllPoints()
		top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
		top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
		top:SetHeight(topH)

		bottom:ClearAllPoints()
		bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
		bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
		bottom:SetHeight(bottomH)

		left:ClearAllPoints()
		left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
		left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
		left:SetWidth(leftW)

		right:ClearAllPoints()
		right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
		right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
		right:SetWidth(rightW)

		center:ClearAllPoints()
		center:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
		center:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
	end

	if nineCfg.enabled ~= false then
		panelNineSlice = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureViewportNineSlice", f)
		local inset = tonumber(nineCfg.inset) or 0
		panelNineSlice:SetPoint("TOPLEFT", viewport, "TOPLEFT", inset, -inset)
		panelNineSlice:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMRIGHT", -inset, inset)
		panelNineSlice:SetFrameStrata(f:GetFrameStrata())
		panelNineSlice:SetFrameLevel(viewport:GetFrameLevel() + (tonumber(nineCfg.frameLevelOffset) or 50))
		panelNineSlice:EnableMouse(false)
	end

	local Npc_RenderAll
	local Npc_UpdateAndRender
	local routeEditor
	local npcInspector
	local objectScene
	local objectEditor
	local npcRuntime
	local dayCycleRuntime
	local timeHudLine
	local offlineCoordinator

	local state = {
		zoom = math.max(1, zoomMinFactor),
		minZoom = math.max(1, zoomMinFactor),
		maxZoom = math.max(math.max(1, zoomMinFactor), zoomMaxFactor),
		cx = 0.5,
		cy = 0.5,
		u1 = 0,
		uSpan = 1,
		v1 = 0,
		vSpan = 1,
		zoomPivotNX = 0.5,
		zoomPivotNYTop = 0.5,
		dragging = false,
		objectDragging = false,
		dragStartX = 0,
		dragStartY = 0,
		dragOriginCx = 0.5,
		dragOriginCy = 0.5,
		dragUSpan = 1,
		dragVSpan = 1,
		leftDownAt = 0,
		leftDownViewportX = 0,
		leftDownViewportY = 0,
	}

	local function Clamp(v, minV, maxV)
		if v < minV then
			return minV
		end
		if v > maxV then
			return maxV
		end
		return v
	end

	local timeHud = CreateFrame("Frame", nil, hudLayer)
	timeHud:SetSize(340, 20)
	timeHud:SetPoint("TOP", viewport, "TOP", 0, -10)
	timeHud:SetFrameStrata(f:GetFrameStrata())
	timeHud:SetFrameLevel((hudLayer:GetFrameLevel() or 1) + 2)
	timeHud:EnableMouse(false)
	timeHudLine = timeHud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	timeHudLine:SetPoint("CENTER", timeHud, "CENTER", 0, 0)
	timeHudLine:SetText("")
	timeHudLine:SetJustifyH("CENTER")
	local iconTimeTintR, iconTimeTintG, iconTimeTintB, iconTimeTintA = 1, 1, 1, 1
	local loadingOverlayRuntime = nil
	local PORTRAIT_TIMELINE_TEXTURE_PATH =
		"Interface\\AddOns\\WoWGuilde\\Media\\MiniGames\\QuartierMiniature\\Timeline.tga"
	local PORTRAIT_TIMELINE_NATIVE_W = 2048
	local PORTRAIT_TIMELINE_NATIVE_H = 143
	local PORTRAIT_TIMELINE_ASPECT = PORTRAIT_TIMELINE_NATIVE_W / PORTRAIT_TIMELINE_NATIVE_H
	local PORTRAIT_TIMELINE_VISIBLE_SCALE = 0.84
	local PORTRAIT_TIMELINE_OFFSET_Y = 2
	local PORTRAIT_TIMELINE_SMOOTH_TAU_SEC = 0.45
	local PORTRAIT_TIMELINE_MAX_SPEED_PER_SEC = 0.20
	local portraitTimeline = {
		texture = nil,
		mask = nil,
		portrait = nil,
		parent = nil,
		disabled = false,
		warnedNoPortrait = false,
		warnedNoTexture = false,
		displayProgress = nil,
		lastUpdateAt = 0,
	}

	local function IsDevModeEnabled()
		return (ns and ns.Utils and ns.Utils.IsDevMode and ns.Utils.IsDevMode()) == true
	end

	local function DebugTimeline(msg)
		if not IsDevModeEnabled() then
			return
		end
		if print then
			pcall(print, "|cffffd100[WoWGuilde]|r QM Timeline: " .. tostring(msg or ""))
		end
	end

	local function ParseTimeTextProgressMidnight01(text)
		local h, m = string.match(tostring(text or ""), "^(%d%d):(%d%d)$")
		if not h then
			h, m = string.match(tostring(text or ""), "^(%d):(%d%d)$")
		end
		local hour = tonumber(h)
		local minute = tonumber(m)
		if not (hour and minute) then
			return nil
		end
		hour = Clamp(hour, 0, 23)
		minute = Clamp(minute, 0, 59)
		return ((hour * 60) + minute) / 1440
	end

	local function GetMainFramePortraitTexture()
		local direct = _G.WoWGuilde_MainFramePortrait
		if direct and direct.GetObjectType and direct:GetObjectType() == "Texture" then
			return direct, direct:GetParent()
		end
		local mainFrame = _G.WoWGuilde_MainFrame
		local container = mainFrame and mainFrame.PortraitContainer
		local fallback = container and container.portrait
		if fallback and fallback.GetObjectType and fallback:GetObjectType() == "Texture" then
			return fallback, (container or fallback:GetParent())
		end
		return nil, nil
	end

	local function EnsurePortraitTimeline()
		if portraitTimeline.disabled then
			return nil
		end
		local portrait, parent = GetMainFramePortraitTexture()
		if not (portrait and parent and parent.CreateTexture) then
			if not portraitTimeline.warnedNoPortrait then
				portraitTimeline.warnedNoPortrait = true
				DebugTimeline("ana portre bulunamadi (tekrar deneniyor)")
			end
			return nil
		end
		portraitTimeline.warnedNoPortrait = false

		local tex = portraitTimeline.texture
		if not tex then
			tex = parent:CreateTexture(nil, "ARTWORK", nil, 1)
			portraitTimeline.texture = tex
		else
			if tex.SetParent then
				tex:SetParent(parent)
			end
		end
		tex:SetTexture(PORTRAIT_TIMELINE_TEXTURE_PATH)
		if tex.SetDrawLayer then
			local pLayer, pSubLevel = portrait:GetDrawLayer()
			tex:SetDrawLayer(pLayer or "ARTWORK", (tonumber(pSubLevel) or 0) + 1)
		end
		tex:SetBlendMode("BLEND")
		tex:SetAlpha(1)
		tex:SetTexCoord(0, 1, 0, 1)

		local loadedTex = tex.GetTexture and tex:GetTexture() or nil
		if not loadedTex then
			if not portraitTimeline.warnedNoTexture then
				portraitTimeline.warnedNoTexture = true
				portraitTimeline.disabled = true
				tex:Hide()
				DebugTimeline("doku yok: " .. PORTRAIT_TIMELINE_TEXTURE_PATH)
			end
			return nil
		end

		local mask = portraitTimeline.mask
		if not mask then
			mask = parent:CreateMaskTexture(nil, "ARTWORK")
			portraitTimeline.mask = mask
		else
			if mask.SetParent then
				mask:SetParent(parent)
			end
		end
		local pw = math.max(1, tonumber(portrait:GetWidth()) or 1)
		local ph = math.max(1, tonumber(portrait:GetHeight()) or 1)
		local visibleW = math.max(2, pw * PORTRAIT_TIMELINE_VISIBLE_SCALE)
		local visibleH = math.max(2, ph * PORTRAIT_TIMELINE_VISIBLE_SCALE)
		mask:ClearAllPoints()
		mask:SetPoint("CENTER", portrait, "CENTER", 0, PORTRAIT_TIMELINE_OFFSET_Y)
		mask:SetSize(visibleW, visibleH)
		mask:SetTexture(
			"Interface\\CharacterFrame\\TempPortraitAlphaMask",
			"CLAMPTOBLACKADDITIVE",
			"CLAMPTOBLACKADDITIVE"
		)
		if tex.RemoveMaskTexture then
			pcall(tex.RemoveMaskTexture, tex, mask)
		end
		if tex.AddMaskTexture then
			tex:AddMaskTexture(mask)
		end

		portraitTimeline.portrait = portrait
		portraitTimeline.parent = parent
		return tex
	end

	local function SetPortraitTimelineVisible(flag)
		local tex = portraitTimeline.texture
		if not tex and flag == true then
			tex = EnsurePortraitTimeline()
		end
		if not tex then
			return
		end
		local show = flag == true and f:IsShown()
		local mainFrame = _G.WoWGuilde_MainFrame
		if show and mainFrame and mainFrame.IsShown and not mainFrame:IsShown() then
			show = false
		end
		if show then
			tex:Show()
		else
			tex:Hide()
		end
	end

	local function ResolvePortraitTimelineProgress(dayState)
		if type(dayState) ~= "table" then
			return nil
		end
		local p = tonumber(dayState.clockProgressMidnight01)
		if p then
			return (p % 1 + 1) % 1
		end
		local minute = tonumber(dayState.clockMinuteOfDay)
		if minute then
			return Clamp(minute, 0, 1439) / 1440
		end
		return ParseTimeTextProgressMidnight01(dayState.timeText)
	end

	local function Normalize01(v)
		local x = tonumber(v) or 0
		x = x % 1
		if x < 0 then
			x = x + 1
		end
		return x
	end

	local function CircularDelta01(target, current)
		local d = Normalize01(target) - Normalize01(current)
		d = (d + 0.5) % 1
		if d < 0 then
			d = d + 1
		end
		return d - 0.5
	end

	local function UpdatePortraitTimelineFromState(dayState)
		local progress = ResolvePortraitTimelineProgress(dayState)
		if type(progress) ~= "number" then
			SetPortraitTimelineVisible(false)
			return
		end
		local tex = EnsurePortraitTimeline()
		if not tex then
			return
		end
		progress = Normalize01(progress)

		local nowSec = (GetTime and GetTime()) or 0
		local dt = nowSec - (tonumber(portraitTimeline.lastUpdateAt) or nowSec)
		portraitTimeline.lastUpdateAt = nowSec
		if dt < 0 then
			dt = 0
		elseif dt > 0.25 then
			dt = 0.25
		end
		if type(portraitTimeline.displayProgress) ~= "number" then
			portraitTimeline.displayProgress = progress
		else
			local delta = CircularDelta01(progress, portraitTimeline.displayProgress)
			local alpha = 1 - math.exp(-dt / math.max(0.05, PORTRAIT_TIMELINE_SMOOTH_TAU_SEC))
			local step = delta * alpha
			local maxStep = PORTRAIT_TIMELINE_MAX_SPEED_PER_SEC * dt
			if maxStep > 0 then
				if step > maxStep then
					step = maxStep
				elseif step < -maxStep then
					step = -maxStep
				end
			end
			portraitTimeline.displayProgress = Normalize01(portraitTimeline.displayProgress + step)
		end

		local portrait = portraitTimeline.portrait
		if not portrait then
			return
		end
		local pw = math.max(1, tonumber(portrait:GetWidth()) or 1)
		local ph = math.max(1, tonumber(portrait:GetHeight()) or 1)
		local visibleW = math.max(2, pw * PORTRAIT_TIMELINE_VISIBLE_SCALE)
		local visibleH = math.max(2, ph * PORTRAIT_TIMELINE_VISIBLE_SCALE)
		local texH = visibleH
		local texW = math.max(visibleW + 2, texH * PORTRAIT_TIMELINE_ASPECT)
		local travelX = math.max(0, texW - visibleW)
		local renderProgress = Normalize01(portraitTimeline.displayProgress)
		local offsetX = (renderProgress * travelX) - (travelX * 0.5)

		tex:ClearAllPoints()
		tex:SetSize(texW, texH)
		tex:SetPoint("CENTER", portrait, "CENTER", offsetX, PORTRAIT_TIMELINE_OFFSET_Y)
		SetPortraitTimelineVisible(true)
	end

	local function BuildNpcTimeContext(dayState)
		if type(dayState) ~= "table" then
			return nil
		end
		local effective = type(dayState.effective) == "table" and dayState.effective or {}
		local ai = type(effective.ai) == "table" and effective.ai or nil
		return {
			phaseKey = tostring(dayState.phaseKey or "aube"),
			phaseLabel = tostring(dayState.phaseLabel or dayState.phaseKey or "Safak"),
			ai = ai,
		}
	end

	local function ApplyTimeState(dayState)
		local effective = type(dayState) == "table" and type(dayState.effective) == "table" and dayState.effective
			or nil
		local colors = type(effective and effective.colors) == "table" and effective.colors or nil
		local bg = type(colors and colors.background) == "table" and colors.background or nil
		local models = type(colors and colors.models) == "table" and colors.models or nil
		if bg then
			mapBg:SetVertexColor(
				Clamp(tonumber(bg.r) or MAP_BG_DEFAULT_R, 0, 2),
				Clamp(tonumber(bg.g) or MAP_BG_DEFAULT_G, 0, 2),
				Clamp(tonumber(bg.b) or MAP_BG_DEFAULT_B, 0, 2),
				Clamp(tonumber(bg.a) or MAP_BG_DEFAULT_A, 0, 1)
			)
			if loadingOverlayRuntime and loadingOverlayRuntime.SetEnvironmentTint then
				loadingOverlayRuntime:SetEnvironmentTint(
					Clamp(tonumber(bg.r) or MAP_BG_DEFAULT_R, 0, 2),
					Clamp(tonumber(bg.g) or MAP_BG_DEFAULT_G, 0, 2),
					Clamp(tonumber(bg.b) or MAP_BG_DEFAULT_B, 0, 2)
				)
			end
		else
			mapBg:SetVertexColor(MAP_BG_DEFAULT_R, MAP_BG_DEFAULT_G, MAP_BG_DEFAULT_B, MAP_BG_DEFAULT_A)
			if loadingOverlayRuntime and loadingOverlayRuntime.SetEnvironmentTint then
				loadingOverlayRuntime:SetEnvironmentTint(MAP_BG_DEFAULT_R, MAP_BG_DEFAULT_G, MAP_BG_DEFAULT_B)
			end
		end
		do
			-- Slight tint from active time profile while preserving icon readability.
			local tr = Clamp(tonumber(models and models.lightColorR) or tonumber(bg and bg.r) or 1, 0.35, 1.80)
			local tg = Clamp(tonumber(models and models.lightColorG) or tonumber(bg and bg.g) or 1, 0.35, 1.80)
			local tb = Clamp(tonumber(models and models.lightColorB) or tonumber(bg and bg.b) or 1, 0.35, 1.80)
			local tintMix = 0.30
			iconTimeTintR = Clamp(1 + ((tr - 1) * tintMix), 0.55, 1.35)
			iconTimeTintG = Clamp(1 + ((tg - 1) * tintMix), 0.55, 1.35)
			iconTimeTintB = Clamp(1 + ((tb - 1) * tintMix), 0.55, 1.35)
			iconTimeTintA = 1
		end
		if objectScene and objectScene.SetRuntimeLightingOverride then
			objectScene:SetRuntimeLightingOverride(models)
		end
		if npcRuntime and npcRuntime.SetTimeContext then
			npcRuntime.SetTimeContext(BuildNpcTimeContext(dayState))
		end
		UpdatePortraitTimelineFromState(dayState)
		local hudEnabled = (type(timeCfg) ~= "table") or (timeCfg.hudEnabled ~= false)
		local isDevMode = (ns and ns.Utils and ns.Utils.IsDevMode and ns.Utils.IsDevMode()) == true
		if hudEnabled and type(dayState) == "table" and timeHudLine then
			local phaseLabel = tostring(dayState.phaseLabel or dayState.phaseKey or "?")
			local timeText = tostring(dayState.timeText or "00:00")
			if isDevMode then
				timeHudLine:SetText(string.format("%s - %s", phaseLabel, timeText))
			else
				timeHudLine:SetText(phaseLabel)
			end
			timeHud:Show()
		else
			timeHudLine:SetText("")
			timeHud:Hide()
		end
	end

	local function RefreshTimeRuntime(updateClock, dt)
		if not dayCycleRuntime then
			ApplyTimeState(nil)
			return nil
		end
		local snapshot = nil
		if updateClock == true then
			snapshot = dayCycleRuntime:Update(tonumber(dt) or 0)
		else
			snapshot = dayCycleRuntime:GetState()
		end
		ApplyTimeState(snapshot)
		return snapshot
	end

	local function GetEpochNow()
		local serverNow = (GetServerTime and GetServerTime()) or nil
		if serverNow then
			return math.max(0, tonumber(serverNow) or 0)
		end
		return math.max(0, tonumber(time and time() or 0) or 0)
	end

	local function EnsureDayCyclePersistenceMaps()
		WoWGuildeDB = WoWGuildeDB or {}
		WoWGuildeDB.QuartierMiniature = WoWGuildeDB.QuartierMiniature or {}
		local root = WoWGuildeDB.QuartierMiniature
		root.dayCycleState = root.dayCycleState or {}
		root.dayCycleState.version = tonumber(root.dayCycleState.version) or 1
		root.dayCycleState.maps = root.dayCycleState.maps or {}
		return root.dayCycleState.maps
	end

	local DAYCYCLE_OFFLINE_HARD_CAP_SEC = 90 * 24 * 60 * 60

	local function SaveDayCyclePersistence()
		if not (dayCycleRuntime and dayCycleRuntime.GetClockSeconds) then
			return false
		end
		local maps = EnsureDayCyclePersistenceMaps()
		local mapId = tostring(GetActiveMapId() or "default")
		local entry = maps[mapId] or {}
		entry.clockSec = math.max(0, tonumber(dayCycleRuntime:GetClockSeconds()) or 0)
		local nowServer = GetEpochNow()
		entry.updatedAtServer = nowServer
		entry.lastClosedAtServer = nowServer
		if dayCycleRuntime.GetTimeScale then
			entry.timeScale = Clamp(tonumber(dayCycleRuntime:GetTimeScale()) or 1.0, 0.01, 20.0)
		end
		maps[mapId] = entry
		return true
	end

	local function RestoreDayCyclePersistence()
		if not (dayCycleRuntime and dayCycleRuntime.SetClockSeconds) then
			return false
		end
		local maps = EnsureDayCyclePersistenceMaps()
		local mapId = tostring(GetActiveMapId() or "default")
		local entry = maps[mapId]
		if type(entry) ~= "table" then
			return false
		end
		local savedClockSec = tonumber(entry.clockSec)
		if not savedClockSec then
			return false
		end
		local persistedScale = Clamp(
			tonumber(entry.timeScale) or (dayCycleRuntime.GetTimeScale and dayCycleRuntime:GetTimeScale()) or 1.0,
			0.01,
			20.0
		)
		if dayCycleRuntime.SetTimeScale then
			dayCycleRuntime:SetTimeScale(persistedScale)
		end
		local closedAtServer = tonumber(entry.lastClosedAtServer or entry.updatedAtServer) or 0
		local nowServer = GetEpochNow()
		local elapsedSec = 0
		if closedAtServer > 0 and nowServer > closedAtServer then
			elapsedSec = Clamp(nowServer - closedAtServer, 0, DAYCYCLE_OFFLINE_HARD_CAP_SEC)
		end
		dayCycleRuntime:SetClockSeconds(savedClockSec + (elapsedSec * persistedScale))
		return true
	end

	local function FlushMiniGamePersistence()
		SaveDayCyclePersistence()
		if npcRuntime and npcRuntime.FlushPersistenceNow then
			npcRuntime.FlushPersistenceNow()
			return true
		end
		return false
	end

	local NpcEngine = ns.QuartierMiniatureSectionNpcEngine
	if not (NpcEngine and NpcEngine.Build) then
		error("WoWGuilde_QuartierMiniature: NpcEngine modulu bulunamadi")
	end

	npcRuntime = NpcEngine.Build({
		mapLayer = mapLayer,
		viewport = viewport,
		state = state,
		npcLayerParent = npcLayerHost,
		npcLayerFrameLevel = npcLayerHost:GetFrameLevel(),
		npcCfg = npcCfg,
		clamp = Clamp,
		getActiveMapId = GetActiveMapId,
		getCurrentBaseSize = function()
			return currentBaseW, currentBaseH
		end,
	})
	if not npcRuntime then
		error("WoWGuilde_QuartierMiniature: NpcEngine baslatma hatasi")
	end
	Npc_RenderAll = npcRuntime.RenderAll
	Npc_UpdateAndRender = npcRuntime.UpdateAndRender

	if ns and ns.QuartierMiniature and ns.QuartierMiniature.ObjectScene and ns.QuartierMiniature.ObjectScene.Attach then
		objectScene = ns.QuartierMiniature.ObjectScene.Attach({
			mapLayer = mapLayer,
			viewport = viewport,
			state = state,
			objectLayerParent = models3DLayer,
			objectLayerFrameLevel = models3DLayer:GetFrameLevel(),
			hoverLayerParent = models3DHoverLayer,
			hoverLayerFrameLevel = models3DHoverLayer:GetFrameLevel(),
			getMapId = function()
				return GetActiveMapId()
			end,
		})
	end

	local dayCycleFactory = ns and ns.QuartierMiniature and ns.QuartierMiniature.DayCycle
	local timeProfiles = ns and ns.QuartierMiniature and ns.QuartierMiniature.TimeProfiles
	if
		type(dayCycleFactory) == "table"
		and type(dayCycleFactory.CreateRuntime) == "function"
		and type(timeProfiles) == "table"
	then
		dayCycleRuntime = dayCycleFactory.CreateRuntime({
			getMapId = function()
				return GetActiveMapId()
			end,
			timeProfiles = timeProfiles,
			dayDurationSec = tonumber(timeCfg.dayDurationSec) or 7200,
			blendTailRatio = tonumber(timeCfg.blendTailRatio) or 0.20,
			timeScale = tonumber(timeCfg.defaultTimeScale) or 1.0,
			paused = true,
		})
	end
	RefreshTimeRuntime(false, 0)

	f.SetNpcName = function(_, selector, newName)
		if npcRuntime and npcRuntime.SetNpcName then
			return npcRuntime.SetNpcName(selector, newName)
		end
		return false
	end
	f.GetNpcSnapshot = function(_, includeDebugPaths)
		if npcRuntime and npcRuntime.GetNpcSnapshot then
			return npcRuntime.GetNpcSnapshot(includeDebugPaths == true)
		end
		return {}
	end
	f.GetNpcPickerSnapshot = function(_)
		if npcRuntime and npcRuntime.GetNpcPickerSnapshot then
			return npcRuntime.GetNpcPickerSnapshot()
		end
		return {}
	end
	f.GetNpcDetailSnapshot = function(_, selector, includeDebugPaths)
		if npcRuntime and npcRuntime.GetNpcDetailSnapshot then
			return npcRuntime.GetNpcDetailSnapshot(selector, includeDebugPaths == true)
		end
		return nil
	end
	f.OrderNpcTalkWith = function(_, sourceSelector, targetSelector)
		if npcRuntime and npcRuntime.OrderTalkWith then
			return npcRuntime.OrderTalkWith(sourceSelector, targetSelector)
		end
		return false, "missing_runtime"
	end
	f.OrderNpcJoinConversation = function(_, sourceSelector, targetSelector)
		if npcRuntime and npcRuntime.OrderJoinConversation then
			return npcRuntime.OrderJoinConversation(sourceSelector, targetSelector)
		end
		return false, "missing_runtime"
	end
	f.GetNpcConversationJoinInfo = function(_, sourceSelector, targetSelector)
		if npcRuntime and npcRuntime.GetConversationJoinInfo then
			return npcRuntime.GetConversationJoinInfo(sourceSelector, targetSelector)
		end
		return {
			canJoin = false,
			isConversation = false,
			count = 0,
			maxCount = 4,
		}
	end
	f.OrderNpcGoToLieuType = function(_, selector, lieuType, purpose)
		if npcRuntime and npcRuntime.OrderGoToLieuType then
			return npcRuntime.OrderGoToLieuType(selector, lieuType, purpose)
		end
		return false, "missing_runtime"
	end
	f.OrderNpcGoToPoint = function(_, selector, targetU, targetV, purpose, lieuType, waitSeconds)
		if npcRuntime and npcRuntime.OrderGoToPoint then
			return npcRuntime.OrderGoToPoint(selector, targetU, targetV, purpose, lieuType, waitSeconds)
		end
		return false, "missing_runtime"
	end
	f.SetRegisseuseAnchor = function(_, selector, targetU, targetV, radius)
		if npcRuntime and npcRuntime.SetRegisseuseAnchor then
			return npcRuntime.SetRegisseuseAnchor(selector, targetU, targetV, radius)
		end
		return false, "missing_runtime"
	end
	f.SetSelectedNpc = function(_, selector)
		if npcRuntime and npcRuntime.SetSelectedNpc then
			return npcRuntime.SetSelectedNpc(selector)
		end
		return false, "missing_runtime"
	end
	f.CancelNpcOrder = function(_, selector)
		if npcRuntime and npcRuntime.CancelNpcOrder then
			return npcRuntime.CancelNpcOrder(selector)
		end
		return false, "missing_runtime"
	end
	f.CancelNpcIntent = function(_, selector, intentIndex)
		if npcRuntime and npcRuntime.CancelNpcIntent then
			return npcRuntime.CancelNpcIntent(selector, intentIndex)
		end
		return false, "missing_runtime"
	end
	f.CreateSceneObject = function(_, payload)
		if objectScene and objectScene.CreateObject then
			return objectScene:CreateObject(payload)
		end
		return false, "missing_scene"
	end
	f.UpdateSceneObject = function(_, id, patch)
		if objectScene and objectScene.UpdateObject then
			return objectScene:UpdateObject(id, patch)
		end
		return false, "missing_scene"
	end
	f.DeleteSceneObject = function(_, id)
		if objectScene and objectScene.DeleteObject then
			return objectScene:DeleteObject(id)
		end
		return false, "missing_scene"
	end
	f.SelectSceneObject = function(_, id)
		if objectScene and objectScene.SelectObject then
			return objectScene:SelectObject(id)
		end
		return false, "missing_scene"
	end
	f.MoveSceneObjectUp = function(_, id)
		if objectScene and objectScene.MoveObjectUp then
			return objectScene:MoveObjectUp(id)
		end
		return false, "missing_scene"
	end
	f.MoveSceneObjectDown = function(_, id)
		if objectScene and objectScene.MoveObjectDown then
			return objectScene:MoveObjectDown(id)
		end
		return false, "missing_scene"
	end
	f.GetSceneObjects = function(_)
		if objectScene and objectScene.GetObjects then
			return objectScene:GetObjects()
		end
		return {}
	end
	f.ExportSceneObjects = function(_)
		if objectScene and objectScene.ExportText then
			return objectScene:ExportText()
		end
		return ""
	end
	f.GetTimeState = function(_)
		if dayCycleRuntime and dayCycleRuntime.GetStateCopy then
			return dayCycleRuntime:GetStateCopy()
		end
		if dayCycleRuntime and dayCycleRuntime.GetState then
			return dayCycleRuntime:GetState()
		end
		return nil
	end
	f.SetTimePhase = function(_, phaseKey, progressOptional)
		if not (dayCycleRuntime and dayCycleRuntime.SetPhase) then
			return false, "missing_time_runtime"
		end
		local ok = dayCycleRuntime:SetPhase(phaseKey, progressOptional)
		RefreshTimeRuntime(false, 0)
		return ok
	end
	f.SetTimeScale = function(_, scale)
		if not (dayCycleRuntime and dayCycleRuntime.SetTimeScale) then
			return false, "missing_time_runtime"
		end
		local value = dayCycleRuntime:SetTimeScale(scale)
		return true, value
	end
	f.SetTimePaused = function(_, paused)
		if not (dayCycleRuntime and dayCycleRuntime.SetPaused) then
			return false, "missing_time_runtime"
		end
		local value = dayCycleRuntime:SetPaused(paused == true)
		return true, value
	end
	f.ExportTimeProfiles = function(_)
		if timeProfiles and type(timeProfiles.BuildExportText) == "function" then
			return timeProfiles.BuildExportText(GetActiveMapId())
		end
		return ""
	end
	ns.QuartierMiniature = ns.QuartierMiniature or {}
	ns.QuartierMiniature.SetNpcName = function(selector, newName)
		return f.SetNpcName(f, selector, newName)
	end
	ns.QuartierMiniature.GetNpcSnapshot = function()
		return f.GetNpcSnapshot(f, false)
	end
	ns.QuartierMiniature.OrderNpcTalkWith = function(sourceSelector, targetSelector)
		return f.OrderNpcTalkWith(f, sourceSelector, targetSelector)
	end
	ns.QuartierMiniature.OrderNpcJoinConversation = function(sourceSelector, targetSelector)
		return f.OrderNpcJoinConversation(f, sourceSelector, targetSelector)
	end
	ns.QuartierMiniature.OrderNpcGoToLieuType = function(selector, lieuType, purpose)
		return f.OrderNpcGoToLieuType(f, selector, lieuType, purpose)
	end
	ns.QuartierMiniature.OrderNpcGoToPoint = function(selector, targetU, targetV, purpose, lieuType, waitSeconds)
		return f.OrderNpcGoToPoint(f, selector, targetU, targetV, purpose, lieuType, waitSeconds)
	end
	ns.QuartierMiniature.SetRegisseuseAnchor = function(selector, targetU, targetV, radius)
		return f.SetRegisseuseAnchor(f, selector, targetU, targetV, radius)
	end
	ns.QuartierMiniature.CancelNpcOrder = function(selector)
		return f.CancelNpcOrder(f, selector)
	end
	ns.QuartierMiniature.CancelNpcIntent = function(selector, intentIndex)
		return f.CancelNpcIntent(f, selector, intentIndex)
	end
	ns.QuartierMiniature.CreateSceneObject = function(payload)
		return f.CreateSceneObject(f, payload)
	end
	ns.QuartierMiniature.UpdateSceneObject = function(id, patch)
		return f.UpdateSceneObject(f, id, patch)
	end
	ns.QuartierMiniature.DeleteSceneObject = function(id)
		return f.DeleteSceneObject(f, id)
	end
	ns.QuartierMiniature.SelectSceneObject = function(id)
		return f.SelectSceneObject(f, id)
	end
	ns.QuartierMiniature.MoveSceneObjectUp = function(id)
		return f.MoveSceneObjectUp(f, id)
	end
	ns.QuartierMiniature.MoveSceneObjectDown = function(id)
		return f.MoveSceneObjectDown(f, id)
	end
	ns.QuartierMiniature.GetSceneObjects = function()
		return f.GetSceneObjects(f)
	end
	ns.QuartierMiniature.ExportSceneObjects = function()
		return f.ExportSceneObjects(f)
	end
	ns.QuartierMiniature.GetTimeState = function()
		return f.GetTimeState(f)
	end
	ns.QuartierMiniature.SetTimePhase = function(phaseKey, progressOptional)
		return f.SetTimePhase(f, phaseKey, progressOptional)
	end
	ns.QuartierMiniature.SetTimeScale = function(scale)
		return f.SetTimeScale(f, scale)
	end
	ns.QuartierMiniature.SetTimePaused = function(paused)
		return f.SetTimePaused(f, paused)
	end
	ns.QuartierMiniature.ExportTimeProfiles = function()
		return f.ExportTimeProfiles(f)
	end

	local clickMaxTravelPx = math.max(1, tonumber(inspectorCfg.clickMaxTravelPx) or 6)
	local clickMaxDuration = math.max(0.02, tonumber(inspectorCfg.clickMaxDuration) or 0.25)
	local selectRadiusPx = math.max(2, tonumber(inspectorCfg.selectRadiusPx) or 26)
	local presenceRefreshStep = Clamp(tonumber(inspectorCfg.presenceRefreshInterval) or 0.20, 0.05, 1.50)

	if
		inspectorCfg.enabled ~= false
		and ns
		and ns.QuartierMiniature
		and ns.QuartierMiniature.NpcInspector
		and ns.QuartierMiniature.NpcInspector.Attach
	then
		npcInspector = ns.QuartierMiniature.NpcInspector.Attach({
			parent = f,
			hudLayer = hudLayer,
			cfg = inspectorCfg,
			onIntentRightClick = function(npcId, intentIndex)
				local id = tostring(npcId or "")
				local idx = math.max(1, math.floor(tonumber(intentIndex) or 1))
				if id == "" then
					return
				end
				local ok = f:CancelNpcIntent(id, idx)
				if ok and npcInspector then
					npcInspector:UpdateFromSnapshot(f:GetNpcDetailSnapshot(id, false), nil)
					npcInspector:SetSelectedById(id)
				end
			end,
		})
	end

	if
		objectScene
		and ns
		and ns.QuartierMiniature
		and ns.QuartierMiniature.ObjectEditor
		and ns.QuartierMiniature.ObjectEditor.Attach
	then
		objectEditor = ns.QuartierMiniature.ObjectEditor.Attach({
			parent = f,
			hudLayer = hudLayer,
			scene = objectScene,
			isDevMode = function()
				if ns and ns.Utils and ns.Utils.IsDevMode then
					return ns.Utils.IsDevMode()
				end
				return false
			end,
			getTimeRuntime = function()
				return dayCycleRuntime
			end,
			getMapId = function()
				return GetActiveMapId()
			end,
			onTimeChanged = function()
				RefreshTimeRuntime(false, 0)
			end,
		})
	end

	local function GetCursorViewportPosition(self)
		local es = (self and self:GetEffectiveScale()) or 1
		local cx, cy = GetCursorPosition()
		cx = (tonumber(cx) or 0) / es
		cy = (tonumber(cy) or 0) / es
		local left = viewport:GetLeft() or 0
		local bottom = viewport:GetBottom() or 0
		return cx - left, cy - bottom
	end

	local function FindNearestNpcIdAtPoint(px, py, radiusPx, includeNonPlayable)
		local snapshot = f:GetNpcPickerSnapshot()
		if type(snapshot) ~= "table" then
			return nil, snapshot
		end
		local vw = viewport:GetWidth() or 0
		local vh = viewport:GetHeight() or 0
		local uSpan = state.uSpan or 0
		local vSpan = state.vSpan or 0
		if vw <= 1 or vh <= 1 or uSpan <= 0 or vSpan <= 0 then
			return nil, snapshot
		end

		local radius2 = (radiusPx or 0) * (radiusPx or 0)
		local u1 = state.u1 or 0
		local v1 = state.v1 or 0
		local bestId, bestD2 = nil, nil
		for i = 1, #snapshot do
			local npc = snapshot[i]
			local id = tostring(npc and npc.id or "")
			local u = tonumber(npc and npc.u)
			local v = tonumber(npc and npc.v)
			local playable = not (npc and npc.playable == false)
			if (includeNonPlayable == true or playable) and id ~= "" and u and v then
				local nx = (u - u1) / uSpan
				local ny = (v - v1) / vSpan
				local x = nx * vw
				local y = (1 - ny) * vh
				local dx = (px or 0) - x
				local dy = (py or 0) - y
				local d2 = (dx * dx) + (dy * dy)
				if d2 <= radius2 and ((not bestD2) or (d2 < bestD2)) then
					bestId = id
					bestD2 = d2
				end
			end
		end
		return bestId, snapshot
	end

	local legacyOrderMenuFrame = CreateFrame("Frame", nil, UIParent, "UIDropDownMenuTemplate")
	legacyOrderMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")

	local function IsRouteEditorDevMode()
		if not (routeEditor and routeEditor.IsDevMode and routeEditor:IsDevMode()) then
			return false
		end
		if routeEditor.IsEditorOpen then
			return routeEditor:IsEditorOpen()
		end
		return true
	end

	local function BuildNpcLookup(snapshot)
		local byId = {}
		for i = 1, #(snapshot or {}) do
			local row = snapshot[i]
			local id = tostring(row and row.id or "")
			if id ~= "" then
				byId[id] = row
			end
		end
		return byId
	end

	local function BuildTalkCandidates(snapshot, sourceId)
		local out = {}
		for i = 1, #(snapshot or {}) do
			local row = snapshot[i]
			local id = tostring(row and row.id or "")
			if id ~= "" and id ~= sourceId then
				out[#out + 1] = {
					id = id,
					name = tostring(row.name or id),
				}
			end
		end
		table.sort(out, function(a, b)
			return string.lower(a.name) < string.lower(b.name)
		end)
		return out
	end

	local function ViewportPointToWorld(px, py)
		local vw = viewport:GetWidth() or 0
		local vh = viewport:GetHeight() or 0
		if vw <= 0 or vh <= 0 then
			return nil, nil
		end
		local nx = Clamp((tonumber(px) or 0) / vw, 0, 1)
		local nyTop = Clamp(1 - ((tonumber(py) or 0) / vh), 0, 1)
		local u = (state.u1 or 0) + (nx * (state.uSpan or 1))
		local v = (state.v1 or 0) + (nyTop * (state.vSpan or 1))
		return Clamp(u, 0, 1), Clamp(v, 0, 1)
	end

	local function GetRoutesStoreForActiveMap()
		local routesRoot = ns and ns.QuartierMiniature and ns.QuartierMiniature.Routes or nil
		if type(routesRoot) ~= "table" then
			return nil
		end
		if type(routesRoot.maps) == "table" then
			return routesRoot.maps[GetActiveMapId()]
		end
		return routesRoot
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
			local ax = tonumber(a and a.u)
			local ay = tonumber(a and a.v)
			local bx = tonumber(b and b.u)
			local by = tonumber(b and b.v)
			if ax and ay and bx and by then
				local intersects = ((ay > v) ~= (by > v)) and (u < ((bx - ax) * (v - ay) / ((by - ay) + 1e-8) + ax))
				if intersects then
					inside = not inside
				end
			end
			j = i
		end
		return inside
	end

	local function FindLieuAtWorld(u, v)
		local store = GetRoutesStoreForActiveMap()
		local lieux = type(store and store.lieux) == "table" and store.lieux or nil
		if not lieux then
			return nil
		end
		for i = 1, #lieux do
			local lieu = lieux[i]
			local points = type(lieu and lieu.points) == "table" and lieu.points or nil
			if points and #points >= 3 and IsPointInPolygon(points, u, v) then
				local linkId = tostring(lieu.linkId or lieu.id or ("lieu_" .. i))
				local zoneTitle = tostring(lieu.label or lieu.name or lieu.title or lieu.zoneTitle or lieu.id or "")
				return {
					id = tostring(lieu.id or ("lieu_" .. i)),
					linkId = linkId,
					type = string.lower(tostring(lieu.type or "chaumiere")),
					zoneTitle = zoneTitle,
					u = u,
					v = v,
				}
			end
		end
		return nil
	end

	local PRESENCE_FALLBACK_ATLAS = "raceicon128-human-male"
	local presencePanelState = {
		lieuId = nil,
		buildingName = nil,
		lieuType = nil,
		cursorX = nil,
		cursorY = nil,
	}
	local buildingPresencePanel = nil
	local buildingHoverInfoPanel = nil
	local RefreshBuildingPresencePanel

	local function IsAtlasUsable(atlasName)
		if type(atlasName) ~= "string" or atlasName == "" then
			return false
		end
		if C_Texture and C_Texture.GetAtlasInfo then
			return C_Texture.GetAtlasInfo(atlasName) ~= nil
		end
		return true
	end

	local function GetCursorUiPosition()
		local scale = UIParent and UIParent:GetEffectiveScale() or 1
		local x, y = GetCursorPosition()
		return (tonumber(x) or 0) / scale, (tonumber(y) or 0) / scale
	end

	local function ResolveLieuTypeTitle(lieuType)
		local kind = string.lower(tostring(lieuType or ""))
		if kind == "auberge" then
			return "Han"
		end
		if kind == "taverne" then
			return "Taverne"
		end
		if kind == "chaumiere" then
			return "Kulube"
		end
		return "Bina"
	end

	local function ResolveLieuTypeDescription(lieuType)
		local kind = string.lower(tostring(lieuType or ""))
		if kind == "auberge" then
			return "Han, koyunuzdaki koylulari doyurmak icin yerdir."
		end
		if kind == "taverne" then
			return "Taverne, koyunuzdaki koylulari eglendirmek icin yerdir."
		end
		if kind == "chaumiere" then
			return "Kulube, koyunuzdaki koylulari dinlendirmek icin yerdir."
		end
		return "Bu bina koylulari ihtiyaclarina gore agirlar."
	end

	local function GetLieuCapacityForType(lieuType)
		local kind = string.lower(tostring(lieuType or ""))
		if kind == "restaurant" then
			kind = "auberge"
		end
		if kind == "chaumiere" then
			return 2
		end
		if kind == "auberge" then
			return 5
		end
		if kind == "taverne" then
			return 3
		end
		return nil
	end

	local function CollectNpcRowsForLieuId(lieuId)
		local out = {}
		local target = tostring(lieuId or "")
		if target == "" then
			return out
		end
		local snapshot = f:GetNpcSnapshot(false)
		for i = 1, #(snapshot or {}) do
			local row = snapshot[i]
			if tostring(row and row.currentLieuId or "") == target then
				out[#out + 1] = {
					id = tostring(row and row.id or ""),
					name = tostring(row and row.name or ""),
					portraitAtlas = tostring(row and row.portraitAtlas or PRESENCE_FALLBACK_ATLAS),
					portraitUnit = tostring(row and row.portraitUnit or ""),
				}
			end
		end
		table.sort(out, function(a, b)
			return string.lower(a.name or "") < string.lower(b.name or "")
		end)
		return out
	end

	local function SelectNpcFromPresencePanel(npcId)
		local id = tostring(npcId or "")
		if id == "" then
			return
		end
		if npcInspector then
			npcInspector:UpdateFromSnapshot(f:GetNpcDetailSnapshot(id, false), nil)
			npcInspector:SetSelectedById(id)
		end
		f:SetSelectedNpc(id)
	end

	local function EnsurePresencePortraitSlot(panel, index)
		panel._portraitSlots = panel._portraitSlots or {}
		local slot = panel._portraitSlots[index]
		if slot then
			return slot
		end
		slot = CreateFrame("Button", nil, panel)
		slot:SetSize(34, 34)
		slot:EnableMouse(true)
		slot:RegisterForClicks("LeftButtonUp")
		slot.icon = slot:CreateTexture(nil, "ARTWORK", nil, 1)
		slot.icon:SetAllPoints(slot)
		if IsAtlasUsable(PRESENCE_FALLBACK_ATLAS) then
			slot.icon:SetAtlas(PRESENCE_FALLBACK_ATLAS)
		else
			slot.icon:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
		end
		slot.mask = slot:CreateMaskTexture(nil, "ARTWORK")
		slot.mask:SetAllPoints(slot)
		slot.mask:SetTexture(
			"Interface\\CharacterFrame\\TempPortraitAlphaMask",
			"CLAMPTOBLACKADDITIVE",
			"CLAMPTOBLACKADDITIVE"
		)
		slot.icon:AddMaskTexture(slot.mask)
		slot.ring = slot:CreateTexture(nil, "OVERLAY", nil, 5)
		slot.ring:SetSize(45, 45)
		slot.ring:SetPoint("CENTER", slot, "CENTER", 0, 0)
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Map_Faction_Ring") then
			slot.ring:SetAtlas("Map_Faction_Ring")
		else
			slot.ring:SetTexture("Interface\\Buttons\\WHITE8X8")
		end
		if slot.ring.SetDesaturated then
			slot.ring:SetDesaturated(true)
		end
		slot.ring:SetVertexColor(1.0, 0.85, 0.20, 0.92)
		slot:SetScript("OnClick", function(self, button)
			if button ~= "LeftButton" then
				return
			end
			SelectNpcFromPresencePanel(self._npcId)
			RefreshBuildingPresencePanel()
		end)
		slot:Hide()
		panel._portraitSlots[index] = slot
		return slot
	end

	local function EnsureBuildingPresencePanel()
		if buildingPresencePanel then
			return buildingPresencePanel
		end
		local panel = CreateFrame("Frame", nil, hudLayer, "BackdropTemplate")
		panel:SetSize(220, 94)
		panel:SetFrameStrata("FULLSCREEN_DIALOG")
		panel:SetFrameLevel((hudLayer:GetFrameLevel() or 1) + 20)
		panel:EnableMouse(true)
		panel:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		panel:SetBackdropColor(0.01, 0.01, 0.01, 0.95)
		panel:Hide()

		panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -11)
		panel.title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -70, -11)
		panel.title:SetJustifyH("LEFT")
		panel.title:SetTextColor(1.00, 0.82, 0.10, 1.0)
		panel.title:SetText("Bina")

		panel.capacity = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		panel.capacity:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -12)
		panel.capacity:SetJustifyH("RIGHT")
		panel.capacity:SetTextColor(1, 1, 1, 1)
		panel.capacity:SetText("")

		panel.emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		panel.emptyText:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -36)
		panel.emptyText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -36)
		panel.emptyText:SetJustifyH("LEFT")
		panel.emptyText:SetText("Bu binada koylu yok")
		panel.emptyText:Hide()

		panel.description = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		panel.description:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -56)
		panel.description:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -56)
		panel.description:SetJustifyH("LEFT")
		panel.description:SetJustifyV("TOP")
		panel.description:SetTextColor(0.62, 0.62, 0.62, 1.0)
		panel.description:SetText("")

		buildingPresencePanel = panel
		return panel
	end

	local function EnsureBuildingHoverInfoPanel()
		if buildingHoverInfoPanel then
			return buildingHoverInfoPanel
		end
		local panel = CreateFrame("Frame", nil, hudLayer, "BackdropTemplate")
		panel:SetSize(190, 32)
		panel:SetFrameStrata("FULLSCREEN_DIALOG")
		panel:SetFrameLevel((hudLayer:GetFrameLevel() or 1) + 19)
		panel:EnableMouse(false)
		panel:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		panel:SetBackdropColor(0.01, 0.01, 0.01, 0.95)
		panel:Hide()

		panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -9)
		panel.title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -70, -9)
		panel.title:SetJustifyH("LEFT")
		panel.title:SetTextColor(1.00, 0.82, 0.10, 1.0)
		panel.title:SetText("Bina")

		panel.capacity = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		panel.capacity:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -10)
		panel.capacity:SetJustifyH("RIGHT")
		panel.capacity:SetTextColor(1, 1, 1, 1)
		panel.capacity:SetText("0/0")

		buildingHoverInfoPanel = panel
		return panel
	end

	local function HideBuildingHoverInfoPanel()
		if buildingHoverInfoPanel then
			buildingHoverInfoPanel:Hide()
		end
	end

	local function RefreshBuildingHoverInfoPanel(hitLieu, cursorX, cursorY)
		if type(hitLieu) ~= "table" then
			HideBuildingHoverInfoPanel()
			return
		end
		local lieuId = tostring(hitLieu.id or "")
		if lieuId == "" then
			HideBuildingHoverInfoPanel()
			return
		end
		if presencePanelState.lieuId then
			HideBuildingHoverInfoPanel()
			return
		end
		local panel = EnsureBuildingHoverInfoPanel()
		local lieuType = string.lower(tostring(hitLieu.type or ""))
		panel.title:SetText(ResolveLieuTypeTitle(lieuType))
		local rows = CollectNpcRowsForLieuId(lieuId)
		local maxCapacity = GetLieuCapacityForType(lieuType)
		if maxCapacity then
			panel.capacity:SetText(("%d/%d"):format(#rows, maxCapacity))
		else
			panel.capacity:SetText(tostring(#rows))
		end
		local width = 190
		local height = 32
		panel:SetSize(width, height)

		local x = tonumber(cursorX) or 0
		local y = tonumber(cursorY) or 0
		local parentW = UIParent and UIParent:GetWidth() or 0
		local parentH = UIParent and UIParent:GetHeight() or 0
		local placeX = Clamp(x - (width * 0.5), 6, math.max(6, parentW - width - 6))
		local placeY = Clamp(y + 18, 6, math.max(6, parentH - height - 6))
		panel:ClearAllPoints()
		panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", placeX, placeY)
		panel:Show()
	end

	local function HideBuildingPresencePanel()
		presencePanelState.lieuId = nil
		presencePanelState.buildingName = nil
		presencePanelState.lieuType = nil
		presencePanelState.cursorX = nil
		presencePanelState.cursorY = nil
		if buildingPresencePanel then
			buildingPresencePanel:Hide()
		end
	end

	RefreshBuildingPresencePanel = function()
		local lieuId = tostring(presencePanelState.lieuId or "")
		if lieuId == "" then
			HideBuildingPresencePanel()
			return
		end
		local panel = EnsureBuildingPresencePanel()
		local buildingName = tostring(presencePanelState.buildingName or "")
		if buildingName == "" then
			buildingName = "Bina"
		end
		panel.title:SetText(buildingName)
		local descriptionText = ResolveLieuTypeDescription(presencePanelState.lieuType)
		panel.description:SetText(descriptionText)

		local rows = CollectNpcRowsForLieuId(lieuId)
		local maxCapacity = GetLieuCapacityForType(presencePanelState.lieuType)
		if maxCapacity then
			panel.capacity:SetText(("%d/%d"):format(#rows, maxCapacity))
		else
			panel.capacity:SetText(tostring(#rows))
		end
		local iconSize, gap, cols = 34, 6, 6
		local count = #rows
		local usedCols = (count > 0) and math.max(1, math.min(cols, count)) or 0
		local usedRows = (count > 0) and math.max(1, math.ceil(count / cols)) or 0
		local contentW = (usedCols > 0) and ((usedCols * iconSize) + ((usedCols - 1) * gap)) or 0
		local contentH = (usedRows > 0) and ((usedRows * iconSize) + ((usedRows - 1) * gap)) or 0
		local width = math.max(190, 24 + contentW)
		panel.description:SetWidth(math.max(120, width - 24))
		local descH = math.max(16, math.floor((tonumber(panel.description:GetStringHeight()) or 0) + 2))
		local descriptionTopOffset = (count > 0) and (30 + contentH + 3) or 28
		local height = descriptionTopOffset + descH + 6
		panel:SetSize(width, height)

		panel.emptyText:Hide()
		for i = 1, count do
			local row = rows[i]
			local slot = EnsurePresencePortraitSlot(panel, i)
			slot._npcId = tostring(row and row.id or "")
			local portraitUnit = tostring(row and row.portraitUnit or "")
			local atlasName = tostring(row and row.portraitAtlas or "")
			if portraitUnit ~= "" and SetPortraitTexture then
				slot.icon:SetTexture(nil)
				slot.icon:SetTexCoord(0, 1, 0, 1)
				SetPortraitTexture(slot.icon, portraitUnit)
			elseif IsAtlasUsable(atlasName) then
				slot.icon:SetAtlas(atlasName)
			elseif IsAtlasUsable(PRESENCE_FALLBACK_ATLAS) then
				slot.icon:SetAtlas(PRESENCE_FALLBACK_ATLAS)
			else
				slot.icon:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
			end
			slot.icon:SetVertexColor(iconTimeTintR, iconTimeTintG, iconTimeTintB, iconTimeTintA)
			local col = (i - 1) % cols
			local line = math.floor((i - 1) / cols)
			local x = 12 + (col * (iconSize + gap))
			local y = -30 - (line * (iconSize + gap))
			slot:ClearAllPoints()
			slot:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
			local selectedId = tostring(npcInspector and npcInspector:GetSelectedId() or "")
			if selectedId ~= "" and selectedId == slot._npcId then
				if slot.ring.SetDesaturated then
					slot.ring:SetDesaturated(false)
				end
				slot.ring:SetVertexColor(1.00, 0.82, 0.08, 1.00)
			else
				if slot.ring.SetDesaturated then
					slot.ring:SetDesaturated(true)
				end
				slot.ring:SetVertexColor(0.72, 0.72, 0.72, 0.95)
			end
			slot:Show()
		end
		for i = count + 1, #(panel._portraitSlots or {}) do
			panel._portraitSlots[i]:Hide()
		end
		panel.description:ClearAllPoints()
		panel.description:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -descriptionTopOffset)
		panel.description:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -descriptionTopOffset)

		local cursorX = tonumber(presencePanelState.cursorX)
		local cursorY = tonumber(presencePanelState.cursorY)
		if not (cursorX and cursorY) then
			cursorX, cursorY = GetCursorUiPosition()
			presencePanelState.cursorX = cursorX
			presencePanelState.cursorY = cursorY
		end
		local parentW = UIParent and UIParent:GetWidth() or 0
		local parentH = UIParent and UIParent:GetHeight() or 0
		local placeX = Clamp(cursorX - (width * 0.5), 6, math.max(6, parentW - width - 6))
		local placeY = Clamp(cursorY + 18, 6, math.max(6, parentH - height - 6))
		panel:ClearAllPoints()
		panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", placeX, placeY)
		panel:Show()
	end

	local function OpenBuildingPresencePanel(hitLieu)
		if type(hitLieu) ~= "table" then
			HideBuildingPresencePanel()
			return
		end
		local lieuId = tostring(hitLieu.id or "")
		if lieuId == "" then
			HideBuildingPresencePanel()
			return
		end
		presencePanelState.lieuId = lieuId
		presencePanelState.lieuType = string.lower(tostring(hitLieu.type or ""))
		presencePanelState.buildingName = ResolveLieuTypeTitle(presencePanelState.lieuType)
		presencePanelState.cursorX, presencePanelState.cursorY = GetCursorUiPosition()
		RefreshBuildingPresencePanel()
	end

	local function FindPlazaAtWorld(u, v)
		local store = GetRoutesStoreForActiveMap()
		local plazas = type(store and store.plazas) == "table" and store.plazas or nil
		if not plazas then
			return nil
		end
		for i = 1, #plazas do
			local plaza = plazas[i]
			local points = type(plaza and plaza.points) == "table" and plaza.points or nil
			if points and #points >= 3 and IsPointInPolygon(points, u, v) then
				return {
					id = tostring(plaza.id or ("plaza_" .. i)),
					u = u,
					v = v,
				}
			end
		end
		return nil
	end

	local function Dist2PointToSegment(u, v, au, av, bu, bv)
		local abx = bu - au
		local aby = bv - av
		local apx = u - au
		local apy = v - av
		local ab2 = (abx * abx) + (aby * aby)
		if ab2 <= 1e-8 then
			local dx = u - au
			local dy = v - av
			return (dx * dx) + (dy * dy)
		end
		local t = ((apx * abx) + (apy * aby)) / ab2
		if t < 0 then
			t = 0
		elseif t > 1 then
			t = 1
		end
		local cx = au + (abx * t)
		local cy = av + (aby * t)
		local dx = u - cx
		local dy = v - cy
		return (dx * dx) + (dy * dy)
	end

	local function IsPointNearRoute(u, v)
		local store = GetRoutesStoreForActiveMap()
		local routes = type(store and store.routes) == "table" and store.routes or nil
		if not routes then
			return false
		end
		local maxDist = 0.028
		local maxDist2 = maxDist * maxDist
		for i = 1, #routes do
			local points = type(routes[i] and routes[i].points) == "table" and routes[i].points or nil
			if points and #points >= 2 then
				for j = 1, (#points - 1) do
					local a = points[j]
					local b = points[j + 1]
					local au = tonumber(a and a.u)
					local av = tonumber(a and a.v)
					local bu = tonumber(b and b.u)
					local bv = tonumber(b and b.v)
					if au and av and bu and bv then
						if Dist2PointToSegment(u, v, au, av, bu, bv) <= maxDist2 then
							return true
						end
					end
				end
			end
		end
		return false
	end

	local function IsPointOrderable(u, v)
		if not (u and v) then
			return false
		end
		if FindPlazaAtWorld(u, v) then
			return true
		end
		if IsPointNearRoute(u, v) then
			return true
		end
		return false
	end

	local function OpenLegacyOrderMenu(items)
		if CloseDropDownMenus then
			CloseDropDownMenus()
		end
		if EasyMenu then
			local ok = pcall(EasyMenu, items, legacyOrderMenuFrame, "cursor", 0, 0, "MENU", 2)
			if ok then
				return true
			end
		end
		return false
	end

	local _actionMenuSpecsCache = nil
	local function GetActionMenuSpecs()
		if _actionMenuSpecsCache ~= nil then
			return _actionMenuSpecsCache or nil
		end
		local rules = ns and ns.QuartierMiniature and ns.QuartierMiniature.NpcActionRules or nil
		if type(rules) == "table" and type(rules.GetBuiltinActionSpecs) == "function" then
			local ok, specs = pcall(rules.GetBuiltinActionSpecs)
			if ok and type(specs) == "table" then
				_actionMenuSpecsCache = specs
				return specs
			end
		end
		_actionMenuSpecsCache = false
		return nil
	end

	local function GetActionMenuLabel(actionKey, fallback)
		local key = string.lower(tostring(actionKey or ""))
		local specs = GetActionMenuSpecs()
		local spec = specs and specs[key] or nil
		local label = tostring(spec and (spec.travelLabel or spec.label) or "")
		if label ~= "" then
			return label
		end
		return tostring(fallback or "")
	end

	local function OpenNpcRenamePopup(npcId, currentName)
		if not (StaticPopup_Show and StaticPopupDialogs) then
			return
		end
		local id = tostring(npcId or "")
		if id == "" then
			return
		end
		local dialogKey = "WOWGUILDE_QM_RENAME_NPC"
		if not StaticPopupDialogs[dialogKey] then
			StaticPopupDialogs[dialogKey] = {
				text = "Yeni takma ad",
				button1 = ACCEPT,
				button2 = CANCEL,
				hasEditBox = true,
				maxLetters = 32,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
				OnShow = function(self, data)
					local payload = data or (self and self.data)
					local editBox = (self and self.editBox)
						or (self and self.GetName and _G[self:GetName() .. "EditBox"])
						or _G.StaticPopup1EditBox
					if not editBox then
						return
					end
					editBox:SetText(tostring(payload and payload.currentName or ""))
					editBox:HighlightText()
					editBox:SetFocus()
				end,
				OnAccept = function(self, data)
					local payload = data or (self and self.data)
					local apply = payload and payload.apply
					if type(apply) ~= "function" then
						return
					end
					local editBox = (self and self.editBox)
						or (self and self.GetName and _G[self:GetName() .. "EditBox"])
						or _G.StaticPopup1EditBox
					local text = ""
					if editBox and editBox.GetText then
						text = tostring(editBox:GetText() or "")
					end
					apply(text)
				end,
				EditBoxOnEnterPressed = function(editBox)
					local parent = editBox and editBox:GetParent()
					if parent and parent.button1 and parent.button1:IsEnabled() then
						parent.button1:Click()
					end
				end,
				EditBoxOnEscapePressed = function(editBox)
					local parent = editBox and editBox:GetParent()
					if parent then
						parent:Hide()
					end
				end,
			}
		end
		local payload = {
			currentName = tostring(currentName or ""),
			apply = function(nextName)
				local appliedId = id
				local ok, finalName, reason = f:SetNpcName(id, nextName)
				if (not ok) and npcInspector and npcInspector.GetSelectedId then
					local selectedId = tostring(npcInspector:GetSelectedId() or "")
					if selectedId ~= "" and selectedId ~= id then
						ok, finalName, reason = f:SetNpcName(selectedId, nextName)
						if ok then
							appliedId = selectedId
						end
					end
				end
				if ok and npcInspector and npcInspector.UpdateFromSnapshot then
					npcInspector:UpdateFromSnapshot(f:GetNpcSnapshot(false), nil)
					if npcInspector.SetSelectedById then
						npcInspector:SetSelectedById(appliedId)
					end
				end
			end,
		}
		StaticPopup_Show(dialogKey, nil, nil, payload)
	end

	local function GetCurrentTimePhaseKeyForMenu()
		local stateNow = f.GetTimeState and f:GetTimeState() or nil
		return string.lower(tostring(stateNow and stateNow.phaseKey or "aube"))
	end

	local function GetBlockedPurposeReason(purpose)
		local p = string.lower(tostring(purpose or ""))
		local phase = GetCurrentTimePhaseKeyForMenu()
		if p == "distraction" and (phase == "aube" or phase == "matin") then
			return "Taverne su saatte kapali"
		end
		if p == "meal" and (phase == "nuit" or phase == "apres_midi") then
			return "Han su saatte kapali"
		end
		if p == "rest" and (phase == "aube" or phase == "midi" or phase == "apres_midi") then
			return "Koylu bu kadar erken dinlenmek istemiyor"
		end
		return nil
	end

	local function IsDevModeForRegisseuseMenu()
		if ns and ns.Utils and ns.Utils.IsDevMode then
			return ns.Utils.IsDevMode() == true
		end
		return false
	end

	local function ShowOrderContextMenu(ctx)
		if type(ctx) ~= "table" then
			return
		end
		local actorId = tostring(ctx.actorId or "")
		local actorName = tostring(ctx.actorName or actorId or "")
		local actorIsHero = ctx.actorIsHero == true
		local mode = tostring(ctx.mode or "")

		if MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
			MenuUtil.CreateContextMenu(f, function(_, root)
				root:CreateTitle("Koyluya talimat")
				if mode == "npc" then
					local targetNpcId = tostring(ctx.targetNpcId or "")
					local targetNpcName = tostring(ctx.targetNpcName or targetNpcId)
					local targetIsHero = ctx.targetIsHero == true
					local targetIsRegisseuse = ctx.targetIsRegisseuse == true
					local joinInfo = f:GetNpcConversationJoinInfo(actorId, targetNpcId)
					if actorId ~= "" and targetNpcId ~= "" then
						if actorId == targetNpcId then
							if not (actorIsHero or targetIsHero) then
								root:CreateButton("Takma adi degistir", function()
									OpenNpcRenamePopup(actorId, targetNpcName)
								end)
							else
								root:CreateButton(
									"Kahraman adi degistirilemez",
									function() end,
									{ disabled = true }
								)
							end
							return
						end
						local talkLabel = targetIsRegisseuse and "Yonetici ile konusun"
							or ("Sununla sohbet edin: " .. targetNpcName)
						root:CreateButton(talkLabel, function()
							f:OrderNpcTalkWith(actorId, targetNpcId)
						end)
						if targetIsRegisseuse and IsDevModeForRegisseuseMenu() then
							root:CreateButton("Koyu nasil idare edecegimizi sor", function()
								f:OrderNpcTalkWith(actorId, targetNpcId)
							end)
							root:CreateButton("Kimlerle sozlesme yaptigimizi sor", function()
								f:OrderNpcTalkWith(actorId, targetNpcId)
							end)
							root:CreateButton("Kaynaklarimizin neler oldugunu sor", function()
								f:OrderNpcTalkWith(actorId, targetNpcId)
							end)
						end
						if joinInfo and joinInfo.canJoin and joinInfo.isConversation then
							root:CreateButton(("%s sohbetine katil"):format(targetNpcName), function()
								f:OrderNpcJoinConversation(actorId, targetNpcId)
							end)
						end
					else
						root:CreateButton("Once bir koylu secin", function() end, { disabled = true })
					end
					return
				end

				if mode == "point" then
					local targetU = tonumber(ctx.targetU)
					local targetV = tonumber(ctx.targetV)
					if not (targetU and targetV) then
						root:CreateButton("Gecersiz konum", function() end, { disabled = true })
						return
					end
					if actorId ~= "" then
						root:CreateButton(GetActionMenuLabel("aller_ici", "Buraya git"), function()
							f:OrderNpcGoToPoint(actorId, targetU, targetV, "walk", "")
						end)
						root:CreateButton(
							GetActionMenuLabel("aller_ici_et_attendre", "Buraya git ve bekle"),
							function()
								f:OrderNpcGoToPoint(actorId, targetU, targetV, "wait", "", 180)
							end
						)
					end
					if actorId == "" then
						root:CreateButton(
							"Hareket emirleri icin bir koylu secin",
							function() end,
							{ disabled = true }
						)
					end
					return
				end

				if mode == "lieu" then
					local lieuType = tostring(ctx.lieuType or "")
					local targetU = tonumber(ctx.targetU)
					local targetV = tonumber(ctx.targetV)
					if actorId == "" then
						root:CreateButton("Once bir koylu secin", function() end, { disabled = true })
						return
					end
					if not (targetU and targetV) then
						root:CreateButton("Gecersiz konum", function() end, { disabled = true })
						return
					end
					if lieuType == "chaumiere" then
						local blockedReason = GetBlockedPurposeReason("rest")
						if blockedReason then
							root:CreateButton(blockedReason, function() end, { disabled = true })
						else
							root:CreateButton(GetActionMenuLabel("rest", "Dinlen"), function()
								f:OrderNpcGoToPoint(actorId, targetU, targetV, "rest", "chaumiere")
							end)
						end
					elseif lieuType == "taverne" then
						local blockedReason = GetBlockedPurposeReason("distraction")
						if blockedReason then
							root:CreateButton(blockedReason, function() end, { disabled = true })
						else
							root:CreateButton(GetActionMenuLabel("distraction", "Eglen"), function()
								f:OrderNpcGoToPoint(actorId, targetU, targetV, "distraction", "taverne")
							end)
						end
					elseif lieuType == "auberge" then
						local blockedReason = GetBlockedPurposeReason("meal")
						if blockedReason then
							root:CreateButton(blockedReason, function() end, { disabled = true })
						else
							root:CreateButton(GetActionMenuLabel("meal", "Yemek ye"), function()
								f:OrderNpcGoToPoint(actorId, targetU, targetV, "meal", "auberge")
							end)
						end
					end
				end
			end)
			return
		end

		local legacy = {
			{ text = "Koylu Emirleri", isTitle = true, notCheckable = true },
		}
		if mode == "npc" then
			local targetNpcId = tostring(ctx.targetNpcId or "")
			local targetNpcName = tostring(ctx.targetNpcName or targetNpcId)
			local targetIsHero = ctx.targetIsHero == true
			local targetIsRegisseuse = ctx.targetIsRegisseuse == true
			local joinInfo = f:GetNpcConversationJoinInfo(actorId, targetNpcId)
			if actorId ~= "" and targetNpcId ~= "" then
				if actorId == targetNpcId then
					if not (actorIsHero or targetIsHero) then
						legacy[#legacy + 1] = {
							text = "Takma adi degistir",
							notCheckable = true,
							func = function()
								OpenNpcRenamePopup(actorId, targetNpcName)
							end,
						}
					else
						legacy[#legacy + 1] = {
							text = "Kahraman adi degistirilemez",
							notCheckable = true,
							disabled = true,
						}
					end
				else
					local talkLabel = targetIsRegisseuse and "Yonetici ile konusun"
						or ("Sununla sohbet edin: " .. targetNpcName)
					legacy[#legacy + 1] = {
						text = talkLabel,
						notCheckable = true,
						func = function()
							f:OrderNpcTalkWith(actorId, targetNpcId)
						end,
					}
					if targetIsRegisseuse and IsDevModeForRegisseuseMenu() then
						legacy[#legacy + 1] = {
							text = "Koyu nasil idare edecegimizi sor",
							notCheckable = true,
							func = function()
								f:OrderNpcTalkWith(actorId, targetNpcId)
							end,
						}
						legacy[#legacy + 1] = {
							text = "Kimlerle sozlesme yaptigimizi sor",
							notCheckable = true,
							func = function()
								f:OrderNpcTalkWith(actorId, targetNpcId)
							end,
						}
						legacy[#legacy + 1] = {
							text = "Kaynaklarimizin neler oldugunu sor",
							notCheckable = true,
							func = function()
								f:OrderNpcTalkWith(actorId, targetNpcId)
							end,
						}
					end
					if joinInfo and joinInfo.canJoin and joinInfo.isConversation then
						legacy[#legacy + 1] = {
							text = ("%s sohbetine katil"):format(targetNpcName),
							notCheckable = true,
							func = function()
								f:OrderNpcJoinConversation(actorId, targetNpcId)
							end,
						}
					end
				end
			end
		elseif mode == "point" then
			local targetU = tonumber(ctx.targetU)
			local targetV = tonumber(ctx.targetV)
			if targetU and targetV then
				if actorId ~= "" then
					legacy[#legacy + 1] = {
						text = GetActionMenuLabel("aller_ici", "Buraya git"),
						notCheckable = true,
						func = function()
							f:OrderNpcGoToPoint(actorId, targetU, targetV, "walk", "")
						end,
					}
					legacy[#legacy + 1] = {
						text = GetActionMenuLabel("aller_ici_et_attendre", "Buraya git ve bekle"),
						notCheckable = true,
						func = function()
							f:OrderNpcGoToPoint(actorId, targetU, targetV, "wait", "", 180)
						end,
					}
				end
			end
		elseif mode == "lieu" then
			local lieuType = tostring(ctx.lieuType or "")
			local targetU = tonumber(ctx.targetU)
			local targetV = tonumber(ctx.targetV)
			if actorId ~= "" and targetU and targetV then
				if lieuType == "chaumiere" then
					local blockedReason = GetBlockedPurposeReason("rest")
					if blockedReason then
						legacy[#legacy + 1] = {
							text = blockedReason,
							notCheckable = true,
							disabled = true,
						}
					else
						legacy[#legacy + 1] = {
							text = GetActionMenuLabel("rest", "Dinlen"),
							notCheckable = true,
							func = function()
								f:OrderNpcGoToPoint(actorId, targetU, targetV, "rest", "chaumiere")
							end,
						}
					end
				elseif lieuType == "taverne" then
					local blockedReason = GetBlockedPurposeReason("distraction")
					if blockedReason then
						legacy[#legacy + 1] = {
							text = blockedReason,
							notCheckable = true,
							disabled = true,
						}
					else
						legacy[#legacy + 1] = {
							text = GetActionMenuLabel("distraction", "Eglen"),
							notCheckable = true,
							func = function()
								f:OrderNpcGoToPoint(actorId, targetU, targetV, "distraction", "taverne")
							end,
						}
					end
				elseif lieuType == "auberge" then
					local blockedReason = GetBlockedPurposeReason("meal")
					if blockedReason then
						legacy[#legacy + 1] = {
							text = blockedReason,
							notCheckable = true,
							disabled = true,
						}
					else
						legacy[#legacy + 1] = {
							text = GetActionMenuLabel("meal", "Yemek ye"),
							notCheckable = true,
							func = function()
								f:OrderNpcGoToPoint(actorId, targetU, targetV, "meal", "auberge")
							end,
						}
					end
				end
			end
		end
		OpenLegacyOrderMenu(legacy)
	end

	local function GetCoverScale()
		local vw = viewport:GetWidth() or 0
		local vh = viewport:GetHeight() or 0
		if vw <= 0 or vh <= 0 or currentBaseW <= 0 or currentBaseH <= 0 then
			return 1
		end
		return math.max(vw / currentBaseW, vh / currentBaseH)
	end

	local function UpdateZoomBounds()
		state.minZoom = math.max(1, zoomMinFactor)
		state.maxZoom = math.max(state.minZoom, zoomMaxFactor)
	end

	local function GetVisibleSpan()
		local vw = viewport:GetWidth() or 0
		local vh = viewport:GetHeight() or 0
		if vw <= 0 or vh <= 0 or currentBaseW <= 0 or currentBaseH <= 0 then
			return 1, 1
		end
		local scale = GetCoverScale() * state.zoom
		if scale <= 0 then
			return 1, 1
		end
		local worldW = vw / scale
		local worldH = vh / scale
		local uSpan = Clamp(worldW / currentBaseW, 0, 1)
		local vSpan = Clamp(worldH / currentBaseH, 0, 1)
		return uSpan, vSpan
	end

	local function ClampCenter(uSpan, vSpan)
		local minCx, maxCx = uSpan * 0.5, 1 - (uSpan * 0.5)
		local minCy, maxCy = vSpan * 0.5, 1 - (vSpan * 0.5)
		if minCx > maxCx then
			state.cx = 0.5
		else
			state.cx = Clamp(state.cx, minCx, maxCx)
		end
		if minCy > maxCy then
			state.cy = 0.5
		else
			state.cy = Clamp(state.cy, minCy, maxCy)
		end
	end

	local function ApplyTransform()
		local mapChanged = RefreshMapAssets(false)
		if mapChanged then
			mapBg:SetTexture(currentTexPath)
			if dayCycleRuntime and dayCycleRuntime.SetMapId then
				dayCycleRuntime:SetMapId(GetActiveMapId())
				RestoreDayCyclePersistence()
			end
			RefreshTimeRuntime(false, 0)
		end
		UpdateZoomBounds()
		state.zoom = Clamp(state.zoom, state.minZoom, state.maxZoom)
		local uSpan, vSpan = GetVisibleSpan()
		ClampCenter(uSpan, vSpan)

		local u1 = state.cx - (uSpan * 0.5)
		local u2 = state.cx + (uSpan * 0.5)
		local v1 = state.cy - (vSpan * 0.5)
		local v2 = state.cy + (vSpan * 0.5)
		state.u1 = u1
		state.v1 = v1
		state.uSpan = uSpan
		state.vSpan = vSpan
		mapBg:SetTexCoord(u1, u2, v1, v2)
		if objectScene and objectScene.RenderAll then
			objectScene:RenderAll(false)
		end
		if Npc_RenderAll then
			Npc_RenderAll()
		end
		if routeEditor and routeEditor.Render then
			routeEditor.Render()
		end
	end

	local function SetZoomAroundPoint(newZoom, px, py)
		UpdateZoomBounds()
		local vw = viewport:GetWidth() or 0
		local vh = viewport:GetHeight() or 0
		if vw <= 0 or vh <= 0 then
			return
		end

		local oldUSpan, oldVSpan = GetVisibleSpan()
		ClampCenter(oldUSpan, oldVSpan)

		local nx = Clamp(((px and tonumber(px)) or (vw * 0.5)) / vw, 0, 1)
		local nyTop = Clamp(1 - (((py and tonumber(py)) or (vh * 0.5)) / vh), 0, 1)
		state.zoomPivotNX = nx
		state.zoomPivotNYTop = nyTop

		local worldU = (state.cx - oldUSpan * 0.5) + (nx * oldUSpan)
		local worldV = (state.cy - oldVSpan * 0.5) + (nyTop * oldVSpan)

		state.zoom = Clamp(newZoom, state.minZoom, state.maxZoom)
		local newUSpan, newVSpan = GetVisibleSpan()
		state.cx = worldU - ((nx - 0.5) * newUSpan)
		state.cy = worldV - ((nyTop - 0.5) * newVSpan)
		ApplyTransform()
	end

	local dragger = CreateFrame("Button", nil, viewport)
	dragger:SetAllPoints(viewport)
	dragger:EnableMouse(true)
	dragger:EnableMouseWheel(true)
	dragger:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")

	dragger:SetScript("OnMouseWheel", function(self, delta)
		if IsAltKeyDown and IsAltKeyDown() and objectScene and objectScene.AdjustSelectedScaleFromWheel then
			local ok = objectScene:AdjustSelectedScaleFromWheel(delta)
			if ok then
				if objectEditor and objectEditor.Refresh then
					objectEditor:Refresh()
				end
				return
			end
		end
		local factor = zoomWheelFactor
		local px, py = GetCursorPosition()
		local es = self:GetEffectiveScale() or 1
		px = px / es
		py = py / es
		local left = viewport:GetLeft() or 0
		local bottom = viewport:GetBottom() or 0
		px = px - left
		py = py - bottom
		if delta > 0 then
			SetZoomAroundPoint(state.zoom * factor, px, py)
		else
			SetZoomAroundPoint(state.zoom / factor, px, py)
		end
	end)

	dragger:SetScript("OnMouseDown", function(self, button)
		if button == "RightButton" then
			return
		end
		if button ~= "LeftButton" then
			return
		end
		state.leftDownAt = GetTime() or 0
		state.leftDownViewportX, state.leftDownViewportY = GetCursorViewportPosition(self)
		state.dragging = true
		local effectiveScale = self:GetEffectiveScale() or 1
		state.dragStartX, state.dragStartY = GetCursorPosition()
		state.dragStartX = state.dragStartX / effectiveScale
		state.dragStartY = state.dragStartY / effectiveScale
		state.dragOriginCx = state.cx
		state.dragOriginCy = state.cy
		state.dragUSpan, state.dragVSpan = GetVisibleSpan()
	end)

	dragger:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then
			local upAt = GetTime() or 0
			local upX, upY = GetCursorViewportPosition(self)
			local dx = (upX or 0) - (state.leftDownViewportX or 0)
			local dy = (upY or 0) - (state.leftDownViewportY or 0)
			local travel = math.sqrt((dx * dx) + (dy * dy))
			local duration = upAt - (state.leftDownAt or upAt)
			state.dragging = false
			if travel <= clickMaxTravelPx and duration <= clickMaxDuration then
				local wu, wv = ViewportPointToWorld(upX, upY)
				local hitLieu = (wu and wv) and FindLieuAtWorld(wu, wv) or nil
				if hitLieu then
					OpenBuildingPresencePanel(hitLieu)
				else
					HideBuildingPresencePanel()
				end
				if objectScene and objectEditor and objectEditor.IsVisible and objectEditor:IsVisible() then
					local pickedObjectId = objectScene:FindNearestObjectIdAtPoint(upX, upY, selectRadiusPx)
					if pickedObjectId and pickedObjectId ~= "" then
						objectScene:SelectObject(pickedObjectId)
						if objectEditor and objectEditor.Refresh then
							objectEditor:Refresh()
						end
						return
					end
				end
			end
			if npcInspector and travel <= clickMaxTravelPx and duration <= clickMaxDuration then
				if CloseDropDownMenus then
					CloseDropDownMenus()
				end
				local pickedId = FindNearestNpcIdAtPoint(upX, upY, selectRadiusPx, false)
				if pickedId then
					npcInspector:UpdateFromSnapshot(f:GetNpcDetailSnapshot(pickedId, false), nil)
					npcInspector:SetSelectedById(pickedId)
				else
					npcInspector:ClearSelection()
				end
			end
		elseif button == "RightButton" then
			HideBuildingPresencePanel()
			state.objectDragging = false
			state.dragging = false
			if IsRouteEditorDevMode() and IsShiftKeyDown and IsShiftKeyDown() then
				return
			end
			local upX, upY = GetCursorViewportPosition(self)
			local pickedId, snapshot = FindNearestNpcIdAtPoint(upX, upY, selectRadiusPx, true)

			local byId = BuildNpcLookup(snapshot)
			local previouslySelectedId = npcInspector and npcInspector:GetSelectedId() or nil
			if npcInspector and previouslySelectedId and previouslySelectedId ~= "" then
				npcInspector:UpdateFromSnapshot(f:GetNpcDetailSnapshot(previouslySelectedId, false), nil)
			end
			if
				npcInspector
				and pickedId
				and pickedId ~= ""
				and not (byId[pickedId] and byId[pickedId].playable == false)
				and (not previouslySelectedId or previouslySelectedId == "")
			then
				npcInspector:UpdateFromSnapshot(f:GetNpcDetailSnapshot(pickedId, false), nil)
				npcInspector:SetSelectedById(pickedId)
			end

			local actorId = npcInspector and npcInspector:GetSelectedId() or nil
			local actorNpc = npcInspector and npcInspector:GetSelectedNpc() or nil
			local actorName = tostring((actorNpc and actorNpc.name) or (actorId or ""))
			local hasPlayableActor = (
				type(actorId) == "string"
				and actorId ~= ""
				and not (actorNpc and actorNpc.playable == false)
			)
			if not hasPlayableActor then
				return
			end

			if pickedId and pickedId ~= "" then
				local hitNpc = byId[pickedId]
				ShowOrderContextMenu({
					mode = "npc",
					actorId = actorId,
					actorName = actorName,
					actorIsHero = actorNpc and actorNpc.isPlayerHero == true or actorId == "npc_player_hero",
					targetNpcId = pickedId,
					targetNpcName = tostring(hitNpc and hitNpc.name or pickedId),
					targetIsHero = hitNpc and hitNpc.isPlayerHero == true or pickedId == "npc_player_hero",
					targetIsRegisseuse = hitNpc and hitNpc.isRegisseuse == true or false,
				})
				return
			end

			local wu, wv = ViewportPointToWorld(upX, upY)
			local hitLieu = (wu and wv) and FindLieuAtWorld(wu, wv) or nil
			if hitLieu and hasPlayableActor then
				ShowOrderContextMenu({
					mode = "lieu",
					actorId = actorId,
					actorName = actorName,
					lieuType = hitLieu.type,
					targetU = hitLieu.u,
					targetV = hitLieu.v,
				})
				return
			end
			if IsPointOrderable(wu, wv) then
				ShowOrderContextMenu({
					mode = "point",
					actorId = hasPlayableActor and actorId or "",
					actorName = actorName,
					targetU = wu,
					targetV = wv,
				})
				return
			end
			if IsRouteEditorDevMode() then
				return
			end
		end
	end)

	dragger:SetScript("OnHide", function()
		state.dragging = false
		state.objectDragging = false
		state.leftDownAt = 0
		HideBuildingPresencePanel()
		HideBuildingHoverInfoPanel()
		if CloseDropDownMenus then
			CloseDropDownMenus()
		end
	end)

	dragger:SetScript("OnUpdate", function(self)
		if not state.dragging then
			return
		end
		local effectiveScale = self:GetEffectiveScale() or 1
		local cx, cy = GetCursorPosition()
		cx = cx / effectiveScale
		cy = cy / effectiveScale
		local dx = cx - state.dragStartX
		local dy = cy - state.dragStartY
		local vw = viewport:GetWidth() or 1
		local vh = viewport:GetHeight() or 1
		state.cx = state.dragOriginCx - (dx / vw) * state.dragUSpan
		state.cy = state.dragOriginCy + (dy / vh) * state.dragVSpan
		ApplyTransform()
	end)

	if ns and ns.QuartierMiniature and ns.QuartierMiniature.RouteEditor and ns.QuartierMiniature.RouteEditor.Attach then
		routeEditor = ns.QuartierMiniature.RouteEditor.Attach({
			parent = f,
			viewport = viewport,
			overlayParent = pathfindingLayer,
			overlayFrameLevel = pathfindingLayer:GetFrameLevel(),
			dragger = dragger,
			getCamera = function()
				return state.u1 or 0, state.v1 or 0, state.uSpan or 1, state.vSpan or 1
			end,
			getMapId = function()
				return GetActiveMapId()
			end,
			getNpcSnapshot = function()
				local selectedId = ""
				if npcInspector and npcInspector.GetSelectedId then
					selectedId = tostring(npcInspector:GetSelectedId() or "")
				end
				if selectedId ~= "" then
					local one = f:GetNpcDetailSnapshot(selectedId, true)
					if one then
						return { one }
					end
					return {}
				end
				return f:GetNpcSnapshot(true)
			end,
			setRegisseuseAnchor = function(u, v)
				return f:SetRegisseuseAnchor("npc_regisseuse", u, v)
			end,
			isDevMode = function()
				if ns and ns.Utils and ns.Utils.IsDevMode then
					return ns.Utils.IsDevMode()
				end
				return false
			end,
			shouldBlockRightClick = function(button)
				if button ~= "RightButton" then
					return false
				end
				if IsShiftKeyDown and IsShiftKeyDown() then
					return false
				end
				if not npcInspector then
					return false
				end
				local id = npcInspector:GetSelectedId()
				return type(id) == "string" and id ~= ""
			end,
		})
	end
	dragger:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")

	local OFFLINE_GRACE_SEC = 0
	local OFFLINE_HARD_CAP_SEC = 90 * 24 * 60 * 60
	local OFFLINE_DETAIL_CAP_SEC = 6 * 60 * 60
	local OFFLINE_DAY_SEC = 24 * 60 * 60
	local OFFLINE_FRAME_BUDGET_MS = 10
	local OFFLINE_MAX_STEPS_PER_FRAME = 180
	local OFFLINE_BOOST_FRAMES = 6
	local OFFLINE_BOOST_BUDGET_MS = 20
	local OFFLINE_BOOST_MAX_STEPS = 360
	local OFFLINE_OVERLAY_THRESHOLD_SEC = 20
	local OFFLINE_MIN_CATCHUP_SEC = 2.0
	local OFFLINE_SIMULATED_MAX_SEC = 90 * 60
	local OFFLINE_AVERAGE_MIN_SEC = 90 * 60
	local OFFLINE_AVERAGE_MAX_SEC = 2 * 60 * 60
	local OFFLINE_BACKGROUND_TICK_SEC = 5
	local OFFLINE_BACKGROUND_FLUSH_SEC = 60
	local npcSimAccum = 0
	local inspectorAccum = 0
	local presenceAccum = 0
	local loadingOverlayFactory = ns and ns.QuartierMiniature and ns.QuartierMiniature.LoadingOverlay
	if not (type(loadingOverlayFactory) == "table" and type(loadingOverlayFactory.Create) == "function") then
		error("WoWGuilde_QuartierMiniature: LoadingOverlay modulu bulunamadi")
	end
	loadingOverlayRuntime = loadingOverlayFactory.Create({
		parent = viewport,
		frameLevel = (hudLayer:GetFrameLevel() or 1) + 120,
		namePrefix = "WoWGuilde_QuartierMiniature_LoadingOverlay",
		isDevMode = function()
			if ns and ns.Utils and ns.Utils.IsDevMode then
				return ns.Utils.IsDevMode() == true
			end
			return false
		end,
	})
	if not loadingOverlayRuntime then
		error("WoWGuilde_QuartierMiniature: LoadingOverlay baslatma hatasi")
	end
	if loadingOverlayRuntime.SetEnvironmentTint and mapBg and mapBg.GetVertexColor then
		local r, g, b = mapBg:GetVertexColor()
		loadingOverlayRuntime:SetEnvironmentTint(r or MAP_BG_DEFAULT_R, g or MAP_BG_DEFAULT_G, b or MAP_BG_DEFAULT_B)
	end

	local function UpdateOfflineOverlay(show, doneSec, totalSec, logText)
		if loadingOverlayRuntime and loadingOverlayRuntime.Update then
			loadingOverlayRuntime:Update(show == true, doneSec, totalSec, logText)
		end
	end

	local offlineCoordinatorFactory = ns and ns.QuartierMiniature and ns.QuartierMiniature.OfflineCoordinator
	if not (type(offlineCoordinatorFactory) == "table" and type(offlineCoordinatorFactory.Create) == "function") then
		error("WoWGuilde_QuartierMiniature: OfflineCoordinator modulu bulunamadi")
	end

	offlineCoordinator = offlineCoordinatorFactory.Create({
		trackWhenUnavailable = true,
		graceSec = OFFLINE_GRACE_SEC,
		hardCapSec = OFFLINE_HARD_CAP_SEC,
		detailCapSec = OFFLINE_DETAIL_CAP_SEC,
		daySec = OFFLINE_DAY_SEC,
		overlayThresholdSec = OFFLINE_OVERLAY_THRESHOLD_SEC,
		frameBudgetMs = OFFLINE_FRAME_BUDGET_MS,
		frameMaxSteps = OFFLINE_MAX_STEPS_PER_FRAME,
		boostFrames = OFFLINE_BOOST_FRAMES,
		boostBudgetMs = OFFLINE_BOOST_BUDGET_MS,
		boostMaxSteps = OFFLINE_BOOST_MAX_STEPS,
		backgroundTickerSec = OFFLINE_BACKGROUND_TICK_SEC,
		backgroundFlushSec = OFFLINE_BACKGROUND_FLUSH_SEC,
		backgroundLiveWhileHidden = false,
		cloudsMinSec = 1.5,
		resolveMinSec = 0.20,
		minCatchupSec = OFFLINE_MIN_CATCHUP_SEC,
		simulatedMaxSec = OFFLINE_SIMULATED_MAX_SEC,
		averageMinSec = OFFLINE_AVERAGE_MIN_SEC,
		averageMaxSec = OFFLINE_AVERAGE_MAX_SEC,
		isSectionShown = function()
			return f:IsShown()
		end,
		getMapId = function()
			return GetActiveMapId()
		end,
		getBootstrapPersistenceEpoch = function()
			if npcRuntime and npcRuntime.GetBootstrapPersistenceEpoch then
				return npcRuntime.GetBootstrapPersistenceEpoch()
			end
			return 0
		end,
		getEpochNow = function()
			local serverNow = (GetServerTime and GetServerTime()) or nil
			if serverNow then
				return math.max(0, tonumber(serverNow) or 0)
			end
			return math.max(0, tonumber(time and time() or 0) or 0)
		end,
		getClockSeconds = function()
			if dayCycleRuntime and dayCycleRuntime.GetClockSeconds then
				return dayCycleRuntime:GetClockSeconds()
			end
			return 0
		end,
		isDevMode = function()
			if ns and ns.Utils and ns.Utils.IsDevMode then
				return ns.Utils.IsDevMode() == true
			end
			return false
		end,
		debugPrint = true,
		refreshTimeRuntime = function(updateClock, dt)
			RefreshTimeRuntime(updateClock == true, tonumber(dt) or 0)
		end,
		stepSimulation = function(step, opts)
			if npcRuntime and npcRuntime.StepSimulation then
				return npcRuntime.StepSimulation(step, opts)
			end
			return false
		end,
		applyApproximateOfflineDays = function(dayCount, opts)
			if npcRuntime and npcRuntime.ApplyApproximateOfflineDays then
				return npcRuntime.ApplyApproximateOfflineDays(dayCount, opts)
			end
			return false, 0
		end,
		applyApproximateOfflineSeconds = function(elapsedSec, opts)
			if npcRuntime and npcRuntime.ApplyApproximateOfflineSeconds then
				return npcRuntime.ApplyApproximateOfflineSeconds(elapsedSec, opts)
			end
			return false, 0
		end,
		beginVirtualClock = function(baseNowSec)
			if npcRuntime and npcRuntime.BeginVirtualClock then
				return npcRuntime.BeginVirtualClock(baseNowSec)
			end
			return 0
		end,
		endVirtualClock = function()
			if npcRuntime and npcRuntime.EndVirtualClock then
				return npcRuntime.EndVirtualClock()
			end
			return false
		end,
		flushPersistenceNow = function()
			return FlushMiniGamePersistence()
		end,
		setTimePaused = function(flag)
			if dayCycleRuntime and dayCycleRuntime.SetPaused then
				dayCycleRuntime:SetPaused(flag == true)
			end
		end,
		onOverlay = function(show, doneSec, totalSec, logText)
			UpdateOfflineOverlay(show, doneSec, totalSec, logText)
		end,
		onCatchupFinished = function()
			npcSimAccum = 0
			RefreshTimeRuntime(false, 0)
			if Npc_RenderAll then
				Npc_RenderAll()
			end
		end,
	})
	if not offlineCoordinator then
		error("WoWGuilde_QuartierMiniature: OfflineCoordinator baslatma hatasi")
	end

	local npcTicker = CreateFrame("Frame", nil, f)
	npcTicker:SetScript("OnUpdate", function(_, elapsed)
		if not f:IsShown() then
			return
		end
		local dt = tonumber(elapsed) or 0
		if
			offlineCoordinator
			and offlineCoordinator.HandleVisibleFrame
			and offlineCoordinator:HandleVisibleFrame(dt)
		then
			return
		end
		if RefreshMapAssets(false) then
			mapBg:SetTexture(currentTexPath)
			state.zoom = state.minZoom
			state.cx = 0.5
			state.cy = 0.5
			if objectScene and objectScene.SetMapId then
				objectScene:SetMapId(GetActiveMapId())
			end
			if dayCycleRuntime and dayCycleRuntime.SetMapId then
				dayCycleRuntime:SetMapId(GetActiveMapId())
				dayCycleRuntime:SetPaused(false)
				RestoreDayCyclePersistence()
			end
			RefreshTimeRuntime(false, 0)
			ApplyTransform()
			if npcInspector then
				npcInspector:ClearSelection()
			end
			HideBuildingPresencePanel()
			HideBuildingHoverInfoPanel()
			if objectEditor and objectEditor.Refresh then
				objectEditor:Refresh()
			end
		end

		RefreshTimeRuntime(true, dt)
		if Npc_UpdateAndRender then
			npcSimAccum = npcSimAccum + dt
			local steps = 0
			while npcSimAccum >= npcUpdateStep and steps < npcMaxCatchupSteps do
				Npc_UpdateAndRender(npcUpdateStep)
				npcSimAccum = npcSimAccum - npcUpdateStep
				steps = steps + 1
			end
			if npcSimAccum > (npcUpdateStep * npcMaxCatchupSteps) then
				npcSimAccum = npcUpdateStep
			end
			if steps == 0 and Npc_RenderAll then
				-- Keep PNJ visuals fluid during camera pan/zoom even when no sim step runs this frame.
				Npc_RenderAll()
			end
		end
		if npcInspector then
			inspectorAccum = inspectorAccum + dt
			if inspectorAccum >= inspectorRefreshStep then
				inspectorAccum = 0
				local selectedId = npcInspector:GetSelectedId()
				if selectedId and selectedId ~= "" then
					npcInspector:UpdateFromSnapshot(f:GetNpcDetailSnapshot(selectedId, false), nil)
				end
			end
			f:SetSelectedNpc(npcInspector:GetSelectedId())
		else
			f:SetSelectedNpc(nil)
		end
		if presencePanelState.lieuId then
			presenceAccum = presenceAccum + dt
			if presenceAccum >= presenceRefreshStep then
				presenceAccum = 0
				RefreshBuildingPresencePanel()
			end
		else
			presenceAccum = 0
		end
		if objectScene and objectScene.SetHoveredLieuId then
			local cx, cy = GetCursorPosition()
			local es = viewport:GetEffectiveScale() or 1
			cx = (tonumber(cx) or 0) / es
			cy = (tonumber(cy) or 0) / es
			local left = viewport:GetLeft() or 0
			local bottom = viewport:GetBottom() or 0
			local px = cx - left
			local py = cy - bottom
			local vw = viewport:GetWidth() or 0
			local vh = viewport:GetHeight() or 0
			if px >= 0 and py >= 0 and px <= vw and py <= vh then
				local wu, wv = ViewportPointToWorld(px, py)
				local hitLieu = (wu and wv) and FindLieuAtWorld(wu, wv) or nil
				objectScene:SetHoveredLieuId(hitLieu and hitLieu.linkId or nil)
				RefreshBuildingHoverInfoPanel(hitLieu, cx, cy)
			else
				objectScene:SetHoveredLieuId(nil)
				HideBuildingHoverInfoPanel()
			end
		end
		if routeEditor and routeEditor.Update then
			routeEditor.Update(dt)
		end
	end)

	f:SetScript("OnSizeChanged", function()
		ApplyTransform()
		ApplyInspiredNineSlice()
	end)

	f.ResetView = function()
		state.zoom = state.minZoom
		state.cx = 0.5
		state.cy = 0.5
		ApplyTransform()
	end

	f:SetScript("OnShow", function()
		portraitTimeline.displayProgress = nil
		portraitTimeline.lastUpdateAt = 0
		EnsurePortraitTimeline()
		SetPortraitTimelineVisible(true)
		RefreshMapAssets(true)
		mapBg:SetTexture(currentTexPath)
		if objectScene and objectScene.SetMapId then
			objectScene:SetMapId(GetActiveMapId())
		end
		if dayCycleRuntime and dayCycleRuntime.SetMapId then
			dayCycleRuntime:SetMapId(GetActiveMapId())
			dayCycleRuntime:SetPaused(false)
			RestoreDayCyclePersistence()
		end
		RefreshTimeRuntime(false, 0)
		f.ResetView()
		if npcInspector then
			npcInspector:ClearSelection()
		end
		HideBuildingPresencePanel()
		HideBuildingHoverInfoPanel()
		if objectEditor and objectEditor.Refresh then
			objectEditor:Refresh()
		end
		ApplyInspiredNineSlice()
		if routeEditor and routeEditor.RefreshVisibility then
			routeEditor.RefreshVisibility()
		end
		if routeEditor and routeEditor.Render then
			routeEditor.Render()
		end
		npcSimAccum = 0
		if offlineCoordinator and offlineCoordinator.HandleOnShow then
			offlineCoordinator:HandleOnShow()
		end
	end)

	f:SetScript("OnHide", function()
		SetPortraitTimelineVisible(false)
		if loadingOverlayRuntime and loadingOverlayRuntime.HideNow then
			loadingOverlayRuntime:HideNow()
		end
		if offlineCoordinator and offlineCoordinator.HandleOnHide then
			offlineCoordinator:HandleOnHide()
		else
			FlushMiniGamePersistence()
		end
		if dayCycleRuntime and dayCycleRuntime.SetPaused then
			dayCycleRuntime:SetPaused(false)
		end
	end)

	return f
end
