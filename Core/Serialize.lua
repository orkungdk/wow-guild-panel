local ADDON, ns = ...

ns.Serialize = ns.Serialize or {}
local Serialize = ns.Serialize

function Serialize.Escape(s)
	s = tostring(s or "")
	s = s:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub('"', '\\"')
	return s
end

function Serialize.Value(v, sb)
	local t = type(v)
	if t == "string" then
		sb[#sb + 1] = '"' .. Serialize.Escape(v) .. '"'
	elseif t == "number" or t == "boolean" then
		sb[#sb + 1] = tostring(v)
	elseif t == "table" then
		sb[#sb + 1] = "{"
		local first = true
		for k, vv in pairs(v) do
			if not first then
				sb[#sb + 1] = ","
			end
			first = false
			local key = type(k) == "string" and ('["' .. Serialize.Escape(k) .. '"]') or ("[" .. tostring(k) .. "]")
			sb[#sb + 1] = key .. "="
			Serialize.Value(vv, sb)
		end
		sb[#sb + 1] = "}"
	else
		sb[#sb + 1] = "nil"
	end
end

function Serialize.Table(t)
	local sb = { "return " }
	Serialize.Value(t, sb)
	return table.concat(sb)
end

function Serialize.KV(tbl)
	local sb = { "return {" }
	local first = true
	for k, v in pairs(tbl or {}) do
		if not first then
			sb[#sb + 1] = ","
		end
		first = false
		local key = type(k) == "string" and ('["' .. Serialize.Escape(k) .. '"]') or ("[" .. tostring(k) .. "]")
		sb[#sb + 1] = key .. "="
		Serialize.Value(v, sb)
	end
	sb[#sb + 1] = "}"
	return table.concat(sb)
end

function Serialize.LoadTable(src, env, maxLen)
	if type(src) ~= "string" or src == "" then
		return nil, "empty"
	end
	if maxLen and #src > maxLen then
		return nil, "too_large"
	end
	local fn, err = loadstring(src)
	if not fn then
		return nil, err
	end
	setfenv(fn, env or {})
	local ok, out = pcall(fn)
	if not ok then
		return nil, "exec"
	end
	if type(out) ~= "table" then
		return nil, "type"
	end
	return out
end

function Serialize.Deserialize(src, maxLen)
	local out = Serialize.LoadTable(src, {}, maxLen)
	return out
end
