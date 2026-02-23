-- WoWGuilde, notifications Comms (dev uniquement)
local ADDON, ns = ...

ns.CommsNotices = ns.CommsNotices or {}
local Notices = ns.CommsNotices

local devMode = false

function Notices.SetDevMode(enabled)
	devMode = not not enabled
end

local function ChatNotice(kind, text)
	if not text or text == "" then
		return
	end
	if not devMode then
		return
	end
	local k = kind and ("[" .. tostring(kind) .. "] ") or ""
	print("|cffffd100[WoW Guilde]|r" .. k .. text)
end

function Notices.Receive(from, subject)
	ChatNotice("RÉCEPTION", ("Réception de %s : %s."):format(tostring(from), tostring(subject)))
end

function Notices.Send(target, subject)
	ChatNotice("ENVOI", ("Envoi à %s : %s."):format(tostring(target), tostring(subject)))
end

function Notices.Error(from, subject, err)
	ChatNotice(
		"ERREUR",
		("Erreur réception %s depuis %s : %s."):format(tostring(subject), tostring(from), tostring(err))
	)
end

function Notices.VersionMismatch(from, kind, got, expected)
	ChatNotice(
		"ERREUR",
		("Version incompatible de %s (%s). Attendue : %s."):format(
			tostring(from),
			tostring(got or "?"),
			tostring(expected or "?")
		)
	)
end

function Notices.SendDigestGuild()
	Notices.Send("guilde", "envoi résumé")
end

function Notices.SendSnapshotRequest(target)
	Notices.Send(target, "demande snapshot")
end

function Notices.ErrorSnapshot(from, err)
	Notices.Error(from, "snapshot de guilde", err)
end

function Notices.ReceiveSnapshot(from)
	Notices.Receive(from, "réception snapshot de guilde")
end

function Notices.ErrorNews(from, err)
	Notices.Error(from, "actualités", err)
end

function Notices.ReceiveNews(from)
	Notices.Receive(from, "réception actualités")
end

function Notices.SendRelayNews(target)
	Notices.Send(target, "relais actualités")
end

function Notices.ErrorNewsBatch(from, err)
	Notices.Error(from, "lot d’actualités", err)
end

function Notices.ReceiveNewsBatch(from, count)
	Notices.Receive(from, ("réception lot d’actualités x%d"):format(tonumber(count) or 0))
end

function Notices.ReceiveDigestAnnounce(from)
	Notices.Receive(from, "réception annonce résumé")
end

function Notices.ReceiveSnapshotRequest(from)
	Notices.Receive(from, "réception demande snapshot")
end

function Notices.SendSnapshot(target)
	Notices.Send(target, "envoi snapshot de guilde")
end

function Notices.SendNewsReqStageGuild(stageDisplay)
	Notices.Send("guilde", ("envoi requête actualités étape %d"):format(tonumber(stageDisplay) or 0))
end

function Notices.ReceiveNewsReqStage(from, stageDisplay)
	Notices.Receive(from, ("réception requête actualités étape %d"):format(tonumber(stageDisplay) or 0))
end

function Notices.SendPatchGuild(full)
	Notices.Send("guilde", ("envoi mise à jour %s"):format(tostring(full)))
end

function Notices.SendPatchTarget(target, full)
	Notices.Send(target, ("envoi mise à jour %s"):format(tostring(full)))
end

function Notices.ReceivePatch(from, full)
	Notices.Receive(from, ("réception mise à jour %s"):format(tostring(full)))
end

function Notices.SendEmote(target, key)
	Notices.Send(target, ("envoi émote %s"):format(tostring(key)))
end

function Notices.ReceiveEmote(from, key)
	Notices.Receive(from, ("réception émote %s"):format(tostring(key)))
end

function Notices.ReceiveProudNews(actor, newsId)
	Notices.Receive(actor, ("mise à jour fierté %s"):format(tostring(newsId)))
end

function Notices.ReceiveNewsDelete(sender)
	Notices.Receive(sender, "réception suppression actualité")
end

function Notices.SendNewsDeleteGuild(newsId)
	Notices.Send("guilde", ("envoi suppression actualité %s"):format(tostring(newsId)))
end

function Notices.SendProudNewsGuild(newsId)
	Notices.Send("guilde", ("envoi fierté %s"):format(tostring(newsId)))
end

function Notices.SendFeaturedNewsGuild()
	Notices.Send("guilde", "envoi fièreté légendaire")
end

function Notices.SendNewsGuild()
	Notices.Send("guilde", "envoi actualités")
end

function Notices.SendNewsBatch(target, count)
	Notices.Send(target, ("envoi lot d’actualités x%d"):format(tonumber(count) or 0))
end
