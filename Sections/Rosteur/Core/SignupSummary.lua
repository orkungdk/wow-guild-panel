local ADDON, ns = ...

ns.RosteurSectionSignupSummary = ns.RosteurSectionSignupSummary or {}
local SignupSummary = ns.RosteurSectionSignupSummary

function SignupSummary.Build(ctx)
	local Rosteur = ctx and ctx.Rosteur or nil
	local DB = ctx and ctx.DB or nil
	local Utils = ctx and ctx.Utils or nil
	local ROLE_ORDER = (ctx and ctx.ROLE_ORDER) or { "TANK", "HEAL", "DPS" }
	local NormalizeRoleTag = ctx and ctx.NormalizeRoleTag or function(role)
		role = tostring(role or ""):upper()
		if role == "TANK" or role == "HEAL" or role == "DPS" then
			return role
		end
		return nil
	end
	local NormalizeHeroKey = ctx and ctx.NormalizeHeroKey or function(v)
		v = tostring(v or "")
		v = v:gsub("^%s+", ""):gsub("%s+$", ""):lower()
		if v == "" then
			return nil
		end
		return v
	end
	local GetGuildUID = ctx and ctx.GetGuildUID or function()
		return nil
	end
	local GetPseudoAlias = ctx and ctx.GetPseudoAlias or function()
		return nil
	end
	local function GetSignupRoles(entry)
		local roles = {}
		if type(entry) == "table" and type(entry.roles) == "table" then
			for k, v in pairs(entry.roles) do
				local role = NormalizeRoleTag(k)
				if role and v then
					roles[role] = true
				end
			end
		end
		local fallback = NormalizeRoleTag(type(entry) == "table" and entry.role or nil)
		if fallback then
			roles[fallback] = true
		end
		return roles
	end

	local function IsSignupVisibleForActiveRoster(rosteur, signup)
		if type(signup) ~= "table" then
			return false
		end
		local activeRosterId = rosteur and rosteur.activeRosterId or nil
		local full = signup.full
		if not (activeRosterId and full and Rosteur and Rosteur.IsSignupHidden) then
			return true
		end
		local gid = GetGuildUID()
		if not gid then
			return true
		end
		return not Rosteur.IsSignupHidden(gid, activeRosterId, full)
	end

	local function BuildRoleHeroSummary(rosteur, opts)
		local out = {
			TANK = { heroes = {}, order = {} },
			HEAL = { heroes = {}, order = {} },
			DPS = { heroes = {}, order = {} },
		}

		local signups = rosteur and rosteur.prep and rosteur.prep.signups or nil
		if type(signups) == "table" then
			for _, v in pairs(signups) do
				if type(v) == "table" then
					local allowed = true
					if opts and opts.onlyVisibleForActive then
						local visibleFn = (opts and opts.isVisibleFn) or IsSignupVisibleForActiveRoster
						allowed = visibleFn(rosteur, v)
					end
					if allowed then
						local signupRoles = GetSignupRoles(v)
						for role in pairs(signupRoles) do
							if role and out[role] then
								local data = out[role]
								local heroFull = v.heroFull or ""
								local heroName = v.heroName or ""
								if heroFull == "" and v.uid and DB and DB.GetGuildPlayerMain then
									heroFull = DB:GetGuildPlayerMain(GetGuildUID(), v.uid) or ""
								end
								if heroName == "" and heroFull ~= "" then
									heroName = GetPseudoAlias(heroFull)
								end
								if heroName == "" then
									heroName = v.name or v.full or ""
								end
								if heroName == "" and heroFull ~= "" and Utils and Utils.BaseName then
									heroName = Utils.BaseName(heroFull)
								end
								local heroKey = NormalizeHeroKey(heroName)
								if not heroKey then
									heroKey = NormalizeHeroKey(v.uid)
								end
								if not heroKey then
									heroKey = NormalizeHeroKey(heroFull)
								end
								if not heroKey then
									heroKey = NormalizeHeroKey(v.full) or tostring(math.random())
								end
								local hero = data.heroes[heroKey]
								if not hero then
									hero = { heroFull = heroFull, heroName = heroName, entries = {} }
									data.heroes[heroKey] = hero
									data.order[#data.order + 1] = heroKey
								end
								hero.entries[#hero.entries + 1] = v
							end
						end
					end
				end
			end
		end

		for _, role in ipairs(ROLE_ORDER) do
			local data = out[role]
			if data and data.order then
				table.sort(data.order, function(a, b)
					local ha = data.heroes[a]
					local hb = data.heroes[b]
					return tostring(ha and ha.heroName or "") < tostring(hb and hb.heroName or "")
				end)
				for _, heroKey in ipairs(data.order) do
					local hero = data.heroes[heroKey]
					if hero and hero.entries then
						table.sort(hero.entries, function(a, b)
							return tostring(a.name or a.full or "") < tostring(b.name or b.full or "")
						end)
					end
				end
			end
		end

		return out
	end

	return {
		IsSignupVisibleForActiveRoster = IsSignupVisibleForActiveRoster,
		BuildRoleHeroSummary = BuildRoleHeroSummary,
	}
end
