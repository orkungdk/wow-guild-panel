local ADDON, ns = ...

local M = ns.HerosSection

function M.BuildNewsList(ctx)
	local ns = ctx.ns
	local HU = ctx.HU
	local const = ctx.const
	local state = ctx.state
	local ui = ctx.ui
	local fn = ctx.fn

	local HERO_LIST_CFG = const.HERO_LIST_CFG

	local newsHero = CreateFrame("Frame", "WoWGuilde_HerosNewsHero", ui.profile)
	ui.profile.newsHero = newsHero

	local newsArea = CreateFrame("Frame", "WoWGuilde_HerosNewsArea", newsHero)
	newsArea:SetPoint("RIGHT", ui.profileArea, "RIGHT", HERO_LIST_CFG.columnX, HERO_LIST_CFG.columnY)
	newsArea:SetSize(HERO_LIST_CFG.columnWidth, HERO_LIST_CFG.columnHeight)
	newsHero:SetAllPoints(newsArea)
	ui.newsArea = newsArea

	local newsBg = newsArea:CreateTexture(nil, "BACKGROUND")
	newsBg:SetPoint("TOPLEFT", newsArea, "TOPLEFT", -10, 10)
	newsBg:SetPoint("BOTTOMRIGHT", newsArea, "BOTTOMRIGHT", 35, -10)
	newsBg:SetAtlas("glues-gameMode-BG")
	newsBg:SetAlpha(0.6)

	local listTitle = newsArea:CreateFontString(nil, "OVERLAY", nil, 2)
	listTitle:SetPoint("TOPLEFT", newsArea, "TOPLEFT", -5, 65)
	listTitle:SetFont("Fonts\\MORPHEUS.ttf", 20, "OUTLINE")
	listTitle:SetTextColor(0.894, 0.655, 0.125, 1)
	listTitle:SetText("Kahraman haberleri")
	ui.listTitle = listTitle

	local function List_UpdateTitle()
		if not listTitle then
			return
		end
		if not state.heroNewsTarget then
			if state.newsState.filter.onlyProud then
				listTitle:SetText("Kahraman gururlari")
			else
				listTitle:SetText("Kahraman haberleri")
			end
			return
		end
		local name = state.heroNewsTarget.display or "kahraman"
		if state.newsState.filter.onlyProud then
			listTitle:SetText("Gururlar: " .. name)
		else
			listTitle:SetText("Haberler: " .. name)
		end
	end
	List_UpdateTitle()

	local listDropdown =
		CreateFrame("DropdownButton", "WoWGuilde_HerosNewsDropdown", newsArea, "WowStyle1DropdownTemplate")
	listDropdown:SetPoint("TOPLEFT", listTitle, "BOTTOMLEFT", 0, -5)
	listDropdown:SetSize(160, 25)
	listDropdown.SetSelectionText = function() end
	listDropdown:SetScript("OnEnter", function() end)
	listDropdown:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	listDropdown:SetDefaultText("Filtreler")

	local function Filter_ToggleOnlyProud()
		state.newsState.filter.onlyProud = not state.newsState.filter.onlyProud
		if fn.Filter_Sync then
			fn.Filter_Sync()
		end
		if List_UpdateTitle then
			List_UpdateTitle()
		end
		if fn.List_Refresh then
			fn.List_Refresh()
		end
	end

	local function Filter_SetAllTypes(enabled)
		if fn.Filter_EnsureTypes then
			fn.Filter_EnsureTypes()
		end
		for key in pairs(state.newsState.filter.types) do
			state.newsState.filter.types[key] = enabled
		end
		if fn.Filter_Sync then
			fn.Filter_Sync()
		end
		if fn.List_Refresh then
			fn.List_Refresh()
		end
	end

	local function Filter_ToggleType(key)
		if fn.Filter_EnsureTypes then
			fn.Filter_EnsureTypes()
		end
		state.newsState.filter.types[key] = not state.newsState.filter.types[key]
		if fn.Filter_Sync then
			fn.Filter_Sync()
		end
		if fn.List_Refresh then
			fn.List_Refresh()
		end
	end

	local function Dropdown_AddToggleEntry(menu, label, getter, toggler)
		if menu.CreateCheckbox then
			menu:CreateCheckbox(label, getter, toggler)
		else
			menu:CreateButton(label, toggler, { isNotRadio = true, checked = getter })
		end
	end

	local function Dropdown_Generate(owner, root)
		Dropdown_AddToggleEntry(root, "Sadece gururlar", function()
			return state.newsState.filter.onlyProud
		end, Filter_ToggleOnlyProud)
		if root.CreateDivider then
			root:CreateDivider()
		end
		local typesMenu = root:CreateButton("Haber turleri")
		if typesMenu then
			typesMenu:CreateButton("Hepsini goster", function()
				Filter_SetAllTypes(true)
			end)
			typesMenu:CreateButton("Hepsini gizle", function()
				Filter_SetAllTypes(false)
			end)
			if typesMenu.CreateDivider then
				typesMenu:CreateDivider()
			end
			for _, group in ipairs(const.NEWS_TYPE_GROUPS) do
				local sub = typesMenu:CreateButton(group.label)
				if sub then
					for _, key in ipairs(group.keys) do
						Dropdown_AddToggleEntry(
							sub,
							fn.News_GetTypeLabel and fn.News_GetTypeLabel(key) or key,
							function()
								if fn.Filter_EnsureTypes then
									fn.Filter_EnsureTypes()
								end
								return state.newsState.filter.types[key] == true
							end,
							function()
								Filter_ToggleType(key)
							end
						)
					end
				end
			end
			if #const.NEWS_TYPE_UNGROUPED > 0 then
				local sub = typesMenu:CreateButton("Diger")
				if sub then
					for _, key in ipairs(const.NEWS_TYPE_UNGROUPED) do
						Dropdown_AddToggleEntry(
							sub,
							fn.News_GetTypeLabel and fn.News_GetTypeLabel(key) or key,
							function()
								if fn.Filter_EnsureTypes then
									fn.Filter_EnsureTypes()
								end
								return state.newsState.filter.types[key] == true
							end,
							function()
								Filter_ToggleType(key)
							end
						)
					end
				end
			end
		end
	end
	listDropdown:SetupMenu(Dropdown_Generate)

	local listFrame = CreateFrame("Frame", "WoWGuilde_HerosNewsListFrame", newsArea)
	listFrame:SetPoint("TOPLEFT", newsArea, "TOPLEFT", 0, 0)
	listFrame:SetPoint("BOTTOMRIGHT", newsArea, "BOTTOMRIGHT", -HERO_LIST_CFG.listFrameRightPad, 0)
	ui.listFrame = listFrame

	local listScroll =
		CreateFrame("ScrollFrame", "WoWGuilde_HerosNewsListScroll", listFrame, "QuestScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, 0)
	listScroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", 0, 0)

	local listContent = CreateFrame("Frame", "WoWGuilde_HerosNewsListContent", listScroll)
	listContent:SetSize(1, 1)
	listScroll:SetScrollChild(listContent)
	ui.newsListContent = listContent

	local listEntries = {}
	ui.listEntries = listEntries
	local listEntryCount = 0

	local function List_CreateEntry(parent)
		listEntryCount = listEntryCount + 1
		local item = CreateFrame("Button", "WoWGuilde_HerosNewsListEntry" .. listEntryCount, parent)
		item:SetHeight(HERO_LIST_CFG.itemHeight)
		item:EnableMouse(true)
		item:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		local bg = item:CreateTexture(nil, "BACKGROUND")
		bg:SetPoint("TOPLEFT", item, "TOPLEFT", HERO_LIST_CFG.bgLeftPad, 0)
		bg:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, 0)
		bg:SetAtlas("glues-gameMode-BG")
		bg:SetAlpha(1)
		bg:SetVertexColor(1, 1, 1, 0.8)
		item.bg = bg

		local hover = item:CreateTexture(nil, "HIGHLIGHT")
		hover:SetPoint("TOPLEFT", item, "TOPLEFT", HERO_LIST_CFG.bgLeftPad, 0)
		hover:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, 0)
		hover:SetAtlas("glues-gameMode-BG")
		hover:SetBlendMode("ADD")
		hover:SetAlpha(0.65)
		item.hover = hover

		local iconFrame = CreateFrame("Frame", item:GetName() .. "Icon", item)
		iconFrame:SetPoint("LEFT", item, "LEFT", HERO_LIST_CFG.iconPad, 0)
		iconFrame:SetSize(HERO_LIST_CFG.iconSize, HERO_LIST_CFG.iconSize)

		local icon = iconFrame:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints(iconFrame)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		item.icon = icon

		local iconOverlay = iconFrame:CreateTexture(nil, "OVERLAY")
		iconOverlay:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
		HU.Util_SetAtlasOrTexture(iconOverlay, "plunderstorm-actionbar-slot-border", "Interface\\Buttons\\WHITE8x8")
		iconOverlay:SetSize(HERO_LIST_CFG.overlaySize, HERO_LIST_CFG.overlaySize)
		iconOverlay:SetAlpha(1)
		item.iconOverlay = iconOverlay

		local proudOverlay = iconFrame:CreateTexture(nil, "OVERLAY")
		proudOverlay:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
		proudOverlay:SetAtlas("chatframe-button-highlightalert")
		proudOverlay:SetSize(HERO_LIST_CFG.iconSize + 20, HERO_LIST_CFG.iconSize + 20)
		proudOverlay:SetAlpha(0.5)
		proudOverlay:SetBlendMode("ADD")
		proudOverlay:Hide()
		item.proudOverlay = proudOverlay

		local mineBadge = CreateFrame("Button", "Minebadge", iconFrame)
		mineBadge:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", -8, -4)
		mineBadge:SetSize(14, 14)
		mineBadge:EnableMouse(true)
		mineBadge:RegisterForClicks("RightButtonUp")
		mineBadge:SetFrameLevel(iconFrame:GetFrameLevel() + 3)
		mineBadge:Hide()

		local iconFx = mineBadge:CreateTexture(nil, "BACKGROUND")
		iconFx:SetPoint("CENTER", mineBadge, "CENTER", 0, 0)
		iconFx:SetSize(18, 18)
		iconFx:SetAtlas("UI-Frame-CypherChoice-Portrait-FX-Mask")
		iconFx:SetVertexColor(1, 1, 1, 0.6)
		item.iconFx = iconFx

		local mineTex = mineBadge:CreateTexture(nil, "ARTWORK")
		mineTex:SetAllPoints(mineBadge)
		HU.Util_SetAtlasOrTexture(mineTex, const.BADGE_MINE_ATLAS, const.BADGE_MINE_TEX)
		mineBadge.icon = mineTex

		mineBadge:SetScript("OnEnter", function(self)
			if not self._isMine then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", 4, -4)
			GameTooltip:ClearLines()
			local msg = "Vous avez fait cette actualité"
			if not self._isMine then
				msg = "Actualité marquée fière"
			end
			GameTooltip:AddLine(msg, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		mineBadge:SetScript("OnLeave", function(self)
			local parentItem = self._item
			if parentItem and parentItem:IsMouseOver() then
				local onEnter = parentItem:GetScript("OnEnter")
				if onEnter then
					onEnter(parentItem)
				end
				return
			end
			GameTooltip:Hide()
		end)
		mineBadge:SetScript("OnClick", function(self, button)
			if button ~= "RightButton" then
				return
			end
			if not self._news or not (fn.CanOpenNewsMenu and fn.CanOpenNewsMenu(self._news, self._isMine)) then
				return
			end
			GameTooltip:Hide()
			if fn.Proud_OpenMenu then
				fn.Proud_OpenMenu(self, self._news, self._isMine)
			end
		end)
		item.mineBadge = mineBadge

		local title = item:CreateFontString(nil, "OVERLAY")
		title:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", HERO_LIST_CFG.textLeftPad, -4)
		title:SetPoint("RIGHT", item, "RIGHT", -HERO_LIST_CFG.textRightPad, 0)
		title:SetFont("Fonts\\2002.ttf", 14, "OUTLINE")
		title:SetTextColor(0.894, 0.655, 0.125, 1)
		title:SetJustifyH("LEFT")
		item.title = title

		local text = item:CreateFontString(nil, "OVERLAY")
		text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
		text:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -HERO_LIST_CFG.textRightPad, HERO_LIST_CFG.textBottomPad)
		text:SetFont("Fonts\\FRIZQT__.TTF", 12)
		text:SetTextColor(1, 1, 1, 1)
		text:SetJustifyH("LEFT")
		text:SetJustifyV("TOP")
		text:SetWordWrap(true)
		item.text = text

		item:SetScript("OnEnter", function(self)
			if not self._news then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("LEFT", self, "RIGHT", 10, 0)
			GameTooltip:ClearLines()
			local titleText = self._news.title or (fn.News_GetTypeLabel and fn.News_GetTypeLabel(self._news.type))
			GameTooltip:AddLine(titleText, 0.8941, 0.6549, 0.1255)
			local body = self._news.text or ""
			if ns and ns.Utils and ns.Utils.ReplaceNewsTags then
				body = ns.Utils.ReplaceNewsTags(body, self._news.time)
			end
			GameTooltip:AddLine(body, 1, 1, 1, true)
			if
				fn.Featured_IsNewsFeatured
				and fn.Featured_IsNewsFeatured(fn.Proud_GetGuildUID and fn.Proud_GetGuildUID(self._news), self._news.id)
			then
				GameTooltip:AddLine("Cette prouesse est une fièreté légendaire.", 1, 0.5, 0, true)
			end
			local proudLine = nil
			if fn.Proud_IsChecked and fn.Proud_IsChecked(self._news) then
				proudLine = "Vous êtes fier de votre actualité !"
			elseif fn.Proud_HasAnyOther and fn.Proud_HasAnyOther(self._news) then
				local byStore = fn.Proud_GetByStore and fn.Proud_GetByStore(self._news and self._news.guildUID) or nil
				local by = byStore and byStore[self._news.id]
				local name = by and next(by)
				if name and name ~= "" then
					proudLine = name
						.. " est tres fier de son actualité !\nN'hesitez pas a lui remettre vos félicitations."
				end
			end
			if proudLine then
				GameTooltip:AddLine(proudLine, 0.95, 0.82, 0.35, true)
			end
			GameTooltip:AddLine(HU.Util_PrettyTimeAgo(self._news.time), 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		item:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		item:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				if self._news and fn.CanOpenNewsMenu and fn.CanOpenNewsMenu(self._news, self._isMine) then
					GameTooltip:Hide()
					if fn.Proud_OpenMenu then
						fn.Proud_OpenMenu(self, self._news, self._isMine)
					end
				end
				return
			end
			if self._action then
				self._action()
			end
		end)

		item:SetScript("OnMouseDown", function(self, button)
			if button ~= "LeftButton" then
				return
			end
			if not (state.heroNewsTarget and state.heroNewsTarget.isSelf) then
				return
			end
			if self._news and fn.Featured_StartDrag then
				fn.Featured_StartDrag(self._news, "news")
			end
		end)
		item:SetScript("OnMouseUp", function(self, button)
			if button ~= "LeftButton" then
				return
			end
			if state.featuredDragNews and state.heroNewsTarget and state.heroNewsTarget.isSelf then
				if state.featuredDragMode == "clear" then
					if fn.Featured_ClearForData then
						fn.Featured_ClearForData(state.heroNewsTarget.data)
					end
					if fn.Featured_EndDrag then
						fn.Featured_EndDrag()
					end
					return
				end
				if ui.profile and ui.profile.legendaryNewsSlot and ui.profile.legendaryNewsSlot:IsMouseOver() then
					if fn.Featured_SetFromNews then
						fn.Featured_SetFromNews(state.heroNewsTarget.data, state.featuredDragNews)
					end
				end
			end
			if fn.Featured_EndDrag then
				fn.Featured_EndDrag()
			end
		end)

		return item
	end

	local function List_SetEntryData(item, news)
		local title = (news and news.title)
			or (news and fn.News_GetTypeLabel and fn.News_GetTypeLabel(news.type))
			or "Actualité"
		local body = (news and news.text) or ""
		title = title:gsub("[\r\n]+", " ")
		body = body:gsub("[\r\n]+", " ")
		if news and ns and ns.Utils and ns.Utils.ReplaceNewsTags then
			body = ns.Utils.ReplaceNewsTags(body, news.time)
		end
		item.title:SetText(title)
		item.text:SetText(body)
		item._news = news
		item._isMine = not not (news and fn.Filter_IsMyNews and fn.Filter_IsMyNews(news))
		local isFeatured = news
			and news.id
			and fn.Featured_IsNewsFeatured
			and fn.Featured_IsNewsFeatured(news.guildUID, news.id)
		if news and news.icon and item.icon then
			HU.Util_SetPearlIcon(item.icon, news.icon, HERO_LIST_CFG.iconSize)
		else
			HU.Util_SetPearlIcon(item.icon, nil, HERO_LIST_CFG.iconSize)
		end
		if item.mineBadge then
			local isMine = item._isMine
			local proudOther = news and fn.Proud_HasAnyOther and fn.Proud_HasAnyOther(news)
			local proudMe = news and fn.Proud_IsChecked and fn.Proud_IsChecked(news)
			local proudAny = (not not proudOther) or not not proudMe
			if isFeatured then
				proudAny = true
			end
			local showBadge = not not isMine
			item.mineBadge:SetShown(showBadge)
			item.mineBadge._news = news
			item.mineBadge._item = item
			item.mineBadge._isMine = not not isMine
			item.mineBadge._proudAny = not not proudAny
			local badgeAtlas = proudAny and const.BADGE_PROUD_ATLAS or const.BADGE_MINE_ATLAS
			local badgeFallback = proudAny and const.BADGE_PROUD_TEX or const.BADGE_MINE_TEX
			if item.mineBadge.icon then
				HU.Util_SetAtlasOrTexture(item.mineBadge.icon, badgeAtlas, badgeFallback)
				if isFeatured then
					item.mineBadge.icon:SetVertexColor(
						const.FEATURED_BORDER_R,
						const.FEATURED_BORDER_G,
						const.FEATURED_BORDER_B,
						1
					)
				elseif proudOther and not (fn.Proud_IsChecked and fn.Proud_IsChecked(news)) then
					item.mineBadge.icon:SetVertexColor(0.25, 1, 0.35, 1)
				else
					item.mineBadge.icon:SetVertexColor(1, 1, 1, 1)
				end
			end
			if item.iconOverlay then
				if isFeatured then
					item.iconOverlay:SetVertexColor(
						const.FEATURED_BORDER_R,
						const.FEATURED_BORDER_G,
						const.FEATURED_BORDER_B,
						1
					)
				elseif proudAny then
					item.iconOverlay:SetVertexColor(const.PROUD_BORDER_R, const.PROUD_BORDER_G, const.PROUD_BORDER_B, 1)
				else
					item.iconOverlay:SetVertexColor(1, 1, 1, 1)
				end
			end
			if item.proudOverlay then
				item.proudOverlay:SetShown(proudAny or isFeatured)
				if isFeatured then
					item.proudOverlay:SetVertexColor(
						const.FEATURED_BORDER_R,
						const.FEATURED_BORDER_G,
						const.FEATURED_BORDER_B,
						0.5
					)
				elseif proudAny then
					if fn.Proud_IsChecked and fn.Proud_IsChecked(news) then
						item.proudOverlay:SetVertexColor(1, 1, 1, 0.5)
					else
						item.proudOverlay:SetVertexColor(0.25, 1, 0.35, 0.4)
					end
				end
			end
		end
	end

	local function List_Refresh()
		if not state.newsQueue then
			return
		end
		if fn.News_SeedIfEmpty then
			fn.News_SeedIfEmpty()
		end
		local y = 0
		local maxW = listFrame:GetWidth() > 0 and listFrame:GetWidth() or 360
		listContent:SetWidth(maxW)

		local displayIndex = 0
		local filtered = {}
		local gid = HU.Util_GetActiveGuildUID()
		if gid and gid ~= "" then
			for i = 1, #state.newsQueue do
				local news = state.newsQueue[i]
				if
					news
					and HU.Util_IsSameGuildUID(news.guildUID, gid)
					and fn.Filter_IsNewsAllowed
					and fn.Filter_IsNewsAllowed(news)
				then
					filtered[#filtered + 1] = news
				end
			end
		end
		table.sort(filtered, function(a, b)
			return (a.time or 0) > (b.time or 0)
		end)

		for i = 1, #filtered do
			local news = filtered[i]
			displayIndex = displayIndex + 1
			local item = listEntries[displayIndex]
			if not item then
				item = List_CreateEntry(listContent)
				listEntries[displayIndex] = item
			end
			item:ClearAllPoints()
			item:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -y)
			item:SetPoint("RIGHT", listContent, "RIGHT", -HERO_LIST_CFG.scrollRightPad, 0)
			item:SetWidth(maxW)
			item:Show()
			List_SetEntryData(item, news)
			item._action = nil
			y = y + HERO_LIST_CFG.itemHeight + HERO_LIST_CFG.itemSpacing
		end

		if displayIndex == 0 then
			displayIndex = 1
			local item = listEntries[displayIndex]
			if not item then
				item = List_CreateEntry(listContent)
				listEntries[displayIndex] = item
			end
			item:ClearAllPoints()
			item:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -y)
			item:SetPoint("RIGHT", listContent, "RIGHT", -HERO_LIST_CFG.scrollRightPad, 0)
			item:SetWidth(maxW)
			item:Show()
			item._action = nil
			if not state.heroNewsTarget then
				item.title:SetText("Bir kahraman sec")
				item.text:SetText("Soldaki listeden bir karakter sec.")
			elseif not (fn.Filter_AnyTypeEnabled and fn.Filter_AnyTypeEnabled()) then
				item.title:SetText("Aktif filtre yok")
				item.text:SetText("Etkinlestirmek icin tikla")
				item._action = function()
					Filter_SetAllTypes(true)
				end
			else
				item.title:SetText("Haber yok")
				item.text:SetText("Bu kahraman icin haber yok.")
			end
			item._news = nil
			if item.mineBadge then
				item.mineBadge:SetShown(false)
				item.mineBadge._news = nil
				item.mineBadge._item = item
				item.mineBadge._isMine = false
				item.mineBadge._proudAny = false
				if item.mineBadge.icon then
					item.mineBadge.icon:SetVertexColor(1, 1, 1, 1)
				end
			end
			if item.icon then
				HU.Util_SetPearlIcon(item.icon, 3717420, HERO_LIST_CFG.iconSize)
			end
			if item.iconOverlay then
				item.iconOverlay:SetVertexColor(1, 1, 1, 1)
			end
			if item.proudOverlay then
				item.proudOverlay:Hide()
			end
			y = y + HERO_LIST_CFG.itemHeight + HERO_LIST_CFG.itemSpacing
		end

		for i = displayIndex + 1, #listEntries do
			listEntries[i]:Hide()
		end
		listContent:SetHeight(math.max(y, 1))
	end

	fn.List_UpdateTitle = List_UpdateTitle
	fn.List_Refresh = List_Refresh
end

return M
