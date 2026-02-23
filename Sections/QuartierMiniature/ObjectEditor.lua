local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.ObjectEditor = QM.ObjectEditor or {}
local ObjectEditor = QM.ObjectEditor

local sliderSeq = 0
local function NextSliderName()
	sliderSeq = sliderSeq + 1
	return "WoWGuilde_QMObjectSlider_" .. tostring(sliderSeq)
end

local function Clamp(v, minV, maxV)
	if v < minV then
		return minV
	end
	if v > maxV then
		return maxV
	end
	return v
end

local function CreateSlider(parent, x, y, width, label, minV, maxV, step)
	local slider = CreateFrame("Slider", NextSliderName(), parent, "OptionsSliderTemplate")
	slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	slider:SetWidth(width)
	slider:SetMinMaxValues(minV, maxV)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	_G[slider:GetName() .. "Low"]:SetText(tostring(minV))
	_G[slider:GetName() .. "High"]:SetText(tostring(maxV))
	_G[slider:GetName() .. "Text"]:SetText(label)
	return slider
end

local function EnableShiftWheelNudge(slider, shiftStepOverride)
	if not slider then
		return
	end
	slider:EnableMouseWheel(true)
	slider:HookScript("OnMouseWheel", function(self, delta)
		if not (IsShiftKeyDown and IsShiftKeyDown()) then
			return
		end
		local cur = tonumber(self:GetValue()) or 0
		local minV, maxV = self:GetMinMaxValues()
		local step = tonumber(shiftStepOverride) or tonumber(self:GetValueStep()) or 1
		if step <= 0 then
			step = 1
		end
		local nextValue = cur + ((tonumber(delta) or 0) * step)
		if minV and nextValue < minV then
			nextValue = minV
		end
		if maxV and nextValue > maxV then
			nextValue = maxV
		end
		self:SetValue(nextValue)
	end)
end

local function CreateSubSection(parent, titleText, width, height)
	local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	frame:SetSize(width, height)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	frame:SetBackdropColor(0.02, 0.02, 0.02, 0.45)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
	title:SetText(tostring(titleText or ""))
	frame._title = title

	return frame
end

function ObjectEditor.Attach(opts)
	if type(opts) ~= "table" then
		return nil
	end
	local parent = opts.parent
	local hudLayer = opts.hudLayer or parent
	local scene = opts.scene
	if not (parent and hudLayer and scene) then
		return nil
	end

	local E = {
		kind = "m2",
		rows = {},
		updating = false,
		listOffset = 0,
		catalogPath = {},
		catalogOffset = 0,
		catalogChoice = nil,
		catalogSearchQuery = "",
		currentTab = "models",
	}
	local catalog = QM.ObjectCatalog

	function E:IsDevMode()
		if type(opts.isDevMode) == "function" then
			local ok, value = pcall(opts.isDevMode)
			return ok and value == true
		end
		return false
	end

	local panel = CreateFrame("Frame", "WoWGuilde_QMObjectEditor", hudLayer, "BackdropTemplate")
	panel:SetSize(430, 700)
	panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -22, -46)
	panel:SetFrameStrata(parent:GetFrameStrata())
	panel:SetFrameLevel((hudLayer:GetFrameLevel() or parent:GetFrameLevel() or 1) + 26)
	panel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0.02, 0.02, 0.02, 0.92)
	panel:Hide()
	panel:SetScript("OnShow", function(self)
		if not E:IsDevMode() then
			self:Hide()
		end
	end)
	E.panel = panel

	local titleBar = CreateFrame("Frame", nil, panel)
	titleBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
	titleBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
	titleBar:SetHeight(18)
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnDragStart", function()
		panel:StartMoving()
	end)
	titleBar:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
	end)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
	title:SetText("Objets 3D - Quartier Miniature")

	local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 2, 2)
	closeBtn:SetScript("OnClick", function()
		panel:Hide()
	end)

	local tabModelsBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	tabModelsBtn:SetSize(96, 20)
	tabModelsBtn:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -8)
	tabModelsBtn:SetText("Modeles")

		local tabColorBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		tabColorBtn:SetSize(148, 20)
		tabColorBtn:SetPoint("LEFT", tabModelsBtn, "RIGHT", 6, 0)
		tabColorBtn:SetText("Colorimetrie ambiante")

		local tabTimeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		tabTimeBtn:SetSize(84, 20)
		tabTimeBtn:SetPoint("LEFT", tabColorBtn, "RIGHT", 6, 0)
		tabTimeBtn:SetText("Temps")

	local toggleBtn = CreateFrame("Button", nil, hudLayer, "UIPanelButtonTemplate")
	toggleBtn:SetSize(96, 22)
	toggleBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -24, -20)
	toggleBtn:SetText("Objets 3D")
	toggleBtn:SetFrameStrata(parent:GetFrameStrata())
	toggleBtn:SetFrameLevel((hudLayer:GetFrameLevel() or parent:GetFrameLevel() or 1) + 30)
	toggleBtn:SetScript("OnClick", function()
		if not E:IsDevMode() then
			panel:Hide()
			return
		end
		if panel:IsShown() then
			panel:Hide()
		else
			panel:Show()
			E:Refresh()
		end
	end)
	E.toggleBtn = toggleBtn

	local sourceSection = CreateSubSection(panel, "Source Modele", 410, 122)
	sourceSection:SetPoint("TOPLEFT", tabModelsBtn, "BOTTOMLEFT", -4, -12)

	local listSection = CreateSubSection(panel, "Liste des modeles 3D", 410, 244)
	listSection:SetPoint("TOPLEFT", sourceSection, "BOTTOMLEFT", 0, -10)

	local linkSection = CreateSubSection(panel, "Liaison survol", 410, 94)
	linkSection:SetPoint("TOPLEFT", listSection, "BOTTOMLEFT", 0, -10)

	local modelControlsSection = CreateSubSection(panel, "Positionement / Rotation / Export", 410, 580)
	modelControlsSection:SetPoint("TOPLEFT", linkSection, "BOTTOMLEFT", 0, -10)

		local colorSection = CreateSubSection(panel, "Colorimetrie Ambiante", 410, 308)
		colorSection:SetPoint("TOPLEFT", tabModelsBtn, "BOTTOMLEFT", -4, -12)

		local timeSection = CreateSubSection(panel, "Cycle Temporel", 410, 620)
		timeSection:SetPoint("TOPLEFT", tabModelsBtn, "BOTTOMLEFT", -4, -12)

	local modelInput = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	modelInput:SetSize(220, 22)
	modelInput:SetPoint("TOPLEFT", sourceSection, "TOPLEFT", 8, -28)
	modelInput:SetAutoFocus(false)
	modelInput:SetTextInsets(6, 6, 0, 0)
	modelInput:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	modelInput:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	E.modelInput = modelInput

	local modelLabel = sourceSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	modelLabel:SetPoint("BOTTOMLEFT", modelInput, "TOPLEFT", 0, 2)
	modelLabel:SetText("Model (fileID ou path)")

	local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	addBtn:SetSize(84, 22)
	addBtn:SetPoint("TOPLEFT", modelInput, "BOTTOMLEFT", 0, -6)
	addBtn:SetText("Ajouter")

	local browseBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	browseBtn:SetSize(84, 22)
	browseBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
	browseBtn:SetText("Catalogue")

	local replaceBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	replaceBtn:SetSize(104, 22)
	replaceBtn:SetPoint("LEFT", browseBtn, "RIGHT", 6, 0)
	replaceBtn:SetText("Remplacer objet")

	local status = sourceSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", 0, -4)
	status:SetJustifyH("LEFT")
	status:SetText("Pret")
	E.status = status

	local hint = sourceSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -2)
	hint:SetText("Astuce: sliders + champs numeriques pour un ajustement fin")

	local listFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	listFrame:SetPoint("TOPLEFT", listSection, "TOPLEFT", 8, -24)
	listFrame:SetSize(394, 158)
	listFrame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	listFrame:SetBackdropColor(0, 0, 0, 0.35)

	local listScroll = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 4, -4)
	listScroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -24, 4)

	local listContent = CreateFrame("Frame", nil, listScroll)
	listContent:SetSize(360, 1)
	listScroll:SetScrollChild(listContent)
	E.listContent = listContent

	local objectNameLabel = listSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	objectNameLabel:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -8)
	objectNameLabel:SetText("Nom objet (affiche dans la liste)")

	local objectNameInput = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	objectNameInput:SetSize(220, 20)
	objectNameInput:SetPoint("TOPLEFT", objectNameLabel, "BOTTOMLEFT", 0, -2)
	objectNameInput:SetAutoFocus(false)
	objectNameInput:SetTextInsets(4, 4, 0, 0)

	local hoverModelLabel = linkSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hoverModelLabel:SetPoint("TOPLEFT", linkSection, "TOPLEFT", 8, -28)
	hoverModelLabel:SetText("ID liaison")

	local hoverModelInput = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	hoverModelInput:SetSize(128, 20)
	hoverModelInput:SetPoint("TOPLEFT", hoverModelLabel, "BOTTOMLEFT", 0, -2)
	hoverModelInput:SetAutoFocus(false)
	hoverModelInput:SetTextInsets(4, 4, 0, 0)

	local hoverInfoText = linkSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hoverInfoText:SetPoint("LEFT", hoverModelLabel, "RIGHT", 138, 0)
	hoverInfoText:SetText("Objet/zone: -")
	hoverInfoText:SetJustifyH("LEFT")

	local hoverExportBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	hoverExportBtn:SetSize(120, 20)
	hoverExportBtn:SetPoint("TOPLEFT", hoverModelInput, "BOTTOMLEFT", 0, -10)
	hoverExportBtn:SetText("Export objets")

	local sliderAnchor = CreateFrame("Frame", nil, panel)
	sliderAnchor:SetPoint("TOPLEFT", modelControlsSection, "TOPLEFT", 8, -26)
	sliderAnchor:SetSize(394, 364)

	local sliderWidth = 308
	local sliderX = CreateSlider(sliderAnchor, 0, 0, sliderWidth, "X", -10000, 10000, 0.01)
	local sliderY = CreateSlider(sliderAnchor, 0, -44, sliderWidth, "Y", -10000, 10000, 0.01)
	local sliderZ = CreateSlider(sliderAnchor, 0, -88, sliderWidth, "Z", -2000, 2000, 0.01)
	local sliderYaw = CreateSlider(sliderAnchor, 0, -132, sliderWidth, "Yaw", 0, 360, 1)
	local sliderPitch = CreateSlider(sliderAnchor, 0, -176, sliderWidth, "Pitch", 0, 360, 1)
	local sliderRoll = CreateSlider(sliderAnchor, 0, -220, sliderWidth, "Roll", 0, 360, 1)
	local sliderScale = CreateSlider(sliderAnchor, 0, -264, sliderWidth, "Scale", 0.01, 1.0, 0.01)
	local sliderObjExposure = CreateSlider(sliderAnchor, 0, -308, sliderWidth, "Exposition objet", 0.1, 5.0, 0.01)
	local sliderObjR = CreateSlider(sliderAnchor, 0, -352, sliderWidth, "Obj R", 0, 200, 1)
	local sliderObjG = CreateSlider(sliderAnchor, 0, -396, sliderWidth, "Obj G", 0, 200, 1)
	local sliderObjB = CreateSlider(sliderAnchor, 0, -440, sliderWidth, "Obj B", 0, 200, 1)
	local sliderTemp = CreateSlider(sliderAnchor, 0, -308, sliderWidth, "Temperature", -100, 100, 1)
	local sliderLum = CreateSlider(sliderAnchor, 0, -352, sliderWidth, "Luminance", 0, 300, 1)
	local sliderR = CreateSlider(sliderAnchor, 0, -396, sliderWidth, "Light R", 0, 200, 1)
	local sliderG = CreateSlider(sliderAnchor, 0, -440, sliderWidth, "Light G", 0, 200, 1)
	local sliderB = CreateSlider(sliderAnchor, 0, -484, sliderWidth, "Light B", 0, 200, 1)
	local sliderHoverLum = CreateSlider(sliderAnchor, 0, -528, sliderWidth, "Luminosite Hover", 100, 300, 1)

	local sectionPositioning = modelControlsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	sectionPositioning:SetPoint("BOTTOMLEFT", sliderX, "TOPLEFT", 0, 6)
	sectionPositioning:SetText("Positionement")

	local sectionRotation = modelControlsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	sectionRotation:SetPoint("BOTTOMLEFT", sliderYaw, "TOPLEFT", 0, 6)
	sectionRotation:SetText("Rotation")

	local sectionObjectLighting = modelControlsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	sectionObjectLighting:SetPoint("BOTTOMLEFT", sliderObjExposure, "TOPLEFT", 0, 6)
	sectionObjectLighting:SetText("Colorimetrie objet")

	local sectionExport = modelControlsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	sectionExport:SetText("Export et controle")
	EnableShiftWheelNudge(sliderX, 1)
	EnableShiftWheelNudge(sliderY, 5)
	EnableShiftWheelNudge(sliderZ, 1)
	EnableShiftWheelNudge(sliderYaw, 1)
	EnableShiftWheelNudge(sliderPitch, 1)
	EnableShiftWheelNudge(sliderRoll, 1)
	EnableShiftWheelNudge(sliderScale, 0.01)
	EnableShiftWheelNudge(sliderObjExposure, 0.01)
	EnableShiftWheelNudge(sliderObjR, 1)
	EnableShiftWheelNudge(sliderObjG, 1)
	EnableShiftWheelNudge(sliderObjB, 1)
	EnableShiftWheelNudge(sliderTemp)
	EnableShiftWheelNudge(sliderLum)
	EnableShiftWheelNudge(sliderR)
	EnableShiftWheelNudge(sliderG)
	EnableShiftWheelNudge(sliderB)
	EnableShiftWheelNudge(sliderHoverLum)

		local sliderValueInputs = {}
		local modelTabWidgets = {}
		local colorTabWidgets = {}
		local timeTabWidgets = {}
	local modelSliders = {
		sliderX,
		sliderY,
		sliderZ,
		sliderYaw,
		sliderPitch,
		sliderRoll,
		sliderScale,
		sliderObjExposure,
		sliderObjR,
		sliderObjG,
		sliderObjB,
	}
	local colorSliders = { sliderTemp, sliderLum, sliderR, sliderG, sliderB, sliderHoverLum }

	local function AddWidgets(target, ...)
		for i = 1, select("#", ...) do
			local w = select(i, ...)
			if w then
				target[#target + 1] = w
			end
		end
	end

	local function ParseNumberInput(text)
		local cleaned = tostring(text or ""):gsub(",", "."):gsub("%s+", "")
		return tonumber(cleaned)
	end

	local function CreateValueBox(slider, minV, maxV, decimals, lockRange)
		local box = CreateFrame("EditBox", nil, sliderAnchor, "InputBoxTemplate")
		box:SetSize(82, 20)
		box:SetPoint("LEFT", slider, "RIGHT", 8, 0)
		box:SetAutoFocus(false)
		box:SetTextInsets(4, 4, 0, 0)
		box._slider = slider
		box._min = minV
		box._max = maxV
		box._decimals = decimals or 2
		box._lockRange = (lockRange == true)
		local formatStr = "%." .. tostring(box._decimals) .. "f"
		box._formatStr = formatStr

		local function CommitValue(self, clearFocus)
			if self._committing then
				return
			end
			self._committing = true
			local raw = ParseNumberInput(self:GetText())
			local nextValue = raw
			if not nextValue then
				nextValue = tonumber(self._slider:GetValue()) or 0
			end
				if self._lockRange then
					nextValue = Clamp(nextValue, self._min, self._max)
				else
					if nextValue < self._min then
						self._min = nextValue
					end
					if nextValue > self._max then
						self._max = nextValue
					end
					self._slider:SetMinMaxValues(self._min, self._max)
					local low = _G[self._slider:GetName() .. "Low"]
					local high = _G[self._slider:GetName() .. "High"]
					if low then
						low:SetText(string.format("%.2f", self._min))
					end
					if high then
						high:SetText(string.format("%.2f", self._max))
					end
				end
				self._slider:SetValue(nextValue)
			if clearFocus then
				self:ClearFocus()
			end
			if not self:HasFocus() then
				self:SetText(string.format(self._formatStr, nextValue))
			end
			self._committing = false
		end

		box:SetScript("OnEnterPressed", function(self)
			CommitValue(self, true)
		end)
		box:SetScript("OnEditFocusLost", function(self)
			CommitValue(self, false)
		end)
		box:SetScript("OnEscapePressed", function(self)
			local current = tonumber(self._slider:GetValue()) or 0
			self:SetText(string.format(self._formatStr, current))
			self:ClearFocus()
		end)

		sliderValueInputs[slider] = box
		return box
	end

	CreateValueBox(sliderX, -10000, 10000, 2)
	CreateValueBox(sliderY, -10000, 10000, 2)
	CreateValueBox(sliderZ, -2000, 2000, 2)
	CreateValueBox(sliderYaw, 0, 360, 1)
	CreateValueBox(sliderPitch, 0, 360, 1)
	CreateValueBox(sliderRoll, 0, 360, 1)
	CreateValueBox(sliderScale, 0.01, 1.0, 2, true)
	CreateValueBox(sliderObjExposure, 0.1, 5.0, 2, true)
	CreateValueBox(sliderObjR, 0, 200, 0, true)
	CreateValueBox(sliderObjG, 0, 200, 0, true)
	CreateValueBox(sliderObjB, 0, 200, 0, true)
	CreateValueBox(sliderTemp, -100, 100, 0)
	CreateValueBox(sliderLum, 0, 300, 0)
	CreateValueBox(sliderR, 0, 200, 0)
	CreateValueBox(sliderG, 0, 200, 0)
	CreateValueBox(sliderB, 0, 200, 0)
	CreateValueBox(sliderHoverLum, 100, 300, 0)

	local function SetSliderVisible(slider, visible)
		if not slider then
			return
		end
		local mode = visible and "Show" or "Hide"
		slider[mode](slider)
		local low = _G[slider:GetName() .. "Low"]
		local high = _G[slider:GetName() .. "High"]
		local text = _G[slider:GetName() .. "Text"]
		if low and low[mode] then
			low[mode](low)
		end
		if high and high[mode] then
			high[mode](high)
		end
		if text and text[mode] then
			text[mode](text)
		end
		local box = sliderValueInputs[slider]
		if box and box[mode] then
			box[mode](box)
		end
	end

	local function SetWidgetsVisible(widgets, visible)
		local mode = visible and "Show" or "Hide"
		for i = 1, #widgets do
			local w = widgets[i]
			if w and w[mode] then
				w[mode](w)
			end
		end
	end

	local exportBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	exportBtn:SetSize(88, 22)
	exportBtn:SetPoint("TOPLEFT", sliderObjB, "BOTTOMLEFT", 0, -22)
	exportBtn:SetText("Export")

	local deleteBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	deleteBtn:SetSize(88, 22)
	deleteBtn:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -6)
	deleteBtn:SetText("Supprimer")

	local dupBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	dupBtn:SetSize(88, 22)
	dupBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 6, 0)
	dupBtn:SetText("Dupliquer")

	sectionExport:SetPoint("BOTTOMLEFT", exportBtn, "TOPLEFT", 0, 6)

	AddWidgets(
		modelTabWidgets,
		sourceSection,
		listSection,
		linkSection,
		modelControlsSection,
		modelInput,
		modelLabel,
		addBtn,
		browseBtn,
		replaceBtn,
		status,
		hint,
		listFrame,
		listScroll,
		listContent,
		objectNameLabel,
		objectNameInput,
		hoverModelLabel,
		hoverModelInput,
		hoverInfoText,
			hoverExportBtn,
			sectionPositioning,
			sectionRotation,
			sectionObjectLighting,
			sectionExport,
			deleteBtn,
			dupBtn,
		exportBtn
	)
		AddWidgets(colorTabWidgets, colorSection)
		AddWidgets(timeTabWidgets, timeSection)

		local embeddedTimeEditor = nil
		if ns and ns.QuartierMiniature and ns.QuartierMiniature.TimeEditor and ns.QuartierMiniature.TimeEditor.Attach then
			embeddedTimeEditor = ns.QuartierMiniature.TimeEditor.Attach({
				embeddedParent = timeSection,
				parent = panel,
				hudLayer = hudLayer,
				getRuntime = function()
					if type(opts.getTimeRuntime) == "function" then
						return opts.getTimeRuntime()
					end
					return nil
				end,
				getMapId = function()
					if type(opts.getMapId) == "function" then
						return opts.getMapId()
					end
					return "default"
				end,
				isDevMode = function()
					return E:IsDevMode()
				end,
				onChanged = function(reason)
					if type(opts.onTimeChanged) == "function" then
						opts.onTimeChanged(reason)
					end
				end,
			})
		end

		local function RefreshTabVisibility()
			local isColorTab = E.currentTab == "color"
			local isTimeTab = E.currentTab == "time"

			if not isTimeTab then
				sliderAnchor:ClearAllPoints()
				if isColorTab then
					sliderAnchor:SetPoint("TOPLEFT", colorSection, "TOPLEFT", 8, -28)
				else
					sliderAnchor:SetPoint("TOPLEFT", modelControlsSection, "TOPLEFT", 8, -26)
				end
			else
				sliderAnchor:SetPoint("TOPLEFT", modelControlsSection, "TOPLEFT", 8, -26)
			end

		-- Re-layout sliders per tab so spacing remains compact and consistent.
		sliderX:ClearAllPoints()
		sliderY:ClearAllPoints()
		sliderZ:ClearAllPoints()
		sliderYaw:ClearAllPoints()
		sliderPitch:ClearAllPoints()
		sliderRoll:ClearAllPoints()
		sliderScale:ClearAllPoints()
		sliderObjExposure:ClearAllPoints()
		sliderObjR:ClearAllPoints()
		sliderObjG:ClearAllPoints()
		sliderObjB:ClearAllPoints()
		sliderHoverLum:ClearAllPoints()
		sliderTemp:ClearAllPoints()
		sliderLum:ClearAllPoints()
		sliderR:ClearAllPoints()
		sliderG:ClearAllPoints()
		sliderB:ClearAllPoints()

		local stepY = -44
			if isTimeTab then
				-- no slider layout on time tab
			elseif isColorTab then
				sliderTemp:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, 0)
				sliderLum:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY)
				sliderR:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 2)
			sliderG:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 3)
			sliderB:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 4)
			sliderHoverLum:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 5)
		else
			sliderX:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, 0)
			sliderY:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY)
			sliderZ:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 2)
			sliderYaw:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 3)
			sliderPitch:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 4)
			sliderRoll:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 5)
			sliderScale:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 6)
			sliderObjExposure:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 7)
			sliderObjR:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 8)
			sliderObjG:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 9)
			sliderObjB:SetPoint("TOPLEFT", sliderAnchor, "TOPLEFT", 0, stepY * 10)
		end

			SetWidgetsVisible(modelTabWidgets, (not isColorTab) and (not isTimeTab))
			SetWidgetsVisible(colorTabWidgets, isColorTab)
			SetWidgetsVisible(timeTabWidgets, isTimeTab)
			for i = 1, #modelSliders do
				SetSliderVisible(modelSliders[i], (not isColorTab) and (not isTimeTab))
			end
			for i = 1, #colorSliders do
				SetSliderVisible(colorSliders[i], isColorTab and (not isTimeTab))
			end
			sliderAnchor:SetShown(not isTimeTab)
			tabModelsBtn:SetEnabled(E.currentTab ~= "models")
			tabColorBtn:SetEnabled(E.currentTab ~= "color")
			tabTimeBtn:SetEnabled(E.currentTab ~= "time")
			if embeddedTimeEditor and embeddedTimeEditor.SetEmbeddedVisible then
				embeddedTimeEditor:SetEmbeddedVisible(isTimeTab)
				if isTimeTab and embeddedTimeEditor.Refresh then
					embeddedTimeEditor:Refresh()
				end
			end

			-- Resize panel to visible content.
			if panel:IsShown() then
				local panelTop = panel:GetTop()
				local panelBottomTarget
				if isTimeTab then
					panelBottomTarget = timeSection:GetBottom()
				elseif isColorTab then
					panelBottomTarget = sliderHoverLum:GetBottom()
				else
					panelBottomTarget = deleteBtn:GetBottom()
				end
				if panelTop and panelBottomTarget then
					local wanted = math.ceil((panelTop - panelBottomTarget) + 20)
					panel:SetHeight(math.max(330, wanted))
				end
			else
				panel:SetHeight(isTimeTab and 700 or (isColorTab and 360 or 700))
			end
		end

		local function SetCurrentTab(tab)
			if tab ~= "color" and tab ~= "time" then
				tab = "models"
			end
			E.currentTab = tab
		RefreshTabVisibility()
	end

	local exportFrame = CreateFrame("Frame", "WoWGuilde_QMObjectExport", panel, "BackdropTemplate")
	exportFrame:SetSize(760, 350)
	exportFrame:SetPoint("CENTER", parent, "CENTER", 0, 0)
	exportFrame:SetFrameStrata(parent:GetFrameStrata())
	exportFrame:SetFrameLevel(panel:GetFrameLevel() + 30)
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
	exportTitle:SetText("Export complet QM.Objects (coller dans Sections/QuartierMiniature/ObjectsData.lua)")
	exportFrame:SetMovable(true)
	exportFrame:SetClampedToScreen(true)
	local exportDrag = CreateFrame("Frame", nil, exportFrame)
	exportDrag:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 8, -8)
	exportDrag:SetPoint("TOPRIGHT", exportFrame, "TOPRIGHT", -30, -8)
	exportDrag:SetHeight(18)
	exportDrag:EnableMouse(true)
	exportDrag:RegisterForDrag("LeftButton")
	exportDrag:SetScript("OnDragStart", function()
		exportFrame:StartMoving()
	end)
	exportDrag:SetScript("OnDragStop", function()
		exportFrame:StopMovingOrSizing()
	end)

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
		local textHeight = 24
		if self.GetTextHeight then
			textHeight = tonumber(self:GetTextHeight()) or textHeight
		elseif self.GetStringHeight then
			textHeight = tonumber(self:GetStringHeight()) or textHeight
		end
		self:SetHeight(math.max(1, textHeight + 20))
	end)
	exportScroll:SetScrollChild(exportEdit)

	local catalogFrame = CreateFrame("Frame", "WoWGuilde_QMObjectCatalog", panel, "BackdropTemplate")
	catalogFrame:SetSize(760, 430)
	catalogFrame:SetPoint("CENTER", parent, "CENTER", 0, 0)
	catalogFrame:SetFrameStrata(parent:GetFrameStrata())
	catalogFrame:SetFrameLevel(panel:GetFrameLevel() + 32)
	catalogFrame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	catalogFrame:SetBackdropColor(0.01, 0.01, 0.01, 0.95)
	catalogFrame:Hide()
	catalogFrame:EnableMouseWheel(true)
	catalogFrame:EnableMouse(true)

	local catalogTitle = catalogFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	catalogTitle:SetPoint("TOPLEFT", catalogFrame, "TOPLEFT", 12, -10)
	catalogTitle:SetText("Catalogue assets M2")
	catalogFrame:SetMovable(true)
	catalogFrame:SetClampedToScreen(true)
	local catalogDrag = CreateFrame("Frame", nil, catalogFrame)
	catalogDrag:SetPoint("TOPLEFT", catalogFrame, "TOPLEFT", 8, -8)
	catalogDrag:SetPoint("TOPRIGHT", catalogFrame, "TOPRIGHT", -30, -8)
	catalogDrag:SetHeight(18)
	catalogDrag:EnableMouse(true)
	catalogDrag:RegisterForDrag("LeftButton")
	catalogDrag:SetScript("OnDragStart", function()
		catalogFrame:StartMoving()
	end)
	catalogDrag:SetScript("OnDragStop", function()
		catalogFrame:StopMovingOrSizing()
	end)

	local closeCatalog = CreateFrame("Button", nil, catalogFrame, "UIPanelCloseButton")
	closeCatalog:SetPoint("TOPRIGHT", catalogFrame, "TOPRIGHT", 2, 2)
	closeCatalog:SetScript("OnClick", function()
		catalogFrame:Hide()
		HideCatalogPreview()
	end)

	local catalogPathText = catalogFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	catalogPathText:SetPoint("TOPLEFT", catalogFrame, "TOPLEFT", 14, -36)
	catalogPathText:SetText("/")

	local catalogUpBtn = CreateFrame("Button", nil, catalogFrame, "UIPanelButtonTemplate")
	catalogUpBtn:SetSize(34, 20)
	catalogUpBtn:SetPoint("LEFT", catalogPathText, "RIGHT", 10, 0)
	catalogUpBtn:SetText("..")

	local catalogSearch = CreateFrame("EditBox", nil, catalogFrame, "InputBoxTemplate")
	catalogSearch:SetSize(220, 20)
	catalogSearch:SetPoint("TOPLEFT", catalogFrame, "TOPLEFT", 12, -58)
	catalogSearch:SetAutoFocus(false)
	catalogSearch:SetTextInsets(6, 6, 0, 0)
	catalogSearch:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)

	local catalogPrevBtn = CreateFrame("Button", nil, catalogFrame, "UIPanelButtonTemplate")
	catalogPrevBtn:SetSize(28, 20)
	catalogPrevBtn:SetPoint("TOPRIGHT", catalogFrame, "TOPRIGHT", -66, -34)
	catalogPrevBtn:SetText("<")

	local catalogNextBtn = CreateFrame("Button", nil, catalogFrame, "UIPanelButtonTemplate")
	catalogNextBtn:SetSize(28, 20)
	catalogNextBtn:SetPoint("LEFT", catalogPrevBtn, "RIGHT", 4, 0)
	catalogNextBtn:SetText(">")

	local catalogListFrame = CreateFrame("Frame", nil, catalogFrame, "BackdropTemplate")
	catalogListFrame:SetPoint("TOPLEFT", catalogFrame, "TOPLEFT", 12, -84)
	catalogListFrame:SetSize(732, 292)
	catalogListFrame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	catalogListFrame:SetBackdropColor(0, 0, 0, 0.35)
	catalogListFrame:EnableMouseWheel(true)
	catalogListFrame:EnableMouse(true)

	local catalogRows = {}
	local catalogVisibleRows = 12
	local catalogChoiceText = catalogFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	catalogChoiceText:SetPoint("TOPLEFT", catalogListFrame, "BOTTOMLEFT", 2, -8)
	catalogChoiceText:SetText("Selection: (aucune)")

	local catalogUseBtn = CreateFrame("Button", nil, catalogFrame, "UIPanelButtonTemplate")
	catalogUseBtn:SetSize(120, 22)
	catalogUseBtn:SetPoint("BOTTOMLEFT", catalogFrame, "BOTTOMLEFT", 12, 12)
	catalogUseBtn:SetText("Choisir")

	local catalogApplyBtn = CreateFrame("Button", nil, catalogFrame, "UIPanelButtonTemplate")
	catalogApplyBtn:SetSize(140, 22)
	catalogApplyBtn:SetPoint("LEFT", catalogUseBtn, "RIGHT", 8, 0)
	catalogApplyBtn:SetText("Appliquer a objet")

	local catalogItems = {}
	local catalogAllEntries = nil
	local catalogSearchResults = {}
	local catalogSearchState = nil
	local catalogSearchWorker = CreateFrame("Frame")
	catalogSearchWorker:Hide()
	local RefreshCatalogRows
	local HideCatalogPreview
	local ShowCatalogPreview

	local catalogPreview = CreateFrame("Frame", "WoWGuilde_QMObjectCatalogPreview", UIParent, "BackdropTemplate")
	catalogPreview:SetSize(280, 300)
	catalogPreview:SetFrameStrata("TOOLTIP")
	catalogPreview:SetFrameLevel(catalogFrame:GetFrameLevel() + 80)
	catalogPreview:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	catalogPreview:SetBackdropColor(0.01, 0.01, 0.01, 0.97)
	catalogPreview:Hide()
	catalogPreview:EnableMouse(false)

	local catalogPreviewPlayerModel = CreateFrame("PlayerModel", nil, catalogPreview)
	catalogPreviewPlayerModel:SetPoint("TOPLEFT", catalogPreview, "TOPLEFT", 10, -10)
	catalogPreviewPlayerModel:SetPoint("TOPRIGHT", catalogPreview, "TOPRIGHT", -10, -10)
	catalogPreviewPlayerModel:SetHeight(230)
	catalogPreviewPlayerModel:EnableMouse(false)

	local catalogPreviewGenericModel = CreateFrame("Model", nil, catalogPreview)
	catalogPreviewGenericModel:SetPoint("TOPLEFT", catalogPreviewPlayerModel, "TOPLEFT", 0, 0)
	catalogPreviewGenericModel:SetPoint("TOPRIGHT", catalogPreviewPlayerModel, "TOPRIGHT", 0, 0)
	catalogPreviewGenericModel:SetPoint("BOTTOM", catalogPreviewPlayerModel, "BOTTOM", 0, 0)
	catalogPreviewGenericModel:EnableMouse(false)
	catalogPreviewGenericModel:Hide()

	local catalogPreviewTitle = catalogPreview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	catalogPreviewTitle:SetPoint("TOPLEFT", catalogPreviewPlayerModel, "BOTTOMLEFT", 2, -8)
	catalogPreviewTitle:SetPoint("TOPRIGHT", catalogPreviewPlayerModel, "BOTTOMRIGHT", -2, -8)
	catalogPreviewTitle:SetJustifyH("LEFT")
	catalogPreviewTitle:SetWordWrap(false)
	catalogPreviewTitle:SetText("ID: -")

	local catalogPreviewPath = catalogPreview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	catalogPreviewPath:SetPoint("TOPLEFT", catalogPreviewTitle, "BOTTOMLEFT", 0, -4)
	catalogPreviewPath:SetPoint("TOPRIGHT", catalogPreviewTitle, "BOTTOMRIGHT", 0, -4)
	catalogPreviewPath:SetJustifyH("LEFT")
	catalogPreviewPath:SetTextColor(0.78, 0.78, 0.78, 1)
	catalogPreviewPath:SetWordWrap(false)
	catalogPreviewPath:SetText("")

	local catalogPreviewLoadToken = 0
	local catalogPreviewActiveModel = nil

	local function IsCatalogPreviewModelLoaded(model)
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

	local function SetCatalogPreviewActiveModel(model)
		catalogPreviewActiveModel = model
		if catalogPreviewPlayerModel then
			catalogPreviewPlayerModel:SetShown(model == catalogPreviewPlayerModel)
		end
		if catalogPreviewGenericModel then
			catalogPreviewGenericModel:SetShown(model == catalogPreviewGenericModel)
		end
	end

	local function ResetCatalogPreviewModel(model)
		if not model then
			return
		end
		if model.SetAlpha then
			pcall(model.SetAlpha, model, 1)
		end
		if model.SetPortraitZoom then
			pcall(model.SetPortraitZoom, model, 0)
		end
		if model.SetCamDistanceScale then
			pcall(model.SetCamDistanceScale, model, 1)
		end
		if model.SetFacing then
			pcall(model.SetFacing, model, 0)
		end
		if model.SetPosition then
			pcall(model.SetPosition, model, 0, 0, 0)
		end
		if model.ClearModel then
			pcall(model.ClearModel, model)
		end
	end

	local function TryLoadCatalogPreviewModel(model, fileId)
		if not (model and fileId and fileId > 0) then
			return false
		end
		local ok = false
		if model.SetModelByFileID then
			ok = pcall(model.SetModelByFileID, model, fileId)
		end
		if (not ok) and model.SetModel then
			ok = pcall(model.SetModel, model, fileId)
		end
		return ok
	end

	local function ApplyCatalogPreviewCamera(model)
		if not model then
			return
		end
		if model.SetSequence then
			pcall(model.SetSequence, model, 0)
		end
		if model.GetModelBounds then
			local ok, minX, maxX, minY, maxY, minZ, maxZ = pcall(model.GetModelBounds, model)
			if ok and minX and maxX and minY and maxY and minZ and maxZ then
				local cx = (minX + maxX) * 0.5
				local cy = (minY + maxY) * 0.5
				local cz = (minZ + maxZ) * 0.5
				local spanX = math.abs(maxX - minX)
				local spanY = math.abs(maxY - minY)
				local spanZ = math.abs(maxZ - minZ)
				local span = math.max(spanX, spanY, spanZ, 0.01)
				if model.SetPosition then
					pcall(model.SetPosition, model, -cx, -cy, -cz)
				end
				if model.SetCamDistanceScale then
					local dist = Clamp(1.6 + (span * 2.4), 1.2, 8.0)
					pcall(model.SetCamDistanceScale, model, dist)
				end
			end
		end
	end

	HideCatalogPreview = function()
		catalogPreviewLoadToken = catalogPreviewLoadToken + 1
		catalogPreview:Hide()
		ResetCatalogPreviewModel(catalogPreviewPlayerModel)
		ResetCatalogPreviewModel(catalogPreviewGenericModel)
		SetCatalogPreviewActiveModel(catalogPreviewPlayerModel)
		if GameTooltip and GameTooltip:IsShown() then
			GameTooltip:Hide()
		end
	end

	local function PlaceCatalogPreview(anchor)
		local ui = UIParent
		if not ui then
			return
		end

		local pW = catalogPreview:GetWidth() or 280
		local pH = catalogPreview:GetHeight() or 300
		local uiW = ui:GetWidth() or 0
		local uiH = ui:GetHeight() or 0
		local cursorX, cursorY = GetCursorPosition()
		local uiScale = ui:GetEffectiveScale() or 1
		if uiScale <= 0 then
			uiScale = 1
		end

		if cursorX and cursorY and cursorX > 0 and cursorY > 0 then
			local x = (cursorX / uiScale) + 18
			local y = (cursorY / uiScale) + 18

			if (x + pW + 8) > uiW then
				x = (cursorX / uiScale) - pW - 18
			end
			x = Clamp(x, 8, math.max(8, uiW - pW - 8))
			y = Clamp(y, pH + 8, math.max(pH + 8, uiH - 8))

			catalogPreview:ClearAllPoints()
			catalogPreview:SetPoint("TOPLEFT", ui, "BOTTOMLEFT", x, y)
			return
		end

		if not anchor then
			return
		end

		local aLeft = anchor:GetLeft() or 0
		local aRight = anchor:GetRight() or aLeft
		local aTop = anchor:GetTop() or 0
		local uiLeft = ui:GetLeft() or 0
		local uiRight = ui:GetRight() or 0

		local showOnRight = (uiRight - aRight) >= (aLeft - uiLeft)
		catalogPreview:ClearAllPoints()
		if showOnRight then
			catalogPreview:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 12, 0)
		else
			catalogPreview:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -12, 0)
		end
	end

	ShowCatalogPreview = function(entry, anchor)
		if type(entry) ~= "table" then
			HideCatalogPreview()
			return
		end
		local fileId = math.floor(tonumber(entry.fileId or entry.id) or 0)
		local modelPath = tostring(entry.path or "")
		if fileId <= 0 then
			HideCatalogPreview()
			return
		end

		PlaceCatalogPreview(anchor)
		if fileId > 0 then
			catalogPreviewTitle:SetText(("ID: %d"):format(fileId))
		else
			catalogPreviewTitle:SetText("ID: -")
		end
		catalogPreviewPath:SetText(modelPath ~= "" and modelPath or tostring(entry.name or ""))

		catalogPreviewLoadToken = catalogPreviewLoadToken + 1
		local token = catalogPreviewLoadToken
		ResetCatalogPreviewModel(catalogPreviewPlayerModel)
		ResetCatalogPreviewModel(catalogPreviewGenericModel)
		SetCatalogPreviewActiveModel(catalogPreviewPlayerModel)
		catalogPreview:Show()
		catalogPreviewPath:SetTextColor(0.78, 0.78, 0.78, 1)

		local order = { catalogPreviewPlayerModel, catalogPreviewGenericModel }
		local loaded = false
		for i = 1, #order do
				local m = order[i]
				if TryLoadCatalogPreviewModel(m, fileId) then
					SetCatalogPreviewActiveModel(m)
					ApplyCatalogPreviewCamera(m)
					loaded = true
					break
				end
		end
		if loaded then
			return
		end

		local maxRetries = 8
		local function EnsureLoaded(attempt)
			if token ~= catalogPreviewLoadToken or not catalogPreview:IsShown() then
				return
			end
			local active = catalogPreviewActiveModel or catalogPreviewPlayerModel
			if IsCatalogPreviewModelLoaded(active) then
				ApplyCatalogPreviewCamera(active)
				catalogPreviewPath:SetTextColor(0.78, 0.78, 0.78, 1)
				return
			end
			if attempt >= maxRetries then
				catalogPreviewPath:SetTextColor(0.95, 0.55, 0.55, 1)
				return
			end
			if active then
				TryLoadCatalogPreviewModel(active, fileId)
			end
			for i = 1, #order do
				local m = order[i]
				if m ~= active and TryLoadCatalogPreviewModel(m, fileId) then
					SetCatalogPreviewActiveModel(m)
					ApplyCatalogPreviewCamera(m)
					break
				end
			end
			C_Timer.After(0.25, function()
				EnsureLoaded(attempt + 1)
			end)
		end
		C_Timer.After(0.05, function()
			EnsureLoaded(1)
		end)
	end

	local function BuildSearchMatch(entry, queryLower)
		if type(entry) ~= "table" or queryLower == "" then
			return false
		end
		local fid = tostring(tonumber(entry.fileId) or 0)
		local name = tostring(entry.name or ""):lower()
		local path = tostring(entry.path or ""):lower()
		if fid:find(queryLower, 1, true) then
			return true
		end
		if name:find(queryLower, 1, true) then
			return true
		end
		if path:find(queryLower, 1, true) then
			return true
		end
		return false
	end

	local function EnsureCatalogEntries()
		if catalogAllEntries then
			return catalogAllEntries
		end
		if catalog and catalog.GetEntries then
			catalogAllEntries = catalog.GetEntries() or {}
		else
			catalogAllEntries = {}
		end
		return catalogAllEntries
	end

	local function StartSegmentedSearch(queryLower)
		if queryLower == "" then
			catalogSearchState = nil
			catalogSearchResults = {}
			catalogSearchWorker:Hide()
			catalogSearchWorker:SetScript("OnUpdate", nil)
			return
		end
		local entries = EnsureCatalogEntries()
		catalogSearchResults = {}
		catalogSearchState = {
			queryLower = queryLower,
			nextIndex = 1,
			total = #entries,
			done = false,
		}
		catalogSearchWorker:Show()
		catalogSearchWorker:SetScript("OnUpdate", function()
			local st = catalogSearchState
			if not st then
				catalogSearchWorker:Hide()
				catalogSearchWorker:SetScript("OnUpdate", nil)
				return
			end
			local budgetStart = debugprofilestop and debugprofilestop() or 0
			local entriesLocal = EnsureCatalogEntries()
			while st.nextIndex <= st.total do
				local e = entriesLocal[st.nextIndex]
				if BuildSearchMatch(e, st.queryLower) then
					catalogSearchResults[#catalogSearchResults + 1] = {
						type = "file",
						entry = e,
					}
				end
				st.nextIndex = st.nextIndex + 1
				if debugprofilestop then
					local elapsed = (debugprofilestop() - budgetStart)
					if elapsed >= 4.0 then
						break
					end
				elseif (st.nextIndex % 300) == 0 then
					break
				end
			end
			local finished = st.nextIndex > st.total
			if finished then
				st.done = true
				catalogSearchWorker:Hide()
				catalogSearchWorker:SetScript("OnUpdate", nil)
			end
			RefreshCatalogRows()
		end)
	end

	local function JoinPath(parts)
		if type(parts) ~= "table" or #parts == 0 then
			return "/"
		end
		return "/" .. table.concat(parts, "/")
	end

	local function MakeModelInputFromEntry(entry)
		if type(entry) ~= "table" then
			return ""
		end
		return tostring(entry.fileId or 0)
	end

	local function SetCatalogChoice(entry)
		E.catalogChoice = entry
		if type(entry) == "table" then
			modelInput:SetText(MakeModelInputFromEntry(entry))
			catalogChoiceText:SetText(("Selection ID: %d"):format(tonumber(entry.fileId) or 0))
		else
			catalogChoiceText:SetText("Selection: (aucune)")
		end
	end

	local function BuildModelPatchFromInput(inputText, kind)
		if not (QM.Objects and QM.Objects.NormalizeObject) then
			return nil
		end
		local normalized = QM.Objects.NormalizeObject({
			modelInput = tostring(inputText or ""),
			kind = kind or "m2",
			x = 0,
			y = 0,
			z = 0,
			yaw = 0,
			pitch = 0,
			roll = 0,
			scale = 1,
			size = 96,
			enabled = true,
		})
		if not normalized then
			return nil
		end
		return {
			kind = tostring(normalized.kind or "m2"),
			sourceType = tostring(normalized.sourceType or "path"),
			sourceValue = normalized.sourceValue,
			sourceFileId = normalized.sourceFileId,
		}
	end

	local function ApplyPatchToSelectedObject(patch)
		local id = scene.GetSelectedId and scene:GetSelectedId() or nil
		if not id or not scene.UpdateObject then
			return false, "missing_selection"
		end
		if type(patch) ~= "table" then
			return false, "invalid_patch"
		end
		return scene:UpdateObject(id, patch)
	end

	local function GetSelectedObjectSnapshot()
		local id = scene.GetSelectedId and scene:GetSelectedId() or nil
		if not id then
			return nil
		end
		local objs = scene.GetObjects and scene:GetObjects() or {}
		local sid = tostring(id)
		for i = 1, #objs do
			local o = objs[i]
			if tostring(o and o.id or "") == sid then
				return o
			end
		end
		return nil
	end

	local function ApplyCatalogChoiceToSelected()
		if not E.catalogChoice then
			return false, "missing_choice"
		end
		local input = MakeModelInputFromEntry(E.catalogChoice)
		local patch = BuildModelPatchFromInput(input, "m2")
		local current = GetSelectedObjectSnapshot()
		if patch and current then
			patch.u = current.u
			patch.v = current.v
			patch.x = current.x
			patch.y = current.y
			patch.z = current.z
			patch.yaw = current.yaw
			patch.pitch = current.pitch
			patch.roll = current.roll
			patch.scale = current.scale
			patch.size = current.size
			patch.enabled = current.enabled
		end
		local ok = patch and ApplyPatchToSelectedObject(patch)
		return ok and true or false
	end

	RefreshCatalogRows = function()
		HideCatalogPreview()
		local searchQuery = tostring(E.catalogSearchQuery or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local searchLower = searchQuery:lower()
		local inSearch = searchLower ~= ""
		if inSearch then
			if (not catalogSearchState) or (catalogSearchState.queryLower ~= searchLower) then
				StartSegmentedSearch(searchLower)
			end
			catalogItems = catalogSearchResults
		elseif catalog and catalog.ListNode then
			catalogItems = {}
			if catalogSearchState then
				catalogSearchState = nil
				catalogSearchWorker:Hide()
				catalogSearchWorker:SetScript("OnUpdate", nil)
			end
			local folders, files = catalog.ListNode(E.catalogPath)
			for i = 1, #folders do
				catalogItems[#catalogItems + 1] = {
					type = "folder",
					name = folders[i],
				}
			end
			for i = 1, #files do
				catalogItems[#catalogItems + 1] = {
					type = "file",
					entry = files[i],
				}
			end
		else
			catalogItems = {}
		end
		local maxOffset = math.max(0, #catalogItems - catalogVisibleRows)
		E.catalogOffset = Clamp(E.catalogOffset, 0, maxOffset)
		if inSearch then
			local suffix = ""
			if catalogSearchState and not catalogSearchState.done then
				suffix = " ..."
			end
			catalogPathText:SetText(("Recherche globale (%d%s)"):format(#catalogItems, suffix))
		else
			catalogPathText:SetText(JoinPath(E.catalogPath))
		end
		catalogUpBtn:SetEnabled((not inSearch) and #E.catalogPath > 0)
		catalogPrevBtn:SetEnabled(E.catalogOffset > 0)
		catalogNextBtn:SetEnabled(E.catalogOffset < maxOffset)

		for i = 1, catalogVisibleRows do
			local row = catalogRows[i]
			if not row then
				row = CreateFrame("Button", nil, catalogListFrame)
				row:SetSize(724, 22)
				row:SetPoint("TOPLEFT", catalogListFrame, "TOPLEFT", 4, -((i - 1) * 24) - 4)
				row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				row.bg = row:CreateTexture(nil, "BACKGROUND")
				row.bg:SetAllPoints(row)
				row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
				row.bg:SetVertexColor(0.12, 0.12, 0.12, 0.6)
				row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
				row.text:SetJustifyH("LEFT")
				row:EnableMouseWheel(true)
				row:SetScript("OnMouseWheel", function(_, delta)
					local maxOffset = math.max(0, #catalogItems - catalogVisibleRows)
					if delta > 0 then
						E.catalogOffset = math.max(0, E.catalogOffset - 1)
					elseif delta < 0 then
						E.catalogOffset = math.min(maxOffset, E.catalogOffset + 1)
					end
					RefreshCatalogRows()
				end)
				catalogRows[i] = row
			end
			local idx = E.catalogOffset + i
			local item = catalogItems[idx]
			if item then
				if item.type == "folder" then
					row.text:SetText("[D] " .. tostring(item.name) .. "/")
					row.bg:SetVertexColor(0.14, 0.18, 0.24, 0.55)
				else
					local e = item.entry
					if inSearch then
						row.text:SetText(
							("[%d] %s"):format(tonumber(e and e.fileId) or 0, tostring(e and e.path or ""))
						)
					else
						row.text:SetText(
							("[%d] %s"):format(tonumber(e and e.fileId) or 0, tostring(e and e.name or ""))
						)
					end
					if E.catalogChoice and e and E.catalogChoice.key == e.key then
						row.bg:SetVertexColor(0.45, 0.33, 0.08, 0.8)
					else
						row.bg:SetVertexColor(0.12, 0.12, 0.12, 0.6)
					end
				end
				row:SetScript("OnClick", function(_, button)
					if button == "RightButton" then
						if #E.catalogPath > 0 then
							table.remove(E.catalogPath, #E.catalogPath)
							E.catalogOffset = 0
							RefreshCatalogRows()
						end
						return
					end
					if item.type == "folder" then
						E.catalogPath[#E.catalogPath + 1] = item.name
						E.catalogOffset = 0
						RefreshCatalogRows()
						return
					end
					SetCatalogChoice(item.entry)
					local selectedId = scene.GetSelectedId and scene:GetSelectedId() or nil
					if selectedId then
						local ok = ApplyCatalogChoiceToSelected()
						if ok then
							status:SetText(
								"Objet remplace (ID " .. tostring(item.entry and item.entry.fileId or "?") .. ")"
							)
							E:Refresh()
						else
							status:SetText("Echec remplacement auto")
						end
					else
						status:SetText("ID selectionne: " .. tostring(item.entry and item.entry.fileId or "?"))
					end
				end)
					row._catalogItem = item
					row:SetScript("OnEnter", function(self)
						local hoverItem = self._catalogItem
						if hoverItem and hoverItem.type == "file" then
							ShowCatalogPreview(hoverItem.entry, self)
						end
					end)
				row:SetScript("OnLeave", function()
					HideCatalogPreview()
				end)
				row:Show()
			else
				row._catalogItem = nil
				row:SetScript("OnEnter", nil)
				row:SetScript("OnLeave", nil)
				row:Hide()
			end
		end
	end

	catalogSearch:SetScript("OnTextChanged", function(self)
		E.catalogSearchQuery = tostring(self:GetText() or "")
		E.catalogOffset = 0
		local q = tostring(E.catalogSearchQuery or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
		if q == "" then
			StartSegmentedSearch("")
		elseif (not catalogSearchState) or (catalogSearchState.queryLower ~= q) then
			StartSegmentedSearch(q)
		end
		RefreshCatalogRows()
	end)
	catalogSearch:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)

	local function SelectCatalogDefault()
		if not (catalog and catalog.GetDefaultEntry) then
			return
		end
		local first = catalog.GetDefaultEntry()
		if first then
			SetCatalogChoice(first)
		end
	end

	catalogUpBtn:SetScript("OnClick", function()
		if #E.catalogPath > 0 then
			table.remove(E.catalogPath, #E.catalogPath)
			E.catalogOffset = 0
			RefreshCatalogRows()
		end
	end)
	catalogPrevBtn:SetScript("OnClick", function()
		E.catalogOffset = math.max(0, E.catalogOffset - catalogVisibleRows)
		RefreshCatalogRows()
	end)
	catalogNextBtn:SetScript("OnClick", function()
		local maxOffset = math.max(0, #catalogItems - catalogVisibleRows)
		E.catalogOffset = math.min(maxOffset, E.catalogOffset + catalogVisibleRows)
		RefreshCatalogRows()
	end)
	catalogListFrame:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(0, #catalogItems - catalogVisibleRows)
		if delta > 0 then
			E.catalogOffset = math.max(0, E.catalogOffset - 1)
		elseif delta < 0 then
			E.catalogOffset = math.min(maxOffset, E.catalogOffset + 1)
		end
		RefreshCatalogRows()
	end)
	catalogListFrame:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and #E.catalogPath > 0 then
			table.remove(E.catalogPath, #E.catalogPath)
			E.catalogOffset = 0
			RefreshCatalogRows()
		end
	end)
	catalogFrame:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(0, #catalogItems - catalogVisibleRows)
		if delta > 0 then
			E.catalogOffset = math.max(0, E.catalogOffset - 1)
		elseif delta < 0 then
			E.catalogOffset = math.min(maxOffset, E.catalogOffset + 1)
		end
		RefreshCatalogRows()
	end)
	catalogFrame:SetScript("OnHide", function()
		HideCatalogPreview()
	end)
	catalogFrame:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and #E.catalogPath > 0 then
			table.remove(E.catalogPath, #E.catalogPath)
			E.catalogOffset = 0
			RefreshCatalogRows()
		end
	end)

	catalogUseBtn:SetScript("OnClick", function()
		if not E.catalogChoice then
			status:SetText("Aucun asset selectionne")
			return
		end
		modelInput:SetText(MakeModelInputFromEntry(E.catalogChoice))
		status:SetText("Selection ID: " .. tostring(E.catalogChoice.fileId or "?"))
		catalogFrame:Hide()
	end)

	catalogApplyBtn:SetScript("OnClick", function()
		if not E.catalogChoice then
			status:SetText("Aucun asset selectionne")
			return
		end
		local ok = ApplyCatalogChoiceToSelected()
		if ok then
			status:SetText("Objet remplace")
		else
			status:SetText("Echec remplacement")
		end
		E:Refresh()
	end)

	SelectCatalogDefault()

	local function SetHoverSliderLabel(value)
		local mult = (tonumber(value) or 160) / 100
		_G[sliderHoverLum:GetName() .. "Text"]:SetText(("Luminosite Hover: x%.2f"):format(mult))
	end

	local function ApplyHoverLinkFromField()
		local sourceId = tostring((scene.GetSelectedId and scene:GetSelectedId()) or "")
		if sourceId == "" then
			return false
		end
		local inputId = tostring(hoverModelInput:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local nextLink = (inputId ~= "") and inputId or nil
		local selectedObj = nil
		local objs = scene.GetObjects and scene:GetObjects() or {}
		for i = 1, #objs do
			local o = objs[i]
			if tostring(o and o.id or "") == sourceId then
				selectedObj = o
				break
			end
		end
		local currentLink = tostring(selectedObj and selectedObj.hoverLinkId or "")
		local nextText = tostring(nextLink or "")
		if currentLink == nextText then
			return true
		end
		local ok = scene.UpdateObject and scene:UpdateObject(sourceId, { hoverLinkId = nextLink })
		if ok then
			if nextLink then
				status:SetText("Liaison validee: " .. sourceId .. " -> " .. nextText)
			else
				status:SetText("Liaison retiree: " .. sourceId)
			end
			E:Refresh()
			return true
		end
		status:SetText("Echec validation liaison")
		return false
	end

	local function ApplyObjectNameFromField()
		local sourceId = tostring((scene.GetSelectedId and scene:GetSelectedId()) or "")
		if sourceId == "" then
			return false
		end
		local inputName = tostring(objectNameInput:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local nextName = (inputName ~= "") and inputName or nil
		local selectedObj = nil
		local objs = scene.GetObjects and scene:GetObjects() or {}
		for i = 1, #objs do
			local o = objs[i]
			if tostring(o and o.id or "") == sourceId then
				selectedObj = o
				break
			end
		end
		local currentName = tostring(selectedObj and selectedObj.displayName or "")
		local nextNameText = tostring(nextName or "")
		if currentName == nextNameText then
			return true
		end
		local ok = scene.UpdateObject and scene:UpdateObject(sourceId, { displayName = nextName })
		if ok then
			status:SetText("Nom mis a jour: " .. sourceId)
			E:Refresh()
			return true
		end
		status:SetText("Echec maj nom")
		return false
	end

	local function GetSelectedId()
		return scene.GetSelectedId and scene:GetSelectedId() or nil
	end

	local function GetSelectedObject()
		local id = tostring(GetSelectedId() or "")
		if id == "" then
			return nil
		end
		local objs = scene.GetObjects and scene:GetObjects() or {}
		for i = 1, #objs do
			if tostring(objs[i] and objs[i].id or "") == id then
				return objs[i]
			end
		end
		return nil
	end

	local function SetSliderDisplay(slider, fmt, value)
		_G[slider:GetName() .. "Text"]:SetText(fmt:format(value or 0))
		local box = sliderValueInputs[slider]
		if box and (not box:HasFocus()) then
			box:SetText(string.format(box._formatStr, tonumber(value) or 0))
		end
	end

	local function TempSliderToKelvin(v)
		return math.floor(6500 + ((tonumber(v) or 0) * 35))
	end

	local function ApplyGlobalLightingFromSliders()
		if E.updating or (not scene.SetGlobalLighting) then
			return
		end
		scene:SetGlobalLighting(
			(tonumber(sliderR:GetValue()) or 100) / 100,
			(tonumber(sliderG:GetValue()) or 100) / 100,
			(tonumber(sliderB:GetValue()) or 100) / 100,
			(tonumber(sliderLum:GetValue()) or 100) / 100
		)
	end

	local function UpdateSliderValues()
		E.updating = true
		local obj = GetSelectedObject()
		if obj then
			sliderX:SetValue(tonumber(obj.x) or 0)
			sliderY:SetValue(tonumber(obj.y) or 0)
			sliderZ:SetValue(tonumber(obj.z) or 0)
			sliderYaw:SetValue(tonumber(obj.yaw) or 0)
			sliderPitch:SetValue(tonumber(obj.pitch) or 0)
			sliderRoll:SetValue(tonumber(obj.roll) or 0)
			sliderScale:SetValue(tonumber(obj.scale) or 1)
			sliderObjExposure:SetValue(tonumber(obj.objectExposure) or 1)
			sliderObjR:SetValue(Clamp((tonumber(obj.objectColorR) or 1) * 100, 0, 200))
			sliderObjG:SetValue(Clamp((tonumber(obj.objectColorG) or 1) * 100, 0, 200))
			sliderObjB:SetValue(Clamp((tonumber(obj.objectColorB) or 1) * 100, 0, 200))
			deleteBtn:SetEnabled(true)
			dupBtn:SetEnabled(true)
			objectNameInput:SetText(tostring(obj.displayName or ""))
			hoverModelInput:SetText(tostring(obj.hoverLinkId or ""))
			hoverInfoText:SetText(("Objet/zone: %s"):format(tostring(obj.id or "-")))
		else
			sliderX:SetValue(0)
			sliderY:SetValue(0)
			sliderZ:SetValue(0)
			sliderYaw:SetValue(0)
			sliderPitch:SetValue(0)
			sliderRoll:SetValue(0)
			sliderScale:SetValue(1)
			sliderObjExposure:SetValue(1)
			sliderObjR:SetValue(100)
			sliderObjG:SetValue(100)
			sliderObjB:SetValue(100)
			deleteBtn:SetEnabled(false)
			dupBtn:SetEnabled(false)
			objectNameInput:SetText("")
			hoverModelInput:SetText("")
			hoverInfoText:SetText("Objet/zone: -")
		end
		if scene.GetColorTemperature then
			sliderTemp:SetValue(Clamp((tonumber(scene:GetColorTemperature()) or 0) * 100, -100, 100))
		else
			sliderTemp:SetValue(0)
		end
		if scene.GetGlobalLighting then
			local r, g, b, lum = scene:GetGlobalLighting()
			sliderR:SetValue(Clamp((tonumber(r) or 1) * 100, 0, 200))
			sliderG:SetValue(Clamp((tonumber(g) or 1) * 100, 0, 200))
			sliderB:SetValue(Clamp((tonumber(b) or 1) * 100, 0, 200))
			sliderLum:SetValue(Clamp((tonumber(lum) or 1) * 100, 0, 300))
		else
			sliderR:SetValue(100)
			sliderG:SetValue(100)
			sliderB:SetValue(100)
			sliderLum:SetValue(100)
		end
		if scene.GetHoverLightMultiplier then
			local hm = tonumber(scene:GetHoverLightMultiplier()) or 1.6
			sliderHoverLum:SetValue(Clamp(hm * 100, 100, 300))
		else
			sliderHoverLum:SetValue(160)
		end
		E.updating = false
	end

	local function SliderApply(key, value)
		if E.updating then
			return
		end
		local id = GetSelectedId()
		if not id then
			return
		end
		if scene.UpdateObject then
			scene:UpdateObject(id, { [key] = value })
		end
		E:RefreshList()
	end

	sliderX:SetScript("OnValueChanged", function(self, value)
		SliderApply("x", value)
		SetSliderDisplay(self, "X: %.2f", value)
	end)
	sliderY:SetScript("OnValueChanged", function(self, value)
		SliderApply("y", value)
		SetSliderDisplay(self, "Y: %.2f", value)
	end)
	sliderZ:SetScript("OnValueChanged", function(self, value)
		SliderApply("z", value)
		SetSliderDisplay(self, "Z: %.2f", value)
	end)
	sliderYaw:SetScript("OnValueChanged", function(self, value)
		SliderApply("yaw", Clamp(value, 0, 360))
		SetSliderDisplay(self, "Yaw: %.1f", value)
	end)
	sliderPitch:SetScript("OnValueChanged", function(self, value)
		SliderApply("pitch", Clamp(value, 0, 360))
		SetSliderDisplay(self, "Pitch: %.1f", value)
	end)
	sliderRoll:SetScript("OnValueChanged", function(self, value)
		SliderApply("roll", Clamp(value, 0, 360))
		SetSliderDisplay(self, "Roll: %.1f", value)
	end)
	sliderScale:SetScript("OnValueChanged", function(self, value)
		SliderApply("scale", Clamp(tonumber(value) or 1, 0.01, 1.0))
		SetSliderDisplay(self, "Scale: %.2f", value)
	end)
	sliderObjExposure:SetScript("OnValueChanged", function(self, value)
		SliderApply("objectExposure", Clamp(tonumber(value) or 1, 0.1, 5.0))
		SetSliderDisplay(self, "Exposition objet: %.2f", value)
	end)
	sliderObjR:SetScript("OnValueChanged", function(self, value)
		SliderApply("objectColorR", Clamp((tonumber(value) or 100) / 100, 0.0, 2.0))
		SetSliderDisplay(self, "Obj R: %.2f", (tonumber(value) or 100) / 100)
	end)
	sliderObjG:SetScript("OnValueChanged", function(self, value)
		SliderApply("objectColorG", Clamp((tonumber(value) or 100) / 100, 0.0, 2.0))
		SetSliderDisplay(self, "Obj G: %.2f", (tonumber(value) or 100) / 100)
	end)
	sliderObjB:SetScript("OnValueChanged", function(self, value)
		SliderApply("objectColorB", Clamp((tonumber(value) or 100) / 100, 0.0, 2.0))
		SetSliderDisplay(self, "Obj B: %.2f", (tonumber(value) or 100) / 100)
	end)
	sliderTemp:SetScript("OnValueChanged", function(self, value)
		local tempNorm = Clamp((tonumber(value) or 0) / 100, -1, 1)
		if not E.updating and scene.SetColorTemperature then
			scene:SetColorTemperature(tempNorm)
		end
		SetSliderDisplay(self, "Temp: %dK", TempSliderToKelvin(value))
	end)
	sliderLum:SetScript("OnValueChanged", function(self, value)
		ApplyGlobalLightingFromSliders()
		SetSliderDisplay(self, "Lum: %.2f", (tonumber(value) or 100) / 100)
	end)
	sliderR:SetScript("OnValueChanged", function(self, value)
		ApplyGlobalLightingFromSliders()
		SetSliderDisplay(self, "Light R: %.2f", (tonumber(value) or 100) / 100)
	end)
	sliderG:SetScript("OnValueChanged", function(self, value)
		ApplyGlobalLightingFromSliders()
		SetSliderDisplay(self, "Light G: %.2f", (tonumber(value) or 100) / 100)
	end)
	sliderB:SetScript("OnValueChanged", function(self, value)
		ApplyGlobalLightingFromSliders()
		SetSliderDisplay(self, "Light B: %.2f", (tonumber(value) or 100) / 100)
	end)
	sliderHoverLum:SetScript("OnValueChanged", function(self, value)
		SetHoverSliderLabel(value)
		if not E.updating and scene.SetHoverLightMultiplier then
			scene:SetHoverLightMultiplier((tonumber(value) or 160) / 100)
		end
	end)

	function E:RefreshList()
		local objs = scene.GetObjects and scene:GetObjects() or {}
		local selectedId = tostring(GetSelectedId() or "")
		for i = 1, #E.rows do
			E.rows[i]:Hide()
		end
		for i = 1, #objs do
			local row = E.rows[i]
			if not row then
				row = CreateFrame("Button", nil, listContent)
				row:SetSize(348, 20)
				row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
				row.text:SetJustifyH("LEFT")
				row.bg = row:CreateTexture(nil, "BACKGROUND")
				row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
				row.bg:SetAllPoints(row)
				row.bg:SetAlpha(0.12)
				E.rows[i] = row
			end
			local obj = objs[i]
			local id = tostring(obj and obj.id or "")
			row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -((i - 1) * 22))
			local src = tostring(obj and obj.sourceType or "") .. ":" .. tostring(obj and obj.sourceValue or "")
			local statusTxt = scene.GetRenderStatus and scene:GetRenderStatus(id) or "?"
			local prefix = (statusTxt == "loaded") and "OK loaded" or ("ERREUR " .. tostring(statusTxt))
			local displayName = tostring(obj and obj.displayName or "")
			local shownName = (displayName ~= "") and displayName or id
			row.text:SetText(("%s | %s | %s | %s"):format(prefix, shownName, tostring(obj.kind or "auto"), src))
			row._objectId = id
			if id ~= "" and id == selectedId then
				row.bg:SetVertexColor(1.00, 0.82, 0.10)
				row.bg:SetAlpha(0.30)
			else
				row.bg:SetVertexColor(0.2, 0.2, 0.2)
				row.bg:SetAlpha(0.16)
			end
			row:SetScript("OnClick", function(self)
				local targetId = tostring(self._objectId or "")
				if scene.SelectObject then
					scene:SelectObject(targetId)
				end
				E:Refresh()
			end)
			row:Show()
		end
		listContent:SetHeight(math.max(1, #objs * 22 + 2))
	end

	function E:Refresh()
		local isDev = E:IsDevMode()
		toggleBtn:SetShown(isDev)
		toggleBtn:EnableMouse(isDev)
		if (not isDev) and panel:IsShown() then
			panel:Hide()
			return
		end
		E:RefreshList()
		UpdateSliderValues()
		RefreshTabVisibility()
	end

	function E:IsVisible()
		return panel:IsShown()
	end

	addBtn:SetScript("OnClick", function()
		local input = tostring(modelInput:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if input == "" then
			status:SetText("Model invalide")
			return
		end
		if scene.CreateObject then
			local ok, idOrErr = scene:CreateObject({
				modelInput = input,
				kind = E.kind,
				x = 0,
				y = 0,
				z = 0,
				yaw = 0,
				pitch = 0,
				roll = 0,
				scale = 1,
				size = 96,
				enabled = true,
			})
			if ok then
				status:SetText("Ajoute: " .. tostring(idOrErr))
				E:Refresh()
				modelInput:SetText("")
			else
				status:SetText("Erreur: " .. tostring(idOrErr))
			end
		end
	end)

	browseBtn:SetScript("OnClick", function()
		E.catalogOffset = 0
		catalogSearch:SetText(E.catalogSearchQuery or "")
		RefreshCatalogRows()
		catalogFrame:Show()
	end)

	replaceBtn:SetScript("OnClick", function()
		local input = tostring(modelInput:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if input == "" and E.catalogChoice then
			input = MakeModelInputFromEntry(E.catalogChoice)
			modelInput:SetText(input)
		end
		if input == "" then
			status:SetText("Model invalide")
			return
		end
		local patch = BuildModelPatchFromInput(input, "m2")
		local ok = patch and ApplyPatchToSelectedObject(patch)
		if ok then
			status:SetText("Objet remplace")
			E:Refresh()
		else
			status:SetText("Echec remplacement")
		end
	end)

	deleteBtn:SetScript("OnClick", function()
		local id = GetSelectedId()
		if id and scene.DeleteObject then
			scene:DeleteObject(id)
			SelectCatalogDefault()
			status:SetText("Supprime: " .. tostring(id))
			E:Refresh()
		end
	end)

	dupBtn:SetScript("OnClick", function()
		local id = GetSelectedId()
		if id and scene.DuplicateObject then
			local ok, newId = scene:DuplicateObject(id)
			if ok then
				status:SetText("Duplique: " .. tostring(newId))
			else
				status:SetText("Erreur duplication")
			end
			E:Refresh()
		end
	end)

	exportBtn:SetScript("OnClick", function()
		if scene.ExportText then
			exportEdit:SetText(scene:ExportText())
			exportTitle:SetText("Export complet QM.Objects (coller dans Sections/QuartierMiniature/ObjectsData.lua)")
			exportFrame:Show()
			exportEdit:SetFocus()
			exportEdit:HighlightText()
		end
	end)

	hoverModelInput:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		ApplyHoverLinkFromField()
	end)
	hoverModelInput:SetScript("OnEditFocusLost", function()
		ApplyHoverLinkFromField()
	end)
	hoverModelInput:SetScript("OnEscapePressed", function(self)
		local obj = GetSelectedObject()
		self:SetText(tostring(obj and obj.hoverLinkId or ""))
		self:ClearFocus()
	end)

	objectNameInput:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		ApplyObjectNameFromField()
	end)
	objectNameInput:SetScript("OnEditFocusLost", function()
		ApplyObjectNameFromField()
	end)
	objectNameInput:SetScript("OnEscapePressed", function(self)
		local obj = GetSelectedObject()
		self:SetText(tostring(obj and obj.displayName or ""))
		self:ClearFocus()
	end)

	hoverExportBtn:SetScript("OnClick", function()
		if scene.ExportText then
			exportEdit:SetText(scene:ExportText())
			exportTitle:SetText("Export complet QM.Objects (inclut hoverLinkId)")
			exportFrame:Show()
			exportEdit:SetFocus()
			exportEdit:HighlightText()
		end
	end)

	tabModelsBtn:SetScript("OnClick", function()
		SetCurrentTab("models")
	end)

	tabColorBtn:SetScript("OnClick", function()
		SetCurrentTab("color")
	end)

	tabTimeBtn:SetScript("OnClick", function()
		SetCurrentTab("time")
	end)

	if scene.SetOnChanged then
		scene:SetOnChanged(function()
			if panel:IsShown() then
				E:Refresh()
			end
		end)
	end

	SetCurrentTab(E.currentTab)
	E:Refresh()
	return E
end
