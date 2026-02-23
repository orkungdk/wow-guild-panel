local ADDON, ns = ...

ns.RosteurSection = ns.RosteurSection or {}
local M = ns.RosteurSection

function M.CreateContext(parent)
	local ctx = {
		parent = parent,
		ns = ns,
		Sections = ns.Sections,
		Rosteur = ns.Rosteur,
		Utils = ns.Utils,
		DB = ns.DB,
		EventBus = ns.EventBus,
		const = {},
		state = {},
		ui = {},
		fn = {},
	}

	local const = ctx.const
	const.ROLE_ORDER = { "TANK", "HEAL", "DPS" }
	const.ROLE_LABEL = { TANK = "Protection", HEAL = "Soins", DPS = "Dégâts" }
	const.PREP_CONFIG_MIN_WAIT_SECONDS = 2 * 24 * 60 * 60
	const.ROLE_ATLAS = {
		TANK = "UI-LFG-RoleIcon-Tank",
		HEAL = "UI-LFG-RoleIcon-Healer",
		DPS = "UI-LFG-RoleIcon-DPS",
	}

	ctx.state.showPrepSummary = false
	ctx.state.pendingStartConfigGuildUID = nil
	ctx.state.sidebarCollapsed = { TANK = false, HEAL = false, DPS = false }

	return ctx
end

return M
