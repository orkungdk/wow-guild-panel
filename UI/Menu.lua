local ADDON, ns = ...
ns.HerosMenu = ns.HerosMenu or {}
local Ctx = ns.HerosMenu
Ctx.providers = Ctx.providers or {}
ns.Sections = ns.Sections or {}
local Sections = ns.Sections

--==================================================
-- Cibles: résout le perso actif pour les actions
--==================================================
local HU = ns.Heros and ns.Heros.Utils or nil
local Targets = ns.Targets
local Reactions = ns.Reactions

local function ResolveLiveCharacter(d)
	if Targets and Targets.ResolveForData then
		local full, online, rec = Targets.ResolveForData(d)
		if full and full ~= "" then
			return full, online, rec
		end
	end
	if HU and HU.ResolveLiveCharacterForData then
		local full, online, rec = HU.ResolveLiveCharacterForData(d)
		if full and full ~= "" then
			return full, online, rec
		end
	end
	return nil, false, nil
end

-- Présence fiabilisée
local function PresenceState(d)
	local _, online, r = ResolveLiveCharacter(d)
	if r then
		return online
	end
	return false
end

-- Cible pour /w et /invite = perso actif si présent
local function BestTarget(d)
	local full, _, _ = ResolveLiveCharacter(d)
	if full and full ~= "" then
		return full
	end
	return nil
end

local function IsDevMode()
	if ns.Utils and ns.Utils.IsDevMode then
		return ns.Utils.IsDevMode()
	end
	if ns and ns.Comms and ns.Comms.DEV_MODE ~= nil then
		return ns.Comms.DEV_MODE == true
	end
	return false
end

local function Menu_AddToggleEntry(menu, label, getter, toggler)
	if menu.CreateCheckbox then
		menu:CreateCheckbox(label, getter, toggler)
	else
		menu:CreateButton(label, toggler, { isNotRadio = true, checked = getter })
	end
end

local function RefreshHerosList()
	if ns and ns.Sections and ns.Sections.HerosFrame and ns.Sections.HerosFrame.Refresh then
		ns.Sections.HerosFrame.Refresh()
	end
end

local function ResolveGuildMemberUID(guildUID, data)
	if not guildUID or type(data) ~= "table" then
		return nil
	end
	local uid = data.uid
	if uid and uid ~= "" then
		return uid
	end
	if ns and ns.Data and ns.Data.ResolvePlayerUID then
		local full = data.mainFull or data.rosterFull
		local resolved = ns.Data.ResolvePlayerUID(guildUID, full, data.playerGUID)
		if resolved and resolved ~= "" then
			return resolved
		end
	end
	return nil
end

--==================================================
-- Providers
--==================================================
function Ctx.Register(id, fn, order)
	Ctx.providers[id] = { fn = fn, order = order or 50 }
end

local function _SortedProviders()
	local arr = {}
	for id, pr in pairs(ns.HerosMenu.providers or {}) do
		arr[#arr + 1] = { id = id, fn = pr.fn, order = pr.order or 50 }
	end
	table.sort(arr, function(a, b)
		return a.order < b.order
	end)
	return arr
end

function Sections.Heros_OpenContextMenu(anchor, data)
	if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
		return
	end

	local function Generator(owner, root)
		root:CreateTitle((data and data.pseudo) or "?")
		for _, p in ipairs(_SortedProviders()) do
			p.fn(root, data)
		end
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			MenuUtil.CreateContextMenu(anchor or UIParent, Generator)
		end)
	else
		MenuUtil.CreateContextMenu(anchor or UIParent, Generator)
	end
end

--==================================================
-- Core actions
--==================================================
Ctx.Register("core-actions", function(root, data)
	local target = BestTarget(data)
	local isSelf = data and data.isSelf
	local DB = ns and ns.DB or nil
	local HeroAdmin = ns and ns.HerosAdmin or nil

	local pres = PresenceState(data)
	local isOnline = pres == true
	local isOffline = pres == false
	local hadInteractive = false
	local hadPrefs = false

	if isOffline then
		target = nil
	end

	if not isSelf and target and isOnline then
		root:CreateButton("Fisilti gonder", function()
			if ChatFrame_OpenChat then
				ChatFrame_OpenChat("/w " .. target .. " ")
			elseif ChatFrame_SendTell then
				ChatFrame_SendTell(target)
			else
			end
		end)

		root:CreateButton("Grupa davet et", function()
			if not target or target == "" then
				if UIErrorsFrame then
					UIErrorsFrame:AddMessage("Davet hedefi bulunamadi", 1, 0.2, 0.2)
				end
				return
			end
			local meN, meR = UnitFullName and UnitFullName("player")
			local meFull = meN and ((meR and meR ~= "") and (meN .. "-" .. meR) or meN)
				or (UnitName and UnitName("player") or "")
			if meFull ~= "" and target == meFull then
				if UIErrorsFrame then
					UIErrorsFrame:AddMessage("Kendini davet edemezsin", 1, 0.2, 0.2)
				end
				return
			end
			if C_PartyInfo and C_PartyInfo.InviteUnit then
				C_PartyInfo.InviteUnit(target)
			elseif InviteUnit then
				InviteUnit(target)
			else
				if UIErrorsFrame then
					UIErrorsFrame:AddMessage("Davet API kullanilamiyor", 1, 0.2, 0.2)
				end
			end
		end)

		hadInteractive = true
	end

	local reactionsAdded = false
	local canReactByProfile = false
	if not isSelf and isOnline and target and DB and DB.GetGuildMemberPrefs then
		local gid = (ns and ns.Utils and ns.Utils.GetActiveGuildUID and ns.Utils.GetActiveGuildUID()) or nil
		if (not gid or gid == "") and DB.GetGuildUID then
			gid = DB:GetGuildUID()
		end
		local uid = ResolveGuildMemberUID(gid, data)
		if gid and uid then
			canReactByProfile = DB:GetGuildMemberPrefs(gid, uid) ~= nil
		end
	end
	if canReactByProfile and not isSelf and isOnline and target and Reactions and Reactions.AddSubmenu then
		reactionsAdded = Reactions.AddSubmenu(root, target, { allowNoPrefs = false }) == true
		hadInteractive = hadInteractive or reactionsAdded
	end

	if isSelf then
		if Reactions and Reactions.AddSubmenu and IsDevMode() then
			local selfTarget = target
			if not selfTarget or selfTarget == "" then
				local n, r = UnitFullName and UnitFullName("player")
				if n and n ~= "" then
					selfTarget = (r and r ~= "") and (n .. "-" .. r) or n
				else
					selfTarget = UnitName and UnitName("player") or nil
				end
			end
			if selfTarget and selfTarget ~= "" then
				Reactions.AddSubmenu(root, selfTarget, { test = true, allowNoPrefs = true })
				if root.CreateDivider then
					root:CreateDivider()
				end
			end
		end

		local hasReactionOpts = ns and ns.Emotes and ns.Emotes.GetPrefs
		local hasNotifOpts = ns and ns.UI and ns.UI.NewsDrop and ns.UI.NewsDrop.GetPrefs
		if hasReactionOpts or hasNotifOpts then
			local rxnNotif = root:CreateButton("Tepkiler ve bildirimler")
			if rxnNotif then
				if hasReactionOpts then
					local reactionOpts = rxnNotif:CreateButton("Tepki ayarlari")
					if reactionOpts then
						Menu_AddToggleEntry(reactionOpts, "Tepki seslerini kapat", function()
							local D = ns.Emotes.GetPrefs()
							return D and D.sound == false
						end, function()
							local D = ns.Emotes.GetPrefs()
							if D then
								ns.Emotes.SetSound(not D.sound)
								RefreshHerosList()
							end
						end)
						Menu_AddToggleEntry(reactionOpts, "Tepkileri kapat", function()
							local D = ns.Emotes.GetPrefs()
							return D and D.enabled == false
						end, function()
							local D = ns.Emotes.GetPrefs()
							if D then
								ns.Emotes.SetEnabled(not D.enabled)
								RefreshHerosList()
							end
						end)
						if reactionOpts.CreateDivider then
							reactionOpts:CreateDivider()
						end
						Menu_AddToggleEntry(reactionOpts, "Instance icinde rahatsiz etme", function()
							local D = ns.Emotes.GetPrefs()
							return D and D.dndCompetitive == true
						end, function()
							local D = ns.Emotes.GetPrefs()
							if D then
								D.dndCompetitive = not D.dndCompetitive
							end
						end)
					end
				end

				if hasNotifOpts then
					local newsDrop = ns.UI.NewsDrop
					local notifOpts = rxnNotif:CreateButton("Bildirim ayarlari")
					if notifOpts then
						Menu_AddToggleEntry(notifOpts, "Bildirimleri ac", function()
							local D = newsDrop.GetPrefs and newsDrop.GetPrefs() or nil
							return D and D.enabled ~= false
						end, function()
							local D = newsDrop.GetPrefs and newsDrop.GetPrefs() or nil
							if D and newsDrop.SetEnabled then
								newsDrop.SetEnabled(D.enabled == false)
							end
						end)
						local ND = newsDrop.GetPrefs and newsDrop.GetPrefs() or nil
						if ND and ND.enabled ~= false then
							Menu_AddToggleEntry(notifOpts, "Bildirim sesi", function()
								local D = newsDrop.GetPrefs and newsDrop.GetPrefs() or nil
								return D and D.sound ~= false
							end, function()
								local D = newsDrop.GetPrefs and newsDrop.GetPrefs() or nil
								if D and newsDrop.SetSoundEnabled then
									newsDrop.SetSoundEnabled(D.sound == false)
								end
							end)

							if IsDevMode() then
								if notifOpts.CreateDivider then
									notifOpts:CreateDivider()
								end
								Menu_AddToggleEntry(notifOpts, "Yerel haberler", function()
									local D = newsDrop.GetPrefs and newsDrop.GetPrefs() or nil
									return D and D.localNews ~= false
								end, function()
									local D = newsDrop.GetPrefs and newsDrop.GetPrefs() or nil
									if D and newsDrop.SetLocalEnabled then
										newsDrop.SetLocalEnabled(D.localNews == false)
									end
								end)
								Menu_AddToggleEntry(notifOpts, "Alinan haberler", function()
									local D = newsDrop.GetPrefs and newsDrop.GetPrefs() or nil
									return D and D.remoteNews ~= false
								end, function()
									local D = newsDrop.GetPrefs and newsDrop.GetPrefs() or nil
									if D and newsDrop.SetRemoteEnabled then
										newsDrop.SetRemoteEnabled(D.remoteNews == false)
									end
								end)
							end

							if notifOpts.CreateDivider then
								notifOpts:CreateDivider()
							end
							local typeMenu = notifOpts:CreateButton("Bildirim turleri")
							if typeMenu then
								if newsDrop.SetAllTypesEnabled then
									typeMenu:CreateButton("Hepsini goster", function()
										newsDrop.SetAllTypesEnabled(true)
									end)
									typeMenu:CreateButton("Hepsini gizle", function()
										newsDrop.SetAllTypesEnabled(false)
									end)
								end
								if typeMenu.CreateDivider then
									typeMenu:CreateDivider()
								end
								local groups, ungrouped = nil, nil
								if newsDrop.ListNotificationTypeGroups then
									groups, ungrouped = newsDrop.ListNotificationTypeGroups()
								end
								if type(groups) == "table" then
									for i = 1, #groups do
										local group = groups[i]
										local sub = typeMenu:CreateButton(group.label or ("Grup " .. tostring(i)))
										if sub and type(group.entries) == "table" then
											for j = 1, #group.entries do
												local row = group.entries[j]
												local key = row and row.key or nil
												local label = row and row.label or key
												if key and label and newsDrop.IsTypeEnabled and newsDrop.SetTypeEnabled then
													local keyLocal = key
													local labelLocal = label
													Menu_AddToggleEntry(sub, tostring(labelLocal), function()
														return newsDrop.IsTypeEnabled(keyLocal)
													end, function()
														local enabled = newsDrop.IsTypeEnabled(keyLocal)
														newsDrop.SetTypeEnabled(keyLocal, not enabled)
													end)
												end
											end
										end
									end
								end
								if type(ungrouped) == "table" and #ungrouped > 0 then
									local sub = typeMenu:CreateButton("Diger")
									if sub then
										for i = 1, #ungrouped do
											local row = ungrouped[i]
											local key = row and row.key or nil
											local label = row and row.label or key
											if key and label and newsDrop.IsTypeEnabled and newsDrop.SetTypeEnabled then
												local keyLocal = key
												local labelLocal = label
												Menu_AddToggleEntry(sub, tostring(labelLocal), function()
													return newsDrop.IsTypeEnabled(keyLocal)
												end, function()
													local enabled = newsDrop.IsTypeEnabled(keyLocal)
													newsDrop.SetTypeEnabled(keyLocal, not enabled)
												end)
											end
										end
									end
								end
							end
						end
					end
				end

				hadPrefs = true
			end
		end
	end

	local addedAdministrative = false
	if HeroAdmin and HeroAdmin.CanShowAdministrativeForData and HeroAdmin.CanShowAdministrativeForData(data) then
		if (hadInteractive or hadPrefs) and root.CreateDivider then
			root:CreateDivider()
		end
		root:CreateTitle("Yonetim")
		local canRename = HeroAdmin.CanRenameHeroForData and HeroAdmin.CanRenameHeroForData(data)
		root:CreateButton("Kahramani yeniden adlandir", function()
			if HeroAdmin.OpenRenameHeroPopup then
				HeroAdmin.OpenRenameHeroPopup(data)
			end
		end, { disabled = not canRename })
		if HeroAdmin.CanToggleRaidLeaderForData and HeroAdmin.CanToggleRaidLeaderForData(data) then
			Menu_AddToggleEntry(root, "Raid lideri", function()
				return HeroAdmin.IsRaidLeaderForData and HeroAdmin.IsRaidLeaderForData(data)
			end, function()
				if HeroAdmin.ToggleRaidLeaderForData then
					HeroAdmin.ToggleRaidLeaderForData(data)
				end
			end)
		end
		addedAdministrative = true
	end

	if (hadInteractive or hadPrefs or addedAdministrative) and root.CreateDivider then
		root:CreateDivider()
	end

	root:CreateButton("Profili gor", function()
		if ns and ns.Sections and ns.Sections.Heros_SelectByData then
			ns.Sections.Heros_SelectByData(data)
		end
	end)

 
end, 10)
