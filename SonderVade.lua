--[[
    SonderVade (formerly Evade Emote Swapper) — "Show [Replacement] instead of [Original]"
    =====================================================================
    Light macOS-style window (traffic lights, toolbar search, sidebar
    Emotes / Unusual / Favorites, bordered rows, favorite stars).

    How Evade emotes work (from the EvadeEmoteDebug report):
      • Every emote is a ModuleScript in a folder named "Emotes" somewhere under
        ReplicatedStorage.Items (BaseItems, ItemPacks.Base.DailyShop, …). It has an
        ID attribute and Animation / AnimationR6 / AnimationClassic children
        (some emotes keep extra animations in an "Animations" folder).
      • The folder above "Emotes" is the collection (DailyShop, BaseItems, …).
      • Emotes are played on the client-side visual rig Workspace.Rigs.<PlayerName>,
        not on LocalPlayer.Character.
      • Each emote wheel slot (…Popups.Emote.Wheel.Emote1..N) has a preview rig
        whose Animator plays that slot's emote.

    So the library lists ONLY those emote items (no tools, NPCs, carries,
    movement), swaps are stored per item, and the replacement uses the
    target item's variant that matches the rig (Classic / R6 / R15).

    RightCtrl = show / hide.   Config: EvadeEmoteSwap.json.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst   = game:GetService("ReplicatedFirst")
local StarterPlayer     = game:GetService("StarterPlayer")
local StarterGui        = game:GetService("StarterGui")
local Lighting          = game:GetService("Lighting")
local UserInputService  = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")
local TweenService      = game:GetService("TweenService")
local ContentProvider   = game:GetService("ContentProvider")

local LocalPlayer = Players.LocalPlayer
local genv = (getgenv and getgenv()) or _G

-- Stop any previous instance (v1 / v2 / v4 / v5) before starting
for _, oldKey in ipairs({ "SonderVade", "EvadeEmoteSwapper" }) do -- close a running copy (new or old name)
    local old = genv[oldKey]
    if type(old) == "table" and type(old.Destroy) == "function" then pcall(old.Destroy) end
end

local VERSION        = "7.3"
-- true = developer build (Diagnostics panel + Copy Diagnostics), false = build to share with players
local DEV_BUILD      = false
local CONFIG_FILE    = "EvadeEmoteSwap.json"
local FAV_FILE       = "EvadeEmoteSwap_favorites.json"
local SETTINGS_KEY   = "__settings"
local UI_KEY         = "__ui"
local ALIAS_KEY      = "__aliases"
local ITEM_SWAPS_KEY = "__itemSwaps"
local PROPS_KEY      = "__propJoints"
local UNUSUAL_KEY    = "__unusual"
local TOGGLE_KEY     = Enum.KeyCode.RightControl

local SETTINGS = {
    AutoScanEnabled = true,
    ScanInterval = 2,
    DetectCurrentlyPlaying = true,
    DetectWheelEmotes = true,
    AutoRefreshUI = true,
    ReadItemNames = true,      -- read display names from the game's item data modules
    SwapEngineEnabled = true,
    KeepEmoting = false,       -- gameplay (opt-in): re-play a swapped emote when the server ends it
    HideKey = "RightControl",  -- key that hides / shows the UI (Settings → Hide / show UI key)
    Headless = false,          -- visual (local only): hide head + face
    KorbloxRight = false,      -- visual (local only): Korblox right leg
    KorbloxLeft = false,       -- visual (local only): mirrored Korblox left leg
    Accessories = {},          -- visual (local only): catalog accessory ids worn on the rig
    HideGameGui = false,       -- hide the game's own GUI (HUD, wheel, chat, player list)
    HideGameKey = "None",      -- key that toggles HideGameGui ("None" = no key)
    MoveLikeReplacement = true, -- gameplay: move like the replacement emote (copies EmoteInfo.SpeedMult / Length; was "MatchMovement" before 5.7)
}

local MIN_INTERVAL, MAX_INTERVAL = 0.5, 30
local WHEEL_SCAN_BUDGET = 8000
local UI_THROTTLE       = 0.2
local MIN_ID_DIGITS     = 5

-- Bold "collections" palette: cream page, white cards, thick black outlines, hard black shadows
local L = {
    Bg          = Color3.fromRGB(250, 246, 236),
    Sidebar     = Color3.fromRGB(250, 246, 236),
    SidebarSel  = Color3.fromRGB(255, 214, 64),
    Toolbar     = Color3.fromRGB(250, 246, 236),
    ToolbarHover= Color3.fromRGB(240, 233, 216),
    Content     = Color3.fromRGB(255, 255, 255),
    Border      = Color3.fromRGB(17, 17, 17),
    RowBorder   = Color3.fromRGB(17, 17, 17),
    RowHover    = Color3.fromRGB(255, 249, 226),
    RowPlaying  = Color3.fromRGB(222, 246, 208),
    RowText     = Color3.fromRGB(17, 17, 17),
    SelRow      = Color3.fromRGB(255, 236, 150),
    SelRowBorder= Color3.fromRGB(17, 17, 17),
    FieldFill   = Color3.fromRGB(255, 255, 255),
    FieldBorder = Color3.fromRGB(17, 17, 17),
    ButtonHover = Color3.fromRGB(255, 246, 212),
    GrayBtn     = Color3.fromRGB(236, 231, 218),
    GrayBtnH    = Color3.fromRGB(224, 217, 200),
    GrayBtnOn   = Color3.fromRGB(255, 214, 64),
    DarkBtn     = Color3.fromRGB(17, 17, 17),
    DarkBtnH    = Color3.fromRGB(52, 52, 52),
    SlateBtn    = Color3.fromRGB(110, 214, 92),
    SlateBtnH   = Color3.fromRGB(96, 196, 78),
    Text        = Color3.fromRGB(17, 17, 17),
    TitleText   = Color3.fromRGB(17, 17, 17),
    Secondary   = Color3.fromRGB(72, 70, 66),
    Tertiary    = Color3.fromRGB(128, 122, 110),
    Accent      = Color3.fromRGB(96, 84, 240),
    AccentHover = Color3.fromRGB(116, 104, 255),
    AccentSoft  = Color3.fromRGB(232, 229, 255),
    AccentSoftH = Color3.fromRGB(218, 214, 255),
    Shadow      = Color3.fromRGB(17, 17, 17),
    Primary     = Color3.fromRGB(255, 208, 47),
    PrimaryH    = Color3.fromRGB(255, 220, 92),
    Star        = Color3.fromRGB(255, 176, 0),
    Good        = Color3.fromRGB(36, 156, 72),
    Warn        = Color3.fromRGB(200, 126, 0),
    Bad         = Color3.fromRGB(214, 54, 64),
    BadSoft     = Color3.fromRGB(253, 236, 237),
    Purple      = Color3.fromRGB(140, 82, 204),
    Red         = Color3.fromRGB(255, 95, 87),
    Yellow      = Color3.fromRGB(254, 188, 46),
    Green       = Color3.fromRGB(40, 200, 64),
    SwitchOff   = Color3.fromRGB(226, 220, 204),
    SwitchOn    = Color3.fromRGB(110, 214, 92),
}
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local F = { Regular = Enum.Font.Gotham, Medium = Enum.Font.GothamMedium, Bold = Enum.Font.GothamBold, Black = Enum.Font.GothamBlack, Mono = Enum.Font.Code }

-- ============================================================
-- State
-- ============================================================
local Alive = true
local Connections = {}
local API
local Gui
local renderAll
local onSwapFailed = function() end

-- Library = Evade emote items: ReplicatedStorage.Items.**.Emotes.<ModuleScript>
local Library         = {}  -- [itemKey] = entry (stable table, never reassigned)
local LibraryByName   = {}  -- [normName] = {itemKeys}
local LibraryCount, LibraryVersion = 0, 0
local LibrarySorted, LibrarySortedVersion = {}, -1
local LibCounts       = { Emotes = 0, Unusual = 0 }
local LibraryScanning = false
local AllAnims        = {}  -- [animationId] = { Key = itemKey, Variant = "AnimationClassic", Keys = {[itemKey] = true} }
local AllAnimsCount   = 0

local FavoriteIds, Aliases, LegacySwaps = {}, {}, {}
local FavVersion = 0
local Detected, Swaps = {}, {}   -- Swaps[sourceItemKey] = {Target = targetItemKey, SourceName, TargetName}

local OwnTracks  = setmetatable({}, { __mode = "k" })
local SeenTracks = setmetatable({}, { __mode = "k" })
local TrackCache = setmetatable({}, { __mode = "k" })
local TrackState, PlayingCount, ActiveReplacements = {}, {}, {}
local FailedTargets, FailedAnims = {}, {}
local CharMaids, PlayerConns, UiState = {}, {}, {}
local Diag = { Scanned = 0, Duration = 0, Deep = false, When = "never", Items = 0, NamesRead = 0, Collections = 0, ItemsRoot = false }

local LocalAnimator, LocalRig, LocalIsRig
local PreviewTrack
local PreferredVariant     -- variant this player's rig uses, learned from real plays / the wheel preview rig
local Core = {}            -- internal helpers (keeps the main chunk under Luau's 200-local limit)
Core.FavUnusual = {}       -- [cosmetic key] = true (starred Unusual cosmetics)

-- ============================================================
-- Utilities
-- ============================================================
local function bind(signal, fn)
    local c = signal:Connect(fn)
    Connections[#Connections + 1] = c
    return c
end

local lastNotify = {}
local function notify(text, key)
    if key then
        local t = lastNotify[key]
        if t and os.clock() - t < 10 then return end
        lastNotify[key] = os.clock()
    end
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = "SonderVade", Text = text, Duration = 3 })
    end)
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normName(s)
    return (tostring(s or ""):lower():gsub("[^%w]", ""))
end

local function escapeRich(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function fmtNum(v)
    return (string.format("%.1f", v):gsub("%.0$", ""))
end

local function hex(c)
    return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function countTable(t)
    local n = 0
    for _ in pairs(t) do n += 1 end
    return n
end

local function toId(value)
    local t = typeof(value)
    if t == "number" then
        if value >= 10 ^ (MIN_ID_DIGITS - 1) and value % 1 == 0 then return string.format("%d", value) end
        return nil
    elseif t == "string" then
        local id = value:match("rbxassetid://(%d+)") or value:match("[?&][iI][dD]=(%d+)") or value:match("^%s*(%d+)%s*$")
        if id and #id >= MIN_ID_DIGITS then return id end
    end
    return nil
end

local function safeFullName(inst)
    local ok, name = pcall(inst.GetFullName, inst)
    return ok and name or tostring(inst)
end

-- "BoldMarch" → "Bold March", "M3GANDance" → "M3GAN Dance" (formatting only, used when no display name exists)
function Core.prettify(name)
    local s = tostring(name):gsub("_", " ")
    s = s:gsub("(%l)(%u)", "%1 %2")
    s = s:gsub("(%u)(%u%l)", "%1 %2")
    return trim(s)
end

function Core.multiAdd(index, key, value)
    if not key or key == "" then return end
    local list = index[key]
    if not list then
        index[key] = { value }
        return
    end
    for _, v in ipairs(list) do
        if v == value then return end
    end
    list[#list + 1] = value
end

function Core.multiRemove(index, key, value)
    local list = index[key]
    if not list then return end
    for i, v in ipairs(list) do
        if v == value then
            table.remove(list, i)
            break
        end
    end
    if #list == 0 then index[key] = nil end
end

-- ============================================================
-- UI refresh throttle
-- ============================================================
local uiScheduled = false
local function scheduleUI(force)
    if not Alive then return end
    if not SETTINGS.AutoRefreshUI and not force then return end
    if uiScheduled then return end
    uiScheduled = true
    task.delay(UI_THROTTLE, function()
        uiScheduled = false
        if Alive and renderAll then
            local ok, err = pcall(renderAll)
            if not ok then warn("[SonderVade] UI error: " .. tostring(err)) end
        end
    end)
end

-- ============================================================
-- Config & favorites persistence
-- ============================================================
function Core.readJson(file)
    if type(readfile) ~= "function" then return nil end
    if type(isfile) == "function" then
        local ok, exists = pcall(isfile, file)
        if not ok or not exists then return nil end
    end
    local ok, raw = pcall(readfile, file)
    if not ok or type(raw) ~= "string" or raw == "" then return nil end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if ok2 and type(data) == "table" then return data end
    return nil
end

function Core.writeJson(file, data)
    if type(writefile) ~= "function" then return end
    local ok, json = pcall(HttpService.JSONEncode, HttpService, data)
    if ok then pcall(writefile, file, json) end
end

local function saveConfig()
    local data = {}
    -- v1–v4 animation-id swaps that could not be matched to an emote item stay in their old format
    for src, info in pairs(LegacySwaps) do data[src] = info end
    local items = {}
    for src, info in pairs(Swaps) do
        items[src] = { Target = info.Target, SourceName = info.SourceName, TargetName = info.TargetName }
    end
    data[ITEM_SWAPS_KEY] = items
    local s = {}
    for k, v in pairs(SETTINGS) do s[k] = v end
    data[SETTINGS_KEY] = s
    data[UI_KEY] = UiState
    data[ALIAS_KEY] = Aliases
    data[PROPS_KEY] = Core.PropJoints
    data[UNUSUAL_KEY] = Core.WornUnusual or ""
    local favU = {}
    for k in pairs(Core.FavUnusual) do favU[#favU + 1] = k end
    data["__favUnusual"] = favU
    Core.writeJson(CONFIG_FILE, data)
end

local function loadConfig()
    local data = Core.readJson(CONFIG_FILE)
    if not data then return end
    for k, v in pairs(data) do
        if k == SETTINGS_KEY and type(v) == "table" then
            for sk, sv in pairs(v) do
                if SETTINGS[sk] ~= nil and type(sv) == type(SETTINGS[sk]) then SETTINGS[sk] = sv end
            end
        elseif k == UI_KEY and type(v) == "table" then
            for uk, uv in pairs(v) do
                if type(uv) == "number" then UiState[uk] = uv end
            end
        elseif k == UNUSUAL_KEY then
            Core.WornUnusual = (type(v) == "string" and v ~= "") and v or nil
        elseif k == "__favUnusual" and type(v) == "table" then
            for _, key in ipairs(v) do Core.FavUnusual[tostring(key)] = true end
        elseif k == PROPS_KEY and type(v) == "table" then
            for jk, jv in pairs(v) do
                if type(jk) == "string" and type(jv) == "string" then Core.PropJoints[jk] = jv end
            end
        elseif k == ALIAS_KEY and type(v) == "table" then
            for ak, av in pairs(v) do
                if type(ak) == "string" and ak ~= "" and (type(av) == "string" or type(av) == "number") then
                    Aliases[ak] = tostring(av)
                end
            end
        elseif k == ITEM_SWAPS_KEY and type(v) == "table" then
            for src, info in pairs(v) do
                if type(info) == "table" and info.Target ~= nil and tostring(src) ~= tostring(info.Target) then
                    Swaps[tostring(src)] = {
                        Target = tostring(info.Target),
                        SourceName = type(info.SourceName) == "string" and info.SourceName or tostring(src),
                        TargetName = type(info.TargetName) == "string" and info.TargetName or tostring(info.Target),
                    }
                end
            end
        elseif type(v) == "table" and v.Target ~= nil then
            local src, tgt = toId(tostring(k)), toId(tostring(v.Target))
            if src and tgt and src ~= tgt then
                LegacySwaps[src] = {
                    Target = tgt,
                    SourceName = type(v.SourceName) == "string" and v.SourceName or src,
                    TargetName = type(v.TargetName) == "string" and v.TargetName or tgt,
                }
            end
        end
    end
    SETTINGS.ScanInterval = math.clamp(tonumber(SETTINGS.ScanInterval) or 2, MIN_INTERVAL, MAX_INTERVAL)
end

local function saveFavorites()
    local list = {}
    for id, f in pairs(FavoriteIds) do
        local e = Library[id]
        list[#list + 1] = { Id = id, Name = (e and e.Name) or f.Name, Collection = (e and e.Collection) or f.Collection }
    end
    table.sort(list, function(a, b)
        local an, bn = tostring(a.Name):lower(), tostring(b.Name):lower()
        if an ~= bn then return an < bn end
        return a.Id < b.Id
    end)
    Core.writeJson(FAV_FILE, { Version = 2, Favorites = list })
end

local function loadFavorites()
    local data = Core.readJson(FAV_FILE)
    if not data or type(data.Favorites) ~= "table" then return end
    for _, item in ipairs(data.Favorites) do
        if type(item) == "table" and item.Id ~= nil and tostring(item.Id) ~= "" then
            FavoriteIds[tostring(item.Id)] = {
                Name = type(item.Name) == "string" and item.Name or tostring(item.Id),
                Collection = type(item.Collection) == "string" and item.Collection or nil,
            }
        end
    end
end

-- ============================================================
-- Library core (Evade emote items)
-- ============================================================
function Core.indexEntry(e)
    for k in pairs(e._keys or {}) do Core.multiRemove(LibraryByName, k, e.Id) end
    local keys = {}
    local function add(s)
        local k = normName(s)
        if k ~= "" and not keys[k] then
            keys[k] = true
            Core.multiAdd(LibraryByName, k, e.Id)
        end
    end
    add(e.Name)
    add(e.ModuleName)
    if e.Collection then
        add(e.Collection .. e.Name)
        add(e.Collection .. e.ModuleName)
    end
    e._keys = keys
    e.Lower = e.Name:lower()
    local ids = {}
    for _, v in ipairs(e.VariantOrder) do ids[#ids + 1] = e.Variants[v] end
    e.Search = (e.Name .. " " .. e.ModuleName .. " " .. (e.Collection or "") .. " " .. e.Id .. " " .. table.concat(ids, " ")):lower()
end

function Core.removeEntry(key)
    local e = Library[key]
    if not e then return end
    Library[key] = nil
    LibraryCount -= 1
    for k in pairs(e._keys or {}) do Core.multiRemove(LibraryByName, k, key) end
    LibraryVersion += 1
end

function Core.itemKey(mod)
    local id = mod:GetAttribute("ID")
    if type(id) == "number" then return string.format("%d", id) end
    if type(id) == "string" and id ~= "" then return id end
    return safeFullName(mod)
end

function Core.relName(d, mod)
    local parts, cur = {}, d
    while cur and cur ~= mod do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(parts, "/")
end

-- Collection = the folder that holds the item's "Emotes" folder (DailyShop, BaseItems, EmotePack, …)
function Core.collectionOf(mod)
    local a = mod:GetAttribute("Collection")
    if type(a) == "string" and trim(a) ~= "" then return trim(a) end
    local folder = mod.Parent
    local p = folder and folder.Parent
    if p and p ~= ReplicatedStorage and p.Name ~= "Items" then return p.Name end
    return nil
end

function Core.isUnusual(mod, data)
    if safeFullName(mod):lower():find("unusual", 1, true) then return true end
    for _, k in ipairs({ "Rarity", "Category", "Tier", "Type" }) do
        local v = mod:GetAttribute(k)
        if type(v) == "string" and v:lower():find("unusual", 1, true) then return true end
        if type(data) == "table" then
            local dv = rawget(data, k)
            if type(dv) == "string" and dv:lower():find("unusual", 1, true) then return true end
        end
    end
    return false
end

function Core.registerItem(mod, data)
    local key = Core.itemKey(mod)
    local ok, desc = pcall(mod.GetDescendants, mod)
    if not ok then return nil end
    local variants, order = {}, {}
    for _, d in ipairs(desc) do
        if d:IsA("Animation") then
            local id = toId(d.AnimationId)
            if id then
                local rel = Core.relName(d, mod)
                if not variants[rel] then
                    variants[rel] = id
                    order[#order + 1] = rel
                end
                local rec = AllAnims[id]
                if not rec then
                    AllAnims[id] = { Key = key, Variant = rel, Keys = { [key] = true } }
                    AllAnimsCount += 1
                else
                    rec.Keys[key] = true
                end
            end
        end
    end
    if #order == 0 then return nil end -- no animation → not playable as an emote

    local name
    local attrName = mod:GetAttribute("DisplayName")
    if type(attrName) == "string" and trim(attrName) ~= "" then name = trim(attrName) end
    if not name and type(data) == "table" then
        -- Evade item data: { AppearanceInfo = { Name = "Rockin' Stride", … }, EmoteInfo = { … } }
        local info = rawget(data, "AppearanceInfo")
        local an = type(info) == "table" and rawget(info, "Name")
        if type(an) == "string" and trim(an) ~= "" then name = trim(an) end
    end
    if not name and type(data) == "table" then
        for _, k in ipairs({ "DisplayName", "Name", "Title" }) do
            local v = rawget(data, k)
            if type(v) == "string" and trim(v) ~= "" then
                name = trim(v)
                break
            end
        end
    end

    local e = Library[key]
    if not e then
        e = { Id = key }
        Library[key] = e
        LibraryCount += 1
    end
    e.ItemId = key
    e.Name = name or Core.prettify(mod.Name)
    e.ModuleName = mod.Name
    e.Collection = Core.collectionOf(mod)
    e.Category = Core.isUnusual(mod, data) and "Unusual" or "Emotes"
    e.Kind = "Emote"
    e.Source = "Items"
    e.Path = safeFullName(mod)
    e.Module = mod -- needed to find the emote's prop template (EmoteModel)
    e.Verified = true
    e.Variants, e.VariantOrder = variants, order
    e.HasProps = Core.hasProps(mod)
    e.Favorite = FavoriteIds[key] ~= nil
    e.CurrentlyPlaying = PlayingCount[key] ~= nil
    Core.indexEntry(e)
    return e
end

function Core.ensureFavoriteEntries()
    for key, f in pairs(FavoriteIds) do
        if not Library[key] then
            local e = {
                Id = key, ItemId = key, Name = f.Name or ("Item " .. key), ModuleName = f.Name or key,
                Collection = f.Collection, Category = "Emotes", Kind = "Emote", Source = "Saved",
                Path = "(saved favorite — not found in the current game data)", Verified = false,
                Variants = {}, VariantOrder = {}, HasProps = false, Favorite = true, CurrentlyPlaying = false,
            }
            Library[key] = e
            LibraryCount += 1
            Core.indexEntry(e)
        end
    end
end

local function getLibrarySorted()
    if LibrarySortedVersion ~= LibraryVersion then
        table.clear(LibrarySorted)
        local em, un = 0, 0
        for _, e in pairs(Library) do
            LibrarySorted[#LibrarySorted + 1] = e
            if e.Category == "Unusual" then un += 1 else em += 1 end
        end
        table.sort(LibrarySorted, function(a, b)
            if a.Lower ~= b.Lower then return a.Lower < b.Lower end
            return a.Id < b.Id
        end)
        LibCounts.Emotes, LibCounts.Unusual = em, un
        LibrarySortedVersion = LibraryVersion
    end
    return LibrarySorted
end

local function toggleFavorite(id)
    if not id then return end
    if FavoriteIds[id] then
        FavoriteIds[id] = nil
    else
        local e = Library[id]
        FavoriteIds[id] = { Name = e and e.Name or id, Collection = e and e.Collection or nil }
    end
    local e = Library[id]
    if e then e.Favorite = FavoriteIds[id] ~= nil end
    FavVersion += 1
    saveFavorites()
    scheduleUI(true)
end

function Core.resolveName(text)
    local n = normName(text)
    if n == "" then return nil end
    local a = Aliases[n]
    if a and Library[a] then return a end
    local list = LibraryByName[n]
    if list and #list > 0 then return list[1] end
    return nil
end

-- If several items share one animation, prefer the one that has a swap
function Core.sourceKeyFor(rec)
    if Swaps[rec.Key] then return rec.Key end
    for k in pairs(rec.Keys) do
        if Swaps[k] then return k end
    end
    return rec.Key
end

-- "classic" / "r6" / "r15", or nil when the path carries no rig style (e.g. "Animations/Loop")
function Core.styleOf(variant)
    if not variant then return nil end
    local p = tostring(variant):lower()
    if p:find("classic", 1, true) then return "classic" end
    if p:find("r6", 1, true) then return "r6" end
    local leaf = p:match("([^/]+)$") or p
    if leaf == "animation" or p:find("r15", 1, true) then return "r15" end
    return nil
end

-- R6 and Classic are both blocky rigs and can fall back to each other; R15 animations
-- never play on a blocky rig (and vice versa) — the joints differ, so nothing would move.
Core.STYLE_ORDER = { classic = { "classic", "r6" }, r6 = { "r6", "classic" }, r15 = { "r15" } }

function Core.rigStyle()
    return Core.styleOf(PreferredVariant) or "classic"
end

-- Exact same variant as the source when the target has it, otherwise the best variant
-- for the same rig family. Returns nil when the target has no animation for this rig.
-- shuffle = true: shuffle emotes (several equal versions, e.g. Zombie Stride ×3) pick one
-- of their top versions at random on every play, like the game does.
-- Intro / Outro / End part of a multi-part emote
function Core.isPhase(variant)
    local leaf = (tostring(variant or ""):match("([^/]+)$") or ""):lower()
    return leaf:find("intro", 1, true) ~= nil or leaf:find("outro", 1, true) ~= nil or leaf:match("^end") ~= nil
end

function Core.pickVariant(entry, wanted, shuffle)
    if not entry or #entry.VariantOrder == 0 then return nil end
    -- same part as the source (an Intro plays the target's Intro); shuffle only applies to the main animation
    if wanted and entry.Variants[wanted] and (not shuffle or Core.isPhase(wanted)) then return entry.Variants[wanted], wanted end
    if Core.isPhase(wanted) then wanted = wanted:match("^(.*)/[^/]+$") or nil end
    local want = Core.styleOf(wanted) or Core.rigStyle()
    local order = Core.STYLE_ORDER[want] or Core.STYLE_ORDER.classic
    local scored, bestScore = {}, nil
    local hasSelection = false
    if shuffle then
        for _, v in ipairs(entry.VariantOrder) do
            if v:lower():find("selection", 1, true) then hasSelection = true break end
        end
    end
    for i, v in ipairs(entry.VariantOrder) do
        local style = Core.styleOf(v)
        local score
        if style == order[1] then
            score = 10
        elseif order[2] and style == order[2] then
            score = 8
        elseif style == nil then
            score = 3 -- unlabeled part of a multi-animation emote: only used when nothing better exists
        end
        if score then
            local leaf = (v:match("([^/]+)$") or v):lower()
            if leaf:find("intro", 1, true) or leaf:find("outro", 1, true) or leaf:match("^end") then score -= 2 end
            if hasSelection then
                -- shuffle emote: the game picks among Selection/N, not the top-level default
                if v:lower():find("selection", 1, true) then score += 1 end
            elseif not v:find("/", 1, true) then
                score += 1
            end
            scored[#scored + 1] = { v = v, score = score, i = i }
            if not bestScore or score > bestScore then bestScore = score end
        end
    end
    if not bestScore then return nil end
    local top = {}
    for _, s in ipairs(scored) do
        if s.score >= bestScore then top[#top + 1] = s end
    end
    table.sort(top, function(a, b) return a.i < b.i end)
    local chosen = (shuffle and #top > 1) and top[math.random(1, #top)] or top[1]
    return entry.Variants[chosen.v], chosen.v
end

-- Number of interchangeable versions an emote has for this rig (shuffle emotes > 1)
function Core.versionCount(entry)
    if not entry or #entry.VariantOrder == 0 then return 0 end
    local _, first = Core.pickVariant(entry, nil, false)
    if not first then return 0 end
    local seen, n = {}, 0
    for _ = 1, 40 do
        local _, v = Core.pickVariant(entry, nil, true)
        if v and not seen[v] then
            seen[v] = true
            n += 1
        end
    end
    return n
end

-- ============================================================
-- Detected emotes (keyed by item key)
-- ============================================================
local function ensureDetected(key, name)
    local e = Detected[key]
    local lib = Library[key]
    if e then
        e.LastSeen = os.clock()
        if lib then e.Name = lib.Name end
        return e, false
    end
    e = {
        Key = key, Id = key, Name = (lib and lib.Name) or name or ("Item " .. tostring(key)),
        Origin = "DETECTED", InWheel = false, IsPlaying = PlayingCount[key] ~= nil,
        IsLocal = false, SeenOther = false, Unresolved = false, Manual = false, FromSwap = false,
        LastSeen = os.clock(),
    }
    Detected[key] = e
    return e, true
end

local function newUnresolved(key, name)
    return {
        Key = key, Id = nil, Name = name, Origin = "WHEEL", InWheel = true, IsPlaying = false,
        IsLocal = true, SeenOther = false, Unresolved = true, Manual = false, FromSwap = false, LastSeen = os.clock(),
    }
end

local function recordDetected(key, isLocal)
    local e, created = ensureDetected(key)
    local changed = created
    if isLocal then
        if not e.IsLocal then e.IsLocal = true; changed = true end
    else
        if not e.SeenOther then e.SeenOther = true; changed = true end
        if created then e.Origin = "OTHER PLAYER" end
    end
    if changed then scheduleUI() end
    return e
end

local function setPlaying(key, playing)
    local lib = Library[key]
    if lib then lib.CurrentlyPlaying = playing end
    local e = Detected[key]
    if e and e.IsPlaying ~= playing then
        e.IsPlaying = playing
        e.LastSeen = os.clock()
        scheduleUI()
    end
end

local function trackEnded(track)
    local st = TrackState[track]
    if not st then return end
    TrackState[track] = nil
    if st.Conn then st.Conn:Disconnect() end
    local n = (PlayingCount[st.Id] or 1) - 1
    if n <= 0 then
        PlayingCount[st.Id] = nil
        setPlaying(st.Id, false)
    else
        PlayingCount[st.Id] = n
    end
end

local function trackStarted(animator, track, key)
    if TrackState[track] then return end
    local st = { Id = key, Animator = animator }
    TrackState[track] = st
    PlayingCount[key] = (PlayingCount[key] or 0) + 1
    setPlaying(key, true)
    st.Conn = track.Stopped:Connect(function() trackEnded(track) end)
    if not track.IsPlaying then trackEnded(track) end
end

-- ============================================================
-- Library scan (only Evade emote items — tools, NPCs, carries etc. are ignored)
-- ============================================================
Core.ModuleData = setmetatable({}, { __mode = "k" })

-- Item modules are plain data tables already required by the game; read them in parallel with a timeout
function Core.readModules(mods)
    local results = {}
    if not SETTINGS.ReadItemNames then return results end
    local pending = 0
    for _, m in ipairs(mods) do
        local cached = Core.ModuleData[m]
        if cached ~= nil then
            if cached then results[m] = cached end
        else
            pending += 1
            task.spawn(function()
                local ok, v = pcall(require, m)
                local r = (ok and type(v) == "table") and v or false
                Core.ModuleData[m] = r
                if r then results[m] = r end
                pending -= 1
            end)
        end
    end
    local t0 = os.clock()
    while pending > 0 and Alive and os.clock() - t0 < 3 do task.wait(0.05) end
    return results
end

function Core.migrateLegacy()
    local changed = false
    local moves = {}
    for src, info in pairs(LegacySwaps) do
        local a, b = AllAnims[src], AllAnims[info.Target]
        if a and b then moves[#moves + 1] = { src, a.Key, b.Key } end
    end
    for _, m in ipairs(moves) do
        LegacySwaps[m[1]] = nil
        if not Swaps[m[2]] and m[2] ~= m[3] then
            Swaps[m[2]] = {
                Target = m[3],
                SourceName = Library[m[2]] and Library[m[2]].Name or m[2],
                TargetName = Library[m[3]] and Library[m[3]].Name or m[3],
            }
            ensureDetected(m[2]).FromSwap = true
        end
        changed = true
    end
    local favMoves = {}
    for id in pairs(FavoriteIds) do
        if not Library[id] and AllAnims[id] then favMoves[#favMoves + 1] = id end
    end
    for _, id in ipairs(favMoves) do
        local key = AllAnims[id].Key
        FavoriteIds[key] = FavoriteIds[key] or FavoriteIds[id]
        FavoriteIds[id] = nil
        changed = true
    end
    for k, v in pairs(Aliases) do
        if not Library[v] and AllAnims[v] then
            Aliases[k] = AllAnims[v].Key
            changed = true
        end
    end
    if changed then
        FavVersion += 1
        saveConfig()
        saveFavorites()
    end
end

local function fullLibraryScan(deep)
    if LibraryScanning or not Alive then return end
    LibraryScanning = true
    scheduleUI(true)
    local t0 = os.clock()
    if deep then
        for k in pairs(Core.ModuleData) do Core.ModuleData[k] = nil end
    end

    local root = ReplicatedStorage:FindFirstChild("Items")
    Diag.ItemsRoot = root ~= nil
    local mods, cosmetics, processed = {}, {}, 0
    if root then
        local ok, desc = pcall(root.GetDescendants, root)
        if ok then
            for _, d in ipairs(desc) do
                processed += 1
                if d:IsA("ModuleScript") and d.Parent then
                    if d.Parent.Name == "Emotes" then
                        mods[#mods + 1] = d
                    elseif Core.cosmeticCandidate(d) then
                        -- every cosmetic folder: Cosmetics.Unusual*, gamepass sets, RELICSAuras, collabs …
                        cosmetics[#cosmetics + 1] = d
                    end
                end
                if processed % 4000 == 0 then task.wait() end
            end
        end
    end

    local data = Core.readModules(mods)
    local cosmeticData = Core.readModules(cosmetics)
    if not Alive then
        LibraryScanning = false
        return
    end
    table.clear(Core.Cosmetics)
    for _, m in ipairs(cosmetics) do
        if Core.isUnusualCosmetic(m, cosmeticData[m]) then pcall(Core.registerCosmetic, m, cosmeticData[m]) end
    end
    Diag.Cosmetics = countTable(Core.Cosmetics)

    -- Rebuild the animation index in one go (no yields) so detection never sees a half-built index
    table.clear(AllAnims)
    AllAnimsCount = 0
    local seen, named, colls = {}, 0, {}
    for _, m in ipairs(mods) do
        local ok, e = pcall(Core.registerItem, m, data[m])
        if ok and e then
            seen[e.Id] = true
            if data[m] then named += 1 end
            if e.Collection then colls[e.Collection] = true end
        end
    end
    local drop = {}
    for key, e in pairs(Library) do
        if not seen[key] and e.Source == "Items" then drop[#drop + 1] = key end
    end
    for _, key in ipairs(drop) do Core.removeEntry(key) end

    Core.migrateLegacy()
    Core.ensureFavoriteEntries()
    for _, info in pairs(Swaps) do Core.prefetchPoses(info.Target) end
    Core.patchAll()
    for key, d in pairs(Detected) do
        local e = Library[key]
        if e and not d.Unresolved then d.Name = e.Name end
    end

    Diag.Items, Diag.NamesRead, Diag.Collections = countTable(seen), named, countTable(colls)
    Diag.Scanned, Diag.Duration, Diag.Deep = processed, os.clock() - t0, deep and true or false
    local okD, when = pcall(os.date, "%H:%M:%S")
    Diag.When = okD and when or "?"
    LibraryScanning = false
    LibraryVersion += 1
    scheduleUI(true)
end

-- Event-driven refresh when the game adds / removes item data at runtime (debounced)
local function watchRoots()
    local pending = false
    local function dirty(d)
        if pending or not Alive then return end
        if not (d:IsA("ModuleScript") or d:IsA("Animation")) then return end
        pending = true
        task.delay(3, function()
            pending = false
            if Alive then fullLibraryScan(false) end
        end)
    end
    local function attach(root)
        bind(root.DescendantAdded, dirty)
        bind(root.DescendantRemoving, dirty)
    end
    local root = ReplicatedStorage:FindFirstChild("Items")
    if root then
        attach(root)
    else
        bind(ReplicatedStorage.ChildAdded, function(c)
            if c.Name == "Items" then
                attach(c)
                task.delay(3, function()
                    if Alive then fullLibraryScan(false) end
                end)
            end
        end)
    end
end

-- ============================================================
-- Emote props — Evade keeps them as <EmoteItem>.Character / .CharacterClassic .EmoteModel
-- (a Model with the prop parts and the Motor6D / Weld joints that connect them to the rig).
-- ============================================================
Core.PropJoints = {}                                  -- learned from the game: [jointName] = rig part name (persisted)
Core.OwnProps = setmetatable({}, { __mode = "k" })    -- prop models created by this script
Core.PreviewProps = nil

Core.LIMB_ALIASES = {
    RightHand = { "Right Arm" }, RightLowerArm = { "Right Arm" }, RightUpperArm = { "Right Arm" },
    LeftHand = { "Left Arm" }, LeftLowerArm = { "Left Arm" }, LeftUpperArm = { "Left Arm" },
    UpperTorso = { "Torso" }, LowerTorso = { "Torso" },
    RightFoot = { "Right Leg" }, RightLowerLeg = { "Right Leg" }, RightUpperLeg = { "Right Leg" },
    LeftFoot = { "Left Leg" }, LeftLowerLeg = { "Left Leg" }, LeftUpperLeg = { "Left Leg" },
    ["Right Arm"] = { "RightHand", "RightLowerArm" }, ["Left Arm"] = { "LeftHand", "LeftLowerArm" },
    Torso = { "UpperTorso", "LowerTorso" }, ["Right Leg"] = { "RightFoot" }, ["Left Leg"] = { "LeftFoot" },
}

function Core.inPropModel(d, rig)
    local cur = d.Parent
    while cur and cur ~= rig do
        if cur:IsA("Model") and (cur.Name == "EmoteModel" or Core.OwnProps[cur]) then return true end
        cur = cur.Parent
    end
    return false
end

-- Evade's animation rig (Workspace.Rigs.<Player>) has no HumanoidRootPart of its own: its root joint
-- Joints.TorsoRot hangs from the HITBOX model's HumanoidRootPart (Workspace.Players.<Player>).
function Core.hitboxModel()
    local players = workspace:FindFirstChild("Players")
    return (players and players:FindFirstChild(LocalPlayer.Name)) or LocalPlayer.Character
end

-- Rigs that must never borrow parts from the player's hitbox (emote wheel preview rigs)
Core.NoHitbox = setmetatable({}, { __mode = "k" })

-- A body part of the rig (never a part of another prop model), with R6 ↔ R15 name aliases.
-- Also finds parts outside the rig that the rig's own joints attach to (the hitbox root).
function Core.findRigPart(rig, name)
    if not rig or not name then return nil end
    local function find(n)
        for _, d in ipairs(rig:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == n and not Core.inPropModel(d, rig) then return d end
        end
        for _, d in ipairs(rig:GetDescendants()) do
            if d:IsA("JointInstance") and not Core.inPropModel(d, rig) then
                local p0 = d.Part0
                if p0 and p0.Name == n and not p0:IsDescendantOf(rig) then return p0 end
            end
        end
        local hitbox = not Core.NoHitbox[rig] and Core.hitboxModel()
        if hitbox and hitbox ~= rig then
            local p = hitbox:FindFirstChild(n)
            if p and p:IsA("BasePart") then return p end
        end
        return nil
    end
    local p = find(name)
    if p then return p end
    for _, alt in ipairs(Core.LIMB_ALIASES[name] or {}) do
        p = find(alt)
        if p then return p end
    end
    return nil
end

Core.BODY_PARTS = {
    HumanoidRootPart = true, Head = true, Torso = true, ["Left Arm"] = true, ["Right Arm"] = true,
    ["Left Leg"] = true, ["Right Leg"] = true, UpperTorso = true, LowerTorso = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true,
    RightHand = true, LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true,
    RightLowerLeg = true, RightFoot = true,
}

function Core.hasParts(inst)
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") and not Core.BODY_PARTS[d.Name] then return true end
    end
    return false
end

-- Prop emotes keep an EmoteModel (or loose prop parts) inside Character / CharacterClassic models
function Core.hasProps(mod)
    if mod:FindFirstChild("EmoteModel", true) then return true end
    for _, d in ipairs(mod:GetDescendants()) do
        if d:IsA("Model") and (d.Name == "Character" or d.Name == "CharacterClassic") and Core.hasParts(d) then return true end
    end
    return false
end

-- Rig style a prop template is meant for, from its path inside the emote module:
-- "…Classic…" → classic, "…R6…" → r6, "…R15…" or a plain "Character" holder → r15
function Core.propStyle(relPath)
    local p = relPath:lower()
    if p:find("classic", 1, true) then return "classic" end
    if p:find("r6", 1, true) then return "r6" end
    if p:find("r15", 1, true) then return "r15" end
    for seg in p:gmatch("[^/]+") do
        if seg == "character" then return "r15" end
    end
    return nil
end

-- All prop templates inside an emote module (EmoteModel models anywhere, or Character* models
-- that hold prop parts directly), each scored for the rig style and closeness to the variant
-- that is being played. Returns template, kind ("EmoteModel" / "holder").
function Core.propTemplate(entry, variant)
    local mod = entry and entry.Module
    if not mod or not mod.Parent then return nil end
    local want = Core.styleOf(variant) or Core.rigStyle()
    local order = Core.STYLE_ORDER[want] or Core.STYLE_ORDER.classic
    local variantDir = (tostring(variant or ""):match("^(.*)/[^/]+$") or ""):lower()

    local candidates = {}
    for _, d in ipairs(mod:GetDescendants()) do
        if d:IsA("Model") and d.Name == "EmoteModel" then
            candidates[#candidates + 1] = { inst = d, kind = "EmoteModel" }
        end
    end
    if #candidates == 0 then
        for _, d in ipairs(mod:GetDescendants()) do
            if d:IsA("Model") and d.Name:sub(1, 9) == "Character" and Core.hasParts(d) then
                candidates[#candidates + 1] = { inst = d, kind = "holder" }
            end
        end
    end

    local best, bestScore
    for i, c in ipairs(candidates) do
        local rel = Core.relName(c.inst, mod)
        local style = Core.propStyle(rel)
        local score = 0
        if style == order[1] then
            score += 10
        elseif order[2] and style == order[2] then
            score += 8
        elseif style == nil then
            score += 5
        else
            score += 1 -- wrong rig family: only if nothing else exists
        end
        -- same branch as the animation (e.g. both under "Animations/R6" or "Selection/1")
        local relDir = (rel:match("^(.*)/[^/]+$") or ""):lower()
        if variantDir ~= "" and relDir ~= "" then
            local a, b = variantDir .. "/", relDir .. "/"
            local common = 0
            for k = 1, math.min(#a, #b) do
                if a:sub(k, k) ~= b:sub(k, k) then break end
                if a:sub(k, k) == "/" then common = k end
            end
            if common > 0 then score += 2 end
        end
        score -= i * 0.001
        if not best or score > bestScore then best, bestScore = c, score end
    end
    if best then return best.inst, best.kind end
    return nil
end

-- Short outline of an emote module, shown in Diagnostics when no prop template is found
function Core.describeModule(mod)
    if not mod then return "(module missing)" end
    local lines = {}
    for _, d in ipairs(mod:GetDescendants()) do
        if d:IsA("Model") or d:IsA("Folder") or d:IsA("Animation") then
            lines[#lines + 1] = Core.relName(d, mod) .. "(" .. d.ClassName .. ")"
            if #lines >= 14 then
                lines[#lines + 1] = "…"
                break
            end
        end
    end
    return table.concat(lines, ", ")
end

-- Clone even when the game marked the template Archivable = false (Clone() would return nil)
function Core.cloneArchivable(inst)
    local changed = {}
    local function mark(o)
        if not o.Archivable then
            changed[#changed + 1] = o
            o.Archivable = true
        end
    end
    pcall(mark, inst)
    for _, d in ipairs(inst:GetDescendants()) do pcall(mark, d) end
    local ok, c = pcall(inst.Clone, inst)
    for _, o in ipairs(changed) do pcall(function() o.Archivable = false end) end
    return ok and c or nil
end

-- Clone the target emote's props onto the rig. Joint parts outside the template are mapped
-- to the rig by name; unknown ones use what was learned from the game, else the root part.
-- parentOverride: where to put the props (default: inside the rig, so the Animator moves them)
-- Pose hierarchy of an animation: [poseName] = parent pose name. Poses are named after the
-- parts they move, so this tells which part each prop joint hangs from (e.g. Hull → HumanoidRootPart).
Core.PoseCache = {}
function Core.poseParents(animId)
    if not animId then return nil end
    local cached = Core.PoseCache[animId]
    if cached ~= nil then return cached or nil end
    Core.PoseCache[animId] = false -- in flight (or failed)
    local ok, seq = pcall(function()
        return game:GetService("KeyframeSequenceProvider"):GetKeyframeSequenceAsync("rbxassetid://" .. animId)
    end)
    if not ok or not seq then return nil end
    local map = {}
    local function walk(pose, parentName)
        for _, child in ipairs(pose:GetChildren()) do
            if child:IsA("Pose") then
                if parentName and not map[child.Name] then map[child.Name] = parentName end
                walk(child, child.Name)
            end
        end
    end
    for _, kf in ipairs(seq:GetChildren()) do
        if kf:IsA("Keyframe") then walk(kf, nil) end
    end
    Core.PoseCache[animId] = map
    return map
end

-- The part a prop joint should hang from according to the animation (inside the props or on the rig)
function Core.partFromPose(clone, rig, map, joint)
    local p1 = joint.Part1
    local parentName = map and p1 and map[p1.Name]
    if not parentName then return nil end
    local inside = clone:FindFirstChild(parentName, true)
    if inside and inside:IsA("BasePart") and inside ~= p1 then return inside end
    return Core.findRigPart(rig, parentName)
end

-- Re-attach joints that were guessed, once the animation's pose data is available
function Core.refixJoints(clone, rig, map)
    local notes = {}
    for _, d in ipairs(clone:GetDescendants()) do
        if (d:IsA("JointInstance") or d:IsA("WeldConstraint")) and d:GetAttribute("SwapGuessedPart0") then
            local target = Core.partFromPose(clone, rig, map, d)
            if target and target ~= d.Part0 then
                d.Part0 = target
                d:SetAttribute("SwapGuessedPart0", nil)
                notes[#notes + 1] = d.Name .. "→" .. target.Name .. " (animation)"
            end
        end
    end
    return notes
end

-- Download a prop emote's pose data ahead of time so its props attach correctly on the first play
function Core.prefetchPoses(key)
    local e = Library[key]
    if not e or not e.HasProps then return end
    local animId = Core.pickVariant(e, PreferredVariant)
    if animId and Core.PoseCache[animId] == nil then task.spawn(Core.poseParents, animId) end
end

function Core.attachProps(rig, entry, variant, parentOverride, animId)
    local template, kind = Core.propTemplate(entry, variant)
    if not template then
        return nil, "no prop template found — module contains: " .. Core.describeModule(entry and entry.Module)
    end
    local clone = Core.cloneArchivable(template)
    if not clone then return nil, "clone failed (" .. template:GetFullName() .. ")" end
    Core.OwnProps[clone] = true
    clone.Name = "SwapEmoteModel"
    if kind == "holder" then
        -- loose props inside a Character template: drop any dummy body parts / humanoid / animations
        for _, d in ipairs(clone:GetDescendants()) do
            if (d:IsA("BasePart") and Core.BODY_PARTS[d.Name]) or d:IsA("Humanoid") or d:IsA("Animation")
                or d:IsA("AnimationController") or d:IsA("Script") or d:IsA("LocalScript") then
                pcall(function() d:Destroy() end)
            end
        end
    end
    local root = Core.findRigPart(rig, "HumanoidRootPart") or rig.PrimaryPart or Core.findRigPart(rig, "Torso")
    if not root then
        Core.removeProps(clone)
        return nil, "rig has no root part"
    end
    local poseMap = animId and Core.PoseCache[animId] or nil
    if poseMap == false then poseMap = nil end
    -- start at the character so parts without joints end up next to it
    pcall(function() clone:PivotTo(root.CFrame) end)
    local notes, parts = {}, 0
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BasePart") then
            parts += 1
            d.Anchored = false
            d.CanCollide = false
            d.CanTouch = false
            d.CanQuery = false
            d.Massless = true
        elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
            for _, prop in ipairs({ "Part0", "Part1" }) do
                local p = d[prop]
                if p == nil or not p:IsDescendantOf(clone) then
                    local target, how = nil, nil
                    if p then
                        target, how = Core.findRigPart(rig, p.Name), "by name"
                    end
                    if not target and prop == "Part0" and poseMap then
                        target, how = Core.partFromPose(clone, rig, poseMap, d), "animation"
                    end
                    if not target and prop == "Part0" then
                        local learned = Core.PropJoints[d.Name] or Core.PropJoints["*"]
                        if learned then target, how = Core.findRigPart(rig, learned), "learned" end
                    end
                    if not target and prop == "Part0" then target, how = root, "root" end
                    if target then
                        d[prop] = target
                        if how == "root" or how == "learned" then d:SetAttribute("SwapGuessedPart0", true) end
                        notes[#notes + 1] = d.Name .. "→" .. target.Name .. " (" .. how .. ")"
                    end
                end
            end
            if d:IsA("Motor6D") then
                local dc1 = d:FindFirstChild("DefaultC1")
                if dc1 and dc1:IsA("CFrameValue") then d.C1 = dc1.Value end
            end
        end
    end
    -- parts not connected to the rig through any chain of joints would fall away:
    -- weld them to the root where they are
    local adj = {}
    local function link(a, b)
        if a and b then
            adj[a] = adj[a] or {}
            adj[b] = adj[b] or {}
            table.insert(adj[a], b)
            table.insert(adj[b], a)
        end
    end
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("JointInstance") or d:IsA("WeldConstraint") then link(d.Part0, d.Part1) end
    end
    local reached, queue = {}, {}
    for p in pairs(adj) do
        if not p:IsDescendantOf(clone) then
            reached[p] = true
            queue[#queue + 1] = p
        end
    end
    while #queue > 0 do
        local p = table.remove(queue)
        for _, q in ipairs(adj[p]) do
            if not reached[q] then
                reached[q] = true
                queue[#queue + 1] = q
            end
        end
    end
    local loose = 0
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BasePart") and not reached[d] then
            local w = Instance.new("WeldConstraint")
            w.Part0 = root
            w.Part1 = d
            w.Parent = d
            loose += 1
        end
    end
    clone.Parent = parentOverride or rig
    local summary = string.format("%s %s · %d parts%s · %s", kind, template:GetFullName():match("[^%.]+%.[^%.]+%.[^%.]+$") or template.Name,
        parts, loose > 0 and (" (" .. loose .. " welded to root)") or "", #notes > 0 and table.concat(notes, ", ") or "no external joints")
    -- pose data not downloaded yet: fetch it and correct the guessed joints in place
    if animId and not poseMap then
        task.spawn(function()
            local map = Core.poseParents(animId)
            if not map or not clone.Parent or not Core.OwnProps[clone] then return end
            local fixed = Core.refixJoints(clone, rig, map)
            if #fixed > 0 then
                Diag.LastProps = (Diag.LastProps or "") .. " · corrected: " .. table.concat(fixed, ", ")
            end
        end)
    end
    return clone, summary
end

function Core.removeProps(model)
    if model then
        Core.OwnProps[model] = nil
        pcall(function() model:Destroy() end)
    end
end

-- Hide (not destroy) a prop model the game spawned for the original emote; returns an undo list
function Core.hideModel(model, list)
    list = list or {}
    local function set(inst, prop, value)
        local ok, old = pcall(function() return inst[prop] end)
        if ok and old ~= value then
            list[#list + 1] = { inst, prop, old }
            pcall(function() inst[prop] = value end)
        end
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            set(d, "Transparency", 1)
        elseif d:IsA("Decal") or d:IsA("Texture") then
            set(d, "Transparency", 1)
        elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Light")
            or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") or d:IsA("LayerCollector") then
            set(d, "Enabled", false)
        end
    end
    return list
end

function Core.restoreHidden(list)
    if not list then return end
    for i = #list, 1, -1 do
        local inst, prop, old = list[i][1], list[i][2], list[i][3]
        pcall(function() inst[prop] = old end)
    end
    table.clear(list)
end

function Core.hideGameProps(rig, list)
    list = list or {}
    for _, d in ipairs(rig:GetDescendants()) do
        if d:IsA("Model") and d.Name == "EmoteModel" and not Core.OwnProps[d] and not Core.inPropModel(d, rig) then
            Core.hideModel(d, list)
        end
    end
    return list
end

-- When the game attaches real emote props to the rig, remember which body part each joint uses
function Core.learnFromGameProps(model)
    local changed = false
    for _, j in ipairs(model:GetDescendants()) do
        if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
            local p0 = j.Part0
            if p0 and not p0:IsDescendantOf(model) and Core.PropJoints[j.Name] ~= p0.Name then
                Core.PropJoints[j.Name] = p0.Name
                Core.PropJoints["*"] = p0.Name
                changed = true
            end
        end
    end
    if changed and not Core.SavePending then
        Core.SavePending = true
        task.delay(2, function()
            Core.SavePending = false
            if Alive then saveConfig() end
        end)
    end
end

-- ============================================================
-- Movement while emoting (OPTIONAL, gameplay — Settings → "Move like the replacement")
-- Evade reads EmoteInfo.SpeedMult (and Length) from the emote's item data table:
-- Facepalm SpeedMult=0 (can't move), Catjam 0.2, Rockin' Stride 0.3 … Copying the
-- replacement's values onto the original emote lets you move like the replacement.
-- ============================================================
Core.SpeedPatches = {}

function Core.moduleData(mod)
    if not mod then return nil end
    local cached = Core.ModuleData[mod]
    if cached ~= nil then return cached or nil end
    local ok, v = pcall(require, mod)
    local r = (ok and type(v) == "table") and v or false
    Core.ModuleData[mod] = r
    return r or nil
end

function Core.emoteInfo(key)
    local e = Library[key]
    local data = e and Core.moduleData(e.Module)
    local info = data and rawget(data, "EmoteInfo")
    return type(info) == "table" and info or nil
end

function Core.unpatchMovement(key)
    local p = Core.SpeedPatches[key]
    if not p then return end
    Core.SpeedPatches[key] = nil
    for _, c in ipairs(p.copies or {}) do
        for field, value in pairs(c.old) do
            pcall(function() c.info[field] = value end)
        end
        for _, field in ipairs(c.cleared or {}) do
            pcall(function() c.info[field] = nil end)
        end
    end
end

-- EmoteInfo fields copied from the replacement: sound always (it is what you hear),
-- movement fields only with Settings → "Move like the replacement"
Core.SOUND_FIELDS = { "Sound", "SoundLoops" }
Core.MOVE_FIELDS = { "SpeedMult", "Length", "BetterEmoteSystem" }
Core.NativeLoop = {}   -- [animId] = the animation asset's own Looped setting

-- Sound asset id from an EmoteInfo.Sound value (id, "rbxassetid://…" or a Sound instance)
function Core.soundIdOf(v)
    if typeof(v) == "Instance" then
        if v:IsA("Sound") then return toId(v.SoundId) end
        local s = v:FindFirstChildWhichIsA("Sound", true)
        return s and toId(s.SoundId) or nil
    end
    if type(v) == "string" or type(v) == "number" then return toId(tostring(v)) end
    return nil
end

-- Every sound id an emote item can play: EmoteInfo.Sound + Sound instances inside the module
function Core.emoteSoundIds(key, info)
    local ids = {}
    local id = info and Core.soundIdOf(rawget(info, "Sound"))
    if id then ids[id] = true end
    local e = Library[key]
    if e and e.Module then
        for _, d in ipairs(e.Module:GetDescendants()) do
            if d:IsA("Sound") then
                local sid = toId(d.SoundId)
                if sid then ids[sid] = true end
            end
        end
    end
    return ids
end

-- Runtime fallback: for a few seconds after the original starts, any Sound playing the
-- original emote's audio near the player is switched to the replacement's audio.
function Core.swapSound(rig, srcKey, targetKey)
    local p = Core.SpeedPatches[srcKey]
    local srcInfo = Core.emoteInfo(srcKey)
    local srcIds = Core.emoteSoundIds(srcKey, p and p.oldInfo or srcInfo)
    if p and p.oldInfo then
        local oid = Core.soundIdOf(p.oldInfo.Sound)
        if oid then srcIds[oid] = true end
    end
    local ti = Core.emoteInfo(targetKey)
    local targetId = ti and Core.soundIdOf(rawget(ti, "Sound"))
    if not targetId then
        for id in pairs(Core.emoteSoundIds(targetKey, nil)) do targetId = id break end
    end
    if targetId then srcIds[targetId] = nil end
    if not next(srcIds) then return end
    local places = { rig, Core.hitboxModel(), LocalPlayer.Character, workspace.CurrentCamera, game:GetService("SoundService") }
    task.spawn(function()
        local t0, switched = os.clock(), 0
        while Alive and os.clock() - t0 < 3 do
            for _, place in ipairs(places) do
                if place and place.Parent then
                    for _, s in ipairs(place:GetDescendants()) do
                        if s:IsA("Sound") and not s:GetAttribute("SwapSound") and srcIds[toId(s.SoundId) or ""] then
                            s:SetAttribute("SwapSound", true)
                            if targetId then
                                local wasPlaying = s.IsPlaying
                                s.SoundId = "rbxassetid://" .. targetId
                                if wasPlaying then s:Play() end
                            else
                                s.Volume = 0 -- the replacement has no sound: silence the original's
                            end
                            switched += 1
                        end
                    end
                end
            end
            task.wait(0.1)
        end
        if switched > 0 then Diag.Sound = string.format("%d sound(s) switched at play time → %s", switched, tostring(targetId or "muted")) end
    end)
end

-- The executor's require() can return its own copy of an item table, separate from the one the
-- game's scripts use. Find the game's copies in memory (same AppearanceInfo.Name + EmoteInfo).
Core.GameDataIndex, Core.GameDataAt = nil, 0

-- Item tables in memory. getgc(true) on most executors; filtergc (sUNC) on executors without getgc.
function Core.memoryItemTables()
    if type(getgc) == "function" then
        local ok, objs = pcall(getgc, true)
        if ok and type(objs) == "table" then return objs, "getgc" end
    end
    if type(filtergc) == "function" then
        local ok, objs = pcall(filtergc, "table", { Keys = { "EmoteInfo", "AppearanceInfo" } }, false)
        if ok and type(objs) == "table" then return objs, "filtergc" end
    end
    return nil, "none"
end

function Core.gameEmoteInfos(name)
    if type(name) ~= "string" then return {} end
    if not Core.GameDataIndex or os.clock() - Core.GameDataAt > 20 then
        local index = {}
        local objs, how = Core.memoryItemTables()
        Core.MemoryAccess = how
        if objs then
            for _, t in ipairs(objs) do
                if type(t) == "table" then
                    local okR, ei, ai = pcall(function() return rawget(t, "EmoteInfo"), rawget(t, "AppearanceInfo") end)
                    if okR and type(ei) == "table" and type(ai) == "table" then
                        local n = rawget(ai, "Name")
                        if type(n) == "string" then
                            index[n] = index[n] or {}
                            table.insert(index[n], ei)
                        end
                    end
                end
            end
        end
        Core.GameDataIndex, Core.GameDataAt = index, os.clock()
    end
    return Core.GameDataIndex[name] or {}
end

-- Display name stored in the item data (what the game's copies are keyed by)
function Core.dataName(key)
    local e = Library[key]
    local data = e and Core.moduleData(e.Module)
    local ai = data and rawget(data, "AppearanceInfo")
    local n = type(ai) == "table" and rawget(ai, "Name") or nil
    return type(n) == "string" and n or (e and e.Name)
end

function Core.unpatchAll()
    local keys = {}
    for k in pairs(Core.SpeedPatches) do keys[#keys + 1] = k end
    for _, k in ipairs(keys) do Core.unpatchMovement(k) end
end

function Core.patchMovement(key)
    Core.unpatchMovement(key)
    local swap = Swaps[key]
    if not swap or not SETTINGS.SwapEngineEnabled then return end
    local srcName = Library[key] and Library[key].Name or key
    local si, ti = Core.emoteInfo(key), Core.emoteInfo(swap.Target)
    if not si or not ti then
        Diag.Movement = srcName .. ": item data not readable"
        return
    end
    local fields = {}
    for _, f in ipairs(Core.SOUND_FIELDS) do fields[#fields + 1] = f end
    if SETTINGS.MoveLikeReplacement then
        for _, f in ipairs(Core.MOVE_FIELDS) do fields[#fields + 1] = f end
    end
    local oldInfo = {}
    for _, f in ipairs(fields) do oldInfo[f] = rawget(si, f) end
    local old = { SpeedMult = rawget(si, "SpeedMult"), Length = rawget(si, "Length") }
    local newSpeed, newLength = rawget(ti, "SpeedMult"), rawget(ti, "Length")
    -- our copy + every copy the game's own scripts hold
    local infos, seen = { si }, { [si] = true }
    for _, gi in ipairs(Core.gameEmoteInfos(Core.dataName(key))) do
        if not seen[gi] and gi ~= ti then
            seen[gi] = true
            infos[#infos + 1] = gi
        end
    end
    local copies = {}
    for _, info in ipairs(infos) do
        local isFrozen = table.isfrozen and table.isfrozen(info)
        local prev, cleared = {}, {}
        for _, f in ipairs(fields) do
            local v = rawget(info, f)
            if v == nil then cleared[#cleared + 1] = f else prev[f] = v end
        end
        local ok = not isFrozen and pcall(function()
            for _, f in ipairs(fields) do info[f] = rawget(ti, f) end
        end)
        if ok then copies[#copies + 1] = { info = info, old = prev, cleared = cleared } end
    end
    if #copies > 0 then
        Core.SpeedPatches[key] = { info = si, old = old, oldInfo = oldInfo, copies = copies }
        Diag.Sound = string.format("%s: sound %s → %s", srcName,
            tostring(Core.soundIdOf(oldInfo.Sound) or "none"), tostring(Core.soundIdOf(rawget(ti, "Sound")) or "none"))
        if SETTINGS.MoveLikeReplacement then
            Diag.Movement = string.format("%s: SpeedMult %s → %s, Length %s → %s · %d data copies patched (%d in game memory, via %s)",
                srcName, tostring(old.SpeedMult), tostring(newSpeed), tostring(old.Length), tostring(newLength),
                #copies, #infos - 1, tostring(Core.MemoryAccess or "?"))
            if Core.MemoryAccess == "none" then
                Diag.Movement = Diag.Movement .. " — your executor has no getgc/filtergc: the game's own copy can't be changed, so you can't move"
            end
        end
    else
        Diag.Movement = srcName .. ": could not change item data"
    end
end

function Core.patchAll()
    for key in pairs(Swaps) do Core.patchMovement(key) end
end

-- ============================================================
-- Unusual cosmetics (visual only). Each Unusual keeps a full character copy
-- (Character = R15, CharacterClassic = classic) whose effects — attachments with
-- ParticleEmitter / Beam / Light, and extra parts welded to Head/Torso — are moved
-- onto the matching parts of the local rig.
-- ============================================================
Core.Cosmetics = {}        -- [key] = { Key, Id, Name, Lower, Collection, Module, IsCosmetic = true }
Core.UnusualParts = nil    -- instances added to the rig (removed on take-off)
Core.EFFECT_CLASSES = { "ParticleEmitter", "Beam", "Trail", "Light", "Fire", "Smoke", "Sparkles", "BillboardGui", "SurfaceGui", "Highlight" }

function Core.isEffect(inst)
    for _, cls in ipairs(Core.EFFECT_CLASSES) do
        if inst:IsA(cls) then return true end
    end
    return false
end

function Core.hasEffects(inst)
    for _, d in ipairs(inst:GetDescendants()) do
        if Core.isEffect(d) then return true end
    end
    return false
end

function Core.isRigBodyPart(p)
    return p:IsA("BasePart") and (Core.BODY_PARTS[p.Name] or p.Name == "TorsoRot" or p.Name == "ArmRot") or false
end

-- Nearest ancestor folder named "Cosmetics" (nil when the module is not a cosmetic)
function Core.cosmeticsFolderOf(mod)
    local p, depth = mod.Parent, 0
    while p and p ~= ReplicatedStorage and depth < 8 do
        if p.Name == "Cosmetics" then return p end
        p, depth = p.Parent, depth + 1
    end
    return nil
end

-- Worth reading: anything in an Unusual* folder, or a cosmetic that carries its own character
-- copy (Character / CharacterClassic) — that is how Unusual effects are stored.
function Core.cosmeticCandidate(mod)
    local parent = mod.Parent
    if parent.Name:sub(1, 7) == "Unusual" then return true end
    if not Core.cosmeticsFolderOf(mod) then return false end
    return mod:FindFirstChild("CharacterClassic") ~= nil or mod:FindFirstChild("Character") ~= nil
end

function Core.isUnusualCosmetic(mod, data)
    if mod.Parent and mod.Parent.Name:sub(1, 7) == "Unusual" then return true end
    if type(data) == "table" then
        local ci, ui, ei = rawget(data, "CosmeticInfo"), rawget(data, "UIInfo"), rawget(data, "EquipInfo")
        if type(ci) == "table" and rawget(ci, "Unusual") == true then return true end
        local rarity = type(ui) == "table" and rawget(ui, "Rarity") or nil
        if type(rarity) == "string" and rarity:lower():find("unusual", 1, true) then return true end
        local slot = type(ei) == "table" and rawget(ei, "SlotType") or nil
        if type(slot) == "string" and slot:lower():find("unusual", 1, true) then return true end
        return false
    end
    -- data unreadable: fall back to the path
    local okP, path = pcall(mod.GetFullName, mod)
    path = okP and path:lower() or ""
    return path:find("unusual", 1, true) ~= nil or path:find("aura", 1, true) ~= nil
end

function Core.registerCosmetic(mod, data)
    local key = Core.itemKey(mod)
    local info = type(data) == "table" and rawget(data, "AppearanceInfo") or nil
    local an = type(info) == "table" and rawget(info, "Name") or nil
    local name = (type(an) == "string" and trim(an) ~= "") and trim(an) or Core.prettify(mod.Name)
    local cosmeticsFolder = Core.cosmeticsFolderOf(mod) or (mod.Parent and mod.Parent.Parent)
    local coll = cosmeticsFolder and cosmeticsFolder.Parent and cosmeticsFolder.Parent ~= ReplicatedStorage and cosmeticsFolder.Parent.Name or nil
    if coll == "Items" then coll = nil end
    Core.Cosmetics[key] = { Key = key, Id = key, Name = name, Lower = name:lower(), Collection = coll, Module = mod, IsCosmetic = true }
end

-- ============================================================
-- Body visuals (local only): Headless and Korblox legs on the animation rig
-- ============================================================
Core.KORBLOX_MESH    = "rbxassetid://101851696" -- Korblox Deathspeaker Right Leg (R6 mesh)
Core.KORBLOX_TEXTURE = "rbxassetid://101851254"
Core.KORBLOX_LEFT_MESH = "rbxassetid://101851582" -- Korblox Deathspeaker Left Leg (R6 mesh, armored)
Core.LeftMeshFailed = false                        -- left mesh did not load → mirrored right leg instead

-- Avatar tab (sidebar): body visuals shown as wearable rows
Core.BODY_ITEMS = {
    { Setting = "Headless", Name = "Headless Horseman (head)", Note = "hides your head and face" },
    { Setting = "KorbloxRight", Name = "Korblox Deathspeaker Right Leg", Note = "bony right leg" },
    { Setting = "KorbloxLeft", Name = "Korblox Deathspeaker Left Leg", Note = "armored left leg" },
}

function Core.bodyItems()
    local out = {}
    for _, b in ipairs(Core.BODY_ITEMS) do
        out[#out + 1] = { Key = "body:" .. b.Setting, Setting = b.Setting, Name = b.Name, Note = b.Note, IsBody = true }
    end
    return out
end

function Core.toggleBody(setting)
    SETTINGS[setting] = not SETTINGS[setting]
    Core.applyBody()
    saveConfig()
    return SETTINGS[setting]
end
Core.Body = { Hidden = {}, Parts = {}, Conns = {} }

function Core.removeBody()
    local b = Core.Body
    for _, c in ipairs(b.Conns) do pcall(function() c:Disconnect() end) end
    for _, p in ipairs(b.Parts) do pcall(function() p:Destroy() end) end
    Core.restoreHidden(b.Hidden)
    table.clear(b.Conns)
    table.clear(b.Parts)
end

-- A body part of the rig itself (never the hitbox, never a prop)
function Core.ownBodyPart(rig, names)
    for _, n in ipairs(names) do
        for _, d in ipairs(rig:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == n and not Core.inPropModel(d, rig) and not Core.OwnProps[d] then return d end
        end
    end
    return nil
end

-- Make a part (and its face / textures) invisible, and keep it invisible if the game resets it
function Core.hideBodyPart(part)
    local b = Core.Body
    local function set(inst, prop, value)
        local ok, old = pcall(function() return inst[prop] end)
        if ok and old ~= value then
            b.Hidden[#b.Hidden + 1] = { inst, prop, old }
            pcall(function() inst[prop] = value end)
        end
    end
    set(part, "Transparency", 1)
    for _, d in ipairs(part:GetChildren()) do
        if d:IsA("Decal") or d:IsA("Texture") then set(d, "Transparency", 1) end
    end
    b.Conns[#b.Conns + 1] = part:GetPropertyChangedSignal("Transparency"):Connect(function()
        if part.Transparency ~= 1 then part.Transparency = 1 end
    end)
    b.Conns[#b.Conns + 1] = part.ChildAdded:Connect(function(d)
        if d:IsA("Decal") or d:IsA("Texture") then set(d, "Transparency", 1) end
    end)
end

function Core.korbloxLeg(rig, leg, mirrored, container)
    Core.hideBodyPart(leg)
    local p = Instance.new("Part")
    p.Name = mirrored and "SwapKorbloxLeft" or "SwapKorbloxRight"
    p.Size = leg.Size
    p.CanCollide, p.CanTouch, p.CanQuery, p.Massless, p.Anchored = false, false, false, true, false
    p.CFrame = leg.CFrame
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.FileMesh
    -- left leg: Korblox's own (armored) left leg; mirrored right leg only if that mesh fails to load
    local useLeftMesh = mirrored and not Core.LeftMeshFailed
    mesh.MeshId = useLeftMesh and Core.KORBLOX_LEFT_MESH or Core.KORBLOX_MESH
    mesh.TextureId = Core.KORBLOX_TEXTURE
    mesh:SetAttribute("SwapLeft", useLeftMesh or nil)
    -- R6 limb meshes are made for a 1×2×1 limb; a negative X mirrors the right leg for the left side
    local flip = (mirrored and not useLeftMesh) and -1 or 1
    mesh.Scale = Vector3.new(flip * leg.Size.X / 1, leg.Size.Y / 2, leg.Size.Z / 1)
    mesh.Parent = p
    local w = Instance.new("Weld")
    w.Part0, w.Part1 = leg, p
    w.Parent = p
    p.Parent = container
    return mesh
end

function Core.applyBody()
    Core.removeBody()
    local rig = LocalRig
    local wanted = SETTINGS.Headless or SETTINGS.KorbloxRight or SETTINGS.KorbloxLeft
    if not wanted then
        Diag.Body = "off"
        return
    end
    if not rig or not rig.Parent then
        Diag.Body = "waiting for your rig"
        return
    end
    local notes = {}
    if SETTINGS.Headless then
        local head = Core.ownBodyPart(rig, { "Head" })
        if head then
            Core.hideBodyPart(head)
            notes[#notes + 1] = "headless"
        else
            notes[#notes + 1] = "headless: no Head part"
        end
    end
    local meshes = {}
    if SETTINGS.KorbloxRight or SETTINGS.KorbloxLeft then
        local container = Instance.new("Model")
        container.Name = "SwapBody"
        container.Parent = rig
        Core.Body.Parts[#Core.Body.Parts + 1] = container
        for _, side in ipairs({ { SETTINGS.KorbloxRight, { "Right Leg", "RightUpperLeg" }, false, "right" },
                                { SETTINGS.KorbloxLeft, { "Left Leg", "LeftUpperLeg" }, true, "left" } }) do
            if side[1] then
                local leg = Core.ownBodyPart(rig, side[2])
                if leg then
                    meshes[#meshes + 1] = Core.korbloxLeg(rig, leg, side[3], container)
                    notes[#notes + 1] = "korblox " .. side[4] .. (leg.Name:find("Upper", 1, true) and " (R15: upper leg only)" or "")
                else
                    notes[#notes + 1] = "korblox " .. side[4] .. ": no leg part"
                end
            end
        end
    end
    Diag.Body = table.concat(notes, ", ")
    if #meshes > 0 then
        task.spawn(function()
            local results = {}
            pcall(function()
                game:GetService("ContentProvider"):PreloadAsync(meshes, function(content, s)
                    results[#results + 1] = (tostring(content) == Core.KORBLOX_LEFT_MESH and "left " or "right ") .. s.Name
                    if tostring(content) == Core.KORBLOX_LEFT_MESH and s ~= Enum.AssetFetchStatus.Success then
                        Core.LeftMeshFailed = true
                    end
                end)
            end)
            Diag.Body = table.concat(notes, ", ") .. " · mesh " .. table.concat(results, ", ")
            -- left mesh failed: rebuild with the mirrored right leg
            for _, m in ipairs(meshes) do
                if Core.LeftMeshFailed and m:GetAttribute("SwapLeft") and m.Parent then
                    task.defer(Core.applyBody)
                    break
                end
            end
        end)
    end
end

-- ============================================================
-- Catalog accessories (visual, local only): any accessory id from the Roblox catalog,
-- loaded with game:GetObjects and welded to the animation rig at its attachment point.
-- ============================================================
Core.AccCache = {}       -- [id] = template Accessory (or false when it failed to load)
Core.AccNames = {}       -- [id] = display name
Core.AccStatus = {}      -- [id] = "ok" / reason
Core.AccContainer = nil
Core.AccGen = 0

-- Standard R6 attachment points: [attachment name] = { part names, offset for a standard-size part, standard size }
Core.ATTACH_POINTS = {
    HatAttachment = { { "Head" }, CFrame.new(0, 0.6, 0), Vector3.new(2, 1, 1) },
    HairAttachment = { { "Head" }, CFrame.new(0, 0.6, 0), Vector3.new(2, 1, 1) },
    FaceFrontAttachment = { { "Head" }, CFrame.new(0, 0, -0.6), Vector3.new(2, 1, 1) },
    FaceCenterAttachment = { { "Head" }, CFrame.new(0, 0, 0), Vector3.new(2, 1, 1) },
    NeckAttachment = { { "Torso", "UpperTorso" }, CFrame.new(0, 1, 0), Vector3.new(2, 2, 1) },
    BodyFrontAttachment = { { "Torso", "UpperTorso" }, CFrame.new(0, 0, -0.5), Vector3.new(2, 2, 1) },
    BodyBackAttachment = { { "Torso", "UpperTorso" }, CFrame.new(0, 0, 0.5), Vector3.new(2, 2, 1) },
    LeftCollarAttachment = { { "Torso", "UpperTorso" }, CFrame.new(-1, 1, 0), Vector3.new(2, 2, 1) },
    RightCollarAttachment = { { "Torso", "UpperTorso" }, CFrame.new(1, 1, 0), Vector3.new(2, 2, 1) },
    WaistFrontAttachment = { { "Torso", "LowerTorso" }, CFrame.new(0, -1, -0.5), Vector3.new(2, 2, 1) },
    WaistCenterAttachment = { { "Torso", "LowerTorso" }, CFrame.new(0, -1, 0), Vector3.new(2, 2, 1) },
    WaistBackAttachment = { { "Torso", "LowerTorso" }, CFrame.new(0, -1, 0.5), Vector3.new(2, 2, 1) },
    LeftShoulderAttachment = { { "Left Arm", "LeftUpperArm" }, CFrame.new(0, 1, 0), Vector3.new(1, 2, 1) },
    RightShoulderAttachment = { { "Right Arm", "RightUpperArm" }, CFrame.new(0, 1, 0), Vector3.new(1, 2, 1) },
    LeftGripAttachment = { { "Left Arm", "LeftHand" }, CFrame.new(0, -1, 0), Vector3.new(1, 2, 1) },
    RightGripAttachment = { { "Right Arm", "RightHand" }, CFrame.new(0, -1, 0), Vector3.new(1, 2, 1) },
    LeftFootAttachment = { { "Left Leg", "LeftFoot" }, CFrame.new(0, -1, 0), Vector3.new(1, 2, 1) },
    RightFootAttachment = { { "Right Leg", "RightFoot" }, CFrame.new(0, -1, 0), Vector3.new(1, 2, 1) },
}

-- Catalog id from "12345", "rbxassetid://12345" or a catalog link
function Core.parseAssetId(text)
    return tostring(text or ""):match("(%d%d%d%d+)")
end

-- Download an accessory once (yields)
function Core.loadAccessory(id)
    local cached = Core.AccCache[id]
    if cached ~= nil then return cached or nil end
    local found
    local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
    if ok and type(objs) == "table" then
        for _, o in ipairs(objs) do
            if o:IsA("Accoutrement") then found = o break end
            local inner = o:FindFirstChildWhichIsA("Accoutrement", true)
            if inner then found = inner break end
        end
    end
    if not found then
        local okI, model = pcall(function() return game:GetService("InsertService"):LoadAsset(tonumber(id)) end)
        if okI and model then found = model:FindFirstChildWhichIsA("Accoutrement", true) end
    end
    if not found or not found:FindFirstChild("Handle") then
        Core.AccCache[id] = false
        Core.AccStatus[id] = (ok or found) and "not an accessory (or no Handle)" or "could not download (executor has no GetObjects?)"
        return nil
    end
    for _, d in ipairs(found:GetDescendants()) do
        if d:IsA("LuaSourceContainer") then pcall(function() d:Destroy() end) end
    end
    Core.AccCache[id] = found
    Core.AccNames[id] = found.Name
    Core.AccStatus[id] = "ok"
    return found
end

-- Where on the rig an accessory attachment goes: (part, CFrame relative to that part)
function Core.rigAttachPoint(rig, attName)
    for _, d in ipairs(rig:GetDescendants()) do
        if d:IsA("Attachment") and d.Name == attName and d.Parent and d.Parent:IsA("BasePart")
            and not Core.inPropModel(d.Parent, rig) and not (Core.AccContainer and d:IsDescendantOf(Core.AccContainer)) then
            return d.Parent, d.CFrame
        end
    end
    local info = Core.ATTACH_POINTS[attName]
    if not info then return nil end
    local part = Core.ownBodyPart(rig, info[1])
    if not part then return nil end
    local s = part.Size
    local std = info[3]
    local off = info[2]
    local p = off.Position * Vector3.new(s.X / std.X, s.Y / std.Y, s.Z / std.Z)
    return part, CFrame.new(p) * (off - off.Position)
end

function Core.attachAccessory(rig, template, container)
    local acc = template:Clone()
    local handle = acc:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then
        acc:Destroy()
        return false, "no Handle"
    end
    for _, d in ipairs(handle:GetChildren()) do
        if d:IsA("JointInstance") or d:IsA("WeldConstraint") then d:Destroy() end
    end
    local accAtt
    for _, d in ipairs(handle:GetChildren()) do
        if d:IsA("Attachment") and Core.ATTACH_POINTS[d.Name] then accAtt = d break end
    end
    accAtt = accAtt or handle:FindFirstChildWhichIsA("Attachment")
    local part, rigCF, handleCF
    if accAtt then
        part, rigCF = Core.rigAttachPoint(rig, accAtt.Name)
        handleCF = accAtt.CFrame
    end
    if not part then
        -- old-style hat: AttachmentPoint relative to the top of the head
        part, rigCF = Core.rigAttachPoint(rig, "HatAttachment")
        local okP, ap = pcall(function() return acc.AttachmentPoint end)
        handleCF = okP and ap or CFrame.new()
        if part then rigCF = rigCF * CFrame.new(0, -0.1, 0) end
    end
    if not part then
        acc:Destroy()
        return false, "no body part for " .. tostring(accAtt and accAtt.Name or "hat")
    end
    for _, d in ipairs(acc:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery, d.Massless = false, false, false, false, true
        end
    end
    -- head accessories ride on the head anchor too (follows prop heads during emotes)
    if part.Name == "Head" then part = Core.headAnchor(rig) or part end
    handle.CFrame = part.CFrame * rigCF * handleCF:Inverse()
    local w = Instance.new("Weld")
    w.Name = "SwapAccessoryWeld"
    w.Part0, w.Part1, w.C0, w.C1 = part, handle, rigCF, handleCF
    w.Parent = handle
    acc.Parent = container
    return true, part.Name
end

function Core.removeAccessories()
    Core.AccGen += 1
    if Core.AccContainer then pcall(function() Core.AccContainer:Destroy() end) end
    Core.AccContainer = nil
end

-- (Re)build all saved accessories on the current rig
function Core.applyAccessories()
    Core.removeAccessories()
    local rig = LocalRig
    local list = SETTINGS.Accessories
    if type(list) ~= "table" or #list == 0 then
        Diag.Accessories = "none"
        return
    end
    if not rig or not rig.Parent then
        Diag.Accessories = "waiting for your rig"
        return
    end
    local container = Instance.new("Model")
    container.Name = "SwapAccessories"
    container.Parent = rig
    Core.AccContainer = container
    local gen = Core.AccGen
    task.spawn(function()
        local okN, failed = 0, {}
        for _, id in ipairs(list) do
            id = tostring(id)
            local tpl = Core.loadAccessory(id)
            if gen ~= Core.AccGen or not Alive then return end
            if tpl then
                local ok, where = Core.attachAccessory(rig, tpl, container)
                if ok then okN += 1 else failed[#failed + 1] = id .. ": " .. tostring(where) end
                Core.AccStatus[id] = ok and ("on " .. tostring(where)) or tostring(where)
            else
                failed[#failed + 1] = id .. ": " .. tostring(Core.AccStatus[id])
            end
        end
        Diag.Accessories = string.format("%d worn%s", okN, #failed > 0 and (" · failed: " .. table.concat(failed, "; ")) or "")
        if Core.OnAccessoriesChanged then pcall(Core.OnAccessoriesChanged) end
    end)
end

-- ============================================================
-- Hide the game's own GUI (local): every PlayerGui ScreenGui except this script's, plus Roblox core GUI
-- ============================================================
Core.GameGui = nil -- { Guis = {[gui] = prevEnabled}, Core = {[type] = prev}, Conns = {} } while hidden

function Core.setGameGuiHidden(on)
    local st = Core.GameGui
    if not on then
        if not st then return end
        Core.GameGui = nil
        for _, c in ipairs(st.Conns) do pcall(function() c:Disconnect() end) end
        for gui, prev in pairs(st.Guis) do pcall(function() gui.Enabled = prev end) end
        for t, prev in pairs(st.Core) do pcall(function() StarterGui:SetCoreGuiEnabled(t, prev) end) end
        return
    end
    if st then return end
    st = { Guis = {}, Core = {}, Conns = {} }
    Core.GameGui = st
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local function hide(gui)
        if not gui:IsA("ScreenGui") or gui == Gui or (Gui and gui:IsAncestorOf(Gui)) then return end
        if st.Guis[gui] == nil then st.Guis[gui] = gui.Enabled end
        gui.Enabled = false
        st.Conns[#st.Conns + 1] = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if Core.GameGui == st and gui.Enabled then gui.Enabled = false end
        end)
    end
    if pg then
        for _, g in ipairs(pg:GetChildren()) do pcall(hide, g) end
        st.Conns[#st.Conns + 1] = pg.ChildAdded:Connect(function(g) pcall(hide, g) end)
    end
    for _, t in ipairs(Enum.CoreGuiType:GetEnumItems()) do
        if t ~= Enum.CoreGuiType.All then
            local ok, prev = pcall(function() return StarterGui:GetCoreGuiEnabled(t) end)
            if ok then
                st.Core[t] = prev
                pcall(function() StarterGui:SetCoreGuiEnabled(t, false) end)
            end
        end
    end
end

-- ============================================================
-- Catalog browser (sidebar → Catalog): search Roblox catalog accessories and wear them (visual)
-- ============================================================
Core.Catalog = { Results = {}, Seen = {}, Query = nil, Pages = nil, Cursor = nil, Loading = false, Status = "", Token = 0 }
Core.CATALOG_TYPES = { "Hat", "HairAccessory", "FaceAccessory", "NeckAccessory", "ShoulderAccessory", "FrontAccessory", "BackAccessory", "WaistAccessory" }

function Core.isWorn(id)
    for _, v in ipairs(SETTINGS.Accessories) do
        if tostring(v) == tostring(id) then return true end
    end
    return false
end

-- Wear / take off one catalog accessory (shared with Settings → Catalog accessory)
function Core.toggleAccessory(id, name)
    id = tostring(id)
    if name then Core.AccNames[id] = Core.AccNames[id] or name end
    local removed = false
    for j, v in ipairs(SETTINGS.Accessories) do
        if tostring(v) == id then
            table.remove(SETTINGS.Accessories, j)
            removed = true
            break
        end
    end
    if not removed then table.insert(SETTINGS.Accessories, id) end
    Core.applyAccessories()
    saveConfig()
    if Core.OnAccessoriesChanged then pcall(Core.OnAccessoriesChanged) end
    return not removed
end

function Core.addCatalogItems(list)
    local c = Core.Catalog
    for _, it in ipairs(list) do
        local id = it.Id and tostring(it.Id)
        if id and not c.Seen[id] then
            c.Seen[id] = true
            c.Results[#c.Results + 1] = {
                Key = "cat:" .. id, Id = id, Name = tostring(it.Name or id), Lower = tostring(it.Name or id):lower(),
                Creator = it.Creator, IsCatalog = true,
            }
        end
    end
end

-- Roblox's own catalog API for clients (AvatarEditorService), web API through the executor as fallback
function Core.catalogFetch(query, more)
    local c = Core.Catalog
    -- an accessory id (e.g. 10159600649) or a catalog link: show exactly that item
    local idq = query:match("^%s*(%d%d%d%d+)%s*$")
    if not idq and (query:find("roblox.com", 1, true) or query:find("rbxassetid", 1, true)) then idq = Core.parseAssetId(query) end
    if idq then
        if more then return {}, "id" end
        c.More = false
        local okI, info = pcall(function()
            return game:GetService("MarketplaceService"):GetProductInfo(tonumber(idq), Enum.InfoType.Asset)
        end)
        local name = (okI and type(info) == "table" and info.Name) or ("Accessory " .. idq)
        local creator = okI and type(info) == "table" and type(info.Creator) == "table" and info.Creator.Name or nil
        Core.AccNames[idq] = Core.AccNames[idq] or name
        return { { Id = idq, Name = name, Creator = creator } }, "id"
    end
    local okA, list = pcall(function()
        local pages
        if more then
            pages = c.Pages
            if not pages or pages.IsFinished then return {} end
            pages:AdvanceToNextPageAsync()
        else
            local params = CatalogSearchParams.new()
            params.SearchKeyword = query
            local types = {}
            for _, n in ipairs(Core.CATALOG_TYPES) do
                local okT, t = pcall(function() return Enum.AvatarAssetType[n] end)
                if okT and t then types[#types + 1] = t end
            end
            params.AssetTypes = types
            pcall(function() params.Limit = 60 end)
            pages = game:GetService("AvatarEditorService"):SearchCatalog(params)
            c.Pages = pages
        end
        local out = {}
        for _, it in ipairs(pages:GetCurrentPage()) do
            if it.ItemType == nil or tostring(it.ItemType) == "Asset" or it.ItemType == Enum.AvatarItemType.Asset then
                out[#out + 1] = { Id = it.Id, Name = it.Name, Creator = it.CreatorName }
            end
        end
        c.More = not pages.IsFinished
        return out
    end)
    if okA and type(list) == "table" and (#list > 0 or more) then return list, "catalog" end
    -- fallback: catalog web API through the executor's http function
    local req = (type(request) == "function" and request) or (type(http_request) == "function" and http_request)
        or (type(syn) == "table" and syn.request) or (type(http) == "table" and http.request)
    if not req then return nil, okA and "no results" or ("catalog search failed: " .. tostring(list)) end
    local url = "https://catalog.roblox.com/v1/search/items/details?Category=11&Limit=30&Keyword="
        .. game:GetService("HttpService"):UrlEncode(query or "")
    if more and c.Cursor then url = url .. "&cursor=" .. c.Cursor end
    local okR, res = pcall(req, { Url = url, Method = "GET" })
    if not okR or type(res) ~= "table" or not res.Body then return nil, "web search failed" end
    local okJ, data = pcall(function() return game:GetService("HttpService"):JSONDecode(res.Body) end)
    if not okJ or type(data) ~= "table" or type(data.data) ~= "table" then return nil, "web search: unexpected reply" end
    c.Cursor = data.nextPageCursor
    c.More = data.nextPageCursor ~= nil
    local out = {}
    for _, it in ipairs(data.data) do
        if it.itemType == nil or it.itemType == "Asset" then
            out[#out + 1] = { Id = it.id, Name = it.name, Creator = it.creatorName }
        end
    end
    return out, "web"
end

-- Debounced search; onDone() re-renders the list
function Core.catalogSearch(query, more, onDone)
    local c = Core.Catalog
    query = trim(query or "")
    if not more and c.Query == query then return end
    c.Token += 1
    local my = c.Token
    if not more then
        c.Query = query
        c.Results, c.Seen, c.Pages, c.Cursor, c.More = {}, {}, nil, nil, false
    end
    c.Loading = true
    c.Status = "Searching the catalog…"
    if onDone then pcall(onDone) end
    task.spawn(function()
        if not more then task.wait(0.4) end -- typing debounce
        if my ~= c.Token or not Alive then return end
        local list, how = Core.catalogFetch(query, more)
        if my ~= c.Token or not Alive then return end
        c.Loading = false
        if list then
            Core.addCatalogItems(list)
            c.Status = string.format("%d accessories%s", #c.Results, c.More and " · more available" or "")
        else
            c.Status = tostring(how)
        end
        if onDone then pcall(onDone) end
    end)
end

-- Items for the list: worn accessories first, then the search results
function Core.catalogItems()
    local items, seen = {}, {}
    for _, v in ipairs(SETTINGS.Accessories) do
        local id = tostring(v)
        seen[id] = true
        items[#items + 1] = { Key = "cat:" .. id, Id = id, Name = Core.AccNames[id] or ("Accessory " .. id), IsCatalog = true }
    end
    for _, r in ipairs(Core.Catalog.Results) do
        if not seen[r.Id] then items[#items + 1] = r end
    end
    return items
end

function Core.removeUnusual()
    for _, inst in ipairs(Core.UnusualParts or {}) do pcall(function() inst:Destroy() end) end
    Core.UnusualParts = nil
end

-- ============================================================
-- Head anchor: Unusual head effects and head accessories sit on an invisible part welded
-- to the head. Emotes that take the head off (e.g. Headless Baller) use a prop head: the
-- anchor is re-welded to that prop head while it is visible, and back to the real head after.
-- ============================================================
Core.HeadAnchor = nil
Core.OWN_VISUALS = { SwapUnusual = true, SwapAccessories = true, SwapBody = true, SwapHeadAnchor = true }

function Core.isOwnVisual(d, rig)
    local cur = d
    while cur and cur ~= rig do
        if Core.OWN_VISUALS[cur.Name] then return true end
        cur = cur.Parent
    end
    return false
end

function Core.headAnchor(rig)
    local a = Core.HeadAnchor
    if a and a.Parent == rig then return a end
    local head = Core.ownBodyPart(rig, { "Head" })
    if not head then return nil end
    a = Instance.new("Part")
    a.Name = "SwapHeadAnchor"
    a.Size = head.Size
    a.Transparency = 1
    a.CanCollide, a.CanTouch, a.CanQuery, a.Massless, a.Anchored = false, false, false, true, false
    a.CFrame = head.CFrame
    local w = Instance.new("Weld")
    w.Name = "SwapHeadWeld"
    w.Part0, w.Part1 = head, a
    w.Parent = a
    a.Parent = rig
    Core.HeadAnchor = a
    return a
end

-- A visible head-like part of an emote prop (Headless Baller's held head …)
function Core.findPropHead(rig)
    for _, d in ipairs(rig:GetDescendants()) do
        if d:IsA("BasePart") and d.Transparency < 0.99 and Core.inPropModel(d, rig) and not Core.isOwnVisual(d, rig) then
            -- "Head", "FakeHead", "Head2" … but not "Headphones" / "Headband"
            local n = d.Name:lower()
            if n == "head" or n:sub(-4) == "head" or n:match("^head[%d_]*$") then return d end
        end
    end
    return nil
end

-- Unusual parts / effects that belong on the head go onto the anchor instead
function Core.visualTarget(rig, name)
    local t = Core.findRigPart(rig, name)
    if t and t.Name == "Head" and t:IsDescendantOf(rig) then return Core.headAnchor(rig) or t end
    return t
end

-- Keeps the anchor on the right head (runs while the script is alive)
function Core.headFollowStep()
    local rig = LocalRig
    local a = Core.HeadAnchor
    if not rig or not a or a.Parent ~= rig then return end
    local w = a:FindFirstChild("SwapHeadWeld")
    if not w then return end
    local want = Core.findPropHead(rig) or Core.ownBodyPart(rig, { "Head" })
    if want and w.Part0 ~= want then
        w.Part0 = want
        -- keep the effects' size/position relative to the new head
        a.Size = want.Size
        Diag.HeadFollow = (want.Name == "Head" and not Core.inPropModel(want, rig)) and "on your head"
            or ("following emote prop part " .. want:GetFullName():match("[^%.]+%.[^%.]+$"))
    end
end

function Core.wearUnusual(key)
    Core.removeUnusual()
    local c = key and Core.Cosmetics[key]
    local rig = LocalRig
    if not c then return false, "cosmetic not found in the game data" end
    if not rig or not rig.Parent then return false, "your rig was not found yet" end
    local holders = (Core.rigStyle() == "r15") and { "Character", "CharacterClassic" } or { "CharacterClassic", "Character" }
    local template
    for _, hn in ipairs(holders) do
        template = c.Module:FindFirstChild(hn)
        if template then break end
    end
    if not template then return false, "no Character template in this cosmetic" end
    local clone = Core.cloneArchivable(template)
    if not clone then return false, "clone failed" end

    local moved = {}
    local container = Instance.new("Model")
    container.Name = "SwapUnusual"
    Core.OwnProps[container] = true
    moved[1] = container

    -- 1. extra (non-body) parts: no physics, collected into the container
    local extra, extraList = {}, {}
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BasePart") and not Core.isRigBodyPart(d) then
            d.Anchored = false
            d.CanCollide = false
            d.CanTouch = false
            d.CanQuery = false
            d.Massless = true
            extra[d] = true
            extraList[#extraList + 1] = d
        end
    end

    -- 2. joints between a body part and an extra part → re-point the body side to the rig.
    --    WeldConstraints keep whatever offset the parts have when re-pointed (template space,
    --    far from the rig), so they become Welds with the template's offset instead.
    local joints, connected = 0, {}
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
            local p0, p1 = d.Part0, d.Part1
            if p0 and p1 and (extra[p0] or extra[p1]) and not (extra[p0] and extra[p1]) then
                local body = extra[p0] and p1 or p0
                local part = extra[p0] and p0 or p1
                local target = Core.visualTarget(rig, body.Name)
                if target then
                    if d:IsA("WeldConstraint") then
                        local w = Instance.new("Weld")
                        w.Name = "SwapUnusualWeld"
                        w.Part0, w.Part1 = target, part
                        w.C0 = body.CFrame:ToObjectSpace(part.CFrame)
                        w.Parent = container
                        d:Destroy()
                    else
                        if body == p0 then d.Part0 = target else d.Part1 = target end
                        d.Parent = container
                    end
                    connected[part] = true
                    joints += 1
                end
            elseif p0 and p1 and extra[p0] and extra[p1] then
                -- extra ↔ extra: keep the offset they have in the template
                if d:IsA("WeldConstraint") then
                    local w = Instance.new("Weld")
                    w.Part0, w.Part1 = p0, p1
                    w.C0 = p0.CFrame:ToObjectSpace(p1.CFrame)
                    w.Parent = p1
                    d:Destroy()
                end
            end
        end
    end
    -- spread "connected" through extra ↔ extra joints
    local changed = true
    while changed do
        changed = false
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("JointInstance") then
                local p0, p1 = d.Part0, d.Part1
                if p0 and p1 and extra[p0] and extra[p1] and (connected[p0] ~= connected[p1]) then
                    connected[p0], connected[p1] = true, true
                    changed = true
                end
            end
        end
    end
    -- loose extra parts (logos, floating items with no joint): weld to the nearest body part
    local bodies = {}
    for _, d in ipairs(clone:GetDescendants()) do
        if Core.isRigBodyPart(d) then bodies[#bodies + 1] = d end
    end
    for _, p in ipairs(extraList) do
        if not connected[p] then
            local best, bestDist
            for _, b in ipairs(bodies) do
                local dist = (b.Position - p.Position).Magnitude
                if not best or dist < bestDist then best, bestDist = b, dist end
            end
            local target = best and Core.visualTarget(rig, best.Name)
            if target then
                local w = Instance.new("Weld")
                w.Name = "SwapUnusualWeld"
                w.Part0, w.Part1 = target, p
                w.C0 = best.CFrame:ToObjectSpace(p.CFrame)
                w.Parent = container
                connected[p] = true
                joints += 1
            end
        end
    end
    for _, p in ipairs(extraList) do
        if not extra[p.Parent] then p.Parent = container end
    end

    -- 3. effects sitting on body parts (attachments holding emitters, or emitters on the part)
    local effects = 0
    for _, bp in ipairs(clone:GetDescendants()) do
        if Core.isRigBodyPart(bp) then
            local target = Core.visualTarget(rig, bp.Name)
            if target then
                for _, child in ipairs(bp:GetChildren()) do
                    if (child:IsA("Attachment") and Core.hasEffects(child)) or Core.isEffect(child) then
                        -- GUIs (logos on Billboard/SurfaceGuis) pointing at the template's body part → the rig's
                        for _, g in ipairs(child:GetDescendants()) do
                            if (g:IsA("BillboardGui") or g:IsA("SurfaceGui")) and g.Adornee and g.Adornee:IsDescendantOf(clone) then
                                g.Adornee = nil
                            end
                        end
                        if (child:IsA("BillboardGui") or child:IsA("SurfaceGui")) and child.Adornee and child.Adornee:IsDescendantOf(clone) then
                            child.Adornee = target
                        end
                        child.Parent = target
                        moved[#moved + 1] = child
                        effects += 1
                    end
                end
            end
        end
    end

    -- 4. beams/trails pointing at attachments that stayed behind: move those attachments too
    local count = #moved
    for i = 1, count do
        for _, d in ipairs(moved[i]:GetDescendants()) do
            if d:IsA("Beam") or d:IsA("Trail") then
                for _, prop in ipairs({ "Attachment0", "Attachment1" }) do
                    local att = d[prop]
                    if att and att:IsDescendantOf(clone) then
                        local bp = att.Parent
                        local target = bp and Core.isRigBodyPart(bp) and Core.visualTarget(rig, bp.Name)
                        if target then
                            att.Parent = target
                            moved[#moved + 1] = att
                        end
                    end
                end
            end
        end
    end

    container.Parent = rig
    pcall(function() clone:Destroy() end)
    Core.UnusualParts = moved
    Core.WornUnusual = key
    local summary = string.format("%s: %d parts, %d joints, %d effects (%s)", c.Name, #extraList, joints, effects, template.Name)
    Diag.Unusual = summary
    return true, summary
end

-- ============================================================
-- Visual swap engine
-- ============================================================
local function stopPreview()
    local t = PreviewTrack
    PreviewTrack = nil
    if t then pcall(function() t:Stop(0.2) end) end
    if Core.PreviewProps then
        Core.removeProps(Core.PreviewProps)
        Core.PreviewProps = nil
    end
end

local function loadTrack(animator, animId, purpose)
    if FailedAnims[animId] then return nil end
    local cache = TrackCache[animator]
    if not cache then
        cache = {}
        TrackCache[animator] = cache
    end
    local key = (purpose or "r") .. animId
    if cache[key] then return cache[key] end
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. animId
    local ok, track = pcall(animator.LoadAnimation, animator, anim)
    if not ok or not track then
        FailedAnims[animId] = tostring(track)
        return nil
    end
    OwnTracks[track] = true
    if not pcall(function() track.Priority = Enum.AnimationPriority.Action4 end) then
        pcall(function() track.Priority = Enum.AnimationPriority.Action end)
    end
    cache[key] = track
    return track
end

local function stopReplacement(sourceTrack, restoreSource)
    local rep = ActiveReplacements[sourceTrack]
    if not rep then return end
    ActiveReplacements[sourceTrack] = nil
    if rep.Conn then rep.Conn:Disconnect() end
    local shared = false
    for _, other in pairs(ActiveReplacements) do
        if other.Replacement == rep.Replacement then shared = true break end
    end
    if not shared then
        pcall(function()
            if rep.Replacement.IsPlaying then rep.Replacement:Stop(0.15) end
        end)
    end
    Core.removeProps(rep.Props)
    rep.Props = nil
    Core.restoreHidden(rep.Hidden)
    if restoreSource then
        pcall(function()
            if sourceTrack.IsPlaying then sourceTrack:AdjustWeight(rep.PrevWeight or 1, 0.1) end
        end)
        if rep.SourceLoopChanged then pcall(function() sourceTrack.Looped = false end) end
    end
end

local function stopAllReplacements(restoreSource)
    local list = {}
    for t in pairs(ActiveReplacements) do list[#list + 1] = t end
    for _, t in ipairs(list) do stopReplacement(t, restoreSource) end
end

local function stopReplacementsForSource(sourceKey)
    local list = {}
    for t, rep in pairs(ActiveReplacements) do
        if rep.SourceId == sourceKey then list[#list + 1] = t end
    end
    for _, t in ipairs(list) do stopReplacement(t, true) end
end

local function hideSource(track)
    pcall(function() track:AdjustWeight(0.001, 0) end)
end

local function applySwap(animator, track, srcKey, variant)
    if not SETTINGS.SwapEngineEnabled or OwnTracks[track] then return end
    local swap = Swaps[srcKey]
    if not swap or swap.Target == srcKey then return end
    local target = Library[swap.Target]
    local targetAnim, targetVariant
    if target then targetAnim, targetVariant = Core.pickVariant(target, variant, true) end
    local sourceName = Library[srcKey] and Library[srcKey].Name or srcKey
    if not targetAnim then
        FailedTargets[swap.Target] = "no animation for this rig"
        Diag.LastSwap = string.format("%s [%s] → %s: NOT applied — target has no %s/compatible animation, original kept",
            sourceName, tostring(variant), tostring(swap.TargetName or swap.Target), Core.styleOf(variant) or Core.rigStyle())
        notify(tostring(swap.TargetName or swap.Target) .. " has no animation for your rig type — original kept.", "fail" .. swap.Target)
        onSwapFailed(srcKey, swap.Target)
        scheduleUI(true)
        return
    end
    local sourceAnim = track.Animation and toId(track.Animation.AnimationId)
    if targetAnim == sourceAnim then return end

    local existing = ActiveReplacements[track]
    if existing then
        if existing.TargetAnim == targetAnim then
            hideSource(track)
            if not existing.Replacement.IsPlaying then existing.Replacement:Play(0.1, 1, 1) end
            return
        end
        stopReplacement(track, true)
    end

    local newTrack = loadTrack(animator, targetAnim, "r")
    if not newTrack then
        FailedTargets[swap.Target] = "load failed"
        notify("Replacement unavailable: " .. tostring(swap.TargetName or swap.Target), "fail" .. swap.Target)
        onSwapFailed(srcKey, swap.Target)
        scheduleUI(true)
        return
    end
    if PreviewTrack then stopPreview() end

    local prevWeight = 1
    pcall(function() prevWeight = track.WeightTarget end)
    if type(prevWeight) ~= "number" or prevWeight <= 0.01 then prevWeight = 1 end

    local priority = track.Priority
    if priority == Enum.AnimationPriority.Core or priority == Enum.AnimationPriority.Idle or priority == Enum.AnimationPriority.Movement then
        priority = Enum.AnimationPriority.Action
    end
    pcall(function() newTrack.Priority = priority end)

    local rep = {
        Replacement = newTrack, SourceId = srcKey, TargetId = swap.Target, TargetAnim = targetAnim,
        Animator = animator, PrevWeight = prevWeight,
    }
    ActiveReplacements[track] = rep
    hideSource(track)

    -- Props: hide the original emote's props, attach the replacement's props (before Play so the
    -- Animator picks up the new prop joints)
    local rig = animator:FindFirstAncestorOfClass("Model")
    local propNote = "none"
    if rig then
        rep.Hidden = Core.hideGameProps(rig)
        if target.HasProps then
            local props, note = Core.attachProps(rig, target, targetVariant, nil, targetAnim)
            rep.Props = props
            propNote = props and note or ("failed: " .. tostring(note))
        end
    end
    task.defer(function()
        if ActiveReplacements[track] == rep then hideSource(track) end
    end)
    -- the game may spawn the original's props a moment after the animation starts
    task.delay(0.3, function()
        if ActiveReplacements[track] == rep and rig and rig.Parent then Core.hideGameProps(rig, rep.Hidden) end
    end)
    -- if the game removes unknown objects from its rig, re-attach the props outside the rig
    task.delay(0.6, function()
        if ActiveReplacements[track] ~= rep or not rig or not rig.Parent or not target.HasProps then return end
        if not rep.Props then return end -- attaching already failed; Diag.LastProps has the reason
        if rep.Props.Parent == rig then
            Diag.LastProps = (Diag.LastProps or "") .. " · still attached after 0.6s"
            return
        end
        Core.removeProps(rep.Props)
        local props, note = Core.attachProps(rig, target, targetVariant, workspace.CurrentCamera or workspace, targetAnim)
        rep.Props = props
        Diag.LastProps = target.Name .. ": removed from rig by the game → re-attached outside the rig (static) · "
            .. (props and note or ("failed: " .. tostring(note)))
    end)

    -- Looping: a looping replacement (strides, dances) on a one-shot original (Facepalm) used to stop
    -- after the original's few seconds. Keep the replacement's own looping and keep the hidden
    -- original running underneath, so the emote lasts until the game / player ends it.
    local native = Core.NativeLoop[targetAnim]
    if native ~= nil then
        newTrack.Looped = native or track.Looped
        if native and not track.Looped then
            rep.SourceLoopChanged = true
            pcall(function() track.Looped = true end)
        end
    elseif track.Looped then
        newTrack.Looped = true
        pcall(function() newTrack:SetAttribute("SwapForcedLoop", true) end)
    end
    newTrack:Play(0.1, 1, 1)
    if native == nil then
        task.spawn(function()
            local t0 = os.clock()
            while Alive and ActiveReplacements[track] == rep and newTrack.Length <= 0 and os.clock() - t0 < 5 do task.wait() end
            if newTrack.Length <= 0 then return end
            local loops = newTrack.Looped -- the asset's own setting unless we forced it on above
            if not newTrack:GetAttribute("SwapForcedLoop") then Core.NativeLoop[targetAnim] = loops end
            if ActiveReplacements[track] ~= rep then return end
            if loops and not track.Looped then
                rep.SourceLoopChanged = true
                pcall(function() track.Looped = true end)
            end
            newTrack.Looped = loops or track.Looped
            if not newTrack.IsPlaying then pcall(function() newTrack:Play(0.1, 1, 1) end) end
        end)
    end
    Core.swapSound(rig, srcKey, swap.Target)
    Diag.LastSwap = string.format("%s [%s %s] → %s [%s %s] on %s · %d version(s)",
        sourceName, tostring(variant), tostring(sourceAnim), target.Name, tostring(targetVariant), targetAnim,
        LocalIsRig and "rig" or "character", Core.versionCount(target))
    Diag.LastProps = target.HasProps and (target.Name .. ": " .. propNote) or (target.Name .. ": no props")

    rep.Conn = track.Stopped:Connect(function()
        stopReplacement(track, false)
        Core.maybeReemote(srcKey, rep)
    end)
    if not track.IsPlaying then
        stopReplacement(track, false)
        return
    end

    local targetKey = swap.Target
    task.delay(5, function()
        if not Alive or ActiveReplacements[track] ~= rep then return end
        local len = 0
        pcall(function() len = newTrack.Length end)
        if len <= 0 then
            FailedTargets[targetKey] = "asset did not load"
            FailedAnims[targetAnim] = "asset did not load"
            stopReplacement(track, true)
            local cache = TrackCache[animator]
            if cache then cache["r" .. targetAnim] = nil end
            notify("Replacement could not be loaded — original restored.", "fail" .. targetKey)
            onSwapFailed(srcKey, targetKey)
            scheduleUI(true)
        end
    end)
end

function Core.playingTracks()
    local animator = LocalAnimator
    if not animator then return {} end
    local ok, tracks = pcall(animator.GetPlayingAnimationTracks, animator)
    return ok and tracks or {}
end

local function reapplyPlaying(onlyKey)
    local animator = LocalAnimator
    if not animator or not SETTINGS.SwapEngineEnabled then return end
    for _, t in ipairs(Core.playingTracks()) do
        if not OwnTracks[t] and t.Animation then
            local rec = AllAnims[toId(t.Animation.AnimationId) or ""]
            if rec then
                local key = Core.sourceKeyFor(rec)
                if Swaps[key] and (not onlyKey or key == onlyKey) then applySwap(animator, t, key, rec.Variant) end
            end
        end
    end
end

local function isSourcePlaying(sourceKey)
    for _, t in ipairs(Core.playingTracks()) do
        if not OwnTracks[t] and t.Animation then
            local rec = AllAnims[toId(t.Animation.AnimationId) or ""]
            if rec and rec.Keys[sourceKey] then return true end
        end
    end
    return false
end

-- ============================================================
-- Keep emoting (OPTIONAL, Settings → "Keep emoting"): the SERVER ends an emote whose real
-- data does not allow what you do (e.g. moving with Facepalm). When that happens without
-- any key / click from you, the emote is started again — the same request the game sends
-- when you pick it from the wheel. Any key or click from you (except WASD / arrows) stops it.
-- ============================================================
Core.LastUserInput = 0
Core.LastReemote = 0
Core.ReemoteCount = 0
Core.MOVE_KEYS = { W = true, A = true, S = true, D = true, Up = true, Down = true, Left = true, Right = true, LeftShift = true }

function Core.noteInput(input)
    local t = input.UserInputType
    if t == Enum.UserInputType.Keyboard then
        if Core.MOVE_KEYS[input.KeyCode.Name] then return end
    elseif t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.Gamepad1 then
        return
    end
    Core.LastUserInput = os.clock()
end

function Core.maybeReemote(srcKey, rep)
    if not Alive or not SETTINGS.KeepEmoting or not SETTINGS.SwapEngineEnabled then return end
    if not (rep and rep.Replacement and rep.Replacement.Looped) then return end -- only looping replacements
    local id = tonumber(srcKey)
    if not id then return end
    local ended = os.clock()
    task.delay(0.35, function()
        if not Alive or not SETTINGS.KeepEmoting then return end
        if Core.LastUserInput >= ended - 0.8 then return end      -- you ended it yourself
        if os.clock() - Core.LastReemote < 1.5 then return end    -- never spam the server
        if isSourcePlaying(srcKey) then return end                -- next part (Intro → main) already playing
        local hb = Core.hitboxModel()
        local hum = hb and hb:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return end
        -- walking: only a problem when the speed patch could NOT reach the game's data (then the
        -- emote ended because you moved, and re-playing it would freeze you in place). With the
        -- patch active the emote simply ran out (one-shot emotes like Facepalm last ~4.5 s).
        local movePatched = SETTINGS.MoveLikeReplacement and Core.SpeedPatches[srcKey] ~= nil
            and Core.MemoryAccess ~= nil and Core.MemoryAccess ~= "none"
        if hum and hum.MoveDirection.Magnitude > 0.1 and not movePatched then
            Diag.Reemote = "not re-played: you were moving (the original emote can't move)"
            return
        end
        local events = ReplicatedStorage:FindFirstChild("Events")
        local remote = events and events:FindFirstChild("CharacterTask")
        if not remote then return end
        Core.LastReemote = os.clock()
        Core.ReemoteCount += 1
        local ok = pcall(function() remote:FireServer("Emote", id) end)
        Diag.Reemote = string.format("%s re-played %d time(s) after the server ended it", ok and "emote" or "FAILED:", Core.ReemoteCount)
    end)
end

local function hasActiveReplacement(sourceKey)
    for _, rep in pairs(ActiveReplacements) do
        if rep.SourceId == sourceKey then
            local ok, playing = pcall(function() return rep.Replacement.IsPlaying end)
            if ok and playing then return true end
        end
    end
    return false
end

-- "ok" | "failed" | "unknown" (no answer before the timeout)
local function checkLoadable(key, timeout)
    local e = Library[key]
    local animId = e and Core.pickVariant(e, PreferredVariant)
    if not animId then return "failed" end
    FailedAnims[animId] = nil
    local animator = LocalAnimator
    if animator then
        local cache = TrackCache[animator]
        local t = cache and (cache["r" .. animId] or cache["p" .. animId])
        if t then
            local len = 0
            pcall(function() len = t.Length end)
            if len > 0 then return "ok" end
        end
    end
    local result, done = "unknown", false
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. animId
    task.spawn(function()
        pcall(function()
            ContentProvider:PreloadAsync({ anim }, function(_, status)
                local s = tostring(status)
                if s:find("Success") then
                    result = "ok"
                elseif s:find("Failure") then
                    result = "failed"
                end
            end)
        end)
        done = true
    end)
    local t0 = os.clock()
    while Alive and not done and os.clock() - t0 < timeout do task.wait(0.05) end
    return result
end

local function setSwap(sourceKey, sourceName, targetKey, targetName)
    if not sourceKey or not targetKey or sourceKey == targetKey then return false end
    FailedTargets[targetKey] = nil
    Swaps[sourceKey] = { Target = targetKey, SourceName = sourceName or sourceKey, TargetName = targetName or targetKey }
    saveConfig()
    Core.prefetchPoses(targetKey)
    Core.patchMovement(sourceKey)
    stopReplacementsForSource(sourceKey)
    reapplyPlaying(sourceKey)
    scheduleUI(true)
    return true
end

local function removeSwap(sourceKey)
    if not Swaps[sourceKey] then return end
    Core.unpatchMovement(sourceKey)
    Swaps[sourceKey] = nil
    stopReplacementsForSource(sourceKey)
    saveConfig()
    scheduleUI(true)
end

-- ============================================================
-- Animation hooks: Evade plays emotes on the visual rig Workspace.Rigs.<PlayerName>
-- ============================================================
-- Only the local player's own rig is hooked; other players are never scanned
local function onTrack(animator, track, isLocal)
    if not Alive or not isLocal or OwnTracks[track] then return end
    SeenTracks[track] = true
    local anim = track.Animation
    local id = anim and toId(anim.AnimationId)
    local rec = id and AllAnims[id]
    if not rec then return end -- not an emote item (movement, tools, carries …) → ignored
    local key = Core.sourceKeyFor(rec)
    -- learn the rig's variant from the main animation only (never from an Intro / Outro / End part)
    if Core.styleOf(rec.Variant) and not Core.isPhase(rec.Variant) then PreferredVariant = rec.Variant end
    recordDetected(key, true)
    if SETTINGS.DetectCurrentlyPlaying then trackStarted(animator, track, key) end
    if Swaps[key] then applySwap(animator, track, key, rec.Variant) end
end

local function cleanupCharacter(model)
    local maid = CharMaids[model]
    if not maid then return end
    CharMaids[model] = nil
    for _, c in ipairs(maid) do pcall(function() c:Disconnect() end) end
    local animator = maid.Animator
    if animator then
        local reps = {}
        for t, rep in pairs(ActiveReplacements) do
            if rep.Animator == animator then reps[#reps + 1] = t end
        end
        for _, t in ipairs(reps) do stopReplacement(t, false) end
        local states = {}
        for t, st in pairs(TrackState) do
            if st.Animator == animator then states[#states + 1] = t end
        end
        for _, t in ipairs(states) do trackEnded(t) end
        if LocalAnimator == animator then
            LocalAnimator = nil
            LocalRig = nil
            LocalIsRig = false
            PreviewTrack = nil
        end
    end
end

local function hookCharacter(model, isLocal, isRig)
    if not Alive or CharMaids[model] then return end
    local maid = {}
    CharMaids[model] = maid
    local hum = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 15)
    if not Alive or CharMaids[model] ~= maid then return end
    if not hum then cleanupCharacter(model) return end
    -- Evade calls Humanoid:LoadAnimation on the rig; prefer its Animator, fall back to the Humanoid itself
    local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5) or hum
    if not Alive or CharMaids[model] ~= maid then return end

    maid.Animator = animator
    if isLocal and (isRig or not LocalIsRig) then
        LocalAnimator = animator
        LocalRig = model
        LocalIsRig = isRig and true or false
    end
    maid[#maid + 1] = animator.AnimationPlayed:Connect(function(track)
        onTrack(animator, track, isLocal)
    end)
    maid[#maid + 1] = model.AncestryChanged:Connect(function(_, parent)
        if parent == nil then cleanupCharacter(model) end
    end)
    if isLocal and isRig then
        -- a new rig after respawn: Headless / Korblox back on
        task.delay(1, function()
            if Alive and LocalRig == model then
                Core.applyBody()
                Core.applyAccessories()
            end
        end)
    end
    if isLocal and isRig and Core.WornUnusual then
        -- a new rig after respawn: put the visual Unusual back on
        task.delay(1, function()
            if Alive and LocalRig == model and Core.WornUnusual and LibraryCount > 0 then
                Core.wearUnusual(Core.WornUnusual)
                scheduleUI()
            end
        end)
    end
    if isLocal then
        -- Props the game attaches to the rig: learn their joints, and hide them while a swap is active
        maid[#maid + 1] = model.DescendantAdded:Connect(function(d)
            if not (d:IsA("Model") and d.Name == "EmoteModel") or Core.OwnProps[d] then return end
            task.defer(function()
                if not Alive or not d.Parent then return end
                Core.learnFromGameProps(d)
                for _, rep in pairs(ActiveReplacements) do
                    if rep.Animator == animator then
                        rep.Hidden = rep.Hidden or {}
                        Core.hideModel(d, rep.Hidden)
                        break
                    end
                end
            end)
        end)
    end
    local ok, tracks = pcall(animator.GetPlayingAnimationTracks, animator)
    if ok then
        for _, t in ipairs(tracks) do onTrack(animator, t, isLocal) end
    end
    scheduleUI()
end

-- Fallback for games / updates without a Rigs folder: the local Character itself
local function hookPlayer(plr)
    if plr ~= LocalPlayer or PlayerConns[plr] then return end
    local conns = {}
    PlayerConns[plr] = conns
    conns[#conns + 1] = plr.CharacterAdded:Connect(function(char)
        task.spawn(hookCharacter, char, true, false)
    end)
    conns[#conns + 1] = plr.CharacterRemoving:Connect(cleanupCharacter)
    if plr.Character then task.spawn(hookCharacter, plr.Character, true, false) end
end

local function unhookPlayer(plr)
    local conns = PlayerConns[plr]
    if conns then
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        PlayerConns[plr] = nil
    end
end

local function hookRigs()
    local function onRig(m)
        if not m:IsA("Model") then return end
        if m.Name == LocalPlayer.Name then
            task.spawn(hookCharacter, m, true, true)
        end
    end
    local function attach(folder)
        for _, c in ipairs(folder:GetChildren()) do onRig(c) end
        bind(folder.ChildAdded, onRig)
        bind(folder.ChildRemoved, cleanupCharacter)
    end
    local rigs = workspace:FindFirstChild("Rigs")
    if rigs then
        attach(rigs)
    else
        bind(workspace.ChildAdded, function(c)
            if c.Name == "Rigs" then attach(c) end
        end)
    end
end

-- ============================================================
-- EmoteWheelScanner — Evade wheel: PlayerGui…Popups.Emote.Wheel.Emote1..N, each slot has a
-- ViewportFrame preview rig whose Animator plays that emote's animation.
-- ============================================================
local EmoteWheelScanner = { RootCount = 0, LastScan = 0, Slots = 0 }
do
    local roots = {}
    local thread
    local playerGui
    local slotLast = setmetatable({}, { __mode = "k" })   -- [Animator] = last animation id it played
    local slotHooked = setmetatable({}, { __mode = "k" })
    -- Wheel display overrides (visual, local only): a swapped slot shows the replacement's
    -- name and plays the replacement on its preview rig; restored when the swap goes away.
    local W = {
        Own = setmetatable({}, { __mode = "k" }),      -- [AnimationTrack] = true (our preview tracks)
        Labels = {},                                   -- [TextLabel] = { Src, Target, Orig, Shown }
        Anims = {},                                    -- [Animator] = { Src, Target, Track, Hidden = {track=true} }
        LabelHooked = setmetatable({}, { __mode = "k" }),
    }
    EmoteWheelScanner.Overrides = W

    -- swap still valid for this override record?
    function W.valid(rec)
        local s = Swaps[rec.Src]
        return s ~= nil and s.Target == rec.Target and Library[rec.Target] ~= nil and SETTINGS.SwapEngineEnabled
    end

    function W.hideTrack(rec, t)
        if W.Own[t] or rec.Hidden[t] then return end
        rec.Hidden[t] = true
        pcall(function() t:AdjustWeight(0.001, 0) end)
    end

    function W.restoreAnim(animator)
        local rec = W.Anims[animator]
        if not rec then return end
        W.Anims[animator] = nil
        if rec.Track then
            W.Own[rec.Track] = nil
            pcall(function() rec.Track:Stop(0.1) end)
            pcall(function() rec.Track:Destroy() end)
        end
        for t in pairs(rec.Hidden) do
            pcall(function() if t.IsPlaying then t:AdjustWeight(1, 0.1) end end)
        end
        if rec.Props then Core.removeProps(rec.Props) end
        if rec.HiddenProps then Core.restoreHidden(rec.HiddenProps) end
    end

    -- Hold the preview still on one pose, like the game's own wheel previews
    function W.freeze(rec)
        task.spawn(function()
            local track = rec.Track
            local t0 = os.clock()
            while Alive and W.Anims[rec.Animator] == rec and track.Length <= 0 and os.clock() - t0 < 5 do task.wait(0.1) end
            if not Alive or W.Anims[rec.Animator] ~= rec or track.Length <= 0 then return end
            local rel = 0.3
            for t in pairs(rec.Hidden) do
                local ok, speed, pos, len = pcall(function() return t.Speed, t.TimePosition, t.Length end)
                if ok and len > 0 and speed == 0 then
                    rel = math.clamp(pos / len, 0, 0.95) -- same point in the animation as the original preview
                    break
                end
            end
            pcall(function()
                track:AdjustSpeed(0)
                track.TimePosition = rel * track.Length
            end)
            rec.Frozen = true
        end)
    end

    -- The replacement's props on the preview rig (the original's props hidden)
    function W.props(rec, rig, target, variant, animId)
        if not rig then return end
        Core.NoHitbox[rig] = true
        rec.HiddenProps = Core.hideGameProps(rig, rec.HiddenProps)
        if rec.Props and rec.Props.Parent then return end
        rec.Props = nil
        if not target.HasProps then return end
        local okA, clone = pcall(Core.attachProps, rig, target, variant, nil, animId)
        if okA and clone then rec.Props = clone end
    end

    function W.restoreLabel(label)
        local rec = W.Labels[label]
        if not rec then return end
        W.Labels[label] = nil
        pcall(function() if label.Text == rec.Shown then label.Text = rec.Orig end end)
    end

    function W.applyLabel(label, text, srcKey)
        local s = Swaps[srcKey]
        local target = s and Library[s.Target]
        local rec = W.Labels[label]
        if rec and (rec.Src ~= srcKey or not target or rec.Target ~= s.Target) then
            W.restoreLabel(label)
            rec = nil
        end
        if not target or not SETTINGS.SwapEngineEnabled then return end
        if not rec then
            rec = { Src = srcKey, Target = s.Target, Orig = text, Shown = target.Name }
            W.Labels[label] = rec
        end
        if not W.LabelHooked[label] then
            W.LabelHooked[label] = true
            label:GetPropertyChangedSignal("Text"):Connect(function()
                local r = W.Labels[label]
                if not Alive or not r or label.Text == r.Shown then return end
                -- the game rewrote the label: keep overriding only if it is still the same emote
                if Core.resolveName(label.Text) == r.Src and W.valid(r) then
                    r.Orig = label.Text
                    task.defer(function()
                        if W.Labels[label] == r then pcall(function() label.Text = r.Shown end) end
                    end)
                else
                    W.Labels[label] = nil
                end
            end)
        end
        if label.Text ~= rec.Shown then pcall(function() label.Text = rec.Shown end) end
    end

    function W.applyAnim(animator, srcKey, rig)
        local rigName = rig and rig.Name
        local s = Swaps[srcKey]
        local target = s and Library[s.Target]
        local rec = W.Anims[animator]
        if rec and (rec.Src ~= srcKey or not target or rec.Target ~= s.Target) then
            W.restoreAnim(animator)
            rec = nil
        end
        if not target or not SETTINGS.SwapEngineEnabled then return end
        local okT, tracks = pcall(animator.GetPlayingAnimationTracks, animator)
        tracks = okT and tracks or {}
        if not rec then
            local wanted = (rigName and rigName:find("Classic", 1, true)) and "AnimationClassic" or PreferredVariant
            local animId, variant = Core.pickVariant(target, wanted, false)
            if not animId or FailedAnims[animId] then return end
            local priority = Enum.AnimationPriority.Action
            for _, t in ipairs(tracks) do
                if not W.Own[t] then priority = t.Priority break end
            end
            local anim = Instance.new("Animation")
            anim.AnimationId = "rbxassetid://" .. animId
            local okL, track = pcall(animator.LoadAnimation, animator, anim)
            if not okL or not track then return end
            W.Own[track] = true
            track.Priority = priority
            track.Looped = true
            rec = { Src = srcKey, Target = s.Target, Track = track, Hidden = {}, Animator = animator,
                Variant = variant, AnimId = animId }
            W.Anims[animator] = rec
        end
        for _, t in ipairs(tracks) do W.hideTrack(rec, t) end
        if not rec.Track.IsPlaying then
            rec.Frozen = false
            pcall(function() rec.Track:Play(0) end)
        end
        if not rec.Frozen and not rec.Freezing then
            rec.Freezing = true
            W.freeze(rec)
            task.delay(6, function() rec.Freezing = false end)
        end
        W.props(rec, rig, target, rec.Variant, rec.AnimId)
    end

    -- Drop overrides whose swap was removed / changed or whose GUI is gone
    function W.sync()
        local deadA, deadL = {}, {}
        for animator, rec in pairs(W.Anims) do
            if not W.valid(rec) or animator.Parent == nil then deadA[#deadA + 1] = animator end
        end
        for label, rec in pairs(W.Labels) do
            if not W.valid(rec) or label.Parent == nil then deadL[#deadL + 1] = label end
        end
        for _, a in ipairs(deadA) do W.restoreAnim(a) end
        for _, l in ipairs(deadL) do W.restoreLabel(l) end
    end

    function EmoteWheelScanner.RestoreWheel()
        local a, l = {}, {}
        for animator in pairs(W.Anims) do a[#a + 1] = animator end
        for label in pairs(W.Labels) do l[#l + 1] = label end
        for _, x in ipairs(a) do W.restoreAnim(x) end
        for _, x in ipairs(l) do W.restoreLabel(x) end
    end

    local BLACKLIST = {
        emote = true, emotes = true, wheel = true, emotewheel = true, equip = true, equipped = true,
        unequip = true, close = true, back = true, none = true, empty = true, select = true,
        selected = true, search = true, cancel = true, ok = true, play = true, settings = true,
        shop = true, buy = true, owned = true, locked = true, new = true, free = true, slot = true,
    }

    local function isWheelName(n)
        n = n:lower()
        return n:find("emote", 1, true) ~= nil or n:find("wheel", 1, true) ~= nil
    end

    function EmoteWheelScanner.ConsiderRoot(inst)
        if not Alive or not isWheelName(inst.Name) then return end
        if not (inst:IsA("GuiBase2d") or inst:IsA("Folder")) then return end
        if Gui and (inst == Gui or inst:IsDescendantOf(Gui)) then return end
        roots[inst] = true
    end

    function EmoteWheelScanner.Discover()
        if not playerGui then return end
        local ok, desc = pcall(playerGui.GetDescendants, playerGui)
        if ok then
            for _, d in ipairs(desc) do EmoteWheelScanner.ConsiderRoot(d) end
        end
    end

    function EmoteWheelScanner.Init()
        playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
        if not playerGui or not Alive then return end
        bind(playerGui.DescendantAdded, EmoteWheelScanner.ConsiderRoot)
        EmoteWheelScanner.Discover()
    end

    local function activeRoots()
        local list, hasWheel = {}, false
        for r in pairs(roots) do
            if r.Parent == nil or not r:IsDescendantOf(playerGui) then
                roots[r] = nil
            else
                list[#list + 1] = r
                if r.Name:lower():find("wheel", 1, true) then hasWheel = true end
            end
        end
        local filtered = {}
        for _, r in ipairs(list) do
            if not hasWheel or r.Name:lower():find("wheel", 1, true) then filtered[#filtered + 1] = r end
        end
        local result = {}
        for _, r in ipairs(filtered) do
            local nested = false
            for _, o in ipairs(filtered) do
                if o ~= r and r:IsDescendantOf(o) then nested = true break end
            end
            if not nested then result[#result + 1] = r end
        end
        return result
    end

    local function slotText(d)
        if not (d:IsA("TextLabel") or d:IsA("TextButton")) then return nil end
        local okT, raw = pcall(function() return d.ContentText end)
        local text = trim(okT and raw or d.Text)
        local ov = W.Labels[d]
        if ov then
            if d.Text == ov.Shown then
                text = trim(ov.Orig) -- our override: the slot still holds the original emote
            else
                W.Labels[d] = nil    -- the game rewrote it
            end
        end
        if #text < 2 or #text > 40 then return nil end
        if text:match("^[%d%s%p]+$") then return nil end
        if BLACKLIST[normName(text)] then return nil end
        return text
    end

    local function findSlot(d, root)
        local cur = d
        while cur and cur ~= root do
            if cur:IsA("GuiButton") then return cur end
            if cur ~= d and cur:IsA("GuiObject") then
                local n = cur.Name:lower()
                if n:find("slot", 1, true) or n:find("item", 1, true) or n:find("button", 1, true) or n:find("emote", 1, true) then
                    return cur
                end
            end
            cur = cur.Parent
        end
        return nil
    end

    -- Animation ids exposed by one instance (preview Animator tracks, Animation objects)
    local function animIdsOf(d, out)
        if d:IsA("Animator") then
            local ok, tracks = pcall(d.GetPlayingAnimationTracks, d)
            if ok then
                for _, t in ipairs(tracks) do
                    local id = not W.Own[t] and t.Animation and toId(t.Animation.AnimationId)
                    if id then out[#out + 1] = id end
                end
            end
            if slotLast[d] then out[#out + 1] = slotLast[d] end
            if not slotHooked[d] then
                slotHooked[d] = true
                d.AnimationPlayed:Connect(function(t)
                    if not Alive or W.Own[t] then return end
                    local id = t.Animation and toId(t.Animation.AnimationId)
                    if id then slotLast[d] = id end
                    local rec = W.Anims[d]
                    if rec then
                        -- the game restarted its preview: hide it again right away (unless it is a new emote)
                        local r = id and AllAnims[id]
                        if not r or r.Key == rec.Src then W.hideTrack(rec, t) else W.restoreAnim(d) end
                    end
                end)
            end
        elseif d:IsA("Animation") then
            local id = toId(d.AnimationId)
            if id then out[#out + 1] = id end
        elseif d:IsA("Model") and d.Name:sub(1, 9) == "VisualRig" and not PreferredVariant then
            -- the wheel preview rig tells which variant this player's rig uses
            PreferredVariant = d.Name:find("Classic", 1, true) and "AnimationClassic" or "Animation"
        end
    end

    local function collectWheel(rootList)
        local seen, slots = {}, {}
        local budget = WHEEL_SCAN_BUDGET
        for _, root in ipairs(rootList) do
            local ok, desc = pcall(root.GetDescendants, root)
            if ok then
                for _, d in ipairs(desc) do
                    budget -= 1
                    if budget <= 0 then break end
                    local ids, texts = {}, {}
                    animIdsOf(d, ids)
                    local text = slotText(d)
                    if text then texts[1] = text end
                    if #ids > 0 or #texts > 0 or d:IsA("Animator") then
                        local slot = findSlot(d, root)
                        if slot then
                            local b = slots[slot]
                            if not b then
                                b = { ids = {}, texts = {}, labels = {}, animators = {} }
                                slots[slot] = b
                            end
                            for _, id in ipairs(ids) do b.ids[#b.ids + 1] = id end
                            for _, t in ipairs(texts) do b.texts[#b.texts + 1] = t end
                            if text then b.labels[#b.labels + 1] = { d, text } end
                            if d:IsA("Animator") then
                                local rig = d:FindFirstAncestorWhichIsA("Model")
                                b.animators[#b.animators + 1] = { d, rig }
                            end
                        else
                            for _, id in ipairs(ids) do
                                local rec = AllAnims[id]
                                if rec and Library[rec.Key] then seen[rec.Key] = Library[rec.Key].Name end
                            end
                        end
                    end
                end
            end
            if budget <= 0 then break end
        end

        local slotCount = 0
        for _, b in pairs(slots) do
            local keys, slotKey = {}, nil
            for _, id in ipairs(b.ids) do
                local rec = AllAnims[id]
                if rec and Library[rec.Key] then keys[rec.Key] = true end
            end
            -- labels that match no emote ("[Q]", "TOO MANY", …) are wheel UI text, not emotes: ignored
            local labelKey = {}
            for _, l in ipairs(b.labels) do
                local key = Core.resolveName(l[2])
                if key then labelKey[#labelKey + 1] = { l[1], l[2], key } end
            end
            if next(keys) then
                slotCount += 1
                for k in pairs(keys) do
                    seen[k] = Library[k].Name
                    slotKey = slotKey or k
                end
                for _, lk in ipairs(labelKey) do
                    if keys[lk[3]] then slotKey = lk[3] break end
                end
            elseif labelKey[1] then
                slotKey = labelKey[1][3]
                seen[slotKey] = Library[slotKey].Name
                slotCount += 1
            end
            -- show the applied replacement in the wheel slot itself
            if slotKey and Swaps[slotKey] then
                for _, lk in ipairs(labelKey) do
                    if lk[3] == slotKey then pcall(W.applyLabel, lk[1], lk[2], slotKey) end
                end
                for _, a in ipairs(b.animators) do pcall(W.applyAnim, a[1], slotKey, a[2]) end
            end
        end
        W.sync()
        EmoteWheelScanner.Slots = slotCount
        return seen
    end

    local function resolvePending()
        local moves
        for key, e in pairs(Detected) do
            if e.Unresolved then
                local id = Core.resolveName(e.Name)
                if id then
                    moves = moves or {}
                    moves[#moves + 1] = { key, id, e }
                end
            end
        end
        if not moves then return false end
        for _, m in ipairs(moves) do
            local key, id, old = m[1], m[2], m[3]
            Detected[key] = nil
            local e = ensureDetected(id, old.Name)
            e.InWheel = e.InWheel or old.InWheel
            e.IsLocal = true
            if e.Origin == "DETECTED" then e.Origin = "WHEEL" end
        end
        return true
    end

    local function reconcilePlaying()
        local changed = false
        local animator = LocalAnimator
        if animator and SETTINGS.DetectCurrentlyPlaying then
            local tracks = Core.playingTracks()
            local live = {}
            for _, t in ipairs(tracks) do
                live[t] = true
                if not OwnTracks[t] and not SeenTracks[t] then
                    onTrack(animator, t, true)
                    changed = true
                end
            end
            local ended = {}
            for t in pairs(TrackState) do
                if not live[t] then
                    local okp, playing = pcall(function() return t.IsPlaying end)
                    if not (okp and playing) then ended[#ended + 1] = t end
                end
            end
            for _, t in ipairs(ended) do
                trackEnded(t)
                changed = true
            end
        end
        local stale = {}
        for t in pairs(ActiveReplacements) do
            local okp, playing = pcall(function() return t.IsPlaying end)
            if not (okp and playing) then stale[#stale + 1] = t end
        end
        for _, t in ipairs(stale) do
            stopReplacement(t, false)
            changed = true
        end
        return changed
    end

    function EmoteWheelScanner.Tick()
        if not Alive then return end
        local changed = false
        local rootList = (SETTINGS.DetectWheelEmotes and playerGui) and activeRoots() or {}
        if EmoteWheelScanner.RootCount ~= #rootList then
            EmoteWheelScanner.RootCount = #rootList
            changed = true
        end
        if #rootList > 0 and LibraryCount > 0 then
            local seen = collectWheel(rootList)
            for key, e in pairs(Detected) do
                local inWheel = seen[key] ~= nil
                if e.InWheel ~= inWheel then
                    e.InWheel = inWheel
                    changed = true
                end
            end
            for key, name in pairs(seen) do
                if key:sub(1, 5) == "name:" then
                    if not Detected[key] then
                        Detected[key] = newUnresolved(key, name)
                        changed = true
                    end
                else
                    local e, created = ensureDetected(key, name)
                    if created then
                        e.Origin = "WHEEL"
                        changed = true
                    end
                    e.IsLocal = true
                    if not e.InWheel then
                        e.InWheel = true
                        changed = true
                    end
                end
            end
        end
        if #rootList == 0 or LibraryCount == 0 then W.sync() end
        if resolvePending() then changed = true end
        if reconcilePlaying() then changed = true end
        EmoteWheelScanner.LastScan = os.clock()
        if changed then scheduleUI() end
    end

    function EmoteWheelScanner.Stop()
        if thread then
            local t = thread
            thread = nil
            if coroutine.running() ~= t then pcall(task.cancel, t) end
        end
    end

    function EmoteWheelScanner.Start()
        EmoteWheelScanner.Stop()
        if not Alive or not SETTINGS.AutoScanEnabled then return end
        local me
        me = task.spawn(function()
            while Alive and thread == me do
                local ok, err = pcall(EmoteWheelScanner.Tick)
                if not ok then warn("[SonderVade] scan error: " .. tostring(err)) end
                task.wait(math.clamp(SETTINGS.ScanInterval, MIN_INTERVAL, MAX_INTERVAL))
            end
        end)
        thread = me
    end

    function EmoteWheelScanner.IsRunning()
        return thread ~= nil
    end
end

-- ============================================================
-- Preview (temporary, never commits a swap)
-- ============================================================
local function previewAnimation(key, onFail)
    local animator = LocalAnimator
    if not animator then return false end
    local e = Library[key]
    local animId, variant
    if e then animId, variant = Core.pickVariant(e, PreferredVariant, true) end
    if not animId then return false end
    FailedAnims[animId] = nil
    stopPreview()
    local t = loadTrack(animator, animId, "p")
    if not t then return false end
    PreviewTrack = t
    local rig = animator:FindFirstAncestorOfClass("Model")
    if e.HasProps and rig then Core.PreviewProps = Core.attachProps(rig, e, variant, nil, animId) end
    t.Looped = false
    t:Play(0.1)
    task.delay(2.5, function()
        if PreviewTrack == t then
            local len = 0
            pcall(function() len = t.Length end)
            if len <= 0 and onFail then onFail() end
        end
    end)
    task.delay(5, function()
        if PreviewTrack == t then stopPreview() end
    end)
    return true
end

-- Luau allows at most 200 live locals per function, so the UI and startup
-- code lives in its own function instead of the main chunk.
local function runUI()
    -- ============================================================
    -- UI components
    -- ============================================================
    local function new(class, props, children)
        local inst = Instance.new(class)
        local parent
        for k, v in pairs(props or {}) do
            if k == "Parent" then parent = v else inst[k] = v end
        end
        for _, c in ipairs(children or {}) do c.Parent = inst end
        if parent then inst.Parent = parent end
        return inst
    end

    local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }) end
    local function stroke(color) return new("UIStroke", { Color = color or L.Border, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end

    -- Hard black drop shadow (the "sticker" look): a black copy of the element, offset
    -- down-right, kept in sync with the element's position / size / visibility.
    local function shade(gui, offset)
        offset = offset or 3
        local parent = gui.Parent
        if not parent then return nil end
        local cr = gui:FindFirstChildOfClass("UICorner")
        local sh = new("Frame", {
            Name = "HardShadow", BackgroundColor3 = L.Shadow, BorderSizePixel = 0,
            ZIndex = math.max(gui.ZIndex - 1, 0), Parent = parent,
        }, { corner(cr and cr.CornerRadius.Offset or 6) })
        local function sync()
            local p = gui.Position
            sh.Position = UDim2.new(p.X.Scale, p.X.Offset + offset, p.Y.Scale, p.Y.Offset + offset)
            sh.Size = gui.Size
            sh.AnchorPoint = gui.AnchorPoint
            sh.Visible = gui.Visible and gui.BackgroundTransparency < 1
        end
        sync()
        for _, prop in ipairs({ "Position", "Size", "Visible", "AnchorPoint", "BackgroundTransparency" }) do
            gui:GetPropertyChangedSignal(prop):Connect(sync)
        end
        gui:GetPropertyChangedSignal("Parent"):Connect(function() sh.Parent = gui.Parent end)
        gui.Destroying:Connect(function() sh:Destroy() end)
        return sh
    end

    local function tween(obj, t, props)
        local ok, tw = pcall(TweenService.Create, TweenService, obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
        if ok and tw then tw:Play() end
    end

    local function label(props)
        props.BackgroundTransparency = 1
        props.Font = props.Font or F.Regular
        props.TextSize = props.TextSize or 12
        props.TextColor3 = props.TextColor3 or L.Text
        props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
        props.TextTruncate = props.TextTruncate or Enum.TextTruncate.AtEnd
        return new("TextLabel", props)
    end

    local BUTTON_STYLES = {
        default = { Bg = L.Content, Hover = L.ButtonHover, Text = L.Text, Border = L.Border },
        primary = { Bg = L.Primary, Hover = L.PrimaryH, Text = L.Text, Border = L.Border },
        soft    = { Bg = L.AccentSoft, Hover = L.AccentSoftH, Text = L.Text, Border = L.Border },
        ghost   = { Bg = L.Content, Hover = L.BadSoft, Text = L.Bad, Border = L.Border },
        toolbar = { Bg = L.Content, Hover = L.ButtonHover, Text = L.Text, Border = L.Border },
        gray    = { Bg = L.GrayBtn, Hover = L.GrayBtnH, Text = L.Text, Border = L.Border },
        grayOn  = { Bg = L.GrayBtnOn, Hover = L.PrimaryH, Text = L.Text, Border = L.Border },
        dark    = { Bg = L.DarkBtn, Hover = L.DarkBtnH, Text = WHITE, Border = L.Border },
        slate   = { Bg = L.SlateBtn, Hover = L.SlateBtnH, Text = L.Text, Border = L.Border },
    }

    local function applyStyle(btn, styleName)
        local s = BUTTON_STYLES[styleName] or BUTTON_STYLES.default
        btn:SetAttribute("Base", s.Bg)
        btn:SetAttribute("Hover", s.Hover)
        btn.BackgroundColor3 = s.Bg
        btn.TextColor3 = s.Text
        local st = btn:FindFirstChildOfClass("UIStroke")
        if s.Border then
            if not st then
                st = stroke(s.Border)
                st.Parent = btn
            end
            st.Color = s.Border
            st.Enabled = true
        elseif st then
            st.Enabled = false
        end
    end

    local function makeButton(props, styleName, radius, noShadow)
        props.AutoButtonColor = false
        props.Font = props.Font or F.Bold
        props.TextSize = props.TextSize or 12
        local btn = new("TextButton", props, { corner(radius or 6) })
        applyStyle(btn, styleName or "default")
        if not noShadow then shade(btn, 2) end
        btn.MouseEnter:Connect(function()
            if not btn:GetAttribute("Disabled") then tween(btn, 0.1, { BackgroundColor3 = btn:GetAttribute("Hover") }) end
        end)
        btn.MouseLeave:Connect(function()
            tween(btn, 0.1, { BackgroundColor3 = btn:GetAttribute("Base") })
        end)
        return btn
    end

    local function setDisabled(btn, disabled)
        btn:SetAttribute("Disabled", disabled and true or false)
        btn.TextTransparency = disabled and 0.55 or 0
        btn.BackgroundColor3 = btn:GetAttribute("Base")
    end

    local function onClick(btn, fn)
        btn.MouseButton1Click:Connect(function()
            if btn:GetAttribute("Disabled") then return end
            fn()
        end)
    end

    -- opts: Fill (gray filled field), Radius, PadLeft (room for an icon)
    local function makeSearch(props, opts)
        opts = opts or {}
        props.BackgroundColor3 = opts.Fill and L.FieldFill or L.Content
        props.Font = F.Regular
        props.TextSize = props.TextSize or 12
        props.TextColor3 = L.Text
        props.PlaceholderColor3 = L.Tertiary
        props.ClearTextOnFocus = false
        props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
        props.Text = props.Text or ""
        local st = stroke(L.FieldBorder)
        local box = new("TextBox", props, {
            corner(opts.Radius or 7), st,
            new("UIPadding", { PaddingLeft = UDim.new(0, opts.PadLeft or 9), PaddingRight = UDim.new(0, 9) }),
        })
        box.Focused:Connect(function()
            st.Color = L.Accent
            st.Thickness = 3
        end)
        box.FocusLost:Connect(function()
            st.Color = L.FieldBorder
            st.Thickness = 2
        end)
        if not opts.NoShadow then shade(box, 3) end
        return box
    end

    local function makeSwitch(parent, position, getter, onToggle)
        local trackBtn = new("TextButton", {
            Text = "", AutoButtonColor = false, Position = position, Size = UDim2.fromOffset(38, 22),
            BackgroundColor3 = L.SwitchOff, Parent = parent,
        }, { corner(11), stroke(L.Border) })
        local knob = new("Frame", {
            Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(2, 2), BackgroundColor3 = WHITE,
            BorderSizePixel = 0, Parent = trackBtn,
        }, { corner(9), stroke(L.Border) })
        local function sync(animate)
            local on = getter()
            local pos = on and UDim2.fromOffset(18, 2) or UDim2.fromOffset(2, 2)
            local col = on and L.SwitchOn or L.SwitchOff
            if animate then
                tween(knob, 0.15, { Position = pos })
                tween(trackBtn, 0.15, { BackgroundColor3 = col })
            else
                knob.Position = pos
                trackBtn.BackgroundColor3 = col
            end
        end
        trackBtn.MouseButton1Click:Connect(function()
            onToggle()
            sync(true)
        end)
        sync(false)
        return sync
    end

    -- Virtualized list: a small pool of rows is re-bound while scrolling, so thousands
    -- of entries stay cheap. Click handlers read refs.Item at click time (no stale IDs).
    local function VirtualList(parent, opts)
        local list = { Items = {}, Rows = {} }
        local rowH = opts.RowHeight
        local step = rowH + (opts.Gap or 4)
        local scroll = new("ScrollingFrame", {
            Position = opts.Position, Size = opts.Size, BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 4, ScrollBarImageColor3 = L.Tertiary, CanvasSize = UDim2.new(0, 0, 0, 0),
            ScrollingDirection = Enum.ScrollingDirection.Y, AutomaticCanvasSize = Enum.AutomaticSize.None,
            Parent = parent,
        })
        local empty = label({
            Size = UDim2.new(1, -24, 0, 80), Position = UDim2.fromOffset(12, 18), TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None,
            TextColor3 = L.Tertiary, Text = opts.EmptyText or "", Visible = false, Parent = scroll,
        })
        local lastFirst = -1

        local function viewportHeight()
            local h = scroll.AbsoluteSize.Y
            if h < 10 then h = 300 end
            return h
        end

        local function ensurePool()
            local need = math.ceil(viewportHeight() / step) + 3
            while #list.Rows < need do
                local props = {
                    Size = UDim2.new(1, -10, 0, rowH), BackgroundColor3 = L.Content, BorderSizePixel = 0,
                    Visible = false, Parent = scroll,
                }
                if opts.RowClass == "TextButton" then
                    props.Text = ""
                    props.AutoButtonColor = false
                end
                local children = { corner(opts.RowCorner or 6) }
                local st
                if opts.RowStroke then
                    st = stroke(L.RowBorder)
                    children[2] = st
                end
                -- hard shadow behind each row (moved together with the row in Render)
                local rowShadow = new("Frame", {
                    Size = props.Size, BackgroundColor3 = L.Shadow, BorderSizePixel = 0, ZIndex = 0,
                    Visible = false, Parent = scroll,
                }, { corner(opts.RowCorner or 6) })
                local frame = new(opts.RowClass or "Frame", props, children)
                local refs = { Frame = frame, Stroke = st, Shadow = rowShadow }
                opts.Build(frame, refs)
                list.Rows[#list.Rows + 1] = refs
            end
        end

        function list.Render(force)
            ensurePool()
            local items = list.Items
            local first = math.max(0, math.floor(scroll.CanvasPosition.Y / step))
            if not force and first == lastFirst then return end
            lastFirst = first
            for i, refs in ipairs(list.Rows) do
                local index = first + i
                local item = items[index]
                if item then
                    refs.Item = item
                    refs.Index = index
                    refs.Frame.Position = UDim2.fromOffset(1, (index - 1) * step + 1)
                    refs.Frame.Visible = true
                    refs.Shadow.Position = UDim2.fromOffset(4, (index - 1) * step + 4)
                    refs.Shadow.Visible = true
                    opts.Bind(refs, item, index)
                else
                    refs.Item = nil
                    refs.Index = nil
                    refs.Frame.Visible = false
                    refs.Shadow.Visible = false
                end
            end
            empty.Visible = (#items == 0)
        end

        function list.SetItems(items)
            list.Items = items
            local contentH = #items * step + 4
            scroll.CanvasSize = UDim2.fromOffset(0, contentH)
            local maxY = math.max(0, contentH - viewportHeight())
            if scroll.CanvasPosition.Y > maxY then scroll.CanvasPosition = Vector2.new(0, maxY) end
            list.Render(true)
        end

        function list.Rebind() list.Render(true) end
        function list.SetEmptyText(t) empty.Text = t end
        function list.ScrollToTop()
            scroll.CanvasPosition = Vector2.new(0, 0)
            list.Render(true)
        end

        scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function() list.Render(false) end)
        scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() list.Render(true) end)
        list.Scroll = scroll
        return list
    end

    -- ============================================================
    -- Window
    -- ============================================================
    loadConfig()     -- 1. saved swaps, settings, aliases (before the UI so its state is restored)
    loadFavorites()

    local function guiParent()
        if gethui then
            local ok, h = pcall(gethui)
            if ok and h then return h end
        end
        local ok = pcall(function()
            local t = Instance.new("ScreenGui")
            t.Parent = game:GetService("CoreGui")
            t:Destroy()
        end)
        if ok then return game:GetService("CoreGui") end
        return LocalPlayer:WaitForChild("PlayerGui")
    end

    local ParentGui = guiParent()
    pcall(function()
        for _, n in ipairs({ "SonderVade", "EvadeEmoteSwapper" }) do
            local old = ParentGui:FindFirstChild(n)
            if old then old:Destroy() end
        end
    end)

    Gui = new("ScreenGui", { Name = "SonderVade", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 50 })
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(Gui) end end)
    Gui.Parent = ParentGui

    local NORMAL_SIZE = Vector2.new(600, 520)
    local ZOOM_SIZE   = Vector2.new(880, 660)
    local TITLE_H, TOOLBAR_H, SIDEBAR_W = 26, 64, 150 -- TOOLBAR_H = title row + toolbar row

    local State = {
        View = "main", Category = "Emotes", SourceId = nil, SourceName = nil, PickForKey = nil,
        PendingId = nil, FavOnly = false, Queries = { main = "", lib = "" }, Busy = false,
        LibKey = nil, LibFilterKey = nil, Minimized = false, Zoomed = (UiState.Zoomed == 1),
    }

    local Holder = new("Frame", {
        Size = UDim2.fromOffset(NORMAL_SIZE.X, NORMAL_SIZE.Y),
        Position = UDim2.new(0.5, -NORMAL_SIZE.X / 2, 0.5, -NORMAL_SIZE.Y / 2),
        BackgroundTransparency = 1, Parent = Gui,
    })
    new("Frame", { -- hard black window shadow
        Position = UDim2.fromOffset(6, 6), Size = UDim2.fromScale(1, 1), BackgroundColor3 = L.Shadow,
        BorderSizePixel = 0, ZIndex = 0, Parent = Holder,
    }, { corner(14) })
    local Window = new("Frame", {
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = L.Bg, BorderSizePixel = 0, Active = true,
        ClipsDescendants = true, Parent = Holder,
    }, { corner(14), new("UIStroke", { Color = L.Border, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })

    if type(UiState.XS) == "number" and type(UiState.XO) == "number" and type(UiState.YS) == "number" and type(UiState.YO) == "number" then
        Holder.Position = UDim2.new(UiState.XS, UiState.XO, UiState.YS, UiState.YO)
        task.defer(function()
            local cam = workspace.CurrentCamera
            if not cam then return end
            local vp, pos = cam.ViewportSize, Holder.AbsolutePosition
            if pos.X < -NORMAL_SIZE.X + 60 or pos.Y < -10 or pos.X > vp.X - 60 or pos.Y > vp.Y - 40 then
                Holder.Position = UDim2.new(0.5, -NORMAL_SIZE.X / 2, 0.5, -NORMAL_SIZE.Y / 2)
            end
        end)
    end

    -- Toolbar (title bar + toolbar, unified like macOS)
    local Toolbar = new("Frame", { Size = UDim2.new(1, 0, 0, TOOLBAR_H + 4), BackgroundColor3 = L.Toolbar, BorderSizePixel = 0, Parent = Window }, { corner(14) })
    new("Frame", { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), BackgroundColor3 = L.Toolbar, BorderSizePixel = 0, Parent = Toolbar })

    local TitleLbl = label({
        Text = DEV_BUILD and "SonderVade · Dev" or "SonderVade", Font = F.Black, TextSize = 13, TextColor3 = L.TitleText,
        Size = UDim2.new(1, 0, 0, TITLE_H), TextXAlignment = Enum.TextXAlignment.Center, Parent = Toolbar,
    })

    local TrafficLights = {}
    local function trafficLight(x, color, glyph)
        local b = new("TextButton", {
            Position = UDim2.fromOffset(x, math.floor((TITLE_H - 12) / 2) + 1), Size = UDim2.fromOffset(12, 12),
            BackgroundColor3 = color, AutoButtonColor = false, Text = "", Font = F.Bold, TextSize = 10,
            TextColor3 = color:Lerp(BLACK, 0.6), ZIndex = 3, Parent = Toolbar,
        }, { corner(7), new("UIStroke", { Color = L.Border, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
        b:SetAttribute("Glyph", glyph)
        TrafficLights[#TrafficLights + 1] = b
        b.MouseEnter:Connect(function()
            for _, t in ipairs(TrafficLights) do t.Text = t:GetAttribute("Glyph") end
        end)
        b.MouseLeave:Connect(function()
            for _, t in ipairs(TrafficLights) do t.Text = "" end
        end)
        return b
    end
    local CloseLight = trafficLight(12, L.Red, "×")
    local MinLight   = trafficLight(30, L.Yellow, "–")
    local ZoomLight  = trafficLight(48, L.Green, "+")

    -- Toolbar row: segmented ‹ | › control + pill search field
    local ROW2_Y = TITLE_H + 3
    local NavGroup = new("Frame", {
        Position = UDim2.fromOffset(12, ROW2_Y), Size = UDim2.fromOffset(60, 30), BackgroundColor3 = L.Content,
        BorderSizePixel = 0, ZIndex = 3, Visible = false, Parent = Toolbar, -- back / forward hidden (sidebar navigates)
    }, { corner(8), stroke(L.FieldBorder) })
    shade(NavGroup, 3)
    local BackBtn = makeButton({ Text = "<", TextSize = 14, Font = F.Black, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0.5, 0, 1, 0), ZIndex = 3, Parent = NavGroup }, "default", 8, true)
    local FwdBtn  = makeButton({ Text = ">", TextSize = 14, Font = F.Black, Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, 0, 1, 0), ZIndex = 3, Parent = NavGroup }, "default", 8, true)
    for _, b in ipairs({ BackBtn, FwdBtn }) do
        local st = b:FindFirstChildOfClass("UIStroke")
        if st then st.Enabled = false end
    end
    new("Frame", { Position = UDim2.new(0.5, -1, 0, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = L.FieldBorder, BorderSizePixel = 0, ZIndex = 4, Parent = NavGroup })

    local ToolbarSearch = makeSearch({
        Position = UDim2.fromOffset(12, ROW2_Y), Size = UDim2.new(1, -28, 0, 30), PlaceholderText = "Search...",
        TextSize = 13, ZIndex = 3, Parent = Toolbar,
    }, { Radius = 8, PadLeft = 32 })
    do -- drawn magnifier icon (no external image assets)
        local ring = new("Frame", {
            Position = UDim2.new(0, -22, 0.5, -7), Size = UDim2.fromOffset(11, 11), BackgroundTransparency = 1,
            ZIndex = 4, Parent = ToolbarSearch,
        }, { corner(6), new("UIStroke", { Color = L.Secondary, Thickness = 1.6 }) })
        new("Frame", {
            Position = UDim2.fromOffset(9, 10), Size = UDim2.fromOffset(6, 2), Rotation = 45, BackgroundColor3 = L.Secondary,
            BorderSizePixel = 0, ZIndex = 4, Parent = ring,
        })
    end

    -- Sidebar
    local Sidebar = new("Frame", { Position = UDim2.fromOffset(0, TOOLBAR_H + 4), Size = UDim2.new(0, SIDEBAR_W, 1, -(TOOLBAR_H + 4)), BackgroundTransparency = 1, Parent = Window })
    local SidebarLine = new("Frame", { Position = UDim2.new(0, SIDEBAR_W, 0, TOOLBAR_H + 4), Size = UDim2.new(0, 2, 1, -(TOOLBAR_H + 4)), BackgroundColor3 = L.Border, BorderSizePixel = 0, Parent = Window })

    local SidebarItems = {}
    local function sidebarItem(key, text, y, fromBottom)
        local pos = fromBottom and UDim2.new(0, 10, 1, y) or UDim2.fromOffset(10, y)
        -- selected item: yellow fill, black outline and a hard shadow (shown only when selected)
        local sh = new("Frame", {
            Position = pos + UDim2.fromOffset(3, 3), Size = UDim2.new(1, -22, 0, 30), BackgroundColor3 = L.Shadow,
            BorderSizePixel = 0, Visible = false, ZIndex = 0, Parent = Sidebar,
        }, { corner(7) })
        local st = stroke(L.Border)
        st.Enabled = false
        local b = new("TextButton", {
            Position = pos, Size = UDim2.new(1, -22, 0, 30),
            BackgroundColor3 = L.SidebarSel, BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = Sidebar,
        }, { corner(7), st })
        local t = label({ Text = text, Font = F.Bold, TextSize = 12, TextColor3 = L.RowText, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -56, 1, 0), Parent = b })
        local c = label({ Text = "", Font = F.Bold, TextSize = 11, TextColor3 = L.Tertiary, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -50, 0, 0), Size = UDim2.fromOffset(42, 30), Parent = b })
        b.MouseEnter:Connect(function()
            if not b:GetAttribute("Selected") then
                b.BackgroundColor3 = L.ToolbarHover
                b.BackgroundTransparency = 0
            end
        end)
        b.MouseLeave:Connect(function()
            if not b:GetAttribute("Selected") then b.BackgroundTransparency = 1 end
        end)
        SidebarItems[key] = { Button = b, Label = t, Count = c, Stroke = st, Shadow = sh }
        return b
    end
    sidebarItem("Emotes", "Emotes", 12)
    sidebarItem("Unusual", "Unusual", 50)
    sidebarItem("Favorites", "Favorites", 88)
    sidebarItem("Catalog", "Catalog", 126)
    sidebarItem("Avatar", "Avatar", 164)
    sidebarItem("Settings", "Settings", -46, true)

    -- Content area (white, rounded only at the bottom-right corner)
    local Content = new("Frame", {
        Position = UDim2.fromOffset(SIDEBAR_W + 2, TOOLBAR_H + 4), Size = UDim2.new(1, -(SIDEBAR_W + 2), 1, -(TOOLBAR_H + 4)),
        BackgroundColor3 = L.Bg, BorderSizePixel = 0, ClipsDescendants = true, Parent = Window,
    }, { corner(14) })
    new("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = L.Bg, BorderSizePixel = 0, ZIndex = 0, Parent = Content })
    new("Frame", { Size = UDim2.new(0, 14, 1, 0), BackgroundColor3 = L.Bg, BorderSizePixel = 0, ZIndex = 0, Parent = Content })

    -- Forward declarations for navigation
    local navigate, goBack, goForward, renderLib

    local function statusOf(e)
        if e.Unresolved or not e.Id then return "Unknown ID", L.Warn end
        if e.IsPlaying then return "● Playing", L.Good end
        if e.InWheel then return "Wheel", L.Accent end
        if e.Manual then return "Manual", L.Secondary end
        if e.IsLocal then return "Detected", L.Secondary end
        if e.SeenOther then return "Other player", L.Purple end
        if e.FromSwap then return "Saved", L.Secondary end
        return "Detected", L.Secondary
    end

    -- ------------------------------------------------------------
    -- View: YOUR EMOTES
    -- ------------------------------------------------------------
    local MainView = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = Content })
    local MainTitle = label({ Text = "Your Emotes", Font = F.Black, TextSize = 20, Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -210, 0, 26), Parent = MainView })
    local MainCount = label({ Text = "", TextSize = 11, TextColor3 = L.Tertiary, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -206, 0, 12), Size = UDim2.fromOffset(190, 22), Parent = MainView })
    local MAIN_BOX_SIZE, MAIN_BOX_SIZE_BANNER = UDim2.new(1, -32, 1, -124), UDim2.new(1, -32, 1, -154)
    local MainBox = new("Frame", {
        Position = UDim2.fromOffset(16, 42), Size = MAIN_BOX_SIZE, BackgroundColor3 = L.Content,
        BackgroundTransparency = 1, BorderSizePixel = 0, Parent = MainView,
    })

    local function openFor(e)
        if e.Unresolved or not e.Id then
            navigate("pick", { PickForKey = e.Key, Query = e.Name })
        else
            navigate("replace", { SourceId = e.Id, SourceName = e.Name })
        end
    end

    local showBanner -- forward

    local MainList = VirtualList(MainBox, {
        Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 1, -8), RowHeight = 34, Gap = 8,
        RowStroke = true, RowCorner = 7, EmptyText = "",
        Build = function(row, refs)
            refs.Text = label({ RichText = true, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -236, 1, 0), TextSize = 12, TextColor3 = L.RowText, Parent = row })
            refs.Thumb = new("ImageLabel", { Position = UDim2.fromOffset(6, 2), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Visible = false, Parent = row })
            refs.Status = label({ Position = UDim2.new(1, -226, 0, 0), Size = UDim2.new(0, 100, 1, 0), TextSize = 11, Font = F.Medium, TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
            refs.Change = makeButton({ Text = "Change", Font = F.Bold, TextSize = 11, Position = UDim2.new(1, -118, 0.5, -11), Size = UDim2.fromOffset(78, 22), Parent = row }, "gray", 5)
            refs.Remove = makeButton({ Text = "×", TextSize = 15, Position = UDim2.new(1, -36, 0.5, -11), Size = UDim2.fromOffset(28, 22), Parent = row }, "ghost", 5)
            onClick(refs.Change, function()
                local e = refs.Item
                if not e then return end
                if e.IsBody then
                    local now = Core.toggleBody(e.Setting)
                    showBanner(now and ("Wearing " .. e.Name .. " (visual only)") or ("Took off " .. e.Name), now and L.Good or L.Secondary)
                    scheduleUI(true)
                    return
                end
                if e.IsCatalog then
                    local now = Core.toggleAccessory(e.Id, e.Name)
                    showBanner(now and ("Wearing " .. e.Name .. " (visual only)") or ("Took off " .. e.Name), now and L.Good or L.Secondary)
                    scheduleUI(true)
                    return
                end
                if e.IsCosmetic then
                    if Core.WornUnusual == e.Key then
                        Core.removeUnusual()
                        Core.WornUnusual = nil
                        Diag.Unusual = "none"
                        showBanner("Took off " .. e.Name, L.Secondary)
                    else
                        local ok, msg = Core.wearUnusual(e.Key)
                        showBanner(ok and ("Wearing " .. e.Name .. " (visual only)") or ("Failed — " .. tostring(msg)), ok and L.Good or L.Bad)
                    end
                    saveConfig()
                    scheduleUI(true)
                    return
                end
                openFor(e)
            end)
            onClick(refs.Remove, function()
                local e = refs.Item
                if e and e.IsCosmetic then
                    -- star / unstar an Unusual cosmetic
                    if Core.FavUnusual[e.Key] then Core.FavUnusual[e.Key] = nil else Core.FavUnusual[e.Key] = true end
                    saveConfig()
                    scheduleUI(true)
                    return
                end
                if e and e.Id and Swaps[e.Id] then
                    removeSwap(e.Id)
                    showBanner("Removed — " .. e.Name .. " plays its original animation again", L.Secondary)
                end
            end)
        end,
        Bind = function(refs, e)
            refs.Remove.Text = "×"
            refs.Remove.TextColor3 = L.Text
            refs.Thumb.Visible = e.IsCatalog == true
            refs.Text.Position = UDim2.fromOffset(e.IsCatalog and 40 or 10, 0)
            if e.IsBody then
                local on = SETTINGS[e.Setting] == true
                refs.Text.Text = escapeRich(e.Name) .. '<font color="' .. hex(L.Tertiary) .. '">  ·  ' .. escapeRich(e.Note) .. "</font>"
                refs.Status.Text = on and "● Wearing" or ""
                refs.Status.TextColor3 = L.Good
                refs.Change.Text = on and "Take off" or "Wear"
                refs.Remove.Visible = false
                refs.Frame.BackgroundColor3 = on and L.RowPlaying or L.Content
                return
            end
            if e.IsCatalog then
                local worn = Core.isWorn(e.Id)
                refs.Thumb.Image = "rbxthumb://type=Asset&id=" .. e.Id .. "&w=48&h=48"
                local status = worn and Core.AccStatus[e.Id]
                refs.Text.Text = escapeRich(e.Name) .. (e.Creator and ('<font color="' .. hex(L.Tertiary) .. '">  ·  by ' .. escapeRich(tostring(e.Creator)) .. "</font>") or "")
                refs.Status.Text = worn and ((status and status ~= "ok" and not status:find("^on ")) and "⚠ failed" or "● Wearing") or ""
                refs.Status.TextColor3 = (worn and status and status ~= "ok" and not status:find("^on ")) and L.Bad or L.Good
                refs.Change.Text = worn and "Take off" or "Wear"
                refs.Remove.Visible = false
                refs.Frame.BackgroundColor3 = worn and L.RowPlaying or L.Content
                return
            end
            if e.IsCosmetic then
                local worn = Core.WornUnusual == e.Key
                refs.Text.Text = escapeRich(e.Name) .. (e.Collection and ("  ·  " .. escapeRich(e.Collection)) or "")
                refs.Status.Text = worn and "● Wearing" or ""
                refs.Status.TextColor3 = L.Good
                refs.Change.Text = worn and "Take off" or "Wear"
                -- the × slot becomes a favorite star for Unusual cosmetics
                local fav = Core.FavUnusual[e.Key] == true
                refs.Remove.Visible = true
                refs.Remove.Text = fav and "★" or "☆"
                refs.Remove.TextColor3 = fav and L.Star or L.Secondary -- same star as the emote library
                refs.Frame.BackgroundColor3 = worn and L.RowPlaying or L.Content
                return
            end
            local lib = e.Id and Library[e.Id]
            local swap = e.Id and Swaps[e.Id]
            local st, sc = statusOf(e)
            refs.Status.Text = st
            refs.Status.TextColor3 = sc
            local name = escapeRich(e.Name)
            local dim = hex(L.Tertiary)
            if e.Unresolved or not e.Id then
                refs.Text.Text = name .. '<font color="' .. hex(L.Warn) .. '">  ·  no ID in wheel — Find it</font>'
                refs.Change.Text = "Find…"
                refs.Remove.Visible = false
            elseif swap then
                local failed = FailedTargets[swap.Target] ~= nil
                refs.Text.Text = name .. '<font color="' .. hex(failed and L.Bad or L.Accent) .. '">  →  '
                    .. escapeRich(swap.TargetName or swap.Target) .. (failed and "  (unavailable)" or "") .. "</font>"
                refs.Change.Text = "Change"
                refs.Remove.Visible = true
            else
                local extra = (lib and lib.Collection) and ("  ·  " .. escapeRich(lib.Collection)) or ""
                if e.SeenOther and not e.IsLocal then extra = extra .. '<font color="' .. dim .. '">  ·  other player</font>' end
                refs.Text.Text = name .. extra
                refs.Change.Text = "Swap"
                refs.Remove.Visible = false
            end
            refs.Frame.BackgroundColor3 = e.IsPlaying and L.RowPlaying or L.Content
        end,
    })

    local MainBanner = new("Frame", { Position = UDim2.new(0, 16, 1, -108), Size = UDim2.new(1, -32, 0, 26), BackgroundColor3 = L.AccentSoft, BorderSizePixel = 0, Visible = false, Parent = MainView }, { corner(5) })
    local MainBannerLbl = label({ Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextSize = 12, Font = F.Medium, Parent = MainBanner })
    local StatusLine = new("TextButton", {
        Position = UDim2.new(0, 16, 1, -76), Size = UDim2.new(1, -32, 0, 18), BackgroundTransparency = 1,
        Text = "", RichText = true, Font = F.Regular, TextSize = 11, TextColor3 = L.Secondary,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, AutoButtonColor = false, Parent = MainView,
    })
    local ChooseBtn = makeButton({ Text = "Choose Original Emote From Library", Font = F.Bold, TextSize = 12, Position = UDim2.new(0, 16, 1, -50), Size = UDim2.new(1, -32, 0, 34), Parent = MainView }, "dark", 6)

    local bannerToken = 0
    showBanner = function(text, color)
        bannerToken += 1
        local my = bannerToken
        MainBanner.Visible = true
        MainBanner.BackgroundColor3 = color:Lerp(WHITE, 0.87)
        MainBannerLbl.Text = text
        MainBannerLbl.TextColor3 = color:Lerp(BLACK, 0.1)
        MainBox.Size = MAIN_BOX_SIZE_BANNER
        task.delay(8, function()
            if my == bannerToken and Alive then
                MainBanner.Visible = false
                MainBox.Size = MAIN_BOX_SIZE
            end
        end)
    end

    -- ------------------------------------------------------------
    -- View: library browser ("Show instead of …" / "Choose original")
    -- ------------------------------------------------------------
    local LibView = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = Content })
    local LibTitle = label({ Font = F.Black, TextSize = 18, Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -150, 0, 26), Parent = LibView })
    local LibRemoveBtn = makeButton({ Text = "Remove visual", TextSize = 11, Position = UDim2.new(1, -124, 0, 12), Size = UDim2.fromOffset(108, 22), Parent = LibView }, "ghost", 5)
    local LibSearch = makeSearch({
        Position = UDim2.fromOffset(16, 42), Size = UDim2.new(1, -134, 0, 30), PlaceholderText = "Search emotes",
        TextXAlignment = Enum.TextXAlignment.Center, Parent = LibView,
    }, { Fill = true, Radius = 5 })
    local FavFilterBtn = makeButton({ Text = "☆ Favorites", Font = F.Bold, TextSize = 12, Position = UDim2.new(1, -112, 0, 42), Size = UDim2.fromOffset(96, 30), Parent = LibView }, "gray", 5)
    local LibBox = new("Frame", {
        Position = UDim2.fromOffset(16, 80), Size = UDim2.new(1, -32, 1, -152), BackgroundColor3 = L.Content,
        BackgroundTransparency = 1, BorderSizePixel = 0, Parent = LibView,
    })
    local LibStatus = label({ TextSize = 11, TextColor3 = L.Tertiary, Position = UDim2.new(0, 16, 1, -68), Size = UDim2.new(1, -32, 0, 18), Parent = LibView })
    local PreviewBtn = makeButton({ Text = "Preview", Font = F.Bold, TextSize = 12, Position = UDim2.new(0, 16, 1, -86), Size = UDim2.new(0.3, -20, 0, 32), Visible = false, Parent = LibView }, "gray", 6)
    local ApplyBtn = makeButton({ Text = "APPLY VISUAL", Font = F.Bold, TextSize = 12, Position = UDim2.new(0.3, 4, 1, -86), Size = UDim2.new(0.7, -20, 0, 32), Visible = false, Parent = LibView }, "slate", 6)
    local CancelBtn = makeButton({ Text = "Cancel", Font = F.Bold, TextSize = 12, Position = UDim2.new(0, 16, 1, -46), Size = UDim2.new(1, -32, 0, 32), Parent = LibView }, "dark", 6)

    -- Status line: a message (Applied / Saved / Failed / Previewing…) or, when empty, list info
    State.LibMsg, State.LibMsgColor, State.LibInfo = "", L.Secondary, ""
    local function refreshLibStatus()
        if State.LibMsg ~= "" then
            LibStatus.Text = State.LibMsg
            LibStatus.TextColor3 = State.LibMsgColor
            LibStatus.Font = F.Medium
        else
            LibStatus.Text = State.LibInfo
            LibStatus.TextColor3 = L.Tertiary
            LibStatus.Font = F.Regular
        end
    end

    local function setLibStatus(text, color)
        State.LibMsg = text or ""
        State.LibMsgColor = color or L.Secondary
        refreshLibStatus()
    end

    -- Bottom area grows when a selection exists ([Preview] [APPLY VISUAL] row)
    local function layoutLib(hasSelection)
        PreviewBtn.Visible = hasSelection
        ApplyBtn.Visible = hasSelection
        LibStatus.Position = hasSelection and UDim2.new(0, 16, 1, -108) or UDim2.new(0, 16, 1, -68)
        LibBox.Size = hasSelection and UDim2.new(1, -32, 1, -192) or UDim2.new(1, -32, 1, -152)
    end

    local function paintLibRow(refs)
        local e = refs.Item
        if not e then return end
        local selected = e.Id == State.PendingId
        local swap = State.View == "replace" and State.SourceId and Swaps[State.SourceId]
        local current = swap and swap.Target == e.Id
        refs.Frame.BackgroundColor3 = selected and L.SelRow or (refs.Hover and L.RowHover or L.Content)
        if refs.Stroke then
            refs.Stroke.Color = selected and L.SelRowBorder or L.RowBorder
            refs.Stroke.Thickness = selected and 3 or 2
        end
        local txt = escapeRich(e.Name)
        if e.Collection then txt = txt .. "  ·  " .. escapeRich(e.Collection) end
        refs.Text.Text = txt
        refs.Text.Font = selected and F.Medium or F.Regular
        local meta = {}
        if current then meta[#meta + 1] = "current" end
        if FailedTargets[e.Id] then meta[#meta + 1] = "unavailable" end
        if e.Category == "Unusual" and State.Category ~= "Unusual" then meta[#meta + 1] = "unusual" end
        if e.HasProps then meta[#meta + 1] = "props" end
        if #e.VariantOrder > 0 and not Core.pickVariant(e, PreferredVariant) then meta[#meta + 1] = "not for your rig" end
        if e.Source == "Saved" then meta[#meta + 1] = "not in game data" end
        if e.CurrentlyPlaying then meta[#meta + 1] = "playing" end
        refs.Meta.Text = table.concat(meta, " · ")
        refs.Meta.TextColor3 = FailedTargets[e.Id] and L.Bad or (current and L.Accent or L.Tertiary)
        local fav = FavoriteIds[e.Id] ~= nil
        refs.Star.Text = fav and "★" or "☆"
        refs.Star.TextColor3 = fav and L.Star or L.Secondary
    end

    local updateLibButtons, previewSelected -- forward
    local lastClickId, lastClickAt = nil, 0

    local function selectLib(e)
        if not e then return end
        local now = os.clock()
        local double = lastClickId == e.Id and now - lastClickAt < 0.35
        lastClickId, lastClickAt = e.Id, now
        State.PendingId = e.Id
        setLibStatus("Selected: " .. e.Name .. (e.Collection and (" · " .. e.Collection) or ""), L.Secondary)
        renderLib(false)
        if double then previewSelected() end
    end

    local LibList = VirtualList(LibBox, {
        Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 1, -8), RowHeight = 30, Gap = 8,
        RowClass = "TextButton", RowStroke = true, RowCorner = 7, EmptyText = "",
        Build = function(row, refs)
            refs.Text = label({ TextSize = 12, TextColor3 = L.RowText, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -150, 1, 0), Parent = row })
            refs.Meta = label({ TextSize = 10, TextColor3 = L.Tertiary, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -140, 0, 0), Size = UDim2.fromOffset(106, 26), Parent = row })
            refs.Star = new("TextButton", {
                Text = "☆", Font = F.Regular, TextSize = 15, BackgroundTransparency = 1, AutoButtonColor = false,
                Position = UDim2.new(1, -30, 0, 0), Size = UDim2.fromOffset(26, 26), TextColor3 = L.Secondary, Parent = row,
            })
            row.MouseEnter:Connect(function()
                refs.Hover = true
                paintLibRow(refs)
            end)
            row.MouseLeave:Connect(function()
                refs.Hover = false
                paintLibRow(refs)
            end)
            row.MouseButton1Click:Connect(function() selectLib(refs.Item) end)
            -- Star toggles favorite only: it never selects, previews or applies
            refs.Star.MouseButton1Click:Connect(function()
                local e = refs.Item
                if e then
                    toggleFavorite(e.Id)
                    paintLibRow(refs)
                end
            end)
        end,
        Bind = function(refs) paintLibRow(refs) end,
    })

    -- ------------------------------------------------------------
    -- View: SETTINGS
    -- ------------------------------------------------------------
    local SettingsView = new("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
        ScrollBarImageColor3 = L.Tertiary, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false, Parent = Content,
    }, {
        new("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20), PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 16) }),
        new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    label({ Text = "Settings", Font = F.Bold, TextSize = 17, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = SettingsView })
    local SettingsGroup = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = L.Content,
        BorderSizePixel = 0, LayoutOrder = 2, Parent = SettingsView,
    }, { corner(8), stroke(L.RowBorder), new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })

    local SwitchSyncs = {}
    local applySetting -- forward

    local function settingRow(order, title, desc)
        local row = new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, LayoutOrder = order, Parent = SettingsGroup })
        label({ Text = title, Font = F.Medium, TextSize = 13, Position = UDim2.fromOffset(14, desc and 7 or 0), Size = UDim2.new(1, -160, 0, desc and 18 or 46), Parent = row })
        if desc then
            label({ Text = desc, TextSize = 10, TextColor3 = L.Tertiary, Position = UDim2.fromOffset(14, 25), Size = UDim2.new(1, -160, 0, 14), Parent = row })
        end
        if order > 1 then
            new("Frame", { Size = UDim2.new(1, -14, 0, 1), Position = UDim2.fromOffset(14, 0), BackgroundColor3 = L.RowBorder, BorderSizePixel = 0, Parent = row })
        end
        return row
    end

    local function toggleRow(order, title, desc, key)
        local row = settingRow(order, title, desc)
        SwitchSyncs[#SwitchSyncs + 1] = makeSwitch(row, UDim2.new(1, -52, 0.5, -11), function() return SETTINGS[key] end, function()
            SETTINGS[key] = not SETTINGS[key]
            applySetting(key)
        end)
    end

    local function setInterval(v)
        v = tonumber(v)
        if v then
            SETTINGS.ScanInterval = math.clamp(math.floor(v * 10 + 0.5) / 10, MIN_INTERVAL, MAX_INTERVAL)
            applySetting("ScanInterval")
        else
            for _, s in ipairs(SwitchSyncs) do s(false) end
        end
    end

    toggleRow(1, "Auto Scan", "Scan the emote wheel automatically", "AutoScanEnabled")
    do
        local row = settingRow(2, "Scan interval", "Seconds between wheel scans (0.5 – 30)")
        local minus = makeButton({ Text = "–", TextSize = 14, Position = UDim2.new(1, -132, 0.5, -12), Size = UDim2.fromOffset(28, 24), Parent = row }, "default")
        local box = makeSearch({ Position = UDim2.new(1, -98, 0.5, -12), Size = UDim2.fromOffset(52, 24), Text = fmtNum(SETTINGS.ScanInterval), TextXAlignment = Enum.TextXAlignment.Center, Parent = row })
        local plus = makeButton({ Text = "+", TextSize = 14, Position = UDim2.new(1, -40, 0.5, -12), Size = UDim2.fromOffset(28, 24), Parent = row }, "default")
        onClick(minus, function() setInterval(SETTINGS.ScanInterval - 0.5) end)
        onClick(plus, function() setInterval(SETTINGS.ScanInterval + 0.5) end)
        box.FocusLost:Connect(function() setInterval(box.Text) end)
        SwitchSyncs[#SwitchSyncs + 1] = function()
            if not box:IsFocused() then box.Text = fmtNum(SETTINGS.ScanInterval) end
        end
    end
    toggleRow(3, "Detect wheel emotes", "Read emotes from the in-game emote wheel", "DetectWheelEmotes")
    toggleRow(4, "Read emote display names", "Use names from the game's item data (else module names)", "ReadItemNames")
    toggleRow(5, "Visual swap engine", "Play replacements when originals are used", "SwapEngineEnabled")
    toggleRow(6, "Move like the replacement", "Copies the replacement's walk speed — the server may end the emote if you move faster than the original allows", "MoveLikeReplacement")
    toggleRow(15, "Keep emoting", "One-shot originals (e.g. Facepalm) end after a few seconds: play them again (any key / click stops)", "KeepEmoting")
    -- Keybind rows: click, then press any key (Esc = cancel, Backspace = no key)
    local function keyRow(order, title, desc, key)
        local row = settingRow(order, title, desc)
        local keyBtn = makeButton({ Text = SETTINGS[key], TextSize = 12, Position = UDim2.new(1, -132, 0.5, -12), Size = UDim2.fromOffset(120, 24), Parent = row }, "default")
        onClick(keyBtn, function()
            if Core.KeyCapture then return end
            keyBtn.Text = "Press a key…"
            Core.KeyCapture = function(name)
                Core.KeyCapture = nil
                if name == "Backspace" and key ~= "HideKey" then name = "None" end
                if name then
                    SETTINGS[key] = name
                    applySetting(key)
                end
                keyBtn.Text = SETTINGS[key]
            end
        end)
        SwitchSyncs[#SwitchSyncs + 1] = function()
            if not Core.KeyCapture then keyBtn.Text = SETTINGS[key] end
        end
    end
    keyRow(7, "Hide / show UI key", "Click, then press any key (Esc = cancel)", "HideKey")
    toggleRow(11, "Hide game GUI", "Hides the game's HUD, wheel, chat and player list (this UI stays)", "HideGameGui")
    keyRow(12, "Hide game GUI key", "Click, then press a key (Backspace = no key)", "HideGameKey")
    do
        -- Catalog accessories: paste an id or catalog link, Add; each one gets a Remove button
        local row = settingRow(13, "Catalog accessory (visual)", "Accessory id or catalog link — only you see it")
        local box = makeSearch({ Position = UDim2.new(1, -212, 0.5, -12), Size = UDim2.fromOffset(140, 24), PlaceholderText = "e.g. 48474313", Parent = row })
        local addBtn = makeButton({ Text = "Add", TextSize = 12, Position = UDim2.new(1, -64, 0.5, -12), Size = UDim2.fromOffset(52, 24), Parent = row }, "primary")
        local listFrame = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
            LayoutOrder = 14, Parent = SettingsGroup,
        }, { new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })
        local function rebuild()
            for _, c in ipairs(listFrame:GetChildren()) do
                if c:IsA("Frame") then c:Destroy() end
            end
            for i, id in ipairs(SETTINGS.Accessories) do
                id = tostring(id)
                local r = new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = i, Parent = listFrame })
                label({
                    Text = string.format("%s  ·  %s  ·  %s", tostring(Core.AccNames[id] or "loading…"), id, tostring(Core.AccStatus[id] or "")),
                    TextSize = 11, TextColor3 = L.Secondary, Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -110, 1, 0), Parent = r,
                })
                local rm = makeButton({ Text = "Remove", TextSize = 11, Position = UDim2.new(1, -76, 0.5, -11), Size = UDim2.fromOffset(64, 22), Parent = r }, "default")
                onClick(rm, function()
                    for j, v in ipairs(SETTINGS.Accessories) do
                        if tostring(v) == id then table.remove(SETTINGS.Accessories, j) break end
                    end
                    applySetting("Accessories")
                end)
            end
        end
        Core.OnAccessoriesChanged = rebuild
        local function add()
            local id = Core.parseAssetId(box.Text)
            if not id then
                notify("Enter a catalog accessory id (numbers) or a catalog link.", "accid")
                return
            end
            for _, v in ipairs(SETTINGS.Accessories) do
                if tostring(v) == id then return end
            end
            table.insert(SETTINGS.Accessories, id)
            box.Text = ""
            applySetting("Accessories")
        end
        onClick(addBtn, add)
        box.FocusLost:Connect(function(enter) if enter then add() end end)
        rebuild()
    end

    local RefreshRow = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 3, Parent = SettingsView })
    local RefreshBtn = makeButton({ Text = "Refresh Library", TextSize = 12, Size = UDim2.fromOffset(130, 30), Parent = RefreshRow }, "default", 7)
    -- Diagnostics (panel + copy button + save-file info) exist only in the developer build
    local CopyDiagBtn = makeButton({ Text = "Copy Diagnostics", TextSize = 12, Position = UDim2.fromOffset(138, 0), Size = UDim2.fromOffset(130, 30), Visible = DEV_BUILD, Parent = RefreshRow }, "default", 7)
    local infoX = DEV_BUILD and 276 or 138
    label({
        Text = "Refresh rescans the game's emote data (swaps and favorites are kept).", TextSize = 10,
        TextColor3 = L.Tertiary, TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
        Position = UDim2.fromOffset(infoX, 0), Size = UDim2.new(1, -infoX, 1, 0), Parent = RefreshRow,
    })
    label({ Text = "DIAGNOSTICS", Font = F.Bold, TextSize = 10, TextColor3 = L.Tertiary, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 4, Visible = DEV_BUILD, Parent = SettingsView })
    local DiagLbl = label({
        Text = "", Font = F.Mono, TextSize = 11, TextColor3 = L.Secondary, TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top, Visible = DEV_BUILD,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5, Parent = SettingsView,
    })
    label({
        Visible = DEV_BUILD,
        Text = (type(writefile) == "function")
            and ("Swaps → " .. CONFIG_FILE .. "   ·   Favorites → " .. FAV_FILE)
            or "This executor has no writefile: swaps and favorites last for this session only.",
        TextSize = 10, TextColor3 = L.Tertiary, TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
        Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 6, Parent = SettingsView,
    })

    applySetting = function(key)
        local v = SETTINGS[key]
        if key == "AutoScanEnabled" or key == "ScanInterval" then
            if SETTINGS.AutoScanEnabled then EmoteWheelScanner.Start() else EmoteWheelScanner.Stop() end
        elseif key == "DetectWheelEmotes" then
            if not v then
                for _, e in pairs(Detected) do e.InWheel = false end
            else
                EmoteWheelScanner.Discover()
                pcall(EmoteWheelScanner.Tick)
            end
        elseif key == "DetectCurrentlyPlaying" then
            if v then
                for k in pairs(SeenTracks) do SeenTracks[k] = nil end
                pcall(EmoteWheelScanner.Tick)
            else
                local list = {}
                for t in pairs(TrackState) do list[#list + 1] = t end
                for _, t in ipairs(list) do trackEnded(t) end
            end
        elseif key == "ReadItemNames" then
            task.spawn(fullLibraryScan, true)
        elseif key == "MoveLikeReplacement" then
            Core.patchAll() -- re-patch: sound always, movement only when on
        elseif key == "Headless" or key == "KorbloxRight" or key == "KorbloxLeft" then
            Core.applyBody()
        elseif key == "Accessories" then
            Core.applyAccessories()
            if Core.OnAccessoriesChanged then Core.OnAccessoriesChanged() end
        elseif key == "HideGameGui" then
            Core.setGameGuiHidden(v)
        elseif key == "SwapEngineEnabled" then
            if v then
                Core.patchAll()
                reapplyPlaying()
            else
                stopAllReplacements(true)
                Core.unpatchAll()
            end
        end
        saveConfig()
        for _, s in ipairs(SwitchSyncs) do s(true) end
        scheduleUI(true)
    end

    local function diagnosticsText()
        local unusual, saved, props = 0, 0, 0
        for _, e in pairs(Library) do
            if e.Category == "Unusual" then unusual += 1 end
            if e.Source == "Saved" then saved += 1 end
            if e.HasProps then props += 1 end
        end
        local unresolved = 0
        for _, d in pairs(Detected) do
            if d.Unresolved then unresolved += 1 end
        end
        local rig = LocalIsRig and ("Workspace.Rigs." .. LocalPlayer.Name) or (LocalAnimator and "LocalPlayer.Character (no rig found)" or "not found yet")
        return table.concat({
            string.format("Last scan     %s · %s · %.2fs · %d instances under ReplicatedStorage.Items%s",
                Diag.Deep and "deep" or "standard", Diag.When, Diag.Duration, Diag.Scanned, Diag.ItemsRoot and "" or " (Items folder NOT found)"),
            string.format("Emote items   %d (%d with props, %d unusual) · %d collections · %d names read", Diag.Items, props, unusual, Diag.Collections, Diag.NamesRead),
            string.format("Animations    %d emote animation IDs indexed · rig variant: %s", AllAnimsCount, tostring(PreferredVariant or "unknown (play an emote)")),
            string.format("Local rig     %s · style %s", rig, Core.rigStyle()),
            "Last swap     " .. tostring(Diag.LastSwap or "none yet"),
            "Last props    " .. tostring(Diag.LastProps or "none yet") .. string.format("  · learned joints %d", countTable(Core.PropJoints)),
            string.format("Movement      %s · %s", SETTINGS.MoveLikeReplacement and "ON" or "off", tostring(Diag.Movement or "no change yet")),
            string.format("Sound         %s", tostring(Diag.Sound or "no change yet")),
            string.format("Keep emoting  %s · %s", SETTINGS.KeepEmoting and "ON" or "off", tostring(Diag.Reemote or "not needed yet")),
            string.format("Body          %s · hide key %s", tostring(Diag.Body or "off"), tostring(SETTINGS.HideKey)),
            string.format("Accessories   %s", tostring(Diag.Accessories or "none")),
            string.format("Head effects  %s", tostring(Diag.HeadFollow or "on your head")),
            string.format("Catalog       %s", tostring(Core.Catalog.Status ~= "" and Core.Catalog.Status or "not searched yet")),
            string.format("Game GUI      %s · key %s", SETTINGS.HideGameGui and "hidden" or "shown", tostring(SETTINGS.HideGameKey)),
            string.format("Unusual       %d cosmetics · %s", Diag.Cosmetics or 0, tostring(Diag.Unusual or (Core.WornUnusual and ("saved: " .. Core.WornUnusual) or "none"))),
            string.format("Wheel         %d UI roots · %d slots resolved · %d unresolved names", EmoteWheelScanner.RootCount, EmoteWheelScanner.Slots, unresolved),
            string.format("Swaps         %d saved · %d replacing now · engine %s · %d old swaps not matched", countTable(Swaps), countTable(ActiveReplacements), SETTINGS.SwapEngineEnabled and "on" or "off", countTable(LegacySwaps)),
            string.format("Favorites     %d (%d not in current game data)", countTable(FavoriteIds), saved),
            "Not read      server-only data, other players' inventories",
        }, "\n")
    end

    -- ============================================================
    -- Navigation (Back / Forward history)
    -- ============================================================
    local History, HistIndex = {}, 0

    local function setSearchText(box, text)
        if box.Text ~= text then box.Text = text end
    end

    local function syncSearchBoxes()
        if State.View == "main" then
            ToolbarSearch.PlaceholderText = "Search your emotes"
            setSearchText(ToolbarSearch, State.Queries.main)
        elseif State.View == "replace" or State.View == "pick" then
            ToolbarSearch.PlaceholderText = "Search library"
            setSearchText(ToolbarSearch, State.Queries.lib)
            setSearchText(LibSearch, State.Queries.lib)
        else
            ToolbarSearch.PlaceholderText = "Search"
            setSearchText(ToolbarSearch, "")
        end
    end

    local function showView(entry, fresh)
        stopPreview()
        State.View = entry.View
        State.SourceId, State.SourceName, State.PickForKey = entry.SourceId, entry.SourceName, entry.PickForKey
        State.Busy = false
        if entry.View == "replace" or entry.View == "pick" then
            if fresh then State.Queries.lib = entry.Query or "" end
            local swap = entry.View == "replace" and State.SourceId and Swaps[State.SourceId]
            State.PendingId = swap and swap.Target or nil
            State.LibKey, State.LibFilterKey = nil, nil
            setLibStatus("", L.Secondary)
        end
        MainView.Visible = entry.View == "main"
        LibView.Visible = entry.View == "replace" or entry.View == "pick"
        SettingsView.Visible = entry.View == "settings"
        local active = (entry.View == "main" and MainView) or (entry.View == "settings" and SettingsView) or LibView
        active.Position = UDim2.fromOffset(10, 0)
        tween(active, 0.16, { Position = UDim2.fromOffset(0, 0) })
        syncSearchBoxes()
        local ok, err = pcall(renderAll)
        if not ok then warn("[SonderVade] UI error: " .. tostring(err)) end
    end

    navigate = function(view, params)
        params = params or {}
        for i = #History, HistIndex + 1, -1 do History[i] = nil end
        History[#History + 1] = {
            View = view, SourceId = params.SourceId, SourceName = params.SourceName,
            PickForKey = params.PickForKey, Query = params.Query,
        }
        if #History > 30 then table.remove(History, 1) end
        HistIndex = #History
        showView(History[HistIndex], true)
    end

    goBack = function()
        if HistIndex > 1 then
            HistIndex -= 1
            showView(History[HistIndex], false)
        end
    end

    goForward = function()
        if HistIndex < #History then
            HistIndex += 1
            showView(History[HistIndex], false)
        end
    end

    -- ============================================================
    -- Rendering
    -- ============================================================
    local function buildDetectedItems(query, category)
        local q = trim(query):lower()
        local items, total, playing = {}, 0, 0
        if category == "Avatar" then
            local list = Core.bodyItems()
            return list, #list, 0
        end
        if category == "Catalog" then
            -- Roblox catalog accessories: the search box searches the catalog itself
            Core.catalogSearch(query, false, function() if Alive then scheduleUI(true) end end)
            local list = Core.catalogItems()
            return list, #list, 0
        end
        if category == "Unusual" then
            -- Unusual = the game's Unusual cosmetics (visual wear), not emotes
            for _, c in pairs(Core.Cosmetics) do
                total += 1
                if q == "" or c.Lower:find(q, 1, true) or (c.Collection and c.Collection:lower():find(q, 1, true)) then
                    items[#items + 1] = c
                end
            end
            table.sort(items, function(a, b)
                -- favorites always on top (like the emote library), then the one you wear, then A–Z
                local fa, fb = Core.FavUnusual[a.Key] == true, Core.FavUnusual[b.Key] == true
                if fa ~= fb then return fa end
                local wa, wb = Core.WornUnusual == a.Key, Core.WornUnusual == b.Key
                if wa ~= wb then return wa end
                if a.Lower ~= b.Lower then return a.Lower < b.Lower end
                return a.Key < b.Key
            end)
            return items, total, 0
        end
        for _, e in pairs(Detected) do
            local visible
            if e.Unresolved then
                visible = e.InWheel
            else
                visible = e.IsPlaying or e.InWheel or e.IsLocal or e.Manual or Swaps[e.Id] ~= nil
            end
            if visible and category == "Unusual" then
                local lib = e.Id and Library[e.Id]
                visible = lib ~= nil and lib.Category == "Unusual"
            elseif visible and category == "Favorites" then
                visible = e.Id ~= nil and FavoriteIds[e.Id] ~= nil
            end
            if visible then
                total += 1
                if e.IsPlaying then playing += 1 end
                if q == "" or e.Name:lower():find(q, 1, true) or (e.Id and e.Id:find(q, 1, true)) then
                    items[#items + 1] = e
                end
            end
        end
        local function rank(e)
            if e.Unresolved then return 4 end
            if e.IsPlaying then return 0 end
            if e.InWheel then return 1 end
            if e.IsLocal or e.Manual or (e.Id and Swaps[e.Id]) then return 2 end
            return 3
        end
        table.sort(items, function(a, b)
            local ra, rb = rank(a), rank(b)
            if ra ~= rb then return ra < rb end
            local an, bn = a.Name:lower(), b.Name:lower()
            if an ~= bn then return an < bn end
            return a.Key < b.Key
        end)
        if category == "Favorites" then
            -- starred Unusual cosmetics are favorites too (listed after the emotes)
            local cos = {}
            for key in pairs(Core.FavUnusual) do
                local c = Core.Cosmetics[key]
                if c then
                    total += 1
                    if q == "" or c.Lower:find(q, 1, true) then cos[#cos + 1] = c end
                end
            end
            table.sort(cos, function(a, b) return a.Lower < b.Lower end)
            for _, c in ipairs(cos) do items[#items + 1] = c end
        end
        return items, total, playing
    end

    local function buildLibraryItems()
        local q = trim(State.Queries.lib):lower()
        local cat = State.Category
        local favOnly = State.FavOnly or cat == "Favorites"
        local out = {}
        for _, e in ipairs(getLibrarySorted()) do
            local ok = State.View == "pick" or e.Id ~= State.SourceId
            if ok and favOnly and not FavoriteIds[e.Id] then ok = false end
            if ok and cat == "Unusual" and e.Category ~= "Unusual" then ok = false end
            if ok and cat == "Emotes" and e.Category == "Unusual" then ok = false end
            if ok and q ~= "" and not e.Search:find(q, 1, true) then ok = false end
            if ok then out[#out + 1] = e end
        end
        return out
    end

    local function renderMain()
        local items, total, playing = buildDetectedItems(State.Queries.main, State.Category)
        MainList.SetItems(items)
        MainTitle.Text = (State.Category == "Emotes" and "Your Emotes")
            or (State.Category == "Unusual" and "Unusual Cosmetics")
            or (State.Category == "Catalog" and "Catalog Accessories")
            or (State.Category == "Avatar" and "Avatar · Headless & Korblox") or "Your Emotes · Favorites"
        local isCatalog = State.Category == "Catalog"
        local isAvatar = State.Category == "Avatar"
        if State.View == "main" then
            ToolbarSearch.PlaceholderText = isCatalog and "Search the catalog or paste an accessory ID (e.g. 10159600649)"
                or "Search your emotes"
        end
        ChooseBtn.Visible = not isAvatar
        ChooseBtn.Text = isCatalog and (Core.Catalog.Loading and "Searching…" or (Core.Catalog.More and "Load More Results" or "No More Results"))
            or "Choose Original Emote From Library"
        if isAvatar then
            local worn = 0
            for _, b in ipairs(Core.BODY_ITEMS) do
                if SETTINGS[b.Setting] then worn += 1 end
            end
            MainCount.Text = worn .. " worn  ·  visual only"
            MainList.SetEmptyText("")
        elseif isCatalog then
            MainCount.Text = #SETTINGS.Accessories .. " worn  ·  " .. tostring(Core.Catalog.Status)
            MainList.SetEmptyText(Core.Catalog.Loading and "Searching the catalog…"
                or ("No accessories found (" .. tostring(Core.Catalog.Status) .. ").\nType a name in the search box (e.g. \"wings\"), or paste an accessory ID / catalog link."))
        elseif State.Category == "Unusual" then
            local worn = Core.WornUnusual and Core.Cosmetics[Core.WornUnusual]
            MainCount.Text = total .. " cosmetics" .. (worn and ("  ·  wearing " .. worn.Name) or "")
        else
            MainCount.Text = total .. " detected" .. (playing > 0 and ("  ·  " .. playing .. " playing") or "")
        end
        if isCatalog or isAvatar then
            -- empty text already set above
        elseif total > 0 and #items == 0 then
            MainList.SetEmptyText("Nothing matches your search.")
        elseif State.Category == "Unusual" then
            MainList.SetEmptyText("No Unusual cosmetics found in the game data (Settings → Refresh Library).")
        elseif State.Category == "Favorites" then
            MainList.SetEmptyText("None of your detected emotes are favorites yet.\nStar emotes in the library to add them.")
        else
            MainList.SetEmptyText("No emotes detected yet.\nOpen your emote wheel or play an emote — or use the button below to choose one from the library.")
        end

        local scanning = EmoteWheelScanner.IsRunning()
        local wheel
        if not SETTINGS.DetectWheelEmotes then
            wheel = "wheel scan off"
        elseif EmoteWheelScanner.RootCount > 0 then
            wheel = "wheel UI found"
        else
            wheel = "wheel UI not found yet"
        end
        local swaps = countTable(Swaps)
        StatusLine.Text = string.format(
            'Auto Scan: <font color="%s"><b>%s</b></font>   ·   every %ss   ·   %s   ·   %d active swap%s%s',
            hex(scanning and L.Good or L.Bad), scanning and "ON" or "OFF", fmtNum(SETTINGS.ScanInterval), wheel,
            swaps, swaps == 1 and "" or "s", SETTINGS.SwapEngineEnabled and "" or "   ·   engine off")
    end

    updateLibButtons = function()
        local pick = State.View == "pick"
        local has = State.PendingId ~= nil
        local swap = (not pick) and State.SourceId and Swaps[State.SourceId] or nil
        local same = swap ~= nil and has and swap.Target == State.PendingId
        if State.Busy then
            ApplyBtn.Text = "CHECKING…"
        elseif pick then
            ApplyBtn.Text = "USE AS ORIGINAL"
        elseif same then
            ApplyBtn.Text = "APPLIED ✓"
        else
            ApplyBtn.Text = "APPLY VISUAL"
        end
        setDisabled(ApplyBtn, State.Busy or not has or same)
        setDisabled(PreviewBtn, State.Busy or not has)
        layoutLib(has or State.Busy)
        LibRemoveBtn.Visible = swap ~= nil
        local favActive = State.FavOnly or State.Category == "Favorites"
        FavFilterBtn.Text = favActive and "★ Favorites" or "☆ Favorites"
        applyStyle(FavFilterBtn, favActive and "grayOn" or "gray")
    end

    local function updateLibHeader()
        if State.View == "pick" then
            LibTitle.Text = "Choose the original emote"
        else
            LibTitle.Text = "Show instead of " .. tostring(State.SourceName or "?")
        end
    end

    renderLib = function(force)
        local filterKey = table.concat({ State.View, State.Category, tostring(State.FavOnly), State.Queries.lib, tostring(State.SourceId) }, "|")
        local key = filterKey .. "|" .. LibraryVersion .. "|" .. FavVersion
        if force or key ~= State.LibKey then
            local items = buildLibraryItems()
            local resetScroll = filterKey ~= State.LibFilterKey
            State.LibKey, State.LibFilterKey = key, filterKey
            LibList.SetItems(items)
            if resetScroll then LibList.ScrollToTop() end
            local catLabel = (State.FavOnly or State.Category == "Favorites") and "Favorites"
                or (State.Category == "Unusual" and "Unusual" or "Emotes")
            local count = (State.Category == "Unusual" and LibCounts.Unusual) or (State.Category == "Emotes" and LibCounts.Emotes) or countTable(FavoriteIds)
            local info = (LibraryScanning and "Scanning library…  ·  " or "")
                .. string.format("Showing %d of %d  ·  %s", #items, count, catLabel)
            if State.View == "replace" then
                local swap = State.SourceId and Swaps[State.SourceId]
                info = info .. "  ·  " .. (swap and ("currently showing " .. tostring(swap.TargetName or swap.Target)) or "no visual applied yet")
            else
                local old = State.PickForKey and Detected[State.PickForKey]
                info = info .. "  ·  " .. (old and ('wheel shows "' .. old.Name .. '" without an ID') or "pick the emote you play in-game")
            end
            State.LibInfo = info
            if LibraryScanning and #items == 0 then
                LibList.SetEmptyText("Scanning library…")
            elseif LibraryCount == 0 then
                LibList.SetEmptyText("No emotes discovered yet.\nOpen your emote wheel, play an emote, or use Settings → Refresh Library.")
            elseif (State.FavOnly or State.Category == "Favorites") and next(FavoriteIds) == nil then
                LibList.SetEmptyText("No favorites yet — click ☆ next to any emote.")
            elseif State.Category == "Unusual" and LibCounts.Unusual == 0 then
                LibList.SetEmptyText("The game's accessible data marks no emotes as Unusual.")
            else
                LibList.SetEmptyText("No emotes match your search.")
            end
        else
            LibList.Rebind()
        end
        updateLibHeader()
        updateLibButtons()
        refreshLibStatus()
    end

    local function renderSettings()
        for _, s in ipairs(SwitchSyncs) do s(false) end
        if DEV_BUILD then DiagLbl.Text = diagnosticsText() end
        RefreshBtn.Text = LibraryScanning and "Refreshing…" or "Refresh Library"
        setDisabled(RefreshBtn, LibraryScanning)
    end

    renderAll = function()
        getLibrarySorted()
        local favCount = countTable(FavoriteIds) + countTable(Core.FavUnusual)
        for key, it in pairs(SidebarItems) do
            local selected = (key == "Settings" and State.View == "settings") or (key == State.Category and State.View ~= "settings")
            it.Button:SetAttribute("Selected", selected)
            it.Button.BackgroundColor3 = L.SidebarSel
            it.Button.BackgroundTransparency = selected and 0 or 1
            it.Stroke.Enabled = selected
            it.Shadow.Visible = selected
        end
        SidebarItems.Emotes.Count.Text = tostring(LibCounts.Emotes)
        local cosmeticCount = countTable(Core.Cosmetics)
        SidebarItems.Unusual.Count.Text = cosmeticCount > 0 and tostring(cosmeticCount) or ""
        SidebarItems.Favorites.Count.Text = favCount > 0 and tostring(favCount) or ""
        SidebarItems.Catalog.Count.Text = #SETTINGS.Accessories > 0 and tostring(#SETTINGS.Accessories) or ""
        local bodyOn = (SETTINGS.Headless and 1 or 0) + (SETTINGS.KorbloxRight and 1 or 0) + (SETTINGS.KorbloxLeft and 1 or 0)
        SidebarItems.Avatar.Count.Text = bodyOn > 0 and tostring(bodyOn) or ""
        setDisabled(BackBtn, HistIndex <= 1)
        setDisabled(FwdBtn, HistIndex >= #History)

        if State.View == "main" then
            renderMain()
        elseif State.View == "replace" or State.View == "pick" then
            renderLib(false)
        elseif State.View == "settings" then
            renderSettings()
        end
    end

    -- ============================================================
    -- Actions
    -- ============================================================
    previewSelected = function()
        local id = State.PendingId
        if not id then return end
        local e = Library[id]
        local name = e and e.Name or id
        if not LocalAnimator then
            setLibStatus("Character not ready — preview unavailable", L.Warn)
            return
        end
        local started = previewAnimation(id, function()
            if State.PendingId == id then setLibStatus("Failed — " .. name .. " is unavailable", L.Bad) end
        end)
        if started then
            setLibStatus("Previewing " .. name .. " for 5s — not applied", L.Accent)
        else
            setLibStatus("Failed — animation unavailable", L.Bad)
        end
    end

    local function applyVisual()
        if State.Busy then return end
        local src, srcName, tgtId = State.SourceId, State.SourceName, State.PendingId
        if not src or not Library[src] or #Library[src].VariantOrder == 0 then
            setLibStatus("Failed — the original emote was not found in the game's emote data", L.Bad)
            return
        end
        if not tgtId or not Library[tgtId] then
            setLibStatus("Select a replacement emote first", L.Warn)
            return
        end
        if #Library[tgtId].VariantOrder == 0 then
            setLibStatus("Failed — this saved favorite is not in the current game data", L.Bad)
            return
        end
        if not Core.pickVariant(Library[tgtId], PreferredVariant) then
            setLibStatus("Failed — " .. Library[tgtId].Name .. " has no animation for your rig type (" .. Core.rigStyle() .. ")", L.Bad)
            return
        end
        if tgtId == src then
            setLibStatus("The replacement must be a different emote", L.Warn)
            return
        end
        local tgt = Library[tgtId]
        local tgtName = tgt and tgt.Name or tgtId
        State.Busy = true
        stopPreview()
        FailedTargets[tgtId] = nil
        setLibStatus("Checking that " .. tgtName .. " can be loaded…", L.Secondary)
        updateLibButtons()

        task.spawn(function()
            local result = checkLoadable(tgtId, 6)
            if not Alive then return end
            State.Busy = false
            local stillHere = State.View == "replace" and State.SourceId == src
            if result == "failed" then
                FailedTargets[tgtId] = "preload failed"
                if stillHere then
                    setLibStatus("Failed — animation unavailable", L.Bad)
                    renderLib(true)
                else
                    showBanner("Failed — animation unavailable   ·   " .. tgtName, L.Bad)
                end
                return
            end
            setSwap(src, srcName, tgtId, tgtName)
            local msg, color
            if not SETTINGS.SwapEngineEnabled then
                msg, color = "Saved — the visual swap engine is off (Settings)", L.Warn
            elseif hasActiveReplacement(src) then
                msg, color = "Applied — replacement is playing", L.Good
            elseif isSourcePlaying(src) then
                msg, color = "Failed — animation unavailable", L.Bad
            else
                msg, color = "Saved — waiting for original emote", L.Accent
            end
            if color == L.Bad and stillHere then
                setLibStatus(msg, color)
                renderLib(true)
            else
                if stillHere then navigate("main") end
                showBanner(msg .. "   ·   " .. tostring(srcName) .. " → " .. tgtName, color)
                scheduleUI(true)
            end
        end)
    end

    local function useAsOriginal()
        local id = State.PendingId
        local e = id and Library[id]
        if not e then return end
        local d = ensureDetected(id, e.Name)
        d.IsLocal = true
        d.Manual = true
        if State.PickForKey then
            local old = Detected[State.PickForKey]
            if old and old.Unresolved then
                Aliases[normName(old.Name)] = id
                d.InWheel = d.InWheel or old.InWheel
                Detected[State.PickForKey] = nil
                saveConfig()
            end
        end
        navigate("replace", { SourceId = id, SourceName = d.Name })
    end

    onSwapFailed = function(sourceId, targetId)
        local s = Swaps[sourceId]
        local text = "Failed — animation unavailable"
        if s then text = text .. "   ·   " .. tostring(s.SourceName) .. " → " .. tostring(s.TargetName or targetId) end
        if State.View == "replace" and State.SourceId == sourceId then
            setLibStatus("Failed — animation unavailable", L.Bad)
        end
        showBanner(text, L.Bad)
    end

    -- Wiring
    onClick(CloseLight, function() if API then API.Destroy() end end)

    local function applyWindowSize()
        local size = State.Zoomed and ZOOM_SIZE or NORMAL_SIZE
        local cam = workspace.CurrentCamera
        if cam then
            local vp = cam.ViewportSize
            size = Vector2.new(math.min(size.X, math.max(480, vp.X - 40)), math.min(size.Y, math.max(320, vp.Y - 40)))
        end
        -- minimized: only a small box with the three traffic lights
        local w = State.Minimized and 66 or size.X
        local h = State.Minimized and TITLE_H or size.Y
        tween(Holder, 0.18, { Size = UDim2.fromOffset(w, h) })
        Content.Visible = not State.Minimized
        TitleLbl.Visible = not State.Minimized
        ToolbarSearch.Visible = not State.Minimized
        Sidebar.Visible = not State.Minimized
        SidebarLine.Visible = not State.Minimized
    end

    onClick(MinLight, function()
        State.Minimized = not State.Minimized
        applyWindowSize()
    end)
    onClick(ZoomLight, function()
        State.Zoomed = not State.Zoomed
        State.Minimized = false
        UiState.Zoomed = State.Zoomed and 1 or 0
        applyWindowSize()
        saveConfig()
    end)
    onClick(BackBtn, function() goBack() end)
    onClick(FwdBtn, function() goForward() end)

    for key, it in pairs(SidebarItems) do
        it.Button.MouseButton1Click:Connect(function()
            if key == "Settings" then
                if State.View ~= "settings" then navigate("settings") end
                return
            end
            State.Category = key
            if key == "Favorites" then State.FavOnly = false end
            if State.View == "settings" then
                navigate("main")
            else
                scheduleUI(true)
            end
        end)
    end

    do
        local libToken = 0
        local function libQueryChanged(text)
            if text == State.Queries.lib then return end
            State.Queries.lib = text
            libToken += 1
            local my = libToken
            task.delay(0.06, function()
                if my == libToken and Alive and (State.View == "replace" or State.View == "pick") then renderLib(false) end
            end)
        end
        ToolbarSearch:GetPropertyChangedSignal("Text"):Connect(function()
            local text = ToolbarSearch.Text
            if State.View == "main" then
                if text ~= State.Queries.main then
                    State.Queries.main = text
                    scheduleUI(true)
                end
            elseif State.View == "replace" or State.View == "pick" then
                setSearchText(LibSearch, text)
                libQueryChanged(text)
            elseif text ~= "" then
                State.Queries.main = text
                navigate("main")
            end
        end)
        LibSearch:GetPropertyChangedSignal("Text"):Connect(function()
            local text = LibSearch.Text
            if State.View == "replace" or State.View == "pick" then
                setSearchText(ToolbarSearch, text)
                libQueryChanged(text)
            end
        end)
    end

    onClick(FavFilterBtn, function()
        if State.Category == "Favorites" then
            State.Category = "Emotes"
            State.FavOnly = false
        else
            State.FavOnly = not State.FavOnly
        end
        renderAll()
    end)
    onClick(PreviewBtn, function() previewSelected() end)
    onClick(ApplyBtn, function()
        if State.View == "pick" then useAsOriginal() else applyVisual() end
    end)
    onClick(CancelBtn, function()
        stopPreview()
        if HistIndex > 1 then goBack() else navigate("main") end
    end)
    onClick(LibRemoveBtn, function()
        local src = State.SourceId
        if src and Swaps[src] then
            removeSwap(src)
            State.PendingId = nil
            setLibStatus("Removed — " .. tostring(State.SourceName) .. " plays its original animation again", L.Secondary)
            renderLib(true)
        end
    end)
    onClick(ChooseBtn, function()
        if State.Category == "Catalog" then
            if Core.Catalog.More and not Core.Catalog.Loading then
                Core.catalogSearch(State.Queries.main, true, function() if Alive then scheduleUI(true) end end)
            end
            return
        end
        navigate("pick")
    end)
    StatusLine.MouseButton1Click:Connect(function()
        SETTINGS.AutoScanEnabled = not SETTINGS.AutoScanEnabled
        applySetting("AutoScanEnabled")
    end)
    onClick(CopyDiagBtn, function()
        local text = "SonderVade v" .. VERSION .. "\n" .. diagnosticsText()
        if type(setclipboard) == "function" and pcall(setclipboard, text) then
            notify("Diagnostics copied to clipboard.")
        else
            notify("This executor has no setclipboard — please screenshot the Diagnostics panel.")
        end
    end)
    onClick(RefreshBtn, function()
        if LibraryScanning then return end
        task.spawn(function()
            fullLibraryScan(true)
            if not Alive then return end
            EmoteWheelScanner.Discover()
            pcall(EmoteWheelScanner.Tick)
            notify(string.format("Library refreshed: %d emotes · %d animation IDs", LibraryCount, AllAnimsCount))
            scheduleUI(true)
        end)
        scheduleUI(true)
    end)

    -- Drag by the toolbar (not by its buttons / search field)
    do
        local dragging, dragStart, startPos
        local interactive = { ToolbarSearch, BackBtn, FwdBtn, CloseLight, MinLight, ZoomLight }
        local function over(gui, pos)
            local p, s = gui.AbsolutePosition, gui.AbsoluteSize
            return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
        end
        local function begin(input)
            if dragging then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
            local pos = Vector2.new(input.Position.X, input.Position.Y)
            for _, g in ipairs(interactive) do
                if over(g, pos) then return end
            end
            dragging, dragStart, startPos = true, input.Position, Holder.Position
        end
        Toolbar.InputBegan:Connect(begin)
        TitleLbl.InputBegan:Connect(begin)
        bind(UserInputService.InputChanged, function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                Holder.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
        bind(UserInputService.InputEnded, function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                dragging = false
                local p = Holder.Position
                UiState.XS, UiState.XO, UiState.YS, UiState.YO = p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset
                saveConfig()
            end
        end)
    end

    bind(UserInputService.InputBegan, function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if Core.KeyCapture then
            -- choosing a new hide key
            local cb = Core.KeyCapture
            if input.KeyCode == Enum.KeyCode.Escape then cb(nil) else cb(input.KeyCode.Name) end
            return
        end
        local okK, kc = pcall(function() return Enum.KeyCode[SETTINGS.HideKey] end)
        local hideKey = (okK and kc) and SETTINGS.HideKey or TOGGLE_KEY.Name
        -- Evade binds many keys itself (so "processed" is true for them): only skip while typing in a text box
        local typing = UserInputService:GetFocusedTextBox() ~= nil
        local _ = processed
        if typing then return end
        if input.KeyCode.Name == hideKey then
            Gui.Enabled = not Gui.Enabled
        elseif SETTINGS.HideGameKey ~= "None" and input.KeyCode.Name == SETTINGS.HideGameKey then
            SETTINGS.HideGameGui = not SETTINGS.HideGameGui
            applySetting("HideGameGui")
        end
    end)

    -- ============================================================
    -- Cleanup
    -- ============================================================
    local function destroy()
        if not Alive then return end
        Alive = false
        EmoteWheelScanner.Stop()
        pcall(EmoteWheelScanner.RestoreWheel) -- wheel names / previews back to the originals
        stopAllReplacements(true)
        stopPreview()
        Core.unpatchAll()      -- give the emotes their original movement back
        Core.removeUnusual()   -- take the visual Unusual off
        Core.removeBody()      -- Headless / Korblox off
        Core.removeAccessories()
        Core.setGameGuiHidden(false)
        if Core.HeadAnchor then pcall(function() Core.HeadAnchor:Destroy() end) end

        local states = {}
        for t in pairs(TrackState) do states[#states + 1] = t end
        for _, t in ipairs(states) do trackEnded(t) end

        local chars = {}
        for char in pairs(CharMaids) do chars[#chars + 1] = char end
        for _, char in ipairs(chars) do cleanupCharacter(char) end

        for plr, conns in pairs(PlayerConns) do
            for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
            PlayerConns[plr] = nil
        end
        for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
        table.clear(Connections)

        for _, cache in pairs(TrackCache) do
            for _, t in pairs(cache) do
                pcall(function() t:Stop(0) end)
                pcall(function() t:Destroy() end)
            end
        end

        if Gui then pcall(function() Gui:Destroy() end) end
        if genv.SonderVade == API then genv.SonderVade = nil end
    end

    Gui.AncestryChanged:Connect(function(_, parent)
        if parent == nil then destroy() end
    end)

    API = {
        Version = VERSION,
        Destroy = destroy,
        Refresh = function() task.spawn(fullLibraryScan, true) end,
        Swaps = Swaps,
        Library = Library,
        AllAnimations = AllAnims,
        Detected = Detected,
        Favorites = FavoriteIds,
        Settings = SETTINGS,
        Scanner = EmoteWheelScanner,
        SetSwap = setSwap,
        RemoveSwap = removeSwap,
    }
    genv.SonderVade = API

    -- ============================================================
    -- Start
    -- ============================================================
    -- Saved swaps appear in "Your Emotes" even before they are seen again
    for src, info in pairs(Swaps) do
        local d = ensureDetected(src, info.SourceName)
        d.FromSwap = true
    end

    if State.Zoomed then applyWindowSize() end
    navigate("main")                  -- restore UI
    watchRoots()                      -- event-driven library updates
    fullLibraryScan(false)            -- 2. library cache (standard scan)
    if Alive then
        EmoteWheelScanner.Init()      -- 3. wheel scanner
        hookRigs()                    -- 4. Evade visual rigs (Workspace.Rigs.<Player>)
        hookPlayer(LocalPlayer)       --    fallback: the local Character
        bind(Players.PlayerRemoving, unhookPlayer)
        scheduleUI(true)              -- 5. UI state
        EmoteWheelScanner.Start()     -- 6. auto-scan loop
        if SETTINGS.HideGameGui then Core.setGameGuiHidden(true) end
        bind(UserInputService.InputBegan, function(input) Core.noteInput(input) end)
        task.spawn(function()
            while Alive do
                pcall(Core.headFollowStep)
                task.wait(0.15)
            end
        end)
        notify(string.format("v%s loaded · %d emotes · %d swaps · %d favorites", VERSION, LibraryCount, countTable(Swaps), countTable(FavoriteIds)))
    end
end

runUI()
