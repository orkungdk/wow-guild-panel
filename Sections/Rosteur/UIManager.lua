local ADDON, ns = ...

local M = ns.RosteurSection

function M.BuildManagerUI(ctx)
	local ns = ctx.ns
	local Rosteur = ctx.Rosteur
	local Utils = ctx.Utils
	local const = ctx.const
	local ui = ctx.ui
	local state = ctx.state
	local fn = ctx.fn

	local ROLE_ORDER = const.ROLE_ORDER
	local ROLE_LABEL = const.ROLE_LABEL
	local ROLE_ATLAS = const.ROLE_ATLAS

	local managerPanel = ui.managerPanel
	local headerArea = ui.headerArea
	local f = ui.frame

	local sideArea = nil
	local sideInfo = nil
	local sideHint = nil
	local devToggle = nil
	local devDelete = nil

	-- =========================
	-- Manager: Idle
	-- =========================
	local idlePanel = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerIdle", managerPanel)
	idlePanel:SetAllPoints(managerPanel)
	idlePanel:SetFrameLevel(100)
	idlePanel.bgAtlas = idlePanel:CreateTexture("WoWGuilde_Rosteur_ManagerIdle_BgAtlas", "BACKGROUND")
	idlePanel.bgAtlas:SetAllPoints(idlePanel)
	idlePanel.bgAtlas:SetAtlas("auctionhouse-background-index")
	idlePanel.bgAtlas:SetAlpha(1)

	idlePanel.bg = idlePanel:CreateTexture("WoWGuilde_Rosteur_ManagerIdle_Bg", "BORDER")
	idlePanel.bg:SetAllPoints(idlePanel)
	idlePanel.bg:SetColorTexture(0, 0, 0, 0.4)

	local idleTitle =
		idlePanel:CreateFontString("WoWGuilde_Rosteur_ManagerIdle_Title", "OVERLAY", "GameFontNormalLarge")
	idleTitle:SetPoint("TOP", idlePanel, "TOP", 0, -80)
	idleTitle:SetFont("Fonts\\MORPHEUS.ttf", 32, "OUTLINE")
	idleTitle:SetText("Lancement d'une saison de raid")

	local idleDesc = idlePanel:CreateFontString("WoWGuilde_Rosteur_ManagerIdle_Desc", "OVERLAY", "GameFontHighlight")
	idleDesc:SetPoint("TOP", idleTitle, "BOTTOM", 0, -12)
	idleDesc:SetWidth(520)
	idleDesc:SetJustifyH("CENTER")
	idleDesc:SetText(
		"Ouvrez les inscriptions, collectez les rôles souhaités et préparez la configuration de votre groupe de raid pour la saison à venir."
	)

	local startBtn =
		CreateFrame("Button", "WoWGuilde_Rosteur_ManagerIdle_Start", idlePanel, "BigRedThreeSliceButtonTemplate")
	startBtn:SetSize(360, 70)
	startBtn:SetPoint("TOP", idleDesc, "BOTTOM", 0, -28)
	startBtn.underlay = startBtn:CreateTexture("WoWGuilde_Rosteur_ManagerIdle_Start_Underlay", "BACKGROUND", nil, -2)
	local shadowW, shadowH = 450, 130
	local shadowX, shadowY = 0, -25
	startBtn.underlay:SetSize(shadowW, shadowH)
	startBtn.underlay:SetPoint("CENTER", startBtn, "CENTER", shadowX, shadowY)
	startBtn.underlay:SetAtlas("perks-mount-shadow", false)
	startBtn.underlay:SetAlpha(1)
	startBtn:SetText("Préparer une saison de Raid")
	startBtn:SetNormalFontObject("GameFontHighlightLarge")

	local idleNote =
		idlePanel:CreateFontString("WoWGuilde_Rosteur_ManagerIdle_Note", "OVERLAY", "GameFontHighlightSmall")
	idleNote:SetPoint("TOP", startBtn, "BOTTOM", 0, -20)
	idleNote:SetText("Ouvre les inscriptions pour toute la guilde.")

	-- =========================
	-- Manager: Prep
	-- =========================
	local prepPanel = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerPrep", managerPanel)
	prepPanel:SetAllPoints(managerPanel)
	prepPanel:Hide()

	state.showPrepSummary = state.showPrepSummary or false

	local prepLayout = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerPrep_Layout", prepPanel)
	prepLayout:SetPoint("TOPLEFT", prepPanel, "TOPLEFT", 10, -10)
	prepLayout:SetPoint("BOTTOMRIGHT", prepPanel, "BOTTOMRIGHT", -10, 70)

	local prepSections = {}
	ui.prepSections = prepSections

	state.prepSummaryData = state.prepSummaryData
		or {
			TANK = { heroes = {}, order = {} },
			HEAL = { heroes = {}, order = {} },
			DPS = { heroes = {}, order = {} },
		}

	local PREP_ICON_DECOR = {
		size = 370,
		offsetX = 0,
		offsetY = -80,
		alpha = 1,
		byRole = {
			DPS = "UI-LFG-RoleIcon-DPS-Background",
			TANK = "UI-LFG-RoleIcon-Tank-Background",
			HEAL = "UI-LFG-RoleIcon-Healer-Background",
		},
	}
	local PREP_ICON_MASK_ANIM = {
		maskAtlas = "ui-frame-genericplayerchoice-portrait-border-mask",
		raysAtlas = "shop-saletag-fx-glow",
		duration = 4,
		startX = -150,
		endX = 150,
		delayMin = 1,
		delayMax = 3,
		initialDelayMin = 0,
		initialDelayMax = 3,
		size = 175,
		textureWidth = 220,
		textureHeight = 200,
		offsetY = 0,
		alpha = 1,
	}
	local prepOrder = {
		{
			role = "DPS",
			title = "Dégâts",
			desc = "Inflige les dégâts principaux.",
			atlas = ROLE_ATLAS.DPS,
		},
		{
			role = "TANK",
			title = "Protection",
			desc = "Encaisse et protège le groupe.",
			atlas = ROLE_ATLAS.TANK,
		},
		{
			role = "HEAL",
			title = "Soins",
			desc = "Soutient et soigne l'équipe.",
			atlas = ROLE_ATLAS.HEAL,
		},
	}

	local ShowPrepTooltip = nil
	for _, def in ipairs(prepOrder) do
		local role = def.role
		local prefix = "WoWGuilde_Rosteur_PrepSection_" .. role
		local section = CreateFrame("Frame", prefix, prepLayout)
		section.role = role
		section:EnableMouse(true)
		section._role = role
		section:SetScript("OnEnter", function(self)
			if ShowPrepTooltip then
				ShowPrepTooltip(self._role)
			end
		end)
		section:SetScript("OnLeave", function()
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)
		section.bg = section:CreateTexture(prefix .. "_Bg", "BACKGROUND")
		section.bg:SetPoint("TOPLEFT", section, "TOPLEFT", -8, 12)
		section.bg:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", 8, -12)
		section.bg:SetAtlas("GarrFollower-Shadow", true)
		section.bg:SetAlpha(0.6)

		section.header = CreateFrame("Frame", prefix .. "_Header", section)
		section.header:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
		section.header:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, 0)
		section.header:SetHeight(140)

		section.icon = section.header:CreateTexture(prefix .. "_Icon", "ARTWORK")
		section.icon:SetSize(120, 120)
		section.icon:SetPoint("TOP", section.header, "TOP", 0, -40)
		if def.atlas then
			section.icon:SetAtlas(def.atlas, false)
		end

		section.iconMask = section.header:CreateMaskTexture(prefix .. "_IconMask", "ARTWORK")
		section.iconMask:SetPoint("CENTER", section.icon, "CENTER", -2, 2)
		section.iconMask:SetSize(PREP_ICON_MASK_ANIM.size, PREP_ICON_MASK_ANIM.size)
		section.iconMask:SetAtlas(PREP_ICON_MASK_ANIM.maskAtlas, false)

		section.iconRays = section.header:CreateTexture(prefix .. "_IconRays", "ARTWORK", nil, 2)
		local startX = tonumber(PREP_ICON_MASK_ANIM.startX) or -100
		local endX = tonumber(PREP_ICON_MASK_ANIM.endX) or 100
		local moveX = endX - startX
		section.iconRays:SetPoint("CENTER", section.icon, "CENTER", startX, PREP_ICON_MASK_ANIM.offsetY)
		section.iconRays:SetSize(PREP_ICON_MASK_ANIM.textureWidth, PREP_ICON_MASK_ANIM.textureHeight)
		section.iconRays:SetAtlas(PREP_ICON_MASK_ANIM.raysAtlas, false)
		section.iconRays:SetAlpha(PREP_ICON_MASK_ANIM.alpha or 0.35)
		section.iconRays:AddMaskTexture(section.iconMask)

		section.iconRaysAnim = section.iconRays:CreateAnimationGroup()
		section.iconRaysAnim:SetLooping("NONE")
		local move = section.iconRaysAnim:CreateAnimation("Translation")
		move:SetOrder(1)
		move:SetDuration(PREP_ICON_MASK_ANIM.duration)
		move:SetOffset(moveX, 0)
		local function RandomDelay(minV, maxV)
			local minN = tonumber(minV) or 0
			local maxN = tonumber(maxV) or minN
			if maxN < minN then
				minN, maxN = maxN, minN
			end
			return minN + (maxN - minN) * math.random()
		end
		local function RestartRays(afterSeconds)
			local function Start()
				if not section.iconRays or not section.iconRaysAnim then
					return
				end
				section.iconRaysAnim:Stop()
				section.iconRays:ClearAllPoints()
				section.iconRays:SetPoint("CENTER", section.icon, "CENTER", startX, PREP_ICON_MASK_ANIM.offsetY)
				section.iconRaysAnim:Play()
			end
			if C_Timer and C_Timer.After then
				C_Timer.After(afterSeconds or 0, Start)
			else
				Start()
			end
		end
		section.iconRaysAnim:SetScript("OnFinished", function()
			local delay = RandomDelay(PREP_ICON_MASK_ANIM.delayMin, PREP_ICON_MASK_ANIM.delayMax)
			RestartRays(delay)
		end)
		local initialDelay = RandomDelay(PREP_ICON_MASK_ANIM.initialDelayMin, PREP_ICON_MASK_ANIM.initialDelayMax)
		RestartRays(initialDelay)

		section.iconDecor = section.header:CreateTexture(prefix .. "_IconDecor", "ARTWORK", nil, -1)
		section.iconDecor:SetPoint("CENTER", section.icon, "CENTER", PREP_ICON_DECOR.offsetX, PREP_ICON_DECOR.offsetY)
		section.iconDecor:SetSize(PREP_ICON_DECOR.size, PREP_ICON_DECOR.size)
		local decorAtlas = PREP_ICON_DECOR.byRole and PREP_ICON_DECOR.byRole[role] or nil
		if decorAtlas and decorAtlas ~= "" then
			section.iconDecor:SetAtlas(decorAtlas, false)
		end
		section.iconDecor:SetAlpha(PREP_ICON_DECOR.alpha or 1)
		section.iconDecor:SetVertexColor(1, 1, 1, 0.05)

		section.title = section.header:CreateFontString(prefix .. "_Title", "OVERLAY", "GameFontNormalLarge")
		section.title:SetPoint("TOP", section.icon, "BOTTOM", 0, -20)
		section.title:SetText(def.title)

		section.desc = section.header:CreateFontString(prefix .. "_Desc", "OVERLAY", "GameFontHighlightSmall")
		section.desc:SetPoint("TOP", section.title, "BOTTOM", 0, -4)
		section.desc:SetWidth(200)
		section.desc:SetJustifyH("CENTER")
		section.desc:SetText(def.desc)

		section.count = section.header:CreateFontString(prefix .. "_Count", "OVERLAY", "GameFontNormalHuge")
		section.count:SetPoint("TOP", section.desc, "BOTTOM", 0, -20)
		section.count:SetFont("Fonts\\FRIZQT__.TTF", 40, "OUTLINE")
		section.count:SetTextColor(1, 0.678, 0, 1)
		section.count:SetText("0")

		section.applyBtn = CreateFrame("Button", prefix .. "_ApplyBtn", section.header, "UIPanelButtonTemplate")
		section.applyBtn:SetSize(120, 22)
		section.applyBtn:SetPoint("TOP", section.count, "BOTTOM", 0, -80)
		section.applyBtn:SetText("Postuler")
		section.applyBtn:SetScript("OnClick", function()
			local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
			if not gid or not Rosteur then
				return
			end
			local full, meta = fn.GetMySignupMeta and fn.GetMySignupMeta(gid) or nil
			if not full or full == "" then
				return
			end
			local allowed = ns
				and ns.UI
				and ns.UI.GetAllowedRoles
				and ns.UI.GetAllowedRoles(meta.classTag, meta.spec, meta.specID)
			if allowed and next(allowed) and not allowed[role] then
				if UIErrorsFrame and UIErrorsFrame.AddMessage then
					UIErrorsFrame:AddMessage("Ce role n'est pas disponible pour ce personnage.", 1, 0.2, 0.2, 1)
				end
				return
			end
			Rosteur.SetSignup(gid, full, role, meta)
			if f and f.Refresh then
				f.Refresh()
			end
		end)
		section.removeBtn = CreateFrame("Button", prefix .. "_RemoveBtn", section.header, "UIPanelButtonTemplate")
		section.removeBtn:SetSize(120, 22)
		section.removeBtn:SetPoint("TOP", section.applyBtn, "BOTTOM", 0, -4)
		section.removeBtn:SetText("Retirer")
		section.removeBtn:Hide()

		prepSections[role] = section
	end

	ShowPrepTooltip = function(role)
		if not GameTooltip then
			return
		end
		local TOOLTIP_WIDTH = 400
		local MAX_CONTENT_LINES = 20
		local section = prepSections and prepSections[role] or nil
		local anchor = section or UIParent
		local countAnchor = section and section.count or nil
		local data = state.prepSummaryData and state.prepSummaryData[role] or nil
		local totalEntries = 0
		if data and data.order and data.heroes then
			for _, heroKey in ipairs(data.order) do
				local hero = data.heroes[heroKey]
				if hero and hero.entries then
					totalEntries = totalEntries + #hero.entries
				end
			end
		end
		if totalEntries <= 0 then
			GameTooltip:Hide()
			return
		end
		GameTooltip:SetOwner(anchor, "ANCHOR_NONE")
		GameTooltip:ClearAllPoints()
		if countAnchor then
			GameTooltip:SetPoint("TOP", countAnchor, "TOP", 0, 5)
		else
			GameTooltip:SetPoint("CENTER", anchor, "CENTER", 0, 0)
		end
		if GameTooltip.SetMinimumWidth then
			GameTooltip:SetMinimumWidth(TOOLTIP_WIDTH)
		end
		GameTooltip:SetWidth(TOOLTIP_WIDTH)
		GameTooltip:ClearLines()
		local label = ROLE_LABEL[role] or role
		GameTooltip:AddLine(label, 0.894, 0.655, 0.125, true)

		if not data or not data.order or #data.order == 0 then
			GameTooltip:Hide()
			return
		end

		local function SelectHeroes(maxLines)
			local selected = {}
			local used = 0
			for _, heroKey in ipairs(data.order) do
				local hero = data.heroes and data.heroes[heroKey] or nil
				if hero then
					local entriesCount = hero.entries and #hero.entries or 0
					local linesNeeded = 1 + entriesCount
					if #selected > 0 then
						linesNeeded = linesNeeded + 1
					end
					if used + linesNeeded > maxLines then
						return selected, true
					end
					selected[#selected + 1] = heroKey
					used = used + linesNeeded
				end
			end
			return selected, false
		end

		local selectedKeys, truncated = SelectHeroes(MAX_CONTENT_LINES)
		if truncated then
			selectedKeys = SelectHeroes(MAX_CONTENT_LINES - 1)
		end

		for i, heroKey in ipairs(selectedKeys) do
			local hero = data.heroes and data.heroes[heroKey] or nil
			if hero then
				if i > 1 then
					GameTooltip:AddLine(" ")
				end
				local heroLine = hero.heroName
				if not heroLine or heroLine == "" then
					heroLine = hero.heroFull
				end
				if not heroLine or heroLine == "" then
					heroLine = "Héro"
				end
				GameTooltip:AddLine(heroLine, 1, 1, 1, true)
				if hero.entries then
					for _, entry in ipairs(hero.entries) do
						local charName = entry.name or entry.full or "-"
						local colored = fn.ColorizeName and fn.ColorizeName(charName, entry.classTag) or charName
						GameTooltip:AddLine(colored, nil, nil, nil, true)
					end
				end
			end
		end
		if truncated then
			GameTooltip:AddLine("...", 0.8, 0.8, 0.8, true)
		end
		GameTooltip:SetWidth(TOOLTIP_WIDTH)
		GameTooltip:Show()
	end

	local prepSep1 = prepLayout:CreateTexture("WoWGuilde_Rosteur_PrepSeparator_1", "BORDER")
	prepSep1:SetWidth(4)
	prepSep1:SetAtlas("combattimeline-line-shadow")
	prepSep1:SetAlpha(0.4)
	prepSep1:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)

	local prepSep2 = prepLayout:CreateTexture("WoWGuilde_Rosteur_PrepSeparator_2", "BORDER")
	prepSep2:SetWidth(4)
	prepSep2:SetAtlas("combattimeline-line-shadow")
	prepSep2:SetAlpha(0.4)
	prepSep2:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)

	local function LayoutPrepColumns()
		local w = prepLayout:GetWidth() or 0
		if w <= 0 then
			return
		end
		local gap = 18
		local colW = math.max(120, (w - gap * 2) / 3)
		local tank = prepSections.TANK
		local heal = prepSections.HEAL
		local dps = prepSections.DPS
		if not dps or not heal or not tank then
			return
		end

		dps:ClearAllPoints()
		dps:SetPoint("TOPLEFT", prepLayout, "TOPLEFT", 0, 0)
		dps:SetPoint("BOTTOMLEFT", prepLayout, "BOTTOMLEFT", 0, 0)
		dps:SetWidth(colW)

		heal:ClearAllPoints()
		heal:SetPoint("TOPLEFT", dps, "TOPRIGHT", gap, 0)
		heal:SetPoint("BOTTOMLEFT", dps, "BOTTOMRIGHT", gap, 0)
		heal:SetWidth(colW)

		tank:ClearAllPoints()
		tank:SetPoint("TOPLEFT", heal, "TOPRIGHT", gap, 0)
		tank:SetPoint("BOTTOMRIGHT", prepLayout, "BOTTOMRIGHT", 0, 0)

		prepSep1:ClearAllPoints()
		prepSep1:SetPoint("TOP", prepLayout, "TOP", 0, -6)
		prepSep1:SetPoint("BOTTOM", prepLayout, "BOTTOM", 0, 6)
		prepSep1:SetPoint("LEFT", dps, "RIGHT", gap / 2, 0)

		prepSep2:ClearAllPoints()
		prepSep2:SetPoint("TOP", prepLayout, "TOP", 0, -6)
		prepSep2:SetPoint("BOTTOM", prepLayout, "BOTTOM", 0, 6)
		prepSep2:SetPoint("LEFT", heal, "RIGHT", gap / 2, 0)
	end

	prepLayout:SetScript("OnSizeChanged", LayoutPrepColumns)
	LayoutPrepColumns()

	local configBtn =
		CreateFrame("Button", "WoWGuilde_Rosteur_ManagerPrep_Config", prepPanel, "BigRedThreeSliceButtonTemplate")
	configBtn:SetSize(240, 34)
	configBtn:SetPoint("BOTTOM", prepPanel, "BOTTOM", 0, 10)
	configBtn:SetText("Créer le rosteur")
	configBtn:SetNormalFontObject("GameFontHighlightLarge")
	do
		local fs = configBtn:GetFontString()
		if fs and fs.GetFont then
			local font, _, flags = fs:GetFont()
			fs:SetFont(font, 12, flags)
		end
	end
	local function UpdateConfigBtnTextState(isDisabled)
		local fs = configBtn and configBtn:GetFontString()
		if not fs then
			return
		end
		if isDisabled then
			fs:SetTextColor(0.439, 0.439, 0.439, 1)
		else
			fs:SetTextColor(1, 1, 1, 1)
		end
	end
	fn.UpdateConfigBtnTextState = UpdateConfigBtnTextState

	configBtn:SetScript("OnEnter", function(self)
		if not GameTooltip then
			return
		end
		local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
		local rosteur = Rosteur and Rosteur.GetState and Rosteur.GetState(gid) or nil
		local isLocked, remaining = fn.IsPrepConfigLocked and fn.IsPrepConfigLocked(rosteur) or false, 0
		local forceByShift = (remaining or 0) > 0 and IsShiftKeyDown and IsShiftKeyDown()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint("BOTTOM", self, "TOP", 0, 25)
		GameTooltip:ClearLines()
		GameTooltip:AddLine("Créer le rosteur", 1, 0.82, 0, false)
		if rosteur and rosteur.phase == "prep" and isLocked then
			GameTooltip:AddLine(
				"Merci d'attendre au minimum 2 jours avant de commencer à créer le rosteur.",
				1,
				1,
				1,
				true
			)
		elseif rosteur and rosteur.phase == "prep" and forceByShift then
			GameTooltip:AddLine(
				"Merci d'attendre au minimum 2 jours avant de commencer à créer le rosteur.\n\nVous pouvez tout de même forcer la création en maintenant majuscule enfoncé.",
				1,
				1,
				1,
				true
			)
		else
			GameTooltip:AddLine("Commencer à créer le rosteur avec les candidatures reçues.", 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	configBtn:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	configBtn:SetScript("OnUpdate", function(self)
		if not self:IsVisible() then
			return
		end
		local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
		local rosteur = Rosteur and Rosteur.GetState and Rosteur.GetState(gid) or nil
		if rosteur and rosteur.phase == "prep" then
			local isLocked = fn.IsPrepConfigLocked and fn.IsPrepConfigLocked(rosteur)
			if isLocked then
				if self.Disable then
					self:Disable()
				elseif self.SetEnabled then
					self:SetEnabled(false)
				end
				UpdateConfigBtnTextState(true)
			else
				if self.Enable then
					self:Enable()
				elseif self.SetEnabled then
					self:SetEnabled(true)
				end
				UpdateConfigBtnTextState(false)
			end
		end
	end)

	-- =========================
	-- Manager: Config
	-- =========================
	local configPanel = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerConfig", managerPanel)
	configPanel:SetAllPoints(managerPanel)
	configPanel:Hide()

	sideArea = CreateFrame("Frame", "WoWGuilde_Rosteur_SideArea", configPanel)
	sideArea:SetPoint("TOPRIGHT", configPanel, "TOPRIGHT", -20, -20)
	sideArea:SetPoint("BOTTOMRIGHT", configPanel, "BOTTOMRIGHT", -20, 20)
	sideArea:SetWidth(240)

	local sideBg = sideArea:CreateTexture("WoWGuilde_Rosteur_SideBg", "BACKGROUND")
	sideBg:SetPoint("TOPLEFT", sideArea, "TOPLEFT", -10, 10)
	sideBg:SetPoint("BOTTOMRIGHT", sideArea, "BOTTOMRIGHT", 35, -10)
	sideBg:SetAtlas("glues-gameMode-BG")
	sideBg:SetAlpha(0.6)

	if fn.IsDevMode and fn.IsDevMode() then
		devDelete = CreateFrame("Button", "WoWGuilde_Rosteur_DevDelete", sideArea, "UIPanelButtonTemplate")
		devDelete:SetSize(160, 24)
		devDelete:SetPoint("BOTTOM", sideArea, "BOTTOM", 0, 8)
		devDelete:SetText("Supprimer rosteur")

		devToggle = CreateFrame("Button", "WoWGuilde_Rosteur_DevToggle", sideArea, "UIPanelButtonTemplate")
		devToggle:SetSize(140, 24)
		devToggle:SetPoint("BOTTOM", sideArea, "BOTTOM", 0, 38)
		devToggle:SetText("Vue: Auto")
	end

	local configContent = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerConfig_Content", configPanel)
	configContent:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 0, 0)
	configContent:SetPoint("BOTTOMLEFT", configPanel, "BOTTOMLEFT", 0, 0)
	configContent:SetPoint("RIGHT", sideArea, "LEFT", -12, 0)

	local configHeader = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerConfig_Header", configContent)
	configHeader:SetPoint("TOPLEFT", configContent, "TOPLEFT", 0, 0)
	configHeader:SetPoint("TOPRIGHT", configContent, "TOPRIGHT", 0, 0)
	configHeader:SetHeight(80)

	local rosterSelect =
		CreateFrame("DropdownButton", "WoWGuilde_Rosteur_RosterSelect", configHeader, "WowStyle1DropdownTemplate")
	rosterSelect:SetPoint("TOPLEFT", configHeader, "TOPLEFT", 0, -6)
	rosterSelect:SetSize(240, 25)
	rosterSelect:SetDefaultText("Rosteur actif")

	local validateBtn = CreateFrame("Button", "WoWGuilde_Rosteur_ValidateBtn", configHeader, "UIPanelButtonTemplate")
	validateBtn:SetSize(180, 28)
	validateBtn:SetPoint("TOPRIGHT", configHeader, "TOPRIGHT", 0, -6)
	validateBtn:SetText("Valider le rosteur")

	local summaryBtn =
		CreateFrame("Button", "WoWGuilde_Rosteur_ConfigSummaryBtn", configHeader, "UIPanelButtonTemplate")
	summaryBtn:SetSize(120, 26)
	summaryBtn:SetPoint("RIGHT", validateBtn, "LEFT", -8, 0)
	summaryBtn:SetText("Résumé")

	local templateSelect =
		CreateFrame("DropdownButton", "WoWGuilde_Rosteur_TemplateSelect", configHeader, "WowStyle1DropdownTemplate")
	templateSelect:SetPoint("TOPLEFT", rosterSelect, "BOTTOMLEFT", 0, -10)
	templateSelect:SetSize(200, 25)
	templateSelect:SetDefaultText("Préconfiguration")

	local createRosterBtn =
		CreateFrame("Button", "WoWGuilde_Rosteur_CreateRoster", configHeader, "UIPanelButtonTemplate")
	createRosterBtn:SetSize(160, 26)
	createRosterBtn:SetPoint("LEFT", templateSelect, "RIGHT", 12, 0)
	createRosterBtn:SetText("Créer un rosteur")

	local deleteRosterBtn =
		CreateFrame("Button", "WoWGuilde_Rosteur_DeleteRoster", configHeader, "UIPanelButtonTemplate")
	deleteRosterBtn:SetSize(160, 26)
	deleteRosterBtn:SetPoint("LEFT", createRosterBtn, "RIGHT", 8, 0)
	deleteRosterBtn:SetText("Supprimer rosteur")

	local rosterView = fn.MakeRosterView
		and fn.MakeRosterView(configContent, {
			namePrefix = "WoWGuilde_Rosteur_ConfigView",
			enableDrag = true,
			onDrop = function(role)
				local data = fn.GetDrag and fn.GetDrag() or nil
				if not data or not Rosteur then
					return
				end
				local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
				local rosteur = Rosteur.GetState and Rosteur.GetState(gid) or nil
				local activeId = rosteur and rosteur.activeRosterId or nil
				if not activeId then
					return
				end
				Rosteur.AssignEntry(gid, activeId, role, data)
				if fn.StopDrag then
					fn.StopDrag()
				end
			end,
		})
	if rosterView then
		rosterView:SetPoint("TOPLEFT", configHeader, "BOTTOMLEFT", 0, -10)
		rosterView:SetPoint("BOTTOMLEFT", configContent, "BOTTOMLEFT", 0, 0)
		rosterView:SetWidth(420)
	end

	local signupFrame = CreateFrame("Frame", "WoWGuilde_Rosteur_SignupFrame", configContent)
	signupFrame:SetPoint("TOPLEFT", rosterView, "TOPRIGHT", 20, 0)
	signupFrame:SetPoint("BOTTOMRIGHT", configContent, "BOTTOMRIGHT", 0, 0)

	local signupTitle = signupFrame:CreateFontString("WoWGuilde_Rosteur_SignupTitle", "OVERLAY", "GameFontNormal")
	signupTitle:SetPoint("TOPLEFT", signupFrame, "TOPLEFT", 0, -2)
	signupTitle:SetText("Demandes d'inscription")

	local signupScroll =
		CreateFrame("ScrollFrame", "WoWGuilde_Rosteur_SignupScroll", signupFrame, "QuestScrollFrameTemplate")
	signupScroll:SetPoint("TOPLEFT", signupTitle, "BOTTOMLEFT", 0, -8)
	signupScroll:SetPoint("BOTTOMRIGHT", signupFrame, "BOTTOMRIGHT", -24, 60)

	local signupContent = CreateFrame("Frame", "WoWGuilde_Rosteur_SignupContent", signupScroll)
	signupScroll:SetScrollChild(signupContent)

	local signupDrop = CreateFrame("Frame", "WoWGuilde_Rosteur_SignupDrop", signupFrame)
	signupDrop:SetPoint("TOPLEFT", signupScroll, "TOPLEFT", 0, 0)
	signupDrop:SetPoint("BOTTOMRIGHT", signupScroll, "BOTTOMRIGHT", 0, 0)
	signupDrop:SetScript("OnReceiveDrag", function()
		local data = fn.GetDrag and fn.GetDrag() or nil
		if data and data.source == "roster" and Rosteur then
			local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
			Rosteur.UnassignEntry(gid, data.rosterId, data.id)
			if fn.StopDrag then
				fn.StopDrag()
			end
		end
	end)
	signupDrop:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then
			local data = fn.GetDrag and fn.GetDrag() or nil
			if data and data.source == "roster" and Rosteur then
				local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
				Rosteur.UnassignEntry(gid, data.rosterId, data.id)
				if fn.StopDrag then
					fn.StopDrag()
				end
			end
		end
	end)

	state.signupPool = {}
	state.signupEntries = {}

	local puBox = CreateFrame("EditBox", "WoWGuilde_Rosteur_PUBox", signupFrame, "InputBoxTemplate")
	puBox:SetAutoFocus(false)
	puBox:SetSize(160, 24)
	puBox:SetPoint("BOTTOMLEFT", signupFrame, "BOTTOMLEFT", 0, 10)
	local PU_PLACEHOLDER = const.PU_PLACEHOLDER or "Nom du PU"
	const.PU_PLACEHOLDER = PU_PLACEHOLDER
	puBox:SetText(PU_PLACEHOLDER)
	puBox:SetCursorPosition(0)
	puBox:SetScript("OnEditFocusGained", function(self)
		if self:GetText() == PU_PLACEHOLDER then
			self:SetText("")
		end
	end)
	puBox:SetScript("OnEditFocusLost", function(self)
		if self:GetText() == "" then
			self:SetText(PU_PLACEHOLDER)
		end
	end)

	local puRole = CreateFrame("DropdownButton", "WoWGuilde_Rosteur_PURole", signupFrame, "WowStyle1DropdownTemplate")
	puRole:SetPoint("LEFT", puBox, "RIGHT", 8, 0)
	puRole:SetSize(120, 24)
	puRole:SetDefaultText("DPS")
	puRole._value = "DPS"
	puRole:SetupMenu(function(_, root)
		for _, role in ipairs(ROLE_ORDER) do
			root:CreateButton(ROLE_LABEL[role] or role, function()
				puRole._value = role
				puRole:SetDefaultText(ROLE_LABEL[role] or role)
			end, {
				isRadio = true,
				checked = function()
					return puRole._value == role
				end,
			})
		end
	end)

	local puAddBtn = CreateFrame("Button", "WoWGuilde_Rosteur_PUAdd", signupFrame, "UIPanelButtonTemplate")
	puAddBtn:SetSize(90, 24)
	puAddBtn:SetPoint("LEFT", puRole, "RIGHT", 8, 0)
	puAddBtn:SetText("Ajouter")

	-- =========================
	-- Manager: Locked
	-- =========================
	local lockedPanel = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerLocked", managerPanel)
	lockedPanel:SetAllPoints(managerPanel)
	lockedPanel:Hide()

	local lockedTitle =
		lockedPanel:CreateFontString("WoWGuilde_Rosteur_ManagerLocked_Title", "OVERLAY", "GameFontNormalLarge")
	lockedTitle:SetPoint("TOPLEFT", lockedPanel, "TOPLEFT", 0, -10)
	lockedTitle:SetText("Rosteur validé")

	local lockedView = fn.MakeRosterView
		and fn.MakeRosterView(lockedPanel, { namePrefix = "WoWGuilde_Rosteur_LockedView", enableDrag = false })
	if lockedView then
		lockedView:SetPoint("TOPLEFT", lockedTitle, "BOTTOMLEFT", 0, -10)
		lockedView:SetPoint("BOTTOMRIGHT", lockedPanel, "BOTTOMRIGHT", 0, 0)
	end

	ui.managerIdle = idlePanel
	ui.managerPrep = prepPanel
	ui.managerConfig = configPanel
	ui.managerLocked = lockedPanel
	ui.startBtn = startBtn
	ui.configBtn = configBtn
	ui.rosterSelect = rosterSelect
	ui.validateBtn = validateBtn
	ui.summaryBtn = summaryBtn
	ui.templateSelect = templateSelect
	ui.createRosterBtn = createRosterBtn
	ui.deleteRosterBtn = deleteRosterBtn
	ui.rosterView = rosterView
	ui.signupFrame = signupFrame
	ui.signupScroll = signupScroll
	ui.signupContent = signupContent
	ui.signupDrop = signupDrop
	ui.puBox = puBox
	ui.puRole = puRole
	ui.puAddBtn = puAddBtn
	ui.sideArea = sideArea
	ui.sideInfo = sideInfo
	ui.sideHint = sideHint
	ui.devToggle = devToggle
	ui.devDelete = devDelete
	ui.lockedView = lockedView
end

return M
