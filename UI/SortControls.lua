local ADDON, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

local function MethodLabel(m)
	if m == "class" then
		return "Sinif"
	elseif m == "name" then
		return "Isim"
	elseif m == "mplus" then
		return "M+ puani"
	elseif m == "achv" then
		return "Basari puani"
	end
	return "Son giris"
end

function UI.MakeSortControls(parent, sortState, onApply)
	local controls = CreateFrame("DropdownButton", "WoWGuilde_Dropdown", parent, "WowStyle1DropdownTemplate")
	controls:SetPoint("TOPLEFT", parent, "TOPLEFT", 60, 30)
	controls:SetSize(225, 25)

	local function ApplySort(method)
		sortState.method = method
		ns.Prefs.SetHeros("sortMethod", method)
		controls:SetDefaultText("Sirala: " .. MethodLabel(sortState.method))
		onApply()
	end

	local function DropdownGenerator(owner, root)
		root:CreateButton("Son giris", function()
			ApplySort("last")
		end, {
			isRadio = true,
			checked = function()
				return sortState.method == "last"
			end,
		})
		root:CreateButton("Sinif", function()
			ApplySort("class")
		end, {
			isRadio = true,
			checked = function()
				return sortState.method == "class"
			end,
		})
		root:CreateButton("Isim", function()
			ApplySort("name")
		end, {
			isRadio = true,
			checked = function()
				return sortState.method == "name"
			end,
		})
		if root.CreateDivider then
			root:CreateDivider()
		end
		root:CreateButton("M+ puani", function()
			ApplySort("mplus")
		end, {
			isRadio = true,
			checked = function()
				return sortState.method == "mplus"
			end,
		})
		root:CreateButton("Basari puani", function()
			ApplySort("achv")
		end, {
			isRadio = true,
			checked = function()
				return sortState.method == "achv"
			end,
		})
	end

	controls:SetupMenu(DropdownGenerator)
	controls:SetDefaultText("Sirala: " .. MethodLabel(sortState.method))
	return controls
end
