local ADDON, ns = ...

ns.Data = ns.Data or {}
local Data = ns.Data
local NewsFeed = {}
Data.NewsFeed = NewsFeed

local function Now()
	return time and time() or 0
end

local seq = 0
local function BuildID(prefix, ts)
	seq = seq + 1
	return ("news:%s:%d:%d"):format(tostring(prefix or "custom"), ts, seq)
end

local function GetActiveGuildUID()
	if ns.Utils and ns.Utils.GetActiveGuildUID then
		return ns.Utils.GetActiveGuildUID()
	end
	if ns.DB and ns.DB.GetGuildUID then
		return ns.DB:GetGuildUID()
	end
	return nil
end

local pending = {}
local pendingRemovals = {}
local deliveredByGuild = {}

local function GetDeliveredMap(guildUID)
	if not guildUID or guildUID == "" then
		return nil
	end
	local t = deliveredByGuild[guildUID]
	if not t then
		t = {}
		deliveredByGuild[guildUID] = t
	end
	return t
end
local function FlushPending()
	local hasSocial = ns.Sections and ns.Sections.Social_AddNews
	local hasHeros = ns.Sections and ns.Sections.Heros_AddNews
	if not (hasSocial or hasHeros) then
		return
	end
	if ns.Sections and ns.Sections.Social_BeginNewsBatch then
		ns.Sections.Social_BeginNewsBatch()
	end
	if ns.Sections and ns.Sections.Heros_BeginNewsBatch then
		ns.Sections.Heros_BeginNewsBatch()
	end
	if #pending > 0 then
		for i = 1, #pending do
			local n = pending[i]
			if hasSocial then
				ns.Sections.Social_AddNews(
					n.id,
					n.text,
					n.typ,
					n.icon,
					n.ts,
					n.guildUID,
					n.replaceKey,
					n.title,
					n.removedAt,
					n.uid
				)
			end
			if hasHeros then
				ns.Sections.Heros_AddNews(
					n.id,
					n.text,
					n.typ,
					n.icon,
					n.ts,
					n.guildUID,
					n.replaceKey,
					n.title,
					n.removedAt,
					n.uid
				)
			end
		end
		wipe(pending)
	end
	if #pendingRemovals > 0 then
		for i = 1, #pendingRemovals do
			if ns.Sections and ns.Sections.Social_RemoveNews then
				ns.Sections.Social_RemoveNews(pendingRemovals[i])
			end
			if ns.Sections and ns.Sections.Heros_RemoveNews then
				ns.Sections.Heros_RemoveNews(pendingRemovals[i])
			end
		end
		wipe(pendingRemovals)
	end
	if ns.Sections and ns.Sections.Social_EndNewsBatch then
		ns.Sections.Social_EndNewsBatch()
	end
	if ns.Sections and ns.Sections.Heros_EndNewsBatch then
		ns.Sections.Heros_EndNewsBatch()
	end
end

function NewsFeed.Add(text, typ, icon, ts, id, prefix, guildUIDOverride, replaceKey, title, removedAt, uid)
	if not text or text == "" then
		return
	end
	local guildUID = guildUIDOverride or GetActiveGuildUID()
	if not guildUID or guildUID == "" then
		return
	end
	local t = tonumber(ts or 0) or 0
	if t <= 0 then
		t = Now()
	end
	local nid = id or BuildID(prefix, t)
	local deliveredMap = GetDeliveredMap(guildUID)
	if deliveredMap then
		local prev = tonumber(deliveredMap[nid] or 0) or 0
		if prev > 0 then
			if t <= prev then
				return
			end
			NewsFeed.RemoveById(nid)
		end
		deliveredMap[nid] = t
	end
	local delivered = false
	if ns.Sections and ns.Sections.Social_AddNews then
		ns.Sections.Social_AddNews(nid, text, typ, icon, t, guildUID, replaceKey, title, removedAt, uid)
		delivered = true
	end
	if ns.Sections and ns.Sections.Heros_AddNews then
		ns.Sections.Heros_AddNews(nid, text, typ, icon, t, guildUID, replaceKey, title, removedAt, uid)
		delivered = true
	end
	if delivered then
		FlushPending()
	else
		pending[#pending + 1] = {
			id = nid,
			text = text,
			typ = typ,
			icon = icon,
			ts = t,
			guildUID = guildUID,
			replaceKey = replaceKey,
			title = title,
			removedAt = removedAt,
			uid = uid,
		}
	end
end

function NewsFeed.RemoveById(id)
	if not id or id == "" then
		return
	end
	for _, map in pairs(deliveredByGuild) do
		map[id] = nil
	end
	if ns.Sections and ns.Sections.Featured_ClearByNewsId then
		ns.Sections.Featured_ClearByNewsId(id)
	end
	local delivered = false
	if ns.Sections and ns.Sections.Social_RemoveNews then
		ns.Sections.Social_RemoveNews(id)
		delivered = true
	end
	if ns.Sections and ns.Sections.Heros_RemoveNews then
		ns.Sections.Heros_RemoveNews(id)
		delivered = true
	end
	if delivered then
		FlushPending()
	else
		pendingRemovals[#pendingRemovals + 1] = id
	end
end

function NewsFeed.Flush()
	FlushPending()
end

return NewsFeed
