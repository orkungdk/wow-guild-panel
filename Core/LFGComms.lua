-- Guild LFG: announce category (Raid, Mythic+, etc.), list others, invite/whisper. Logout = leave list.
local ADDON, ns = ...
local Comms = ns.Comms
local EventBus = ns.EventBus

if not Comms or not Comms.QueueGuildLine then
	return
end

Comms._lfgList = Comms._lfgList or {}
Comms._lfgAnnounced = false

local function LocalFullName()
	local name = UnitName("player")
	local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName and GetRealmName() or ""
	if realm and realm ~= "" then
		return name .. "-" .. realm
	end
	return name or ""
end

-- Returns flat list of { name, category, note } so same player can appear multiple times.
function Comms.GetLFGList()
	local out = {}
	for name, cats in pairs(Comms._lfgList or {}) do
		if type(cats) == "table" then
			for category, note in pairs(cats) do
				if category and category ~= "" then
					out[#out + 1] = { name = name, category = category, note = note or "" }
				end
			end
		end
	end
	return out
end

function Comms.OnLFGMessage(message, channel, sender)
	if channel ~= "GUILD" or not sender or sender == "" then
		return
	end
	local p = {}
	for s in message:gmatch("([^;]+)") do
		p[#p + 1] = s
	end
	if p[1] ~= "LFG" then
		return
	end
	if p[2] == "LEAVE" then
		local category = p[3]
		if not category or category == "" then
			Comms._lfgList[sender] = nil
		else
			if Comms._lfgList[sender] then
				Comms._lfgList[sender][category] = nil
				if next(Comms._lfgList[sender]) == nil then
					Comms._lfgList[sender] = nil
				end
			end
		end
	elseif p[2] == "ANN" then
		local category = p[3] or ""
		local note = p[4] or ""
		if category ~= "" then
			Comms._lfgList[sender] = Comms._lfgList[sender] or {}
			Comms._lfgList[sender][category] = note
		end
	end
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_LFG_UPDATED", Comms._lfgList)
	end
end

function Comms.SendLFGAnn(category, note)
	if not category or category == "" then
		return
	end
	Comms._lfgAnnounced = true
	Comms._lfgList[LocalFullName()] = Comms._lfgList[LocalFullName()] or {}
	Comms._lfgList[LocalFullName()][category] = note or ""
	local noteSafe = (note and note:gsub(";", " ") or ""):sub(1, 100)
	local line = "LFG;ANN;" .. tostring(category) .. ";" .. noteSafe
	Comms.QueueGuildLine(line)
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_LFG_UPDATED", Comms._lfgList)
	end
end

-- category: optional. If given, leave only that category; if nil, leave all (e.g. logout).
function Comms.SendLFGLeave(category)
	local me = LocalFullName()
	if not Comms._lfgList[me] then
		return
	end
	if not category or category == "" then
		Comms._lfgAnnounced = false
		Comms._lfgList[me] = nil
		Comms.QueueGuildLine("LFG;LEAVE")
	else
		Comms._lfgList[me][category] = nil
		if next(Comms._lfgList[me]) == nil then
			Comms._lfgList[me] = nil
			Comms._lfgAnnounced = false
		end
		Comms.QueueGuildLine("LFG;LEAVE;" .. tostring(category))
	end
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_LFG_UPDATED", Comms._lfgList)
	end
end

if EventBus and EventBus.On then
	EventBus.On("PLAYER_LOGOUT", function()
		if Comms._lfgAnnounced then
			Comms.SendLFGLeave()
		end
	end)
end
