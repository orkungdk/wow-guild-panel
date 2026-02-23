--=====================================================================
-- Emotes : historique éphémère (RAM), zéro trace en DB
--=====================================================================
local ADDON, ns = ...
ns.Emotes = ns.Emotes or {}
local Emotes = ns.Emotes
local EventBus = ns.EventBus

-- =================== Préfs (sans history) ===================
local function Defaults()
	return {
		enabled = true,
		sound = true,
		queueMax = 10,
		dndCompetitive = false,
		mutes = {}, -- aucune donnée d'émote persistée
	}
end

local function GetStore()
	if ns and ns.Prefs and ns.Prefs.GetSocial then
		local t = ns.Prefs.GetSocial("Emotes", nil)
		if type(t) ~= "table" then
			t = Defaults()
			if ns.Prefs.SetSocial then
				ns.Prefs.SetSocial("Emotes", t)
			end
		end
		return t
	end
	return Defaults()
end

local function DBE()
	local D = GetStore()
	D.enabled = (D.enabled ~= false)
	D.sound = (D.sound ~= false)
	D.queueMax = tonumber(D.queueMax or 10) or 10
	D.dndCompetitive = (D.dndCompetitive == true)
	D.mutes = D.mutes or {}

	-- purge immédiate d’anciennes versions
	if D.history ~= nil then
		wipe(D.history)
		D.history = nil
	end
	return D
end

function Emotes.GetPrefs()
	return DBE()
end

-- =================== Utilitaires ===================
local function MyFullName()
	local n, r = UnitFullName and UnitFullName("player")
	if not n then
		n = UnitName and UnitName("player") or "?"
	end
	if r and r ~= "" then
		return n .. "-" .. r
	end
	return n
end

local function IsCompetitiveInstance()
	if not IsInInstance then
		return false
	end
	local inInst, instType = IsInInstance()
	if not inInst then
		return false
	end
	return instType ~= "none"
end

local function PushGuildPrefs(D)
	if not (ns and ns.DB and ns.DB.UpsertGuildMemberPrefs and ns.DB.GetMyUID and ns.DB.GetGuildUID) then
		return
	end
	local gid = ns.DB:GetGuildUID()
	local uid = ns.DB:GetMyUID()
	if gid and uid and D then
		local ts = time()
		ns.DB:UpsertGuildMemberPrefs(gid, uid, { emotesEnabled = D.enabled, emotesSound = D.sound, updatedAt = ts })
		if ns.Comms and ns.Comms.SendGuildMemberPrefs then
			ns.Comms:SendGuildMemberPrefs(
				gid,
				uid,
				{ emotesEnabled = D.enabled, emotesSound = D.sound, updatedAt = ts }
			)
		end
		if EventBus and EventBus.Emit then
			EventBus.Emit(
				"WG_MEMBER_PREFS_CHANGED",
				gid,
				uid,
				{ emotesEnabled = D.enabled, emotesSound = D.sound, updatedAt = ts }
			)
		end
		if ns and ns.Comms and ns.Comms.DEV_MODE then
			print(
				("|cffffd100[WoW Guilde]|r PREFS Emotes enabled=%s sound=%s"):format(
					tostring(D.enabled),
					tostring(D.sound)
				)
			)
		end
	end
end

local function PurgeDBHistoryNow()
	local D = GetStore()
	if type(D) == "table" and D.history ~= nil then
		wipe(D.history)
		D.history = nil
	end
end

-- =================== Catalogue (en code, pas en DB) ===================
Emotes.Catalog = {
	thanks = {
		label = "Merci",
		icon = 3193419,
		phrases = {
			"te remercie chaleureusement pour ton aide",
			"t’adresse toute sa gratitude avec un grand sourire",
			"te lance un regard sincère plein de reconnaissance",
			"exprime sa profonde gratitude envers toi",
			"te félicite et te remercie dans le même élan",
		},
	},
	wow = {
		label = "Étonnement",
		icon = 237552,
		phrases = {
			"est impressionné par ton exploit et reste bouche bée",
			"te regarde avec de grands yeux, complètement étonné",
			"ne peut cacher son émerveillement face à ta performance",
			"s’exclame d’étonnement devant ton geste",
			"semble abasourdi et admiratif en même temps",
		},
	},
	wellplayed = {
		label = "Bravo",
		icon = 237554,
		phrases = {
			"te félicite pour ton talent et ta réussite",
			"t’adresse des félicitations appuyées avec respect",
			"reconnaît ton habileté et salue ton jeu",
			"te lance un sourire admiratif en guise de bravo",
			"te félicite chaleureusement pour ta maîtrise",
		},
	},
	greetings = {
		label = "Bonjour",
		icon = 5788303,
		phrases = {
			"te salue avec enthousiasme et bonne humeur",
			"t’adresse une chaleureuse salutation amicale",
			"vient vers toi avec un signe de la main et un sourire",
			"te souhaite une agréable journée avec respect",
			"s’incline légèrement pour te saluer",
		},
	},
	oops = {
		label = "Erreur",
		icon = 3718862,
		phrases = {
			"semble confus et admet son erreur devant toi",
			"s’excuse d’un ton maladroit en se grattant la tête",
			"rit nerveusement et reconnaît sa bourde",
			"te lance un regard gêné en murmurant de s’être trompé",
			"rougit légèrement en s’excusant de sa maladresse",
		},
	},
	excuse = {
		label = "Excuse",
		icon = 237555,
		phrases = {
			"te demande pardon avec sincérité",
			"s’excuse humblement pour sa conduite",
			"te lance un regard désolé en murmurant des excuses",
			"t’adresse des excuses franches et respectueuses",
			"reconnaît ses torts et s’excuse immédiatement",
		},
	},
	threaten = {
		label = "Menace",
		icon = 1035042,
		phrases = {
			"te fixe d’un regard sombre et menaçant",
			"t’adresse une promesse de vengeance glaciale",
			"laisse échapper un rire inquiétant en te pointant du doigt",
			"te murmure que tu ne sortiras pas indemne de cette rencontre",
			"serre les poings et te lance un avertissement redoutable",
		},
	},
	bye = {
		label = "Au revoir",
		icon = 3750311,
		phrases = {
			"te fait un signe de la main en s’éloignant",
			"t’adresse un dernier sourire avant de partir",
			"te souhaite une bonne route avant de disparaître",
			"salue la compagnie et prend congé poliment",
			"te quitte en te souhaitant bonne continuation",
		},
	},
	gg = {
		label = "GG !",
		icon = 3750314,
		phrases = {
			"salue ton jeu avec un grand bravo",
			"te félicite en lançant un franc GG",
			"reconnaît ta belle performance et applaudit",
			"te lance un tonitruant GG plein d’admiration",
			"souligne ton talent avec un GG bien mérité",
		},
	},
}

-- =================== Historique ÉPHÉMÈRE uniquement ===================
local MAX_LOG = 100
local SessionHistory = {} -- jamais sauvegardé

local function PushSession(entry)
	SessionHistory[#SessionHistory + 1] = entry
	if #SessionHistory > MAX_LOG then
		table.remove(SessionHistory, 1)
	end
end

local function FlushSession()
	wipe(SessionHistory)
end

function Emotes.GetHistory()
	local out = {}
	for i = 1, #SessionHistory do
		out[i] = SessionHistory[i]
	end
	return out
end

-- =================== API publique ===================
function Emotes.SetEnabled(v)
	local D = DBE()
	D.enabled = not not v
	if D.enabled == false then
		D.sound = false
	end
	PushGuildPrefs(D)
end
function Emotes.SetSound(v)
	local D = DBE()
	D.sound = not not v
	PushGuildPrefs(D)
end
function Emotes.ToggleMute(nameRealm)
	if not nameRealm or nameRealm == "" then
		return
	end
	local D = DBE()
	D.mutes[nameRealm] = D.mutes[nameRealm] and nil or true
end
function Emotes.IsMuted(nameRealm)
	return DBE().mutes[nameRealm] == true
end

local function ResolveHeroPseudo(nameRealm)
	if not nameRealm or nameRealm == "" then
		return nil
	end
	local cache = ns and ns.Utils and ns.Utils.PSEUDO_CACHE or nil
	if cache then
		local rec = cache[nameRealm]
		if not rec and Ambiguate then
			rec = cache[Ambiguate(nameRealm, "none")]
		end
		local alias = rec and rec.alias
		if alias and alias ~= "" then
			return alias
		end
	end
	if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
		local short = Ambiguate and Ambiguate(nameRealm, "none") or nameRealm
		local n = GetNumGuildMembers() or 0
		for i = 1, n do
			local rosterName, _, _, _, _, _, note = GetGuildRosterInfo(i)
			if rosterName and rosterName ~= "" then
				local full = (ns.FullFromRosterName and ns.FullFromRosterName(rosterName)) or rosterName
				local rosterShort = Ambiguate and Ambiguate(full, "none") or full
				if nameRealm == full or nameRealm == rosterName or short == full or short == rosterShort then
					local alias = (ns.Utils and ns.Utils.AliasFromNote and ns.Utils.AliasFromNote(note)) or nil
					if (not alias or alias == "") and ns.Utils and ns.Utils.ParsePseudo then
						alias = ns.Utils.ParsePseudo(note, rosterName)
					end
					if alias and alias ~= "" then
						return alias
					end
					break
				end
			end
		end
	end
	if ns.Utils and ns.Utils.BaseName then
		return ns.Utils.BaseName(nameRealm)
	end
	return nameRealm
end

function Emotes.ResolveHeroPseudo(nameRealm)
	return ResolveHeroPseudo(nameRealm)
end

-- Envoi (clé uniquement)
function Emotes.Send(target, key, opts)
	local def = Emotes.Catalog[key]
	if not def then
		print(("Émotion « %s » inconnue."):format(tostring(key)))
		return
	end
	local D = DBE()
	if D.dndCompetitive and IsCompetitiveInstance() then
		return
	end
	local ctx = (type(opts) == "table" and type(opts.context) == "table") and opts.context or nil
	if ctx then
		local actorPseudo = ResolveHeroPseudo(MyFullName())
		if actorPseudo and actorPseudo ~= "" and tostring(ctx.actorPseudo or "") == "" then
			local out = {}
			for k, v in pairs(ctx) do
				out[k] = v
			end
			out.actorPseudo = actorPseudo
			ctx = out
		end
	end
	if ns and ns.Comms and ns.Comms.SendEmote then
		ns.Comms:SendEmote(target, key, ctx) -- ne jamais envoyer de texte DB
	else
		if DoEmote then
			local map = { sad = "CRY", happy = "HAPPY", cheer = "CHEER", love = "LOVE", angry = "ANGRY" }
			DoEmote(map[key] or "CHEER", target)
		end
	end
end

-- Réception
function Emotes.Receive(key, from, ts, context)
	local D = DBE()
	if not D.enabled then
		return
	end
	if D.dndCompetitive and IsCompetitiveInstance() then
		return
	end
	if from == MyFullName() and not ns.Emotes._testMode then
		return
	end
	if Emotes.IsMuted(from) then
		return
	end

	local def = Emotes.Catalog[key]
	if not def then
		return
	end
	local displayFrom = (type(context) == "table" and tostring(context.actorPseudo or "") ~= "" and context.actorPseudo)
		or ResolveHeroPseudo(from)
		or from

	-- Historique uniquement en RAM
	PushSession({ time = ts or time(), from = from, displayFrom = displayFrom, key = key, label = def.label })

	-- UI immédiate
	if ns.UI and ns.UI.EmoteToast and ns.UI.EmoteToast.Queue then
		ns.UI.EmoteToast.Queue(key, from, def.label, { fromPseudo = displayFrom, context = context })
	end

	-- Purge DB dès que possible, même si un autre module a recréé 'history'
	C_Timer.After(0, PurgeDBHistoryNow)
end

-- Test local
function Emotes.DebugLocal(key, from, opts)
	ns.Emotes._testMode = true
	Emotes.Receive(
		key or "greetings",
		from or "Testeur-RP",
		time(),
		(type(opts) == "table" and type(opts.context) == "table") and opts.context or nil
	)
	ns.Emotes._testMode = nil
end

-- =================== Sécurité : zéro trace au disque ===================
if EventBus and EventBus.On then
	EventBus.On("ADDON_LOADED", function(_, arg1)
		if arg1 == ADDON then
			DBE() -- normalise et purge anciennes traces
			PurgeDBHistoryNow() -- par sécurité
			FlushSession() -- session propre
			PushGuildPrefs(DBE())
		end
	end)
	EventBus.On("PLAYER_LOGOUT", function()
		PurgeDBHistoryNow() -- garantie: aucune chaîne en clair en DB
		FlushSession()
	end)
	EventBus.On("PLAYER_LEAVING_WORLD", function()
		PurgeDBHistoryNow()
		FlushSession()
	end)
	EventBus.On("PLAYER_ENTERING_WORLD", function()
		local D = DBE()
		local inInst = IsCompetitiveInstance()
		if D.dndCompetitive and inInst and not Emotes._dndAutoActive then
			Emotes._dndAutoActive = true
			Emotes._dndAutoPrev = { enabled = D.enabled, sound = D.sound }
			D.enabled = false
			D.sound = false
			PushGuildPrefs(D)
		elseif (not D.dndCompetitive or not inInst) and Emotes._dndAutoActive then
			local prev = Emotes._dndAutoPrev or {}
			D.enabled = prev.enabled ~= false
			D.sound = prev.sound ~= false
			Emotes._dndAutoActive = nil
			Emotes._dndAutoPrev = nil
			PushGuildPrefs(D)
		end
	end)
end
