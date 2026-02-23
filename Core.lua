local ADDON, ns = ...
local EventBus = ns.EventBus

local function EnsureGlobal()
	if not WoWGuilde then
		WoWGuilde = {}
	end
	return WoWGuilde
end

local function d(...)
	print("|cff8be9fd[WoWGuilde]|r", ...)
end

if not EventBus or not EventBus.On then
	return
end

-- ==========================================================
-- ADDON READY : point d'entrée principal (ex-ADDON_LOADED)
-- ==========================================================

EventBus.On("ADDON_READY", function()
	local M = EnsureGlobal()

	-- API globale minimale
	M.d = d
	M.Toggle = function()
		if ns and ns.UI and ns.UI.Toggle then
			ns.UI.Toggle()
		end
	end

	-- SavedVariables
	WoWGuildeDB = WoWGuildeDB or {}

	-- Init UI (création UNE FOIS)
	if ns and ns.UI and ns.UI.Init then
		ns.UI.Init()
	end
end)

-- ==========================================================
-- PLAYER_LOGIN : logique gameplay / données joueur
-- ==========================================================

EventBus.On("PLAYER_LOGIN", function()
	if ns and ns.GB and ns.GB.Init then
		ns.GB.Init()
	end
	if ns and ns.DB and ns.DB.SanitizeOtherDrafts then
		if C_Timer and C_Timer.After then
			C_Timer.After(1, function()
				if ns and ns.DB and ns.DB.SanitizeOtherDrafts then
					ns.DB:SanitizeOtherDrafts()
				end
			end)
		else
			ns.DB:SanitizeOtherDrafts()
		end
	end
end)
