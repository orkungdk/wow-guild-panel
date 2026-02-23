local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.HoverObjects = QM.HoverObjects or { version = 1, maps = {} }
local HoverObjects = QM.HoverObjects

local function Clamp(v, minV, maxV)
	if v < minV then
		return minV
	end
	if v > maxV then
		return maxV
	end
	return v
end

local function F(v)
	return string.format("%.4f", tonumber(v) or 0)
end

local function Trim(s)
	local v = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if (#v >= 2) and ((v:sub(1, 1) == '"' and v:sub(-1) == '"') or (v:sub(1, 1) == "'" and v:sub(-1) == "'")) then
		v = v:sub(2, -2)
	end
	return v
end

function HoverObjects.EnsureMapStore(mapId)
	HoverObjects.maps = type(HoverObjects.maps) == "table" and HoverObjects.maps or {}
	local key = tostring(mapId or "default")
	HoverObjects.maps[key] = type(HoverObjects.maps[key]) == "table" and HoverObjects.maps[key] or {}
	local store = HoverObjects.maps[key]
	store.settings = type(store.settings) == "table" and store.settings or {}
	store.settings.lightMultiplier = Clamp(tonumber(store.settings.lightMultiplier) or 1.6, 1.0, 3.0)
	store.links = type(store.links) == "table" and store.links or {}
	return store
end

function HoverObjects.NormalizeLink(input)
	if type(input) ~= "table" then
		return nil
	end
	local sourceObjectId = Trim(input.sourceObjectId)
	local lieuId = Trim(input.lieuId)
	if sourceObjectId == "" or lieuId == "" then
		return nil
	end
	return {
		id = Trim(input.id),
		sourceObjectId = sourceObjectId,
		lieuId = lieuId,
		modelLabel = Trim(input.modelLabel),
		lieuLabel = Trim(input.lieuLabel),
		enabled = input.enabled ~= false,
	}
end

function HoverObjects.BuildExportText(mapId)
	HoverObjects.maps = type(HoverObjects.maps) == "table" and HoverObjects.maps or {}
	HoverObjects.EnsureMapStore(mapId)

	local entries = {}
	for key, store in pairs(HoverObjects.maps) do
		entries[#entries + 1] = {
			keyText = tostring(key),
			store = store,
		}
	end
	table.sort(entries, function(a, b)
		return a.keyText < b.keyText
	end)

	local sb = {}
	sb[#sb + 1] = "local ADDON, ns = ..."
	sb[#sb + 1] = ""
	sb[#sb + 1] = "ns.QuartierMiniature = ns.QuartierMiniature or {}"
	sb[#sb + 1] = "local QM = ns.QuartierMiniature"
	sb[#sb + 1] = ""
	sb[#sb + 1] = "QM.HoverObjects = QM.HoverObjects or {}"
	sb[#sb + 1] = ("QM.HoverObjects.version = %s"):format(tostring(tonumber(HoverObjects.version) or 1))
	sb[#sb + 1] = "QM.HoverObjects.maps = {"
	for i = 1, #entries do
		local entry = entries[i]
		local store = entry.store
		local settings = type(store.settings) == "table" and store.settings or {}
		local links = type(store.links) == "table" and store.links or {}
		sb[#sb + 1] = ("\t[%q] = {"):format(entry.keyText)
		sb[#sb + 1] = "\t\tsettings = {"
		sb[#sb + 1] = ("\t\t\tlightMultiplier = %s,"):format(F(settings.lightMultiplier or 1.6))
		sb[#sb + 1] = "\t\t},"
		sb[#sb + 1] = "\t\tlinks = {"
		for j = 1, #links do
			local link = links[j]
			sb[#sb + 1] = (
				"\t\t\t{ id = %q, sourceObjectId = %q, lieuId = %q, modelLabel = %q, lieuLabel = %q, enabled = %s },"
			):format(
				tostring(link.id or ("hover_" .. j)),
				tostring(link.sourceObjectId or ""),
				tostring(link.lieuId or ""),
				tostring(link.modelLabel or ""),
				tostring(link.lieuLabel or ""),
				(link.enabled ~= false) and "true" or "false"
			)
		end
		sb[#sb + 1] = "\t\t},"
		sb[#sb + 1] = "\t},"
	end
	sb[#sb + 1] = "}"
	return table.concat(sb, "\n")
end
