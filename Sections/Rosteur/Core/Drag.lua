local ADDON, ns = ...

ns.RosteurSectionCoreDrag = ns.RosteurSectionCoreDrag or {}
local Drag = ns.RosteurSectionCoreDrag

function Drag.Build(env)
	local Utils = env and env.Utils or nil
	local ColorizeName = env and env.ColorizeName or function(name)
		return tostring(name or "-")
	end

	local dragState = { data = nil }
	local ROSTER_CLASS_VISUAL_SIZE = 45
	local dragVisual = nil

	local function GetClassRGBA(classTag)
		if classTag and RAID_CLASS_COLORS then
			local rec = RAID_CLASS_COLORS[classTag]
			if rec then
				return rec.r or 0.6, rec.g or 0.6, rec.b or 0.6, 0.95
			end
		end
		return 0.35, 0.35, 0.35, 0.95
	end

	local function GetShortDragName(data)
		local raw = data and (data.name or data.full) or "+"
		local nameOnly = tostring(raw or "+")
		if Utils and Utils.BaseName then
			nameOnly = Utils.BaseName(nameOnly) or nameOnly
		else
			local dash = string.find(nameOnly, "-", 1, true)
			if dash and dash > 1 then
				nameOnly = string.sub(nameOnly, 1, dash - 1)
			end
		end
		if string.len(nameOnly) > 20 then
			nameOnly = string.sub(nameOnly, 1, 20) .. "..."
		end
		return nameOnly
	end

	local function EnsureDragVisual()
		if dragVisual then
			return dragVisual
		end
		dragVisual = CreateFrame("Frame", "WoWGuilde_Rosteur_DragVisual", UIParent)
		dragVisual:SetSize(58, 58)
		dragVisual:SetFrameStrata("TOOLTIP")
		dragVisual:SetFrameLevel(200)
		dragVisual:Hide()

		local mask = dragVisual:CreateMaskTexture(nil, "BACKGROUND")
		mask:SetSize(ROSTER_CLASS_VISUAL_SIZE, ROSTER_CLASS_VISUAL_SIZE)
		mask:SetPoint("CENTER", dragVisual, "CENTER", 0, 0)
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		dragVisual._mask = mask

		local shadow = dragVisual:CreateTexture(nil, "BACKGROUND")
		shadow:SetPoint("TOPLEFT", dragVisual, "TOPLEFT", -14, 9)
		shadow:SetPoint("BOTTOMRIGHT", dragVisual, "BOTTOMRIGHT", 14, -12)
		shadow:SetAtlas("GarrFollower-Shadow", true)
		shadow:SetAlpha(0.95)
		dragVisual._shadow = shadow

		local classBg = dragVisual:CreateTexture(nil, "ARTWORK", nil, -1)
		classBg:SetSize(ROSTER_CLASS_VISUAL_SIZE, ROSTER_CLASS_VISUAL_SIZE)
		classBg:SetPoint("CENTER", dragVisual, "CENTER", 0, 0)
		classBg:SetColorTexture(0.35, 0.35, 0.35, 0.95)
		classBg:AddMaskTexture(mask)
		dragVisual._classBg = classBg

		local ring = dragVisual:CreateTexture(nil, "OVERLAY", nil, 6)
		ring:SetPoint("TOPLEFT", dragVisual, "TOPLEFT", 2, -2)
		ring:SetPoint("BOTTOMRIGHT", dragVisual, "BOTTOMRIGHT", -2, 2)
		ring:SetAtlas("Map_Faction_Ring", true)
		ring:SetVertexColor(1, 1, 1, 1)
		dragVisual._ring = ring

		local holder = dragVisual:CreateTexture(nil, "OVERLAY", nil, 7)
		holder:SetSize(65, 30)
		holder:SetPoint("BOTTOM", dragVisual, "BOTTOM", 0, -8)
		holder:SetAtlas("common-dropdown-textholder", false)
		holder:SetVertexColor(1, 0.847, 0.196, 1)
		dragVisual._holder = holder

		local label = dragVisual:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("CENTER", holder, "CENTER", 0, 0)
		label:SetWidth(58)
		label:SetJustifyH("CENTER")
		label:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
		dragVisual._label = label

		return dragVisual
	end

	local function UpdateDragVisualPosition()
		local v = dragVisual
		if not (v and v:IsShown()) then
			return
		end
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		v:ClearAllPoints()
		v:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	end

	local function ShowDragVisual(data)
		local v = EnsureDragVisual()
		local classTag = data and data.classTag or nil
		local classCoords = classTag and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classTag] or nil
		if classTag and classCoords then
			v._classBg:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
			v._classBg:SetTexCoord(classCoords[1], classCoords[2], classCoords[3], classCoords[4])
			v._classBg:SetVertexColor(1, 1, 1, 1)
		else
			local r, g, b, a = GetClassRGBA(classTag)
			v._classBg:SetColorTexture(r, g, b, a)
			v._classBg:SetTexCoord(0, 1, 0, 1)
		end
		v._ring:SetDesaturated(false)
		v._ring:SetVertexColor(1, 1, 1, 1)
		v._holder:SetVertexColor(1, 0.718, 0.125, 1)
		local shortName = GetShortDragName(data)
		v._label:SetText(ColorizeName(shortName, classTag))
		v:Show()
		v:SetScript("OnUpdate", UpdateDragVisualPosition)
		UpdateDragVisualPosition()
	end

	local function HideDragVisual()
		if dragVisual then
			dragVisual:SetScript("OnUpdate", nil)
			dragVisual:Hide()
		end
	end

	local function StartDrag(data)
		dragState.data = data
		ShowDragVisual(data)
	end

	local function StopDrag()
		dragState.data = nil
		HideDragVisual()
	end

	local function StopDragDeferred()
		if C_Timer and C_Timer.After then
			C_Timer.After(0, StopDrag)
		else
			StopDrag()
		end
	end

	local function GetDrag()
		return dragState.data
	end

	return {
		StartDrag = StartDrag,
		StopDrag = StopDrag,
		StopDragDeferred = StopDragDeferred,
		GetDrag = GetDrag,
		GetShortDragName = GetShortDragName,
		ROSTER_CLASS_VISUAL_SIZE = ROSTER_CLASS_VISUAL_SIZE,
	}
end
