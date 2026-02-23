local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
ns.QuartierMiniature.LoadingOverlay = ns.QuartierMiniature.LoadingOverlay or {}
local LoadingOverlay = ns.QuartierMiniature.LoadingOverlay

local function Clamp(v, minV, maxV)
	if v < minV then
		return minV
	end
	if v > maxV then
		return maxV
	end
	return v
end

local function IsDevModeDefault()
	if ns and ns.Utils and ns.Utils.IsDevMode then
		return ns.Utils.IsDevMode() == true
	end
	return false
end

local function FormatDuration(totalSec)
	local s = math.max(0, math.floor(tonumber(totalSec) or 0))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	if h > 0 then
		return string.format("%dh%02dm%02ds", h, m, sec)
	end
	return string.format("%dm%02ds", m, sec)
end

function LoadingOverlay.Create(opts)
	opts = type(opts) == "table" and opts or {}
	local parent = opts.parent
	if not parent then
		return nil
	end
	local isDevMode = type(opts.isDevMode) == "function" and opts.isDevMode or IsDevModeDefault
	local setInputBlocked = type(opts.setInputBlocked) == "function" and opts.setInputBlocked or nil
	local frameLevel = math.max(1, math.floor(tonumber(opts.frameLevel) or ((parent:GetFrameLevel() or 1) + 120)))
	local namePrefix = tostring(opts.namePrefix or "WoWGuilde_QuartierMiniature_LoadingOverlay")
	local function N(suffix)
		return namePrefix .. "_" .. tostring(suffix or "")
	end

	local hideToken = 0

	local root = CreateFrame("Frame", N("Root"), parent)
	root:SetAllPoints(parent)
	root:SetFrameStrata(parent:GetFrameStrata() or "MEDIUM")
	root:SetFrameLevel(frameLevel)
	root:SetClipsChildren(true)
	root:EnableMouse(false)
	root:Hide()

	local bgShade = root:CreateTexture(N("Shade"), "BACKGROUND")
	bgShade:SetAllPoints(root)
	bgShade:SetColorTexture(0, 0, 0, 0.68)

	local devCard = CreateFrame("Frame", N("DevCard"), root)
	devCard:SetSize(540, 120)
	devCard:SetPoint("CENTER", root, "CENTER", 0, -6)
	local devCardBg = devCard:CreateTexture(N("DevCardBg"), "BACKGROUND")
	devCardBg:SetAllPoints(devCard)
	devCardBg:SetColorTexture(0.07, 0.07, 0.07, 0.90)
	local devTitle = devCard:CreateFontString(N("DevTitle"), "OVERLAY", "GameFontNormalLarge")
	devTitle:SetPoint("TOP", devCard, "TOP", 0, -14)
	devTitle:SetText("Mini bolge senkronizasyonu")
	local devBar = CreateFrame("StatusBar", N("DevBar"), devCard)
	devBar:SetPoint("TOPLEFT", devCard, "TOPLEFT", 18, -44)
	devBar:SetPoint("TOPRIGHT", devCard, "TOPRIGHT", -18, -44)
	devBar:SetHeight(18)
	devBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	devBar:SetStatusBarColor(0.80, 0.67, 0.24, 1)
	devBar:SetMinMaxValues(0, 1)
	devBar:SetValue(0)
	local devPercent = devCard:CreateFontString(N("DevPercent"), "OVERLAY", "GameFontHighlight")
	devPercent:SetPoint("TOP", devBar, "BOTTOM", 0, -8)
	devPercent:SetText("0%")
	local devLog = devCard:CreateFontString(N("DevLog"), "OVERLAY", "GameFontHighlightSmall")
	devLog:SetPoint("TOP", devPercent, "BOTTOM", 0, -6)
	devLog:SetText("")
	devLog:SetTextColor(0.82, 0.82, 0.82, 1)
	devLog:SetJustifyH("CENTER")
	devLog:SetWidth(500)

	local fakeRoot = CreateFrame("Frame", N("CloudsRoot"), root)
	fakeRoot:SetAllPoints(root)
	fakeRoot:SetClipsChildren(true)
	fakeRoot:EnableMouse(false)
	fakeRoot:Hide()
	local fakeBg = fakeRoot:CreateTexture(N("CloudsBg"), "BACKGROUND", nil, -8)
	fakeBg:SetAllPoints(fakeRoot)
	fakeBg:SetTexture("Interface\\AddOns\\WoWGuilde\\Media\\MiniGames\\Chargement\\Fond.tga")
	fakeBg:SetAlpha(1)
	fakeBg:SetVertexColor(1, 1, 1, 1)

	local pieces = {}
	local cloudTintR, cloudTintG, cloudTintB = 1, 1, 1
	local function ApplyCloudTint()
		fakeBg:SetVertexColor(cloudTintR, cloudTintG, cloudTintB, 1)
		for i = 1, #pieces do
			local p = pieces[i]
			local tex = p and p.texture or nil
			if tex and tex.SetVertexColor then
				tex:SetVertexColor(cloudTintR, cloudTintG, cloudTintB, 1)
			end
		end
	end
	local function AddPiece(textureName, anchor, subLevel, dx, dy, delaySec, sizeKind, widthOverride, heightOverride)
		local lvl = Clamp(math.floor(tonumber(subLevel) or 0), -8, 7)
		local idx = #pieces + 1
		local tex = fakeRoot:CreateTexture(N("Cloud_" .. tostring(textureName) .. "_" .. tostring(idx)), "ARTWORK", nil, lvl)
		tex:SetTexture("Interface\\AddOns\\WoWGuilde\\Media\\MiniGames\\Chargement\\" .. textureName .. ".tga")
		tex:SetAlpha(1)
		tex:Show()
		local grp = tex:CreateAnimationGroup()
		local move = grp:CreateAnimation("Translation")
		move:SetOrder(1)
		move:SetDuration(2.6)
		move:SetSmoothing("OUT")
		move:SetOffset(dx, dy)
		move:SetStartDelay(delaySec or 0)
		local scale = grp:CreateAnimation("Scale")
		scale:SetOrder(1)
		scale:SetDuration(2.6)
		scale:SetSmoothing("OUT")
		scale:SetScale(1.28, 1.28)
		scale:SetStartDelay(delaySec or 0)
		local alpha = grp:CreateAnimation("Alpha")
		alpha:SetOrder(1)
		alpha:SetDuration(2.2)
		alpha:SetSmoothing("OUT")
		alpha:SetFromAlpha(1)
		alpha:SetToAlpha(0)
		alpha:SetStartDelay(delaySec or 0)
			if grp.SetToFinalAlpha then
				grp:SetToFinalAlpha(true)
			end
			grp:SetScript("OnFinished", function()
				if tex and tex.Hide then
					tex:Hide()
				end
			end)
			pieces[#pieces + 1] = {
				texture = tex,
			anchor = anchor,
			group = grp,
			sizeKind = sizeKind,
			widthOverride = tonumber(widthOverride),
			heightOverride = tonumber(heightOverride),
		}
	end

	-- Ordre du design HTML fourni.
	AddPiece("BG1", "BOTTOMLEFT", 7, -300, -300, 0.50, "corner", 404, 315)
	AddPiece("HD1", "TOPRIGHT", 6, 300, 300, 0.50, "corner", 395, 300)
	AddPiece("BD2", "BOTTOMRIGHT", 5, 300, -300, 0.00, "corner", 404, 350)
	AddPiece("CB1", "BOTTOM", 4, 0, -350, 0.00, "center", 333, 100)
	AddPiece("HG2", "TOPLEFT", 3, -300, 300, 0.50, "corner", 440, 320)
	AddPiece("HG1", "TOPLEFT", 2, -300, 300, 0.00, "corner", 340, 285)
	AddPiece("CH1", "TOP", 1, 0, 350, 0.00, "center", 333, 85)
	AddPiece("BG2", "BOTTOMLEFT", 0, -300, -300, 0.00, "corner", 645, 315)
	AddPiece("BD1", "BOTTOMRIGHT", -1, 300, -300, 0.50, "corner", 615, 400)
	AddPiece("HD2", "TOPRIGHT", -2, 300, 300, 0.00, "corner", 520, 300)

	local bgAnim = fakeBg:CreateAnimationGroup()
	local bgScale = bgAnim:CreateAnimation("Scale")
	bgScale:SetOrder(1)
	bgScale:SetDuration(4.0)
	bgScale:SetSmoothing("OUT")
	bgScale:SetScale(1.5, 1.5)
	local bgAlpha = bgAnim:CreateAnimation("Alpha")
	bgAlpha:SetOrder(1)
	bgAlpha:SetDuration(6.0)
	bgAlpha:SetSmoothing("OUT")
	bgAlpha:SetFromAlpha(1)
	bgAlpha:SetToAlpha(0)
		if bgAnim.SetToFinalAlpha then
			bgAnim:SetToFinalAlpha(true)
		end
		bgAnim:SetScript("OnFinished", function()
			if fakeBg and fakeBg.Hide then
				fakeBg:Hide()
			end
		end)

	local function SetBlocked(flag)
		if setInputBlocked then
			setInputBlocked(flag == true)
		end
	end

	local function SetVisible(flag)
		local show = flag == true
		if show then
			root:Show()
		else
			root:Hide()
			fakeRoot:Hide()
		end
		SetBlocked(show)
	end

	local function LayoutPieces()
		local w = math.max(1, fakeRoot:GetWidth() or 1)
		local h = math.max(1, fakeRoot:GetHeight() or 1)
		local cornerW = math.max(160, math.floor(w * 0.34))
		local cornerH = math.max(160, math.floor(h * 0.34))
		local centerW = math.max(180, math.floor(w * 0.28))
		local centerH = math.max(120, math.floor(h * 0.22))
		for i = 1, #pieces do
			local p = pieces[i]
			local tex = p and p.texture or nil
			if tex then
				tex:ClearAllPoints()
				local anchor = p.anchor or "CENTER"
				if anchor == "TOP" then
					tex:SetPoint("TOP", fakeRoot, "TOP", 0, 0)
				elseif anchor == "BOTTOM" then
					tex:SetPoint("BOTTOM", fakeRoot, "BOTTOM", 0, 0)
				elseif anchor == "TOPLEFT" then
					tex:SetPoint("TOPLEFT", fakeRoot, "TOPLEFT", 0, 0)
				elseif anchor == "TOPRIGHT" then
					tex:SetPoint("TOPRIGHT", fakeRoot, "TOPRIGHT", 0, 0)
				elseif anchor == "BOTTOMLEFT" then
					tex:SetPoint("BOTTOMLEFT", fakeRoot, "BOTTOMLEFT", 0, 0)
				elseif anchor == "BOTTOMRIGHT" then
					tex:SetPoint("BOTTOMRIGHT", fakeRoot, "BOTTOMRIGHT", 0, 0)
				else
					tex:SetPoint("CENTER", fakeRoot, "CENTER", 0, 0)
				end
				local overrideW = tonumber(p.widthOverride)
				local overrideH = tonumber(p.heightOverride)
				if overrideW and overrideH and overrideW > 0 and overrideH > 0 then
					tex:SetSize(overrideW, overrideH)
				elseif p.sizeKind == "center" then
					tex:SetSize(centerW, centerH)
				else
					tex:SetSize(cornerW, cornerH)
				end
			end
		end
	end
	fakeRoot:SetScript("OnSizeChanged", LayoutPieces)

	local function ResetFakeVisual()
		hideToken = hideToken + 1
		if bgAnim and bgAnim.Stop then
			bgAnim:Stop()
		end
			fakeBg:SetAlpha(1)
			fakeBg:Show()
		for i = 1, #pieces do
			local p = pieces[i]
			if p and p.group and p.group.Stop then
				p.group:Stop()
			end
			if p and p.texture then
				p.texture:SetAlpha(1)
				p.texture:Show()
			end
		end
		LayoutPieces()
		ApplyCloudTint()
	end

	local function PlayFakeRevealThenHide()
		ResetFakeVisual()
		fakeRoot:Show()
		if bgAnim and bgAnim.Play then
			bgAnim:Play()
		end
		for i = 1, #pieces do
			local p = pieces[i]
			if p and p.group and p.group.Play then
				p.group:Play()
			end
		end
		local token = hideToken
		if C_Timer and C_Timer.After then
			C_Timer.After(6.1, function()
				if token ~= hideToken then
					return
				end
				fakeRoot:Hide()
				root:Hide()
				SetBlocked(false)
			end)
		else
			fakeRoot:Hide()
			root:Hide()
			SetBlocked(false)
		end
	end

	local E = {}

	function E:Update(show, doneSec, totalSec, logText)
		if show == true then
			if isDevMode() then
				hideToken = hideToken + 1
				fakeRoot:Hide()
				bgShade:SetColorTexture(0, 0, 0, 0.68)
				devCard:Show()
				SetVisible(true)
				local total = math.max(0.001, tonumber(totalSec) or 0.001)
				local done = Clamp(tonumber(doneSec) or 0, 0, total)
				local ratio = Clamp(done / total, 0, 1)
				devBar:SetValue(ratio)
				devPercent:SetText(
					string.format(
						"%d%%  (%s / %s)",
						math.floor((ratio * 100) + 0.5),
						FormatDuration(done),
						FormatDuration(total)
					)
				)
				devLog:SetText(tostring(logText or "Initialisation..."))
			else
				devCard:Hide()
				bgShade:SetColorTexture(0, 0, 0, 0.10)
				if not root:IsShown() then
					SetVisible(true)
				end
				if not fakeRoot:IsShown() then
					ResetFakeVisual()
					fakeRoot:Show()
				end
			end
			return
		end

		if isDevMode() then
			SetVisible(false)
		else
			if root:IsShown() then
				PlayFakeRevealThenHide()
			else
				SetVisible(false)
			end
		end
	end

	function E:HideNow()
		hideToken = hideToken + 1
		SetVisible(false)
	end

	function E:SetEnvironmentTint(r, g, b)
		cloudTintR = Clamp(tonumber(r) or 1, 0, 2)
		cloudTintG = Clamp(tonumber(g) or 1, 0, 2)
		cloudTintB = Clamp(tonumber(b) or 1, 0, 2)
		ApplyCloudTint()
	end

	return E
end

return LoadingOverlay
