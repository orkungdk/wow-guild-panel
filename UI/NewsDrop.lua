--========================================================
-- NewsDrop : petite "piece" qui tombe vers l'icone de menu
--========================================================
local ADDON, ns = ...
ns.UI = ns.UI or {}

local NewsDrop = ns.UI.NewsDrop or {}
ns.UI.NewsDrop = NewsDrop

local EventBus = ns.EventBus

local queue = {}
local playing = false
local recentNotified = {}

local DUR = {
	inDrop = 0.36,
	outDrop = 0.22,
	hold = 3.0,
}

local OFFSETS = {
	start = 96,
	hover = 15,
}

local DEFAULT_SIZE = 20
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local DEFAULT_SOUND_ID = 138215
NewsDrop.DEFAULT_SOUND_ID = DEFAULT_SOUND_ID
NewsDrop.DEFAULT_ICON = DEFAULT_ICON

local RING_ATLAS = "Map_Faction_Ring"
local MASK_TEXTURE = "interface/common/commonmaskcircle"
local RING_PAD = 6
local RING_SHADOW_TEXTURE = "Interface\\AddOns\\WoWGuilde\\Media\\toast-shadow"
local RING_SHADOW_ALPHA = 0.45
local DIM_ALPHA = 0.35
local DIM_COLOR = 0.6

local MICRO_BUTTONS = {
	"CharacterMicroButton",
	"ProfessionMicroButton",
	"PlayerSpellsMicroButton",
	"AchievementMicroButton",
	"QuestLogMicroButton",
	"HousingMicroButton",
	"LFDMicroButton",
	"CollectionsMicroButton",
	"EJMicroButton",
	"MainMenuMicroButton",
	"StoreMicroButton",
}

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

local HIDDEN_NOTIFICATION_TYPES = {
	guild = true,
	collection = true,
	social = true,
}

local NEWS_TYPE_ORDER = {
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

local NEWS_TYPE_GROUPS = {
	{ label = "Gorevler", keys = { "quest", "questdaily", "worldquest" } },
	{ label = "Dunya", keys = { "world", "housing", "housingcleanup" } },
	{ label = "Ilerleme", keys = { "achievement", "level", "gear", "spec" } },
	{ label = "Savas", keys = { "pve", "raid", "mplus", "cibles", "pvp", "death" } },
	{ label = "Ganimet", keys = { "loot", "woodharvest", "herbharvest", "fishingharvest", "oreharvest" } },
	{ label = "Koleksiyon", keys = { "mount", "toy", "transmog", "housingdecor" } },
	{ label = "Iletisim", keys = { "connection", "guildchat" } },
	{ label = "Cesitli", keys = { "generic" } },
}

local DEFAULT_ENABLED_TYPES = {
	mount = true,
	achievement = true,
	quest = true,
	questdaily = true,
	raid = true,
	mplus = true,
	pve = true,
	level = true,
	death = true,
	toy = true,
	worldquest = true,
}

local function IsDevMode()
	if ns and ns.Utils and ns.Utils.IsDevMode then
		return ns.Utils.IsDevMode()
	end
	if ns and ns.Comms and ns.Comms.DEV_MODE ~= nil then
		return ns.Comms.DEV_MODE == true
	end
	if ns and ns.DEV_MODE ~= nil then
		return ns.DEV_MODE == true
	end
	return false
end

local function NormalizeTypeKey(v)
	local t = tostring(v or "")
	t = t:gsub("^%s+", ""):gsub("%s+$", ""):lower()
	if t == "" then
		return "generic"
	end
	return t
end

local function CanonicalTypeKey(key)
	local k = NormalizeTypeKey(key)
	local meta = ns and ns.Data and ns.Data.NewsMeta and ns.Data.NewsMeta[k] or nil
	if type(meta) == "table" and meta.type and meta.type ~= "" then
		return NormalizeTypeKey(meta.type)
	end
	return k
end

local function GetPrefStore()
	if ns and ns.Prefs and ns.Prefs.GetSocial then
		local t = ns.Prefs.GetSocial("NewsDrop", nil)
		if type(t) ~= "table" then
			t = {}
			if ns.Prefs.SetSocial then
				ns.Prefs.SetSocial("NewsDrop", t)
			end
		end
		return t
	end
	NewsDrop._prefs = NewsDrop._prefs or {}
	return NewsDrop._prefs
end

local function Prefs()
	local p = GetPrefStore()
	p.enabled = (p.enabled ~= false)
	p.sound = (p.sound ~= false)
	p.localNews = (p.localNews ~= false)
	p.remoteNews = (p.remoteNews ~= false)
	if type(p.types) ~= "table" then
		p.types = {}
	end
	return p
end

local function SetPrefFlag(key, value)
	local p = Prefs()
	p[key] = value == true
	if ns and ns.Prefs and ns.Prefs.SetSocial then
		ns.Prefs.SetSocial("NewsDrop", p)
	end
end

local function BuildTypeList()
	local out = {}
	local seen = {}
	local function add(key, label)
		local k = CanonicalTypeKey(key)
		if HIDDEN_NOTIFICATION_TYPES[k] then
			return
		end
		if seen[k] then
			return
		end
		seen[k] = true
		out[#out + 1] = {
			key = k,
			label = tostring(label or NEWS_TYPE_LABELS[k] or k),
		}
	end

	for i = 1, #NEWS_TYPE_ORDER do
		local key = NEWS_TYPE_ORDER[i]
		add(key, NEWS_TYPE_LABELS[CanonicalTypeKey(key)] or NEWS_TYPE_LABELS[key] or key)
	end

	local meta = ns and ns.Data and ns.Data.NewsMeta or nil
	if type(meta) == "table" then
		for rawKey, row in pairs(meta) do
			local label = nil
			if type(row) == "table" then
				label = row.title
				add(rawKey, label)
				add(row.type, label)
			else
				add(rawKey, tostring(row))
			end
		end
	end

	return out
end

local function BuildTypeGroups()
	local groups = {}
	local grouped = {}
	local all = BuildTypeList()
	local byKey = {}
	for i = 1, #all do
		local row = all[i]
		byKey[row.key] = row.label
	end
	for i = 1, #NEWS_TYPE_GROUPS do
		local src = NEWS_TYPE_GROUPS[i]
		local dst = { label = src.label, entries = {} }
		for j = 1, #src.keys do
			local key = CanonicalTypeKey(src.keys[j])
			grouped[key] = true
			dst.entries[#dst.entries + 1] = { key = key, label = byKey[key] or NEWS_TYPE_LABELS[key] or key }
		end
		groups[#groups + 1] = dst
	end
	local ungrouped = {}
	for i = 1, #all do
		local key = all[i].key
		if not grouped[key] then
			ungrouped[#ungrouped + 1] = { key = key, label = all[i].label or NEWS_TYPE_LABELS[key] or key }
		end
	end
	return groups, ungrouped
end

local function ResolveNewsType(news)
	if type(news) ~= "table" then
		return "generic"
	end

	-- Source canonique: cle type stockee sur la news, puis canonicalisation NewsMeta.
	local directRaw = news.type or news.typ
	local direct = CanonicalTypeKey(directRaw)
	if directRaw ~= nil and direct ~= "" and direct ~= "generic" then
		return direct
	end

	local rk = tostring(news.replaceKey or "")
	if rk ~= "" then
		local prefix = NormalizeTypeKey(rk:match("^([^:]+)"))
		if prefix ~= "" then
			local meta = ns and ns.Data and ns.Data.NewsMeta and ns.Data.NewsMeta[prefix] or nil
			if type(meta) == "table" and meta.type and meta.type ~= "" then
				return NormalizeTypeKey(meta.type)
			end
			if NEWS_TYPE_LABELS[prefix] ~= nil then
				return prefix
			end
		end
	end

	local title = tostring(news.title or ""):lower()
	if title ~= "" then
		for key, label in pairs(NEWS_TYPE_LABELS) do
			if tostring(label or ""):lower() == title then
				return NormalizeTypeKey(key)
			end
		end
	end

	return "generic"
end

local function IsAllowedByPrefs(news, source)
	local p = Prefs()
	if p.enabled == false then
		return false
	end
	if source == "local" and p.localNews == false then
		return false
	end
	if source == "remote" and p.remoteNews == false then
		return false
	end
	local typ = ResolveNewsType(news)
	if not NewsDrop.IsTypeEnabled(typ) then
		return false
	end
	return true
end

local function RememberNotified(news)
	if type(news) ~= "table" then
		return
	end
	local id = tostring(news.id or "")
	if id == "" then
		return
	end
	local now = time and time() or 0
	recentNotified[id] = now
end

local function WasRecentlyNotified(news, windowSec)
	if type(news) ~= "table" then
		return false
	end
	local id = tostring(news.id or "")
	if id == "" then
		return false
	end
	local now = time and time() or 0
	local w = tonumber(windowSec or 2) or 2
	local ts = tonumber(recentNotified[id] or 0) or 0
	if ts > 0 and (now - ts) <= w then
		return true
	end
	return false
end

local function IsMyNews(news)
	if type(news) ~= "table" then
		return false
	end
	local myUID = ns and ns.DB and ns.DB.GetMyUID and ns.DB:GetMyUID() or nil
	local uid = news.uid and tostring(news.uid) or nil
	if myUID and uid and uid ~= "" then
		return uid == tostring(myUID)
	end
	return false
end

function NewsDrop.GetPrefs()
	return Prefs()
end

function NewsDrop.SetEnabled(v)
	SetPrefFlag("enabled", v)
end

function NewsDrop.SetSoundEnabled(v)
	SetPrefFlag("sound", v)
end

function NewsDrop.SetLocalEnabled(v)
	SetPrefFlag("localNews", v)
end

function NewsDrop.SetRemoteEnabled(v)
	SetPrefFlag("remoteNews", v)
end

function NewsDrop.IsTypeEnabled(typeKey)
	local p = Prefs()
	local key = CanonicalTypeKey(typeKey)
	local explicit = p.types[key]
	if explicit ~= nil then
		return explicit == true
	end
	return DEFAULT_ENABLED_TYPES[key] == true
end

function NewsDrop.SetTypeEnabled(typeKey, enabled)
	local p = Prefs()
	local key = CanonicalTypeKey(typeKey)
	if enabled == false then
		p.types[key] = false
	else
		p.types[key] = true
	end
	if ns and ns.Prefs and ns.Prefs.SetSocial then
		ns.Prefs.SetSocial("NewsDrop", p)
	end
end

function NewsDrop.ListNotificationTypes()
	return BuildTypeList()
end

function NewsDrop.ListNotificationTypeGroups()
	return BuildTypeGroups()
end

function NewsDrop.GetTypeLabel(typeKey)
	local key = CanonicalTypeKey(typeKey)
	return NEWS_TYPE_LABELS[key] or key
end

function NewsDrop.SetAllTypesEnabled(enabled)
	local p = Prefs()
	local all = BuildTypeList()
	for i = 1, #all do
		local key = CanonicalTypeKey(all[i] and all[i].key)
		p.types[key] = (enabled == true)
	end
	if ns and ns.Prefs and ns.Prefs.SetSocial then
		ns.Prefs.SetSocial("NewsDrop", p)
	end
end

local function NormalizeIcon(icon)
	if icon == nil or icon == "" then
		return nil
	end
	if type(icon) == "number" then
		return icon > 0 and icon or nil
	end
	if type(icon) == "string" then
		local n = tonumber(icon)
		if n and n > 0 then
			return n
		end
		return icon
	end
	return nil
end

local function GetAnchor()
	if _G.GuildMicroButton then
		return _G.GuildMicroButton
	end
	if _G.WoWGuildeTab and _G.WoWGuildeTab.Icon then
		return _G.WoWGuildeTab.Icon
	end
	if _G.WoWGuilde_GuildButton then
		return _G.WoWGuilde_GuildButton
	end
	return nil
end

local function ResolveSize()
	return DEFAULT_SIZE
end

local function EnsureFrame()
	if NewsDrop.f then
		return NewsDrop.f
	end

	local f = CreateFrame("Frame", "WoWGuilde_NewsDrop", UIParent)
	f:SetFrameStrata("TOOLTIP")
	f:SetFrameLevel(10000)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()

	f.icon = f:CreateTexture(nil, "ARTWORK", nil, 1)
	f.icon:SetAllPoints(f)
	f.icon:SetAlpha(0)
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	f.mask = f:CreateMaskTexture()
	f.mask:SetAllPoints(f.icon)
	f.mask:SetTexture(MASK_TEXTURE)
	f.icon:AddMaskTexture(f.mask)

	f.border = f:CreateTexture(nil, "OVERLAY", nil, 2)
	f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -RING_PAD, RING_PAD)
	f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", RING_PAD, -RING_PAD)
	f.border:SetAtlas(RING_ATLAS, true)
	f.border:SetAlpha(0.95)

	f.ringShadow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
	f.ringShadow:SetPoint("CENTER", f.border, "CENTER", 0, -2)
	f.ringShadow:SetSize(DEFAULT_SIZE + (RING_PAD * 2) + 10, DEFAULT_SIZE + (RING_PAD * 2) + 10)
	f.ringShadow:SetTexture(RING_SHADOW_TEXTURE)
	f.ringShadow:SetAlpha(RING_SHADOW_ALPHA)

	f:SetScript("OnEnter", function()
		local last = NewsDrop.lastNews
		if not last then
			return
		end
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:ClearLines()
		local title = last.title or last.text or "Haber"
		GameTooltip:SetText(title, 1, 0.82, 0)
		if last.text and last.text ~= title then
			GameTooltip:AddLine(last.text, 1, 1, 1, true)
		end
		if last.ts and ns and ns.Utils and ns.Utils.PrettyTimeAgo then
			GameTooltip:AddLine(ns.Utils.PrettyTimeAgo(last.ts), 0.8, 0.8, 0.8)
		end
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	f:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			if NewsDrop.Dismiss then
				NewsDrop.Dismiss()
			end
		end
	end)

	-- Animation entree
	local inAG = f:CreateAnimationGroup()
	f.inAG = inAG

	local inMove = inAG:CreateAnimation("Translation")
	inMove:SetOrder(1)
	inMove:SetOffset(0, -(OFFSETS.start - OFFSETS.hover))
	inMove:SetDuration(DUR.inDrop)
	inMove:SetSmoothing("OUT")

	local inAlpha = inAG:CreateAnimation("Alpha")
	inAlpha:SetTarget(f.icon)
	inAlpha:SetOrder(1)
	inAlpha:SetFromAlpha(0)
	inAlpha:SetToAlpha(1)
	inAlpha:SetDuration(DUR.inDrop * 0.6)

	inAG:SetScript("OnFinished", function()
		if f._anchor then
			f:ClearAllPoints()
			f:SetPoint("CENTER", f._anchor, "CENTER", 0, OFFSETS.hover)
		end
		f.icon:SetAlpha(1)
	end)

	-- Animation sortie
	local outAG = f:CreateAnimationGroup()
	f.outAG = outAG

	local outMove = outAG:CreateAnimation("Translation")
	outMove:SetOrder(1)
	outMove:SetOffset(0, -OFFSETS.hover)
	outMove:SetDuration(DUR.outDrop)
	outMove:SetSmoothing("IN")

	local outScale = outAG:CreateAnimation("Scale")
	outScale:SetOrder(1)
	outScale:SetScale(0.2, 0.2)
	outScale:SetDuration(DUR.outDrop)
	outScale:SetSmoothing("IN")
	outScale:SetOrigin("CENTER", 0, 0)

	local outAlpha = outAG:CreateAnimation("Alpha")
	outAlpha:SetTarget(f.icon)
	outAlpha:SetOrder(1)
	outAlpha:SetFromAlpha(1)
	outAlpha:SetToAlpha(0)
	outAlpha:SetDuration(DUR.outDrop)

	outAG:SetScript("OnFinished", function()
		if NewsDrop._SetMicroMenuDim then
			NewsDrop._SetMicroMenuDim(false)
		end
		f:Hide()
		playing = false
		if NewsDrop._ShowNext then
			if C_Timer and C_Timer.After then
				C_Timer.After(0.05, NewsDrop._ShowNext)
			else
				NewsDrop._ShowNext()
			end
		end
	end)

	NewsDrop.f = f
	return f
end

local function ApplyDimToTexture(tex, dim)
	if not tex then
		return
	end
	if dim then
		if not tex.__wgDim then
			local r, g, b, a = tex:GetVertexColor()
			tex.__wgDim = { r = r, g = g, b = b, a = a }
		end
		tex:SetVertexColor(DIM_COLOR, DIM_COLOR, DIM_COLOR, tex.__wgDim.a or 1)
	else
		if tex.__wgDim then
			tex:SetVertexColor(tex.__wgDim.r, tex.__wgDim.g, tex.__wgDim.b, tex.__wgDim.a)
			tex.__wgDim = nil
		end
	end
end

local function ApplyDimToFrame(frame, dim)
	if not frame then
		return
	end
	if dim then
		if frame.__wgDimAlpha == nil then
			frame.__wgDimAlpha = frame:GetAlpha()
		end
		frame:SetAlpha(DIM_ALPHA)
	else
		if frame.__wgDimAlpha ~= nil then
			frame:SetAlpha(frame.__wgDimAlpha)
			frame.__wgDimAlpha = nil
		end
	end

	local regions = { frame:GetRegions() }
	for i = 1, #regions do
		ApplyDimToTexture(regions[i], dim)
	end
	local children = { frame:GetChildren() }
	for i = 1, #children do
		ApplyDimToFrame(children[i], dim)
	end
end

local function SetMicroMenuDim(dim)
	for i = 1, #MICRO_BUTTONS do
		local f = _G[MICRO_BUTTONS[i]]
		if f then
			ApplyDimToFrame(f, dim)
		end
	end
end

NewsDrop._SetMicroMenuDim = SetMicroMenuDim

local function ApplyIcon(tex, icon, size)
	if ns.Utils and ns.Utils.SetPearlIcon then
		ns.Utils.SetPearlIcon(tex, icon, size)
	else
		tex:SetSize(size, size)
		tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_Orb_05")
		tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
end

local function PlayDrop(icon, soundId)
	local anchor = GetAnchor()
	if not anchor or (anchor.IsShown and not anchor:IsShown()) then
		return false
	end

	local f = EnsureFrame()
	f._playId = (f._playId or 0) + 1
	local playId = f._playId
	local size = ResolveSize(anchor)
	f:SetSize(size, size)

	local iconVal = NormalizeIcon(icon)
	if not iconVal then
		iconVal = DEFAULT_ICON
	end

	ApplyIcon(f.icon, iconVal, size)

	f:ClearAllPoints()
	f:SetPoint("CENTER", anchor, "CENTER", 0, OFFSETS.start)
	f._anchor = anchor
	f:SetScale(1)
	f.icon:SetAlpha(0)
	f:Show()
	SetMicroMenuDim(true)

	if soundId and PlaySound then
		pcall(PlaySound, soundId, "SFX")
	end

	if f.inAG then
		f.inAG:Stop()
		f.inAG:Play()
	end

	if C_Timer and C_Timer.After then
		C_Timer.After(DUR.inDrop + DUR.hold, function()
			if f:IsShown() and f.outAG and f._playId == playId then
				f.outAG:Stop()
				f.outAG:Play()
			end
		end)
	else
		if f.outAG then
			f.outAG:Stop()
			f.outAG:Play()
		end
	end

	return true
end

function NewsDrop._ShowNext()
	if playing then
		return
	end
	local nextItem = table.remove(queue, 1)
	if not nextItem then
		return
	end
	playing = true
	local okCall, ok = xpcall(function()
		return PlayDrop(nextItem.icon, nextItem.soundId)
	end, geterrorhandler())
	if not okCall then
		-- Evite l'etat bloque (playing=true) si une news distante provoque une erreur d'affichage.
		playing = false
		if C_Timer and C_Timer.After then
			C_Timer.After(0.05, NewsDrop._ShowNext)
		else
			NewsDrop._ShowNext()
		end
		return
	end
	if not ok then
		playing = false
		table.insert(queue, 1, nextItem)
		if C_Timer and C_Timer.After then
			C_Timer.After(0.5, NewsDrop._ShowNext)
		else
			NewsDrop._ShowNext()
		end
	end
end

function NewsDrop.Dismiss()
	queue = {}
	playing = false
	if NewsDrop._SetMicroMenuDim then
		NewsDrop._SetMicroMenuDim(false)
	end
	local f = NewsDrop.f
	if f then
		f._playId = (f._playId or 0) + 1
		if f.inAG then
			f.inAG:Stop()
		end
		if f.outAG then
			f.outAG:Stop()
		end
		f:Hide()
	end
end

function NewsDrop.Show(icon, soundId)
	queue[#queue + 1] = {
		icon = icon,
		soundId = soundId,
	}
	NewsDrop._ShowNext()
end

-- Hook reception/creation news
if EventBus and EventBus.On then
	EventBus.On("WG_NEWS_RECEIVED", function(_, kv)
		if WasRecentlyNotified(kv, 2) then
			return
		end
		if not IsAllowedByPrefs(kv, "remote") then
			return
		end
		local icon = kv and kv.icon or nil
		NewsDrop.lastNews = kv
		RememberNotified(kv)
		local p = Prefs()
		NewsDrop.Show(icon, p.sound and DEFAULT_SOUND_ID or nil)
	end)
	EventBus.On("WG_NEWS_CREATED", function(_, item, _, noBroadcast)
		local source = "local"
		if noBroadcast == true then
			-- noBroadcast=true peut aussi representer une actu distante appliquee localement.
			if IsMyNews(item) then
				return
			end
			source = "remote"
		end
		if WasRecentlyNotified(item, 2) then
			return
		end
		if not IsAllowedByPrefs(item, source) then
			return
		end
		local icon = item and item.icon or nil
		NewsDrop.lastNews = item
		RememberNotified(item)
		local p = Prefs()
		NewsDrop.Show(icon, p.sound and DEFAULT_SOUND_ID or nil)
	end)
end
