local ADDON, ns = ...

-- Config NewsTTL:
-- - Nombre simple = jours (ex: loot = 7)
-- - Table = unite precise: { seconds=30 } / { minutes=15 } / { hours=6 } / { days=3 } / { months=1 }
-- - session utilise toujours la table (pour de petites durees)
-- - monthDays definit la duree d'un "mois" en jours
-- Config NewsMeta:
-- - Permet de definir le type et/ou le titre par module
-- - Exemple: merchantgold = { type = "loot", title = "Ventes au marchand" }

ns.Data = ns.Data or {}
local Data = ns.Data
Data.NewsTTL = Data.NewsTTL
	or {
		daySeconds = 86400,
		monthDays = 30,
		dataRetentionDays = 14,
		default = 14,
		session = { seconds = 60 },
		windowtime = 14,
		killtype = 14,
		deaths = 14,
		mplusmilestone = 14,
		mplus = 14,
		dungeonboss = 14,
		raidboss = 14,
		loot = 14,
		epiccollectibles = 14,
		achievement = 14,
		level = 14,
		itemlevel = 14,
		spec = 14,
		zone = 14,
		mount = 14,
		toy = 14,
		transmog = 14,
		lfg = 14,
		pvpkills = 14,
		guildchat = 14,
		honorlevel = 14,
		merchantgold = 14,
		merchantitems = 14,
		woodharvest = 14,
		herbharvest = 14,
		fishingharvest = 14,
		oreharvest = 14,
		housing = 14,
		housingcleanup = 14,
		housingdecor = 14,
		quest = 14,
	}

Data.NewsMeta = Data.NewsMeta
	or {
		windowtime = { type = "guild", title = "Centre de guilde" },
		killtype = { type = "cibles", title = "Cibles" },
		deaths = { type = "death", title = "Morts" },
		mplusmilestone = { type = "mplus", title = "Mythique+" },
		mplus = { type = "mplus", title = "Mythique+" },
		dungeonboss = { type = "pve", title = "Donjons" },
		raidboss = { type = "raid", title = "Raid" },
		loot = { type = "loot", title = "Butin" },
		epiccollectibles = { type = "collection", title = "Collections" },
		achievement = { type = "achievement", title = "Hauts faits" },
		achievement_each = { type = "achievement", title = "Hauts faits" },
		level = { type = "level", title = "Niveau" },
		itemlevel = { type = "gear", title = "Équipement" },
		spec = { type = "spec", title = "Spécialisation" },
		zone = { type = "world", title = "Monde" },
		mount = { type = "mount", title = "Montures" },
		toy = { type = "toy", title = "Jouets" },
		transmog = { type = "transmog", title = "Apparences" },
		lfg = { type = "pve", title = "Recherche de groupe" },
		pvpkills = { type = "pvp", title = "Joueur contre Joueur" },
		guildchat = { type = "guildchat", title = "Messages de guilde" },
		guildgg = { type = "guildchat", title = "Messages de guilde" },
		honorlevel = { type = "pvp", title = "Honneur" },
		session = { type = "connection", title = "Connexion" },
		merchantgold = { type = "loot", title = "Or gagné au marchand" },
		merchantitems = { type = "loot", title = "Objets vendus" },
		woodharvest = { type = "woodharvest", title = "Récolte de bois" },
		herbharvest = { type = "herbharvest", title = "Récolte de plantes" },
		fishingharvest = { type = "fishingharvest", title = "Récolte de pêche" },
		oreharvest = { type = "oreharvest", title = "Récolte de minerais" },
		housing = { type = "housing", title = "Logis" },
		housingcleanup = { type = "housingcleanup", title = "Entretien de l'île" },
		housingdecor = { type = "housingdecor", title = "Objets de logis" },
		questdaily = { type = "questdaily", title = "Quêtes journalières" },
		worldquest = { type = "worldquest", title = "Expéditions" },
		quest = { type = "quest", title = "Quêtes" },
	}
