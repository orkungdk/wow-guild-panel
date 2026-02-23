local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.NpcPersistence = QM.NpcPersistence or {}
local NpcPersistence = QM.NpcPersistence

local NEED_KEYS = {
	"social",
	"fatigue",
	"faim",
	"distraction",
}

local function GetEpochNow()
	local serverNow = (GetServerTime and GetServerTime()) or nil
	if serverNow then
		return math.max(0, tonumber(serverNow) or 0)
	end
	return math.max(0, tonumber(time and time() or 0) or 0)
end

local function Clamp(v, minV, maxV)
	if v < minV then
		return minV
	end
	if v > maxV then
		return maxV
	end
	return v
end

local function TrimName(rawName)
	if type(rawName) ~= "string" then
		return nil
	end
	local name = rawName:gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return nil
	end
	return name
end

local function EnsureRoot()
	WoWGuildeDB = WoWGuildeDB or {}
	WoWGuildeDB.QuartierMiniature = WoWGuildeDB.QuartierMiniature or {}
	local root = WoWGuildeDB.QuartierMiniature
	root.version = tonumber(root.version) or 1
	root.npcState = root.npcState or {}
	root.npcState.version = tonumber(root.npcState.version) or 1
	root.npcState.maps = root.npcState.maps or {}
	return root.npcState
end

local function CopyNeedTable(src)
	local out = {}
	if type(src) ~= "table" then
		return out
	end
	for i = 1, #NEED_KEYS do
		local key = NEED_KEYS[i]
		local v = tonumber(src[key])
		if v then
			out[key] = Clamp(v, 0, 100)
		end
	end
	return out
end

local function CopyNpcEntry(src)
	if type(src) ~= "table" then
		return nil
	end
	local out = {
		id = tostring(src.id or ""),
		name = TrimName(src.name),
		needs = CopyNeedTable(src.needs),
	}
	local u = tonumber(src.u)
	local v = tonumber(src.v)
	if u and v then
		out.u = Clamp(u, 0, 1)
		out.v = Clamp(v, 0, 1)
	end
	local regieCenterU = tonumber(src.regieCenterU)
	local regieCenterV = tonumber(src.regieCenterV)
	if regieCenterU and regieCenterV then
		out.regieCenterU = Clamp(regieCenterU, 0, 1)
		out.regieCenterV = Clamp(regieCenterV, 0, 1)
	end
	local regieRadius = tonumber(src.regieRadius)
	if regieRadius then
		out.regieRadius = Clamp(regieRadius, 0.015, 0.090)
	end
	local portraitAtlas = tostring(src.portraitAtlas or "")
	if portraitAtlas ~= "" then
		out.portraitAtlas = portraitAtlas
	end
	if src.portraitFlipX ~= nil then
		out.portraitFlipX = src.portraitFlipX == true
	end
	local function CopyIntentEntry(raw)
		if type(raw) ~= "table" then
			return nil
		end
		local kind = tostring(raw.kind or "")
		if kind ~= "lieu_pause" and kind ~= "talk" and kind ~= "join_talk" then
			return nil
		end
		local row = {
			kind = kind,
			source = tostring(raw.source or "player"),
			remainingSec = Clamp(tonumber(raw.remainingSec) or 0, 0, 7200),
		}
		if row.remainingSec <= 0 then
			return nil
		end
		if kind == "lieu_pause" then
			row.purpose = tostring(raw.purpose or "rest")
			row.lieuType = tostring(raw.lieuType or "")
			row.waitSeconds = Clamp(tonumber(raw.waitSeconds) or 0, 0, 600)
			row.freeMove = raw.freeMove == true
			local tu = tonumber(raw.targetU)
			local tv = tonumber(raw.targetV)
			if tu and tv then
				row.targetU = Clamp(tu, 0, 1)
				row.targetV = Clamp(tv, 0, 1)
			else
				return nil
			end
		else
			row.partnerId = tostring(raw.partnerId or "")
			if row.partnerId == "" then
				return nil
			end
			row.groupId = tostring(raw.groupId or "")
		end
		return row
	end
	local intent = type(src.intent) == "table" and src.intent or nil
	if intent then
		local restored = {
			active = CopyIntentEntry(intent.active),
			queue = {},
		}
		local queue = type(intent.queue) == "table" and intent.queue or {}
		for i = 1, #queue do
			local item = CopyIntentEntry(queue[i])
			if item then
				restored.queue[#restored.queue + 1] = item
			end
		end
		if restored.active or #restored.queue > 0 then
			out.intent = restored
		end
	end
	local activity = type(src.activity) == "table" and src.activity or nil
	if activity then
		local kind = tostring(activity.kind or "")
		local remainingSec = tonumber(activity.remainingSec)
		if (kind == "self_pause" or kind == "discussion") and remainingSec and remainingSec > 0 then
			out.activity = {
				kind = kind,
				remainingSec = Clamp(remainingSec, 0.1, 900),
				purpose = tostring(activity.purpose or ""),
				partnerId = tostring(activity.partnerId or ""),
				source = tostring(activity.source or ""),
				groupId = tostring(activity.groupId or ""),
				lockRemainingSec = Clamp(tonumber(activity.lockRemainingSec) or 0, 0, 900),
			}
		end
	end
	return out
end

function NpcPersistence.LoadNpcs(mapId, signature)
	local state = EnsureRoot()
	local key = tostring(mapId or "default")
	local entry = state.maps[key]
	if type(entry) ~= "table" then
		return {}, false, {
			mapId = key,
			signature = "",
			updatedAt = 0,
			updatedAtServer = 0,
		}
	end
	local saved = type(entry.npcs) == "table" and entry.npcs or {}
	local out = {}
	for i = 1, #saved do
		local copy = CopyNpcEntry(saved[i])
		if copy then
			out[#out + 1] = copy
		end
	end
	local sameSignature = tostring(entry.signature or "") == tostring(signature or "")
	local updatedAtServer = tonumber(entry.updatedAtServer)
	if not updatedAtServer or updatedAtServer <= 0 then
		updatedAtServer = tonumber(entry.updatedAt) or 0
	end
	return out, sameSignature, {
		mapId = key,
		signature = tostring(entry.signature or ""),
		updatedAt = tonumber(entry.updatedAt) or 0,
		updatedAtServer = updatedAtServer,
	}
end

function NpcPersistence.SaveNpcs(mapId, signature, npcs)
	if type(npcs) ~= "table" then
		return 0
	end
	local state = EnsureRoot()
	local key = tostring(mapId or "default")
	local maps = state.maps
	maps[key] = maps[key] or {}
	local entry = maps[key]
	local updatedAt = GetEpochNow()
	local nowUptime = (GetTime and GetTime() or 0)
	local function SerializeIntent(raw)
		if type(raw) ~= "table" then
			return nil
		end
		local kind = tostring(raw.kind or "")
		if kind ~= "lieu_pause" and kind ~= "talk" and kind ~= "join_talk" then
			return nil
		end
		local expiresAt = tonumber(raw.expiresAt)
		local remainingSec = nil
		if expiresAt and expiresAt > 0 then
			remainingSec = Clamp(expiresAt - nowUptime, 0, 7200)
			if remainingSec <= 0 then
				return nil
			end
		else
			remainingSec = 600
		end
		local out = {
			kind = kind,
			source = tostring(raw.source or "player"),
			remainingSec = remainingSec,
		}
		if kind == "lieu_pause" then
			local tu = tonumber(raw.targetU)
			local tv = tonumber(raw.targetV)
			if not (tu and tv) then
				return nil
			end
			out.targetU = Clamp(tu, 0, 1)
			out.targetV = Clamp(tv, 0, 1)
			out.purpose = tostring(raw.purpose or "rest")
			out.lieuType = tostring(raw.lieuType or "")
			out.waitSeconds = Clamp(tonumber(raw.waitSeconds) or 0, 0, 600)
			out.freeMove = raw.freeMove == true
		else
			out.partnerId = tostring(raw.partnerId or "")
			if out.partnerId == "" then
				return nil
			end
			out.groupId = tostring(raw.groupId or raw.talkGroupId or "")
		end
		return out
	end
	entry.signature = tostring(signature or "")
	entry.updatedAt = updatedAt
	entry.updatedAtServer = updatedAt
	entry.npcs = {}
	for i = 1, #npcs do
		local npc = npcs[i]
		if type(npc) == "table" then
			local id = tostring(npc.persistentId or npc.id or ("npc_" .. i))
			local name = TrimName(npc.displayName or npc.name)
			local needs = CopyNeedTable(npc.needs)
			local row = {
				id = id,
				name = name,
				needs = needs,
			}
			local u = tonumber(npc.u)
			local v = tonumber(npc.v)
			if u and v then
				row.u = Clamp(u, 0, 1)
				row.v = Clamp(v, 0, 1)
			end
			local centerU = tonumber(npc.regieCenterU)
			local centerV = tonumber(npc.regieCenterV)
			if centerU and centerV then
				row.regieCenterU = Clamp(centerU, 0, 1)
				row.regieCenterV = Clamp(centerV, 0, 1)
			end
			local radius = tonumber(npc.regieRadius)
			if radius then
				row.regieRadius = Clamp(radius, 0.015, 0.090)
			end
			local portraitAtlas = tostring(npc.portraitAtlas or "")
			if portraitAtlas ~= "" then
				row.portraitAtlas = portraitAtlas
			end
			if npc.portraitFlipX ~= nil then
				row.portraitFlipX = npc.portraitFlipX == true
			end
			local activeIntent = SerializeIntent(npc.manualOrder)
			local queueIntents = {}
			if type(npc.manualOrderQueue) == "table" then
				for q = 1, #npc.manualOrderQueue do
					local saved = SerializeIntent(npc.manualOrderQueue[q])
					if saved then
						queueIntents[#queueIntents + 1] = saved
					end
				end
			end
			if activeIntent or #queueIntents > 0 then
				row.intent = {
					active = activeIntent,
					queue = queueIntents,
				}
			end
			local stateName = tostring(npc.behaviorState or "")
			local behaviorTimer = tonumber(npc.behaviorTimer) or 0
			if stateName == "self_pause" and behaviorTimer > 0.10 then
				local lockUntil = tonumber(npc.essentialPauseLockUntil) or 0
				row.activity = {
					kind = "self_pause",
					remainingSec = Clamp(behaviorTimer, 0.1, 900),
					purpose = tostring(npc.essentialPausePurpose or npc.pausePurpose or ""),
					source = tostring(npc.essentialPauseSource or "auto"),
					lockRemainingSec = Clamp(lockUntil - nowUptime, 0, 900),
				}
			elseif stateName == "discussion" and behaviorTimer > 0.10 then
				local partnerId = tostring(
					npc.behaviorPartner and npc.behaviorPartner.persistentId
						or npc.discussionSocialBonusPartnerId
						or ""
				)
				if partnerId ~= "" then
					row.activity = {
						kind = "discussion",
						remainingSec = Clamp(behaviorTimer, 0.1, 180),
						partnerId = partnerId,
						source = tostring(npc.approachSource or npc.discussionSocialBonusSource or "player"),
						groupId = tostring(npc.conversationGroupId or ""),
					}
				end
			end
			entry.npcs[#entry.npcs + 1] = row
		end
	end
	return updatedAt
end
