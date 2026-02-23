local ADDON, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

local MAP = {
	WARRIOR = { ["Protection"] = "Tank", ["Armes"] = "DPS", ["Fureur"] = "DPS" },
	PALADIN = { ["Protection"] = "Tank", ["Sacré"] = "Heal", ["Vindicte"] = "DPS" },
	DEATHKNIGHT = { ["Sang"] = "Tank", ["Givre"] = "DPS", ["Impie"] = "DPS" },
	DRUID = {
		["Gardien"] = "Tank",
		["Restauration"] = "Heal",
		["Équilibre"] = "DPS",
		["Farouche"] = "DPS",
		["Combat farouche"] = "DPS",
	},
	MONK = {
		["Maître brasseur"] = "Tank",
		["Tisse-brume"] = "Heal",
		["Marche-vent"] = "DPS",
	},
	DEMONHUNTER = { ["Vengeance"] = "Tank", ["Dévastation"] = "DPS" },
	PRIEST = { ["Discipline"] = "Heal", ["Sacré"] = "Heal", ["Ombre"] = "DPS" },
	SHAMAN = {
		["Amélioration"] = "DPS",
		["Élémentaire"] = "DPS",
		["Restauration"] = "Heal",
	},
	MAGE = { ["Givre"] = "DPS", ["Feu"] = "DPS", ["Arcanes"] = "DPS" },
	WARLOCK = {
		["Destruction"] = "DPS",
		["Démonologie"] = "DPS",
		["Affliction"] = "DPS",
	},
	HUNTER = {
		["Maîtrise des bêtes"] = "DPS",
		["Précision"] = "DPS",
		["Survie"] = "DPS",
	},
	ROGUE = { ["Assassinat"] = "DPS", ["Hors-la-loi"] = "DPS", ["Finesse"] = "DPS" },
	EVOKER = {
		["Augmentation"] = "DPS",
		["Dévastation"] = "DPS",
		["Préservation"] = "Heal",
	},
}

local TECH_SPEC_ROLE = {
	[62] = "DPS", -- Mage Arcane
	[63] = "DPS", -- Mage Fire
	[64] = "DPS", -- Mage Frost
	[65] = "HEAL", -- Paladin Holy
	[66] = "TANK", -- Paladin Protection
	[70] = "DPS", -- Paladin Retribution
	[71] = "DPS", -- Warrior Arms
	[72] = "DPS", -- Warrior Fury
	[73] = "TANK", -- Warrior Protection
	[102] = "DPS", -- Druid Balance
	[103] = "DPS", -- Druid Feral
	[104] = "TANK", -- Druid Guardian
	[105] = "HEAL", -- Druid Restoration
	[250] = "TANK", -- Death Knight Blood
	[251] = "DPS", -- Death Knight Frost
	[252] = "DPS", -- Death Knight Unholy
	[253] = "DPS", -- Hunter Beast Mastery
	[254] = "DPS", -- Hunter Marksmanship
	[255] = "DPS", -- Hunter Survival
	[256] = "HEAL", -- Priest Discipline
	[257] = "HEAL", -- Priest Holy
	[258] = "DPS", -- Priest Shadow
	[259] = "DPS", -- Rogue Assassination
	[260] = "DPS", -- Rogue Outlaw
	[261] = "DPS", -- Rogue Subtlety
	[262] = "DPS", -- Shaman Elemental
	[263] = "DPS", -- Shaman Enhancement
	[264] = "HEAL", -- Shaman Restoration
	[265] = "DPS", -- Warlock Affliction
	[266] = "DPS", -- Warlock Demonology
	[267] = "DPS", -- Warlock Destruction
	[268] = "TANK", -- Monk Brewmaster
	[269] = "DPS", -- Monk Windwalker
	[270] = "HEAL", -- Monk Mistweaver
	[577] = "DPS", -- Demon Hunter Havoc
	[581] = "TANK", -- Demon Hunter Vengeance
	[1467] = "DPS", -- Evoker Devastation
	[1468] = "HEAL", -- Evoker Preservation
	[1473] = "DPS", -- Evoker Augmentation
}

local TECH_CLASS_ROLES = {
	WARRIOR = { TANK = true, DPS = true },
	PALADIN = { TANK = true, HEAL = true, DPS = true },
	DEATHKNIGHT = { TANK = true, DPS = true },
	DRUID = { TANK = true, HEAL = true, DPS = true },
	MONK = { TANK = true, HEAL = true, DPS = true },
	DEMONHUNTER = { TANK = true, DPS = true },
	PRIEST = { HEAL = true, DPS = true },
	SHAMAN = { HEAL = true, DPS = true },
	MAGE = { DPS = true },
	WARLOCK = { DPS = true },
	HUNTER = { DPS = true },
	ROGUE = { DPS = true },
	EVOKER = { HEAL = true, DPS = true },
}

function UI.GetAllowedRoles(classTag, specName, specID)
	local allowed = {}
	local classKey = tostring(classTag or ""):upper():gsub("^%s+", ""):gsub("%s+$", "")

	local role = TECH_SPEC_ROLE[tonumber(specID or 0) or 0]
	if role then
		allowed[role] = true
	end

	local base = TECH_CLASS_ROLES[classKey]
	if base then
		for k in pairs(base) do
			allowed[k] = true
		end
	end

	if not next(allowed) then
		allowed.TANK = true
		allowed.HEAL = true
		allowed.DPS = true
	end

	return allowed
end

function UI.IsRoleAllowed(roleTag, classTag, specName, specID)
	local role = tostring(roleTag or ""):upper()
	if role ~= "TANK" and role ~= "HEAL" and role ~= "DPS" then
		return false
	end
	local allowed = UI.GetAllowedRoles(classTag, specName, specID)
	return allowed and allowed[role] == true
end

function UI.RoleFromClassSpec(classTag, spec)
	local t = MAP[classTag or ""]
	if t then
		local r = t[spec or ""]
		if r then
			return r
		end
	end
	return "-"
end

function UI.GetRoleAtlas(role)
	if role:find("Tank") then
		return "UI-LFG-RoleIcon-Tank"
	elseif role:find("Heal") then
		return "UI-LFG-RoleIcon-Healer"
	elseif role:find("Dégats") or role:find("DPS") then
		return "UI-LFG-RoleIcon-DPS"
	end
	return nil
end
