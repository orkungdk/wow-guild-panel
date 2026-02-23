local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.TimeEditor = QM.TimeEditor or {}
local TimeEditor = QM.TimeEditor

local sliderSeq = 0
local function NextSliderName()
	sliderSeq = sliderSeq + 1
	return "WoWGuilde_QMTimeSlider_" .. tostring(sliderSeq)
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

local function SetSliderLabel(slider, text)
	if not slider then
		return
	end
	local fs = _G[slider:GetName() .. "Text"]
	if fs then
		fs:SetText(tostring(text or ""))
	end
end

local function SetTextureOrAtlas(tex, atlas, texture)
	if not tex then
		return
	end
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		tex:SetAtlas(atlas)
	else
		tex:SetTexture(texture or atlas)
	end
end

local function EnsurePhaseRow(timeline, key)
	if type(timeline) ~= "table" then
		return nil
	end
	for i = 1, #timeline do
		local row = timeline[i]
		if tostring(row and row.key or "") == key then
			return row
		end
	end
	return timeline[1]
end

function TimeEditor.Attach(opts)
	if type(opts) ~= "table" then
		return nil
	end

	local embeddedParent = opts.embeddedParent
	local embedded = embeddedParent ~= nil
	local parent = opts.parent
	local hudLayer = opts.hudLayer or parent
	if embedded then
		parent = embeddedParent
		hudLayer = embeddedParent
	end
	if not (parent and hudLayer) then
		return nil
	end

	local profiles = QM.TimeProfiles
	if not (type(profiles) == "table" and type(profiles.EnsureMapStore) == "function") then
		return nil
	end

	local function GetMapId()
		if type(opts.getMapId) == "function" then
			return tostring(opts.getMapId() or "default")
		end
		return "default"
	end

	local function GetRuntime()
		if type(opts.getRuntime) == "function" then
			return opts.getRuntime()
		end
		return opts.runtime
	end

	local function IsDevMode()
		if type(opts.isDevMode) == "function" then
			local ok, value = pcall(opts.isDevMode)
			return ok and value == true
		end
		return false
	end

	local function NotifyChanged(reason)
		if type(opts.onChanged) == "function" then
			opts.onChanged(reason)
		end
	end

	local E = {
		updating = false,
		selectedPhaseKey = "aube",
		phaseButtons = {},
		shareSliders = {},
	}

	local panel = CreateFrame("Frame", embedded and nil or "WoWGuilde_QMTimeEditor", embedded and embeddedParent or hudLayer, "BackdropTemplate")
	if embedded then
		panel:SetAllPoints(embeddedParent)
		panel:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 8,
			edgeSize = 10,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		panel:SetBackdropColor(0.02, 0.02, 0.02, 0.45)
		panel:Show()
	else
		panel:SetSize(452, 740)
		panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -470, -46)
		panel:SetFrameStrata(parent:GetFrameStrata())
		panel:SetFrameLevel((hudLayer:GetFrameLevel() or parent:GetFrameLevel() or 1) + 28)
		panel:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		panel:SetBackdropColor(0.02, 0.02, 0.02, 0.94)
		panel:Hide()
		panel:SetScript("OnShow", function(self)
			if not IsDevMode() then
				self:Hide()
			end
		end)
	end
	E.panel = panel

	local toggleBtn = nil
	if not embedded then
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
		title:SetText("Zaman - Mini bolge")

		local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
		closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 2, 2)
		closeBtn:SetScript("OnClick", function()
			panel:Hide()
		end)

		toggleBtn = CreateFrame("Button", nil, hudLayer, "UIPanelButtonTemplate")
		toggleBtn:SetSize(96, 22)
		toggleBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -126, -20)
		toggleBtn:SetText("Zaman")
		toggleBtn:SetFrameStrata(parent:GetFrameStrata())
		toggleBtn:SetFrameLevel((hudLayer:GetFrameLevel() or parent:GetFrameLevel() or 1) + 30)
		toggleBtn:SetScript("OnClick", function()
			if not IsDevMode() then
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
	end

	local statusBox = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	if embedded then
		statusBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
		statusBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
	else
		statusBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -34)
		statusBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -34)
	end
	statusBox:SetHeight(38)
	statusBox:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	statusBox:SetBackdropColor(0.0, 0.0, 0.0, 0.42)

	local statusLine = statusBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusLine:SetPoint("TOPLEFT", statusBox, "TOPLEFT", 8, -6)
	statusLine:SetPoint("TOPRIGHT", statusBox, "TOPRIGHT", -8, -6)
	statusLine:SetJustifyH("LEFT")
	statusLine:SetText("Dongu: -")
	E.statusLine = statusLine

	local mapLine = statusBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	mapLine:SetPoint("TOPLEFT", statusLine, "BOTTOMLEFT", 0, -3)
	mapLine:SetPoint("TOPRIGHT", statusBox, "TOPRIGHT", -8, -3)
	mapLine:SetJustifyH("LEFT")
	mapLine:SetText("Harita: -")
	E.mapLine = mapLine

	local scrollHost = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	scrollHost:SetPoint("TOPLEFT", statusBox, "BOTTOMLEFT", 0, -8)
	if embedded then
		scrollHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
	else
		scrollHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 38)
	end
	scrollHost:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	scrollHost:SetBackdropColor(0.0, 0.0, 0.0, 0.28)

	local scroll = CreateFrame("ScrollFrame", nil, scrollHost, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", scrollHost, "TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", scrollHost, "BOTTOMRIGHT", -26, 4)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(392, 1800)
	scroll:SetScrollChild(content)

	local cursorY = -10
	local function AddSectionTitle(text)
		local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint("TOPLEFT", content, "TOPLEFT", 10, cursorY)
		fs:SetText(tostring(text or ""))
		cursorY = cursorY - 22
		return fs
	end

	local function AddSmallHint(text)
		local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", content, "TOPLEFT", 12, cursorY)
		fs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -18, cursorY)
		fs:SetJustifyH("LEFT")
		fs:SetText(tostring(text or ""))
		cursorY = cursorY - 16
		return fs
	end

	local function AddSlider(label, minV, maxV, step)
		local slider = CreateSlider(content, 12, cursorY, 322, label, minV, maxV, step)
		cursorY = cursorY - 44
		return slider
	end

	AddSectionTitle("Calisma")
	local pauseBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	pauseBtn:SetSize(104, 22)
	pauseBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 12, cursorY)
	pauseBtn:SetText("Duraklat")

	local resumeBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	resumeBtn:SetSize(104, 22)
	resumeBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 6, 0)
	resumeBtn:SetText("Devam")

	local forceBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	forceBtn:SetSize(116, 22)
	forceBtn:SetPoint("LEFT", resumeBtn, "RIGHT", 6, 0)
	forceBtn:SetText("Faz zorla")
	cursorY = cursorY - 30

	local speedSlider = AddSlider("Dongu hizi", 10, 800, 1)
	local dayScrubSlider = AddSlider("Gun rengi", 0, 100, 1)
	local forceProgressSlider = AddSlider("Zorlanan faz ilerleme", 0, 100, 1)

	AddSectionTitle("Faz dagilimi (%)")
	AddSmallHint("Toplam otomatik olarak 100% olur.")

	local phaseOrder = profiles.GetPhaseOrder and profiles.GetPhaseOrder() or {
		"aube",
		"matin",
		"midi",
		"apres_midi",
		"crepuscule",
		"nuit",
	}

	for i = 1, #phaseOrder do
		local key = phaseOrder[i]
		local label = profiles.GetPhaseLabel and profiles.GetPhaseLabel(key) or key
		E.shareSliders[key] = AddSlider("Part " .. tostring(label), 1, 90, 1)
	end

	cursorY = cursorY - 4
	AddSectionTitle("Edition phase")
	AddSmallHint("Selectionnez une phase puis modifiez ses couleurs et modificateurs IA.")

	local phaseButtonRows = 2
	local phaseButtonCols = 3
	local phaseButtonW = 118
	local phaseButtonH = 20
	for i = 1, #phaseOrder do
		local key = phaseOrder[i]
		local label = profiles.GetPhaseLabel and profiles.GetPhaseLabel(key) or key
		local row = math.floor((i - 1) / phaseButtonCols)
		local col = (i - 1) % phaseButtonCols
		local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		btn:SetSize(phaseButtonW, phaseButtonH)
		btn:SetPoint("TOPLEFT", content, "TOPLEFT", 12 + (col * (phaseButtonW + 6)), cursorY - (row * 24))
		btn:SetText(label)
		btn._phaseKey = key
		btn:SetScript("OnClick", function(self)
			E.selectedPhaseKey = tostring(self._phaseKey or "aube")
			E:Refresh()
		end)
		E.phaseButtons[#E.phaseButtons + 1] = btn
	end
	cursorY = cursorY - ((phaseButtonRows * 24) + 8)

	local bgRSlider = AddSlider("Fond R", 0, 200, 1)
	local bgGSlider = AddSlider("Fond G", 0, 200, 1)
	local bgBSlider = AddSlider("Fond B", 0, 200, 1)
	local bgASlider = AddSlider("Fond Alpha", 0, 100, 1)

	local modelTempSlider = AddSlider("Modeles Temperature", -100, 100, 1)
	local modelRSlider = AddSlider("Modeles Light R", 0, 200, 1)
	local modelGSlider = AddSlider("Modeles Light G", 0, 200, 1)
	local modelBSlider = AddSlider("Modeles Light B", 0, 200, 1)
	local modelLumSlider = AddSlider("Modeles Luminance", 0, 300, 1)

	local aiDynSlider = AddSlider("IA Dynamisme", 20, 300, 1)
	local aiInteractionSlider = AddSlider("IA Interaction", 20, 300, 1)
	local aiAutoIntentSlider = AddSlider("IA AutoIntentRate", 20, 300, 1)
	local aiNeedsDrainSlider = AddSlider("IA NeedsDrain", 20, 300, 1)
	local aiNeedsRecoverySlider = AddSlider("IA NeedsRecovery", 20, 300, 1)

	local wRestSlider = AddSlider("Poids rest", 10, 400, 1)
	local wMealSlider = AddSlider("Poids meal", 10, 400, 1)
	local wDistractionSlider = AddSlider("Poids distraction", 10, 400, 1)
	local wMoveSlider = AddSlider("Poids move_place", 10, 400, 1)
	local wObserveSlider = AddSlider("Poids observe_nature", 10, 400, 1)
	local wTalkSlider = AddSlider("Poids talk", 10, 400, 1)

	cursorY = cursorY - 8
	AddSectionTitle("Actions")
	local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	resetBtn:SetSize(164, 22)
	resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 12, cursorY)
	resetBtn:SetText("Hikaye preset sifirla")

	local exportBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	exportBtn:SetSize(128, 22)
	exportBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
	exportBtn:SetText("Profilleri disari aktar")
	cursorY = cursorY - 30

	content:SetHeight(math.abs(cursorY) + 30)

	local exportFrame = CreateFrame("Frame", "WoWGuilde_QMTimeExport", panel, "BackdropTemplate")
	exportFrame:SetSize(760, 380)
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
	exportTitle:SetText("QM.TimeProfiles tam export (Sections/QuartierMiniature/TimeProfilesData.lua icine yapistir)")

	local closeExport = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
	closeExport:SetPoint("TOPRIGHT", exportFrame, "TOPRIGHT", 2, 2)
	closeExport:SetScript("OnClick", function()
		exportFrame:Hide()
	end)

	local exportScroll = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
	exportScroll:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 12, -34)
	exportScroll:SetPoint("BOTTOMRIGHT", exportFrame, "BOTTOMRIGHT", -34, 14)
	local exportEdit = CreateFrame("EditBox", nil, exportScroll)
	exportEdit:SetMultiLine(true)
	exportEdit:SetFontObject(ChatFontNormal)
	exportEdit:SetWidth(700)
	exportEdit:SetAutoFocus(false)
	exportEdit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	exportEdit:SetScript("OnTextChanged", function(self)
		local textHeight = nil
		if self.GetStringHeight then
			textHeight = self:GetStringHeight()
		elseif self.GetTextHeight then
			textHeight = self:GetTextHeight()
		end
		self:SetHeight(math.max(1, (tonumber(textHeight) or self:GetHeight() or 1) + 20))
	end)
	exportScroll:SetScrollChild(exportEdit)

	local refreshTicker = 0
	panel:SetScript("OnUpdate", function(_, elapsed)
		if not panel:IsShown() then
			return
		end
		refreshTicker = refreshTicker + (tonumber(elapsed) or 0)
		if refreshTicker < 0.20 then
			return
		end
		refreshTicker = 0
		local runtime = GetRuntime()
		local state = runtime and runtime.GetState and runtime:GetState() or nil
		if state then
			statusLine:SetText(
				string.format(
					"Cycle: %s (%s) - Heure %s - Jour %.1f%%",
					tostring(state.phaseLabel or "?"),
					tostring(state.phaseKey or "?"),
					tostring(state.timeText or "00:00"),
					(tonumber(state.dayProgress01) or 0) * 100
				)
			)
		else
			statusLine:SetText("Dongu: yok")
		end
		mapLine:SetText("Map: " .. tostring(GetMapId()))
	end)

	local function GetStore()
		return profiles.EnsureMapStore(GetMapId())
	end

	local function GetSelectedPhase(store)
		return EnsurePhaseRow(store and store.timeline, E.selectedPhaseKey)
	end

	local function HighlightSelectedPhase()
		for i = 1, #E.phaseButtons do
			local btn = E.phaseButtons[i]
			local selected = tostring(btn._phaseKey or "") == tostring(E.selectedPhaseKey or "")
			btn:SetEnabled(not selected)
		end
	end

	local function UpdateFromStore()
		E.updating = true
		local store = GetStore()
		local runtime = GetRuntime()
		local runtimeState = runtime and runtime.GetState and runtime:GetState() or nil
		local phase = GetSelectedPhase(store)
		if phase and type(phase.key) == "string" then
			E.selectedPhaseKey = phase.key
		end

		for i = 1, #phaseOrder do
			local key = phaseOrder[i]
			local row = EnsurePhaseRow(store.timeline, key)
			local slider = E.shareSliders[key]
			if slider and row then
				local pct = Clamp((tonumber(row.share) or 0) * 100, 0, 100)
				slider:SetValue(pct)
				SetSliderLabel(slider, string.format("Part %s: %.1f%%", tostring(row.label or key), pct))
			end
		end

		local colors = phase and phase.colors or {}
		local bg = type(colors.background) == "table" and colors.background or {}
		local models = type(colors.models) == "table" and colors.models or {}
		local ai = phase and phase.ai or {}
		local weights = type(ai.actionWeights) == "table" and ai.actionWeights or {}

		bgRSlider:SetValue(Clamp((tonumber(bg.r) or 1) * 100, 0, 200))
		bgGSlider:SetValue(Clamp((tonumber(bg.g) or 1) * 100, 0, 200))
		bgBSlider:SetValue(Clamp((tonumber(bg.b) or 1) * 100, 0, 200))
		bgASlider:SetValue(Clamp((tonumber(bg.a) or 1) * 100, 0, 100))
		modelTempSlider:SetValue(Clamp((tonumber(models.colorTemperature) or 0) * 100, -100, 100))
		modelRSlider:SetValue(Clamp((tonumber(models.lightColorR) or 1) * 100, 0, 200))
		modelGSlider:SetValue(Clamp((tonumber(models.lightColorG) or 1) * 100, 0, 200))
		modelBSlider:SetValue(Clamp((tonumber(models.lightColorB) or 1) * 100, 0, 200))
		modelLumSlider:SetValue(Clamp((tonumber(models.lightLuminance) or 1) * 100, 0, 300))

		aiDynSlider:SetValue(Clamp((tonumber(ai.dynamism) or 1) * 100, 20, 300))
		aiInteractionSlider:SetValue(Clamp((tonumber(ai.interaction) or 1) * 100, 20, 300))
		aiAutoIntentSlider:SetValue(Clamp((tonumber(ai.autoIntentRate) or 1) * 100, 20, 300))
		aiNeedsDrainSlider:SetValue(Clamp((tonumber(ai.needsDrain) or 1) * 100, 20, 300))
		aiNeedsRecoverySlider:SetValue(Clamp((tonumber(ai.needsRecovery) or 1) * 100, 20, 300))

		wRestSlider:SetValue(Clamp((tonumber(weights.rest) or 1) * 100, 10, 400))
		wMealSlider:SetValue(Clamp((tonumber(weights.meal) or 1) * 100, 10, 400))
		wDistractionSlider:SetValue(Clamp((tonumber(weights.distraction) or 1) * 100, 10, 400))
		wMoveSlider:SetValue(Clamp((tonumber(weights.move_place) or 1) * 100, 10, 400))
		wObserveSlider:SetValue(Clamp((tonumber(weights.observe_nature) or 1) * 100, 10, 400))
		wTalkSlider:SetValue(Clamp((tonumber(weights.talk) or 1) * 100, 10, 400))

		local speed = runtime and runtime.GetTimeScale and runtime:GetTimeScale() or 1.0
		speedSlider:SetValue(Clamp((tonumber(speed) or 1.0) * 100, 10, 800))
		local dayPct = Clamp((tonumber(runtimeState and runtimeState.dayProgress01) or 0) * 100, 0, 100)
		dayScrubSlider:SetValue(dayPct)
		SetSliderLabel(
			dayScrubSlider,
			string.format(
				"Colorimetrie journee: %.1f%% (%s - %s)",
				dayPct,
				tostring(runtimeState and runtimeState.phaseLabel or "?"),
				tostring(runtimeState and runtimeState.timeText or "00:00")
			)
		)

		HighlightSelectedPhase()
		E.updating = false
	end

	local function MutateSelectedPhase(fn)
		local store = GetStore()
		local phase = GetSelectedPhase(store)
		if not phase then
			return
		end
		phase.colors = type(phase.colors) == "table" and phase.colors or {}
		phase.colors.background = type(phase.colors.background) == "table" and phase.colors.background or {}
		phase.colors.models = type(phase.colors.models) == "table" and phase.colors.models or {}
		phase.ai = type(phase.ai) == "table" and phase.ai or {}
		phase.ai.actionWeights = type(phase.ai.actionWeights) == "table" and phase.ai.actionWeights or {}
		fn(phase)
		NotifyChanged("time_profile_edit")
	end

	local function HandleShareChanged(phaseKey, sliderValue)
		if E.updating then
			return
		end
		local store = GetStore()
		local row = EnsurePhaseRow(store.timeline, phaseKey)
		if not row then
			return
		end
		row.share = Clamp((tonumber(sliderValue) or 1) / 100, 0.001, 1.0)
		store.timeline = profiles.NormalizeTimeline(store.timeline)
		NotifyChanged("time_share_edit")
		UpdateFromStore()
	end

	for i = 1, #phaseOrder do
		local key = phaseOrder[i]
		local slider = E.shareSliders[key]
		slider:SetScript("OnValueChanged", function(self, value)
			HandleShareChanged(key, value)
			SetSliderLabel(self, string.format("Part %s: %.1f%%", tostring(profiles.GetPhaseLabel and profiles.GetPhaseLabel(key) or key), tonumber(value) or 0))
		end)
	end

	bgRSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.colors.background.r = Clamp((tonumber(value) or 100) / 100, 0.0, 2.0)
			end)
		end
		SetSliderLabel(self, string.format("Fond R: %.2f", (tonumber(value) or 0) / 100))
	end)
	bgGSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.colors.background.g = Clamp((tonumber(value) or 100) / 100, 0.0, 2.0)
			end)
		end
		SetSliderLabel(self, string.format("Fond G: %.2f", (tonumber(value) or 0) / 100))
	end)
	bgBSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.colors.background.b = Clamp((tonumber(value) or 100) / 100, 0.0, 2.0)
			end)
		end
		SetSliderLabel(self, string.format("Fond B: %.2f", (tonumber(value) or 0) / 100))
	end)
	bgASlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.colors.background.a = Clamp((tonumber(value) or 100) / 100, 0.0, 1.0)
			end)
		end
		SetSliderLabel(self, string.format("Fond Alpha: %.2f", (tonumber(value) or 0) / 100))
	end)

	modelTempSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.colors.models.colorTemperature = Clamp((tonumber(value) or 0) / 100, -1.0, 1.0)
			end)
		end
		SetSliderLabel(self, string.format("Modeles Temperature: %.2f", (tonumber(value) or 0) / 100))
	end)
	modelRSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.colors.models.lightColorR = Clamp((tonumber(value) or 100) / 100, 0.0, 2.0)
			end)
		end
		SetSliderLabel(self, string.format("Modeles Light R: %.2f", (tonumber(value) or 0) / 100))
	end)
	modelGSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.colors.models.lightColorG = Clamp((tonumber(value) or 100) / 100, 0.0, 2.0)
			end)
		end
		SetSliderLabel(self, string.format("Modeles Light G: %.2f", (tonumber(value) or 0) / 100))
	end)
	modelBSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.colors.models.lightColorB = Clamp((tonumber(value) or 100) / 100, 0.0, 2.0)
			end)
		end
		SetSliderLabel(self, string.format("Modeles Light B: %.2f", (tonumber(value) or 0) / 100))
	end)
	modelLumSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.colors.models.lightLuminance = Clamp((tonumber(value) or 100) / 100, 0.0, 3.0)
			end)
		end
		SetSliderLabel(self, string.format("Modeles Luminance: %.2f", (tonumber(value) or 0) / 100))
	end)

	aiDynSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.ai.dynamism = Clamp((tonumber(value) or 100) / 100, 0.20, 3.0)
			end)
		end
		SetSliderLabel(self, string.format("IA Dynamisme: %.2f", (tonumber(value) or 0) / 100))
	end)
	aiInteractionSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.ai.interaction = Clamp((tonumber(value) or 100) / 100, 0.20, 3.0)
			end)
		end
		SetSliderLabel(self, string.format("IA Interaction: %.2f", (tonumber(value) or 0) / 100))
	end)
	aiAutoIntentSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.ai.autoIntentRate = Clamp((tonumber(value) or 100) / 100, 0.20, 4.0)
			end)
		end
		SetSliderLabel(self, string.format("IA AutoIntentRate: %.2f", (tonumber(value) or 0) / 100))
	end)
	aiNeedsDrainSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.ai.needsDrain = Clamp((tonumber(value) or 100) / 100, 0.20, 4.0)
			end)
		end
		SetSliderLabel(self, string.format("IA NeedsDrain: %.2f", (tonumber(value) or 0) / 100))
	end)
	aiNeedsRecoverySlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.ai.needsRecovery = Clamp((tonumber(value) or 100) / 100, 0.20, 4.0)
			end)
		end
		SetSliderLabel(self, string.format("IA NeedsRecovery: %.2f", (tonumber(value) or 0) / 100))
	end)

	wRestSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.ai.actionWeights.rest = Clamp((tonumber(value) or 100) / 100, 0.10, 4.0)
			end)
		end
		SetSliderLabel(self, string.format("Poids rest: %.2f", (tonumber(value) or 0) / 100))
	end)
	wMealSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.ai.actionWeights.meal = Clamp((tonumber(value) or 100) / 100, 0.10, 4.0)
			end)
		end
		SetSliderLabel(self, string.format("Poids meal: %.2f", (tonumber(value) or 0) / 100))
	end)
	wDistractionSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.ai.actionWeights.distraction = Clamp((tonumber(value) or 100) / 100, 0.10, 4.0)
			end)
		end
		SetSliderLabel(self, string.format("Poids distraction: %.2f", (tonumber(value) or 0) / 100))
	end)
	wMoveSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.ai.actionWeights.move_place = Clamp((tonumber(value) or 100) / 100, 0.10, 4.0)
			end)
		end
		SetSliderLabel(self, string.format("Poids move_place: %.2f", (tonumber(value) or 0) / 100))
	end)
	wObserveSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.ai.actionWeights.observe_nature = Clamp((tonumber(value) or 100) / 100, 0.10, 4.0)
			end)
		end
		SetSliderLabel(self, string.format("Poids observe_nature: %.2f", (tonumber(value) or 0) / 100))
	end)
	wTalkSlider:SetScript("OnValueChanged", function(self, value)
		if not E.updating then
			MutateSelectedPhase(function(phase)
				phase.ai.actionWeights.talk = Clamp((tonumber(value) or 100) / 100, 0.10, 4.0)
			end)
		end
		SetSliderLabel(self, string.format("Poids talk: %.2f", (tonumber(value) or 0) / 100))
	end)

	speedSlider:SetScript("OnValueChanged", function(self, value)
		local norm = Clamp((tonumber(value) or 100) / 100, 0.10, 8.0)
		if not E.updating then
			local runtime = GetRuntime()
			if runtime and runtime.SetTimeScale then
				runtime:SetTimeScale(norm)
				NotifyChanged("time_speed")
			end
		end
		SetSliderLabel(self, string.format("Vitesse cycle: %.2fx", norm))
	end)

	dayScrubSlider:SetScript("OnValueChanged", function(self, value)
		local pct = Clamp(tonumber(value) or 0, 0, 100)
		local runtime = GetRuntime()
		if not E.updating and runtime and runtime.GetState and runtime.SetClockSeconds then
			local state = runtime:GetState()
			local duration = math.max(60, tonumber(state and state.dayDurationSec) or 7200)
			runtime:SetClockSeconds(duration * (pct / 100))
			NotifyChanged("time_scrub")
		end
		local stateNow = runtime and runtime.GetState and runtime:GetState() or nil
		SetSliderLabel(
			self,
			string.format(
				"Colorimetrie journee: %.1f%% (%s - %s)",
				pct,
				tostring(stateNow and stateNow.phaseLabel or "?"),
				tostring(stateNow and stateNow.timeText or "00:00")
			)
		)
	end)

	forceProgressSlider:SetScript("OnValueChanged", function(self, value)
		SetSliderLabel(self, string.format("Progression phase forcee: %.0f%%", tonumber(value) or 0))
	end)

	pauseBtn:SetScript("OnClick", function()
		local runtime = GetRuntime()
		if runtime and runtime.SetPaused then
			runtime:SetPaused(true)
			NotifyChanged("time_pause")
		end
		E:Refresh()
	end)

	resumeBtn:SetScript("OnClick", function()
		local runtime = GetRuntime()
		if runtime and runtime.SetPaused then
			runtime:SetPaused(false)
			NotifyChanged("time_resume")
		end
		E:Refresh()
	end)

	forceBtn:SetScript("OnClick", function()
		local runtime = GetRuntime()
		if runtime and runtime.SetPhase then
			runtime:SetPhase(E.selectedPhaseKey, Clamp((tonumber(forceProgressSlider:GetValue()) or 0) / 100, 0, 1))
			NotifyChanged("time_force_phase")
		end
		E:Refresh()
	end)

	resetBtn:SetScript("OnClick", function()
		local store = GetStore()
		store.settings = profiles.GetDefaultSettings and profiles.GetDefaultSettings() or {
			dayDurationSec = 7200,
			timelinePreset = "narrative_balanced",
		}
		store.timeline = profiles.GetDefaultTimeline and profiles.GetDefaultTimeline() or store.timeline
		store.timeline = profiles.NormalizeTimeline(store.timeline)
		E.selectedPhaseKey = "aube"
		local runtime = GetRuntime()
		if runtime and runtime.SetPhase then
			runtime:SetPhase("aube", 0)
		end
		NotifyChanged("time_reset")
		UpdateFromStore()
	end)

	exportBtn:SetScript("OnClick", function()
		local text = ""
		if profiles.BuildExportText then
			text = profiles.BuildExportText(GetMapId())
		end
		exportEdit:SetText(text or "")
		exportFrame:Show()
		exportEdit:SetFocus()
		exportEdit:HighlightText()
	end)

	function E:Refresh()
		local isDev = IsDevMode()
		if toggleBtn then
			toggleBtn:SetShown(isDev)
			toggleBtn:EnableMouse(isDev)
		end
		if embedded then
			panel:SetShown(isDev)
			if not isDev then
				return
			end
		else
			if (not isDev) and panel:IsShown() then
				panel:Hide()
				return
			end
		end
		UpdateFromStore()
	end

	function E:SetEmbeddedVisible(visible)
		if not embedded then
			return
		end
		panel:SetShown(visible == true and IsDevMode())
	end

	function E:IsVisible()
		return panel:IsShown()
	end

	E:Refresh()
	return E
end

return TimeEditor
