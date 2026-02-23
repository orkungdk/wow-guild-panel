local ADDON, ns = ...
ns.GB = ns.GB or {}

local GB = ns.GB

local function ensureCommunitiesLoaded()
	if not CommunitiesFrame and C_AddOns and C_AddOns.IsAddOnLoaded then
		if not C_AddOns.IsAddOnLoaded("Blizzard_Communities") then
			C_AddOns.LoadAddOn("Blizzard_Communities")
		end
	end
end

-- Vérifie si l’onglet actif est une guilde
local function IsGuildSelected()
	if not CommunitiesFrame or not CommunitiesFrame.selectedClubId then
		return false
	end
	local info = C_Club.GetClubInfo(CommunitiesFrame.selectedClubId)
	return info and info.clubType == Enum.ClubType.Guild
end

local function UpdateVisibility(tab)
	if not tab then
		return
	end
	if CommunitiesFrame:IsShown() and IsGuildSelected() then
		tab:Show()
	else
		tab:Hide()
	end
end

-- Liste des icônes disponibles
local iconChoices = {
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

-- Crée une mini-fenêtre flottante avec une grille d’icônes
local function CreateIconPicker(tab)
	if _G.WoWGuilde_IconPicker then
		return _G.WoWGuilde_IconPicker
	end

	local cols, size, padding = 5, 32, 8
	local rows = math.ceil(#iconChoices / cols)
	local width = 20 + cols * (size + padding)
	local height = 30 + rows * (size + padding)

	-- 🔑 Parent : CommunitiesFrame
	local picker = CreateFrame("Frame", "WoWGuilde_IconPicker", CommunitiesFrame, "BackdropTemplate")
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

	for i, icon in ipairs(iconChoices) do
		local btn = CreateFrame("Button", nil, picker)
		btn:SetSize(size, size)
		btn:SetNormalTexture(icon)
		btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

		local row = math.floor((i - 1) / cols)
		local col = (i - 1) % cols
		btn:SetPoint("TOPLEFT", 15 + col * (size + padding), -25 - row * (size + padding))

		btn:SetScript("OnClick", function()
			-- Sauvegarde en BDD
			if ns and ns.Prefs and ns.Prefs.SetSocial then
				ns.Prefs.SetSocial("chosenIcon", icon or "Interface\\ICONS\\inv_ability_skyriding_glyph")
			end

			-- Met à jour le bouton de guilde
			if ns and ns.Prefs and ns.Prefs.GetSocial then
				tab.Icon:SetTexture(ns.Prefs.GetSocial("chosenIcon", "Interface\\ICONS\\inv_ability_skyriding_glyph"))
			end

			-- Met à jour la fenêtre principale si elle est ouverte
			if ns and ns.UI and ns.UI.Refresh then
				ns.UI.Refresh()
			end

			picker:Hide()
			tab:SetChecked(false)
		end)
	end

	return picker
end

-- Création du bouton guilde
local function createGuildTab()
	if _G.WoWGuildeTab then
		return _G.WoWGuildeTab
	end
	if not CommunitiesFrame then
		return
	end

	local lastTab = CommunitiesFrame.GuildInfoTab
		or CommunitiesFrame.GuildBenefitsTab
		or CommunitiesFrame.RosterTab
		or CommunitiesFrame.ChatTab

	local tab = CreateFrame("CheckButton", "WoWGuildeTab", CommunitiesFrame, "CommunitiesFrameTabTemplate")
	tab.tooltip = "Guild hayati"
	tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	-- Icône
	if ns and ns.Prefs and ns.Prefs.GetSocial then
		tab.Icon:SetTexture(ns.Prefs.GetSocial("chosenIcon", "Interface\\ICONS\\inv_ability_skyriding_glyph"))
	else
		tab.Icon:SetTexture("Interface\\ICONS\\inv_ability_skyriding_glyph")
	end

	-- Position
	if lastTab then
		tab:SetPoint("TOPLEFT", lastTab, "BOTTOMLEFT", 0, -20)
	else
		tab:SetPoint("TOPLEFT", CommunitiesFrame, "TOPLEFT", 12, -80)
	end

	local picker = CreateIconPicker(tab)

	-- Clique gauche/droite
	tab:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			if picker:IsShown() then
				picker:Hide()
			else
				picker:ClearAllPoints()
				picker:SetPoint("TOPLEFT", self, "TOPRIGHT", 10, 0)
				picker:Show()
				picker:SetFrameLevel(self:GetFrameLevel() + 10)
			end
		else
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			if CommunitiesFrame:IsShown() then
				HideUIPanel(CommunitiesFrame)
			end

			-- toggle fenêtre custom
			WoWGuilde.Toggle()

			-- synchro immédiate du highlight
			self:SetChecked(ns.UI and ns.UI.IsShown and ns.UI.IsShown())
		end
	end)

	-- Décoche quand la fenêtre custom se ferme
	if ns.UI then
		ns.Utils.SafeHooksecurefunc(ns.UI, "Hide", function()
			tab:SetChecked(false)
		end)
	end

	-- Tooltip
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Guild hayati", 1, 0.82, 0)
		GameTooltip:AddLine("Aktiviteleri, basarilari ve ortak ilerlemeyi gorun.", 1, 1, 1)
		GameTooltip:AddLine("<Sag tik ile ikonu degistir>", 0, 1, 0)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Synchro bouton <-> fenêtre
	ns.Utils.SafeHooksecurefunc(WoWGuilde, "Toggle", function()
		tab:SetChecked(ns.UI and ns.UI.IsShown and ns.UI.IsShown())
	end)

	-- Visibilité conditionnelle
	ns.Utils.SafeHooksecurefunc(CommunitiesFrame, "SelectClub", function()
		UpdateVisibility(tab)
	end)
	CommunitiesFrame:HookScript("OnShow", function()
		UpdateVisibility(tab)
	end)
	CommunitiesFrame:HookScript("OnHide", function()
		UpdateVisibility(tab)
	end)

	UpdateVisibility(tab)
	return tab
end

local function attachToRetail()
	ensureCommunitiesLoaded()
	if not CommunitiesFrame then
		return false
	end
	createGuildTab()
	return true
end

function GB.Init()
	if attachToRetail() then
		return
	end
	-- Classic fallback
	if GuildFrame then
		local btn = CreateFrame("Button", "WoWGuilde_GuildButton", GuildFrame, "UIPanelButtonTemplate")
		btn:SetSize(120, 22)
		btn:SetText("WoW Guild")
		btn:SetPoint("TOPRIGHT", GuildFrame, "TOPRIGHT", -36, -32)
		btn:SetScript("OnClick", function()
			WoWGuilde.Toggle()
		end)
	end
end
