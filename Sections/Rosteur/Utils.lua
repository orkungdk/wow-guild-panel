local ADDON, ns = ...

local M = ns.RosteurSection

function M.SetupUtils(ctx)
	local ns = ctx.ns
	local Utils = ctx.Utils
	local DB = ctx.DB
	local const = ctx.const
	local fn = ctx.fn
	local state = ctx.state

	local dragState = state.dragState or { data = nil }
	state.dragState = dragState

	local function TrimSpaces(value)
		local s = tostring(value or "")
		return (s:gsub("^%s+", ""):gsub("%s+$", ""))
	end

	local function Now()
		if time then
			return time()
		end
		return 0
	end

	local function IsPrepConfigLocked(rosteur)
		if not rosteur or rosteur.phase ~= "prep" then
			return false
		end
		local startedAt = rosteur and rosteur.prep and tonumber(rosteur.prep.startedAt) or nil
		if not startedAt or startedAt <= 0 then
			startedAt = tonumber(rosteur and rosteur.updatedAt) or 0
		end
		local now = Now()
		local unlockAt = startedAt + const.PREP_CONFIG_MIN_WAIT_SECONDS
		local remaining = unlockAt - now
		if remaining <= 0 then
			return false, 0
		end
		if IsShiftKeyDown and IsShiftKeyDown() then
			return false, remaining
		end
		return true, remaining
	end

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

	local function GetGuildUID()
		if Utils and Utils.GetActiveGuildUID then
			return Utils.GetActiveGuildUID()
		end
		if DB and DB.GetGuildUID then
			return DB:GetGuildUID()
		end
		return nil
	end

	local function GetMyFull()
		local name, realm = UnitFullName and UnitFullName("player") or nil
		if not name or name == "" then
			return nil
		end
		realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
		return name .. "-" .. realm
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

	local function GetMySignupMeta(gid)
		local meta = {}
		local uid = DB and DB.GetMyUID and DB:GetMyUID() or nil
		if uid and uid ~= "" then
			meta.uid = uid
		end
		local full = ""
		if DB and DB.GetGuildPlayerMain and uid then
			full = DB:GetGuildPlayerMain(gid, uid) or ""
		end
		if full == "" then
			full = GetMyFull() or ""
		end
		local p = (gid and uid and DB and DB.GetGuildPlayer) and DB:GetGuildPlayer(gid, uid) or nil
		local c = p and p.characters and p.characters[full] or nil
		if not c and p and p.characters then
			local fallbackFull = GetMyFull()
			if fallbackFull and p.characters[fallbackFull] then
				c = p.characters[fallbackFull]
				full = fallbackFull
			end
		end
		if c then
			meta.name = c.name or meta.name
			meta.classTag = c.classTag or meta.classTag
			meta.spec = c.spec or meta.spec
			meta.specID = c.specID or meta.specID
		end
		local heroFull = ""
		if gid and uid and DB and DB.GetGuildPlayerMain then
			heroFull = DB:GetGuildPlayerMain(gid, uid) or ""
		end
		if heroFull == "" then
			heroFull = full or ""
		end
		if heroFull ~= "" then
			meta.heroFull = heroFull
			meta.heroName = GetPseudoAlias(heroFull)
			if (not meta.heroName or meta.heroName == "") and Utils and Utils.BaseName then
				meta.heroName = Utils.BaseName(heroFull)
			end
		end
		if (not meta.name or meta.name == "") and Utils and Utils.BaseName and full ~= "" then
			meta.name = Utils.BaseName(full)
		end
		return full, meta
	end

	local function StartDrag(data)
		dragState.data = data
	end

	local function StopDrag()
		dragState.data = nil
	end

	local function GetDrag()
		return dragState.data
	end

	local function ColorizeName(name, classTag)
		if Utils and Utils.ColorizeByClassTag and classTag and classTag ~= "" then
			return Utils.ColorizeByClassTag(name, classTag)
		end
		return tostring(name or "-")
	end

	local function IsMyRaidLeaderIdentity(gid, raidLeaderUID)
		local rl = tostring(raidLeaderUID or "")
		if rl == "" then
			return false
		end
		local myUID = DB and DB.GetMyUID and DB:GetMyUID() or nil
		if myUID and myUID ~= "" and rl == myUID then
			return true
		end
		if rl:sub(1, 7) == "pseudo:" then
			local full = GetMyFull()
			local alias = full and GetPseudoAlias(full) or nil
			if (not alias or alias == "") and gid and myUID and DB and DB.GetGuildPlayerMain then
				local heroFull = DB:GetGuildPlayerMain(gid, myUID)
				if heroFull and heroFull ~= "" then
					alias = GetPseudoAlias(heroFull)
				end
			end
			if alias and alias ~= "" and Utils and Utils.PseudoKey then
				return rl == ("pseudo:" .. Utils.PseudoKey(alias))
			end
		end
		return false
	end

	local function NormalizeHeroKey(value)
		local v = tostring(value or "")
		v = v:gsub("^%s+", ""):gsub("%s+$", ""):lower()
		if v == "" then
			return nil
		end
		return v
	end

	local function NormalizeRoleTag(role)
		role = tostring(role or ""):upper()
		if role == "TANK" or role == "HEAL" or role == "DPS" then
			return role
		end
		return nil
	end

	fn.TrimSpaces = TrimSpaces
	fn.Now = Now
	fn.IsPrepConfigLocked = IsPrepConfigLocked
	fn.IsDevMode = IsDevMode
	fn.GetGuildUID = GetGuildUID
	fn.GetMyFull = GetMyFull
	fn.GetMySignupMeta = GetMySignupMeta
	fn.StartDrag = StartDrag
	fn.StopDrag = StopDrag
	fn.GetDrag = GetDrag
	fn.ColorizeName = ColorizeName
	fn.GetPseudoAlias = GetPseudoAlias
	fn.IsMyRaidLeaderIdentity = IsMyRaidLeaderIdentity
	fn.NormalizeHeroKey = NormalizeHeroKey
	fn.NormalizeRoleTag = NormalizeRoleTag
end

return M
