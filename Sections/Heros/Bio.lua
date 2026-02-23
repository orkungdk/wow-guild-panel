local ADDON, ns = ...

local M = ns.HerosSection

function M.BuildBio(ctx)
	local ns = ctx.ns
	local HU = ctx.HU
	local DB = ctx.DB
	local Comms = ctx.Comms
	local const = ctx.const
	local state = ctx.state
	local ui = ctx.ui
	local fn = ctx.fn
	local Prefs = ns and ns.Prefs or nil
	local EnsureGeneralBioDraft

	if M.BuildBioMarkdown then
		M.BuildBioMarkdown(ctx)
	end

	local BIO_CFG = const.BIO_CFG
	local REROLL_OFFSET_X = 10
	local REROLL_OFFSET_Y = -80
	local REROLL_WIDTH = 230
	local REROLL_HEIGHT = 210

	-- =========================================================
	-- BIOGRAPHIE HERO (ScrollFrame Blizzard-like)
	-- =========================================================
	local biographieHero = CreateFrame("Frame", "WoWGuilde_HerosBiographieHero", ui.profile)
	ui.profile.biographieHero = biographieHero

	local biographieHeroArea = CreateFrame("Frame", "WoWGuilde_HerosBiographieHeroArea", biographieHero)
	local rerollArea = CreateFrame("Frame", "WoWGuilde_HerosRerollArea", biographieHero)
	ui.profile.rerollArea = rerollArea

	local function Bio_Layout()
		biographieHeroArea:ClearAllPoints()
		biographieHeroArea:SetPoint("RIGHT", ui.profileArea, "RIGHT", BIO_CFG.offsetX, BIO_CFG.offsetY)
		biographieHeroArea:SetSize(BIO_CFG.width, BIO_CFG.height)

		biographieHero:ClearAllPoints()
		biographieHero:SetAllPoints(biographieHeroArea)

		rerollArea:ClearAllPoints()
		rerollArea:SetPoint("TOPLEFT", biographieHeroArea, "BOTTOMLEFT", REROLL_OFFSET_X, REROLL_OFFSET_Y)
		rerollArea:SetSize(REROLL_WIDTH, REROLL_HEIGHT)
	end
	Bio_Layout()

	-- =========================================================
	-- BACKGROUND
	-- =========================================================

	local bioBg = biographieHeroArea:CreateTexture(nil, "BACKGROUND")
	bioBg:SetPoint("TOPLEFT", -10, 10)
	bioBg:SetPoint("BOTTOMRIGHT", 35, -10)
	bioBg:SetAtlas("LevelUp-Shadow-Lower")
	bioBg:SetTexCoord(0.5, 1, 0, 1)
	bioBg:SetAlpha(0.6)

	local bioBgExtra = biographieHeroArea:CreateTexture(nil, "BORDER")
	bioBgExtra:ClearAllPoints()
	bioBgExtra:SetPoint("TOPLEFT", biographieHeroArea, "TOPLEFT", -25, 111)
	bioBgExtra:SetSize(80, 70)
	bioBgExtra:SetAtlas("housing-dashboard-filigree-corner-TL")
	bioBgExtra:SetAlpha(0.3)

	local bioBgExtra2 = biographieHeroArea:CreateTexture(nil, "BORDER")
	bioBgExtra2:ClearAllPoints()
	bioBgExtra2:SetPoint("TOPLEFT", biographieHeroArea, "TOPLEFT", -8, 65)
	bioBgExtra2:SetSize(165, 97)
	bioBgExtra2:SetAtlas("housing-celebrationtoast-frame")
	bioBgExtra2:SetTexCoord(0.5, 1, 0, 0.5)
	bioBgExtra2:SetAlpha(1)

	local bioBorder = biographieHeroArea:CreateTexture(nil, "BORDER", nil, 2)
	bioBorder:SetPoint("TOPLEFT", -5, 12)
	bioBorder:SetPoint("TOPRIGHT", 0, 12)
	bioBorder:SetHeight(2)
	bioBorder:SetAtlas("LevelUp-Glow-Gold")
	bioBorder:SetTexCoord(0.5, 1, 0, 1)
	bioBorder:SetBlendMode("ADD")
	bioBorder:SetAlpha(0.9)

	-- =========================================================
	-- TITRES
	-- =========================================================

	local bioTitle = biographieHeroArea:CreateFontString(nil, "OVERLAY", nil, 2)
	bioTitle:SetPoint("TOPLEFT", 10, 70)
	bioTitle:SetFont("Fonts\\MORPHEUS.ttf", 20, "OUTLINE")
	bioTitle:SetTextColor(0.894, 0.655, 0.125)
	bioTitle:SetText("Kahraman destani")
	ui.profile.bioTitle = bioTitle

	const.BIO_EMPTY_SELF =
		"Henuz kendin ya da kahramanlarin hakkinda bir hikaye yazmadin.\nIstersen destanini yaz."
	const.BIO_EMPTY_OTHER = "Bu guild kahramani henuz bir destan paylasmadi."

	local function EmitGuildRosterUpdate()
		if ns and ns.EventBus and ns.EventBus.Emit then
			ns.EventBus.Emit("GUILD_ROSTER_UPDATE")
		end
	end

	local function RefreshCommunityMirrorOffsets()
		if ns and ns.UI and ns.UI.UpdateCommunityMirrorOffsets then
			ns.UI.UpdateCommunityMirrorOffsets()
		end
	end

	local function Bio_GetVisibility()
		return (ns.Prefs and ns.Prefs.GetHeros and ns.Prefs.GetHeros("bioVisibility", "public")) or "public"
	end
	fn.Bio_GetVisibility = Bio_GetVisibility

	local function Bio_SetVisibility(value)
		if ns.Prefs and ns.Prefs.SetHeros then
			ns.Prefs.SetHeros("bioVisibility", value)
		end
	end

	local function NormalizeBioVisibility(b)
		if ns.BioRules and ns.BioRules.NormalizeVisibility then
			return ns.BioRules.NormalizeVisibility(b)
		end
		return (b and b.visibility ~= "" and b.visibility) or "public"
	end

	local function Bio_IsPendingDeletion(b)
		if ns.BioRules and ns.BioRules.IsPendingDeletion then
			return ns.BioRules.IsPendingDeletion(b)
		end
		local ts = tonumber(b and b.deletedAt or 0) or 0
		return ts > 0 and ts > time()
	end

	local function Bio_FormatDeletionCountdown(ts)
		if ns.BioRules and ns.BioRules.FormatDeletionCountdown then
			return ns.BioRules.FormatDeletionCountdown(ts)
		end
		local diff = (tonumber(ts or 0) or 0) - time()
		if diff <= 0 then
			return "1 dakikadan az"
		end
		local days = math.floor(diff / 86400)
		local hours = math.floor((diff % 86400) / 3600)
		local mins = math.floor((diff % 3600) / 60)
		if days > 0 then
			return ("%d gun"):format(days)
		end
		if hours > 0 then
			return ("%d sa"):format(hours)
		end
		if mins > 0 then
			return ("%d dk"):format(mins)
		end
		return "1 dakikadan az"
	end

	local function Bio_ShowDeletionTooltip(owner, ts)
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		GameTooltip:SetText("Silme planlandi", 1, 0.35, 0.35)
		GameTooltip:AddLine("Bu karakter artik guild'de degil.", 1, 1, 1, true)
		GameTooltip:AddLine("Silme: " .. Bio_FormatDeletionCountdown(ts) .. " sonra.", 1, 0.82, 0, true)
		GameTooltip:Show()
	end

	local function IsPublicPublished(b)
		if ns.BioRules and ns.BioRules.IsPublicPublished then
			return ns.BioRules.IsPublicPublished(b, { allowPending = true })
		end
		return type(b) == "table" and b.status == "published" and NormalizeBioVisibility(b) ~= "private"
	end

	local function ResolveTargetUID(data)
		local gid = (HU.Util_GetActiveGuildUID and HU.Util_GetActiveGuildUID())
			or (DB and DB.GetGuildUID and DB:GetGuildUID())
		if not gid or gid == "" or not data then
			return nil, nil
		end
		local uid = data.uid
		if (not uid or uid == "") and ns.Data and ns.Data.ResolvePlayerUID then
			uid = ns.Data.ResolvePlayerUID(gid, data.mainFull or data.rosterFull, data.playerGUID)
		end
		return gid, uid
	end

	local function TargetHasPublishedBio(data)
		local gid, uid = ResolveTargetUID(data)
		if not gid or not uid or uid == "" or not (DB and DB.GetGuildMemberPrefs) then
			return false
		end
		local prefs = DB:GetGuildMemberPrefs(gid, uid)
		local map = prefs and prefs.biographie
		if type(map) ~= "table" then
			return false
		end
		for _, b in pairs(map) do
			if IsPublicPublished(b) then
				return true
			end
		end
		return false
	end

	local function Bio_SetAllVisibility(value)
		if not (DB and DB.UpsertGuildMemberPrefs and DB.GetMyUID) then
			return
		end
		local gid = (HU.Util_GetActiveGuildUID and HU.Util_GetActiveGuildUID())
			or (DB and DB.GetGuildUID and DB:GetGuildUID())
		if not gid or gid == "" then
			return
		end
		local uid = DB:GetMyUID()
		local prefs = DB.GetGuildMemberPrefs and DB:GetGuildMemberPrefs(gid, uid) or nil
		local biographie = prefs and prefs.biographie or nil
		if type(biographie) ~= "table" then
			return
		end
		local payload = {}
		local now = time()
		local setAll = (value == "private")
		for k, v in pairs(biographie) do
			if type(v) == "table" then
				local copy = {}
				for kk, vv in pairs(v) do
					copy[kk] = vv
				end
				if not Bio_IsPendingDeletion(copy) then
					local isDraft = (copy.status == "draft")
					if setAll or not isDraft then
						copy.visibility = value
						copy.updatedAt = now
						payload[k] = copy
					end
				end
			end
		end
		DB:UpsertGuildMemberPrefs(gid, uid, { biographie = payload, updatedAt = now })
		if ns and ns.Comms and ns.Comms.SendGuildMemberPrefs then
			ns.Comms:SendGuildMemberPrefs(gid, uid, { biographie = payload, updatedAt = now })
		end
		if ui.profile and ui.profile.BioSide_Rebuild then
			ui.profile:BioSide_Rebuild()
		end
		EmitGuildRosterUpdate()
	end

	local function Bio_PublishAll()
		if not (DB and DB.UpsertGuildMemberPrefs and DB.GetMyUID) then
			return
		end
		local gid = (HU.Util_GetActiveGuildUID and HU.Util_GetActiveGuildUID())
			or (DB and DB.GetGuildUID and DB:GetGuildUID())
		if not gid or gid == "" then
			return
		end
		local uid = DB:GetMyUID()
		local prefs = DB.GetGuildMemberPrefs and DB:GetGuildMemberPrefs(gid, uid) or nil
		local biographie = prefs and prefs.biographie or nil
		if type(biographie) ~= "table" then
			return
		end
		local function Trim(s)
			return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
		end
		local function Bio_IsPublishable(b)
			if type(b) ~= "table" then
				return false
			end
			if Bio_IsPendingDeletion(b) then
				return false
			end
			if b.status == "published" then
				return false
			end
			local title = Trim(b.title)
			if title == "" then
				return false
			end
			local md = Trim(b.md)
			local wow = Trim(b.wow)
			local html = Trim(b.html)
			local text = Trim(b.text)
			return (md ~= "" or wow ~= "" or html ~= "" or text ~= "")
		end
		local payload = {}
		local count = 0
		local now = time()
		for k, v in pairs(biographie) do
			if Bio_IsPublishable(v) then
				local copy = {}
				for kk, vv in pairs(v) do
					copy[kk] = vv
				end
				copy.status = "published"
				copy.visibility = "public"
				copy.updatedAt = now
				payload[k] = copy
				count = count + 1
			end
		end
		if count == 0 then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage("Aucune épopée publiable (titre + texte requis).", 1, 0.2, 0.2, 1)
			end
			return
		end
		DB:UpsertGuildMemberPrefs(gid, uid, { biographie = payload, updatedAt = now })
		if ns and ns.Comms and ns.Comms.SendGuildMemberPrefs then
			ns.Comms:SendGuildMemberPrefs(gid, uid, { biographie = payload, updatedAt = now })
		end
		if ui.profile and ui.profile.BioSide_Rebuild then
			ui.profile:BioSide_Rebuild()
		end
		EmitGuildRosterUpdate()
	end

	local function Bio_DeleteAll()
		if not (DB and DB.UpsertGuildMemberPrefs and DB.GetMyUID) then
			return
		end
		local gid = (HU.Util_GetActiveGuildUID and HU.Util_GetActiveGuildUID())
			or (DB and DB.GetGuildUID and DB:GetGuildUID())
		if not gid or gid == "" then
			return
		end
		local uid = DB:GetMyUID()
		local now = time()
		if ui.profile then
			ui.profile._bioSkipAutoDraft = true
		end
		DB:UpsertGuildMemberPrefs(gid, uid, { biographie = "__DELETE__", updatedAt = now }, true)
		if ns and ns.Comms and ns.Comms.SendGuildMemberPrefs then
			ns.Comms:SendGuildMemberPrefs(gid, uid, { biographie = "__DELETE__", updatedAt = now })
		end
		if ui.profile and ui.profile.BioSide_Rebuild then
			ui.profile:BioSide_Rebuild()
		end
		EmitGuildRosterUpdate()
	end

	local function Bio_HasAny()
		return ui.profile.bioHasAny == true
	end

	local function Bio_HasPublishable()
		if not (DB and DB.GetMyUID) then
			return false
		end
		local gid = (HU.Util_GetActiveGuildUID and HU.Util_GetActiveGuildUID())
			or (DB and DB.GetGuildUID and DB:GetGuildUID())
		if not gid or gid == "" then
			return false
		end
		local uid = DB:GetMyUID()
		local prefs = DB.GetGuildMemberPrefs and DB:GetGuildMemberPrefs(gid, uid) or nil
		local biographie = prefs and prefs.biographie or nil
		if type(biographie) ~= "table" then
			return false
		end
		local function Trim(s)
			return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
		end
		for _, v in pairs(biographie) do
			if type(v) == "table" then
				if not Bio_IsPendingDeletion(v) then
					if v.status ~= "published" then
						local title = Trim(v.title)
						if title ~= "" then
							local md = Trim(v.md)
							local wow = Trim(v.wow)
							local html = Trim(v.html)
							local text = Trim(v.text)
							if md ~= "" or wow ~= "" or html ~= "" or text ~= "" then
								return true
							end
						end
					end
				end
			end
		end
		return false
	end

	local BIO_SIDE_ATLASES = (ns and ns.BACKGROUND_ATLASES) or {}

	local DEFAULT_SIDE_ATLAS = "delve-entrance-background-nightfall-sanctum"

	local function Bio_ApplySideAtlas(tex, atlas)
		if not tex then
			return
		end
		if HU and HU.Util_IsAtlas and HU.Util_IsAtlas(atlas) then
			tex:SetAtlas(atlas)
		end
	end

	local function Bio_ApplyItemAtlas(item, bio)
		if not item or not item.innerBg then
			return
		end
		local atlas = DEFAULT_SIDE_ATLAS
		if bio and type(bio) == "table" then
			local selected = bio.backgroundAtlas or bio.sideAtlas
			if selected and selected ~= "" then
				atlas = selected
			end
		end
		Bio_ApplySideAtlas(item.innerBg, atlas)
	end

	local function Menu_AddRadio(menu, label, value)
		if menu.CreateButton then
			menu:CreateButton(label, function()
				Bio_SetVisibility(value)
				Bio_SetAllVisibility(value)
			end, {
				isRadio = true,
				checked = function()
					return Bio_GetVisibility() == value
				end,
			})
		end
	end

	-- boutons options (self/other)
	local bioOptionsBtn = CreateFrame("Button", "WoWGuilde_HerosBiographieOptions", biographieHeroArea)
	bioOptionsBtn:SetSize(35, 35)
	bioOptionsBtn:SetPoint("LEFT", bioTitle, "RIGHT", -3, -1)
	bioOptionsBtn.icon = bioOptionsBtn:CreateTexture(nil, "ARTWORK")
	bioOptionsBtn.icon:SetAllPoints(bioOptionsBtn)
	bioOptionsBtn.icon:SetAtlas("GM-icon-settings")
	bioOptionsBtn.icon:SetVertexColor(1, 0.769, 0.278, 1)
	bioOptionsBtn.hover = bioOptionsBtn:CreateTexture(nil, "HIGHLIGHT")
	bioOptionsBtn.hover:SetAllPoints(bioOptionsBtn)
	bioOptionsBtn.hover:SetAtlas("GM-icon-settings")
	bioOptionsBtn.hover:SetBlendMode("ADD")
	bioOptionsBtn.hover:SetAlpha(0.5)
	bioOptionsBtn.hover:SetVertexColor(1, 0.769, 0.278, 1)
	ui.profile.bioOptionsBtn = bioOptionsBtn
	bioOptionsBtn:SetScript("OnClick", function(self)
		if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
			return
		end
		local function Generator(owner, root)
			root:CreateTitle("Épopée")
			if Bio_HasAny() then
				root:CreateButton("Supprimer toutes mes épopées", function()
					if StaticPopupDialogs then
						StaticPopupDialogs["WOWGUILDE_DELETE_ALL_BIOS"] = {
							text = "Écrire SUPPRIMER pour confirmer la suppression de toutes vos épopées.",
							button1 = "Oui",
							button2 = "Non",
							hasEditBox = true,
							editBoxWidth = 180,
							EditBoxOnEnterPressed = function(selfEditBox)
								if selfEditBox and selfEditBox.ClearFocus then
									selfEditBox:ClearFocus()
								end
							end,
							OnShow = function(selfPopup)
								if selfPopup.editBox then
									selfPopup.editBox:SetText("")
									selfPopup.editBox:SetFocus()
								end
							end,
							OnAccept = function(selfPopup)
								local box = selfPopup and selfPopup.editBox
								if not box and selfPopup and selfPopup.GetName then
									box = _G[selfPopup:GetName() .. "EditBox"]
								end
								local text = (box and box.GetText and box:GetText()) or ""
								text = text:gsub("^%s+", ""):gsub("%s+$", "")
								if text == "SUPPRIMER" then
									Bio_DeleteAll()
								else
									if UIErrorsFrame and UIErrorsFrame.AddMessage then
										UIErrorsFrame:AddMessage("Texte incorrect. Écrivez SUPPRIMER.", 1, 0.2, 0.2, 1)
									end
									StaticPopup_Show("WOWGUILDE_DELETE_ALL_BIOS")
								end
							end,
							EditBoxOnTextChanged = function() end,
							timeout = 0,
							whileDead = 1,
							hideOnEscape = 1,
							preferredIndex = 3,
						}
						StaticPopup_Show("WOWGUILDE_DELETE_ALL_BIOS")
					else
						Bio_DeleteAll()
					end
				end)
				if root.CreateDivider then
					root:CreateDivider()
				end
				local visibility = root:CreateButton("Changer la visibilité de toute mes épopées")
				if visibility then
					Menu_AddRadio(visibility, "Public (guilde)", "public")
					Menu_AddRadio(visibility, "Privé (moi seul)", "private")
				end
				if Bio_HasPublishable() then
					root:CreateButton("Publier toutes mes épopées", function()
						Bio_PublishAll()
					end)
				end
				if root.CreateDivider then
					root:CreateDivider()
				end
				root:CreateButton("Consulter mes épopées", function()
					if ui.profile and ui.profile.ShowBiographyEdit then
						ui.profile:ShowBiographyEdit()
					end
				end)
			else
				root:CreateButton("Créer mon épopée", function()
					if ui.profile and ui.profile.ShowBiographyEdit then
						ui.profile:ShowBiographyEdit()
					end
				end)
			end
		end
		MenuUtil.CreateContextMenu(self, Generator)
	end)

	local bioOtherOptionsBtn = CreateFrame("Button", "WoWGuilde_HerosBiographieOtherOptions", biographieHeroArea)
	bioOtherOptionsBtn:SetSize(35, 35)
	bioOtherOptionsBtn:SetPoint("LEFT", bioTitle, "RIGHT", 0, 0)
	bioOtherOptionsBtn.icon = bioOtherOptionsBtn:CreateTexture(nil, "ARTWORK")
	bioOtherOptionsBtn.icon:SetAllPoints(bioOtherOptionsBtn)
	bioOtherOptionsBtn.icon:SetAtlas("GM-icon-assist-hover")
	bioOtherOptionsBtn.icon:SetVertexColor(1, 0.769, 0.278, 1)
	bioOtherOptionsBtn.hover = bioOtherOptionsBtn:CreateTexture(nil, "HIGHLIGHT")
	bioOtherOptionsBtn.hover:SetAllPoints(bioOtherOptionsBtn)
	bioOtherOptionsBtn.hover:SetAtlas("GM-icon-assist-hover")
	bioOtherOptionsBtn.hover:SetBlendMode("ADD")
	bioOtherOptionsBtn.hover:SetAlpha(0.5)
	bioOtherOptionsBtn.hover:SetVertexColor(1, 0.769, 0.278, 1)
	ui.profile.bioOtherOptionsBtn = bioOtherOptionsBtn
	bioOtherOptionsBtn:SetScript("OnClick", function(self)
		if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
			return
		end
		local function Generator(owner, root)
			root:CreateTitle("Épopée")
			local data = ui.profile and (ui.profile._bioOtherTarget or ui.profile._bioViewTarget) or nil
			if not data then
				root:CreateButton("Aucune option pour l'instant", function() end, { disabled = true })
				return
			end
			if not TargetHasPublishedBio(data) then
				root:CreateButton("Aucune épopée publiée", function() end, { disabled = true })
				return
			end

			local targetFull = nil
			if HU and HU.ResolveLiveCharacterForData then
				targetFull = HU.ResolveLiveCharacterForData(data)
			end
			if not targetFull or targetFull == "" then
				targetFull = HU and HU.FullNameForData and HU.FullNameForData(data) or nil
			end
			if HU and HU.AddReactionsSubmenu then
				local ok = HU.AddReactionsSubmenu(root, targetFull, { allowNoPrefs = true })
				if not ok then
					root:CreateButton("Envoyer une réaction", function() end, { disabled = true })
				end
			else
				root:CreateButton("Envoyer une réaction", function() end, { disabled = true })
			end

			if root.CreateDivider then
				root:CreateDivider()
			end

			local pseudo = (ns.Utils and ns.Utils.Trim and ns.Utils.Trim(data.pseudo)) or tostring(data.pseudo or "")
			if pseudo == "" then
				pseudo = nil
			end
			local messageTarget = targetFull or pseudo
			root:CreateButton("Envoyer un message", function()
				if not messageTarget or messageTarget == "" then
					if UIErrorsFrame and UIErrorsFrame.AddMessage then
						UIErrorsFrame:AddMessage("Cible introuvable", 1, 0.2, 0.2, 1)
					end
					return
				end
				if ChatFrame_OpenChat then
					ChatFrame_OpenChat("/w " .. messageTarget .. " ")
				elseif ChatFrame_SendTell then
					ChatFrame_SendTell(messageTarget)
				end
			end, { disabled = not messageTarget })

			if root.CreateDivider then
				root:CreateDivider()
			end

			local name = pseudo or (data.pseudo ~= "" and data.pseudo) or "ce héros"
			local needs = HU and HU.NeedsElision and HU.NeedsElision(name) or false
			local de = needs and "d'" or "de "
			local label = "Consulter les épopées " .. de .. name
			root:CreateButton(label, function()
				if ui.profile and ui.profile.ShowBiographyPreview then
					ui.profile:ShowBiographyPreview(data)
				elseif ns and ns.Sections and ns.Sections.Heros_SelectByData then
					ns.Sections.Heros_SelectByData(data)
				end
			end)
		end
		MenuUtil.CreateContextMenu(self, Generator)
	end)

	fn.Bio_GetSideAtlases = function()
		return BIO_SIDE_ATLASES
	end
	fn.Bio_ApplyItemAtlas = Bio_ApplyItemAtlas

	local bioSubtitle = biographieHeroArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bioSubtitle:SetPoint("TOPLEFT", bioTitle, "BOTTOMLEFT", 0, -10)
	bioSubtitle:SetPoint("RIGHT", biographieHeroArea, "RIGHT", -8, 0)
	bioSubtitle:SetJustifyH("LEFT")
	bioSubtitle:SetText("Canli bir hikaye, guild tarafindan beslenir.")
	ui.profile.bioSubtitle = bioSubtitle

	-- =========================================================
	-- SCROLL FRAME (TAILLE FIXE)
	-- =========================================================

	local bioScroll =
		CreateFrame("ScrollFrame", "WoWGuilde_HerosBiographieScroll", biographieHeroArea, "QuestScrollFrameTemplate")

	bioScroll:SetPoint("TOPLEFT", bioSubtitle, "BOTTOMLEFT", 5, -50)
	bioScroll:SetPoint("RIGHT", biographieHeroArea, "RIGHT", -6, 0)
	bioScroll:SetHeight(102)

	local bioCreateBg = bioScroll:CreateTexture(nil, "BACKGROUND")
	bioCreateBg:SetPoint("TOPLEFT", bioScroll, "TOPLEFT", -25, 25)
	bioCreateBg:SetPoint("BOTTOMRIGHT", bioScroll, "BOTTOMRIGHT", 8, -25)
	bioCreateBg:SetAtlas("TalkingHeads-Neutral-TextBackground")
	bioCreateBg:SetAlpha(0.7)

	-- cacher scrollbar
	do
		local sb = bioScroll.ScrollBar or _G["WoWGuilde_HerosBiographieScrollScrollBar"]
		if sb then
			sb:Hide()
			sb:SetAlpha(0)
			sb:SetWidth(1)
			if sb.ScrollUpButton then
				sb.ScrollUpButton:Hide()
			end
			if sb.ScrollDownButton then
				sb.ScrollDownButton:Hide()
			end
			if sb.ThumbTexture then
				sb.ThumbTexture:Hide()
			end
		end
	end

	-- bouton creer
	local bioCreateBtn = CreateFrame("Button", "WoWGuilde_HerosBiographieCreateBtn", biographieHeroArea)
	bioCreateBtn:SetPoint("BOTTOMLEFT", bioScroll, "BOTTOMLEFT", 8, 8)
	local bioCreateText = bioCreateBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	bioCreateText:SetPoint("LEFT")
	bioCreateText:SetText("|A:quest-legendary-available:18:18|a Destanini yaz")
	bioCreateBtn:SetFontString(bioCreateText)
	local bioCreateFont = _G["WoWGuilde_HerosBioCreateFont"] or CreateFont("WoWGuilde_HerosBioCreateFont")
	bioCreateFont:CopyFontObject(GameFontHighlight)
	bioCreateFont:SetTextColor(0.31, 0.153, 0.055, 1)
	bioCreateFont:SetShadowColor(0, 0, 0, 0)
	bioCreateFont:SetShadowOffset(0, 0)
	bioCreateText:SetFontObject(bioCreateFont)
	bioCreateText:SetShadowColor(0, 0, 0, 0)
	bioCreateText:SetShadowOffset(0, 0)
	if bioCreateBtn.SetNormalFontObject then
		bioCreateBtn:SetNormalFontObject(bioCreateFont)
	end
	if bioCreateBtn.SetHighlightFontObject then
		bioCreateBtn:SetHighlightFontObject(bioCreateFont)
	end
	local createPadX = 12
	local createPadY = 8
	bioCreateBtn:SetSize(
		bioCreateText:GetStringWidth() + (createPadX * 2),
		bioCreateText:GetStringHeight() + (createPadY * 2)
	)
	bioCreateBtn:Hide()
	ui.profile.bioCreateBtn = bioCreateBtn
	bioCreateBtn:SetScript("OnClick", function()
		if ui.profile and ui.profile.ShowBiographyEdit then
			ui.profile:ShowBiographyEdit()
		end
	end)

	-- =========================================================
	-- REROLLS (SECTION)
	-- =========================================================
	local rerollDivider = biographieHero:CreateTexture(nil, "BORDER")
	rerollDivider:SetPoint("BOTTOMLEFT", biographieHeroArea, "BOTTOMLEFT", REROLL_OFFSET_X, -2)
	rerollDivider:SetPoint("BOTTOMRIGHT", biographieHeroArea, "BOTTOMLEFT", REROLL_OFFSET_X + REROLL_WIDTH, -2)
	rerollDivider:SetHeight(3)
	rerollDivider:SetAtlas("AnimaChannel-Reinforce-TextShadow")
	rerollDivider:SetAlpha(1)

	local rerollBg = rerollArea:CreateTexture(nil, "BACKGROUND")
	rerollBg:SetPoint("TOPLEFT", rerollArea, "TOPLEFT", -10, 10)
	rerollBg:SetPoint("BOTTOMRIGHT", rerollArea, "BOTTOMRIGHT", 35, -10)
	rerollBg:SetAtlas("glues-gameMode-BG")
	rerollBg:SetAlpha(0.6)

	local rerollTitle = rerollArea:CreateFontString(nil, "OVERLAY", nil, 2)
	rerollTitle:SetPoint("TOPLEFT", rerollArea, "TOPLEFT", -3, 40)
	rerollTitle:SetFont("Fonts\\MORPHEUS.ttf", 18, "OUTLINE")
	rerollTitle:SetTextColor(0.894, 0.655, 0.125, 1)
	rerollTitle:SetText("Guild taburu")

	local rerollScroll =
		CreateFrame("ScrollFrame", "WoWGuilde_HerosRerollScroll", rerollArea, "QuestScrollFrameTemplate")
	rerollScroll:SetPoint("TOPLEFT", rerollTitle, "BOTTOMLEFT", 0, -20)
	rerollScroll:SetPoint("BOTTOMRIGHT", rerollArea, "BOTTOMRIGHT", -6, 5)

	do
		local sb = rerollScroll.ScrollBar or _G["WoWGuilde_HerosRerollScrollScrollBar"]
		if sb then
			sb:Hide()
			sb:SetAlpha(0)
			sb:SetWidth(1)
			if sb.ScrollUpButton then
				sb.ScrollUpButton:Hide()
			end
			if sb.ScrollDownButton then
				sb.ScrollDownButton:Hide()
			end
			if sb.ThumbTexture then
				sb.ThumbTexture:Hide()
			end
		end
	end

	local rerollContent = CreateFrame("Frame", "WoWGuilde_HerosRerollContent", rerollScroll)
	rerollScroll:SetScrollChild(rerollContent)
	rerollContent:SetPoint("TOPLEFT")
	rerollContent:SetWidth(1)
	rerollContent:SetHeight(1)

	local rerollItems = {}
	local rerollForcedMainByHeroKey = {}
	local REROLL_ITEM_H = 20

	local function FindGuildIndexByFull(fullName)
		if not fullName or fullName == "" or not GetNumGuildMembers or not GetGuildRosterInfo then
			return nil
		end
		local targetShort = Ambiguate and Ambiguate(fullName, "none") or fullName
		local n = GetNumGuildMembers() or 0
		for i = 1, n do
			local name = GetGuildRosterInfo(i)
			if name and name ~= "" then
				local rosterFull = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name
				local rosterShort = Ambiguate and Ambiguate(rosterFull, "none") or rosterFull
				if rosterFull == fullName or rosterShort == targetShort then
					return i
				end
			end
		end
		return nil
	end

	local function ComposeGuildNoteWithMain(rawNote, pseudo, setMain)
		local note = (ns.Utils and ns.Utils.Trim and ns.Utils.Trim(rawNote)) or tostring(rawNote or "")
		local p = (ns.Utils and ns.Utils.Trim and ns.Utils.Trim(pseudo)) or tostring(pseudo or "")
		if p == "" then
			return note
		end
		local firstSeg = note:match("([^,]+)") or ""
		local rest = note:match("^[^,]+,%s*(.*)$")
		if firstSeg == "" then
			firstSeg = p
		end
		firstSeg = firstSeg:gsub("[%s]*[•·]%s*[Mm][Aa][Ii][Nn]", "")
		firstSeg = (ns.Utils and ns.Utils.Trim and ns.Utils.Trim(firstSeg)) or firstSeg
		if firstSeg == "" then
			firstSeg = p
		end
		local outFirst = p
		if setMain then
			outFirst = p .. " • Main"
		end
		if rest and rest ~= "" then
			return outFirst .. ", " .. rest
		end
		return outFirst
	end

	local function SetHeroMainFromEntry(heroData, entry)
		if not heroData or not entry or not entry.fullName then
			return
		end
		if InCombatLockdown and InCombatLockdown() then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage("Impossible en combat.", 1, 0.2, 0.2, 1)
			end
			return
		end
		if not (GetNumGuildMembers and GetGuildRosterInfo and ns and ns.Utils and ns.Utils.ParsePseudo) then
			return
		end
		if not GuildRosterSetPublicNote then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage("API note de guilde indisponible.", 1, 0.2, 0.2, 1)
			end
			return
		end

		local heroKey = (HU and HU.KeyForPseudo and HU.KeyForPseudo(heroData.pseudo or ""))
			or (ns.Utils and ns.Utils.PseudoKey and ns.Utils.PseudoKey(heroData.pseudo or ""))
			or ""
		if heroKey == "" then
			return
		end

		local targetIndex = FindGuildIndexByFull(entry.fullName)
		if not targetIndex then
			return
		end
		rerollForcedMainByHeroKey[heroKey] = entry.fullName

		local canonicalPseudo = (ns.Utils and ns.Utils.Trim and ns.Utils.Trim(heroData and heroData.pseudo)) or ""
		if canonicalPseudo == "" then
			canonicalPseudo = (entry and entry.name) or ""
		end

		local clearChanges = {}
		local setChanges = {}
		local n = GetNumGuildMembers() or 0
		for i = 1, n do
			local name, _, _, _, _, _, note = GetGuildRosterInfo(i)
			if name then
				local pseudo = ns.Utils.ParsePseudo(note, name)
				local pkey = (HU and HU.KeyForPseudo and HU.KeyForPseudo(pseudo))
					or (ns.Utils and ns.Utils.PseudoKey and ns.Utils.PseudoKey(pseudo))
					or pseudo
				if pkey == heroKey then
					local cleared = ComposeGuildNoteWithMain(note, canonicalPseudo, false)
					if tostring(note or "") ~= tostring(cleared or "") then
						clearChanges[#clearChanges + 1] = { idx = i, note = cleared }
					end
					if i == targetIndex then
						local setMain = ComposeGuildNoteWithMain(cleared, canonicalPseudo, true)
						if tostring(cleared or "") ~= tostring(setMain or "") then
							setChanges[#setChanges + 1] = { idx = i, note = setMain }
						end
					end
				end
			end
		end

		-- 1) remove Main suffix from all hero entries
		for i = 1, #clearChanges do
			local c = clearChanges[i]
			pcall(GuildRosterSetPublicNote, c.idx, c.note or "")
		end
		-- 2) set Main suffix on selected entry only
		for i = 1, #setChanges do
			local c = setChanges[i]
			pcall(GuildRosterSetPublicNote, c.idx, c.note or "")
		end
		if C_GuildInfo and C_GuildInfo.GuildRoster then
			C_GuildInfo.GuildRoster()
		elseif GuildRoster then
			GuildRoster()
		end
		if C_Timer and C_Timer.After and C_GuildInfo and C_GuildInfo.GuildRoster then
			C_Timer.After(0.2, function()
				C_GuildInfo.GuildRoster()
			end)
		end
		if ui and ui.profile and ui.profile.Reroll_Update then
			ui.profile:Reroll_Update(heroData)
		end
		if ns and ns.Sections and ns.Sections.HerosFrame and ns.Sections.HerosFrame.Refresh then
			ns.Sections.HerosFrame.Refresh()
		end
	end

	local function CanEditGuildPublicNote()
		if C_GuildInfo and C_GuildInfo.CanEditPublicNote then
			return C_GuildInfo.CanEditPublicNote() == true
		end
		return true
	end

	local function OpenRerollMenu(anchor, heroData, entry)
		if not (MenuUtil and type(MenuUtil.CreateContextMenu) == "function") then
			return
		end
		MenuUtil.CreateContextMenu(anchor or UIParent, function(_, root)
			root:CreateTitle((entry and entry.name) or "Personnage")
			root:CreateButton("Passer en main", function()
				SetHeroMainFromEntry(heroData, entry)
			end, { disabled = not CanEditGuildPublicNote() })
		end)
	end

	local function Reroll_AcquireItem(index)
		local item = rerollItems[index]
		if not item then
			item = CreateFrame("Frame", nil, rerollContent)
			item:SetHeight(REROLL_ITEM_H)
			item:EnableMouse(true)
			item.hl = item:CreateTexture(nil, "ARTWORK")
			item.hl:SetAllPoints(item)
			item.hl:SetAtlas("shop-header-menu-selected-right", true)
			item.hl:SetAlpha(0.8)
			item.hl:SetBlendMode("ADD")
			item.hl:Hide()
			item.text = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			item.text:SetPoint("LEFT", 6, 0)
			item.text:SetPoint("RIGHT", -6, 0)
			item.text:SetJustifyH("LEFT")
			item.text:SetTextColor(0.9, 0.9, 0.9, 1)
			item.mainIcon = nil
			item.sep = item:CreateTexture(nil, "BORDER")
			item.sep:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, -2)
			item.sep:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, -2)
			item.sep:SetHeight(2)
			item.sep:SetAtlas("AnimaChannel-Reinforce-TextShadow")
			item.sep:SetAlpha(1)
			item:SetScript("OnEnter", function(self)
				if self.hl then
					self.hl:Show()
				end
				if not GameTooltip then
					return
				end
				local fullName = self._fullName
				if not fullName or fullName == "" then
					return
				end
				local realm = fullName:match("%-(.+)$") or fullName
				GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
				GameTooltip:ClearLines()
				GameTooltip:AddLine(realm, 1, 1, 1, true)
				GameTooltip:AddLine(
					"Dernière connexion connue :\n" .. tostring(self._lastOnlineText or "offline"),
					0.8,
					0.8,
					0.8,
					true
				)
				GameTooltip:Show()
				GameTooltip:SetScript("OnUpdate", function(tt)
					local x, y = GetCursorPosition()
					if not x or not y then
						return
					end
					local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
					tt:ClearAllPoints()
					tt:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (x / scale) + 16, (y / scale) + 16)
				end)
			end)
			item:SetScript("OnLeave", function()
				if item.hl then
					item.hl:Hide()
				end
				if GameTooltip then
					GameTooltip:SetScript("OnUpdate", nil)
					GameTooltip:Hide()
				end
			end)
			item:SetScript("OnMouseUp", function(self, button)
				if button ~= "RightButton" then
					return
				end
				if not self._entry or not self._heroData then
					return
				end
				OpenRerollMenu(self, self._heroData, self._entry)
			end)
			rerollItems[index] = item
		end
		item:Show()
		return item
	end

	local function Reroll_Clear(isNewcomer)
		local item = Reroll_AcquireItem(1)
		item:ClearAllPoints()
		item:SetPoint("TOPLEFT", rerollContent, "TOPLEFT", 0, -4)
		item:SetPoint("TOPRIGHT", rerollContent, "TOPRIGHT", 0, -4)
		if isNewcomer then
			item.text:SetText("Bu karakter yeni katildi. Iletisim kurmaktan cekinme.")
		else
			item.text:SetText("Karakter bulunamadi.")
		end
		item.text:SetTextColor(0.7, 0.7, 0.7, 1)
		item._fullName = nil
		if item.sep then
			item.sep:Hide()
		end
		for i = 2, #rerollItems do
			rerollItems[i]:Hide()
		end
		rerollContent:SetHeight(REROLL_ITEM_H + 6)
	end

	local function CollectRerollsForHero(data)
		local out = {}
		if not data or not GetNumGuildMembers then
			return out
		end
		if not (ns and ns.Utils and ns.Utils.ParsePseudo) then
			return out
		end
		local heroKey = ""
		if HU and HU.KeyForPseudo then
			heroKey = HU.KeyForPseudo(data.pseudo or "")
		elseif ns.Utils and ns.Utils.PseudoKey then
			heroKey = ns.Utils.PseudoKey(data.pseudo or "")
		end
		if heroKey == "" then
			return out
		end

		local function ShortName(fullName)
			if not fullName or fullName == "" then
				return ""
			end
			if ns and ns.Utils and ns.Utils.BaseName then
				return ns.Utils.BaseName(fullName)
			end
			return (tostring(fullName):gsub("%-.+$", ""))
		end

		local mainFull = data.mainFull or ""
		local mainShort = mainFull ~= "" and ShortName(mainFull) or ""
		local forcedMainFull = rerollForcedMainByHeroKey[heroKey] or ""
		local forcedMainShort = forcedMainFull ~= "" and ShortName(forcedMainFull) or ""
		local mainEntry = nil
		local alts = {}
		local seen = {}

		local function NameKey(name, full)
			if full and full ~= "" then
				return tostring(full):lower()
			end
			if ns and ns.Utils and ns.Utils.PseudoKey then
				return ns.Utils.PseudoKey(name or "")
			end
			return tostring(name or ""):lower()
		end

		local function RemoveAltByKey(key)
			for i = #alts, 1, -1 do
				if alts[i].key == key then
					table.remove(alts, i)
				end
			end
		end

		local num = GetNumGuildMembers() or 0
		for i = 1, num do
			local name, _, _, _, classDisplayName, _, note, _, online, _, classFileName = GetGuildRosterInfo(i)
			if name then
				local lastText = "offline"
				local lastMinutes = 999999
				if online then
					lastText = "online"
					lastMinutes = 0
				elseif ns and ns.GetLastOnlineInfo then
					local mins, txt = ns.GetLastOnlineInfo(i)
					lastMinutes = tonumber(mins or 999999) or 999999
					if txt and txt ~= "" then
						lastText = txt
					end
				end
				local pseudo, isMainTag = ns.Utils.ParsePseudo(note, name)
				local pkey = (HU and HU.KeyForPseudo and HU.KeyForPseudo(pseudo))
					or (ns.Utils and ns.Utils.PseudoKey and ns.Utils.PseudoKey(pseudo))
					or pseudo
				if pkey == heroKey then
					local full = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name
					local short = ShortName(full)
					local isMain = isMainTag and true or false
					if forcedMainFull ~= "" then
						isMain = (full == forcedMainFull or short == forcedMainShort)
					end
					local classLoc = classDisplayName or classFileName or ""
					local entry = {
						name = short,
						fullName = full,
						classLoc = classLoc,
						classTag = classFileName,
						online = online and true or false,
						lastOnlineText = lastText,
						lastOnlineMinutes = lastMinutes,
						key = NameKey(short, full),
						isMain = isMain,
					}
					if isMain then
						if not mainEntry or (not mainEntry.online and entry.online) then
							mainEntry = entry
						end
						RemoveAltByKey(entry.key)
						seen[entry.key] = true
					else
						if not seen[entry.key] then
							alts[#alts + 1] = entry
							seen[entry.key] = true
						end
					end
				end
			end
		end

		if not mainEntry then
			local fallbackFull = data.mainFull or data.rosterFull or ""
			local fallbackName = mainShort ~= "" and mainShort or ShortName(fallbackFull)
			if fallbackName == "" then
				fallbackName = data.pseudo or ""
			end
			if fallbackName == "" then
				fallbackName = "—"
			end
			local fallbackTag = (data.mainClassTag and data.mainClassTag ~= "" and data.mainClassTag) or data.classTag
			local fallbackLoc = (data.mainClassLoc and data.mainClassLoc ~= "" and data.mainClassLoc)
				or data.classLoc
				or ""
			mainEntry = {
				name = fallbackName,
				fullName = fallbackFull,
				classLoc = fallbackLoc,
				classTag = fallbackTag,
				online = data.online and true or false,
				lastOnlineText = (data.online and "online") or "offline",
				lastOnlineMinutes = (data.online and 0) or 999999,
				key = NameKey(fallbackName),
				isMain = true,
			}
		end

		table.sort(alts, function(a, b)
			local aMin = tonumber(a.lastOnlineMinutes or 999999) or 999999
			local bMin = tonumber(b.lastOnlineMinutes or 999999) or 999999
			if aMin ~= bMin then
				return aMin < bMin
			end
			return (a.name or "") < (b.name or "")
		end)

		out[#out + 1] = mainEntry
		for i = 1, #alts do
			out[#out + 1] = alts[i]
		end

		return out
	end

	local function Reroll_Update(data)
		if not data then
			Reroll_Clear()
			return
		end

		local entries = CollectRerollsForHero(data)
		if data.hasNote == false then
			Reroll_Clear(true)
			return
		end
		if (data.hasNote == false) and (#entries == 0 or (#entries == 1 and entries[1].isMain)) then
			Reroll_Clear(true)
			return
		end
		if #entries == 0 then
			Reroll_Clear(data.hasNote == false)
			return
		end

		local scrollW = rerollScroll:GetWidth() or 0
		if scrollW > 0 then
			rerollContent:SetWidth(scrollW - 12)
		end

		local y = -4
		for i = 1, #entries do
			local entry = entries[i]
			local item = Reroll_AcquireItem(i)
			item:ClearAllPoints()
			item:SetPoint("TOPLEFT", rerollContent, "TOPLEFT", 0, y)
			item:SetPoint("TOPRIGHT", rerollContent, "TOPRIGHT", 0, y)
			local nameText = (entry.name and entry.name ~= "") and entry.name or "—"
			local classText = (entry.classLoc and entry.classLoc ~= "") and entry.classLoc or "—"
			local classColor = (
				ns.Utils
				and ns.Utils.GetClassColorHexSafe
				and ns.Utils.GetClassColorHexSafe(entry.classTag)
			) or "|cffffffff"
			local line = classColor .. string.format("%s • %s", nameText, classText) .. "|r"
			if i == 1 and entry.isMain then
				line = line .. " |A:UI-HUD-UnitFrame-Player-Group-LeaderIcon:16:16:4:0|a"
			end
			if entry.online then
				line = "|A:plunderstorm-map-zoneGreen-hover:14:14|a " .. line
			end
			item.text:SetTextColor(0.9, 0.9, 0.9, 1)
			item.text:SetText(line)
			item.text:ClearAllPoints()
			item.text:SetPoint("LEFT", 6, 0)
			item.text:SetPoint("RIGHT", -6, 0)
			item._fullName = entry.fullName or nil
			item._lastOnlineText = entry.lastOnlineText or ((entry.online and "online") or "offline")
			item._entry = entry
			item._heroData = data
			if item.sep then
				item.sep:Show()
			end
			y = y - REROLL_ITEM_H
		end
		for i = #entries + 1, #rerollItems do
			rerollItems[i]:Hide()
		end
		rerollContent:SetHeight(-y + 6)
	end

	rerollScroll:SetScript("OnSizeChanged", function()
		if ui.profile and ui.profile._profileData then
			Reroll_Update(ui.profile._profileData)
		end
	end)

	function ui.profile:Reroll_Update(data)
		Reroll_Update(data)
	end

	-- =========================================================
	-- SCROLL CHILD (HAUTEUR DYNAMIQUE)
	-- =========================================================

	local bioContent = CreateFrame("Frame", "WoWGuilde_HerosBioContent", bioScroll)
	bioScroll:SetScrollChild(bioContent)

	bioContent:SetPoint("TOPLEFT")
	bioContent:SetWidth(1)
	bioContent:SetHeight(1)

	-- =========================================================
	-- TEXTE
	-- =========================================================

	local bioText = bioContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	bioText:SetPoint("TOPLEFT", 6, -4)
	bioText:SetJustifyH("LEFT")
	bioText:SetJustifyV("TOP")
	bioText:SetWordWrap(true)
	bioText:SetNonSpaceWrap(true)
	bioText:SetTextColor(0.31, 0.153, 0.055, 1)
	bioText:SetShadowColor(0, 0, 0, 0)
	bioText:SetShadowOffset(0, 0)
	bioText:SetSpacing(0.1)
	bioText:SetText("")

	ui.profile.bioText = bioText

	ui.profile.bioHtml = nil

	-- =========================================================
	-- MARKDOWN RENDER (MULTI FONTSTRINGS)
	-- =========================================================

	local mdLines = nil
	local mdActive = false
	local mdPool = {}
	local mdActiveLines = {}
	local mdTexPool = {}
	local mdActiveTextures = {}
	local mdTipPool = {}
	local mdActiveTips = {}
	local mdMeasure = bioContent:CreateFontString(nil, "ARTWORK")

	local baseFont, baseSize, baseFlags = GameFontHighlight:GetFont()
	if not baseFont then
		baseFont = "Fonts\\FRIZQT__.TTF"
		baseSize = 12
		baseFlags = ""
	end

	local mdFonts = {
		h1 = { font = baseFont, size = math.max((baseSize or 12) + 10, 20), flags = baseFlags or "" },
		h2 = { font = baseFont, size = math.max((baseSize or 12) + 6, 16), flags = baseFlags or "" },
		h3 = { font = baseFont, size = math.max((baseSize or 12) + 3, 14), flags = baseFlags or "" },
		text = { font = baseFont, size = baseSize or 12, flags = baseFlags or "" },
		bullet = { font = baseFont, size = baseSize or 12, flags = baseFlags or "" },
	}

	local mdBodyColor = { 0.7, 0.7, 0.7, 1 }
	local mdHeadingColor = { 1, 0.82, 0, 1 }
	local mdBlankHeight = math.max(8, (mdFonts.text.size or 12) + 2)

	local function MD_Clear()
		for i = #mdActiveLines, 1, -1 do
			local fs = mdActiveLines[i]
			mdActiveLines[i] = nil
			if fs then
				fs:SetText("")
				fs:Hide()
				mdPool[#mdPool + 1] = fs
			end
		end
		for i = #mdActiveTextures, 1, -1 do
			local tex = mdActiveTextures[i]
			mdActiveTextures[i] = nil
			if tex then
				tex:Hide()
				tex:SetTexture(nil)
				mdTexPool[#mdTexPool + 1] = tex
			end
		end
		for i = #mdActiveTips, 1, -1 do
			local f = mdActiveTips[i]
			mdActiveTips[i] = nil
			if f then
				f:Hide()
				f._tipTitle = nil
				f._tipBody = nil
				f._tipIcon = nil
				mdTipPool[#mdTipPool + 1] = f
			end
		end
	end

	local function MD_Acquire()
		local fs = table.remove(mdPool)
		if not fs then
			fs = bioContent:CreateFontString(nil, "ARTWORK")
			fs:SetJustifyH("LEFT")
			fs:SetJustifyV("TOP")
			fs:SetWordWrap(true)
			fs:SetNonSpaceWrap(true)
		end
		fs:Show()
		mdActiveLines[#mdActiveLines + 1] = fs
		return fs
	end

	local function MD_AcquireTexture()
		local tex = table.remove(mdTexPool)
		if not tex then
			tex = bioContent:CreateTexture(nil, "ARTWORK")
		end
		tex:Show()
		mdActiveTextures[#mdActiveTextures + 1] = tex
		return tex
	end

	local function MD_AcquireTip()
		local f = table.remove(mdTipPool)
		if not f then
			f = CreateFrame("Frame", nil, bioContent)
			f:EnableMouse(true)
			f._linkTex = f:CreateTexture(nil, "OVERLAY")
			f:SetScript("OnEnter", function(self)
				if (self._tipTitle or self._tipBody or self._tipIcon) and GameTooltip then
					GameTooltip:SetOwner(self, "ANCHOR_TOP")
					if self._tipIcon then
						GameTooltip:SetText(self._tipIcon)
						if self._tipTitle and self._tipTitle ~= "" then
							GameTooltip:AddLine(self._tipTitle, 1, 1, 1, true)
						end
						if self._tipBody and self._tipBody ~= "" then
							GameTooltip:AddLine(self._tipBody, 1, 1, 1, true)
						end
					else
						if self._tipTitle and self._tipTitle ~= "" then
							GameTooltip:SetText(self._tipTitle)
							if self._tipBody and self._tipBody ~= "" then
								GameTooltip:AddLine(self._tipBody, 1, 1, 1, true)
							end
						elseif self._tipBody then
							GameTooltip:SetText(self._tipBody)
						end
					end
					GameTooltip:Show()
				end
			end)
			f:SetScript("OnLeave", function()
				if GameTooltip then
					GameTooltip:Hide()
				end
			end)
		end
		f:Show()
		mdActiveTips[#mdActiveTips + 1] = f
		return f
	end

	local function MD_TextWidth(text, font)
		if not mdMeasure then
			return 0
		end
		mdMeasure:SetFont(font.font, font.size, font.flags)
		mdMeasure:SetText(text or "")
		return mdMeasure:GetStringWidth() or 0
	end

	local function MD_WrapLines(text, maxW, font)
		local out = {}
		local s = text or ""
		local len = #s
		if len == 0 then
			out[1] = { start = 1, ["end"] = 0, width = 0 }
			return out
		end
		local i = 1
		local lineStart = 1
		local lineWidth = 0
		while i <= len do
			local isSpace = s:sub(i, i):match("%s") ~= nil
			local j = i + 1
			while j <= len and (s:sub(j, j):match("%s") ~= nil) == isSpace do
				j = j + 1
			end
			local token = s:sub(i, j - 1)
			local tokenWidth = MD_TextWidth(token, font)
			if lineWidth + tokenWidth > maxW and lineWidth > 0 then
				out[#out + 1] = { start = lineStart, ["end"] = i - 1, width = lineWidth }
				lineStart = i
				lineWidth = 0
			end
			lineWidth = lineWidth + tokenWidth
			i = j
		end
		out[#out + 1] = { start = lineStart, ["end"] = len, width = lineWidth }
		return out
	end

	local function MD_Layout(textW, minH)
		MD_Clear()
		if not mdLines or #mdLines == 0 then
			if minH and minH > 0 then
				bioContent:SetHeight(minH)
			end
			return
		end

		local x = 6
		local y = -4
		local bodyR, bodyG, bodyB, bodyA = bioText:GetTextColor()
		if not bodyR then
			bodyR, bodyG, bodyB, bodyA = mdBodyColor[1], mdBodyColor[2], mdBodyColor[3], mdBodyColor[4]
		end

		for _, line in ipairs(mdLines) do
			if line.kind == "blank" then
				y = y - mdBlankHeight
			elseif line.kind == "texture" then
				if line.before and line.before > 0 then
					y = y - line.before
				end
				local tex = MD_AcquireTexture()
				local xIndent = x + (line.indent or 0)
				local w = textW - (line.indent or 0)
				if w < 20 then
					w = 20
				end
				local drawW = line.width or w
				if line.fullWidth then
					drawW = w
				end
				if drawW > w then
					drawW = w
				end
				local h = line.height
				if not h then
					if line.ratio and drawW > 0 then
						h = drawW * line.ratio
					else
						h = 32
					end
				end
				if h < 8 then
					h = 8
				end
				tex:ClearAllPoints()
				tex:SetPoint("TOPLEFT", xIndent, y)
				tex:SetSize(drawW, h)
				if line.atlas then
					tex:SetAtlas(line.atlas, true)
				else
					tex:SetTexture(line.texture)
				end
				y = y - h
				if line.after and line.after > 0 then
					y = y - line.after
				end
			else
				if line.before and line.before > 0 then
					y = y - line.before
				end
				local fs = MD_Acquire()
				local xIndent = x + (line.indent or 0)
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", xIndent, y)
				local w = textW - (line.indent or 0)
				if w < 20 then
					w = 20
				end
				fs:SetWidth(w)

				local font = mdFonts[line.kind] or mdFonts.text
				fs:SetFont(font.font, font.size, font.flags)
				if line.kind == "h1" or line.kind == "h2" or line.kind == "h3" then
					fs:SetTextColor(mdHeadingColor[1], mdHeadingColor[2], mdHeadingColor[3], mdHeadingColor[4])
				else
					fs:SetTextColor(bodyR, bodyG, bodyB, bodyA)
				end

				fs:SetText(line.text or "")
				local h = fs:GetStringHeight() or font.size or 0
				y = y - h

				if line.tooltips and line.plain and #line.tooltips > 0 then
					local wrapLines = MD_WrapLines(line.plain, w, font)
					local lineCount = #wrapLines
					local lineHeight = (lineCount > 0 and (h / lineCount)) or h
					for _, tip in ipairs(line.tooltips) do
						local rangeStart = tip.offset + 1
						local rangeEnd = tip.offset + tip.length
						for li, ln in ipairs(wrapLines) do
							if rangeEnd >= ln.start and rangeStart <= ln["end"] then
								local segStart = rangeStart > ln.start and rangeStart or ln.start
								local segEnd = rangeEnd < ln["end"] and rangeEnd or ln["end"]
								local before = line.plain:sub(ln.start, segStart - 1)
								local segment = line.plain:sub(segStart, segEnd)
								local xOffset = MD_TextWidth(before, font)
								local wTip = MD_TextWidth(segment, font)
								if wTip < 4 then
									wTip = 4
								end
								local maxW = w - xOffset
								if maxW > 0 and wTip > maxW then
									wTip = maxW
								end
								local tipFrame = MD_AcquireTip()
								tipFrame._tipTitle = tip.title
								tipFrame._tipBody = tip.body
								tipFrame._tipIcon = tip.iconTag
								tipFrame:ClearAllPoints()
								tipFrame:SetPoint("TOPLEFT", fs, "TOPLEFT", xOffset, -((li - 1) * lineHeight))
								tipFrame:SetSize(wTip, lineHeight)
								if tipFrame._linkTex then
									if tip.linkAtlas and tip.linkAtlas ~= "" then
										local wTex = wTip
										local hTex = tip.linkH or 12
										local ox = tip.linkOffsetX or 0
										local oy = tip.linkOffsetY or 0
										tipFrame._linkTex:SetAtlas(tip.linkAtlas)
										tipFrame._linkTex:SetSize(wTex, hTex)
										tipFrame._linkTex:ClearAllPoints()
										tipFrame._linkTex:SetPoint("TOP", tipFrame, "BOTTOM", ox, oy)
										tipFrame._linkTex:Show()
									else
										tipFrame._linkTex:Hide()
									end
								end
							end
						end
					end
				end
				if line.after and line.after > 0 then
					y = y - line.after
				end
			end
		end

		local h = -y + 8
		if minH and minH > 0 and h < minH then
			h = minH
		end
		bioContent:SetHeight(h)
	end

	-- =========================================================
	-- REFLOW (CLE DU SCROLL)
	-- =========================================================

	local bioReflowPending = false
	local function Bio_ReflowImmediate()
		if not bioScroll:IsShown() then
			return
		end

		local scrollW = bioScroll:GetWidth()
		if not scrollW or scrollW <= 0 then
			return
		end
		local scrollH = bioScroll:GetHeight() or 0

		-- largeur fixe (marge ~60)
		local textW = scrollW - 60
		if textW < 20 then
			textW = 20
		end
		bioContent:SetWidth(textW)

		local minH = scrollH > 0 and (scrollH - 8) or 0
		if mdActive then
			MD_Layout(textW, minH)
		else
			bioText:SetWidth(textW)
			bioText:SetText(bioText:GetText() or "")
			local h = bioText:GetStringHeight() or 0
			if h < minH then
				h = minH
			end
			bioContent:SetHeight(h + 12)
		end
	end

	local function Bio_Reflow()
		Bio_ReflowImmediate()
		if bioReflowPending or not (C_Timer and C_Timer.After) then
			return
		end
		bioReflowPending = true
		C_Timer.After(0, function()
			bioReflowPending = false
			Bio_ReflowImmediate()
		end)
	end

	-- =========================================================
	-- HOOKS
	-- =========================================================

	bioScroll:SetScript("OnSizeChanged", Bio_Reflow)
	bioScroll:SetScript("OnShow", Bio_Reflow)
	biographieHeroArea:SetScript("OnShow", Bio_Reflow)

	-- =========================================================
	-- API SIMPLE
	-- =========================================================

	function ui.profile:Bio_ApplyText(text, mode)
		local raw = tostring(text or "")
		if mode == "markdown" then
			if fn.Bio_RenderMarkdownLines then
				mdLines = fn.Bio_RenderMarkdownLines(raw)
				mdActive = true
				bioText:Hide()
			else
				local rendered = (fn.Bio_RenderMarkdown and fn.Bio_RenderMarkdown(raw)) or raw
				mdLines = nil
				mdActive = false
				MD_Clear()
				bioText:Show()
				bioText:SetText(rendered)
			end
		elseif mode == "wow" then
			mdLines = nil
			mdActive = false
			MD_Clear()
			bioText:Show()
			bioText:SetText(raw)
		elseif mode == "html" or mode == true then
			mdLines = nil
			mdActive = false
			MD_Clear()
			bioText:Show()
			bioText:SetText((raw:gsub("<[^>]+>", "")))
		else
			mdLines = nil
			mdActive = false
			MD_Clear()
			bioText:Show()
			bioText:SetText(raw)
		end
		Bio_Reflow()
	end

	function ui.profile:Bio_SetTextColor(r, g, b, a)
		bioText:SetTextColor(r, g, b, a)
		if mdActive then
			Bio_Reflow()
		end
	end

	function ui.profile:SetBiographyText(text, mode)
		if ui.profile.Bio_ApplyText then
			ui.profile:Bio_ApplyText(text, mode)
		else
			bioText:SetText(text or "")
			Bio_Reflow()
		end
	end

	-- =========================================================
	-- ÉDITION ÉPOPÉE (section temporaire)
	-- =========================================================
	local bioEdit = CreateFrame("Frame", "WoWGuilde_HerosBiographieHeroEdit", ui.profile)
	bioEdit:SetAllPoints(ui.profileArea)
	bioEdit:Hide()
	ui.profile.bioEdit = bioEdit

	-- =========================================================
	-- Barre laterale (liste d'epopees)
	-- =========================================================
	local bioEditSide = CreateFrame("Frame", "WoWGuilde_BioEditSide", bioEdit)
	bioEditSide:SetPoint("TOPRIGHT", bioEdit, "TOPRIGHT", 0, -10)
	bioEditSide:SetPoint("BOTTOMRIGHT", bioEdit, "BOTTOMRIGHT", 0, 0)
	bioEditSide:SetWidth(250)
	ui.profile.bioEditSide = bioEditSide

	local bioEditBg = bioEdit:CreateTexture(nil, "BACKGROUND")
	bioEditBg:ClearAllPoints()
	bioEditBg:SetPoint("TOPLEFT", bioEdit, "TOPLEFT", 12, -90)
	bioEditBg:SetPoint("BOTTOMRIGHT", bioEditSide, "BOTTOMLEFT", 1, 13)
	bioEditBg:SetAtlas("glues-gameMode-BG")
	bioEditBg:SetAlpha(0.8)

	local bioEditSideBg = bioEditSide:CreateTexture(nil, "BACKGROUND")
	bioEditSideBg:SetPoint("TOPLEFT", bioEditSide, "TOPLEFT", 0, -85)
	bioEditSideBg:SetPoint("BOTTOMRIGHT", bioEditSide, "BOTTOMRIGHT", -20, 20)
	bioEditSideBg:SetAtlas("glues-gameMode-BG")
	bioEditSideBg:SetAlpha(1)

	local bioEditSideTitle = bioEditSide:CreateFontString(nil, "OVERLAY", nil, 2)
	bioEditSideTitle:SetPoint("TOPLEFT", bioEditSide, "TOPLEFT", 20, -100)
	bioEditSideTitle:SetPoint("RIGHT", bioEditSide, "RIGHT", -36, 0)
	bioEditSideTitle:SetFont("Fonts\\MORPHEUS.ttf", 18, "OUTLINE")
	bioEditSideTitle:SetTextColor(0.894, 0.655, 0.125, 1)
	bioEditSideTitle:SetJustifyH("LEFT")
	bioEditSideTitle:SetText("Destanlar")

	local bioEditSideScroll = CreateFrame(
		"ScrollFrame",
		"WoWGuilde_HerosBiographieSideScrollMainZone",
		bioEditSide,
		"QuestScrollFrameTemplate"
	)
	bioEditSideScroll:SetPoint("TOPLEFT", bioEditSideTitle, "BOTTOMLEFT", 0, -10)
	bioEditSideScroll:SetPoint("BOTTOMRIGHT", bioEditSide, "BOTTOMRIGHT", -52, 30)

	local bioEditSideContent = CreateFrame("Frame", "WoWGuilde_BioEditSideContent", bioEditSideScroll)
	bioEditSideContent:SetSize(180, 1)
	bioEditSideScroll:SetScrollChild(bioEditSideContent)

	local editor = M.BuildBioEditor(ctx, bioEdit, bioEditSide)

	local bioEditSaveBtn = CreateFrame("Button", "WoWGuilde_BioEditSaveBtn", bioEditSide)
	bioEditSaveBtn:SetSize(20, 20)
	bioEditSaveBtn:SetPoint("TOP", bioEditSide, "TOP", 85, -100)
	ui.profile.bioEditSaveBtn = bioEditSaveBtn
	bioEditSaveBtn.icon = bioEditSaveBtn:CreateTexture(nil, "ARTWORK")
	bioEditSaveBtn.icon:SetAllPoints(bioEditSaveBtn)
	bioEditSaveBtn.icon:SetAtlas("common-icon-checkmark-yellow")
	bioEditSaveBtn.icon:SetVertexColor(1, 1, 1, 1)
	bioEditSaveBtn.hover = bioEditSaveBtn:CreateTexture(nil, "HIGHLIGHT")
	bioEditSaveBtn.hover:SetAllPoints(bioEditSaveBtn)
	bioEditSaveBtn.hover:SetAtlas("common-icon-checkmark-yellow")
	bioEditSaveBtn.hover:SetBlendMode("ADD")
	bioEditSaveBtn.hover:SetAlpha(0.5)
	bioEditSaveBtn:SetScript("OnEnter", function(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Kaydet ve cik")
			GameTooltip:Show()
		end
	end)
	bioEditSaveBtn:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	bioEditSaveBtn:SetScript("OnClick", function()
		if ui.profile and ui.profile._bioReadOnly then
			return
		end
		if not editor or not editor.CommitBio then
			return
		end
		local isPublished = editor._activeBioItem
			and editor._activeBioItem._bio
			and editor._activeBioItem._bio.status == "published"
		if isPublished then
			editor.CommitBio()
		else
			editor.CommitBio("draft")
		end
		if ui.profile and ui.profile.HideBiographyEdit then
			ui.profile:HideBiographyEdit()
		end
	end)

	local bioEditExitBtn = CreateFrame("Button", "WoWGuilde_BioEditExitBtn", bioEditSide)
	bioEditExitBtn:SetSize(20, 20)
	bioEditExitBtn:SetPoint("TOP", bioEditSide, "TOP", 85, -100)
	bioEditExitBtn.icon = bioEditExitBtn:CreateTexture(nil, "ARTWORK")
	bioEditExitBtn.icon:SetAllPoints(bioEditExitBtn)
	bioEditExitBtn.icon:SetAtlas("common-icon-rotateright")
	bioEditExitBtn.icon:SetVertexColor(1, 1, 1, 1)
	bioEditExitBtn.hover = bioEditExitBtn:CreateTexture(nil, "HIGHLIGHT")
	bioEditExitBtn.hover:SetAllPoints(bioEditExitBtn)
	bioEditExitBtn.hover:SetAtlas("common-icon-rotateright")
	bioEditExitBtn.hover:SetBlendMode("ADD")
	bioEditExitBtn.hover:SetAlpha(0.5)
	bioEditExitBtn:SetScript("OnEnter", function(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Cik")
			GameTooltip:Show()
		end
	end)
	bioEditExitBtn:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	bioEditExitBtn:SetScript("OnClick", function()
		if ui.profile and ui.profile.HideBiographyEdit then
			ui.profile:HideBiographyEdit()
		end
	end)
	bioEditExitBtn:Hide()
	ui.profile.bioEditExitBtn = bioEditExitBtn

	-- =========================================================
	-- Première case (épôpée du héros) - toujours active
	-- =========================================================
	local EP_ITEM_H = 72
	local BioSide_SetActiveItem = nil
	local epHeroItem = CreateFrame("Button", "WoWGuilde_HerosMainBio", bioEditSideContent)
	epHeroItem:SetPoint("TOPLEFT", bioEditSideContent, "TOPLEFT", -5, 0)
	epHeroItem:SetPoint("RIGHT", bioEditSideContent, "RIGHT", 3, 0)
	epHeroItem:SetHeight(EP_ITEM_H)
	epHeroItem:EnableMouse(true)
	epHeroItem:RegisterForClicks("LeftButtonUp")
	epHeroItem:SetFrameLevel(bioEditSideContent:GetFrameLevel() + 1)

	epHeroItem.bg = epHeroItem:CreateTexture(nil, "BACKGROUND")
	epHeroItem.bg:SetPoint("TOPLEFT", epHeroItem, "TOPLEFT", 2, -2)
	epHeroItem.bg:SetPoint("BOTTOMRIGHT", epHeroItem, "BOTTOMRIGHT", -2, 2)
	epHeroItem.bg:SetAtlas("glues-gameMode-BG")
	epHeroItem.bg:SetAlpha(0.35)

	epHeroItem.innerBg = epHeroItem:CreateTexture(nil, "BORDER")
	epHeroItem.innerBg:SetPoint("TOPLEFT", epHeroItem, "TOPLEFT", -8, 8)
	epHeroItem.innerBg:SetPoint("BOTTOMRIGHT", epHeroItem, "BOTTOMRIGHT", 8, -8)
	epHeroItem.innerBg:SetAtlas("delve-entrance-background-nightfall-sanctum")
	epHeroItem.innerBg:SetVertexColor(0.5, 0.5, 0.5, 0.9)
	epHeroItem.innerBg:SetTexCoord(1, 0, 0, 1)
	epHeroItem.innerBgMask = epHeroItem:CreateMaskTexture(nil, "BORDER")
	epHeroItem.innerBgMask:SetPoint("TOPLEFT", epHeroItem, "TOPLEFT", -8, 26)
	epHeroItem.innerBgMask:SetPoint("BOTTOMRIGHT", epHeroItem, "BOTTOMRIGHT", 8, -25)
	epHeroItem.innerBgMask:SetAtlas("evergreen-weeklyrewards-reward-selected-edgeglow_mask")
	epHeroItem.innerBg:AddMaskTexture(epHeroItem.innerBgMask)

	epHeroItem.hover = epHeroItem:CreateTexture(nil, "HIGHLIGHT")
	epHeroItem.hover:SetPoint("TOPLEFT", epHeroItem, "TOPLEFT", 2, -2)
	epHeroItem.hover:SetPoint("BOTTOMRIGHT", epHeroItem, "BOTTOMRIGHT", -2, 2)
	epHeroItem.hover:SetAtlas("glues-gameMode-BG")
	epHeroItem.hover:SetBlendMode("ADD")
	epHeroItem.hover:SetAlpha(0.5)
	epHeroItem.hover:Hide()

	epHeroItem.active = epHeroItem:CreateTexture(nil, "OVERLAY")
	epHeroItem.active:SetPoint("TOPLEFT", epHeroItem, "TOPLEFT", -5, 2)
	epHeroItem.active:SetPoint("BOTTOMRIGHT", epHeroItem, "BOTTOMRIGHT", 5, 0)
	epHeroItem.active:SetAtlas("n-weeklyrewards-reward-selected-edgeg")
	epHeroItem.active:SetBlendMode("ADD")
	epHeroItem.active:SetAlpha(0.4)
	epHeroItem.active:Hide()

	epHeroItem.title = epHeroItem:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	epHeroItem.title:SetPoint("TOPLEFT", 12, -12)
	epHeroItem.title:SetPoint("RIGHT", 0, 0)
	epHeroItem.title:SetJustifyH("LEFT")
	epHeroItem.title:SetTextColor(1, 1, 1, 1)
	epHeroItem.title:SetText("Kahraman destani")

	epHeroItem.status = epHeroItem:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	epHeroItem.status:SetPoint("BOTTOMLEFT", epHeroItem, "BOTTOMLEFT", 12, 24)
	epHeroItem.status:SetTextColor(0.8, 0.8, 0.8, 1)
	epHeroItem.status:SetText("—")

	epHeroItem.date = epHeroItem:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	epHeroItem.date:SetPoint("BOTTOMLEFT", epHeroItem, "BOTTOMLEFT", 12, 12)
	epHeroItem.date:SetTextColor(0.6, 0.6, 0.6, 1)
	epHeroItem.date:SetText("—")

	epHeroItem:SetScript("OnEnter", function(self)
		if self.hover then
			self.hover:Show()
		end
	end)
	epHeroItem:SetScript("OnLeave", function(self)
		if self.hover then
			self.hover:Hide()
		end
	end)
	epHeroItem:SetScript("OnClick", function(self)
		if self._gid and self._uid then
			if editor and editor.SetEditTargetGeneral then
				editor.SetEditTargetGeneral(self._gid, self._uid, self._bio, self)
			end
			if ui.profile and ui.profile._bioReadOnly and editor and editor.UpdatePreview then
				editor.UpdatePreview()
			end
			BioSide_SetActiveItem(self)
			return
		end
		if editor and editor.SetActiveBioItem then
			editor.SetActiveBioItem(self)
		end
		if editor and editor.ClearStatus then
			editor.ClearStatus("Aucune épopée sélectionnée")
		end
		BioSide_SetActiveItem(self)
	end)
	epHeroItem:SetScript("OnMouseUp", function(self, button)
		if button ~= "RightButton" then
			return
		end
		if ui.profile and ui.profile._bioReadOnly then
			return
		end
		if editor and editor.SetEditTargetGeneral then
			editor.SetEditTargetGeneral(self._gid, self._uid, self._bio, self)
		end
		if editor and editor.OpenOptionsMenu then
			editor.OpenOptionsMenu(self, {
				showLayout = false,
				showCover = true,
				showCoverDivider = false,
				allowDelete = false,
			})
		end
	end)

	local separateur = bioEditSideContent:CreateTexture("separateur", "BORDER")
	separateur:SetPoint("TOPLEFT", epHeroItem, "BOTTOMLEFT", 2, -6)
	separateur:SetPoint("TOPRIGHT", epHeroItem, "BOTTOMRIGHT", -2, -6)
	separateur:SetHeight(3)
	separateur:SetAtlas("AnimaChannel-Reinforce-TextShadow")
	bioEditSideContent:SetHeight(EP_ITEM_H + 16)

	-- =========================================================
	-- Deuxième case (clone visuel)
	-- =========================================================
	local addStory = CreateFrame("Button", "addStory", bioEditSideContent)
	addStory:SetPoint("TOPLEFT", separateur, "BOTTOMLEFT", -2, -6)
	addStory:SetPoint("RIGHT", bioEditSideContent, "RIGHT", 3, 0)
	addStory:SetHeight(EP_ITEM_H)
	ui.profile._bioSideAddStory = addStory
	addStory:EnableMouse(true)
	addStory:RegisterForClicks("LeftButtonUp")
	addStory:SetFrameLevel(bioEditSideContent:GetFrameLevel() + 1)

	addStory.bg = addStory:CreateTexture(nil, "BACKGROUND")
	addStory.bg:SetPoint("TOPLEFT", addStory, "TOPLEFT", 2, -2)
	addStory.bg:SetPoint("BOTTOMRIGHT", addStory, "BOTTOMRIGHT", -2, 2)
	addStory.bg:SetAtlas("glues-gameMode-BG")
	addStory.bg:SetAlpha(0.35)

	addStory.bg2 = addStory:CreateTexture(nil, "BACKGROUND")
	addStory.bg2:SetPoint("CENTER", addStory, "CENTER", 0, 0)
	addStory.bg2:SetSize(40, 40)
	addStory.bg2:SetAtlas("glues-characterSelect-icon-addCard-glow")
	addStory.bg2:SetAlpha(0.6)

	addStory.hoverGlow = addStory:CreateTexture(nil, "HIGHLIGHT")
	addStory.hoverGlow:SetPoint("TOPLEFT", addStory, "TOPLEFT", -3, 5)
	addStory.hoverGlow:SetPoint("BOTTOMRIGHT", addStory, "BOTTOMRIGHT", 3, -3)
	addStory.hoverGlow:SetAtlas("glues-characterSelect-card-glow-FX")
	addStory.hoverGlow:SetAlpha(0.6)
	addStory.hoverGlow:SetBlendMode("ADD")
	addStory.hoverGlow:Hide()

	addStory.hoverPlus = addStory:CreateTexture(nil, "OVERLAY")
	addStory.hoverPlus:SetPoint("CENTER", addStory, "CENTER", 0, 0)
	addStory.hoverPlus:SetAtlas("glues-characterSelect-icon-FX-plus")
	addStory.hoverPlus:SetSize(60, 60)
	addStory.hoverPlus:SetBlendMode("ADD")
	addStory.hoverPlus:SetAlpha(1)
	addStory.hoverPlus:Hide()

	addStory.active = addStory:CreateTexture(nil, "BORDER")
	addStory.active:SetPoint("TOPLEFT", addStory, "TOPLEFT", 2, -2)
	addStory.active:SetPoint("BOTTOMRIGHT", addStory, "BOTTOMRIGHT", -2, 2)
	addStory.active:SetAtlas("glues-gameMode-BG")
	addStory.active:SetAlpha(0.75)
	addStory.active:Hide()

	addStory:SetScript("OnEnter", function(self)
		if self.hoverGlow then
			self.hoverGlow:Show()
		end
		if self.hoverPlus then
			self.hoverPlus:Show()
		end
	end)
	addStory:SetScript("OnLeave", function(self)
		if self.hoverGlow then
			self.hoverGlow:Hide()
		end
		if self.hoverPlus then
			self.hoverPlus:Hide()
		end
	end)
	addStory:SetScript("OnClick", function(self)
		if ui.profile and ui.profile._bioReadOnly then
			return
		end
		if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
			return
		end
		local function Generator(owner, root)
			root:CreateTitle("Créer une épopée")
			local gid = (HU.Util_GetActiveGuildUID and HU.Util_GetActiveGuildUID())
				or (DB and DB.GetGuildUID and DB:GetGuildUID())
			if not gid or gid == "" or not (ns and DB and DB.GetMyUID) then
				root:CreateButton("Aucun personnage disponible", function() end, { disabled = true })
				return
			end
			if DB and DB.SaveSelfProfile then
				DB:SaveSelfProfile()
			end
			local uid = DB:GetMyUID()
			local chars = DB:GetGuildPlayerCharacters(gid, uid) or {}
			local prefs = DB.GetGuildMemberPrefs and DB:GetGuildMemberPrefs(gid, uid) or nil
			local biographie = prefs and prefs.biographie or {}
			if not next(chars) then
				root:CreateButton(
					"Pour créer de nouvelles bio, ajoutez de nouveaux personnages dans la guilde",
					function() end,
					{ disabled = true }
				)
				return
			end
			local any = false
			for full, c in pairs(chars) do
				if not (biographie and type(biographie[full]) == "table") then
					any = true
					local label = c and c.name or (tostring(full):match("^([^%-]+)") or full)
					root:CreateButton(label, function()
						local payload = {
							title = label,
							md = "",
							text = "",
							status = "draft",
							visibility = "private",
							createdAt = time(),
							updatedAt = time(),
						}
						if DB and DB.UpsertGuildMemberPrefs then
							DB:UpsertGuildMemberPrefs(gid, uid, {
								biographie = { [full] = payload },
								updatedAt = time(),
							})
						end
						if ns and ns.Comms and ns.Comms.SendGuildMemberPrefs then
							ns.Comms:SendGuildMemberPrefs(gid, uid, {
								biographie = { [full] = payload },
								updatedAt = time(),
							})
						end
						if ui.profile then
							ui.profile._bioEditTargetFull = full
							ui.profile._bioEditTargetKind = "char"
						end
						if ui.profile and ui.profile.BioSide_Rebuild then
							ui.profile:BioSide_Rebuild()
						end
						if ui.profile and ui.profile.ShowBiographyEdit then
							ui.profile:ShowBiographyEdit()
						end
					end)
				end
			end
			if not any then
				root:CreateButton(
					"Pour créer de nouvelles bio, ajoutez de nouveaux personnages dans la guilde",
					function() end,
					{ disabled = true }
				)
			end
		end
		MenuUtil.CreateContextMenu(self, Generator)
	end)

	-- =========================================================
	-- Liste dynamique des épopées (persos du joueur)
	-- =========================================================
	local function FormatBioStatus(status, visibility)
		if status == "draft" then
			return "Taslak"
		end
		if visibility == "private" then
			return "Yayinlandi (ozel)"
		end
		return "Yayinlandi"
	end

	local function ApplyBioStatusText(fontString, bio)
		if not fontString then
			return
		end
		if Bio_IsPendingDeletion(bio) then
			fontString:SetText("Silme planlandi")
		elseif bio then
			fontString:SetText(FormatBioStatus(bio.status, bio.visibility))
		else
			fontString:SetText("—")
		end
	end

	local function FormatBioDate(ts)
		local t = tonumber(ts or 0) or 0
		if t <= 0 then
			return "—"
		end
		local dt = date("*t", t)
		local day = tonumber(dt.day or 0) or 0
		local month = tonumber(dt.month or 0) or 0
		local year = tonumber(dt.year or 0) or 0
		local names = _G.CALENDAR_FULLDATE_MONTH_NAMES or _G.MONTH_NAMES or _G.CALENDAR_MONTH_NAMES
		if type(names) == "table" and names[month] then
			return string.format("%d %s %d", day, names[month], year)
		end
		if type(FormatShortDate) == "function" then
			return FormatShortDate(day, month, year)
		end
		return date("%Y-%m-%d", t)
	end

	local function EnsureDeletionBadge(item)
		if item._deleteBadge then
			return
		end
		local badge = CreateFrame("Frame", nil, item)
		badge:SetSize(16, 16)
		badge:SetPoint("TOPRIGHT", -10, -10)
		badge.tex = badge:CreateTexture(nil, "ARTWORK")
		badge.tex:SetAllPoints(badge)
		badge.tex:SetAtlas("common-icon-redx")
		badge.tex:SetVertexColor(1, 0.45, 0.2, 1)
		badge:Hide()
		badge:SetScript("OnEnter", function(self)
			if item and item._deleteAt then
				Bio_ShowDeletionTooltip(self, item._deleteAt)
			end
		end)
		badge:SetScript("OnLeave", function()
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)
		item._deleteBadge = badge
	end

	local function UpdateDeletionBadge(item, bio)
		local delAt = tonumber(bio and bio.deletedAt or 0) or 0
		if delAt > 0 and delAt > time() then
			EnsureDeletionBadge(item)
			item._deleteAt = delAt
			item._deleteBadge:Show()
		else
			if item._deleteBadge then
				item._deleteBadge:Hide()
			end
			item._deleteAt = nil
		end
	end

	local function CreateBioSideItem(parent)
		local item = CreateFrame("Button", nil, parent)
		item:SetHeight(EP_ITEM_H)
		item:EnableMouse(true)
		item:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		item:SetFrameLevel(parent:GetFrameLevel() + 1)

		item.bg = item:CreateTexture(nil, "BACKGROUND")
		item.bg:SetPoint("TOPLEFT", item, "TOPLEFT", 2, -2)
		item.bg:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -2, 2)
		item.bg:SetAtlas("glues-gameMode-BG")
		item.bg:SetAlpha(0.35)

		item.innerBg = item:CreateTexture(nil, "BORDER")
		item.innerBg:SetPoint("TOPLEFT", item, "TOPLEFT", -8, 8)
		item.innerBg:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 8, -8)
		item.innerBg:SetAtlas("delve-entrance-background-nightfall-sanctum")
		item.innerBg:SetVertexColor(0.5, 0.5, 0.5, 0.9)
		item.innerBg:SetTexCoord(1, 0, 0, 1)
		item.innerBgMask = item:CreateMaskTexture(nil, "BORDER")
		item.innerBgMask:SetPoint("TOPLEFT", item, "TOPLEFT", -8, 26)
		item.innerBgMask:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 8, -25)
		item.innerBgMask:SetAtlas("evergreen-weeklyrewards-reward-selected-edgeglow_mask")
		item.innerBg:AddMaskTexture(item.innerBgMask)

		item.hover = item:CreateTexture(nil, "HIGHLIGHT")
		item.hover:SetPoint("TOPLEFT", item, "TOPLEFT", 2, -2)
		item.hover:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -2, 2)
		item.hover:SetAtlas("glues-gameMode-BG")
		item.hover:SetBlendMode("ADD")
		item.hover:SetAlpha(0.5)
		item.hover:Hide()

		item.active = item:CreateTexture(nil, "OVERLAY")
		item.active:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 2)
		item.active:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, 0)
		item.active:SetAtlas("glues-characterSelect-card-selected-hover")
		item.active:SetAlpha(0.35)
		item.active:Hide()

		item.title = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		item.title:SetPoint("TOPLEFT", 12, -12)
		item.title:SetPoint("RIGHT", 0, 0)
		item.title:SetJustifyH("LEFT")
		item.title:SetTextColor(1, 1, 1, 1)

		item.status = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		item.status:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 12, 24)
		item.status:SetTextColor(0.8, 0.8, 0.8, 1)

		item.date = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		item.date:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 12, 12)
		item.date:SetTextColor(0.6, 0.6, 0.6, 1)

		item:SetScript("OnEnter", function(self)
			if self.hover then
				self.hover:Show()
			end
		end)
		item:SetScript("OnLeave", function(self)
			if self.hover then
				self.hover:Hide()
			end
		end)

		item:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				return
			end
			if self._gid and self._uid and self._full then
				if editor and editor.SetEditTarget then
					editor.SetEditTarget(self._gid, self._uid, self._full, self._bio, self)
				end
				if ui.profile and ui.profile._bioReadOnly and editor and editor.UpdatePreview then
					editor.UpdatePreview()
				end
				BioSide_SetActiveItem(self)
			end
		end)

		local function OpenBioSideReactionsMenu(owner)
			if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
				return
			end
			MenuUtil.CreateContextMenu(owner, function(_, root)
				if root.CreateTitle then
					root:CreateTitle("Réactions")
				end
				local targetFull = nil
				if owner and owner._full and owner._full ~= "" and owner._full ~= "__general__" then
					targetFull = owner._full
				end
				if not targetFull then
					local data = ui.profile and (ui.profile._bioOtherTarget or ui.profile._bioViewTarget) or nil
					if HU and HU.ResolveLiveCharacterForData then
						targetFull = HU.ResolveLiveCharacterForData(data)
					end
					if not targetFull or targetFull == "" then
						targetFull = HU and HU.FullNameForData and HU.FullNameForData(data) or nil
					end
				end
				if HU and HU.AddReactionsSubmenu then
					local ok = HU.AddReactionsSubmenu(root, targetFull, { allowNoPrefs = true })
					if not ok then
						root:CreateButton("Envoyer une réaction", function() end, { disabled = true })
					end
				else
					root:CreateButton("Envoyer une réaction", function() end, { disabled = true })
				end
			end)
		end

		item:SetScript("OnMouseUp", function(self, button)
			if button ~= "RightButton" then
				return
			end
			if ui.profile and ui.profile._bioReadOnly then
				OpenBioSideReactionsMenu(self)
				return
			end
			if editor and editor.SetEditTarget then
				editor.SetEditTarget(self._gid, self._uid, self._full, self._bio, self)
			end
			if editor and editor.OpenOptionsMenu then
				editor.OpenOptionsMenu(self, { showLayout = false })
			end
		end)

		return item
	end

	BioSide_SetActiveItem = function(item)
		if epHeroItem and epHeroItem.active then
			epHeroItem.active:Hide()
		end
		if addStory and addStory.active then
			addStory.active:Hide()
		end
		local items = ui.profile and ui.profile._bioSideItems or nil
		if items then
			for i = 1, #items do
				local it = items[i]
				if it and it.active then
					it.active:Hide()
				end
			end
		end
		if item and item.active then
			item.active:Show()
		end
	end
	ui.profile.BioSide_SetActiveItem = BioSide_SetActiveItem

	function ui.profile:BioSide_Rebuild()
		if not (ns and DB and DB.GetMyUID and DB.GetGuildPlayerCharacters) then
			return
		end
		local gid = (HU.Util_GetActiveGuildUID and HU.Util_GetActiveGuildUID())
			or (DB and DB.GetGuildUID and DB:GetGuildUID())
		if not gid or gid == "" then
			return
		end
		local viewTarget = (self._bioReadOnly and self._bioViewTarget) or nil
		if viewTarget then
			local uid = viewTarget.uid
			if (not uid or uid == "") and ns.Data and ns.Data.ResolvePlayerUID then
				uid = ns.Data.ResolvePlayerUID(gid, viewTarget.mainFull or viewTarget.rosterFull, viewTarget.playerGUID)
			end
			if not uid or uid == "" then
				if editor and editor.ClearStatus then
					editor.ClearStatus("Aucune épopée publiée")
				end
				return
			end

			local prefs = DB.GetGuildMemberPrefs and DB:GetGuildMemberPrefs(gid, uid) or nil
			local biographie = prefs and prefs.biographie or nil
			local chars = DB:GetGuildPlayerCharacters(gid, uid) or {}
			local epic = biographie and biographie["__general__"] or nil
			local showGeneral = IsPublicPublished(epic)

			if epHeroItem then
				if showGeneral then
					epHeroItem:Show()
					epHeroItem._gid = gid
					epHeroItem._uid = uid
					epHeroItem._bio = epic
					ApplyBioStatusText(epHeroItem.status, epic)
					epHeroItem.date:SetText(FormatBioDate(epic.updatedAt or epic.createdAt))
					Bio_ApplyItemAtlas(epHeroItem, epic)
					UpdateDeletionBadge(epHeroItem, epic)
				else
					epHeroItem:Hide()
					epHeroItem._gid = nil
					epHeroItem._uid = nil
					epHeroItem._bio = nil
					if epHeroItem.active then
						epHeroItem.active:Hide()
					end
					UpdateDeletionBadge(epHeroItem, nil)
				end
			end
			if separateur then
				if showGeneral then
					separateur:Show()
				else
					separateur:Hide()
				end
			end
			if addStory then
				addStory:Hide()
			end

			local list = {}
			if type(biographie) == "table" then
				for full, bio in pairs(biographie) do
					if full ~= "__general__" and IsPublicPublished(bio) then
						list[#list + 1] = { full = full, c = chars[full], bio = bio }
					end
				end
			end
			table.sort(list, function(a, b)
				local at = tonumber(a.bio.updatedAt or a.bio.createdAt or 0) or 0
				local bt = tonumber(b.bio.updatedAt or b.bio.createdAt or 0) or 0
				return at > bt
			end)

			local items = self._bioSideItems or {}
			local prev = showGeneral and separateur or nil
			for i = 1, #list do
				local item = items[i]
				if not item then
					item = CreateBioSideItem(bioEditSideContent)
					items[i] = item
				end
				item:Show()
				item:ClearAllPoints()
				if prev then
					item:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 2, -6)
				else
					item:SetPoint("TOPLEFT", bioEditSideContent, "TOPLEFT", -5, 0)
				end
				item:SetPoint("RIGHT", bioEditSideContent, "RIGHT", 3, 0)

				local c = list[i].c
				local bio = list[i].bio or {}
				local title = bio.title or (c and c.name) or (tostring(list[i].full):match("^([^%-]+)") or list[i].full)
				item.title:SetText(title)
				ApplyBioStatusText(item.status, bio)
				item.date:SetText(FormatBioDate(bio.updatedAt or bio.createdAt))
				item._gid = gid
				item._uid = uid
				item._full = list[i].full
				item._bio = bio
				Bio_ApplyItemAtlas(item, bio)
				UpdateDeletionBadge(item, bio)
				prev = item
			end
			for i = #list + 1, #items do
				items[i]:Hide()
			end
			self._bioSideItems = items

			local visibleCount = #list + (showGeneral and 1 or 0)
			local total = 0
			if visibleCount > 0 then
				total = (visibleCount * EP_ITEM_H) + ((visibleCount - 1) * 6)
			end
			if showGeneral and #list > 0 then
				total = total + 16
			end
			if total <= 0 then
				total = EP_ITEM_H
			end
			bioEditSideContent:SetHeight(total)

			local desiredKind = self._bioEditTargetKind
			local desiredFull = self._bioEditTargetFull
			local selectedItem = nil
			if desiredKind == "char" and desiredFull then
				for i = 1, #items do
					local item = items[i]
					if item and item._full == desiredFull then
						if editor and editor.SetEditTarget then
							editor.SetEditTarget(item._gid, item._uid, item._full, item._bio, item)
						end
						selectedItem = item
						break
					end
				end
			end
			if not selectedItem and showGeneral and epHeroItem and epHeroItem._gid and epHeroItem._uid then
				if editor and editor.SetEditTargetGeneral then
					editor.SetEditTargetGeneral(epHeroItem._gid, epHeroItem._uid, epHeroItem._bio, epHeroItem)
				end
				selectedItem = epHeroItem
			end
			if not selectedItem and #items > 0 then
				local item = items[1]
				if item and editor and editor.SetEditTarget then
					editor.SetEditTarget(item._gid, item._uid, item._full, item._bio, item)
					selectedItem = item
				end
			end
			if selectedItem then
				BioSide_SetActiveItem(selectedItem)
				if self._bioReadOnly and editor and editor.UpdatePreview then
					editor.UpdatePreview()
				end
			else
				BioSide_SetActiveItem(nil)
				if editor and editor.ClearStatus then
					editor.ClearStatus("Aucune épopée publiée")
				end
			end
			return
		end
		if DB and DB.SaveSelfProfile then
			DB:SaveSelfProfile()
		end
		local uid = DB:GetMyUID()
		local chars = DB:GetGuildPlayerCharacters(gid, uid) or {}
		local prefs = DB.GetGuildMemberPrefs and DB:GetGuildMemberPrefs(gid, uid) or nil
		local biographie = prefs and prefs.biographie or nil
		local epic = biographie and biographie["__general__"] or nil
		local skipAutoDraft = self._bioSkipAutoDraft == true
		if skipAutoDraft then
			self._bioSkipAutoDraft = nil
		end
		if not (biographie and type(epic) == "table") then
			if not skipAutoDraft then
				local created = EnsureGeneralBioDraft(true)
				if created then
					biographie = biographie or {}
					biographie["__general__"] = created
					epic = created
				end
			else
				epic = nil
			end
		end
		if epHeroItem then
			epHeroItem._gid = gid
			epHeroItem._uid = uid
			epHeroItem._bio = epic
			if epic then
				ApplyBioStatusText(epHeroItem.status, epic)
				epHeroItem.date:SetText(FormatBioDate(epic.updatedAt or epic.createdAt))
			else
				ApplyBioStatusText(epHeroItem.status, nil)
				epHeroItem.date:SetText("—")
			end
			Bio_ApplyItemAtlas(epHeroItem, epic)
			UpdateDeletionBadge(epHeroItem, epic)
		end
		local available = 0
		local list = {}
		local have = {}
		for full, c in pairs(chars) do
			local bio = biographie and biographie[full] or nil
			if bio and type(bio) == "table" then
				list[#list + 1] = { full = full, c = c, bio = bio }
				have[full] = true
			else
				available = available + 1
			end
		end
		if type(biographie) == "table" then
			for full, bio in pairs(biographie) do
				if full ~= "__general__" and type(bio) == "table" and not have[full] and Bio_IsPendingDeletion(bio) then
					list[#list + 1] = { full = full, c = nil, bio = bio }
				end
			end
		end
		if addStory then
			if available > 0 then
				addStory:Show()
			else
				addStory:Hide()
			end
		end
		table.sort(list, function(a, b)
			local at = tonumber(a.bio.updatedAt or a.bio.createdAt or 0) or 0
			local bt = tonumber(b.bio.updatedAt or b.bio.createdAt or 0) or 0
			return at > bt
		end)

		local items = self._bioSideItems or {}
		local prev = separateur
		for i = 1, #list do
			local item = items[i]
			if not item then
				item = CreateBioSideItem(bioEditSideContent)
				items[i] = item
			end
			item:Show()
			item:ClearAllPoints()
			item:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 2, -6)
			item:SetPoint("RIGHT", bioEditSideContent, "RIGHT", 3, 0)

			local c = list[i].c
			local bio = list[i].bio or {}
			local title = bio.title or (c and c.name) or (tostring(list[i].full):match("^([^%-]+)") or list[i].full)
			item.title:SetText(title)
			ApplyBioStatusText(item.status, bio)
			item.date:SetText(FormatBioDate(bio.updatedAt or bio.createdAt))
			item._gid = gid
			item._uid = uid
			item._full = list[i].full
			item._bio = bio
			Bio_ApplyItemAtlas(item, bio)
			UpdateDeletionBadge(item, bio)
			prev = item
		end
		for i = #list + 1, #items do
			items[i]:Hide()
		end
		self._bioSideItems = items

		if addStory and addStory:IsShown() then
			addStory:ClearAllPoints()
			addStory:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)
			addStory:SetPoint("RIGHT", bioEditSideContent, "RIGHT", 3, 0)
		end
		local total = (EP_ITEM_H * 2) + 32 + (#list * (EP_ITEM_H + 6))
		bioEditSideContent:SetHeight(total)

		local desiredKind = self._bioEditTargetKind
		local desiredFull = self._bioEditTargetFull
		local selected = false
		local selectedItem = nil
		if desiredKind == "char" and desiredFull then
			for i = 1, #items do
				local item = items[i]
				if item and item._full == desiredFull then
					if editor and editor.SetEditTarget then
						editor.SetEditTarget(item._gid, item._uid, item._full, item._bio, item)
					end
					selectedItem = item
					selected = true
					break
				end
			end
		end
		if not selected and epHeroItem and epHeroItem._gid and epHeroItem._uid then
			if editor and editor.SetEditTargetGeneral then
				editor.SetEditTargetGeneral(epHeroItem._gid, epHeroItem._uid, epHeroItem._bio, epHeroItem)
			end
			selectedItem = epHeroItem
		end
		if selectedItem then
			BioSide_SetActiveItem(selectedItem)
		end
	end

	bioEditSideContent:SetHeight((EP_ITEM_H * 2) + 32)

	EnsureGeneralBioDraft = function(silent)
		if not (DB and DB.UpsertGuildMemberPrefs and DB.GetMyUID) then
			return nil
		end
		local gid = (HU.Util_GetActiveGuildUID and HU.Util_GetActiveGuildUID())
			or (DB and DB.GetGuildUID and DB:GetGuildUID())
		if not gid or gid == "" then
			return nil
		end
		local uid = DB:GetMyUID()
		local prefs = DB.GetGuildMemberPrefs and DB:GetGuildMemberPrefs(gid, uid) or nil
		local biographie = prefs and prefs.biographie or nil
		if biographie and type(biographie["__general__"]) == "table" then
			return nil
		end
		local now = time()
		local payload = {
			title = "",
			md = "",
			text = "",
			status = "draft",
			visibility = "private",
			createdAt = now,
			updatedAt = now,
		}
		DB:UpsertGuildMemberPrefs(gid, uid, {
			biographie = { ["__general__"] = payload },
			updatedAt = now,
		})
		if ns and ns.Comms and ns.Comms.SendGuildMemberPrefs then
			ns.Comms:SendGuildMemberPrefs(gid, uid, {
				biographie = { ["__general__"] = payload },
				updatedAt = now,
			})
		end
		if not silent then
			ui.profile._bioEditTargetKind = "general"
			ui.profile._bioEditTargetFull = nil
		end
		if ui.profile then
			ui.profile.bioHasAny = true
			if ui.profile.bioCreateBtn then
				ui.profile.bioCreateBtn:Hide()
			end
		end
		return payload
	end

	function ui.profile:ShowBiographyEdit()
		self._bioReadOnly = false
		self._bioViewTarget = nil
		self._bioEditActive = true
		self._bioEditKey = (state and state.selectedKey) or self._bioEditKey
		EnsureGeneralBioDraft()
		if editor and editor.SetRatioMode then
			local viewMode = (Prefs and Prefs.GetHeros and Prefs.GetHeros("bioEditorView", "edit")) or "edit"
			if viewMode == "double" then
				editor.SetRatioMode(true)
			else
				editor.SetRatioMode(false)
				if editor.SetEditMode then
					editor.SetEditMode(true)
				end
			end
		elseif editor and editor.SetEditMode then
			editor.SetEditMode(true)
		end
		if self.bioEditSaveBtn then
			self.bioEditSaveBtn:Show()
		end
		if self.bioEditExitBtn then
			self.bioEditExitBtn:Hide()
		end
		if self.bioEditorOptionsBtn then
			self.bioEditorOptionsBtn:Show()
		end
		if self.biographieHero then
			self.biographieHero:Hide()
		end
		if self.newsHero then
			self.newsHero:Hide()
		end
		if self.legendaryNewsSlot then
			self.legendaryNewsSlot:Hide()
		end
		if self.bioEdit then
			self.bioEdit:Show()
		end
		if self.BioSide_Rebuild then
			self:BioSide_Rebuild()
		end
		RefreshCommunityMirrorOffsets()
	end

	function ui.profile:ShowBiographyPreview(data)
		if not data then
			return
		end
		self._bioReadOnly = true
		self._bioViewTarget = data
		self._bioEditActive = true
		if HU and HU.KeyForPseudo and data and data.pseudo then
			self._bioEditKey = HU.KeyForPseudo(data.pseudo)
		else
			self._bioEditKey = nil
		end
		self._bioEditTargetKind = nil
		self._bioEditTargetFull = nil
		if editor and editor.SetRatioMode then
			editor.SetRatioMode(false)
		end
		if editor and editor.SetEditMode then
			editor.SetEditMode(false)
		end
		if self.bioEditSaveBtn then
			self.bioEditSaveBtn:Hide()
		end
		if self.bioEditExitBtn then
			self.bioEditExitBtn:Show()
		end
		if self.bioEditorOptionsBtn then
			self.bioEditorOptionsBtn:Hide()
		end
		if self.biographieHero then
			self.biographieHero:Hide()
		end
		if self.newsHero then
			self.newsHero:Hide()
		end
		if self.legendaryNewsSlot then
			self.legendaryNewsSlot:Hide()
		end
		if self.bioEdit then
			self.bioEdit:Show()
		end
		if self.BioSide_Rebuild then
			self:BioSide_Rebuild()
		end
		RefreshCommunityMirrorOffsets()
	end

	function ui.profile:HideBiographyEdit()
		self._bioEditActive = false
		self._bioReadOnly = false
		self._bioViewTarget = nil
		if self.bioEdit then
			self.bioEdit:Hide()
		end
		if self.bioEditSaveBtn then
			self.bioEditSaveBtn:Show()
		end
		if self.bioEditExitBtn then
			self.bioEditExitBtn:Hide()
		end
		if self.bioEditorOptionsBtn then
			self.bioEditorOptionsBtn:Show()
		end
		if self.biographieHero then
			self.biographieHero:Show()
		end
		if self.newsHero then
			self.newsHero:Show()
		end
		if self.legendaryNewsSlot then
			self.legendaryNewsSlot:Show()
		end
		RefreshCommunityMirrorOffsets()
	end

	fn.Bio_Layout = Bio_Layout
end

return M
