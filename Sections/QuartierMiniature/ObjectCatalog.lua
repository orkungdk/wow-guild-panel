local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.ObjectCatalog = QM.ObjectCatalog or { version = 1, entries = {} }
local Catalog = QM.ObjectCatalog

local _built = false
local _entries = {}
local _root = nil

local function Trim(s)
	return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function UnquoteCsvToken(s)
	local token = Trim(s)
	if token:sub(1, 1) == '"' and token:sub(-1) == '"' and #token >= 2 then
		token = token:sub(2, -2):gsub('""', '"')
	end
	return token
end

local function SplitPath(path)
	local parts = {}
	local p = tostring(path or ""):gsub("\\", "/")
	for seg in p:gmatch("([^/]+)") do
		if seg and seg ~= "" then
			parts[#parts + 1] = seg
		end
	end
	return parts
end

local function ParseEntry(raw)
	if type(raw) == "table" then
		local fid = tonumber(raw.fileId or raw.id)
		local path = Trim(raw.path)
		if not (fid and fid > 0 and path ~= "") then
			return nil
		end
		local lower = path:lower()
		if not lower:match("%.m2$") then
			return nil
		end
		local parts = SplitPath(path)
		local name = parts[#parts] or path
		local folders = {}
		for i = 1, math.max(0, #parts - 1) do
			folders[#folders + 1] = parts[i]
		end
		return {
			fileId = math.floor(fid),
			path = path,
			name = name,
			key = tostring(math.floor(fid)) .. ";" .. path,
			folders = folders,
		}
	end
	if type(raw) ~= "string" then
		return nil
	end
	local line = Trim(raw)
	if line == "" then
		return nil
	end
	line = line:gsub(",$", "")
	local idTxt, path = line:match("^\"?(%d+)\"?%s*;%s*(.-)%s*$")
	if not (idTxt and path and path ~= "") then
		return nil
	end
	path = UnquoteCsvToken(path)
	local fid = tonumber(idTxt)
	if not (fid and fid > 0) then
		return nil
	end
	local lower = path:lower()
	if not lower:match("%.m2$") then
		return nil
	end
	local parts = SplitPath(path)
	local name = parts[#parts] or path
	local folders = {}
	for i = 1, math.max(0, #parts - 1) do
		folders[#folders + 1] = parts[i]
	end
	return {
		fileId = math.floor(fid),
		path = path,
		name = name,
		key = tostring(math.floor(fid)) .. ";" .. path,
		folders = folders,
	}
end

local function Build()
	if _built then
		return
	end
	Catalog.entries = type(Catalog.entries) == "table" and Catalog.entries or {}
	_entries = {}
	for i = 1, #Catalog.entries do
		local parsed = ParseEntry(Catalog.entries[i])
		if parsed then
			_entries[#_entries + 1] = parsed
		end
	end
	table.sort(_entries, function(a, b)
		if a.path == b.path then
			return a.fileId < b.fileId
		end
		return a.path < b.path
	end)

	_root = { folders = {}, files = {} }
	for i = 1, #_entries do
		local e = _entries[i]
		local node = _root
		for j = 1, #e.folders do
			local folder = e.folders[j]
			node.folders[folder] = node.folders[folder] or { folders = {}, files = {}, name = folder }
			node = node.folders[folder]
		end
		node.files[#node.files + 1] = e
	end
	_built = true
end

local function GetNode(pathParts)
	Build()
	local node = _root
	local parts = type(pathParts) == "table" and pathParts or {}
	for i = 1, #parts do
		local key = tostring(parts[i] or "")
		if key == "" or not (node and node.folders and node.folders[key]) then
			return nil
		end
		node = node.folders[key]
	end
	return node
end

function Catalog.GetEntries()
	Build()
	return _entries
end

function Catalog.GetDefaultEntry()
	Build()
	return _entries[1]
end

function Catalog.ListNode(pathParts)
	local node = GetNode(pathParts)
	if not node then
		return {}, {}
	end
	local folders = {}
	for name, _ in pairs(node.folders) do
		folders[#folders + 1] = name
	end
	table.sort(folders)
	local files = {}
	for i = 1, #node.files do
		files[#files + 1] = node.files[i]
	end
	table.sort(files, function(a, b)
		if a.name == b.name then
			return a.fileId < b.fileId
		end
		return a.name < b.name
	end)
	return folders, files
end
