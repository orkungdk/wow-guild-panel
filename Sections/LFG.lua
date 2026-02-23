-- Guild LFG section: Raid, Mythic+, Levelling, Achievement, Delve. List with Invite/Whisper. Logout = leave.
local ADDON, ns = ...
ns.Sections = ns.Sections or {}
local Sections = ns.Sections
local Comms = ns.Comms
local EventBus = ns.EventBus

local LFG_CATEGORIES = {
	{ key = "Raid", label = "Raid" },
	{ key = "Mythic+", label = "Mythic+" },
	{ key = "Levelling", label = "Levelling" },
	{ key = "Achievement", label = "Achievement" },
	{ key = "Delve", label = "Delve" },
}

local HEADER_HEIGHT = 50
local BG_PAD_L, BG_PAD_T, BG_PAD_R, BG_PAD_B = 3, -8, 0, 0
local WOOD_HEIGHT = 50
local ITEM_HEIGHT = 44
local LIST_PAD = 12

local function LocalFullName()
	local name = UnitName("player")
	local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName and GetRealmName() or ""
	if realm and realm ~= "" then
		return name .. "-" .. realm
	end
	return name or ""
end

function Sections.LFG(parent)
	local f = CreateFrame("Frame", "WoWGuilde_LFG", parent)
	f:SetAllPoints(parent)
	f:Hide()

	local bgFrame = CreateFrame("Frame", "WoWGuilde_LFG_BgFrame", f)
	bgFrame:SetAllPoints(f)
	bgFrame:SetFrameLevel(100)

	local topShadow = bgFrame:CreateTexture("WoWGuilde_LFG_TopShadow", "BORDER")
	topShadow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(HEADER_HEIGHT + 2))
	topShadow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(HEADER_HEIGHT + 2))
	topShadow:SetHeight(170)
	topShadow:SetAtlas("Artifacts-HeaderBG")
	topShadow:SetAlpha(0.6)

	local bg = bgFrame:CreateTexture("WoWGuilde_LFG_Bg", "BACKGROUND", nil, -2)
	bg:SetPoint("TOPLEFT", bgFrame, "TOPLEFT", BG_PAD_L, BG_PAD_T)
	bg:SetPoint("BOTTOMRIGHT", bgFrame, "BOTTOMRIGHT", BG_PAD_R, BG_PAD_B)
	bg:SetAtlas("auctionhouse-background-index")
	bg:SetAlpha(1)

	local topDecor = bgFrame:CreateTexture("WoWGuilde_LFG_TopDecor", "BACKGROUND", nil, -1)
	topDecor:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -4)
	topDecor:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -4)
	topDecor:SetAtlas("wood-topper", false)
	topDecor:SetHeight(WOOD_HEIGHT)
	topDecor:SetTexCoord(0.15, 1, 0, 1)

	local topLine = bgFrame:CreateTexture("WoWGuilde_LFG_TopLine", "BORDER")
	topLine:SetPoint("BOTTOMLEFT", f, "TOPLEFT", -2, -(HEADER_HEIGHT + 4))
	topLine:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 12, -(HEADER_HEIGHT + 4))
	topLine:SetHeight(2)
	topLine:SetAtlas("LevelUp-Glow-Gold")
	topLine:SetBlendMode("ADD")
	topLine:SetAlpha(0.85)

	local headerArea = CreateFrame("Frame", "WoWGuilde_LFG_HeaderArea", f)
	headerArea:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -2)
	headerArea:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -12)
	headerArea:SetHeight(HEADER_HEIGHT)

	local title = headerArea:CreateFontString("WoWGuilde_LFG_Title", "OVERLAY", nil, 2)
	title:SetPoint("TOPLEFT", headerArea, "TOPLEFT", 10, -8)
	title:SetFont("Fonts\\2002.ttf", 20, "OUTLINE")
	title:SetTextColor(0.894, 0.655, 0.125)
	title:SetText("Guild Aktivitesi Ara")

	local subtitle = headerArea:CreateFontString("WoWGuilde_LFG_Subtitle", "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
	subtitle:SetText("Raid, Mythic+, Levelling, Achievement veya Delve secin. Cikista listeden silinirsiniz.")

	local mainArea = CreateFrame("Frame", "WoWGuilde_LFG_MainArea", f)
	mainArea:SetPoint("TOPLEFT", headerArea, "BOTTOMLEFT", 0, -6)
	mainArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 0)

	local noGuildMsg = mainArea:CreateFontString("WoWGuilde_LFG_NoGuild", "OVERLAY", "GameFontNormalLarge")
	noGuildMsg:SetPoint("CENTER", mainArea, "CENTER", 0, 0)
	noGuildMsg:SetText("Guild uyesi degilsiniz.")
	noGuildMsg:Hide()

	local leftPanel = CreateFrame("Frame", "WoWGuilde_LFG_LeftPanel", mainArea)
	leftPanel:SetPoint("TOPLEFT", mainArea, "TOPLEFT", LIST_PAD, -LIST_PAD)
	leftPanel:SetWidth(320)
	leftPanel:SetPoint("BOTTOM", mainArea, "BOTTOM", 0, LIST_PAD)

	local catLabel = leftPanel:CreateFontString("WoWGuilde_LFG_CatLabel", "OVERLAY", "GameFontNormal")
	catLabel:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 0, 0)
	catLabel:SetText("Ne ariyorsunuz?")

	local myCategory = nil
	local categoryButtons = {}
	for i, cat in ipairs(LFG_CATEGORIES) do
		local btn = CreateFrame("Button", "WoWGuilde_LFG_Cat_" .. cat.key, leftPanel, "UIPanelButtonTemplate")
		btn:SetSize(140, 28)
		btn:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", ((i - 1) % 2) * 150, -28 - math.floor((i - 1) / 2) * 34)
		btn:SetText(cat.label)
		btn.catKey = cat.key
		btn:SetScript("OnClick", function()
			myCategory = cat.key
			for _, b in ipairs(categoryButtons) do
				if b.catKey == cat.key then
					b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
					local ht = b:GetHighlightTexture()
					if ht and ht.SetAlpha then ht:SetAlpha(1) end
					b:LockHighlight()
				else
					b:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
					local ht = b:GetHighlightTexture()
					if ht and ht.SetAlpha then ht:SetAlpha(0) end
					b:UnlockHighlight()
				end
			end
		end)
		categoryButtons[i] = btn
	end

	local noteLabel = leftPanel:CreateFontString("WoWGuilde_LFG_NoteLabel", "OVERLAY", "GameFontNormal")
	noteLabel:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 0, -132)
	noteLabel:SetText("Not (istege bagli)")

	local noteEdit = CreateFrame("EditBox", "WoWGuilde_LFG_NoteEdit", leftPanel, "InputBoxTemplate")
	noteEdit:SetSize(280, 22)
	noteEdit:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 0, -4)
	noteEdit:SetAutoFocus(false)
	noteEdit:SetMaxLetters(100)
	noteEdit:SetText("")

	local addRemoveBtn = CreateFrame("Button", "WoWGuilde_LFG_AddRemove", leftPanel, "UIPanelButtonTemplate")
	addRemoveBtn:SetSize(160, 32)
	addRemoveBtn:SetPoint("TOPLEFT", noteEdit, "BOTTOMLEFT", 0, -16)
	addRemoveBtn:SetText("Listeye ekle")

	local listArea = CreateFrame("Frame", "WoWGuilde_LFG_ListArea", mainArea)
	listArea:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", LIST_PAD * 2, 0)
	listArea:SetPoint("BOTTOMRIGHT", mainArea, "BOTTOMRIGHT", -LIST_PAD, LIST_PAD)

	local listTitle = listArea:CreateFontString("WoWGuilde_LFG_ListTitle", "OVERLAY", "GameFontNormalLarge")
	listTitle:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, 0)
	listTitle:SetText("Listedekiler")

	local scrollFrame = CreateFrame("ScrollFrame", "WoWGuilde_LFG_Scroll", listArea, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", listTitle, "BOTTOMLEFT", 0, -8)
	scrollFrame:SetPoint("BOTTOMRIGHT", listArea, "BOTTOMRIGHT", -24, 0)

	local scrollChild = CreateFrame("Frame", "WoWGuilde_LFG_ScrollChild", scrollFrame)
	scrollChild:SetSize(scrollFrame:GetWidth(), 1)
	scrollFrame:SetScrollChild(scrollChild)

	local emptyListMsg = listArea:CreateFontString("WoWGuilde_LFG_EmptyList", "OVERLAY", "GameFontHighlight")
	emptyListMsg:SetPoint("CENTER", scrollFrame, "CENTER", 0, 0)
	emptyListMsg:SetText("Henuz kimse eklemedi.")
	emptyListMsg:Hide()

	local itemPool = {}
	local function GetOrCreateItem(index)
		if not itemPool[index] then
			local row = CreateFrame("Frame", "WoWGuilde_LFG_Item" .. index, scrollChild)
			row:SetHeight(ITEM_HEIGHT)
			row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(index - 1) * ITEM_HEIGHT)
			row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

			local bg = row:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints(row)
			bg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
			row.bg = bg

			row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			row.nameText:SetPoint("LEFT", row, "LEFT", 8, 0)
			row.nameText:SetPoint("RIGHT", row, "RIGHT", -198, 0)
			row.nameText:SetJustifyH("LEFT")

			row.catText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.catText:SetPoint("LEFT", row.nameText, "LEFT", 0, 0)
			row.catText:SetPoint("RIGHT", row.nameText, "RIGHT", 0, 0)
			row.catText:SetPoint("TOP", row.nameText, "BOTTOM", 0, 2)
			row.catText:SetJustifyH("LEFT")

			row.whisperBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.whisperBtn:SetSize(70, 24)
			row.whisperBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
			row.whisperBtn:SetText("Whisper")

			row.inviteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.inviteBtn:SetSize(70, 24)
			row.inviteBtn:SetPoint("RIGHT", row.whisperBtn, "LEFT", -6, 0)
			row.inviteBtn:SetText("Davet et")

			row.removeBtn = CreateFrame("Button", nil, row)
			row.removeBtn:SetSize(24, 24)
			row.removeBtn:SetPoint("RIGHT", row.inviteBtn, "LEFT", -6, 0)
			local removeLabel = row.removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
			removeLabel:SetPoint("CENTER", row.removeBtn, "CENTER", 0, 0)
			removeLabel:SetTextColor(1, 0.3, 0.3, 1)
			removeLabel:SetText("X")
			row.removeBtn:SetScript("OnClick", function() end)
			row.removeBtn:SetScript("OnEnter", function(self)
				if GameTooltip then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText("Listeden cikar", 1, 1, 1, 1, true)
					GameTooltip:Show()
				end
			end)
			row.removeBtn:SetScript("OnLeave", function()
				if GameTooltip then GameTooltip:Hide() end
			end)

			itemPool[index] = row
		end
		return itemPool[index]
	end

	local function DoWhisper(fullName)
		if not fullName or fullName == "" then
			return
		end
		if ChatFrame_OpenChat then
			ChatFrame_OpenChat("/w " .. fullName .. " ", "SAY")
		else
			local edit = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend()
			if edit then
				edit:SetText("/w " .. fullName .. " ")
				edit:Show()
			end
		end
	end

	local function DoInvite(fullName)
		if not fullName or fullName == "" then
			return
		end
		if C_PartyInfo and C_PartyInfo.InviteUnit then
			C_PartyInfo.InviteUnit(fullName)
		end
	end

	local function RefreshList()
		local inGuild = IsInGuild and IsInGuild()
		noGuildMsg:SetShown(not inGuild)
		leftPanel:SetShown(inGuild)
		listArea:SetShown(inGuild)
		if not inGuild then
			return
		end

		local list = Comms and Comms.GetLFGList and Comms.GetLFGList() or {}
		local myName = LocalFullName()

		addRemoveBtn:SetText("Listeye ekle")
		addRemoveBtn:SetScript("OnClick", function()
			if not myCategory then
				return
			end
			local note = (noteEdit.GetText and noteEdit:GetText()) or ""
			if Comms and Comms.SendLFGAnn then
				Comms.SendLFGAnn(myCategory, note)
			end
			RefreshList()
		end)

		for _, b in ipairs(categoryButtons) do
			if b.catKey == myCategory then
				b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
				local ht = b:GetHighlightTexture()
				if ht and ht.SetAlpha then ht:SetAlpha(1) end
				b:LockHighlight()
			else
				b:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
				local ht = b:GetHighlightTexture()
				if ht and ht.SetAlpha then ht:SetAlpha(0) end
				b:UnlockHighlight()
			end
		end

		local ordered = list
		table.sort(ordered, function(a, b)
			if (a.name or "") ~= (b.name or "") then
				return (a.name or "") < (b.name or "")
			end
			return (a.category or "") < (b.category or "")
		end)

		for i, data in ipairs(ordered) do
			local row = GetOrCreateItem(i)
			row:Show()
			row.nameText:SetText(data.name or "")
			local sub = data.category or ""
			if data.note and data.note ~= "" then
				sub = sub .. " - " .. (data.note or "")
			end
			row.catText:SetText(sub)
			row.whisperBtn:SetScript("OnClick", function()
				DoWhisper(data.name)
			end)
			row.inviteBtn:SetScript("OnClick", function()
				DoInvite(data.name)
			end)
			local isOwn = (data.name == myName)
			if row.removeBtn then
				row.removeBtn:SetShown(isOwn)
				row.removeBtn:SetScript("OnClick", function()
					if isOwn and Comms and Comms.SendLFGLeave then
						Comms.SendLFGLeave(data.category)
						RefreshList()
					end
				end)
			end
		end
		for i = #ordered + 1, #itemPool do
			itemPool[i]:Hide()
		end

		scrollChild:SetHeight(math.max(1, #ordered * ITEM_HEIGHT))
		emptyListMsg:SetShown(#ordered == 0)
	end

	f:SetScript("OnShow", function()
		RefreshList()
	end)

	if EventBus and EventBus.On then
		EventBus.On("WG_LFG_UPDATED", function()
			if f:IsShown() then
				RefreshList()
			end
		end)
	end

	return f
end
