local ADDON, ns = ...

local M = ns.RosteurSection

function M.BuildPlayerUI(ctx)
	local const = ctx.const
	local ui = ctx.ui
	local fn = ctx.fn

	local ROLE_LABEL = const.ROLE_LABEL
	local ROLE_ATLAS = const.ROLE_ATLAS

	local playerPanel = ui.playerPanel

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
	playerChoice:SetText("Secimin: -")

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

	local playerLockedView = fn.MakeRosterView
		and fn.MakeRosterView(playerLocked, { namePrefix = "WoWGuilde_Rosteur_PlayerLockedView", enableDrag = false })
	if playerLockedView then
		playerLockedView:SetPoint("TOPLEFT", playerLockedTitle, "BOTTOMLEFT", 0, -10)
		playerLockedView:SetPoint("BOTTOMRIGHT", playerLocked, "BOTTOMRIGHT", 0, 0)
	end

	ui.playerIdle = playerIdle
	ui.playerConfig = playerConfig
	ui.playerSignup = playerSignup
	ui.playerLocked = playerLocked
	ui.playerCounts = playerCounts
	ui.roleButtons = roleButtons
	ui.playerChoice = playerChoice
	ui.playerClear = playerClear
	ui.playerLockedView = playerLockedView
end

return M
