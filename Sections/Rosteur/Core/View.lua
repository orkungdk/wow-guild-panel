local ADDON, ns = ...

ns.RosteurSectionCoreView = ns.RosteurSectionCoreView or {}
local View = ns.RosteurSectionCoreView

function View.Build(env)
	local ROLE_ORDER = env and env.ROLE_ORDER or { "TANK", "HEAL", "DPS" }
	local ROLE_LABEL = env and env.ROLE_LABEL or { TANK = "Protection", HEAL = "Soins", DPS = "Dégâts" }
	local ROLE_ATLAS = env and env.ROLE_ATLAS or {
		TANK = "UI-LFG-RoleIcon-Tank",
		HEAL = "UI-LFG-RoleIcon-Healer",
		DPS = "UI-LFG-RoleIcon-DPS",
	}
	local ColorizeName = env and env.ColorizeName or function(name)
		return tostring(name or "-")
	end
	local StartDrag = env and env.StartDrag or function()
	end
	local StopDrag = env and env.StopDrag or function()
	end
	local StopDragDeferred = env and env.StopDragDeferred or function()
	end
	local GetDrag = env and env.GetDrag or function()
		return nil
	end
	local GetShortDragName = env and env.GetShortDragName or function(data)
		return tostring((data and (data.name or data.full)) or "+")
	end
	local ROSTER_CLASS_VISUAL_SIZE = env and env.ROSTER_CLASS_VISUAL_SIZE or 45

	local viewCounter = 0
	local entryCounter = 0
	local prepItemCounter = 0

	local function CreateEntryButton(parent)
		entryCounter = entryCounter + 1
		local name = "WoWGuilde_Rosteur_Entry_" .. tostring(entryCounter)
		local btn = CreateFrame("Button", name, parent, "BackdropTemplate")
		btn:SetHeight(22)
		btn:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 10,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		btn:SetBackdropColor(0, 0, 0, 0.35)
		btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.6)

		btn.text = btn:CreateFontString(name .. "_Text", "OVERLAY", "GameFontHighlight")
		btn.text:SetPoint("LEFT", 8, 0)
		btn.text:SetPoint("RIGHT", -8, 0)
		btn.text:SetJustifyH("LEFT")

		return btn
	end

	local function AcquireFromPool(pool, parent)
		local btn = pool[#pool]
		if btn then
			pool[#pool] = nil
			btn:SetParent(parent)
			btn:Show()
			return btn
		end
		return CreateEntryButton(parent)
	end

	local function ReleaseAll(pool, list)
		for i = 1, #list do
			local btn = list[i]
			btn:Hide()
			btn:SetParent(nil)
			pool[#pool + 1] = btn
		end
		for i = 1, #list do
			list[i] = nil
		end
	end

	local function LayoutList(content, entries, rowHeight, gap, width)
		local h = 0
		local w = width or (content:GetWidth() or 0)
		for i = 1, #entries do
			local btn = entries[i]
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -h)
			btn:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -h)
			btn:SetHeight(rowHeight)
			h = h + rowHeight + gap
		end
		if h > 0 then
			h = h - gap
		end
		if w > 0 then
			content:SetWidth(w)
		end
		content:SetHeight(math.max(1, h))
	end

	local function CountAssignedEntries(list)
		if type(list) ~= "table" then
			return 0
		end
		local count = 0
		for k, v in pairs(list) do
			if type(k) == "number" and type(v) == "table" then
				count = count + 1
			end
		end
		return count
	end

	local function MaxNumericIndex(list)
		if type(list) ~= "table" then
			return 0
		end
		local maxIndex = 0
		for k in pairs(list) do
			if type(k) == "number" and k > maxIndex then
				maxIndex = k
			end
		end
		return maxIndex
	end

	local function MakeRosterView(parent, opts)
		local prefix = opts and opts.namePrefix
		if not prefix then
			viewCounter = viewCounter + 1
			prefix = "WoWGuilde_Rosteur_View" .. tostring(viewCounter)
		end
		local view = CreateFrame("Frame", prefix, parent)
		view.sections = {}
		view.pools = {}
		view.entries = {}
		view.collapsed = { TANK = false, HEAL = false, DPS = false }
		view.isBuilder = opts and opts.layout == "builder"

		view.scroll = CreateFrame("ScrollFrame", prefix .. "_Scroll", view, "QuestScrollFrameTemplate")
		view.scroll:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
		view.scroll:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -30, 0)

		view.content = CreateFrame("Frame", prefix .. "_Content", view.scroll)
		view.scroll:SetScrollChild(view.content)
		if view.isBuilder then
			-- Builder view does not use the main vertical scroll at all.
			view.scroll:Hide()
			view.content:Hide()
			view.content = CreateFrame("Frame", prefix .. "_ContentStatic", view)
			view.content:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
			view.content:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, 0)
			view.content:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 0, 0)
			view.content:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
			view:SetScript("OnSizeChanged", function(self, w)
				if w and w > 0 then
					view.content:SetWidth(w)
				end
				if view.Refresh then
					view.Refresh()
				end
			end)
		else
			view.scroll:SetScript("OnSizeChanged", function(self, w)
				if w and w > 0 then
					view.content:SetWidth(w)
				end
				if view.Refresh then
					view.Refresh()
				end
			end)
			if view.scroll.GetWidth then
				local w = view.scroll:GetWidth() or 0
				if w > 0 then
					view.content:SetWidth(w)
				end
			end
		end

		local function ToggleSection(role)
			view.collapsed[role] = not view.collapsed[role]
			if view.Refresh then
				view.Refresh()
			end
		end

		if view.isBuilder then
			local SECTION_SEP_SHADOW_WIDTH = 900
			local SECTION_SEP_SHADOW_HEIGHT = 130
			local SECTION_SEP_SHADOW_Y = 2

			view.title = view.content:CreateFontString(prefix .. "_BuilderTitle", "OVERLAY", "GameFontNormalLarge")
			view.title:SetPoint("TOP", view.content, "TOP", 0, -4)
			view.title:SetJustifyH("CENTER")
			view.title:SetFont("Fonts\\2002.ttf", 25, "OUTLINE")
			view.title:SetTextColor(1, 0.694, 0, 1)
			view.title:SetText("Création du groupe de raid")

			view.totalCount = view.content:CreateFontString(prefix .. "_BuilderTotalCount", "OVERLAY", "GameFontHighlight")
			view.totalCount:SetJustifyH("CENTER")
			view.totalCount:SetText("0 place")

			for _, role in ipairs(ROLE_ORDER) do
				local section = CreateFrame("Frame", prefix .. "_Section_" .. role, view.content)
				section.role = role

				section.title = section:CreateFontString(prefix .. "_SectionTitle_" .. role, "OVERLAY", "GameFontNormal")
				section.title:SetJustifyH("LEFT")
				section.title:SetPoint("TOPLEFT", section, "TOPLEFT", 8, 0)
				section.title:SetPoint("TOPRIGHT", section, "TOPRIGHT", -8, 0)

				section.sep = section:CreateTexture(prefix .. "_SectionSep_" .. role, "BORDER")
				section.sep:SetAtlas("AnimaChannel-Reinforce-TextShadow")
				section.sep:SetVertexColor(0, 0, 0, 0.5)
				section.sep:SetHeight(3)
				section.sep:SetPoint("BOTTOMLEFT", section.title, "TOPLEFT", 0, 15)
				section.sep:SetPoint("BOTTOMRIGHT", section.title, "TOPRIGHT", 0, 15)
				section.sepShadow = section:CreateTexture(prefix .. "_SectionSepShadow_" .. role, "BACKGROUND")
				section.sepShadow:SetAtlas("LevelUp-Shadow-Lower", true)
				section.sepShadow:SetTexCoord(0.5, 1, 0, 1)
				section.sepShadow:SetSize(SECTION_SEP_SHADOW_WIDTH, SECTION_SEP_SHADOW_HEIGHT)
				section.sepShadow:SetPoint("TOP", section.sep, "BOTTOM", 0, SECTION_SEP_SHADOW_Y)
				section.sepShadow:SetAlpha(0.5)
				section.dragGlow = section:CreateTexture(prefix .. "_SectionDragGlow_" .. role, "BACKGROUND", nil, 3)
				section.dragGlow:SetAtlas("GarrMission_ListGlow-Select", true)
				section.dragGlow:SetPoint("TOPLEFT", section, "TOPLEFT", -10, 14)
				section.dragGlow:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", 10, -8)
				section.dragGlow:SetVertexColor(1, 0.808, 0.49, 0.549)
				section.dragGlow:SetBlendMode("ADD")
				section.dragGlow:Hide()
				section:SetScript("OnUpdate", function(self)
					if not self.dragGlow then
						return
					end
					local drag = GetDrag()
					if type(drag) ~= "table" then
						self.dragGlow:Hide()
						return
					end
					local dragRole = tostring(drag.requestedRole or drag.role or "")
					local matches = dragRole == self.role
					self.dragGlow:SetShown(matches)
				end)

				section.count =
					section:CreateFontString(prefix .. "_SectionCount_" .. role, "OVERLAY", "GameFontHighlightSmall")
				section.count:SetJustifyH("LEFT")
				section.count:SetPoint("TOPLEFT", section.title, "BOTTOMLEFT", 0, -4)
				section.count:SetPoint("TOPRIGHT", section.title, "BOTTOMRIGHT", 0, -4)

				section.scroll = CreateFrame("ScrollFrame", prefix .. "_SectionScroll_" .. role, section)
				section.scroll:SetPoint("TOPLEFT", section.count, "BOTTOMLEFT", 0, -8)
				section.scroll:SetPoint("TOPRIGHT", section.count, "BOTTOMRIGHT", 0, -8)
				section.scroll:SetHeight(72)
				section.scroll:EnableMouse(true)
				section.scroll:EnableMouseWheel(true)

				section.body = CreateFrame("Frame", prefix .. "_SectionBody_" .. role, section.scroll)
				section.body:SetPoint("TOPLEFT", section.scroll, "TOPLEFT", 0, 0)
				section.body:SetHeight(72)
				section.body:SetWidth(1)
				section.scroll:SetScrollChild(section.body)

				section.scroll:SetScript("OnMouseWheel", function(self, delta)
					local max = math.max(0, (section.body:GetWidth() or 0) - (self:GetWidth() or 0))
					if max <= 0 then
						self:SetHorizontalScroll(0)
						return
					end
					local cur = self:GetHorizontalScroll() or 0
					local nextPos = cur - (delta * 32)
					if nextPos < 0 then
						nextPos = 0
					elseif nextPos > max then
						nextPos = max
					end
					self:SetHorizontalScroll(nextPos)
				end)

				view.sections[role] = section
				view.pools[role] = {}
				view.entries[role] = {}
			end

			function view.Refresh()
				local roster = view._roster
				local targets = roster and roster.targets or nil
				local groups = roster and roster.groups or nil
				local width = view.content:GetWidth() or view:GetWidth() or 0
				local contentWidth = math.max(1, width - 10)
				local sectionWidth = math.max(220, contentWidth - 24)
				local startX = math.max(0, math.floor((contentWidth - sectionWidth) / 2))
				local baseY = 78
				local totalTarget = 0
				local stackY = baseY
				local stackGap = 18
				local SLOT_SIZE = 58
				local SLOT_GAP = 14

				view.totalCount:ClearAllPoints()
				view.totalCount:SetPoint("TOP", view.title, "BOTTOM", 0, -8)

				for _, role in ipairs(ROLE_ORDER) do
					local section = view.sections[role]
					local entries = view.entries[role]
					local pool = view.pools[role]
					ReleaseAll(pool, entries)

					local target = math.max(0, math.floor(tonumber(targets and targets[role] or 0) or 0))
					local list = type(groups) == "table" and type(groups[role]) == "table" and groups[role] or {}
					local count = CountAssignedEntries(list)
					local slotCount = math.max(target, MaxNumericIndex(list), count)
					totalTarget = totalTarget + target

					local atlas = ROLE_ATLAS and ROLE_ATLAS[role] or nil
					local roleLabel = ROLE_LABEL[role] or role
					if atlas and atlas ~= "" then
						section.title:SetText("|A:" .. atlas .. ":16:16|a " .. roleLabel)
					else
						section.title:SetText(roleLabel)
					end
					section.count:SetText(tostring(target) .. " places")

					local bodyHeight = 72
					local isDps = role == "DPS"
					local step = SLOT_SIZE + 22
					if isDps then
						step = math.max(100, SLOT_SIZE + 42)
					end
					local naturalW = 0
					if slotCount > 0 then
						naturalW = SLOT_SIZE + (math.max(0, slotCount - 1) * step)
					end

					for i = 1, slotCount do
						local entry = list[i]
						local btn = AcquireFromPool(pool, section.body)
						entries[#entries + 1] = btn
						btn:SetSize(SLOT_SIZE, SLOT_SIZE)
						btn:ClearAllPoints()
						btn:SetPoint("TOPLEFT", section.body, "TOPLEFT", (i - 1) * step, -7)
						btn:SetBackdrop(nil)
						btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
						btn:RegisterForDrag("LeftButton")
						btn.slotRole = role
						btn.slotIndex = i
						btn.text:ClearAllPoints()
						btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
						btn.text:SetWidth(SLOT_SIZE - 10)
						btn.text:SetJustifyH("CENTER")
						btn:SetScale(1)
						btn:SetAlpha(1)

						if not btn._wowguildeCircleMask then
							local mask = btn:CreateMaskTexture(nil, "BACKGROUND")
							mask:SetAllPoints(btn)
							mask:SetTexture(
								"Interface\\CharacterFrame\\TempPortraitAlphaMask",
								"CLAMPTOBLACKADDITIVE",
								"CLAMPTOBLACKADDITIVE"
							)
							btn._wowguildeCircleMask = mask
						end
						if not btn._wowguildeFilledMask then
							local filledMask = btn:CreateMaskTexture(nil, "BACKGROUND")
							filledMask:SetSize(ROSTER_CLASS_VISUAL_SIZE, ROSTER_CLASS_VISUAL_SIZE)
							filledMask:SetPoint("CENTER", btn, "CENTER", 0, 0)
							filledMask:SetTexture(
								"Interface\\CharacterFrame\\TempPortraitAlphaMask",
								"CLAMPTOBLACKADDITIVE",
								"CLAMPTOBLACKADDITIVE"
							)
							btn._wowguildeFilledMask = filledMask
						end
						if not btn._wowguildeCircleBg then
							local bg = btn:CreateTexture(nil, "BACKGROUND")
							bg:SetAllPoints(btn)
							bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)
							bg:AddMaskTexture(btn._wowguildeCircleMask)
							btn._wowguildeCircleBg = bg
						end
						if not btn._wowguildeFilledBg then
							local filledBg = btn:CreateTexture(nil, "ARTWORK", nil, -1)
							filledBg:SetSize(ROSTER_CLASS_VISUAL_SIZE, ROSTER_CLASS_VISUAL_SIZE)
							filledBg:SetPoint("CENTER", btn, "CENTER", 0, 0)
							filledBg:SetColorTexture(0.35, 0.35, 0.35, 0.95)
							filledBg:AddMaskTexture(btn._wowguildeFilledMask)
							btn._wowguildeFilledBg = filledBg
						end
						if not btn._wowguildeCircleRing then
							local ring = btn:CreateTexture(nil, "BORDER")
							ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
							ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
							ring:SetTexture("Interface\\Buttons\\UI-Quickslot2")
							ring:SetAlpha(0.8)
							btn._wowguildeCircleRing = ring
						end
						if not btn._wowguildeEmptyShadow then
							local shadow = btn:CreateTexture(nil, "BACKGROUND")
							shadow:SetPoint("TOPLEFT", btn, "TOPLEFT", -14, 9)
							shadow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 14, -12)
							shadow:SetAtlas("GarrFollower-Shadow", true)
							shadow:SetAlpha(0.95)
							btn._wowguildeEmptyShadow = shadow
						end
						if not btn._wowguildeEmptyBg then
							local emptyBg = btn:CreateTexture(nil, "ARTWORK", nil, -1)
							emptyBg:SetAllPoints(btn)
							emptyBg:SetAtlas("plunderstorm-glues-queueselector-solo", true)
							btn._wowguildeEmptyBg = emptyBg
						end
						if not btn._wowguildeEmptyRing then
							local emptyRing = btn:CreateTexture(nil, "OVERLAY", nil, 6)
							emptyRing:SetPoint("TOPLEFT", btn, "TOPLEFT", 4, -4)
							emptyRing:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
							emptyRing:SetAtlas("Map_Faction_Ring", true)
							if emptyRing.SetDesaturated then
								emptyRing:SetDesaturated(true)
							end
							emptyRing:SetVertexColor(0.85, 0.85, 0.85, 1)
							btn._wowguildeEmptyRing = emptyRing
						end
						if not btn._wowguildeEmptyTextHolder then
							local holder = btn:CreateTexture(nil, "OVERLAY", nil, 7)
							holder:SetSize(65, 30)
							holder:SetPoint("BOTTOM", btn, "BOTTOM", 0, -8)
							holder:SetAtlas("common-dropdown-textholder", false)
							if holder.SetDrawLayer then
								holder:SetDrawLayer("OVERLAY", 7)
							end
							btn._wowguildeEmptyTextHolder = holder
						end

						if entry then
							btn.data = {
								id = entry.id,
								full = entry.full,
								name = entry.name or entry.full,
								classTag = entry.classTag,
								uid = entry.uid,
								heroFull = entry.heroFull,
								heroName = entry.heroName,
								requestedRole = entry.requestedRole,
								slotRole = role,
								slotIndex = i,
								isPU = entry.isPU,
								source = "roster",
								rosterId = roster and roster.id or nil,
							}
							local nameText = ColorizeName(btn.data.name, btn.data.classTag)
							if btn.data.isPU then
								nameText = nameText .. " |cff9d9d9d(Externe)|r"
							end
							local shortName = GetShortDragName(btn.data)
							btn.text:SetText(ColorizeName(shortName, btn.data.classTag))
							btn.text:SetTextColor(1, 1, 1, 1)
							btn.text:ClearAllPoints()
							btn.text:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
							if btn._wowguildeEmptyTextHolder then
								btn.text:SetPoint("CENTER", btn._wowguildeEmptyTextHolder, "CENTER", 0, 0)
							else
								btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
							end
							if btn._wowguildeFilledBg then
								local classCoords = btn.data.classTag
									and CLASS_ICON_TCOORDS
									and CLASS_ICON_TCOORDS[btn.data.classTag]
								if classCoords then
									btn._wowguildeFilledBg:SetTexture(
										"Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
									)
									btn._wowguildeFilledBg:SetTexCoord(
										classCoords[1],
										classCoords[2],
										classCoords[3],
										classCoords[4]
									)
									btn._wowguildeFilledBg:SetVertexColor(1, 1, 1, 1)
								else
									btn._wowguildeFilledBg:SetTexCoord(0, 1, 0, 1)
									btn._wowguildeFilledBg:SetColorTexture(0.35, 0.35, 0.35, 0.95)
								end
								btn._wowguildeFilledBg:Show()
							end
							if btn._wowguildeCircleBg then
								btn._wowguildeCircleBg:Hide()
							end
							if btn._wowguildeCircleRing then
								btn._wowguildeCircleRing:Hide()
							end
							if btn._wowguildeEmptyShadow then
								btn._wowguildeEmptyShadow:Show()
							end
							if btn._wowguildeEmptyBg then
								btn._wowguildeEmptyBg:Hide()
							end
							if btn._wowguildeEmptyRing then
								btn._wowguildeEmptyRing:SetDesaturated(false)
								btn._wowguildeEmptyRing:SetVertexColor(1, 1, 1, 1)
								btn._wowguildeEmptyRing:Show()
							end
							if btn._wowguildeEmptyTextHolder then
								btn._wowguildeEmptyTextHolder:SetVertexColor(1, 0.847, 0.196, 1)
								btn._wowguildeEmptyTextHolder:Show()
							end
							btn:SetScript("OnDragStart", function(self)
								if opts and opts.enableDrag then
									StartDrag(self.data)
								end
							end)
							btn:SetScript("OnDragStop", function()
								StopDragDeferred()
							end)
						else
							btn.data = nil
							btn.text:SetText("|cffffffff+|r")
							btn.text:SetTextColor(1, 1, 1, 1)
							btn.text:ClearAllPoints()
							btn.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
							if btn._wowguildeEmptyTextHolder then
								btn.text:SetPoint("CENTER", btn._wowguildeEmptyTextHolder, "CENTER", 0, 0)
								btn._wowguildeEmptyTextHolder:SetVertexColor(1, 1, 1, 1)
								btn._wowguildeEmptyTextHolder:Show()
							else
								btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
							end
							if btn._wowguildeFilledBg then
								btn._wowguildeFilledBg:Hide()
							end
							if btn._wowguildeCircleBg then
								btn._wowguildeCircleBg:Hide()
							end
							if btn._wowguildeCircleRing then
								btn._wowguildeCircleRing:Hide()
							end
							if btn._wowguildeEmptyShadow then
								btn._wowguildeEmptyShadow:Show()
							end
							if btn._wowguildeEmptyBg then
								btn._wowguildeEmptyBg:Show()
							end
							if btn._wowguildeEmptyRing then
								btn._wowguildeEmptyRing:SetDesaturated(true)
								btn._wowguildeEmptyRing:SetVertexColor(0.85, 0.85, 0.85, 1)
								btn._wowguildeEmptyRing:Show()
							end
							btn:SetScript("OnDragStart", nil)
							btn:SetScript("OnDragStop", nil)
						end

						btn:SetScript("OnReceiveDrag", function(self)
							if opts and opts.onDrop then
								opts.onDrop(self.slotRole, self.slotIndex)
							end
						end)
						btn:SetScript("OnMouseDown", function(self, button)
							if button == "LeftButton" and opts and opts.enableDrag and self.data then
								StartDrag(self.data)
							end
						end)
						btn:SetScript("OnMouseUp", function(self, button)
							if button == "RightButton" and self.data and opts and opts.onUnassign then
								opts.onUnassign(self.data)
								StopDrag()
								return
							end
							if button == "LeftButton" and GetDrag() and opts and opts.onDrop then
								opts.onDrop(self.slotRole, self.slotIndex)
								return
							end
							StopDrag()
						end)
					end

					local bodyW = isDps and math.max(sectionWidth, naturalW) or sectionWidth
					section.body:SetWidth(bodyW)
					section.body:SetHeight(72)
					local hasOverflow = isDps and bodyW > sectionWidth
					section.scroll:EnableMouseWheel(hasOverflow)
					local xStart = 0
					if not isDps then
						xStart = math.max(0, math.floor((sectionWidth - naturalW) / 2))
					elseif not hasOverflow then
						xStart = math.max(0, math.floor((sectionWidth - naturalW) / 2))
					end
					for i = 1, #entries do
						local btn = entries[i]
						btn._baseX = xStart + ((i - 1) * step)
						btn:ClearAllPoints()
						btn:SetPoint("TOPLEFT", section.body, "TOPLEFT", btn._baseX, -7)
						btn:SetScale(1)
						btn:SetAlpha(1)
					end
					section.scroll:SetHorizontalScroll(0)
					section.scroll:SetScript("OnHorizontalScroll", nil)

					section:ClearAllPoints()
					section:SetPoint("TOPLEFT", view.content, "TOPLEFT", startX, -stackY)
					section:SetWidth(sectionWidth)
					local secH = 18 + 7 + 16 + 8 + bodyHeight
					section:SetHeight(secH)
					stackY = stackY + secH + stackGap
				end

				if totalTarget <= 1 then
					view.totalCount:SetText(tostring(totalTarget) .. " place configurée")
				else
					view.totalCount:SetText(tostring(totalTarget) .. " places configurées")
				end
				view.content:SetHeight(math.max(1, stackY + 12))
			end
		else
			for _, role in ipairs(ROLE_ORDER) do
				local section = CreateFrame("Frame", prefix .. "_Section_" .. role, view.content)
				section.role = role
				section.header = CreateFrame("Button", prefix .. "_SectionHeader_" .. role, section)
				section.header:SetHeight(24)
				section.header:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
				section.header:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, 0)
				section.header:SetScript("OnClick", function()
					ToggleSection(role)
				end)

				section.header.text =
					section.header:CreateFontString(prefix .. "_SectionHeaderText_" .. role, "OVERLAY", "GameFontNormal")
				section.header.text:SetPoint("LEFT", 4, 0)
				section.header.text:SetJustifyH("LEFT")

				section.body = CreateFrame("Frame", prefix .. "_SectionBody_" .. role, section)
				section.body:SetPoint("TOPLEFT", section.header, "BOTTOMLEFT", 0, -4)
				section.body:SetPoint("TOPRIGHT", section.header, "BOTTOMRIGHT", 0, -4)
				section.body:SetHeight(1)

				if opts and opts.onDrop then
					section:SetScript("OnReceiveDrag", function()
						opts.onDrop(role)
					end)
					section:SetScript("OnMouseUp", function(_, button)
						if button == "LeftButton" and GetDrag() then
							opts.onDrop(role)
						end
					end)
				end

				view.sections[role] = section
				view.pools[role] = {}
				view.entries[role] = {}
			end

			function view.Refresh()
				local roster = view._roster
				local targets = roster and roster.targets or nil
				local y = 0
				local width = view.scroll:GetWidth() or 0
				local contentWidth = math.max(1, width - 10)

				for _, role in ipairs(ROLE_ORDER) do
					local section = view.sections[role]
					local entries = view.entries[role]
					local pool = view.pools[role]
					ReleaseAll(pool, entries)

					local list = roster and roster.groups and roster.groups[role] or nil
					local count = CountAssignedEntries(list)
					local target = targets and targets[role] or nil
					local label = ROLE_LABEL[role] or role
					local prefixLabel = view.collapsed[role] and "► " or "▼ "
					local suffix = target and (" (" .. count .. "/" .. tostring(target) .. ")") or (" (" .. count .. ")")
					section.header.text:SetText(prefixLabel .. label .. suffix)

					local bodyHeight = 0
					if not view.collapsed[role] and type(list) == "table" then
						local maxIndex = MaxNumericIndex(list)
						for i = 1, maxIndex do
							local entry = list[i]
							if type(entry) == "table" then
								local btn = AcquireFromPool(pool, section.body)
								entries[#entries + 1] = btn
								btn:SetWidth(contentWidth)
								btn.data = {
									id = entry.id,
									full = entry.full,
									name = entry.name or entry.full,
									classTag = entry.classTag,
									uid = entry.uid,
									heroFull = entry.heroFull,
									heroName = entry.heroName,
									requestedRole = entry.requestedRole,
									slotRole = role,
									slotIndex = i,
									isPU = entry.isPU,
									source = "roster",
									rosterId = roster and roster.id or nil,
								}
								local nameText = ColorizeName(btn.data.name, btn.data.classTag)
								if btn.data.isPU then
									nameText = nameText .. " |cff9d9d9d(Externe)|r"
								end
								btn.text:SetText(nameText)
								btn:RegisterForDrag("LeftButton")
								btn:SetScript("OnDragStart", function(self)
									if opts and opts.enableDrag then
										StartDrag(self.data)
									end
								end)
								btn:SetScript("OnDragStop", function()
									StopDragDeferred()
								end)
								btn:SetScript("OnMouseDown", function(self)
									if opts and opts.enableDrag then
										StartDrag(self.data)
									end
								end)
								btn:SetScript("OnMouseUp", function()
									if opts and opts.enableDrag then
										StopDrag()
									end
								end)
							end
						end
						LayoutList(section.body, entries, 22, 4, contentWidth)
						bodyHeight = section.body:GetHeight()
					else
						section.body:SetHeight(1)
					end

					section:ClearAllPoints()
					section:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, -y)
					section:SetPoint("TOPRIGHT", view.content, "TOPRIGHT", 0, -y)
					local sectionHeight = 24 + 4 + bodyHeight + 10
					section:SetHeight(sectionHeight)
					y = y + sectionHeight
				end
				view.content:SetHeight(math.max(1, y))
			end
		end

		return view
	end

	local function CreateSimpleList(parent, namePrefix)
		local list = CreateFrame("Frame", namePrefix, parent)
		list._prefix = namePrefix
		list.pool = {}
		list.items = {}
		list.rowHeight = 20

		list.scroll = CreateFrame("ScrollFrame", namePrefix .. "_Scroll", list, "QuestScrollFrameTemplate")
		list.scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
		list.scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -6, 0)

		do
			local sb = list.scroll.ScrollBar or _G[namePrefix .. "_ScrollScrollBar"]
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

		list.content = CreateFrame("Frame", namePrefix .. "_Content", list.scroll)
		list.scroll:SetScrollChild(list.content)
		list.content:SetPoint("TOPLEFT")
		list.content:SetWidth(1)
		list.content:SetHeight(1)

		local function AcquireItem()
			local item = list.pool[#list.pool]
			if item then
				list.pool[#list.pool] = nil
				item:SetParent(list.content)
				item:Show()
				return item
			end

			prepItemCounter = prepItemCounter + 1
			local itemName = namePrefix .. "_Item_" .. tostring(prepItemCounter)
			item = CreateFrame("Frame", itemName, list.content)
			item:SetHeight(list.rowHeight)
			item.text = item:CreateFontString(itemName .. "_Text", "ARTWORK", "GameFontHighlightSmall")
			item.text:SetPoint("LEFT", 6, 0)
			item.text:SetPoint("RIGHT", -6, 0)
			item.text:SetJustifyH("LEFT")
			item.text:SetTextColor(0.9, 0.9, 0.9, 1)
			item.sep = item:CreateTexture(itemName .. "_Sep", "BORDER")
			item.sep:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, -2)
			item.sep:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, -2)
			item.sep:SetHeight(2)
			item.sep:SetAtlas("AnimaChannel-Reinforce-TextShadow")
			item.sep:SetAlpha(0.35)
			return item
		end

		function list:Clear()
			ReleaseAll(self.pool, self.items)
			self.content:SetHeight(1)
		end

		function list:SetEntries(entries)
			ReleaseAll(self.pool, self.items)
			local width = self.scroll:GetWidth() or 0
			if width < 80 then
				width = 200
			end
			for i = 1, #entries do
				local entry = entries[i]
				local item = AcquireItem()
				self.items[#self.items + 1] = item
				item:SetWidth(width)
				local nameText = ColorizeName(entry.name or entry.full or "-", entry.classTag)
				if entry.isPU then
					nameText = nameText .. " |cff9d9d9d(Externe)|r"
				end
				item.text:SetText(nameText)
				item._fullName = entry.full
			end
			LayoutList(self.content, self.items, self.rowHeight, 2, width)
		end

		return list
	end

	return {
		CountAssignedEntries = CountAssignedEntries,
		MaxNumericIndex = MaxNumericIndex,
		MakeRosterView = MakeRosterView,
		CreateSimpleList = CreateSimpleList,
	}
end
