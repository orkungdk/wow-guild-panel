local ADDON, ns = ...

ns.Prefs = ns.Prefs or {}
local Prefs = ns.Prefs
local EventBus = ns.EventBus

local function EnsureDB()
	WoWGuildeDB = WoWGuildeDB or {}
	return WoWGuildeDB
end

local function ensure(path)
	local ref = EnsureDB()
	for _, k in ipairs(path) do
		ref[k] = ref[k] or {}
		ref = ref[k]
	end
	return ref
end

local function ensureSettings()
	local db = EnsureDB()
	if type(db.Settings) ~= "table" then
		db.Settings = {}
	end
	return db.Settings
end

function Prefs.GetHeros(key, default)
	local db = WoWGuildeDB
	if type(db) == "table" and type(db.HerosPrefs) == "table" then
		local v = db.HerosPrefs[key]
		if v ~= nil then
			return v
		end
	end
	return default
end

function Prefs.SetHeros(key, val)
	local t = ensure({ "HerosPrefs" })
	t[key] = val
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_PREFS_CHANGED", "Heros", key, val)
	end
	if ns and ns.Comms and ns.Comms.DEV_MODE then
		print("|cffffd100[WoW Guilde]|r PREFS Heros " .. tostring(key) .. "=" .. tostring(val))
	end
end

function Prefs.GetSocial(key, default)
	local settings = ensureSettings()
	local v = settings[key]
	if v ~= nil then
		return v
	end
	return default
end

function Prefs.SetSocial(key, val)
	local t = ensureSettings()
	t[key] = val
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_PREFS_CHANGED", "Social", key, val)
	end
	if ns and ns.Comms and ns.Comms.DEV_MODE then
		print("|cffffd100[WoW Guilde]|r PREFS Social " .. tostring(key) .. "=" .. tostring(val))
	end
end
