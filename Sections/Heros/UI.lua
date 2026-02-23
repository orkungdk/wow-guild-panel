local ADDON, ns = ...

local M = ns.HerosSection

function M.BuildBaseUI(ctx)
	local const = ctx.const
	local ui = ctx.ui
	local Sections = ctx.Sections

	local LIST_WIDTH = const.LIST_WIDTH
	local HEADER_HEIGHT = const.HEADER_HEIGHT
	local BG_PAD_L, BG_PAD_T, BG_PAD_R, BG_PAD_B = const.BG_PAD_L, const.BG_PAD_T, const.BG_PAD_R, const.BG_PAD_B
	local NINESLICE_PAD_L, NINESLICE_PAD_T, NINESLICE_PAD_R, NINESLICE_PAD_B =
		const.NINESLICE_PAD_L, const.NINESLICE_PAD_T, const.NINESLICE_PAD_R, const.NINESLICE_PAD_B
	local WOOD_PAD_L, WOOD_PAD_R, WOOD_PAD_T, WOOD_PAD_B =
		const.WOOD_PAD_L, const.WOOD_PAD_R, const.WOOD_PAD_T, const.WOOD_PAD_B
	local WOOD_HEIGHT = const.WOOD_HEIGHT
	local FEATURED_SIZE = const.FEATURED_SIZE

	-- =========================================================
	-- Cadre principal
	-- =========================================================
	local f = CreateFrame("Frame", "WoWGuilde_HerosMenu", ctx.parent)
	f:SetAllPoints(ctx.parent)
	f:Hide()
	Sections.HerosFrame = f
	ui.frame = f

	local bg = f:CreateTexture("WoWGuilde_HerosBackground", "BACKGROUND", nil, -1)
	bg:SetAllPoints(f)
	bg:SetTexture("Interface\\QuestFrame\\UI-QuestLogDualPane-Background")
	bg:SetAlpha(0.8)
	bg:Hide()
	ui.bg = bg

	-- =========================================================
	-- Colonne gauche : liste défilante
	-- =========================================================
	local scrollFrame = CreateFrame("ScrollFrame", "WoWGuilde_HerosScrollFrame", f, "QuestScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -3)
	scrollFrame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 3)
	scrollFrame:SetWidth(LIST_WIDTH)

	scrollFrame.bg = scrollFrame:CreateTexture("WoWGuilde_HerosScrollBG", "BACKGROUND")
	scrollFrame.bg:SetPoint("TOPLEFT", 0, 0)
	scrollFrame.bg:SetPoint("BOTTOMRIGHT", 30, 0)
	scrollFrame.bg:SetAtlas("auctionhouse-background-summarylist")
	scrollFrame.bg:SetAlpha(1)

	scrollFrame.separator = scrollFrame:CreateTexture("WoWGuilde_HerosScrollSeparator", "BORDER")
	scrollFrame.separator:SetPoint("TOPLEFT", scrollFrame.bg, "TOPRIGHT", 0, -2)
	scrollFrame.separator:SetPoint("BOTTOMLEFT", scrollFrame.bg, "BOTTOMRIGHT", 0, 0)
	scrollFrame.separator:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
	scrollFrame.separator:SetWidth(2)
	scrollFrame.separator:SetAtlas("UI-Achievement-Border-3")
	scrollFrame.separator:SetAlpha(0.8)

	scrollFrame.bottomDecor = scrollFrame:CreateTexture("WoWGuilde_HerosScrollBottom", "BORDER")
	scrollFrame.bottomDecor:SetPoint("BOTTOM", scrollFrame.bg, "BOTTOM", -10, 20)
	scrollFrame.bottomDecor:SetSize(180, 180)
	scrollFrame.bottomDecor:SetAtlas("BfAMission-Icon-HUB")
	scrollFrame.bottomDecor:SetAlpha(0.1)

	local content = CreateFrame("Frame", "WoWGuilde_HerosContent", scrollFrame)
	content:SetSize(LIST_WIDTH, 400)
	scrollFrame:SetScrollChild(content)

	ui.scrollFrame = scrollFrame
	ui.rosterListContent = content

	-- =========================================================
	-- Pied de liste : total de kisi cevrimici
	-- =========================================================
	local footer = CreateFrame("Button", "WoWGuilde_HerosRosterFooter", scrollFrame)
	footer:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMLEFT", 8, -23)
	footer:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -28, -23)
	footer:SetHeight(18)
	footer:EnableMouse(true)

	footer.text = footer:CreateFontString("WoWGuilde_HerosRosterFooterText", "OVERLAY", "GameFontHighlightSmall")
	footer.text:SetPoint("CENTER", footer, "CENTER", 0, 0)
	footer.text:SetJustifyH("CENTER")
	footer.text:SetText("0 kahraman cevrimici.")

	footer.countOnline = 0
	footer.countRecent = 0
	footer.countCharacters = 0

	footer:SetScript("OnEnter", function(self)
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Kahramanlar", 1, 0.82, 0, 1)
		local onlineText = (self.countOnline == 1) and "|A:plunderstorm-map-zoneGreen-hover:12:12|a 1 kahraman cevrimici"
			or string.format("|A:plunderstorm-map-zoneGreen-hover:12:12|a %d kahraman cevrimici.", self.countOnline or 0)
		local recentText = string.format("- %d kahraman son zamanlarda guild'i hareketlendirdi.", self.countRecent or 0)
		local totalCharsText = string.format("- Guild'de %d karakter var.", self.countCharacters or 0)
		GameTooltip:AddLine(onlineText, 1, 1, 1, true)
		GameTooltip:AddLine(recentText, 1, 1, 1, true)
		GameTooltip:AddLine(totalCharsText, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	footer:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)

	ui.rosterFooter = footer

	-- =========================================================
	-- Zone centrale : profil et contenu
	-- =========================================================
	local profileArea = CreateFrame("Frame", "WoWGuilde_HerosProfileArea", f)
	profileArea:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 30, 0)
	profileArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	ui.profileArea = profileArea

	-- Groupe de fonds (toutes les textures de fond vont ici)
	profileArea.bgFrame = CreateFrame("Frame", nil, profileArea)
	profileArea.bgFrame:SetAllPoints(profileArea)
	profileArea.bgFrame:SetFrameLevel(101)

	profileArea.topShadow = profileArea.bgFrame:CreateTexture(nil, "BORDER")
	profileArea.topShadow:SetPoint("TOPLEFT", profileArea, "TOPLEFT", 0, -(HEADER_HEIGHT + 2))
	profileArea.topShadow:SetPoint("TOPRIGHT", profileArea, "TOPRIGHT", 0, -(HEADER_HEIGHT + 2))
	profileArea.topShadow:SetHeight(170)
	profileArea.topShadow:SetAtlas("Artifacts-HeaderBG")
	profileArea.topShadow:SetAlpha(0.6)

	profileArea.bg = profileArea.bgFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
	profileArea.bg:SetPoint("TOPLEFT", profileArea.bgFrame, "TOPLEFT", BG_PAD_L, BG_PAD_T)
	profileArea.bg:SetPoint("BOTTOMRIGHT", profileArea.bgFrame, "BOTTOMRIGHT", BG_PAD_R, BG_PAD_B)
	profileArea.bg:SetDrawLayer("BACKGROUND", -8)
	profileArea.bg:SetAtlas("auctionhouse-background-index")
	profileArea.bg:SetAlpha(1)

	profileArea.nineSlice = CreateFrame("Frame", nil, profileArea.bgFrame, "NineSlicePanelTemplate")
	profileArea.nineSlice:SetPoint("TOPLEFT", profileArea.bgFrame, "TOPLEFT", NINESLICE_PAD_L, NINESLICE_PAD_T)
	profileArea.nineSlice:SetPoint("BOTTOMRIGHT", profileArea.bgFrame, "BOTTOMRIGHT", NINESLICE_PAD_R, NINESLICE_PAD_B)
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
		NineSliceUtil.ApplyLayoutByName(profileArea.nineSlice, "InsetFrameTemplate")
	end
	local nslice = profileArea.nineSlice.NineSlice or profileArea.nineSlice
	if nslice then
		if nslice.TopLeftCorner then
			nslice.TopLeftCorner:Hide()
		end
		if nslice.BottomLeftCorner then
			nslice.BottomLeftCorner:Hide()
		end
		if nslice.LeftEdge then
			nslice.LeftEdge:Hide()
		end
	end

	-- =========================================================
	-- Profil : cadre principal
	-- =========================================================
	local profile = CreateFrame("Frame", "WoWGuilde_HerosProfile", profileArea)
	profile:SetAllPoints(profileArea)
	ui.profile = profile

	-- =========================================================
	-- En-tête (bande bois, nom, icône, décor)
	-- =========================================================
	profile.header = CreateFrame("Frame", "WoWGuilde_HerosProfile_Header", profileArea)
	profile.header:SetPoint("TOPLEFT", profileArea, "TOPLEFT", 10, 0)
	profile.header:SetPoint("TOPRIGHT", profileArea, "TOPRIGHT", 0, -8)
	profile.header:SetHeight(HEADER_HEIGHT)
	profile.header:SetFrameLevel(profile:GetFrameLevel() + 5)

	profileArea.topDecor = profileArea.bgFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
	profileArea.topDecor:SetPoint("TOPLEFT", profileArea, "TOPLEFT", WOOD_PAD_L, WOOD_PAD_T)
	profileArea.topDecor:SetPoint("TOPRIGHT", profileArea, "TOPRIGHT", WOOD_PAD_R, WOOD_PAD_B)
	profileArea.topDecor:SetAtlas("wood-topper", false)
	profileArea.topDecor:SetHeight(WOOD_HEIGHT)
	profileArea.topDecor:SetTexCoord(0.15, 1, 0, 1)

	profileArea.topLine = profileArea.bgFrame:CreateTexture(nil, "BORDER")
	profileArea.topLine:SetPoint("BOTTOMLEFT", profileArea, "TOPLEFT", -12, -(HEADER_HEIGHT + 2))
	profileArea.topLine:SetPoint("BOTTOMRIGHT", profileArea, "TOPRIGHT", 12, -(HEADER_HEIGHT + 2))
	profileArea.topLine:SetHeight(5)
	profileArea.topLine:SetAtlas("LevelUp-Bar-Gold")
	profileArea.topLine:SetAlpha(0.8)

	profile.classIcon = profile.header:CreateTexture(nil, "ARTWORK")
	profile.classIcon:SetSize(48, 48)
	profile.classIcon:SetPoint("LEFT", 4, -2)
	profile.classIcon:SetAlpha(1)

	profile.classIconMask = profile.header:CreateMaskTexture(nil, "ARTWORK")
	profile.classIconMask:SetAllPoints(profile.classIcon)
	profile.classIconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	profile.classIcon:AddMaskTexture(profile.classIconMask)

	profile.classOverlay = profile.header:CreateTexture(nil, "OVERLAY", nil, 1)
	profile.classOverlay:SetAtlas("charactercreate-ring-metallight", true)
	profile.classOverlay:SetSize(82, 82)
	profile.classOverlay:SetPoint("CENTER", profile.classIcon, "CENTER", 0, 0)
	profile.classOverlay:SetAlpha(0.9)

	profile.classOverlayShadow = profile.header:CreateTexture(nil, "OVERLAY", nil, -5)
	profile.classOverlayShadow:SetAtlas("common-roundhighlight", true)
	profile.classOverlayShadow:SetSize(42, 42)
	profile.classOverlayShadow:SetPoint("CENTER", profile.classIcon, "CENTER", 0, 0)
	profile.classOverlayShadow:SetAlpha(1)
	profile.classOverlayShadow:SetVertexColor(0, 0, 0, 1)

	profile.name = profile.header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	profile.name:SetPoint("LEFT", profile.classIcon, "RIGHT", 12, 8)
	profile.name:SetPoint("RIGHT", -(FEATURED_SIZE + 16), 0)
	profile.name:SetJustifyH("LEFT")
	profile.nameBtn = CreateFrame("Button", "WoWGuilde_ProfileNameBtn", profile.header)
	profile.nameBtn:SetFrameLevel(profile.header:GetFrameLevel() + 5)
	profile.nameBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	profile.nameBtn:EnableMouse(true)
	profile.nameBtn:SetAllPoints(profile.name)
	profile.nameBtn:SetScript("OnClick", function(_, button)
		if profile and profile.ProfileName_OnClick then
			profile:ProfileName_OnClick(button)
		end
	end)
	profile.nameBtn:SetScript("OnEnter", function(self)
		if profile and profile.ProfileName_OnEnter then
			profile:ProfileName_OnEnter(self)
		end
	end)
	profile.nameBtn:SetScript("OnLeave", function(self)
		if profile and profile.ProfileName_OnLeave then
			profile:ProfileName_OnLeave(self)
		end
	end)

	profile.epicLine = profile.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	profile.epicLine:SetPoint("TOPLEFT", profile.name, "BOTTOMLEFT", 0, -2)
	profile.epicLine:SetPoint("RIGHT", -8, 0)
	profile.epicLine:SetJustifyH("LEFT")
	profile.epicLine:SetTextColor(1, 0.82, 0, 1)
	profile.epicLine:Hide()

	profile.subline = profile.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	profile.subline:SetPoint("TOPLEFT", profile.epicLine, "BOTTOMLEFT", 0, -2)
	profile.subline:SetPoint("RIGHT", -8, 0)
	profile.subline:SetJustifyH("LEFT")

	profile.legendaryNewsSlot = CreateFrame("Button", "legendaryNews", profile.header)
	profile.legendaryNewsSlot:SetSize(FEATURED_SIZE / 2, FEATURED_SIZE)
	profile.legendaryNewsSlot:SetPoint("RIGHT", profile.header, "RIGHT", 0, -38)
	profile.legendaryNewsSlot:EnableMouse(true)
	profile.legendaryNewsSlot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	profile.legendaryNewsSlot:SetFrameStrata("TOOLTIP")
	profile.legendaryNewsSlot:SetClipsChildren(false)

	profile.legendaryNewsSlot.bg = profile.legendaryNewsSlot:CreateTexture(nil, "BACKGROUND")
	profile.legendaryNewsSlot.bg:SetAllPoints(profile.legendaryNewsSlot)
	profile.legendaryNewsSlot.bg:SetAtlas("ChallengeMode-SpikeyStar")
	profile.legendaryNewsSlot.bg:SetTexCoord(0, 0.5, 0, 1)
	profile.legendaryNewsSlot.bg:SetAlpha(1)

	profile.legendaryNewsSlot.bgBorder = profile.legendaryNewsSlot:CreateTexture(nil, "BORDER")
	profile.legendaryNewsSlot.bgBorder:ClearAllPoints()
	profile.legendaryNewsSlot.bgBorder:SetPoint("CENTER", profile.legendaryNewsSlot, "CENTER", 10, 0)
	profile.legendaryNewsSlot.bgBorder:SetSize((FEATURED_SIZE / 2) - 20, FEATURED_SIZE - 20)
	profile.legendaryNewsSlot.bgBorder:SetAtlas("heartofazeroth-slot-minor-glass")
	profile.legendaryNewsSlot.bgBorder:SetTexCoord(0, 0.5, 0, 1)
	profile.legendaryNewsSlot.bgBorder:SetBlendMode("ADD")
	profile.legendaryNewsSlot.bgBorder:SetAlpha(0.5)

	profile.legendaryNewsSlot.icon = profile.legendaryNewsSlot:CreateTexture(nil, "ARTWORK")
	profile.legendaryNewsSlot.icon:SetPoint("CENTER", profile.legendaryNewsSlot, "RIGHT", 0, 0)
	profile.legendaryNewsSlot.icon:SetSize(FEATURED_SIZE - 65, FEATURED_SIZE - 65)
	profile.legendaryNewsSlot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	profile.legendaryNewsSlot.icon:Hide()

	profile.legendaryNewsSlot.iconMask = profile.legendaryNewsSlot:CreateMaskTexture(nil, "ARTWORK")
	profile.legendaryNewsSlot.iconMask:SetAllPoints(profile.legendaryNewsSlot.icon)
	profile.legendaryNewsSlot.iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	profile.legendaryNewsSlot.icon:AddMaskTexture(profile.legendaryNewsSlot.iconMask)

	profile.legendaryNewsSlot.iconBorder = profile.legendaryNewsSlot:CreateTexture(nil, "OVERLAY", nil, 1)
	profile.legendaryNewsSlot.iconBorder:SetPoint("CENTER", profile.legendaryNewsSlot.icon, "CENTER", 0, 1)
	profile.legendaryNewsSlot.iconBorder:SetAtlas("charactercreate-ring-select")
	profile.legendaryNewsSlot.iconBorder:SetVertexColor(1, 0.702, 0.325, 0.781)
	profile.legendaryNewsSlot.iconBorder:SetSize(FEATURED_SIZE - 35, FEATURED_SIZE - 35)
	profile.legendaryNewsSlot.iconBorder:SetAlpha(0.9)

	profile.legendaryNewsSlot.glow = profile.legendaryNewsSlot:CreateTexture(nil, "OVERLAY")
	profile.legendaryNewsSlot.glow:SetAllPoints(profile.legendaryNewsSlot)
	profile.legendaryNewsSlot.glow:SetAtlas("GarrMission_CurrentEncounter-Glow")
	profile.legendaryNewsSlot.glow:SetTexCoord(0, 0.5, 0, 1)
	profile.legendaryNewsSlot.glow:SetBlendMode("ADD")
	profile.legendaryNewsSlot.glow:SetAlpha(0.6)
	profile.legendaryNewsSlot.glow:Hide()

	local dragIcon = CreateFrame("Frame", nil, UIParent)
	dragIcon.size = 40
	dragIcon:SetSize(dragIcon.size, dragIcon.size)
	dragIcon:SetFrameStrata("FULLSCREEN_DIALOG")
	dragIcon:SetFrameLevel(300)
	dragIcon:SetClampedToScreen(true)
	dragIcon:EnableMouse(false)
	dragIcon:Hide()
	dragIcon.icon = dragIcon:CreateTexture(nil, "ARTWORK", nil, 1)
	dragIcon.icon:SetAllPoints(dragIcon)
	dragIcon.icon:SetAlpha(1)
	dragIcon.icon:SetDrawLayer("ARTWORK", 0)

	dragIcon.iconMask = dragIcon:CreateMaskTexture(nil, "ARTWORK")
	dragIcon.iconMask:SetAllPoints(dragIcon.icon)
	dragIcon.iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	dragIcon.icon:AddMaskTexture(dragIcon.iconMask)

	dragIcon.iconBorder = dragIcon:CreateTexture(nil, "OVERLAY", nil, 4)
	dragIcon.iconBorder:SetPoint("CENTER", dragIcon.icon, "CENTER", 0, 0)
	dragIcon.iconBorder:SetSize(50, 50)
	dragIcon.iconBorder:SetAtlas("Map_Faction_Ring")
	dragIcon.iconBorder:SetAlpha(1)
	dragIcon.iconBorder:SetDrawLayer("OVERLAY", 1)

	dragIcon.iconBorder2 = dragIcon:CreateTexture(nil, "BACKGROUND", nil, 2)
	dragIcon.iconBorder2:SetPoint("CENTER", dragIcon.icon, "CENTER", 0, 0)
	dragIcon.iconBorder2:SetSize(60, 60)
	dragIcon.iconBorder2:SetAtlas("shop-drop-shadow")
	dragIcon.iconBorder2:SetDrawLayer("BACKGROUND", 0)

	dragIcon.OnUpdate = function(self)
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	end

	ui.dragIcon = dragIcon

	profile:Hide()
end

return M
