local ADDON, ns = ...

local M = ns.HerosSection

function M.BuildNewsFeatured(ctx)
	local ns = ctx.ns
	local HU = ctx.HU
	local DB = ctx.DB
	local Comms = ctx.Comms
	local EventBus = ctx.EventBus
	local const = ctx.const
	local state = ctx.state
	local ui = ctx.ui
	local fn = ctx.fn
	local Targets = ns.Targets

	local PROUD_BORDER_R, PROUD_BORDER_G, PROUD_BORDER_B = const.PROUD_BORDER_R, const.PROUD_BORDER_G, const.PROUD_BORDER_B
	local FEATURED_BORDER_R, FEATURED_BORDER_G, FEATURED_BORDER_B =
		const.FEATURED_BORDER_R, const.FEATURED_BORDER_G, const.FEATURED_BORDER_B
	local dragEscapeCatcher = nil

	local function Proud_GetRoot(guildUID)
		local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID()) or nil
		if not gid or gid == "" then
			return nil
		end
		WoWGuildeDB = WoWGuildeDB or {}
		WoWGuildeDB.guilds = WoWGuildeDB.guilds or {}
		local g = WoWGuildeDB.guilds[gid]
		if not g then
			g = { guildInfo = { guildUID = gid }, players = {} }
			WoWGuildeDB.guilds[gid] = g
		end
		if type(g.proudNews) ~= "table" then
			g.proudNews = {}
		end
		g.proudNews.proudByCharacter = g.proudNews.proudByCharacter or {}
		g.proudNews.proudByMe = g.proudNews.proudByMe or {}
		return g.proudNews
	end

	local function Proud_GetStore(guildUID)
		local root = Proud_GetRoot(guildUID)
		return root and root.proudByMe or nil
	end

	local function Proud_GetByStore(guildUID)
		local root = Proud_GetRoot(guildUID)
		return root and root.proudByCharacter or nil
	end

	local function Proud_GetGuildUID(news)
		if news and news.guildUID then
			return news.guildUID
		end
		if DB and DB.GetGuildUID then
			return DB:GetGuildUID()
		end
		return nil
	end

	local function Proud_IsChecked(news)
		if not news or not news.id then
			return false
		end
		local gid = Proud_GetGuildUID(news)
		local t = Proud_GetStore(gid)
		if not t then
			return false
		end
		return t[news.id] == true
	end

	local Proud_IsLocalActor

	local function Proud_HasAnyOther(news)
		if not news or not news.id then
			return false
		end
		local gid = Proud_GetGuildUID(news)
		local t = Proud_GetByStore(gid)
		if not t then
			return false
		end
		local by = t[news.id]
		if type(by) ~= "table" then
			return false
		end
		for k, v in pairs(by) do
			if v and not Proud_IsLocalActor(k, v) then
				return true
			end
		end
		return false
	end

	local function Proud_HasAnyOrMe(news)
		if Proud_IsChecked(news) then
			return true
		end
		return Proud_HasAnyOther(news)
	end

	local function Proud_GetLocalUID()
		if DB and DB.GetMyUID then
			return DB:GetMyUID()
		end
		return nil
	end

	local function Proud_GetLocalFull()
		local n, r = UnitFullName and UnitFullName("player")
		if not n or n == "" then
			n = UnitName and UnitName("player") or ""
		end
		if r and r ~= "" then
			return n .. "-" .. r
		end
		return n ~= "" and n or nil
	end

	Proud_IsLocalActor = function(key, value)
		local uid = Proud_GetLocalUID()
		if uid and key == uid then
			return true
		end
		local full = Proud_GetLocalFull()
		if full and key == full then
			return true
		end
		local base = (ns.Utils and ns.Utils.BaseName and full) and ns.Utils.BaseName(full) or nil
		if base and key == base then
			return true
		end
		if type(value) == "table" and value.name and value.name ~= "" then
			if full and value.name == full then
				return true
			end
			if base and value.name == base then
				return true
			end
		end
		return false
	end

	local Featured_GetStore
	local Featured_Transfer

	local function Featured_MergeByKey(dst, src)
		if type(dst) ~= "table" or type(src) ~= "table" then
			return
		end
		for key, v in pairs(src) do
			if type(v) == "table" then
				local incoming = tonumber(v.updatedAt or 0) or 0
				local existing = tonumber(dst[key] and dst[key].updatedAt or 0) or 0
				if existing == 0 or incoming == 0 or incoming >= existing then
					local out = {}
					for fk, fv in pairs(v) do
						out[fk] = fv
					end
					dst[key] = out
				end
			end
		end
	end

	local function Featured_GetRoot(guildUID)
		local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID()) or nil
		if not gid or gid == "" then
			return nil
		end
		WoWGuildeDB = WoWGuildeDB or {}
		WoWGuildeDB.guilds = WoWGuildeDB.guilds or {}
		local g = WoWGuildeDB.guilds[gid]
		if not g then
			g = { guildInfo = { guildUID = gid }, players = {} }
			WoWGuildeDB.guilds[gid] = g
		end
		local proudRoot = Proud_GetRoot(gid)
		if not proudRoot then
			return nil
		end
		proudRoot.legendaryProud = proudRoot.legendaryProud or {}
		proudRoot.legendaryProud.byKey = proudRoot.legendaryProud.byKey or {}
		if type(g.featuredNews) == "table" and type(g.featuredNews.byKey) == "table" then
			Featured_MergeByKey(proudRoot.legendaryProud.byKey, g.featuredNews.byKey)
			g.featuredNews = nil
		end
		return proudRoot.legendaryProud
	end

	Featured_GetStore = function(guildUID)
		local root = Featured_GetRoot(guildUID)
		return root and root.byKey or nil
	end

	Featured_Transfer = function(oldId, newNews, guildUID)
		if not oldId or not newNews or not newNews.id then
			return
		end
		local t = Featured_GetStore(guildUID)
		if not t then
			return
		end
		local updated = false
		for key, item in pairs(t) do
			if item and item.id == oldId then
				t[key] = {
					id = newNews.id,
					type = newNews.type,
					title = newNews.title,
					icon = newNews.icon,
					time = newNews.time,
					guildUID = newNews.guildUID or guildUID,
					replaceKey = newNews.replaceKey or "",
					note = item.note,
					updatedAt = time(),
				}
				updated = true
				if ns.Sections and ns.Sections.Social_OnFeaturedUpdate then
					ns.Sections.Social_OnFeaturedUpdate(guildUID, key, t[key])
				end
				if state.heroNewsTarget and state.heroNewsTarget.key == key and fn.Featured_UpdateDisplay then
					fn.Featured_UpdateDisplay()
				end
			end
		end
		if updated and fn.List_Refresh then
			fn.List_Refresh()
		end
	end

	local function Featured_KeyFromData(data)
		if not data then
			return nil
		end
		local uid = fn.ResolveHeroUID and fn.ResolveHeroUID(data) or nil
		if uid and uid ~= "" then
			return uid
		end
		local full = HU.FullNameForData(data)
		if full and full ~= "" then
			return "full:" .. full
		end
		return nil
	end

	local function Featured_GetForKey(guildUID, key)
		local t = Featured_GetStore(guildUID)
		if not t or not key then
			return nil
		end
		return t[key]
	end

	local function Featured_SetForKey(guildUID, key, news)
		local t = Featured_GetStore(guildUID)
		if not t or not key or not news then
			return
		end
		t[key] = news
	end

	local function Featured_ClearForKey(guildUID, key)
		local t = Featured_GetStore(guildUID)
		if not t or not key then
			return
		end
		t[key] = nil
	end

	local function Featured_ClearByNewsId(guildUID, newsId)
		if not guildUID or not newsId then
			return
		end
		local t = Featured_GetStore(guildUID)
		if not t then
			return
		end
		for key, v in pairs(t) do
			if v and v.id == newsId then
				t[key] = nil
				if ns.Sections and ns.Sections.Social_OnFeaturedUpdate then
					ns.Sections.Social_OnFeaturedUpdate(guildUID, key, { clear = true })
				end
				if state.heroNewsTarget and state.heroNewsTarget.key == key and fn.Featured_UpdateDisplay then
					fn.Featured_UpdateDisplay()
				end
			end
		end
		if fn.List_Refresh then
			fn.List_Refresh()
		end
	end

	function ns.Sections.Featured_ClearByNewsId(newsId)
		if not newsId or newsId == "" then
			return
		end
		local gid = HU.Util_GetActiveGuildUID()
		if not gid or gid == "" then
			return
		end
		Featured_ClearByNewsId(gid, newsId)
	end

	local function Featured_IsNewsFeatured(guildUID, newsId)
		if not guildUID or not newsId then
			return false
		end
		local t = Featured_GetStore(guildUID)
		if not t then
			return false
		end
		for _, v in pairs(t) do
			if v and v.id == newsId then
				return true
			end
		end
		return false
	end

	local function Featured_UpdateDisplay()
		if not ui.profile or not ui.profile.legendaryNewsSlot then
			return
		end
		local gid = HU.Util_GetActiveGuildUID()
		local key = state.heroNewsTarget and state.heroNewsTarget.key or nil
		local item = (gid and key) and Featured_GetForKey(gid, key) or nil

		ui.profile.legendaryNewsSlot._featured = item
		if item and item.icon then
			if ui.profile.legendaryNewsSlot.bg then
				ui.profile.legendaryNewsSlot.bg:SetDesaturated(false)
				ui.profile.legendaryNewsSlot.bg:SetVertexColor(1, 1, 1, 1)
			end
			HU.Util_SetPearlIcon(ui.profile.legendaryNewsSlot.icon, item.icon)
			ui.profile.legendaryNewsSlot.icon:Show()
			if ui.profile.legendaryNewsSlot.iconBorder then
				ui.profile.legendaryNewsSlot.iconBorder:Show()
			end
		else
			if ui.profile.legendaryNewsSlot.bg then
				ui.profile.legendaryNewsSlot.bg:SetDesaturated(true)
				ui.profile.legendaryNewsSlot.bg:SetVertexColor(0.5, 0.5, 0.5, 0.9)
			end
			ui.profile.legendaryNewsSlot.icon:Hide()
			if ui.profile.legendaryNewsSlot.iconBorder then
				ui.profile.legendaryNewsSlot.iconBorder:Hide()
			end
		end
		if ns.UI and ns.UI.UpdateCommunityMirrorOffsets then
			ns.UI.UpdateCommunityMirrorOffsets()
		end
	end

	local function Featured_SetFromNews(data, news)
		if not data or not news then
			return
		end
		local gid = HU.Util_GetActiveGuildUID()
		if not gid or gid == "" then
			return
		end
		local key = Featured_KeyFromData(data)
		if not key then
			return
		end
		local item = {
			id = news.id,
			type = news.type,
			title = news.title,
			icon = news.icon,
			time = news.time,
			guildUID = news.guildUID or gid,
			replaceKey = news.replaceKey or "",
			note = news.note,
			updatedAt = time(),
		}
		Featured_SetForKey(gid, key, item)
		if DB and DB.UpsertLegendaryProud then
			DB:UpsertLegendaryProud(gid, key, item, false)
		end
		if EventBus and EventBus.Emit then
			EventBus.Emit("WG_LEGENDARY_PROUD_CHANGED", gid, key, item, false)
		end
		Featured_UpdateDisplay()
		if fn.List_Refresh then
			fn.List_Refresh()
		end
		if ns.Sections and ns.Sections.Social_OnFeaturedUpdate then
			ns.Sections.Social_OnFeaturedUpdate(gid, key, item)
		end
		if Comms and Comms.SendFeaturedNews then
			Comms:SendFeaturedNews(gid, key, item, false)
		end
		if PlaySound then
			PlaySoundFile(567551, "SFX")
		end
	end

	local function Featured_ClearForData(data)
		if not data then
			return
		end
		local gid = HU.Util_GetActiveGuildUID()
		if not gid or gid == "" then
			return
		end
		local key = Featured_KeyFromData(data)
		if not key then
			return
		end
		Featured_ClearForKey(gid, key)
		if DB and DB.UpsertLegendaryProud then
			DB:UpsertLegendaryProud(gid, key, nil, true)
		end
		if EventBus and EventBus.Emit then
			EventBus.Emit("WG_LEGENDARY_PROUD_CHANGED", gid, key, nil, true)
		end
		Featured_UpdateDisplay()
		if fn.List_Refresh then
			fn.List_Refresh()
		end
		if ns.Sections and ns.Sections.Social_OnFeaturedUpdate then
			ns.Sections.Social_OnFeaturedUpdate(gid, key, { clear = true })
		end
		if Comms and Comms.SendFeaturedNews then
			Comms:SendFeaturedNews(gid, key, nil, true)
		end
	end

	local function Featured_SetNoteForKey(guildUID, key, note)
		if not guildUID or not key then
			return
		end
		local item = Featured_GetForKey(guildUID, key)
		if not item then
			return
		end
		local clean = tostring(note or "")
		if clean == "" then
			clean = nil
		end
		item.note = clean
		item.updatedAt = time()
		Featured_SetForKey(guildUID, key, item)
		if state.heroNewsTarget and state.heroNewsTarget.key == key then
			Featured_UpdateDisplay()
		end
		if fn.List_Refresh then
			fn.List_Refresh()
		end
		if ns.Sections and ns.Sections.Social_OnFeaturedUpdate then
			ns.Sections.Social_OnFeaturedUpdate(guildUID, key, item)
		end
		if Comms and Comms.SendFeaturedNews then
			Comms:SendFeaturedNews(guildUID, key, item, false)
		end
	end

	local Featured_EndDrag

	local function Featured_StartDrag(news, mode)
		state.featuredDragNews = news
		state.featuredDragMode = mode or "news"
		if PlaySound then
			PlaySoundFile(567542, "SFX")
		end
		if ui.profile and ui.profile.legendaryNewsSlot and ui.profile.legendaryNewsSlot.glow then
			ui.profile.legendaryNewsSlot.glow:Show()
		end
		if ui.dragIcon and news and news.icon then
			HU.Util_SetPearlIcon(ui.dragIcon.icon, news.icon, ui.dragIcon.size)
			ui.dragIcon.OnUpdate(ui.dragIcon)
			ui.dragIcon:Show()
			ui.dragIcon:SetScript("OnUpdate", ui.dragIcon.OnUpdate)
		end
		if not dragEscapeCatcher then
			dragEscapeCatcher = CreateFrame("Frame", nil, UIParent)
			dragEscapeCatcher:SetAllPoints(UIParent)
			dragEscapeCatcher:EnableKeyboard(true)
			if dragEscapeCatcher.SetPropagateKeyboardInput then
				dragEscapeCatcher:SetPropagateKeyboardInput(true)
			end
			dragEscapeCatcher:SetScript("OnKeyDown", function(_, key)
				if key == "ESCAPE" and state.featuredDragNews then
					Featured_EndDrag()
				end
			end)
		end
		dragEscapeCatcher:Show()
	end

	Featured_EndDrag = function()
		state.featuredDragNews = nil
		state.featuredDragMode = nil
		if ui.profile and ui.profile.legendaryNewsSlot and ui.profile.legendaryNewsSlot.glow then
			ui.profile.legendaryNewsSlot.glow:Hide()
		end
		if ui.dragIcon then
			ui.dragIcon:Hide()
			ui.dragIcon:SetScript("OnUpdate", nil)
		end
		if dragEscapeCatcher then
			dragEscapeCatcher:Hide()
		end
	end

	local featuredNoteTarget = nil
	local featuredNoteFrame = nil

	local function Featured_EnsureNoteFrame()
		if featuredNoteFrame then
			return featuredNoteFrame
		end

		local parent = (ui.listFrame and ui.listFrame:GetParent()) or UIParent
		local frame = CreateFrame("Frame", "WoWGuilde_FeaturedNote", parent)
		frame:Hide()

		if ui.listFrame then
			frame:SetPoint("TOPLEFT", ui.listFrame, "TOPLEFT", 0, 0)
			frame:SetPoint("BOTTOMRIGHT", ui.listFrame, "BOTTOMRIGHT", 0, 0)
			frame:SetFrameStrata(ui.listFrame:GetFrameStrata())
			frame:SetFrameLevel((ui.listFrame:GetFrameLevel() or 0) + 10)
		else
			frame:SetSize(420, 240)
			frame:SetPoint("CENTER")
		end

		frame.bg = frame:CreateTexture(nil, "BACKGROUND")
		frame.bg:SetAllPoints(frame)
		frame.bg:SetAtlas("glues-gameMode-BG")
		frame.bg:SetAlpha(0.8)

		frame.scroll = CreateFrame("ScrollFrame", nil, frame, "QuestScrollFrameTemplate")
		frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
		frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 36)

		frame.editBox = CreateFrame("EditBox", nil, frame.scroll)
		frame.editBox:SetMultiLine(true)
		frame.editBox:SetFontObject("ChatFontNormal")
		frame.editBox:SetWidth(const.HERO_LIST_CFG.columnWidth - const.HERO_LIST_CFG.scrollRightPad - 10)
		frame.editBox:SetAutoFocus(true)
		frame.editBox:SetTextInsets(8, 8, 8, 8)
		frame.editBox:SetScript("OnEscapePressed", function()
			frame:Hide()
			if ui.listFrame then
				ui.listFrame:Show()
			end
		end)
		frame.editBox:SetScript("OnTextChanged", function(self)
			self:GetParent():UpdateScrollChildRect()
		end)
		frame.scroll:SetScrollChild(frame.editBox)

		frame.ok = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		frame.ok:SetSize(90, 22)
		frame.ok:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
		frame.ok:SetText("Onayla")
		frame.ok:SetScript("OnClick", function()
			if not featuredNoteTarget then
				frame:Hide()
				if ui.listFrame then
					ui.listFrame:Show()
				end
				return
			end
			local text = frame.editBox and frame.editBox:GetText() or ""
			Featured_SetNoteForKey(featuredNoteTarget.guildUID, featuredNoteTarget.key, text)
			frame:Hide()
			if ui.listFrame then
				ui.listFrame:Show()
			end
		end)

		frame.cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		frame.cancel:SetSize(90, 22)
		frame.cancel:SetPoint("BOTTOMRIGHT", frame.ok, "BOTTOMLEFT", -8, 0)
		frame.cancel:SetText("Iptal")
		frame.cancel:SetScript("OnClick", function()
			frame:Hide()
			if ui.listFrame then
				ui.listFrame:Show()
			end
		end)

		table.insert(UISpecialFrames, frame:GetName())
		featuredNoteFrame = frame
		return frame
	end

	local function Featured_OpenNoteEditor()
		if not ui.profile or not ui.profile.legendaryNewsSlot or not ui.profile.legendaryNewsSlot._featured then
			return
		end
		if not state.heroNewsTarget or not state.heroNewsTarget.key then
			return
		end
		local gid = HU.Util_GetActiveGuildUID()
		if not gid or gid == "" then
			return
		end
		featuredNoteTarget = { guildUID = gid, key = state.heroNewsTarget.key }
		local frame = Featured_EnsureNoteFrame()
		local current = ui.profile.legendaryNewsSlot._featured.note or ""
		frame.editBox:SetText(current)
		frame.editBox:HighlightText()
		frame:Show()
		if ui.listFrame then
			ui.listFrame:Hide()
		end
	end

	local function Featured_OpenMenu(anchor)
		if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
			return
		end
		if
			not (
				state.heroNewsTarget
				and state.heroNewsTarget.isSelf
				and ui.profile.legendaryNewsSlot
				and ui.profile.legendaryNewsSlot._featured
			)
		then
			return
		end
		local function Generator(_, root)
			root:CreateButton("Écrire sur cette actualité légendaire", function()
				Featured_OpenNoteEditor()
			end)
		end
		MenuUtil.CreateContextMenu(anchor, Generator)
	end

	ui.profile.legendaryNewsSlot:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			Featured_OpenMenu(self)
			return
		end
		if button ~= "LeftButton" then
			return
		end
		if not state.featuredDragNews then
			return
		end
		if state.heroNewsTarget and state.heroNewsTarget.isSelf and state.heroNewsTarget.data then
			if state.featuredDragMode == "clear" then
				Featured_ClearForData(state.heroNewsTarget.data)
				Featured_EndDrag()
				return
			end
			Featured_SetFromNews(state.heroNewsTarget.data, state.featuredDragNews)
		end
		Featured_EndDrag()
	end)
	ui.profile.legendaryNewsSlot:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then
			return
		end
		if not (state.heroNewsTarget and state.heroNewsTarget.isSelf and state.heroNewsTarget.data) then
			return
		end
		if self._featured then
			Featured_StartDrag(self._featured, "clear")
		end
	end)
	ui.profile.legendaryNewsSlot:SetScript("OnReceiveDrag", function()
		if not state.featuredDragNews then
			return
		end
		if state.heroNewsTarget and state.heroNewsTarget.isSelf and state.heroNewsTarget.data then
			Featured_SetFromNews(state.heroNewsTarget.data, state.featuredDragNews)
		end
		Featured_EndDrag()
	end)
	ui.profile.legendaryNewsSlot:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		local offsetX = (self._featured and 40) or 10
		GameTooltip:SetPoint("LEFT", self, "RIGHT", offsetX, 0)
		GameTooltip:ClearLines()
		if self._featured then
			local titleText = self._featured.title or (fn.News_GetTypeLabel and fn.News_GetTypeLabel(self._featured.type))
			GameTooltip:AddLine(titleText, 1, 1, 1, true)
			local base = fn.News_FindById and fn.News_FindById(self._featured.id) or nil
			if base and base.text and base.text ~= "" then
				local body = base.text
				if ns and ns.Utils and ns.Utils.ReplaceNewsTags then
					body = ns.Utils.ReplaceNewsTags(body, base.time or self._featured.time)
				end
				GameTooltip:AddLine(body, 1, 1, 1, true)
			end
			if self._featured.note and self._featured.note ~= "" then
				GameTooltip:AddLine("|TInterface\\Common\\UI-TooltipDivider-Transparent:8:220:0:0|t", 1, 1, 1, false)
				GameTooltip:AddLine(self._featured.note, 0.894, 0.655, 0.125, true)
			end
			if self._featured.time then
				GameTooltip:AddLine(HU.Util_PrettyTimeAgo(self._featured.time), 0.6, 0.6, 0.6)
			end
		elseif state.heroNewsTarget and state.heroNewsTarget.isSelf then
			GameTooltip:AddLine("Placez, ici, une actualité que vous jugez légendaire", 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	ui.profile.legendaryNewsSlot:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	ui.frame:HookScript("OnMouseUp", function(_, button)
		if button ~= "LeftButton" then
			return
		end
		if not state.featuredDragNews then
			return
		end
		if state.heroNewsTarget and state.heroNewsTarget.isSelf then
			if state.featuredDragMode == "clear" then
				Featured_ClearForData(state.heroNewsTarget.data)
				Featured_EndDrag()
				return
			end
			if ui.profile and ui.profile.legendaryNewsSlot and ui.profile.legendaryNewsSlot:IsMouseOver() then
				Featured_SetFromNews(state.heroNewsTarget.data, state.featuredDragNews)
			end
		end
		Featured_EndDrag()
	end)

	local function Proud_SetBy(newsId, actorKey, value, actorName, guildUID)
		if not newsId or newsId == "" or not actorKey or actorKey == "" then
			return
		end
		local gid = guildUID or (DB and DB.GetGuildUID and DB:GetGuildUID()) or nil
		if not gid or gid == "" then
			return
		end
		local t = Proud_GetByStore(gid)
		if not t then
			return
		end
		if not t[newsId] then
			t[newsId] = {}
		end
		t[newsId][actorKey] = value
		if type(t[newsId][actorKey]) == "table" then
			t[newsId][actorKey].name = actorName or t[newsId][actorKey].name
		else
			t[newsId][actorKey] = { name = actorName, updatedAt = time(), value = value }
		end
	end

	local function Proud_SetChecked(news, value)
		if not news or not news.id then
			return
		end
		local gid = Proud_GetGuildUID(news)
		local t = Proud_GetStore(gid)
		if not t then
			return
		end
		if t[news.id] == value then
			return
		end
		t[news.id] = value
		if ns.Comms and ns.Comms.SendProud then
			ns.Comms:SendProud(news.id, value, news.guildUID)
		end
		if fn.List_Refresh then
			fn.List_Refresh()
		end
	end

	local function Proud_Transfer(oldId, newId, guildUID)
		if not oldId or not newId then
			return
		end
		local t = Proud_GetStore(guildUID)
		if t and t[oldId] ~= nil then
			if t[newId] == nil then
				t[newId] = t[oldId]
			else
				t[newId] = (t[newId] == true) or (t[oldId] == true)
			end
			t[oldId] = nil
		end
		local by = Proud_GetByStore(guildUID)
		if by and type(by[oldId]) == "table" then
			local dst = by[newId]
			if type(dst) ~= "table" then
				dst = {}
			end
			for k, v in pairs(by[oldId]) do
				if v then
					dst[k] = v
				end
			end
			by[newId] = dst
			by[oldId] = nil
		end
	end

	local function Proud_ApplyRemote(newsId, sender, value, senderUID, guildUID)
		if senderUID and senderUID ~= "" then
			Proud_SetBy(newsId, senderUID, value, sender, guildUID)
		else
			Proud_SetBy(newsId, sender, value, sender, guildUID)
		end
		if fn.List_Refresh then
			fn.List_Refresh()
		end
	end

	local function CanOpenNewsMenu(news, isMine)
		if isMine then
			return true
		end
		local targetFull, targetOnline, targetRec = nil, false, nil
		if fn.News_ResolveTarget then
			targetFull, targetOnline, targetRec = fn.News_ResolveTarget(news)
		elseif fn.News_ResolveTargetFull then
			targetFull = fn.News_ResolveTargetFull(news)
		end
		local isReachable = targetOnline or (targetRec and targetRec.isMobile)
		local canProfile = targetFull and ns.Sections and ns.Sections.Heros_SelectByFull
		if canProfile then
			return true
		end
		if ns.Roles and ns.Roles.CanModerateNews and ns.Roles.CanModerateNews() then
			return true
		end
		return (fn.CanReactToNews and fn.CanReactToNews(news, isMine) and isReachable) or false
	end

	local function Proud_OpenMenu(anchor, news, isMine)
		if not (news and news.id) then
			return
		end
		if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
			return
		end
		local function Generator(owner, root)
			local isMineLocal = isMine
			if isMineLocal == nil then
				isMineLocal = fn.Filter_IsMyNews and fn.Filter_IsMyNews(news) or false
			end
			local isFeatured = Featured_IsNewsFeatured(Proud_GetGuildUID(news), news.id)
			local canModerate = (ns.Roles and ns.Roles.CanModerateNews and ns.Roles.CanModerateNews())
			local canProud = isMineLocal and root.CreateCheckbox
			local canDelete = canModerate or isMineLocal
			local hasReaction = false
			local reactionNewsOpts = {
				news = news,
				newsTypeLabel = fn.News_GetTypeLabel and fn.News_GetTypeLabel(news and news.type) or nil,
			}

			local targetFull, targetOnline, targetRec = nil, false, nil
			if fn.News_ResolveTarget then
				targetFull, targetOnline, targetRec = fn.News_ResolveTarget(news)
			elseif fn.News_ResolveTargetFull then
				targetFull = fn.News_ResolveTargetFull(news)
				if targetFull and HU and HU.ResolveLiveCharacterForFull then
					local _, online, rec = HU.ResolveLiveCharacterForFull(targetFull)
					targetOnline = online == true
					targetRec = rec
				elseif targetFull and Targets and Targets.ResolveForFull then
					local _, online, rec = Targets.ResolveForFull(targetFull)
					targetOnline = online == true
					targetRec = rec
				end
			end
			if not targetOnline and targetRec and targetRec.isMobile then
				targetOnline = true
			end
			local canProfile = targetFull and ns.Sections and ns.Sections.Heros_SelectByFull

			if root.CreateButton then
				if canProfile then
					root:CreateButton("Voir le profil", function()
						if ns and ns.UI and ns.UI.Show then
							ns.UI.Show()
						end
						if ns and ns.UI and ns.UI.ShowSection then
							ns.UI.ShowSection("Nos héros")
						end
						ns.Sections.Heros_SelectByFull(targetFull)
					end)
				else
					root:CreateButton("Voir le profil", function() end, { disabled = true })
				end
				if root.CreateDivider then
					root:CreateDivider()
				end
			end

			if isFeatured then
				canProud = false
				if not canModerate then
					canDelete = false
				end
			end
			if canProud then
				root:CreateCheckbox("Je suis fier de cette actualité", function()
					return Proud_IsChecked(news)
				end, function()
					Proud_SetChecked(news, not Proud_IsChecked(news))
				end)
			end
			if canDelete then
				if canProud and root.CreateDivider then
					root:CreateDivider()
				end
				root:CreateButton("Supprimer cette actualité", function()
					if ns.Data and ns.Data.JournalistAPI and ns.Data.JournalistAPI.RemoveNewsById then
						ns.Data.JournalistAPI.RemoveNewsById(news.guildUID, news.id)
					end
					if ns.Comms and ns.Comms.SendNewsDelete then
						ns.Comms:SendNewsDelete(news.id, news.guildUID)
					end
				end)
			end

			if root.CreateButton and fn.CanReactToNews and fn.CanReactToNews(news, isMineLocal) then
				if isMineLocal and HU.IsDevMode() then
					if root.CreateDivider then
						root:CreateDivider()
					end
					local me = UnitName and UnitName("player")
					if not me or me == "" then
						me = UnitFullName and UnitFullName("player")
					end
					reactionNewsOpts.test = true
					hasReaction = HU.AddReactionsSubmenu(root, me or "?", reactionNewsOpts)
				elseif not isMineLocal then
					if targetFull and targetOnline then
						if root.CreateDivider then
							root:CreateDivider()
						end
						reactionNewsOpts.allowNoPrefs = true
						hasReaction = HU.AddReactionsSubmenu(root, targetFull, reactionNewsOpts) == true
					end
				end
			end
		end
		MenuUtil.CreateContextMenu(anchor, Generator)
	end

	fn.Proud_GetRoot = Proud_GetRoot
	fn.Proud_GetStore = Proud_GetStore
	fn.Proud_GetByStore = Proud_GetByStore
	fn.Proud_GetGuildUID = Proud_GetGuildUID
	fn.Proud_IsChecked = Proud_IsChecked
	fn.Proud_HasAnyOther = Proud_HasAnyOther
	fn.Proud_HasAnyOrMe = Proud_HasAnyOrMe
	fn.Proud_GetLocalUID = Proud_GetLocalUID
	fn.Proud_GetLocalFull = Proud_GetLocalFull
	fn.Proud_IsLocalActor = Proud_IsLocalActor
	fn.Proud_SetBy = Proud_SetBy
	fn.Proud_SetChecked = Proud_SetChecked
	fn.Proud_Transfer = Proud_Transfer
	fn.Proud_ApplyRemote = Proud_ApplyRemote

	fn.Featured_GetStore = Featured_GetStore
	fn.Featured_Transfer = Featured_Transfer
	fn.Featured_KeyFromData = Featured_KeyFromData
	fn.Featured_GetForKey = Featured_GetForKey
	fn.Featured_SetForKey = Featured_SetForKey
	fn.Featured_ClearForKey = Featured_ClearForKey
	fn.Featured_ClearByNewsId = Featured_ClearByNewsId
	fn.Featured_IsNewsFeatured = Featured_IsNewsFeatured
	fn.Featured_UpdateDisplay = Featured_UpdateDisplay
	fn.Featured_SetFromNews = Featured_SetFromNews
	fn.Featured_ClearForData = Featured_ClearForData
	fn.Featured_SetNoteForKey = Featured_SetNoteForKey
	fn.Featured_StartDrag = Featured_StartDrag
	fn.Featured_EndDrag = Featured_EndDrag
	fn.Featured_OpenNoteEditor = Featured_OpenNoteEditor

	fn.CanOpenNewsMenu = CanOpenNewsMenu
	fn.Proud_OpenMenu = Proud_OpenMenu
end

return M
