local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.NpcInteractions = QM.NpcInteractions or {}

-- Legacy shim: NpcActionRules is now the single source of truth.
function QM.NpcInteractions.CreateRunner(api)
	local rules = QM and QM.NpcActionRules
	if type(rules) == "table" and type(rules.CreateRunner) == "function" then
		return rules.CreateRunner(api)
	end
	return nil
end
