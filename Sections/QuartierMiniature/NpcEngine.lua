local ADDON, ns = ...

ns.QuartierMiniatureSectionNpcEngine = ns.QuartierMiniatureSectionNpcEngine or {}
local M = ns.QuartierMiniatureSectionNpcEngine

function M.Build(env)
	local runtime = ns and ns.QuartierMiniatureNpcEngineRuntime or nil
	if not (runtime and type(runtime.Build) == "function") then
		return nil
	end
	return runtime.Build(env)
end

return M
