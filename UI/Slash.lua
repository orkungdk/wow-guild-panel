local ADDON, ns = ...

local function RegisterCommand(command)
	if SecureCmdList and SecureCmdList.Add then
		SecureCmdList.Add(command)
		return true
	end
	if Blizzard_RegisterSlashCommand then
		Blizzard_RegisterSlashCommand(command.name, command.commands, command.handler)
		return true
	end
	-- Fallback standard WoW (SLASH_ + SlashCmdList)
	if type(command.name) == "string" and type(command.commands) == "table" and type(command.handler) == "function" then
		for i = 1, #command.commands do
			_G["SLASH_" .. command.name .. i] = command.commands[i]
		end
		SlashCmdList[command.name] = command.handler
		return true
	end
	return false
end

RegisterCommand({
	name = "WOWGUILDE",
	commands = { "/wg" },
	handler = function()
		if ns and ns.UI and ns.UI.Toggle then
			ns.UI.Toggle()
		end
	end,
})

RegisterCommand({
	name = "WOWGUILDECLEAR",
	commands = { "/wgclear" },
	handler = function()
		local guildUID = ns.DB and ns.DB.GetGuildUID and ns.DB:GetGuildUID() or nil
		if not guildUID then
			return
		end
		WoWGuildeDB = WoWGuildeDB or {}
		WoWGuildeDB.guilds = WoWGuildeDB.guilds or {}
		local g = WoWGuildeDB.guilds[guildUID]
		if not g then
			return
		end
		if g.statistics then
			g.statistics.players = {}
			g.statistics.updatedAt = 0
		end
		if g.news then
			g.news.items = {}
			g.news.updatedAt = 0
			g.news.lastClean = 0
			g.news.nextId = 0
		end
		if g.newsAnalyste then
			g.newsAnalyste.modules = {}
		end
		if ns.Sections and ns.Sections.SocialFrame and ns.Sections.SocialFrame.ClearNews then
			ns.Sections.SocialFrame:ClearNews()
		end
		if ns.Data and ns.Data.Journalist and ns.Data.Journalist.TickNow then
			ns.Data.Journalist.TickNow()
		end
	end,
})

RegisterCommand({
	name = "WOWGUILDEBTN",
	commands = { "/wgbtn" },
	handler = function()
		if ns and ns.GB and ns.GB.ForceCreate then
			ns.GB.ForceCreate()
		elseif ns and ns.GB and ns.GB.Init then
			ns.GB.Init()
		end
	end,
})

RegisterCommand({
	name = "WOWGUILDETEST",
	commands = { "/wgtest" },
	handler = function(msg)
		if not (ns and ns.Prefs and ns.Prefs.SetSocial) then
			return
		end
		local v = tonumber(tostring(msg or ""):match("(%d+%.?%d*)"))
		if not v then
			ns.Prefs.SetSocial("debugProgressPct", nil)
		else
			if v < 0 then
				v = 0
			elseif v > 100 then
				v = 100
			end
			ns.Prefs.SetSocial("debugProgressPct", v)
		end
		if ns.UI and ns.UI.Refresh then
			ns.UI.Refresh()
		end
	end,
})

RegisterCommand({
	name = "WOWGUILDEROSTER",
	commands = { "/wgroster", "/wgrosteur", "/wgrand" },
	handler = function(msg)
		if not (ns and ns.Rosteur and ns.Rosteur.CreateRandomSignupsFromGuild) then
			return
		end
		msg = tostring(msg or "")
		local token = msg:lower():match("^(%S+)")
		local templateKey = "raid20"
		if token == "10" or token == "raid10" then
			templateKey = "raid10"
		elseif token == "20" or token == "raid20" then
			templateKey = "raid20"
		elseif token == "custom" then
			templateKey = "custom"
		end
		local ok, info = ns.Rosteur.CreateRandomSignupsFromGuild(nil, templateKey)
		if ok then
			print("|cffffd100[WoW Guild]|r Rastgele kayitlar olusturuldu (" .. tostring(info or 0) .. " karakter).")
		else
			local reason = info
			local msgOut = "Rastgele kayitlar olusturulamadi."
			if reason == "noguild" then
				msgOut = "Etkin guild yok."
			elseif reason == "empty" then
				msgOut = "Guild karakteri bulunamadi."
			end
			print("|cffffd100[WoW Guild]|r " .. msgOut)
		end
	end,
})

RegisterCommand({
	name = "WOWGUILDEDROP",
	commands = { "/wgdrop" },
	handler = function(msg)
		if not (ns and ns.UI and ns.UI.NewsDrop and ns.UI.NewsDrop.Show) then
			return
		end
		msg = tostring(msg or "")
		local iconArg, soundArg = msg:match("^(%S+)%s*(%S*)$")
		local icon = iconArg and iconArg ~= "" and iconArg or nil
		local soundId = tonumber(soundArg)
		if not soundId and ns.UI.NewsDrop.DEFAULT_SOUND_ID then
			soundId = ns.UI.NewsDrop.DEFAULT_SOUND_ID
		end
		ns.UI.NewsDrop.Show(icon, soundId)
	end,
})
