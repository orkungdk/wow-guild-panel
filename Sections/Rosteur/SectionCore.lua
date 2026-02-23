local ADDON, ns = ...

ns.RosteurSectionCore = ns.RosteurSectionCore or {}
local Core = ns.RosteurSectionCore

function Core.Build(env)
	local Common = ns.RosteurSectionCoreCommon
	local Drag = ns.RosteurSectionCoreDrag
	local View = ns.RosteurSectionCoreView

	if not (Common and Common.Build) then
		error("WoWGuilde_Rosteur: module Core/Common introuvable")
	end
	if not (Drag and Drag.Build) then
		error("WoWGuilde_Rosteur: module Core/Drag introuvable")
	end
	if not (View and View.Build) then
		error("WoWGuilde_Rosteur: module Core/View introuvable")
	end

	local common = Common.Build({
		Utils = env and env.Utils or nil,
		DB = env and env.DB or nil,
		PREP_CONFIG_MIN_WAIT_SECONDS = env and env.PREP_CONFIG_MIN_WAIT_SECONDS or nil,
	})

	local drag = Drag.Build({
		Utils = env and env.Utils or nil,
		ColorizeName = common.ColorizeName,
	})

	local view = View.Build({
		ROLE_ORDER = env and env.ROLE_ORDER or nil,
		ROLE_LABEL = env and env.ROLE_LABEL or nil,
		ROLE_ATLAS = env and env.ROLE_ATLAS or nil,
		ColorizeName = common.ColorizeName,
		StartDrag = drag.StartDrag,
		StopDrag = drag.StopDrag,
		StopDragDeferred = drag.StopDragDeferred,
		GetDrag = drag.GetDrag,
		GetShortDragName = drag.GetShortDragName,
		ROSTER_CLASS_VISUAL_SIZE = drag.ROSTER_CLASS_VISUAL_SIZE,
	})

	return {
		TrimSpaces = common.TrimSpaces,
		IsPrepConfigLocked = common.IsPrepConfigLocked,
		IsDevMode = common.IsDevMode,
		GetGuildUID = common.GetGuildUID,
		GetMyFull = common.GetMyFull,
		GetMySignupMeta = common.GetMySignupMeta,
		ColorizeName = common.ColorizeName,
		GetPseudoAlias = common.GetPseudoAlias,
		StartDrag = drag.StartDrag,
		StopDrag = drag.StopDrag,
		StopDragDeferred = drag.StopDragDeferred,
		GetDrag = drag.GetDrag,
		IsMyRaidLeaderIdentity = common.IsMyRaidLeaderIdentity,
		NormalizeHeroKey = common.NormalizeHeroKey,
		CountAssignedEntries = view.CountAssignedEntries,
		MaxNumericIndex = view.MaxNumericIndex,
		MakeRosterView = view.MakeRosterView,
		CreateSimpleList = view.CreateSimpleList,
		NormalizeRoleTag = common.NormalizeRoleTag,
	}
end
