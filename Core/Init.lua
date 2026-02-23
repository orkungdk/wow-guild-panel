local ADDON, ns = ...
ns.name     = ADDON
ns.Sections = ns.Sections or {}
ns.UI       = ns.UI or {}
ns.Utils    = ns.Utils or {}
ns.Data     = ns.Data or {}
ns.Prefs    = ns.Prefs or {}
local Utils = ns.Utils
local EventBus = ns.EventBus

---------------------------------------------------------
-- SafeRefresh utilitaire
---------------------------------------------------------
local function SafeRefresh(frame, fn)
    if frame and frame:IsShown() and type(fn) == "function" then
        pcall(fn)
    end
end

---------------------------------------------------------
-- Cache des pseudos (depuis la note de guilde)
-- Alias = tout ce qui est AVANT " • MAIN" (insensible à la casse)
-- On stocke { alias = "...", class = "MAGE" } pour couleur de classe
---------------------------------------------------------
local PSEUDO_CACHE = {}

local function Trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function AliasFromNote(note)
    if not note or note == "" then return nil end
    local alias = note:match("^(.-)%s*•%s*[Mm][Aa][Ii][Nn]") or note:match("^(.-)%s*•") or note
    alias = Trim(alias)
    if alias == "" then return nil end
    return alias
end

local function BuildPseudoCache_WoWGuilde()
    wipe(PSEUDO_CACHE)
    if not IsInGuild() then
        ns.Utils.PSEUDO_CACHE = PSEUDO_CACHE
        return
    end

    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        -- classFileName est le 11e retour (ex: "MAGE")
        local name, _, _, _, _, _, note, _, _, _, classFileName = GetGuildRosterInfo(i)
        if name then
            local full  = (ns.FullFromRosterName and ns.FullFromRosterName(name)) or name
            local alias = AliasFromNote(note)
            if alias then
                local rec = { alias = alias, class = classFileName } -- ex: { alias="Dëvo", class="MAGE" }
                PSEUDO_CACHE[full]                    = rec          -- Nom-Royaume
                PSEUDO_CACHE[Ambiguate(full, "none")] = rec          -- Nom court
            end
        end
    end

    -- expose la référence à jour (utile si d'autres fichiers la lisent)
    Utils.PSEUDO_CACHE = PSEUDO_CACHE
end

-- Mise à jour auto du cache (et premier build fiable au login)
do
    local function OnEvent(evt)
        if evt == "PLAYER_LOGIN" then
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
            C_Timer.After(0.2, BuildPseudoCache_WoWGuilde) -- laisse le temps au roster d’être peuplé
        else
            BuildPseudoCache_WoWGuilde()
        end
    end
    if EventBus and EventBus.On then
        EventBus.On("PLAYER_LOGIN", OnEvent)
        EventBus.On("PLAYER_GUILD_UPDATE", OnEvent)
        EventBus.On("GUILD_ROSTER_UPDATE", OnEvent)
    end
end

---------------------------------------------------------
-- Expose dans ns.Utils
---------------------------------------------------------
ns.SafeRefresh = SafeRefresh
Utils.PSEUDO_CACHE     = PSEUDO_CACHE
Utils.BuildPseudoCache = BuildPseudoCache_WoWGuilde
Utils.AliasFromNote    = AliasFromNote
