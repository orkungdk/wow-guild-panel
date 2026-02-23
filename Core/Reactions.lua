local ADDON, ns = ...

ns.Reactions = ns.Reactions or {}
local Reactions = ns.Reactions

local REACTION_ORDER = {
	"gg",
	"|DIV|",
	"greetings",
	"wellplayed",
	"thanks",
	"bye",
	"|DIV|",
	"wow",
	"oops",
	"excuse",
	"|DIV|",
	"threaten",
}

local function Catalog()
	return (ns.Emotes and ns.Emotes.Catalog) or {}
end

function Reactions.Sequence()
	local seq, seen = {}, {}
	local cat = Catalog()

	for _, k in ipairs(REACTION_ORDER) do
		if k == "|DIV|" then
			table.insert(seq, { divider = true })
		else
			local def = cat[k]
			if def then
				table.insert(seq, { key = k, def = def })
				seen[k] = true
			end
		end
	end

	local rest = {}
	for k, def in pairs(cat) do
		if not seen[k] then
			table.insert(rest, { key = k, def = def })
		end
	end
	table.sort(rest, function(a, b)
		local oa = tonumber(a.def and a.def.order) or math.huge
		local ob = tonumber(b.def and b.def.order) or math.huge
		if oa ~= ob then
			return oa < ob
		end
		local la = (a.def and a.def.label) or a.key
		local lb = (b.def and b.def.label) or b.key
		return tostring(la) < tostring(lb)
	end)
	for _, node in ipairs(rest) do
		table.insert(seq, node)
	end

	return seq
end

local function ResolveOptions(isTestOrOpts)
	if type(isTestOrOpts) == "table" then
		return isTestOrOpts
	end
	return { test = isTestOrOpts == true }
end

local function BuildNewsContext(news, typeLabel)
	if type(news) ~= "table" then
		return nil
	end
	local ctx = { source = "news" }
	local hasData = false
	local icon = news.icon
	if icon ~= nil and icon ~= "" then
		ctx.newsIcon = icon
		hasData = true
	end
	local newsType = tostring(news.type or news.typ or "")
	if newsType ~= "" then
		ctx.newsType = newsType
		hasData = true
	end
	local label = tostring(typeLabel or news.title or "")
	if label ~= "" then
		ctx.newsTypeLabel = label
		hasData = true
	end
	local title = tostring(news.title or "")
	if title ~= "" then
		ctx.newsTitle = title
		hasData = true
	end
	if not hasData then
		return nil
	end
	return ctx
end

local function HasAddonPrefs(targetFull)
	if not (ns and ns.DB and ns.DB.GetGuildUID and ns.DB.GetGuildMemberPrefs and ns.Data and ns.Data.ResolvePlayerUID) then
		return false
	end
	local gid = ns.DB:GetGuildUID()
	if not gid or gid == "" then
		return false
	end
	local guid = nil
	if ns.Targets and ns.Targets.ResolveForFull then
		local _, _, rec = ns.Targets.ResolveForFull(targetFull)
		if rec and rec.guid and rec.guid ~= "" then
			guid = rec.guid
		end
	end
	local uid = ns.Data.ResolvePlayerUID(gid, targetFull, guid)
	if not uid or uid == "" then
		return false
	end
	return ns.DB:GetGuildMemberPrefs(gid, uid) ~= nil
end

function Reactions.AddSubmenu(root, targetFull, isTestOrOpts)
	if not root or not targetFull or targetFull == "" then
		return false
	end
	if not (ns and ns.Emotes and ns.Emotes.Catalog) then
		return false
	end

	local opts = ResolveOptions(isTestOrOpts)
	local isTest = opts.test == true
	if not isTest and not opts.allowNoPrefs and not HasAddonPrefs(targetFull) then
		return false
	end
	local label = opts.label or (isTest and "Tester une réaction" or "Envoyer une réaction")
	local menu = root.CreateButton and root:CreateButton(label) or nil
	if not menu then
		return false
	end

	local newsContext = BuildNewsContext(opts.news, opts.newsTypeLabel)
	for _, node in ipairs(Reactions.Sequence()) do
		if node.divider then
			if menu.CreateDivider then
				menu:CreateDivider()
			end
		else
			local nodeLabel = (node.def and node.def.label) or node.key
			local child = menu:CreateButton(nodeLabel, function()
				if isTest then
					if ns.Emotes and ns.Emotes.DebugLocal then
						ns.Emotes.DebugLocal(node.key, UnitName and UnitName("player") or targetFull, {
							context = newsContext,
						})
					end
				elseif ns.Emotes and ns.Emotes.Send then
					ns.Emotes.Send(targetFull, node.key, { context = newsContext })
				end
			end)
			if node.def and node.def.icon and child and child.SetIcon then
				child:SetIcon(node.def.icon)
			end
		end
	end

	return true
end
