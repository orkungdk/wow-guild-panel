local ADDON, ns = ...
ns.GB = ns.GB or {}

local GB = ns.GB
local EventBus = ns.EventBus

-- ====== Utilitaires Communities (optionnel, non bloquant) ======
local function IsCommunitiesLoaded()
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded("Blizzard_Communities")
	end
	if type(IsAddOnLoaded) == "function" then
		return IsAddOnLoaded("Blizzard_Communities")
	end
	return false
end

local function UpdateVisibility(tab)
	if not tab or not CommunitiesFrame then
		return
	end

	if CommunitiesFrame:IsShown() then
		local clubId = CommunitiesFrame:GetSelectedClubId()
		if clubId then
			local info = C_Club.GetClubInfo(clubId)
			if info and info.clubType == Enum.ClubType.Guild then
				tab:Show()
				return
			end
		end
	end

	tab:Hide()
end

-- ====== Chat : pseudo BDD + couleur de classe + menu ======
local function GetPseudoRecForSender(sender)
	if not sender or sender == "" or not ns or not ns.Utils then
		return nil
	end
	local cache = ns.Utils.PSEUDO_CACHE
	if not cache then
		return nil
	end
	local rec = cache[sender]
	if not rec and Ambiguate then
		rec = cache[Ambiguate(sender, "none")]
	end
	if not rec and IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
		local senderShort = Ambiguate and Ambiguate(sender, "none") or sender
		local n = GetNumGuildMembers() or 0
		for i = 1, n do
			local name, _, _, _, _, _, note, _, _, _, classFileName = GetGuildRosterInfo(i)
			if name and name ~= "" then
				local full = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name
				local short = Ambiguate and Ambiguate(full, "none") or full
				if
					sender == full
					or sender == name
					or senderShort == full
					or senderShort == short
					or sender == short
				then
					local alias
					if ns.Utils.AliasFromNote then
						alias = ns.Utils.AliasFromNote(note)
					elseif ns.Utils.ParsePseudo then
						alias = (ns.Utils.ParsePseudo(note, name))
					end
					if alias and alias ~= "" then
						rec = { alias = alias, class = classFileName }
						cache[full] = rec
						cache[short] = rec
						cache[name] = rec
						break
					end
				end
			end
		end
	end
	return rec
end

local function BuildPseudoChatLink(sender)
	local rec = GetPseudoRecForSender(sender)
	if not rec or not rec.alias or rec.alias == "" then
		return nil
	end
	local color = (ns.Utils and ns.Utils.GetClassColorHexSafe and ns.Utils.GetClassColorHexSafe(rec.class))
		or "|cffffffff"
	local display = ("%s[%s]|r"):format(color, rec.alias)
	return ("|Hwg:%s|h%s|h"):format(sender, display)
end

local function GetPseudoAliasForSender(sender)
	local rec = GetPseudoRecForSender(sender)
	if not rec or not rec.alias or rec.alias == "" then
		return nil
	end
	return rec.alias
end

local function AliasKey(name)
	if ns and ns.Utils and ns.Utils.PseudoKey then
		return ns.Utils.PseudoKey(name)
	end
	return tostring(name or ""):lower()
end

local function GetDropdownPlayerName(dropdown)
	if dropdown and dropdown.name and dropdown.name ~= "" then
		return dropdown.name
	end
	if dropdown and dropdown.unit and UnitName then
		local n, r = UnitName(dropdown.unit)
		if n and n ~= "" then
			if r and r ~= "" then
				return n .. "-" .. r
			end
			return n
		end
	end
	return nil
end

local function IsGuildMemberFull(name)
	if not name or name == "" then
		return false
	end
	if not (IsInGuild and IsInGuild()) or not GetNumGuildMembers or not GetGuildRosterInfo then
		return false
	end
	local short = Ambiguate and Ambiguate(name, "none") or name
	local n = GetNumGuildMembers() or 0
	for i = 1, n do
		local rosterName = GetGuildRosterInfo(i)
		if rosterName and rosterName ~= "" then
			local full = (ns.FullFromRosterName and ns.FullFromRosterName(rosterName)) or rosterName
			local rShort = Ambiguate and Ambiguate(full, "none") or full
			if name == full or name == rosterName or short == full or short == rShort or name == rShort then
				return true
			end
		end
	end
	return false
end

local function SetupChatPseudoHooks()
	if GB._chatPseudoSetup then
		return
	end
	GB._chatPseudoSetup = true
	GB._aliasToSender = GB._aliasToSender or {}

	if ChatFrame_AddMessageEventFilter then
		local function filter(_, _, msg, sender, ...)
			if not sender or sender == "" then
				return false
			end
			local alias = GetPseudoAliasForSender(sender)
			if not alias then
				return false
			end
			local key = AliasKey(alias)
			if key ~= "" then
				GB._aliasToSender[key] = sender
			end
			return false, msg, alias, ...
		end
		local events = {
			"CHAT_MSG_SAY",
			"CHAT_MSG_YELL",
			"CHAT_MSG_EMOTE",
			"CHAT_MSG_TEXT_EMOTE",
			"CHAT_MSG_WHISPER",
			"CHAT_MSG_WHISPER_INFORM",
			"CHAT_MSG_PARTY",
			"CHAT_MSG_PARTY_LEADER",
			"CHAT_MSG_RAID",
			"CHAT_MSG_RAID_LEADER",
			"CHAT_MSG_RAID_WARNING",
			"CHAT_MSG_INSTANCE_CHAT",
			"CHAT_MSG_INSTANCE_CHAT_LEADER",
			"CHAT_MSG_GUILD",
			"CHAT_MSG_OFFICER",
			"CHAT_MSG_GUILD_ACHIEVEMENT",
			"CHAT_MSG_CHANNEL",
			"CHAT_MSG_AFK",
			"CHAT_MSG_DND",
		}
		for i = 1, #events do
			ChatFrame_AddMessageEventFilter(events[i], filter)
		end
	end

	if type(SetItemRef) == "function" and not GB._origSetItemRef then
		GB._origSetItemRef = SetItemRef
		SetItemRef = function(link, text, button, chatFrame)
			local linkType, data = link:match("^([^:]+):(.+)$")
			if linkType == "player" and data and data ~= "" then
				local raw = data:match("^([^:]+)") or data
				local key = AliasKey(raw)
				local sender = key ~= "" and GB._aliasToSender and GB._aliasToSender[key] or nil
				if sender and sender ~= "" then
					local replaced = data:gsub("^[^:]+", sender, 1)
					return GB._origSetItemRef("player:" .. replaced, text, button, chatFrame)
				end
			end
			return GB._origSetItemRef(link, text, button, chatFrame)
		end
	end
end

-- ====== Picker d'icones ======
local iconChoices = {
	"Interface\\ICONS\\inv_ability_skyriding_glyph",
	"Interface\\ICONS\\achievement_legionpvp6tier1",
	"Interface\\ICONS\\inv_holiday_beerfest_beerfesttrophy",
	"Interface\\ICONS\\inv_holiday_beerfest_highmountain",
	"Interface\\ICONS\\inv_holiday_beerfest_dreanei",
	"Interface\\ICONS\\inv_misc_bag_hearthstone",
	"Interface\\ICONS\\inv_ability_holyfire_wave",
	"Interface\\ICONS\\achievement_guildperk_ladyluck_rank2",
	"Interface\\ICONS\\vas_guildnamechange",
	"Interface\\ICONS\\achievement_guildperk_fasttrack_rank2",
	"Interface\\ICONS\\artifactability_balancedruid_fullmoon",
	"Interface\\ICONS\\garrison_building_storehouse",
	"Interface\\ICONS\\inv_misc_coinbag_special",
	"Interface\\ICONS\\inv_prg_icon_puzzle13",
	"Interface\\ICONS\\inv_112_raidtrinkets_manaforge_tanktrinket1",
	"Interface\\ICONS\\spell_misc_emotionafraid",
	"Interface\\ICONS\\ui_embercourt-emoji-happy",
	"Interface\\ICONS\\ui_embercourt-emoji-veryhappy",
	"Interface\\ICONS\\spell_misc_emotionhappy",
	"Interface\\ICONS\\spell_misc_emotionsad",
}

local function CreateIconPicker(tab)
	if _G.WoWGuilde_IconPicker then
		return _G.WoWGuilde_IconPicker
	end
	if not CommunitiesFrame then
		return nil
	end

	local cols, size, padding = 5, 32, 8
	local rows = math.ceil(#iconChoices / cols)
	local width = 20 + cols * (size + padding)
	local height = 30 + rows * (size + padding)

	local picker = CreateFrame("Frame", "WoWGuilde_IconPicker", CommunitiesFrame, "BackdropTemplate")
	picker:SetSize(width, height)
	picker:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	picker:SetFrameStrata("HIGH")
	picker:Hide()

	picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	picker.title:SetPoint("TOP", 0, -8)
	picker.title:SetText("Choisissez votre icone")

	for i, icon in ipairs(iconChoices) do
		local btn = CreateFrame("Button", nil, picker)
		btn:SetSize(size, size)
		btn:SetNormalTexture(icon)
		btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

		local row = math.floor((i - 1) / cols)
		local col = (i - 1) % cols
		btn:SetPoint("TOPLEFT", 15 + col * (size + padding), -25 - row * (size + padding))

		btn:SetScript("OnClick", function()
			local chosen = icon or "Interface\\ICONS\\inv_ability_skyriding_glyph"
			if ns and ns.Prefs and ns.Prefs.SetSocial then
				ns.Prefs.SetSocial("chosenIcon", chosen)
			end
			if tab and tab.Icon then
				if ns and ns.Prefs and ns.Prefs.GetSocial then
					tab.Icon:SetTexture(ns.Prefs.GetSocial("chosenIcon", chosen))
				end
			end
			if ns and ns.UI and ns.UI.Refresh then
				ns.UI.Refresh()
			end
			picker:Hide()
			if tab and tab.SetChecked then
				tab:SetChecked(false)
			end
		end)
	end

	return picker
end

-- ====== Creation du bouton ======
local function CreateGuildButton()
	if _G.WoWGuildeTab then
		return _G.WoWGuildeTab
	end
	if not CommunitiesFrame then
		return nil
	end

	local tab = CreateFrame("CheckButton", "WoWGuildeTab", CommunitiesFrame, "CommunitiesFrameTabTemplate")
	tab.tooltip = "La vie de votre guilde"
	tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	-- Icone
	local icon
	if ns and ns.Prefs and ns.Prefs.GetSocial then
		icon = ns.Prefs.GetSocial("chosenIcon", "Interface\\ICONS\\inv_ability_skyriding_glyph")
	else
		icon = "Interface\\ICONS\\inv_ability_skyriding_glyph"
	end
	tab.Icon:SetTexture(icon)

	-- Position, on essaie sous l'onglet de roster sinon fallback
	local anchor = CommunitiesFrame.GuildInfoTab
		or CommunitiesFrame.GuildBenefitsTab
		or CommunitiesFrame.RosterTab
		or CommunitiesFrame.ChatTab
	if anchor then
		tab:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
		tab:SetFrameLevel(anchor:GetFrameLevel() + 1)
	else
		tab:SetPoint("TOPLEFT", CommunitiesFrame, "TOPLEFT", 12, -80)
		tab:SetFrameLevel(CommunitiesFrame:GetFrameLevel() + 5)
	end

	local picker = CreateIconPicker(tab)

	tab:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			if picker and picker:IsShown() then
				picker:Hide()
			elseif picker then
				picker:ClearAllPoints()
				picker:SetPoint("TOPLEFT", self, "TOPRIGHT", 10, 0)
				picker:Show()
				picker:SetFrameLevel(self:GetFrameLevel() + 10)
			end
		else
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)

			-- Ferme "Communautes", puis ouvre ta fenetre un tic plus tard
			if CommunitiesFrame and CommunitiesFrame:IsShown() and HideUIPanel then
				HideUIPanel(CommunitiesFrame)
			end

			C_Timer.After(0, function()
				if ns and ns.UI and ns.UI.Toggle then
					ns.UI.Toggle()
				elseif WoWGuilde and WoWGuilde.Toggle then
					WoWGuilde.Toggle()
				else
					print("|cff8be9fd[WoWGuilde:GB]|r Toggle introuvable, verifie le chargement de MainFrame.lua")
				end
				if ns and ns.UI and ns.UI.IsShown and self.SetChecked then
					self:SetChecked(ns.UI.IsShown())
				end
			end)
		end
	end)

	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("La vie de votre guilde", 1, 0.82, 0)
		GameTooltip:AddLine("Consultez les activites, succes et progres collectifs.", 1, 1, 1)
		GameTooltip:AddLine("<Clic droit pour modifier l'icone>", 0, 1, 0)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Decoche quand la fenetre custom se ferme
	if ns and ns.UI and ns.UI.Hide then
		ns.Utils.SafeHooksecurefunc(ns.UI, "Hide", function()
			if tab and tab.SetChecked then
				tab:SetChecked(false)
			end
		end)
	end

	-- Visibilite dynamique
	if CommunitiesFrame.SelectClub then
		ns.Utils.SafeHooksecurefunc(CommunitiesFrame, "SelectClub", function()
			UpdateVisibility(tab)
		end)
	end
	CommunitiesFrame:HookScript("OnShow", function()
		UpdateVisibility(tab)
	end)
	CommunitiesFrame:HookScript("OnHide", function()
		UpdateVisibility(tab)
	end)

	UpdateVisibility(tab)
	return tab
end

-- ====== Tentatives progressives (sans forcer le load) ======
local retrySchedule = { 0, 0.1, 0.25, 0.5, 1, 2, 3 }
local probing = false
local ticker = nil

local function StopTicker()
	if ticker and ticker.Cancel then
		ticker:Cancel()
	end
	ticker = nil
end
local function TryCreateWithRetries(i)
	i = i or 1
	if _G.WoWGuildeTab then
		probing = false
		StopTicker()
		return
	end
	if CommunitiesFrame then
		local tab = CreateGuildButton()
		if tab then
			probing = false
			StopTicker()
			return
		end
	end
	if not IsCommunitiesLoaded() then
		probing = false
		return
	end
	local delay = retrySchedule[i]
	if delay then
		C_Timer.After(delay, function()
			TryCreateWithRetries(i + 1)
		end)
	else
		probing = false
	end
end

function GB.TryDecorateCommunities()
	if probing then
		return
	end
	probing = true
	TryCreateWithRetries(1)
end

function GB.ForceCreate()
	probing = false
	TryCreateWithRetries(1)
end

-- ====== Hook du micro menu Guilde, Shift+clic ouvre l'addon ======
local function ToggleAddonWindow()
	if ns and ns.UI and ns.UI.Toggle then
		ns.UI.Toggle()
	elseif WoWGuilde and WoWGuilde.Toggle then
		WoWGuilde.Toggle()
	else
		print("|cff8be9fd[WoWGuilde:GB]|r Toggle introuvable, verifie le chargement de MainFrame.lua")
	end
end

local function SetupGuildMicroButtonHook()
	local btn = _G.GuildMicroButton
	if not btn or btn._WoWGuildeHooked then
		return btn and true or false
	end

	local orig = btn:GetScript("OnClick")
	btn:SetScript("OnClick", function(self, button, ...)
		-- Shift + clic (gauche ou droit), on ouvre l'addon et on evite l'action par defaut
		if (button == "LeftButton" or button == "RightButton") and IsShiftKeyDown() then
			-- si la fenetre Communautes est ouverte, on la ferme d'abord
			if CommunitiesFrame and CommunitiesFrame:IsShown() and HideUIPanel then
				HideUIPanel(CommunitiesFrame)
			end
			ToggleAddonWindow()
			if self.SetButtonState then
				self:SetButtonState("NORMAL")
			end
			return
		end

		-- sinon, comportement Blizzard inchange
		if type(orig) == "function" then
			orig(self, button, ...)
		end
		if button == "RightButton" then
			C_Timer.After(0, function()
				if self and self.SetButtonState then
					self:SetButtonState("NORMAL")
				end
				if self and self.UnlockHighlight then
					self:UnlockHighlight()
				end
			end)
		end
		C_Timer.After(0, function()
			if GB and GB.TryDecorateCommunities then
				GB.TryDecorateCommunities()
			end
		end)
	end)

	btn._WoWGuildeHooked = true
	return true
end

-- petite boucle de retry pour s'assurer que le bouton est dispo
local function TryHookGuildBtn(i)
	i = i or 1
	if SetupGuildMicroButtonHook() then
		return
	end
	local delay = retrySchedule[i]
	if delay then
		C_Timer.After(delay, function()
			TryHookGuildBtn(i + 1)
		end)
	end
end

-- appelle le hook pendant l'initialisation
function GB.Init()
	GB.TryDecorateCommunities()
	TryHookGuildBtn(1)
	SetupChatPseudoHooks()
	if ns.Utils and ns.Utils.SafeHooksecurefunc then
		ns.Utils.SafeHooksecurefunc("ToggleCommunitiesFrame", function()
			GB.TryDecorateCommunities()
		end)
		ns.Utils.SafeHooksecurefunc("ToggleGuildFrame", function()
			GB.TryDecorateCommunities()
		end)
		ns.Utils.SafeHooksecurefunc("Communities_LoadUI", function()
			GB.TryDecorateCommunities()
		end)
	end
	if EventBus and EventBus.On then
		EventBus.On("PLAYER_ENTERING_WORLD", function()
			GB.TryDecorateCommunities()
		end)
		EventBus.On("PLAYER_GUILD_UPDATE", function()
			GB.TryDecorateCommunities()
		end)
	end
	if C_Timer and C_Timer.NewTicker then
		StopTicker()
		ticker = C_Timer.NewTicker(1, function()
			if _G.WoWGuildeTab then
				StopTicker()
				return
			end
			if CommunitiesFrame then
				GB.TryDecorateCommunities()
			end
		end, 10)
	end
end

-- ====== Auto-bootstrap (EventBus uniquement) ======
do
	if EventBus and EventBus.On then
		EventBus.On("PLAYER_LOGIN", function()
			GB.Init()
		end)
	end
end
