local ADDON, ns = ...

ns.HerosSection = ns.HerosSection or {}
local M = ns.HerosSection

function M.CreateContext(parent)
	local ctx = {
		parent = parent,
		ns = ns,
		Sections = ns.Sections,
		HU = (ns.Heros and ns.Heros.Utils) or {},
		DB = ns.DB or {},
		Comms = ns.Comms or {},
		EventBus = ns.EventBus,
		const = {},
		state = {},
		ui = {},
		fn = {},
	}

	local const = ctx.const
	const.LINE_HEIGHT = 36
	const.ENTRY_GAP = 10
	const.LIST_WIDTH = 250
	const.PROFILE_WIDTH = 420
	const.MAX_OFFLINE_MIN = 168 * 60

	const.HEADER_HEIGHT = 72
	const.BG_PAD_L, const.BG_PAD_T, const.BG_PAD_R, const.BG_PAD_B = 3, -8, 0, 0
	const.NINESLICE_PAD_L, const.NINESLICE_PAD_T, const.NINESLICE_PAD_R, const.NINESLICE_PAD_B = 0, 3, 0, 0
	const.WOOD_PAD_L, const.WOOD_PAD_R, const.WOOD_PAD_T, const.WOOD_PAD_B = 0, 0, 0, 0
	const.WOOD_HEIGHT = 75

	const.FEATURED_SIZE = 130

	const.NEWS_MAX = 256
	const.HERO_LIST_CFG = {
		columnWidth = 250,
		columnHeight = 430,
		columnX = -48,
		columnY = -70,
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
	}
	const.BIO_CFG = {
		width = 530,
		height = 120,
		offsetX = -350,
		offsetY = 65,
	}

	local prefs = ns.Prefs
	ctx.state.sortState = {
		method = (prefs and prefs.GetHeros and prefs.GetHeros("sortMethod", "last")) or "last",
		onlineFirst = (prefs and prefs.GetHeros and prefs.GetHeros("onlineFirst", true)) or true,
	}
	ctx.state.entries = {}
	ctx.state.selectedKey = nil
	ctx.state.selectedEntry = nil

	ctx.state.newsQueue = {}
	ctx.state.heroNewsTarget = nil
	ctx.state.featuredDragNews = nil
	ctx.state.featuredDragMode = nil

	ctx.state.newsState = {
		filter = {
			onlyProud = (prefs and prefs.GetHeros and prefs.GetHeros("newsOnlyProud", false)) or false,
			types = (prefs and prefs.GetHeros and prefs.GetHeros("newsTypes", nil)) or nil,
		},
	}

	const.NEWS_TYPE_LABELS = {
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
		housingcleanup = "Ada bakimi",
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

	const.NEWS_TYPE_ORDER = {
		"achievement",
		"mount",
		"toy",
		"transmog",
		"connection",
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
		"world",
		"quest",
		"questdaily",
		"worldquest",
		"level",
		"gear",
		"spec",
		"death",
		"pvp",
		"generic",
	}

	const.NEWS_TYPE_GROUPS = {
		{ label = "Gorevler", keys = { "quest", "questdaily", "worldquest" } },
		{ label = "Dunya", keys = { "world", "housing", "housingcleanup" } },
		{ label = "Ilerleme", keys = { "achievement", "level", "gear", "spec" } },
		{ label = "Savas", keys = { "pve", "raid", "mplus", "cibles", "pvp", "death" } },
		{ label = "Ganimet", keys = { "loot", "woodharvest", "herbharvest", "fishingharvest", "oreharvest" } },
		{ label = "Koleksiyon", keys = { "mount", "toy", "transmog", "housingdecor" } },
		{ label = "Iletisim", keys = { "connection", "guildchat" } },
		{ label = "Cesitli", keys = { "generic" } },
	}

	const.NEWS_TYPE_GROUPED = {}
	for _, group in ipairs(const.NEWS_TYPE_GROUPS) do
		for _, key in ipairs(group.keys) do
			const.NEWS_TYPE_GROUPED[key] = true
		end
	end
	const.NEWS_TYPE_UNGROUPED = {}
	for _, key in ipairs(const.NEWS_TYPE_ORDER) do
		if not const.NEWS_TYPE_GROUPED[key] then
			const.NEWS_TYPE_UNGROUPED[#const.NEWS_TYPE_UNGROUPED + 1] = key
		end
	end

	const.BADGE_MINE_ATLAS = "checkmark-minimal-disabled"
	const.BADGE_MINE_TEX = "Interface\\Buttons\\UI-CheckBox-Check"
	const.BADGE_PROUD_ATLAS = "checkmark-minimal"
	const.BADGE_PROUD_TEX = "Interface\\Common\\ReputationStar"
	const.PROUD_BORDER_R, const.PROUD_BORDER_G, const.PROUD_BORDER_B = 1, 0.914, 0.608
	const.FEATURED_BORDER_R, const.FEATURED_BORDER_G, const.FEATURED_BORDER_B = 1, 0.5, 0

	return ctx
end

return M
