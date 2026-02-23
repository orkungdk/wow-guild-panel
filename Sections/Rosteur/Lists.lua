local ADDON, ns = ...

local M = ns.RosteurSection

local viewCounter = 0
local entryCounter = 0
local prepItemCounter = 0

function M.SetupLists(ctx)
	local const = ctx.const
	local fn = ctx.fn

	local ROLE_ORDER = const.ROLE_ORDER
	local ROLE_LABEL = const.ROLE_LABEL

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

		view.scroll = CreateFrame("ScrollFrame", prefix .. "_Scroll", view, "QuestScrollFrameTemplate")
		view.scroll:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
		view.scroll:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -30, 0)

		view.content = CreateFrame("Frame", prefix .. "_Content", view.scroll)
		view.scroll:SetScrollChild(view.content)

		local function ToggleSection(role)
			view.collapsed[role] = not view.collapsed[role]
			if view.Refresh then
				view.Refresh()
			end
		end

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
					if button == "LeftButton" and fn.GetDrag and fn.GetDrag() then
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
				local count = type(list) == "table" and #list or 0
				local target = targets and targets[role] or nil
				local label = ROLE_LABEL[role] or role
				local prefixText = view.collapsed[role] and "► " or "▼ "
				local suffix = target and (" (" .. count .. "/" .. tostring(target) .. ")") or (" (" .. count .. ")")
				section.header.text:SetText(prefixText .. label .. suffix)

				local bodyHeight = 0
				if not view.collapsed[role] and type(list) == "table" then
					for i = 1, #list do
						local entry = list[i]
						local btn = AcquireFromPool(pool, section.body)
						entries[#entries + 1] = btn
						btn:SetWidth(contentWidth)
						btn.data = {
							id = entry.id,
							full = entry.full,
							name = entry.name or entry.full,
							classTag = entry.classTag,
							uid = entry.uid,
							isPU = entry.isPU,
							source = "roster",
							rosterId = roster and roster.id or nil,
						}
						local nameText = fn.ColorizeName and fn.ColorizeName(btn.data.name, btn.data.classTag) or btn.data.name
						if btn.data.isPU then
							nameText = nameText .. " |cff9d9d9d(PU)|r"
						end
						btn.text:SetText(nameText)
						btn:RegisterForDrag("LeftButton")
						btn:SetScript("OnDragStart", function(self)
							if opts and opts.enableDrag and fn.StartDrag then
								fn.StartDrag(self.data)
							end
						end)
						btn:SetScript("OnDragStop", function()
							if fn.StopDrag then
								fn.StopDrag()
							end
						end)
						btn:SetScript("OnMouseDown", function(self)
							if opts and opts.enableDrag and fn.StartDrag then
								fn.StartDrag(self.data)
							end
						end)
						btn:SetScript("OnMouseUp", function()
							if opts and opts.enableDrag and fn.StopDrag then
								fn.StopDrag()
							end
						end)
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
				local nameText = fn.ColorizeName and fn.ColorizeName(entry.name or entry.full or "-", entry.classTag)
					or tostring(entry.name or entry.full or "-")
				if entry.isPU then
					nameText = nameText .. " |cff9d9d9d(PU)|r"
				end
				item.text:SetText(nameText)
				item._fullName = entry.full
			end
			LayoutList(self.content, self.items, self.rowHeight, 2, width)
		end

		return list
	end

	fn.CreateEntryButton = CreateEntryButton
	fn.AcquireFromPool = AcquireFromPool
	fn.ReleaseAll = ReleaseAll
	fn.LayoutList = LayoutList
	fn.MakeRosterView = MakeRosterView
	fn.CreateSimpleList = CreateSimpleList
end

return M
