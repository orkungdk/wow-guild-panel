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
		Comms._lfgList[sender] = nil
	elseif p[2] == "ANN" then
		local category = p[3] or ""
		local note = p[4] or ""
		Comms._lfgList[sender] = { category = category, note = note }
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
	Comms._lfgList[LocalFullName()] = { category = category, note = note or "" }
	local noteSafe = (note and note:gsub(";", " ") or ""):sub(1, 100)
	local line = "LFG;ANN;" .. tostring(category) .. ";" .. noteSafe
	Comms.QueueGuildLine(line)
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_LFG_UPDATED", Comms._lfgList)
	end
end

function Comms.SendLFGLeave()
	if not Comms._lfgAnnounced then
		return
	end
	Comms._lfgAnnounced = false
	Comms._lfgList[LocalFullName()] = nil
	Comms.QueueGuildLine("LFG;LEAVE")
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_LFG_UPDATED", Comms._lfgList)
	end
end

function Comms.GetLFGList()
	return Comms._lfgList or {}
end

if EventBus and EventBus.On then
	EventBus.On("PLAYER_LOGOUT", function()
		if Comms._lfgAnnounced then
			Comms.SendLFGLeave()
		end
	end)
end
