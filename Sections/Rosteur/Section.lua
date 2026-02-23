local ADDON, ns = ...

ns.Sections = ns.Sections or {}
local Sections = ns.Sections

local Rosteur = ns.Rosteur
local Utils = ns.Utils
local DB = ns.DB
local EventBus = ns.EventBus

local ROLE_ORDER = { "TANK", "HEAL", "DPS" }
local ROLE_LABEL = { TANK = "Protection", HEAL = "Soins", DPS = "Dégâts" }
local PREP_CONFIG_MIN_WAIT_SECONDS = 2 * 24 * 60 * 60
local ROLE_ATLAS = {
	TANK = "UI-LFG-RoleIcon-Tank",
	HEAL = "UI-LFG-RoleIcon-Healer",
	DPS = "UI-LFG-RoleIcon-DPS",
}
local sidebarCollapsed = { TANK = true, HEAL = true, DPS = true }
local pendingStartConfigGuildUID = nil

local Core = ns.RosteurSectionCore
if not (Core and Core.Build) then
	error("WoWGuilde_Rosteur: module SectionCore introuvable")
end

local core = Core.Build({
	Utils = Utils,
	DB = DB,
	ROLE_ORDER = ROLE_ORDER,
	ROLE_LABEL = ROLE_LABEL,
	ROLE_ATLAS = ROLE_ATLAS,
	PREP_CONFIG_MIN_WAIT_SECONDS = PREP_CONFIG_MIN_WAIT_SECONDS,
})

local TrimSpaces = core.TrimSpaces
local IsPrepConfigLocked = core.IsPrepConfigLocked
local IsDevMode = core.IsDevMode
local GetGuildUID = core.GetGuildUID
local GetMyFull = core.GetMyFull
local GetMySignupMeta = core.GetMySignupMeta
local ColorizeName = core.ColorizeName
local GetPseudoAlias = core.GetPseudoAlias
local StartDrag = core.StartDrag
local StopDrag = core.StopDrag
local StopDragDeferred = core.StopDragDeferred
local GetDrag = core.GetDrag
local IsMyRaidLeaderIdentity = core.IsMyRaidLeaderIdentity
local NormalizeHeroKey = core.NormalizeHeroKey
local CountAssignedEntries = core.CountAssignedEntries
local MaxNumericIndex = core.MaxNumericIndex
local MakeRosterView = core.MakeRosterView
local CreateSimpleList = core.CreateSimpleList
local NormalizeRoleTag = core.NormalizeRoleTag

function Sections.Rosteur(parent)
	local f = CreateFrame("Frame", "WoWGuilde_Rosteur", parent)
	f:SetAllPoints(parent)
	f:Hide()

	local HEADER_HEIGHT = 50
	local BG_PAD_L, BG_PAD_T, BG_PAD_R, BG_PAD_B = 3, -8, 0, 0
	local WOOD_PAD_L, WOOD_PAD_R, WOOD_PAD_T, WOOD_PAD_B = 3, 0, -4, 0
	local WOOD_HEIGHT = 50

	f.bgFrame = CreateFrame("Frame", "WoWGuilde_Rosteur_BgFrame", f)
	f.bgFrame:SetAllPoints(f)
	f.bgFrame:SetFrameLevel(100)

	f.topShadow = f.bgFrame:CreateTexture("WoWGuilde_Rosteur_TopShadow", "BORDER")
	f.topShadow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(HEADER_HEIGHT + 2))
	f.topShadow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(HEADER_HEIGHT + 2))
	f.topShadow:SetHeight(170)
	f.topShadow:SetAtlas("Artifacts-HeaderBG")
	f.topShadow:SetAlpha(0.6)

	f.bg = f.bgFrame:CreateTexture("WoWGuilde_Rosteur_Bg", "BACKGROUND", nil, -2)
	f.bg:SetPoint("TOPLEFT", f.bgFrame, "TOPLEFT", BG_PAD_L, BG_PAD_T)
	f.bg:SetPoint("BOTTOMRIGHT", f.bgFrame, "BOTTOMRIGHT", BG_PAD_R, BG_PAD_B)
	f.bg:SetDrawLayer("BACKGROUND", -2)
	f.bg:SetAtlas("auctionhouse-background-index")
	f.bg:SetAlpha(1)

	f.topDecor = f.bgFrame:CreateTexture("WoWGuilde_Rosteur_TopDecor", "BACKGROUND", nil, -1)
	f.topDecor:SetPoint("TOPLEFT", f, "TOPLEFT", WOOD_PAD_L, WOOD_PAD_T)
	f.topDecor:SetPoint("TOPRIGHT", f, "TOPRIGHT", WOOD_PAD_R, WOOD_PAD_B)
	f.topDecor:SetAtlas("wood-topper", false)
	f.topDecor:SetHeight(WOOD_HEIGHT)
	f.topDecor:SetTexCoord(0.15, 1, 0, 1)

	f.topLine = f.bgFrame:CreateTexture("WoWGuilde_Rosteur_TopLine", "BORDER")
	f.topLine:SetPoint("BOTTOMLEFT", f, "TOPLEFT", -2, -(HEADER_HEIGHT + 4))
	f.topLine:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 12, -(HEADER_HEIGHT + 4))
	f.topLine:SetHeight(2)
	f.topLine:SetAtlas("LevelUp-Glow-Gold")
	f.topLine:SetBlendMode("ADD")
	f.topLine:SetAlpha(0.85)

	local headerArea = CreateFrame("Frame", "WoWGuilde_Rosteur_HeaderArea", f)
	headerArea:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -2)
	headerArea:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -12)
	headerArea:SetHeight(HEADER_HEIGHT)

	local title = headerArea:CreateFontString("WoWGuilde_Rosteur_Title", "OVERLAY", nil, 2)
	title:SetPoint("TOPLEFT", headerArea, "TOPLEFT", 10, -8)
	title:SetFont("Fonts\\2002.ttf", 20, "OUTLINE")
	title:SetTextColor(0.894, 0.655, 0.125)
	title:SetText("Raid grubu yonetimi")

	local subtitle = headerArea:CreateFontString("WoWGuilde_Rosteur_Subtitle", "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
	subtitle:SetPoint("RIGHT", headerArea, "RIGHT", -10, 0)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetText("Hazirlik, kayit ve roster ayarlari")

	local mainArea = CreateFrame("Frame", "WoWGuilde_Rosteur_MainArea", f)
	mainArea:SetPoint("TOPLEFT", headerArea, "BOTTOMLEFT", 0, -6)
	mainArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 0)

	local sideArea = nil
	local sideInfo = nil
	local sideHint = nil
	local devToggle = nil
	local devDelete = nil

	local managerPanel = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerPanel", mainArea)
	managerPanel:Hide()

	local playerPanel = CreateFrame("Frame", "WoWGuilde_Rosteur_PlayerPanel", mainArea)
	playerPanel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
	playerPanel:SetPoint("BOTTOMRIGHT", mainArea, "BOTTOMRIGHT", -10, 10)
	playerPanel:Hide()

	local resetZeroBtn = CreateFrame("Button", "WoWGuilde_Rosteur_ResetToZero", f)
	resetZeroBtn:SetSize(22, 22)
	resetZeroBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -15, -65)
	resetZeroBtn.icon = resetZeroBtn:CreateTexture("WoWGuilde_Rosteur_ResetToZero_Icon", "ARTWORK")
	resetZeroBtn.icon:SetSize(22, 22)
	resetZeroBtn.icon:SetPoint("CENTER", resetZeroBtn, "CENTER", 0, 0)
	resetZeroBtn.icon:SetAtlas("common-icon-undo", true)
	resetZeroBtn.highlight = resetZeroBtn:CreateTexture("WoWGuilde_Rosteur_ResetToZero_Highlight", "HIGHLIGHT")
	resetZeroBtn.highlight:SetAllPoints(resetZeroBtn.icon)
	resetZeroBtn.highlight:SetAtlas("common-icon-undo", true)
	resetZeroBtn.highlight:SetBlendMode("ADD")
	resetZeroBtn.highlight:SetAlpha(0.45)
	resetZeroBtn:SetScript("OnEnter", function(self)
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("Tum roster kayitlarini sil.")
		GameTooltip:Show()
	end)
	resetZeroBtn:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)

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
	idleTitle:SetFont("Fonts\\2002.ttf", 32, "OUTLINE")
	idleTitle:SetText("Raid sezonu baslat")

	local idleDesc = idlePanel:CreateFontString("WoWGuilde_Rosteur_ManagerIdle_Desc", "OVERLAY", "GameFontHighlight")
	idleDesc:SetPoint("TOP", idleTitle, "BOTTOM", 0, -12)
	idleDesc:SetWidth(520)
	idleDesc:SetJustifyH("CENTER")
	idleDesc:SetText(
		"Kayitlari ac, istenen rolleri topla ve gelecek sezon icin raid grubunu hazirla."
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
	startBtn:SetText("Raid sezonu hazirla")
	startBtn:SetNormalFontObject("GameFontHighlightLarge")

	local idleNote =
		idlePanel:CreateFontString("WoWGuilde_Rosteur_ManagerIdle_Note", "OVERLAY", "GameFontHighlightSmall")
	idleNote:SetPoint("TOP", startBtn, "BOTTOM", 0, -20)
	idleNote:SetText("Tum guild icin kayitlari acar.")

	-- =========================
	-- Manager: Prep
	-- =========================
	local prepPanel = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerPrep", managerPanel)
	prepPanel:SetAllPoints(managerPanel)
	prepPanel:Hide()

	local showPrepSummary = false
	local showManagerEmpty = false

	local prepLayout = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerPrep_Layout", prepPanel)
	prepLayout:SetPoint("TOPLEFT", prepPanel, "TOPLEFT", 10, -10)
	prepLayout:SetPoint("BOTTOMRIGHT", prepPanel, "BOTTOMRIGHT", -10, 70)

	local prepSections = {}
	local prepSummaryData = {}
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
			title = "DPS",
			desc = "Ana hasar verir.",
			atlas = ROLE_ATLAS.DPS,
		},
		{
			role = "TANK",
			title = "Tank",
			desc = "Hasar alir ve grubu korur.",
			atlas = ROLE_ATLAS.TANK,
		},
		{
			role = "HEAL",
			title = "Heal",
			desc = "Destek olur ve ekibi iyilestirir.",
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
		-- Flip via vertex to invert the shadow
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
		section.applyBtn:SetText("Basvur")
		section.applyBtn:SetScript("OnClick", function()
			local gid = GetGuildUID()
			if not gid or not Rosteur then
				return
			end
			local full, meta = GetMySignupMeta(gid)
			if not full or full == "" then
				return
			end
			local allowed = ns
				and ns.UI
				and ns.UI.GetAllowedRoles
				and ns.UI.GetAllowedRoles(meta.classTag, meta.spec, meta.specID)
			if allowed and next(allowed) and not allowed[role] then
				if UIErrorsFrame and UIErrorsFrame.AddMessage then
					UIErrorsFrame:AddMessage("Bu rol bu karakter icin uygun degil.", 1, 0.2, 0.2, 1)
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
		section.removeBtn:SetText("Cikar")
		section.removeBtn:Hide()

		prepSections[role] = section
		prepSummaryData[role] = { heroes = {}, order = {} }
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
		local data = prepSummaryData[role]
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
						local colored = ColorizeName(charName, entry.classTag)
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
	-- Rotation 90° via texcoord (rotation atlas unreliable in some contexts)
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
	configBtn:SetText("Roster olustur")
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
	configBtn:SetScript("OnEnter", function(self)
		if not GameTooltip then
			return
		end
		local gid = GetGuildUID()
		local rosteur = Rosteur and Rosteur.GetState and Rosteur.GetState(gid) or nil
		local isLocked, remaining = IsPrepConfigLocked(rosteur)
		local forceByShift = (remaining or 0) > 0 and IsShiftKeyDown and IsShiftKeyDown()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint("BOTTOM", self, "TOP", 0, 25)
		GameTooltip:ClearLines()
		GameTooltip:AddLine("Roster olustur", 1, 0.82, 0, false)
		if rosteur and rosteur.phase == "prep" and isLocked then
			GameTooltip:AddLine(
				"Roster olusturmaya baslamadan once en az 2 gun bekle.",
				1,
				1,
				1,
				true
			)
		elseif rosteur and rosteur.phase == "prep" and forceByShift then
			GameTooltip:AddLine(
				"Roster olusturmaya baslamadan once en az 2 gun bekle.\n\nYine de Shift basili tutarak zorlayabilirsin.",
				1,
				1,
				1,
				true
			)
		else
			GameTooltip:AddLine("Gelen basvurularla roster olusturmaya basla.", 1, 1, 1, true)
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
		local gid = GetGuildUID()
		local rosteur = Rosteur and Rosteur.GetState and Rosteur.GetState(gid) or nil
		if rosteur and rosteur.phase == "prep" then
			local isLocked = IsPrepConfigLocked(rosteur)
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
	sideArea:SetPoint("TOPRIGHT", configPanel, "TOPRIGHT", -48, -20)
	sideArea:SetPoint("BOTTOMRIGHT", configPanel, "BOTTOMRIGHT", -48, 1)
	sideArea:SetWidth(220)

	local sideBg = sideArea:CreateTexture("WoWGuilde_Rosteur_SideBg", "BACKGROUND")
	sideBg:SetPoint("TOPLEFT", sideArea, "TOPLEFT", -10, 10)
	sideBg:SetPoint("BOTTOMRIGHT", sideArea, "BOTTOMRIGHT", 35, -10)
	sideBg:SetAtlas("glues-gameMode-BG")
	sideBg:SetAlpha(0.6)

	local sideTitle = sideArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	sideTitle:SetPoint("TOPLEFT", sideArea, "TOPLEFT", 8, -6)
	sideTitle:SetPoint("TOPRIGHT", sideArea, "TOPRIGHT", -8, -6)
	sideTitle:SetJustifyH("CENTER")
	sideTitle:SetText("Liste des candidatures")

	local validateBtn =
		CreateFrame("Button", "WoWGuilde_Rosteur_ValidateBtn", sideArea, "BigRedThreeSliceButtonTemplate")
	validateBtn:SetHeight(28)
	validateBtn:SetPoint("BOTTOMLEFT", sideArea, "BOTTOMLEFT", 8, 8)
	validateBtn:SetPoint("BOTTOMRIGHT", sideArea, "BOTTOMRIGHT", -8, 8)
	if validateBtn.SetNormalFontObject then
		validateBtn:SetNormalFontObject("GameFontHighlight")
	end
	if validateBtn.Text then
		validateBtn.Text:SetTextColor(1, 0.82, 0, 1)
	end
	validateBtn:SetText("Roster onayla")

	local sideScroll = CreateFrame("ScrollFrame", "WoWGuilde_Rosteur_SideScroll", sideArea, "QuestScrollFrameTemplate")
	sideScroll:SetPoint("TOPLEFT", sideTitle, "BOTTOMLEFT", 0, -14)
	sideScroll:SetPoint("TOPRIGHT", sideArea, "TOPRIGHT", -4, -8)
	sideScroll:SetPoint("BOTTOMLEFT", validateBtn, "TOPLEFT", 0, 12)
	sideScroll:SetPoint("BOTTOMRIGHT", validateBtn, "TOPRIGHT", 0, 12)

	local sideContent = CreateFrame("Frame", "WoWGuilde_Rosteur_SideContent", sideScroll)
	sideContent:SetPoint("TOPLEFT")
	sideContent:SetPoint("TOPRIGHT")
	sideContent:SetWidth(1)
	sideContent:SetHeight(1)
	sideScroll:SetScrollChild(sideContent)
	sideScroll:SetScript("OnSizeChanged", function(self, w)
		if w and w > 0 then
			sideContent:SetWidth(w)
		end
	end)
	if sideScroll.GetWidth then
		local w = sideScroll:GetWidth() or 0
		if w > 0 then
			sideContent:SetWidth(w)
		end
	end

	local sideSections = {}
	local sidebarRosteur = nil

	local configContent = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerConfig_Content", configPanel)
	configContent:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 0, 0)
	configContent:SetPoint("BOTTOMLEFT", configPanel, "BOTTOMLEFT", 0, 0)
	configContent:SetPoint("RIGHT", sideArea, "LEFT", -8, 0)

	local rosterSelect, summaryBtn, templateSelect, createRosterBtn, deleteRosterBtn = nil
	local rosterView, signupFrame, signupTitle, signupScroll, signupDrop = nil
	local signupPool, signupEntries = nil
	local puBox, puRole, puAddBtn = nil
	local PU_PLACEHOLDER = "Nom du joueur externe"

	local configEmpty = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerConfig_Empty", configContent)
	configEmpty:SetAllPoints(configContent)

	local emptyTitle = configEmpty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	emptyTitle:SetPoint("CENTER", configEmpty, "CENTER", 0, 80)
	emptyTitle:SetFont("Fonts\\2002.ttf", 25, "OUTLINE")
	emptyTitle:SetTextColor(1, 0.659, 0, 1)
	emptyTitle:SetText("Raid grubu ayarlanmis degil")

	local emptyDropdown =
		CreateFrame("DropdownButton", "WoWGuilde_Rosteur_EmptyTemplateSelect", configEmpty, "WowStyle1DropdownTemplate")
	emptyDropdown:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -18)
	emptyDropdown:SetSize(200, 26)
	emptyDropdown:SetScale(1)
	emptyDropdown:SetDefaultText("Préconfiguration")
	emptyDropdown._value = nil

	local emptyDesc = configEmpty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyDesc:SetPoint("TOP", emptyDropdown, "BOTTOM", 0, -12)
	emptyDesc:SetPoint("LEFT", configEmpty, "LEFT", 60, 0)
	emptyDesc:SetPoint("RIGHT", configEmpty, "RIGHT", -60, 0)
	emptyDesc:SetJustifyH("CENTER")
	emptyDesc:SetText(
		"Créez une configuration de raid à partir d'une préconfiguration.\n"
			.. "Cela définit la structure (rôles, places) et permet d'organiser les candidatures."
	)

	local configSelect =
		CreateFrame("DropdownButton", "WoWGuilde_Rosteur_ConfigSelect", configEmpty, "WowStyle1DropdownTemplate")
	configSelect:SetPoint("BOTTOMRIGHT", sideArea, "TOPRIGHT", 30, 35)
	configSelect:SetSize(240, 26)
	configSelect:SetScale(1)
	configSelect:SetDefaultText("Choisir une configuration")
	configSelect._value = nil
	local configUI = nil
	do
		local ConfigUI = ns.RosteurSectionConfig
		if ConfigUI and type(ConfigUI.Build) == "function" then
			local ok, built = pcall(ConfigUI.Build, {
				Rosteur = Rosteur,
				Utils = Utils,
				DB = DB,
				ROLE_ORDER = ROLE_ORDER,
				ROLE_ATLAS = ROLE_ATLAS,
				GetGuildUID = GetGuildUID,
				CountAssignedEntries = CountAssignedEntries,
				TrimSpaces = TrimSpaces,
				NormalizeRoleTag = NormalizeRoleTag,
				emptyDropdown = emptyDropdown,
				configSelect = configSelect,
				emptyTitle = emptyTitle,
				configEmpty = configEmpty,
				sideArea = sideArea,
				requestRefresh = function()
					if f and f.Refresh then
						f.Refresh()
					end
				end,
			})
			if ok and type(built) == "table" then
				configUI = built
			end
		end
	end
	if not configUI then
		local function FallbackResolveActiveRoster(gid)
			local rosteur = Rosteur and Rosteur.GetState and Rosteur.GetState(gid) or nil
			if not (rosteur and type(rosteur.rosters) == "table") then
				return nil, rosteur
			end
			local activeId = rosteur.activeRosterId
			if not activeId then
				return nil, rosteur
			end
			for i = 1, #rosteur.rosters do
				local r = rosteur.rosters[i]
				if r and r.id == activeId then
					return r, rosteur
				end
			end
			return nil, rosteur
		end
		local function FallbackComputeRosterMissing(active)
			local missing = { TANK = 0, HEAL = 0, DPS = 0 }
			if type(active) ~= "table" then
				return missing, 0
			end
			local groups = active.groups or {}
			local targets = active.targets or {}
			local total = 0
			for _, role in ipairs(ROLE_ORDER) do
				local target = tonumber(targets[role] or 0) or 0
				if role == "TANK" and target <= 0 then
					target = 2
				end
				local current = CountAssignedEntries(groups[role])
				local miss = math.max(0, target - current)
				missing[role] = miss
				total = total + miss
			end
			return missing, total
		end
		local function FallbackBuildMissingText(missing)
			local parts = {}
			if (missing.TANK or 0) > 0 then
				parts[#parts + 1] = tostring(missing.TANK) .. " Protection"
			end
			if (missing.HEAL or 0) > 0 then
				parts[#parts + 1] = tostring(missing.HEAL) .. " Soins"
			end
			if (missing.DPS or 0) > 0 then
				parts[#parts + 1] = tostring(missing.DPS) .. " Dégâts"
			end
			return table.concat(parts, ", ")
		end
		local function FallbackFillRosterMissingWithPU(gid, active, missing)
			if not (gid and active and active.id and Rosteur and Rosteur.AddPU) then
				return
			end
			for _, role in ipairs(ROLE_ORDER) do
				local count = tonumber(missing[role] or 0) or 0
				for i = 1, count do
					Rosteur.AddPU(gid, active.id, role, "Externe " .. tostring(i))
				end
			end
		end
		local function FallbackSetConfigEmptyTitleLayout(hasRoster)
			if not (emptyTitle and configEmpty and configSelect) then
				return
			end
			emptyTitle:ClearAllPoints()
			configSelect:ClearAllPoints()
			if hasRoster then
				emptyTitle:SetPoint("RIGHT", configSelect, "LEFT", -10, 0)
				configSelect:SetPoint("BOTTOMRIGHT", sideArea, "TOPRIGHT", 30, 35)
			else
				emptyTitle:SetPoint("CENTER", configEmpty, "CENTER", 0, 80)
				configSelect:SetPoint("TOPLEFT", configEmpty, "TOPLEFT", 20, -20)
			end
		end
		configUI = {
			SetCreatePopupExtrasShown = function() end,
			ResolveActiveRoster = FallbackResolveActiveRoster,
			ComputeRosterMissing = FallbackComputeRosterMissing,
			BuildMissingText = FallbackBuildMissingText,
			FillRosterMissingWithPU = FallbackFillRosterMissingWithPU,
			SetConfigEmptyTitleLayout = FallbackSetConfigEmptyTitleLayout,
			SetupConfigSelectDropdown = function() end,
			SetupEmptyTemplateDropdown = function() end,
		}
	end

	local SetCreatePopupExtrasShown = configUI.SetCreatePopupExtrasShown
	local ResolveActiveRoster = configUI.ResolveActiveRoster
	local ComputeRosterMissing = configUI.ComputeRosterMissing
	local BuildMissingText = configUI.BuildMissingText
	local FillRosterMissingWithPU = configUI.FillRosterMissingWithPU
	local SetConfigEmptyTitleLayout = configUI.SetConfigEmptyTitleLayout
	local SetupConfigSelectDropdown = configUI.SetupConfigSelectDropdown
	local SetupEmptyTemplateDropdown = configUI.SetupEmptyTemplateDropdown

	local function EntryId(entry)
		if type(entry) ~= "table" then
			return nil
		end
		return entry.id or entry.full
	end

	local function GetSignupRoles(entry)
		local out = {}
		if type(entry) ~= "table" then
			return out
		end
		if type(entry.roles) == "table" then
			for k, v in pairs(entry.roles) do
				local role = NormalizeRoleTag(k)
				if role and v then
					out[role] = true
				end
			end
		end
		local fallback = NormalizeRoleTag(entry.role)
		if fallback then
			out[fallback] = true
		end
		return out
	end

	local function SignupHasRole(entry, role)
		local normRole = NormalizeRoleTag(role)
		if not normRole then
			return false
		end
		local roles = GetSignupRoles(entry)
		return roles[normRole] == true
	end

	local function CanEntryDropOnRole(entry, targetRole)
		local slotRole = NormalizeRoleTag(targetRole)
		if not slotRole then
			return false
		end
		local requestedRole = NormalizeRoleTag(entry and entry.requestedRole)
		if requestedRole then
			return requestedRole == slotRole
		end
		if not SignupHasRole(entry, slotRole) then
			return false
		end
		return true
	end

	local function ShowDropRoleError()
		if UIErrorsFrame and UIErrorsFrame.AddMessage then
			UIErrorsFrame:AddMessage("Bu karakter bu rol icin basvurmedi.", 1, 0.2, 0.2, 1)
		end
	end

	rosterView = MakeRosterView(configContent, {
		namePrefix = "WoWGuilde_Rosteur_View",
		layout = "builder",
		enableDrag = true,
		onDrop = function(slotRole, slotIndex)
			local drag = GetDrag()
			if type(drag) ~= "table" then
				return
			end
			local gid = GetGuildUID()
			if not (gid and Rosteur) then
				StopDrag()
				return
			end
			local active = ResolveActiveRoster and ResolveActiveRoster(gid) or nil
			if not (type(active) == "table" and active.id) then
				StopDrag()
				return
			end
			local role = NormalizeRoleTag(slotRole)
			local index = tonumber(slotIndex)
			if not (role and index) then
				StopDrag()
				return
			end
			index = math.max(1, math.floor(index))

			if not CanEntryDropOnRole(drag, role) then
				ShowDropRoleError()
				StopDrag()
				return
			end

			local groups = type(active.groups) == "table" and active.groups or {}
			local targetList = type(groups[role]) == "table" and groups[role] or {}
			local targetEntry = targetList[index]

			if drag.source == "roster" then
				if drag.rosterId and active.id and drag.rosterId ~= active.id then
					StopDrag()
					return
				end
				local sourceRole = NormalizeRoleTag(drag.slotRole)
				local sourceIndex = tonumber(drag.slotIndex)
				if not (sourceRole and sourceIndex) then
					StopDrag()
					return
				end
				sourceIndex = math.max(1, math.floor(sourceIndex))
				if sourceRole == role and sourceIndex == index then
					StopDrag()
					return
				end

				local sourceList = type(groups[sourceRole]) == "table" and groups[sourceRole] or {}
				local sourceEntry = sourceList[sourceIndex] or drag
				local sourceId = EntryId(sourceEntry)
				local targetId = EntryId(targetEntry)
				if not sourceId then
					StopDrag()
					return
				end

				if targetEntry and targetId and targetId ~= sourceId then
					Rosteur.AssignEntry(gid, active.id, sourceRole, targetEntry, sourceIndex)
				end
				Rosteur.AssignEntry(gid, active.id, role, sourceEntry, index)
				StopDrag()
				return
			end

			local replaced = targetEntry
			if replaced then
				local replacedId = EntryId(replaced)
				if replacedId then
					Rosteur.UnassignEntry(gid, active.id, replacedId)
				end
				if not replaced.isPU and Rosteur.RestoreSignupCluster then
					Rosteur.RestoreSignupCluster(gid, replaced, active.id)
				end
			end

			local assigned = Rosteur.AssignEntry(gid, active.id, role, drag, index)
			if assigned and not drag.isPU and Rosteur.HideSignupCluster then
				Rosteur.HideSignupCluster(gid, drag, active.id)
			end
			StopDrag()
		end,
		onUnassign = function(entry)
			if type(entry) ~= "table" then
				return
			end
			local gid = GetGuildUID()
			if not (gid and Rosteur) then
				StopDrag()
				return
			end
			local active = ResolveActiveRoster and ResolveActiveRoster(gid) or nil
			if not (type(active) == "table" and active.id) then
				StopDrag()
				return
			end
			local entryId = EntryId(entry)
			if entryId then
				Rosteur.UnassignEntry(gid, active.id, entryId)
				if not entry.isPU and Rosteur.RestoreSignupCluster then
					Rosteur.RestoreSignupCluster(gid, entry, active.id)
				end
			end
			StopDrag()
		end,
	})
	rosterView:SetPoint("TOPLEFT", configContent, "TOPLEFT", 0, 0)
	rosterView:SetPoint("BOTTOMRIGHT", configContent, "BOTTOMRIGHT", 0, 0)
	rosterView:Hide()

	-- =========================
	-- Manager: Locked
	-- =========================
	local lockedPanel = CreateFrame("Frame", "WoWGuilde_Rosteur_ManagerLocked", managerPanel)
	lockedPanel:SetAllPoints(managerPanel)
	lockedPanel:Hide()

	local lockedTitle =
		lockedPanel:CreateFontString("WoWGuilde_Rosteur_ManagerLocked_Title", "OVERLAY", "GameFontNormalLarge")
	lockedTitle:SetPoint("TOPLEFT", lockedPanel, "TOPLEFT", 0, -10)
	lockedTitle:SetText("Roster onaylandi")

	local lockedView = MakeRosterView(lockedPanel, { namePrefix = "WoWGuilde_Rosteur_LockedView", enableDrag = false })
	lockedView:SetPoint("TOPLEFT", lockedTitle, "BOTTOMLEFT", 0, -10)
	lockedView:SetPoint("BOTTOMRIGHT", lockedPanel, "BOTTOMRIGHT", 0, 0)

	-- =========================
	-- Player: Idle
	-- =========================
	local playerIdle = CreateFrame("Frame", "WoWGuilde_Rosteur_PlayerIdle", playerPanel)
	playerIdle:SetAllPoints(playerPanel)

	local playerIdleText =
		playerIdle:CreateFontString("WoWGuilde_Rosteur_PlayerIdle_Text", "OVERLAY", "GameFontHighlight")
	playerIdleText:SetPoint("TOPLEFT", playerIdle, "TOPLEFT", 0, -20)
	playerIdleText:SetText("Aktif raid hazirligi yok.")

	local playerConfig = CreateFrame("Frame", "WoWGuilde_Rosteur_PlayerConfig", playerPanel)
	playerConfig:SetAllPoints(playerPanel)
	playerConfig:Hide()

	local playerConfigText =
		playerConfig:CreateFontString("WoWGuilde_Rosteur_PlayerConfig_Text", "OVERLAY", "GameFontHighlight")
	playerConfigText:SetPoint("TOPLEFT", playerConfig, "TOPLEFT", 0, -20)
	playerConfigText:SetText("Roster ayarlaniyor.")

	-- =========================
	-- Player: Signup
	-- =========================
	local playerSignup = CreateFrame("Frame", "WoWGuilde_Rosteur_PlayerSignup", playerPanel)
	playerSignup:SetAllPoints(playerPanel)
	playerSignup:Hide()

	local playerTitle =
		playerSignup:CreateFontString("WoWGuilde_Rosteur_PlayerSignup_Title", "OVERLAY", "GameFontNormalLarge")
	playerTitle:SetPoint("TOPLEFT", playerSignup, "TOPLEFT", 0, -10)
	playerTitle:SetText("Raid kaydi")

	local playerCounts =
		playerSignup:CreateFontString("WoWGuilde_Rosteur_PlayerSignup_Counts", "OVERLAY", "GameFontHighlight")
	playerCounts:SetPoint("TOPLEFT", playerTitle, "BOTTOMLEFT", 0, -6)
	playerCounts:SetText("Tank: 0 | Heal: 0 | DPS: 0")

	local roleButtons = {}
	local function CreateRoleButton(role, x)
		local btnName = "WoWGuilde_Rosteur_PlayerRole_" .. role
		local btn = CreateFrame("Button", btnName, playerSignup, "UIPanelButtonTemplate")
		btn:SetSize(150, 36)
		btn:SetPoint("TOPLEFT", playerCounts, "BOTTOMLEFT", x, -16)
		btn:SetText(ROLE_LABEL[role] or role)
		btn.role = role
		btn.icon = btn:CreateTexture(btnName .. "_Icon", "ARTWORK")
		btn.icon:SetSize(16, 16)
		btn.icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
		btn.icon:SetAtlas(ROLE_ATLAS[role], true)
		roleButtons[role] = btn
		return btn
	end

	CreateRoleButton("TANK", 0)
	CreateRoleButton("HEAL", 170)
	CreateRoleButton("DPS", 340)

	local playerChoice =
		playerSignup:CreateFontString("WoWGuilde_Rosteur_PlayerSignup_Choice", "OVERLAY", "GameFontHighlightSmall")
	playerChoice:SetPoint("TOPLEFT", roleButtons.TANK, "BOTTOMLEFT", 0, -10)
	playerChoice:SetText("Secimlerin: -")

	local playerClear =
		CreateFrame("Button", "WoWGuilde_Rosteur_PlayerSignup_Clear", playerSignup, "UIPanelButtonTemplate")
	playerClear:SetSize(120, 24)
	playerClear:SetPoint("TOPLEFT", playerChoice, "BOTTOMLEFT", 0, -8)
	playerClear:SetText("Iptal")

	-- =========================
	-- Player: Locked
	-- =========================
	local playerLocked = CreateFrame("Frame", "WoWGuilde_Rosteur_PlayerLocked", playerPanel)
	playerLocked:SetAllPoints(playerPanel)
	playerLocked:Hide()

	local playerLockedTitle =
		playerLocked:CreateFontString("WoWGuilde_Rosteur_PlayerLocked_Title", "OVERLAY", "GameFontNormalLarge")
	playerLockedTitle:SetPoint("TOPLEFT", playerLocked, "TOPLEFT", 0, -10)
	playerLockedTitle:SetText("Resmi roster")

	local playerLockedView =
		MakeRosterView(playerLocked, { namePrefix = "WoWGuilde_Rosteur_PlayerLockedView", enableDrag = false })
	playerLockedView:SetPoint("TOPLEFT", playerLockedTitle, "BOTTOMLEFT", 0, -10)
	playerLockedView:SetPoint("BOTTOMRIGHT", playerLocked, "BOTTOMRIGHT", 0, 0)

	-- =========================
	-- Handlers
	-- =========================
	startBtn:SetScript("OnClick", function()
		local gid = GetGuildUID()
		if Rosteur and gid then
			Rosteur.StartPreparation(gid)
		end
	end)

	configBtn:SetScript("OnClick", function()
		if showPrepSummary then
			showPrepSummary = false
			if f.Refresh then
				f.Refresh()
			end
			return
		end
		local gid = GetGuildUID()
		local rosteur = Rosteur and Rosteur.GetState and Rosteur.GetState(gid) or nil
		if not (Rosteur and gid and rosteur) then
			return
		end
		if not (Rosteur.ShouldShowManagerTab and Rosteur.ShouldShowManagerTab()) then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage("Sadece raid lideri roster olusturabilir.", 1, 0.2, 0.2, 1)
			end
			return
		end
		if rosteur.phase ~= "prep" then
			Rosteur.StartConfig(gid)
			return
		end
		local isLocked = IsPrepConfigLocked(rosteur)
		if isLocked then
			return
		end
		if StaticPopup_Show and StaticPopupDialogs then
			if not StaticPopupDialogs.WOWGUILDE_ROSTEUR_CONFIRM_START_CONFIG then
				StaticPopupDialogs.WOWGUILDE_ROSTEUR_CONFIRM_START_CONFIG = {
					text = "Roster ayarina gecilsin mi?\n\nBasvurular hemen kapanacak.\n\nOnaylamak icin CONFIRMER yaz.",
					button1 = "Onayla",
					button2 = "Iptal",
					hasEditBox = true,
					editBoxWidth = 180,
					EditBoxOnEnterPressed = function(selfEditBox)
						if selfEditBox and selfEditBox.ClearFocus then
							selfEditBox:ClearFocus()
						end
					end,
					OnShow = function(selfPopup)
						SetCreatePopupExtrasShown(selfPopup, false)
						if selfPopup.editBox then
							selfPopup.editBox:SetText("")
							selfPopup.editBox:SetFocus()
						end
					end,
					OnAccept = function(selfPopup)
						local box = selfPopup and selfPopup.editBox
						if not box and selfPopup and selfPopup.GetName then
							box = _G[selfPopup:GetName() .. "EditBox"]
						end
						local text = (box and box.GetText and box:GetText()) or ""
						if strupper(TrimSpaces(text)) ~= "CONFIRMER" then
							if UIErrorsFrame and UIErrorsFrame.AddMessage then
								UIErrorsFrame:AddMessage("Yanlis metin. CONFIRMER yaz.", 1, 0.2, 0.2, 1)
							end
							StaticPopup_Show("WOWGUILDE_ROSTEUR_CONFIRM_START_CONFIG")
							return
						end
						local targetGID = pendingStartConfigGuildUID
						pendingStartConfigGuildUID = nil
						if
							Rosteur
							and targetGID
							and Rosteur.ShouldShowManagerTab
							and Rosteur.ShouldShowManagerTab()
						then
							Rosteur.StartConfig(targetGID)
						end
						if f and f.Refresh then
							f.Refresh()
						end
					end,
					OnCancel = function()
						pendingStartConfigGuildUID = nil
					end,
					EditBoxOnTextChanged = function() end,
					timeout = 0,
					whileDead = 1,
					hideOnEscape = 1,
					preferredIndex = 3,
				}
			end
			pendingStartConfigGuildUID = gid
			StaticPopup_Show("WOWGUILDE_ROSTEUR_CONFIRM_START_CONFIG")
		else
			Rosteur.StartConfig(gid)
		end
	end)

	if summaryBtn then
		summaryBtn:SetScript("OnClick", function()
			showPrepSummary = true
			if f.Refresh then
				f.Refresh()
			end
		end)
	end

	local pendingValidateGuildUID = nil
	local pendingValidateRosterID = nil
	local function ConfirmValidateWithPU()
		local gid = pendingValidateGuildUID
		local rosterId = pendingValidateRosterID
		pendingValidateGuildUID = nil
		pendingValidateRosterID = nil
		if not (Rosteur and gid and rosterId) then
			return
		end
		local rosteur = Rosteur.GetState and Rosteur.GetState(gid) or nil
		if not (rosteur and type(rosteur.rosters) == "table") then
			return
		end
		local active = nil
		for i = 1, #rosteur.rosters do
			local r = rosteur.rosters[i]
			if r and r.id == rosterId then
				active = r
				break
			end
		end
		if not active then
			return
		end
		local missing, totalMissing = ComputeRosterMissing(active)
		if totalMissing > 0 then
			FillRosterMissingWithPU(gid, active, missing)
		end
		Rosteur.ValidateRoster(gid, rosterId)
	end

	local function UpdateValidateButtonState(active)
		if not validateBtn then
			return
		end
		local hasActive = type(active) == "table" and active.id ~= nil
		validateBtn._wowguildeHasActive = hasActive
		validateBtn._wowguildeActiveRosterID = hasActive and active.id or nil
		if not hasActive then
			if validateBtn.SetEnabled then
				validateBtn:SetEnabled(false)
			end
			validateBtn:SetAlpha(0.5)
			validateBtn._wowguildeMissing = nil
			validateBtn._wowguildeMissingTotal = 0
			return
		end
		local missing, totalMissing = ComputeRosterMissing(active)
		local shiftDown = IsShiftKeyDown and IsShiftKeyDown() or false
		validateBtn._wowguildeMissing = missing
		validateBtn._wowguildeMissingTotal = totalMissing
		validateBtn._wowguildeMissingText = BuildMissingText(missing)
		local canValidateNow = totalMissing == 0 or shiftDown
		if validateBtn.SetEnabled then
			validateBtn:SetEnabled(canValidateNow)
		end
		validateBtn:SetAlpha(canValidateNow and 1 or 0.45)
	end

	validateBtn:SetScript("OnUpdate", function(self)
		local shiftDown = IsShiftKeyDown and IsShiftKeyDown() or false
		if self._wowguildeShiftState ~= shiftDown then
			self._wowguildeShiftState = shiftDown
			local gid = GetGuildUID()
			local active = nil
			if Rosteur and gid then
				active = ResolveActiveRoster(gid)
			end
			UpdateValidateButtonState(active)
		end
	end)

	validateBtn:SetScript("OnEnter", function(self)
		local gid = GetGuildUID()
		local active = nil
		if Rosteur and gid then
			active = ResolveActiveRoster(gid)
		end
		UpdateValidateButtonState(active)
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Roster onayla", 1, 0.82, 0, true)
		if not self._wowguildeHasActive then
			GameTooltip:AddLine("Aktif ayar yok.", 1, 0.2, 0.2, true)
		elseif (self._wowguildeMissingTotal or 0) > 0 then
			GameTooltip:AddLine("Eksik roller: " .. (self._wowguildeMissingText or "-"), 1, 0.2, 0.2, true)
			GameTooltip:AddLine(" ", 1, 0.2, 0.2, true)
			GameTooltip:AddLine(
				"Shift basili tutup tiklayarak dis oyuncularla tamamla.",
				0.9,
				0.9,
				0.9,
				true
			)
		else
			GameTooltip:AddLine("Gerekli tum yerler dolu.", 0.2, 1, 0.2, true)
		end
		GameTooltip:Show()
	end)
	validateBtn:SetScript("OnLeave", function()
		if GameTooltip and GameTooltip.Hide then
			GameTooltip:Hide()
		end
	end)

	validateBtn:SetScript("OnClick", function()
		local gid = GetGuildUID()
		if not (Rosteur and gid) then
			return
		end
		local active = ResolveActiveRoster(gid)
		if not (active and active.id) then
			return
		end
		local missing, totalMissing = ComputeRosterMissing(active)
		if totalMissing <= 0 then
			Rosteur.ValidateRoster(gid, active.id)
			return
		end
		if not (IsShiftKeyDown and IsShiftKeyDown()) then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage(
					"Rôles manquants: "
						.. BuildMissingText(missing)
						.. ". Maintenez MAJ pour forcer avec des joueurs externes.",
					1,
					0.2,
					0.2,
					1
				)
			end
			return
		end
		if StaticPopup_Show and StaticPopupDialogs then
			if not StaticPopupDialogs.WOWGUILDE_ROSTEUR_CONFIRM_VALIDATE_PU then
				StaticPopupDialogs.WOWGUILDE_ROSTEUR_CONFIRM_VALIDATE_PU = {
					text = "Les emplacements vides seront remplacés par des joueurs externes (hors rosteur/guilde).\n\nContinuer ?",
					button1 = "Continuer",
					button2 = "Iptal",
					OnAccept = function()
						ConfirmValidateWithPU()
					end,
					timeout = 0,
					whileDead = 1,
					hideOnEscape = 1,
					preferredIndex = 3,
				}
			end
			pendingValidateGuildUID = gid
			pendingValidateRosterID = active.id
			StaticPopup_Show("WOWGUILDE_ROSTEUR_CONFIRM_VALIDATE_PU")
		end
	end)

	if createRosterBtn then
		createRosterBtn:SetScript("OnClick", function()
			local gid = GetGuildUID()
			if Rosteur and gid and templateSelect and templateSelect._value then
				Rosteur.CreateRoster(gid, templateSelect._value)
			end
		end)
	end

	local function DeleteActiveRoster(reset)
		local gid = GetGuildUID()
		if not Rosteur or not gid then
			return
		end
		if reset and Rosteur.Reset then
			Rosteur.Reset(gid)
			return
		end
		local rosteur = Rosteur.GetState and Rosteur.GetState(gid) or nil
		local activeId = rosteur and rosteur.activeRosterId or nil
		if activeId or (rosteur and rosteur.rosters and rosteur.rosters[1]) then
			Rosteur.DeleteRoster(gid, activeId, { force = reset == true })
		end
	end

	if deleteRosterBtn then
		deleteRosterBtn:SetScript("OnClick", function()
			DeleteActiveRoster(true)
		end)
	end

	resetZeroBtn:SetScript("OnClick", function()
		local gid = GetGuildUID()
		if IsShiftKeyDown and IsShiftKeyDown() and IsDevMode and IsDevMode() then
			if Rosteur and Rosteur.Reset and gid then
				Rosteur.Reset(gid)
			end
		elseif Rosteur and Rosteur.ClearSignups and gid then
			Rosteur.ClearSignups(gid)
		end
		if f.Refresh then
			f.Refresh()
		end
	end)

	if puAddBtn then
		puAddBtn:SetScript("OnClick", function()
			local raw = puBox:GetText()
			if raw == PU_PLACEHOLDER then
				raw = ""
			end
			local name = Utils and Utils.Trim and Utils.Trim(raw) or raw
			if not name or name == "" then
				return
			end
			local gid = GetGuildUID()
			if Rosteur and gid then
				local rosteur = Rosteur.GetState and Rosteur.GetState(gid) or nil
				local activeId = rosteur and rosteur.activeRosterId or nil
				if activeId then
					Rosteur.AddPU(gid, activeId, puRole and puRole._value or "DPS", name)
					puBox:SetText(PU_PLACEHOLDER)
				end
			end
		end)
	end

	for role, btn in pairs(roleButtons) do
		btn:SetScript("OnClick", function()
			local gid = GetGuildUID()
			if not gid or not Rosteur then
				return
			end
			local full, meta = GetMySignupMeta(gid)
			if full and full ~= "" then
				local rosteur = Rosteur.GetState and Rosteur.GetState(gid) or nil
				local signup = rosteur and Rosteur.GetSignup and Rosteur.GetSignup(rosteur, full) or nil
				if SignupHasRole(signup, role) then
					if Rosteur.RemoveSignupRole then
						Rosteur.RemoveSignupRole(gid, full, role)
					else
						Rosteur.SetSignup(gid, full, nil)
					end
				else
					Rosteur.SetSignup(gid, full, role, meta)
				end
			end
		end)
	end

	playerClear:SetScript("OnClick", function()
		local gid = GetGuildUID()
		if not gid or not Rosteur then
			return
		end
		local full = GetMySignupMeta(gid)
		if full and full ~= "" then
			Rosteur.SetSignup(gid, full, nil)
		end
	end)

	local function UpdateDevToggle()
		if not devToggle or not Rosteur or not Rosteur.GetDevView then
			return
		end
		local view = Rosteur.GetDevView() or "auto"
		local label = "Auto"
		if view == "player" then
			label = "Joueur"
		elseif view == "manager" then
			label = "Chef"
		end
		devToggle:SetText("Vue: " .. label)
	end

	if devToggle then
		devToggle:SetScript("OnClick", function()
			if Rosteur and Rosteur.GetDevView and Rosteur.SetDevView then
				local view = Rosteur.GetDevView() or "auto"
				local nextView = "auto"
				if view == "auto" then
					nextView = "player"
				elseif view == "player" then
					nextView = "manager"
				end
				Rosteur.SetDevView(nextView)
			end
			UpdateDevToggle()
			if ns and ns.UI and ns.UI.Refresh then
				ns.UI.Refresh()
			end
			if f.Refresh then
				f.Refresh()
			end
		end)
	end

	if devDelete then
		devDelete:SetScript("OnClick", function()
			DeleteActiveRoster(true)
			if f.Refresh then
				f.Refresh()
			end
		end)
	end

	local function UpdateRosterDropdown(rosteur)
		if not rosterSelect or not rosterSelect.SetupMenu then
			return
		end
		local activeId = rosteur and rosteur.activeRosterId or nil
		local activeName = nil
		if rosteur and type(rosteur.rosters) == "table" then
			for i = 1, #rosteur.rosters do
				local r = rosteur.rosters[i]
				if r and r.id == activeId then
					activeName = r.name or ("Configuration \226\128\162" .. tostring(i))
					break
				end
			end
		end
		rosterSelect._value = activeId
		if activeName then
			rosterSelect:SetDefaultText("Rosteur: " .. activeName)
		else
			rosterSelect:SetDefaultText("Rosteur actif")
		end

		rosterSelect:SetupMenu(function(_, root)
			if rosteur and type(rosteur.rosters) == "table" then
				for i = 1, #rosteur.rosters do
					local r = rosteur.rosters[i]
					if r then
						root:CreateButton(r.name or ("Configuration \226\128\162" .. tostring(i)), function()
							local gid = GetGuildUID()
							if Rosteur and gid then
								Rosteur.SetActiveRoster(gid, r.id)
							end
						end, {
							isRadio = true,
							checked = function()
								return rosterSelect._value == r.id
							end,
						})
					end
				end
			else
				root:CreateButton("Aucun rosteur", function() end, { disabled = true })
			end
		end)
	end

	local function UpdateTemplateDropdown()
		if not templateSelect or not templateSelect.SetupMenu then
			return
		end
		local templates = Rosteur and Rosteur.GetTemplates and Rosteur.GetTemplates() or {}
		local firstKey = templateSelect._value
		if not firstKey then
			for _, key in ipairs({ "raid20", "raid10", "custom" }) do
				if templates[key] then
					firstKey = key
					break
				end
			end
			if not firstKey then
				for k, _ in pairs(templates) do
					firstKey = k
					break
				end
			end
			templateSelect._value = firstKey
		end
		local label = firstKey and templates[firstKey] and templates[firstKey].name or "Préconfiguration"
		if label then
			templateSelect:SetDefaultText(label)
		end

		templateSelect:SetupMenu(function(_, root)
			local ordered = { "raid20", "raid10", "custom" }
			local seen = {}
			for _, key in ipairs(ordered) do
				local def = templates[key]
				if def then
					seen[key] = true
					root:CreateButton(def.name or key, function()
						templateSelect._value = key
						templateSelect:SetDefaultText(def.name or key)
					end, {
						isRadio = true,
						checked = function()
							return templateSelect._value == key
						end,
					})
				end
			end
			for key, def in pairs(templates) do
				if not seen[key] then
					root:CreateButton(def.name or key, function()
						templateSelect._value = key
						templateSelect:SetDefaultText(def.name or key)
					end, {
						isRadio = true,
						checked = function()
							return templateSelect._value == key
						end,
					})
				end
			end
		end)
	end

	local function ClearSideSections()
		for _, sec in pairs(sideSections) do
			sec:Hide()
			sec:SetParent(nil)
		end
		for k in pairs(sideSections) do
			sideSections[k] = nil
		end
		if sideContent then
			sideContent:SetHeight(1)
		end
	end

	local function MakeHeroSection(parent, hero)
		local section = CreateFrame("Frame", nil, parent)

		section.header = CreateFrame("Frame", nil, section)
		section.header:SetHeight(10)
		section.header:SetPoint("TOPLEFT")
		section.header:SetPoint("TOPRIGHT")

		section.header.text = section.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		section.header.text:SetPoint("LEFT", 8, 0)
		section.header.text:SetJustifyH("LEFT")
		section.header.text:SetText(hero.heroName or hero.heroFull or hero.heroKey or "Héro")
		section.header.glow = section.header:CreateTexture(nil, "BACKGROUND")
		section.header.glow:SetPoint("LEFT", section.header.text, "RIGHT", 4, 0)
		section.header.glow:SetPoint("RIGHT", section.header, "RIGHT", -4, 0)
		section.header.glow:SetPoint("CENTER", section.header, "CENTER", 0, 1)
		section.header.glow:SetHeight(1)
		section.header.glow:SetAtlas("LevelUp-Glow-Gold", false)
		section.header.glow:SetDesaturated(true)
		section.header.glow:SetTexCoord(0.5, 1, 0, 1)

		section.body = CreateFrame("Frame", nil, section)
		section.body:SetPoint("TOPLEFT", section.header, "BOTTOMLEFT", 0, -2)
		section.body:SetPoint("TOPRIGHT", section.header, "BOTTOMRIGHT", 0, -2)

		local y = 0
		local CHILD_HEIGHT = 25
		local CHILD_GAP = 0
		local FIRST_TOP_GAP = 2
		local BETWEEN_TOP_GAP = 2
		local LAST_BOTTOM_EXTRA = 8
		if hero.entries then
			for i = 1, #hero.entries do
				local entry = hero.entries[i]
				if i == 1 then
					y = y + FIRST_TOP_GAP
				else
					y = y + BETWEEN_TOP_GAP
				end
				local btn = CreateFrame("Button", nil, section.body)
				btn:SetHeight(CHILD_HEIGHT)
				btn:SetPoint("TOPLEFT", section.body, "TOPLEFT", 24, -y)
				btn:SetPoint("TOPRIGHT", section.body, "TOPRIGHT", -8, -y)
				btn:EnableMouse(true)

				btn.bg = btn:CreateTexture(nil, "BACKGROUND")
				btn.bg:SetAllPoints(btn)
				btn.bg:SetAtlas("glues-characterSelect-button-collapseExpand-disabled", true)
				btn.bg:SetAlpha(0.6)

				btn.hover = btn:CreateTexture(nil, "HIGHLIGHT")
				btn.hover:SetPoint("TOP", btn, "TOP", 0, 0)
				btn.hover:SetPoint("BOTTOM", btn, "BOTTOM", 0, 0)
				btn.hover:SetPoint("LEFT", btn, "LEFT", 1, 0)
				btn.hover:SetPoint("RIGHT", btn, "RIGHT", -1, 0)
				btn.hover:SetAtlas("glues-characterSelect-button-collapseExpand-hover", true)
				btn.hover:SetBlendMode("ADD")
				btn.hover:Hide()
				btn.hover:SetAlpha(0.3)

				btn:SetScript("OnEnter", function(self)
					if self.hover then
						self.hover:Show()
					end
				end)
				btn:SetScript("OnLeave", function(self)
					if self.hover then
						self.hover:Hide()
					end
				end)
				btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				btn.text:SetPoint("TOPLEFT", 8, -2)
				btn.text:SetPoint("BOTTOMRIGHT", -6, 4)
				btn.text:SetJustifyH("LEFT")
				local rawName = entry.name or entry.full or "-"
				if Utils and Utils.BaseName then
					rawName = Utils.BaseName(rawName)
				end
				local nameText = ColorizeName(rawName, entry.classTag)
				if entry.isPU then
					nameText = nameText .. " |cff9d9d9d(Externe)|r"
				end
				btn.text:SetText(nameText)
				btn.data = {
					id = entry.id or entry.full,
					full = entry.full,
					name = entry.name,
					classTag = entry.classTag,
					uid = entry.uid,
					heroFull = entry.heroFull,
					heroName = entry.heroName,
					role = entry.role,
					roles = entry.roles,
					requestedRole = role,
					isPU = entry.isPU,
					source = "signup",
				}
				btn:RegisterForDrag("LeftButton")
				btn:SetScript("OnDragStart", function(self)
					StartDrag(self.data)
				end)
				btn:SetScript("OnDragStop", function()
					StopDragDeferred()
				end)
				y = y + CHILD_HEIGHT + CHILD_GAP
				if i == #hero.entries then
					y = y + LAST_BOTTOM_EXTRA
				end
			end
		end
		if y > 0 then
			y = y - 2
		end
		section.body:SetHeight(math.max(1, y))

		section:SetHeight(20 + 2 + section.body:GetHeight())
		return section
	end

	local signupSummary = nil
	do
		local SignupSummary = ns.RosteurSectionSignupSummary
		if SignupSummary and type(SignupSummary.Build) == "function" then
			local ok, built = pcall(SignupSummary.Build, {
				Rosteur = Rosteur,
				DB = DB,
				Utils = Utils,
				ROLE_ORDER = ROLE_ORDER,
				NormalizeRoleTag = NormalizeRoleTag,
				NormalizeHeroKey = NormalizeHeroKey,
				GetGuildUID = GetGuildUID,
				GetPseudoAlias = GetPseudoAlias,
			})
			if ok and type(built) == "table" then
				signupSummary = built
			end
		end
	end
	if not signupSummary then
		local function FallbackIsSignupVisibleForActiveRoster(rosteur, signup)
			if type(signup) ~= "table" then
				return false
			end
			local activeRosterId = rosteur and rosteur.activeRosterId or nil
			local full = signup.full
			if not (activeRosterId and full and Rosteur and Rosteur.IsSignupHidden) then
				return true
			end
			local gid = GetGuildUID()
			if not gid then
				return true
			end
			return not Rosteur.IsSignupHidden(gid, activeRosterId, full)
		end
		local function FallbackBuildRoleHeroSummary(rosteur, opts)
			local out = {
				TANK = { heroes = {}, order = {} },
				HEAL = { heroes = {}, order = {} },
				DPS = { heroes = {}, order = {} },
			}
			local signups = rosteur and rosteur.prep and rosteur.prep.signups or nil
			if type(signups) == "table" then
				for _, v in pairs(signups) do
					if type(v) == "table" then
						local allowed = true
						if opts and opts.onlyVisibleForActive then
							local visibleFn = opts.isVisibleFn or FallbackIsSignupVisibleForActiveRoster
							allowed = visibleFn(rosteur, v)
						end
						if allowed then
							local signupRoles = GetSignupRoles(v)
							for role in pairs(signupRoles) do
								if role and out[role] then
									local data = out[role]
									local heroName = v.heroName or v.name or v.full or "Héro"
									local heroKey = NormalizeHeroKey(heroName)
										or NormalizeHeroKey(v.uid)
										or NormalizeHeroKey(v.full)
										or tostring(math.random())
									local hero = data.heroes[heroKey]
									if not hero then
										hero = { heroFull = v.heroFull or v.full, heroName = heroName, entries = {} }
										data.heroes[heroKey] = hero
										data.order[#data.order + 1] = heroKey
									end
									hero.entries[#hero.entries + 1] = v
								end
							end
						end
					end
				end
			end
			for _, role in ipairs(ROLE_ORDER) do
				local data = out[role]
				table.sort(data.order, function(a, b)
					local ha = data.heroes[a]
					local hb = data.heroes[b]
					return tostring(ha and ha.heroName or "") < tostring(hb and hb.heroName or "")
				end)
				for _, heroKey in ipairs(data.order) do
					local hero = data.heroes[heroKey]
					if hero and hero.entries then
						table.sort(hero.entries, function(a, b)
							return tostring(a.name or a.full or "") < tostring(b.name or b.full or "")
						end)
					end
				end
			end
			return out
		end
		signupSummary = {
			IsSignupVisibleForActiveRoster = FallbackIsSignupVisibleForActiveRoster,
			BuildRoleHeroSummary = FallbackBuildRoleHeroSummary,
		}
	end
	local UpdateSignupList
	local IsSignupVisibleForActiveRoster = signupSummary.IsSignupVisibleForActiveRoster

	local function MakeSideRoleSection(role, data)
		local prefix = "WoWGuilde_Rosteur_SideRole_" .. role
		local sec = CreateFrame("Frame", prefix, sideContent)
		sec.role = role

		local HEADER_HEIGHT = 48
		local BODY_GAP = 6
		sec.header = CreateFrame("Button", prefix .. "_Header", sec)
		sec.header:SetHeight(HEADER_HEIGHT)
		sec.header:SetPoint("TOPLEFT")
		sec.header:SetPoint("TOPRIGHT")
		sec.header:EnableMouse(true)
		sec.header:RegisterForClicks("LeftButtonUp")

		sec.header.bg = sec.header:CreateTexture(prefix .. "_HeaderBg", "BACKGROUND")
		sec.header.bg:SetAllPoints(sec.header)
		sec.header.bg:SetAtlas("glues-characterSelect-button-collapseExpand", true)

		sec.header.hover = sec.header:CreateTexture(prefix .. "_HeaderHover", "HIGHLIGHT")
		sec.header.hover:SetPoint("TOP", sec.header, "TOP", 0, 0)
		sec.header.hover:SetPoint("BOTTOM", sec.header, "BOTTOM", 0, 0)
		sec.header.hover:SetPoint("LEFT", sec.header, "LEFT", 3, 0)
		sec.header.hover:SetPoint("RIGHT", sec.header, "RIGHT", -3, 0)
		sec.header.hover:SetAtlas("glues-characterSelect-button-collapseExpand-hover", true)
		sec.header.hover:SetBlendMode("ADD")
		sec.header.hover:Hide()

		sec.header:SetScript("OnEnter", function(self)
			if self.hover then
				self.hover:Show()
			end
		end)
		sec.header:SetScript("OnLeave", function(self)
			if self.hover then
				self.hover:Hide()
			end
			self:ClearAllPoints()
			self:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, 0)
			self:SetPoint("TOPRIGHT", sec, "TOPRIGHT", 0, 0)
		end)
		sec.header:SetScript("OnMouseDown", function(self)
			if self.bg then
				self.bg:ClearAllPoints()
				self.bg:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1)
				self.bg:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 1, -1)
			end
			if self.hover then
				self.hover:ClearAllPoints()
				self.hover:SetPoint("TOP", self, "TOP", 0, -1)
				self.hover:SetPoint("BOTTOM", self, "BOTTOM", 0, -1)
				self.hover:SetPoint("LEFT", self, "LEFT", 2, -1)
				self.hover:SetPoint("RIGHT", self, "RIGHT", 0, -1)
			end
		end)
		sec.header:SetScript("OnMouseUp", function(self)
			if self.bg then
				self.bg:ClearAllPoints()
				self.bg:SetAllPoints(self)
			end
			if self.hover then
				self.hover:ClearAllPoints()
				self.hover:SetPoint("TOP", self, "TOP", 0, 0)
				self.hover:SetPoint("BOTTOM", self, "BOTTOM", 0, 0)
				self.hover:SetPoint("LEFT", self, "LEFT", 1, 0)
				self.hover:SetPoint("RIGHT", self, "RIGHT", -1, 0)
			end
		end)

		sec.header.icon = sec.header:CreateTexture(prefix .. "_Icon", "ARTWORK")
		sec.header.icon:SetSize(16, 16)
		sec.header.icon:SetPoint("LEFT", 10, 3)
		if ROLE_ATLAS and ROLE_ATLAS[role] then
			sec.header.icon:SetAtlas(ROLE_ATLAS[role], false)
		end

		sec.header.text = sec.header:CreateFontString(prefix .. "_Text", "OVERLAY", "GameFontNormal")
		sec.header.text:SetPoint("LEFT", sec.header.icon, "RIGHT", 6, -1)
		sec.header.text:SetJustifyH("LEFT")
		sec.header.text:SetText(ROLE_LABEL[role] or role)

		sec.header:SetScript("OnClick", function()
			sidebarCollapsed[role] = not sidebarCollapsed[role]
			if UpdateSignupList then
				UpdateSignupList(sidebarRosteur)
			end
		end)

		sec.body = CreateFrame("Frame", prefix .. "_Body", sec)
		sec.body:SetPoint("TOPLEFT", sec.header, "BOTTOMLEFT", 0, -BODY_GAP)
		sec.body:SetPoint("TOPRIGHT", sec.header, "BOTTOMRIGHT", 0, -BODY_GAP)
		sec.body:SetHeight(1)

		local y = 0
		if data and data.order and data.heroes and #data.order > 0 then
			for _, heroKey in ipairs(data.order) do
				local hero = data.heroes[heroKey]
				if hero then
					local hsec = MakeHeroSection(sec.body, hero)
					hsec:SetPoint("TOPLEFT", sec.body, "TOPLEFT", 0, -y)
					hsec:SetPoint("TOPRIGHT", sec.body, "TOPRIGHT", 0, -y)
					y = y + hsec:GetHeight() + 6
				end
			end
		else
			local emptyHero = { heroName = "Aucune candidature", entries = {} }
			local hsec = MakeHeroSection(sec.body, emptyHero)
			hsec:SetPoint("TOPLEFT", sec.body, "TOPLEFT", 0, -y)
			hsec:SetPoint("TOPRIGHT", sec.body, "TOPRIGHT", 0, -y)
			y = y + hsec:GetHeight() + 6
		end
		if y > 0 then
			y = y - 6
		end
		sec.body:SetHeight(math.max(1, y))

		local showBody = not sidebarCollapsed[role]
		sec.body:SetShown(showBody)
		sec:SetHeight(HEADER_HEIGHT + (showBody and (BODY_GAP + sec.body:GetHeight()) or 0))
		return sec
	end

	UpdateSignupList = function(rosteur)
		sidebarRosteur = rosteur
		if not sideContent then
			return
		end
		ClearSideSections()
		local dataByRole = signupSummary.BuildRoleHeroSummary(rosteur, {
			onlyVisibleForActive = true,
			isVisibleFn = IsSignupVisibleForActiveRoster,
		})

		local y = 0
		for _, role in ipairs(ROLE_ORDER) do
			local sec = MakeSideRoleSection(role, dataByRole[role])
			sideSections[role] = sec
			sec:ClearAllPoints()
			sec:SetPoint("TOPLEFT", sideContent, "TOPLEFT", 0, -y)
			sec:SetPoint("TOPRIGHT", sideContent, "TOPRIGHT", 0, -y)
			y = y + (sec:GetHeight() or 1) + 10
		end
		if y > 0 then
			y = y - 10
		end
		sideContent:SetHeight(math.max(1, y))
	end

	local function UpdatePrepLists(rosteur)
		if not prepSections then
			return
		end
		prepSummaryData = signupSummary.BuildRoleHeroSummary(rosteur)
	end

	local function UpdateCounts(rosteur)
		local counts = Rosteur and Rosteur.GetSignupCounts and Rosteur.GetSignupCounts(rosteur) or {}
		local tank = counts.TANK or 0
		local heal = counts.HEAL or 0
		local dps = counts.DPS or 0
		if prepSections then
			if prepSections.TANK and prepSections.TANK.count then
				prepSections.TANK.count:SetText(tostring(tank))
			end
			if prepSections.HEAL and prepSections.HEAL.count then
				prepSections.HEAL.count:SetText(tostring(heal))
			end
			if prepSections.DPS and prepSections.DPS.count then
				prepSections.DPS.count:SetText(tostring(dps))
			end
		end
		playerCounts:SetText("Tank: " .. tank .. " | Heal: " .. heal .. " | DPS: " .. dps)
	end

	local function UpdatePlayerChoice(rosteur)
		local gid = GetGuildUID()
		local full = GetMySignupMeta(gid)
		local signup = rosteur and full and Rosteur.GetSignup and Rosteur.GetSignup(rosteur, full) or nil
		local roles = GetSignupRoles(signup)
		local labels = {}
		for _, role in ipairs(ROLE_ORDER) do
			if roles[role] then
				labels[#labels + 1] = ROLE_LABEL[role] or role
			end
		end
		local label = (#labels > 0) and table.concat(labels, " / ") or "-"
		playerChoice:SetText("Secimlerin: " .. label)
		for key, btn in pairs(roleButtons) do
			local fs = btn:GetFontString()
			if fs then
				if roles[key] then
					fs:SetTextColor(0.2, 1, 0.2)
				else
					fs:SetTextColor(1, 1, 1)
				end
			end
		end
	end

	local function UpdateRoleButtonsAvailability()
		if not (ns and ns.UI and ns.UI.GetAllowedRoles) then
			return
		end
		local gid = GetGuildUID()
		local _, meta = GetMySignupMeta(gid)
		local allowed = ns.UI.GetAllowedRoles(meta.classTag, meta.spec, meta.specID)
		local hasRules = allowed and next(allowed) ~= nil
		for role, btn in pairs(roleButtons) do
			local ok = true
			if hasRules then
				ok = allowed[role] == true
			end
			if btn.SetEnabled then
				btn:SetEnabled(ok)
			end
			if btn.icon and btn.icon.SetDesaturated then
				btn.icon:SetDesaturated(not ok)
			end
			local fs = btn:GetFontString()
			if fs and fs.SetAlpha then
				fs:SetAlpha(ok and 1 or 0.4)
			end
		end
	end

	local function GetMyHeroPseudoFromRoster()
		if not (Utils and Utils.ParsePseudo and Utils.PseudoKey and GetNumGuildMembers and GetGuildRosterInfo) then
			return nil, nil
		end
		local myGUID = UnitGUID and UnitGUID("player") or nil
		local myFull = GetMyFull()
		local myShort = myFull and Ambiguate and Ambiguate(myFull, "none") or myFull
		local myBase = myFull and Utils.BaseName and Utils.BaseName(myFull) or myFull
		local n = GetNumGuildMembers() or 0
		for i = 1, n do
			local name, _, _, _, _, _, note, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
			if name then
				local full = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name
				local short = Ambiguate and Ambiguate(full, "none") or full
				local base = Utils.BaseName and Utils.BaseName(full) or full
				local isMe = (myGUID and guid and myGUID == guid)
					or (myFull and full == myFull)
					or (myShort and short == myShort)
					or (myBase and base == myBase)
				if isMe then
					local pseudo = Utils.ParsePseudo(note, name)
					return Utils.PseudoKey(pseudo), pseudo
				end
			end
		end
		return nil, nil
	end

	local function GetMyGuildCharacters(gid)
		local out = {}
		local seen = {}
		local pseudoKey, pseudoName = GetMyHeroPseudoFromRoster()

		local dbByFull = {}
		if gid and DB and DB.GetGuildPlayers then
			local players = DB:GetGuildPlayers(gid)
			if type(players) == "table" then
				for _, p in pairs(players) do
					local chars = p and p.characters or nil
					if type(chars) == "table" then
						for full, c in pairs(chars) do
							local f = (type(c) == "table" and c.full) or full
							if f and f ~= "" and type(c) == "table" then
								dbByFull[f] = c
							end
						end
					end
				end
			end
		end

		if pseudoKey and GetNumGuildMembers and GetGuildRosterInfo then
			local n = GetNumGuildMembers() or 0
			for i = 1, n do
				local name, _, _, _, _, _, note, _, _, _, classFileName = GetGuildRosterInfo(i)
				if name then
					local p = Utils and Utils.ParsePseudo and Utils.ParsePseudo(note, name) or nil
					local key = Utils and Utils.PseudoKey and Utils.PseudoKey(p) or nil
					if key == pseudoKey then
						local full = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name
						if full and full ~= "" and not seen[full] then
							seen[full] = true
							local dbChar = dbByFull[full]
							local dispName = (Ambiguate and Ambiguate(full, "none"))
								or (Utils and Utils.BaseName and Utils.BaseName(full))
								or full
							out[#out + 1] = {
								full = full,
								name = (dbChar and dbChar.name) or dispName,
								classTag = (dbChar and dbChar.classTag) or classFileName,
								spec = dbChar and dbChar.spec or nil,
								specID = dbChar and dbChar.specID or nil,
								level = dbChar and dbChar.level or nil,
								heroName = pseudoName or p,
							}
						end
					end
				end
			end
		end

		-- Fallback: if no pseudo group found, keep previous local-DB behavior.
		if #out == 0 and gid and DB and DB.GetMyUID and DB.GetGuildPlayer then
			local uid = DB:GetMyUID()
			local player = uid and DB:GetGuildPlayer(gid, uid) or nil
			local chars = player and player.characters or nil
			if type(chars) == "table" then
				for full, c in pairs(chars) do
					if type(c) == "table" then
						local f = c.full or full
						if f and f ~= "" and not seen[f] then
							seen[f] = true
							out[#out + 1] = {
								full = f,
								name = c.name or (Utils and Utils.BaseName and Utils.BaseName(f)) or f,
								classTag = c.classTag,
								spec = c.spec,
								specID = c.specID,
								level = c.level,
								heroName = pseudoName
									or GetPseudoAlias(f)
									or (Utils and Utils.BaseName and Utils.BaseName(f)),
							}
						end
					end
				end
			end
		end

		table.sort(out, function(a, b)
			return tostring(a.name or a.full or "") < tostring(b.name or b.full or "")
		end)
		return out
	end

	local function UpdateManagerApplyButtons(rosteur, phase)
		if not prepSections then
			return
		end
		local gid = GetGuildUID()
		local myUID = DB and DB.GetMyUID and DB:GetMyUID() or nil
		local chars = GetMyGuildCharacters(gid)
		local signups = rosteur and rosteur.prep and rosteur.prep.signups or nil

		local function GetCompatibles(role)
			local list = {}
			for i = 1, #chars do
				local ch = chars[i]
				local existing = type(signups) == "table" and signups[ch.full] or nil
				local allowed = ns
					and ns.UI
					and ns.UI.GetAllowedRoles
					and ns.UI.GetAllowedRoles(ch.classTag, ch.spec, ch.specID)
				local ok = true
				if allowed and next(allowed) then
					ok = allowed[role] == true
				end
				if ok and not SignupHasRole(existing, role) then
					list[#list + 1] = ch
				end
			end
			return list
		end

		local function GetOwnedRoleEntries(role)
			local list = {}
			if type(signups) ~= "table" then
				return list
			end
			for _, v in pairs(signups) do
				if type(v) == "table" and SignupHasRole(v, role) then
					if myUID and v.uid and v.uid == myUID then
						list[#list + 1] = v
					end
				end
			end
			table.sort(list, function(a, b)
				return tostring(a.name or a.full or "") < tostring(b.name or b.full or "")
			end)
			return list
		end

		for role, section in pairs(prepSections) do
			local btn = section and section.applyBtn or nil
			local removeBtn = section and section.removeBtn or nil
			if btn then
				local isVisible = phase == "prep"
				local compatibles = isVisible and GetCompatibles(role) or {}
				btn:SetShown(isVisible)
				if btn.SetEnabled then
					btn:SetEnabled(isVisible and #compatibles > 0)
				end
				if isVisible then
					btn:SetText("Basvur")
					btn:SetScript("OnClick", function(self)
						if not (MenuUtil and MenuUtil.CreateContextMenu and Rosteur and gid) then
							local ch = compatibles[1]
							if ch then
								local meta = {
									uid = myUID,
									name = ch.name,
									classTag = ch.classTag,
									spec = ch.spec,
									specID = ch.specID,
									heroFull = ch.full,
									heroName = ch.heroName
										or GetPseudoAlias(ch.full)
										or (Utils and Utils.BaseName and Utils.BaseName(ch.full)),
								}
								Rosteur.SetSignup(gid, ch.full, role, meta)
								if f and f.Refresh then
									f.Refresh()
								end
							end
							return
						end
						MenuUtil.CreateContextMenu(self, function(_, root)
							root:CreateTitle("Postuler " .. (ROLE_LABEL[role] or role))
							for i = 1, #compatibles do
								local ch = compatibles[i]
								local label = ColorizeName(ch.name or ch.full, ch.classTag)
								root:CreateButton(label, function()
									local meta = {
										uid = myUID,
										name = ch.name,
										classTag = ch.classTag,
										spec = ch.spec,
										specID = ch.specID,
										heroFull = ch.full,
										heroName = ch.heroName
											or GetPseudoAlias(ch.full)
											or (Utils and Utils.BaseName and Utils.BaseName(ch.full)),
									}
									Rosteur.SetSignup(gid, ch.full, role, meta)
									if f and f.Refresh then
										f.Refresh()
									end
								end)
							end
						end)
					end)
				end
			end
			if removeBtn then
				local isVisible = phase == "prep"
				local ownedEntries = isVisible and GetOwnedRoleEntries(role) or {}
				removeBtn:SetShown(isVisible)
				if removeBtn.SetEnabled then
					removeBtn:SetEnabled(isVisible and #ownedEntries > 0)
				end
				if isVisible then
					removeBtn:SetScript("OnClick", function(self)
						if not (MenuUtil and MenuUtil.CreateContextMenu and Rosteur and gid) then
							local e = ownedEntries[1]
							if e and e.full then
								if Rosteur.RemoveSignupRole then
									Rosteur.RemoveSignupRole(gid, e.full, role)
								else
									Rosteur.SetSignup(gid, e.full, nil)
								end
								if f and f.Refresh then
									f.Refresh()
								end
							end
							return
						end
						MenuUtil.CreateContextMenu(self, function(_, root)
							root:CreateTitle("Retirer candidature")
							for i = 1, #ownedEntries do
								local e = ownedEntries[i]
								root:CreateButton(ColorizeName(e.name or e.full, e.classTag), function()
									if Rosteur.RemoveSignupRole then
										Rosteur.RemoveSignupRole(gid, e.full, role)
									else
										Rosteur.SetSignup(gid, e.full, nil)
									end
									if f and f.Refresh then
										f.Refresh()
									end
								end)
							end
						end)
					end)
				end
			end
		end
	end

	local function ShowManagerState(phase)
		if showManagerEmpty then
			idlePanel:SetShown(false)
			prepPanel:SetShown(false)
			configPanel:SetShown(true)
			lockedPanel:SetShown(false)
			return
		end
		idlePanel:SetShown(phase == "idle")
		if phase == "config" then
			prepPanel:SetShown(showPrepSummary)
			configPanel:SetShown(not showPrepSummary)
		else
			prepPanel:SetShown(phase == "prep")
			configPanel:SetShown(phase == "config")
		end
		lockedPanel:SetShown(phase == "locked")
	end

	local function LayoutManagerPanel(phase)
		managerPanel:ClearAllPoints()
		if phase == "idle" then
			managerPanel:SetAllPoints(f)
		elseif phase == "prep" then
			managerPanel:SetPoint("TOPLEFT", headerArea, "BOTTOMLEFT", 0, -6)
			managerPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 20)
		elseif phase == "config" then
			managerPanel:SetPoint("TOPLEFT", headerArea, "BOTTOMLEFT", 0, -6)
			managerPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 20)
		else
			managerPanel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
			managerPanel:SetPoint("BOTTOMRIGHT", mainArea, "BOTTOMRIGHT", -10, 10)
		end
	end

	local function ShowPlayerState(phase)
		playerIdle:SetShown(phase == "idle")
		playerSignup:SetShown(phase == "prep")
		playerConfig:SetShown(phase == "config")
		playerLocked:SetShown(phase == "locked")
		if phase ~= "prep" then
			playerSignup:Hide()
		end
		if phase ~= "config" then
			playerConfig:Hide()
		end
		if phase ~= "locked" then
			playerLocked:Hide()
		end
	end

	local function UpdateSidePanel(rosteur, phase, active, canManage)
		if not sideInfo or not sideHint then
			return
		end
		local counts = Rosteur and Rosteur.GetSignupCounts and Rosteur.GetSignupCounts(rosteur) or {}
		local tank = counts.TANK or 0
		local heal = counts.HEAL or 0
		local dps = counts.DPS or 0
		local phaseLabel = "En attente"
		if phase == "prep" then
			phaseLabel = "Préparation"
		elseif phase == "config" then
			phaseLabel = "Configuration"
		elseif phase == "locked" then
			phaseLabel = "Rosteur validé"
		end
		local rosterName = active and active.name or "-"
		local season = rosteur and rosteur.seasonName or ""
		local seasonLine = (season ~= "" and ("Saison: " .. season .. "\n")) or ""
		sideInfo:SetText(
			seasonLine
				.. "Phase: "
				.. phaseLabel
				.. "\nRosteur: "
				.. rosterName
				.. "\nProtection: "
				.. tank
				.. "\nSoins: "
				.. heal
				.. "\nDégâts: "
				.. dps
		)

		local hint = ""
		if phase == "idle" then
			if canManage then
				hint = "Lancez la préparation pour ouvrir les inscriptions."
			else
				hint = "Aucune préparation en cours."
			end
		elseif phase == "prep" then
			if canManage then
				hint = "Quand tout le monde est prêt, configurez le rosteur."
			else
				hint = "Choisissez votre rôle pour ce raid."
			end
		elseif phase == "config" then
			if canManage then
				hint = "Glissez les demandes dans les sections."
			else
				hint = "Le rosteur est en cours de configuration."
			end
		elseif phase == "locked" then
			hint = "Rosteur validé. Prêt à partir."
		end
		sideHint:SetText(hint)
	end

	local function Refresh()
		local gid = GetGuildUID()
		local rosteur = Rosteur and Rosteur.GetState and Rosteur.GetState(gid) or nil
		local phase = rosteur and rosteur.phase or "idle"
		local canManageRaw = Rosteur and Rosteur.ShouldShowManagerTab and Rosteur.ShouldShowManagerTab() or false
		local canManage = canManageRaw
		if Rosteur and Rosteur.ResolveCanManage then
			canManage = Rosteur.ResolveCanManage(canManageRaw)
		end
		local raidLeaderUID = DB and DB.GetGuildRaidLeaderUID and DB:GetGuildRaidLeaderUID(gid) or nil
		local isRaidLeader = IsMyRaidLeaderIdentity and IsMyRaidLeaderIdentity(gid, raidLeaderUID) or false
		local canManagePhase = canManage
		if phase == "config" then
			local devForceManager = IsDevMode() and Rosteur and Rosteur.GetDevView and Rosteur.GetDevView() == "manager"
			if devForceManager then
				canManagePhase = true
			elseif not canManage then
				canManagePhase = false
			else
				local hasLeaderIdentity = IsMyRaidLeaderIdentity and IsMyRaidLeaderIdentity(gid, raidLeaderUID) or false
				if not raidLeaderUID or tostring(raidLeaderUID) == "" then
					canManagePhase = true
				elseif hasLeaderIdentity then
					canManagePhase = true
				elseif Rosteur and Rosteur.ShouldShowManagerTab and Rosteur.ShouldShowManagerTab() then
					canManagePhase = true
				else
					canManagePhase = false
				end
			end
		end

		local active = nil
		if rosteur and rosteur.activeRosterId and type(rosteur.rosters) == "table" then
			for i = 1, #rosteur.rosters do
				local r = rosteur.rosters[i]
				if r and r.id == rosteur.activeRosterId then
					active = r
					break
				end
			end
		end

		UpdateDevToggle()
		if title and subtitle then
			if isRaidLeader then
				title:SetText("Gestion du groupe de raid")
				subtitle:SetText("Préparation, inscriptions et configuration du groupe de raid")
			else
				title:SetText("Inscription au groupe de raid")
				subtitle:SetText("Organisation inscription et découverte du groupe de raid")
			end
		end
		UpdateSidePanel(rosteur, phase, active, canManagePhase)
		local hasAnyConfig = rosteur and type(rosteur.rosters) == "table" and rosteur.rosters[1] ~= nil
		if configEmpty then
			local noConfig = (not rosteur) or (type(rosteur.rosters) ~= "table") or (rosteur.rosters[1] == nil)
			showManagerEmpty = false
			configEmpty:SetShown(false)
			if canManage and not showPrepSummary and phase ~= "locked" then
				configEmpty:SetShown(true)
				if noConfig then
					emptyTitle:SetText("Aucun rosteur configuré")
					SetConfigEmptyTitleLayout(false)
					emptyDropdown:Show()
					if emptyDesc then
						emptyDesc:Show()
					end
					configSelect:Hide()
					if rosterView then
						rosterView:Hide()
					end
					SetupEmptyTemplateDropdown()
				elseif hasAnyConfig then
					if active and active.name then
						emptyTitle:SetText(active.name)
					else
						emptyTitle:SetText("Configuration active")
					end
					SetConfigEmptyTitleLayout(true)
					emptyDropdown:Hide()
					if emptyDesc then
						emptyDesc:Hide()
					end
					configSelect:Show()
					if rosterView then
						rosterView:Show()
					end
					SetupConfigSelectDropdown(rosteur)
				end
			end
		end
		local hasAnySignup = rosteur
			and rosteur.prep
			and type(rosteur.prep.signups) == "table"
			and next(rosteur.prep.signups) ~= nil
		local canReset = hasAnySignup == true
		if devDelete and devDelete.SetEnabled then
			devDelete:SetEnabled(hasAnyConfig)
		end

		if phase ~= "config" then
			showPrepSummary = false
		end
		local useSharedPrepView = (not canManagePhase) and phase == "prep"
		local managerIdle = canManagePhase and phase == "idle"
		LayoutManagerPanel(phase)
		managerPanel:SetShown(canManagePhase or useSharedPrepView)
		playerPanel:SetShown((not canManagePhase) and not useSharedPrepView)
		local showResetOnThisPage = canManagePhase and phase == "prep"
		resetZeroBtn:SetShown(showResetOnThisPage)
		if resetZeroBtn.SetEnabled then
			resetZeroBtn:SetEnabled(showResetOnThisPage and canReset)
		end
		headerArea:SetShown(not managerIdle)
		if sideArea then
			sideArea:SetShown(canManagePhase and phase == "config" and not showPrepSummary)
		end
		if validateBtn then
			local showValidate = canManagePhase and phase == "config" and not showPrepSummary
			if showValidate then
				UpdateValidateButtonState(active)
			else
				if validateBtn.SetEnabled then
					validateBtn:SetEnabled(false)
				end
				validateBtn:SetAlpha(0.5)
				validateBtn._wowguildeHasActive = false
				validateBtn._wowguildeMissing = nil
				validateBtn._wowguildeMissingTotal = 0
			end
		end
		if f.bgFrame then
			f.bgFrame:SetShown(not managerIdle)
		end

		if canManagePhase or useSharedPrepView then
			ShowManagerState(phase)
			UpdateCounts(rosteur)
			UpdateManagerApplyButtons(rosteur, phase)
			local showSummary = phase == "prep" or (phase == "config" and showPrepSummary)
			if showSummary then
				UpdatePrepLists(rosteur)
			elseif phase == "config" and canManagePhase then
				UpdateRosterDropdown(rosteur)
				UpdateTemplateDropdown()
				UpdateSignupList(rosteur)
				if rosterView then
					rosterView._roster = active
					if rosterView.Refresh then
						rosterView.Refresh()
					end
				end
				local hasAnyConfig = rosteur and type(rosteur.rosters) == "table" and rosteur.rosters[1] ~= nil
				if deleteRosterBtn and deleteRosterBtn.SetEnabled then
					deleteRosterBtn:SetEnabled(hasAnyConfig)
				end
			elseif phase == "locked" and canManagePhase then
				lockedView._roster = active
				lockedView.Refresh()
			end
		else
			ShowPlayerState(phase)
			UpdateCounts(rosteur)
			UpdatePlayerChoice(rosteur)
			UpdateRoleButtonsAvailability()
			if phase == "locked" then
				playerLockedView._roster = active
				playerLockedView.Refresh()
			end
		end

		if configBtn then
			local isRaidLeader = Rosteur and Rosteur.ShouldShowManagerTab and Rosteur.ShouldShowManagerTab() or false
			if canManagePhase and isRaidLeader and phase == "config" and showPrepSummary then
				configBtn:SetText("Retour")
				configBtn:Show()
				if configBtn.Enable then
					configBtn:Enable()
				elseif configBtn.SetEnabled then
					configBtn:SetEnabled(true)
				end
				UpdateConfigBtnTextState(false)
			elseif canManagePhase and isRaidLeader and phase == "prep" then
				configBtn:SetText("Roster olustur")
				configBtn:Show()
				local isLocked = IsPrepConfigLocked(rosteur)
				if isLocked then
					if configBtn.Disable then
						configBtn:Disable()
					elseif configBtn.SetEnabled then
						configBtn:SetEnabled(false)
					end
					UpdateConfigBtnTextState(true)
				else
					if configBtn.Enable then
						configBtn:Enable()
					elseif configBtn.SetEnabled then
						configBtn:SetEnabled(true)
					end
					UpdateConfigBtnTextState(false)
				end
			else
				configBtn:Hide()
			end
		end
	end

	f.Refresh = Refresh

	f:SetScript("OnShow", function()
		Refresh()
	end)

	if EventBus and EventBus.On then
		EventBus.On("WG_ROSTEUR_UPDATED", function()
			if f:IsShown() then
				Refresh()
			end
		end)
		EventBus.On("GROUP_ROSTER_UPDATE", function()
			if f:IsShown() then
				Refresh()
			end
		end)
		EventBus.On("GUILD_ROSTER_UPDATE", function()
			if f:IsShown() then
				Refresh()
			end
		end)
	end

	return f
end
