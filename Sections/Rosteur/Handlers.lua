local ADDON, ns = ...

local M = ns.RosteurSection

function M.BindHandlers(ctx)
	local ns = ctx.ns
	local Rosteur = ctx.Rosteur
	local Utils = ctx.Utils
	local const = ctx.const
	local ui = ctx.ui
	local state = ctx.state
	local fn = ctx.fn

	local startBtn = ui.startBtn
	local configBtn = ui.configBtn
	local summaryBtn = ui.summaryBtn
	local validateBtn = ui.validateBtn
	local createRosterBtn = ui.createRosterBtn
	local deleteRosterBtn = ui.deleteRosterBtn
	local resetZeroBtn = ui.resetZeroBtn
	local puAddBtn = ui.puAddBtn
	local puBox = ui.puBox
	local puRole = ui.puRole
	local roleButtons = ui.roleButtons or {}
	local playerClear = ui.playerClear
	local devToggle = ui.devToggle
	local devDelete = ui.devDelete
	local templateSelect = ui.templateSelect
	local f = ui.frame

	local PU_PLACEHOLDER = const.PU_PLACEHOLDER or "Nom du PU"
	const.PU_PLACEHOLDER = PU_PLACEHOLDER

	if startBtn then
		startBtn:SetScript("OnClick", function()
			local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
			if Rosteur and gid then
				Rosteur.StartPreparation(gid)
			end
		end)
	end

	if configBtn then
		configBtn:SetScript("OnClick", function()
			if state.showPrepSummary then
				state.showPrepSummary = false
				if fn.Refresh then
					fn.Refresh()
				end
				return
			end
			local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
			local rosteur = Rosteur and Rosteur.GetState and Rosteur.GetState(gid) or nil
			if not (Rosteur and gid and rosteur) then
				return
			end
			if not (Rosteur.ShouldShowManagerTab and Rosteur.ShouldShowManagerTab()) then
				if UIErrorsFrame and UIErrorsFrame.AddMessage then
					UIErrorsFrame:AddMessage("Seul le Chef de raid peut créer le rosteur.", 1, 0.2, 0.2, 1)
				end
				return
			end
			if rosteur.phase ~= "prep" then
				Rosteur.StartConfig(gid)
				return
			end
			local isLocked = fn.IsPrepConfigLocked and fn.IsPrepConfigLocked(rosteur)
			if isLocked then
				return
			end
			if StaticPopup_Show and StaticPopupDialogs then
				if not StaticPopupDialogs.WOWGUILDE_ROSTEUR_CONFIRM_START_CONFIG then
					StaticPopupDialogs.WOWGUILDE_ROSTEUR_CONFIRM_START_CONFIG = {
						text = "Confirmer le passage en configuration du rosteur ?\n\nLes postulations seront immédiatement fermées.\n\nÉcrivez CONFIRMER pour valider.",
						button1 = "Confirmer",
						button2 = "Annuler",
						hasEditBox = true,
						editBoxWidth = 180,
						EditBoxOnEnterPressed = function(selfEditBox)
							if selfEditBox and selfEditBox.ClearFocus then
								selfEditBox:ClearFocus()
							end
						end,
						OnShow = function(selfPopup)
							if selfPopup.editBox then
								selfPopup.editBox:SetText("")
								selfPopup.editBox:SetFocus()
							end
						end,
						OnAccept = function(selfPopup)
							local box = selfPopup and selfPopup.editBox
							if not box and selfPopup and selfPopup.GetName then
								box = _G[selfPopup:GetName() .. "EditBox"]
							end
							local text = (box and box.GetText and box:GetText()) or ""
							if strupper(fn.TrimSpaces and fn.TrimSpaces(text) or text) ~= "CONFIRMER" then
								if UIErrorsFrame and UIErrorsFrame.AddMessage then
									UIErrorsFrame:AddMessage("Texte incorrect. Écrivez CONFIRMER.", 1, 0.2, 0.2, 1)
								end
								StaticPopup_Show("WOWGUILDE_ROSTEUR_CONFIRM_START_CONFIG")
								return
							end
							local targetGID = state.pendingStartConfigGuildUID
							state.pendingStartConfigGuildUID = nil
							if
								Rosteur
								and targetGID
								and Rosteur.ShouldShowManagerTab
								and Rosteur.ShouldShowManagerTab()
							then
								Rosteur.StartConfig(targetGID)
							end
							if f and f.Refresh then
								f.Refresh()
							end
						end,
						OnCancel = function()
							state.pendingStartConfigGuildUID = nil
						end,
						EditBoxOnTextChanged = function() end,
						timeout = 0,
						whileDead = 1,
						hideOnEscape = 1,
						preferredIndex = 3,
					}
				end
				state.pendingStartConfigGuildUID = gid
				StaticPopup_Show("WOWGUILDE_ROSTEUR_CONFIRM_START_CONFIG")
			else
				Rosteur.StartConfig(gid)
			end
		end)
	end

	if summaryBtn then
		summaryBtn:SetScript("OnClick", function()
			state.showPrepSummary = true
			if fn.Refresh then
				fn.Refresh()
			end
		end)
	end

	if validateBtn then
		validateBtn:SetScript("OnClick", function()
			local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
			if Rosteur and gid then
				Rosteur.ValidateRoster(gid)
			end
		end)
	end

	if createRosterBtn then
		createRosterBtn:SetScript("OnClick", function()
			local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
			if Rosteur and gid and templateSelect and templateSelect._value then
				Rosteur.CreateRoster(gid, templateSelect._value)
			end
		end)
	end

	local function DeleteActiveRoster(reset)
		local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
		if not Rosteur or not gid then
			return
		end
		if reset and Rosteur.Reset then
			Rosteur.Reset(gid)
			return
		end
		local rosteur = Rosteur.GetState and Rosteur.GetState(gid) or nil
		local activeId = rosteur and rosteur.activeRosterId or nil
		if activeId or (rosteur and rosteur.rosters and rosteur.rosters[1]) then
			Rosteur.DeleteRoster(gid, activeId, { force = reset == true })
		end
	end

	if deleteRosterBtn then
		deleteRosterBtn:SetScript("OnClick", function()
			DeleteActiveRoster(true)
		end)
	end

	if resetZeroBtn then
		resetZeroBtn:SetScript("OnClick", function()
			local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
			if Rosteur and Rosteur.ClearSignups and gid then
				Rosteur.ClearSignups(gid)
			end
			if f and f.Refresh then
				f.Refresh()
			end
		end)
	end

	if puAddBtn then
		puAddBtn:SetScript("OnClick", function()
			if not puBox then
				return
			end
			local raw = puBox:GetText()
			if raw == PU_PLACEHOLDER then
				raw = ""
			end
			local name = Utils and Utils.Trim and Utils.Trim(raw) or raw
			if not name or name == "" then
				return
			end
			local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
			if Rosteur and gid then
				local rosteur = Rosteur.GetState and Rosteur.GetState(gid) or nil
				local activeId = rosteur and rosteur.activeRosterId or nil
				if activeId then
					Rosteur.AddPU(gid, activeId, puRole and puRole._value or "DPS", name)
					puBox:SetText(PU_PLACEHOLDER)
				end
			end
		end)
	end

	for role, btn in pairs(roleButtons) do
		btn:SetScript("OnClick", function()
			local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
			if not gid or not Rosteur then
				return
			end
			local full, meta = fn.GetMySignupMeta and fn.GetMySignupMeta(gid) or nil
			if full and full ~= "" then
				Rosteur.SetSignup(gid, full, role, meta)
			end
		end)
	end

	if playerClear then
		playerClear:SetScript("OnClick", function()
			local gid = fn.GetGuildUID and fn.GetGuildUID() or nil
			if not gid or not Rosteur then
				return
			end
			local full = fn.GetMySignupMeta and fn.GetMySignupMeta(gid) or nil
			if full and full ~= "" then
				Rosteur.SetSignup(gid, full, nil)
			end
		end)
	end

	local function UpdateDevToggle()
		if not devToggle or not Rosteur or not Rosteur.GetDevView then
			return
		end
		local view = Rosteur.GetDevView() or "auto"
		local label = "Auto"
		if view == "player" then
			label = "Joueur"
		elseif view == "manager" then
			label = "Chef"
		end
		devToggle:SetText("Vue: " .. label)
	end

	fn.UpdateDevToggle = UpdateDevToggle

	if devToggle then
		devToggle:SetScript("OnClick", function()
			if Rosteur and Rosteur.GetDevView and Rosteur.SetDevView then
				local view = Rosteur.GetDevView() or "auto"
				local nextView = "auto"
				if view == "auto" then
					nextView = "player"
				elseif view == "player" then
					nextView = "manager"
				end
				Rosteur.SetDevView(nextView)
			end
			UpdateDevToggle()
			if ns and ns.UI and ns.UI.Refresh then
				ns.UI.Refresh()
			end
			if f and f.Refresh then
				f.Refresh()
			end
		end)
	end

	if devDelete then
		devDelete:SetScript("OnClick", function()
			DeleteActiveRoster(true)
			if f and f.Refresh then
				f.Refresh()
			end
		end)
	end
end

return M
