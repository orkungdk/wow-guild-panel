local ADDON, ns = ...

local M = ns.HerosSection

function M.BuildNewsCore(ctx)
	local ns = ctx.ns
	local HU = ctx.HU
	local DB = ctx.DB
	local const = ctx.const
	local state = ctx.state
	local fn = ctx.fn

	local newsState = state.newsState
	local newsQueue = state.newsQueue
	local NEWS_TYPE_LABELS = const.NEWS_TYPE_LABELS

	local function News_GetTypeLabel(typ)
		typ = (typ and tostring(typ):lower()) or ""
		if not typ or typ == "" then
			return NEWS_TYPE_LABELS.generic
		end
		return NEWS_TYPE_LABELS[typ] or NEWS_TYPE_LABELS.generic
	end

	local function Filter_EnsureTypes()
		if not newsState.filter.types or next(newsState.filter.types) == nil then
			newsState.filter.types = {}
		end
		for key in pairs(NEWS_TYPE_LABELS) do
			if newsState.filter.types[key] == nil then
				newsState.filter.types[key] = true
			end
		end
	end

	local function Filter_AnyTypeEnabled()
		Filter_EnsureTypes()
		for _, enabled in pairs(newsState.filter.types) do
			if enabled then
				return true
			end
		end
		return false
	end

	local function Filter_Sync()
		if ns.Prefs and ns.Prefs.SetHeros then
			ns.Prefs.SetHeros("newsOnlyProud", newsState.filter.onlyProud)
			ns.Prefs.SetHeros("newsTypes", newsState.filter.types)
		end
	end

	local function Filter_IsMyNews(n)
		if not n then
			return false
		end
		local text = HU.NormalizeText((n.text or "") .. " " .. (n.title or ""))
		if text == "" then
			return false
		end
		local uid = DB and DB.GetMyUID and DB:GetMyUID() or nil
		if uid and n.replaceKey and tostring(n.replaceKey):find(uid, 1, true) then
			return true
		end
		local name = UnitName and UnitName("player") or nil
		local full = UnitFullName and UnitFullName("player") or nil
		if name and text:find(name, 1, true) then
			return true
		end
		if full and full ~= name and text:find(full, 1, true) then
			return true
		end
		if ns.Data and ns.Data.JournalistAPI and ns.Data.JournalistAPI.GetPlayerDisplayName then
			local display = ns.Data.JournalistAPI.GetPlayerDisplayName()
			if display and display ~= "" and text:find(display, 1, true) then
				return true
			end
		end
		return false
	end

	local function News_FindTargetFromAlias(text)
		local cache = ns.Utils and ns.Utils.PSEUDO_CACHE or nil
		if not cache or not text or text == "" then
			return nil
		end
		local hay = text:lower()
		local onlineFallback = nil
		local offlineFallback = nil
		for key, rec in pairs(cache) do
			local alias = type(rec) == "table" and rec.alias or rec
			if alias and alias ~= "" then
				local needle = tostring(alias):lower()
				if needle ~= "" and hay:find(needle, 1, true) then
					local candidate = key
					if HU and HU.ResolveLiveCharacterForFull then
						local live, online = HU.ResolveLiveCharacterForFull(key)
						if live and live ~= "" then
							candidate = live
						end
						if online == true then
							return candidate
						end
					end
					if candidate:find("-", 1, true) then
						if not onlineFallback then
							onlineFallback = candidate
						end
					elseif not offlineFallback then
						offlineFallback = candidate
					end
				end
			end
		end
		return onlineFallback or offlineFallback
	end

	local function News_ExtractUID(replaceKey)
		if not replaceKey or replaceKey == "" then
			return nil
		end
		return tostring(replaceKey):match("(uid:[%w]+)")
	end

	local function News_GetUID(news)
		if not news then
			return nil
		end
		local uid = news.uid
		if uid and uid ~= "" then
			uid = tostring(uid)
			if uid:sub(1, 4) == "uid:" then
				return uid
			end
			local extracted = uid:match("(uid:[%w]+)")
			if extracted and extracted ~= "" then
				return extracted
			end
		end
		return News_ExtractUID(news.replaceKey)
	end

	local function News_ResolveTargetFull(news)
		if not news then
			return nil
		end
		local uid = News_GetUID(news)
		local gid = fn.Proud_GetGuildUID and fn.Proud_GetGuildUID(news) or nil
		if uid and gid then
			if HU and HU.ResolveLiveCharacterForUID then
				local full = HU.ResolveLiveCharacterForUID(gid, uid)
				if full and full ~= "" then
					return full
				end
			elseif DB and DB.GetGuildPlayerMain then
				local full = DB:GetGuildPlayerMain(gid, uid)
				if full and full ~= "" then
					return full
				end
			end
		end
		local text = HU.NormalizeText((news.text or "") .. " " .. (news.title or ""))
		local full = News_FindTargetFromAlias(text)
		if full and full ~= "" and HU and HU.ResolveLiveCharacterForFull then
			local live = HU.ResolveLiveCharacterForFull(full)
			if live and live ~= "" then
				return live
			end
		end
		return full
	end

	local function News_ResolveTarget(news)
		if not news then
			return nil, false, nil
		end
		local uid = News_GetUID(news)
		local gid = fn.Proud_GetGuildUID and fn.Proud_GetGuildUID(news) or nil
		if uid and gid and HU and HU.ResolveLiveCharacterForUID then
			local full, online, rec = HU.ResolveLiveCharacterForUID(gid, uid)
			if full and full ~= "" then
				return full, online == true, rec
			end
		elseif uid and gid and DB and DB.GetGuildPlayerMain then
			local full = DB:GetGuildPlayerMain(gid, uid)
			if full and full ~= "" then
				return full, false, nil
			end
		end
		local full = News_ResolveTargetFull(news)
		if full and full ~= "" and HU and HU.ResolveLiveCharacterForFull then
			local live, online, rec = HU.ResolveLiveCharacterForFull(full)
			if live and live ~= "" then
				return live, online == true, rec
			end
		end
		return full, false, nil
	end

	local function ResolveAchievementDisplay(text, icon)
		if not text or text == "" then
			return text, icon
		end
		local id = text:match("|Hachievement:(%d+):") or text:match("|Hachievement:(%d+)")
		if not id then
			id = text:match("\n(%d+)%s*%.%s*$") or text:match("\n(%d+)%s*$")
		end
		if not id then
			return text, icon
		end
		if not GetAchievementInfo then
			return text, icon
		end
		local name, _, _, _, _, _, _, _, achIcon = GetAchievementInfo(tonumber(id))
		if name and name ~= "" then
			text = text:gsub("\n" .. id .. "%s*%.%s*$", "\n" .. name .. ".")
			text = text:gsub("\n" .. id .. "%s*$", "\n" .. name)
		end
		local iconId = tonumber(icon)
		local isDefaultIcon = (not icon or icon == 0 or icon == 134400 or icon == 131072 or icon == "Interface\\Icons\\INV_Misc_Orb_05" or iconId == 0 or iconId == 134400 or iconId == 131072)
		if isDefaultIcon and achIcon and achIcon ~= 0 then
			icon = achIcon
		end
		return text, icon
	end

	local function ResolveHeroUID(data)
		if not data then
			return nil
		end
		local gid = HU.Util_GetActiveGuildUID()
		if not gid or gid == "" then
			return nil
		end
		local full = data.mainFull or data.rosterFull
		if ns.Data and ns.Data.ResolvePlayerUID then
			local uid = ns.Data.ResolvePlayerUID(gid, full, data.playerGUID)
			return uid
		end
		return nil
	end

	local function BuildTargetNames(data)
		local names, seen = {}, {}
		local function add(name)
			name = tostring(name or "")
			if name == "" then
				return
			end
			local key = name:lower()
			if seen[key] then
				return
			end
			seen[key] = true
			names[#names + 1] = key
		end

		if not data then
			return names
		end

		add(data.pseudo)
		add(data.mainFull)
		add(data.rosterFull)
		if ns.Utils and ns.Utils.BaseName then
			add(ns.Utils.BaseName(data.mainFull))
			add(ns.Utils.BaseName(data.rosterFull))
		end
		if data.pseudo and data.realm and data.realm ~= "" and not data.pseudo:find("%-%") then
			add(data.pseudo .. "-" .. data.realm)
		end
		if ns.Utils and ns.Utils.PSEUDO_CACHE then
			local rec = nil
			if data.rosterFull then
				rec = ns.Utils.PSEUDO_CACHE[data.rosterFull]
			end
			if not rec and data.mainFull then
				rec = ns.Utils.PSEUDO_CACHE[data.mainFull]
			end
			if not rec and data.pseudo then
				rec = ns.Utils.PSEUDO_CACHE[data.pseudo]
			end
			local alias = rec and rec.alias
			if alias and alias ~= "" then
				add(alias)
			end
		end

		return names
	end

	local function Filter_IsTargetNews(n)
		if not n or not state.heroNewsTarget then
			return false
		end
		if state.heroNewsTarget.uid and n.replaceKey and tostring(n.replaceKey):find(state.heroNewsTarget.uid, 1, true) then
			return true
		end
		local text = HU.NormalizeText((n.text or "") .. " " .. (n.title or ""))
		if text == "" then
			return false
		end
		local lowerText = text:lower()
		for _, name in ipairs(state.heroNewsTarget.names or {}) do
			if lowerText:find(name, 1, true) then
				return true
			end
		end
		return false
	end

	local function Filter_IsNewsAllowed(n)
		if not n then
			return false
		end
		if not Filter_IsTargetNews(n) then
			return false
		end
		Filter_EnsureTypes()
		local typ = (n.type and tostring(n.type):lower()) or "generic"
		if not NEWS_TYPE_LABELS[typ] then
			typ = "generic"
		end
		if newsState.filter.onlyProud and not (fn.Proud_HasAnyOrMe and fn.Proud_HasAnyOrMe(n)) then
			if not (n and n.id and fn.Featured_IsNewsFeatured and fn.Featured_IsNewsFeatured(fn.Proud_GetGuildUID and fn.Proud_GetGuildUID(n) or nil, n.id)) then
				return false
			end
		end
		if newsState.filter.types then
			local anyEnabled = false
			for _, enabled in pairs(newsState.filter.types) do
				if enabled then
					anyEnabled = true
					break
				end
			end
			if not anyEnabled then
				return false
			end
			if newsState.filter.types[typ] == false then
				return false
			end
		end
		return true
	end

	local function CanReactToNews(news, isMine)
		if not news or not (ns and ns.Emotes and ns.Emotes.Catalog) then
			return false
		end
		if isMine then
			return HU.IsDevMode()
		end
		return true
	end

	local function News_SetTarget(data)
		if not data then
			state.heroNewsTarget = nil
			if fn.List_UpdateTitle then
				fn.List_UpdateTitle()
			end
			if fn.List_Refresh then
				fn.List_Refresh()
			end
			if fn.Featured_UpdateDisplay then
				fn.Featured_UpdateDisplay()
			end
			return
		end
		state.heroNewsTarget = {
			uid = ResolveHeroUID(data),
			key = fn.Featured_KeyFromData and fn.Featured_KeyFromData(data) or nil,
			names = BuildTargetNames(data),
			display = data.pseudo
				or (data.mainFull and ns.Utils and ns.Utils.BaseName and ns.Utils.BaseName(data.mainFull))
				or (data.rosterFull and ns.Utils and ns.Utils.BaseName and ns.Utils.BaseName(data.rosterFull))
				or "asdasdasd",
			isSelf = data.isSelf == true,
			data = data,
		}
		if fn.List_UpdateTitle then
			fn.List_UpdateTitle()
		end
		if fn.List_Refresh then
			fn.List_Refresh()
		end
		if fn.Featured_UpdateDisplay then
			fn.Featured_UpdateDisplay()
		end
		if ns.UI and ns.UI.UpdateCommunityMirrorOffsets then
			ns.UI.UpdateCommunityMirrorOffsets()
		end
	end

	local function News_Add(id, text, typ, icon, ts, guildUID, replaceKey, title, removedAt, uid)
		if not id or not text then
			return
		end
		local gid = guildUID or HU.Util_GetActiveGuildUID()
		if not gid or gid == "" then
			return
		end
		for i = 1, #newsQueue do
			local n = newsQueue[i]
			if n and n.id == id then
				n.text = text
				n.type = (typ and tostring(typ):lower()) or n.type
				n.title = title
				n.icon = icon or n.icon
				n.time = ts or n.time
				n.guildUID = gid
				n.replaceKey = replaceKey or n.replaceKey or ""
				n.removedAt = tonumber(removedAt or n.removedAt or 0) or 0
				n.uid = uid or n.uid
				return
			end
		end
		if typ and tostring(typ):lower() == "achievement" then
			text, icon = ResolveAchievementDisplay(text, icon)
		end
		local replacedIds = nil
		if replaceKey and replaceKey ~= "" then
			for i = #newsQueue, 1, -1 do
				local n = newsQueue[i]
				if n and n.replaceKey == replaceKey then
					if n.id then
						if not replacedIds then
							replacedIds = {}
						end
						replacedIds[#replacedIds + 1] = n.id
					end
					table.remove(newsQueue, i)
				end
			end
		end
		if #newsQueue >= const.NEWS_MAX then
			table.remove(newsQueue, 1)
		end
		local newItem = {
			id = id,
			text = text,
			type = (typ and tostring(typ):lower()) or "generic",
			title = title,
			icon = icon or "Interface\\Icons\\INV_Misc_Orb_05",
			time = ts or time(),
			guildUID = gid,
			replaceKey = replaceKey or "",
			removedAt = tonumber(removedAt or 0) or 0,
			uid = uid,
		}
		newsQueue[#newsQueue + 1] = newItem
		if replacedIds then
			for i = 1, #replacedIds do
				if fn.Proud_Transfer then
					fn.Proud_Transfer(replacedIds[i], id, gid)
				end
				if fn.Featured_Transfer then
					fn.Featured_Transfer(replacedIds[i], newItem, gid)
				end
			end
		end
	end

	local function News_FindById(id)
		if not id then
			return nil
		end
		for i = #newsQueue, 1, -1 do
			local n = newsQueue[i]
			if n and n.id == id then
				return n
			end
		end
		return nil
	end

	local function News_SeedIfEmpty()
		if #newsQueue > 0 then
			return
		end
		if not (ns.Data and ns.Data.Journalist and ns.Data.Journalist.GetRecentNews) then
			return
		end
		local gid = HU.Util_GetActiveGuildUID()
		if not gid or gid == "" then
			return
		end
		local items = ns.Data.Journalist.GetRecentNews(gid, const.NEWS_MAX) or {}
		for i = 1, #items do
			local n = items[i]
			if n and n.id and n.text then
				News_Add(n.id, n.text, n.typ, n.icon, n.ts, gid, n.replaceKey, n.title, n.removedAt, n.uid)
			end
		end
	end

	local function News_RemoveById(id)
		if not id or id == "" then
			return
		end
		for i = #newsQueue, 1, -1 do
			local n = newsQueue[i]
			if n and n.id == id then
				table.remove(newsQueue, i)
			end
		end
		if fn.List_Refresh then
			fn.List_Refresh()
		end
	end

	fn.News_GetTypeLabel = News_GetTypeLabel
	fn.Filter_EnsureTypes = Filter_EnsureTypes
	fn.Filter_AnyTypeEnabled = Filter_AnyTypeEnabled
	fn.Filter_Sync = Filter_Sync
	fn.Filter_IsMyNews = Filter_IsMyNews
	fn.News_FindTargetFromAlias = News_FindTargetFromAlias
	fn.News_ExtractUID = News_ExtractUID
	fn.News_ResolveTargetFull = News_ResolveTargetFull
	fn.News_ResolveTarget = News_ResolveTarget
	fn.ResolveAchievementDisplay = ResolveAchievementDisplay
	fn.ResolveHeroUID = ResolveHeroUID
	fn.BuildTargetNames = BuildTargetNames
	fn.Filter_IsTargetNews = Filter_IsTargetNews
	fn.Filter_IsNewsAllowed = Filter_IsNewsAllowed
	fn.CanReactToNews = CanReactToNews
	fn.News_SetTarget = News_SetTarget
	fn.News_Add = News_Add
	fn.News_FindById = News_FindById
	fn.News_SeedIfEmpty = News_SeedIfEmpty
	fn.News_RemoveById = News_RemoveById
end

return M
