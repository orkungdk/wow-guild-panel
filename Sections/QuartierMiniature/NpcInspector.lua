local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.NpcInspector = QM.NpcInspector or {}
local NpcInspector = QM.NpcInspector

local NEED_ORDER = {
	{ key = "social", label = "Social" },
	{ key = "fatigue", label = "Fatigue" },
	{ key = "faim", label = "Faim" },
	{ key = "distraction", label = "Distraction" },
}

local NEED_BG_ATLAS = "UI-CastingBar-Background"
local NEED_BG_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Background"
local NEED_FILL_ATLAS = "ui-castingbar-tier2-empower-2x"
local NEED_FILL_FALLBACK_TEXTURE = "Interface\\TARGETINGFRAME\\UI-StatusBar"
local NEED_FRAME_ATLAS = "UI-CastingBar-Frame"
local NEED_FRAME_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Frame"
local NEED_PIP_ATLAS = "UI-CastingBar-Pip"
local NEED_PIP_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Pip"
local INTENT_SLOT_ATLAS = "UI-HUD-ActionBar-IconFrame-Slot"
local INTENT_SLOT_TEXTURE = "Interface\\HUD\\ActionBar\\UI-HUD-ActionBar-IconFrame-Slot"
local INTENT_ROW_ATLAS = "UI-HUD-ActionBar-IconFrame-AddRow"
local INTENT_ROW_TEXTURE = "Interface\\HUD\\ActionBar\\UI-HUD-ActionBar-IconFrame-AddRow"
local INTENT_HIGHLIGHT_ATLAS = "UI-HUD-ActionBar-IconFrame-Mouseover"
local INTENT_HIGHLIGHT_TEXTURE = "Interface\\HUD\\ActionBar\\UI-HUD-ActionBar-IconFrame-Mouseover"
local INTENT_ICON_MASK = "Interface\\common\\commoniconmask"
local INTENT_ICON_FALLBACK = "Interface\\ICONS\\INV_Misc_QuestionMark"

local function Clamp(v, minV, maxV)
	if v < minV then
		return minV
	end
	if v > maxV then
		return maxV
	end
	return v
end

local function SetTextureOrAtlas(tex, atlasName, texturePath)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlasName) then
		tex:SetAtlas(atlasName)
	else
		tex:SetTexture(texturePath or atlasName)
	end
end

local function CreateNeedRow(parent, yOffset, labelText)
	local row = {}
	row.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yOffset)
	row.label:SetJustifyH("LEFT")
	row.label:SetText(labelText)

	row.bg = parent:CreateTexture(nil, "ARTWORK", nil, 1)
	row.bg:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
	row.bg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, yOffset - 15)
	row.bg:SetHeight(12)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(NEED_BG_ATLAS) then
		row.bg:SetAtlas(NEED_BG_ATLAS)
	else
		row.bg:SetTexture(NEED_BG_TEXTURE)
	end
	row.bg:SetTexCoord(0, 1, 0, 1)
	row.bg:SetBlendMode("BLEND")
	row.bg:SetVertexColor(1.00, 1.00, 1.00, 1.00)

	row.bar = CreateFrame("StatusBar", nil, parent)
	row.bar:SetPoint("TOPLEFT", row.bg, "TOPLEFT", 1, -1)
	row.bar:SetPoint("BOTTOMRIGHT", row.bg, "BOTTOMRIGHT", -1, 1)
	row.bar:SetMinMaxValues(0, 100)
	row.bar:SetValue(0)
	row.bar._fill = row.bar:CreateTexture(nil, "ARTWORK")
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(NEED_FILL_ATLAS) then
		row.bar._fill:SetAtlas(NEED_FILL_ATLAS)
	else
		row.bar._fill:SetTexture(NEED_FILL_ATLAS)
		if row.bar._fill.GetTexture and not row.bar._fill:GetTexture() then
			row.bar._fill:SetTexture(NEED_FILL_FALLBACK_TEXTURE)
		end
	end
	if row.bar._fill.SetDesaturated then
		row.bar._fill:SetDesaturated(true)
	end
	row.bar:SetStatusBarTexture(row.bar._fill)
	row.bar:SetAlpha(1)
	row.bar:SetStatusBarColor(0.20, 0.90, 0.20, 1.0)

	row.frame = row.bar:CreateTexture(nil, "OVERLAY", nil, 6)
	row.frame:SetAllPoints(row.bg)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(NEED_FRAME_ATLAS) then
		row.frame:SetAtlas(NEED_FRAME_ATLAS)
	else
		row.frame:SetTexture(NEED_FRAME_TEXTURE)
	end
	row.frame:SetVertexColor(1.00, 1.00, 1.00, 1.00)

	row.pip = row.bar:CreateTexture(nil, "OVERLAY", nil, 7)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(NEED_PIP_ATLAS) then
		row.pip:SetAtlas(NEED_PIP_ATLAS)
	else
		row.pip:SetTexture(NEED_PIP_TEXTURE)
	end
	if row.pip.SetDesaturated then
		row.pip:SetDesaturated(true)
	end
	row.pip:SetSize(4, 14)
	row.pip:SetAlpha(0.6)
	row.pip:SetBlendMode("ADD")
	row.pip:SetPoint("CENTER", row.bar, "LEFT", 0, 0)

	return row
end

local function GetNeedReserveColor(value)
	local t = Clamp((tonumber(value) or 0) / 100, 0, 1)
	local lowR, lowG, lowB = 0.92, 0.18, 0.18
	local highR, highG, highB = 0.18, 0.84, 0.18
	local r = lowR + ((highR - lowR) * t)
	local g = lowG + ((highG - lowG) * t)
	local b = lowB + ((highB - lowB) * t)
	return r, g, b
end

function NpcInspector.Attach(opts)
	if type(opts) ~= "table" then
		return nil
	end

	local parent = opts.parent
	local hudLayer = opts.hudLayer or parent
	if not (parent and hudLayer) then
		return nil
	end

	local cfg = type(opts.cfg) == "table" and opts.cfg or {}
	local onIntentRightClick = type(opts.onIntentRightClick) == "function" and opts.onIntentRightClick or nil
	local anchor = tostring(cfg.anchor or "BOTTOMRIGHT")
	local offsetX = tonumber(cfg.offsetX) or -16
	local offsetY = tonumber(cfg.offsetY) or 16
	local intentSlotMax = 12
	local refreshInterval = Clamp(tonumber(cfg.refreshInterval) or 0.10, 0.04, 0.80)
	local frameLevelOffset = math.floor(tonumber(cfg.frameLevelOffset) or 14)

	local E = {
		selectedId = nil,
		refreshElapsed = 0,
		refreshInterval = refreshInterval,
		snapshotById = {},
		lastIntentNpcId = nil,
		lastIntentStateKey = nil,
	}

	local panel = CreateFrame("Frame", nil, hudLayer, "BackdropTemplate")
	panel:SetSize(286, 206)
	panel:SetPoint(anchor, parent, anchor, offsetX, offsetY)
	panel:SetFrameStrata(parent:GetFrameStrata())
	panel:SetFrameLevel((hudLayer:GetFrameLevel() or parent:GetFrameLevel() or 1) + frameLevelOffset)
	panel:EnableMouse(false)
	panel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0.01, 0.01, 0.01, 0.92)
	panel:Hide()
	E.panel = panel

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
	title:SetJustifyH("LEFT")
	title:SetText("-")
	E.title = title

	local npcName = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	npcName:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -30)
	npcName:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -30)
	npcName:SetJustifyH("LEFT")
	npcName:SetText("-")
	E.npcName = npcName

	local intentStrip = CreateFrame("Frame", nil, hudLayer)
	intentStrip:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -10)
	intentStrip:SetSize(562, 45)
	intentStrip:SetFrameStrata(parent:GetFrameStrata())
	intentStrip:SetFrameLevel((hudLayer:GetFrameLevel() or parent:GetFrameLevel() or 1) + frameLevelOffset + 2)
	intentStrip:EnableMouse(true)
	intentStrip:Hide()
	E.intentStrip = intentStrip

	local intentSlots = {}
	for i = 1, intentSlotMax do
		local slot = CreateFrame("Button", nil, intentStrip)
		local slotPositionX = (i - 1) * 47
		local slotPositionY = 0
		slot:SetSize(45, 45)
		slot:SetPoint("TOPLEFT", intentStrip, "TOPLEFT", slotPositionX, slotPositionY)

		slot.bg = slot:CreateTexture(nil, "ARTWORK", nil, 1)
		slot.bg:SetSize(45, 45)
		slot.bg:SetPoint("CENTER", slot, "CENTER", 0, 0)
		SetTextureOrAtlas(slot.bg, INTENT_SLOT_ATLAS, INTENT_SLOT_TEXTURE)
		slot.bg:SetVertexColor(1, 1, 1, 0.95)

		slot.icon = slot:CreateTexture(nil, "ARTWORK", nil, 2)
		slot.icon:SetSize(45, 45)
		slot.icon:SetPoint("CENTER", slot, "CENTER", 0, 0)
		slot.icon:SetTexture(INTENT_ICON_FALLBACK)

		slot.iconMask = slot:CreateMaskTexture(nil, "ARTWORK")
		slot.iconMask:SetSize(37, 37)
		slot.iconMask:SetPoint("CENTER", slot, "CENTER", 0, 0)
		slot.iconMask:SetTexture(INTENT_ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		slot.icon:AddMaskTexture(slot.iconMask)

		slot.frame = slot:CreateTexture(nil, "OVERLAY", nil, 7)
		slot.frame:SetSize(50, 50)
		slot.frame:SetPoint("CENTER", slot, "CENTER", 3, -3)
		SetTextureOrAtlas(slot.frame, INTENT_ROW_ATLAS, INTENT_ROW_TEXTURE)
		slot.frame:SetVertexColor(1, 1, 1, 1)

		slot.highlight = slot:CreateTexture(nil, "OVERLAY", nil, 2)
		slot.highlight:SetSize(45, 45)
		slot.highlight:SetPoint("CENTER", slot, "CENTER", 0, 0)
		SetTextureOrAtlas(slot.highlight, INTENT_HIGHLIGHT_ATLAS, INTENT_HIGHLIGHT_TEXTURE)
		slot.highlight:SetVertexColor(1, 1, 1, 0.95)
		slot.highlight:SetBlendMode("ADD")
		slot.highlight:Hide()
		slot._intentIndex = i
		slot._intentEntry = nil
		slot:EnableMouse(true)
		slot:RegisterForClicks("RightButtonUp")
		slot:SetScript("OnClick", function(self, button)
			if button ~= "RightButton" then
				return
			end
			if not onIntentRightClick then
				return
			end
			local entry = self._intentEntry
			if type(entry) ~= "table" or entry.cancelable == false then
				return
			end
			local selectedId = tostring(E.selectedId or "")
			if selectedId == "" then
				return
			end
			onIntentRightClick(selectedId, self._intentIndex, entry)
		end)
		slot:SetScript("OnEnter", function(self)
			local entry = self._intentEntry
			if type(entry) ~= "table" then
				return
			end
			if not GameTooltip then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:ClearLines()

			local title = tostring(entry.label or "Action")
			GameTooltip:AddLine(title, 1.00, 0.82, 0.20)

			local isCurrent = entry.current == true
			GameTooltip:AddLine(isCurrent and "En cours" or "En attente", 0.90, 0.90, 0.90)

			local source = tostring(entry.source or "")
			if source == "player" then
				GameTooltip:AddLine("Source: Joueur", 0.65, 0.95, 0.65)
			elseif source == "auto" then
				GameTooltip:AddLine("Source: Auto", 0.75, 0.85, 1.00)
			elseif source ~= "" and source ~= "state" then
				GameTooltip:AddLine("Source: " .. source, 0.75, 0.85, 1.00)
			end

			if entry.cancelable == true then
				GameTooltip:AddLine("Clic droit: annuler", 1.00, 0.30, 0.30)
			else
				GameTooltip:AddLine("Non annulable", 0.65, 0.65, 0.65)
			end
			GameTooltip:Show()
		end)
		slot:SetScript("OnLeave", function()
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)

		slot:Hide()
		intentSlots[i] = slot
	end
	E.intentSlots = intentSlots
	E.intentSlotMax = intentSlotMax

	local rows = {}
	for i = 1, #NEED_ORDER do
		local spec = NEED_ORDER[i]
		local yOffset = -54 - ((i - 1) * 34)
		rows[spec.key] = CreateNeedRow(panel, yOffset, spec.label)
	end
	E.rows = rows

	local function UpdateRow(key, value)
		local row = rows[key]
		if not row then
			return
		end
		local v = Clamp(tonumber(value) or 0, 0, 100)
		local t = v / 100
		local r, g, b = GetNeedReserveColor(v)
		row.bar:SetStatusBarColor(r, g, b, 1.0)
		row.bar:SetValue(v)
		if row.pip then
			row.pip:SetVertexColor(r, g, b, 1.0)
			local width = row.bar:GetWidth() or 0
			if width <= 0 and row.bg then
				width = row.bg:GetWidth() or 0
			end
			local x = width * t
			row.pip:ClearAllPoints()
			row.pip:SetPoint("CENTER", row.bar, "LEFT", x, 0)
		end
	end

	local function RefreshIntentStrip(npc)
		if type(npc) ~= "table" then
			intentStrip:Hide()
			for i = 1, #intentSlots do
				intentSlots[i]._intentEntry = nil
				intentSlots[i]:EnableMouse(false)
				intentSlots[i]:Hide()
			end
			return
		end

		local intents = type(npc.intentions) == "table" and npc.intentions or {}
		local shown = math.min(E.intentSlotMax or #intentSlots, #intents)
		for i = 1, shown do
			local slot = intentSlots[i]
			local entry = intents[i]
			local iconValue = entry and entry.icon or nil
			local resolvedIcon = nil
			if type(iconValue) == "number" then
				local fileId = math.floor(iconValue + 0.5)
				if fileId > 0 then
					resolvedIcon = fileId
				end
			elseif type(iconValue) == "string" then
				local raw = iconValue:gsub("^%s+", ""):gsub("%s+$", "")
				if raw ~= "" then
					if raw:match("^%d+$") then
						local fileId = math.floor(tonumber(raw) or 0)
						if fileId > 0 then
							resolvedIcon = fileId
						end
					else
						resolvedIcon = raw
					end
				end
			end
			if resolvedIcon ~= nil then
				slot.icon:SetTexture(resolvedIcon)
			else
				slot.icon:SetTexture(INTENT_ICON_FALLBACK)
			end
			local isCurrent = (entry and entry.current) == true
			if isCurrent then
				slot.highlight:Show()
			else
				slot.highlight:Hide()
			end
			slot._intentEntry = entry
			slot:EnableMouse(true)
			slot:Show()
		end
		for i = shown + 1, #intentSlots do
			intentSlots[i]._intentEntry = nil
			intentSlots[i]:EnableMouse(false)
			intentSlots[i]:Hide()
		end
		if shown > 0 then
			intentStrip:Show()
		else
			intentStrip:Hide()
		end
	end

	local function BuildIntentStateKey(npc)
		if type(npc) ~= "table" then
			return "none"
		end
		local parts = { tostring(npc.id or ""), ":" }
		local intents = type(npc.intentions) == "table" and npc.intentions or {}
		parts[#parts + 1] = tostring(#intents)
		for i = 1, #intents do
			local row = intents[i]
			parts[#parts + 1] = ";"
			parts[#parts + 1] = tostring(row and row.label or "")
			parts[#parts + 1] = "|"
			parts[#parts + 1] = tostring(row and row.icon or "")
			parts[#parts + 1] = "|"
			parts[#parts + 1] = ((row and row.current) == true) and "1" or "0"
			parts[#parts + 1] = "|"
			parts[#parts + 1] = tostring(row and row.source or "")
			parts[#parts + 1] = "|"
			parts[#parts + 1] = tostring(row and row.kind or "")
			parts[#parts + 1] = "|"
			parts[#parts + 1] = tostring(row and row.purpose or "")
			parts[#parts + 1] = "|"
			parts[#parts + 1] = tostring(row and row.queueIndex or "")
			parts[#parts + 1] = "|"
			parts[#parts + 1] = ((row and row.cancelable) == false) and "0" or "1"
		end
		return table.concat(parts)
	end

	function E:ClearSelection()
		self.selectedId = nil
		self.panel:Hide()
		RefreshIntentStrip(nil)
		self.lastIntentNpcId = nil
		self.lastIntentStateKey = nil
	end

	function E:GetSelectedId()
		return self.selectedId
	end

	function E:GetSelectedNpc()
		if not self.selectedId then
			return nil
		end
		return self.snapshotById[self.selectedId]
	end

	function E:SetSelectedById(id)
		if type(id) ~= "string" or id == "" then
			self:ClearSelection()
			return false
		end
		self.selectedId = id
		self:RefreshNow()
		return true
	end

	function E:RefreshNow()
		if not self.selectedId then
			self.panel:Hide()
			RefreshIntentStrip(nil)
			return
		end

		local npc = self.snapshotById[self.selectedId]
		if type(npc) ~= "table" then
			self.panel:Hide()
			RefreshIntentStrip(nil)
			self.lastIntentNpcId = nil
			self.lastIntentStateKey = nil
			return
		end

		local nameText = tostring(npc.name or "-")
		local orderLabel = "-"
		local intents = type(npc.intentions) == "table" and npc.intentions or {}
		if #intents > 0 then
			local preview = nil
			for i = 1, #intents do
				local row = intents[i]
				if type(row) == "table" and row.current ~= true then
					preview = row
					break
				end
			end
			if not preview then
				preview = intents[1]
			end
			local label = preview and tostring(preview.label or "") or ""
			if label ~= "" then
				orderLabel = label
			end
		end
		if self.title then
			self.title:SetText(nameText)
		end
		self.npcName:SetText(orderLabel)

		local needs = type(npc.needs) == "table" and npc.needs or {}
		for i = 1, #NEED_ORDER do
			local spec = NEED_ORDER[i]
			UpdateRow(spec.key, needs[spec.key])
		end

		self.panel:Show()
		local intentStateKey = BuildIntentStateKey(npc)
		if self.lastIntentNpcId ~= self.selectedId or self.lastIntentStateKey ~= intentStateKey then
			RefreshIntentStrip(npc)
			self.lastIntentNpcId = self.selectedId
			self.lastIntentStateKey = intentStateKey
		end
	end

	function E:UpdateFromSnapshot(snapshotPayload, elapsed)
		if elapsed and elapsed > 0 then
			self.refreshElapsed = self.refreshElapsed + elapsed
			if self.refreshElapsed < self.refreshInterval then
				return
			end
			self.refreshElapsed = 0
		end

		local byId = {}
		if type(snapshotPayload) == "table" then
			local singleId = tostring(snapshotPayload.id or "")
			if singleId ~= "" then
				byId[singleId] = snapshotPayload
			else
				for i = 1, #snapshotPayload do
					local row = snapshotPayload[i]
					local id = tostring(row and row.id or "")
					if id ~= "" then
						byId[id] = row
					end
				end
			end
		end
		self.snapshotById = byId
		self:RefreshNow()
	end

	return E
end

return NpcInspector
