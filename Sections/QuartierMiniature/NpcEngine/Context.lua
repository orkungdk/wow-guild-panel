local ADDON, ns = ...

ns.QuartierMiniatureNpcEngine = ns.QuartierMiniatureNpcEngine or {}
ns.QuartierMiniatureNpcEngine.Modules = ns.QuartierMiniatureNpcEngine.Modules or {}
local Modules = ns.QuartierMiniatureNpcEngine.Modules

function Modules.InstallContext(ctx, moduleEnv)
	if type(ctx) ~= "table" or type(moduleEnv) ~= "table" then
		return nil
	end
	setfenv(1, moduleEnv)

mapLayer, viewport, state, npcCfg, Clamp, GetActiveMapId, getCurrentBaseSize = nil, nil, nil, nil, nil, nil, nil
currentBaseW, currentBaseH = nil, nil
Npc_RenderAll, Npc_UpdateAndRender, FindNpcBySelector, OrderNpcTalkWith, TryStartNextQueuedOrder = nil, nil, nil, nil, nil
PI, npcLayer = nil, nil
npcVirtualClockSec, npcVirtualClockActive, npcBootstrapPersistenceEpoch = nil, nil, nil
NPC_LIEU_ENTER_GROW_DURATION = 0.14
NPC_LIEU_ENTER_SHRINK_DURATION = 0.20
NPC_LIEU_EXIT_GROW_DURATION = 0.22
NPC_MIN_VISIBLE_SCALE = 0.001
NPC_LIEU_PRESENCE_SWITCH_DEBOUNCE = 0.12
NPC_CONVERSATION_MAX_PARTICIPANTS = 4
NPC_PLAYER_HERO_ID = "npc_player_hero"
NPC_PLAYER_HERO_NAME_FALLBACK = "Rndu"
NPC_REGISSEUSE_ID = "npc_regisseuse"
NPC_REGISSEUSE_NAME = "Regisseuse"
NPC_REGISSEUSE_PORTRAIT_TEXTURE =
	"Interface\\AddOns\\WoWGuilde\\Media\\MiniGames\\QuartierMiniature\\Regiseur.tga"
npcConversationSerial = 0
AreNpcsInSameConversation = nil
GenerateConversationGroupId = nil
IsConversationState = nil
IsNpcInConversationState = nil
GetConversationMembers = nil
GetConversationGroupIdForNpc = nil
PickConversationPartnerForNpc = nil
EnsureConversationPartner = nil
RebindConversationMembers = nil
TryJoinConversation = nil
GetNpcConversationJoinInfo = nil
OrderNpcJoinConversation = nil

function Lerp(a, b, t)
	return a + ((b - a) * t)
end

function ApplyNpcPortraitFlip(frame, flipped)
	local icon = frame and frame._icon
	if not icon then
		return
	end
	if flipped then
		icon:SetTexCoord(1, 0, 0, 1)
	else
		icon:SetTexCoord(0, 1, 0, 1)
	end
end

function RollNpcPortraitFlip(npc)
	if type(npc) ~= "table" then
		return
	end
	npc.portraitFlipX = (math.random() < 0.5)
	ApplyNpcPortraitFlip(npc.frame, npc.portraitFlipX == true)
end

function ApplyNpcPresenceVisual(frame, scale, alpha)
	if not frame then
		return
	end
	local s = Clamp(tonumber(scale) or 1, NPC_MIN_VISIBLE_SCALE, 2)
	local a = Clamp(tonumber(alpha) or 1, 0, 1)
	frame:SetScale(1)
	frame:SetAlpha(1)
	local iconHost = frame._iconHost
	if iconHost then
		iconHost:SetScale(s)
		iconHost:SetAlpha(a)
	end
	local ringHost = frame._ringHost
	if ringHost then
		ringHost:SetScale(s)
		ringHost:SetAlpha(a)
	end
	local shadow = frame._shadow
	if shadow then
		shadow:SetAlpha(0.85 * a)
	end
end

function UpdateNpcLieuPresenceVisual(npc, inLieu, dt)
	local frame = npc and npc.frame
	if not frame then
		return false
	end
	local delta = Clamp(tonumber(dt) or 0.016, 0.004, 0.20)
	if npc._presenceKnown ~= true then
		npc._presenceKnown = true
		if inLieu then
			npc._presenceState = "hidden_in_lieu"
			npc._presenceProgress = 1
			ApplyNpcPresenceVisual(frame, NPC_MIN_VISIBLE_SCALE, 0)
			return false
		end
		npc._presenceState = "visible_outside"
		npc._presenceProgress = 1
		ApplyNpcPresenceVisual(frame, 1, 1)
		return true
	end

	local stateName = tostring(npc._presenceState or "visible_outside")
	local progress = Clamp(tonumber(npc._presenceProgress) or 0, 0, 1)

	-- Prevent "rubber band" look by never reversing an in-flight transition.
	-- A transition can only switch direction once it has fully completed.
	if stateName == "entering_lieu" then
		-- keep current direction until hidden_in_lieu
	elseif stateName == "exiting_lieu" then
		-- keep current direction until visible_outside
	elseif inLieu then
		if stateName == "visible_outside" then
			stateName = "entering_lieu"
			progress = 0
		end
	else
		if stateName == "hidden_in_lieu" then
			RollNpcPortraitFlip(npc)
			stateName = "exiting_lieu"
			progress = 0
		end
	end

	local scale = 1
	local alpha = 1
	if stateName == "entering_lieu" then
		local totalDuration = NPC_LIEU_ENTER_GROW_DURATION + NPC_LIEU_ENTER_SHRINK_DURATION
		progress = Clamp(progress + (delta / totalDuration), 0, 1)
		local growRatio = NPC_LIEU_ENTER_GROW_DURATION / totalDuration
		if progress <= growRatio then
			local t = (growRatio > 0) and (progress / growRatio) or 1
			scale = Lerp(1.0, 1.3, t)
			alpha = 1
		else
			local t = (progress - growRatio) / math.max(1e-6, 1 - growRatio)
			scale = Lerp(1.3, 0.0, t)
			alpha = Lerp(1.0, 0.0, t)
		end
		if progress >= 1 then
			stateName = "hidden_in_lieu"
			scale = NPC_MIN_VISIBLE_SCALE
			alpha = 0
		end
	elseif stateName == "exiting_lieu" then
		progress = Clamp(progress + (delta / NPC_LIEU_EXIT_GROW_DURATION), 0, 1)
		scale = Lerp(0.0, 1.0, progress)
		alpha = Lerp(0.0, 1.0, progress)
		if progress >= 1 then
			stateName = "visible_outside"
			scale = 1
			alpha = 1
		end
	elseif stateName == "hidden_in_lieu" then
		scale = NPC_MIN_VISIBLE_SCALE
		alpha = 0
	else
		stateName = "visible_outside"
		scale = 1
		alpha = 1
		progress = 1
	end

	npc._presenceState = stateName
	npc._presenceProgress = progress
	ApplyNpcPresenceVisual(frame, scale, alpha)
	return stateName ~= "hidden_in_lieu"
end

function SyncBaseSize()
	currentBaseW, currentBaseH = getCurrentBaseSize()
end

function NowSec()
	if npcVirtualClockActive then
		return tonumber(npcVirtualClockSec) or 0
	end
	local now = GetTime and GetTime() or 0
	return tonumber(now) or 0
end

function BeginVirtualClock(baseNowSec)
	local base = tonumber(baseNowSec)
	if base == nil then
		base = GetTime and GetTime() or 0
	end
	npcVirtualClockSec = math.max(0, tonumber(base) or 0)
	npcVirtualClockActive = true
	return npcVirtualClockSec
end

function EndVirtualClock()
	npcVirtualClockActive = false
	npcVirtualClockSec = nil
	return true
end

function AdvanceVirtualClock(dt)
	if npcVirtualClockActive then
		npcVirtualClockSec = math.max(0, (tonumber(npcVirtualClockSec) or 0) + math.max(0, tonumber(dt) or 0))
	end
	return NowSec()
end

function GetBootstrapPersistenceEpoch()
	return tonumber(npcBootstrapPersistenceEpoch) or 0
end

function SetBootstrapPersistenceEpoch(epochSec)
	local value = tonumber(epochSec)
	if not value or value <= 0 then
		npcBootstrapPersistenceEpoch = nil
		return 0
	end
	npcBootstrapPersistenceEpoch = math.floor(value)
	return npcBootstrapPersistenceEpoch
end


mapLayer = env.mapLayer
viewport = env.viewport
state = env.state
npcCfg = env.npcCfg or {}
Clamp = env.clamp
GetActiveMapId = env.getActiveMapId
getCurrentBaseSize = env.getCurrentBaseSize
if not (mapLayer and viewport and state and type(Clamp) == "function" and type(GetActiveMapId) == "function") then
	return nil
end
if type(getCurrentBaseSize) ~= "function" then
	return nil
end

currentBaseW, currentBaseH = getCurrentBaseSize()

Npc_RenderAll = nil
Npc_UpdateAndRender = nil
FindNpcBySelector = nil
OrderNpcTalkWith = nil
TryStartNextQueuedOrder = nil
PI = math.pi
npcLayer = CreateFrame("Frame", "WoWGuilde_QuartierMiniatureNPCLayer", env.npcLayerParent or mapLayer)
npcLayer:SetAllPoints(viewport)
if env.npcLayerFrameLevel then
	npcLayer:SetFrameLevel(math.floor(tonumber(env.npcLayerFrameLevel) or (mapLayer:GetFrameLevel() + 10)))
else
	npcLayer:SetFrameLevel(mapLayer:GetFrameLevel() + 10)
end
npcLayer:EnableMouse(false)

NPC_COUNT = math.max(1, math.floor(tonumber(npcCfg.count) or 6)) + 2
NPC_BOUND_PAD = Clamp(tonumber(npcCfg.boundPad) or 0.04, 0, 0.45)
NPC_SPEED_MIN = tonumber(npcCfg.speedMin) or 0.014
NPC_SPEED_MAX = tonumber(npcCfg.speedMax) or 0.034
NPC_BASE_SIZE = tonumber(npcCfg.baseSize) or 46
NPC_ICON_SIZE = tonumber(npcCfg.iconSize) or 30
NPC_RING_W = tonumber(npcCfg.ringWidth) or 52
NPC_RING_H = tonumber(npcCfg.ringHeight) or 54
NPC_RING_OFFSET_X = tonumber(npcCfg.ringOffsetX) or 0
NPC_RING_OFFSET_Y = tonumber(npcCfg.ringOffsetY) or 0
NPC_RING_AVOIDANCE_OFFSET_PX = Clamp(tonumber(npcCfg.ringAvoidanceOffsetPx) or 6, 0, 48)
NPC_SHADOW_W = tonumber(npcCfg.shadowWidth) or 52
NPC_SHADOW_H = tonumber(npcCfg.shadowHeight) or 54
NPC_SHADOW_OFFSET_Y = tonumber(npcCfg.shadowOffsetY) or -8
NPC_ROUTE_TO_ROUTE_DIST = Clamp(tonumber(npcCfg.routeToRouteSwitchDist) or 0.028, 0.002, 0.2)
NPC_ROUTE_TO_PLAZA_DIST = Clamp(tonumber(npcCfg.routeToPlazaSwitchDist) or 0.030, 0.002, 0.2)
NPC_PLAZA_TO_ROUTE_DIST = Clamp(tonumber(npcCfg.plazaToRouteSwitchDist) or 0.030, 0.002, 0.2)
NPC_MAX_PER_ZONE = math.max(1, math.floor(tonumber(npcCfg.maxPerZone) or 3))
NPC_MAX_ACTIONS_PER_ZONE = math.max(1, math.floor(tonumber(npcCfg.maxActionsPerZone) or 3))
NPC_PROX_SWITCH_COOLDOWN = tonumber(npcCfg.proximitySwitchCooldown) or 1.0
NPC_TRANSITION_SPEED_FACTOR = Clamp(tonumber(npcCfg.transitionSpeedFactor) or 1.35, 0.5, 4.0)
NPC_ROUTE_WALK_HALF_WIDTH = Clamp(tonumber(npcCfg.routeWalkHalfWidth) or 0.012, 0.002, 0.08)
NPC_ROUTE_OPPOSITE_PASS_FACTOR = Clamp(tonumber(npcCfg.routeOppositePassFactor) or 0.58, 0.35, 0.90)
NPC_ROUTE_OPPOSITE_MIN_DELTA = Clamp(tonumber(npcCfg.routeOppositeMinDelta) or 2.20, 1.2, PI)
NPC_MANUAL_PATH_PLAZA_FACTOR = Clamp(tonumber(npcCfg.manualPathPlazaFactor) or 1.35, 0.60, 3.00)
NPC_MANUAL_PATH_PLAZA_ENTRY_RADIUS =
	Clamp(tonumber(npcCfg.manualPathPlazaEntryRadius) or 0.035, NPC_ROUTE_WALK_HALF_WIDTH, 0.20)
NPC_MANUAL_PATH_MAX_PLAZA_ANCHORS = math.max(2, math.floor(tonumber(npcCfg.manualPathMaxPlazaAnchors) or 8))
NPC_MANUAL_PATH_PLAZA_LINK_MAX_DIST = Clamp(
	tonumber(npcCfg.manualPathPlazaLinkMaxDist)
		or math.max((tonumber(npcCfg.manualPathPlazaEdgeMaxDist) or 0.055) * 1.45, 0.080),
	0.025,
	0.35
)
NPC_MANUAL_PATH_PLAZA_LINK_PENALTY = Clamp(tonumber(npcCfg.manualPathPlazaLinkPenalty) or 1.08, 1.00, 2.00)
NPC_MANUAL_PATH_REALTIME_REPLAN = npcCfg.manualPathRealtimeReplan == true
NPC_MANUAL_PATH_REPLAN_INTERVAL = Clamp(tonumber(npcCfg.manualPathReplanInterval) or 1.20, 0.25, 8.0)
NPC_MANUAL_PATH_SMOOTH_STEP = Clamp(
	tonumber(npcCfg.manualPathSmoothStep) or math.max((tonumber(npcCfg.postTalkZoneReach) or 0.016) * 0.90, 0.010),
	0.004,
	0.08
)
NPC_MANUAL_PATH_MAX_POINTS = math.max(6, math.floor(tonumber(npcCfg.manualPathMaxPoints) or 20))
NPC_ZONE_SHIFT_PATH_MAX_POINTS = math.max(4, math.floor(tonumber(npcCfg.zoneShiftPathMaxPoints) or 12))
NPC_MANUAL_PATH_PLAZA_EDGE_MAX_DIST = Clamp(
	tonumber(npcCfg.manualPathPlazaEdgeMaxDist)
		or math.max((tonumber(npcCfg.manualPathPlazaEntryRadius) or 0.035) * 1.8, 0.055),
	0.020,
	0.22
)
NPC_MANUAL_PATH_JUNCTION_DIST = Clamp(
	tonumber(npcCfg.manualPathJunctionDist)
		or math.max((tonumber(npcCfg.routeWalkHalfWidth) or 0.012) * 1.35, 0.010),
	0.004,
	0.12
)
NPC_MANUAL_PATH_JUNCTION_PENALTY = Clamp(tonumber(npcCfg.manualPathJunctionPenalty) or 1.08, 1.00, 2.50)
NPC_CROWD_EXPAND_SENSE_RADIUS =
	Clamp(tonumber(npcCfg.crowdExpandSenseRadius) or 0.060, NPC_ROUTE_WALK_HALF_WIDTH, 0.30)
NPC_CROWD_EXPAND_THRESHOLD = math.max(0, math.floor(tonumber(npcCfg.crowdExpandThreshold) or 3))
NPC_CROWD_EXPAND_MAX_BONUS = Clamp(tonumber(npcCfg.crowdExpandMaxBonus) or 0.010, 0, 0.08)
NPC_CROWD_RELOCATE_MAX_RADIUS = Clamp(tonumber(npcCfg.crowdRelocateMaxRadius) or 0.028, 0.004, 0.20)
NPC_CROWD_RELOCATE_MIN_DIST_FACTOR = Clamp(tonumber(npcCfg.crowdRelocateMinDistFactor) or 0.58, 0.20, 1.0)
NPC_WALK_STEP = Clamp(tonumber(npcCfg.walkStep) or 0.010, 0.002, 0.04)
NPC_WALK_TURN_RATE = Clamp(tonumber(npcCfg.walkTurnRate) or 2.8, 0.5, 8.0)
NPC_WALK_DESIRED_JITTER = Clamp(tonumber(npcCfg.walkDesiredJitter) or 0.65, 0.05, 2.5)
NPC_WALK_LOOK_AHEAD = Clamp(tonumber(npcCfg.walkLookAhead) or 0.020, 0.004, 0.10)
NPC_WALK_SPEED_BLEND = Clamp(tonumber(npcCfg.walkSpeedBlend) or 2.2, 0.2, 8.0)
NPC_IDLE_FAST_PATH = npcCfg.idleFastPath ~= false
NPC_LOW_CPU_MODE = npcCfg.lowCpuMode ~= false
NPC_LOW_CPU_NPC_STRIDE = math.max(1, math.floor(tonumber(npcCfg.lowCpuNpcStride) or 1))
NPC_LOW_CPU_MOVE_MAX_LOOPS = math.max(4, math.floor(tonumber(npcCfg.lowCpuMoveMaxLoops) or 12))
NPC_LOW_CPU_PROBE_COUNT = math.max(3, math.floor(tonumber(npcCfg.lowCpuProbeCount) or 6))
NPC_LOW_CPU_RESCUE_COUNT = math.max(3, math.floor(tonumber(npcCfg.lowCpuRescueCount) or 6))
-- Collisions PNJ desactivees globalement: superposition autorisee sans penalite.
NPC_COLLISIONS_ENABLED = false
NPC_INTENT_QUEUE_MAX = math.max(1, math.min(12, math.floor(tonumber(npcCfg.intentQueueMax) or 12)))
NPC_AUTO_INTENT_ENABLED = npcCfg.autoIntentEnabled ~= false
NPC_AUTO_INTENT_INTERVAL_MIN = Clamp(tonumber(npcCfg.autoIntentIntervalMin) or 5.0, 1.0, 120.0)
NPC_AUTO_INTENT_INTERVAL_MAX =
	Clamp(tonumber(npcCfg.autoIntentIntervalMax) or 12.0, NPC_AUTO_INTENT_INTERVAL_MIN, 240.0)
-- Une seule auto-envie a la fois: pas d'empilement.
NPC_AUTO_INTENT_MAX_QUEUE = 1
NPC_AUTO_SOCIAL_ENABLED = npcCfg.autoSocialConversations ~= false
NPC_AUTO_SOCIAL_MAX_RESERVE = Clamp(tonumber(npcCfg.autoSocialMaxReserve) or 70, 0, 100)
NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MIN = Clamp(tonumber(npcCfg.autoSocialTriggerChanceMin) or 0.04, 0, 1)
NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MAX =
	Clamp(tonumber(npcCfg.autoSocialTriggerChanceMax) or 0.22, NPC_AUTO_SOCIAL_TRIGGER_CHANCE_MIN, 1)
NPC_SPATIAL_GRID_CELL = Clamp(
	tonumber(npcCfg.spatialGridCell) or math.max((tonumber(npcCfg.crowdSenseRadius) or 0.055) * 0.85, 0.030),
	0.015,
	0.20
)
NPC_LONG_GOAL_MIN_DIST = Clamp(tonumber(npcCfg.longGoalMinDist) or 0.16, 0.02, 0.95)
NPC_LONG_GOAL_MAX_DIST = Clamp(tonumber(npcCfg.longGoalMaxDist) or 0.46, NPC_LONG_GOAL_MIN_DIST + 0.01, 1.40)
NPC_LONG_GOAL_RETARGET_MIN = Clamp(tonumber(npcCfg.longGoalRetargetMin) or 4.0, 0.5, 60.0)
NPC_LONG_GOAL_RETARGET_MAX = Clamp(tonumber(npcCfg.longGoalRetargetMax) or 10.0, NPC_LONG_GOAL_RETARGET_MIN, 120.0)
NPC_LONG_GOAL_REACH = Clamp(tonumber(npcCfg.longGoalReach) or 0.020, 0.004, 0.12)
NPC_LONG_GOAL_PLAZA_BIAS = Clamp(tonumber(npcCfg.longGoalPlazaBias) or 0.72, 0, 1)
NPC_POI_PICK_CHANCE = Clamp(tonumber(npcCfg.poiPickChance) or 0.60, 0, 1)
NPC_POI_PICK_RADIUS = Clamp(tonumber(npcCfg.poiPickRadius) or 0.090, 0.010, 0.45)
NPC_POI_OBSERVE_MIN_APPROACH =
	Clamp(tonumber(npcCfg.poiObserveMinApproach) or 0.018, 0.0, math.max(0.0, NPC_POI_PICK_RADIUS * 0.95))
NPC_POI_NEAR_RADIUS = Clamp(tonumber(npcCfg.poiNearRadius) or 0.030, 0.005, NPC_POI_PICK_RADIUS)
NPC_POI_PAUSE_MULT_MIN = Clamp(tonumber(npcCfg.poiPauseMultMin) or 1.8, 1.0, 10.0)
NPC_POI_PAUSE_MULT_MAX = Clamp(tonumber(npcCfg.poiPauseMultMax) or 3.0, NPC_POI_PAUSE_MULT_MIN, 16.0)
NPC_POI_SCAN_MAX_PER_ROLL = math.max(1, math.floor(Clamp(tonumber(npcCfg.poiScanMaxPerRoll) or 24, 1, 256)))
NPC_POI_ROLL_MIN = Clamp(tonumber(npcCfg.poiRollMin) or 2.2, 0.4, 120.0)
NPC_POI_ROLL_MAX = Clamp(tonumber(npcCfg.poiRollMax) or 5.2, NPC_POI_ROLL_MIN, 180.0)
NPC_POI_COOLDOWN_MIN = Clamp(tonumber(npcCfg.poiCooldownMin) or 12.0, 1.0, 300.0)
NPC_POI_COOLDOWN_MAX = Clamp(tonumber(npcCfg.poiCooldownMax) or 24.0, NPC_POI_COOLDOWN_MIN, 600.0)
-- Legacy POI roll is disabled by default to keep idle actions at 50/50
-- between "move_place" and "observe_nature" (handled by auto-intent candidates).
NPC_LEGACY_AUTO_POI_ROLL_ENABLED = npcCfg.legacyAutoPoiRoll == true
NPC_POI_CONTEMPLATE_MIN = Clamp(tonumber(npcCfg.poiContemplateMin) or 20.0, 5.0, 600.0)
NPC_POI_CONTEMPLATE_MAX = Clamp(tonumber(npcCfg.poiContemplateMax) or 40.0, NPC_POI_CONTEMPLATE_MIN, 900.0)
NPC_SEVERE_BLOCK_MAX_ITERATIONS = math.max(1, math.floor(tonumber(npcCfg.severeBlockMaxIterations) or 3))
NPC_PLAZA_ROAM_RETARGET_MIN = Clamp(tonumber(npcCfg.plazaRoamRetargetMin) or 1.6, 0.3, 20)
NPC_PLAZA_ROAM_RETARGET_MAX = Clamp(tonumber(npcCfg.plazaRoamRetargetMax) or 3.8, NPC_PLAZA_ROAM_RETARGET_MIN, 40)
NPC_PERSONAL_SPACE = Clamp(tonumber(npcCfg.personalSpace) or 0.020, 0.004, 0.08)
NPC_CROWD_SENSE = Clamp(tonumber(npcCfg.crowdSenseRadius) or 0.055, NPC_PERSONAL_SPACE + 0.002, 0.20)
NPC_CROWD_MIN_SPEED_FACTOR = Clamp(tonumber(npcCfg.crowdMinSpeedFactor) or 0.28, 0.05, 1.0)
NPC_WAIT_MIN = Clamp(tonumber(npcCfg.waitMin) or 0.35, 0.05, 5.0)
NPC_WAIT_MAX = Clamp(tonumber(npcCfg.waitMax) or 1.25, NPC_WAIT_MIN, 8.0)
NPC_WAIT_NEAR_CHANCE = Clamp(tonumber(npcCfg.waitNearChance) or 0.22, 0, 1)
NPC_REVERSE_CHANCE = Clamp(tonumber(npcCfg.reverseChance) or 0.01, 0, 0.25)
NPC_SOCIAL_ENCOUNTER_PROC_CHANCE = Clamp(tonumber(npcCfg.encounterChance) or 0.20, 0, 1.0)
NPC_SOCIAL_ENCOUNTER_CHECK_MIN = Clamp(tonumber(npcCfg.encounterCheckMin) or 0.30, 0.05, 8.0)
NPC_SOCIAL_ENCOUNTER_CHECK_MAX =
	Clamp(tonumber(npcCfg.encounterCheckMax) or 0.95, NPC_SOCIAL_ENCOUNTER_CHECK_MIN, 12.0)
NPC_SOCIAL_ENCOUNTER_SAME_DIR_BLOCK_DELTA =
	Clamp(tonumber(npcCfg.encounterSameDirectionBlockDelta) or 0.95, 0.20, math.pi)
NPC_SOCIAL_ENCOUNTER_NEAR_MAX = math.max(0, math.floor(tonumber(npcCfg.encounterNearMax) or 4))
NPC_SOCIAL_ENCOUNTER_RADIUS = Clamp(tonumber(npcCfg.encounterRadius) or 0.090, NPC_PERSONAL_SPACE * 1.2, 0.35)
NPC_SOCIAL_ENCOUNTER_MIN_DIST = Clamp(
	tonumber(npcCfg.encounterMinDist) or (NPC_PERSONAL_SPACE * 1.15),
	NPC_PERSONAL_SPACE * 0.8,
	NPC_SOCIAL_ENCOUNTER_RADIUS
)
NPC_SOCIAL_APPROACH_STOP_DIST = Clamp(
	tonumber(npcCfg.approachStopDist) or (NPC_PERSONAL_SPACE * 1.25),
	NPC_PERSONAL_SPACE,
	NPC_SOCIAL_ENCOUNTER_RADIUS
)
NPC_SOCIAL_DISCUSS_MIN = Clamp(tonumber(npcCfg.discussMin) or 8.0, 3.0, 60.0)
NPC_SOCIAL_DISCUSS_MAX = Clamp(tonumber(npcCfg.discussMax) or 18.0, NPC_SOCIAL_DISCUSS_MIN, 90.0)
NPC_SOCIAL_DISCUSS_PREFERRED_DIST = Clamp(
	tonumber(npcCfg.discussPreferredDist) or (NPC_SOCIAL_APPROACH_STOP_DIST * 0.95),
	NPC_PERSONAL_SPACE * 1.2,
	NPC_SOCIAL_ENCOUNTER_RADIUS
)
NPC_SOCIAL_DISCUSS_MIN_DIST = Clamp(
	tonumber(npcCfg.discussMinDist) or math.max(NPC_SOCIAL_DISCUSS_PREFERRED_DIST * 0.82, NPC_PERSONAL_SPACE * 1.18),
	NPC_PERSONAL_SPACE * 1.05,
	NPC_SOCIAL_DISCUSS_PREFERRED_DIST
)
NPC_SOCIAL_DISCUSS_VARIANCE = Clamp(tonumber(npcCfg.discussVariance) or 0.30, 0, 0.95)
NPC_SOCIAL_DISCUSS_LONG_CHANCE = Clamp(tonumber(npcCfg.discussLongChance) or 0.22, 0, 1)
NPC_SOCIAL_DISCUSS_LONG_MULT_MIN = Clamp(tonumber(npcCfg.discussLongMultMin) or 1.20, 1.0, 6.0)
NPC_SOCIAL_DISCUSS_LONG_MULT_MAX =
	Clamp(tonumber(npcCfg.discussLongMultMax) or 2.00, NPC_SOCIAL_DISCUSS_LONG_MULT_MIN, 10.0)
NPC_SOCIAL_AUTO_SMALLTALK_MIN = Clamp(tonumber(npcCfg.autoSmallTalkMin) or 4.0, 2.0, 30.0)
NPC_SOCIAL_AUTO_SMALLTALK_MAX =
	Clamp(tonumber(npcCfg.autoSmallTalkMax) or 9.0, NPC_SOCIAL_AUTO_SMALLTALK_MIN, 45.0)
NPC_SOCIAL_COOLDOWN_MIN = Clamp(tonumber(npcCfg.socialCooldownMin) or 2.5, 0, 30)
NPC_SOCIAL_COOLDOWN_MAX = Clamp(tonumber(npcCfg.socialCooldownMax) or 6.0, NPC_SOCIAL_COOLDOWN_MIN, 60)
NPC_GLOBAL_TALK_LOCK_DURATION = Clamp(tonumber(npcCfg.globalTalkLockDuration) or 120.0, 0, 900)
NPC_SOCIAL_POST_TALK_COOLDOWN_MIN = Clamp(
	tonumber(npcCfg.postTalkCooldownMin) or math.max(NPC_SOCIAL_COOLDOWN_MIN + 1.2, NPC_SOCIAL_COOLDOWN_MIN * 1.6),
	NPC_SOCIAL_COOLDOWN_MIN,
	90
)
NPC_SOCIAL_POST_TALK_COOLDOWN_MAX = Clamp(
	tonumber(npcCfg.postTalkCooldownMax)
		or math.max(NPC_SOCIAL_POST_TALK_COOLDOWN_MIN + 2.0, NPC_SOCIAL_COOLDOWN_MAX * 2.2),
	NPC_SOCIAL_POST_TALK_COOLDOWN_MIN,
	180
)
NPC_SOCIAL_POST_TALK_ZONE_SWITCH_MIN = Clamp(tonumber(npcCfg.postTalkZoneSwitchMin) or 3.5, 0.8, 40)
NPC_SOCIAL_POST_TALK_ZONE_SWITCH_MAX =
	Clamp(tonumber(npcCfg.postTalkZoneSwitchMax) or 8.0, NPC_SOCIAL_POST_TALK_ZONE_SWITCH_MIN, 90)
NPC_SOCIAL_POST_TALK_ZONE_REACH = Clamp(tonumber(npcCfg.postTalkZoneReach) or 0.016, 0.004, 0.12)
NPC_ZONE_ROUTINE_ACTIONS = math.max(1, math.floor(tonumber(npcCfg.zoneRoutineActionsPerZone) or 2))
NPC_ZONE_ROUTINE_PAUSE_MIN = Clamp(tonumber(npcCfg.zoneRoutinePauseMin) or 1.8, 0.2, 30)
NPC_ZONE_ROUTINE_PAUSE_MAX = Clamp(tonumber(npcCfg.zoneRoutinePauseMax) or 4.8, NPC_ZONE_ROUTINE_PAUSE_MIN, 60)
NPC_ZONE_ROUTINE_TTL_MIN = Clamp(tonumber(npcCfg.zoneRoutineTargetTtlMin) or 5.5, 0.5, 60)
NPC_ZONE_ROUTINE_TTL_MAX = Clamp(tonumber(npcCfg.zoneRoutineTargetTtlMax) or 12.0, NPC_ZONE_ROUTINE_TTL_MIN, 90)
NPC_SOCIAL_REPEAT_PARTNER_COOLDOWN_MIN = Clamp(
	tonumber(npcCfg.repeatPartnerCooldownMin) or math.max(NPC_SOCIAL_POST_TALK_COOLDOWN_MIN * 1.2, 8.0),
	NPC_SOCIAL_POST_TALK_COOLDOWN_MIN,
	180
)
NPC_SOCIAL_REPEAT_PARTNER_COOLDOWN_MAX = Clamp(
	tonumber(npcCfg.repeatPartnerCooldownMax)
		or math.max(NPC_SOCIAL_REPEAT_PARTNER_COOLDOWN_MIN + 4.0, NPC_SOCIAL_POST_TALK_COOLDOWN_MAX * 1.4),
	NPC_SOCIAL_REPEAT_PARTNER_COOLDOWN_MIN,
	240
)
NPC_SOCIAL_DISENGAGE_MIN_DIST = Clamp(
	tonumber(npcCfg.disengageMinDist)
		or math.max(NPC_SOCIAL_DISCUSS_PREFERRED_DIST * 1.30, NPC_PERSONAL_SPACE * 2.2),
	NPC_SOCIAL_DISCUSS_MIN_DIST * 1.05,
	NPC_SOCIAL_ENCOUNTER_RADIUS * 1.6
)
NPC_SOCIAL_DISENGAGE_MIN = Clamp(tonumber(npcCfg.disengageMin) or 0.9, 0.15, 12.0)
NPC_SOCIAL_DISENGAGE_MAX = Clamp(tonumber(npcCfg.disengageMax) or 2.4, NPC_SOCIAL_DISENGAGE_MIN, 24.0)
NPC_SOCIAL_DUO_WALK_CHANCE = Clamp(tonumber(npcCfg.duoWalkChance) or 0.32, 0, 1)
NPC_SOCIAL_DUO_WALK_MIN = Clamp(tonumber(npcCfg.duoWalkMin) or 3.5, 0.5, 40)
NPC_SOCIAL_DUO_WALK_MAX = Clamp(tonumber(npcCfg.duoWalkMax) or 9.0, NPC_SOCIAL_DUO_WALK_MIN, 80)
NPC_SOCIAL_DUO_SEPARATION =
	Clamp(tonumber(npcCfg.duoWalkSeparation) or (NPC_PERSONAL_SPACE * 1.5), NPC_PERSONAL_SPACE * 1.1, 0.20)
NPC_SOCIAL_DUO_TARGET_RADIUS = Clamp(tonumber(npcCfg.duoTargetRadius) or 0.080, 0.01, 0.30)
NPC_SOCIAL_DUO_TARGET_REACH = Clamp(tonumber(npcCfg.duoTargetReach) or 0.020, 0.005, 0.10)
NPC_SOCIAL_PAIR_SOFT_MIN_DIST = Clamp(
	tonumber(npcCfg.socialPairSoftMinDist) or (NPC_PERSONAL_SPACE * 0.72),
	NPC_PERSONAL_SPACE * 0.45,
	NPC_PERSONAL_SPACE * 0.98
)
NPC_SOCIAL_DISCUSS_SOFT_MIN_DIST = Clamp(
	tonumber(npcCfg.discussSoftMinDist) or math.max(NPC_SOCIAL_PAIR_SOFT_MIN_DIST * 1.55, NPC_PERSONAL_SPACE * 1.35),
	NPC_SOCIAL_PAIR_SOFT_MIN_DIST,
	NPC_PERSONAL_SPACE * 3.0
)
NPC_SELF_PAUSE_CHANCE = Clamp(tonumber(npcCfg.selfPauseChance) or 0.14, 0, 2.0)
NPC_SELF_PAUSE_MIN = Clamp(tonumber(npcCfg.selfPauseMin) or 1.2, 0.2, 20)
NPC_SELF_PAUSE_MAX = Clamp(tonumber(npcCfg.selfPauseMax) or 3.8, NPC_SELF_PAUSE_MIN, 40)
NPC_SELF_PAUSE_COOLDOWN_MIN = Clamp(tonumber(npcCfg.selfPauseCooldownMin) or 3.0, 0, 30)
NPC_SELF_PAUSE_COOLDOWN_MAX = Clamp(tonumber(npcCfg.selfPauseCooldownMax) or 8.0, NPC_SELF_PAUSE_COOLDOWN_MIN, 60)
NPC_SELF_PAUSE_EDGE_MIN_DIST = Clamp(tonumber(npcCfg.selfPauseEdgeMinDist) or 0.004, 0, 0.10)
NPC_SELF_PAUSE_EDGE_MAX_DIST =
	Clamp(tonumber(npcCfg.selfPauseEdgeMaxDist) or 0.022, NPC_SELF_PAUSE_EDGE_MIN_DIST + 0.001, 0.20)
NPC_SELF_PAUSE_ZONE_CELL = Clamp(tonumber(npcCfg.selfPauseZoneCell) or 0.025, 0.005, 0.20)
configuredMinSeparationPx = tonumber(npcCfg.minSeparationPx) or math.max(14, NPC_ICON_SIZE * 0.55)
ringSafeSeparationPx = (npcCfg.enforceRingSeparation == true)
		and (math.max(NPC_RING_W, NPC_RING_H) + (NPC_RING_AVOIDANCE_OFFSET_PX * 2))
	or 0
NPC_MIN_SEPARATION_PX = Clamp(math.max(configuredMinSeparationPx, ringSafeSeparationPx), 6, 140)
NPC_SPAWN_MIN_DIST = Clamp(tonumber(npcCfg.spawnMinDist) or (NPC_PERSONAL_SPACE * 1.3), NPC_PERSONAL_SPACE, 0.20)
NPC_EMERGENCY_SEPARATION_MULT = Clamp(tonumber(npcCfg.emergencySeparationMult) or 1.25, 1.0, 3.0)
NPC_SEPARATION_INTERVAL =
	Clamp(tonumber(npcCfg.separationInterval) or (NPC_LOW_CPU_MODE and 0.08 or 0.03), 0.00, 0.40)
if NPC_SPEED_MAX < NPC_SPEED_MIN then
	NPC_SPEED_MAX = NPC_SPEED_MIN
end
npcPool = {}
npcGlobalTalkLock = 0
NpcPersistence = ns and ns.QuartierMiniature and ns.QuartierMiniature.NpcPersistence or nil
NPC_PERSIST_SAVE_INTERVAL = Clamp(tonumber(npcCfg.persistSaveInterval) or 4.0, 0.5, 30.0)
NPC_SHOW_NAMES = npcCfg.showNames ~= false
NPC_NAME_FONT_SIZE = Clamp(tonumber(npcCfg.nameFontSize) or 11, 8, 24)
NPC_NAME_MAX_LEN = math.max(8, math.floor(tonumber(npcCfg.nameMaxLen) or 22))
NPC_NEEDS_CFG = type(npcCfg.needs) == "table" and npcCfg.needs or {}
NPC_NEEDS_ENABLED = NPC_NEEDS_CFG.enabled ~= false
NPC_NEEDS_INITIAL_MIN = Clamp(tonumber(NPC_NEEDS_CFG.initialMin) or 22, 0, 100)
NPC_NEEDS_INITIAL_MAX = Clamp(tonumber(NPC_NEEDS_CFG.initialMax) or 58, NPC_NEEDS_INITIAL_MIN, 100)
NPC_NEEDS_SOCIAL_RISE = Clamp(tonumber(NPC_NEEDS_CFG.socialRisePerSec) or 0.014, 0, 3)
NPC_NEEDS_SOCIAL_RECOVER_TALK = Clamp(tonumber(NPC_NEEDS_CFG.socialRecoverTalkPerSec) or 0.075, 0, 3)
NPC_NEEDS_SOCIAL_RECOVER_LIEU_GROUP = Clamp(tonumber(NPC_NEEDS_CFG.socialRecoverLieuGroupPerSec) or 0.030, 0, 3)
NPC_NEEDS_SOCIAL_LIEU_GROUP_MIN_COUNT =
	math.max(2, math.floor(tonumber(NPC_NEEDS_CFG.socialLieuGroupMinCount) or 2))
NPC_NEEDS_FATIGUE_RISE_MOVE = Clamp(tonumber(NPC_NEEDS_CFG.fatigueRiseMovePerSec) or 0.028, 0, 3)
NPC_NEEDS_FATIGUE_RECOVER_REST = Clamp(tonumber(NPC_NEEDS_CFG.fatigueRecoverRestPerSec) or 0.022, 0, 3)
NPC_NEEDS_FAIM_RISE = Clamp(tonumber(NPC_NEEDS_CFG.faimRisePerSec) or 0.018, 0, 3)
NPC_NEEDS_FAIM_RECOVER_PAUSE = Clamp(tonumber(NPC_NEEDS_CFG.faimRecoverPausePerSec) or 0.010, 0, 3)
NPC_NEEDS_DISTRACTION_RISE = Clamp(tonumber(NPC_NEEDS_CFG.distractionRisePerSec) or 0.015, 0, 3)
NPC_NEEDS_DISTRACTION_RECOVER_PAUSE = Clamp(tonumber(NPC_NEEDS_CFG.distractionRecoverPausePerSec) or 0.020, 0, 3)
essentialHoldMin = Clamp(tonumber(NPC_NEEDS_CFG.essentialHoldMin) or 60, 0, 100)
NPC_NEEDS_ESSENTIAL = {
	holdMin = essentialHoldMin,
	holdMax = Clamp(tonumber(NPC_NEEDS_CFG.essentialHoldMax) or 80, essentialHoldMin, 100),
	recoverBoost = Clamp(tonumber(NPC_NEEDS_CFG.essentialRecoverBoost) or 12.0, 1.0, 40.0),
	holdMargin = Clamp(tonumber(NPC_NEEDS_CFG.essentialHoldMarginSec) or 0.75, 0, 12.0),
}
NPC_NEEDS_FATIGUE_SPEED_PENALTY = Clamp(tonumber(NPC_NEEDS_CFG.fatigueSpeedPenalty) or 0.45, 0, 0.95)
NPC_NEEDS_SOCIAL_URGENCY = Clamp(tonumber(NPC_NEEDS_CFG.socialUrgencyThreshold) or 66, 0, 100)
NPC_NEEDS_DISTRACTION_PAUSE = Clamp(tonumber(NPC_NEEDS_CFG.distractionPauseThreshold) or 72, 0, 100)
NPC_SOCIAL_BONUS_PLAYER_MIN = Clamp(tonumber(npcCfg.socialPlayerTalkGainMin) or 20, 0, 100)
NPC_SOCIAL_BONUS_PLAYER_MAX =
	Clamp(tonumber(npcCfg.socialPlayerTalkGainMax) or 25, NPC_SOCIAL_BONUS_PLAYER_MIN, 100)
NPC_SOCIAL_BONUS_AUTO_MIN = Clamp(tonumber(npcCfg.socialAutoTalkGainMin) or 10, 0, 100)
NPC_SOCIAL_BONUS_AUTO_MAX = Clamp(tonumber(npcCfg.socialAutoTalkGainMax) or 15, NPC_SOCIAL_BONUS_AUTO_MIN, 100)
NPC_DEFAULT_NAMES = type(npcCfg.defaultNames) == "table" and npcCfg.defaultNames or {}
INTENT_ICON_DEFAULT = "Interface\\ICONS\\INV_Misc_QuestionMark"
INTENT_ICON_TALK = "Interface\\ICONS\\INV_Misc_GroupNeedMore"
INTENT_ICON_REST = "Interface\\ICONS\\Spell_Holy_Restoration"
INTENT_ICON_MEAL = "Interface\\ICONS\\INV_Misc_Food_64"
INTENT_ICON_DISTRACTION = "Interface\\ICONS\\INV_Drink_05"
INTENT_ICON_NATURE = "Interface\\ICONS\\INV_Misc_Flower_02"
INTENT_ICON_MOVE = "Interface\\ICONS\\Ability_Rogue_Sprint"
INTENT_ICON_PAUSE = "Interface\\ICONS\\Spell_Nature_Sleep"
actionRules = nil
do
	local qmini = ns and ns.QuartierMiniature or nil
	local rules = qmini and qmini.NpcActionRules or nil
	local interactions = qmini and qmini.NpcInteractions or nil
	local factory = nil
	if type(rules) == "table" and type(rules.CreateRunner) == "function" then
		factory = rules.CreateRunner
	elseif type(interactions) == "table" and type(interactions.CreateRunner) == "function" then
		factory = interactions.CreateRunner
	end
	if type(factory) == "function" then
		local ok, runner = pcall(factory, {
			Clamp = Clamp,
			RandomRoll = math.random,
			icons = {
				DEFAULT = INTENT_ICON_DEFAULT,
				TALK = INTENT_ICON_TALK,
				REST = INTENT_ICON_REST,
				MEAL = INTENT_ICON_MEAL,
				DISTRACTION = INTENT_ICON_DISTRACTION,
				NATURE = INTENT_ICON_NATURE,
				MOVE = INTENT_ICON_MOVE,
			},
		})
		if ok and type(runner) == "table" then
			actionRules = runner
		end
	end
end
npcPersistenceTimer = 0
npcPersistenceMapId = tostring(GetActiveMapId() or "default")
npcLowCpuPhase = 0
npcSeparationTimer = 0
npcVirtualClockSec = nil
npcVirtualClockActive = false
npcBootstrapPersistenceEpoch = 0
currentTimeContext = {
	phaseKey = "aube",
	phaseLabel = "Aube",
	ai = {
		dynamism = 1.0,
		interaction = 1.0,
		autoIntentRate = 1.0,
		needsDrain = 1.0,
		needsRecovery = 1.0,
		actionWeights = {
			rest = 1.0,
			meal = 1.0,
			distraction = 1.0,
			move_place = 1.0,
			observe_nature = 1.0,
			talk = 1.0,
		},
	},
}

function NormalizeTimeActionWeights(raw)
	local src = type(raw) == "table" and raw or {}
	return {
		rest = Clamp(tonumber(src.rest) or 1.0, 0.10, 4.0),
		meal = Clamp(tonumber(src.meal) or 1.0, 0.10, 4.0),
		distraction = Clamp(tonumber(src.distraction) or 1.0, 0.10, 4.0),
		move_place = Clamp(tonumber(src.move_place) or tonumber(src.walk) or 1.0, 0.10, 4.0),
		observe_nature = Clamp(tonumber(src.observe_nature) or 1.0, 0.10, 4.0),
		talk = Clamp(tonumber(src.talk) or 1.0, 0.10, 4.0),
	}
end

function NormalizeTimeAi(raw)
	local src = type(raw) == "table" and raw or {}
	return {
		dynamism = Clamp(tonumber(src.dynamism) or 1.0, 0.20, 3.0),
		interaction = Clamp(tonumber(src.interaction) or 1.0, 0.20, 3.0),
		autoIntentRate = Clamp(tonumber(src.autoIntentRate) or 1.0, 0.20, 4.0),
		needsDrain = Clamp(tonumber(src.needsDrain) or 1.0, 0.20, 4.0),
		needsRecovery = Clamp(tonumber(src.needsRecovery) or 1.0, 0.20, 4.0),
		actionWeights = NormalizeTimeActionWeights(src.actionWeights),
	}
end

function NormalizeTimeContext(raw)
	local src = type(raw) == "table" and raw or {}
	local aiSrc = type(src.ai) == "table" and src.ai or {}
	return {
		phaseKey = tostring(src.phaseKey or "aube"),
		phaseLabel = tostring(src.phaseLabel or src.phaseKey or "Aube"),
		ai = NormalizeTimeAi(aiSrc),
	}
end

function GetTimeDynamismFactor()
	local ai = type(currentTimeContext and currentTimeContext.ai) == "table" and currentTimeContext.ai or nil
	return Clamp(tonumber(ai and ai.dynamism) or 1.0, 0.20, 3.0)
end

function GetTimeInteractionFactor()
	local ai = type(currentTimeContext and currentTimeContext.ai) == "table" and currentTimeContext.ai or nil
	return Clamp(tonumber(ai and ai.interaction) or 1.0, 0.20, 3.0)
end

function GetTimeAutoIntentRate()
	local ai = type(currentTimeContext and currentTimeContext.ai) == "table" and currentTimeContext.ai or nil
	return Clamp(tonumber(ai and ai.autoIntentRate) or 1.0, 0.20, 4.0)
end

function GetTimeNeedsDrainFactor()
	local ai = type(currentTimeContext and currentTimeContext.ai) == "table" and currentTimeContext.ai or nil
	return Clamp(tonumber(ai and ai.needsDrain) or 1.0, 0.20, 4.0)
end

function GetTimeNeedsRecoveryFactor()
	local ai = type(currentTimeContext and currentTimeContext.ai) == "table" and currentTimeContext.ai or nil
	return Clamp(tonumber(ai and ai.needsRecovery) or 1.0, 0.20, 4.0)
end

function GetTimeActionWeight(purpose)
	local ai = type(currentTimeContext and currentTimeContext.ai) == "table" and currentTimeContext.ai or nil
	local weights = type(ai and ai.actionWeights) == "table" and ai.actionWeights or nil
	if type(weights) ~= "table" then
		return 1.0
	end
	local p = string.lower(tostring(purpose or ""))
	if p == "walk" or p == "wait" or p == "se_promener" then
		p = "move_place"
	end
	return Clamp(tonumber(weights[p]) or 1.0, 0.10, 4.0)
end

function BuildTimeBehaviorModifiers()
	return {
		dynamism = GetTimeDynamismFactor(),
		interaction = GetTimeInteractionFactor(),
	}
end

function IsNightPhase()
	return string.lower(tostring(currentTimeContext and currentTimeContext.phaseKey or "")) == "nuit"
end

function NormalizePurposeKey(purpose)
	local p = string.lower(tostring(purpose or ""))
	if p == "walk" or p == "wait" or p == "se_promener" then
		p = "move_place"
	end
	return p
end

function IsPurposeAllowedForPhase(purpose, phaseKey)
	local p = NormalizePurposeKey(purpose)
	local phase = string.lower(tostring(phaseKey or "aube"))
	if p == "distraction" and (phase == "aube" or phase == "matin") then
		return false
	end
	if p == "meal" and (phase == "nuit" or phase == "apres_midi") then
		return false
	end
	if p == "rest" and (phase == "aube" or phase == "midi" or phase == "apres_midi") then
		return false
	end
	return true
end

function IsPurposeAllowedNow(purpose)
	return IsPurposeAllowedForPhase(purpose, currentTimeContext and currentTimeContext.phaseKey)
end
currentTimeContext = NormalizeTimeContext(nil)

function BuildPresenceAtlasPool()
	local out, seen = {}, {}
	local src = ns and ns.Data and ns.Data.SessionPresenceAtlas or nil
	if type(src) == "table" then
		for _, sexBucket in pairs(src) do
			if type(sexBucket) == "table" then
				for _, atlas in pairs(sexBucket) do
					if type(atlas) == "string" and atlas ~= "" and not seen[atlas] then
						seen[atlas] = true
						out[#out + 1] = atlas
					end
				end
			end
		end
	end
	if #out == 0 then
		out = {
			"raceicon128-human-male",
			"raceicon128-orc-male",
			"raceicon128-nightelf-female",
			"raceicon128-bloodelf-female",
			"raceicon128-tauren-male",
			"raceicon128-draenei-female",
		}
	end
	return out
end

presenceAtlasPool = BuildPresenceAtlasPool()
NPC_FALLBACK_ATLAS = "raceicon128-human-male"

function IsAtlasUsable(atlasName)
	if type(atlasName) ~= "string" or atlasName == "" then
		return false
	end
	if C_Texture and C_Texture.GetAtlasInfo then
		local info = C_Texture.GetAtlasInfo(atlasName)
		return info ~= nil
	end
	return true
end

function PickValidNpcAtlas()
	if #presenceAtlasPool > 0 then
		for _ = 1, 12 do
			local candidate = presenceAtlasPool[math.random(1, #presenceAtlasPool)]
			if IsAtlasUsable(candidate) then
				return candidate
			end
		end
		for i = 1, #presenceAtlasPool do
			if IsAtlasUsable(presenceAtlasPool[i]) then
				return presenceAtlasPool[i]
			end
		end
	end
	return NPC_FALLBACK_ATLAS
end

function RandRange(minV, maxV)
	return minV + (math.random() * (maxV - minV))
end

function TrimNpcName(rawName)
	if type(rawName) ~= "string" then
		return nil
	end
	local name = rawName:gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return nil
	end
	if #name > NPC_NAME_MAX_LEN then
		name = string.sub(name, 1, NPC_NAME_MAX_LEN)
	end
	return name
end

function BuildFallbackName(index)
	local idx = math.max(1, math.floor(tonumber(index) or 1))
	if #NPC_DEFAULT_NAMES > 0 then
		local candidate = TrimNpcName(NPC_DEFAULT_NAMES[((idx - 1) % #NPC_DEFAULT_NAMES) + 1])
		if candidate then
			return candidate
		end
	end
	return "Villageois " .. tostring(idx)
end

function BuildNpcNeeds(rawNeeds)
	local function ReadNeed(key)
		local value = tonumber(rawNeeds and rawNeeds[key])
		if value == nil then
			value = RandRange(NPC_NEEDS_INITIAL_MIN, NPC_NEEDS_INITIAL_MAX)
		end
		return Clamp(value, 0, 100)
	end
	return {
		social = ReadNeed("social"),
		fatigue = ReadNeed("fatigue"),
		faim = ReadNeed("faim"),
		distraction = ReadNeed("distraction"),
	}
end

essentialNeeds = {}
essentialNeeds.GetNeedsTable = function(npc)
	local needs = type(npc and npc.needs) == "table" and npc.needs or nil
	if not needs then
		needs = BuildNpcNeeds(nil)
		if npc then
			npc.needs = needs
		end
	end
	return needs
end
essentialNeeds.GetValue = function(npc, purpose)
	local needs = essentialNeeds.GetNeedsTable(npc)
	local mode = tostring(purpose or "")
	if mode == "rest" then
		return Clamp(tonumber(needs.fatigue) or 0, 0, 100)
	end
	if mode == "meal" then
		return Clamp(tonumber(needs.faim) or 0, 0, 100)
	end
	if mode == "distraction" then
		return Clamp(tonumber(needs.distraction) or 0, 0, 100)
	end
	return 100
end
essentialNeeds.GetTarget = function(npc, purpose)
	local mode = tostring(purpose or "")
	if mode ~= "rest" and mode ~= "distraction" and mode ~= "meal" then
		return NPC_NEEDS_ESSENTIAL.holdMin
	end
	if type(npc.essentialNeedTargets) ~= "table" then
		npc.essentialNeedTargets = {}
	end
	local target = tonumber(npc.essentialNeedTargets[mode])
	if not target then
		target = NPC_NEEDS_ESSENTIAL.holdMax
		npc.essentialNeedTargets[mode] = target
	end
	return Clamp(target, NPC_NEEDS_ESSENTIAL.holdMin, NPC_NEEDS_ESSENTIAL.holdMax)
end
essentialNeeds.ResetTarget = function(npc, purpose)
	local mode = tostring(purpose or "")
	if mode == "" or type(npc) ~= "table" then
		return
	end
	if type(npc.essentialNeedTargets) == "table" then
		npc.essentialNeedTargets[mode] = nil
	end
end
essentialNeeds.EstimateRecoverySeconds = function(npc, purpose, targetValue)
	local eps = 0.000001
	local mode = tostring(purpose or "")
	local target = Clamp(tonumber(targetValue) or essentialNeeds.GetTarget(npc, mode), 0, 100)
	if mode == "rest" then
		local current = Clamp(tonumber(essentialNeeds.GetNeedsTable(npc).fatigue) or 0, 0, 100)
		local missing = math.max(0, target - current)
		local recoverPerSec = math.max(eps, NPC_NEEDS_FATIGUE_RECOVER_REST * NPC_NEEDS_ESSENTIAL.recoverBoost)
		return missing / recoverPerSec
	end
	if mode == "meal" then
		local faim = Clamp(tonumber(essentialNeeds.GetNeedsTable(npc).faim) or 0, 0, 100)
		local faimPauseGain = math.max(NPC_NEEDS_FAIM_RECOVER_PAUSE, NPC_NEEDS_FAIM_RISE * 1.35)
		local faimPerSec = math.max(eps, faimPauseGain * 1.45 * NPC_NEEDS_ESSENTIAL.recoverBoost)
		return math.max(0, target - faim) / faimPerSec
	end
	if mode == "distraction" then
		local needs = essentialNeeds.GetNeedsTable(npc)
		local distraction = Clamp(tonumber(needs.distraction) or 0, 0, 100)
		local distractionPauseGain =
			math.max(NPC_NEEDS_DISTRACTION_RECOVER_PAUSE, NPC_NEEDS_DISTRACTION_RISE * 1.35)
		local distractionPerSec = math.max(eps, distractionPauseGain * 1.25 * NPC_NEEDS_ESSENTIAL.recoverBoost)
		return math.max(0, target - distraction) / distractionPerSec
	end
	return 0
end
essentialNeeds.IsCritical = function(npc)
	if not npc then
		return false
	end
	local restTarget = essentialNeeds.GetTarget(npc, "rest")
	local mealTarget = essentialNeeds.GetTarget(npc, "meal")
	local distractionTarget = essentialNeeds.GetTarget(npc, "distraction")
	local restValue = essentialNeeds.GetValue(npc, "rest")
	local mealValue = essentialNeeds.GetValue(npc, "meal")
	local distractionValue = essentialNeeds.GetValue(npc, "distraction")
	return (restValue < restTarget) or (mealValue < mealTarget) or (distractionValue < distractionTarget)
end
essentialNeeds.IsAllGreen = function(npc)
	if not npc then
		return false
	end
	local needs = essentialNeeds.GetNeedsTable(npc)
	return (tonumber(needs.fatigue) or 0) >= NPC_NEEDS_ESSENTIAL.holdMax
		and (tonumber(needs.faim) or 0) >= NPC_NEEDS_ESSENTIAL.holdMax
		and (tonumber(needs.distraction) or 0) >= NPC_NEEDS_ESSENTIAL.holdMax
end

function ShouldStopEssentialPauseByReserve(npc, purpose, reserve)
	if type(npc) ~= "table" then
		return false
	end
	local mode = tostring(purpose or "")
	local value = Clamp(tonumber(reserve) or 0, 0, 100)
	local currentPercent = math.floor(value + 0.0001)
	if currentPercent >= 100 then
		return true
	end
	if currentPercent < 80 then
		npc.essentialPauseRollPurpose = mode
		npc.essentialPauseRollPercent = currentPercent
		return false
	end

	if tostring(npc.essentialPauseRollPurpose or "") ~= mode then
		npc.essentialPauseRollPurpose = mode
		npc.essentialPauseRollPercent = currentPercent
		return false
	end

	local lastPercent = math.floor(tonumber(npc.essentialPauseRollPercent) or currentPercent)
	if currentPercent <= lastPercent then
		return false
	end
	for p = math.max(81, lastPercent + 1), currentPercent do
		local chance = Clamp((p - 80) * 0.05, 0, 1)
		if math.random() <= chance then
			npc.essentialPauseRollPercent = p
			return true
		end
	end
	npc.essentialPauseRollPercent = currentPercent
	return false
end

function RandomWorldCoord()
	local span = math.max(0.001, 1 - (NPC_BOUND_PAD * 2))
	local pad = NPC_BOUND_PAD
	return pad + (math.random() * span)
end

NAV_EPS = 0.000001
navRefreshElapsed = 99
navCache = {
	signature = "nil",
	segments = {},
	routeGrid = nil,
	nodes = {},
	routes = {},
	plazas = {},
	lieux = {},
	pois = {},
	hasRoutes = false,
	hasPlazas = false,
	hasLieux = false,
	hasPois = false,
}
npcSpatial = {
	enabled = false,
	cellSize = NPC_SPATIAL_GRID_CELL,
	cells = {},
	dirty = true,
	poiScanCursor = 1,
}

function NpcSpatialCellKey(x, y)
	return tostring(x) .. ":" .. tostring(y)
end

function NpcSpatialCellFromPoint(u, v)
	local cellSize = tonumber(npcSpatial.cellSize) or NPC_SPATIAL_GRID_CELL
	if cellSize <= NAV_EPS then
		cellSize = NPC_SPATIAL_GRID_CELL
	end
	local cx = math.floor(Clamp(tonumber(u) or 0.5, 0, 1) / cellSize)
	local cy = math.floor(Clamp(tonumber(v) or 0.5, 0, 1) / cellSize)
	return cx, cy, NpcSpatialCellKey(cx, cy)
end

function NpcSpatialDetach(npc)
	if not npc then
		return
	end
	local key = npc._spatialKey
	if type(key) ~= "string" or key == "" then
		npc._spatialKey = nil
		return
	end
	local cell = npcSpatial.cells[key]
	if type(cell) == "table" then
		for i = #cell, 1, -1 do
			if cell[i] == npc then
				cell[i] = cell[#cell]
				cell[#cell] = nil
				break
			end
		end
		if #cell == 0 then
			npcSpatial.cells[key] = nil
		end
	end
	npc._spatialKey = nil
end

function NpcSpatialAttach(npc)
	if not npc then
		return
	end
	local cx, cy, key = NpcSpatialCellFromPoint(npc.u, npc.v)
	local cell = npcSpatial.cells[key]
	if not cell then
		cell = {}
		npcSpatial.cells[key] = cell
	end
	cell[#cell + 1] = npc
	npc._spatialX = cx
	npc._spatialY = cy
	npc._spatialKey = key
end

function NpcSpatialReindex(npc)
	if not npcSpatial.enabled then
		return
	end
	local cx, cy, key = NpcSpatialCellFromPoint(npc and npc.u, npc and npc.v)
	if key == npc._spatialKey then
		npc._spatialX = cx
		npc._spatialY = cy
		return
	end
	NpcSpatialDetach(npc)
	local cell = npcSpatial.cells[key]
	if not cell then
		cell = {}
		npcSpatial.cells[key] = cell
	end
	cell[#cell + 1] = npc
	npc._spatialX = cx
	npc._spatialY = cy
	npc._spatialKey = key
end


end

return Modules
