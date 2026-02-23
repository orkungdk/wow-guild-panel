local ADDON, ns = ...

ns.QuartierMiniatureNpcEngineRuntime = ns.QuartierMiniatureNpcEngineRuntime or {}
local Runtime = ns.QuartierMiniatureNpcEngineRuntime

local MODULE_ORDER = {
	"InstallContext",
	"InstallNavigation",
	"InstallSocial",
	"InstallOrders",
	"InstallMovement",
	"InstallVisual",
	"InstallPersistence",
	"InstallOfflineSim",
	"InstallSnapshots",
}

local function BuildBaseContext(env)
	if type(env) ~= "table" then
		return nil
	end

	local mapLayer = env.mapLayer
	local viewport = env.viewport
	local state = env.state
	local clamp = env.clamp
	local getActiveMapId = env.getActiveMapId
	local getCurrentBaseSize = env.getCurrentBaseSize
	if not (mapLayer and viewport and state and type(clamp) == "function" and type(getActiveMapId) == "function") then
		return nil
	end
	if type(getCurrentBaseSize) ~= "function" then
		return nil
	end

	return {
		ADDON = ADDON,
		ns = ns,
		env = env,
		mapLayer = mapLayer,
		viewport = viewport,
		state = state,
		npcCfg = env.npcCfg or {},
		Clamp = clamp,
		GetActiveMapId = getActiveMapId,
		getCurrentBaseSize = getCurrentBaseSize,
	}
end

local function BuildModuleEnv(ctx)
	local env = {
		_G = _G,
	}

	-- Some Blizzard helpers resolve mixins via raw lookups on the caller env.
	-- Mirror mixin globals directly to avoid "unable to find mixin (...Mixin)".
	for key, value in pairs(_G) do
		if type(key) == "string" and string.find(key, "Mixin", 1, true) then
			env[key] = value
		end
	end

	return setmetatable(env, {
		__index = function(_, key)
			local value = rawget(ctx, key)
			if value ~= nil then
				return value
			end
			return _G[key]
		end,
		__newindex = function(t, key, value)
			ctx[key] = value
			rawset(t, key, value)
		end,
	})
end

function Runtime.Build(env)
	local modulesRoot = ns and ns.QuartierMiniatureNpcEngine and ns.QuartierMiniatureNpcEngine.Modules or nil
	if type(modulesRoot) ~= "table" then
		error("WoWGuilde_QuartierMiniature: modules NpcEngine introuvables")
	end

	local ctx = BuildBaseContext(env)
	if type(ctx) ~= "table" then
		return nil
	end
	local moduleEnv = BuildModuleEnv(ctx)

	for i = 1, #MODULE_ORDER do
		local installerName = MODULE_ORDER[i]
		local installer = modulesRoot[installerName]
		if type(installer) ~= "function" then
			error("WoWGuilde_QuartierMiniature: module NpcEngine manquant: " .. tostring(installerName))
		end
		local ok, err = pcall(installer, ctx, moduleEnv)
		if not ok then
			error("WoWGuilde_QuartierMiniature: echec module " .. tostring(installerName) .. ": " .. tostring(err))
		end
	end

	local runtime = rawget(ctx, "__runtime")
	if type(runtime) ~= "table" then
		error("WoWGuilde_QuartierMiniature: runtime NpcEngine invalide")
	end
	return runtime
end

return Runtime
