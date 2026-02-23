local ADDON, ns = ...

ns.BioRules = ns.BioRules or {}
local Rules = ns.BioRules

function Rules.NormalizeVisibility(bio)
	local vis = bio and bio.visibility
	if type(vis) ~= "string" or vis == "" then
		return "public"
	end
	return vis
end

function Rules.IsPendingDeletion(bio, now)
	local ts = tonumber(bio and bio.deletedAt or 0) or 0
	local t = now or time()
	return ts > 0 and ts > t
end

function Rules.IsPublicPublished(bio, opts)
	if type(bio) ~= "table" then
		return false
	end
	if bio.status ~= "published" then
		return false
	end
	if Rules.NormalizeVisibility(bio) == "private" then
		return false
	end
	local allowPending = opts and opts.allowPending
	if not allowPending then
		local now = opts and opts.now or time()
		if Rules.IsPendingDeletion(bio, now) then
			return false
		end
	end
	return true
end

function Rules.FormatDeletionCountdown(ts, now)
	local diff = (tonumber(ts or 0) or 0) - (now or time())
	if diff <= 0 then
		return "moins d'une minute"
	end
	local days = math.floor(diff / 86400)
	local hours = math.floor((diff % 86400) / 3600)
	local mins = math.floor((diff % 3600) / 60)
	if days > 0 then
		return ("%d jour%s"):format(days, days > 1 and "s" or "")
	end
	if hours > 0 then
		return ("%d h"):format(hours)
	end
	if mins > 0 then
		return ("%d min"):format(mins)
	end
	return "moins d'une minute"
end
