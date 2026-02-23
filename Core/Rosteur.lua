local ADDON, ns = ...

ns.Rosteur = ns.Rosteur or {}
local Rosteur = ns.Rosteur

local EventBus = ns.EventBus
local Utils = ns.Utils
local Roles = ns.Roles
local DB = ns.DB

local function IsDevMode()
	if Utils and Utils.IsDevMode then
		return Utils.IsDevMode()
	end
	if ns and ns.Comms and ns.Comms.DEV_MODE ~= nil then
		return ns.Comms.DEV_MODE == true
	end
	if ns and ns.DEV_MODE ~= nil then
		return ns.DEV_MODE == true
	end
	return false
end

local function Now()
	if time then
		return time()
	end
	return 0
end

local function GetGuildUID()
	if Utils and Utils.GetActiveGuildUID then
		local gid = Utils.GetActiveGuildUID()
		if gid and gid ~= "" then
			return gid
		end
	end
	if ns.DB and ns.DB.GetGuildUID then
		return ns.DB:GetGuildUID()
	end
	return nil
end

local function GetMyUID()
	if ns.DB and ns.DB.GetMyUID then
		return ns.DB:GetMyUID()
	end
	return nil
end

local function EnsureGuildRoot(guildUID)
	WoWGuildeDB = WoWGuildeDB or {}
	WoWGuildeDB.guilds = WoWGuildeDB.guilds or {}
	local g = WoWGuildeDB.guilds[guildUID]
	if not g then
		g = { guildInfo = { guildUID = guildUID }, players = {} }
		WoWGuildeDB.guilds[guildUID] = g
	end
	g.guildInfo = g.guildInfo or { guildUID = guildUID }
	g.guildShared = g.guildShared or {}
	return g
end

local function EnsureRosteur(guildUID)
	local g = EnsureGuildRoot(guildUID)
	local r = g.guildShared.rosteur
	if type(r) ~= "table" then
		r = {
			version = 1,
			phase = "idle",
			updatedAt = 0,
			seasonName = "",
			prep = { signups = {} },
			rosters = {},
			activeRosterId = nil,
			lockedAt = nil,
			lockedByUID = nil,
		}
		g.guildShared.rosteur = r
	end
	if type(r.prep) ~= "table" then
		r.prep = { signups = {} }
	end
	if type(r.prep.signups) ~= "table" then
		r.prep.signups = {}
	end
	if type(r.prep.hiddenSignups) ~= "table" then
		r.prep.hiddenSignups = {}
	end
	if type(r.prep.hiddenSignupsByRoster) ~= "table" then
		r.prep.hiddenSignupsByRoster = {}
	end
	-- Legacy migration: old implementation removed entries from signups globally.
	if type(r.prep.hiddenSignups) == "table" then
		for full, rec in pairs(r.prep.hiddenSignups) do
			if type(rec) == "table" and not r.prep.signups[full] then
				r.prep.signups[full] = rec
			end
		end
		r.prep.hiddenSignups = {}
	end
	if type(r.rosters) ~= "table" then
		r.rosters = {}
	end
	if type(r.createTargetsByTemplate) ~= "table" then
		r.createTargetsByTemplate = {}
	end
	return r, g
end

local function Notify(guildUID, rosteur, opts)
	if EventBus and EventBus.Emit then
		EventBus.Emit("WG_ROSTEUR_UPDATED", guildUID, rosteur, opts and opts.sender)
	end
	if opts and opts.announce == false then
		return
	end
	if ns.Comms and ns.Comms.Sync and ns.Comms.Sync.AnnounceElement then
		ns.Comms.Sync.AnnounceElement(guildUID, "rosteur", "state", rosteur.updatedAt)
	end
end

local function Touch(guildUID, rosteur)
	rosteur.updatedAt = Now()
	Notify(guildUID, rosteur)
end

local function CopyTargets(src)
	if type(src) ~= "table" then
		return nil
	end
	local out = {}
	for k, v in pairs(src) do
		out[k] = tonumber(v or 0) or 0
	end
	return out
end

local function NormalizeCreateTargets(src)
	if type(src) ~= "table" then
		return nil
	end
	local out = {}
	for key, value in pairs(src) do
		if type(value) == "table" then
			out[tostring(key)] = {
				TANK = 2,
				HEAL = math.max(0, math.floor(tonumber(value.HEAL or 0) or 0)),
				DPS = math.max(0, math.floor(tonumber(value.DPS or 0) or 0)),
			}
		end
	end
	return out
end

local function NormalizeRole(role)
	role = tostring(role or "")
	if role == "TANK" or role == "HEAL" or role == "DPS" then
		return role
	end
	return nil
end

local function NormalizeRoles(roles, fallbackRole)
	local out = {}
	if type(roles) == "table" then
		for k, v in pairs(roles) do
			local role = NormalizeRole(k)
			if role and v then
				out[role] = true
			end
		end
	end
	local fallback = NormalizeRole(fallbackRole)
	if fallback then
		out[fallback] = true
	end
	return out
end

local function GetSignupRoles(entry)
	if type(entry) ~= "table" then
		return {}
	end
	return NormalizeRoles(entry.roles, entry.role)
end

local function SignupHasRole(entry, role)
	local normRole = NormalizeRole(role)
	if not normRole then
		return false
	end
	local roles = GetSignupRoles(entry)
	return roles[normRole] == true
end

local function GetPrimaryRole(entry)
	if type(entry) ~= "table" then
		return nil
	end
	local roles = GetSignupRoles(entry)
	local role = NormalizeRole(entry.role)
	if role and roles[role] then
		return role
	end
	for _, key in ipairs({ "TANK", "HEAL", "DPS" }) do
		if roles[key] then
			return key
		end
	end
	return nil
end

local function CopySignupEntry(entry, full)
	if type(entry) ~= "table" then
		return nil
	end
	local copied = {
		full = entry.full or full,
		role = GetPrimaryRole(entry),
		roles = GetSignupRoles(entry),
		uid = entry.uid,
		name = entry.name,
		classTag = entry.classTag,
		spec = entry.spec,
		specID = entry.specID,
		heroFull = entry.heroFull,
		heroName = entry.heroName,
		updatedAt = tonumber(entry.updatedAt or 0) or 0,
	}
	return copied
end

local function MergeSignupRecord(localEntry, incomingEntry, full)
	local a = CopySignupEntry(localEntry, full)
	local b = CopySignupEntry(incomingEntry, full)
	if not a then
		return b
	end
	if not b then
		return a
	end
	local at = tonumber(a.updatedAt or 0) or 0
	local bt = tonumber(b.updatedAt or 0) or 0
	if bt > at then
		return b
	end
	if at > bt then
		return a
	end
	local roles = GetSignupRoles(a)
	for role in pairs(GetSignupRoles(b)) do
		roles[role] = true
	end
	a.roles = roles
	a.role = GetPrimaryRole(a)
	a.uid = a.uid or b.uid
	a.name = a.name or b.name
	a.classTag = a.classTag or b.classTag
	a.spec = a.spec or b.spec
	a.specID = a.specID or b.specID
	a.heroFull = a.heroFull or b.heroFull
	a.heroName = a.heroName or b.heroName
	return a
end

local function MergePrepSignups(localState, incomingState)
	if type(localState) ~= "table" or type(incomingState) ~= "table" then
		return incomingState
	end
	local localPrep = type(localState.prep) == "table" and localState.prep or {}
	local incomingPrep = type(incomingState.prep) == "table" and incomingState.prep or {}
	local localSignups = type(localPrep.signups) == "table" and localPrep.signups or {}
	local incomingSignups = type(incomingPrep.signups) == "table" and incomingPrep.signups or {}

	local merged = incomingState
	merged.prep = type(merged.prep) == "table" and merged.prep or {}
	merged.prep.signups = {}

	for full, entry in pairs(localSignups) do
		merged.prep.signups[full] = CopySignupEntry(entry, full)
	end
	for full, entry in pairs(incomingSignups) do
		merged.prep.signups[full] = MergeSignupRecord(merged.prep.signups[full], entry, full)
	end
	return merged
end

local function ShuffleList(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
end

local function GetPseudoAlias(full)
	if not full or full == "" or not Utils or not Utils.PSEUDO_CACHE then
		return nil
	end
	local cache = Utils.PSEUDO_CACHE
	local rec = cache[full]
	if not rec and Ambiguate then
		rec = cache[Ambiguate(full, "none")]
	end
	return rec and rec.alias or nil
end

local function NormalizeHeroKey(value)
	local v = tostring(value or "")
	v = v:gsub("^%s+", ""):gsub("%s+$", ""):lower()
	if v == "" then
		return nil
	end
	return v
end

local function GetAllowedRolesFromMeta(entry, meta)
	if not (ns and ns.UI and ns.UI.GetAllowedRoles) then
		return nil
	end
	local classTag = (meta and meta.classTag) or (entry and entry.classTag)
	local specName = (meta and meta.spec) or (entry and entry.spec)
	local specID = (meta and meta.specID) or (entry and entry.specID)
	return ns.UI.GetAllowedRoles(classTag, specName, specID)
end

local function PickRole(counts, targets)
	local bestRole = nil
	local bestScore = nil
	for _, role in ipairs({ "TANK", "HEAL", "DPS" }) do
		local target = tonumber(targets and targets[role]) or 0
		if target <= 0 then
			target = 1
		end
		local score = (counts[role] or 0) / target
		if not bestScore or score < bestScore or (score == bestScore and math.random() < 0.5) then
			bestScore = score
			bestRole = role
		end
	end
	return bestRole or "DPS"
end

local function PickRoleAllowed(counts, targets, allowed)
	local bestRole = nil
	local bestScore = nil
	for _, role in ipairs({ "TANK", "HEAL", "DPS" }) do
		if not allowed or allowed[role] then
			local target = tonumber(targets and targets[role]) or 0
			if target <= 0 then
				target = 1
			end
			local score = (counts[role] or 0) / target
			if not bestScore or score < bestScore or (score == bestScore and math.random() < 0.5) then
				bestScore = score
				bestRole = role
			end
		end
	end
	return bestRole or "DPS"
end

local function NewId(prefix)
	local p = prefix or "r"
	return p .. tostring(Now()) .. "_" .. tostring(math.random(1000, 9999))
end

local function FindRoster(rosteur, rosterId)
	if type(rosteur) ~= "table" or type(rosteur.rosters) ~= "table" then
		return nil, nil
	end
	for i = 1, #rosteur.rosters do
		local r = rosteur.rosters[i]
		if r and r.id == rosterId then
			return r, i
		end
	end
	return nil, nil
end

local function EnsureRosterGroups(roster)
	roster.groups = roster.groups or {}
	roster.groups.TANK = roster.groups.TANK or {}
	roster.groups.HEAL = roster.groups.HEAL or {}
	roster.groups.DPS = roster.groups.DPS or {}
	return roster.groups
end

local function RemoveEntryFromRoster(roster, entryId)
	if not roster or not entryId then
		return
	end
	local groups = EnsureRosterGroups(roster)
	for _, list in pairs(groups) do
		if type(list) == "table" then
			for i, e in pairs(list) do
				if type(i) == "number" and e and (e.id == entryId or e.full == entryId) then
					list[i] = nil
				end
			end
		end
	end
end

local TEMPLATES = {
	raid10 = { name = "Raid 10", targets = { TANK = 2, HEAL = 2, DPS = 6 } },
	raid15 = { name = "Raid 15", targets = { TANK = 2, HEAL = 3, DPS = 10 } },
	raid20 = { name = "Raid 20", targets = { TANK = 2, HEAL = 4, DPS = 14 } },
	raid25 = { name = "Raid 25", targets = { TANK = 2, HEAL = 5, DPS = 18 } },
}

Rosteur._devView = Rosteur._devView or "auto"

function Rosteur.SetDevView(view)
	if not IsDevMode() then
		return
	end
	if view ~= "auto" and view ~= "player" and view ~= "manager" then
		return
	end
	Rosteur._devView = view
end

function Rosteur.GetDevView()
	return Rosteur._devView or "auto"
end

function Rosteur.ResolveCanManage(real)
	local view = Rosteur.GetDevView()
	if IsDevMode() then
		if view == "player" then
			return false
		end
		if view == "manager" then
			return true
		end
	end
	return real
end

function Rosteur.GetTemplates()
	return TEMPLATES
end

function Rosteur.GetState(guildUID)
	local gid = guildUID or GetGuildUID()
	if not gid then
		return nil
	end
	local r = EnsureRosteur(gid)
	return r
end

function Rosteur.GetPhase(guildUID)
	local r = Rosteur.GetState(guildUID)
	return r and r.phase or "idle"
end

function Rosteur.IsActive(guildUID)
	local phase = Rosteur.GetPhase(guildUID)
	return phase ~= "idle"
end

function Rosteur.CanManage()
	if Roles and Roles.IsGuildLeader and Roles.IsGuildLeader() then
		return true
	end
	if Roles and Roles.IsOfficer and Roles.IsOfficer() then
		return true
	end
	if UnitIsGroupLeader and UnitIsGroupLeader("player") then
		return true
	end
	if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then
		return true
	end
	if UnitIsRaidOfficer and UnitIsRaidOfficer("player") then
		return true
	end
	return false
end

local function IsUIDRaidLeaderFlagged(gid, uid)
	if not (gid and gid ~= "" and uid and uid ~= "" and DB and DB.GetGuildMemberPrefs) then
		return false
	end
	local prefs = DB:GetGuildMemberPrefs(gid, uid)
	return type(prefs) == "table" and prefs.raidLeader == true
end

local function IsUIDRaidLeaderFlaggedAnywhere(uid)
	if not (uid and uid ~= "" and WoWGuildeDB and type(WoWGuildeDB.guilds) == "table") then
		return false
	end
	for _, g in pairs(WoWGuildeDB.guilds) do
		local prefsMap = g and g.guildShared and g.guildShared.guildMemberPrefs
		local prefs = type(prefsMap) == "table" and prefsMap[uid] or nil
		if type(prefs) == "table" and prefs.raidLeader == true then
			return true
		end
	end
	return false
end

function Rosteur.ShouldShowManagerTab()
	local view = Rosteur.GetDevView()
	if IsDevMode() then
		if view == "player" then
			return false
		end
		if view == "manager" then
			return true
		end
	end
	local myUID = GetMyUID()
	if not myUID or myUID == "" then
		return false
	end
	local gidActive = GetGuildUID()
	if gidActive and gidActive ~= "" and IsUIDRaidLeaderFlagged(gidActive, myUID) then
		return true
	end
	local gidDB = DB and DB.GetGuildUID and DB:GetGuildUID() or nil
	if gidDB and gidDB ~= "" and gidDB ~= gidActive and IsUIDRaidLeaderFlagged(gidDB, myUID) then
		return true
	end
	return IsUIDRaidLeaderFlaggedAnywhere(myUID)
end

function Rosteur.ShouldShowSignupTab(guildUID)
	local r = Rosteur.GetState(guildUID)
	if not r then
		return false
	end
	local phase = tostring(r.phase or "idle")
	if phase == "prep" or phase == "locked" then
		return true
	end
	if phase == "config" then
		local startedAt = tonumber(r.prep and r.prep.startedAt or 0) or 0
		return startedAt > 0
	end
	return false
end

function Rosteur.GetSignupCounts(rosteur)
	local out = { TANK = 0, HEAL = 0, DPS = 0 }
	local r = rosteur
	if not r then
		return out
	end
	local signups = r.prep and r.prep.signups or nil
	if type(signups) ~= "table" then
		return out
	end
	for _, v in pairs(signups) do
		local roles = GetSignupRoles(v)
		for role in pairs(roles) do
			out[role] = (out[role] or 0) + 1
		end
	end
	return out
end

function Rosteur.GetSignup(rosteur, full)
	if not rosteur or not full then
		return nil
	end
	local signups = rosteur.prep and rosteur.prep.signups
	if type(signups) ~= "table" then
		return nil
	end
	return signups[full]
end

function Rosteur.StartPreparation(guildUID, seasonName)
	local gid = guildUID or GetGuildUID()
	if not gid then
		return false
	end
	local r = EnsureRosteur(gid)
	r.phase = "prep"
	r.seasonName = seasonName or ""
	r.prep = {
		startedAt = Now(),
		startedByUID = GetMyUID(),
		signups = {},
	}
	r.rosters = {}
	r.activeRosterId = nil
	r.lockedAt = nil
	r.lockedByUID = nil
	Touch(gid, r)
	return true
end

function Rosteur.StartConfig(guildUID)
	local gid = guildUID or GetGuildUID()
	if not gid then
		return false
	end
	if not Rosteur.ShouldShowManagerTab() then
		return false
	end
	local r = EnsureRosteur(gid)
	if r.phase ~= "prep" then
		return false
	end
	r.phase = "config"
	if not r.activeRosterId then
		Rosteur.CreateRoster(gid, "raid20")
	else
		Touch(gid, r)
	end
	return true
end

function Rosteur.SetActiveRoster(guildUID, rosterId)
	local gid = guildUID or GetGuildUID()
	if not gid or not rosterId then
		return false
	end
	local r = EnsureRosteur(gid)
	local roster = FindRoster(r, rosterId)
	if not roster then
		return false
	end
	r.activeRosterId = rosterId
	Touch(gid, r)
	return true
end

function Rosteur.CreateRoster(guildUID, templateKey, name, customTargets)
	local gid = guildUID or GetGuildUID()
	if not gid then
		return false
	end
	local r = EnsureRosteur(gid)
	local tpl = TEMPLATES[templateKey or ""] or TEMPLATES.raid20
	local rosterId = NewId("rosteur_")
	local index = #r.rosters + 1
	local rosterName = name or (tpl.name .. " \226\128\162" .. tostring(index))
	local targets = CopyTargets(tpl.targets) or { TANK = 2, HEAL = 0, DPS = 0 }
	local key = tostring(templateKey or "")
	if type(customTargets) == "table" then
		targets.TANK = 2
		targets.HEAL = math.max(0, math.floor(tonumber(customTargets.HEAL or targets.HEAL or 0) or 0))
		targets.DPS = math.max(0, math.floor(tonumber(customTargets.DPS or targets.DPS or 0) or 0))
		if key ~= "" then
			r.createTargetsByTemplate = r.createTargetsByTemplate or {}
			r.createTargetsByTemplate[key] = { TANK = 2, HEAL = targets.HEAL, DPS = targets.DPS }
		end
	end
	local roster = {
		id = rosterId,
		name = rosterName,
		createdAt = Now(),
		createdByUID = GetMyUID(),
		targets = targets,
		groups = { TANK = {}, HEAL = {}, DPS = {} },
	}
	r.rosters[#r.rosters + 1] = roster
	r.activeRosterId = rosterId
	Touch(gid, r)
	return rosterId
end

function Rosteur.GetCreateTargets(guildUID, templateKey)
	local gid = guildUID or GetGuildUID()
	local key = tostring(templateKey or "")
	if not gid or key == "" then
		return nil
	end
	local r = EnsureRosteur(gid)
	local t = r and r.createTargetsByTemplate and r.createTargetsByTemplate[key] or nil
	if type(t) ~= "table" then
		return nil
	end
	return {
		TANK = 2,
		HEAL = math.max(0, math.floor(tonumber(t.HEAL or 0) or 0)),
		DPS = math.max(0, math.floor(tonumber(t.DPS or 0) or 0)),
	}
end

function Rosteur.CreateRandomRosterFromGuild(guildUID, templateKey, rosterName)
	local gid = guildUID or GetGuildUID()
	if not gid then
		return false, "noguild"
	end
	if not (ns.DB and ns.DB.GetGuildPlayers) then
		return false, "nodata"
	end
	local players = ns.DB:GetGuildPlayers(gid)
	if type(players) ~= "table" then
		return false, "nodata"
	end

	local entries = {}
	local seen = {}
	for uid, p in pairs(players) do
		local heroFull = p and p.mainFull or nil
		if (not heroFull or heroFull == "") and ns.DB and ns.DB.GetGuildPlayerMain then
			heroFull = ns.DB:GetGuildPlayerMain(gid, uid)
		end
		if not heroFull or heroFull == "" then
			heroFull = nil
		end
		local heroName = heroFull
		if heroName and Utils and Utils.BaseName then
			heroName = Utils.BaseName(heroName)
		end
		local chars = p and p.characters or nil
		if type(chars) == "table" then
			for full, c in pairs(chars) do
				local f = (type(c) == "table" and c.full) or full
				if f and f ~= "" and not seen[f] then
					seen[f] = true
					local name = type(c) == "table" and c.name or nil
					if (not name or name == "") and Utils and Utils.BaseName then
						name = Utils.BaseName(f)
					end
					entries[#entries + 1] = {
						id = f,
						full = f,
						name = name or f,
						classTag = type(c) == "table" and c.classTag or nil,
						uid = uid,
					}
				end
			end
		end
	end
	if #entries == 0 then
		return false, "empty"
	end

	local r = EnsureRosteur(gid)
	r.phase = "config"
	r.prep = r.prep or { signups = {} }
	r.prep.signups = r.prep.signups or {}

	local tpl = TEMPLATES[templateKey or ""] or TEMPLATES.raid20
	local rosterId = NewId("rosteur_")
	local index = #r.rosters + 1
	local name = rosterName or (tpl.name .. " #" .. tostring(index))
	local roster = {
		id = rosterId,
		name = name,
		createdAt = Now(),
		createdByUID = GetMyUID(),
		targets = CopyTargets(tpl.targets),
		groups = { TANK = {}, HEAL = {}, DPS = {} },
	}
	r.rosters[#r.rosters + 1] = roster
	r.activeRosterId = rosterId

	local groups = EnsureRosterGroups(roster)
	groups.TANK = {}
	groups.HEAL = {}
	groups.DPS = {}

	ShuffleList(entries)
	local counts = { TANK = 0, HEAL = 0, DPS = 0 }
	local targets = roster.targets or {}
	for _, entry in ipairs(entries) do
		local role = PickRole(counts, targets)
		counts[role] = (counts[role] or 0) + 1
		local id = entry.id or entry.full or NewId("entry_")
		groups[role][#groups[role] + 1] = {
			id = id,
			full = entry.full or entry.name or id,
			name = entry.name or entry.full or id,
			classTag = entry.classTag,
			uid = entry.uid,
		}
	end

	Touch(gid, r)
	return true, #entries, rosterId
end

function Rosteur.CreateRandomSignupsFromGuild(guildUID, templateKey)
	local gid = guildUID or GetGuildUID()
	if not gid then
		return false, "noguild"
	end
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	end
	if Utils and Utils.BuildPseudoCache then
		Utils.BuildPseudoCache()
	end
	local players = (ns.DB and ns.DB.GetGuildPlayers) and ns.DB:GetGuildPlayers(gid) or nil

	local entries = {}
	local seen = {}
	if type(players) == "table" then
		for uid, p in pairs(players) do
			local heroFull = p and p.mainFull or nil
			if (not heroFull or heroFull == "") and ns.DB and ns.DB.GetGuildPlayerMain then
				heroFull = ns.DB:GetGuildPlayerMain(gid, uid)
			end
			if heroFull == "" then
				heroFull = nil
			end
			local heroName = heroFull and GetPseudoAlias(heroFull) or nil
			if (not heroName or heroName == "") and heroFull and Utils and Utils.BaseName then
				heroName = Utils.BaseName(heroFull)
			end
			local chars = p and p.characters or nil
			if type(chars) == "table" then
				for full, c in pairs(chars) do
					local f = (type(c) == "table" and c.full) or full
					if f and f ~= "" and not seen[f] then
						seen[f] = true
						local name = type(c) == "table" and c.name or nil
						if (not name or name == "") and Utils and Utils.BaseName then
							name = Utils.BaseName(f)
						end
						if (not heroFull or heroFull == "") then
							heroFull = f
							if (not heroName or heroName == "") then
								heroName = GetPseudoAlias(heroFull)
								if (not heroName or heroName == "") and Utils and Utils.BaseName then
									heroName = Utils.BaseName(heroFull)
								end
							end
						end
						if (not heroName or heroName == "") and heroFull and Utils and Utils.BaseName then
							heroName = Utils.BaseName(heroFull)
						end
						entries[#entries + 1] = {
							full = f,
							name = name or f,
							classTag = type(c) == "table" and c.classTag or nil,
							spec = type(c) == "table" and c.spec or nil,
							specID = type(c) == "table" and c.specID or nil,
							uid = uid,
							heroFull = heroFull or f,
							heroName = heroName,
							heroKey = NormalizeHeroKey(heroName) or NormalizeHeroKey(uid) or NormalizeHeroKey(heroFull) or NormalizeHeroKey(f),
						}
					end
				end
			end
		end
	end

	if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
		local n = GetNumGuildMembers() or 0
		for i = 1, n do
			local name, _, _, _, _, _, note, _, _, _, classFileName = GetGuildRosterInfo(i)
			if name then
				local full = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name
				if full and full ~= "" and not seen[full] then
					seen[full] = true
					local heroName = (Utils and Utils.AliasFromNote and Utils.AliasFromNote(note)) or nil
					if (not heroName or heroName == "") then
						heroName = GetPseudoAlias(full)
					end
					if (not heroName or heroName == "") and Utils and Utils.BaseName then
						heroName = Utils.BaseName(full)
					end
					local charName = (Ambiguate and Ambiguate(full, "none")) or (Utils and Utils.BaseName and Utils.BaseName(full)) or full
					entries[#entries + 1] = {
						full = full,
						name = charName,
						classTag = classFileName,
						spec = nil,
						specID = nil,
						uid = nil,
						heroFull = full,
						heroName = heroName,
						heroKey = NormalizeHeroKey(heroName) or NormalizeHeroKey(full),
					}
				end
			end
		end
	end
	if #entries == 0 then
		return false, "empty"
	end
	-- Random sample for debug roster generation: keep between 12 and 20 signups.
	local minSignups, maxSignups = 12, 20
	if #entries > 0 then
		ShuffleList(entries)
		local wanted = math.random(minSignups, maxSignups)
		if wanted > #entries then
			wanted = #entries
		end
		for i = #entries, wanted + 1, -1 do
			entries[i] = nil
		end
	end

	Rosteur.StartPreparation(gid)
	local r = EnsureRosteur(gid)
	r.prep = r.prep or { signups = {} }
	r.prep.signups = {}

	local tpl = TEMPLATES[templateKey or ""] or TEMPLATES.raid20
	local counts = { TANK = 0, HEAL = 0, DPS = 0 }
	local targets = tpl.targets or {}

	local heroData = {}
	for _, entry in ipairs(entries) do
		local key = NormalizeHeroKey(entry.heroName) or entry.heroKey or NormalizeHeroKey(entry.uid) or NormalizeHeroKey(entry.heroFull) or NormalizeHeroKey(entry.full)
		local data = heroData[key]
		if not data then
			data = { heroFull = entry.heroFull, heroName = entry.heroName, tankEntries = {} }
			heroData[key] = data
		end
		local allowed = GetAllowedRolesFromMeta(entry)
		if not allowed or allowed.TANK then
			data.tankEntries[#data.tankEntries + 1] = entry
		end
	end

	local tankHeroes = {}
	for key, data in pairs(heroData) do
		if data.tankEntries and data.tankEntries[1] then
			tankHeroes[#tankHeroes + 1] = key
		end
	end
	ShuffleList(tankHeroes)

	local forced = {}
	local forcedCount = 0
	for i = 1, math.min(2, #tankHeroes) do
		local key = tankHeroes[i]
		local data = heroData[key]
		if data then
			local chosen = nil
			if data.heroFull then
				for _, e in ipairs(data.tankEntries) do
					if e.full == data.heroFull then
						chosen = e
						break
					end
				end
			end
			chosen = chosen or data.tankEntries[1]
			if chosen then
				forced[chosen.full] = "TANK"
				forcedCount = forcedCount + 1
			end
		end
	end
	counts.TANK = forcedCount

	ShuffleList(entries)
	for _, entry in ipairs(entries) do
		local role = forced[entry.full]
		if not role then
			local allowed = GetAllowedRolesFromMeta(entry)
			role = PickRoleAllowed(counts, targets, allowed)
			counts[role] = (counts[role] or 0) + 1
		end
		r.prep.signups[entry.full] = {
			full = entry.full,
			name = entry.name,
			classTag = entry.classTag,
			spec = entry.spec,
			specID = entry.specID,
			uid = entry.uid,
			heroFull = entry.heroFull,
			heroName = entry.heroName,
			role = role,
			roles = { [role] = true },
			updatedAt = Now(),
		}
	end

	Touch(gid, r)
	return true, #entries
end

function Rosteur.DeleteRoster(guildUID, rosterId, opts)
	local gid = guildUID or GetGuildUID()
	if not gid then
		return false
	end
	local r = EnsureRosteur(gid)
	local force = opts and opts.force == true
	if r.phase == "locked" and not force then
		return false
	end
	local targetId = rosterId or r.activeRosterId
	if not targetId and type(r.rosters) == "table" and r.rosters[1] then
		targetId = r.rosters[1].id
	end
	if not targetId then
		return false
	end
	local _, idx = FindRoster(r, targetId)
	if not idx then
		return false
	end
	table.remove(r.rosters, idx)
	if type(r.prep) == "table" and type(r.prep.hiddenSignupsByRoster) == "table" then
		r.prep.hiddenSignupsByRoster[tostring(targetId)] = nil
	end
	if r.activeRosterId == targetId then
		local nextRoster = r.rosters[1]
		r.activeRosterId = nextRoster and nextRoster.id or nil
	end
	Touch(gid, r)
	return true
end

function Rosteur.RenameRoster(guildUID, rosterId, newName)
	local gid = guildUID or GetGuildUID()
	if not gid or not rosterId then
		return false
	end
	local name = (Utils and Utils.Trim and Utils.Trim(newName)) or tostring(newName or "")
	if name == "" then
		return false
	end
	local r = EnsureRosteur(gid)
	local roster = FindRoster(r, rosterId)
	if not roster then
		return false
	end
	roster.name = name
	Touch(gid, r)
	return true
end

function Rosteur.SetRosterTargets(guildUID, rosterId, newTargets)
	local gid = guildUID or GetGuildUID()
	if not gid or not rosterId or type(newTargets) ~= "table" then
		return false
	end
	local r = EnsureRosteur(gid)
	local roster = FindRoster(r, rosterId)
	if not roster then
		return false
	end
	roster.targets = roster.targets or {}
	roster.targets.TANK = 2
	roster.targets.HEAL = math.max(0, math.floor(tonumber(newTargets.HEAL or roster.targets.HEAL or 0) or 0))
	roster.targets.DPS = math.max(0, math.floor(tonumber(newTargets.DPS or roster.targets.DPS or 0) or 0))
	Touch(gid, r)
	return true
end

function Rosteur.Reset(guildUID)
	local gid = guildUID or GetGuildUID()
	if not gid then
		return false
	end
	local r = EnsureRosteur(gid)
	r.phase = "idle"
	r.seasonName = ""
	r.prep = { signups = {}, hiddenSignups = {}, hiddenSignupsByRoster = {} }
	r.rosters = {}
	r.activeRosterId = nil
	r.lockedAt = nil
	r.lockedByUID = nil
	Touch(gid, r)
	return true
end

function Rosteur.SetSignup(guildUID, full, role, meta)
	local gid = guildUID or GetGuildUID()
	if not gid or not full then
		return false
	end
	local r = EnsureRosteur(gid)
	if r.phase ~= "prep" then
		return false
	end
	local signups = r.prep and r.prep.signups
	if type(signups) ~= "table" then
		r.prep = r.prep or {}
		r.prep.signups = {}
		signups = r.prep.signups
	end
	local normRole = NormalizeRole(role)
	if not normRole then
		signups[full] = nil
		if type(r.prep.hiddenSignupsByRoster) == "table" then
			for rosterKey, bucket in pairs(r.prep.hiddenSignupsByRoster) do
				if type(bucket) == "table" and bucket[full] then
					bucket[full] = nil
					if next(bucket) == nil then
						r.prep.hiddenSignupsByRoster[rosterKey] = nil
					end
				end
			end
		end
		if type(r.prep.hiddenSignups) == "table" then
			r.prep.hiddenSignups[full] = nil
		end
		Touch(gid, r)
		return true
	end
	local allowed = GetAllowedRolesFromMeta(nil, meta)
	if allowed and next(allowed) and not allowed[normRole] then
		if UIErrorsFrame and UIErrorsFrame.AddMessage then
			UIErrorsFrame:AddMessage("Ce rôle n'est pas disponible pour cette classe/spé.", 1, 0.2, 0.2, 1)
		end
		return false
	end
	local entry = signups[full] or {}
	entry.full = full
	entry.roles = GetSignupRoles(entry)
	entry.roles[normRole] = true
	entry.role = normRole
	if type(meta) == "table" then
		entry.uid = meta.uid or entry.uid
		entry.name = meta.name or entry.name
		entry.classTag = meta.classTag or entry.classTag
		entry.spec = meta.spec or entry.spec
		entry.specID = meta.specID or entry.specID
		entry.heroFull = meta.heroFull or entry.heroFull
		entry.heroName = meta.heroName or entry.heroName
	end
	if not entry.name and Utils and Utils.BaseName then
		entry.name = Utils.BaseName(full)
	end
	entry.updatedAt = Now()
	signups[full] = entry
	Touch(gid, r)
	return true
end

function Rosteur.RemoveSignupRole(guildUID, full, role)
	local gid = guildUID or GetGuildUID()
	if not gid or not full then
		return false
	end
	local normRole = NormalizeRole(role)
	if not normRole then
		return false
	end
	local r = EnsureRosteur(gid)
	if r.phase ~= "prep" then
		return false
	end
	local signups = r.prep and r.prep.signups
	if type(signups) ~= "table" then
		return false
	end
	local entry = signups[full]
	if type(entry) ~= "table" then
		return false
	end
	local roles = GetSignupRoles(entry)
	if not roles[normRole] then
		return false
	end
	roles[normRole] = nil
	if not next(roles) then
		return Rosteur.SetSignup(gid, full, nil)
	end
	entry.roles = roles
	entry.role = GetPrimaryRole(entry)
	entry.updatedAt = Now()
	signups[full] = entry
	Touch(gid, r)
	return true
end

function Rosteur.HasSignupRole(rosteur, full, role)
	if not rosteur or not full then
		return false
	end
	local signup = Rosteur.GetSignup(rosteur, full)
	return SignupHasRole(signup, role)
end

function Rosteur.ClearSignups(guildUID)
	local gid = guildUID or GetGuildUID()
	if not gid then
		return false
	end
	local r = EnsureRosteur(gid)
	r.prep = r.prep or {}
	r.prep.signups = {}
	r.prep.hiddenSignups = {}
	r.prep.hiddenSignupsByRoster = {}
	Touch(gid, r)
	return true
end

local function SignupMatchesCluster(s, fullKey, uidKey, heroFullKey, heroKey)
	if type(s) ~= "table" then
		return false
	end
	if fullKey ~= "" and tostring(s.full or "") == fullKey then
		return true
	end
	if uidKey ~= "" and tostring(s.uid or "") == uidKey then
		return true
	end
	if heroFullKey ~= "" and tostring(s.heroFull or "") == heroFullKey then
		return true
	end
	if heroKey then
		local otherHeroKey = NormalizeHeroKey(s.heroName) or NormalizeHeroKey(s.heroFull)
		if otherHeroKey and otherHeroKey == heroKey then
			return true
		end
	end
	return false
end

local function ResolveHiddenRosterKey(r, entry, rosterId)
	local key = rosterId or (entry and entry.rosterId) or (r and r.activeRosterId)
	key = tostring(key or "")
	if key == "" then
		return nil
	end
	return key
end

function Rosteur.IsSignupHidden(guildUID, rosterId, full)
	local gid = guildUID or GetGuildUID()
	if not gid or not rosterId or not full then
		return false
	end
	local r = EnsureRosteur(gid)
	local prep = r and r.prep
	local byRoster = prep and prep.hiddenSignupsByRoster
	local bucket = type(byRoster) == "table" and byRoster[tostring(rosterId)] or nil
	return type(bucket) == "table" and bucket[full] == true
end

function Rosteur.HideSignupCluster(guildUID, entry, rosterId)
	local gid = guildUID or GetGuildUID()
	if not gid or type(entry) ~= "table" then
		return 0
	end
	local r = EnsureRosteur(gid)
	local prep = r and r.prep
	local signups = prep and prep.signups
	if type(signups) ~= "table" then
		return 0
	end
	local hiddenKey = ResolveHiddenRosterKey(r, entry, rosterId)
	if not hiddenKey then
		return 0
	end
	prep.hiddenSignupsByRoster = prep.hiddenSignupsByRoster or {}
	local byRoster = prep.hiddenSignupsByRoster
	local hidden = byRoster[hiddenKey]
	if type(hidden) ~= "table" then
		hidden = {}
		byRoster[hiddenKey] = hidden
	end

	local byFull = tostring(entry.full or entry.id or "")
	local byUID = tostring(entry.uid or "")
	local byHeroFull = tostring(entry.heroFull or "")
	local byHeroKey = NormalizeHeroKey(entry.heroName) or NormalizeHeroKey(entry.heroFull)
	local removed = 0

	for full, s in pairs(signups) do
		if SignupMatchesCluster(s, byFull, byUID, byHeroFull, byHeroKey) then
			if hidden[full] ~= true then
				hidden[full] = true
				removed = removed + 1
			end
		end
	end

	if removed > 0 then
		Touch(gid, r)
	end
	return removed
end

function Rosteur.RestoreSignupCluster(guildUID, entry, rosterId)
	local gid = guildUID or GetGuildUID()
	if not gid or type(entry) ~= "table" then
		return 0
	end
	local r = EnsureRosteur(gid)
	local prep = r and r.prep
	local signups = prep and prep.signups
	if type(signups) ~= "table" then
		return 0
	end
	local hiddenKey = ResolveHiddenRosterKey(r, entry, rosterId)
	if not hiddenKey then
		return 0
	end
	local byRoster = prep and prep.hiddenSignupsByRoster
	local hidden = type(byRoster) == "table" and byRoster[hiddenKey] or nil
	local legacyHidden = prep and prep.hiddenSignups
	if type(hidden) ~= "table" and type(legacyHidden) ~= "table" then
		return 0
	end

	local byFull = tostring(entry.full or entry.id or "")
	local byUID = tostring(entry.uid or "")
	local byHeroFull = tostring(entry.heroFull or "")
	local byHeroKey = NormalizeHeroKey(entry.heroName) or NormalizeHeroKey(entry.heroFull)
	local restored = 0

	if type(hidden) == "table" then
		for full, isHidden in pairs(hidden) do
			if isHidden then
				local s = signups[full] or (type(legacyHidden) == "table" and legacyHidden[full]) or nil
				if SignupMatchesCluster(s, byFull, byUID, byHeroFull, byHeroKey) then
					hidden[full] = nil
					restored = restored + 1
				end
			end
		end
		if next(hidden) == nil and type(byRoster) == "table" then
			byRoster[hiddenKey] = nil
		end
	end

	-- Backward compatibility for states where signups were moved out.
	if type(legacyHidden) == "table" then
		for full, s in pairs(legacyHidden) do
			if SignupMatchesCluster(s, byFull, byUID, byHeroFull, byHeroKey) then
				if not signups[full] then
					signups[full] = s
				end
				legacyHidden[full] = nil
				restored = restored + 1
			end
		end
	end

	if restored > 0 then
		Touch(gid, r)
	end
	return restored
end

function Rosteur.ClearSignupCluster(guildUID, entry, rosterId)
	return Rosteur.HideSignupCluster(guildUID, entry, rosterId)
end

function Rosteur.AssignEntry(guildUID, rosterId, role, entry, slotIndex)
	local gid = guildUID or GetGuildUID()
	if not gid or not rosterId or not entry then
		return false
	end
	local r = EnsureRosteur(gid)
	local roster = FindRoster(r, rosterId)
	if not roster then
		return false
	end
	local normRole = NormalizeRole(role)
	if not normRole then
		return false
	end
	local id = entry.id or entry.full or NewId("entry_")
	RemoveEntryFromRoster(roster, id)
	local out = {
		id = id,
		full = entry.full or entry.name or id,
		name = entry.name or entry.full or id,
		classTag = entry.classTag,
		uid = entry.uid,
		heroFull = entry.heroFull,
		heroName = entry.heroName,
		requestedRole = NormalizeRole(entry.requestedRole or entry.role),
		isPU = entry.isPU and true or false,
	}
	local groups = EnsureRosterGroups(roster)
	local list = groups[normRole]
	local idx = tonumber(slotIndex)
	local maxTarget = tonumber(roster.targets and roster.targets[normRole] or 0) or 0
	if normRole == "TANK" and maxTarget <= 0 then
		maxTarget = 2
	end
	if idx then
		idx = math.floor(idx)
		if idx < 1 then
			idx = 1
		end
		if maxTarget > 0 and idx > maxTarget then
			idx = maxTarget
		end
		list[idx] = out
	else
		local place = 1
		if maxTarget > 0 then
			while place <= maxTarget and list[place] ~= nil do
				place = place + 1
			end
			if place > maxTarget then
				return false
			end
		else
			local highest = 0
			for k in pairs(list) do
				if type(k) == "number" and k > highest then
					highest = k
				end
			end
			place = highest + 1
		end
		list[place] = out
	end
	Touch(gid, r)
	return true
end

function Rosteur.UnassignEntry(guildUID, rosterId, entryId)
	local gid = guildUID or GetGuildUID()
	if not gid or not rosterId or not entryId then
		return false
	end
	local r = EnsureRosteur(gid)
	local roster = FindRoster(r, rosterId)
	if not roster then
		return false
	end
	RemoveEntryFromRoster(roster, entryId)
	Touch(gid, r)
	return true
end

function Rosteur.AddPU(guildUID, rosterId, role, name)
	local gid = guildUID or GetGuildUID()
	if not gid or not rosterId or not name or name == "" then
		return false
	end
	local entry = { id = NewId("pu_"), name = name, full = name, isPU = true }
	return Rosteur.AssignEntry(gid, rosterId, role, entry)
end

function Rosteur.ValidateRoster(guildUID, rosterId)
	local gid = guildUID or GetGuildUID()
	if not gid then
		return false
	end
	local r = EnsureRosteur(gid)
	if r.phase ~= "config" then
		return false
	end
	local targetId = rosterId or r.activeRosterId
	if not targetId then
		return false
	end
	r.phase = "locked"
	r.activeRosterId = targetId
	r.lockedAt = Now()
	r.lockedByUID = GetMyUID()
	Touch(gid, r)
	return true
end

function Rosteur.NormalizeState(data)
	local out = {
		version = tonumber(data and data.version or 1) or 1,
		phase = tostring(data and data.phase or "idle"),
		updatedAt = tonumber(data and data.updatedAt or 0) or 0,
		seasonName = tostring(data and data.seasonName or ""),
		prep = { signups = {} },
		rosters = {},
		activeRosterId = data and data.activeRosterId or nil,
		lockedAt = tonumber(data and data.lockedAt or 0) or 0,
		lockedByUID = data and data.lockedByUID or nil,
		createTargetsByTemplate = {},
	}
	if type(data) == "table" then
		out.createTargetsByTemplate = NormalizeCreateTargets(data.createTargetsByTemplate) or {}
	end
	if type(data) == "table" and type(data.prep) == "table" then
		out.prep.startedAt = tonumber(data.prep.startedAt or 0) or 0
		out.prep.startedByUID = data.prep.startedByUID
		if type(data.prep.signups) == "table" then
			for full, v in pairs(data.prep.signups) do
				if type(v) == "table" then
					local roles = NormalizeRoles(v.roles, v.role)
					local primary = NormalizeRole(v.role)
					if not primary then
						for _, key in ipairs({ "TANK", "HEAL", "DPS" }) do
							if roles[key] then
								primary = key
								break
							end
						end
					end
					out.prep.signups[full] = {
						full = v.full or full,
						role = primary,
						roles = roles,
						uid = v.uid,
						name = v.name,
						classTag = v.classTag,
						spec = v.spec,
						specID = v.specID,
						heroFull = v.heroFull,
						heroName = v.heroName,
						updatedAt = tonumber(v.updatedAt or 0) or 0,
					}
				end
			end
		end
		if type(data.prep.hiddenSignups) == "table" then
			out.prep.hiddenSignups = {}
			for full, v in pairs(data.prep.hiddenSignups) do
				if type(v) == "table" then
					local roles = NormalizeRoles(v.roles, v.role)
					local primary = NormalizeRole(v.role)
					if not primary then
						for _, key in ipairs({ "TANK", "HEAL", "DPS" }) do
							if roles[key] then
								primary = key
								break
							end
						end
					end
					out.prep.hiddenSignups[full] = {
						full = v.full or full,
						role = primary,
						roles = roles,
						uid = v.uid,
						name = v.name,
						classTag = v.classTag,
						spec = v.spec,
						specID = v.specID,
						heroFull = v.heroFull,
						heroName = v.heroName,
						updatedAt = tonumber(v.updatedAt or 0) or 0,
					}
				end
			end
		end
		if type(data.prep.hiddenSignupsByRoster) == "table" then
			out.prep.hiddenSignupsByRoster = {}
			for rosterKey, bucket in pairs(data.prep.hiddenSignupsByRoster) do
				if type(bucket) == "table" then
					local outBucket = {}
					for full, isHidden in pairs(bucket) do
						outBucket[full] = isHidden == true
					end
					out.prep.hiddenSignupsByRoster[tostring(rosterKey)] = outBucket
				end
			end
		end
	end
	if type(data) == "table" and type(data.rosters) == "table" then
		for i = 1, #data.rosters do
			local r = data.rosters[i]
			if type(r) == "table" then
				local roster = {
					id = r.id or NewId("rosteur_"),
					name = r.name or ("Rosteur #" .. tostring(i)),
					createdAt = tonumber(r.createdAt or 0) or 0,
					createdByUID = r.createdByUID,
					targets = CopyTargets(r.targets),
					groups = { TANK = {}, HEAL = {}, DPS = {} },
				}
				if type(r.groups) == "table" then
					for _, role in ipairs({ "TANK", "HEAL", "DPS" }) do
						local list = r.groups[role]
						if type(list) == "table" then
							for j = 1, #list do
								local e = list[j]
								if type(e) == "table" then
									roster.groups[role][#roster.groups[role] + 1] = {
										id = e.id or e.full or NewId("entry_"),
										full = e.full or e.name or e.id,
										name = e.name or e.full or e.id,
										classTag = e.classTag,
										uid = e.uid,
										requestedRole = NormalizeRole(e.requestedRole or e.role),
										isPU = e.isPU and true or false,
									}
								end
							end
						end
					end
				end
				out.rosters[#out.rosters + 1] = roster
			end
		end
	end
	return out
end

function Rosteur.ApplyRemote(guildUID, data, ts, sender)
	local gid = guildUID or GetGuildUID()
	if not gid or type(data) ~= "table" then
		return false
	end
	local r = EnsureRosteur(gid)
	local incomingAt = tonumber(ts or data.updatedAt or 0) or 0
	local existingAt = tonumber(r.updatedAt or 0) or 0
	if incomingAt > 0 and existingAt > incomingAt then
		return false
	end
	local normalized = Rosteur.NormalizeState(data)
	normalized.updatedAt = incomingAt > 0 and incomingAt or normalized.updatedAt
	if tostring(r.phase or "") == "prep" and tostring(normalized.phase or "") == "prep" then
		normalized = MergePrepSignups(r, normalized)
		normalized.updatedAt = math.max(existingAt, incomingAt, tonumber(normalized.updatedAt or 0) or 0)
	end
	local g = EnsureGuildRoot(gid)
	g.guildShared.rosteur = normalized
	Notify(gid, normalized, { announce = false, sender = sender })
	return true
end

return Rosteur
