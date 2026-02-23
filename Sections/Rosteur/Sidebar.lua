local ADDON, ns = ...

local M = ns.RosteurSection

function M.BuildSidebar(ctx)
	local ns = ctx.ns
	local Rosteur = ctx.Rosteur
	local const = ctx.const
	local ui = ctx.ui
	local state = ctx.state
	local fn = ctx.fn

	local ROLE_ORDER = const.ROLE_ORDER
	local ROLE_LABEL = const.ROLE_LABEL
	local ROLE_ATLAS = const.ROLE_ATLAS

	local sideArea = ui.sideArea
	if not sideArea then
		return
	end

	if ui.sideInfo then
		ui.sideInfo:Hide()
	end
	if ui.sideHint then
		ui.sideHint:Hide()
	end

	if ui.devToggle then
		ui.devToggle:ClearAllPoints()
		ui.devToggle:SetPoint("BOTTOM", sideArea, "BOTTOM", 0, 12)
	end
	if ui.devDelete then
		ui.devDelete:ClearAllPoints()
		ui.devDelete:SetPoint("BOTTOM", sideArea, "BOTTOM", 0, 38)
	end

	local scroll = CreateFrame("ScrollFrame", "WoWGuilde_Rosteur_SideScroll", sideArea, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", sideArea, "TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", sideArea, "BOTTOMRIGHT", -24, 60)

	do
		local sb = scroll.ScrollBar or _G[scroll:GetName() .. "ScrollBar"]
		if sb then
			sb:Show()
			sb:SetAlpha(0.6)
		end
	end

	local content = CreateFrame("Frame", "WoWGuilde_Rosteur_SideContent", scroll)
	content:SetPoint("TOPLEFT")
	content:SetPoint("TOPRIGHT")
	content:SetWidth(1)
	content:SetHeight(1)
	scroll:SetScrollChild(content)

	local sidebar = {
		scroll = scroll,
		content = content,
		sections = {},
	}
	ui.sidebar = sidebar

	local function MakeHeroSection(heroKey, hero)
		local section = CreateFrame("Frame", nil, content)
		section.heroKey = heroKey
		section.hero = hero

		section.header = CreateFrame("Button", nil, section)
		section.header:SetHeight(24)
		section.header:SetPoint("TOPLEFT")
		section.header:SetPoint("TOPRIGHT")

		section.header.text = section.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		section.header.text:SetPoint("LEFT", 8, 0)
		section.header.text:SetJustifyH("LEFT")
		section.header.text:SetText(hero.heroName or hero.heroFull or "Héro")

		section.body = CreateFrame("Frame", nil, section)
		section.body:SetPoint("TOPLEFT", section.header, "BOTTOMLEFT", 0, -4)
		section.body:SetPoint("TOPRIGHT", section.header, "BOTTOMRIGHT", 0, -4)
		section.body:SetHeight(1)

		section.items = {}
		local y = 0
		if hero.entries then
			for i = 1, #hero.entries do
				local entry = hero.entries[i]
				local btn = CreateFrame("Button", nil, section.body)
				btn:SetHeight(20)
				btn:SetPoint("TOPLEFT", section.body, "TOPLEFT", 12, -y)
				btn:SetPoint("TOPRIGHT", section.body, "TOPRIGHT", -6, -y)
				btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				btn.text:SetPoint("LEFT", 2, 0)
				btn.text:SetPoint("RIGHT", -2, 0)
				btn.text:SetJustifyH("LEFT")
				local nameText = fn.ColorizeName and fn.ColorizeName(entry.name or entry.full or "-", entry.classTag)
					or tostring(entry.name or entry.full or "-")
				btn.text:SetText(nameText)
				btn.data = entry
				section.items[#section.items + 1] = btn
				y = y + 20 + 4
			end
		end
		if y > 0 then
			y = y - 4
		end
		section.body:SetHeight(math.max(1, y))

		section:SetHeight(24 + 4 + section.body:GetHeight())
		return section
	end

	local function LayoutSidebar()
		local y = 0
		for _, role in ipairs(ROLE_ORDER) do
			local sec = sidebar.sections[role]
			if sec then
				sec:ClearAllPoints()
				sec:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
				sec:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
				local h = sec:GetHeight() or 1
				y = y + h + 10
			end
		end
		if y > 0 then
			y = y - 10
		end
		content:SetHeight(math.max(1, y))
	end

	local function ClearSidebar()
		for _, role in ipairs(ROLE_ORDER) do
			local sec = sidebar.sections[role]
			if sec then
				sec:Hide()
				sec:SetParent(nil)
				sidebar.sections[role] = nil
			end
		end
		content:SetHeight(1)
	end

	local function BuildRoleSection(role, data)
		local prefix = "WoWGuilde_Rosteur_SideRole_" .. role
		local sec = CreateFrame("Frame", prefix, content)
		sec.role = role

		sec.header = CreateFrame("Button", prefix .. "_Header", sec)
		sec.header:SetHeight(28)
		sec.header:SetPoint("TOPLEFT")
		sec.header:SetPoint("TOPRIGHT")

		sec.header.icon = sec.header:CreateTexture(prefix .. "_Icon", "ARTWORK")
		sec.header.icon:SetSize(16, 16)
		sec.header.icon:SetPoint("LEFT", 6, 0)
		if ROLE_ATLAS and ROLE_ATLAS[role] then
			sec.header.icon:SetAtlas(ROLE_ATLAS[role], true)
		end

		sec.header.text = sec.header:CreateFontString(prefix .. "_Text", "OVERLAY", "GameFontNormal")
		sec.header.text:SetPoint("LEFT", sec.header.icon, "RIGHT", 6, 0)
		sec.header.text:SetJustifyH("LEFT")
		sec.header.text:SetText(ROLE_LABEL[role] or role)

		sec.header:SetScript("OnClick", function()
			state.sidebarCollapsed[role] = not state.sidebarCollapsed[role]
			if sidebar.Refresh then
				sidebar.Refresh()
			end
		end)

		sec.body = CreateFrame("Frame", prefix .. "_Body", sec)
		sec.body:SetPoint("TOPLEFT", sec.header, "BOTTOMLEFT", 0, -4)
		sec.body:SetPoint("TOPRIGHT", sec.header, "BOTTOMRIGHT", 0, -4)
		sec.body:SetHeight(1)

		sec.heroSections = {}
		local y = 0
		if data and data.order and data.heroes then
			for _, heroKey in ipairs(data.order) do
				local hero = data.heroes[heroKey]
				if hero then
					local hsec = MakeHeroSection(heroKey, hero)
					hsec:SetParent(sec.body)
					hsec:ClearAllPoints()
					hsec:SetPoint("TOPLEFT", sec.body, "TOPLEFT", 0, -y)
					hsec:SetPoint("TOPRIGHT", sec.body, "TOPRIGHT", 0, -y)
					sec.heroSections[#sec.heroSections + 1] = hsec
					y = y + (hsec:GetHeight() or 1) + 6
				end
			end
		end
		if y > 0 then
			y = y - 6
		end
		sec.body:SetHeight(math.max(1, y))

		local bodyVisible = not state.sidebarCollapsed[role]
		sec.body:SetShown(bodyVisible)
		local totalH = 28 + (bodyVisible and (4 + sec.body:GetHeight()) or 0)
		sec:SetHeight(totalH)

		return sec
	end

	function sidebar.Refresh()
		ClearSidebar()
		local rosteur = sidebar._rosteur
		local prep = rosteur and rosteur.prep or nil
		if not prep then
			LayoutSidebar()
			return
		end

		local dataByRole = {
			TANK = { heroes = {}, order = {} },
			HEAL = { heroes = {}, order = {} },
			DPS = { heroes = {}, order = {} },
		}
		local signups = prep.signups
		if type(signups) == "table" then
			for _, v in pairs(signups) do
				if type(v) == "table" then
					local role = fn.NormalizeRoleTag and fn.NormalizeRoleTag(v.role) or nil
					if role and dataByRole[role] then
						local data = dataByRole[role]
						local heroFull = v.heroFull or ""
						local heroName = v.heroName or ""
						if heroName == "" and heroFull ~= "" and Utils and Utils.BaseName then
							heroName = Utils.BaseName(heroFull)
						end
						local heroKey = fn.NormalizeHeroKey and fn.NormalizeHeroKey(heroName) or nil
						if not heroKey then
							heroKey = fn.NormalizeHeroKey and fn.NormalizeHeroKey(v.uid) or nil
						end
						if not heroKey then
							heroKey = fn.NormalizeHeroKey and fn.NormalizeHeroKey(heroFull) or nil
						end
						if not heroKey then
							heroKey = fn.NormalizeHeroKey and fn.NormalizeHeroKey(v.full) or tostring(math.random())
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

		for _, role in ipairs(ROLE_ORDER) do
			local data = dataByRole[role]
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
			local sec = BuildRoleSection(role, data)
			sidebar.sections[role] = sec
		end

		LayoutSidebar()
	end
end

return M
