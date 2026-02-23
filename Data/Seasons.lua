local ADDON, ns = ...

ns.Data = ns.Data or {}
local Data = ns.Data

Data.Seasons = {
	current = {
		expansion = "TWW",
		season = 1,
		mplus = {
			[1271] = true,
			[1270] = true,
			[1267] = true,
			[1298] = true,
			[1303] = true,
			[1185] = true,
			[1194] = true,
		},
		dungeons = {
			[1271] = true,
			[1274] = true,
			[1210] = true,
			[1272] = true,
			[1269] = true,
			[1268] = true,
			[1270] = true,
			[1267] = true,
			[1298] = true,
			[1303] = true,
		},
		raids = {
			-- JournalInstanceID
			[756] = true,
		},
	},
	history = {},
}
