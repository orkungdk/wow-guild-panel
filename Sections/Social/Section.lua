-- WoWGuilde/Sections/Social/Section.lua
local ADDON, ns = ...
ns.Sections = ns.Sections or {}
local Sections = ns.Sections

function Sections.Social(parent)
	local f = CreateFrame("Frame", "WoWGuilde_Social", parent)
	f:SetAllPoints(parent)
	f:Hide()
	ns.Sections.SocialFrame = f
	local SU = (ns.Social and ns.Social.Utils) or {}
	local HU = (ns.Heros and ns.Heros.Utils) or nil
	local EventBus = ns.EventBus
	local GP = ns.GuildProgress

	--------------------------------------------------------
	-- Config
	--------------------------------------------------------
	local CFG = {
		ORB_SIZE = 220,
		COHESION = 0,
		MAX_NEWS = 256,
		SPEED_SCALE = 0.35,
		RING_SPIN_SCALE = 1.0,

		SPAWN_INTERVAL_RANGE = { 1.40, 3.20 },
		PEARL_LIFETIME_RANGE = { 22.0, 34.0 },
		BUBBLE_DURATION_RANGE = { 1.60, 3.20 },
		HOVER_RELEASE_COOLDOWN_RANGE = { 0.60, 1.10 },
		PENDING_FADE_JITTER_RANGE = { 0.15, 0.45 },

		FADE_OUT = {
			duration = 0.28,
			startScale = 1.00,
			endScale = 0.82,
			startAlpha = 1.00,
			endAlpha = 0.00,
		},
	}

	-- Anneaux (rayon, vitesse, taille icone, max simultanees)
	local RINGS_CFG = {
		{
			radius = 215,
			baseSpeed = 0.65 * CFG.SPEED_SCALE,
			spinSpeed = 0.32,
			iconSize = 48,
			maxActive = 5,
			alpha = 0.30,
			iconOffsetX = 0,
			iconOffsetY = 0,
			ringOffsetX = 2,
			ringOffsetY = 0,
			extraTexOffsetX = 0,
			extraTexOffsetY = 0,
		},
		{
			radius = 165,
			baseSpeed = -0.95 * CFG.SPEED_SCALE,
			spinSpeed = -0.26,
			iconSize = 26,
			maxActive = 4,
			alpha = 0.40,
			iconOffsetX = 0,
			iconOffsetY = 0,
			ringOffsetX = 0,
			ringOffsetY = 0,
			extraTexOffsetX = 0,
			extraTexOffsetY = 0,
		},
		{
			radius = 115,
			baseSpeed = 0.95 * CFG.SPEED_SCALE,
			spinSpeed = 0.40,
			iconSize = 18,
			maxActive = 18,
			alpha = 1.00,
			iconOffsetX = 0,
			iconOffsetY = 0,
			ringOffsetX = 0,
			ringOffsetY = 0,
			extraTexOffsetX = 0,
			extraTexOffsetY = 0,
		},
	}

	local LIST_CFG = {
		columnWidth = 320,
		columnHeight = 450,
		columnX = -180,
		columnY = -8,
		listFrameRightPad = 4,
		itemHeight = 40,
		itemSpacing = 2,
		iconSize = 35,
		iconPad = 8,
		overlaySize = 54,
		bgLeftPad = 8,
		textLeftPad = 14,
		textRightPad = 20,
		textBottomPad = 10,
		scrollRightPad = 10,
		virtualWindow = 20,
	}

	local CHAT_CFG = {
		width = 595,
		height = 220,
		x = 15,
		y = 15,
		padding = 12,
		titleOffset = 22,
		font = "Fonts\\2002.TTF",
		fontSize = 12,
		fontFlags = "",
		maxLines = 200,
	}

	--------------------------------------------------------
	-- Layout
	--------------------------------------------------------
	local LAYOUT = {
		decor = {
			point = "CENTER",
			relTo = nil,
			relPoint = "CENTER",
			x = 0,
			y = 0,
			w = 1185,
			h = 610,
		},
		origin = { dx = 325, dy = 0 },
		rings = { dx = 0, dy = 0 },
		pearls = { dx = 0, dy = 0 },
	}

	local origin = CreateFrame("Frame", "WoWGuilde_SocialOrigin", nil)
	origin:SetSize(1, 1)

	local groups = {}
	groups.decor = CreateFrame("Frame", "WoWGuilde_SocialDecor", f)
	groups.ring = CreateFrame("Frame", "WoWGuilde_SocialRingGroup", f)
	groups.list = CreateFrame("Frame", "WoWGuilde_SocialListGroup", f)
	groups.ring:SetAllPoints(f)
	groups.list:SetAllPoints(f)
	groups.list:Hide()

	origin:SetParent(groups.ring)

	groups.rings = CreateFrame("Frame", "WoWGuilde_SocialRings", groups.ring)
	groups.pearls = CreateFrame("Frame", "WoWGuilde_SocialPearls", groups.ring)

	local function Layout_Apply()
		LAYOUT.decor.relTo = LAYOUT.decor.relTo or f
		groups.decor:ClearAllPoints()
		groups.decor:SetSize(LAYOUT.decor.w, LAYOUT.decor.h)
		groups.decor:SetPoint(
			LAYOUT.decor.point,
			LAYOUT.decor.relTo,
			LAYOUT.decor.relPoint,
			LAYOUT.decor.x,
			LAYOUT.decor.y
		)
		groups.decor:SetFrameLevel(100)

		origin:ClearAllPoints()
		origin:SetPoint("CENTER", groups.decor, "CENTER", LAYOUT.origin.dx, LAYOUT.origin.dy)

		groups.rings:ClearAllPoints()
		groups.rings:SetSize(1, 1)
		groups.rings:SetPoint("CENTER", origin, "CENTER", LAYOUT.rings.dx, LAYOUT.rings.dy + 30)

		groups.pearls:ClearAllPoints()
		groups.pearls:SetSize(1, 1)
		groups.pearls:SetPoint("CENTER", origin, "CENTER", LAYOUT.pearls.dx, LAYOUT.pearls.dy + 30)
		-- Keep render order: decor < rings < pearls.
		groups.ring:SetFrameStrata("HIGH")
		groups.ring:SetFrameLevel(groups.decor:GetFrameLevel() + 10)
		groups.rings:SetFrameStrata(groups.ring:GetFrameStrata())
		groups.rings:SetFrameLevel(groups.ring:GetFrameLevel() + 1)
		groups.pearls:SetFrameStrata(groups.ring:GetFrameStrata())
		groups.pearls:SetFrameLevel(groups.rings:GetFrameLevel() + 20)
	end
	Layout_Apply()

	--------------------------------------------------------
	-- Decor
	--------------------------------------------------------
	local bg = groups.decor:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(groups.decor)
	bg:SetAtlas("auctionhouse-background-index")

	local bg2 = groups.decor:CreateTexture(nil, "BACKGROUND", nil, 2)
	bg2:SetAllPoints(groups.decor)
	bg2:SetAtlas("delve-entrance-background-mycomancer-cavern")
	bg2:SetVertexColor(0.533, 0.533, 0.533, 0.8)

	local BACKGROUND_ATLASES = (ns and ns.BACKGROUND_ATLASES) or {}

	local function ApplyBackgroundAtlas(atlas)
		if SU.Util_IsAtlas(atlas) then
			bg2:SetAtlas(atlas)
			return true
		end
		return false
	end

	do
		local savedAtlas = ns.Prefs and ns.Prefs.GetSocial and ns.Prefs.GetSocial("backgroundAtlas", nil)
		if savedAtlas then
			ApplyBackgroundAtlas(savedAtlas)
		end
	end

	local bg3 = groups.decor:CreateTexture(nil, "BACKGROUND", nil, 3)
	bg3:SetPoint("RIGHT", groups.decor, "RIGHT", 47, 0)
	bg3:SetSize(580, 610)
	bg3:SetAtlas("GarrLanding-FollowerScrollFrame")

	local bg4 = groups.decor:CreateTexture(nil, "BACKGROUND", nil, 4)
	bg4:SetPoint("CENTER", bg3, "LEFT", -1, 0)
	bg4:SetSize(15, 614)
	bg4:SetAtlas("CovenantSanctum-Divider-Kyrian")

	local bg3TitleShadow = groups.decor:CreateTexture(nil, "OVERLAY", nil, 1)
	bg3TitleShadow:SetPoint("CENTER", bg3, "BOTTOM", -25, 25)
	bg3TitleShadow:SetSize(470, 80)
	bg3TitleShadow:SetAtlas("shop-card-label-bg", true)
	bg3TitleShadow:SetVertexColor(0, 0, 0, 0.8)

	local bg3Title = groups.decor:CreateFontString(nil, "OVERLAY", nil, 2)
	bg3Title:SetPoint("BOTTOM", bg3, "BOTTOM", -25, 25)
	bg3Title:SetSize(400, 25)
	bg3Title:SetFont("Fonts\\MORPHEUS.ttf", 25, "OUTLINE")
	bg3Title:SetTextColor(0.894, 0.655, 0.125, 1)
	bg3Title:SetText("Guild haberleri")

	--------------------------------------------------------
	-- Progression de guilde (barres)
	--------------------------------------------------------
	local progressPanel
	local progressBarsByKey = {}
	local progressGlobalBar
	local Progress_Update
	local Progress_GetSummary
	local OrbTooltip_Update

	do
		local function FormatPoints(n)
			local v = tonumber(n or 0) or 0
			local frac = math.abs(v - math.floor(v))
			if frac >= 0.01 then
				return string.format("%.2f", v)
			end
			if ns.Utils and ns.Utils.FormatThousands then
				return ns.Utils.FormatThousands(v)
			end
			return tostring(math.floor(v + 0.5))
		end

		local function Clamp01(v)
			if SU and SU.Util_Clamp01 then
				return SU.Util_Clamp01(v)
			end
			if v < 0 then
				return 0
			end
			if v > 1 then
				return 1
			end
			return v
		end

		Progress_GetSummary = function()
			if not GP or not GP.GetSummary then
				return nil
			end
			local summary = GP.GetSummary()
			if not summary then
				return nil
			end
			local debugPct = nil
			if ns.Prefs and ns.Prefs.GetSocial then
				debugPct = tonumber(ns.Prefs.GetSocial("debugProgressPct", nil))
			end
			if debugPct ~= nil then
				if debugPct < 0 then
					debugPct = 0
				elseif debugPct > 100 then
					debugPct = 100
				end
				summary.totalTarget = 100
				summary.totalPoints = debugPct
				summary.totalRatio = debugPct / 100
			end
			return summary
		end

		Progress_Update = function()
			local summary = Progress_GetSummary and Progress_GetSummary() or nil
			if not summary then
				return
			end
			if progressGlobalBar then
				progressGlobalBar:SetValue(Clamp01(summary.totalRatio or 0))
				progressGlobalBar.valueText:SetText(
					FormatPoints(summary.totalPoints or 0) .. " / " .. FormatPoints(summary.totalTarget or 0)
				)
			end
			if f._tokensText then
				local pts = math.ceil(tonumber(summary.totalPoints or summary.totalPointsRaw or 0) or 0)
				if ns.Utils and ns.Utils.FormatThousands then
					f._tokensText:SetText(ns.Utils.FormatThousands(pts))
				else
					f._tokensText:SetText(tostring(pts))
				end
			end
			if f._tokensFill then
				local ratio = 0
				if summary.totalTarget and summary.totalTarget > 0 then
					ratio = Clamp01((summary.totalPoints or 0) / summary.totalTarget)
				else
					ratio = Clamp01(summary.totalRatio or 0)
				end
				f._tokensFill:SetValue(ratio)
				if f._SetTokenMaskPct then
					f._SetTokenMaskPct(ratio)
				end
				if f._SetTokenEdgePct then
					f._SetTokenEdgePct(ratio)
				end
			end
			if summary.groups then
				for i = 1, #summary.groups do
					local g = summary.groups[i]
					local bar = g and progressBarsByKey[g.key] or nil
					if bar then
						local share = tonumber(g.share or 0) or 0
						bar:SetValue(Clamp01(share))
						local pct = math.floor(share * 100 + 0.5)
						bar.valueText:SetText(FormatPoints(g.points or 0) .. " (" .. tostring(pct) .. "%)")
					end
				end
			end
			if OrbTooltip_Update then
				OrbTooltip_Update(summary)
			end
		end
	end

	bg2:SetTexCoord(0, 1.1, 0, 1)

	local mask = groups.decor:CreateMaskTexture(nil, "ARTWORK", nil, 1)
	mask:SetPoint("CENTER", bg2, "CENTER", 320, 30)
	mask:SetSize(1050, 1050)
	mask:SetAtlas("FogMaskHardEdge", false)
	bg3:AddMaskTexture(mask)
	bg2:AddMaskTexture(mask)

	local CENTER_RING_CFG = {
		{
			atlas = "heartofazeroth-orb-activated",
			size = 280,
			speed = 0.06,
			alpha = 0.4,
			add = true,
			pulse = nil,
			layer = 1,
		},
		{
			atlas = "heartofazeroth-orb-activated",
			size = 408,
			speed = -0.16,
			alpha = 0.10,
			add = true,
			pulse = "standard",
			layer = 2,
		},
		{
			atlas = "heartofazeroth-animation-stars",
			size = 412,
			speed = 0.06,
			alpha = 0.10,
			add = true,
			pulse = "jitter",
			layer = 1,
		},
		{
			atlas = "heartofazeroth-animation-ring-constellation",
			size = 412,
			speed = 0.03,
			alpha = 0.10,
			add = true,
			pulse = "jitter",
			layer = 4,
		},
	}

	local centerRings = {}
	local function CreateCenterRing(cfg)
		if not cfg or not cfg.atlas then
			return
		end
		local t = groups.rings:CreateTexture(nil, "BACKGROUND", nil, 1)
		t:SetPoint("CENTER", groups.rings, "CENTER", 0, 0)
		if t.SetDrawLayer then
			t:SetDrawLayer("BACKGROUND", tonumber(cfg.layer) or 1)
		end
		t:SetSize(cfg.size or 260, cfg.size or 260)
		t:SetAtlas(cfg.atlas)
		t:SetAlpha(tonumber(cfg.alpha) or 0.10)
		if cfg.add then
			t:SetBlendMode("ADD")
		end
		t._rot = 0
		t._speed = tonumber(cfg.speed or 0) or 0
		t._baseAlpha = tonumber(cfg.alpha) or 0.10
		t._pulse = cfg.pulse
		t._pulsePhase = 0
		t._pulseJitterAt = 0
		t._pulseJitterAlpha = nil
		centerRings[#centerRings + 1] = t
	end

	for i = 1, #CENTER_RING_CFG do
		CreateCenterRing(CENTER_RING_CFG[i])
	end

	--------------------------------------------------------
	-- Background menu
	--------------------------------------------------------
	local function Background_OpenMenu(anchor)
		if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
			return
		end
		local function Generator(_, root)
			if root.CreateTitle then
				root:CreateTitle("Choisir un fond")
			elseif root.CreateButton then
				root:CreateButton("Choisir un fond", function() end, { disabled = true, isTitle = true })
			end
			for i = 1, #BACKGROUND_ATLASES do
				local entry = BACKGROUND_ATLASES[i]
				local label = entry.label
				root:CreateButton(label, function()
					if ApplyBackgroundAtlas(entry.atlas) then
						if ns.Prefs and ns.Prefs.SetSocial then
							ns.Prefs.SetSocial("backgroundAtlas", entry.atlas)
						end
					end
				end, {
					isRadio = true,
					checked = function()
						return (bg2:GetAtlas() or "") == entry.atlas
					end,
				})
				if root.CreateDivider and (i % 5 == 0) and i < #BACKGROUND_ATLASES then
					root:CreateDivider()
				end
			end
		end
		MenuUtil.CreateContextMenu(anchor, Generator)
	end

	local bgMenuHit = CreateFrame("Button", nil, groups.decor)
	bgMenuHit:SetAllPoints(groups.decor)
	bgMenuHit:SetFrameStrata(groups.decor:GetFrameStrata())
	bgMenuHit:SetFrameLevel(groups.decor:GetFrameLevel() + 1)
	bgMenuHit:EnableMouse(true)
	if bgMenuHit.SetPropagateMouseClicks then
		bgMenuHit:SetPropagateMouseClicks(true)
	end
	bgMenuHit:RegisterForClicks("RightButtonUp")
	bgMenuHit:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			Background_OpenMenu(bgMenuHit)
		end
	end)

	--------------------------------------------------------
	-- State + Forward decl
	--------------------------------------------------------
	local News_GetTypeLabel
	local List_Refresh
	local List_UpdateTitle
	local Pearl_StartFadeOut
	local Pearl_SpawnOnRing
	local Pearl_TrySpawn
	local Pearl_Release
	local ReleaseAllPearlHover
	local News_GetAuthorPseudo
	local News_AuthorPrefix
	local Ring_ClearRuntime

	local activePearls = {}
	local listBatchDepth = 0
	local listBatchDirty = false

	local function List_MarkDirtyOrRefresh()
		if listBatchDepth > 0 then
			listBatchDirty = true
			return
		end
		if groups.list:IsShown() and List_Refresh then
			List_Refresh()
		end
	end

	local State = {
		view = {
			mode = (ns.Prefs and ns.Prefs.GetSocial and ns.Prefs.GetSocial("viewMode", "ring")) or "ring",
		},
		filter = {
			onlyMine = (ns.Prefs and ns.Prefs.GetSocial and ns.Prefs.GetSocial("onlyMine", false)) or false,
			onlyProud = (ns.Prefs and ns.Prefs.GetSocial and ns.Prefs.GetSocial("onlyProud", false)) or false,
			types = (ns.Prefs and ns.Prefs.GetSocial and ns.Prefs.GetSocial("newsTypes", nil)) or nil,
		},
	}

	--------------------------------------------------------
	-- News types
	--------------------------------------------------------
	local NEWS_TYPE_LABELS = {
		achievement = "Basarilar",
		mount = "Binek",
		toy = "Oyuncak",
		transmog = "Gorunum",
		connection = "Baglanti",
		guild = "Guild",
		guildchat = "Guild sohbeti",
		pve = "Zindanlar",
		cibles = "Hedefler",
		raid = "Raid",
		mplus = "Mythic+",
		loot = "Ganimet",
		woodharvest = "Odun toplama",
		herbharvest = "Bitki toplama",
		fishingharvest = "Balik tutma",
		oreharvest = "Maden toplama",
		housing = "Konut",
		housingcleanup = "Konut bakimi",
		housingdecor = "Konut esyalari",
		collection = "Koleksiyon",
		world = "Dunya",
		quest = "Gorevler",
		questdaily = "Gunluk gorevler",
		worldquest = "Dunya gorevleri",
		level = "Seviye",
		gear = "Ekipman",
		spec = "Uzmanlik",
		death = "Olumler",
		pvp = "PvP",
		social = "Sosyal",
		generic = "Cesitli",
	}

	local NEWS_TYPE_ORDER = {
		"achievement",
		"mount",
		"toy",
		"transmog",
		"connection",
		"guild",
		"guildchat",
		"pve",
		"cibles",
		"raid",
		"mplus",
		"loot",
		"woodharvest",
		"herbharvest",
		"fishingharvest",
		"oreharvest",
		"housing",
		"housingcleanup",
		"housingdecor",
		"collection",
		"world",
		"quest",
		"questdaily",
		"worldquest",
		"level",
		"gear",
		"spec",
		"death",
		"pvp",
		"social",
		"generic",
	}

	local NEWS_TYPE_GROUPS = {
		{ label = "Gorevler", keys = { "quest", "questdaily", "worldquest" } },
		{ label = "Dunya", keys = { "world" } },
		{ label = "Ilerleme", keys = { "achievement", "level", "gear", "spec" } },
		{ label = "Savas", keys = { "pve", "raid", "mplus", "cibles", "pvp", "death" } },
		{ label = "Ganimet", keys = { "loot", "woodharvest", "herbharvest", "fishingharvest", "oreharvest" } },
		{ label = "Koleksiyon", keys = { "mount", "toy", "transmog", "collection", "housing", "housingcleanup", "housingdecor" } },
		{ label = "Iletisim", keys = { "connection", "guild", "guildchat", "social" } },
		{ label = "Cesitli", keys = { "generic" } },
	}
	local NEWS_TYPE_GROUPED = {}
	for _, group in ipairs(NEWS_TYPE_GROUPS) do
		for _, key in ipairs(group.keys) do
			NEWS_TYPE_GROUPED[key] = true
		end
	end
	local NEWS_TYPE_UNGROUPED = {}
	for _, key in ipairs(NEWS_TYPE_ORDER) do
		if not NEWS_TYPE_GROUPED[key] then
			NEWS_TYPE_UNGROUPED[#NEWS_TYPE_UNGROUPED + 1] = key
		end
	end

	News_GetTypeLabel = function(typ)
		typ = (typ and tostring(typ):lower()) or ""
		if not typ or typ == "" then
			return NEWS_TYPE_LABELS.generic
		end
		return NEWS_TYPE_LABELS[typ] or NEWS_TYPE_LABELS.generic
	end

	--------------------------------------------------------
	-- Filters + proud
	--------------------------------------------------------
	local function Filter_EnsureTypes()
		if not State.filter.types or next(State.filter.types) == nil then
			State.filter.types = {}
		end
		for key in pairs(NEWS_TYPE_LABELS) do
			if State.filter.types[key] == nil then
				State.filter.types[key] = true
			end
		end
	end

	local function Filter_AnyTypeEnabled()
		Filter_EnsureTypes()
		for _, enabled in pairs(State.filter.types) do
			if enabled then
				return true
			end
		end
		return false
	end

	local function Filter_Sync()
		if ns.Prefs and ns.Prefs.SetSocial then
			ns.Prefs.SetSocial("onlyMine", State.filter.onlyMine)
			ns.Prefs.SetSocial("onlyProud", State.filter.onlyProud)
			ns.Prefs.SetSocial("newsTypes", State.filter.types)
		end
	end

	local function Filter_IsMyNews(n)
		if not n then
			return false
		end
		local text = SU.NormalizeText((n.text or "") .. " " .. (n.title or ""))
		if text == "" then
			return false
		end
		local uid = ns.DB and ns.DB.GetMyUID and ns.DB:GetMyUID() or nil
		if uid and n.replaceKey and tostring(n.replaceKey):find(uid, 1, true) then
			return true
		end
		local name = UnitName and UnitName("player") or nil
		local full = UnitFullName and UnitFullName("player") or nil
		if name and text:find(name, 1, true) then
			return true
		end
		if full and full ~= name and text:find(full, 1, true) then
			return true
		end
		if ns.Data and ns.Data.JournalistAPI and ns.Data.JournalistAPI.GetPlayerDisplayName then
			local display = ns.Data.JournalistAPI.GetPlayerDisplayName()
			if display and display ~= "" and text:find(display, 1, true) then
				return true
			end
		end
		return false
	end

	local BADGE_MINE_ATLAS = "checkmark-minimal-disabled"
	local BADGE_MINE_TEX = "Interface\\Buttons\\UI-CheckBox-Check"
	local BADGE_PROUD_ATLAS = "checkmark-minimal"
	local BADGE_PROUD_TEX = "Interface\\Common\\ReputationStar"
	local PROUD_BORDER_R, PROUD_BORDER_G, PROUD_BORDER_B = 1, 0.914, 0.608
	local FEATURED_BORDER_R, FEATURED_BORDER_G, FEATURED_BORDER_B = 1, 0.5, 0

	local function Proud_GetRoot(guildUID)
		local gid = guildUID or (ns.DB and ns.DB.GetGuildUID and ns.DB:GetGuildUID()) or nil
		if not gid or gid == "" then
			return nil
		end
		WoWGuildeDB = WoWGuildeDB or {}
		WoWGuildeDB.guilds = WoWGuildeDB.guilds or {}
		local g = WoWGuildeDB.guilds[gid]
		if not g then
			g = { guildInfo = { guildUID = gid }, players = {} }
			WoWGuildeDB.guilds[gid] = g
		end
		if type(g.proudNews) ~= "table" then
			g.proudNews = {}
		end
		g.proudNews.proudByCharacter = g.proudNews.proudByCharacter or {}
		g.proudNews.proudByMe = g.proudNews.proudByMe or {}
		return g.proudNews
	end

	local function Featured_MergeByKey(dst, src)
		if type(dst) ~= "table" or type(src) ~= "table" then
			return
		end
		for key, v in pairs(src) do
			if type(v) == "table" then
				local incoming = tonumber(v.updatedAt or 0) or 0
				local existing = tonumber(dst[key] and dst[key].updatedAt or 0) or 0
				if existing == 0 or incoming == 0 or incoming >= existing then
					local out = {}
					for fk, fv in pairs(v) do
						out[fk] = fv
					end
					dst[key] = out
				end
			end
		end
	end

	local function Featured_GetRoot(guildUID)
		local gid = guildUID or (ns.DB and ns.DB.GetGuildUID and ns.DB:GetGuildUID()) or nil
		if not gid or gid == "" then
			return nil
		end
		WoWGuildeDB = WoWGuildeDB or {}
		WoWGuildeDB.guilds = WoWGuildeDB.guilds or {}
		local g = WoWGuildeDB.guilds[gid]
		if not g then
			g = { guildInfo = { guildUID = gid }, players = {} }
			WoWGuildeDB.guilds[gid] = g
		end
		local proudRoot = Proud_GetRoot(gid)
		if not proudRoot then
			return nil
		end
		proudRoot.legendaryProud = proudRoot.legendaryProud or {}
		proudRoot.legendaryProud.byKey = proudRoot.legendaryProud.byKey or {}
		if type(g.featuredNews) == "table" and type(g.featuredNews.byKey) == "table" then
			Featured_MergeByKey(proudRoot.legendaryProud.byKey, g.featuredNews.byKey)
			g.featuredNews = nil
		end
		return proudRoot.legendaryProud
	end

	local function Featured_GetStore(guildUID)
		local root = Featured_GetRoot(guildUID)
		return root and root.byKey or nil
	end

	local function Featured_IsNewsFeatured(guildUID, newsId)
		if not guildUID or not newsId then
			return false
		end
		local t = Featured_GetStore(guildUID)
		if not t then
			return false
		end
		for _, v in pairs(t) do
			if v and v.id == newsId then
				return true
			end
		end
		return false
	end

	local function Proud_GetStore(guildUID)
		local root = Proud_GetRoot(guildUID)
		return root and root.proudByMe or nil
	end

	local function Proud_GetByStore(guildUID)
		local root = Proud_GetRoot(guildUID)
		return root and root.proudByCharacter or nil
	end

	local function Proud_GetLocalUID()
		if ns.DB and ns.DB.GetMyUID then
			return ns.DB:GetMyUID()
		end
		return nil
	end

	local function Proud_GetLocalFull()
		local n, r = UnitFullName and UnitFullName("player")
		if not n or n == "" then
			n = UnitName and UnitName("player") or ""
		end
		if r and r ~= "" then
			return n .. "-" .. r
		end
		return n ~= "" and n or nil
	end

	local function Proud_IsLocalActor(key, value)
		local uid = Proud_GetLocalUID()
		if uid and key == uid then
			return true
		end
		local full = Proud_GetLocalFull()
		if full and key == full then
			return true
		end
		local base = (ns.Utils and ns.Utils.BaseName and full) and ns.Utils.BaseName(full) or nil
		if base and key == base then
			return true
		end
		if type(value) == "table" and value.name and value.name ~= "" then
			if full and value.name == full then
				return true
			end
			if base and value.name == base then
				return true
			end
		end
		return false
	end

	local function Proud_GetGuildUID(news)
		if news and news.guildUID then
			return news.guildUID
		end
		if ns.DB and ns.DB.GetGuildUID then
			return ns.DB:GetGuildUID()
		end
		return nil
	end

	local function News_FindTargetFromAlias(text)
		local cache = ns.Utils and ns.Utils.PSEUDO_CACHE or nil
		if not cache or not text or text == "" then
			return nil
		end
		local hay = text:lower()
		local onlineFallback = nil
		local offlineFallback = nil
		for key, rec in pairs(cache) do
			local alias = type(rec) == "table" and rec.alias or rec
			if alias and alias ~= "" then
				local needle = tostring(alias):lower()
				if needle ~= "" and hay:find(needle, 1, true) then
					local candidate = key
					if HU and HU.ResolveLiveCharacterForFull then
						local live, online = HU.ResolveLiveCharacterForFull(key)
						if live and live ~= "" then
							candidate = live
						end
						if online == true then
							return candidate
						end
					end
					if candidate:find("-", 1, true) then
						if not onlineFallback then
							onlineFallback = candidate
						end
					elseif not offlineFallback then
						offlineFallback = candidate
					end
				end
			end
		end
		return onlineFallback or offlineFallback
	end

	local function News_ExtractUID(replaceKey)
		if not replaceKey or replaceKey == "" then
			return nil
		end
		return tostring(replaceKey):match("(uid:[%w]+)")
	end

	local function News_GetUID(news)
		if not news then
			return nil
		end
		local uid = news.uid
		if uid and uid ~= "" then
			uid = tostring(uid)
			if uid:sub(1, 4) == "uid:" then
				return uid
			end
			local extracted = uid:match("(uid:[%w]+)")
			if extracted and extracted ~= "" then
				return extracted
			end
		end
		return News_ExtractUID(news.replaceKey)
	end

	local function News_ResolveTargetFull(news)
		if not news then
			return nil
		end
		local uid = News_GetUID(news)
		local gid = Proud_GetGuildUID(news)
		if uid and gid then
			if HU and HU.ResolveLiveCharacterForUID then
				local full = HU.ResolveLiveCharacterForUID(gid, uid)
				if full and full ~= "" then
					return full
				end
			elseif ns.DB and ns.DB.GetGuildPlayerMain then
				local full = ns.DB:GetGuildPlayerMain(gid, uid)
				if full and full ~= "" then
					return full
				end
			end
		end
		local text = SU.NormalizeText((news.text or "") .. " " .. (news.title or ""))
		local full = News_FindTargetFromAlias(text)
		if full and full ~= "" and HU and HU.ResolveLiveCharacterForFull then
			local live = HU.ResolveLiveCharacterForFull(full)
			if live and live ~= "" then
				return live
			end
		end
		return full
	end

	local function News_ResolveTarget(news)
		if not news then
			return nil, false, nil
		end
		local uid = News_GetUID(news)
		local gid = Proud_GetGuildUID(news)
		if uid and gid and HU and HU.ResolveLiveCharacterForUID then
			local full, online, rec = HU.ResolveLiveCharacterForUID(gid, uid)
			if full and full ~= "" then
				return full, online == true, rec
			end
		elseif uid and gid and ns.DB and ns.DB.GetGuildPlayerMain then
			local full = ns.DB:GetGuildPlayerMain(gid, uid)
			if full and full ~= "" then
				return full, false, nil
			end
		end
		local text = SU.NormalizeText((news.text or "") .. " " .. (news.title or ""))
		local full = News_FindTargetFromAlias(text)
		if full and full ~= "" and HU and HU.ResolveLiveCharacterForFull then
			local live, online, rec = HU.ResolveLiveCharacterForFull(full)
			if live and live ~= "" then
				return live, online == true, rec
			end
		end
		return full, false, nil
	end

	local function Proud_IsUID(key)
		return type(key) == "string" and key:sub(1, 4) == "uid:"
	end

	local function Proud_ResolveNameFromUID(uid, guildUID)
		if not uid or not ns.DB or not ns.DB.GetGuildPlayerMain then
			return nil
		end
		local full = ns.DB:GetGuildPlayerMain(guildUID, uid)
		if not full or full == "" then
			return nil
		end
		if ns.Utils and ns.Utils.PSEUDO_CACHE then
			local rec = ns.Utils.PSEUDO_CACHE[full] or ns.Utils.PSEUDO_CACHE[Ambiguate(full, "none")]
			if rec and rec.alias and rec.alias ~= "" then
				return rec.alias
			end
		end
		if ns.Utils and ns.Utils.BaseName then
			return ns.Utils.BaseName(full)
		end
		return full
	end

	local function Proud_PickAnyName(by, guildUID)
		if type(by) ~= "table" then
			return nil
		end
		for k, v in pairs(by) do
			if not Proud_IsLocalActor(k, v) then
				if type(v) == "table" and v.name and v.name ~= "" then
					return v.name
				end
				if Proud_IsUID(k) then
					local resolved = Proud_ResolveNameFromUID(k, guildUID)
					if resolved and resolved ~= "" then
						return resolved
					end
					return k
				elseif type(k) == "string" and k ~= "" then
					return k
				end
			end
		end
		return nil
	end

	local Pearl_UpdateVisual

	local function Proud_IsChecked(news)
		if not news or not news.id then
			return false
		end
		local gid = Proud_GetGuildUID(news)
		local t = Proud_GetStore(gid)
		if not t then
			return false
		end
		return t[news.id] == true
	end

	local function Proud_HasAnyOther(news)
		if not news or not news.id then
			return false
		end
		local gid = Proud_GetGuildUID(news)
		local t = Proud_GetByStore(gid)
		if not t then
			return false
		end
		local by = t[news.id]
		if type(by) ~= "table" then
			return false
		end
		for k, v in pairs(by) do
			if v and not Proud_IsLocalActor(k, v) then
				return true
			end
		end
		return false
	end

	local function Proud_HasAnyOrMe(news)
		if Proud_IsChecked(news) then
			return true
		end
		return Proud_HasAnyOther(news)
	end

	local function Proud_SetBy(newsId, actorKey, value, actorName, guildUID)
		if not newsId or newsId == "" or not actorKey or actorKey == "" then
			return
		end
		local t = Proud_GetByStore(guildUID)
		if not t then
			return
		end
		local by = t[newsId]
		if type(by) ~= "table" then
			by = {}
		end
		if value then
			if Proud_IsUID(actorKey) then
				by[actorKey] = { name = actorName }
			else
				by[actorKey] = true
			end
		else
			by[actorKey] = nil
			if actorName and actorName ~= "" then
				by[actorName] = nil
				if ns.Utils and ns.Utils.BaseName then
					local base = ns.Utils.BaseName(actorName)
					if base and base ~= "" then
						by[base] = nil
					end
				end
				for k, v in pairs(by) do
					if type(v) == "table" and v.name == actorName then
						by[k] = nil
					end
				end
			end
		end
		if next(by) == nil then
			t[newsId] = nil
		else
			t[newsId] = by
		end
	end

	local function Proud_SetChecked(news, value)
		if not news or not news.id then
			return
		end
		if Featured_IsNewsFeatured(Proud_GetGuildUID(news), news.id) then
			return
		end
		local gid = Proud_GetGuildUID(news)
		local t = Proud_GetStore(gid)
		if not t then
			return
		end
		if value then
			t[news.id] = true
		else
			t[news.id] = nil
		end
		local uid = Proud_GetLocalUID()
		local full = Proud_GetLocalFull()
		if uid then
			Proud_SetBy(news.id, uid, value, full or uid, gid)
		elseif full then
			Proud_SetBy(news.id, full, value, full, gid)
		end
		if ns.Comms and ns.Comms.SendNewsProud then
			ns.Comms:SendNewsProud(news.id, news.guildUID, value)
		end
		if List_Refresh then
			List_Refresh()
		end
		for i = 1, #activePearls do
			local p = activePearls[i]
			if p and p._news and p._news.id == news.id then
				Pearl_UpdateVisual(p)
			end
		end
	end

	local function Proud_Transfer(oldId, newId, guildUID)
		if not oldId or not newId or oldId == newId then
			return
		end
		local t = Proud_GetStore(guildUID)
		if t and t[oldId] ~= nil then
			if t[newId] == nil then
				t[newId] = t[oldId]
			else
				t[newId] = (t[newId] == true) or (t[oldId] == true)
			end
			t[oldId] = nil
		end
		local by = Proud_GetByStore(guildUID)
		if by and type(by[oldId]) == "table" then
			local dst = by[newId]
			if type(dst) ~= "table" then
				dst = {}
			end
			for k, v in pairs(by[oldId]) do
				if v then
					dst[k] = v
				end
			end
			by[newId] = dst
			by[oldId] = nil
		end
	end

	local function Proud_ApplyRemote(newsId, sender, value, senderUID, guildUID)
		if senderUID and senderUID ~= "" then
			Proud_SetBy(newsId, senderUID, value, sender, guildUID)
		else
			Proud_SetBy(newsId, sender, value, sender, guildUID)
		end
		if List_Refresh then
			List_Refresh()
		end
	end

	Pearl_UpdateVisual = function(p)
		if not p or not p._news then
			return
		end
		local isMine = Filter_IsMyNews(p._news)
		local proudOther = Proud_HasAnyOther(p._news)
		local proudMe = Proud_IsChecked(p._news)
		local proudAny = (not not proudOther) or not not proudMe
		local isFeatured = Featured_IsNewsFeatured(Proud_GetGuildUID(p._news), p._news.id)
		if isFeatured then
			proudAny = true
		end
		p._isMine = not not isMine
		p._proudAny = not not proudAny

		if p.mineBadge then
			local showBadge = not not isMine
			p.mineBadge:SetShown(showBadge)
			p.mineBadge._news = p._news
			p.mineBadge._item = p
			p.mineBadge._isMine = not not isMine
			p.mineBadge._proudAny = not not proudAny
			local badgeAtlas = proudAny and BADGE_PROUD_ATLAS or BADGE_MINE_ATLAS
			local badgeFallback = proudAny and BADGE_PROUD_TEX or BADGE_MINE_TEX
			if p.mineBadge.icon then
				SU.Util_SetAtlasOrTexture(p.mineBadge.icon, badgeAtlas, badgeFallback)
				if isFeatured then
					p.mineBadge.icon:SetVertexColor(FEATURED_BORDER_R, FEATURED_BORDER_G, FEATURED_BORDER_B, 1)
				elseif proudOther and not Proud_IsChecked(p._news) then
					p.mineBadge.icon:SetVertexColor(0.25, 1, 0.35, 1)
				else
					p.mineBadge.icon:SetVertexColor(1, 1, 1, 1)
				end
			end
		end

		if p.iconOverlay then
			if isFeatured then
				p.iconOverlay:SetVertexColor(FEATURED_BORDER_R, FEATURED_BORDER_G, FEATURED_BORDER_B, 1)
			elseif proudAny then
				p.iconOverlay:SetVertexColor(PROUD_BORDER_R, PROUD_BORDER_G, PROUD_BORDER_B, 1)
			else
				p.iconOverlay:SetVertexColor(1, 1, 1, 1)
			end
		end
		if p.proudOverlay then
			p.proudOverlay:SetShown(proudAny or isFeatured)
			if isFeatured then
				p.proudOverlay:SetVertexColor(FEATURED_BORDER_R, FEATURED_BORDER_G, FEATURED_BORDER_B, 0.6)
			elseif proudAny then
				if Proud_IsChecked(p._news) then
					p.proudOverlay:SetVertexColor(1, 1, 1, 0.6)
				else
					p.proudOverlay:SetVertexColor(0.25, 1, 0.35, 0.6)
				end
			end
		end
	end

	function Sections.Social_OnProudUpdate(newsId, sender, value, senderUID, guildUID)
		Proud_ApplyRemote(newsId, sender, value, senderUID, guildUID)
		for i = 1, #activePearls do
			local p = activePearls[i]
			if p and p._news and p._news.id == newsId then
				Pearl_UpdateVisual(p)
			end
		end
		if List_Refresh then
			List_Refresh()
		end
		if ns.Sections and ns.Sections.Heros_OnProudUpdate then
			ns.Sections.Heros_OnProudUpdate(newsId, sender, value, senderUID, guildUID)
		end
	end

	function Sections.Social_OnFeaturedUpdate(guildUID, heroKey, news)
		if not guildUID or not heroKey then
			return
		end
		if List_Refresh then
			List_Refresh()
		end
		for i = 1, #activePearls do
			local p = activePearls[i]
			if p and p._news then
				Pearl_UpdateVisual(p)
			end
		end
	end

	local CanReactToNews

	local function Proud_OpenMenu(anchor, news, isMine)
		if not (news and news.id) then
			return
		end
		if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
			return
		end
		local function Generator(owner, root)
			local isMineLocal = isMine
			if isMineLocal == nil then
				isMineLocal = Filter_IsMyNews(news)
			end
			local authorPseudo = News_GetAuthorPseudo(news)
			local isFeatured = Featured_IsNewsFeatured(Proud_GetGuildUID(news), news.id)
			local canModerate = (ns.Roles and ns.Roles.CanModerateNews and ns.Roles.CanModerateNews())
			local canProud = isMineLocal and root.CreateCheckbox
			local canDelete = canModerate or isMineLocal
			local hasReaction = false
			local reactionNewsOpts = {
				news = news,
				newsTypeLabel = News_GetTypeLabel and News_GetTypeLabel(news and news.type) or nil,
			}

			local targetFull, targetOnline, targetRec = News_ResolveTarget(news)
			if not targetOnline and targetRec and targetRec.isMobile then
				targetOnline = true
			end
			local canProfile = targetFull and ns.Sections and ns.Sections.Heros_SelectByFull
			if root.CreateTitle then
				if isMineLocal then
					root:CreateTitle("Senin haberin")
				else
					local author = tostring(authorPseudo or "Bilinmiyor")
					root:CreateTitle("Haber " .. News_AuthorPrefix(author) .. author)
				end
			end

			if root.CreateButton then
				if canProfile then
					root:CreateButton("Profili gor", function()
						if ns and ns.UI and ns.UI.Show then
							ns.UI.Show()
						end
						if ns and ns.UI and ns.UI.ShowSection then
							ns.UI.ShowSection("Nos héros")
						end
						ns.Sections.Heros_SelectByFull(targetFull)
					end)
				else
					root:CreateButton("Profili gor", function() end, { disabled = true })
				end
			end

			if isFeatured then
				canProud = false
				if not canModerate then
					canDelete = false
				end
			end
			if canProud then
				root:CreateCheckbox("Bu haberle gurur duyuyorum", function()
					return Proud_IsChecked(news)
				end, function()
					Proud_SetChecked(news, not Proud_IsChecked(news))
				end)
			end
			if canDelete then
				if root.CreateDivider then
					root:CreateDivider()
				end
				root:CreateButton("Bu haberi sil", function()
					if ns.Data and ns.Data.JournalistAPI and ns.Data.JournalistAPI.RemoveNewsById then
						ns.Data.JournalistAPI.RemoveNewsById(news.guildUID, news.id)
					end
					if ns.Comms and ns.Comms.SendNewsDelete then
						ns.Comms:SendNewsDelete(news.id, news.guildUID)
					end
				end)
			end

			if root.CreateButton and CanReactToNews(news, isMineLocal) then
				if isMineLocal and SU.IsDevMode() then
					if root.CreateDivider then
						root:CreateDivider()
					end
					local me = UnitName and UnitName("player")
					if not me or me == "" then
						me = UnitFullName and UnitFullName("player")
					end
					reactionNewsOpts.test = true
					hasReaction = SU.AddReactionsSubmenu(root, me or "?", reactionNewsOpts)
				elseif not isMineLocal then
					if targetFull and targetOnline then
						if root.CreateDivider then
							root:CreateDivider()
						end
						reactionNewsOpts.allowNoPrefs = true
						hasReaction = SU.AddReactionsSubmenu(root, targetFull, reactionNewsOpts) == true
					end
				end
			end
		end
		MenuUtil.CreateContextMenu(anchor, Generator)
	end

	CanReactToNews = function(news, isMine)
		if not news or not (ns and ns.Emotes and ns.Emotes.Catalog) then
			return false
		end
		if isMine then
			return SU.IsDevMode()
		end
		return true
	end

	local function CanOpenNewsMenu(news, isMine)
		if isMine then
			return true
		end
		local targetFull, targetOnline, targetRec = News_ResolveTarget(news)
		local isReachable = targetOnline or (targetRec and targetRec.isMobile)
		local canProfile = targetFull and ns.Sections and ns.Sections.Heros_SelectByFull
		if canProfile then
			return true
		end
		if ns.Roles and ns.Roles.CanModerateNews and ns.Roles.CanModerateNews() then
			return true
		end
		return CanReactToNews(news, isMine) and isReachable
	end

	News_GetAuthorPseudo = function(news)
		if not news then
			return "Inconnu"
		end
		local uid = News_ExtractUID(news.replaceKey)
		local gid = Proud_GetGuildUID(news)
		if uid and gid then
			local alias = Proud_ResolveNameFromUID(uid, gid)
			if alias and alias ~= "" then
				return alias
			end
		end
		local full = News_ResolveTargetFull(news)
		if full and full ~= "" and ns and ns.Utils and ns.Utils.PSEUDO_CACHE then
			local rec = ns.Utils.PSEUDO_CACHE[full] or ns.Utils.PSEUDO_CACHE[Ambiguate(full, "none")]
			local alias = rec and rec.alias
			if alias and alias ~= "" then
				return alias
			end
		end
		if full and full ~= "" and ns and ns.Utils and ns.Utils.BaseName then
			return ns.Utils.BaseName(full)
		end
		return "Inconnu"
	end

	News_AuthorPrefix = function(pseudo)
		local s = tostring(pseudo or ""):gsub("^%s+", "")
		local first = s:sub(1, 1):lower()
		if first == "" then
			return "de "
		end
		if first:find("[aeiouyàâäæéèêëîïôöœùûüÿ]") then
			return "d'"
		end
		return "de "
	end

	local function Filter_IsNewsAllowed(n)
		if not n then
			return false
		end
		Filter_EnsureTypes()
		local typ = (n.type and tostring(n.type):lower()) or "generic"
		if not NEWS_TYPE_LABELS[typ] then
			typ = "generic"
		end
		if State.filter.onlyMine and not Filter_IsMyNews(n) then
			return false
		end
		if State.filter.onlyProud and not Proud_HasAnyOrMe(n) then
			if not (n and n.id and Featured_IsNewsFeatured(Proud_GetGuildUID(n), n.id)) then
				return false
			end
		end
		if State.filter.types then
			local anyEnabled = false
			for _, enabled in pairs(State.filter.types) do
				if enabled then
					anyEnabled = true
					break
				end
			end
			if not anyEnabled then
				return false
			end
			if State.filter.types[typ] == false then
				return false
			end
		end
		return true
	end

	--------------------------------------------------------
	-- View switch
	--------------------------------------------------------
	local styleDropdown = CreateFrame("DropdownButton", "WoWGuilde_SocialStyleDropdown", f, "WowStyle1DropdownTemplate")
	styleDropdown:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 70)
	styleDropdown:SetSize(120, 25)
	styleDropdown.SetSelectionText = function() end
	styleDropdown:SetScript("OnEnter", function() end)
	styleDropdown:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)

	--  ara (LFG) butonu: LFG sekmesine gecis
	local lfgButton = CreateFrame("Button", "WoWGuilde_SocialLFGButton", f, "BigRedThreeSliceButtonTemplate")
	lfgButton:SetSize(200, 50)
	lfgButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 200, 30)
	lfgButton:SetText("Grup ara")
	lfgButton:SetNormalFontObject("GameFontNormal")
	lfgButton:SetScript("OnClick", function()
		if ns and ns.UI and ns.UI.ShowSection then
			ns.UI.ShowSection("LFG")
		end
	end)
	lfgButton:SetScript("OnEnter", function(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText("Guild Aktivitesi Ara", 1, 0.82, 0)
			GameTooltip:AddLine("Raid, Mythic+, Levelling, Achievement veya Delve listesini ac.", 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	lfgButton:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)

	local function View_Apply(mode)
		local prevMode = State.view.mode
		State.view.mode = mode
		if ns.Prefs and ns.Prefs.SetSocial then
			ns.Prefs.SetSocial("viewMode", mode)
		end
		if mode == "list" and Ring_ClearRuntime then
			Ring_ClearRuntime()
		elseif mode == "ring" and prevMode ~= "ring" and Ring_ClearRuntime then
			-- Always re-enter ring mode from an empty state.
			Ring_ClearRuntime()
		end
		groups.ring:SetShown(mode == "ring")
		groups.list:SetShown(mode == "list")
		if Progress_Update then
			Progress_Update()
		end
		if mask then
			mask:SetShown(mode == "ring")
		end
		if mode == "list" and List_Refresh then
			List_Refresh()
		end
		styleDropdown:SetDefaultText(mode == "list" and "Liste" or "Halka")
	end

	local function Filter_ExpirePearls()
		for i = #activePearls, 1, -1 do
			local p = activePearls[i]
			if p and p._news and not Filter_IsNewsAllowed(p._news) then
				p._lifeLeft = 0
				p._expired = true
				p._pendingFade = false
				p._pendingJitter = nil
				Pearl_StartFadeOut(p)
			end
		end
	end

	local function Filter_ToggleOnlyMine()
		State.filter.onlyMine = not State.filter.onlyMine
		Filter_Sync()
		if List_UpdateTitle then
			List_UpdateTitle()
		end
		if groups.list:IsShown() and List_Refresh then
			List_Refresh()
		end
		Filter_ExpirePearls()
	end

	local function Filter_ToggleOnlyProud()
		State.filter.onlyProud = not State.filter.onlyProud
		Filter_Sync()
		if List_UpdateTitle then
			List_UpdateTitle()
		end
		if groups.list:IsShown() and List_Refresh then
			List_Refresh()
		end
		Filter_ExpirePearls()
	end

	local function Filter_SetAllTypes(enabled)
		Filter_EnsureTypes()
		for key in pairs(State.filter.types) do
			State.filter.types[key] = enabled
		end
		Filter_Sync()
		if groups.list:IsShown() and List_Refresh then
			List_Refresh()
		end
		Filter_ExpirePearls()
	end

	local function Filter_SetTypes(keys, enabled)
		Filter_EnsureTypes()
		for i = 1, #keys do
			local key = keys[i]
			State.filter.types[key] = enabled
		end
		Filter_Sync()
		if groups.list:IsShown() and List_Refresh then
			List_Refresh()
		end
		Filter_ExpirePearls()
	end

	local function Filter_EnableAll()
		State.filter.onlyMine = false
		State.filter.onlyProud = false
		Filter_SetAllTypes(true)
		if List_UpdateTitle then
			List_UpdateTitle()
		end
	end

	local function Filter_ToggleType(key)
		Filter_EnsureTypes()
		State.filter.types[key] = not State.filter.types[key]
		Filter_Sync()
		if groups.list:IsShown() and List_Refresh then
			List_Refresh()
		end
		Filter_ExpirePearls()
	end

	local function Dropdown_AddToggleEntry(menu, label, getter, toggler)
		if menu.CreateCheckbox then
			menu:CreateCheckbox(label, getter, toggler)
		else
			menu:CreateButton(label, toggler, { isNotRadio = true, checked = getter })
		end
	end

	local function Dropdown_AddRadioEntry(menu, label, getter, toggler)
		if menu.CreateRadio then
			menu:CreateRadio(label, getter, toggler)
		else
			menu:CreateButton(label, toggler, { isRadio = true, checked = getter })
		end
	end

	local function Dropdown_Generate(owner, root)
		Dropdown_AddRadioEntry(root, "Halka", function()
			return State.view.mode == "ring"
		end, function()
			View_Apply("ring")
		end)
		Dropdown_AddRadioEntry(root, "Liste", function()
			return State.view.mode == "list"
		end, function()
			View_Apply("list")
		end)
		if root.CreateDivider then
			root:CreateDivider()
		end
		Dropdown_AddToggleEntry(root, "Sadece benim haberlerim", function()
			return State.filter.onlyMine
		end, Filter_ToggleOnlyMine)
		Dropdown_AddToggleEntry(root, "Sadece guild gururlari", function()
			return State.filter.onlyProud
		end, Filter_ToggleOnlyProud)

		local typesMenu = root:CreateButton("Haber turleri")
		if typesMenu then
			typesMenu:CreateButton("Hepsini goster", function()
				Filter_SetAllTypes(true)
			end)
			typesMenu:CreateButton("Hepsini gizle", function()
				Filter_SetAllTypes(false)
			end)
			if typesMenu.CreateDivider then
				typesMenu:CreateDivider()
			end
			for _, group in ipairs(NEWS_TYPE_GROUPS) do
				local sub = typesMenu:CreateButton(group.label)
				if sub then
					for _, key in ipairs(group.keys) do
						Dropdown_AddToggleEntry(sub, News_GetTypeLabel(key), function()
							Filter_EnsureTypes()
							return State.filter.types[key] == true
						end, function()
							Filter_ToggleType(key)
						end)
					end
				end
			end
			if #NEWS_TYPE_UNGROUPED > 0 then
				local sub = typesMenu:CreateButton("Diger")
				if sub then
					for _, key in ipairs(NEWS_TYPE_UNGROUPED) do
						Dropdown_AddToggleEntry(sub, News_GetTypeLabel(key), function()
							Filter_EnsureTypes()
							return State.filter.types[key] == true
						end, function()
							Filter_ToggleType(key)
						end)
					end
				end
			end
		end
	end

	styleDropdown:SetupMenu(Dropdown_Generate)

	--------------------------------------------------------
	-- List view
	--------------------------------------------------------
	local listBody = CreateFrame("Frame", "WoWGuilde_SocialListBody", groups.list)
	listBody:SetPoint("RIGHT", groups.list, "RIGHT", LIST_CFG.columnX, LIST_CFG.columnY)
	listBody:SetSize(LIST_CFG.columnWidth, LIST_CFG.columnHeight)

	local listTitle = listBody:CreateFontString(nil, "OVERLAY", nil, 2)
	listTitle:SetPoint("TOPLEFT", listBody, "TOPLEFT", 10, 40)
	listTitle:SetFont("Fonts\\MORPHEUS.ttf", 22, "OUTLINE")
	listTitle:SetTextColor(0.894, 0.655, 0.125, 1)
	listTitle:SetText("Tum haberler")

	List_UpdateTitle = function()
		if State.filter.onlyMine and State.filter.onlyProud then
			listTitle:SetText("Gurur duydugum haberler")
		elseif State.filter.onlyMine then
			listTitle:SetText("Benim haberlerim")
		elseif State.filter.onlyProud then
			listTitle:SetText("Guild gururlari")
		else
			listTitle:SetText("Tum haberler")
		end
	end
	List_UpdateTitle()

	local listFrame = CreateFrame("Frame", "WoWGuilde_SocialListFrame", listBody)
	listFrame:SetPoint("TOPLEFT", listBody, "TOPLEFT", 0, 0)
	listFrame:SetPoint("BOTTOMRIGHT", listBody, "BOTTOMRIGHT", -LIST_CFG.listFrameRightPad, 0)

	local listBg = listFrame:CreateTexture(nil, "BACKGROUND")
	listBg:SetPoint("TOPLEFT", listFrame, "TOPLEFT", -10, 10)
	listBg:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", 35, -10)
	listBg:SetAtlas("glues-gameMode-BG")
	listBg:SetAlpha(0.8)

	local listScroll = CreateFrame("ScrollFrame", "WoWGuilde_SocialListScroll", listFrame, "QuestScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, 0)
	listScroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", 0, 0)

	local listContent = CreateFrame("Frame", "WoWGuilde_SocialListContent", listScroll)
	listContent:SetSize(1, 1)
	listScroll:SetScrollChild(listContent)

	local listEntries = {}
	local listEntryCount = 0
	local listFiltered = {}
	local listFilteredSignature = ""
	local listScrollHooked = false

	local function List_CreateEntry(parent)
		listEntryCount = listEntryCount + 1
		local item = CreateFrame("Button", "WoWGuilde_SocialListEntry" .. listEntryCount, parent)
		item:SetHeight(LIST_CFG.itemHeight)
		item:EnableMouse(true)
		item:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		local bg = item:CreateTexture(nil, "BACKGROUND")
		bg:SetPoint("TOPLEFT", item, "TOPLEFT", LIST_CFG.bgLeftPad, 0)
		bg:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, 0)
		bg:SetAtlas("glues-gameMode-BG")
		bg:SetAlpha(1)
		bg:SetVertexColor(1, 1, 1, 0.8)
		item.bg = bg

		local hover = item:CreateTexture(nil, "HIGHLIGHT")
		hover:SetPoint("TOPLEFT", item, "TOPLEFT", LIST_CFG.bgLeftPad, 0)
		hover:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, 0)
		hover:SetAtlas("glues-gameMode-BG")
		hover:SetBlendMode("ADD")
		hover:SetAlpha(0.65)
		item.hover = hover

		local iconFrame = CreateFrame("Frame", item:GetName() .. "Icon", item)
		iconFrame:SetPoint("LEFT", item, "LEFT", LIST_CFG.iconPad, 0)
		iconFrame:SetSize(LIST_CFG.iconSize, LIST_CFG.iconSize)

		local icon = iconFrame:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints(iconFrame)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		item.icon = icon

		local iconOverlay = iconFrame:CreateTexture(nil, "OVERLAY")
		iconOverlay:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
		SU.Util_SetAtlasOrTexture(iconOverlay, "plunderstorm-actionbar-slot-border", "Interface\\Buttons\\WHITE8x8")
		iconOverlay:SetSize(LIST_CFG.overlaySize, LIST_CFG.overlaySize)
		iconOverlay:SetAlpha(1)
		item.iconOverlay = iconOverlay

		local proudOverlay = iconFrame:CreateTexture(nil, "OVERLAY")
		proudOverlay:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
		proudOverlay:SetAtlas("chatframe-button-highlightalert")
		proudOverlay:SetSize(LIST_CFG.iconSize + 20, LIST_CFG.iconSize + 20)
		proudOverlay:SetAlpha(0.5)
		proudOverlay:SetBlendMode("ADD")
		proudOverlay:Hide()
		item.proudOverlay = proudOverlay

		local mineBadge = CreateFrame("Button", "Minebadge", iconFrame)
		mineBadge:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", -8, -4)
		mineBadge:SetSize(14, 14)
		mineBadge:EnableMouse(true)
		mineBadge:RegisterForClicks("RightButtonUp")
		mineBadge:SetFrameLevel(iconFrame:GetFrameLevel() + 3)
		mineBadge:Hide()

		local iconFx = mineBadge:CreateTexture(nil, "BACKGROUND")
		iconFx:SetPoint("CENTER", mineBadge, "CENTER", 0, 0)
		iconFx:SetSize(18, 18)
		iconFx:SetAtlas("UI-Frame-CypherChoice-Portrait-FX-Mask")
		iconFx:SetVertexColor(1, 1, 1, 0.6)
		item.iconFx = iconFx

		local mineTex = mineBadge:CreateTexture(nil, "ARTWORK")
		mineTex:SetAllPoints(mineBadge)
		SU.Util_SetAtlasOrTexture(mineTex, BADGE_MINE_ATLAS, BADGE_MINE_TEX)
		mineBadge.icon = mineTex

		mineBadge:SetScript("OnEnter", function(self)
			if not self._isMine then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", 4, -4)
			GameTooltip:ClearLines()
			local msg = "Bu haber senin"
			if not self._isMine then
				msg = "Gurur haberi"
			end
			GameTooltip:AddLine(msg, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		mineBadge:SetScript("OnLeave", function(self)
			local parentItem = self._item
			if parentItem and parentItem:IsMouseOver() then
				local onEnter = parentItem:GetScript("OnEnter")
				if onEnter then
					onEnter(parentItem)
				end
				return
			end
			GameTooltip:Hide()
		end)
		mineBadge:SetScript("OnClick", function(self, button)
			if button ~= "RightButton" then
				return
			end
			if not self._news or not CanOpenNewsMenu(self._news, self._isMine) then
				return
			end
			ReleaseAllPearlHover()
			GameTooltip:Hide()
			Proud_OpenMenu(self, self._news, self._isMine)
		end)
		item.mineBadge = mineBadge

		local title = item:CreateFontString(nil, "OVERLAY")
		title:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", LIST_CFG.textLeftPad, -4)
		title:SetPoint("RIGHT", item, "RIGHT", -LIST_CFG.textRightPad, 0)
		title:SetFont("Fonts\\2002.ttf", 14, "OUTLINE")
		title:SetTextColor(0.894, 0.655, 0.125, 1)
		title:SetJustifyH("LEFT")
		item.title = title

		local text = item:CreateFontString(nil, "OVERLAY")
		text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
		text:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -LIST_CFG.textRightPad, LIST_CFG.textBottomPad)
		text:SetFont("Fonts\\FRIZQT__.TTF", 12)
		text:SetTextColor(1, 1, 1, 1)
		text:SetJustifyH("LEFT")
		text:SetJustifyV("TOP")
		text:SetWordWrap(true)
		item.text = text

		item:SetScript("OnEnter", function(self)
			if not self._news then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("LEFT", self, "RIGHT", 10, 0)
			GameTooltip:ClearLines()
			local titleText = self._news.title or News_GetTypeLabel(self._news.type)
			GameTooltip:AddLine(titleText, 0.8941, 0.6549, 0.1255)
			local text = self._news.text or ""
			if ns and ns.Utils and ns.Utils.ReplaceNewsTags then
				text = ns.Utils.ReplaceNewsTags(text, self._news.time)
			end
			GameTooltip:AddLine(text, 1, 1, 1, true)
			if Featured_IsNewsFeatured(Proud_GetGuildUID(self._news), self._news.id) then
				GameTooltip:AddLine("Bu basari efsane bir gurur haberi.", 1, 0.5, 0, true)
			end
			local proudLine = nil
			if Proud_IsChecked(self._news) then
				proudLine = "Haberinle gurur duyuyorsun!"
			elseif Proud_HasAnyOther(self._news) then
				local byStore = Proud_GetByStore(self._news and self._news.guildUID)
				local by = byStore and byStore[self._news.id]
				local name = Proud_PickAnyName(by, self._news.guildUID)
				if name and name ~= "" then
					proudLine = name
						.. " bu haberle cok gurur duyuyor!\nTebrik etmeyi unutma."
				end
			end
			if proudLine then
				GameTooltip:AddLine(proudLine, 0.95, 0.82, 0.35, true)
			end
			GameTooltip:AddLine(SU.Util_PrettyTimeAgo(self._news.time), 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		item:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		item:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				if self._news and CanOpenNewsMenu(self._news, self._isMine) then
					GameTooltip:Hide()
					Proud_OpenMenu(self, self._news, self._isMine)
				end
				return
			end
			if self._action then
				self._action()
			end
		end)

		return item
	end

	local function List_SetEntryData(item, news)
		local title = (news and news.title) or (news and News_GetTypeLabel(news.type)) or "Haber"
		local body = (news and news.text) or ""
		title = title:gsub("[\r\n]+", " ")
		body = body:gsub("[\r\n]+", " ")
		if news and ns and ns.Utils and ns.Utils.ReplaceNewsTags then
			body = ns.Utils.ReplaceNewsTags(body, news.time)
		end
		item.title:SetText(title)
		item.text:SetText(body)
		item._news = news
		item._isMine = not not (news and Filter_IsMyNews(news))
		local isFeatured = news and news.id and Featured_IsNewsFeatured(news.guildUID, news.id)
		local proudOther = news and Proud_HasAnyOther(news)
		local proudMe = news and Proud_IsChecked(news)
		local proudAny = (not not proudOther) or not not proudMe
		if isFeatured then
			proudAny = true
		end
		if news and news.icon and item.icon then
			SU.Util_SetPearlIcon(item.icon, news.icon, LIST_CFG.iconSize)
		else
			SU.Util_SetPearlIcon(item.icon, nil, LIST_CFG.iconSize)
		end
		if item.mineBadge then
			local isMine = item._isMine
			local showBadge = not not isMine
			item.mineBadge:SetShown(showBadge)
			item.mineBadge._news = news
			item.mineBadge._item = item
			item.mineBadge._isMine = not not isMine
			item.mineBadge._proudAny = not not proudAny
			local badgeAtlas = proudAny and BADGE_PROUD_ATLAS or BADGE_MINE_ATLAS
			local badgeFallback = proudAny and BADGE_PROUD_TEX or BADGE_MINE_TEX
			if item.mineBadge.icon then
				SU.Util_SetAtlasOrTexture(item.mineBadge.icon, badgeAtlas, badgeFallback)
				if isFeatured then
					item.mineBadge.icon:SetVertexColor(FEATURED_BORDER_R, FEATURED_BORDER_G, FEATURED_BORDER_B, 1)
				elseif proudOther and not Proud_IsChecked(news) then
					item.mineBadge.icon:SetVertexColor(0.25, 1, 0.35, 1)
				else
					item.mineBadge.icon:SetVertexColor(1, 1, 1, 1)
				end
			end
			if item.iconOverlay then
				if isFeatured then
					item.iconOverlay:SetVertexColor(FEATURED_BORDER_R, FEATURED_BORDER_G, FEATURED_BORDER_B, 1)
				elseif proudAny then
					item.iconOverlay:SetVertexColor(PROUD_BORDER_R, PROUD_BORDER_G, PROUD_BORDER_B, 1)
				else
					item.iconOverlay:SetVertexColor(1, 1, 1, 1)
				end
			end
			if item.proudOverlay then
				item.proudOverlay:SetShown(proudAny or isFeatured)
				if isFeatured then
					item.proudOverlay:SetVertexColor(FEATURED_BORDER_R, FEATURED_BORDER_G, FEATURED_BORDER_B, 0.5)
				elseif proudAny then
					if Proud_IsChecked(news) then
						item.proudOverlay:SetVertexColor(1, 1, 1, 0.5)
					else
						item.proudOverlay:SetVertexColor(0.25, 1, 0.35, 0.4)
					end
				end
			end
		end
	end

	local newsQueue, newsIndex = {}, 0

	local function List_BuildFilteredNews()
		local filtered = {}
		local gid = SU.Util_GetActiveGuildUID()
		if gid and gid ~= "" then
			for i = 1, #newsQueue do
				local news = newsQueue[i]
				if news and SU.Util_IsSameGuildUID(news.guildUID, gid) and Filter_IsNewsAllowed(news) then
					filtered[#filtered + 1] = news
				end
			end
		end
		table.sort(filtered, function(a, b)
			return (a.time or 0) > (b.time or 0)
		end)
		return filtered, gid
	end

	local function List_MakeFilteredSignature(filtered, gid)
		local out = { tostring(gid or ""), tostring(#filtered) }
		for i = 1, #filtered do
			local n = filtered[i]
			out[#out + 1] = tostring(n and n.id or "")
			out[#out + 1] = tostring(n and n.time or 0)
		end
		return table.concat(out, "|")
	end

	local function List_RenderWindow()
		local y = 0
		local itemStep = (LIST_CFG.itemHeight or 40) + (LIST_CFG.itemSpacing or 0)
		local windowSize = math.max(1, tonumber(LIST_CFG.virtualWindow or 20) or 20)
		local maxW = listFrame:GetWidth() > 0 and listFrame:GetWidth() or 600
		listContent:SetWidth(maxW)

		local displayIndex = 0
		local total = #listFiltered
		local first = 1
		if total > 0 then
			local offset = listScroll:GetVerticalScroll() or 0
			first = math.floor(offset / itemStep) + 1
			local maxFirst = math.max(1, total - windowSize + 1)
			if first < 1 then
				first = 1
			elseif first > maxFirst then
				first = maxFirst
			end
		end
		local last = math.min(total, first + windowSize - 1)
		for i = first, last do
			local news = listFiltered[i]
			displayIndex = displayIndex + 1
			local item = listEntries[displayIndex]
			if not item then
				item = List_CreateEntry(listContent)
				listEntries[displayIndex] = item
			end
			item:ClearAllPoints()
			y = (i - 1) * itemStep
			item:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -y)
			item:SetPoint("RIGHT", listContent, "RIGHT", -LIST_CFG.scrollRightPad, 0)
			item:SetWidth(maxW)
			item:Show()
			List_SetEntryData(item, news)
			item._action = nil
		end

		if displayIndex == 0 and not Filter_AnyTypeEnabled() then
			displayIndex = 1
			local item = listEntries[displayIndex]
			if not item then
				item = List_CreateEntry(listContent)
				listEntries[displayIndex] = item
			end
			item:ClearAllPoints()
			item:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -y)
			item:SetPoint("RIGHT", listContent, "RIGHT", -LIST_CFG.scrollRightPad, 0)
			item:SetWidth(maxW)
			item:Show()
			item.title:SetText("Aktif filtre yok")
			item.text:SetText("Etkinlestirmek icin tikla")
			item._news = nil
			item._action = Filter_EnableAll
			if item.mineBadge then
				item.mineBadge:SetShown(false)
				item.mineBadge._news = nil
				item.mineBadge._item = item
				item.mineBadge._isMine = false
				item.mineBadge._proudAny = false
				if item.mineBadge.icon then
					item.mineBadge.icon:SetVertexColor(1, 1, 1, 1)
				end
			end
			if item.icon then
				SU.Util_SetPearlIcon(item.icon, 3717420, LIST_CFG.iconSize)
			end
			if item.iconOverlay then
				item.iconOverlay:SetVertexColor(1, 1, 1, 1)
			end
			if item.proudOverlay then
				item.proudOverlay:Hide()
			end
			y = itemStep
			listContent:SetHeight(math.max(y, 1))
		else
			listContent:SetHeight(math.max(total * itemStep, 1))
		end

		for i = displayIndex + 1, #listEntries do
			listEntries[i]:Hide()
		end
	end

	List_Refresh = function()
		if not newsQueue then
			return
		end
		local filtered, gid = List_BuildFilteredNews()
		local signature = List_MakeFilteredSignature(filtered, gid)
		listFiltered = filtered
		local hasChanged = (signature ~= listFilteredSignature)
		listFilteredSignature = signature

		if hasChanged and listScroll and listScroll.SetVerticalScroll then
			local maxOffset = math.max(
				(#listFiltered * ((LIST_CFG.itemHeight or 40) + (LIST_CFG.itemSpacing or 0)))
					- (listScroll:GetHeight() or 0),
				0
			)
			local offset = listScroll:GetVerticalScroll() or 0
			if offset > maxOffset then
				listScroll:SetVerticalScroll(maxOffset)
			end
		end

		List_RenderWindow()
		if not listScrollHooked then
			listScrollHooked = true
			listScroll:HookScript("OnVerticalScroll", function()
				List_RenderWindow()
			end)
			listScroll:HookScript("OnSizeChanged", function()
				List_RenderWindow()
			end)
		end
	end

	--------------------------------------------------------
	-- Orb + rings
	--------------------------------------------------------
	local orb = CreateFrame("Frame", "WoWGuilde_SocialOrb", groups.rings)
	orb:SetPoint("CENTER")
	orb:SetSize(CFG.ORB_SIZE, CFG.ORB_SIZE)

	local orbCore = orb:CreateTexture(nil, "ARTWORK")
	orbCore:SetAllPoints(orb)
	orbCore:SetSize(222, 222)
	orbCore:SetAtlas("heartofazeroth-orb-shadow")
	orbCore:SetAlpha(1)

	local ring = orb:CreateTexture(nil, "OVERLAY")
	ring:SetAllPoints(orb)
	ring:SetAtlas("heartofazeroth-orb-glass")
	ring:SetAlpha(0.5)
	ring:SetBlendMode("ADD")

	local orbGlow = orb:CreateTexture(nil, "BACKGROUND")
	orbGlow:SetPoint("CENTER")
	orbGlow:SetSize(320, 338)
	orbGlow:SetAtlas("common-mask-circle")
	orbGlow:SetVertexColor(0, 0, 0, 0.2)

	local glow2 = orb:CreateTexture(nil, "BACKGROUND")
	glow2:SetPoint("CENTER")
	glow2:SetSize(440, 418)
	glow2:SetAtlas("common-mask-circle")
	glow2:SetVertexColor(0, 0, 0, 0.12)

	local cohesionFS = orb:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	cohesionFS:SetDrawLayer("OVERLAY", 1)
	cohesionFS:SetPoint("CENTER", 0, -2)
	cohesionFS:SetTextColor(1, 1, 1, 0.95)
	cohesionFS:SetText("0")

	local cohesionBg = orb:CreateTexture(nil, "OVERLAY")
	cohesionBg:SetDrawLayer("OVERLAY", 0)
	cohesionBg:SetPoint("CENTER", cohesionFS, "CENTER", 0, -2)
	cohesionBg:SetSize(120, 85)
	cohesionBg:SetAtlas("UI-Frame-CypherChoice-CountdownShadow", true)
	cohesionBg:SetAlpha(1)

	local TOKEN_CFG = {
		size = 220,
		fillAtlas = "evergreen-weeklyrewards-reward-unlocked-fx-swirl",
	}

	local tokenFrame = CreateFrame("Frame", "WoWGuilde_SocialTokens", orb)
	tokenFrame:SetPoint("CENTER", orb, "CENTER", 0, 0)
	tokenFrame:SetSize(TOKEN_CFG.size, TOKEN_CFG.size)

	local orbTop = CreateFrame("Frame", nil, orb)
	orbTop:SetAllPoints(orb)
	-- Keep the orb top effect above orb core, but below pearls layer.
	orbTop:SetFrameLevel(orb:GetFrameLevel() + 1)

	local orbCoreTop = orbTop:CreateTexture(nil, "OVERLAY", nil, 7)
	orbCoreTop:SetAllPoints(orbTop)
	orbCoreTop:SetSize(222, 222)
	orbCoreTop:SetAtlas("heartofazeroth-orb-shadow")
	orbCoreTop:SetAlpha(1)

	local tokenFill = CreateFrame("StatusBar", nil, tokenFrame)
	tokenFill:SetAllPoints(tokenFrame)
	tokenFill:SetMinMaxValues(0, 1)
	tokenFill:SetValue(0)
	tokenFill:SetOrientation("VERTICAL")

	local fillTex = tokenFill:CreateTexture(nil, "BACKGROUND")
	fillTex:SetAllPoints(tokenFill)
	fillTex:SetDrawLayer("BACKGROUND", -2)
	fillTex:SetAtlas("AdventureMap_TileBg_Parchment", true)
	fillTex:SetBlendMode("ADD")
	fillTex:SetVertexColor(0.961, 1, 0.914, 0.352)
	tokenFill:SetStatusBarTexture(fillTex)
	tokenFill._fillTex = fillTex

	-- progress edge sparkle (masked) + top edge glow
	local progressEdge = tokenFrame:CreateTexture(nil, "OVERLAY")
	progressEdge:SetAtlas("evergreen-weeklyrewards-reward-selected-edgeglow", true)
	progressEdge:SetBlendMode("ADD")
	progressEdge:SetAlpha(0.85)
	local progressEdgeAnim = progressEdge:CreateAnimationGroup()
	progressEdgeAnim:SetLooping("REPEAT")
	local edgeRot = progressEdgeAnim:CreateAnimation("Rotation")
	edgeRot:SetOrigin("CENTER", 0, 0)
	edgeRot:SetDegrees(-360)
	edgeRot:SetDuration(1)
	progressEdgeAnim:Play()

	local progressEdgeMask = tokenFrame:CreateMaskTexture(nil, "OVERLAY")
	progressEdgeMask:SetAtlas("UI-Frame-CypherChoice-Portrait-FX-Mask", true)
	progressEdgeMask:SetSize(TOKEN_CFG.size + 10, 6)
	progressEdgeMask:SetPoint("CENTER", tokenFrame, "CENTER", 0, 0)
	progressEdge:AddMaskTexture(progressEdgeMask)

	local progressCircleMask = tokenFrame:CreateMaskTexture(nil, "OVERLAY")
	progressCircleMask:SetAtlas("common-mask-circle", true)
	progressCircleMask:SetAllPoints(tokenFrame)
	progressEdge:AddMaskTexture(progressCircleMask)

	local function SetProgressEdgePct(pct)
		if pct < 0 then
			pct = 0
		end
		if pct > 1 then
			pct = 1
		end
		if pct == 0 or pct == 1 then
			progressEdge:Hide()
		else
			progressEdge:Show()
		end
		local y = -TOKEN_CFG.size * 0.5 + (TOKEN_CFG.size * pct)
		progressEdge:ClearAllPoints()
		progressEdge:SetPoint("CENTER", tokenFrame, "CENTER", 0, y)
		progressEdgeMask:ClearAllPoints()
		progressEdgeMask:SetPoint("CENTER", tokenFrame, "CENTER", 0, y)
	end

	local SPIN_CFG = {
		{ size = 1, color = { 1, 1, 1, 0.851 }, degrees = -360, duration = 20 },
		{ size = 0.8, color = { 1, 1, 1, 0.851 }, degrees = -360, duration = 16 },
		{ size = 0.6, color = { 1, 1, 1, 0.851 }, degrees = -360, duration = 12 },
		{ size = 0.4, color = { 1, 1, 1, 0.851 }, degrees = -360, duration = 9 },
		{ size = 0.2, color = { 1, 1, 1, 0.851 }, degrees = -360, duration = 9 },
	}

	local spinTextures = {}
	local function CreateSpinTex(size, color, degrees, duration)
		local r, g, b, a = color[1], color[2], color[3], color[4]
		local t = tokenFrame:CreateTexture(nil, "BACKGROUND")
		t:SetPoint("CENTER", tokenFrame, "CENTER", 0, 0)
		t:SetSize(TOKEN_CFG.size * size, TOKEN_CFG.size * size)
		t:SetAtlas(TOKEN_CFG.fillAtlas, false)
		t:SetTexCoord(0, 1, 0, 1)
		t:SetVertexColor(r, g, b, a)
		t:SetAlpha(a)

		local ag = t:CreateAnimationGroup()
		ag:SetLooping("REPEAT")
		local rot = ag:CreateAnimation("Rotation")
		rot:SetOrigin("CENTER", 0, 0)
		rot:SetDegrees(degrees)
		rot:SetDuration(duration)
		ag:Play()

		return t
	end

	for i = 1, #SPIN_CFG do
		local cfg = SPIN_CFG[i]
		spinTextures[#spinTextures + 1] = CreateSpinTex(cfg.size, cfg.color, cfg.degrees, cfg.duration)
	end

	-- shared mask applied to the group (fill + spin)
	if tokenFrame.CreateMaskTexture then
		local groupMask = tokenFrame:CreateMaskTexture(nil, "OVERLAY")
		groupMask:SetAtlas("item_upgrade_tooltip_fullmask", true)
		groupMask:SetSize(240, TOKEN_CFG.size)
		groupMask:SetPoint("BOTTOM", tokenFrame, "BOTTOM", 0, 0)
		fillTex:AddMaskTexture(groupMask)
		for i = 1, #spinTextures do
			spinTextures[i]:AddMaskTexture(groupMask)
		end
		local progressMask = tokenFrame:CreateMaskTexture(nil, "OVERLAY")
		progressMask:SetAtlas("common-mask-circle", true)
		progressMask:SetAllPoints(tokenFrame)
		fillTex:AddMaskTexture(progressMask)

		local function SetMaskHeightPct(pct)
			if pct < 0 then
				pct = 0
			end
			if pct > 1 then
				pct = 1
			end
			groupMask:SetSize(220, TOKEN_CFG.size * pct)
			groupMask:ClearAllPoints()
			groupMask:SetPoint("BOTTOM", tokenFrame, "BOTTOM", 0, 0)
		end

		SetMaskHeightPct(1)
		f._SetTokenMaskPct = SetMaskHeightPct
	end

	SetProgressEdgePct(0)
	f._SetTokenEdgePct = SetProgressEdgePct

	f._tokensText = cohesionFS
	f._tokensFill = tokenFill
	f._tokensSize = TOKEN_CFG.size

	--------------------------------------------------------
	-- Orb hover tooltip (progression par groupe)
	--------------------------------------------------------
	local ORB_TT_CFG = {
		width = 528,
		height = 325,
		padTop = 10,
		padBottom = 12,
		barHeight = 160,
		barWidth = 20,
		barSpacing = 24,
		iconSize = 22,
		iconRaise = 0,
		iconPad = 4,
		pctGap = 2,
		barGap = 4,
		titleFont = "Fonts\\2002.TTF",
		descFont = "Fonts\\FRIZQT__.TTF",
	}

	local ORB_GROUP_ICONS = {
		quests = "SmallQuestBang",
		world = "poi-islands-table",
		progression = "poi-workorders",
		combat = "VignetteEventElite",
		loot = "Auctioneer",
		collections = "poi-transmogrifier",
		communications = "Mailbox",
	}
	local ORB_GROUP_STORY = {
		quests = {
			top = "Kahramanlar gorevleri arka arkaya yapmayi seviyor",
			low = "Gorevler ikinci planda",
		},
		world = {
			top = "Kahramanlar dunyada macerayi seviyor",
			low = "Dunya daha az kesfediliyor",
		},
		progression = {
			top = "Kahramanlar ilerlemeye odakli",
			low = "Ilerleme daha sakin",
		},
		combat = {
			top = "Kahramanlar savasmayi seviyor",
			low = "Savaslar daha seyrek",
		},
		loot = {
			top = "Kahramanlar ganimet pesinde",
			low = "Ganimet avciligi daha sakin",
		},
		collections = {
			top = "Kahramanlar koleksiyon tamamlamayi seviyor",
			low = "Koleksiyon daha az on planda",
		},
		communications = {
			top = "Kahramanlar iletisimi tercih ediyor",
			low = "Iletisim daha az",
		},
	}

	local orbTooltip = CreateFrame("Frame", "WoWGuilde_SocialOrbTooltip", groups.rings)
	orbTooltip:SetPoint("TOP", orb, "BOTTOM", 0, 100)
	orbTooltip:SetSize(ORB_TT_CFG.width, ORB_TT_CFG.height)
	orbTooltip:SetFrameStrata("DIALOG")
	orbTooltip:SetFrameLevel(orb:GetFrameLevel() + 20)
	orbTooltip:EnableMouse(true)
	orbTooltip:Hide()

	local orbTooltipBg = orbTooltip:CreateTexture(nil, "BACKGROUND")
	orbTooltipBg:SetAllPoints(orbTooltip)
	orbTooltipBg:SetAtlas("common-dropdown-bg")
	orbTooltipBg:SetVertexColor(1, 1, 1, 1)

	local orbTooltipEdge = orbTooltip:CreateTexture(nil, "BORDER")
	orbTooltipEdge:SetPoint("CENTER", orbTooltip, "TOP", 4, 12)
	orbTooltipEdge:SetSize(170, 80)
	orbTooltipEdge:SetAtlas("common-dropdown-bg", false)
	orbTooltipEdge:SetVertexColor(1, 1, 1, 1)

	local orbTooltipScoreTop = orbTooltip:CreateFontString(nil, "OVERLAY", nil, 2)
	orbTooltipScoreTop:SetPoint("BOTTOM", orbTooltip, "TOP", 0, -2)
	orbTooltipScoreTop:SetFont(ORB_TT_CFG.titleFont, 34, "")
	orbTooltipScoreTop:SetTextColor(0.90, 0.90, 0.90, 0.9)
	orbTooltipScoreTop:SetText("0")
	orbTooltipScoreTop:SetJustifyH("CENTER")

	local orbTooltipTitle = orbTooltip:CreateFontString(nil, "OVERLAY", nil, 2)
	orbTooltipTitle:SetPoint("TOP", orbTooltipScoreTop, "BOTTOM", 0, -20)
	orbTooltipTitle:SetFont(ORB_TT_CFG.titleFont, 20, "")
	orbTooltipTitle:SetTextColor(1, 0.725, 0, 1)
	orbTooltipTitle:SetText("Guild barometresi")
	orbTooltipTitle:SetJustifyH("CENTER")

	local orbTooltipDesc = orbTooltip:CreateFontString(nil, "OVERLAY")
	orbTooltipDesc:SetPoint("TOP", orbTooltipTitle, "BOTTOM", 0, -10)
	orbTooltipDesc:SetWidth(ORB_TT_CFG.width - 200)
	orbTooltipDesc:SetFont(ORB_TT_CFG.descFont, 12, "")
	orbTooltipDesc:SetTextColor(0.92, 0.92, 0.92, 0.9)
	orbTooltipDesc:SetJustifyH("CENTER")
	orbTooltipDesc:SetJustifyV("TOP")
	orbTooltipDesc:SetText("En dolu: — · En bos: —")

	local barsFrame = CreateFrame("Frame", nil, orbTooltip)
	barsFrame:SetPoint("BOTTOM", orbTooltip, "BOTTOM", 0, ORB_TT_CFG.padBottom)

	local barsByKey = {}
	local barsOrder = {}
	do
		local groupsCfg = (GP and GP.Config and GP.Config.groups) or {}
		for i = 1, #groupsCfg do
			local cfg = groupsCfg[i]
			if cfg and cfg.key and cfg.key ~= "divers" then
				barsOrder[#barsOrder + 1] = cfg
			end
		end
	end

	local function Clamp01(v)
		if SU and SU.Util_Clamp01 then
			return SU.Util_Clamp01(v)
		end
		if v < 0 then
			return 0
		end
		if v > 1 then
			return 1
		end
		return v
	end

	local iconRaise = math.max(0, tonumber(ORB_TT_CFG.iconRaise or 0) or 0)
	local slotHeight = ORB_TT_CFG.barHeight + ORB_TT_CFG.iconSize - iconRaise
	if slotHeight < ORB_TT_CFG.barHeight then
		slotHeight = ORB_TT_CFG.barHeight
	end
	barsFrame:SetSize(ORB_TT_CFG.width, slotHeight)

	local function ShowSectionBarTooltip(bar)
		if not (bar and GameTooltip) then
			return
		end
		local title = tostring(bar._groupLabel or bar._groupKey or "—")
		local pct = tonumber(bar._pctValue or 0) or 0
		if pct < 0 then
			pct = 0
		elseif pct > 100 then
			pct = 100
		end
		GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
		GameTooltip:ClearLines()
		GameTooltip:AddLine(title, 1, 0.78, 0.18, 1)
		GameTooltip:AddLine(string.format("%d%%", math.floor(pct + 0.5)), 0.95, 0.95, 0.95, 1)
		GameTooltip:Show()
	end

	local function HideSectionBarTooltip()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end

	local function FormatScore(n)
		local v = tonumber(n or 0) or 0
		if ns.Utils and ns.Utils.FormatThousands then
			return ns.Utils.FormatThousands(v)
		end
		return tostring(math.floor(v + 0.5))
	end

	do
		local barCount = #barsOrder
		if barCount < 1 then
			barCount = 1
		end
		local totalWidth = (barCount * ORB_TT_CFG.barWidth) + ((barCount - 1) * ORB_TT_CFG.barSpacing)
		local startX = -(totalWidth * 0.5) + (ORB_TT_CFG.barWidth * 0.5)
		for i = 1, #barsOrder do
			local cfg = barsOrder[i]
			local barSlot = CreateFrame("Frame", nil, barsFrame)
			barSlot:SetSize(ORB_TT_CFG.barWidth, slotHeight)
			barSlot:SetPoint(
				"BOTTOM",
				barsFrame,
				"BOTTOM",
				startX + ((i - 1) * (ORB_TT_CFG.barWidth + ORB_TT_CFG.barSpacing)),
				0
			)

			local bar = CreateFrame("StatusBar", nil, barSlot)
			bar:SetSize(ORB_TT_CFG.barWidth, ORB_TT_CFG.barHeight)
			bar:SetPoint("BOTTOM", barSlot, "BOTTOM", 0, ORB_TT_CFG.iconSize + 18)
			bar:EnableMouse(true)
			bar:SetOrientation("VERTICAL")
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(0)
			local barFill = bar:CreateTexture(nil, "BORDER", nil, -2)
			barFill:SetAllPoints(bar)
			barFill:SetAtlas("ui-castingbar-disabled-tier2-empower-2x", true)
			barFill:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
			bar:SetStatusBarTexture(barFill)
			bar:SetReverseFill(false)
			if type(cfg.color) == "table" then
				bar:SetStatusBarColor(0.518, 0.518, 0.518, 1)
			else
				bar:SetStatusBarColor(0.8, 0.8, 0.8, 1)
			end

			local iconLayer = CreateFrame("Frame", nil, barSlot)
			iconLayer:SetAllPoints(barSlot)
			iconLayer:SetFrameLevel(bar:GetFrameLevel() + 12)

			local barBorder = bar:CreateTexture(nil, "OVERLAY", nil, 7)
			barBorder:SetAllPoints(bar)
			barBorder:SetDrawLayer("OVERLAY", 7)
			barBorder:SetAtlas("timerunning-dialog-frametop", true)
			barBorder:SetAlpha(0.7)
			bar.border = barBorder

			local iconBg = iconLayer:CreateTexture(nil, "BACKGROUND")
			iconBg:SetSize(25, 25)
			iconBg:SetPoint("BOTTOM", barSlot, "BOTTOM", 0, 20)
			iconBg:SetAtlas("AdventureMapQuest-PortraitBG", false)
			iconBg:SetVertexColor(0, 0, 0, 1)

			local icon = iconLayer:CreateTexture(nil, "ARTWORK")
			icon:SetPoint("CENTER", iconBg, "CENTER", 0, 0)
			icon:SetSize(ORB_TT_CFG.iconSize, ORB_TT_CFG.iconSize)
			icon:SetAtlas(ORB_GROUP_ICONS[cfg.key] or "common-mask-circle", false)
			icon:SetDesaturated(true)
			icon:SetVertexColor(1, 0.867, 0.541, 1)

			local iconOverlay = iconLayer:CreateTexture(nil, "OVERLAY")
			iconOverlay:SetPoint("CENTER", iconBg, "CENTER", 0, 0)
			iconOverlay:SetSize(ORB_TT_CFG.iconSize + 12, ORB_TT_CFG.iconSize + 12)
			iconOverlay:SetAtlas("Evergreen-toast-celebration-content-ring", false)
			iconOverlay:SetAlpha(1)

			local pctText = iconLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			pctText:SetPoint("BOTTOM", bar, "BOTTOM", 0, 10)
			pctText:SetTextColor(1, 1, 1, 1)
			pctText:SetText("0")

			local pctShadow = iconLayer:CreateTexture(nil, "ARTWORK")
			pctShadow:SetPoint("CENTER", pctText, "CENTER", 0, -1)
			pctShadow:SetSize(ORB_TT_CFG.barWidth + 14, 20)
			pctShadow:SetAtlas("UI-Frame-CypherChoice-CountdownShadow", false)
			pctShadow:SetVertexColor(0, 0, 0, 0.9)
			pctShadow:SetAlpha(0.85)

			bar._groupKey = cfg.key
			bar._groupLabel = cfg.label or cfg.key
			bar._pctValue = 0
			bar._pctText = pctText
			bar._icon = icon
			bar:SetScript("OnEnter", function(self)
				ShowSectionBarTooltip(self)
			end)
			bar:SetScript("OnLeave", HideSectionBarTooltip)
			barsByKey[cfg.key] = bar
		end
	end

	OrbTooltip_Update = function(summary)
		if not summary and Progress_GetSummary then
			summary = Progress_GetSummary()
		end
		if not summary or type(summary.groups) ~= "table" then
			orbTooltipDesc:SetText("Ilerleme verisi yok.")
			for _, bar in pairs(barsByKey) do
				bar:SetValue(0)
				bar._pctValue = 0
				if bar._pctText then
					bar._pctText:SetText("0")
				end
				if bar:IsMouseOver() then
					ShowSectionBarTooltip(bar)
				end
			end
			return
		end

		local totalPoints = tonumber(summary.totalPoints or summary.totalPointsRaw or 0) or 0
		if totalPoints <= 0 then
			orbTooltipDesc:SetText("Tercih cikarmak icin yeterli veri yok.")
			for _, bar in pairs(barsByKey) do
				bar:SetValue(0)
				bar._pctValue = 0
				if bar._pctText then
					bar._pctText:SetText("0")
				end
				if bar:IsMouseOver() then
					ShowSectionBarTooltip(bar)
				end
			end
			orbTooltipScoreTop:SetText("0")
			return
		end

		local function GetShare(g)
			if g.share ~= nil then
				return Clamp01(tonumber(g.share or 0) or 0)
			end
			return Clamp01((tonumber(g.points or 0) or 0) / totalPoints)
		end

		local function RatioToPct(ratio)
			local pct = math.floor(Clamp01(ratio) * 100 + 0.5)
			if pct < 0 then
				pct = 0
			elseif pct > 100 then
				pct = 100
			end
			return pct
		end

		local function StoryFor(key, label, which)
			local entry = ORB_GROUP_STORY[key]
			if entry and entry[which] then
				return entry[which]
			end
			if which == "top" then
				return "Les héros préfèrent " .. (label or "ce domaine")
			end
			return (label or "Ce domaine") .. " est moins mis en avant"
		end

		local top, low = nil, nil
		for i = 1, #summary.groups do
			local g = summary.groups[i]
			if g and g.key and g.key ~= "divers" then
				local share = GetShare(g)
				if not top or share > top.share then
					top = { key = g.key, label = g.label or g.key, share = share }
				end
				if not low or share < low.share then
					low = { key = g.key, label = g.label or g.key, share = share }
				end
			end
		end

		local topPct = top and RatioToPct(top.share) or 0
		local lowPct = low and RatioToPct(low.share) or 0
		local topText = top and StoryFor(top.key, top.label, "top") or "Les héros préfèrent —"
		local lowText = low and StoryFor(low.key, low.label, "low") or "— est moins mis en avant"
		orbTooltipDesc:SetText(string.format("%s (%d%%).\n%s (%d%%).", topText, topPct, lowText, lowPct))
		local scoreText = FormatScore(summary.totalPoints or summary.totalPointsRaw or 0)
		orbTooltipScoreTop:SetText(scoreText)

		for i = 1, #summary.groups do
			local g = summary.groups[i]
			if g and g.key and g.key ~= "divers" then
				local bar = barsByKey[g.key]
				if bar then
					local share = GetShare(g)
					local pct = RatioToPct(share)
					bar:SetValue(Clamp01(share))
					bar._pctValue = pct
					if bar._pctText then
						bar._pctText:SetText(tostring(pct))
					end
					if bar:IsMouseOver() then
						ShowSectionBarTooltip(bar)
					end
				end
			end
		end
	end

	local function ShowOrbTooltip(owner)
		if not GameTooltip then
			return
		end
		local summary = Progress_GetSummary and Progress_GetSummary() or nil
		GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("Guild barometresi", 1, 0.78, 0.18, 1)
		if not summary or type(summary.groups) ~= "table" then
			GameTooltip:AddLine("Ilerleme verisi yok.", 0.9, 0.9, 0.9, 1)
			GameTooltip:Show()
			return
		end

		local totalPoints = tonumber(summary.totalPoints or summary.totalPointsRaw or 0) or 0
		GameTooltip:AddLine("Skor: " .. FormatScore(totalPoints), 0.95, 0.95, 0.95, 1)
		GameTooltip:AddLine(" ")

		local groupsByKey = {}
		for i = 1, #summary.groups do
			local g = summary.groups[i]
			if g and g.key then
				groupsByKey[g.key] = g
			end
		end

		local function GetShare(g)
			if g.share ~= nil then
				return Clamp01(tonumber(g.share or 0) or 0)
			end
			if totalPoints > 0 then
				return Clamp01((tonumber(g.points or 0) or 0) / totalPoints)
			end
			return 0
		end

		local function RatioToPct(ratio)
			local pct = math.floor(Clamp01(ratio) * 100 + 0.5)
			if pct < 0 then
				pct = 0
			elseif pct > 100 then
				pct = 100
			end
			return pct
		end

		local shown = {}
		for i = 1, #barsOrder do
			local cfg = barsOrder[i]
			local g = cfg and groupsByKey[cfg.key] or nil
			if g and g.key and g.key ~= "divers" then
				local pct = RatioToPct(GetShare(g))
				local label = g.label or cfg.label or g.key
				GameTooltip:AddLine(string.format("%s : %d%%", label, pct), 0.9, 0.9, 0.9, 1)
				shown[g.key] = true
			end
		end
		for i = 1, #summary.groups do
			local g = summary.groups[i]
			if g and g.key and g.key ~= "divers" and not shown[g.key] then
				local pct = RatioToPct(GetShare(g))
				local label = g.label or g.key
				GameTooltip:AddLine(string.format("%s : %d%%", label, pct), 0.9, 0.9, 0.9, 1)
			end
		end

		local function StoryFor(key, label, which)
			local entry = ORB_GROUP_STORY[key]
			if entry and entry[which] then
				return entry[which]
			end
			if which == "top" then
				return "Les héros préfèrent " .. (label or "ce domaine")
			end
			return (label or "Ce domaine") .. " est moins mis en avant"
		end

		local top, low = nil, nil
		for i = 1, #summary.groups do
			local g = summary.groups[i]
			if g and g.key and g.key ~= "divers" then
				local share = GetShare(g)
				if not top or share > top.share then
					top = { key = g.key, label = g.label or g.key, share = share }
				end
				if not low or share < low.share then
					low = { key = g.key, label = g.label or g.key, share = share }
				end
			end
		end

		GameTooltip:AddLine(" ")
		if totalPoints <= 0 or not top or not low then
			GameTooltip:AddLine("Tercih cikarmak icin yeterli veri yok.", 0.8, 0.8, 0.8, 1, true)
		else
			local topPct = RatioToPct(top.share)
			local lowPct = RatioToPct(low.share)
			local topText = StoryFor(top.key, top.label, "top")
			local lowText = StoryFor(low.key, low.label, "low")
			GameTooltip:AddLine(string.format("%s (%d%%).", topText, topPct), 0.85, 0.85, 0.85, 1, true)
			GameTooltip:AddLine(string.format("%s (%d%%).", lowText, lowPct), 0.85, 0.85, 0.85, 1, true)
		end

		GameTooltip:SetScript("OnUpdate", function(self)
			local x, y = GetCursorPosition()
			if not x or not y then
				return
			end
			local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
			self:ClearAllPoints()
			self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (x / scale) + 16, (y / scale) + 16)
		end)
		GameTooltip:Show()
	end

	local function HideOrbTooltip()
		if GameTooltip then
			GameTooltip:SetScript("OnUpdate", nil)
			GameTooltip:Hide()
		end
	end

	local orbHit = CreateFrame("Button", nil, orb)
	orbHit:SetAllPoints(orb)
	orbHit:EnableMouse(true)
	local function Tooltip_Show()
		ShowOrbTooltip(orbHit)
	end
	local function Tooltip_Hide()
		HideOrbTooltip()
	end
	orbHit:SetScript("OnEnter", Tooltip_Show)
	orbHit:SetScript("OnLeave", Tooltip_Hide)
	orbTooltip:SetScript("OnEnter", nil)
	orbTooltip:SetScript("OnLeave", nil)

	local rings = {}
	do
		local function CreateDecorRing(radius, alpha, index)
			local rf = CreateFrame("Frame", "WoWGuilde_SocialDecorRing" .. index, groups.rings)
			rf:SetPoint("CENTER", groups.rings, "CENTER")
			rf:SetSize(radius * 2.05, radius * 2.05)

			local t = rf:CreateTexture(nil, "ARTWORK")
			t:SetAllPoints(rf)
			SU.Util_SetAtlasOrTexture(t, "Azerite-GoldRing-Rank4", "Interface\\Buttons\\UI-Quickslot2")
			t:SetVertexColor(1, 1, 1, 1)

			rf._rot, rf._tex1 = 0, t
			return rf
		end

		for i, cfg in ipairs(RINGS_CFG) do
			rings[i] = {
				radius = cfg.radius,
				baseSpeed = cfg.baseSpeed,
				curSpeed = cfg.baseSpeed,
				targetSpeed = cfg.baseSpeed,
				spinSpeed = cfg.spinSpeed or cfg.baseSpeed,
				frame = CreateDecorRing(cfg.radius, cfg.alpha, i),
				maxActive = cfg.maxActive,
				iconSize = cfg.iconSize,
				iconOffsetX = cfg.iconOffsetX or 0,
				iconOffsetY = cfg.iconOffsetY or 0,
				ringOffsetX = cfg.ringOffsetX or 0,
				ringOffsetY = cfg.ringOffsetY or 0,
				extraTexOffsetX = cfg.extraTexOffsetX or 0,
				extraTexOffsetY = cfg.extraTexOffsetY or 0,
			}

			rings[i].frame:SetFrameLevel(orb:GetFrameLevel() - 1)
		end
	end

	--------------------------------------------------------
	-- News queue
	--------------------------------------------------------
	local activeNewsIds = {}

	local function ResolveAchievementDisplay(text, icon)
		if not text or text == "" then
			return text, icon
		end
		local id = text:match("|Hachievement:(%d+):") or text:match("|Hachievement:(%d+)")
		if not id then
			id = text:match("\n(%d+)%s*%.%s*$") or text:match("\n(%d+)%s*$")
		end
		if not id then
			return text, icon
		end
		if not GetAchievementInfo then
			return text, icon
		end
		local name, _, _, _, _, _, _, _, achIcon = GetAchievementInfo(tonumber(id))
		if name and name ~= "" then
			text = text:gsub("\n" .. id .. "%s*%.%s*$", "\n" .. name .. ".")
			text = text:gsub("\n" .. id .. "%s*$", "\n" .. name)
		end
		local iconId = tonumber(icon)
		local isDefaultIcon = (
			not icon
			or icon == 0
			or icon == 134400
			or icon == 131072
			or icon == "Interface\\Icons\\INV_Misc_Orb_05"
			or iconId == 0
			or iconId == 134400
			or iconId == 131072
		)
		if isDefaultIcon and achIcon and achIcon ~= 0 then
			icon = achIcon
		end
		return text, icon
	end

	local function Featured_Transfer(oldId, newNews, guildUID)
		if not oldId or not newNews or not newNews.id then
			return
		end
		local t = Featured_GetStore(guildUID)
		if not t then
			return
		end
		local updated = false
		for key, item in pairs(t) do
			if item and item.id == oldId then
				t[key] = {
					id = newNews.id,
					type = newNews.type,
					title = newNews.title,
					icon = newNews.icon,
					time = newNews.time,
					guildUID = newNews.guildUID or guildUID,
					replaceKey = newNews.replaceKey or "",
					note = item.note,
					updatedAt = time(),
				}
				updated = true
				if ns.Sections and ns.Sections.Heros_OnFeaturedUpdate then
					ns.Sections.Heros_OnFeaturedUpdate(guildUID, key, t[key])
				end
			end
		end
		if updated and List_Refresh then
			List_Refresh()
		end
	end

	local function News_Add(id, text, typ, icon, ts, guildUID, replaceKey, title, removedAt, uid)
		if not id or not text then
			return
		end
		local gid = guildUID or SU.Util_GetActiveGuildUID()
		if not gid or gid == "" then
			return
		end
		for i = #newsQueue, 1, -1 do
			local n = newsQueue[i]
			if n and n.id == id then
				n.text = text
				n.type = (typ and tostring(typ):lower()) or n.type
				n.title = title
				n.icon = icon or n.icon
				n.time = ts or n.time
				n.guildUID = gid
				n.replaceKey = replaceKey or n.replaceKey or ""
				n.removedAt = tonumber(removedAt or n.removedAt or 0) or 0
				n.uid = uid or n.uid
				return
			end
		end
		if typ and tostring(typ):lower() == "achievement" then
			text, icon = ResolveAchievementDisplay(text, icon)
		end
		local replacedIds = nil
		if replaceKey and replaceKey ~= "" then
			for i = #newsQueue, 1, -1 do
				local n = newsQueue[i]
				if n and n.replaceKey == replaceKey then
					if n.id then
						activeNewsIds[n.id] = nil
					end
					if n.id then
						if not replacedIds then
							replacedIds = {}
						end
						replacedIds[#replacedIds + 1] = n.id
					end
					table.remove(newsQueue, i)
				end
			end
		end
		if #newsQueue >= CFG.MAX_NEWS then
			table.remove(newsQueue, 1)
		end
		local newItem = {
			id = id,
			text = text,
			type = (typ and tostring(typ):lower()) or "generic",
			title = title,
			icon = icon or "Interface\\Icons\\INV_Misc_Orb_05",
			time = ts or time(),
			guildUID = gid,
			replaceKey = replaceKey or "",
			removedAt = tonumber(removedAt or 0) or 0,
			uid = uid,
		}
		newsQueue[#newsQueue + 1] = newItem
		if replacedIds then
			for i = 1, #replacedIds do
				Proud_Transfer(replacedIds[i], id, gid)
				Featured_Transfer(replacedIds[i], newItem, gid)
			end
		end
	end

	local News_SeedIfEmpty

	local function News_RemoveById(id)
		if not id or id == "" then
			return
		end
		for i = #newsQueue, 1, -1 do
			local n = newsQueue[i]
			if n and n.id == id then
				activeNewsIds[id] = nil
				table.remove(newsQueue, i)
			end
		end
		News_SeedIfEmpty()
		for j = #activePearls, 1, -1 do
			local p = activePearls[j]
			if p and p._news and p._news.id == id and not p._dying then
				p._lifeLeft = 0
				p._expired = true
				p._pendingFade = false
				p._pendingJitter = nil
				Pearl_StartFadeOut(p)
			end
		end
		List_MarkDirtyOrRefresh()
	end

	News_SeedIfEmpty = function()
		if #newsQueue > 0 then
			return
		end
		if not (ns.Data and ns.Data.Journalist and ns.Data.Journalist.GetRecentNews) then
			return
		end
		local gid = SU.Util_GetActiveGuildUID()
		if not gid or gid == "" then
			return
		end
		local items = ns.Data.Journalist.GetRecentNews(gid, CFG.MAX_NEWS) or {}
		for i = 1, #items do
			local n = items[i]
			if n and n.id and n.text then
				News_Add(n.id, n.text, n.typ, n.icon, n.ts, gid, n.replaceKey, n.title, n.removedAt, n.uid)
			end
		end
	end

	local function News_PickNext()
		if #newsQueue == 0 then
			return nil
		end
		local candidates = {}
		local gid = SU.Util_GetActiveGuildUID()
		if not gid or gid == "" then
			return nil
		end
		for i = 1, #newsQueue do
			local n = newsQueue[i]
			if
				n
				and n.id
				and not activeNewsIds[n.id]
				and SU.Util_IsSameGuildUID(n.guildUID, gid)
				and Filter_IsNewsAllowed(n)
			then
				candidates[#candidates + 1] = n
			end
		end
		if #candidates == 0 then
			if #activePearls == 0 then
				for k in pairs(activeNewsIds) do
					activeNewsIds[k] = nil
				end
				for i = 1, #newsQueue do
					local n = newsQueue[i]
					if
						n
						and n.id
						and not activeNewsIds[n.id]
						and SU.Util_IsSameGuildUID(n.guildUID, gid)
						and Filter_IsNewsAllowed(n)
					then
						candidates[#candidates + 1] = n
					end
				end
			end
		end
		if #candidates == 0 then
			return nil
		end
		return candidates[math.random(#candidates)]
	end

	--------------------------------------------------------
	-- Pearls
	--------------------------------------------------------
	local pearlPool = {}
	-- activePearls initialised above
	local pearlCount = 0

	local hoverCount = 0
	local hoverCooldown = 0

	ReleaseAllPearlHover = function()
		hoverCount = 0
		hoverCooldown = 0
		for i = 1, #activePearls do
			local p = activePearls[i]
			if p then
				p._hovered = false
				p._frozen = false
				p._badgeHover = false
				if p._ring then
					p._ring.targetSpeed = p._ring.baseSpeed
				end
			end
		end
	end

	local globalBubbleBlock = 0
	local lastSpawn = 0
	local nextSpawnDelay = SU.Util_RangePick(CFG.SPAWN_INTERVAL_RANGE)

	Ring_ClearRuntime = function()
		if ReleaseAllPearlHover then
			ReleaseAllPearlHover()
		end
		for i = #activePearls, 1, -1 do
			local p = activePearls[i]
			activePearls[i] = nil
			if p and Pearl_Release then
				Pearl_Release(p)
			end
		end
		wipe(activeNewsIds)
		globalBubbleBlock = 0
		lastSpawn = 0
		nextSpawnDelay = SU.Util_RangePick(CFG.SPAWN_INTERVAL_RANGE)
	end

	local function Pearl_Position(p)
		local x = math.cos(p._angle) * p._ring.radius
		local y = math.sin(p._angle) * p._ring.radius
		p:ClearAllPoints()
		p:SetPoint("CENTER", groups.pearls, "CENTER", x, y)
	end

	local function Pearl_Acquire()
		local p = table.remove(pearlPool)
		if not p then
			pearlCount = pearlCount + 1
			p = CreateFrame("Button", "WoWGuilde_SocialPearl" .. pearlCount, groups.pearls, "BackdropTemplate")
			p:SetSize(34, 34)
			p:EnableMouse(true)
			p:SetHitRectInsets(-8, -8, -8, -8)
			p:RegisterForClicks("RightButtonUp")

			p:SetFrameStrata("HIGH")
			p:SetFrameLevel(orb:GetFrameLevel() + 2)

			local pc = CreateFrame("Frame", p:GetName() .. "Content", p)
			pc:SetAllPoints(p)
			p.content = pc

			local icon = pc:CreateTexture(nil, "ARTWORK")
			icon:SetPoint("CENTER", pc, "CENTER", 0, 0)
			icon:SetSize(30, 30)
			icon:SetTexCoord(0, 1, 0, 1)
			p.icon = icon

			local iconMask = pc:CreateMaskTexture(nil, "ARTWORK")
			iconMask:SetAllPoints(icon)
			iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
			icon:AddMaskTexture(iconMask)
			p.iconMask = iconMask

			local ringTex = pc:CreateTexture(nil, "OVERLAY")
			ringTex:SetPoint("CENTER", icon, "CENTER", 0, 0)
			ringTex:SetSize(34, 34)
			SU.Util_SetAtlasOrTexture(ringTex, "heartofazeroth-slot-minor-glass", "Interface\\Buttons\\WHITE8x8")
			ringTex:SetBlendMode("ADD")
			ringTex:SetAlpha(1)
			p.ringTex = ringTex

			local extraTex = pc:CreateTexture(nil, "OVERLAY")
			extraTex:SetPoint("CENTER", icon, "CENTER", 0, 0)
			extraTex:SetSize(60, 35)
			SU.Util_SetAtlasOrTexture(extraTex, "Map_Faction_Ring", "Interface\\Buttons\\WHITE8x8")
			p.extraTex = extraTex

			local proudOverlay = pc:CreateTexture(nil, "OVERLAY")
			proudOverlay:SetPoint("CENTER", icon, "CENTER", -1.5, 1)
			proudOverlay:SetAtlas("groupfinder-eye-highlight")
			proudOverlay:SetSize(80, 80)
			proudOverlay:SetAlpha(0.5)
			proudOverlay:SetBlendMode("ADD")
			proudOverlay:Hide()
			p.proudOverlay = proudOverlay

			local mineBadge = CreateFrame("Button", nil, pc)
			mineBadge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 6, -6)
			mineBadge:SetSize(14, 14)
			mineBadge:EnableMouse(true)
			mineBadge:RegisterForClicks("RightButtonUp")
			mineBadge:SetFrameLevel(p:GetFrameLevel() + 3)
			mineBadge:Hide()

			local iconFx = mineBadge:CreateTexture(nil, "BACKGROUND")
			iconFx:SetPoint("CENTER", mineBadge, "CENTER", 0, 0)
			iconFx:SetSize(18, 18)
			iconFx:SetAtlas("UI-Frame-CypherChoice-Portrait-FX-Mask")
			iconFx:SetVertexColor(1, 1, 1, 0.6)
			p.iconFx = iconFx

			local badgeTex = mineBadge:CreateTexture(nil, "ARTWORK")
			badgeTex:SetAllPoints(mineBadge)
			SU.Util_SetAtlasOrTexture(badgeTex, BADGE_MINE_ATLAS, BADGE_MINE_TEX)
			mineBadge.icon = badgeTex

			mineBadge:SetScript("OnEnter", function(self)
				local parentItem = self._item
				if parentItem then
					parentItem._badgeHover = true
					if parentItem._ring then
						parentItem._ring.targetSpeed = 0
					end
					parentItem._frozen = true
				end
				if not self._isMine then
					return
				end
				GameTooltip:SetOwner(self, "ANCHOR_NONE")
				GameTooltip:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", 4, -4)
				GameTooltip:ClearLines()
				local msg = "Bu haber senin"
				GameTooltip:AddLine(msg, 1, 1, 1, true)
				GameTooltip:Show()
			end)
			mineBadge:SetScript("OnLeave", function(self)
				local parentItem = self._item
				if parentItem and parentItem:IsMouseOver() then
					return
				end
				if parentItem then
					parentItem._badgeHover = false
					if not parentItem:IsMouseOver() then
						parentItem._frozen = false
						if parentItem._ring then
							parentItem._ring.targetSpeed = parentItem._ring.baseSpeed
						end
						if parentItem._hovered then
							parentItem._hovered = false
							hoverCount = math.max(0, hoverCount - 1)
						end
					end
				end
				GameTooltip:Hide()
			end)
			mineBadge:SetScript("OnClick", function(self, button)
				if button ~= "RightButton" then
					return
				end
				if not self._news or not CanOpenNewsMenu(self._news, self._isMine) then
					return
				end
				ReleaseAllPearlHover()
				GameTooltip:Hide()
				Proud_OpenMenu(self, self._news, self._isMine)
			end)
			p.mineBadge = mineBadge

			p:SetScript("OnEnter", function(self)
				self._hovered = true
				hoverCount = hoverCount + 1
				self._ring.targetSpeed = 0
				self._frozen = true
				if self._news then
					GameTooltip:SetOwner(self, "ANCHOR_TOP")
					GameTooltip:ClearLines()
					local title = self._news.title or News_GetTypeLabel(self._news.type)
					GameTooltip:AddLine(title, 0.8941, 0.6549, 0.1255)
					local text = self._news.text or ""
					if ns and ns.Utils and ns.Utils.ReplaceNewsTags then
						text = ns.Utils.ReplaceNewsTags(text, self._news.time)
					end
					GameTooltip:AddLine(text, 1, 1, 1, true)
					if Featured_IsNewsFeatured(Proud_GetGuildUID(self._news), self._news.id) then
						GameTooltip:AddLine("Bu basari efsane bir gurur haberi.", 1, 0.5, 0, true)
					end
					GameTooltip:AddLine(SU.Util_PrettyTimeAgo(self._news.time), 0.6, 0.6, 0.6)
					GameTooltip:Show()
				end
			end)

			p:SetScript("OnLeave", function(self)
				if self.mineBadge and self.mineBadge:IsMouseOver() then
					return
				end
				if self._hovered then
					self._hovered = false
					hoverCount = math.max(0, hoverCount - 1)
				end
				self._ring.targetSpeed = self._ring.baseSpeed
				self._frozen = false
				GameTooltip:Hide()

				if self._expired then
					self._pendingFade = true
					self._pendingJitter = SU.Util_RangePick(CFG.PENDING_FADE_JITTER_RANGE)
				end

				if hoverCount == 0 then
					hoverCooldown = SU.Util_RangePick(CFG.HOVER_RELEASE_COOLDOWN_RANGE)
				end
			end)

			p:SetScript("OnClick", function(self, button)
				if button ~= "RightButton" then
					return
				end
				if not self._news or not CanOpenNewsMenu(self._news, self._isMine) then
					return
				end
				ReleaseAllPearlHover()
				GameTooltip:Hide()
				Proud_OpenMenu(self, self._news, self._isMine)
			end)
		end

		p:Show()
		p:SetAlpha(1)
		p:SetScale(1)

		if p.content then
			p.content:SetAlpha(1)
			p.content:SetScale(1)
			p.content:SetScript("OnUpdate", nil)
		end

		p._hovered, p._frozen, p._expired, p._dying = false, false, false, false
		p._pendingFade, p._pendingJitter = false, nil

		return p
	end

	Pearl_Release = function(p)
		if p._popAG and p._popAG:IsPlaying() then
			p._popAG:Stop()
		end

		local nid = p._news and p._news.id
		if nid then
			activeNewsIds[nid] = nil
		end

		p:Hide()
		p._news, p._ring = nil, nil
		p._hovered, p._frozen, p._expired, p._dying = false, false, false, false
		p._pendingFade, p._pendingJitter = false, nil

		if p.content then
			p.content:SetAlpha(1)
			p.content:SetScale(0.1)
			p.content:SetScript("OnUpdate", nil)
		end
		table.insert(pearlPool, p)
	end

	Pearl_StartFadeOut = function(p)
		if not p or p._dying then
			return
		end
		p._dying = true

		local target = p.content or p
		local t, duration = 0, (CFG.FADE_OUT.duration or 0.28)
		local s0 = (CFG.FADE_OUT.startScale or 1.0)
		local s1 = (CFG.FADE_OUT.endScale or 0.82)
		local a0 = (CFG.FADE_OUT.startAlpha or (target:GetAlpha() or 1))
		local a1 = (CFG.FADE_OUT.endAlpha or 0)

		local function easeOutQuad(u)
			return 1 - (1 - u) * (1 - u)
		end

		target:SetScale(s0)
		target:SetAlpha(a0)

		target:SetScript("OnUpdate", function(self, elapsed)
			t = t + elapsed
			local u = t / duration
			if u > 1 then
				u = 1
			end
			local k = easeOutQuad(u)

			local scale = s0 + (s1 - s0) * k
			local alpha = a0 + (a1 - a0) * k
			self:SetScale(scale)
			self:SetAlpha(alpha)

			if u >= 1 then
				self:SetScript("OnUpdate", nil)
				for i = #activePearls, 1, -1 do
					if activePearls[i] == p then
						table.remove(activePearls, i)
						break
					end
				end
				Pearl_Release(p)
			end
		end)
	end

	local function Ring_CanSpawn(r)
		local count = 0
		for _, p in ipairs(activePearls) do
			if p._ring == r then
				count = count + 1
			end
		end
		return count < (r.maxActive or 3)
	end

	Pearl_SpawnOnRing = function(r, news)
		local p = Pearl_Acquire()

		local iconSize = r.iconSize or 30
		p:SetSize(iconSize + 4, iconSize + 4)

		if p.icon then
			p.icon:SetSize(iconSize, iconSize)
		end
		if p.iconMask and p.icon then
			p.iconMask:SetAllPoints(p.icon)
		end
		if p.ringTex then
			p.ringTex:SetSize(iconSize + 6, iconSize + 6)
		end
		if p.iconOverlay then
			p.iconOverlay:SetSize(iconSize + 8, iconSize + 8)
		end
		if p.extraTex then
			p.extraTex:SetSize(iconSize + 10, iconSize + 10)
		end
		if p.proudOverlay then
			p.proudOverlay:SetSize(iconSize + 14, iconSize + 14)
		end

		local iconOX = r.iconOffsetX or 0
		local iconOY = r.iconOffsetY or 0
		local ringOX = r.ringOffsetX or 0
		local ringOY = r.ringOffsetY or 0
		local extraOX = r.extraTexOffsetX or 0
		local extraOY = r.extraTexOffsetY or 0

		if p.icon then
			p.icon:ClearAllPoints()
			p.icon:SetPoint("CENTER", p.content, "CENTER", iconOX, iconOY)
		end

		if p.ringTex and p.icon then
			p.ringTex:ClearAllPoints()
			p.ringTex:SetPoint("CENTER", p.icon, "CENTER", ringOX, ringOY)
		end

		if p.extraTex and p.icon then
			p.extraTex:ClearAllPoints()
			p.extraTex:SetPoint("CENTER", p.icon, "CENTER", extraOX, extraOY)
		end
		if p.iconOverlay and p.icon then
			p.iconOverlay:ClearAllPoints()
			p.iconOverlay:SetPoint("CENTER", p.icon, "CENTER", 0, 0)
		end
		if p.proudOverlay and p.icon then
			p.proudOverlay:ClearAllPoints()
			p.proudOverlay:SetPoint("CENTER", p.icon, "CENTER", -1.5, 1)
		end
		if p.mineBadge and p.icon then
			local badgeSize = math.max(12, math.floor(iconSize * 0.4 + 0.5))
			local badgeOffset = math.max(2, math.floor(10 - (iconSize * 0.2) + 0.5))
			p.mineBadge:SetSize(badgeSize, badgeSize)
			p.mineBadge:ClearAllPoints()
			p.mineBadge:SetPoint("BOTTOMRIGHT", p.icon, "BOTTOMRIGHT", badgeOffset, -badgeOffset)
			if p.iconFx then
				p.iconFx:SetSize(badgeSize + 2, badgeSize + 2)
			end
		end

		p._ring, p._news = r, news
		if news and news.id then
			activeNewsIds[news.id] = true
		end

		p._lifeLeft = SU.Util_RangePick(CFG.PEARL_LIFETIME_RANGE)
		p._expired, p._hovered, p._frozen = false, false, false

		local tries, valid, angle = 0, false, 0
		repeat
			angle = math.random() * (2 * math.pi)
			valid = true
			for _, other in ipairs(activePearls) do
				if other._ring == r then
					local diff = math.abs(angle - other._angle)
					if diff > math.pi then
						diff = (2 * math.pi) - diff
					end
					if diff < 0.6 then
						valid = false
						break
					end
				end
			end
			tries = tries + 1
		until valid or tries > 20
		p._angle = angle

		if p.icon then
			SU.Util_SetPearlIcon(p.icon, news and news.icon, iconSize)
		end
		Pearl_UpdateVisual(p)

		Pearl_Position(p)

		if p.content then
			p.content:SetAlpha(0)
			p.content:SetScale(0.1)

			local t, duration = 0, 0.6
			local SCALE_KEYFRAMES = {
				{ t = 0.0, scale = 0.1 },
				{ t = 0.4, scale = 1.2 },
				{ t = 0.7, scale = 0.9 },
				{ t = 1.0, scale = 1.0 },
			}

			p.content:SetScript("OnUpdate", function(self, elapsed)
				t = t + elapsed
				local progress = math.min(t / duration, 1)

				local prev, nextKF = SCALE_KEYFRAMES[1], SCALE_KEYFRAMES[#SCALE_KEYFRAMES]
				for i = 1, #SCALE_KEYFRAMES - 1 do
					local a, b = SCALE_KEYFRAMES[i], SCALE_KEYFRAMES[i + 1]
					if progress >= a.t and progress <= b.t then
						prev, nextKF = a, b
						break
					end
				end

				local seg = (progress - prev.t) / (nextKF.t - prev.t)
				local current = prev.scale + (nextKF.scale - prev.scale) * seg

				self:SetScale(current)
				self:SetAlpha(progress)

				if progress >= 1 then
					self:SetScript("OnUpdate", nil)
					self:SetScale(nextKF.scale)
					self:SetAlpha(1)
				end
			end)
		end

		activePearls[#activePearls + 1] = p
		globalBubbleBlock = SU.Util_RangePick(CFG.BUBBLE_DURATION_RANGE)
	end

	Pearl_TrySpawn = function()
		if hoverCount > 0 then
			return false
		end
		if hoverCooldown > 0 then
			return false
		end
		if globalBubbleBlock > 0 then
			return false
		end

		local news = News_PickNext()
		if not news then
			return false
		end

		local candidates = {}
		for _, r in ipairs(rings) do
			if Ring_CanSpawn(r) and math.abs(r.targetSpeed) > 0.0001 then
				table.insert(candidates, r)
			end
		end
		if #candidates == 0 then
			return false
		end

		local ringToUse = candidates[math.random(#candidates)]
		Pearl_SpawnOnRing(ringToUse, news)
		return true
	end

	--------------------------------------------------------
	-- Updater
	--------------------------------------------------------
	local updater = CreateFrame("Frame", "WoWGuilde_SocialUpdater", f)
	updater:SetScript("OnUpdate", function(_, elapsed)
		if State.view.mode ~= "ring" or not groups.ring:IsShown() then
			return
		end
		local now = time()
		local removed = false
		for i = #newsQueue, 1, -1 do
			local n = newsQueue[i]
			if n and n.removedAt and n.removedAt > 0 and n.removedAt <= now then
				if n.id then
					activeNewsIds[n.id] = nil
				end
				for j = #activePearls, 1, -1 do
					local p = activePearls[j]
					if p and p._news and p._news.id == n.id and not p._dying then
						p._lifeLeft = 0
						p._expired = true
						p._pendingFade = false
						p._pendingJitter = nil
						Pearl_StartFadeOut(p)
					end
				end
				table.remove(newsQueue, i)
				removed = true
			end
		end

		for _, r in ipairs(rings) do
			local rf = r.frame
			rf._rot = (rf._rot + (r.spinSpeed * CFG.RING_SPIN_SCALE * elapsed)) % (2 * math.pi)
			rf._tex1:SetRotation(rf._rot)

			local diff = r.targetSpeed - r.curSpeed
			if math.abs(diff) > 0.0001 then
				r.curSpeed = r.curSpeed + diff * math.min(1, elapsed * 4.0)
			else
				r.curSpeed = r.targetSpeed
			end
		end
		for i = 1, #centerRings do
			local t = centerRings[i]
			if t and t._speed and t._speed ~= 0 then
				t._rot = (t._rot + (t._speed * elapsed)) % (2 * math.pi)
				t:SetRotation(t._rot)
			end
			if t and t._pulse and t._baseAlpha then
				if t._pulse == "standard" then
					t._pulsePhase = (t._pulsePhase + elapsed * 1.2) % (2 * math.pi)
					local base = tonumber(t._baseAlpha) or 0
					local amp = base * 0.35
					local alpha = base + math.sin(t._pulsePhase) * amp
					if alpha ~= alpha then
						alpha = base
					end
					if alpha < 0 then
						alpha = 0
					end
					if alpha > 1 then
						alpha = 1
					end
					t:SetAlpha(alpha)
				elseif t._pulse == "jitter" then
					local base = tonumber(t._baseAlpha) or 0
					t._pulseJitterAt = (t._pulseJitterAt or 0) - elapsed
					if t._pulseJitterAt <= 0 or t._pulseJitterAlpha == nil then
						t._pulseJitterAt = 0.06 + math.random() * 0.14
						local amp = base * 0.4
						local jitter = (math.random() - 0.5) * 2 * amp
						local target = base + jitter
						if target ~= target then
							target = base
						end
						if target < 0 then
							target = 0
						end
						if target > 1 then
							target = 1
						end
						t._pulseJitterAlpha = target
					end
					local current = t:GetAlpha() or base
					local target = t._pulseJitterAlpha or base
					local blend = math.min(1, elapsed * 10)
					local alpha = current + (target - current) * blend
					if alpha < 0 then
						alpha = 0
					end
					if alpha > 1 then
						alpha = 1
					end
					t:SetAlpha(alpha)
				end
			end
		end

		for i = #activePearls, 1, -1 do
			local p = activePearls[i]
			if not p._frozen then
				p._angle = (p._angle + p._ring.curSpeed * elapsed) % (2 * math.pi)
			end
			Pearl_Position(p)

			if not p._dying and p._news and not Filter_IsNewsAllowed(p._news) then
				p._lifeLeft = 0
				p._expired = true
				p._pendingFade = false
				p._pendingJitter = nil
				Pearl_StartFadeOut(p)
			end

			if not p._dying then
				p._lifeLeft = p._lifeLeft - elapsed
				if p._lifeLeft <= 0 then
					if (hoverCount > 0) or (hoverCooldown > 0) or p._hovered then
						p._expired = true
						p._pendingFade = true
						if not p._pendingJitter then
							p._pendingJitter = SU.Util_RangePick(CFG.PENDING_FADE_JITTER_RANGE)
						end
					else
						Pearl_StartFadeOut(p)
					end
				end
			end
		end

		if globalBubbleBlock > 0 then
			globalBubbleBlock = globalBubbleBlock - elapsed
			if globalBubbleBlock < 0 then
				globalBubbleBlock = 0
			end
		end
		if hoverCooldown > 0 then
			hoverCooldown = hoverCooldown - elapsed
			if hoverCooldown < 0 then
				hoverCooldown = 0
			end
		end

		if hoverCount == 0 and hoverCooldown == 0 then
			for _, p in ipairs(activePearls) do
				if p._pendingFade and not p._hovered and not p._dying then
					if p._pendingJitter then
						p._pendingJitter = p._pendingJitter - elapsed
						if p._pendingJitter <= 0 then
							p._pendingFade, p._pendingJitter = false, nil
							Pearl_StartFadeOut(p)
						end
					else
						p._pendingFade = false
						Pearl_StartFadeOut(p)
					end
				end
			end
		end

		lastSpawn = lastSpawn + elapsed
		if lastSpawn >= nextSpawnDelay then
			if Pearl_TrySpawn() then
				lastSpawn = 0
				nextSpawnDelay = SU.Util_RangePick(CFG.SPAWN_INTERVAL_RANGE)
			else
				lastSpawn = 0
				nextSpawnDelay = 0.25
			end
		end

		if removed and groups.list:IsShown() and List_Refresh then
			List_Refresh()
		end
	end)

	--------------------------------------------------------
	-- API publique
	--------------------------------------------------------
	function f:SetCohesion(v)
		v = SU.Util_Clamp01(tonumber(v) or 0)
		local rr, gg, bb = SU.Util_ColorGradient(v, 1, 0.15, 0.15, 1, 0.9, 0.2, 0.25, 1, 0.45)
		orbCore:SetVertexColor(rr, gg, bb, 0.85)
		orbGlow:SetVertexColor(rr, gg, bb, 0.12)
	end

	function f:SetDecorPoint(point, relTo, relPoint, x, y)
		LAYOUT.decor.point = point or "TOPLEFT"
		LAYOUT.decor.relTo = relTo or f
		LAYOUT.decor.relPoint = relPoint or "TOPLEFT"
		LAYOUT.decor.x, LAYOUT.decor.y = x or 0, y or 0
		Layout_Apply()
	end

	function f:SetDecorSize(w, h)
		LAYOUT.decor.w, LAYOUT.decor.h = w or LAYOUT.decor.w, h or LAYOUT.decor.h
		Layout_Apply()
	end

	function f:SetOriginOffset(dx, dy)
		LAYOUT.origin.dx, LAYOUT.origin.dy = dx or 0, dy or 0
		Layout_Apply()
	end

	function f:SetOrigin(x, y)
		self:SetOriginOffset(x, y)
	end

	function f:SetGroupOffset(groupName, dx, dy)
		local g = LAYOUT[groupName]
		if g then
			g.dx, g.dy = dx or 0, dy or 0
			Layout_Apply()
		end
	end

	function f:SetRingRadius(i, radius)
		local r = rings[i]
		if r and radius and radius > 0 then
			r.radius = radius
			r.frame:SetSize(radius * 2, radius * 2)
		end
	end

	function f:SetRingRadiusScale(scale)
		if not scale or scale <= 0 then
			return
		end
		for i, cfg in ipairs(RINGS_CFG) do
			local r = rings[i]
			local newR = (cfg.radius or r.radius) * scale
			r.radius = newR
			r.frame:SetSize(newR * 2, newR * 2)
		end
	end

	function f:AddNews(id, text, type_, icon, ts, guildUID, replaceKey, title, removedAt, uid)
		News_Add(id, text, type_, icon, ts, guildUID, replaceKey, title, removedAt, uid)
		if listBatchDepth > 0 then
			listBatchDirty = true
		elseif groups.list:IsShown() and List_Refresh then
			List_Refresh()
		end
		if groups.list:IsShown() and listScroll and listScroll.SetVerticalScroll then
			listScroll:SetVerticalScroll(0)
		end
	end

	function f:ClearNews()
		wipe(newsQueue)
		newsIndex = 0
	end

	function f:DebugSpawn()
		if State.view.mode ~= "ring" or not groups.ring:IsShown() then
			return false
		end
		return Pearl_TrySpawn()
	end

	function Sections.Social_AddNews(id, text, type_, icon, ts, guildUID, replaceKey, title, removedAt, uid)
		if f and f.AddNews then
			f:AddNews(id, text, type_, icon, ts, guildUID, replaceKey, title, removedAt, uid)
			if f:IsShown() and State.view.mode == "ring" then
				f:DebugSpawn()
			end
		end
	end

	function f:RemoveNews(id)
		News_RemoveById(id)
	end

	function Sections.Social_RemoveNews(id)
		if f and f.RemoveNews then
			f:RemoveNews(id)
		end
	end

	function Sections.Social_BeginNewsBatch()
		listBatchDepth = listBatchDepth + 1
	end

	function Sections.Social_EndNewsBatch()
		if listBatchDepth <= 0 then
			listBatchDepth = 0
			return
		end
		listBatchDepth = listBatchDepth - 1
		if listBatchDepth == 0 and listBatchDirty then
			listBatchDirty = false
			if groups.list:IsShown() and List_Refresh then
				List_Refresh()
			end
		end
	end

	f:SetScript("OnShow", function()
		Layout_Apply()
		News_SeedIfEmpty()
		if groups.list:IsShown() and List_Refresh then
			List_Refresh()
		end
		if ns.Data and ns.Data.NewsFeed and ns.Data.NewsFeed.Flush then
			ns.Data.NewsFeed.Flush()
		end
		if ns.Data and ns.Data.Journalist and ns.Data.Journalist.TickNow then
			ns.Data.Journalist.TickNow()
		end
		if ns.Data and ns.Data.Journalist and ns.Data.Journalist.StartLive then
			ns.Data.Journalist.StartLive()
		end
		if Progress_Update then
			Progress_Update()
		end
	end)

	f:SetScript("OnHide", function()
		if Ring_ClearRuntime then
			Ring_ClearRuntime()
		end
		HideOrbTooltip()
		if ns.Data and ns.Data.Journalist and ns.Data.Journalist.StopLive then
			ns.Data.Journalist.StopLive()
		end
	end)

	if EventBus and EventBus.On then
		EventBus.On("WG_GUILD_PROGRESS_UPDATED", function(_, guildUID)
			if f and f:IsShown() and Progress_Update then
				Progress_Update()
			end
		end)
	end

	Filter_EnsureTypes()
	View_Apply(State.view.mode)

	return f
end
