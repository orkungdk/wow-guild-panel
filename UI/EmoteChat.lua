-- WoWGuilde/UI/ChatReactions.lua  — version «clean»
local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
ns.Emotes = ns.Emotes or {}
UI.ChatReactions = UI.ChatReactions or {}

local Reactions = ns.Reactions
local Targets = ns.Targets
local EventBus = ns.EventBus
local HU = (ns.Heros and ns.Heros.Utils) or nil

-- ===================== Utils =====================
local function PlayerRealm()
	local _, r = UnitFullName("player")
	return r or ""
end

local function Trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
local function RemoveColors(s)
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local function NormalizeHyphen(s)
	return (s:gsub("[\226\128\147\226\128\148\226\128\150\226\128\151\226\128\145]", "-"))
end

local function SanitizeRawName(s)
	if not s then
		return nil
	end
	s = RemoveColors(s)
	s = s:gsub("%s*%(%*%)%s*$", "") -- retire " (*)"
	s = NormalizeHyphen(s)
	return Trim(s)
end

local function ToFullName(name)
	if not name or name == "" then
		return nil
	end
	if name:find("-", 1, true) then
		return name
	end
	local r = PlayerRealm()
	return (r ~= "" and (name .. "-" .. r)) or name
end

local function MyFullName()
	local n, r = UnitFullName and UnitFullName("player")
	if not n then
		n = UnitName and UnitName("player") or "?"
	end
	if r and r ~= "" then
		return n .. "-" .. r
	end
	return n
end

local function ShortName(name)
	if type(name) ~= "string" then
		return ""
	end
	return name:gsub("%-.*$", "")
end

local function IsDevMode()
	if ns.Utils and ns.Utils.IsDevMode then
		return ns.Utils.IsDevMode()
	end
	if ns and ns.Comms and ns.Comms.DEV_MODE ~= nil then
		return ns.Comms.DEV_MODE == true
	end
	if ns and ns.DEV_MODE ~= nil then
		return ns.DEV_MODE == true
	end
	if ns and ns.Prefs and ns.Prefs.GetSocial then
		return ns.Prefs.GetSocial("devMode", false) == true
	end
	return false
end

local function IsSelfContext(ctx)
	if not ctx then
		return false
	end
	if ctx.isSelf or ctx.isLocalPlayer then
		return true
	end
	if ctx.unit and UnitIsUnit and UnitIsUnit(ctx.unit, "player") then
		return true
	end
	local pn = ctx.playerName or ctx.name
	if type(pn) == "string" then
		pn = SanitizeRawName(pn)
		local me = UnitName and UnitName("player")
		if me and pn == me then
			return true
		end
	end
	return false
end

local function ExtractNameFromContext(owner, root, ctx)
	if ctx then
		if type(ctx.name) == "string" and ctx.name ~= "" then
			return ToFullName(SanitizeRawName(ctx.name))
		end
		if type(ctx.playerName) == "string" and ctx.playerName ~= "" then
			return ToFullName(SanitizeRawName(ctx.playerName))
		end
		if ctx.playerLocation and C_PlayerInfo and C_PlayerInfo.GetName then
			local nm = C_PlayerInfo.GetName(ctx.playerLocation)
			if nm and nm ~= "" then
				return ToFullName(SanitizeRawName(nm))
			end
		end
	end
	if owner and type(owner.name) == "string" and owner.name ~= "" then
		return ToFullName(SanitizeRawName(owner.name))
	end
	if root and root.data and type(root.data.name) == "string" and root.data.name ~= "" then
		return ToFullName(SanitizeRawName(root.data.name))
	end
	return nil
end

-- ===================== Sous-menu Réactions =====================
local function AddReactionsSubmenu(root, targetFull, isTest)
	if Reactions and Reactions.AddSubmenu then
		return Reactions.AddSubmenu(root, targetFull, isTest)
	end
end

-- --- Helpers cache (lit ce que ton Init expose) ----------------
local function GetCacheRec(name)
	local cache = (ns and ns.Utils and ns.Utils.PSEUDO_CACHE) or {}
	if not name or name == "" then
		return nil
	end
	return cache[name] or cache[Ambiguate(name, "none")]
end

local function InPseudoCache(name)
	return GetCacheRec(name) ~= nil
end

local function IsGuildMemberFull(full)
	if Targets and Targets.IsGuildMember then
		return Targets.IsGuildMember(full)
	end
	if not full or full == "" then
		return false
	end
	local cache = ns.DB and ns.DB._RosterByFull or nil
	local short = Ambiguate and Ambiguate(full, "none") or full
	if cache then
		if cache[full] or cache[short] then
			return true
		end
	end
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	end
	local n = GetNumGuildMembers and GetNumGuildMembers() or 0
	for i = 1, n do
		local name = GetGuildRosterInfo(i)
		if name and name ~= "" then
			local rosterFull = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name
			local rosterShort = Ambiguate and Ambiguate(rosterFull, "none") or rosterFull
			if rosterFull == full or rosterShort == short then
				return true
			end
		end
	end
	return false
end

-- ===================== Hook menus =====================
local function InstallChatMenuHook()
	if not Menu or not Menu.ModifyMenu then
		return
	end

	local function Modifier(owner, root, ctx)
		local ok = pcall(function()
			local full = ExtractNameFromContext(owner, root, ctx)
			local myFull = MyFullName()
			if not full and IsSelfContext(ctx) then
				full = myFull
			elseif not full then
				return
			end
			local liveRec = nil
			if Targets and Targets.ResolveForFull then
				local live, _, rec = Targets.ResolveForFull(full)
				if live and live ~= "" then
					full = live
				end
				liveRec = rec
			elseif HU and HU.ResolveLiveCharacterForFull then
				local live = HU.ResolveLiveCharacterForFull(full)
				if live and live ~= "" then
					full = live
				end
			end

			local myShort = Ambiguate and Ambiguate(myFull, "none") or myFull
			local fullShort = Ambiguate and Ambiguate(full, "none") or full
			local isSelf = full == myFull
				or fullShort == myShort
				or ShortName(full) == ShortName(myFull)
				or IsSelfContext(ctx)
			if not InPseudoCache(full) and not IsGuildMemberFull(full) then
				return
			end

			local hasAddon = false
			if ns and ns.DB and ns.DB.GetGuildUID and ns.DB.GetGuildMemberPrefs and ns.Data and ns.Data.ResolvePlayerUID then
				local gid = ns.DB:GetGuildUID()
				if gid and gid ~= "" then
					local uid = ns.Data.ResolvePlayerUID(gid, full, liveRec and liveRec.guid)
					if uid and uid ~= "" then
						hasAddon = ns.DB:GetGuildMemberPrefs(gid, uid) ~= nil
					end
				end
			end

			local canTest = IsDevMode() and isSelf
			local canSend = (not isSelf) and hasAddon
			local willAdd = canTest or canSend

			if willAdd then
				if root.CreateDivider then
					root:CreateDivider()
				end
				if root.CreateTitle then
					root:CreateTitle("Guild")
				end
				if canTest then
					AddReactionsSubmenu(root, full, true)
				elseif canSend then
					AddReactionsSubmenu(root, full, false)
				end
				root:CreateButton("Profili gor", function()
					if ns and ns.UI and ns.UI.Show then
						ns.UI.Show()
					end
					if ns and ns.UI and ns.UI.ShowSection then
						ns.UI.ShowSection("Nos héros")
					end
					if ns and ns.Sections and ns.Sections.Heros_SelectByFull then
						ns.Sections.Heros_SelectByFull(full)
					end
				end)
			end
		end)
		if not ok then
			return
		end
	end

	Menu.ModifyMenu("MENU_CHAT_PLAYER", Modifier)
	-- Avoid tainting protected friend-note actions (SetNote) from Blizzard menus.
	-- Keep only chat player menu hook for addon entries.
end

-- ===================== Bootstrap =====================
if EventBus and EventBus.On then
	EventBus.On("PLAYER_LOGIN", function()
		InstallChatMenuHook()
	end)
end
