local ADDON, ns = ...
ns.UI = ns.UI or {}

local UI = ns.UI
local EventBus = ns.EventBus

local sections = {}
local activeSection
local frame
local rosteurHooks = false

-- ==========================================================
-- Utils
-- ==========================================================

local function GetChosenIcon()
	if ns and ns.Prefs and ns.Prefs.GetSocial then
		return ns.Prefs.GetSocial("chosenIcon", "Interface\\ICONS\\inv_ability_skyriding_glyph")
	end
	return "Interface\\ICONS\\inv_ability_skyriding_glyph"
end

local function IsBlizzMooveActive()
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded("BlizzMoove") or C_AddOns.IsAddOnLoaded("BlizzMove")
	end
	if IsAddOnLoaded then
		return IsAddOnLoaded("BlizzMoove") or IsAddOnLoaded("BlizzMove")
	end
	return false
end

local function EnableFrameMovementIfAllowed()
	if not frame or not IsBlizzMooveActive() or frame._wgMoveEnabled then
		return
	end
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)
	frame._wgMoveEnabled = true
end

local function ForceCenter()
	if not frame then
		return
	end
	if IsBlizzMooveActive() and frame:GetNumPoints() > 0 then
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function HookCommunities()
	if not CommunitiesFrame or not frame or frame._communitiesHooked then
		return
	end
	frame._communitiesHooked = true
	CommunitiesFrame:HookScript("OnShow", function()
		if frame and frame:IsShown() then
			frame:Hide()
		end
	end)
end

local function EnsureCommunitiesLoaded()
	if not CommunitiesFrame and C_AddOns and C_AddOns.IsAddOnLoaded then
		if not C_AddOns.IsAddOnLoaded("Blizzard_Communities") then
			C_AddOns.LoadAddOn("Blizzard_Communities")
		end
	end
end

local TOOLTIP_ORANGE = { 1, 0.8235, 0 }

local ICON_CHOICES = {
	"Interface\\ICONS\\inv_ability_skyriding_glyph",
	"Interface\\ICONS\\achievement_legionpvp6tier1",
	"Interface\\ICONS\\inv_holiday_beerfest_beerfesttrophy",
	"Interface\\ICONS\\inv_holiday_beerfest_highmountain",
	"Interface\\ICONS\\inv_holiday_beerfest_dreanei",
	"Interface\\ICONS\\inv_misc_bag_hearthstone",
	"Interface\\ICONS\\inv_ability_holyfire_wave",
	"Interface\\ICONS\\achievement_guildperk_ladyluck_rank2",
	"Interface\\ICONS\\vas_guildnamechange",
	"Interface\\ICONS\\achievement_guildperk_fasttrack_rank2",
	"Interface\\ICONS\\artifactability_balancedruid_fullmoon",
	"Interface\\ICONS\\garrison_building_storehouse",
	"Interface\\ICONS\\inv_misc_coinbag_special",
	"Interface\\ICONS\\inv_prg_icon_puzzle13",
	"Interface\\ICONS\\inv_112_raidtrinkets_manaforge_tanktrinket1",
	"Interface\\ICONS\\spell_misc_emotionafraid",
	"Interface\\ICONS\\ui_embercourt-emoji-happy",
	"Interface\\ICONS\\ui_embercourt-emoji-veryhappy",
	"Interface\\ICONS\\spell_misc_emotionhappy",
	"Interface\\ICONS\\spell_misc_emotionsad",
}

local function PlayTickSound()
	if PlaySound then
		pcall(PlaySound, 567407, "SFX")
	end
end

local function IsDevMode()
	if ns and ns.Utils and ns.Utils.IsDevMode then
		return ns.Utils.IsDevMode()
	end
	if ns and ns.Comms and ns.Comms.DEV_MODE ~= nil then
		return ns.Comms.DEV_MODE == true
	end
	if ns and ns.DEV_MODE ~= nil then
		return ns.DEV_MODE == true
	end
	return false
end

local function GetRosteurTabLabel()
	if ns and ns.Rosteur and ns.Rosteur.GetDevView and IsDevMode() then
		local view = ns.Rosteur.GetDevView()
		if view == "player" then
			return "Raid kaydi"
		elseif view == "manager" then
			return "Raid yonetimi"
		end
	end
	if ns and ns.Rosteur and ns.Rosteur.ShouldShowManagerTab and ns.Rosteur.ShouldShowManagerTab() then
		return "Raid yonetimi"
	end
	return "Raid kaydi"
end

local function ShouldShowRosteurTab()
	if not ns or not ns.Rosteur then
		return false
	end
	if IsDevMode() then
		return true
	end
	if ns.Rosteur.ShouldShowManagerTab and ns.Rosteur.ShouldShowManagerTab() then
		return true
	end
	if ns.Rosteur.ShouldShowSignupTab and ns.Rosteur.ShouldShowSignupTab() then
		return true
	end
	return false
end

local function ResizeTabToText(tab)
	if not tab then
		return
	end
	local textObj = tab.Text or _G[tab:GetName() .. "Text"]
	local textW = (textObj and textObj.GetStringWidth and textObj:GetStringWidth()) or 0
	local targetW = math.max(90, math.ceil(textW + 32))
	if PanelTemplates_TabResize then
		PanelTemplates_TabResize(tab, 0, targetW, nil, nil)
	else
		tab:SetWidth(targetW)
	end
end

local function EnsureMirrorIconPicker()
	if _G.WoWGuilde_IconPicker_Mirror then
		return _G.WoWGuilde_IconPicker_Mirror
	end
	if not frame then
		return nil
	end
	local cols, size, padding = 5, 32, 8
	local rows = math.ceil(#ICON_CHOICES / cols)
	local width = 20 + cols * (size + padding)
	local height = 30 + rows * (size + padding)

	local picker = CreateFrame("Frame", "WoWGuilde_IconPicker_Mirror", frame, "BackdropTemplate")
	picker:SetSize(width, height)
	picker:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	picker:SetFrameStrata("HIGH")
	picker:Hide()

	picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	picker.title:SetPoint("TOP", 0, -8)
	picker.title:SetText("Ikon secin")

	for i, icon in ipairs(ICON_CHOICES) do
		local btn = CreateFrame("Button", nil, picker)
		btn:SetSize(size, size)
		btn:SetNormalTexture(icon)
		btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

		local row = math.floor((i - 1) / cols)
		local col = (i - 1) % cols
		btn:SetPoint("TOPLEFT", 15 + col * (size + padding), -25 - row * (size + padding))

		btn:SetScript("OnClick", function()
			if ns and ns.Prefs and ns.Prefs.SetSocial then
				ns.Prefs.SetSocial("chosenIcon", icon or "Interface\\ICONS\\inv_ability_skyriding_glyph")
			end
			if _G.WoWGuildeTab and _G.WoWGuildeTab.Icon then
				_G.WoWGuildeTab.Icon:SetTexture(GetChosenIcon())
			end
			if frame and frame._communityMirrorSelf and frame._communityMirrorSelf.Icon then
				frame._communityMirrorSelf.Icon:SetTexture(GetChosenIcon())
			end
			if ns and ns.UI and ns.UI.Refresh then
				ns.UI.Refresh()
			end
			picker:Hide()
		end)
	end

	return picker
end

local function WithSFXMuted(fn)
	local ok, prev = pcall(GetCVar, "Sound_EnableSFX")
	if ok and prev ~= nil then
		pcall(SetCVar, "Sound_EnableSFX", "0")
	end
	local okCall, res = pcall(fn)
	if ok and prev ~= nil then
		pcall(SetCVar, "Sound_EnableSFX", prev)
	end
	if not okCall then
		error(res)
	end
end

local function HasLegendaryNews()
	local slot = _G.legendaryNews
	if not slot then
		return false
	end
	return slot._featured ~= nil and (not slot.IsShown or slot:IsShown())
end

local function UpdateCommunityMirrorOffsets()
	if not frame or not frame._communityMirrorFirst then
		return
	end
	local anchor = frame._communityMirrorAnchor or frame.Inset or frame
	local y = -40
	if activeSection == sections["Online yok"] and HasLegendaryNews() then
		y = -140
	end
	frame._communityMirrorFirst:ClearAllPoints()
	frame._communityMirrorFirst:SetPoint("TOPLEFT", anchor, "TOPRIGHT", frame._communityMirrorX or 10, y)
end

local function CreateCommunityMirrors()
	if not frame or frame._communityMirrors then
		return
	end
	EnsureCommunitiesLoaded()
	if not CommunitiesFrame then
		return
	end

	local anchor = frame.Inset or frame
	local tabs = {
		{ src = CommunitiesFrame.ChatTab, key = "Chat" },
		{ src = CommunitiesFrame.RosterTab, key = "Roster" },
		{ src = CommunitiesFrame.GuildBenefitsTab, key = "Benefits" },
		{ src = CommunitiesFrame.GuildInfoTab, key = "Info" },
	}

	local mirrors = {}
	local prev = nil
	local padY = -20
	for i = 1, #tabs do
		local src = tabs[i].src
		if src then
			local btn = CreateFrame("CheckButton", "WoWGuilde_MirrorTab" .. i, frame, "CommunitiesFrameTabTemplate")
			btn.tooltip = src.tooltip or src.GetTooltipText and src:GetTooltipText() or nil
			btn:RegisterForClicks("LeftButtonUp")

			if btn.Icon and src.Icon and src.Icon.GetTexture then
				btn.Icon:SetTexture(src.Icon:GetTexture())
			end

			if not prev then
				btn:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 10, 0)
			else
				btn:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, padY)
			end

			btn:SetScript("OnClick", function(self)
				for j = 1, #mirrors do
					mirrors[j]:SetChecked(false)
				end
				self:SetChecked(true)
				PlayTickSound()
				if frame and frame:IsShown() then
					HideUIPanel(frame)
				end
				EnsureCommunitiesLoaded()
				if not CommunitiesFrame then
					return
				end
				WithSFXMuted(function()
					if ShowUIPanel then
						ShowUIPanel(CommunitiesFrame)
					else
						CommunitiesFrame:Show()
					end
					if src.Click then
						src:Click()
					elseif src.OnClick then
						src:OnClick()
					end
				end)
			end)

			btn:SetScript("OnEnter", function(self)
				if self.tooltip and GameTooltip then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(self.tooltip, TOOLTIP_ORANGE[1], TOOLTIP_ORANGE[2], TOOLTIP_ORANGE[3])
					GameTooltip:Show()
				end
			end)
			btn:SetScript("OnLeave", function()
				if GameTooltip then
					GameTooltip:Hide()
				end
			end)

			mirrors[#mirrors + 1] = btn
			prev = btn
		end
	end

	local myBtn = CreateFrame("CheckButton", "WoWGuilde_MirrorTabSelf", frame, "CommunitiesFrameTabTemplate")
	myBtn.tooltip = "Guild hayati"
	myBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	if myBtn.Icon then
		myBtn.Icon:SetTexture(GetChosenIcon())
	end
	if not prev then
		myBtn:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 10, 0)
	else
		myBtn:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, padY)
	end
	myBtn:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			local picker = EnsureMirrorIconPicker()
			if picker then
				if picker:IsShown() then
					picker:Hide()
				else
					picker:ClearAllPoints()
					picker:SetPoint("TOPLEFT", self, "TOPRIGHT", 10, 0)
					picker:Show()
					picker:SetFrameLevel(self:GetFrameLevel() + 10)
				end
			end
			return
		end
		for j = 1, #mirrors do
			mirrors[j]:SetChecked(false)
		end
		self:SetChecked(true)
		PlayTickSound()
		UI.Show(true)
	end)
	myBtn:SetScript("OnEnter", function(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Guild hayati", TOOLTIP_ORANGE[1], TOOLTIP_ORANGE[2], TOOLTIP_ORANGE[3])
			GameTooltip:AddLine("Aktiviteleri, basarilari ve ortak ilerlemeyi gorun.", 1, 1, 1)
			GameTooltip:AddLine("<Sag tik ile ikonu degistir>", 0, 1, 0)
			GameTooltip:Show()
		end
	end)
	myBtn:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	mirrors[#mirrors + 1] = myBtn

	frame._communityMirrorButtons = mirrors
	frame._communityMirrorFirst = mirrors[1]
	frame._communityMirrorAnchor = anchor
	frame._communityMirrorX = 10
	frame._communityMirrorSelf = myBtn

	frame._communityMirrors = true
	UpdateCommunityMirrorOffsets()
end

-- ==========================================================
-- Sections
-- ==========================================================

local function ShowSection(name)
	if activeSection then
		activeSection:Hide()
	end
	if sections[name] then
		sections[name]:Show()
		activeSection = sections[name]

		if name == "Notre guilde" and ns.Data and ns.Data.Journalist and ns.Data.Journalist.TickNow then
			ns.Data.Journalist.TickNow()
		end
	end
	UpdateCommunityMirrorOffsets()
end

local function UpdateRosteurTabVisibility()
	if not frame or not frame._tabByName then
		return
	end
	local tab = frame._tabByName["Rosteur"]
	if not tab then
		return
	end
	if ShouldShowRosteurTab() then
		tab:Show()
		tab:SetText(GetRosteurTabLabel())
		ResizeTabToText(tab)
	else
		tab:Hide()
		if activeSection == sections["Rosteur"] then
			ShowSection("Notre guilde")
			if frame._tabByName["Notre guilde"] then
				PanelTemplates_SetTab(frame, frame._tabByName["Notre guilde"]:GetID())
			end
		end
	end
end

local function HookRosteurEvents()
	if rosteurHooks or not EventBus or not EventBus.On then
		return
	end
	rosteurHooks = true
	EventBus.On("WG_ROSTEUR_UPDATED", function()
		UpdateRosteurTabVisibility()
		if sections["Rosteur"] and sections["Rosteur"].Refresh then
			sections["Rosteur"].Refresh()
		end
	end)
	EventBus.On("GROUP_ROSTER_UPDATE", function()
		UpdateRosteurTabVisibility()
	end)
	EventBus.On("GUILD_ROSTER_UPDATE", function()
		UpdateRosteurTabVisibility()
	end)
	EventBus.On("WG_MEMBER_PREFS_RECEIVED", function()
		UpdateRosteurTabVisibility()
	end)
end

-- ==========================================================
-- Tabs
-- ==========================================================

local function CreateTabs(parent)
	local tabDefs = {
		{ key = "Notre guilde", label = "Guild" },
		{ key = "Nos héros", label = "Kahramanlar" },
		{ key = "Rosteur", label = GetRosteurTabLabel() },
	}
	if ns.Sections.LFG then
		table.insert(tabDefs, 3, { key = "LFG", label = "Grup ara" })
	end
	local tabs = {}
	local tabByName = {}

	for i, def in ipairs(tabDefs) do
		local name = def.key
		local tab = CreateFrame("Button", "WoWGuildeTab" .. i, parent, "PanelTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(def.label or name)
		ResizeTabToText(tab)
		tab._wgKey = name

		tab:SetScript("OnClick", function(self)
			PanelTemplates_SetTab(parent, self:GetID())
			PlayTickSound()
			ShowSection(self._wgKey or name)
		end)

		if i == 1 then
			tab:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 12, -30)
		else
			tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -15, 0)
		end

		tabs[i] = tab
		tabByName[name] = tab
	end

	PanelTemplates_SetNumTabs(parent, #tabs)
	PanelTemplates_SetTab(parent, 1)
	parent._tabs = tabs
	parent._tabByName = tabByName
	UpdateRosteurTabVisibility()
end

-- ==========================================================
-- Main Frame
-- ==========================================================

local function CreateMainFrame()
	if frame then
		return frame
	end

	-- Securite dependances (LFG opsiyonel)
	if
		not (
			ns.Sections
			and ns.Sections.Heros
			and ns.Sections.Social
			and ns.Sections.Rosteur
		)
	then
		return nil
	end

	frame = CreateFrame("Frame", "WoWGuilde_MainFrame", UIParent, "ButtonFrameTemplateMinimizable")
	frame:SetSize(1200, 700)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(100)
	frame:SetClampedToScreen(true)
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:Hide()

	-- UIPanel
	frame:SetAttribute("UIPanelLayout-enabled", true)
	frame:SetAttribute("UIPanelLayout-area", "center")
	frame:SetAttribute("UIPanelLayout-pushable", 0)
	frame:SetAttribute("UIPanelLayout-whileDead", true)
	frame:SetAttribute("UIPanelLayout-allowOtherPanels", true)

	UIPanelWindows["WoWGuilde_MainFrame"] = {
		area = "center",
		pushable = 0,
		whileDead = 1,
	}

	if type(UISpecialFrames) == "table" then
		table.insert(UISpecialFrames, "WoWGuilde_MainFrame")
	end

	ForceCenter()
	EnableFrameMovementIfAllowed()

	-- Titre
	if frame.TitleContainer and frame.TitleContainer.TitleText then
		frame.TitleContainer.TitleText:SetText("Guild hayati - Beta - Calisma suruyor")
	end

	-- Portrait dynamique
	frame:HookScript("OnShow", function()
		if frame.PortraitContainer and frame.PortraitContainer.portrait then
			frame.PortraitContainer.portrait:SetTexture(GetChosenIcon())
		end
		ForceCenter()
		EnableFrameMovementIfAllowed()
		HookCommunities()
		CreateCommunityMirrors()
		if frame._communityMirrorSelf and frame._communityMirrorButtons then
			for i = 1, #frame._communityMirrorButtons do
				frame._communityMirrorButtons[i]:SetChecked(false)
			end
			frame._communityMirrorSelf:SetChecked(true)
		end
		UpdateCommunityMirrorOffsets()
		UpdateRosteurTabVisibility()
	end)

	-- Protection UIPanelManager
	if ns.Utils and ns.Utils.SafeHooksecurefunc then
		ns.Utils.SafeHooksecurefunc("UIParent_ManageFramePositions", function()
			if frame and frame:IsShown() then
				ForceCenter()
			end
		end)
	end

	-- Contenu
	local content = frame.Inset or frame
	frame.Content = content

	sections["Nos héros"] = ns.Sections.Heros(content)
	sections["Notre guilde"] = ns.Sections.Social(content)
	if ns.Sections.LFG then
		sections["LFG"] = ns.Sections.LFG(content)
	end
	sections["Rosteur"] = ns.Sections.Rosteur(content)

	ShowSection("Notre guilde")
	CreateTabs(frame)
	HookRosteurEvents()

	return frame
end

-- ==========================================================
-- API PUBLIQUE
-- ==========================================================

function UI.Init()
	if frame then
		return
	end
	CreateMainFrame()
end

function UI.ShowSection(name)
	if not frame then
		CreateMainFrame()
	end
	if not frame then
		return
	end
	ShowSection(name)
	if frame._tabByName and frame._tabByName[name] then
		PanelTemplates_SetTab(frame, frame._tabByName[name]:GetID())
	end
end

function UI.ShowQuartierMiniature()
	if not frame then
		CreateMainFrame()
	end
	if not frame then
		return
	end
	ShowSection("LFG")
	if frame._tabByName and frame._tabByName["LFG"] then
		PanelTemplates_SetTab(frame, frame._tabByName["LFG"]:GetID())
	end
end

function UI.Show(silent)
	if not frame then
		CreateMainFrame()
	end
	if not frame then
		return
	end

	local function doShow()
		if CommunitiesFrame and CommunitiesFrame:IsShown() and HideUIPanel then
			HideUIPanel(CommunitiesFrame)
		end
		C_Timer.After(0, function()
			if frame then
				frame:Show()
				ForceCenter()
				EnableFrameMovementIfAllowed()
			end
		end)
	end

	if silent then
		WithSFXMuted(doShow)
	else
		doShow()
	end
end

function UI.Hide()
	if not frame then
		return
	end
	if HideUIPanel then
		HideUIPanel(frame)
	end
	frame:Hide()
end

function UI.Toggle()
	if frame and frame:IsShown() then
		UI.Hide()
	else
		UI.Show()
	end
end

function UI.IsShown()
	return frame and frame:IsShown() or false
end

function UI.Refresh()
	if frame and frame.PortraitContainer and frame.PortraitContainer.portrait then
		frame.PortraitContainer.portrait:SetTexture(GetChosenIcon())
	end
	if frame and frame._communityMirrorSelf and frame._communityMirrorSelf.Icon then
		frame._communityMirrorSelf.Icon:SetTexture(GetChosenIcon())
	end
	ForceCenter()
	EnableFrameMovementIfAllowed()
	UpdateRosteurTabVisibility()
end

function UI.UpdateCommunityMirrorOffsets()
	UpdateCommunityMirrorOffsets()
end

-- ==========================================================
-- BOOTSTRAP (LE POINT CLÉ)
-- ==========================================================

if EventBus and EventBus.On then
	EventBus.On("ADDON_READY", function()
		UI.Init()
	end)
end
