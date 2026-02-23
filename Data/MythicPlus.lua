local ADDON, ns = ...

ns.Data = ns.Data or {}
local Data = ns.Data
local EventBus = ns.EventBus

local myMplusScore = 0

function Data.GetMyMPlusScore()
	return myMplusScore
end

local function UpdateMyMPlusScore()
	local summary = C_PlayerInfo
		and C_PlayerInfo.GetPlayerMythicPlusRatingSummary
		and C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
	if summary and summary.currentSeasonScore then
		myMplusScore = math.floor(summary.currentSeasonScore)
		if ns.Sections and ns.Sections.HerosFrame and ns.Sections.HerosFrame.Refresh then
			ns.Sections.HerosFrame.Refresh()
		end
	end
end

if EventBus and EventBus.On then
	EventBus.On("PLAYER_ENTERING_WORLD", function()
		UpdateMyMPlusScore()
	end)
	EventBus.On("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", function()
		UpdateMyMPlusScore()
	end)
	EventBus.On("CHALLENGE_MODE_MAPS_UPDATE", function()
		UpdateMyMPlusScore()
	end)
	EventBus.On("CHALLENGE_MODE_COMPLETED", function()
		UpdateMyMPlusScore()
	end)
end
