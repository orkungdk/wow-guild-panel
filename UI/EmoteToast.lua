--=====================================================================
-- EmoteToast ancré sur l'UI (position fixe), indépendant des boutons.
-- Icône arrive et reste, bulle apparaît ensuite avec le nom puis message,
-- la bulle disparaît, enfin l’icône se réduit et disparaît.
-- Clic droit sur la bulle, on termine tout de suite l’attente textHold.
--=====================================================================
local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
UI.EmoteToast = UI.EmoteToast or {}
local Toast = UI.EmoteToast

local queue, showing = {}, false

-- Réglages art par défaut
local DEFAULT_BG = "Interface\\AddOns\\WoWGuilde\\Media\\toast-bg"
local DEFAULT_ICON = "Interface\\Icons\\Ui_embercourt-emoji-happy"

local function GetEmotePrefs()
	if ns.Emotes and ns.Emotes.GetPrefs then
		return ns.Emotes.GetPrefs()
	end
	return {}
end

-- Options DB, échelle et offsets d’ancrage
local function GetUserScale()
	local D = GetEmotePrefs()
	local s = D and tonumber(D.toastScale) or 1
	return (s and s > 0) and s or 1
end

local function GetUserOffsets()
	local D = GetEmotePrefs()
	local ox = D and tonumber(D.toastOffsetX) or 12
	local oy = D and tonumber(D.toastOffsetY) or 0
	return ox, oy
end

local function ResolveBG()
	local D = GetEmotePrefs()
	return (D and D.toastBG and D.toastBG ~= "" and D.toastBG) or DEFAULT_BG
end

local function ResolveIcon(key)
	local D = GetEmotePrefs()
	local pref = D and D.toastIcon
	if pref ~= nil and pref ~= "" then
		local num = tonumber(pref)
		return num or pref
	end
	local def = ns.Emotes and ns.Emotes.Catalog and ns.Emotes.Catalog[key]
	if def and def.icon ~= nil and def.icon ~= "" then
		local num = tonumber(def.icon)
		return num or def.icon
	end
	return DEFAULT_ICON
end

-- Position d'ancrage (UIParent)
local function GetAnchorPosition()
	local D = GetEmotePrefs()
	local x = D and tonumber(D.toastAnchorX) or -240
	local y = D and tonumber(D.toastAnchorY) or 160
	return x, y
end

local function GetPortraitAnchor()
	if PlayerFrame and PlayerFrame.portrait then
		return PlayerFrame.portrait
	end
	if PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerPortrait then
		return PlayerFrame.PlayerFrameContent.PlayerPortrait
	end
	if _G.PlayerFramePortrait then
		return _G.PlayerFramePortrait
	end
	return nil
end

-- Durées
local DUR = {
	iconIn = 0.26,
	bubbleWait = 0.70,
	bubbleIn = 0.52,
	nameHold = 1.00,
	cross = 0.22,
	textHold = 500.30,
	bubbleOut = 0.20,
	iconOut = 0.18,
}

-- Construction des frames
local function EnsureFrames()
	if Toast.f then
		return Toast.f
	end

	local f = CreateFrame("Frame", "WoWGuilde_EmoteToastRoot", UIParent, "BackdropTemplate")
	f:SetSize(10, 10)
	f:SetClampedToScreen(true)
	f:Hide()

	-- Icône ancrée au bouton de la Minimap
	f.iconFrame = CreateFrame("Frame", nil, UIParent)
	f.iconFrame:SetSize(58, 58)
	f.iconFrame:SetFrameStrata("TOOLTIP")
	f.iconFrame:SetFrameLevel(10000)
	f.iconFrame:SetClampedToScreen(true)
	f.iconFrame:Hide()
	f.iconFrame:EnableMouse(true)

	f.icon = f.iconFrame:CreateTexture(nil, "ARTWORK", nil, 1)
	f.icon:SetAllPoints(f.iconFrame)
	f.icon:SetAlpha(0)
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	-- Anti-shimmer (si dispo sur le client)
	if f.icon.SetSnapToPixelGrid then
		f.icon:SetSnapToPixelGrid(false)
		f.icon:SetTexelSnappingBias(0)
	end

	f.iconMask = f.iconFrame:CreateMaskTexture()
	f.iconMask:SetAllPoints(f.icon)
	f.iconMask:SetAtlas("UI-HUD-UnitFrame-Player-Portrait-Mask")
	f.icon:AddMaskTexture(f.iconMask)

	-- Animations icône: entrée (anti "micro-saut")
	do
		local ag = f.iconFrame:CreateAnimationGroup()
		f.iconInAG = ag

		local function BaseScale()
			return (f.__scale or 1)
		end

		ag:SetScript("OnPlay", function()
			local b = BaseScale()
			f.iconFrame:SetScale(b) -- respecter l’échelle utilisateur
			f.icon:SetAlpha(0)
		end)

		-- Pop en 3 temps, produit des facteurs = 1 (1.20 * 0.85 * 0.980392 ≈ 1)
		local s1 = ag:CreateAnimation("Scale")
		s1:SetOrder(1)
		s1:SetScale(1.20, 1.20)
		s1:SetDuration(DUR.iconIn * 0.46)
		s1:SetSmoothing("OUT")
		s1:SetOrigin("CENTER", 0, 0)

		local s2 = ag:CreateAnimation("Scale")
		s2:SetOrder(2)
		s2:SetScale(0.85, 0.85)
		s2:SetDuration(DUR.iconIn * 0.31)
		s2:SetSmoothing("IN")
		s2:SetOrigin("CENTER", 0, 0)

		local s3 = ag:CreateAnimation("Scale")
		s3:SetOrder(3)
		s3:SetScale(0.980392, 0.980392) -- 1/(1.20*0.85)
		s3:SetDuration(DUR.iconIn * 0.23)
		s3:SetSmoothing("OUT")
		s3:SetOrigin("CENTER", 0, 0)

		local aIcon = ag:CreateAnimation("Alpha")
		aIcon:SetTarget(f.icon)
		aIcon:SetOrder(1)
		aIcon:SetFromAlpha(0)
		aIcon:SetToAlpha(1)
		aIcon:SetDuration(DUR.iconIn)

		ag:SetScript("OnFinished", function()
			-- ne pas écraser l’échelle : on reste exactement sur l’échelle utilisateur
			f.iconFrame:SetScale(BaseScale())
			f.icon:SetAlpha(1)
		end)
	end

	-- Animations icône: sortie
	do
		local ag = f.iconFrame:CreateAnimationGroup()
		f.iconOutAG = ag

		local s = ag:CreateAnimation("Scale")
		s:SetOrder(1)
		s:SetScale(0.60, 0.60)
		s:SetDuration(DUR.iconOut)
		s:SetSmoothing("IN")
		s:SetOrigin("CENTER", 0, 0)

		local a = ag:CreateAnimation("Alpha")
		a:SetTarget(f.icon)
		a:SetOrder(1)
		a:SetFromAlpha(1)
		a:SetToAlpha(0)
		a:SetDuration(DUR.iconOut)
	end

	-- Bulle à droite de l’icône
	f.bubble = CreateFrame("Frame", nil, UIParent)
	f.bubble:SetSize(300, 120)
	f.bubble:SetFrameStrata("TOOLTIP")
	f.bubble:SetFrameLevel(10000)
	f.bubble:SetClampedToScreen(true)
	f.bubble:Hide()
	f.bubble:EnableMouse(true)

	f.shadow = f.bubble:CreateTexture(nil, "BACKGROUND", nil, -1)
	f.shadow:SetPoint("CENTER", f.bubble, "CENTER", 10, -8)
	f.shadow:SetSize(250, 100)
	f.shadow:SetTexture("Interface\\AddOns\\WoWGuilde\\Media\\toast-shadow")
	f.shadow:SetAlpha(0.6)

	f.bg = f.bubble:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints(f.bubble)
	f.bg:SetTexture(ResolveBG())
	f.bg:SetTexCoord(0, 1, 0, 1)
	f.bg:SetAlpha(0.85)

	f.name = f.bubble:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.name:SetPoint("CENTER", f.bubble, "CENTER", 0, 17)
	f.name:SetJustifyH("CENTER")
	f.name:SetTextColor(0.145, 0.145, 0.145, 1)
	f.name:SetAlpha(0)
	f.name:SetFont(f.name:GetFont(), 26)
	f.name:SetShadowOffset(0, 0)

	f.text = f.bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.text:SetPoint("CENTER", f.bubble, "CENTER", 0, 17)
	f.text:SetSize(180, 68)
	f.text:SetJustifyH("CENTER")
	f.text:SetJustifyV("MIDDLE")
	f.text:SetWordWrap(true)
	if f.text.SetNonSpaceWrap then
		f.text:SetNonSpaceWrap(true)
	end
	if f.text.SetMaxLines then
		f.text:SetMaxLines(4)
	end
	f.text:SetAlpha(0)
	f.text:SetTextColor(0.204, 0.137, 0.039, 1)
	f.text:SetFont(f.text:GetFont(), 16)
	f.text:SetShadowOffset(0, 0)
	f._defaultTextFont = (select(1, f.text:GetFont())) or "Fonts\\FRIZQT__.TTF"

	f.newsText2 = f.bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.newsText2:SetPoint("CENTER", f.bubble, "CENTER", 0, -6)
	f.newsText2:SetSize(210, 30)
	f.newsText2:SetJustifyH("CENTER")
	f.newsText2:SetJustifyV("MIDDLE")
	f.newsText2:SetWordWrap(true)
	if f.newsText2.SetNonSpaceWrap then
		f.newsText2:SetNonSpaceWrap(true)
	end
	if f.newsText2.SetMaxLines then
		f.newsText2:SetMaxLines(2)
	end
	f.newsText2:SetAlpha(0)
	f.newsText2:SetShadowOffset(0, 0)
	f.newsText2:Hide()

	-- Timeline bulle
	do
		local tl = f.bubble:CreateAnimationGroup()
		f.bubbleTL = tl

		local delay = tl:CreateAnimation("Alpha")
		delay:SetTarget(f.bubble)
		delay:SetOrder(1)
		delay:SetFromAlpha(0)
		delay:SetToAlpha(0)
		delay:SetDuration(DUR.bubbleWait)

		local bin = tl:CreateAnimation("Alpha")
		bin:SetTarget(f.bubble)
		bin:SetOrder(2)
		bin:SetFromAlpha(0)
		bin:SetToAlpha(1)
		bin:SetDuration(DUR.bubbleIn)

		local nameIn = tl:CreateAnimation("Alpha")
		nameIn:SetTarget(f.name)
		nameIn:SetOrder(2)
		nameIn:SetFromAlpha(0)
		nameIn:SetToAlpha(1)
		nameIn:SetDuration(DUR.bubbleIn)

		local holdName = tl:CreateAnimation("Alpha")
		holdName:SetTarget(f.name)
		holdName:SetOrder(3)
		holdName:SetFromAlpha(1)
		holdName:SetToAlpha(1)
		holdName:SetDuration(DUR.nameHold)

		local x1 = tl:CreateAnimation("Alpha")
		x1:SetTarget(f.name)
		x1:SetOrder(4)
		x1:SetFromAlpha(1)
		x1:SetToAlpha(0)
		x1:SetDuration(DUR.cross)

		local x2 = tl:CreateAnimation("Alpha")
		x2:SetTarget(f.text)
		x2:SetOrder(4)
		x2:SetFromAlpha(0)
		x2:SetToAlpha(1)
		x2:SetDuration(DUR.cross)

		local x2b = tl:CreateAnimation("Alpha")
		x2b:SetTarget(f.newsText2)
		x2b:SetOrder(4)
		x2b:SetFromAlpha(0)
		x2b:SetToAlpha(1)
		x2b:SetDuration(DUR.cross)

		local holdTxt = tl:CreateAnimation("Alpha")
		holdTxt:SetTarget(f.text)
		holdTxt:SetOrder(5)
		holdTxt:SetFromAlpha(1)
		holdTxt:SetToAlpha(1)
		holdTxt:SetDuration(DUR.textHold)
		f._holdTxt = holdTxt

		local holdTxt2 = tl:CreateAnimation("Alpha")
		holdTxt2:SetTarget(f.newsText2)
		holdTxt2:SetOrder(5)
		holdTxt2:SetFromAlpha(1)
		holdTxt2:SetToAlpha(1)
		holdTxt2:SetDuration(DUR.textHold)
		f._holdTxt2 = holdTxt2

		holdTxt:SetScript("OnPlay", function()
			f.__inTextHold = true
			if f.__skipHold then
				f.__skipHold = nil
				C_Timer.After(0, function()
					if f._holdTxt and f._holdTxt:IsPlaying() then
						f._holdTxt:Stop()
					end
					if f._holdTxt2 and f._holdTxt2:IsPlaying() then
						f._holdTxt2:Stop()
					end
				end)
			end
		end)

		holdTxt:SetScript("OnFinished", function()
			f.__inTextHold = false
		end)

		local bout = tl:CreateAnimation("Alpha")
		bout:SetTarget(f.bubble)
		bout:SetOrder(6)
		bout:SetFromAlpha(1)
		bout:SetToAlpha(0)
		bout:SetDuration(DUR.bubbleOut)

		local txtOut = tl:CreateAnimation("Alpha")
		txtOut:SetTarget(f.text)
		txtOut:SetOrder(6)
		txtOut:SetFromAlpha(1)
		txtOut:SetToAlpha(0)
		txtOut:SetDuration(DUR.bubbleOut)

		local txt2Out = tl:CreateAnimation("Alpha")
		txt2Out:SetTarget(f.newsText2)
		txt2Out:SetOrder(6)
		txt2Out:SetFromAlpha(1)
		txt2Out:SetToAlpha(0)
		txt2Out:SetDuration(DUR.bubbleOut)

		local nameOut = tl:CreateAnimation("Alpha")
		nameOut:SetTarget(f.name)
		nameOut:SetOrder(6)
		nameOut:SetFromAlpha(0)
		nameOut:SetToAlpha(0)
		nameOut:SetDuration(DUR.bubbleOut)

		tl:SetScript("OnFinished", function()
			if f.iconOutAG then
				f.iconOutAG:Stop()
				f.iconOutAG:Play()
			end
		end)
	end

	f.bubble:SetScript("OnMouseDown", function(_, button)
		if button == "RightButton" then
			local tl = f.bubbleTL
			if not tl or not tl:IsPlaying() then
				return
			end
			f.__skipHold = true
			if f._holdTxt and f._holdTxt:IsPlaying() then
				f.__skipHold = nil
				f._holdTxt:Stop()
			end
			if f._holdTxt2 and f._holdTxt2:IsPlaying() then
				f.__skipHold = nil
				f._holdTxt2:Stop()
			end
		end
	end)

	f.iconOutAG:SetScript("OnFinished", function()
		f.iconFrame:Hide()
		f.bubble:Hide()
		f.__skipHold = nil
		f.__inTextHold = nil
		if f.newsText2 then
			f.newsText2:Hide()
		end
		showing = false
		if #queue > 0 then
			C_Timer.After(0.05, Toast._ShowNext)
		end
	end)

	Toast.f = f
	return f
end

local NEWS_REACTION_PHRASES = {
	greetings = "seni selamlar ve sunu gosterir",
	thanks = "tesekkur eder ve sunu gosterir",
	wellplayed = "alkislar ve sunu gosterir",
	wow = "etkilendi ve sunu gosterir",
	oops = "uzgun ve sunu gosterir",
	excuse = "ozur diler ve sunu gosterir",
	threaten = "kizgin ve sunu gosterir",
	bye = "hosca kal der ve sunu gosterir",
	gg = "tebrik eder ve sunu gosterir",
}

local NEWS_LINE1_STYLE = {
	font = "Fonts\\FRIZQT__.TTF",
	size = 12,
	r = 0.13,
	g = 0.12,
	b = 0.10,
	a = 1,
}

local NEWS_LINE2_STYLE = {
	font = "Fonts\\FRIZQT__.TTF",
	size = 15,
	r = 0.32,
	g = 0.18,
	b = 0.06,
	a = 1,
}

local function ResolveLineStyle(idx)
	local D = GetEmotePrefs()
	local base = (idx == 1) and NEWS_LINE1_STYLE or NEWS_LINE2_STYLE
	local key = (idx == 1) and "toastNewsLine1" or "toastNewsLine2"
	local font = D and D[key .. "Font"] or nil
	local size = D and tonumber(D[key .. "Size"]) or nil
	local r = D and tonumber(D[key .. "R"]) or nil
	local g = D and tonumber(D[key .. "G"]) or nil
	local b = D and tonumber(D[key .. "B"]) or nil
	local a = D and tonumber(D[key .. "A"]) or nil
	return {
		font = (font and font ~= "") and font or base.font,
		size = (size and size > 0) and size or base.size,
		r = (r and r >= 0 and r <= 1) and r or base.r,
		g = (g and g >= 0 and g <= 1) and g or base.g,
		b = (b and b >= 0 and b <= 1) and b or base.b,
		a = (a and a >= 0 and a <= 1) and a or base.a,
	}
end

local function ResolveTypeLabel(ctx)
	if type(ctx) ~= "table" then
		return nil
	end
	local label = tostring(ctx.newsTypeLabel or "")
	if label ~= "" then
		return label
	end
	local typ = tostring(ctx.newsType or ""):lower()
	if typ == "" then
		return tostring(ctx.newsTitle or "")
	end
	local meta = ns and ns.Data and ns.Data.NewsMeta and ns.Data.NewsMeta[typ] or nil
	if type(meta) == "table" then
		local mLabel = tostring(meta.label or meta.title or "")
		if mLabel ~= "" then
			return mLabel
		end
	end
	return tostring(ctx.newsTitle or typ)
end

local function BuildNewsReactionLines(fromDisplay, key, ctx)
	local who = tostring(fromDisplay or "-")
	local verb = NEWS_REACTION_PHRASES[key] or "sana bir tepki gonderir ve sunu gosterir"
	local line1 = ("%s %s"):format(who, verb)
	local line2 = ResolveTypeLabel(ctx) or "Haber"
	local icon = ctx and ctx.newsIcon
	if icon ~= nil and icon ~= "" then
		line2 = ("|T%s:16:16:0:0:64:64:4:60:4:60|t %s"):format(tostring(icon), line2)
	end
	return line1, line2
end

-- API
function Toast.Queue(key, from, label, opts)
	local D = GetEmotePrefs()
	if D and D.queueMax and #queue >= D.queueMax then
		table.remove(queue, 1)
	end
	opts = type(opts) == "table" and opts or nil
	queue[#queue + 1] = {
		key = key,
		from = from,
		label = label,
		fromPseudo = opts and opts.fromPseudo or nil,
		context = opts and opts.context or nil,
	}
	if not showing then
		Toast._ShowNext()
	end
end

function Toast._ShowNext()
	if showing or #queue == 0 then
		return
	end
	showing = true

	local item = table.remove(queue, 1)
	local f = EnsureFrames()
	local from = (item.fromPseudo and item.fromPseudo ~= "" and item.fromPseudo) or item.from or "-"
	local ctx = type(item.context) == "table" and item.context or nil

	-- Arts
	f.bg:SetTexture(ResolveBG())
	if ctx and ctx.source == "news" and ctx.newsIcon ~= nil and ctx.newsIcon ~= "" then
		f.icon:SetTexture(ctx.newsIcon)
	else
		f.icon:SetTexture(ResolveIcon(item.key))
	end

	-- Textes
	local def = ns.Emotes and ns.Emotes.Catalog and ns.Emotes.Catalog[item.key]
	local phrase
	local newsLine2
	if ctx and ctx.source == "news" then
		phrase, newsLine2 = BuildNewsReactionLines(from, item.key, ctx)
	elseif def and def.phrases and #def.phrases > 0 then
		phrase = def.phrases[math.random(#def.phrases)]
	else
		phrase = ("sana '%s' tepkisini gonderdi"):format(item.label or "?")
	end

	f.name:SetText(from)
	if ctx and ctx.source == "news" then
		local s1 = ResolveLineStyle(1)
		local s2 = ResolveLineStyle(2)
		f.text:ClearAllPoints()
		f.text:SetPoint("TOP", f.bubble, "TOP", 0, -15)
		f.text:SetSize(180, 34)
		if f.text.SetMaxLines then
			f.text:SetMaxLines(2)
		end
		f.text:SetFont(s1.font, s1.size)
		f.text:SetTextColor(s1.r, s1.g, s1.b, s1.a)
		f.text:SetText(phrase)

		f.newsText2:ClearAllPoints()
		f.newsText2:SetPoint("TOP", f.bubble, "TOP", 0, -40)
		f.newsText2:SetSize(180, 30)
		f.newsText2:SetFont(s2.font, s2.size)
		f.newsText2:SetTextColor(s2.r, s2.g, s2.b, s2.a)
		f.newsText2:SetText(newsLine2 or "")
		f.newsText2:Show()
	else
		f.text:ClearAllPoints()
		f.text:SetPoint("CENTER", f.bubble, "CENTER", 0, 17)
		f.text:SetSize(210, 68)
		if f.text.SetMaxLines then
			f.text:SetMaxLines(4)
		end
		f.text:SetTextColor(0.204, 0.137, 0.039, 1)
		f.text:SetFont(f._defaultTextFont or "Fonts\\FRIZQT__.TTF", 12)
		f.text:SetText(("%s %s"):format(from, phrase))
		f.newsText2:SetText("")
		f.newsText2:Hide()
	end

	-- Positionnement et échelle
	local scale = GetUserScale()
	f.__scale = scale
	f.iconFrame:SetScale(scale)
	f.bubble:SetScale(scale)

	f.iconFrame:ClearAllPoints()
	local ax, ay = GetAnchorPosition()
	local anchor = GetPortraitAnchor()
	if anchor then
		f.iconFrame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
	else
		f.iconFrame:SetPoint("CENTER", UIParent, "CENTER", ax, ay)
	end

	f.bubble:ClearAllPoints()
	local ox, oy = GetUserOffsets()
	f.bubble:SetPoint("BOTTOMRIGHT", f.iconFrame, "LEFT", 50, -3 + (oy or 0))

	-- Etats initiaux
	f.icon:SetAlpha(0)
	f.iconFrame:Show()

	f.bubble:SetAlpha(0)
	f.name:SetAlpha(0)
	f.text:SetAlpha(0)
	f.newsText2:SetAlpha(0)
	f.bubble:Show()

	-- Lance les animations
	if f.iconInAG then
		f.iconInAG:Stop()
		f.iconInAG:Play()
	end
	if f.bubbleTL then
		f.bubbleTL:Stop()
		f.bubbleTL:Play()
	end

	-- Son optionnel
	local D = GetEmotePrefs()
	if D and D.sound and PlaySoundFile then
		PlaySoundFile(1892487)
	end
end
