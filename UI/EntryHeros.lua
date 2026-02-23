local ADDON, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

function UI.CreateHeroEntry(parentFrame)
	local btn = CreateFrame("Button", nil, parentFrame)
	btn:SetSize(240, 36)

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetPoint("TOPLEFT", 9, 0)
	btn.bg:SetPoint("BOTTOMRIGHT", 0, -0)
	btn.bg:SetAtlas("PetList-ButtonBackground")
	btn.bg:SetAlpha(0.5)

	btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
	btn.hl:SetPoint("TOPLEFT", 9, 0)
	btn.hl:SetPoint("BOTTOMRIGHT", 1, -0)
	btn.hl:SetAtlas("PetList-ButtonHighlight")
	btn.hl:SetAlpha(1)

	btn.border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
	btn.border:SetPoint("TOPLEFT", 8, 1)
	btn.border:SetPoint("BOTTOMRIGHT", 2, -1)
	btn.border:SetBackdrop({
		bgFile = nil,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	btn.border:SetBackdropBorderColor(1, 1, 1, 0.3)

	btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	btn.name:SetPoint("TOPLEFT", btn, "TOPLEFT", 20, -6)
	btn.name:SetJustifyH("LEFT")

	btn.subtext = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	btn.subtext:SetPoint("TOPLEFT", btn.name, "BOTTOMLEFT", 0, -2)
	btn.subtext:SetJustifyH("LEFT")

	btn.classIcon = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
	btn.classIcon:SetSize(24, 24)
	btn.classIcon:SetPoint("RIGHT", btn, "RIGHT", -8, 0)

	local mask = btn:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(btn.classIcon)
	btn.classIcon:AddMaskTexture(mask)

	btn.classOverlay = btn:CreateTexture(nil, "OVERLAY", nil, 6)
	btn.classOverlay:SetAtlas("Adventurers-Followers-Uncommon-Base", true)
	btn.classOverlay:SetSize(39, 35)
	btn.classOverlay:SetPoint("CENTER", btn.classIcon, "CENTER", 0, 0)
	btn.classOverlay:SetVertexColor(1, 0.812, 0.325, 0.702)
	btn.classOverlay:SetAlpha(1)

	btn.onlineOverlay = btn:CreateTexture(nil, "OVERLAY", nil, 7)
	btn.onlineOverlay:SetAtlas("plunderstorm-map-zoneGreen-hover", true)
	btn.onlineOverlay:SetSize(12, 12)
	btn.onlineOverlay:SetPoint("CENTER", btn.classIcon, "CENTER", 9, -9)
	btn.onlineOverlay:Hide()

	function btn:SetOnlineStyle(isOnline, topName, forcedSubtext, fallbackSubtext, noNote)
		local showNewcomer = noNote == true
		if isOnline then
			btn.name:SetText(("|cffffff00%s|r"):format(topName))
			btn.classOverlay:SetVertexColor(0.8941, 0.6549, 0.1255, 0.8)
			btn.border:SetBackdropBorderColor(1, 0.9, 0.4, 0.5)
			btn.bg:SetAlpha(0.8)
			btn.onlineOverlay:SetAtlas(showNewcomer and "newplayerchat-chaticon-newcomer" or "plunderstorm-map-zoneGreen-hover", false)
			btn.onlineOverlay:Show()
			if forcedSubtext and forcedSubtext ~= "" then
				btn.subtext:SetText(forcedSubtext)
			else
				btn.subtext:SetText("|cff00ff00cevrimici|r")
			end
		else
			btn.name:SetText(("|cffffffff%s|r"):format(topName))
			btn.classOverlay:SetVertexColor(1, 1, 1, 0.6)
			btn.border:SetBackdropBorderColor(1, 1, 1, 0.3)
			btn.bg:SetAlpha(0.5)
			if showNewcomer then
				btn.onlineOverlay:SetAtlas("newplayerchat-chaticon-newcomer", false)
				btn.onlineOverlay:Show()
			else
				btn.onlineOverlay:Hide()
			end
			if forcedSubtext and forcedSubtext ~= "" then
				btn.subtext:SetText(forcedSubtext)
			else
				local txt = fallbackSubtext or ""
				if txt ~= "" then
					btn.subtext:SetText("|cff9d9d9d" .. txt .. "|r")
				else
					btn.subtext:SetText("")
				end
			end
		end
	end
	btn:SetScript("OnEnter", function(self)
		UI.ShowHeroTooltip(self, self.data)
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			if ns.Sections.Heros_OpenContextMenu then
				ns.Sections.Heros_OpenContextMenu(self, self.data)
			end
		end
	end)

	return btn
end
