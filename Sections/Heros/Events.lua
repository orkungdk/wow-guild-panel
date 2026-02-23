local ADDON, ns = ...

local M = ns.HerosSection

function M.BindEvents(ctx)
	local ns = ctx.ns
	local HU = ctx.HU
	local DB = ctx.DB
	local Comms = ctx.Comms
	local EventBus = ctx.EventBus
	local const = ctx.const
	local state = ctx.state
	local ui = ctx.ui
	local fn = ctx.fn
	local newsBatchDepth = 0
	local newsBatchDirty = false

	function ns.Sections.Heros_AddNews(id, text, typ, icon, ts, guildUID, replaceKey, title, removedAt, uid)
		if fn.News_Add then
			fn.News_Add(id, text, typ, icon, ts, guildUID, replaceKey, title, removedAt, uid)
		end
		if newsBatchDepth > 0 then
			newsBatchDirty = true
		elseif fn.List_Refresh then
			fn.List_Refresh()
		end
	end

	function ns.Sections.Heros_RemoveNews(id)
		local gid = HU.Util_GetActiveGuildUID()
		if gid and gid ~= "" and fn.Featured_ClearByNewsId then
			fn.Featured_ClearByNewsId(gid, id)
		end
		if fn.News_RemoveById then
			fn.News_RemoveById(id)
		end
	end

	function ns.Sections.Heros_OnProudUpdate(newsId, sender, value, senderUID, guildUID)
		if fn.Proud_ApplyRemote then
			fn.Proud_ApplyRemote(newsId, sender, value, senderUID, guildUID)
		end
		if newsBatchDepth > 0 then
			newsBatchDirty = true
		elseif fn.List_Refresh then
			fn.List_Refresh()
		end
	end

	function ns.Sections.Heros_BeginNewsBatch()
		newsBatchDepth = newsBatchDepth + 1
	end

	function ns.Sections.Heros_EndNewsBatch()
		if newsBatchDepth <= 0 then
			newsBatchDepth = 0
			return
		end
		newsBatchDepth = newsBatchDepth - 1
		if newsBatchDepth == 0 and newsBatchDirty then
			newsBatchDirty = false
			if fn.List_Refresh then
				fn.List_Refresh()
			end
		end
	end

	function ns.Sections.Heros_OnFeaturedUpdate(guildUID, heroKey, news)
		if not heroKey or not news then
			return
		end
		if news.clear then
			if fn.Featured_ClearForKey then
				fn.Featured_ClearForKey(guildUID, heroKey)
			end
		else
			if fn.Featured_SetForKey then
				fn.Featured_SetForKey(guildUID, heroKey, news)
			end
		end
		if state.heroNewsTarget and state.heroNewsTarget.key == heroKey and fn.Featured_UpdateDisplay then
			fn.Featured_UpdateDisplay()
		end
		if ns.UI and ns.UI.UpdateCommunityMirrorOffsets then
			ns.UI.UpdateCommunityMirrorOffsets()
		end
	end

	-- Contrôles de tri si dispo
	if ns.UI and ns.UI.MakeSortControls then
		ns.UI.MakeSortControls(ui.frame, state.sortState, fn.RefreshGuildList)
	end

	-- =========================================================
	-- Events
	-- =========================================================
	if EventBus and EventBus.On then
		local function RefreshIfInGuild()
			if IsInGuild() and fn.RefreshGuildList then
				fn.RefreshGuildList()
			end
		end
		EventBus.On("GUILD_ROSTER_UPDATE", RefreshIfInGuild)
		EventBus.On("PLAYER_GUILD_UPDATE", RefreshIfInGuild)
		EventBus.On("WG_MEMBER_PREFS_RECEIVED", function()
			if fn.RefreshGuildList then
				fn.RefreshGuildList()
			end
			if ui.profile and ui.profile.BioSide_Rebuild then
				ui.profile:BioSide_Rebuild()
			end
		end)
		if C_PlayerInfo then
			EventBus.On("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", RefreshIfInGuild)
			EventBus.On("CHALLENGE_MODE_MAPS_UPDATE", RefreshIfInGuild)
			EventBus.On("CHALLENGE_MODE_LEADERS_UPDATE", RefreshIfInGuild)
		end
	end

	-- =========================================================
	-- Affichage / masquage
	-- =========================================================
	ui.frame:SetScript("OnShow", function()
		ui.bg:Show()
		if fn.Bio_Layout then
			fn.Bio_Layout()
		end

		if IsInGuild() then
			HU.RequestGuildRoster()
			if fn.RefreshGuildList then
				fn.RefreshGuildList()
			end
			if fn.News_SeedIfEmpty then
				fn.News_SeedIfEmpty()
			end
			if fn.List_Refresh then
				fn.List_Refresh()
			end
			if ns.Data and ns.Data.NewsFeed and ns.Data.NewsFeed.Flush then
				ns.Data.NewsFeed.Flush()
			end
			if ns.Data and ns.Data.Journalist and ns.Data.Journalist.TickNow then
				ns.Data.Journalist.TickNow()
			end
			if ns.Data and ns.Data.Journalist and ns.Data.Journalist.StartLive then
				ns.Data.Journalist.StartLive()
			end

			local gid = HU.Util_GetActiveGuildUID()
			if gid and gid ~= "" then
				local t = fn.Featured_GetStore and fn.Featured_GetStore(gid) or nil
				if t then
					local items = ns.Data
							and ns.Data.Journalist
							and ns.Data.Journalist.GetRecentNews
							and ns.Data.Journalist.GetRecentNews(gid, const.NEWS_MAX)
						or {}
					if type(items) == "table" then
						local valid = {}
						for i = 1, #items do
							local n = items[i]
							if n and n.id then
								valid[n.id] = true
							end
						end
						for key, v in pairs(t) do
							if v and v.id and not valid[v.id] then
								t[key] = nil
							end
						end
						if fn.Featured_UpdateDisplay then
							fn.Featured_UpdateDisplay()
						end
					end
				end
			end

			if DB and DB.SaveSelfProfile then
				DB:SaveSelfProfile()
			end

			if Comms and Comms.BroadcastSnapshot then
				Comms:BroadcastSnapshot()
			end

			if ns.RequestGuildData then
				ns.RequestGuildData()
			end
		end
	end)

	ui.frame:SetScript("OnHide", function()
		if fn.Featured_EndDrag then
			fn.Featured_EndDrag()
		end
		ui.bg:Hide()
		if ns.Data and ns.Data.Journalist and ns.Data.Journalist.StopLive then
			ns.Data.Journalist.StopLive()
		end
	end)
end

return M
