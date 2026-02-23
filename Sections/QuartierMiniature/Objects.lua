local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.Objects = QM.Objects or { version = 1, maps = {} }
local Objects = QM.Objects

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

local function NormalizeAngle360(v)
	local n = tonumber(v) or 0
	n = n % 360
	if n < 0 then
		n = n + 360
	end
	return n
end

local function NormalizeModelPath(path)
	local p = tostring(path or "")
	p = p:gsub("^%s+", ""):gsub("%s+$", "")
	if (#p >= 2) and ((p:sub(1, 1) == "\"" and p:sub(-1) == "\"") or (p:sub(1, 1) == "'" and p:sub(-1) == "'")) then
		p = p:sub(2, -2)
	end
	-- WoW model APIs are usually safer with backslashes.
	p = p:gsub("/", "\\")
	return p
end

local function NormalizeTextId(v)
	local s = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if (#s >= 2) and ((s:sub(1, 1) == "\"" and s:sub(-1) == "\"") or (s:sub(1, 1) == "'" and s:sub(-1) == "'")) then
		s = s:sub(2, -2)
	end
	return s
end

local function NormalizeLabel(v)
	return tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function FiniteOrDefault(v, fallback)
	local n = tonumber(v)
	if not n then
		return fallback
	end
	if n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return n
end

function Objects.EnsureMapStore(mapId)
	Objects.maps = type(Objects.maps) == "table" and Objects.maps or {}
	local key = tostring(mapId or "default")
	Objects.maps[key] = type(Objects.maps[key]) == "table" and Objects.maps[key] or {}
	local store = Objects.maps[key]
	store.settings = type(store.settings) == "table" and store.settings or {}
	store.settings.ambientLighting = type(store.settings.ambientLighting) == "table" and store.settings.ambientLighting
		or {}
	store.settings.hoverLightMultiplier = Clamp(tonumber(store.settings.hoverLightMultiplier) or 1.6, 1.0, 3.0)
	store.objects = type(store.objects) == "table" and store.objects or {}
	return store
end

function Objects.NormalizeObject(input)
	if type(input) ~= "table" then
		return nil
	end
	local function Trim(s)
		local v = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if (#v >= 2) and ((v:sub(1, 1) == "\"" and v:sub(-1) == "\"") or (v:sub(1, 1) == "'" and v:sub(-1) == "'")) then
			v = v:sub(2, -2)
		end
		return v
	end
	local sourceType = tostring(input.sourceType or "")
	local sourceValue = input.sourceValue
	local sourceFileId = tonumber(input.sourceFileId)
	if sourceType == "" then
		local probe = input.modelInput
		if probe == nil then
			probe = input.model
		end
		if probe == nil then
			probe = input.sourceValue
		end
		if type(probe) == "number" then
			sourceType = "fileid"
			sourceValue = math.floor(probe)
		elseif type(probe) == "string" then
			local s = Trim(probe)
			-- Support "fileid;path" input from listfiles.
			local left, right = s:match("^([^;]+);(.+)$")
			if left and right then
				local leftNum = tonumber(Trim(left))
				if leftNum and leftNum > 0 then
					sourceFileId = math.floor(leftNum)
				end
				local pathCandidate = Trim(right)
				if pathCandidate ~= "" then
					sourceType = "path"
					sourceValue = pathCandidate
				else
					s = Trim(left)
				end
			end
			if sourceType ~= "path" then
				local n = tonumber(s)
				if n and n > 0 and s:match("^%d+$") then
					sourceType = "fileid"
					sourceValue = math.floor(n)
				elseif s ~= "" then
					sourceType = "path"
					sourceValue = s
				end
			end
		end
	end
	if sourceType ~= "fileid" and sourceType ~= "path" then
		return nil
	end
	if sourceType == "fileid" then
		sourceValue = tonumber(sourceValue)
		if not sourceValue or sourceValue <= 0 then
			return nil
		end
		sourceValue = math.floor(sourceValue)
	else
		sourceValue = NormalizeModelPath(sourceValue)
		if sourceValue == "" then
			return nil
		end
		if sourceValue:lower():match("%.wmo$") then
			return nil
		end
	end

	local kind = tostring(input.kind or "auto"):lower()
	if kind == "wmo" then
		kind = "auto"
	end
	if kind ~= "auto" and kind ~= "m2" then
		kind = "auto"
	end

	local rawX = tonumber(input.x)
	local rawY = tonumber(input.y)
	local hasU = input.u ~= nil
	local hasV = input.v ~= nil
	local legacyAnchor = (not hasU) and (not hasV) and rawX and rawY and rawX >= 0 and rawX <= 1 and rawY >= 0 and rawY <= 1

	local u = Clamp(tonumber(input.u) or 0.5, 0, 1)
	local v = Clamp(tonumber(input.v) or 0.5, 0, 1)
	local x = FiniteOrDefault(rawX, 0)
	local y = FiniteOrDefault(rawY, 0)
	if legacyAnchor then
		u = rawX
		v = rawY
		x = 0
		y = 0
	end

	return {
		id = tostring(input.id or ""),
		displayName = (NormalizeLabel(input.displayName or input.name) ~= "") and NormalizeLabel(input.displayName or input.name)
			or nil,
		kind = kind,
		sourceType = sourceType,
		sourceValue = sourceValue,
		sourceFileId = (sourceFileId and sourceFileId > 0) and math.floor(sourceFileId) or nil,
		u = u,
		v = v,
		x = x,
		y = y,
		z = FiniteOrDefault(input.z, 0),
		yaw = NormalizeAngle360(input.yaw),
		pitch = NormalizeAngle360(input.pitch or 0),
		roll = NormalizeAngle360(input.roll),
		scale = math.max(0.0001, FiniteOrDefault(input.scale, 1)),
		objectExposure = Clamp(FiniteOrDefault(input.objectExposure, 1), 0.1, 5.0),
		objectColorR = Clamp(FiniteOrDefault(input.objectColorR, 1), 0.0, 2.0),
		objectColorG = Clamp(FiniteOrDefault(input.objectColorG, 1), 0.0, 2.0),
		objectColorB = Clamp(FiniteOrDefault(input.objectColorB, 1), 0.0, 2.0),
		size = math.max(1, FiniteOrDefault(input.size, 96)),
		enabled = input.enabled ~= false,
		hoverLinkId = (NormalizeTextId(input.hoverLinkId) ~= "") and NormalizeTextId(input.hoverLinkId) or nil,
	}
end

function Objects.BuildExportText(mapId)
	Objects.maps = type(Objects.maps) == "table" and Objects.maps or {}
	Objects.EnsureMapStore(mapId)
	local sb = {}
	local entries = {}
	for k, v in pairs(Objects.maps) do
		entries[#entries + 1] = {
			keyText = tostring(k),
			store = v,
		}
	end
	table.sort(entries, function(a, b)
		return a.keyText < b.keyText
	end)

	sb[#sb + 1] = "local ADDON, ns = ..."
	sb[#sb + 1] = ""
	sb[#sb + 1] = "ns.QuartierMiniature = ns.QuartierMiniature or {}"
	sb[#sb + 1] = "local QM = ns.QuartierMiniature"
	sb[#sb + 1] = ""
	sb[#sb + 1] = "QM.Objects = QM.Objects or {}"
	sb[#sb + 1] = ("QM.Objects.version = %s"):format(tostring(tonumber(Objects.version) or 1))
	sb[#sb + 1] = "QM.Objects.maps = {"
	for e = 1, #entries do
		local entry = entries[e]
		local key = entry.keyText
		local store = entry.store
		sb[#sb + 1] = ("\t[%q] = {"):format(key)
		local cfg = (QM and QM.Config and QM.Config.objects) or {}
		local defaultTemp = tonumber(cfg.colorTemperature) or 0
		local defaultR = tonumber(cfg.lightColorR) or 1
		local defaultG = tonumber(cfg.lightColorG) or 1
		local defaultB = tonumber(cfg.lightColorB) or 1
		local defaultLum = tonumber(cfg.lightLuminance) or 1
		local defaultHoverLum = 1.6
		local settings = type(store.settings) == "table" and store.settings or {}
		local ambient = type(settings.ambientLighting) == "table" and settings.ambientLighting or nil
		sb[#sb + 1] = "\t\tsettings = {"
		sb[#sb + 1] = "\t\t\tambientLighting = {"
		sb[#sb + 1] = ("\t\t\t\tcolorTemperature = %s,"):format(F(tonumber(ambient and ambient.colorTemperature) or defaultTemp))
		sb[#sb + 1] = ("\t\t\t\tlightColorR = %s,"):format(F(tonumber(ambient and ambient.lightColorR) or defaultR))
		sb[#sb + 1] = ("\t\t\t\tlightColorG = %s,"):format(F(tonumber(ambient and ambient.lightColorG) or defaultG))
		sb[#sb + 1] = ("\t\t\t\tlightColorB = %s,"):format(F(tonumber(ambient and ambient.lightColorB) or defaultB))
		sb[#sb + 1] = ("\t\t\t\tlightLuminance = %s,"):format(F(tonumber(ambient and ambient.lightLuminance) or defaultLum))
		sb[#sb + 1] = "\t\t\t},"
		sb[#sb + 1] = ("\t\t\thoverLightMultiplier = %s,"):format(
			F(tonumber(settings.hoverLightMultiplier) or defaultHoverLum)
		)
		sb[#sb + 1] = "\t\t},"
		sb[#sb + 1] = "\t\tobjects = {"
		local objs = type(store.objects) == "table" and store.objects or {}
		for i = 1, #objs do
			local o = objs[i]
			local v
			if o.sourceType == "fileid" then
				v = tostring(math.floor(tonumber(o.sourceValue) or 0))
			else
				v = string.format("%q", tostring(o.sourceValue or ""))
			end
			sb[#sb + 1] = ("\t\t\t{ id = %q, displayName = %s, kind = %q, sourceType = %q, sourceValue = %s, sourceFileId = %s, u = %s, v = %s, x = %s, y = %s, z = %s, yaw = %s, pitch = %s, roll = %s, scale = %s, objectExposure = %s, objectColorR = %s, objectColorG = %s, objectColorB = %s, size = %d, enabled = %s, hoverLinkId = %s },"):format(
				tostring(o.id or ("obj_" .. i)),
				(tostring(o.displayName or "") ~= "") and string.format("%q", tostring(o.displayName)) or "nil",
				tostring(o.kind or "auto"),
				tostring(o.sourceType or "path"),
				v,
				tostring((tonumber(o.sourceFileId) and tonumber(o.sourceFileId) > 0) and math.floor(tonumber(o.sourceFileId)) or "nil"),
				F(o.u),
				F(o.v),
				F(o.x),
				F(o.y),
				F(o.z),
				F(o.yaw),
				F(o.pitch),
				F(o.roll),
				F(o.scale),
				F(o.objectExposure),
				F(o.objectColorR),
				F(o.objectColorG),
				F(o.objectColorB),
				math.floor(tonumber(o.size) or 96),
				(o.enabled ~= false) and "true" or "false",
				(tostring(o.hoverLinkId or "") ~= "") and string.format("%q", tostring(o.hoverLinkId)) or "nil"
			)
		end
		sb[#sb + 1] = "\t\t},"
		sb[#sb + 1] = "\t},"
	end
	sb[#sb + 1] = "}"
	return table.concat(sb, "\n")
end
