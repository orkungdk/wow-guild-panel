-- ==========================================================
-- EventBus stub (chargement ultra-tot pour capturer les listeners)
-- ==========================================================

local ADDON, ns = ...

ns.EventBus = ns.EventBus or {}
local Bus = ns.EventBus

Bus._listeners = Bus._listeners or {}

local function AddListener(event, handler, once)
	if type(event) ~= "string" or event == "" then
		return false
	end
	if type(handler) ~= "function" then
		return false
	end

	local list = Bus._listeners[event]
	if not list then
		list = {}
		Bus._listeners[event] = list
	end

	table.insert(list, { fn = handler, once = once == true })
	return true
end

if not Bus.On then
	function Bus.On(event, handler)
		return AddListener(event, handler, false)
	end
end

if not Bus.Once then
	function Bus.Once(event, handler)
		return AddListener(event, handler, true)
	end
end

if not Bus.Off then
	function Bus.Off(event, handler)
		local list = Bus._listeners[event]
		if not list or #list == 0 then
			return false
		end

		if handler == nil then
			Bus._listeners[event] = nil
			return true
		end

		for i = #list, 1, -1 do
			if list[i] and list[i].fn == handler then
				table.remove(list, i)
			end
		end

		if #list == 0 then
			Bus._listeners[event] = nil
		end

		return true
	end
end

if not Bus.Emit then
	function Bus.Emit(event, ...)
		local list = Bus._listeners[event]
		if not list or #list == 0 then
			return
		end

		local snapshot = {}
		for i = 1, #list do
			snapshot[i] = list[i]
		end

		for i = 1, #snapshot do
			local entry = snapshot[i]
			if entry and entry.fn then
				local ok = pcall(entry.fn, event, ...)
				if entry.once then
					Bus.Off(event, entry.fn)
				end
				if not ok then
					-- silencieux: handler en phase pre-boot
				end
			end
		end
	end
end
