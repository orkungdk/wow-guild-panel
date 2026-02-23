local ADDON, ns = ...

ns.RosteurSectionConfig = ns.RosteurSectionConfig or {}
local Config = ns.RosteurSectionConfig

function Config.Build(ctx)
	local Rosteur = ctx and ctx.Rosteur or nil
	local Utils = ctx and ctx.Utils or nil
	local DB = ctx and ctx.DB or nil
	local ROLE_ORDER = (ctx and ctx.ROLE_ORDER) or { "TANK", "HEAL", "DPS" }
	local ROLE_ATLAS = (ctx and ctx.ROLE_ATLAS) or {
		TANK = "UI-LFG-RoleIcon-Tank",
		HEAL = "UI-LFG-RoleIcon-Healer",
		DPS = "UI-LFG-RoleIcon-DPS",
	}
	local GetGuildUID = ctx and ctx.GetGuildUID or function()
		return nil
	end
	local CountAssignedEntries = ctx and ctx.CountAssignedEntries or function()
		return 0
	end
	local TrimSpaces = ctx and ctx.TrimSpaces or function(v)
		return tostring(v or "")
	end
	local NormalizeRoleTag = ctx and ctx.NormalizeRoleTag or function(role)
		role = tostring(role or ""):upper()
		if role == "TANK" or role == "HEAL" or role == "DPS" then
			return role
		end
		return nil
	end
	local emptyDropdown = ctx and ctx.emptyDropdown or nil
	local configSelect = ctx and ctx.configSelect or nil
	local emptyTitle = ctx and ctx.emptyTitle or nil
	local configEmpty = ctx and ctx.configEmpty or nil
	local sideArea = ctx and ctx.sideArea or nil
	local requestRefresh = ctx and ctx.requestRefresh or nil

	local pendingConfigRosterId = nil
	local pendingCreateTemplateKey = nil

	local function RequestRefresh()
		if requestRefresh then
			requestRefresh()
		end
	end

	local function SetCreatePopupExtrasShown(selfPopup, shown)
		if not selfPopup then
			return
		end
		if selfPopup._wowguildeCreateSep then
			selfPopup._wowguildeCreateSep:SetShown(shown == true)
		end
		for _, role in ipairs({ "TANK", "HEAL", "DPS" }) do
			local col = selfPopup["_wowguildeCreateCol_" .. role]
			if col then
				col:SetShown(shown == true)
			end
		end
	end

	local function GetPopupNameBox(popup)
		local box = popup and popup.editBox or nil
		if not box and popup and popup.GetName then
			box = _G[popup:GetName() .. "EditBox"]
		end
		return box
	end

	local function Dropdown_AddRadioEntry(menu, label, getter, toggler)
		if menu and menu.CreateRadio then
			menu:CreateRadio(label, getter, toggler)
		else
			menu:CreateButton(label, toggler, { isRadio = true, checked = getter })
		end
	end

	local function SetConfigEmptyTitleLayout(hasRoster)
		if not (emptyTitle and configEmpty and configSelect) then
			return
		end
		emptyTitle:ClearAllPoints()
		configSelect:ClearAllPoints()
		if hasRoster then
			emptyTitle:SetFont("Fonts\\2002.ttf", 17, "OUTLINE")
			emptyTitle:SetPoint("RIGHT", configSelect, "LEFT", -10, 0)
			emptyTitle:SetJustifyH("RIGHT")
			configSelect:SetPoint("BOTTOMRIGHT", sideArea, "TOPRIGHT", 30, 35)
		else
			emptyTitle:SetFont("Fonts\\2002.ttf", 25, "OUTLINE")
			emptyTitle:SetPoint("CENTER", configEmpty, "CENTER", 0, 80)
			emptyTitle:SetJustifyH("CENTER")
			configSelect:SetPoint("TOPLEFT", configEmpty, "TOPLEFT", 20, -20)
		end
	end

	local function ResolveActiveRoster(gid)
		local rosteur = Rosteur and Rosteur.GetState and Rosteur.GetState(gid) or nil
		if not (rosteur and type(rosteur.rosters) == "table") then
			return nil, rosteur
		end
		local activeId = rosteur.activeRosterId
		if not activeId then
			return nil, rosteur
		end
		for i = 1, #rosteur.rosters do
			local r = rosteur.rosters[i]
			if r and r.id == activeId then
				return r, rosteur
			end
		end
		return nil, rosteur
	end

	local function ComputeRosterMissing(active)
		local missing = { TANK = 0, HEAL = 0, DPS = 0 }
		if type(active) ~= "table" then
			return missing, 0
		end
		local groups = active.groups or {}
		local targets = active.targets or {}
		local total = 0
		for _, role in ipairs(ROLE_ORDER) do
			local target = tonumber(targets[role] or 0) or 0
			if role == "TANK" and target <= 0 then
				target = 2
			end
			local current = CountAssignedEntries(groups[role])
			local miss = math.max(0, target - current)
			missing[role] = miss
			total = total + miss
		end
		return missing, total
	end

	local function BuildMissingText(missing)
		local lines = {}
		if (missing.TANK or 0) > 0 then
			lines[#lines + 1] = tostring(missing.TANK) .. " Protection"
		end
		if (missing.HEAL or 0) > 0 then
			lines[#lines + 1] = tostring(missing.HEAL) .. " Soins"
		end
		if (missing.DPS or 0) > 0 then
			lines[#lines + 1] = tostring(missing.DPS) .. " Dégâts"
		end
		return table.concat(lines, ", ")
	end

	local function FillRosterMissingWithPU(gid, active, missing)
		if not (gid and active and active.id and Rosteur and Rosteur.AddPU) then
			return
		end
		local used = {}
		local groups = active.groups or {}
		for _, role in ipairs(ROLE_ORDER) do
			local list = groups[role]
			if type(list) == "table" then
				for _, e in pairs(list) do
					if type(e) == "table" and e.isPU and e.name and e.name ~= "" then
						used[e.name] = true
					end
				end
			end
		end
		local idx = 1
		local function NextPUName()
			while used["Externe " .. tostring(idx)] do
				idx = idx + 1
			end
			local n = "Externe " .. tostring(idx)
			used[n] = true
			idx = idx + 1
			return n
		end
		for _, role in ipairs(ROLE_ORDER) do
			local count = tonumber(missing[role] or 0) or 0
			for _ = 1, count do
				Rosteur.AddPU(gid, active.id, role, NextPUName())
			end
		end
	end

	local function OpenCreateConfigPopup(templateKey)
		local gid = GetGuildUID()
		if not (Rosteur and gid) then
			return
		end
		local function ResolveCreateTargets()
			local key = pendingCreateTemplateKey or templateKey or (emptyDropdown and emptyDropdown._value) or "raid20"
			local templates = Rosteur and Rosteur.GetTemplates and Rosteur.GetTemplates() or {}
			local def = templates[key] or templates.raid20 or {}
			local t = def.targets or {}
			return key, {
				TANK = 2,
				HEAL = tonumber(t.HEAL or 0) or 0,
				DPS = tonumber(t.DPS or 0) or 0,
			}
		end
		local function ResolveEditingRoster(rosterId)
			if not rosterId then
				return nil
			end
			local rosteur = Rosteur and Rosteur.GetState and Rosteur.GetState(gid) or nil
			if not (rosteur and type(rosteur.rosters) == "table") then
				return nil
			end
			for i = 1, #rosteur.rosters do
				local r = rosteur.rosters[i]
				if r and r.id == rosterId then
					return r
				end
			end
			return nil
		end
		pendingCreateTemplateKey = templateKey or (emptyDropdown and emptyDropdown._value) or "raid20"
		if StaticPopup_Show and StaticPopupDialogs then
			if not StaticPopupDialogs.WOWGUILDE_ROSTEUR_CREATE_CONFIG then
				StaticPopupDialogs.WOWGUILDE_ROSTEUR_CREATE_CONFIG = {
					text = "Nom de la configuration :",
					button1 = "Créer",
					button2 = "Annuler",
					hasEditBox = true,
					editBoxWidth = 225,
					OnShow = function(selfPopup)
						SetCreatePopupExtrasShown(selfPopup, false)
						local isEdit = pendingConfigRosterId ~= nil
						local POPUP_EDITBOX_Y = -35
						local POPUP_BUTTON2_Y = -95
						local POPUP_COL_Y = -105

						local selectedKey, defaults = ResolveCreateTargets()
						selfPopup._wowguildeTemplateKey = selectedKey
						selfPopup:SetHeight(250)
						selfPopup:SetWidth(360)
						selfPopup:ClearAllPoints()
						selfPopup:SetPoint("TOP", UIParent, "TOP", 0, -135)

						local textFs = (selfPopup and selfPopup.text)
							or (selfPopup and selfPopup.GetName and _G[selfPopup:GetName() .. "Text"])
						if textFs and textFs.SetText then
							textFs:SetText(isEdit and "Nom de la composition :" or "Nom de la configuration :")
						end
						if selfPopup and selfPopup.button1 and selfPopup.button1.SetText then
							selfPopup.button1:SetText(isEdit and "Enregistrer" or "Créer")
						end
						if selfPopup._wowguildeCreateSep then
							selfPopup._wowguildeCreateSep:Hide()
						end

						SetCreatePopupExtrasShown(selfPopup, true)

						local function EnsureColumn(key, label, editable)
							local col = selfPopup["_wowguildeCreateCol_" .. key]
							if not col then
								col = CreateFrame("Frame", nil, selfPopup)
								col:SetSize(82, 82)
								selfPopup["_wowguildeCreateCol_" .. key] = col
							end
							local labelFs = selfPopup["_wowguildeCreateLabel_" .. key]
							if not labelFs then
								labelFs = col:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
								selfPopup["_wowguildeCreateLabel_" .. key] = labelFs
							end
							local atlas = ROLE_ATLAS and ROLE_ATLAS[key] or nil
							if atlas and atlas ~= "" then
								labelFs:SetText("|A:" .. atlas .. ":54:54|a")
							else
								labelFs:SetText(label)
							end
							labelFs:ClearAllPoints()
							labelFs:SetPoint("TOP", col, "TOP", 0, 0)
							labelFs:SetPoint("LEFT", col, "LEFT", 0, 0)
							labelFs:SetPoint("RIGHT", col, "RIGHT", 0, 0)
							labelFs:SetJustifyH("CENTER")
							local box = selfPopup["_wowguildeCreateBox_" .. key]
							if not box then
								box = CreateFrame("EditBox", nil, col, "InputBoxTemplate")
								box:SetAutoFocus(false)
								box:SetSize(66, 24)
								box:SetMaxLetters(2)
								box:SetNumeric(false)
								box:SetJustifyH("CENTER")
								box:SetTextInsets(0, 0, 0, 0)
								box:SetScript("OnEscapePressed", function(selfBox)
									if selfBox and selfBox.ClearFocus then
										selfBox:ClearFocus()
									end
								end)
								box:SetScript("OnTextChanged", function(selfBox)
									local text = tostring((selfBox and selfBox.GetText and selfBox:GetText()) or "")
									local clean = text:gsub("%D", "")
									if clean ~= text and selfBox and selfBox.SetText then
										selfBox:SetText(clean)
										selfBox:SetCursorPosition(#clean)
									end
								end)
								selfPopup["_wowguildeCreateBox_" .. key] = box
							end
							box:ClearAllPoints()
							box:SetPoint("TOP", labelFs, "BOTTOM", 0, -8)
							box:SetEnabled(editable ~= false)
							box:SetTextColor(1, 1, 1, 1)
							return box
						end

						local tankBox = EnsureColumn("TANK", "Protection", false)
						local healBox = EnsureColumn("HEAL", "Soigneur", true)
						local dpsBox = EnsureColumn("DPS", "Dégâts", true)

						local function ApplyPopupLayout()
							local nameBox = GetPopupNameBox(selfPopup)
							if nameBox then
								nameBox:SetMaxLetters(64)
								nameBox:ClearAllPoints()
								nameBox:SetPoint("TOP", selfPopup, "TOP", 0, POPUP_EDITBOX_Y)
							end

							local btn2 = selfPopup and selfPopup.button2 or nil
							local btn1 = selfPopup and selfPopup.button1 or nil
							if btn2 then
								btn2:ClearAllPoints()
								btn2:SetPoint("TOP", selfPopup, "TOP", 0, POPUP_BUTTON2_Y)
							end
							if btn1 and btn2 then
								btn1:ClearAllPoints()
								btn1:SetPoint("RIGHT", btn2, "LEFT", -10, 0)
							end

							local popupW = selfPopup and selfPopup.GetWidth and selfPopup:GetWidth() or 360
							local colW = 82
							local gap = 12
							local totalW = (colW * 3) + (gap * 2)
							local startX = math.floor((popupW - totalW) / 2)
							local cols = {
								selfPopup and selfPopup._wowguildeCreateCol_TANK or nil,
								selfPopup and selfPopup._wowguildeCreateCol_HEAL or nil,
								selfPopup and selfPopup._wowguildeCreateCol_DPS or nil,
							}
							for i = 1, 3 do
								local col = cols[i]
								if col then
									col:ClearAllPoints()
									col:SetPoint(
										"TOPLEFT",
										selfPopup,
										"TOPLEFT",
										startX + ((i - 1) * (colW + gap)),
										POPUP_COL_Y
									)
								end
							end
						end

						local editingRoster = ResolveEditingRoster(pendingConfigRosterId)
						tankBox:SetText("2")
						tankBox:SetCursorPosition(0)
						tankBox:SetTextColor(0.62, 0.62, 0.62, 1)

						local nameBox = GetPopupNameBox(selfPopup)
						if editingRoster then
							local targets = editingRoster.targets or {}
							if nameBox and nameBox.SetText then
								nameBox:SetText(tostring(editingRoster.name or ""))
							end
							healBox:SetText(tostring(math.max(0, math.floor(tonumber(targets.HEAL or 0) or 0))))
							dpsBox:SetText(tostring(math.max(0, math.floor(tonumber(targets.DPS or 0) or 0))))
						else
							if nameBox and nameBox.SetText then
								local templates = Rosteur and Rosteur.GetTemplates and Rosteur.GetTemplates() or {}
								local def = templates[selectedKey] or nil
								local suggestedName = (def and def.name) or selectedKey or ""
								nameBox:SetText(tostring(suggestedName))
								if nameBox.HighlightText then
									nameBox:HighlightText()
								end
							end
							healBox:SetText(tostring(math.max(0, math.floor(tonumber(defaults.HEAL or 0) or 0))))
							dpsBox:SetText(tostring(math.max(0, math.floor(tonumber(defaults.DPS or 0) or 0))))
						end

						if nameBox and nameBox.SetFocus then
							nameBox:SetFocus()
						end

						ApplyPopupLayout()
						if C_Timer and C_Timer.After then
							C_Timer.After(0, ApplyPopupLayout)
							C_Timer.After(0.05, ApplyPopupLayout)
						end
					end,
					OnAccept = function(selfPopup)
						local box = selfPopup and selfPopup.editBox
						if not box and selfPopup and selfPopup.GetName then
							box = _G[selfPopup:GetName() .. "EditBox"]
						end
						local text = (box and box.GetText and box:GetText()) or ""
						local name = TrimSpaces(text)
						if name == "" then
							if UIErrorsFrame and UIErrorsFrame.AddMessage then
								UIErrorsFrame:AddMessage("Veuillez entrer un nom.", 1, 0.2, 0.2, 1)
							end
							StaticPopup_Show("WOWGUILDE_ROSTEUR_CREATE_CONFIG")
							return
						end
						local key, defaults = ResolveCreateTargets()
						if selfPopup and selfPopup._wowguildeTemplateKey and selfPopup._wowguildeTemplateKey ~= "" then
							key = selfPopup._wowguildeTemplateKey
						end
						local healBox = selfPopup and selfPopup._wowguildeCreateBox_HEAL or nil
						local dpsBox = selfPopup and selfPopup._wowguildeCreateBox_DPS or nil
						local heal = tonumber((healBox and healBox.GetText and healBox:GetText()) or "")
							or defaults.HEAL
							or 0
						local dps = tonumber((dpsBox and dpsBox.GetText and dpsBox:GetText()) or "")
							or defaults.DPS
							or 0
						heal = math.max(0, math.floor(heal))
						dps = math.max(0, math.floor(dps))
						local editId = pendingConfigRosterId
						pendingConfigRosterId = nil
						if editId then
							if Rosteur and Rosteur.RenameRoster then
								Rosteur.RenameRoster(gid, editId, name)
							end
							if Rosteur and Rosteur.SetRosterTargets then
								Rosteur.SetRosterTargets(gid, editId, { TANK = 2, HEAL = heal, DPS = dps })
							end
						else
							Rosteur.CreateRoster(gid, key, name, { TANK = 2, HEAL = heal, DPS = dps })
						end
						RequestRefresh()
					end,
					EditBoxOnTextChanged = function() end,
					OnCancel = function()
						pendingConfigRosterId = nil
					end,
					OnHide = function(selfPopup)
						SetCreatePopupExtrasShown(selfPopup, false)
					end,
					timeout = 0,
					whileDead = 1,
					hideOnEscape = 1,
					preferredIndex = 3,
				}
			end
			StaticPopup_Show("WOWGUILDE_ROSTEUR_CREATE_CONFIG")
		else
			local key = templateKey or (emptyDropdown and emptyDropdown._value) or "raid20"
			Rosteur.CreateRoster(gid, key, nil)
			RequestRefresh()
		end
	end

	local function OpenConfigureCompositionPopup(rosterId)
		local gid = GetGuildUID()
		if not (Rosteur and gid and rosterId) then
			return
		end
		pendingConfigRosterId = rosterId
		OpenCreateConfigPopup(nil)
	end

	local function SetupConfigSelectDropdown(rosteur)
		if not (configSelect and configSelect.SetupMenu) then
			return
		end

		local rosterList = (rosteur and type(rosteur.rosters) == "table") and rosteur.rosters or nil
		local activeId = rosteur and rosteur.activeRosterId or nil
		local activeName = nil
		if rosterList then
			for i = 1, #rosterList do
				local r = rosterList[i]
				if r and r.id == activeId then
					activeName = r.name or ("Configuration " .. tostring(i))
					break
				end
			end
		end

		configSelect._value = activeId
		configSelect:SetDefaultText(activeName or "Choisir une configuration")

		configSelect:SetupMenu(function(_, root)
			if rosterList then
				for i = 1, #rosterList do
					local r = rosterList[i]
					if r and r.id then
						local rosterId = r.id
						local baseName = r.name or ("Configuration " .. tostring(i))
						local targets = r.targets or {}
						local t = tonumber(targets.TANK or 0) or 0
						local h = tonumber(targets.HEAL or 0) or 0
						local d = tonumber(targets.DPS or 0) or 0
						local size = t + h + d
						local iconT = ROLE_ATLAS and ROLE_ATLAS.TANK or ""
						local iconH = ROLE_ATLAS and ROLE_ATLAS.HEAL or ""
						local iconD = ROLE_ATLAS and ROLE_ATLAS.DPS or ""
						local label = string.format(
							"%s (Raid %d) : |A:%s:14:14|a %d   |A:%s:14:14|a %d   |A:%s:14:14|a %d",
							baseName,
							size,
							iconT,
							t,
							iconH,
							h,
							iconD,
							d
						)
						Dropdown_AddRadioEntry(root, label, function()
							return configSelect._value == rosterId
						end, function()
							configSelect._value = rosterId
							local gid = GetGuildUID()
							if Rosteur and gid and rosterId then
								Rosteur.SetActiveRoster(gid, rosterId)
							end
							RequestRefresh()
						end)
					end
				end
			end

			if root.CreateDivider then
				root:CreateDivider()
			end
			local hasSelected = configSelect and configSelect._value ~= nil
			root:CreateButton("Configurer la composition", function()
				OpenConfigureCompositionPopup(configSelect and configSelect._value or nil)
			end, { disabled = not hasSelected })
			root:CreateButton("Supprimer la composition", function()
				local gid = GetGuildUID()
				local targetId = configSelect and configSelect._value or nil
				if Rosteur and gid and targetId then
					Rosteur.DeleteRoster(gid, targetId, { force = true })
				end
				RequestRefresh()
			end, { disabled = not hasSelected })
			if root.CreateDivider then
				root:CreateDivider()
			end

			local templates = Rosteur and Rosteur.GetTemplates and Rosteur.GetTemplates() or {}
			local ordered = { "raid10", "raid15", "raid20", "raid25" }
			for _, key in ipairs(ordered) do
				local def = templates[key]
				if def and def.targets then
					local t = def.targets.TANK or 0
					local h = def.targets.HEAL or 0
					local d = def.targets.DPS or 0
					local iconT = ROLE_ATLAS and ROLE_ATLAS.TANK or ""
					local iconH = ROLE_ATLAS and ROLE_ATLAS.HEAL or ""
					local iconD = ROLE_ATLAS and ROLE_ATLAS.DPS or ""
					local label = string.format(
						"%s : |A:%s:16:16|a %d   |A:%s:16:16|a %d   |A:%s:16:16|a %d",
						def.name or key,
						iconT,
						t,
						iconH,
						h,
						iconD,
						d
					)
					root:CreateButton(label, function()
						OpenCreateConfigPopup(key)
					end)
				end
			end

			if root.CreateDivider then
				root:CreateDivider()
			end
			root:CreateButton("Créer ma composition...", function()
				OpenCreateConfigPopup()
			end)
		end)
	end

	local function SetupEmptyTemplateDropdown()
		if not (emptyDropdown and emptyDropdown.SetupMenu) then
			return
		end
		local templates = Rosteur and Rosteur.GetTemplates and Rosteur.GetTemplates() or {}
		local ordered = { "raid10", "raid15", "raid20", "raid25" }
		local function BuildLabel(key, def)
			if not def or not def.targets then
				return def and def.name or key
			end
			local t = 2
			local h = tonumber(def.targets.HEAL or 0) or 0
			local d = tonumber(def.targets.DPS or 0) or 0
			local size = t + h + d
			local iconT = ROLE_ATLAS and ROLE_ATLAS.TANK or ""
			local iconH = ROLE_ATLAS and ROLE_ATLAS.HEAL or ""
			local iconD = ROLE_ATLAS and ROLE_ATLAS.DPS or ""
			local prefix = string.format("%s (Raid %d) : ", (def.name or key), size)
			return string.format(
				"%s|A:%s:12:12|a %d   |A:%s:12:12|a %d   |A:%s:12:12|a %d",
				prefix,
				iconT,
				t,
				iconH,
				h,
				iconD,
				d
			)
		end
		local firstKey = emptyDropdown._value
		if not firstKey then
			for _, k in ipairs(ordered) do
				if templates[k] then
					firstKey = k
					break
				end
			end
			if not firstKey then
				for k, _ in pairs(templates) do
					firstKey = k
					break
				end
			end
			emptyDropdown._value = firstKey
		end
		local defaultName = firstKey and templates[firstKey] and (templates[firstKey].name or firstKey)
			or "Préconfiguration"
		emptyDropdown:SetDefaultText(defaultName)
		emptyDropdown:SetupMenu(function(_, root)
			local seen = {}
			for _, key in ipairs(ordered) do
				local def = templates[key]
				if def then
					seen[key] = true
					local labelText = BuildLabel(key, def)
					root:CreateButton(labelText, function()
						emptyDropdown._value = key
						emptyDropdown:SetDefaultText(def.name or key)
						OpenCreateConfigPopup(key)
					end, {
						isRadio = true,
						checked = function()
							return emptyDropdown._value == key
						end,
					})
				end
			end
			if root.CreateDivider then
				root:CreateDivider()
			end
			root:CreateButton("Créer ma composition...", function()
				OpenCreateConfigPopup()
			end)
		end)
	end

	return {
		SetCreatePopupExtrasShown = SetCreatePopupExtrasShown,
		GetPopupNameBox = GetPopupNameBox,
		Dropdown_AddRadioEntry = Dropdown_AddRadioEntry,
		SetConfigEmptyTitleLayout = SetConfigEmptyTitleLayout,
		ResolveActiveRoster = ResolveActiveRoster,
		ComputeRosterMissing = ComputeRosterMissing,
		BuildMissingText = BuildMissingText,
		FillRosterMissingWithPU = FillRosterMissingWithPU,
		OpenCreateConfigPopup = OpenCreateConfigPopup,
		OpenConfigureCompositionPopup = OpenConfigureCompositionPopup,
		SetupConfigSelectDropdown = SetupConfigSelectDropdown,
		SetupEmptyTemplateDropdown = SetupEmptyTemplateDropdown,
	}
end
