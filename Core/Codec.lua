local ADDON, ns = ...

ns.Codec = ns.Codec or {}
local Codec = ns.Codec

Codec.B64_PREFIX = Codec.B64_PREFIX or "b64:"

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64bytes = {}
for i = 1, #b64chars do
	b64bytes[b64chars:sub(i, i)] = i - 1
end

function Codec.B64Encode(data)
	data = tostring(data or "")
	if data == "" then
		return ""
	end
	local t = {}
	for i = 1, #data, 3 do
		local a = data:byte(i) or 0
		local b = data:byte(i + 1) or 0
		local c = data:byte(i + 2) or 0
		local n = a * 65536 + b * 256 + c
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		local o1 = b64chars:sub(c1 + 1, c1 + 1)
		local o2 = b64chars:sub(c2 + 1, c2 + 1)
		local o3 = b64chars:sub(c3 + 1, c3 + 1)
		local o4 = b64chars:sub(c4 + 1, c4 + 1)
		if i + 1 > #data then
			o3 = "="
			o4 = "="
		elseif i + 2 > #data then
			o4 = "="
		end
		t[#t + 1] = o1 .. o2 .. o3 .. o4
	end
	return table.concat(t)
end

function Codec.B64Decode(data)
	data = tostring(data or ""):gsub("[^%w%+/%=]", "")
	if data == "" then
		return ""
	end
	local t = {}
	local i = 1
	while i <= #data do
		local c1 = b64bytes[data:sub(i, i)]
		i = i + 1
		local c2 = b64bytes[data:sub(i, i)]
		i = i + 1
		local c3c = data:sub(i, i)
		i = i + 1
		local c4c = data:sub(i, i)
		i = i + 1
		if c1 == nil or c2 == nil then
			break
		end
		local c3 = (c3c ~= "=") and b64bytes[c3c] or 0
		local c4 = (c4c ~= "=") and b64bytes[c4c] or 0
		local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
		local a = math.floor(n / 65536) % 256
		local b = math.floor(n / 256) % 256
		local c = n % 256
		t[#t + 1] = string.char(a)
		if c3c ~= "=" then
			t[#t + 1] = string.char(b)
		end
		if c4c ~= "=" then
			t[#t + 1] = string.char(c)
		end
	end
	return table.concat(t)
end

function Codec.HasB64Prefix(value)
	return type(value) == "string" and value:sub(1, #Codec.B64_PREFIX) == Codec.B64_PREFIX
end

function Codec.StripB64Prefix(value)
	if type(value) ~= "string" then
		return value
	end
	if Codec.HasB64Prefix(value) then
		return value:sub(#Codec.B64_PREFIX + 1)
	end
	return value
end

function Codec.EncodeB64Prefixed(value)
	if type(value) ~= "string" or value == "" then
		return value
	end
	if Codec.HasB64Prefix(value) then
		return value
	end
	return Codec.B64_PREFIX .. Codec.B64Encode(value)
end

function Codec.DecodeB64Prefixed(value)
	if type(value) ~= "string" or value == "" then
		return value
	end
	if not Codec.HasB64Prefix(value) then
		return value
	end
	local raw = Codec.B64Decode(value:sub(#Codec.B64_PREFIX + 1))
	if not raw or raw == "" then
		return value
	end
	return raw
end
