local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.ObjectScene = QM.ObjectScene or {}
local ObjectScene = QM.ObjectScene

local function Clamp(v, minV, maxV)
	if v < minV then
		return minV
	end
	if v > maxV then
		return maxV
	end
	return v
end

local function CopyObject(src)
	if type(src) ~= "table" then
		return nil
	end
	local out = {}
	for k, v in pairs(src) do
		out[k] = v
	end
	return out
end

function ObjectScene.Attach(opts)
	if type(opts) ~= "table" then
		return nil
	end
	local mapLayer = opts.mapLayer
	local viewport = opts.viewport
	local state = opts.state
	local objectLayerParent = opts.objectLayerParent or mapLayer
	local objectLayerFrameLevel = tonumber(opts.objectLayerFrameLevel)
	local hoverLayerParent = opts.hoverLayerParent or objectLayerParent
	local hoverLayerFrameLevel = tonumber(opts.hoverLayerFrameLevel)
	local getMapId = type(opts.getMapId) == "function" and opts.getMapId or function()
		return "default"
	end
	if not (mapLayer and viewport and state and QM.Objects and QM.Objects.EnsureMapStore) then
		return nil
	end

	local cfg = (ns and ns.QuartierMiniature and ns.QuartierMiniature.Config and ns.QuartierMiniature.Config.objects)
		or {}
	local updateInterval = math.max(0, tonumber(opts.updateInterval) or tonumber(cfg.updateInterval) or 0)
	local worldOffsetScale =
		Clamp(tonumber(opts.worldOffsetScale) or tonumber(cfg.worldOffsetScale) or 0.01, 0.001, 0.05)
	local verticalScale = Clamp(tonumber(opts.verticalScale) or tonumber(cfg.verticalScale) or 0.20, 0.01, 2.0)
	local zToXCompensation = Clamp(tonumber(opts.zToXCompensation) or tonumber(cfg.zToXCompensation) or 1.0, -5.0, 5.0)
	local zToYCompensation = Clamp(tonumber(opts.zToYCompensation) or tonumber(cfg.zToYCompensation) or 1.0, -5.0, 5.0)
	local colorTemperature = Clamp(tonumber(opts.colorTemperature) or tonumber(cfg.colorTemperature) or 0, -1.0, 1.0)
	local lightColorR = Clamp(tonumber(opts.lightColorR) or tonumber(cfg.lightColorR) or 1.0, 0.0, 2.0)
	local lightColorG = Clamp(tonumber(opts.lightColorG) or tonumber(cfg.lightColorG) or 1.0, 0.0, 2.0)
	local lightColorB = Clamp(tonumber(opts.lightColorB) or tonumber(cfg.lightColorB) or 1.0, 0.0, 2.0)
	local lightLuminance = Clamp(tonumber(opts.lightLuminance) or tonumber(cfg.lightLuminance) or 1.0, 0.0, 3.0)
	local defaultColorTemperature = colorTemperature
	local defaultLightColorR = lightColorR
	local defaultLightColorG = lightColorG
	local defaultLightColorB = lightColorB
	local defaultLightLuminance = lightLuminance
	local runtimeLightingOverride = nil
	local rotationMode = tostring(opts.rotationMode or cfg.rotationMode or "screen"):lower()
	if rotationMode ~= "screen" and rotationMode ~= "legacy" then
		rotationMode = "legacy"
	end
	local baseRotX = tonumber(opts.baseRotX) or tonumber(cfg.baseRotX) or 70
	local baseRotY = tonumber(opts.baseRotY) or tonumber(cfg.baseRotY) or 0
	local baseRotZ = tonumber(opts.baseRotZ) or tonumber(cfg.baseRotZ) or 0
	local mouseDragUnitsPerPixel =
		Clamp(tonumber(opts.mouseDragUnitsPerPixel) or tonumber(cfg.mouseDragUnitsPerPixel) or 1.0, 0.01, 100)
	local mouseDragCrossFactor =
		Clamp(tonumber(opts.mouseDragCrossFactor) or tonumber(cfg.mouseDragCrossFactor) or 1.0, -4, 4)
	local mouseScaleStep = Clamp(tonumber(opts.mouseScaleStep) or tonumber(cfg.mouseScaleStep) or 1.08, 1.001, 2.0)
	local lockToMap = (opts.lockToMap == true) or (cfg.lockToMap == true)
	local zoomModelScale = (opts.zoomModelScale ~= false) and (cfg.zoomModelScale ~= false)
	local zoomScaleFactor = Clamp(tonumber(opts.zoomScaleFactor) or tonumber(cfg.zoomScaleFactor) or 1.0, 0.10, 4.0)
	local zoomScaleExponent =
		Clamp(tonumber(opts.zoomScaleExponent) or tonumber(cfg.zoomScaleExponent) or 1.0, 0.25, 3.0)

	local function GetZoomFactor()
		local zoom = tonumber(state and state.zoom) or 1
		local minZoom = tonumber(state and state.minZoom) or 1
		if minZoom <= 0 then
			minZoom = 1
		end
		local base = math.max(0.01, zoom / minZoom)
		return (base ^ zoomScaleExponent) * zoomScaleFactor
	end

	local E = {}
	E.mapId = getMapId()
	E.selectedId = nil
	E.runtimes = {}
	E.statusById = {}
	E.hoverRuntimes = {}
	E.hoverStatusById = {}
	E.hoveredLieuId = nil
	E.hoverLightMultiplier = 1.6
	E.selectedLightMultiplier = 1.0
	E.warnedWmo = {}
	E.dragState = nil
	E._emitChanged = nil
	E._lastRenderAt = 0
	E._lastStackAt = 0

	local objectLayer = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureObjectLayer", objectLayerParent)
	objectLayer:SetAllPoints(viewport)
	if objectLayerFrameLevel then
		objectLayer:SetFrameLevel(math.floor(objectLayerFrameLevel))
	else
		objectLayer:SetFrameLevel(mapLayer:GetFrameLevel() + 6)
	end
	objectLayer:EnableMouse(false)
	E.objectLayer = objectLayer

	local hoverLayer = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureObjectHoverLayer", hoverLayerParent)
	hoverLayer:SetAllPoints(viewport)
	if hoverLayerFrameLevel then
		hoverLayer:SetFrameLevel(math.floor(hoverLayerFrameLevel))
	else
		hoverLayer:SetFrameLevel(objectLayer:GetFrameLevel() + 2)
	end
	hoverLayer:EnableMouse(false)
	hoverLayer:Hide()
	E.hoverLayer = hoverLayer

	local function EmitChanged(reason)
		if type(E._emitChanged) == "function" then
			E._emitChanged(reason)
		end
	end

	local function SetRuntimeSelected(rt, selected)
		if not rt then
			return
		end
		rt._selected = (selected == true)
	end

	local function NormalizeRuntimeLightingOverride(raw)
		if type(raw) ~= "table" then
			return nil
		end
		local src = raw
		if type(src.colors) == "table" and type(src.colors.models) == "table" then
			src = src.colors.models
		elseif type(src.models) == "table" then
			src = src.models
		end
		if type(src) ~= "table" then
			return nil
		end
		return {
			colorTemperature = Clamp(tonumber(src.colorTemperature) or colorTemperature, -1.0, 1.0),
			lightColorR = Clamp(tonumber(src.lightColorR) or lightColorR, 0.0, 2.0),
			lightColorG = Clamp(tonumber(src.lightColorG) or lightColorG, 0.0, 2.0),
			lightColorB = Clamp(tonumber(src.lightColorB) or lightColorB, 0.0, 2.0),
			lightLuminance = Clamp(tonumber(src.lightLuminance) or lightLuminance, 0.0, 3.0),
		}
	end

	local function IsRuntimeLightingOverrideEqual(a, b)
		if a == b then
			return true
		end
		if type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		return math.abs((tonumber(a.colorTemperature) or 0) - (tonumber(b.colorTemperature) or 0)) <= 1e-6
			and math.abs((tonumber(a.lightColorR) or 1) - (tonumber(b.lightColorR) or 1)) <= 1e-6
			and math.abs((tonumber(a.lightColorG) or 1) - (tonumber(b.lightColorG) or 1)) <= 1e-6
			and math.abs((tonumber(a.lightColorB) or 1) - (tonumber(b.lightColorB) or 1)) <= 1e-6
			and math.abs((tonumber(a.lightLuminance) or 1) - (tonumber(b.lightLuminance) or 1)) <= 1e-6
	end

	local function GetEffectiveGlobalLighting()
		if type(runtimeLightingOverride) ~= "table" then
			return colorTemperature, lightColorR, lightColorG, lightColorB, lightLuminance
		end
		return runtimeLightingOverride.colorTemperature or colorTemperature,
			runtimeLightingOverride.lightColorR or lightColorR,
			runtimeLightingOverride.lightColorG or lightColorG,
			runtimeLightingOverride.lightColorB or lightColorB,
			runtimeLightingOverride.lightLuminance or lightLuminance
	end

	local function ApplyLightingOnModel(model, luminanceMultiplier, objectTintR, objectTintG, objectTintB)
		if not model then
			return
		end
		local activeTemp, activeR, activeG, activeB, activeLum = GetEffectiveGlobalLighting()
		local t = Clamp(tonumber(activeTemp) or 0, -1, 1)
		local tempR, tempG, tempB = 1.0, 1.0, 1.0
		if t >= 0 then
			tempG = 1.0 - (0.15 * t)
			tempB = 1.0 - (0.35 * t)
		else
			local c = math.abs(t)
			tempR = 1.0 - (0.30 * c)
			tempG = 1.0 - (0.10 * c)
		end
		local lumBoost = Clamp(tonumber(luminanceMultiplier) or 1.0, 0.0, 3.0)
		local lum = math.max(0, (tonumber(activeLum) or 1.0) * lumBoost)
		local tintObjR = Clamp(tonumber(objectTintR) or 1.0, 0.0, 2.0)
		local tintObjG = Clamp(tonumber(objectTintG) or 1.0, 0.0, 2.0)
		local tintObjB = Clamp(tonumber(objectTintB) or 1.0, 0.0, 2.0)
		-- Keep object tint chromatic: color changes should not increase exposure.
		local tintPeak = math.max(tintObjR, tintObjG, tintObjB, 1.0)
		tintObjR = tintObjR / tintPeak
		tintObjG = tintObjG / tintPeak
		tintObjB = tintObjB / tintPeak
		local r = Clamp((tonumber(activeR) or 1.0) * tempR * lum * tintObjR, 0, 3)
		local g = Clamp((tonumber(activeG) or 1.0) * tempG * lum * tintObjG, 0, 3)
		local b = Clamp((tonumber(activeB) or 1.0) * tempB * lum * tintObjB, 0, 3)
		local ambR = Clamp(r * 0.55, 0, 1)
		local ambG = Clamp(g * 0.55, 0, 1)
		local ambB = Clamp(b * 0.55, 0, 1)
		local diffR = Clamp(r * 0.95, 0, 1)
		local diffG = Clamp(g * 0.95, 0, 1)
		local diffB = Clamp(b * 0.95, 0, 1)
		local tintR = Clamp(r, 0, 1)
		local tintG = Clamp(g, 0, 1)
		local tintB = Clamp(b, 0, 1)
		-- Some M2 pipelines react to model color, others to light vectors/colors.
		if model.SetModelColor then
			pcall(model.SetModelColor, model, tintR, tintG, tintB)
		end
		if model.SetLightAmbientColor then
			pcall(model.SetLightAmbientColor, model, ambR, ambG, ambB)
		end
		if model.SetLightDiffuseColor then
			pcall(model.SetLightDiffuseColor, model, diffR, diffG, diffB)
		end
		if model.SetLightDirection then
			pcall(model.SetLightDirection, model, -0.2, -1.0, -0.3)
		end
		if model.SetLight then
			-- Retail/current API form: SetLight(enabled, ModelLightTable)
			local light = {
				omnidirectional = false,
				point = { x = -0.2, y = -1.0, z = -0.3 },
				ambientIntensity = 1.0,
				ambientColor = { r = ambR, g = ambG, b = ambB },
				diffuseIntensity = 1.0,
				diffuseColor = { r = diffR, g = diffG, b = diffB },
			}
			local ok = pcall(model.SetLight, model, true, light)
			if not ok then
				-- Legacy fallback signature seen on older clients/docs.
				pcall(
					model.SetLight,
					model,
					true,
					false,
					-0.2,
					-1.0,
					-0.3,
					1.0,
					ambR,
					ambG,
					ambB,
					1.0,
					diffR,
					diffG,
					diffB
				)
				pcall(model.SetLight, model, true, false, -0.2, -1.0, -0.3, ambR, ambG, ambB, diffR, diffG, diffB)
			end
		end
	end

	local function ApplyRuntimeLighting(rt, luminanceMultiplier, obj)
		if not rt then
			return
		end
		rt._lightObj = obj
		local objTintR = tonumber(obj and obj.objectColorR) or 1.0
		local objTintG = tonumber(obj and obj.objectColorG) or 1.0
		local objTintB = tonumber(obj and obj.objectColorB) or 1.0
		ApplyLightingOnModel(rt.playerModel, luminanceMultiplier, objTintR, objTintG, objTintB)
		ApplyLightingOnModel(rt.genericModel, luminanceMultiplier, objTintR, objTintG, objTintB)
	end

	local function WorldToScreen(u, v)
		local u1 = tonumber(state.u1) or 0
		local v1 = tonumber(state.v1) or 0
		local uSpan = tonumber(state.uSpan) or 1
		local vSpan = tonumber(state.vSpan) or 1
		local vw = viewport:GetWidth() or 0
		local vh = viewport:GetHeight() or 0
		if vw <= 0 or vh <= 0 or uSpan <= 0 or vSpan <= 0 then
			return nil, nil
		end
		local nx = (u - u1) / uSpan
		local ny = (v - v1) / vSpan
		return nx * vw, (1 - ny) * vh
	end

	local function ResolveWorldUV(obj)
		local u = Clamp((tonumber(obj and obj.u) or 0.5), 0, 1)
		local v = Clamp((tonumber(obj and obj.v) or 0.5), 0, 1)
		return u, v
	end

	local function BuildPoseKey(obj)
		if type(obj) ~= "table" then
			return "invalid"
		end
		return table.concat({
			tostring(obj.sourceType or ""),
			tostring(obj.sourceValue or ""),
			string.format("%.4f", (tonumber(obj.x) or 0) * worldOffsetScale),
			string.format("%.4f", (tonumber(obj.y) or 0) * worldOffsetScale),
			string.format("%.4f", tonumber(obj.yaw) or 0),
			string.format("%.4f", tonumber(obj.pitch) or 0),
			string.format("%.4f", tonumber(obj.roll) or 0),
			string.format("%.4f", tonumber(obj.scale) or 1),
			string.format("%.4f", (tonumber(obj.z) or 0) * verticalScale),
		}, "|")
	end

	local function GetStore()
		return QM.Objects.EnsureMapStore(E.mapId)
	end

	local function GetMapSettingsRef()
		local store = GetStore()
		store.settings = type(store.settings) == "table" and store.settings or {}
		return store.settings
	end

	local function GetMapAmbientSettingsRef()
		local settings = GetMapSettingsRef()
		settings.ambientLighting = type(settings.ambientLighting) == "table" and settings.ambientLighting or {}
		return settings.ambientLighting
	end

	local function ReapplyLightingToAll()
		for _, rt in pairs(E.runtimes) do
			ApplyRuntimeLighting(rt, tonumber(rt._lightMultiplier) or 1.0, rt and rt._lightObj or nil)
		end
		for _, rt in pairs(E.hoverRuntimes) do
			ApplyRuntimeLighting(rt, E.hoverLightMultiplier)
		end
	end

	local function PersistAmbientLightingToMap()
		local ambient = GetMapAmbientSettingsRef()
		ambient.colorTemperature = Clamp(tonumber(colorTemperature) or 0, -1.0, 1.0)
		ambient.lightColorR = Clamp(tonumber(lightColorR) or 1.0, 0.0, 2.0)
		ambient.lightColorG = Clamp(tonumber(lightColorG) or 1.0, 0.0, 2.0)
		ambient.lightColorB = Clamp(tonumber(lightColorB) or 1.0, 0.0, 2.0)
		ambient.lightLuminance = Clamp(tonumber(lightLuminance) or 1.0, 0.0, 3.0)
	end

	local function ApplyAmbientLightingFromMap()
		local ambient = GetMapAmbientSettingsRef()
		colorTemperature = Clamp(tonumber(ambient.colorTemperature) or defaultColorTemperature, -1.0, 1.0)
		lightColorR = Clamp(tonumber(ambient.lightColorR) or defaultLightColorR, 0.0, 2.0)
		lightColorG = Clamp(tonumber(ambient.lightColorG) or defaultLightColorG, 0.0, 2.0)
		lightColorB = Clamp(tonumber(ambient.lightColorB) or defaultLightColorB, 0.0, 2.0)
		lightLuminance = Clamp(tonumber(ambient.lightLuminance) or defaultLightLuminance, 0.0, 3.0)
	end

	local function GetObjectsRef()
		local store = GetStore()
		store.objects = type(store.objects) == "table" and store.objects or {}
		return store.objects
	end

	local function GetHoverStore()
		if not (QM.HoverObjects and QM.HoverObjects.EnsureMapStore) then
			return nil
		end
		return QM.HoverObjects.EnsureMapStore(E.mapId)
	end

	local function GetHoverLinksRef()
		local store = GetHoverStore()
		if not store then
			return {}
		end
		store.links = type(store.links) == "table" and store.links or {}
		return store.links
	end

	local function GetHoverSettingsRef()
		local store = GetHoverStore()
		local mapSettings = GetMapSettingsRef()
		local mapHoverLum = Clamp(tonumber(mapSettings.hoverLightMultiplier) or 1.6, 1.0, 3.0)
		if not store then
			mapSettings.hoverLightMultiplier = mapHoverLum
			return nil
		end
		store.settings = type(store.settings) == "table" and store.settings or {}
		local fromHoverStore = tonumber(store.settings.lightMultiplier)
		if fromHoverStore then
			store.settings.lightMultiplier = Clamp(fromHoverStore, 1.0, 3.0)
			mapSettings.hoverLightMultiplier = store.settings.lightMultiplier
		else
			store.settings.lightMultiplier = mapHoverLum
			mapSettings.hoverLightMultiplier = mapHoverLum
		end
		return store.settings
	end

	local function FindObjectById(id)
		local objId = tostring(id or "")
		if objId == "" then
			return nil, nil
		end
		local objs = GetObjectsRef()
		for i = 1, #objs do
			if tostring(objs[i] and objs[i].id or "") == objId then
				return objs[i], i
			end
		end
		return nil, nil
	end

	local function NextObjectId(objs)
		local used = {}
		for i = 1, #objs do
			local id = tostring(objs[i] and objs[i].id or "")
			if id ~= "" then
				used[id] = true
			end
		end
		local n = 1
		while used["obj_" .. n] do
			n = n + 1
		end
		return "obj_" .. n
	end

	local function NextHoverLinkId(links)
		local used = {}
		for i = 1, #links do
			local id = tostring(links[i] and links[i].id or "")
			if id ~= "" then
				used[id] = true
			end
		end
		local n = 1
		while used["hover_" .. n] do
			n = n + 1
		end
		return "hover_" .. n
	end

	local function RepairLegacyDuplicateFrameOffset()
		local objs = GetObjectsRef()
		if #objs <= 1 then
			return 0
		end
		local changed = 0
		local epsilon = 0.00005
		local legacyStep = 0.015

		local function NearlyZero(v)
			return math.abs(tonumber(v) or 0) <= epsilon
		end

		local function BuildPoseSignature(obj)
			if type(obj) ~= "table" then
				return ""
			end
			return table.concat({
				tostring(obj.sourceType or ""),
				tostring(obj.sourceValue or ""),
				tostring(obj.sourceFileId or ""),
				string.format("%.4f", tonumber(obj.x) or 0),
				string.format("%.4f", tonumber(obj.y) or 0),
				string.format("%.4f", tonumber(obj.z) or 0),
				string.format("%.4f", tonumber(obj.yaw) or 0),
				string.format("%.4f", tonumber(obj.pitch) or 0),
				string.format("%.4f", tonumber(obj.roll) or 0),
				string.format("%.4f", tonumber(obj.scale) or 1),
				tostring(obj.size or 96),
				tostring(obj.enabled ~= false),
				tostring(obj.hoverLinkId or ""),
			}, "|")
		end

		local groups = {}
		for i = 1, #objs do
			local obj = objs[i]
			local sig = BuildPoseSignature(obj)
			if sig ~= "" then
				local g = groups[sig]
				if not g then
					g = {}
					groups[sig] = g
				end
				g[#g + 1] = obj
			end
		end

		for _, group in pairs(groups) do
			if #group > 1 then
				local anchor = group[1]
				local au = tonumber(anchor and anchor.u)
				local av = tonumber(anchor and anchor.v)
				if au and av then
					for idx = 2, #group do
						local candidate = group[idx]
						local cu = tonumber(candidate and candidate.u)
						local cv = tonumber(candidate and candidate.v)
						if candidate and cu and cv then
							local du = cu - au
							local dv = cv - av
							local stepU = du / legacyStep
							local stepV = dv / legacyStep
							local nU = math.floor(stepU + 0.5)
							local nV = math.floor(stepV + 0.5)
							if
								nU > 0
								and nV > 0
								and nU == nV
								and NearlyZero(stepU - nU)
								and NearlyZero(stepV - nV)
							then
								candidate.u = Clamp(au, 0, 1)
								candidate.v = Clamp(av, 0, 1)
								changed = changed + 1
							end
						end
					end
				end
			end
		end
		return changed
	end

	local function FindHoverLinkById(id)
		local linkId = tostring(id or "")
		if linkId == "" then
			return nil, nil
		end
		local links = GetHoverLinksRef()
		for i = 1, #links do
			if tostring(links[i] and links[i].id or "") == linkId then
				return links[i], i
			end
		end
		return nil, nil
	end

	local function HasLieuId(lieuId)
		local routesRoot = ns and ns.QuartierMiniature and ns.QuartierMiniature.Routes or nil
		if type(routesRoot) ~= "table" then
			return false
		end
		local mapStore = nil
		if type(routesRoot.maps) == "table" then
			mapStore = routesRoot.maps[E.mapId]
		else
			mapStore = routesRoot
		end
		local lieux = type(mapStore and mapStore.lieux) == "table" and mapStore.lieux or nil
		if not lieux then
			return false
		end
		local target = tostring(lieuId or "")
		for i = 1, #lieux do
			local id = tostring(lieux[i] and lieux[i].id or "")
			if id ~= "" and id == target then
				return true
			end
		end
		return false
	end

	local function AcquireRuntime(runtimeTable, id, parentLayer, withSelection)
		local tableRef = runtimeTable or E.runtimes
		local layerRef = parentLayer or objectLayer
		local rt = tableRef[id]
		if rt then
			return rt
		end
		rt = {}
		rt._ownerTable = tableRef
		rt._ownerId = tostring(id or "")
		rt.holder = CreateFrame("Frame", nil, layerRef, "BackdropTemplate")
		rt.holder:SetFrameLevel(layerRef:GetFrameLevel() + 2)
		rt.holder:EnableMouse(false)

		rt.playerModel = CreateFrame("PlayerModel", nil, rt.holder)
		rt.playerModel:SetAllPoints(rt.holder)
		rt.playerModel:EnableMouse(false)
		rt.playerModel:SetAlpha(1)
		if rt.playerModel.SetKeepModelOnHide then
			pcall(rt.playerModel.SetKeepModelOnHide, rt.playerModel, true)
		end
		if rt.playerModel.SetPortraitZoom then
			pcall(rt.playerModel.SetPortraitZoom, rt.playerModel, 0)
		end
		if rt.playerModel.SetCamDistanceScale then
			pcall(rt.playerModel.SetCamDistanceScale, rt.playerModel, 1)
		end
		rt.genericModel = CreateFrame("Model", nil, rt.holder)
		rt.genericModel:SetAllPoints(rt.holder)
		rt.genericModel:EnableMouse(false)
		rt.genericModel:SetAlpha(1)
		if rt.genericModel.SetKeepModelOnHide then
			pcall(rt.genericModel.SetKeepModelOnHide, rt.genericModel, true)
		end
		rt.genericModel:Hide()

		rt.model = rt.playerModel
		rt._loadToken = 0
		ApplyRuntimeLighting(rt)
		if withSelection ~= false then
			rt.selection = layerRef:CreateTexture(nil, "OVERLAY", nil, 7)
			if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Map_Faction_Ring") then
				rt.selection:SetAtlas("Map_Faction_Ring")
			else
				rt.selection:SetTexture("Interface\\Buttons\\WHITE8X8")
			end
			rt.selection:SetVertexColor(1.00, 0.84, 0.10, 0.65)
			rt.selection:Hide()
		end
		tableRef[id] = rt
		return rt
	end

	local function SetActiveModel(rt, model)
		if not rt then
			return
		end
		rt.model = model or rt.playerModel or rt.genericModel
		if rt.model == rt.genericModel then
			rt._activeRendererKind = "generic"
		else
			rt._activeRendererKind = "player"
		end
		if rt.playerModel then
			if rt.model == rt.playerModel then
				rt.playerModel:Show()
			else
				rt.playerModel:Hide()
			end
		end
		if rt.genericModel then
			if rt.model == rt.genericModel then
				rt.genericModel:Show()
			else
				rt.genericModel:Hide()
			end
		end
		ApplyRuntimeLighting(rt, tonumber(rt._lightMultiplier) or 1.0, rt and rt._lightObj or nil)
	end

	local function ApplyRuntimePose(rt, obj)
		local m = rt and rt.model
		if not (m and type(obj) == "table") then
			return
		end
		local yawInput = tonumber(obj.yaw) or 0
		local pitchInput = tonumber(obj.pitch) or 0
		local rollInput = tonumber(obj.roll) or 0
		local yaw
		local pitch
		local roll
		if rotationMode == "screen" then
			-- Screen-intuitive mapping:
			-- Rot Z (yaw slider) spins visually around camera axis (SetRoll),
			-- Rot X (pitch slider) tilts up/down from baseRotX,
			-- Rot Y (roll slider) turns side axis from baseRotY.
			yaw = math.rad(baseRotY + rollInput)
			pitch = math.rad(baseRotX + pitchInput)
			roll = math.rad(baseRotZ + yawInput)
		else
			-- Native engine axes
			yaw = math.rad(yawInput)
			pitch = math.rad(pitchInput)
			roll = math.rad(rollInput)
		end
		local scale = tonumber(obj.scale) or 1
		local x = (tonumber(obj.x) or 0) * worldOffsetScale
		local y = (tonumber(obj.y) or 0) * worldOffsetScale
		local z = (tonumber(obj.z) or 0) * verticalScale
		local xComp = x + (z * zToXCompensation)
		local yComp = y - (z * zToYCompensation)
		-- Scale must be committed first, otherwise tiny-scale models can keep
		-- an incorrect first-frame offset until a later refresh.
		if m.SetModelScale then
			pcall(m.SetModelScale, m, scale)
		elseif m.SetScale then
			pcall(m.SetScale, m, scale)
		end
		if m.SetFacing then
			pcall(m.SetFacing, m, yaw)
		end
		if m.SetYaw then
			pcall(m.SetYaw, m, yaw)
		end
		if m.SetPitch then
			pcall(m.SetPitch, m, pitch)
		end
		if m.SetRoll then
			pcall(m.SetRoll, m, roll)
		end
		if m.SetPosition then
			pcall(m.SetPosition, m, xComp, yComp, z)
		end
	end

	local function LayoutRuntime(rt, centerX, centerY, parentLayer)
		if not rt or not rt.holder then
			return
		end
		if not centerX or not centerY then
			return
		end
		local vw = viewport:GetWidth() or 0
		local vh = viewport:GetHeight() or 0
		-- Fixed full-map render zone: always 100% of the viewport.
		local zoomFactor = (zoomModelScale and not lockToMap) and GetZoomFactor() or 1
		local rw = math.max(2, vw * zoomFactor)
		local rh = math.max(2, vh * zoomFactor)
		rt.holder:ClearAllPoints()
		rt.holder:SetPoint("CENTER", parentLayer or objectLayer, "BOTTOMLEFT", centerX, centerY)
		rt.holder:SetSize(rw, rh)
		rt.holder:SetScale(1)
	end

	local function ReleaseMissingRuntime(runtimeTable, statusTable, keep)
		local rtTable = runtimeTable or E.runtimes
		local stTable = statusTable or E.statusById
		for id, rt in pairs(rtTable) do
			if not keep[id] then
				if rt.playerModel and rt.playerModel.ClearModel then
					rt.playerModel:ClearModel()
				end
				if rt.genericModel and rt.genericModel.ClearModel then
					rt.genericModel:ClearModel()
				end
				if rt.holder then
					rt.holder:Hide()
					rt.holder:SetParent(nil)
				end
				if rt.selection then
					rt.selection:Hide()
					rt.selection:SetParent(nil)
				end
				rtTable[id] = nil
				stTable[id] = nil
			end
		end
	end

	local function ApplyModelSource(rt, obj)
		if not (rt and type(obj) == "table") then
			return "invalid"
		end
		local function NeedsScaleStabilization(modelObj)
			local scale = tonumber(modelObj and modelObj.scale) or 1
			return scale > 0 and scale < 0.25
		end
		local function NextLoadToken()
			rt._loadToken = (tonumber(rt._loadToken) or 0) + 1
			return rt._loadToken
		end
		local function IsLoadedOn(model)
			if not model then
				return false
			end
			if model.GetModelFileID then
				local okFid, fid = pcall(model.GetModelFileID, model)
				if okFid and tonumber(fid) and tonumber(fid) > 0 then
					return true
				end
			end
			if model.GetModel then
				local okPath, path = pcall(model.GetModel, model)
				if okPath and type(path) == "string" and path ~= "" then
					return true
				end
			end
			return false
		end
		local kind = tostring(obj.kind or ""):lower()
		local rawPath = tostring(obj.sourceValue or ""):lower()
		if kind == "wmo" or (tostring(obj.sourceType or "") == "path" and rawPath:match("%.wmo$")) then
			local warnKey = tostring(obj.sourceType or "") .. ":" .. tostring(obj.sourceValue or "")
			if not E.warnedWmo[warnKey] then
				E.warnedWmo[warnKey] = true
				print("|cffff7f50[WoWGuilde]|r WMO desactive: support retire.")
			end
			rt.lastStatus = "non_renderable"
			return rt.lastStatus
		end
		local sourceKey = tostring(obj.sourceType or "")
			.. ":"
			.. tostring(obj.sourceValue or "")
			.. ":"
			.. tostring(obj.sourceFileId or "")
		if rt.sourceKey == sourceKey then
			return rt.lastStatus or "loaded"
		end
		rt.sourceKey = sourceKey
		rt.lastStatus = "non_renderable"
		NextLoadToken()
		if rt.playerModel and rt.playerModel.ClearModel then
			rt.playerModel:ClearModel()
		end
		if rt.genericModel and rt.genericModel.ClearModel then
			rt.genericModel:ClearModel()
		end

		local function BuildPathCandidates(path)
			local raw = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", "")
			if raw == "" then
				return {}
			end
			local out = {}
			local seen = {}
			local function Add(v)
				v = tostring(v or "")
				if v ~= "" and not seen[v] then
					seen[v] = true
					out[#out + 1] = v
				end
			end
			Add(raw)
			Add(raw:gsub("\\", "/"))
			Add(raw:gsub("/", "\\"))
			return out
		end

		local function TryLoadOn(model)
			if not model then
				return false
			end
			if model.Show then
				model:Show()
			end
			if model.SetAlpha then
				model:SetAlpha(1)
			end
			if model.SetPortraitZoom then
				pcall(model.SetPortraitZoom, model, 0)
			end
			if model.SetCamDistanceScale then
				pcall(model.SetCamDistanceScale, model, 1)
			end
			if model.ClearModel then
				pcall(model.ClearModel, model)
			end
			local ok = false
			if obj.sourceType == "fileid" then
				local fid = tonumber(obj.sourceValue)
				if fid and fid > 0 then
					fid = math.floor(fid)
					if model.SetModelByFileID then
						ok = pcall(model.SetModelByFileID, model, fid)
					end
					if not ok and model.SetModel then
						ok = pcall(model.SetModel, model, fid)
					end
				end
			elseif obj.sourceType == "path" then
				local candidates = BuildPathCandidates(obj.sourceValue)
				if #candidates > 0 and model.SetModel then
					for i = 1, #candidates do
						ok = pcall(model.SetModel, model, candidates[i])
						if ok then
							break
						end
					end
				end
			end

			if not ok then
				local fid = tonumber(obj.sourceFileId)
				if fid and fid > 0 then
					fid = math.floor(fid)
					if model.SetModelByFileID then
						ok = pcall(model.SetModelByFileID, model, fid)
					end
					if not ok and model.SetModel then
						ok = pcall(model.SetModel, model, fid)
					end
				end
			end
			return ok
		end

		local order = {}
		local seen = {}
		local function PushRenderer(r)
			if r and not seen[r] then
				seen[r] = true
				order[#order + 1] = r
			end
		end
		local preferred = tostring(rt._preferredRenderer or "")
		if preferred == "generic" then
			PushRenderer(rt.genericModel)
			PushRenderer(rt.playerModel)
		elseif preferred == "player" then
			PushRenderer(rt.playerModel)
			PushRenderer(rt.genericModel)
		else
			PushRenderer(rt.playerModel)
			PushRenderer(rt.genericModel)
		end

		local ok = false
		for i = 1, #order do
			if TryLoadOn(order[i]) then
				SetActiveModel(rt, order[i])
				ok = true
				break
			end
		end
		if not ok then
			SetActiveModel(rt, rt.playerModel or rt.genericModel)
		end

		rt.lastStatus = ok and "loading" or "non_renderable"
		if ok then
			local token = NextLoadToken()
			local maxRetries = 8
			local function ScheduleScaleStabilizationReloads()
				if not NeedsScaleStabilization(obj) then
					return
				end
				if rt._stabilizedSourceKey == sourceKey then
					return
				end
				rt._stabilizedSourceKey = sourceKey
				local function RebuildAfter(delaySeconds)
					C_Timer.After(delaySeconds, function()
						local owner = rt._ownerTable or E.runtimes
						local ownerId = tostring(rt._ownerId or obj.id or "")
						if not owner[ownerId] then
							return
						end
						if tostring(rt.sourceKey or "") ~= sourceKey then
							return
						end
						-- Hard-reset model payload, then re-apply source/pose.
						-- This fixes first-open bad transforms on tiny scales.
						NextLoadToken()
						if rt.playerModel and rt.playerModel.ClearModel then
							pcall(rt.playerModel.ClearModel, rt.playerModel)
						end
						if rt.genericModel and rt.genericModel.ClearModel then
							pcall(rt.genericModel.ClearModel, rt.genericModel)
						end
						rt.sourceKey = nil
						rt.poseKey = nil
						ApplyModelSource(rt, obj)
						ApplyRuntimePose(rt, obj)
					end)
				end
				RebuildAfter(0.00)
				RebuildAfter(0.15)
			end
			local function EnsureModelLoaded(attempt)
				local owner = rt._ownerTable or E.runtimes
				local ownerId = tostring(rt._ownerId or obj.id or "")
				if not owner[ownerId] then
					return
				end
				if token ~= rt._loadToken then
					return
				end
				local active = rt.model
				ApplyRuntimeLighting(rt, tonumber(rt._lightMultiplier) or 1.0, obj)
				if IsLoadedOn(active) then
					-- Model frames can reset transforms once payload is fully loaded.
					-- Re-apply pose here to keep first render aligned (notably tiny scales).
					ApplyRuntimePose(rt, obj)
					-- One extra delayed pass keeps first-open placement stable on
					-- slow async M2 initialization paths.
					C_Timer.After(0.02, function()
						local owner2 = rt._ownerTable or E.runtimes
						local ownerId2 = tostring(rt._ownerId or obj.id or "")
						if owner2[ownerId2] and token == rt._loadToken then
							ApplyRuntimePose(rt, obj)
						end
					end)
					ScheduleScaleStabilizationReloads()
					rt.lastStatus = "loaded"
					return
				end
				if attempt >= maxRetries then
					rt.lastStatus = "non_renderable"
					return
				end
				if active then
					TryLoadOn(active)
				end
				for i = 1, #order do
					local m = order[i]
					if m ~= active and TryLoadOn(m) then
						SetActiveModel(rt, m)
						ApplyRuntimePose(rt, obj)
						break
					end
				end
				C_Timer.After(0.25, function()
					EnsureModelLoaded(attempt + 1)
				end)
			end
			C_Timer.After(0.05, function()
				EnsureModelLoaded(1)
			end)
		end
		return rt.lastStatus
	end

	function E:SetOnChanged(callback)
		E._emitChanged = callback
	end

	function E:GetSensitivity()
		return worldOffsetScale, verticalScale
	end

	function E:SetSensitivity(nextWorldOffsetScale, nextVerticalScale)
		local changed = false
		local w = Clamp(tonumber(nextWorldOffsetScale) or worldOffsetScale, 0.001, 0.05)
		local z = Clamp(tonumber(nextVerticalScale) or verticalScale, 0.01, 2.0)
		if math.abs(w - worldOffsetScale) > 1e-6 then
			worldOffsetScale = w
			changed = true
		end
		if math.abs(z - verticalScale) > 1e-6 then
			verticalScale = z
			changed = true
		end
		if changed then
			E:RenderAll(true)
			EmitChanged("sensitivity")
		end
		return worldOffsetScale, verticalScale
	end

	function E:GetRotationMode()
		return rotationMode
	end

	function E:SetRotationMode(mode)
		local m = tostring(mode or ""):lower()
		if m ~= "screen" and m ~= "legacy" then
			return false, "invalid_mode"
		end
		if m == rotationMode then
			return true
		end
		rotationMode = m
		E:RenderAll(true)
		EmitChanged("rotation_mode")
		return true
	end

	function E:GetColorTemperature()
		return colorTemperature
	end

	function E:SetColorTemperature(value)
		local nextValue = Clamp(tonumber(value) or 0, -1, 1)
		if math.abs(nextValue - colorTemperature) <= 1e-6 then
			return true
		end
		colorTemperature = nextValue
		PersistAmbientLightingToMap()
		ReapplyLightingToAll()
		EmitChanged("color_temperature")
		return true
	end

	function E:GetGlobalLighting()
		return lightColorR, lightColorG, lightColorB, lightLuminance
	end

	function E:SetGlobalLighting(r, g, b, luminance)
		local nr = Clamp(tonumber(r) or lightColorR, 0, 2)
		local ng = Clamp(tonumber(g) or lightColorG, 0, 2)
		local nb = Clamp(tonumber(b) or lightColorB, 0, 2)
		local nl = Clamp(tonumber(luminance) or lightLuminance, 0, 3)
		if
			math.abs(nr - lightColorR) <= 1e-6
			and math.abs(ng - lightColorG) <= 1e-6
			and math.abs(nb - lightColorB) <= 1e-6
			and math.abs(nl - lightLuminance) <= 1e-6
		then
			return true
		end
		lightColorR, lightColorG, lightColorB, lightLuminance = nr, ng, nb, nl
		PersistAmbientLightingToMap()
		ReapplyLightingToAll()
		EmitChanged("global_lighting")
		return true
	end

	function E:GetRuntimeLightingOverride()
		return CopyObject(runtimeLightingOverride)
	end

	function E:SetRuntimeLightingOverride(profileOrNil)
		local normalized = NormalizeRuntimeLightingOverride(profileOrNil)
		if not normalized and not runtimeLightingOverride then
			return true
		end
		if normalized and runtimeLightingOverride and IsRuntimeLightingOverrideEqual(normalized, runtimeLightingOverride) then
			return true
		end
		if normalized then
			runtimeLightingOverride = normalized
		else
			runtimeLightingOverride = nil
		end
		ReapplyLightingToAll()
		E:RenderAll(true)
		EmitChanged("runtime_lighting_override")
		return true
	end

	function E:ClearRuntimeLightingOverride()
		if not runtimeLightingOverride then
			return true
		end
		runtimeLightingOverride = nil
		ReapplyLightingToAll()
		E:RenderAll(true)
		EmitChanged("runtime_lighting_override")
		return true
	end

	function E:GetMapId()
		return tostring(E.mapId or "default")
	end

	function E:GetHoveredLieuId()
		return E.hoveredLieuId
	end

	function E:SetHoveredLieuId(lieuIdOrNil)
		local nextId = tostring(lieuIdOrNil or "")
		if nextId == "" then
			nextId = nil
		end
		if E.hoveredLieuId == nextId then
			return true
		end
		E.hoveredLieuId = nextId
		E:RenderAll(true)
		return true
	end

	function E:GetHoverLightMultiplier()
		local settings = GetHoverSettingsRef()
		if settings then
			E.hoverLightMultiplier =
				Clamp(tonumber(settings.lightMultiplier) or E.hoverLightMultiplier or 1.6, 1.0, 3.0)
		end
		return E.hoverLightMultiplier
	end

	function E:SetHoverLightMultiplier(value)
		local settings = GetHoverSettingsRef()
		local mapSettings = GetMapSettingsRef()
		local nextValue = Clamp(tonumber(value) or E.hoverLightMultiplier or 1.6, 1.0, 3.0)
		E.hoverLightMultiplier = nextValue
		if settings then
			settings.lightMultiplier = nextValue
		end
		mapSettings.hoverLightMultiplier = nextValue
		for _, rt in pairs(E.hoverRuntimes) do
			ApplyRuntimeLighting(rt, E.hoverLightMultiplier)
		end
		E:RenderAll(true)
		EmitChanged("hover_light_multiplier")
		return true
	end

	function E:GetHoverLinks()
		local links = GetHoverLinksRef()
		local out = {}
		for i = 1, #links do
			out[#out + 1] = CopyObject(links[i])
		end
		return out
	end

	function E:CreateHoverLink(payload)
		if not (QM.HoverObjects and QM.HoverObjects.NormalizeLink) then
			return false, "hover_store_unavailable"
		end
		local links = GetHoverLinksRef()
		local createPayload = CopyObject(type(payload) == "table" and payload or {}) or {}
		createPayload.id = tostring(createPayload.id or "")
		local normalized = QM.HoverObjects.NormalizeLink(createPayload)
		if not normalized then
			return false, "invalid_link"
		end
		normalized.id = (normalized.id ~= "") and normalized.id or NextHoverLinkId(links)
		links[#links + 1] = normalized
		E:RenderAll(true)
		EmitChanged("hover_link_create")
		return true, normalized.id
	end

	function E:UpdateHoverLink(id, patch)
		if not (QM.HoverObjects and QM.HoverObjects.NormalizeLink) then
			return false, "hover_store_unavailable"
		end
		local link, index = FindHoverLinkById(id)
		if not (link and index) then
			return false, "not_found"
		end
		local merged = CopyObject(link)
		for k, v in pairs(type(patch) == "table" and patch or {}) do
			merged[k] = v
		end
		merged.id = tostring(link.id or "")
		local normalized = QM.HoverObjects.NormalizeLink(merged)
		if not normalized then
			return false, "invalid_patch"
		end
		normalized.id = tostring(link.id or "")
		local links = GetHoverLinksRef()
		links[index] = normalized
		E:RenderAll(true)
		EmitChanged("hover_link_update")
		return true
	end

	function E:DeleteHoverLink(id)
		local _, index = FindHoverLinkById(id)
		if not index then
			return false, "not_found"
		end
		local links = GetHoverLinksRef()
		table.remove(links, index)
		E:RenderAll(true)
		EmitChanged("hover_link_delete")
		return true
	end

	function E:SetMapId(mapId)
		E.mapId = tostring(mapId or "default")
		E.selectedId = nil
		E.hoveredLieuId = nil
		RepairLegacyDuplicateFrameOffset()
		ApplyAmbientLightingFromMap()
		ReapplyLightingToAll()
		local settings = GetHoverSettingsRef()
		if settings then
			E.hoverLightMultiplier =
				Clamp(tonumber(settings.lightMultiplier) or E.hoverLightMultiplier or 1.6, 1.0, 3.0)
		end
		E:RenderAll(true)
		EmitChanged("map")
	end

	function E:GetSelectedId()
		return E.selectedId
	end

	function E:GetRenderStatus(id)
		return E.statusById[tostring(id or "")] or "unknown"
	end

	function E:GetObjects()
		local src = GetObjectsRef()
		local out = {}
		for i = 1, #src do
			out[#out + 1] = CopyObject(src[i])
		end
		return out
	end

	function E:ExportText()
		if QM.Objects and QM.Objects.BuildExportText then
			return QM.Objects.BuildExportText(E.mapId)
		end
		return ""
	end

	function E:ExportHoverText()
		if QM.HoverObjects and QM.HoverObjects.BuildExportText then
			return QM.HoverObjects.BuildExportText(E.mapId)
		end
		return ""
	end

	function E:SelectObject(id)
		id = tostring(id or "")
		if id == "" then
			E.selectedId = nil
		else
			E.selectedId = id
		end
			local activeLinkId = tostring(E.hoveredLieuId or "")
			local objs = GetObjectsRef()
		local byId = {}
		for i = 1, #objs do
			local o = objs[i]
			local oid = tostring(o and o.id or "")
			if oid ~= "" then
				byId[oid] = o
			end
		end
			for objId, rt in pairs(E.runtimes) do
				local isSelected = (objId == E.selectedId)
				SetRuntimeSelected(rt, isSelected)
				local obj = byId[objId]
				local objLinkId = tostring(obj and obj.hoverLinkId or "")
				local objectExposure = Clamp(tonumber(obj and obj.objectExposure) or 1.0, 0.1, 5.0)
				local targetLightMultiplier = objectExposure
				if activeLinkId ~= "" and objLinkId == activeLinkId then
					targetLightMultiplier = math.max(targetLightMultiplier, tonumber(E.hoverLightMultiplier) or 1.0)
				end
				if isSelected then
					targetLightMultiplier = math.max(targetLightMultiplier, tonumber(E.selectedLightMultiplier) or 3.0)
				end
				rt._lightMultiplier = targetLightMultiplier
				ApplyRuntimeLighting(rt, targetLightMultiplier, obj)
			end
		E:RenderAll(true)
		EmitChanged("selection")
		return true
	end

	function E:BeginAltDrag(px, py)
		local id = tostring(E.selectedId or "")
		if id == "" then
			return false, "missing_selection"
		end
		local obj = FindObjectById(id)
		if not obj then
			return false, "not_found"
		end
		E.dragState = {
			id = id,
			startPx = tonumber(px) or 0,
			startPy = tonumber(py) or 0,
			startX = tonumber(obj.x) or 0,
			startY = tonumber(obj.y) or 0,
			startZ = tonumber(obj.z) or 0,
		}
		return true
	end

	function E:UpdateAltDrag(px, py)
		local drag = E.dragState
		if not drag then
			return false, "missing_drag"
		end
		local dx = (tonumber(px) or 0) - (tonumber(drag.startPx) or 0)
		local dy = (tonumber(py) or 0) - (tonumber(drag.startPy) or 0)
		local minZoom = tonumber(state and state.minZoom) or 1
		if minZoom <= 0 then
			minZoom = 1
		end
		local zoom = tonumber(state and state.zoom) or minZoom
		local zoomFactor = math.max(0.01, zoom / minZoom)
		-- 1:1 base ratio, then finer control when zoomed in.
		local dragUnits = mouseDragUnitsPerPixel / zoomFactor
		-- Horizontal sensitivity (left/right -> Z) tuned lower for finer control.
		local dragUnitsHorizontal = dragUnits * 0.25
		-- Requested mapping:
		-- Haut = -Y, Bas = +Y, Gauche = -Z, Droite = +Z.
		local nextY = (tonumber(drag.startY) or 0) - (dy * dragUnits)
		local nextZ = (tonumber(drag.startZ) or 0) + (dx * dragUnitsHorizontal)
		return E:UpdateObject(drag.id, {
			x = tonumber(drag.startX) or 0,
			y = nextY,
			z = nextZ,
		})
	end

	function E:EndAltDrag()
		E.dragState = nil
		return true
	end

	function E:AdjustSelectedScaleFromWheel(delta)
		local id = tostring(E.selectedId or "")
		if id == "" then
			return false, "missing_selection"
		end
		local obj = FindObjectById(id)
		if not obj then
			return false, "not_found"
		end
		local current = tonumber(obj.scale) or 1
		local wheel = tonumber(delta) or 0
		if wheel == 0 then
			return true
		end
		local factor = mouseScaleStep ^ math.abs(wheel)
		local nextScale = (wheel > 0) and (current * factor) or (current / factor)
		return E:UpdateObject(id, { scale = nextScale })
	end

	function E:CreateObject(payload)
		local createPayload = CopyObject(type(payload) == "table" and payload or {}) or {}
		if createPayload.u == nil or createPayload.v == nil then
			local u1 = tonumber(state.u1) or 0
			local v1 = tonumber(state.v1) or 0
			local uSpan = tonumber(state.uSpan) or 1
			local vSpan = tonumber(state.vSpan) or 1
			createPayload.u = Clamp(u1 + (uSpan * 0.5), 0, 1)
			createPayload.v = Clamp(v1 + (vSpan * 0.5), 0, 1)
		end
		local obj = QM.Objects.NormalizeObject(createPayload)
		if not obj then
			return false, "invalid_model"
		end
		local objs = GetObjectsRef()
		obj.id = obj.id ~= "" and obj.id or NextObjectId(objs)
		objs[#objs + 1] = obj
		E.selectedId = obj.id
		E:RenderAll(true)
		EmitChanged("create")
		return true, obj.id
	end

	function E:UpdateObject(id, patch)
		id = tostring(id or "")
		if id == "" then
			return false, "missing_id"
		end
		local objs = GetObjectsRef()
		for i = 1, #objs do
			if tostring(objs[i].id or "") == id then
				local merged = CopyObject(objs[i])
				for k, v in pairs(type(patch) == "table" and patch or {}) do
					merged[k] = v
				end
				merged.id = id
				local normalized = QM.Objects.NormalizeObject(merged)
				if not normalized then
					return false, "invalid_patch"
				end
				normalized.id = id
				objs[i] = normalized
				E:RenderAll(true)
				EmitChanged("update")
				return true
			end
		end
		return false, "not_found"
	end

	function E:DeleteObject(id)
		id = tostring(id or "")
		if id == "" then
			return false, "missing_id"
		end
		local objs = GetObjectsRef()
		for i = 1, #objs do
			if tostring(objs[i].id or "") == id then
				table.remove(objs, i)
				if E.selectedId == id then
					E.selectedId = nil
				end
				E:RenderAll(true)
				EmitChanged("delete")
				return true
			end
		end
		return false, "not_found"
	end

	function E:DuplicateObject(id)
		id = tostring(id or "")
		if id == "" then
			return false, "missing_id"
		end
		local objs = GetObjectsRef()
		for i = 1, #objs do
			if tostring(objs[i].id or "") == id then
				local sourceObj = objs[i]
				local copy = CopyObject(sourceObj)
				local su, sv = ResolveWorldUV(sourceObj)
				copy.u = su
				copy.v = sv
				copy.id = ""
				if QM.Objects and QM.Objects.NormalizeObject then
					local normalized = QM.Objects.NormalizeObject(copy)
					if not normalized then
						return false, "invalid_duplicate"
					end
					copy = normalized
				end
				copy.id = NextObjectId(objs)
				objs[#objs + 1] = copy
				E.selectedId = copy.id
				E:RenderAll(true)
				EmitChanged("duplicate")
				return true, copy.id
			end
		end
		return false, "not_found"
	end

	function E:MoveObject(id, delta)
		id = tostring(id or "")
		local step = math.floor(tonumber(delta) or 0)
		if id == "" then
			return false, "missing_id"
		end
		if step == 0 then
			return true
		end
		local objs = GetObjectsRef()
		local from = nil
		for i = 1, #objs do
			if tostring(objs[i] and objs[i].id or "") == id then
				from = i
				break
			end
		end
		if not from then
			return false, "not_found"
		end
		local to = Clamp(from + step, 1, #objs)
		if to == from then
			return true
		end
		local row = objs[from]
		table.remove(objs, from)
		table.insert(objs, to, row)
		E:RenderAll(true)
		EmitChanged("reorder")
		return true
	end

	function E:MoveObjectUp(id)
		return E:MoveObject(id, -1)
	end

	function E:MoveObjectDown(id)
		return E:MoveObject(id, 1)
	end

	function E:FindNearestObjectIdAtPoint(px, py, radiusPx)
		local objs = GetObjectsRef()
		local bestId, bestD2 = nil, nil
		local baseRadius2 = (tonumber(radiusPx) or 26) ^ 2
		for i = 1, #objs do
			local obj = objs[i]
			if obj.enabled ~= false then
				local wu, wv = ResolveWorldUV(obj)
				local x, y = WorldToScreen(wu, wv)
				if x and y then
					local rtRadius = math.max(8, ((tonumber(obj.size) or 96) * (tonumber(obj.scale) or 1)) * 0.5)
					local hitR2 = math.max(baseRadius2, rtRadius * rtRadius)
					local dx = (tonumber(px) or 0) - x
					local dy = (tonumber(py) or 0) - y
					local d2 = (dx * dx) + (dy * dy)
					if d2 <= hitR2 and ((not bestD2) or d2 < bestD2) then
						bestId = tostring(obj.id or "")
						bestD2 = d2
					end
				end
			end
		end
		return bestId
	end

	function E:RenderAll(force)
		local now = GetTime and GetTime() or 0
		local effectiveInterval = updateInterval
		if not force and effectiveInterval > 0 and now > 0 and (now - (E._lastRenderAt or 0)) < effectiveInterval then
			return
		end
		E._lastRenderAt = now
		local hoverSettings = GetHoverSettingsRef()
		if hoverSettings then
			E.hoverLightMultiplier =
				Clamp(tonumber(hoverSettings.lightMultiplier) or E.hoverLightMultiplier or 1.6, 1.0, 3.0)
		end
		local objs = GetObjectsRef()
		if #objs == 0 then
			objectLayer:Hide()
			hoverLayer:Hide()
			ReleaseMissingRuntime(E.runtimes, E.statusById, {})
			ReleaseMissingRuntime(E.hoverRuntimes, E.hoverStatusById, {})
			return
		end
		objectLayer:Show()
		local keep = {}
		local activeLinkId = tostring(E.hoveredLieuId or "")
		local total = #objs
		for i = 1, #objs do
			local obj = objs[i]
			local id = tostring(obj and obj.id or "")
			if id ~= "" then
				keep[id] = true
				local rt = AcquireRuntime(E.runtimes, id, objectLayer, true)
				local size = math.max(1, (tonumber(obj.size) or 96) * (tonumber(obj.scale) or 1))
				local wu, wv = ResolveWorldUV(obj)
				local x, y = WorldToScreen(wu, wv)
				if x and y and obj.enabled ~= false then
					LayoutRuntime(rt, x, y, objectLayer)
					local level = objectLayer:GetFrameLevel() + 2
					if rt._baseLevel ~= level then
						rt._baseLevel = level
						rt.holder:SetFrameLevel(level)
						if rt.playerModel then
							rt.playerModel:SetFrameLevel(level + 1)
						end
						if rt.genericModel then
							rt.genericModel:SetFrameLevel(level + 1)
						end
					end
					rt.holder:Show()
				else
					rt.holder:Hide()
				end

				local poseKey = BuildPoseKey(obj)
				if rt.poseKey ~= poseKey then
					E.statusById[id] = ApplyModelSource(rt, obj)
					ApplyRuntimePose(rt, obj)
					rt.poseKey = poseKey
				else
					E.statusById[id] = rt.lastStatus or E.statusById[id] or "unknown"
					if x and y and obj.enabled ~= false then
						-- Re-apply pose on visible objects to catch async model readiness
						-- (notably for non-default scales on first window open).
						ApplyRuntimePose(rt, obj)
					end
				end

					local objLinkId = tostring(obj and obj.hoverLinkId or "")
					local objectExposure = Clamp(tonumber(obj and obj.objectExposure) or 1.0, 0.1, 5.0)
					local objectColorR = Clamp(tonumber(obj and obj.objectColorR) or 1.0, 0.0, 2.0)
					local objectColorG = Clamp(tonumber(obj and obj.objectColorG) or 1.0, 0.0, 2.0)
					local objectColorB = Clamp(tonumber(obj and obj.objectColorB) or 1.0, 0.0, 2.0)
					local isSelected = (id == E.selectedId)
					local targetLightMultiplier = objectExposure
					if activeLinkId ~= "" and objLinkId == activeLinkId then
						targetLightMultiplier = math.max(targetLightMultiplier, tonumber(E.hoverLightMultiplier) or 1.0)
					end
					if isSelected then
						targetLightMultiplier = math.max(targetLightMultiplier, tonumber(E.selectedLightMultiplier) or 3.0)
					end
					local lightingKey = table.concat({
						string.format("%.4f", targetLightMultiplier),
						string.format("%.4f", objectColorR),
						string.format("%.4f", objectColorG),
						string.format("%.4f", objectColorB),
					}, "|")
					if rt._lightingKey ~= lightingKey then
						rt._lightingKey = lightingKey
						rt._lightMultiplier = targetLightMultiplier
						ApplyRuntimeLighting(rt, targetLightMultiplier, obj)
					end

					SetRuntimeSelected(rt, isSelected)
				if rt.selection then
					local loaded = E.statusById[id] == "loaded"
					if rt._selected and loaded and x and y and obj.enabled ~= false then
						local ring = math.max(14, size * 0.22)
						rt.selection:ClearAllPoints()
						rt.selection:SetPoint("CENTER", objectLayer, "BOTTOMLEFT", x, y)
						rt.selection:SetSize(ring, ring)
						rt.selection:Show()
					else
						rt.selection:Hide()
					end
				end
			end
		end
		local shouldRestack = true
		if shouldRestack then
			E._lastStackAt = now
			-- Force visual stacking order deterministically:
			-- first item in list must be on top (raised last).
			for i = total, 1, -1 do
				local id = tostring(objs[i] and objs[i].id or "")
				local rt = (id ~= "") and E.runtimes[id] or nil
				if rt and rt.holder and rt.holder:IsShown() and rt.holder.Raise then
					rt.holder:Raise()
				end
			end
		end

		local disableHoverClone = true
		local keepHover = {}
		if (not disableHoverClone) and activeLinkId ~= "" then
			for i = 1, #objs do
				local sourceObj = objs[i]
				local sourceId = tostring(sourceObj and sourceObj.id or "")
				local objLinkId = tostring(sourceObj and sourceObj.hoverLinkId or "")
				if sourceId ~= "" and objLinkId ~= "" and objLinkId == activeLinkId and sourceObj.enabled ~= false then
					local runtimeId = "hover:obj:" .. sourceId
					keepHover[runtimeId] = true
					local rt = AcquireRuntime(E.hoverRuntimes, runtimeId, hoverLayer, false)
					local baseRt = E.runtimes[sourceId]
					local preferredRenderer = baseRt and baseRt._activeRendererKind or nil
					rt._preferredRenderer = preferredRenderer
					if preferredRenderer and rt._activeRendererKind and rt._activeRendererKind ~= preferredRenderer then
						-- Keep hover strictly aligned with base object backend.
						rt.sourceKey = nil
						rt.poseKey = nil
					end
					rt._lightMultiplier = E.hoverLightMultiplier
					local wu, wv = ResolveWorldUV(sourceObj)
					local x, y = WorldToScreen(wu, wv)
					if x and y then
						LayoutRuntime(rt, x, y, hoverLayer)
						local level = hoverLayer:GetFrameLevel() + 2
						if rt._baseLevel ~= level then
							rt._baseLevel = level
							rt.holder:SetFrameLevel(level)
							if rt.playerModel then
								rt.playerModel:SetFrameLevel(level + 1)
							end
							if rt.genericModel then
								rt.genericModel:SetFrameLevel(level + 1)
							end
						end
						rt.holder:Show()
					else
						rt.holder:Hide()
					end

					local poseKey = BuildPoseKey(sourceObj)
						.. "|hoverlink:"
						.. objLinkId
						.. "|"
						.. string.format("%.4f", tonumber(E.hoverLightMultiplier) or 1.6)
					if rt.poseKey ~= poseKey then
						E.hoverStatusById[runtimeId] = ApplyModelSource(rt, sourceObj)
						ApplyRuntimePose(rt, sourceObj)
						ApplyRuntimeLighting(rt, E.hoverLightMultiplier)
						rt.poseKey = poseKey
					else
						E.hoverStatusById[runtimeId] = rt.lastStatus or E.hoverStatusById[runtimeId] or "unknown"
						if x and y then
							ApplyRuntimePose(rt, sourceObj)
							ApplyRuntimeLighting(rt, E.hoverLightMultiplier)
						end
					end
				end
			end
		end
		if (not disableHoverClone) and next(keepHover) then
			hoverLayer:Show()
			for i = total, 1, -1 do
				local sourceObj = objs[i]
				local sourceId = tostring(sourceObj and sourceObj.id or "")
				local objLinkId = tostring(sourceObj and sourceObj.hoverLinkId or "")
				if sourceId ~= "" and objLinkId ~= "" and objLinkId == activeLinkId then
					local runtimeId = "hover:obj:" .. sourceId
					local rt = E.hoverRuntimes[runtimeId]
					if rt and rt.holder and rt.holder:IsShown() and rt.holder.Raise then
						rt.holder:Raise()
					end
				end
			end
		else
			hoverLayer:Hide()
		end

		ReleaseMissingRuntime(E.runtimes, E.statusById, keep)
		ReleaseMissingRuntime(E.hoverRuntimes, E.hoverStatusById, keepHover)
	end

	local _initialHoverSettings = GetHoverSettingsRef()
	if _initialHoverSettings then
		E.hoverLightMultiplier =
			Clamp(tonumber(_initialHoverSettings.lightMultiplier) or E.hoverLightMultiplier or 1.6, 1.0, 3.0)
	end
	RepairLegacyDuplicateFrameOffset()
	ApplyAmbientLightingFromMap()
	E:RenderAll()
	return E
end
