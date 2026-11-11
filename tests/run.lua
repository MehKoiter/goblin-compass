-- Goblin Compass logic tests, run outside the game against a stand-in WoW API.
--
--   lua5.1 tests/run.lua        (from the repository root)
--
-- This checks the addon's own logic: on/off, Automatic / Manual, route choice by
-- skill, the quick menu, the route recorder. It can't check anything visual
-- (textures, layout, the arrow's direction): test those in game, see docs/releasing.md.

---------------------------------------------------------------------------
-- Stand-in WoW API: any unknown global or frame method is a harmless no-op
---------------------------------------------------------------------------
local magic
local magicMT = {}
magicMT.__index = function() return magic end
magicMT.__call = function() return magic end
magic = setmetatable({}, magicMT)

local frames = {}
CreateFrame = function(kind, name)
  local f = setmetatable({ scripts = {} }, { __index = function() return function() return magic end end })
  f.SetScript = function(self, n, fn) self.scripts[n] = fn end
  f.GetWidth = function() return 140 end
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end

local realPrint, write = print, io.write
setmetatable(_G, { __index = function() return magic end })
-- APIs the addon feature-tests with "if X then": false means "not available here"
GetTrackingTexture, GetSpellTexture, C_Spell, LibStub, Settings, InterfaceOptions_AddCategory = false, false, false, false, false, false

GoblinCompassDB = {}
Minimap = { GetWidth = function() return 140 end }
local printed = {}
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  printed[#printed + 1] = table.concat(parts, " ")
end
wipe = function(t) for k in pairs(t) do t[k] = nil end end

-- the simulated player
local SIM = { map = 1413, tracking = "Find Minerals", skill = 80, herb = 1 }
local zones = { [1413] = "The Barrens", [1411] = "Durotar", [1440] = "Ashenvale" }
C_Map = {
  GetBestMapForUnit = function() return SIM.map end,
  GetMapInfo = function(id) return { name = zones[id] } end,
  GetPlayerMapPosition = function() return { GetXY = function() return SIM.x or 0.5, SIM.y or 0.3 end } end,
  -- 1 map unit = 1000 yd, so 1% of the map = 10 yd
  GetWorldPosFromMapPos = function(_, v) return 0, { x = v.x * 1000, y = v.y * 1000 } end,
}
CreateVector2D = function(x, y) return { x = x, y = y } end
C_Timer = {
  After = function(_, fn) fn() end,
  NewTicker = function(_, fn) SIM.tick = fn; return { Cancel = function() SIM.tick = nil end } end,
}
local spellNames = { [2580] = "Find Minerals", [2383] = "Find Herbs", [2481] = "Find Treasure", [2575] = "Mining" }
GetSpellInfo = function(id) return spellNames[id] end
C_Minimap = {
  GetNumTrackingTypes = function() return 3 end,
  GetTrackingInfo = function(i)
    local list = { "Find Minerals", "Find Herbs", "Track Beasts" }
    return list[i], 0, list[i] == SIM.tracking, "spell", -1, nil
  end,
}
GetNumSkillLines = function() return 3 end
GetSkillLineInfo = function(i)
  if i == 1 then return "Professions", true end
  if i == 2 then return "Mining", false, false, SIM.skill end
  return "Herbalism", false, false, SIM.herb
end
GetTime = function() return 0 end
GetPlayerFacing = function() return 0 end
UnitBuff = function() return nil end
UIDropDownMenu_CreateInfo = function() return {} end

---------------------------------------------------------------------------
-- Load the addon the way the game does (TOC order), plus two test herb routes
---------------------------------------------------------------------------
assert(loadfile("GoblinCompass/Routes.lua"))()
table.insert(GoblinCompassRoutes, { id = "test-peacebloom", zone = "The Barrens", map = 1413, prof = "Herbalism",
  ore = "Peacebloom", levels = "10-25", pts = { 40, 30, 45, 30, 45, 35 } })
table.insert(GoblinCompassRoutes, { id = "test-bruiseweed", zone = "The Barrens", map = 1413, prof = "Herbalism",
  ore = "Bruiseweed", skill = 100, levels = "10-25", pts = { 40, 30, 45, 30, 45, 35 } })
GOBLINCOMPASS_TEST = {}  -- asks the addon to expose a few internals for testing

-- GatherMate2 stand-in: herb nodes in Ashenvale (map 1440, which has no planned routes).
-- 1% of the map is 10 yd here, so each group of 3 nodes is one "spot".
local HERB_NAMES = { [1] = "Peacebloom", [2] = "Kingsblood" }
local function gmCoord(x, y) return math.floor(x * 100) * 1000000 + math.floor(y * 100) * 100 end
local herbs = {}
local function addSpot(id, x, y)
  for i = 0, 2 do herbs[gmCoord(x + i * 0.4, y)] = id end
end
addSpot(1, 20, 20); addSpot(1, 60, 20); addSpot(1, 60, 60); addSpot(1, 20, 60)  -- Peacebloom square
addSpot(2, 40, 40); addSpot(2, 80, 80); addSpot(2, 80, 20)                      -- Kingsblood (skill 125)
GatherMate2HerbDB = { [1440] = herbs }
-- the other GatherMate2 databases: not installed
GatherMate2MineDB, GatherMate2FishDB, GatherMate2TreasureDB = false, false, false
GatherMateData2MineDB, GatherMateData2HerbDB, GatherMateData2FishDB, GatherMateData2TreasureDB = false, false, false, false
LibStub = function()
  return { GetAddon = function()
    return { GetNameForNode = function(_, _, id) return HERB_NAMES[id] end }
  end }
end

assert(loadfile("GoblinCompass/GoblinCompass.lua"))("GoblinCompass")

local ev
for _, f in ipairs(frames) do if f.scripts.OnEvent and not f.scripts.OnUpdate then ev = f end end
local function fire(e, a) ev.scripts.OnEvent(ev, e, a) end
local function last(n) return printed[#printed - (n or 0)] or "" end
local function gc(cmd) SlashCmdList.GOBLINCOMPASS(cmd) end
local function track(name) SIM.tracking = name; fire("MINIMAP_UPDATE_TRACKING") end
local mm = GoblinCompassMinimapButton

---------------------------------------------------------------------------
-- Tests (they run in order and share state, like a play session)
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; write("  ok    ", name, "\n")
  else failed = failed + 1; write("  FAIL  ", name, "\n        ", tostring(err), "\n") end
end
local function check(cond, msg) if not cond then error(msg or "check failed", 2) end end

fire("ADDON_LOADED", "GoblinCompass")

test("fresh install starts off: login with Find Minerals does nothing", function()
  local n = #printed
  fire("PLAYER_ENTERING_WORLD")
  check(#printed == n, "auto-picked while off: " .. last())
  check(GoblinCompassDB.enabled ~= true)
end)

test("tracking changes while off do nothing", function()
  local n = #printed
  track("Find Herbs"); track("Find Minerals")
  check(#printed == n, "reacted while off: " .. last())
end)

test("minimap right-click opens the 7-item quick menu without toggling", function()
  local items, opened = {}, false
  UIDropDownMenu_AddButton = function(info) if not info.isTitle then items[#items + 1] = info end end
  UIDropDownMenu_Initialize = function(frame, fn) fn(frame, 1) end
  ToggleDropDownMenu = function() opened = true end
  mm.scripts.OnClick(mm, "RightButton")
  check(opened, "menu did not open")
  check(GoblinCompassDB.enabled ~= true, "right-click toggled the addon")
  local names = {}
  for _, it in ipairs(items) do names[#names + 1] = it.text end
  check(table.concat(names, "|") == "Enabled|Automatic (from tracking)|Manual|Walk route in reverse|"
    .. "Skip this node / waypoint|Clear visited nodes|Options...", "menu was: " .. table.concat(names, " | "))
  local optsOpened = false
  InterfaceOptionsFrame_OpenToCategory = function() optsOpened = true end
  items[7].func()
  check(optsOpened, "Options... did not open the options page")
  UIDropDownMenu_AddButton = function() end
end)

test("left-click turns on and picks the Tin route (Barrens, Mining 80)", function()
  mm.scripts.OnClick(mm, "LeftButton")
  check(GoblinCompassDB.enabled == true)
  check(last():find("Tin"), last())
end)

test("left-click again turns off", function()
  mm.scripts.OnClick(mm, "LeftButton")
  check(GoblinCompassDB.enabled == false and last():find("off"), last())
end)

test("picking a profession by hand while off switches on", function()
  gc("mining")
  check(GoblinCompassDB.enabled == true)
end)

test("lower skill picks Copper instead of Tin", function()
  SIM.skill = 30
  track("Track Beasts"); track("Find Minerals")
  check(last():find("Copper"), last())
end)

test("Find Herbs starts the herb route the skill allows", function()
  SIM.herb = 50; track("Find Herbs")
  check(last():find("Peacebloom"), last())
  SIM.herb = 120; track("Find Minerals"); track("Find Herbs")
  check(last():find("Bruiseweed"), last())
end)

test("a manual pick survives a zone change", function()
  gc("fish")
  local n = #printed
  SIM.map = 1411; fire("ZONE_CHANGED_NEW_AREA")
  check(#printed == n, "manual choice was overridden: " .. last())
end)

test("Stop survives a zone change", function()
  gc("stop")
  local n = #printed
  SIM.map = 1413; fire("ZONE_CHANGED_NEW_AREA")
  check(#printed == n, "restarted after stop: " .. last())
end)

test("a tracking change restarts after Stop", function()
  SIM.tracking = "Find Minerals"; fire("UNIT_AURA", "player")
  check(last():find("Copper"), last())
end)

test("Find Minerals in a zone without routes uses node mode", function()
  SIM.map = 1440; fire("ZONE_CHANGED_NEW_AREA")
  check(last():find("Mining node"), last())
end)

test("Manual mode ignores tracking; Automatic picks it up again", function()
  gc("auto")
  check(last():find("manual"), last())
  local n = #printed
  track("Find Herbs")
  check(#printed == n, "manual mode auto-picked: " .. last())
  gc("auto")
  check(last(1):find("Peacebloom"), last(1))  -- Ashenvale has herb data, so a generated route
end)

test("/gc routes lists every route, including herb ones", function()
  gc("routes")
  check(last():find("Bruiseweed"), last())
end)

test("/gc debug runs without errors", function()
  gc("debug")
end)

test("route recorder: spacing, manual points, and output that loads back", function()
  SIM.map, SIM.x, SIM.y = 1413, 0.40, 0.30
  gc("record")
  SIM.x = 0.401; SIM.tick()   -- 1 yd: too close, ignored
  SIM.x = 0.45;  SIM.tick()   -- 50 yd: added
  SIM.y = 0.36;  SIM.tick()   -- 60 yd: added
  gc("record point")          -- added even though we haven't moved
  gc("record stop")
  local entry = GoblinCompassDB.recorded and GoblinCompassDB.recorded[1]
  check(entry, "nothing saved")
  check(entry:find("pts={ 40,30, 45,30, 45,36, 45,36 }", 1, true), entry)
  local route = assert(loadstring("return " .. entry:gsub(",%s*$", "")))()
  check(route.prof == "Herbalism" and route.map == 1413 and #route.pts == 8)
end)

---------------------------------------------------------------------------
-- Generated routes
---------------------------------------------------------------------------
local function loopLength(pts)
  local n, len = #pts / 2, 0
  for i = 1, n do
    local j = i % n + 1
    len = len + math.sqrt((pts[2 * j - 1] - pts[2 * i - 1]) ^ 2 + (pts[2 * j] - pts[2 * i]) ^ 2)
  end
  return len
end

test("loop planner: random spots give a loop with no crossings, visiting each once", function()
  local function crosses(p1, p2, p3, p4)
    local function side(a, b, c) return (b.wx - a.wx) * (c.wy - a.wy) - (b.wy - a.wy) * (c.wx - a.wx) end
    return side(p1, p2, p3) * side(p1, p2, p4) < 0 and side(p3, p4, p1) * side(p3, p4, p2) < 0
  end
  math.randomseed(42)
  for round = 1, 20 do
    local spots = {}
    for i = 1, 30 do spots[i] = { wx = math.random() * 5000, wy = math.random() * 5000 } end
    local tour = GOBLINCOMPASS_TEST.PlanLoop(spots)
    check(#tour == 30, "tour has " .. #tour .. " stops")
    local seen = {}
    for _, t in ipairs(tour) do check(not seen[t], "a spot is visited twice"); seen[t] = true end
    for i = 1, 30 do
      for j = i + 2, 30 do
        if not (i == 1 and j == 30) then
          check(not crosses(tour[i], tour[i % 30 + 1], tour[j], tour[j % 30 + 1]),
            "round " .. round .. ": legs " .. i .. " and " .. j .. " cross")
        end
      end
    end
  end
end)

test("Find Herbs in a zone with no planned route generates one from GatherMate2", function()
  SIM.map, SIM.herb = 1440, 50
  track("Find Minerals"); track("Find Herbs")
  check(last():find("Peacebloom") and last():find("generated"), last())
end)

test("generated route: 4 Peacebloom spots, shortest loop (the square, not the bow-tie)", function()
  SIM.herb = 50
  gc("generate herb")
  local found
  for i = #printed, 1, -1 do
    if printed[i]:find("generated a Herbalism route") then found = printed[i]; break end
  end
  check(found and found:find("4 spots %(12 nodes%)"), tostring(found))
  gc("generate save")
  local entry = GoblinCompassDB.recorded[#GoblinCompassDB.recorded]
  local route = assert(loadstring("return " .. entry:gsub(",%s*$", "")))()
  check(route.ore == "Peacebloom" and route.prof == "Herbalism" and route.map == 1440, entry)
  check(#route.pts == 8, entry)
  -- the square's perimeter is 4 x 40 = 160 map-%; crossing it would be ~193
  check(math.abs(loopLength(route.pts) - 160) < 2, "loop length " .. loopLength(route.pts) .. ": " .. entry)
end)

test("higher skill adds Kingsblood spots", function()
  SIM.herb = 130
  gc("generate herb")
  local found
  for i = #printed, 1, -1 do
    if printed[i]:find("generated a Herbalism route") then found = printed[i]; break end
  end
  check(found and found:find("7 spots %(21 nodes%)"), tostring(found))
end)

test("/gc generate <name> builds a route for just that herb", function()
  gc("generate kingsblood")
  check(last():find("Kingsblood"), last())
end)

test("too few spots: says so and starts nothing", function()
  SIM.herb = 50
  gc("generate kingsblood")
  check(last():find("no Herbalism nodes matching 'kingsblood'"), last())
end)

test("with auto-generate off, Find Herbs falls back to node mode", function()
  GoblinCompassDB.autoGenerate = false
  track("Find Minerals"); track("Find Herbs")
  check(last():find("Herbalism node"), last())
  GoblinCompassDB.autoGenerate = nil
end)

test("bundled routes are well-formed", function()
  local ids = {}
  for _, r in ipairs(GoblinCompassRoutes) do
    check(type(r.id) == "string" and not ids[r.id], "missing or duplicate id: " .. tostring(r.id))
    ids[r.id] = true
    check(type(r.zone) == "string" and type(r.map) == "number" and type(r.ore) == "string"
      and type(r.levels) == "string", r.id .. ": missing zone/map/ore/levels")
    check(type(r.pts) == "table" and #r.pts >= 6 and #r.pts % 2 == 0, r.id .. ": needs 3+ x,y pairs")
    for i, v in ipairs(r.pts) do
      check(type(v) == "number" and v >= 0 and v <= 100, r.id .. ": point " .. i .. " out of 0-100")
    end
    if r.prof then
      check(({ Mining = 1, Herbalism = 1, Fishing = 1, Treasure = 1 })[r.prof], r.id .. ": unknown prof " .. r.prof)
    end
  end
end)

write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
