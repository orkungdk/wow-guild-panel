local ADDON, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

UI.PLACEHOLDER_ICON = 132331

function UI.SetProfileAwareIcon(tex, hasProfile, classTag)
	if hasProfile and classTag and CLASS_ICON_TCOORDS[classTag] then
		local coords = CLASS_ICON_TCOORDS[classTag]
		tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	else
		tex:SetTexture(UI.PLACEHOLDER_ICON)
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end
