local ADDON, ns = ...

local M = ns.HerosSection

function M.BuildRoster(ctx)
	local ns = ctx.ns
	local HU = ctx.HU
	local DB = ctx.DB
	local const = ctx.const
	local state = ctx.state
	local ui = ctx.ui
	local fn = ctx.fn
	local BioRules = ns.BioRules or {}
	local Targets = ns.Targets
	local Reactions = ns.Reactions
	local Comms = ns.Comms

	local function Menu_AddToggleEntry(menu, label, getter, toggler)
		if menu.CreateCheckbox then
			menu:CreateCheckbox(label, getter, toggler)
		else
			menu:CreateButton(label, toggler, { isNotRadio = true, checked = getter })
		end
	end

	local LINE_HEIGHT = const.LINE_HEIGHT
	local ENTRY_GAP = const.ENTRY_GAP
	local MAX_OFFLINE_MIN = const.MAX_OFFLINE_MIN
	local RECENT_ACTIVE_MIN = 14 * 24 * 60

	-- =========================================================
	-- Sélection / affichage profil
	-- =========================================================
	local function ResolveLiveCharacter(data)
		if not data then
			return nil
		end
		if Targets and Targets.ResolveForData then
			local full = Targets.ResolveForData(data)
			if full and full ~= "" then
				return full
			end
		end
		if HU and HU.ResolveLiveCharacterForData then
			local full = HU.ResolveLiveCharacterForData(data)
			if full and full ~= "" then
				return full
			end
		end
		local fallback = data.rosterFull or data.mainFull
		if fallback and fallback ~= "" then
			return fallback
		end
		return nil
	end

	local function SendWhisperToProfileTarget(data)
		local target = ResolveLiveCharacter(data)
		if not target or target == "" then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage("Cible introuvable", 1, 0.2, 0.2, 1)
			end
			return
		end
		if ChatFrame_OpenChat then
			ChatFrame_OpenChat("/w " .. target .. " ")
		elseif ChatFrame_SendTell then
			ChatFrame_SendTell(target)
		end
	end

	local renameHeroTarget = nil
	local renameHeroTargetName = nil

	local function CanManageHeroSettings()
		if not (ns and ns.Roles) then
			return false
		end
		if ns.Roles.IsGuildLeader and ns.Roles.IsGuildLeader() then
			return true
		end
		if ns.Roles.IsOfficer and ns.Roles.IsOfficer() then
			return true
		end
		return false
	end

	local function CanEditGuildPublicNote()
		if C_GuildInfo and C_GuildInfo.CanEditPublicNote then
			return C_GuildInfo.CanEditPublicNote() == true
		end
		return true
	end

	local function ResolveGuildMemberUID(guildUID, data)
		if not guildUID or type(data) ~= "table" then
			return nil
		end
		if data.uid and data.uid ~= "" then
			return data.uid
		end
		if ns and ns.Data and ns.Data.ResolvePlayerUID then
			local full = data.mainFull or data.rosterFull
			local uid = ns.Data.ResolvePlayerUID(guildUID, full, data.playerGUID)
			if uid and uid ~= "" then
				return uid
			end
		end
		return nil
	end

	local function ComposeGuildNoteRename(rawNote, oldPseudo, newPseudo)
		local note = (ns.Utils and ns.Utils.Trim and ns.Utils.Trim(rawNote)) or tostring(rawNote or "")
		local oldP = (ns.Utils and ns.Utils.Trim and ns.Utils.Trim(oldPseudo)) or tostring(oldPseudo or "")
		local newP = (ns.Utils and ns.Utils.Trim and ns.Utils.Trim(newPseudo)) or tostring(newPseudo or "")
		if newP == "" then
			return note
		end
		local firstSeg = note:match("([^,]+)") or ""
		local rest = note:match("^[^,]+,%s*(.*)$")
		local isMain = firstSeg:lower():find("main", 1, true) ~= nil
		if firstSeg == "" then
			firstSeg = oldP
		end
		if firstSeg == "" then
			firstSeg = newP
		end
		local outFirst = newP .. (isMain and " • Main" or "")
		if rest and rest ~= "" then
			return outFirst .. ", " .. rest
		end
		return outFirst
	end

	local function RenameHeroAcrossGuildNotes(data, newPseudo)
		if not data then
			return
		end
		if InCombatLockdown and InCombatLockdown() then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage("Impossible en combat.", 1, 0.2, 0.2, 1)
			end
			return
		end
		if not CanEditGuildPublicNote() then
			return
		end
		if not GuildRosterSetPublicNote then
			return
		end
		local oldPseudo = data.pseudo or ""
		local oldKey = HU.KeyForPseudo and HU.KeyForPseudo(oldPseudo) or oldPseudo
		if not oldKey or oldKey == "" then
			return
		end
		local cleanNew = (ns.Utils and ns.Utils.Trim and ns.Utils.Trim(newPseudo)) or tostring(newPseudo or "")
		if cleanNew == "" then
			return
		end
		local cleanOld = (ns.Utils and ns.Utils.Trim and ns.Utils.Trim(oldPseudo)) or tostring(oldPseudo or "")
		if cleanOld == cleanNew then
			return
		end
		local n = GetNumGuildMembers and GetNumGuildMembers() or 0
		local changes = {}
		for i = 1, n do
			local name, _, _, _, _, _, note = GetGuildRosterInfo(i)
			if name then
				local pseudo = ns.Utils.ParsePseudo(note, name)
				local pkey = HU.KeyForPseudo and HU.KeyForPseudo(pseudo) or pseudo
				local rawFirst = tostring(note or ""):match("([^,]+)") or ""
				local firstWithoutMain = rawFirst:gsub("[%s]*[•·]%s*[Mm][Aa][Ii][Nn]", "")
				local firstKey = HU.KeyForPseudo and HU.KeyForPseudo(firstWithoutMain) or firstWithoutMain
				if pkey == oldKey or firstKey == oldKey then
					local updated = ComposeGuildNoteRename(note, pseudo, cleanNew)
					if tostring(note or "") ~= tostring(updated or "") then
						changes[#changes + 1] = { idx = i, note = updated }
					end
				end
			end
		end
		for i = 1, #changes do
			local c = changes[i]
			pcall(GuildRosterSetPublicNote, c.idx, c.note or "")
		end
		if C_GuildInfo and C_GuildInfo.GuildRoster then
			C_GuildInfo.GuildRoster()
		elseif GuildRoster then
			GuildRoster()
		end
		if ns and ns.Sections and ns.Sections.HerosFrame and ns.Sections.HerosFrame.Refresh then
			ns.Sections.HerosFrame.Refresh()
		end
		if ui and ui.profile and ui.profile._profileData then
			ui.profile._profileData.pseudo = cleanNew
		end
	end

	local function OpenRenameHeroPopup(data)
		if not (StaticPopupDialogs and StaticPopup_Show and data) then
			return
		end
		renameHeroTarget = data
		renameHeroTargetName = (data and data.pseudo) or ""
		if (renameHeroTargetName == "") and data then
			local full = data.mainFull or data.rosterFull or ""
			renameHeroTargetName = (ns.Utils and ns.Utils.BaseName and ns.Utils.BaseName(full)) or full
		end
		if renameHeroTargetName == "" then
			renameHeroTargetName = "?"
		end
		if not StaticPopupDialogs["WOWGUILDE_RENAME_HERO"] then
			StaticPopupDialogs["WOWGUILDE_RENAME_HERO"] = {
				text = 'Kahramanin adini "%s" olarak degistirin (tum karakter notlari guncellenecektir).',
				button1 = "Valider",
				button2 = "Annuler",
				hasEditBox = true,
				editBoxWidth = 220,
				OnShow = function(selfPopup)
					local target = renameHeroTarget
					local curName = renameHeroTargetName or ((target and target.pseudo) or "")
					local box = selfPopup and selfPopup.editBox
					if (not box) and selfPopup and selfPopup.GetName then
						box = _G[selfPopup:GetName() .. "EditBox"]
					end
					if box then
						box:SetText(curName)
						box:HighlightText()
						box:SetFocus()
					end
				end,
				EditBoxOnEnterPressed = function(selfEditBox)
					if selfEditBox and selfEditBox.ClearFocus then
						selfEditBox:ClearFocus()
					end
				end,
				OnAccept = function(selfPopup)
					local box = selfPopup and selfPopup.editBox
					if (not box) and selfPopup and selfPopup.GetName then
						box = _G[selfPopup:GetName() .. "EditBox"]
					end
					local value = (box and box.GetText and box:GetText()) or ""
					local target = renameHeroTarget
					renameHeroTarget = nil
					renameHeroTargetName = nil
					RenameHeroAcrossGuildNotes(target, value)
				end,
				OnCancel = function()
					renameHeroTarget = nil
					renameHeroTargetName = nil
				end,
				EditBoxOnTextChanged = function() end,
				timeout = 0,
				whileDead = 1,
				hideOnEscape = 1,
				preferredIndex = 3,
			}
		end
		StaticPopup_Show("WOWGUILDE_RENAME_HERO", renameHeroTargetName)
	end

	local function GetAdministrativeContext(data)
		local ctx = {
			canManage = CanManageHeroSettings(),
			canEditNote = false,
			isGM = false,
			gid = nil,
			uid = nil,
			hasAddonProfile = false,
		}
		if not data then
			return ctx
		end
		ctx.canEditNote = ctx.canManage and CanEditGuildPublicNote()
		ctx.isGM = ns and ns.Roles and ns.Roles.IsGuildLeader and ns.Roles.IsGuildLeader() or false
		ctx.gid = HU.Util_GetActiveGuildUID and HU.Util_GetActiveGuildUID() or nil
		ctx.uid = ResolveGuildMemberUID(ctx.gid, data)
		ctx.hasAddonProfile = ctx.gid
			and ctx.uid
			and DB
			and DB.GetGuildMemberPrefs
			and DB:GetGuildMemberPrefs(ctx.gid, ctx.uid) ~= nil
		return ctx
	end

	local function CanToggleRaidLeaderForData(data)
		local ctx = GetAdministrativeContext(data)
		return ctx.isGM
			and ctx.gid
			and ctx.uid
			and ctx.hasAddonProfile
			and DB
			and DB.SetGuildRaidLeaderUID
			and DB.GetGuildMemberPrefs
	end

	local function IsRaidLeaderForData(data)
		local ctx = GetAdministrativeContext(data)
		if not (ctx.gid and ctx.uid and DB and DB.GetGuildRaidLeaderUID) then
			return false
		end
		local current = DB:GetGuildRaidLeaderUID(ctx.gid)
		return current == ctx.uid
	end

	local function ToggleRaidLeaderForData(data)
		local ctx = GetAdministrativeContext(data)
		if
			not (
				ctx.isGM
				and ctx.gid
				and ctx.uid
				and ctx.hasAddonProfile
				and DB
				and DB.SetGuildRaidLeaderUID
				and DB.GetGuildMemberPrefs
			)
		then
			return
		end
		local changedOk, changed = DB:SetGuildRaidLeaderUID(ctx.gid, ctx.uid)
		if not changedOk then
			return
		end
		if Comms and Comms.SendGuildMemberPrefs and type(changed) == "table" then
			for i = 1, #changed do
				local changedUID = changed[i]
				local prefs = DB:GetGuildMemberPrefs(ctx.gid, changedUID) or {}
				Comms:SendGuildMemberPrefs(ctx.gid, changedUID, {
					raidLeader = prefs.raidLeader == true,
					updatedAt = tonumber(prefs.updatedAt or 0) or (time and time() or 0),
				})
			end
		end
		if ns and ns.UI and ns.UI.Refresh then
			ns.UI.Refresh()
		end
		if ns and ns.Sections and ns.Sections.HerosFrame and ns.Sections.HerosFrame.Refresh then
			ns.Sections.HerosFrame.Refresh()
		end
	end

	ns.HerosAdmin = ns.HerosAdmin or {}
	ns.HerosAdmin.OpenRenameHeroPopup = OpenRenameHeroPopup
	ns.HerosAdmin.CanShowAdministrativeForData = function(data)
		local ctx = GetAdministrativeContext(data)
		return ctx.canManage == true
	end
	ns.HerosAdmin.CanRenameHeroForData = function(data)
		local ctx = GetAdministrativeContext(data)
		return ctx.canManage and ctx.canEditNote
	end
	ns.HerosAdmin.CanToggleRaidLeaderForData = CanToggleRaidLeaderForData
	ns.HerosAdmin.IsRaidLeaderForData = IsRaidLeaderForData
	ns.HerosAdmin.ToggleRaidLeaderForData = ToggleRaidLeaderForData

	local function OpenProfileNameMenu(anchor, data)
		if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" or not data then
			return
		end
		local target = ResolveLiveCharacter(data)
		local canManage = ns.HerosAdmin
			and ns.HerosAdmin.CanShowAdministrativeForData
			and ns.HerosAdmin.CanShowAdministrativeForData(data)
		local canRename = ns.HerosAdmin
			and ns.HerosAdmin.CanRenameHeroForData
			and ns.HerosAdmin.CanRenameHeroForData(data)
		local canToggleRL = ns.HerosAdmin
			and ns.HerosAdmin.CanToggleRaidLeaderForData
			and ns.HerosAdmin.CanToggleRaidLeaderForData(data)
		local hasAddonProfile = false
		do
			local ctx = GetAdministrativeContext(data)
			hasAddonProfile = ctx.hasAddonProfile
		end
		MenuUtil.CreateContextMenu(anchor or UIParent, function(_, root)
			root:CreateTitle(data.pseudo or "Profil")
			local hasSection = false
			if
				not data.isSelf
				and hasAddonProfile
				and target
				and target ~= ""
				and Reactions
				and Reactions.AddSubmenu
			then
				hasSection = Reactions.AddSubmenu(root, target, false) == true
			end
			if canManage then
				if hasSection and root.CreateDivider then
					root:CreateDivider()
				end
				root:CreateTitle("Administratif")
				root:CreateButton("Renommer le héros", function()
					if ns.HerosAdmin and ns.HerosAdmin.OpenRenameHeroPopup then
						ns.HerosAdmin.OpenRenameHeroPopup(data)
					end
				end, { disabled = not canRename })
				if canToggleRL then
					Menu_AddToggleEntry(root, "Chef de raid", function()
						return ns.HerosAdmin
							and ns.HerosAdmin.IsRaidLeaderForData
							and ns.HerosAdmin.IsRaidLeaderForData(data)
					end, function()
						if ns.HerosAdmin and ns.HerosAdmin.ToggleRaidLeaderForData then
							ns.HerosAdmin.ToggleRaidLeaderForData(data)
						end
					end)
				end
			end
		end)
	end

	local function ShowProfile(data)
		-- =========================================================
		-- 0) Aucun profil → on cache et on sort
		-- =========================================================
		if not data then
			ui.profile:Hide()
			return
		end

		ui.profile:Show()

		-- =========================================================
		-- 1) Gestion édition biographie
		-- =========================================================
		local function syncBioEditor()
			if not ui.profile.HideBiographyEdit then
				return
			end

			if not ui.profile._bioEditActive then
				ui.profile:HideBiographyEdit()
				return
			end

			if not data.pseudo or not HU.KeyForPseudo then
				return
			end

			local newKey = HU.KeyForPseudo(data.pseudo)
			if ui.profile._bioEditKey and newKey ~= ui.profile._bioEditKey then
				ui.profile:HideBiographyEdit()
			end
		end

		syncBioEditor()

		-- =========================================================
		-- 2) Texte par défaut de biographie
		-- =========================================================
		local function setDefaultBioText()
			if not ui.profile.bioText then
				return
			end

			local text = data.isSelf and const.BIO_EMPTY_SELF or const.BIO_EMPTY_OTHER

			if ui.profile.Bio_ApplyText then
				ui.profile:Bio_ApplyText(text)
			else
				ui.profile.bioText:SetText(text)
			end

			if ui.profile.Bio_SetTextColor then
				ui.profile:Bio_SetTextColor(0.192, 0.043, 0, 1)
			else
				ui.profile.bioText:SetTextColor(0.192, 0.043, 0, 1)
			end
		end

		setDefaultBioText()

		if ui.profile.bioSubtitle then
			ui.profile.bioSubtitle:SetText("Canli bir hikaye, guild tarafindan beslenir.")
		end

		-- =========================================================
		-- 3) Boutons (création / options)
		-- =========================================================
		local function updateButtons(hasAnyBio, hasPublishedBio)
			if ui.profile.bioCreateBtn then
				if data.isSelf and not hasAnyBio then
					ui.profile.bioCreateBtn:Show()
				else
					ui.profile.bioCreateBtn:Hide()
				end
			end

			if not ui.profile.bioOptionsBtn then
				return
			end

			if data.isSelf then
				if hasAnyBio then
					ui.profile.bioOptionsBtn:Show()
				else
					ui.profile.bioOptionsBtn:Hide()
				end
				if ui.profile.bioOtherOptionsBtn then
					ui.profile.bioOtherOptionsBtn:Hide()
				end
			else
				ui.profile.bioOptionsBtn:Hide()
				if ui.profile.bioOtherOptionsBtn then
					if hasPublishedBio then
						ui.profile.bioOtherOptionsBtn:Show()
					else
						ui.profile.bioOtherOptionsBtn:Hide()
					end
				end
			end
		end

		-- =========================================================
		-- 4) Icône de classe + overlay
		-- =========================================================
		ns.UI.SetProfileAwareIcon(
			ui.profile.classIcon,
			data.hasProfile,
			data.mainClassTag ~= "" and data.mainClassTag or data.classTag
		)

		if data.hasProfile then
			ui.profile.classOverlay:SetVertexColor(0.8941, 0.6549, 0.1255, 0.9)
		else
			ui.profile.classOverlay:SetVertexColor(0.576, 0.576, 0.576, 0.9)
		end

		-- =========================================================
		-- 5) Nom, classe, spécialisation
		-- =========================================================
		local classTag = data.mainClassTag ~= "" and data.mainClassTag or data.classTag
		local classLoc = data.mainClassLoc ~= "" and data.mainClassLoc or data.classLoc or ""
		local specLoc = data.mainSpec ~= "" and data.mainSpec or data.spec or ""

		local name = data.pseudo ~= "" and data.pseudo or "Joueur"
		ui.profile.name:SetText(("%s%s|r"):format(HU.GetClassColorHex(classTag), name))
		ui.profile._profileData = data
		if ui.profile.nameBtn then
			ui.profile.nameBtn:ClearAllPoints()
			ui.profile.nameBtn:SetPoint("TOPLEFT", ui.profile.name, "TOPLEFT", -2, 2)
			ui.profile.nameBtn:SetPoint("BOTTOMRIGHT", ui.profile.name, "BOTTOMRIGHT", 2, -2)
		end
		if not ui.profile.ProfileName_OnClick then
			function ui.profile:ProfileName_OnClick(button)
				local d = self._profileData
				if not d then
					return
				end
				if button == "RightButton" then
					OpenProfileNameMenu(self.nameBtn or self, d)
				else
					SendWhisperToProfileTarget(d)
				end
			end
		end
		if not ui.profile.ProfileName_OnEnter then
			function ui.profile:ProfileName_OnEnter(anchor)
				local d = self._profileData
				if not d then
					return
				end
				if not CanManageHeroSettings() then
					return
				end
				if not GameTooltip then
					return
				end
				local anchorObj = anchor or self.nameBtn or self
				GameTooltip:SetOwner(anchorObj, "ANCHOR_NONE")
				GameTooltip:SetPoint("BOTTOMRIGHT", anchorObj, "TOPLEFT", -8, 0)
				GameTooltip:ClearLines()
				GameTooltip:AddLine("Clic droit pour gerer les parametres de ce heros.", 0.95, 0.95, 0.95, true)
				GameTooltip:Show()
			end
		end
		if not ui.profile.ProfileName_OnLeave then
			function ui.profile:ProfileName_OnLeave()
				if GameTooltip then
					GameTooltip:Hide()
				end
			end
		end

		local specClass = (classLoc ~= "" and classLoc .. " " or "") .. (specLoc ~= "" and specLoc .. " " or "")

		if ui.profile.subline then
			local sub = specClass ~= "" and specClass or (classLoc ~= "" and classLoc or "—")
			ui.profile.subline:SetText(sub)
			ui.profile.subline:Show()
		end

		-- =========================================================
		-- 6) Sélection de la biographie
		-- =========================================================
		local function normalizeVisibility(b)
			if BioRules and BioRules.NormalizeVisibility then
				return BioRules.NormalizeVisibility(b)
			end
			return (b and b.visibility ~= "" and b.visibility) or "public"
		end

		local function isPublicPublished(b)
			if BioRules and BioRules.IsPublicPublished then
				return BioRules.IsPublicPublished(b, { allowPending = true })
			end
			return type(b) == "table" and b.status == "published" and normalizeVisibility(b) ~= "private"
		end

		local function FormatDeletionCountdown(ts)
			if BioRules and BioRules.FormatDeletionCountdown then
				return BioRules.FormatDeletionCountdown(ts)
			end
			local diff = (tonumber(ts or 0) or 0) - time()
			if diff <= 0 then
				return "moins d'une minute"
			end
			local days = math.floor(diff / 86400)
			local hours = math.floor((diff % 86400) / 3600)
			local mins = math.floor((diff % 3600) / 60)
			if days > 0 then
				return ("%d jour%s"):format(days, days > 1 and "s" or "")
			end
			if hours > 0 then
				return ("%d h"):format(hours)
			end
			if mins > 0 then
				return ("%d min"):format(mins)
			end
			return "moins d'une minute"
		end

		local function pickFeatured(map, excludeKey)
			if not map then
				return nil
			end
			local best, bestAt = nil, -1
			for k, b in pairs(map) do
				if not (excludeKey and k == excludeKey) then
					if isPublicPublished(b) and b.featured == true then
						local t = tonumber(b.updatedAt or b.createdAt or 0) or 0
						if t > bestAt then
							best, bestAt = b, t
						end
					end
				end
			end
			return best
		end

		local featuredBio, generalBio, anyBio = nil, nil, false
		local hasPublishedBio = false
		local gid = HU.Util_GetActiveGuildUID()

		if gid and DB and DB.GetGuildMemberPrefs then
			local uid = data.uid

			if (not uid or uid == "") and ns.Data and ns.Data.ResolvePlayerUID then
				uid = ns.Data.ResolvePlayerUID(gid, data.mainFull or data.rosterFull, data.playerGUID)
			end

			if uid then
				local prefs = DB:GetGuildMemberPrefs(gid, uid)
				local map = prefs and prefs.biographie

				if type(map) == "table" then
					for _, b in pairs(map) do
						if type(b) == "table" then
							anyBio = true
							if isPublicPublished(b) then
								hasPublishedBio = true
							end
						end
					end
				end

				featuredBio = pickFeatured(map, "__general__")
				local general = map and map["__general__"] or nil
				if isPublicPublished(general) then
					generalBio = general
					hasPublishedBio = true
				end
			end
		end

		-- =========================================================
		-- 7) Affichage de la biographie
		-- =========================================================
		local function applyBio(bio)
			if not bio then
				return
			end

			if ui.profile.bioSubtitle then
				local title = bio.title or "Un récit vivant, alimenté par la guilde."
				local delAt = tonumber(bio.deletedAt or 0) or 0
				if delAt > time() then
					title = title .. "  (suppression dans " .. FormatDeletionCountdown(delAt) .. ")"
				end
				ui.profile.bioSubtitle:SetText(title)
			end

			local wow = tostring(bio.wow or "")
			local md = tostring(bio.md or "")
			local html = tostring(bio.html or "")
			local text = tostring(bio.text or "")
			local content = wow ~= "" and { wow, "wow" }
				or md ~= "" and { md, "markdown" }
				or html ~= "" and { html, "html" }
				or text ~= "" and { text, false }

			if content then
				if ui.profile.Bio_ApplyText then
					ui.profile:Bio_ApplyText(content[1], content[2])
				else
					ui.profile.bioText:SetText(content[1])
				end
			end

			if ui.profile.Bio_SetTextColor then
				ui.profile:Bio_SetTextColor(0.31, 0.153, 0.055, 1)
			else
				ui.profile.bioText:SetTextColor(0.31, 0.153, 0.055, 1)
			end
		end

		local showBio = featuredBio or generalBio

		if showBio then
			applyBio(showBio)
		else
			setDefaultBioText()
		end

		ui.profile.bioHasAny = data.isSelf and anyBio or false
		updateButtons(anyBio, hasPublishedBio)
		if ui.profile.epicLine and ui.profile.subline then
			ui.profile.epicLine:ClearAllPoints()
			ui.profile.subline:ClearAllPoints()
			if hasPublishedBio then
				ui.profile.epicLine:SetPoint("TOPLEFT", ui.profile.name, "BOTTOMLEFT", 0, -2)
				ui.profile.epicLine:SetPoint("RIGHT", -8, 0)
				ui.profile.epicLine:SetText("|A:questlog-storylineicon:16:16|a Destan paylasildi")
				ui.profile.epicLine:Show()
				ui.profile.subline:SetPoint("TOPLEFT", ui.profile.epicLine, "BOTTOMLEFT", 0, -2)
				ui.profile.subline:SetPoint("RIGHT", -8, 0)
			else
				ui.profile.epicLine:Hide()
				ui.profile.subline:SetPoint("TOPLEFT", ui.profile.name, "BOTTOMLEFT", 0, -2)
				ui.profile.subline:SetPoint("RIGHT", -8, 0)
			end
		end
		if ui.profile then
			ui.profile._bioOtherTarget = (data.isSelf or not hasPublishedBio) and nil or data
			if ui.profile.Reroll_Update then
				ui.profile:Reroll_Update(data)
			end
		end
	end

	local function ClearProfile()
		ui.profile:Hide()
	end

	local function SelectEntry(entry)
		if state.selectedEntry and state.selectedEntry.selHL then
			state.selectedEntry.selHL:Hide()
		end

		state.selectedEntry = entry

		if entry then
			state.selectedKey = HU.KeyForPseudo(entry.data and entry.data.pseudo or "")
			ShowProfile(entry.data)
			if fn.News_SetTarget then
				fn.News_SetTarget(entry.data)
			end
		else
			state.selectedKey = nil
			ClearProfile()
			if fn.News_SetTarget then
				fn.News_SetTarget(nil)
			end
		end
	end

	function ns.Sections.Heros_SelectByData(data)
		if not data then
			return
		end
		for _, entry in ipairs(state.entries) do
			if entry.data == data then
				SelectEntry(entry)
				return
			end
		end
	end

	function ns.Sections.Heros_SelectByFull(full)
		if not full or full == "" then
			return
		end
		local short = Ambiguate and Ambiguate(full, "none") or full
		for _, entry in ipairs(state.entries) do
			local data = entry.data
			if data then
				local rosterFull = data.rosterFull
				local mainFull = data.mainFull
				local rosterShort = rosterFull and (Ambiguate and Ambiguate(rosterFull, "none") or rosterFull)
				local mainShort = mainFull and (Ambiguate and Ambiguate(mainFull, "none") or mainFull)
				if full == rosterFull or full == mainFull or short == rosterFull or short == mainFull then
					SelectEntry(entry)
					return
				end
				if short == rosterShort or short == mainShort then
					SelectEntry(entry)
					return
				end
			end
		end
	end

	-- =========================================================
	-- Rafraîchissement de la liste
	-- =========================================================
	local function RefreshGuildList()
		local numTotal = GetNumGuildMembers() or 0
		local y = -ENTRY_GAP

		local myGuildUID = (DB and DB.GetGuildUID and DB:GetGuildUID()) or nil
		local myGUID = (UnitGUID and UnitGUID("player")) or nil
		local myPseudoKey

		local groups, order = {}, {}

		local function HasPublishedEpic(prefs)
			local map = prefs and prefs.biographie
			if type(map) ~= "table" then
				return false
			end
			for _, b in pairs(map) do
				if BioRules and BioRules.IsPublicPublished then
					if BioRules.IsPublicPublished(b, { allowPending = true }) then
						return true
					end
				elseif type(b) == "table" and b.status == "published" then
					return true
				end
			end
			return false
		end

		for i = 1, numTotal do
			local name, rank, rankIndex, level, classDisplayName, zone, note, officernote, online, status, classFileName, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid =
				GetGuildRosterInfo(i)
			local noteTrim = (ns.Utils and ns.Utils.Trim and ns.Utils.Trim(note)) or tostring(note or "")
			local hasNote = noteTrim ~= ""

			local rosterFull = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name

			if name then
				local lastMinutes, lastText
				if online then
					lastMinutes, lastText = 0, "online"
				else
					lastMinutes, lastText = ns.GetLastOnlineInfo(i)
				end

				local pseudo, isMainTag = ns.Utils.ParsePseudo(note, name)
				local key = HU.KeyForPseudo(pseudo)

				if guid and myGUID and guid == myGUID then
					myPseudoKey = key
				end

				if not groups[key] then
					groups[key] = {
						key = key,
						pseudo = pseudo,
						isMainAny = isMainTag and true or false,
						online = online and true or false,
						lastOnlineMinutes = online and 0 or lastMinutes,
						lastOnlineText = lastText,
						hasNote = hasNote,

						mplus = 0,
						achv = 0,
						ilevel = 0,

						classLoc = classDisplayName,
						classTag = classFileName,
						spec = "",

						mainFull = nil,
						realm = "",

						updatedAtForClass = 0,
						updatedAtForMain = 0,

						hasProfile = false,
						mainClassLoc = "",
						mainClassTag = "",
						mainSpec = "",

						uid = nil,
						emotesEnabled = nil,
						emotesSound = nil,

						rosterFull = online and rosterFull or nil,
						playerGUID = guid,
					}
					order[#order + 1] = key
				else
					local g = groups[key]
					g.isMainAny = g.isMainAny or isMainTag
					g.online = g.online or online
					if hasNote then
						g.hasNote = true
					end

					if (not g.online) and (lastMinutes < g.lastOnlineMinutes) then
						g.lastOnlineMinutes = lastMinutes
						g.lastOnlineText = lastText
					end

					if online then
						g.rosterFull = rosterFull
						if guid and guid ~= "" then
							g.playerGUID = guid
						end
					end
				end

				local g = groups[key]

				if myGuildUID and DB then
					local rec =
						ns.Data.GetDBAggregateForRosterEntry(myGuildUID, name, classDisplayName, classFileName, guid)
					if rec then
						g.hasProfile = true

						-- Main
						if rec.isMain and rec.mainFull and rec.mainFull ~= "" then
							g.mainFull = rec.mainFull
							g.updatedAtForMain = math.huge
						elseif rec.mainFull and rec.mainFull ~= "" and rec.updatedAt > g.updatedAtForMain then
							g.mainFull = rec.mainFull
							g.updatedAtForMain = rec.updatedAt or g.updatedAtForMain
						end

						-- Classe/spec du main (ou fallback rec)
						if g.mainFull and (g.mainClassTag == "" and g.mainClassLoc == "" and g.mainSpec == "") then
							local mLoc, mTag, mSpec = ns.Data.GetMainClassSpecFromDB(myGuildUID, g.mainFull)
							if mLoc == "" and mTag == "" and mSpec == "" then
								mLoc, mTag, mSpec = rec.classLoc or "", rec.classTag or "", rec.spec or ""
							end
							g.mainClassLoc, g.mainClassTag, g.mainSpec = mLoc, mTag, mSpec
						end

						-- Realm
						if g.realm == "" then
							if rec.mainFull and rec.mainFull:find("-", 1, true) then
								local _, mr = rec.mainFull:match("^(.-)%-(.+)$")
								g.realm = mr or rec.realm or g.realm
							else
								g.realm = rec.realm or g.realm
							end
						end

						-- Agrégats (max)
						if (tonumber(rec.mplus or 0) or 0) > g.mplus then
							g.mplus = tonumber(rec.mplus or 0) or g.mplus
						end
						if (tonumber(rec.achv or 0) or 0) > g.achv then
							g.achv = tonumber(rec.achv or 0) or g.achv
						end
						if (tonumber(rec.ilevel or 0) or 0) > g.ilevel then
							g.ilevel = tonumber(rec.ilevel or 0) or g.ilevel
						end

						-- Classe/spec (priorité online, sinon updatedAt)
						if online then
							g.classLoc = classDisplayName or rec.classLoc or g.classLoc
							g.classTag = classFileName or rec.classTag or g.classTag
							g.spec = rec.spec or g.spec
							g.updatedAtForClass = math.huge
						elseif (tonumber(rec.updatedAt or 0) or 0) > g.updatedAtForClass then
							g.classLoc = rec.classLoc or g.classLoc
							g.classTag = rec.classTag or g.classTag
							g.spec = rec.spec or g.spec
							g.updatedAtForClass = tonumber(rec.updatedAt or 0) or g.updatedAtForClass
						end
					end
				end

				if myGuildUID and ns.Data and ns.Data.ResolvePlayerUID then
					local full = g.mainFull or g.rosterFull
					local uid = ns.Data.ResolvePlayerUID(myGuildUID, full, g.playerGUID)
					if uid and uid ~= "" then
						g.uid = g.uid or uid
					end
				end

				if myGuildUID and g.uid and DB and DB.GetGuildMemberPrefs then
					local prefs = DB:GetGuildMemberPrefs(myGuildUID, g.uid)
					if prefs then
						g.emotesEnabled = prefs.emotesEnabled
						g.emotesSound = prefs.emotesSound
						g.hasEpic = HasPublishedEpic(prefs)
					end
				end
			end
		end

		local list = {}
		for _, key in ipairs(order) do
			local g = groups[key]
			local recentEnough = g.online or g.hasProfile or (g.lastOnlineMinutes <= MAX_OFFLINE_MIN)
			if recentEnough then
				if myPseudoKey and key == myPseudoKey then
					local mine = ns.Data.GetMyMPlusScore and ns.Data.GetMyMPlusScore()
					if mine and mine > g.mplus then
						g.mplus = mine
					end
				end
				list[#list + 1] = g
			end
		end


		local onlineCount = 0
		local recentCount = 0
		for _, data in ipairs(list) do
			if data.online then
				onlineCount = onlineCount + 1
				recentCount = recentCount + 1
			elseif data.lastOnlineMinutes and data.lastOnlineMinutes <= RECENT_ACTIVE_MIN then
				recentCount = recentCount + 1
			end
		end

		table.sort(list, function(a, b)
			-- 1) Online > Offline (comportement inchangé)
			if a.online ~= b.online then
				return a.online
			end

			-- 2) Profils addon d’abord
			if a.hasProfile ~= b.hasProfile then
				return a.hasProfile
			end

			-- 3) Critère de tri choisi
			if state.sortState.method == "class" then
				return (a.classLoc or "") < (b.classLoc or "")
			elseif state.sortState.method == "name" then
				return (a.pseudo or "") < (b.pseudo or "")
			elseif state.sortState.method == "mplus" then
				return (a.mplus or 0) > (b.mplus or 0)
			elseif state.sortState.method == "achv" then
				return (a.achv or 0) > (b.achv or 0)
			else
				return (a.lastOnlineMinutes or 999999) < (b.lastOnlineMinutes or 999999)
			end
		end)

		local restored = false
		local function EmoteIconMarkup(atlas)
			local size = 10
			return ("|A:%s:%d:%d:0:0|a"):format(atlas, size, size)
		end
		local function NameWithEmoteStatus(name, data)
			if not data then
				return name
			end
			if data.hasEpic then
				name = name .. " |A:questlog-storylineicon:12:12|a"
			end
			local enabled = data.emotesEnabled
			local sound = data.emotesSound
			if data.isSelf and ns and ns.Emotes and ns.Emotes.GetPrefs then
				local D = ns.Emotes.GetPrefs()
				if D then
					enabled = D.enabled
					sound = D.sound
				end
			end
			if enabled == false then
				return name .. " " .. EmoteIconMarkup("voicechat-icon-speaker-mutesilenced")
			end
			if sound == false then
				return name .. " " .. EmoteIconMarkup("voicechat-icon-speaker-mute")
			end
			return name
		end

		for i, data in ipairs(list) do
			local entry = state.entries[i]
			if not entry then
				entry = ns.UI.CreateHeroEntry(ui.rosterListContent)
				state.entries[i] = entry
			end

			entry:ClearAllPoints()
			entry:SetPoint("TOPLEFT", ui.rosterListContent, "TOPLEFT", 0, y)
			entry:Show()

			local dispClass = (data.mainClassLoc and data.mainClassLoc ~= "") and data.mainClassLoc or data.classLoc
			local dispSpec = (data.mainSpec and data.mainSpec ~= "") and data.mainSpec or data.spec
			local dispTag = (data.mainClassTag and data.mainClassTag ~= "") and data.mainClassTag or data.classTag

			local subtext
			if state.sortState.method == "name" or state.sortState.method == "last" then
				if data.online then
					subtext = "|cffffffffonline|r"
				else
					subtext = ("|cff9d9d9d%s|r"):format(data.lastOnlineText or "")
				end
			elseif state.sortState.method == "class" then
				if not data.hasProfile then
					subtext = "|cff9d9d9d-|r"
				else
					subtext = ("|cff9d9d9d%s|r"):format(
						(dispClass or "") .. (dispSpec and dispSpec ~= "" and (" " .. dispSpec) or "")
					)
				end
			elseif state.sortState.method == "mplus" then
				if not data.hasProfile then
					subtext = "|cff9d9d9d-|r"
				else
					subtext = HU.GetMPlusRank(data.mplus)
				end
			elseif state.sortState.method == "achv" then
				if not data.hasProfile then
					subtext = "|cff9d9d9d-|r"
				else
					subtext = (ns.Utils and ns.Utils.FormatAchvText and ns.Utils.FormatAchvText(data.achv))
						or ("HF " .. (data.achv or 0))
				end
			else
				if data.online then
					subtext = "|cffffffffonline|r"
				else
					subtext = ("|cff9d9d9d%s|r"):format(data.lastOnlineText or "")
				end
			end

			local isSelf = (ns.Utils and ns.Utils.PseudoKey and ns.Utils.PseudoKey(data.pseudo) == myPseudoKey) and true
				or false
			data.isSelf = isSelf
			local topName = NameWithEmoteStatus(data.pseudo, data)
			entry:SetOnlineStyle(data.online, topName, subtext, "", data.hasNote == false)
			ns.UI.SetProfileAwareIcon(entry.classIcon, data.hasProfile, dispTag)

			if not data.hasProfile then
				entry.classOverlay:SetVertexColor(0.576, 0.576, 0.576, 1)
			else
				entry.classOverlay:SetVertexColor(0.8941, 0.6549, 0.1255, 0.8)
			end

			entry.data = {
				pseudo = data.pseudo,
				mainFull = data.mainFull,
				realm = data.realm,
				hasProfile = data.hasProfile,
				hasNote = data.hasNote,
				hasEpic = data.hasEpic,
				playerGUID = data.playerGUID,
				uid = data.uid,

				classLoc = data.classLoc,
				classTag = data.classTag,
				spec = data.spec,

				mainClassLoc = data.mainClassLoc,
				mainClassTag = data.mainClassTag,
				mainSpec = data.mainSpec,

				ilevel = data.ilevel,
				achv = data.achv,
				mplus = data.mplus,

				online = data.online,
				lastOnlineText = data.lastOnlineText,

				isSelf = isSelf,
				rosterFull = data.rosterFull,
				emotesEnabled = data.emotesEnabled,
				emotesSound = data.emotesSound,
			}

			entry:SetScript("OnClick", function(self, btn)
				if btn == "RightButton" then
					if ns.Sections.Heros_OpenContextMenu then
						ns.Sections.Heros_OpenContextMenu(self, self.data)
					end
				else
					SelectEntry(self)
				end
			end)

			if not restored and state.selectedKey and HU.KeyForPseudo(data.pseudo) == state.selectedKey then
				SelectEntry(entry)
				restored = true
			end

			y = y - (LINE_HEIGHT + ENTRY_GAP)
		end

		for j = #list + 1, #state.entries do
			if state.entries[j] then
				state.entries[j]:Hide()
				if state.entries[j].selHL then
					state.entries[j].selHL:Hide()
				end
			end
		end

		ui.rosterListContent:SetHeight(#list * (LINE_HEIGHT + ENTRY_GAP) + ENTRY_GAP)

		if ui.rosterFooter and ui.rosterFooter.text then
			local icon = "|A:plunderstorm-map-zoneGreen-hover:14:14|a "
			local connectedText = (onlineCount == 1) and (icon .. "1 kahraman cevrimici.")
				or string.format("%s%d kahraman cevrimici.", icon, onlineCount)
			ui.rosterFooter.text:SetText(connectedText)
			ui.rosterFooter.countOnline = onlineCount
			ui.rosterFooter.countRecent = recentCount
			ui.rosterFooter.countCharacters = numTotal
		end

		if #list == 0 then
			SelectEntry(nil)
		elseif not restored and state.entries[1] then
			SelectEntry(state.entries[1])
		end
	end

	ui.frame.Refresh = RefreshGuildList
	fn.RefreshGuildList = RefreshGuildList
end

return M
