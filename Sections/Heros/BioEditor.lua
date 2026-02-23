local ADDON, ns = ...

local M = ns.HerosSection

function M.BuildBioEditor(ctx, bioEdit, bioEditSide)
	local ns = ctx.ns
	local HU = ctx.HU
	local DB = ctx.DB
	local Comms = ctx.Comms
	local state = ctx.state
	local ui = ctx.ui
	local fn = ctx.fn
	local Prefs = ns and ns.Prefs or nil
	local BioRules = ns.BioRules or {}

	local RenderMarkdown = fn.Bio_RenderMarkdown or function(v)
		return tostring(v or "")
	end
	local StripMarkdown = fn.Bio_StripMarkdown or function(v)
		return tostring(v or "")
	end

	local editor = {}
	local previewScroll = nil
	local bodyScroll = nil
	local bodyScrollFake = nil
	local activeBioItem = nil
	local editTarget = nil

	local function EmitGuildRosterUpdate()
		if ns and ns.EventBus and ns.EventBus.Emit then
			ns.EventBus.Emit("GUILD_ROSTER_UPDATE")
		end
	end

	local function CopyTable(src)
		local out = {}
		for k, v in pairs(src or {}) do
			out[k] = v
		end
		return out
	end

	local function IsPublicPublished(b)
		if BioRules and BioRules.IsPublicPublished then
			return BioRules.IsPublicPublished(b)
		end
		local vis = (b and b.visibility ~= "" and b.visibility) or "public"
		local delAt = tonumber(b and b.deletedAt or 0) or 0
		return type(b) == "table"
			and b.status == "published"
			and vis ~= "private"
			and not (delAt > 0 and delAt > time())
	end

	local function NormalizeFeatured(gid, uid, activeKey, skipAutoGeneral)
		local prefs = DB and DB.GetGuildMemberPrefs and DB:GetGuildMemberPrefs(gid, uid) or nil
		local map = prefs and prefs.biographie or nil
		if type(map) ~= "table" then
			return
		end

		local now = time()
		local payload = {}
		local changed = false
		local keepKey = nil
		local keepAt = -1

		for k, v in pairs(map) do
			if type(v) == "table" and v.featured == true then
				if not IsPublicPublished(v) then
					local copy = CopyTable(v)
					copy.featured = nil
					copy.updatedAt = now
					payload[k] = copy
					changed = true
				else
					local t = tonumber(v.updatedAt or v.createdAt or 0) or 0
					if t > keepAt then
						keepAt = t
						keepKey = k
					end
				end
			end
		end

		-- Si plusieurs "featured" valides, on garde le plus récent.
		if keepKey then
			for k, v in pairs(map) do
				if type(v) == "table" and v.featured == true and k ~= keepKey and IsPublicPublished(v) then
					local copy = CopyTable(v)
					copy.featured = nil
					copy.updatedAt = now
					payload[k] = copy
					changed = true
				end
			end
		elseif not skipAutoGeneral then
			local general = map["__general__"]
			if IsPublicPublished(general) and general.featured ~= true then
				local copy = CopyTable(general)
				copy.featured = true
				copy.updatedAt = now
				payload["__general__"] = copy
				changed = true
				keepKey = "__general__"
			end
		end

		if not changed then
			return
		end

		if DB and DB.UpsertGuildMemberPrefs then
			DB:UpsertGuildMemberPrefs(gid, uid, { biographie = payload, updatedAt = now })
		end
		if Comms and Comms.SendGuildMemberPrefs then
			Comms:SendGuildMemberPrefs(gid, uid, { biographie = payload, updatedAt = now })
		end
		if activeKey and editTarget and editTarget.full == activeKey and editTarget.bio then
			editTarget.bio.featured = (keepKey == activeKey) and true or nil
		end
		if ui.profile and ui.profile.BioSide_Rebuild then
			ui.profile:BioSide_Rebuild()
		end
		EmitGuildRosterUpdate()
	end

	local bioEditMain = CreateFrame("Frame", "WoWGuilde_BioEditMain", bioEdit)
	bioEditMain:SetPoint("TOPLEFT", bioEdit, "TOPLEFT", 20, -95)
	bioEditMain:SetPoint("BOTTOMRIGHT", bioEditSide, "BOTTOMLEFT", -5, 20)
	ui.profile.bioEditMain = bioEditMain

	bioEditMain.bg = bioEditMain:CreateTexture(nil, "BACKGROUND")
	bioEditMain.bg:SetAllPoints(bioEditMain)
	bioEditMain.bg:SetAtlas("spellbook-background-evergreen-right")
	bioEditMain.bg:SetVertexColor(0.38, 0.38, 0.38, 1)
	bioEditMain.bg:SetAlpha(1)

	local editorPanel = CreateFrame("Frame", "WoWGuilde_BioEditorPanel", bioEditMain)
	editorPanel:SetAllPoints(bioEditMain)

	local previewPanel = CreateFrame("Frame", "WoWGuilde_BioPreviewPanel", bioEditMain)
	previewPanel:SetAllPoints(bioEditMain)
	previewPanel:Hide()

	editor._editMode = true
	editor._ratioMode = false
	if Prefs and Prefs.GetHeros then
		local viewMode = Prefs.GetHeros("bioEditorView", "edit")
		if viewMode == "double" then
			editor._ratioMode = true
			editor._editMode = true
		else
			editor._ratioMode = false
			editor._editMode = true
		end
	end

	local function UpdatePreviewScrollMode()
		if previewScroll then
			local sb = previewScroll.ScrollBar
			if sb then
				sb:SetShown(true)
				sb:EnableMouse(true)
			end
			previewScroll:EnableMouse(true)
		end
		if bodyScroll then
			local sb = bodyScroll.ScrollBar
			if sb then
				sb:SetShown(not editor._ratioMode)
				sb:EnableMouse(not editor._ratioMode)
			end
			if bodyScrollFake then
				bodyScrollFake:SetShown(editor._ratioMode)
				if editor._ratioMode then
					bodyScrollFake:ClearAllPoints()
					bodyScrollFake:SetPoint("TOPRIGHT", bodyScroll, "TOPRIGHT", 35, 0)
					bodyScrollFake:SetPoint("BOTTOMRIGHT", bodyScroll, "BOTTOMRIGHT", 35, 0)
					bodyScrollFake:SetWidth(3)
				end
			end
		end
	end

	local function ApplyLayout()
		editorPanel:ClearAllPoints()
		previewPanel:ClearAllPoints()
		if editor._ratioMode then
			editorPanel:SetPoint("TOPLEFT", bioEditMain, "TOPLEFT", 0, 0)
			editorPanel:SetPoint("BOTTOMLEFT", bioEditMain, "BOTTOMLEFT", 0, 0)
			editorPanel:SetPoint("RIGHT", bioEditMain, "CENTER", 0, 0)
			previewPanel:SetPoint("TOPRIGHT", bioEditMain, "TOPRIGHT", 0, 0)
			previewPanel:SetPoint("BOTTOMRIGHT", bioEditMain, "BOTTOMRIGHT", -4, 0)
			previewPanel:SetPoint("LEFT", bioEditMain, "CENTER", 2, 0)
			editorPanel:Show()
			previewPanel:Show()
		else
			editorPanel:SetAllPoints(bioEditMain)
			previewPanel:SetAllPoints(bioEditMain)
			editorPanel:SetShown(editor._editMode)
			previewPanel:SetShown(not editor._editMode)
		end
		UpdatePreviewScrollMode()
		if editor._UpdatePresetsVisibility then
			editor._UpdatePresetsVisibility()
		end
	end

	local optionsBtn = CreateFrame("Button", "WoWGuilde_BioOptionsDropdown", bioEditMain)
	optionsBtn:SetSize(35, 35)
	optionsBtn:SetPoint("TOPRIGHT", bioEditMain, "TOPRIGHT", -30, -20)
	if ui and ui.profile then
		ui.profile.bioEditorOptionsBtn = optionsBtn
	end

	optionsBtn.icon = optionsBtn:CreateTexture(nil, "ARTWORK")
	optionsBtn.icon:SetAllPoints(optionsBtn)
	optionsBtn.icon:SetAtlas("GM-icon-settings")
	optionsBtn.icon:SetVertexColor(1, 0.9, 0.6, 1)
	optionsBtn.pushed = optionsBtn:CreateTexture(nil, "ARTWORK")
	optionsBtn.pushed:SetAllPoints(optionsBtn)
	optionsBtn.pushed:SetAtlas("GM-icon-settings")
	optionsBtn.pushed:SetVertexColor(0.85, 0.75, 0.5, 1)
	optionsBtn:SetPushedTexture(optionsBtn.pushed)
	optionsBtn.highlight = optionsBtn:CreateTexture(nil, "HIGHLIGHT")
	optionsBtn.highlight:SetAllPoints(optionsBtn)
	optionsBtn.highlight:SetAtlas("GM-icon-settings")
	optionsBtn.highlight:SetBlendMode("ADD")
	optionsBtn.highlight:SetAlpha(0.35)
	optionsBtn:SetScript("OnEnter", function(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Ayarlar")
			GameTooltip:Show()
		end
	end)
	optionsBtn:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)

	local presetsBtn = CreateFrame("Button", "WoWGuilde_BioMarkdownPresets", bioEditMain)
	presetsBtn:SetSize(14, 14)
	presetsBtn:SetPoint("TOPRIGHT", optionsBtn, "TOPLEFT", 0, -10)
	if ui and ui.profile then
		ui.profile.bioEditorMarkdownBtn = presetsBtn
	end

	presetsBtn.icon = presetsBtn:CreateTexture(nil, "ARTWORK")
	presetsBtn.icon:SetAllPoints(presetsBtn)
	presetsBtn.icon:SetAtlas("common-icon-plus")
	presetsBtn.icon:SetDesaturated(true)
	presetsBtn.icon:SetVertexColor(1, 0.902, 0.6, 1)
	presetsBtn.pushed = presetsBtn:CreateTexture(nil, "ARTWORK")
	presetsBtn.pushed:SetAllPoints(presetsBtn)
	presetsBtn.pushed:SetAtlas("common-icon-plus")
	presetsBtn.pushed:SetDesaturated(true)
	presetsBtn.pushed:SetVertexColor(1, 0.902, 0.6, 1)
	presetsBtn:SetPushedTexture(presetsBtn.pushed)
	presetsBtn.highlight = presetsBtn:CreateTexture(nil, "HIGHLIGHT")
	presetsBtn.highlight:SetAllPoints(presetsBtn)
	presetsBtn.highlight:SetAtlas("common-icon-plus")
	presetsBtn.highlight:SetDesaturated(true)
	presetsBtn.highlight:SetVertexColor(1, 0.902, 0.6, 1)
	presetsBtn.highlight:SetBlendMode("ADD")
	presetsBtn.highlight:SetAlpha(0.35)
	presetsBtn:SetScript("OnEnter", function(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Hazir ayarlar")
			GameTooltip:Show()
		end
	end)
	presetsBtn:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	local function UpdatePresetsVisibility()
		if editor._ratioMode or editor._editMode then
			presetsBtn:SetShown(optionsBtn:IsShown())
		else
			presetsBtn:Hide()
		end
	end
	editor._UpdatePresetsVisibility = UpdatePresetsVisibility
	UpdatePresetsVisibility()
	optionsBtn:HookScript("OnShow", UpdatePresetsVisibility)
	optionsBtn:HookScript("OnHide", UpdatePresetsVisibility)

	local titleBox = CreateFrame("EditBox", "WoWGuilde_BioTitleBox", editorPanel)
	titleBox:SetAutoFocus(false)
	titleBox:SetMaxLetters(64)
	titleBox:SetFontObject("GameFontNormalLarge")
	titleBox:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 25, -30)
	titleBox:SetSize(160, 24)
	titleBox:SetHeight(24)
	titleBox:SetTextInsets(0, 0, 0, 0)
	titleBox:SetJustifyH("LEFT")

	local titleMeasure = editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	titleMeasure:Hide()

	local titlePlaceholder = "Baslik (duzenlemek icin tikla)"
	local titleIsPlaceholder = true
	local titleEditing = false
	local titleAtMax = false
	local titleLastLen = 0
	local titleMaxSoundAt = 0
	local TITLE_MAX_COLOR = { 1, 0.2, 0.2, 1 }
	local TITLE_NORMAL_COLOR = { 1, 0.95, 0.8, 1 }
	local titleFlashTicker = nil
	local function FlashMax(editBox)
		if not editBox or not editBox.SetTextColor then
			return
		end
		if titleFlashTicker and titleFlashTicker.Cancel then
			titleFlashTicker:Cancel()
			titleFlashTicker = nil
		end
		editBox:SetTextColor(TITLE_MAX_COLOR[1], TITLE_MAX_COLOR[2], TITLE_MAX_COLOR[3], TITLE_MAX_COLOR[4])
		local steps = 20
		local duration = 0.8
		local step = duration / steps
		local i = 0
		titleFlashTicker = C_Timer.NewTicker(step, function()
			if titleIsPlaceholder then
				if titleFlashTicker and titleFlashTicker.Cancel then
					titleFlashTicker:Cancel()
					titleFlashTicker = nil
				end
				return
			end
			i = i + 1
			local t = i / steps
			local r = TITLE_MAX_COLOR[1] + (TITLE_NORMAL_COLOR[1] - TITLE_MAX_COLOR[1]) * t
			local g = TITLE_MAX_COLOR[2] + (TITLE_NORMAL_COLOR[2] - TITLE_MAX_COLOR[2]) * t
			local b = TITLE_MAX_COLOR[3] + (TITLE_NORMAL_COLOR[3] - TITLE_MAX_COLOR[3]) * t
			local a = TITLE_MAX_COLOR[4] + (TITLE_NORMAL_COLOR[4] - TITLE_MAX_COLOR[4]) * t
			editBox:SetTextColor(r, g, b, a)
			if i >= steps and titleFlashTicker and titleFlashTicker.Cancel then
				titleFlashTicker:Cancel()
				titleFlashTicker = nil
			end
		end)
	end

	local function PlayMaxSound()
		if PlaySoundFile then
			PlaySoundFile(567415, "SFX")
		elseif ns and ns.PlaySoundFile then
			ns.PlaySoundFile(567415)
		end
	end

	local function Title_SetPlaceholder()
		titleIsPlaceholder = true
		titleBox:SetText(titlePlaceholder)
		titleBox:SetTextColor(0.7, 0.7, 0.7, 1)
	end

	local function Title_SetText(value)
		local text = tostring(value or "")
		if text == "" then
			Title_SetPlaceholder()
			return
		end
		titleIsPlaceholder = false
		titleBox:SetText(text)
		titleBox:SetTextColor(
			TITLE_NORMAL_COLOR[1],
			TITLE_NORMAL_COLOR[2],
			TITLE_NORMAL_COLOR[3],
			TITLE_NORMAL_COLOR[4]
		)
	end

	local function Title_GetMaxWidth()
		local maxW = (editorPanel:GetWidth() or 0) - 24
		if maxW < 10 then
			maxW = 10
		end
		return maxW
	end

	local function Title_UpdateWidth()
		local measureText = titleIsPlaceholder and titlePlaceholder or (titleBox:GetText() or "")
		titleMeasure:SetText(measureText)
		local w = (titleMeasure:GetStringWidth() or 0) + 2
		local maxW = Title_GetMaxWidth()
		if w < 24 then
			w = 24
		elseif w > maxW then
			w = maxW
		end
		titleBox:SetWidth(w)
	end

	local titleWidthPending = false
	local function Title_ScheduleWidthUpdate()
		if titleWidthPending or not (C_Timer and C_Timer.After) then
			return
		end
		titleWidthPending = true
		C_Timer.After(0, function()
			titleWidthPending = false
			Title_UpdateWidth()
		end)
	end

	local AutoSaveBio

	titleBox:SetScript("OnEditFocusGained", function(self)
		if titleIsPlaceholder then
			self:SetText("")
			titleIsPlaceholder = false
		end
		titleEditing = true
		Title_UpdateWidth()
		Title_ScheduleWidthUpdate()
	end)
	titleBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	titleBox:SetScript("OnEditFocusLost", function(self)
		local current = tostring(self:GetText() or "")
		if current == "" then
			Title_SetPlaceholder()
		else
			titleIsPlaceholder = false
			titleBox:SetTextColor(1, 0.95, 0.8, 1)
		end
		self:SetCursorPosition(0)
		titleEditing = false
		Title_UpdateWidth()
		if editor and editor.UpdatePreview then
			editor.UpdatePreview()
		end
		AutoSaveBio()
	end)
	titleBox:SetScript("OnTextChanged", function()
		if not titleEditing then
			return
		end
		Title_UpdateWidth()
		Title_ScheduleWidthUpdate()
		if editor and editor._ratioMode and editor.UpdatePreview then
			editor.UpdatePreview()
		end
		if not titleIsPlaceholder then
			local maxLetters = titleBox:GetMaxLetters() or 0
			local len = #(titleBox:GetText() or "")
			if maxLetters > 0 and len >= maxLetters and titleLastLen < maxLetters then
				titleAtMax = true
				FlashMax(titleBox)
				local now = GetTime and GetTime() or 0
				if now - titleMaxSoundAt > 0.2 then
					titleMaxSoundAt = now
					PlayMaxSound()
				end
			elseif len < maxLetters then
				titleAtMax = false
			end
			titleLastLen = len
		end
	end)
	titleBox:SetScript("OnKeyDown", function(self, key)
		if titleIsPlaceholder then
			return
		end
		if IsModifierKeyDown and IsModifierKeyDown() then
			return
		end
		local ignoreKeys = {
			LSHIFT = true,
			RSHIFT = true,
			LCTRL = true,
			RCTRL = true,
			LALT = true,
			RALT = true,
		}
		if ignoreKeys[key] then
			return
		end
		local maxLetters = self:GetMaxLetters() or 0
		if maxLetters <= 0 then
			return
		end
		local len = #(self:GetText() or "")
		if len < maxLetters then
			return
		end
		local ignore = {
			BACKSPACE = true,
			DELETE = true,
			LEFT = true,
			RIGHT = true,
			UP = true,
			DOWN = true,
			HOME = true,
			END = true,
			PAGEUP = true,
			PAGEDOWN = true,
			ENTER = true,
			ESCAPE = true,
			TAB = true,
		}
		if ignore[key] then
			return
		end
		local now = GetTime and GetTime() or 0
		if now - titleMaxSoundAt > 0.2 then
			titleMaxSoundAt = now
			FlashMax(titleBox)
			PlayMaxSound()
		end
	end)
	editorPanel:SetScript("OnSizeChanged", function()
		Title_UpdateWidth()
	end)

	Title_SetPlaceholder()
	Title_UpdateWidth()

	bodyScroll = CreateFrame("ScrollFrame", "WoWGuilde_BioBodyScroll", editorPanel, "QuestScrollFrameTemplate")
	bodyScroll:SetPoint("TOPLEFT", titleBox, "BOTTOMLEFT", 0, -20)
	bodyScroll:SetPoint("BOTTOMRIGHT", editorPanel, "BOTTOMRIGHT", -60, 20)
	bodyScroll:EnableMouse(true)
	bodyScroll:EnableMouseWheel(true)

	local bodyBox = CreateFrame("EditBox", "WoWGuilde_BioBodyBox", bodyScroll)
	bodyBox:SetMultiLine(true)
	bodyBox:SetFontObject("ChatFontNormal")
	bodyBox:SetWidth(1)
	bodyBox:SetAutoFocus(false)
	bodyBox:SetTextInsets(8, 8, 8, 8)
	bodyBox:SetMaxLetters(4096)
	bodyBox:SetScript("OnMouseDown", function()
		bodyBox:SetFocus()
	end)
	bodyBox:SetScript("OnTextChanged", function(self)
		self:GetParent():UpdateScrollChildRect()
		local maxLetters = self:GetMaxLetters() or 0
		if maxLetters > 0 then
			local len = #(self:GetText() or "")
			if len >= maxLetters then
				PlayMaxSound()
				FlashMax(self)
			end
		end
	end)
	bodyBox:SetScript("OnKeyDown", function(self, key)
		if IsModifierKeyDown and IsModifierKeyDown() then
			return
		end
		local ignore = {
			BACKSPACE = true,
			DELETE = true,
			LEFT = true,
			RIGHT = true,
			UP = true,
			DOWN = true,
			HOME = true,
			END = true,
			PAGEUP = true,
			PAGEDOWN = true,
			ENTER = true,
			ESCAPE = true,
			TAB = true,
			LSHIFT = true,
			RSHIFT = true,
			LCTRL = true,
			RCTRL = true,
			LALT = true,
			RALT = true,
		}
		if ignore[key] then
			return
		end
		local maxLetters = self:GetMaxLetters() or 0
		if maxLetters > 0 and #(self:GetText() or "") >= maxLetters then
			PlayMaxSound()
			FlashMax(self)
		end
	end)
	bodyScroll:SetScrollChild(bodyBox)
	bodyScroll:SetScript("OnMouseDown", function()
		bodyBox:SetFocus()
	end)
	local syncing = false
	local function UpdateScrollBar(scrollFrame, offset)
		local sb = scrollFrame and scrollFrame.ScrollBar
		if not sb then
			return
		end
		if sb.SetValue then
			sb:SetValue(offset)
			return
		end
		if sb.SetScrollPercentage then
			local range = scrollFrame:GetVerticalScrollRange() or 0
			local pct = 0
			if range > 0 then
				pct = offset / range
				if pct < 0 then
					pct = 0
				elseif pct > 1 then
					pct = 1
				end
			end
			sb:SetScrollPercentage(pct)
		end
	end
	local function SyncBodyScroll(offset)
		if not editor._ratioMode or not previewScroll then
			return
		end
		if syncing then
			return
		end
		syncing = true
		local pRange = previewScroll:GetVerticalScrollRange() or 0
		local bRange = bodyScroll:GetVerticalScrollRange() or 0
		if pRange <= 0 or bRange <= 0 then
			bodyScroll:SetVerticalScroll(0)
			UpdateScrollBar(bodyScroll, 0)
		else
			local pct = offset / pRange
			if pct < 0 then
				pct = 0
			elseif pct > 1 then
				pct = 1
			end
			local next = pct * bRange
			bodyScroll:SetVerticalScroll(next)
			UpdateScrollBar(bodyScroll, next)
		end
		syncing = false
	end
	local function SyncPreviewScroll(offset)
		if not editor._ratioMode or not previewScroll then
			return
		end
		if syncing then
			return
		end
		syncing = true
		local pRange = previewScroll:GetVerticalScrollRange() or 0
		local bRange = bodyScroll:GetVerticalScrollRange() or 0
		local next = 0
		if pRange <= 0 or bRange <= 0 then
			next = 0
		else
			local pct = offset / bRange
			if pct < 0 then
				pct = 0
			elseif pct > 1 then
				pct = 1
			end
			next = pct * pRange
		end
		previewScroll:SetVerticalScroll(next)
		UpdateScrollBar(previewScroll, next)
		syncing = false
	end
	local bodyOnVerticalScroll = bodyScroll:GetScript("OnVerticalScroll")
	bodyScroll:SetScript("OnVerticalScroll", function(self, offset)
		if bodyOnVerticalScroll then
			bodyOnVerticalScroll(self, offset)
		else
			self:SetVerticalScroll(offset)
		end
		UpdateScrollBar(self, offset)
		SyncPreviewScroll(offset)
	end)
	local bodyOnMouseWheel = bodyScroll:GetScript("OnMouseWheel")
	bodyScroll:SetScript("OnMouseWheel", function(self, delta)
		local next = nil
		if bodyOnMouseWheel then
			bodyOnMouseWheel(self, delta)
			next = self:GetVerticalScroll() or 0
		else
			local cur = self:GetVerticalScroll() or 0
			local range = self:GetVerticalScrollRange() or 0
			local step = 20
			next = cur - (delta * step)
			if next < 0 then
				next = 0
			elseif next > range then
				next = range
			end
			self:SetVerticalScroll(next)
		end
		UpdateScrollBar(self, next)
		SyncPreviewScroll(next)
	end)
	bodyScroll:SetScript("OnSizeChanged", function()
		local w = bodyScroll:GetWidth() or 0
		if w > 0 then
			bodyBox:SetWidth(w - 20)
		end
	end)
	bodyScrollFake = bodyScroll:CreateTexture(nil, "BORDER")
	bodyScrollFake:SetAtlas("combattimeline-line-shadow-vertical", false)
	bodyScrollFake:SetVertexColor(1, 1, 1, 0.356)
	bodyScrollFake:Hide()

	local statusLabel = editorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusLabel:SetPoint("TOPLEFT", titleBox, "BOTTOMLEFT", 0, 2)
	statusLabel:SetTextColor(0.8, 0.8, 0.8, 1)
	statusLabel:SetText("Destan secilmedi")

	local previewTitleText =
		previewPanel:CreateFontString("WoWGuilde_BioPreviewTitleText", "OVERLAY", "GameFontNormalLarge")
	previewTitleText:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 25, -30)
	previewTitleText:SetPoint("RIGHT", previewPanel, "RIGHT", -60, 0)
	previewTitleText:SetSize(0, 24)
	previewTitleText:SetJustifyH("LEFT")
	previewTitleText:SetText("Onizleme")

	previewScroll = CreateFrame("ScrollFrame", "WoWGuilde_BioPreviewScroll", previewPanel, "QuestScrollFrameTemplate")
	previewScroll:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 20, -64)
	previewScroll:SetPoint("BOTTOMRIGHT", previewPanel, "BOTTOMRIGHT", -60, 20)

	local previewContent = CreateFrame("Frame", "WoWGuilde_BioPreviewContent", previewScroll)
	previewContent:SetSize(1, 1)
	previewScroll:SetScrollChild(previewContent)
	previewScroll:EnableMouseWheel(true)
	local previewOnVerticalScroll = previewScroll:GetScript("OnVerticalScroll")
	previewScroll:SetScript("OnVerticalScroll", function(self, offset)
		if previewOnVerticalScroll then
			previewOnVerticalScroll(self, offset)
		else
			self:SetVerticalScroll(offset)
		end
		UpdateScrollBar(self, offset)
		SyncBodyScroll(offset)
	end)
	local previewOnMouseWheel = previewScroll:GetScript("OnMouseWheel")
	previewScroll:SetScript("OnMouseWheel", function(self, delta)
		local next = nil
		if previewOnMouseWheel then
			previewOnMouseWheel(self, delta)
			next = self:GetVerticalScroll() or 0
		else
			local cur = self:GetVerticalScroll() or 0
			local range = self:GetVerticalScrollRange() or 0
			local step = 20
			next = cur - (delta * step)
			if next < 0 then
				next = 0
			elseif next > range then
				next = range
			end
			self:SetVerticalScroll(next)
		end
		UpdateScrollBar(self, next)
		SyncBodyScroll(next)
	end)

	local previewText = previewContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	previewText:SetPoint("TOPLEFT", 8, -8)
	previewText:SetJustifyH("LEFT")
	previewText:SetJustifyV("TOP")
	previewText:SetWordWrap(true)
	previewText:SetNonSpaceWrap(true)
	previewText:SetTextColor(0.9, 0.9, 0.9, 1)
	previewText:SetSpacing(0.1)
	previewText:SetText("")

	local previewMdLines = nil
	local previewMdActive = false
	local previewMdPool = {}
	local previewMdActiveLines = {}
	local previewTexPool = {}
	local previewActiveTextures = {}
	local previewTipPool = {}
	local previewActiveTips = {}
	local previewMeasure = previewContent:CreateFontString(nil, "ARTWORK")

	local pFont, pSize, pFlags = GameFontHighlight:GetFont()
	if not pFont then
		pFont = "Fonts\\FRIZQT__.TTF"
		pSize = 12
		pFlags = ""
	end

	local previewFonts = {
		h1 = { font = pFont, size = math.max((pSize or 12) + 10, 20), flags = pFlags or "" },
		h2 = { font = pFont, size = math.max((pSize or 12) + 6, 16), flags = pFlags or "" },
		h3 = { font = pFont, size = math.max((pSize or 12) + 3, 14), flags = pFlags or "" },
		text = { font = pFont, size = pSize or 12, flags = pFlags or "" },
		bullet = { font = pFont, size = pSize or 12, flags = pFlags or "" },
	}

	local previewBodyColor = { 0.9, 0.9, 0.9, 1 }
	local previewHeadingColor = { 1, 0.82, 0, 1 }
	local previewBlankHeight = math.max(8, (previewFonts.text.size or 12) + 2)

	local function Preview_ClearMarkdown()
		for i = #previewMdActiveLines, 1, -1 do
			local fs = previewMdActiveLines[i]
			previewMdActiveLines[i] = nil
			if fs then
				fs:SetText("")
				fs:Hide()
				previewMdPool[#previewMdPool + 1] = fs
			end
		end
		for i = #previewActiveTextures, 1, -1 do
			local tex = previewActiveTextures[i]
			previewActiveTextures[i] = nil
			if tex then
				tex:Hide()
				tex:SetTexture(nil)
				previewTexPool[#previewTexPool + 1] = tex
			end
		end
		for i = #previewActiveTips, 1, -1 do
			local f = previewActiveTips[i]
			previewActiveTips[i] = nil
			if f then
				f:Hide()
				f._tipTitle = nil
				f._tipBody = nil
				f._tipIcon = nil
				previewTipPool[#previewTipPool + 1] = f
			end
		end
	end

	local function Preview_Acquire()
		local fs = table.remove(previewMdPool)
		if not fs then
			fs = previewContent:CreateFontString(nil, "ARTWORK")
			fs:SetJustifyH("LEFT")
			fs:SetJustifyV("TOP")
			fs:SetWordWrap(true)
			fs:SetNonSpaceWrap(true)
		end
		fs:Show()
		previewMdActiveLines[#previewMdActiveLines + 1] = fs
		return fs
	end

	local function Preview_AcquireTexture()
		local tex = table.remove(previewTexPool)
		if not tex then
			tex = previewContent:CreateTexture(nil, "ARTWORK")
		end
		tex:Show()
		previewActiveTextures[#previewActiveTextures + 1] = tex
		return tex
	end

	local function Preview_AcquireTip()
		local f = table.remove(previewTipPool)
		if not f then
			f = CreateFrame("Frame", nil, previewContent)
			f:EnableMouse(true)
			f._linkTex = f:CreateTexture(nil, "OVERLAY")
			f:SetScript("OnEnter", function(self)
				if (self._tipTitle or self._tipBody or self._tipIcon) and GameTooltip then
					GameTooltip:SetOwner(self, "ANCHOR_TOP")
					if self._tipIcon then
						GameTooltip:SetText(self._tipIcon)
						if self._tipTitle and self._tipTitle ~= "" then
							GameTooltip:AddLine(self._tipTitle, 1, 1, 1, true)
						end
						if self._tipBody and self._tipBody ~= "" then
							GameTooltip:AddLine(self._tipBody, 1, 1, 1, true)
						end
					else
						if self._tipTitle and self._tipTitle ~= "" then
							GameTooltip:SetText(self._tipTitle)
							if self._tipBody and self._tipBody ~= "" then
								GameTooltip:AddLine(self._tipBody, 1, 1, 1, true)
							end
						elseif self._tipBody then
							GameTooltip:SetText(self._tipBody)
						end
					end
					GameTooltip:Show()
				end
			end)
			f:SetScript("OnLeave", function()
				if GameTooltip then
					GameTooltip:Hide()
				end
			end)
		end
		f:Show()
		previewActiveTips[#previewActiveTips + 1] = f
		return f
	end

	local function Preview_TextWidth(text, font)
		if not previewMeasure then
			return 0
		end
		previewMeasure:SetFont(font.font, font.size, font.flags)
		previewMeasure:SetText(text or "")
		return previewMeasure:GetStringWidth() or 0
	end

	local function Preview_WrapLines(text, maxW, font)
		local out = {}
		local s = text or ""
		local len = #s
		if len == 0 then
			out[1] = { start = 1, ["end"] = 0, width = 0 }
			return out
		end
		local i = 1
		local lineStart = 1
		local lineWidth = 0
		while i <= len do
			local isSpace = s:sub(i, i):match("%s") ~= nil
			local j = i + 1
			while j <= len and (s:sub(j, j):match("%s") ~= nil) == isSpace do
				j = j + 1
			end
			local token = s:sub(i, j - 1)
			local tokenWidth = Preview_TextWidth(token, font)
			if lineWidth + tokenWidth > maxW and lineWidth > 0 then
				out[#out + 1] = { start = lineStart, ["end"] = i - 1, width = lineWidth }
				lineStart = i
				lineWidth = 0
			end
			lineWidth = lineWidth + tokenWidth
			i = j
		end
		out[#out + 1] = { start = lineStart, ["end"] = len, width = lineWidth }
		return out
	end

	local function Preview_LayoutMarkdown(textW)
		Preview_ClearMarkdown()
		if not previewMdLines or #previewMdLines == 0 then
			previewContent:SetHeight(24)
			return
		end

		local x = 8
		local y = -8

		for _, line in ipairs(previewMdLines) do
			if line.kind == "blank" then
				y = y - previewBlankHeight
			elseif line.kind == "texture" then
				if line.before and line.before > 0 then
					y = y - line.before
				end
				local tex = Preview_AcquireTexture()
				local xIndent = x + (line.indent or 0)
				local w = textW - (line.indent or 0)
				if w < 20 then
					w = 20
				end
				local drawW = line.width or w
				if line.fullWidth then
					drawW = w
				end
				if drawW > w then
					drawW = w
				end
				local h = line.height
				if not h then
					if line.ratio and drawW > 0 then
						h = drawW * line.ratio
					else
						h = 32
					end
				end
				if h < 8 then
					h = 8
				end
				tex:ClearAllPoints()
				tex:SetPoint("TOPLEFT", xIndent, y)
				tex:SetSize(drawW, h)
				if line.atlas then
					tex:SetAtlas(line.atlas, true)
				else
					tex:SetTexture(line.texture)
				end
				y = y - h
				if line.after and line.after > 0 then
					y = y - line.after
				end
			else
				if line.before and line.before > 0 then
					y = y - line.before
				end
				local fs = Preview_Acquire()
				local xIndent = x + (line.indent or 0)
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", xIndent, y)
				local w = textW - (line.indent or 0)
				if w < 20 then
					w = 20
				end
				fs:SetWidth(w)

				local font = previewFonts[line.kind] or previewFonts.text
				fs:SetFont(font.font, font.size, font.flags)
				if line.kind == "h1" or line.kind == "h2" or line.kind == "h3" then
					fs:SetTextColor(
						previewHeadingColor[1],
						previewHeadingColor[2],
						previewHeadingColor[3],
						previewHeadingColor[4]
					)
				else
					fs:SetTextColor(previewBodyColor[1], previewBodyColor[2], previewBodyColor[3], previewBodyColor[4])
				end

				fs:SetText(line.text or "")
				local h = fs:GetStringHeight() or font.size or 0
				y = y - h

				if line.tooltips and line.plain and #line.tooltips > 0 then
					local wrapLines = Preview_WrapLines(line.plain, w, font)
					local lineCount = #wrapLines
					local lineHeight = (lineCount > 0 and (h / lineCount)) or h
					for _, tip in ipairs(line.tooltips) do
						local rangeStart = tip.offset + 1
						local rangeEnd = tip.offset + tip.length
						for li, ln in ipairs(wrapLines) do
							if rangeEnd >= ln.start and rangeStart <= ln["end"] then
								local segStart = rangeStart > ln.start and rangeStart or ln.start
								local segEnd = rangeEnd < ln["end"] and rangeEnd or ln["end"]
								local before = line.plain:sub(ln.start, segStart - 1)
								local segment = line.plain:sub(segStart, segEnd)
								local xOffset = Preview_TextWidth(before, font)
								local wTip = Preview_TextWidth(segment, font)
								if wTip < 4 then
									wTip = 4
								end
								local maxW = w - xOffset
								if maxW > 0 and wTip > maxW then
									wTip = maxW
								end
								local tipFrame = Preview_AcquireTip()
								tipFrame._tipTitle = tip.title
								tipFrame._tipBody = tip.body
								tipFrame._tipIcon = tip.iconTag
								tipFrame:ClearAllPoints()
								tipFrame:SetPoint("TOPLEFT", fs, "TOPLEFT", xOffset, -((li - 1) * lineHeight))
								tipFrame:SetSize(wTip, lineHeight)
								if tipFrame._linkTex then
									if tip.linkAtlas and tip.linkAtlas ~= "" then
										local wTex = wTip
										local hTex = tip.linkH or 12
										local ox = tip.linkOffsetX or 0
										local oy = tip.linkOffsetY or 0
										tipFrame._linkTex:SetAtlas(tip.linkAtlas)
										tipFrame._linkTex:SetSize(wTex, hTex)
										tipFrame._linkTex:ClearAllPoints()
										tipFrame._linkTex:SetPoint("TOP", tipFrame, "BOTTOM", ox, oy)
										tipFrame._linkTex:Show()
									else
										tipFrame._linkTex:Hide()
									end
								end
							end
						end
					end
				end
				if line.after and line.after > 0 then
					y = y - line.after
				end
			end
		end

		local h = -y + 16
		previewContent:SetHeight(h)
	end

	previewScroll:SetScript("OnSizeChanged", function()
		local w = previewScroll:GetWidth() or 0
		if w > 0 then
			if not previewMdActive then
				previewText:SetWidth(w - 36)
			end
			if editor.UpdatePreview then
				editor.UpdatePreview()
			end
		end
	end)

	local function Title_GetValue()
		if titleIsPlaceholder then
			return ""
		end
		return tostring(titleBox:GetText() or "")
	end

	function editor.UpdatePreview()
		local t = Title_GetValue()
		local titleText = (t ~= "" and t) or "Onizleme"
		previewTitleText:SetText(titleText)
		if Title_UpdateWidth then
			Title_UpdateWidth()
		end
		if fn.Bio_RenderMarkdownLines then
			previewMdLines = fn.Bio_RenderMarkdownLines(bodyBox:GetText() or "")
			previewMdActive = true
			previewText:Hide()
			local w = previewScroll:GetWidth() or 0
			if w > 0 then
				Preview_LayoutMarkdown(w - 36)
			else
				Preview_LayoutMarkdown(1)
			end
		else
			previewMdLines = nil
			previewMdActive = false
			Preview_ClearMarkdown()
			previewText:Show()
			local wow = RenderMarkdown(bodyBox:GetText() or "")
			previewText:SetText(wow)
			local h = previewText:GetStringHeight() or 0
			previewContent:SetHeight(h + 24)
		end
	end

	function editor.SetEditMode(isEdit)
		editor._editMode = isEdit and true or false
		if editor._editMode and not editor._ratioMode and Prefs and Prefs.SetHeros then
			Prefs.SetHeros("bioEditorView", "edit")
		end
		ApplyLayout()
		if not isEdit or editor._ratioMode then
			editor.UpdatePreview()
		end
	end

	function editor.SetRatioMode(enabled)
		editor._ratioMode = enabled and true or false
		if editor._ratioMode then
			editor._editMode = true
			if Prefs and Prefs.SetHeros then
				Prefs.SetHeros("bioEditorView", "double")
			end
		end
		ApplyLayout()
		editor.UpdatePreview()
	end

	local BIO_BG_ATLASES = (ns and ns.BACKGROUND_ATLASES) or {}

	local function GetSelectedText(editBox)
		if editBox and editBox.GetHighlightText then
			local text = editBox:GetHighlightText()
			if text and text ~= "" then
				return text
			end
		end
		return nil
	end

	local function PrefixLines(text, prefix)
		local out = {}
		for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
			if line ~= "" then
				out[#out + 1] = prefix .. line
			else
				out[#out + 1] = line
			end
		end
		return table.concat(out, "\n")
	end

	local function InsertPrefixAtCursorLine(editBox, prefix)
		if not editBox or not prefix then
			return
		end
		local text = editBox:GetText() or ""
		local pos = editBox.GetCursorPosition and editBox:GetCursorPosition() or #text
		if pos < 0 then
			pos = 0
		end
		local before = text:sub(1, pos)
		local lineStart = before:match(".*\n()") or 1
		local head = text:sub(1, lineStart - 1)
		local tail = text:sub(lineStart)
		editBox:SetText(head .. prefix .. tail)
		if editBox.SetCursorPosition then
			editBox:SetCursorPosition(pos + #prefix)
		end
	end

	local function ApplyLinePrefix(editBox, prefix)
		if not editBox or not prefix then
			return
		end
		editBox:SetFocus()
		local selected = GetSelectedText(editBox)
		if selected then
			local prefixed = PrefixLines(selected, prefix)
			if editBox.Insert then
				editBox:Insert(prefixed)
				return
			end
		end
		InsertPrefixAtCursorLine(editBox, prefix)
	end

	local function ApplyInlineWrap(editBox, token, placeholder)
		if not editBox or not token then
			return
		end
		editBox:SetFocus()
		local insertText
		local selected = GetSelectedText(editBox)
		if selected and selected ~= "" then
			insertText = token .. selected .. token
		else
			local label = placeholder or "Metin"
			insertText = token .. label .. token
		end
		local label = placeholder or "Metin"
		if editBox.Insert then
			editBox:Insert(insertText)
			return
		end
		local text = editBox:GetText() or ""
		local pos = editBox.GetCursorPosition and editBox:GetCursorPosition() or #text
		local before = text:sub(1, pos)
		local after = text:sub(pos + 1)
		editBox:SetText(before .. insertText .. after)
		if editBox.SetCursorPosition then
			editBox:SetCursorPosition(#before + #insertText)
		end
	end

	local function ApplyInlineInsert(editBox, insertText)
		if not editBox or not insertText then
			return
		end
		editBox:SetFocus()
		if editBox.Insert then
			editBox:Insert(insertText)
			return
		end
		local text = editBox:GetText() or ""
		local pos = editBox.GetCursorPosition and editBox:GetCursorPosition() or #text
		local before = text:sub(1, pos)
		local after = text:sub(pos + 1)
		editBox:SetText(before .. insertText .. after)
		if editBox.SetCursorPosition then
			editBox:SetCursorPosition(#before + #insertText)
		end
	end

	local function ApplyLineInsert(editBox, lineText)
		if not editBox or not lineText then
			return
		end
		editBox:SetFocus()
		local text = editBox:GetText() or ""
		local pos = editBox.GetCursorPosition and editBox:GetCursorPosition() or #text
		local before = text:sub(1, pos)
		local after = text:sub(pos + 1)
		local prefix = ""
		local suffix = ""
		if before ~= "" and before:sub(-1) ~= "\n" then
			prefix = "\n"
		end
		if after ~= "" and after:sub(1, 1) ~= "\n" then
			suffix = "\n"
		end
		local insertText = prefix .. lineText .. suffix
		if editBox.Insert then
			editBox:Insert(insertText)
			return
		end
		editBox:SetText(before .. insertText .. after)
		if editBox.SetCursorPosition then
			editBox:SetCursorPosition(#before + #insertText)
		end
	end

	local function Dropdown_AddRadioEntry(menu, label, getter, toggler)
		if menu.CreateRadio then
			menu:CreateRadio(label, getter, toggler)
		else
			menu:CreateButton(label, toggler, { isRadio = true, checked = getter })
		end
	end

	local function ApplyBackgroundAtlasToItem(item, atlas)
		if not item or not item.innerBg or not atlas or atlas == "" then
			return
		end
		if HU and HU.Util_IsAtlas and HU.Util_IsAtlas(atlas) then
			item.innerBg:SetAtlas(atlas)
		else
			item.innerBg:SetAtlas(atlas)
		end
	end

	local function SaveBackgroundAtlas(atlas)
		if not editTarget or type(editTarget.bio) ~= "table" then
			return
		end
		local b = editTarget.bio
		if atlas and atlas ~= "" then
			b.backgroundAtlas = atlas
		else
			b.backgroundAtlas = nil
		end
		local now = time()
		b.updatedAt = now
		if not b.createdAt or b.createdAt <= 0 then
			b.createdAt = now
		end
		local key = editTarget.full or "__general__"
		if DB and DB.UpsertGuildMemberPrefs then
			DB:UpsertGuildMemberPrefs(editTarget.gid, editTarget.uid, {
				biographie = { [key] = b },
				updatedAt = now,
			})
		end
		if Comms and Comms.SendGuildMemberPrefs then
			Comms:SendGuildMemberPrefs(editTarget.gid, editTarget.uid, {
				biographie = { [key] = b },
				updatedAt = now,
			})
		end
	end

	local function SaveBioVisibility(value)
		if not editTarget or type(editTarget.bio) ~= "table" then
			return
		end
		local b = editTarget.bio
		b.visibility = value
		local now = time()
		b.updatedAt = now
		if not b.createdAt or b.createdAt <= 0 then
			b.createdAt = now
		end
		local key = editTarget.full or "__general__"
		if DB and DB.UpsertGuildMemberPrefs then
			DB:UpsertGuildMemberPrefs(editTarget.gid, editTarget.uid, {
				biographie = { [key] = b },
				updatedAt = now,
			})
		end
		if Comms and Comms.SendGuildMemberPrefs then
			Comms:SendGuildMemberPrefs(editTarget.gid, editTarget.uid, {
				biographie = { [key] = b },
				updatedAt = now,
			})
		end
		if editor and editor.ApplyBioToEditor then
			editor.ApplyBioToEditor(b)
		end
		if ui.profile and ui.profile.BioSide_Rebuild then
			ui.profile:BioSide_Rebuild()
		end
		NormalizeFeatured(editTarget.gid, editTarget.uid, key)
		EmitGuildRosterUpdate()
	end

	local function Bio_IsPublishable(bio)
		if type(bio) ~= "table" then
			return false
		end
		if (tonumber(bio.deletedAt or 0) or 0) > time() then
			return false
		end
		local title = tostring(bio.title or "")
		local text = tostring(bio.md or "")
		return title ~= "" and text ~= ""
	end

	local function Bio_ShowPublishError()
		if UIErrorsFrame and UIErrorsFrame.AddMessage then
			UIErrorsFrame:AddMessage("Yayinlamadan once baslik ve metin ekle.", 1, 0.2, 0.2, 1)
		end
	end

	local function DeleteCurrentBio()
		if not editTarget or not editTarget.gid or not editTarget.uid then
			return
		end
		local key = editTarget.full or "__general__"
		local now = time()
		if DB and DB.UpsertGuildMemberPrefs then
			DB:UpsertGuildMemberPrefs(editTarget.gid, editTarget.uid, {
				biographie = { [key] = "__DELETE__" },
				updatedAt = now,
			})
		end
		if Comms and Comms.SendGuildMemberPrefs then
			Comms:SendGuildMemberPrefs(editTarget.gid, editTarget.uid, {
				biographie = { [key] = "__DELETE__" },
				updatedAt = now,
			})
		end
		NormalizeFeatured(editTarget.gid, editTarget.uid, key)
		EmitGuildRosterUpdate()
		if ui.profile and ui.profile.BioSide_Rebuild then
			ui.profile:BioSide_Rebuild()
		end
	end

	SetFeatured = function(flag)
		if not (editTarget and editTarget.gid and editTarget.uid) then
			return
		end
		if flag and not IsPublicPublished(editTarget.bio) then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage("One cikarmadan once herkese acik yayinla.", 1, 0.2, 0.2, 1)
			end
			return
		end
		local key = editTarget.full or "__general__"
		local prefs = DB and DB.GetGuildMemberPrefs and DB:GetGuildMemberPrefs(editTarget.gid, editTarget.uid) or nil
		local map = prefs and prefs.biographie or nil
		if type(map) ~= "table" then
			return
		end

		local now = time()
		local payload = {}
		local changed = false

		for k, v in pairs(map) do
			if type(v) == "table" then
				local want = (k == key) and (flag == true) or false
				local cur = v.featured == true
				if k == key then
					if want ~= cur then
						local copy = CopyTable(v)
						copy.featured = want or nil
						copy.updatedAt = now
						payload[k] = copy
						changed = true
					end
				else
					if v.featured == true then
						local copy = CopyTable(v)
						copy.featured = nil
						copy.updatedAt = now
						payload[k] = copy
						changed = true
					end
				end
			end
		end

		if not changed then
			return
		end

		if DB and DB.UpsertGuildMemberPrefs then
			DB:UpsertGuildMemberPrefs(editTarget.gid, editTarget.uid, {
				biographie = payload,
				updatedAt = now,
			})
		end
		if Comms and Comms.SendGuildMemberPrefs then
			Comms:SendGuildMemberPrefs(editTarget.gid, editTarget.uid, {
				biographie = payload,
				updatedAt = now,
			})
		end

		if editTarget and editTarget.bio then
			editTarget.bio.featured = flag and true or nil
		end
		if editor and editor.ApplyBioToEditor then
			editor.ApplyBioToEditor(editTarget.bio or {})
		end
		if ui.profile and ui.profile.BioSide_Rebuild then
			ui.profile:BioSide_Rebuild()
		end
		NormalizeFeatured(editTarget.gid, editTarget.uid, editTarget.full or "__general__", flag ~= true)
		EmitGuildRosterUpdate()
	end

	AutoSaveBio = function()
		if not (editor and editor.CommitBio and editTarget and editTarget.bio) then
			return
		end
		if editTarget.bio.status == "published" then
			editor.CommitBio()
		else
			editor.CommitBio("draft")
		end
	end

	local function BuildOptionsMenu(root, cfg)
		local showLayout = cfg and cfg.showLayout ~= false
		local showCover = cfg == nil or cfg.showCover ~= false
		local allowDelete = cfg == nil or cfg.allowDelete ~= false
		local showCoverDivider = cfg == nil or cfg.showCoverDivider ~= false
		local function Dropdown_AddToggleEntry(menu, label, getter, toggler)
			if menu.CreateCheckbox then
				menu:CreateCheckbox(label, getter, toggler)
			else
				menu:CreateButton(label, toggler, { isNotRadio = true, checked = getter })
			end
		end
		local hasTarget = editTarget and editTarget.gid and editTarget.uid and editTarget.bio
		local pendingDelete = hasTarget and (tonumber(editTarget.bio.deletedAt or 0) or 0) > time()
		if not pendingDelete then
			if showCover then
				local textureMenu = root:CreateButton("Couverture")
				if textureMenu then
					if #BIO_BG_ATLASES == 0 then
						textureMenu:CreateButton("Aucune texture disponible", function() end, { disabled = true })
					else
						for i = 1, #BIO_BG_ATLASES do
							local entry = BIO_BG_ATLASES[i]
							Dropdown_AddRadioEntry(textureMenu, entry.label, function()
								local b = editTarget and editTarget.bio
								local current = b and (b.backgroundAtlas or b.sideAtlas) or nil
								return current == entry.atlas
							end, function()
								if not editTarget or type(editTarget.bio) ~= "table" then
									return
								end
								editTarget.bio.backgroundAtlas = entry.atlas
								ApplyBackgroundAtlasToItem(editor._activeBioItem, entry.atlas)
								SaveBackgroundAtlas(entry.atlas)
							end)
							if textureMenu.CreateDivider and (i % 5 == 0) and i < #BIO_BG_ATLASES then
								textureMenu:CreateDivider()
							end
						end
					end
				end
				if root.CreateDivider then
					root:CreateDivider()
				end
			end
		end
		if showLayout then
			Dropdown_AddRadioEntry(root, "Duzenleme", function()
				return editor._editMode and not editor._ratioMode
			end, function()
				editor.SetRatioMode(false)
				editor.SetEditMode(true)
			end)
			Dropdown_AddRadioEntry(root, "Onizleme", function()
				return (not editor._editMode) and not editor._ratioMode
			end, function()
				editor.SetRatioMode(false)
				editor.SetEditMode(false)
			end)
			Dropdown_AddRadioEntry(root, "Cift gorunum", function()
				return editor._ratioMode
			end, function()
				editor.SetRatioMode(true)
			end)
			if root.CreateDivider then
				root:CreateDivider()
			end
		end
		if not pendingDelete then
			local isPublished = hasTarget and editTarget.bio and editTarget.bio.status == "published"
			if isPublished then
				root:CreateButton("Yayini kaldir", function()
					if editTarget and editTarget.bio then
						editTarget.bio.visibility = "private"
						SaveBioVisibility("private")
					end
					editor.CommitBio("draft")
				end, { disabled = not hasTarget })
			else
				root:CreateButton("Yayinla", function()
					if editTarget and editTarget.bio and not Bio_IsPublishable(editTarget.bio) then
						Bio_ShowPublishError()
						return
					end
					if editTarget and editTarget.bio then
						editTarget.bio.visibility = "public"
						SaveBioVisibility("public")
					end
					editor.CommitBio("published")
				end, { disabled = not hasTarget })
			end
			if isPublished then
				local visibilityMenu = root:CreateButton("Gorunurluk")
				if visibilityMenu then
					Dropdown_AddRadioEntry(visibilityMenu, "Ozel (sadece ben)", function()
						local b = editTarget and editTarget.bio
						return (b and b.visibility or "public") == "private"
					end, function()
						if not hasTarget then
							return
						end
						editTarget.bio.visibility = "private"
						SaveBioVisibility("private")
					end)
					Dropdown_AddRadioEntry(visibilityMenu, "Herkese acik (guild)", function()
						local b = editTarget and editTarget.bio
						return (b and b.visibility or "public") == "public"
					end, function()
						if not hasTarget then
							return
						end
						editTarget.bio.visibility = "public"
						SaveBioVisibility("public")
					end)
				end
			end
			if IsPublicPublished(editTarget and editTarget.bio) then
				Dropdown_AddToggleEntry(root, "One cikar", function()
					local b = editTarget and editTarget.bio
					return b and b.featured == true
				end, function()
					if not hasTarget then
						return
					end
					SetFeatured(not (editTarget and editTarget.bio and editTarget.bio.featured))
				end)
			end
			if root.CreateDivider then
				root:CreateDivider()
			end
		end
		local canDelete = allowDelete
			and hasTarget
			and editTarget.full ~= "__general__"
			and editTarget.mode ~= "biographie"
		if canDelete then
			root:CreateButton("Sil", function()
				if StaticPopupDialogs then
					StaticPopupDialogs["WOWGUILDE_DELETE_BIO"] = {
						text = "Bu destan silinsin mi?",
						button1 = "Evet",
						button2 = "Hayir",
						OnAccept = function()
							DeleteCurrentBio()
						end,
						timeout = 0,
						whileDead = 1,
						hideOnEscape = 1,
						preferredIndex = 3,
					}
					StaticPopup_Show("WOWGUILDE_DELETE_BIO")
				else
					DeleteCurrentBio()
				end
			end)
			if root.CreateDivider then
				root:CreateDivider()
			end
		end
		root:CreateButton("Enregistrer et quitter", function()
			local isPublished = editTarget and editTarget.bio and editTarget.bio.status == "published"
			if isPublished then
				editor.CommitBio()
			else
				editor.CommitBio("draft")
			end
			if ui and ui.profile and ui.profile.HideBiographyEdit then
				ui.profile:HideBiographyEdit()
			end
		end, { disabled = not hasTarget })
	end

	function editor.OpenOptionsMenu(anchor, cfg)
		if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
			return
		end
		MenuUtil.CreateContextMenu(anchor, function(_, root)
			if root.CreateTitle then
				root:CreateTitle("Ayarlar")
			end
			if not (editTarget and editTarget.bio) and editor._activeBioItem and editor._activeBioItem._gid then
				if editor._activeBioItem._full and editor._activeBioItem._full ~= "" then
					editor.SetEditTarget(
						editor._activeBioItem._gid,
						editor._activeBioItem._uid,
						editor._activeBioItem._full,
						editor._activeBioItem._bio,
						editor._activeBioItem
					)
				else
					editor.SetEditTargetGeneral(
						editor._activeBioItem._gid,
						editor._activeBioItem._uid,
						editor._activeBioItem._bio,
						editor._activeBioItem
					)
				end
			end
			BuildOptionsMenu(root, cfg)
		end)
	end

	local function BuildMarkdownPresetMenu(root)
		local titlesMenu = root:CreateButton("Basliklar")
		if titlesMenu then
			titlesMenu:CreateButton("Seviye 1", function()
				ApplyLinePrefix(bodyBox, "# ")
			end)
			titlesMenu:CreateButton("Seviye 2", function()
				ApplyLinePrefix(bodyBox, "## ")
			end)
			titlesMenu:CreateButton("Seviye 3", function()
				ApplyLinePrefix(bodyBox, "### ")
			end)
		end

		local listsMenu = root:CreateButton("Listeler")
		if listsMenu then
			listsMenu:CreateButton("Seviye 1", function()
				ApplyLinePrefix(bodyBox, "- ")
			end)
			listsMenu:CreateButton("Seviye 2", function()
				ApplyLinePrefix(bodyBox, "-- ")
			end)
			listsMenu:CreateButton("Seviye 3", function()
				ApplyLinePrefix(bodyBox, "--- ")
			end)
		end

		local tipsMenu = root:CreateButton("Tooltip ve ikonlar")
		if tipsMenu then
			tipsMenu:CreateButton("Tooltip (baslik + govde)", function()
				ApplyInlineInsert(bodyBox, "{Baslik;Tooltip govdesi}Metin")
			end)
			tipsMenu:CreateButton("Tooltip (govde)", function()
				ApplyInlineInsert(bodyBox, "{Tooltip govdesi}Metin")
			end)
			tipsMenu:CreateButton("Texture atlas", function()
				ApplyInlineInsert(bodyBox, "{atlas:Map_Faction_Ring;18}")
			end)
			tipsMenu:CreateButton("Texture atlas + tooltip", function()
				ApplyInlineInsert(bodyBox, "{atlas:Map_Faction_Ring;18;Govde}")
			end)
			tipsMenu:CreateButton("Ikon ID + tooltip", function()
				ApplyInlineInsert(bodyBox, "{134400;18;Govde}")
			end)
		end

		local texturesMenu = root:CreateButton("Textures")
		if texturesMenu then
			local presets = {
				{
					name = "VignetteLoot",
					atlas = "VignetteLoot",
					token = "{VignetteLoot;18}",
					inline = true,
					previewSize = 18,
				},
				{
					name = "spellbook-divider",
					atlas = "spellbook-divider",
					token = "{- spellbook-divider -}",
					inline = false,
					previewSize = 18,
				},
			}
			for _, entry in ipairs(presets) do
				local size = entry.previewSize or 18
				local label = entry.name
				if entry.atlas then
					label = string.format("|A:%s:%d:%d|a %s", entry.atlas, size, size, entry.name)
				elseif entry.texture then
					label = string.format("|T%s:%d:%d|t %s", entry.texture, size, size, entry.name)
				end
				texturesMenu:CreateButton(label, function()
					if entry.inline then
						ApplyInlineInsert(bodyBox, entry.token)
					else
						ApplyLineInsert(bodyBox, entry.token)
					end
				end)
			end
		end

		local colorsMenu = root:CreateButton("Renkler")
		if colorsMenu then
			colorsMenu:CreateButton("Altin", function()
				ApplyInlineWrap(bodyBox, "*", "Metin")
			end)
			colorsMenu:CreateButton("Mavi", function()
				ApplyInlineWrap(bodyBox, "*", "1 Metin")
			end)
			colorsMenu:CreateButton("Kirmizi", function()
				ApplyInlineWrap(bodyBox, "*", "2 Metin")
			end)
			colorsMenu:CreateButton("Yesil", function()
				ApplyInlineWrap(bodyBox, "*", "3 Metin")
			end)
			colorsMenu:CreateButton("Mor", function()
				ApplyInlineWrap(bodyBox, "*", "4 Metin")
			end)
			colorsMenu:CreateButton("Orange", function()
				ApplyInlineWrap(bodyBox, "*", "5 Metin")
			end)
		end

		local qualityMenu = root:CreateButton("WoW kalite")
		if qualityMenu then
			qualityMenu:CreateButton("L1 (gri)", function()
				ApplyInlineWrap(bodyBox, "*", "L1 Metin")
			end)
			qualityMenu:CreateButton("L2 (beyaz)", function()
				ApplyInlineWrap(bodyBox, "*", "L2 Metin")
			end)
			qualityMenu:CreateButton("L3 (yesil)", function()
				ApplyInlineWrap(bodyBox, "*", "L3 Metin")
			end)
			qualityMenu:CreateButton("L4 (mavi)", function()
				ApplyInlineWrap(bodyBox, "*", "L4 Metin")
			end)
			qualityMenu:CreateButton("L5 (violet)", function()
				ApplyInlineWrap(bodyBox, "*", "L5 Metin")
			end)
			qualityMenu:CreateButton("L6 (orange)", function()
				ApplyInlineWrap(bodyBox, "*", "L6 Metin")
			end)
		end
	end

	function editor.OpenMarkdownPresetsMenu(anchor)
		if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
			return
		end
		MenuUtil.CreateContextMenu(anchor, function(_, root)
			BuildMarkdownPresetMenu(root)
		end)
	end

	optionsBtn:SetScript("OnClick", function(self)
		editor.OpenOptionsMenu(self, { showLayout = true })
	end)

	presetsBtn:SetScript("OnClick", function(self)
		editor.OpenMarkdownPresetsMenu(self)
	end)

	bodyBox:SetScript("OnTextChanged", function(self)
		self:GetParent():UpdateScrollChildRect()
		if previewPanel:IsShown() then
			editor.UpdatePreview()
		end
	end)
	bodyBox:SetScript("OnEditFocusLost", function()
		AutoSaveBio()
	end)

	function editor.SetActiveBioItem(item)
		if activeBioItem and activeBioItem.active then
			activeBioItem.active:Hide()
		end
		activeBioItem = item
		editor._activeBioItem = item
		if activeBioItem and activeBioItem.active then
			activeBioItem.active:Show()
		end
		if ui and ui.profile and ui.profile.BioSide_SetActiveItem then
			ui.profile.BioSide_SetActiveItem(item)
		end
	end

	function editor.ApplyBioToEditor(bio)
		local b = bio or {}
		Title_SetText(b.title or "")
		Title_UpdateWidth()
		bodyBox:SetText(b.md or b.text or "")
		if b.status == "draft" then
			statusLabel:SetText("Taslak")
		elseif b.visibility == "private" then
			statusLabel:SetText("Yayinlandi (ozel)")
		elseif b and (b.title or b.md or b.text or b.wow or b.html) then
			statusLabel:SetText("Yayinlandi")
		else
			statusLabel:SetText("Destan secilmedi")
		end
	end

	function editor.SetEditTarget(gid, uid, full, bio, item)
		if not gid or not uid or not full then
			return
		end
		editTarget = {
			gid = gid,
			uid = uid,
			full = full,
			mode = "char",
			bio = type(bio) == "table" and bio or {},
		}
		ui.profile._bioEditTargetFull = full
		ui.profile._bioEditTargetKind = "char"
		editor.ApplyBioToEditor(editTarget.bio)
		editor.SetActiveBioItem(item)
	end

	function editor.SetEditTargetGeneral(gid, uid, bio, item)
		if not gid or not uid then
			return
		end
		editTarget = {
			gid = gid,
			uid = uid,
			mode = "biographie",
			full = "__general__",
			bio = type(bio) == "table" and bio or {},
		}
		ui.profile._bioEditTargetFull = nil
		ui.profile._bioEditTargetKind = "general"
		editor.ApplyBioToEditor(editTarget.bio)
		editor.SetActiveBioItem(item)
	end

	local function BuildBioPayload(statusOverride)
		if not editTarget then
			return nil
		end
		local now = time()
		local b = editTarget.bio or {}
		b.title = Title_GetValue()
		b.md = tostring(bodyBox:GetText() or "")
		b.wow = nil
		b.html = nil
		b.text = nil
		local vis = b.visibility
		if vis == nil and fn.Bio_GetVisibility then
			vis = fn.Bio_GetVisibility()
		end
		b.visibility = vis or "public"
		b.updatedAt = now
		if not b.createdAt or b.createdAt <= 0 then
			b.createdAt = now
		end
		if statusOverride then
			b.status = statusOverride
		end
		return b
	end

	function editor.CommitBio(statusOverride)
		if not editTarget then
			return
		end
		local payload = BuildBioPayload(statusOverride)
		if not payload then
			return
		end
		if editTarget.mode == "biographie" then
			local ts = tonumber(payload.updatedAt or time()) or time()
			if DB and DB.UpsertGuildMemberPrefs then
				DB:UpsertGuildMemberPrefs(editTarget.gid, editTarget.uid, {
					biographie = { [editTarget.full or "__general__"] = payload },
					updatedAt = ts,
				})
			end
			if Comms and Comms.SendGuildMemberPrefs then
				Comms:SendGuildMemberPrefs(editTarget.gid, editTarget.uid, {
					biographie = { [editTarget.full or "__general__"] = payload },
					updatedAt = ts,
				})
			end
		else
			if DB and DB.UpsertGuildMemberPrefs then
				DB:UpsertGuildMemberPrefs(editTarget.gid, editTarget.uid, {
					biographie = { [editTarget.full] = payload },
					updatedAt = payload.updatedAt or time(),
				})
			end
			if Comms and Comms.SendGuildMemberPrefs then
				Comms:SendGuildMemberPrefs(editTarget.gid, editTarget.uid, {
					biographie = { [editTarget.full] = payload },
					updatedAt = payload.updatedAt or time(),
				})
			end
		end
		editTarget.bio = payload
		editor.ApplyBioToEditor(payload)
		if ui.profile then
			ui.profile.bioHasAny = true
			if ui.profile.bioCreateBtn then
				ui.profile.bioCreateBtn:Hide()
			end
		end
		if ui.profile and ui.profile.BioSide_Rebuild then
			ui.profile:BioSide_Rebuild()
		end
		EmitGuildRosterUpdate()
	end

	function editor.ClearStatus(msg)
		statusLabel:SetText(msg or "Destan secilmedi")
	end

	return editor
end

return M
