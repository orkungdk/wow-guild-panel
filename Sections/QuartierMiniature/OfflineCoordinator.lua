local ADDON, ns = ...

ns.QuartierMiniature = ns.QuartierMiniature or {}
local QM = ns.QuartierMiniature

QM.OfflineCoordinator = QM.OfflineCoordinator or {}
local OfflineCoordinator = QM.OfflineCoordinator

local function Clamp(v, minV, maxV)
	if v < minV then
		return minV
	end
	if v > maxV then
		return maxV
	end
	return v
end

local function GetEpochNowDefault()
	local serverNow = (GetServerTime and GetServerTime()) or nil
	if serverNow then
		return math.max(0, tonumber(serverNow) or 0)
	end
	return math.max(0, tonumber(time and time() or 0) or 0)
end

local function PushDetailedSegments(out, totalSec)
	local remaining = math.max(0, tonumber(totalSec) or 0)
	if remaining <= 0 then
		return
	end

	-- Keep some short-range fidelity, then quickly increase step size to avoid
	-- thousands of simulation iterations on long catch-ups.
	local fastSec = math.min(remaining, 5 * 60)
	if fastSec > 0 then
		out[#out + 1] = {
			kind = "detail",
			step = 1.0,
			seconds = fastSec,
			remaining = fastSec,
		}
		remaining = remaining - fastSec
	end

	local midWindow = (60 * 60) - (5 * 60)
	local midSec = math.min(remaining, midWindow)
	if midSec > 0 then
		out[#out + 1] = {
			kind = "detail",
			step = 5.0,
			seconds = midSec,
			remaining = midSec,
		}
		remaining = remaining - midSec
	end
	local longWindow = (6 * 60 * 60) - (60 * 60)
	local longSec = math.min(remaining, longWindow)
	if longSec > 0 then
		out[#out + 1] = {
			kind = "detail",
			step = 20.0,
			seconds = longSec,
			remaining = longSec,
		}
		remaining = remaining - longSec
	end
	if remaining > 0 then
		out[#out + 1] = {
			kind = "detail",
			step = 60.0,
			seconds = remaining,
			remaining = remaining,
		}
	end
end

local function PushCoarseSegments(out, totalSec)
	local remaining = math.max(0, tonumber(totalSec) or 0)
	if remaining <= 0 then
		return
	end
	local chunkA = math.min(remaining, 2 * 60 * 60)
	if chunkA > 0 then
		out[#out + 1] = {
			kind = "detail",
			step = 60.0,
			seconds = chunkA,
			remaining = chunkA,
		}
		remaining = remaining - chunkA
	end
	local chunkB = math.min(remaining, 10 * 60 * 60)
	if chunkB > 0 then
		out[#out + 1] = {
			kind = "detail",
			step = 120.0,
			seconds = chunkB,
			remaining = chunkB,
		}
		remaining = remaining - chunkB
	end
	if remaining > 0 then
		out[#out + 1] = {
			kind = "detail",
			step = 300.0,
			seconds = remaining,
			remaining = remaining,
		}
	end
end

local function BuildCatchupSegments(totalSec, detailCapSec, daySec, simulatedMaxSec, averageMinSec, averageMaxSec)
	local total = math.max(0, tonumber(totalSec) or 0)
	if total <= 0 then
		return {}
	end
	local simMax = math.max(0, tonumber(simulatedMaxSec) or (90 * 60))
	local avgMin = math.max(simMax, tonumber(averageMinSec) or simMax)
	local avgMax = math.max(avgMin, tonumber(averageMaxSec) or (2 * 60 * 60))

	-- Tier 1: direct simulation (small/medium elapsed).
	if total <= simMax then
		local out = {}
		local detailedSec = math.min(total, math.max(0, tonumber(detailCapSec) or 0))
		PushDetailedSegments(out, detailedSec)
		local overflow = math.max(0, total - detailedSec)
		local oneDay = math.max(1, tonumber(daySec) or (24 * 60 * 60))
		local extraDays = math.floor(overflow / oneDay)
		local tailSec = overflow - (extraDays * oneDay)
		if extraDays > 0 then
			out[#out + 1] = {
				kind = "approx_days",
				days = extraDays,
				seconds = extraDays * oneDay,
			}
		end
		if tailSec > 0 then
			PushCoarseSegments(out, tailSec)
		end
		return out
	end

	-- Tier 2: averaged approximation.
	if total >= avgMin and total <= avgMax then
		return {
			{
				kind = "approx_seconds",
				mode = "average",
				seconds = total,
			},
		}
	end

	-- Tier 3: very long fallback.
	return {
		{
			kind = "approx_seconds",
			mode = "long",
			seconds = total,
		},
	}
end

function OfflineCoordinator.Create(opts)
	opts = type(opts) == "table" and opts or {}
	local trackWhenUnavailable = opts.trackWhenUnavailable ~= false

	local hardCapSec = math.max(60, tonumber(opts.hardCapSec) or (90 * 24 * 60 * 60))
	local graceSec = Clamp(tonumber(opts.graceSec) or 120, 0, hardCapSec)
	local detailCapSec = Clamp(tonumber(opts.detailCapSec) or (24 * 60 * 60), 0, hardCapSec)
	local daySec = math.max(60, tonumber(opts.daySec) or (24 * 60 * 60))
	local overlayThresholdSec = math.max(0, tonumber(opts.overlayThresholdSec) or 20)
	local frameBudgetMs = math.max(1, tonumber(opts.frameBudgetMs) or 22)
	local frameMaxSteps = math.max(1, math.floor(tonumber(opts.frameMaxSteps) or 650))
	local boostFramesMax = math.max(0, math.floor(tonumber(opts.boostFrames) or 10))
	local boostBudgetMs = math.max(frameBudgetMs, tonumber(opts.boostBudgetMs) or 90)
	local boostMaxSteps = math.max(frameMaxSteps, math.floor(tonumber(opts.boostMaxSteps) or 2400))
	local backgroundTickerSec = math.max(1, tonumber(opts.backgroundTickerSec) or 5)
	local backgroundFlushSec = math.max(backgroundTickerSec, tonumber(opts.backgroundFlushSec) or 60)
	local backgroundLiveWhileHidden = opts.backgroundLiveWhileHidden == true
	local cloudsMinSec = math.max(0, tonumber(opts.cloudsMinSec) or 1.0)
	local resolveMinSec = math.max(0, tonumber(opts.resolveMinSec) or 0.20)
	local minCatchupSec = math.max(0, tonumber(opts.minCatchupSec) or 2.0)
	local simulatedMaxSec = math.max(0, tonumber(opts.simulatedMaxSec) or (90 * 60))
	local averageMinSec = math.max(simulatedMaxSec, tonumber(opts.averageMinSec) or simulatedMaxSec)
	local averageMaxSec = math.max(averageMinSec, tonumber(opts.averageMaxSec) or (2 * 60 * 60))

	local isSectionShown = type(opts.isSectionShown) == "function" and opts.isSectionShown or function()
		return false
	end
	local getMapId = type(opts.getMapId) == "function" and opts.getMapId or function()
		return "default"
	end
	local getBootstrapEpoch = type(opts.getBootstrapPersistenceEpoch) == "function"
			and opts.getBootstrapPersistenceEpoch
		or function()
			return 0
		end
	local refreshTimeRuntime = type(opts.refreshTimeRuntime) == "function" and opts.refreshTimeRuntime or nil
	local stepSimulation = type(opts.stepSimulation) == "function" and opts.stepSimulation or nil
	local applyApproximateOfflineDays = type(opts.applyApproximateOfflineDays) == "function"
			and opts.applyApproximateOfflineDays
		or nil
	local applyApproximateOfflineSeconds = type(opts.applyApproximateOfflineSeconds) == "function"
			and opts.applyApproximateOfflineSeconds
		or nil
	local beginVirtualClock = type(opts.beginVirtualClock) == "function" and opts.beginVirtualClock or nil
	local endVirtualClock = type(opts.endVirtualClock) == "function" and opts.endVirtualClock or nil
	local flushPersistenceNow = type(opts.flushPersistenceNow) == "function" and opts.flushPersistenceNow or nil
	local setTimePaused = type(opts.setTimePaused) == "function" and opts.setTimePaused or nil
	local onOverlay = type(opts.onOverlay) == "function" and opts.onOverlay or nil
	local onCatchupFinished = type(opts.onCatchupFinished) == "function" and opts.onCatchupFinished or nil
	local getEpochNow = type(opts.getEpochNow) == "function" and opts.getEpochNow or GetEpochNowDefault
	local getClockSeconds = type(opts.getClockSeconds) == "function" and opts.getClockSeconds or nil
	local isDevMode = type(opts.isDevMode) == "function" and opts.isDevMode or function()
		return false
	end
	local debugPrint = (opts.debugPrint ~= false) and (isDevMode() == true)

	local mode = "none"
	local inStep = false
	local backgroundFlushAccum = 0
	local lastUnavailableEpoch = nil
	local lastUnavailableMapId = nil
	local backgroundTickCount = 0

	local catchup = {
		active = false,
		phase = "none",
		segments = nil,
		segmentIndex = 1,
		virtualClock = false,
		mapId = nil,
		totalSeconds = 0,
		resolvedSeconds = 0,
		lastLog = "",
		boostFrames = 0,
		showOverlay = false,
		cloudsRemaining = 0,
		resolveRemaining = 0,
		resolveApplied = false,
	}

	local ticker = nil
	local eventFrame = CreateFrame("Frame")

	local function DebugPrint(msg)
		if not debugPrint then
			return
		end
		print("|cffffd100[WoW Guilde]|r QM " .. tostring(msg or ""))
	end

	local function BuildClockDebugSuffix()
		if not getClockSeconds then
			return ""
		end
		local clockSec = tonumber(getClockSeconds()) or 0
		return string.format(" clock=%.1fs", clockSec)
	end

	local function SetOverlay(show, doneSec, totalSec, logText)
		if onOverlay then
			onOverlay(show == true, doneSec, totalSec, logText)
		end
	end

	local function SetModeForVisibility()
		if catchup.active then
			mode = "catchup"
		elseif isSectionShown() then
			mode = "visible_live"
		else
			mode = "background_live"
		end
	end

	local function StopCatchup(flushPersistence)
		if catchup.virtualClock and endVirtualClock then
			endVirtualClock()
		end
		if flushPersistence and flushPersistenceNow then
			flushPersistenceNow()
		end
		catchup.active = false
		catchup.phase = "none"
		catchup.segments = nil
		catchup.segmentIndex = 1
		catchup.virtualClock = false
		catchup.mapId = nil
		catchup.totalSeconds = 0
		catchup.resolvedSeconds = 0
		catchup.lastLog = ""
		catchup.boostFrames = 0
		catchup.showOverlay = false
		catchup.cloudsRemaining = 0
		catchup.resolveRemaining = 0
		catchup.resolveApplied = false
		SetOverlay(false, 0, 0, nil)
		SetModeForVisibility()
	end

	local function StartCatchup(elapsedSec)
		if not trackWhenUnavailable then
			return false
		end
		if not stepSimulation then
			return false
		end
		local elapsed = Clamp(tonumber(elapsedSec) or 0, 0, hardCapSec)
		if elapsed <= graceSec then
			return false
		end
		local effective = math.max(0, elapsed - graceSec)
		if effective < minCatchupSec then
			return false
		end
		local segments =
			BuildCatchupSegments(effective, detailCapSec, daySec, simulatedMaxSec, averageMinSec, averageMaxSec)
		if type(segments) ~= "table" or #segments < 1 then
			return false
		end

		StopCatchup(false)
		catchup.active = true
		catchup.phase = "clouds"
		catchup.segments = segments
		catchup.segmentIndex = 1
		catchup.mapId = tostring(getMapId() or "default")
		catchup.virtualClock = beginVirtualClock ~= nil
		catchup.totalSeconds = math.max(0.001, effective + cloudsMinSec + resolveMinSec)
		catchup.resolvedSeconds = 0
		catchup.lastLog = "Chargement des nuages..."
		catchup.boostFrames = boostFramesMax
		catchup.showOverlay = true
		catchup.cloudsRemaining = cloudsMinSec
		catchup.resolveRemaining = resolveMinSec
		catchup.resolveApplied = false
		mode = "catchup"

		if beginVirtualClock then
			beginVirtualClock(GetTime and GetTime() or 0)
		end
		DebugPrint(
			string.format(
				"catchup start elapsed=%ds effective=%ds segments=%d overlay=%s%s",
				math.floor(elapsed + 0.5),
				math.floor(effective + 0.5),
				#segments,
				catchup.showOverlay and "on" or "off",
				BuildClockDebugSuffix()
			)
		)
		SetOverlay(catchup.showOverlay, 0, catchup.totalSeconds, catchup.lastLog)
		return true
	end

	local function ProcessCatchupFrame(frameElapsed)
		if not catchup.active then
			return false
		end
		if tostring(getMapId() or "default") ~= tostring(catchup.mapId or "default") then
			StopCatchup(false)
			return true
		end

		local startMs = (debugprofilestop and debugprofilestop()) or 0
		local stepsThisFrame = 0
		local frameDt = math.max(0, tonumber(frameElapsed) or 0)
		if frameDt <= 0 then
			frameDt = 1 / 60
		end
		local localBudgetMs = frameBudgetMs
		local localMaxSteps = frameMaxSteps
		if catchup.boostFrames > 0 then
			catchup.boostFrames = catchup.boostFrames - 1
			localBudgetMs = boostBudgetMs
			localMaxSteps = boostMaxSteps
		end

		while catchup.active do
			if catchup.phase == "clouds" then
				local consume = math.min(catchup.cloudsRemaining, frameDt)
				catchup.cloudsRemaining = math.max(0, catchup.cloudsRemaining - consume)
				catchup.resolvedSeconds = math.min(catchup.totalSeconds, catchup.resolvedSeconds + consume)
				catchup.lastLog = "Chargement des nuages..."
				if catchup.cloudsRemaining <= 0 then
					catchup.phase = "simulate"
					catchup.lastLog = "Simulation PNJ..."
				end
				break
			end

			if catchup.phase == "resolve" then
				if not catchup.resolveApplied then
					catchup.resolveApplied = true
					if onCatchupFinished then
						onCatchupFinished()
					end
				end
				local consume = math.min(catchup.resolveRemaining, frameDt)
				catchup.resolveRemaining = math.max(0, catchup.resolveRemaining - consume)
				catchup.resolvedSeconds = math.min(catchup.totalSeconds, catchup.resolvedSeconds + consume)
				catchup.lastLog = "Resolution PNJ..."
				if catchup.resolveRemaining <= 0 then
					catchup.resolvedSeconds = catchup.totalSeconds
					DebugPrint(
						string.format(
							"catchup done resolved=%ds%s",
							math.floor(catchup.resolvedSeconds + 0.5),
							BuildClockDebugSuffix()
						)
					)
					StopCatchup(true)
				end
				break
			end

			-- Default simulation phase.
			catchup.phase = "simulate"
			local seg = catchup.segments and catchup.segments[catchup.segmentIndex]
			if type(seg) ~= "table" then
				catchup.phase = "resolve"
				catchup.lastLog = "Resolution PNJ..."
				break
			end

			local kind = tostring(seg.kind or "")
			if kind == "detail" then
				local remaining = math.max(0, tonumber(seg.remaining) or 0)
				if remaining <= 0 then
					catchup.segmentIndex = catchup.segmentIndex + 1
				else
					local step = math.max(0.01, tonumber(seg.step) or 1.0)
					if step > remaining then
						step = remaining
					end
					if refreshTimeRuntime then
						refreshTimeRuntime(true, step)
					end
					stepSimulation(step, {
						render = false,
						persist = false,
					})
					seg.remaining = remaining - step
					catchup.resolvedSeconds = catchup.resolvedSeconds + step
					catchup.lastLog = string.format(
						"Simulation PNJ %d/%d: reste %ds",
						catchup.segmentIndex,
						#catchup.segments,
						math.max(0, math.floor(seg.remaining + 0.5))
					)
				end
			elseif kind == "approx_days" then
				local days = math.max(0, math.floor(tonumber(seg.days) or 0))
				local seconds = math.max(0, tonumber(seg.seconds) or (days * daySec))
				if seconds > 0 and refreshTimeRuntime then
					refreshTimeRuntime(true, seconds)
				end
				if days > 0 and applyApproximateOfflineDays then
					applyApproximateOfflineDays(days, {
						persist = false,
					})
				end
				catchup.resolvedSeconds = catchup.resolvedSeconds + seconds
				catchup.lastLog = string.format("Approximation sur %d jour(s)...", days)
				catchup.segmentIndex = catchup.segmentIndex + 1
			elseif kind == "approx_seconds" then
				local seconds = math.max(0, tonumber(seg.seconds) or 0)
				local modeTag = tostring(seg.mode or "average")
				if seconds > 0 and refreshTimeRuntime then
					refreshTimeRuntime(true, seconds)
				end
				if seconds > 0 and applyApproximateOfflineSeconds then
					applyApproximateOfflineSeconds(seconds, {
						persist = false,
						mode = modeTag,
					})
				elseif seconds > 0 and applyApproximateOfflineDays then
					applyApproximateOfflineDays(math.max(1, math.floor(seconds / daySec)), {
						persist = false,
					})
				end
				catchup.resolvedSeconds = catchup.resolvedSeconds + seconds
				if modeTag == "long" then
					catchup.lastLog = "Resolution longue: besoins moyens + repositionnement PNJ..."
				else
					catchup.lastLog = "Resolution moyenne des besoins PNJ..."
				end
				catchup.segmentIndex = catchup.segmentIndex + 1
			else
				catchup.segmentIndex = catchup.segmentIndex + 1
			end

			stepsThisFrame = stepsThisFrame + 1
			if stepsThisFrame >= localMaxSteps then
				break
			end
			if debugprofilestop and (debugprofilestop() - startMs) >= localBudgetMs then
				break
			end
		end

		SetOverlay(catchup.showOverlay, catchup.resolvedSeconds, catchup.totalSeconds, catchup.lastLog)
		return true
	end

	local function RunBackgroundTick()
		if not backgroundLiveWhileHidden then
			return
		end
		if not trackWhenUnavailable then
			return
		end
		if inStep then
			return
		end
		if catchup.active then
			return
		end
		if isSectionShown() then
			mode = "visible_live"
			return
		end
		if not stepSimulation then
			return
		end
		inStep = true
		mode = "background_live"
		if setTimePaused then
			setTimePaused(false)
		end
		if refreshTimeRuntime then
			refreshTimeRuntime(true, backgroundTickerSec)
		end
		stepSimulation(backgroundTickerSec, {
			render = false,
			persist = false,
		})
		backgroundTickCount = backgroundTickCount + 1
		if (backgroundTickCount % 6) == 0 then
			DebugPrint(
				string.format(
					"background tick dt=%.1fs total=%.1fs%s",
					backgroundTickerSec,
					backgroundTickCount * backgroundTickerSec,
					BuildClockDebugSuffix()
				)
			)
		end
		backgroundFlushAccum = backgroundFlushAccum + backgroundTickerSec
		if backgroundFlushAccum >= backgroundFlushSec then
			backgroundFlushAccum = 0
			if flushPersistenceNow then
				flushPersistenceNow()
			end
			DebugPrint("background flush persistence")
		end
		inStep = false
	end

	local E = {}

	function E:HandleOnShow()
		mode = "visible_live"
		if setTimePaused then
			setTimePaused(false)
		end
		if not trackWhenUnavailable then
			lastUnavailableEpoch = nil
			lastUnavailableMapId = nil
			SetOverlay(false, 0, 0, nil)
			return false, 0
		end

		local nowEpoch = math.max(0, tonumber(getEpochNow()) or 0)
		local activeMapId = tostring(getMapId() or "default")
		local hadLocalUnavailable = false
		local localUnavailableEpoch = 0

		if tonumber(lastUnavailableEpoch) and tonumber(lastUnavailableEpoch) > 0 then
			if tostring(lastUnavailableMapId or "default") == activeMapId then
				hadLocalUnavailable = true
				localUnavailableEpoch = tonumber(lastUnavailableEpoch) or 0
			end
		end

		lastUnavailableEpoch = nil
		lastUnavailableMapId = nil

		if hadLocalUnavailable then
			local elapsedSec = Clamp(nowEpoch - localUnavailableEpoch, 0, hardCapSec)
			DebugPrint(
				string.format("on show from local hide elapsed=%ds%s", math.floor(elapsedSec + 0.5), BuildClockDebugSuffix())
			)
			if elapsedSec > graceSec then
				return StartCatchup(elapsedSec), elapsedSec
			end
			SetOverlay(false, 0, 0, nil)
			return false, elapsedSec
		end

		local baselineEpoch = tonumber(getBootstrapEpoch()) or 0
		if baselineEpoch > 0 then
			local elapsedSec = Clamp(nowEpoch - baselineEpoch, 0, hardCapSec)
			DebugPrint(string.format("on show elapsed=%ds%s", math.floor(elapsedSec + 0.5), BuildClockDebugSuffix()))
			if elapsedSec > graceSec then
				return StartCatchup(elapsedSec), elapsedSec
			end
		end
		SetOverlay(false, 0, 0, nil)
		return false, 0
	end

	function E:HandleOnHide()
		StopCatchup(false)
		if flushPersistenceNow then
			flushPersistenceNow()
		end
		if not trackWhenUnavailable then
			mode = "none"
			return
		end
		lastUnavailableEpoch = math.max(0, tonumber(getEpochNow()) or 0)
		lastUnavailableMapId = tostring(getMapId() or "default")
		backgroundTickCount = 0
		DebugPrint("on hide -> background live")
		if setTimePaused then
			setTimePaused(false)
		end
		mode = "background_live"
		backgroundFlushAccum = 0
	end

	function E:HandleVisibleFrame(elapsed)
		if inStep then
			return true
		end
		if catchup.active then
			inStep = true
			local ok, handled = pcall(ProcessCatchupFrame, elapsed)
			inStep = false
			if not ok then
				StopCatchup(false)
				return true
			end
			return handled == true
		end
		mode = "visible_live"
		return false
	end

	function E:Shutdown()
		if ticker and ticker.Cancel then
			ticker:Cancel()
		end
		ticker = nil
		if eventFrame then
			eventFrame:UnregisterAllEvents()
			eventFrame:SetScript("OnEvent", nil)
		end
		StopCatchup(false)
		mode = "none"
	end

	function E:GetMode()
		return mode
	end

	if C_Timer and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(backgroundTickerSec, RunBackgroundTick)
	end

	eventFrame:RegisterEvent("PLAYER_LOGOUT")
	eventFrame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGOUT" and flushPersistenceNow then
			flushPersistenceNow()
		end
	end)

	SetModeForVisibility()
	return E
end

return OfflineCoordinator
