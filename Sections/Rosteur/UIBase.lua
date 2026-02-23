local ADDON, ns = ...

local M = ns.RosteurSection

function M.BuildBaseUI(ctx)
	local ui = ctx.ui
	local parent = ctx.parent

	local HEADER_HEIGHT = 50
	local BG_PAD_L, BG_PAD_T, BG_PAD_R, BG_PAD_B = 3, -8, 0, 0
	local WOOD_PAD_L, WOOD_PAD_R, WOOD_PAD_T, WOOD_PAD_B = 3, 0, -4, 0
	local WOOD_HEIGHT = 50

	local f = CreateFrame("Frame", "WoWGuilde_Rosteur", parent)
	f:SetAllPoints(parent)
	f:Hide()

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

	ui.frame = f
	ui.bgFrame = f.bgFrame
	ui.topShadow = f.topShadow
	ui.bg = f.bg
	ui.topDecor = f.topDecor
	ui.topLine = f.topLine
	ui.headerArea = headerArea
	ui.title = title
	ui.subtitle = subtitle
	ui.mainArea = mainArea
	ui.managerPanel = managerPanel
	ui.playerPanel = playerPanel
	ui.resetZeroBtn = resetZeroBtn
end

return M
