-- ==========================================================
-- EventBus (WoW 12 friendly)
-- - Lazy RegisterEvent: on n'enregistre un event WoW que si un module le demande
-- - Boot après PLAYER_LOGIN uniquement
-- - Handlers protégés (xpcall)
-- - API: On / Once / Off / Emit / IsReady / AllowSensitiveEvent
-- ==========================================================

local ADDON, ns = ...

ns.EventBus = ns.EventBus or {}
local Bus = ns.EventBus

-- ==========================================================
-- Config
-- ==========================================================

-- Events sensibles : on évite par défaut de s'y brancher globalement en WoW 12.
-- Tu peux les autoriser explicitement via Bus.AllowSensitiveEvent("COMBAT_LOG_EVENT_UNFILTERED")
local SENSITIVE_EVENTS = {
	COMBAT_LOG_EVENT_UNFILTERED = true,
}
local INTERNAL_EVENTS = {
	ADDON_READY = true,
}
local EARLY_EVENTS = {
	PLAYER_LOGIN = true,
}
-- ==========================================================
-- State
-- ==========================================================

local frame = Bus._frame
local ready = Bus._ready or false

-- listeners[event] = { {fn=..., once=bool}, ... }
local listeners = Bus._listeners or {}
Bus._listeners = listeners

-- events WoW réellement enregistrés sur le frame (pour éviter double-register)
local registered = Bus._registered or {}
Bus._registered = registered

-- events sensibles explicitement autorisés
local allowedSensitive = Bus._allowedSensitive or {}
Bus._allowedSensitive = allowedSensitive

-- internal events already fired (sticky)
local firedSticky = Bus._firedSticky or {}
Bus._firedSticky = firedSticky

-- ==========================================================
-- Utils
-- ==========================================================

local function SafeCall(fn, ...)
	local ok, err = xpcall(fn, geterrorhandler(), ...)
	if not ok then
		-- geterrorhandler() affiche déjà ; on évite de re-throw.
		return false, err
	end
	return true
end

local unpack = table.unpack or unpack

local function IsSensitive(event)
	return SENSITIVE_EVENTS[event] == true
end

local function EnsureFrame()
	if frame then
		return
	end
	frame = CreateFrame("Frame")
	Bus._frame = frame
	frame:SetScript("OnEvent", function(_, event, ...)
		Bus._Dispatch(event, ...)
	end)
end

local function CanRegister(event)
	if type(event) ~= "string" or event == "" then
		return false
	end

	if INTERNAL_EVENTS[event] then
		return false
	end

	if IsSensitive(event) and not allowedSensitive[event] then
		return false
	end

	return true
end

local function RegisterEventIfNeeded(event)
	if not ready then
		return false
	end
	if not CanRegister(event) then
		return false
	end
	if registered[event] then
		return true
	end

	EnsureFrame()

	local ok = pcall(frame.RegisterEvent, frame, event)
	if not ok then
		return false
	end

	registered[event] = true
	return true
end

local function UnregisterEventIfUnused(event)
	if not ready or not frame or not registered[event] then
		return
	end
	local list = listeners[event]
	if list and #list > 0 then
		return
	end
	frame:UnregisterEvent(event)
	registered[event] = nil
end

-- ==========================================================
-- Public API
-- ==========================================================

-- Autorise explicitement un event sensible (ex: COMBAT_LOG_EVENT_UNFILTERED)
function Bus.AllowSensitiveEvent(event)
	if type(event) ~= "string" then
		return false
	end
	if not IsSensitive(event) then
		-- pas sensible : rien à autoriser
		return true
	end
	allowedSensitive[event] = true
	-- si quelqu'un s'était abonné avant autorisation, on tente de register maintenant
	if listeners[event] and #listeners[event] > 0 then
		RegisterEventIfNeeded(event)
	end
	return true
end

function Bus.IsReady()
	return ready
end

-- Subscribe
function Bus.On(event, handler)
	if type(event) ~= "string" or type(handler) ~= "function" then
		return false
	end

	listeners[event] = listeners[event] or {}
	table.insert(listeners[event], { fn = handler, once = false })

	-- Lazy register (uniquement si booted)
	RegisterEventIfNeeded(event)

	if (INTERNAL_EVENTS[event] or EARLY_EVENTS[event]) and firedSticky[event] then
		SafeCall(handler, event, unpack(firedSticky[event], 1, firedSticky[event].n))
		Bus.Off(event, handler)
	end

	return true
end

-- Subscribe once
function Bus.Once(event, handler)
	if type(event) ~= "string" or type(handler) ~= "function" then
		return false
	end

	listeners[event] = listeners[event] or {}
	table.insert(listeners[event], { fn = handler, once = true })

	RegisterEventIfNeeded(event)

	if (INTERNAL_EVENTS[event] or EARLY_EVENTS[event]) and firedSticky[event] then
		SafeCall(handler, event, unpack(firedSticky[event], 1, firedSticky[event].n))
		Bus.Off(event, handler)
	end

	return true
end

-- Unsubscribe (retire toutes les occurrences du handler pour l'event)
function Bus.Off(event, handler)
	local list = listeners[event]
	if not list or #list == 0 then
		return false
	end

	if handler == nil then
		-- purge event complet
		listeners[event] = nil
		UnregisterEventIfUnused(event)
		return true
	end

	for i = #list, 1, -1 do
		if list[i] and list[i].fn == handler then
			table.remove(list, i)
		end
	end

	if #list == 0 then
		listeners[event] = nil
		UnregisterEventIfUnused(event)
	end

	return true
end

-- Emit interne (event custom addon, pas un event WoW)
function Bus.Emit(event, ...)
	if INTERNAL_EVENTS[event] then
		local args = { ... }
		args.n = select("#", ...)
		firedSticky[event] = args
	end
	Bus._Dispatch(event, ...)
end

-- ==========================================================
-- Internal dispatch
-- ==========================================================

function Bus._Dispatch(event, ...)
	local list = listeners[event]
	if not list or #list == 0 then
		return
	end

	-- Copie rapide pour supporter la modification de listeners pendant dispatch
	local snapshot = {}
	for i = 1, #list do
		snapshot[i] = list[i]
	end

	local removedAny = false

	for i = 1, #snapshot do
		local entry = snapshot[i]
		if entry and entry.fn then
			-- Important: on n'impose pas de signature (event, ...) ou (...) :
			-- ici on passe (event, ...) pour rester compatible avec ton ancien code.
			SafeCall(entry.fn, event, ...)

			if entry.once then
				Bus.Off(event, entry.fn)
				removedAny = true
			end
		end
	end

	if removedAny then
		UnregisterEventIfUnused(event)
	end
end

-- ==========================================================
-- Boot strap (barrière PLAYER_LOGIN)
-- ==========================================================

local function Boot()
	if ready then
		return
	end
	ready = true
	Bus._ready = true

	EnsureFrame()

	-- Register tous les events déjà demandés (lazy subscribe avant login)
	for evt, list in pairs(listeners) do
		if list and #list > 0 then
			RegisterEventIfNeeded(evt)
		end
	end

	if listeners.PLAYER_LOGIN and #listeners.PLAYER_LOGIN > 0 then
		local args = {}
		args.n = 0
		firedSticky.PLAYER_LOGIN = args
		Bus._Dispatch("PLAYER_LOGIN")
	end

	-- Event custom "ADDON_READY" (équivalent à ton ancien Dispatch)
	-- MAIS cette fois-ci il arrive après PLAYER_LOGIN, donc safe.
	Bus.Emit("ADDON_READY")
end

-- Une seule frame "bootstrap", aucun timer, aucune callback exotique.
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function()
		f:UnregisterEvent("PLAYER_LOGIN")
		Boot()
	end)
end
