-- Goblin Compass: an arrow that guides you to ore, herbs and fish.
--   Node mode  : points at the nearest known node (data read from GatherMate2)
--   Route mode : walks you around a planned farming loop for the zone you pick
local ADDON_NAME = ...

local floor, sqrt, atan2, rad, deg, cos, sin = math.floor, math.sqrt, math.atan2, math.rad, math.deg, math.cos, math.sin
local ARRIVE_YARDS = 15     -- node mode: closer than this = node counts as visited
local RESPAWN_SECS = 600    -- node mode: visited nodes are ignored for this long
local SWITCH_RATIO = 0.7    -- node mode: switch target only if a new one is this much closer
local WP_RADIUS    = 50     -- route mode: waypoint counts as reached inside this many yards

local PROF_ORDER = { "Mining", "Herbalism", "Fishing", "Treasure" }
local PROF_TYPE  = { Mining = "Mining", Herbalism = "Herb Gathering", Fishing = "Fishing", Treasure = "Treasure" }
local ORE_ORDER  = { "Copper", "Tin", "Iron", "Mithril", "Thorium" }
local ORE_SKILL  = { Copper = 1, Tin = 65, Iron = 125, Mithril = 175, Thorium = 230 }  -- Mining skill needed
local REC_STEP   = 40     -- /gc record: drop a waypoint every this many yards walked
-- tracking abilities -> profession (Find Minerals, Find Herbs, Find Treasure)
local TRACK_SPELLS = { [2580] = "Mining", [2383] = "Herbalism", [2481] = "Treasure" }
local ALIASES = {
  mining = "Mining", mine = "Mining", ore = "Mining",
  herb = "Herbalism", herbs = "Herbalism", herbalism = "Herbalism",
  fish = "Fishing", fishing = "Fishing",
  treasure = "Treasure", chest = "Treasure",
}
-- arrow tint for each profession (r, g, b)
local PROF_COLOR = {
  Mining    = { 1.00, 0.50, 0.10 },
  Herbalism = { 0.35, 0.90, 0.30 },
  Fishing   = { 0.30, 0.60, 1.00 },
  Treasure  = { 1.00, 0.82, 0.15 },
}
-- GatherMate2 saved-variable tables (your own scanned nodes) + shipped data module tables
local SOURCES = {
  Mining    = { "GatherMate2MineDB",     "GatherMateData2MineDB" },
  Herbalism = { "GatherMate2HerbDB",     "GatherMateData2HerbDB" },
  Fishing   = { "GatherMate2FishDB",     "GatherMateData2FishDB" },
  Treasure  = { "GatherMate2TreasureDB", "GatherMateData2TreasureDB" },
}

local state = {
  mode = nil,               -- nil | "nodes" | "route"
  prof = nil, mapID = nil, nodes = nil, target = nil, visited = {},
  route = nil, wp = nil, lastRepick = 0,
  auto = false,             -- current guidance was picked automatically from tracking
  userStopped = false,      -- user pressed stop: don't auto-start again until tracking changes
  lastTrack = nil,          -- profession of the last seen tracking ability
  E = nil, S = nil, axesMap = nil,
}

local function DB() GoblinCompassDB = GoblinCompassDB or {}; return GoblinCompassDB end
local function Print(msg) print("|cff33ff99Goblin Compass:|r " .. tostring(msg)) end

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------
local function TryLoadData()
  local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  if loader then pcall(loader, "GatherMate2_Data") end
end

-- map position (0-1) -> world coordinates (yards)
local function ToWorld(mapID, x, y)
  local _, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
  if pos then return pos.x, pos.y end
end

local function PlayerPos()
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then return end
  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return end
  local x, y = pos:GetXY()
  if not x or (x == 0 and y == 0) then return end
  return mapID, x, y
end

-- Work out which world axes are map-east / map-south for this map, so the arrow
-- is correct whatever the world-coordinate convention is.
local function EnsureAxes(mapID)
  if state.axesMap == mapID and state.E then return true end
  local cx, cy = ToWorld(mapID, 0.5, 0.5)
  local ex, ey = ToWorld(mapID, 0.51, 0.5)
  local sx, sy = ToWorld(mapID, 0.5, 0.51)
  if not (cx and ex and sx) then return false end
  local el = sqrt((ex - cx) ^ 2 + (ey - cy) ^ 2)
  local sl = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
  if el == 0 or sl == 0 then return false end
  state.E = { (ex - cx) / el, (ey - cy) / el }
  state.S = { (sx - cx) / sl, (sy - cy) / sl }
  state.axesMap = mapID
  return true
end

---------------------------------------------------------------------------
-- Node data (GatherMate2)
---------------------------------------------------------------------------
local nameCache = {}
local function NodeName(prof, id)
  local k = prof .. ":" .. tostring(id)
  if nameCache[k] then return nameCache[k] end
  local name
  local Ace = LibStub and LibStub("AceAddon-3.0", true)
  local GM = Ace and Ace:GetAddon("GatherMate2", true)
  if GM and GM.GetNameForNode then
    local ok, r = pcall(GM.GetNameForNode, GM, PROF_TYPE[prof], id)
    if ok and type(r) == "string" then name = r end
  end
  name = name or (prof .. " node #" .. tostring(id))
  nameCache[k] = name
  return name
end

local function PassesFilter(prof, node)
  local f = DB().filter
  if not f or f == "" then return true end
  return NodeName(prof, node.id):lower():find(f:lower(), 1, true) ~= nil
end

local function BuildNodes(prof, mapID)
  local seen, list = {}, {}
  for _, g in ipairs(SOURCES[prof]) do
    local db = _G[g]
    local zone = db and db[mapID]
    if zone then
      for coord, id in pairs(zone) do
        if not seen[coord] then
          seen[coord] = true
          -- GatherMate2 coord encoding: xxxxyyyyLL
          local x = floor(coord / 1000000) / 10000
          local y = floor((coord % 1000000) / 100) / 10000
          local wx, wy = ToWorld(mapID, x, y)
          if wx then
            list[#list + 1] = { key = mapID .. ":" .. coord, x = x, y = y, wx = wx, wy = wy, id = id }
          end
        end
      end
    end
  end
  return list
end

local function MarkVisited(node)
  state.visited[node.key] = GetTime() + RESPAWN_SECS
end

local function PickTarget(px, py)
  local now, best, bd = GetTime(), nil, nil
  for _, n in ipairs(state.nodes) do
    local v = state.visited[n.key]
    if not (v and v > now) and PassesFilter(state.prof, n) then
      local d = (n.wx - px) ^ 2 + (n.wy - py) ^ 2
      if not bd or d < bd then best, bd = n, d end
    end
  end
  return best, bd and sqrt(bd) or nil
end

---------------------------------------------------------------------------
-- Planned routes
---------------------------------------------------------------------------
local function AllRoutes() return GoblinCompassRoutes or {} end

local function RouteLabel(r)
  local s = r.zone
  if r.note then s = s .. " - " .. r.note end
  return s .. " (" .. r.levels .. ")"
end

local function NormZone(s)
  s = (s or ""):lower()
  s = s:gsub("^the ", ""):gsub("^northern ", "")
  return s
end

-- does this route belong to the zone the player is standing in?
local function RouteMatchesMap(route, mapID)
  if not mapID then return false end
  if route.map == mapID then return true end
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  return info and info.name and NormZone(info.name) == NormZone(route.zone) or false
end

local function RoutesHere()
  local out = {}
  local mapID = C_Map.GetBestMapForUnit("player")
  for _, r in ipairs(AllRoutes()) do if RouteMatchesMap(r, mapID) then out[#out + 1] = r end end
  return out
end

local function RouteProf(r) return r.prof or "Mining" end
local function RouteSkill(r) return r.skill or ORE_SKILL[r.ore] or 1 end

-- what the routes gather (r.ore: an ore, herb, fish...), known ores first, then in file order
local function RouteResources()
  local out, seen = {}, {}
  local function add(name) if name and not seen[name] then seen[name] = true; out[#out + 1] = name end end
  for _, ore in ipairs(ORE_ORDER) do
    for _, r in ipairs(AllRoutes()) do if r.ore == ore then add(ore); break end end
  end
  for _, r in ipairs(AllRoutes()) do add(r.ore) end
  return out
end

-- every word in the query must appear somewhere in the route's id/zone/ore/note
local function FindRoutes(q)
  q = (q or ""):lower():gsub("[%-']", " ")
  local words = {}
  for w in q:gmatch("%S+") do words[#words + 1] = w end
  local out = {}
  for _, r in ipairs(AllRoutes()) do
    local hay = (r.id .. " " .. r.zone .. " " .. r.ore .. " " .. RouteProf(r) .. " " .. (r.note or "")):lower():gsub("[%-']", " ")
    local ok = true
    for _, w in ipairs(words) do
      if not hay:find(w, 1, true) then ok = false; break end
    end
    if ok then out[#out + 1] = r end
  end
  return out
end

-- convert route points into world coordinates (cached per route+map)
local function RouteWorld(route, mapID)
  if route._w and route._wmap == mapID then return route._w end
  local w, pts = {}, route.pts
  for i = 1, #pts, 2 do
    local wx, wy = ToWorld(mapID, pts[i] / 100, pts[i + 1] / 100)
    if not wx then return nil end
    w[#w + 1] = { wx, wy, pts[i], pts[i + 1] }
  end
  route._w, route._wmap = w, mapID
  return w
end

local function NextWP(i, n)
  if DB().reverse then return ((i - 2) % n) + 1 end
  return (i % n) + 1
end

---------------------------------------------------------------------------
-- Arrow frame
---------------------------------------------------------------------------
local arrow = CreateFrame("Frame", "GoblinCompassFrame", UIParent)
arrow:SetSize(64, 64)
arrow:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
arrow:SetMovable(true)
arrow:EnableMouse(true)
arrow:RegisterForDrag("LeftButton")
arrow:SetClampedToScreen(true)
arrow:Hide()

arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
arrow.tex:SetSize(56, 56)
arrow.tex:SetPoint("CENTER")
arrow.tex:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\arrow")

local function SetColor(prof)
  local c = PROF_COLOR[prof] or PROF_COLOR.Mining
  arrow.tex:SetVertexColor(c[1], c[2], c[3])
end

arrow.label = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
arrow.label:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
arrow.label2 = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
arrow.label2:SetPoint("TOP", arrow.label, "BOTTOM", 0, -1)

arrow:SetScript("OnDragStart", function(self) if not DB().locked then self:StartMoving() end end)
arrow:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  DB().pos = { p, rp, x, y }
end)

local function Message(line1, line2)
  arrow.tex:Hide()
  arrow.label:SetText(line1 or "")
  arrow.label2:SetText(line2 or "")
end

-- rotate the arrow towards a target given in world coordinates; returns yards
local function Aim(px, py, tx, ty)
  local dx, dy = tx - px, ty - py
  local dist = sqrt(dx * dx + dy * dy)
  local dE = dx * state.E[1] + dy * state.E[2]
  local dS = dx * state.S[1] + dy * state.S[2]
  local facing = GetPlayerFacing()
  arrow.tex:Show()
  if facing then
    -- angle (CCW from north) to target, minus player facing (also CCW from north)
    arrow.tex:SetRotation(atan2(-dE, -dS) - facing)
  end
  return dist
end

local function UpdateNodes(mapID, x, y, px, py)
  if mapID ~= state.mapID or not state.nodes then
    state.mapID, state.nodes, state.target = mapID, BuildNodes(state.prof, mapID), nil
  end
  if #state.nodes == 0 then
    return Message(state.prof, "No known nodes in this zone")
  end

  local t = state.target
  if t and state.visited[t.key] then t = nil end
  if not t then
    t = PickTarget(px, py)
    state.target = t
  elseif GetTime() - state.lastRepick > 3 then
    state.lastRepick = GetTime()
    local cur = sqrt((t.wx - px) ^ 2 + (t.wy - py) ^ 2)
    local best, bd = PickTarget(px, py)
    if best and bd and bd < cur * SWITCH_RATIO then t = best; state.target = best end
  end
  if not t then
    return Message(state.prof, "All known nodes visited (they respawn after a while)")
  end

  local dist = sqrt((t.wx - px) ^ 2 + (t.wy - py) ^ 2)
  if dist < (DB().arrive or ARRIVE_YARDS) then
    MarkVisited(t); state.target = nil
    return
  end
  SetColor(state.prof)
  Aim(px, py, t.wx, t.wy)
  arrow.label:SetText(NodeName(state.prof, t.id))
  arrow.label2:SetText(string.format("%.0f yd", dist))
end

local function UpdateRoute(mapID, x, y, px, py)
  local route = state.route
  if not RouteMatchesMap(route, mapID) then
    return Message(route.zone .. " - " .. route.ore, "Travel to " .. route.zone .. " to start this route")
  end
  local w = RouteWorld(route, mapID)
  if not w or #w < 2 then return Message(route.zone, "Route data could not be placed on the map") end
  local n = #w
  local radius = DB().wpRadius or WP_RADIUS

  local function distTo(i) return sqrt((w[i][1] - px) ^ 2 + (w[i][2] - py) ^ 2) end
  local function nearest()
    local bi, bd
    for i = 1, n do local d = distTo(i); if not bd or d < bd then bi, bd = i, d end end
    return bi, bd
  end

  if not state.wp then
    local i, d = nearest()
    if d < radius * 2 then i = NextWP(i, n) end
    state.wp = i
  end

  -- advance past reached waypoints
  local guard = 0
  while distTo(state.wp) < radius and guard < n do
    state.wp = NextWP(state.wp, n); guard = guard + 1
  end
  -- cut corners: if the following waypoint is already closer, skip ahead
  local cur = distTo(state.wp)
  local nx = NextWP(state.wp, n)
  local dn = distTo(nx)
  if dn < cur and cur < radius * 3 then state.wp, cur = nx, dn end
  -- lost the route (death, teleport, long detour): re-sync to the nearest waypoint
  if cur > 600 and GetTime() - state.lastRepick > 3 then
    state.lastRepick = GetTime()
    local i = nearest()
    state.wp = i; cur = distTo(i)
  end

  local wp = w[state.wp]
  SetColor(RouteProf(route))
  local dist = Aim(px, py, wp[1], wp[2])
  arrow.label:SetText(route.zone .. " - " .. route.ore)
  arrow.label2:SetText(string.format("%.0f yd", dist))
end

local function Update()
  if not state.mode then arrow:Hide(); return end
  local mapID, x, y = PlayerPos()
  if not mapID then return Message("Goblin Compass", "No map position here") end
  local px, py = ToWorld(mapID, x, y)
  if not px or not EnsureAxes(mapID) then return end
  if state.mode == "route" then UpdateRoute(mapID, x, y, px, py) else UpdateNodes(mapID, x, y, px, py) end
end

local acc = 0
arrow:SetScript("OnUpdate", function(_, dt)
  acc = acc + dt
  if acc < 0.03 then return end
  acc = 0
  Update()
end)

---------------------------------------------------------------------------
-- Control
---------------------------------------------------------------------------
-- On/off switch (left-click the minimap button). Off by default after install.
local function IsEnabled() return DB().enabled == true end
local UpdateMMIcon = function() end  -- set once the minimap button exists

-- picking something by hand while switched off switches the addon on
local function EnsureEnabled()
  if not IsEnabled() then DB().enabled = true; UpdateMMIcon() end
end

local function Stop(silent)
  state.mode, state.prof, state.route, state.nodes, state.target, state.wp = nil, nil, nil, nil, nil, nil
  state.auto = false
  arrow:Hide()
  if not silent then state.userStopped = true; Print("stopped.") end
end

local function SetProf(prof, auto)
  if not prof then return Stop() end
  EnsureEnabled()
  TryLoadData()
  state.mode, state.prof, state.route = "nodes", prof, nil
  state.nodes, state.target, state.mapID, state.wp = nil, nil, nil, nil
  state.auto, state.userStopped = auto and true or false, false
  arrow:Show()
  Print((auto and "(auto) " or "") .. "guiding to the nearest " .. prof .. " node. Drag the arrow to move it.")
end

local function StartRoute(route, auto)
  if not route then return Stop() end
  EnsureEnabled()
  state.mode, state.route, state.prof = "route", route, nil
  state.nodes, state.target, state.wp = nil, nil, nil
  state.auto, state.userStopped = auto and true or false, false
  arrow:Show()
  Print((auto and "(auto) " or "") .. "route: " .. route.ore .. " - " .. RouteLabel(route) .. (DB().reverse and " (reverse)" or "") .. ". Follow the arrow around the loop.")
end

---------------------------------------------------------------------------
-- Auto-pick from the active tracking ability (Find Minerals / Find Herbs / Find Treasure)
---------------------------------------------------------------------------
local function TrackSpellName(id)
  local name = GetSpellInfo and GetSpellInfo(id)
  if not name and C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(id) end
  return name
end

local function TrackSpellIcon(id)
  if GetSpellTexture then return GetSpellTexture(id) end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
end

-- which gathering profession the player is tracking right now (or nil)
local function ActiveTracking()
  -- 1) minimap tracking list
  if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
    for i = 1, C_Minimap.GetNumTrackingTypes() or 0 do
      local a, _, c, _, _, f = C_Minimap.GetTrackingInfo(i)
      local name, active, spellID
      if type(a) == "table" then name, active, spellID = a.name, a.active, a.spellID
      else name, active, spellID = a, c, f end
      if active then
        if spellID and TRACK_SPELLS[spellID] then return TRACK_SPELLS[spellID] end
        for id, prof in pairs(TRACK_SPELLS) do
          if name and name == TrackSpellName(id) then return prof end
        end
      end
    end
  end
  -- 2) the single active tracking icon shown on the minimap
  local tex = GetTrackingTexture and GetTrackingTexture()
  if tex then
    for id, prof in pairs(TRACK_SPELLS) do
      local icon = TrackSpellIcon(id)
      if icon and (icon == tex or tostring(icon):lower() == tostring(tex):lower()) then return prof end
    end
  end
  -- 3) tracking shown as a buff
  if UnitBuff then
    for i = 1, 40 do
      local name, _, _, _, _, _, _, _, _, spellID = UnitBuff("player", i)
      if not name then break end
      if spellID and TRACK_SPELLS[spellID] then return TRACK_SPELLS[spellID] end
    end
  end
end

-- the player's skill in a gathering profession (nil if unknown)
local function ProfSkill(prof)
  if not (GetNumSkillLines and GetSkillLineInfo) then return end
  local want = prof
  if prof == "Mining" then want = TrackSpellName(2575) or "Mining" end  -- spell 2575 is "Mining" in the client's language
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank = GetSkillLineInfo(i)
    if not isHeader and (name == want or name == prof) then return rank end
  end
end
local function MiningSkill() return ProfSkill("Mining") end

-- the best planned route for this zone and profession: the highest one your skill allows
local function BestRouteHere(prof)
  local skill = ProfSkill(prof)
  local best, first
  for _, r in ipairs(RoutesHere()) do
    if RouteProf(r) == prof then
      first = first or r
      local need = RouteSkill(r)
      if (not skill or skill >= need) and (not best or need > RouteSkill(best)) then best = r end
    end
  end
  return best or first
end

-- force: tracking just changed, so override whatever was chosen by hand
local function AutoPick(force)
  if not IsEnabled() or DB().autoTrack == false then return end
  local prof = ActiveTracking()
  if not prof then
    if state.auto and force then Stop(true) end  -- switched tracking off / to something else
    return
  end
  if not force and ((state.mode and not state.auto) or state.userStopped) then return end
  local r = BestRouteHere(prof)
  if r then
    if not (state.mode == "route" and state.route == r) then StartRoute(r, true) end
    state.auto = true
    return
  end
  if not (state.mode == "nodes" and state.prof == prof) then SetProf(prof, true) end
  state.auto = true
end

-- Automatic: follow the tracking ability. Manual: only what you pick yourself.
local function SetAutoMode(on)
  DB().autoTrack = on and true or false
  if on then
    AutoPick(true)
  else
    state.auto = false  -- keep the current arrow, but it's yours now
  end
end

local function SetEnabled(on)
  DB().enabled = on and true or false
  UpdateMMIcon()
  if GoblinCompassEnabledCheck then GoblinCompassEnabledCheck:SetChecked(DB().enabled) end
  if on then
    state.userStopped = false
    Print("on." .. (DB().autoTrack == false and " Pick a profession or route from the menu (right-click the minimap button)."
      or " Turn on Find Minerals, Find Herbs or Find Treasure and the arrow follows it."))
    AutoPick(true)
  else
    Stop(true)
    Print("off. Left-click the minimap button to turn it back on.")
  end
end

local function OnTrackingMaybeChanged()
  local prof = ActiveTracking()
  if prof == state.lastTrack then return end
  state.lastTrack, state.userStopped = prof, false
  AutoPick(true)
end

local function Skip()
  if state.mode == "route" and state.wp and state.route then
    local w = state.route._w
    if w then state.wp = NextWP(state.wp, #w) end
  elseif state.target then
    MarkVisited(state.target); state.target = nil
  end
end

local function SetReverse(on)
  DB().reverse = on and true or false
  state.wp = nil
end

local function Debug()
  TryLoadData()
  local Ace = LibStub and LibStub("AceAddon-3.0", true)
  Print("GatherMate2 loaded: " .. tostring((Ace and Ace:GetAddon("GatherMate2", true)) ~= nil))
  local mapID = C_Map.GetBestMapForUnit("player")
  local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  Print("current uiMapID: " .. tostring(mapID) .. (info and (" (" .. tostring(info.name) .. ")") or ""))
  Print("planned routes loaded: " .. #AllRoutes() .. ", routes for this zone: " .. #RoutesHere())
  Print("tracking: " .. tostring(ActiveTracking()) .. ", mining skill: " .. tostring(MiningSkill())
    .. ", choosing: " .. (DB().autoTrack == false and "manual" or "automatic"))
  for _, prof in ipairs(PROF_ORDER) do
    for _, g in ipairs(SOURCES[prof]) do
      local db = _G[g]
      if db then
        local zones, sample = 0, {}
        for k in pairs(db) do
          zones = zones + 1
          if #sample < 6 then sample[#sample + 1] = tostring(k) end
        end
        local here = 0
        if mapID and db[mapID] then for _ in pairs(db[mapID]) do here = here + 1 end end
        Print(string.format("%s: %d zones (keys e.g. %s), %d nodes in this zone", g, zones, table.concat(sample, ","), here))
      else
        Print(g .. ": not found")
      end
    end
  end
end

---------------------------------------------------------------------------
-- Right-click / minimap menu (profession nodes + planned routes)
---------------------------------------------------------------------------
local OpenOptions  -- defined below

local menuFrame = CreateFrame("Frame", "GoblinCompassMenu", UIParent, "UIDropDownMenuTemplate")

local function AddItem(level, text, fn, opts)
  local info = UIDropDownMenu_CreateInfo()
  info.text, info.func = text, fn
  info.notCheckable = true
  if opts then for k, v in pairs(opts) do info[k] = v end end
  UIDropDownMenu_AddButton(info, level)
end

local function InitMenu(self, level)
  level = level or 1
  local val = UIDROPDOWNMENU_MENU_VALUE
  if level == 1 then
    AddItem(level, "Goblin Compass", nil, { isTitle = true })
    AddItem(level, "Enabled", function() SetEnabled(not IsEnabled()) end,
      { notCheckable = false, checked = IsEnabled(), isNotRadio = true })
    AddItem(level, "Automatic (from tracking)", function() SetAutoMode(true) end,
      { notCheckable = false, checked = DB().autoTrack ~= false })
    AddItem(level, "Manual", function() SetAutoMode(false) end,
      { notCheckable = false, checked = DB().autoTrack == false })
    AddItem(level, "Gather nodes (GatherMate2)", nil, { isTitle = true })
    for _, prof in ipairs(PROF_ORDER) do
      AddItem(level, prof, function() SetProf(prof) end,
        { notCheckable = false, checked = (state.mode == "nodes" and state.prof == prof) })
    end
    AddItem(level, "Planned zone routes", nil, { hasArrow = true, value = "ROUTES", keepShownOnClick = true })
    AddItem(level, "Walk route in reverse", function() SetReverse(not DB().reverse) end,
      { notCheckable = false, checked = DB().reverse and true or false, isNotRadio = true, keepShownOnClick = true })
    AddItem(level, "Skip this node / waypoint", Skip)
    AddItem(level, "Clear visited nodes", function() wipe(state.visited); state.target = nil end)
    AddItem(level, "Stop guiding", function() Stop() end)
    AddItem(level, "Options...", function() OpenOptions() end)
  elseif level == 2 and val == "ROUTES" then
    local here = RoutesHere()
    if #here > 0 then
      AddItem(level, "You are in " .. here[1].zone, nil, { isTitle = true })
      for _, r in ipairs(here) do
        AddItem(level, r.ore .. " - " .. RouteLabel(r), function() StartRoute(r) end,
          { notCheckable = false, checked = (state.mode == "route" and state.route == r) })
      end
    end
    for _, ore in ipairs(RouteResources()) do
      AddItem(level, ore, nil, { hasArrow = true, value = "ORE:" .. ore, keepShownOnClick = true })
    end
  elseif level == 3 and type(val) == "string" and val:sub(1, 4) == "ORE:" then
    local ore = val:sub(5)
    for _, r in ipairs(AllRoutes()) do
      if r.ore == ore then
        AddItem(level, RouteLabel(r) .. (r.faction and (" |cff999999" .. r.faction .. "|r") or ""),
          function() StartRoute(r) end,
          { notCheckable = false, checked = (state.mode == "route" and state.route == r) })
      end
    end
  end
end

local function ShowMenu()
  UIDropDownMenu_Initialize(menuFrame, InitMenu, "MENU")
  ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
end
arrow:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then ShowMenu() end end)

---------------------------------------------------------------------------
-- Minimap button (drag to move it around the minimap edge)
---------------------------------------------------------------------------
local mm = CreateFrame("Button", "GoblinCompassMinimapButton", Minimap)
mm:SetSize(31, 31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local mmBg = mm:CreateTexture(nil, "BACKGROUND")
mmBg:SetSize(20, 20); mmBg:SetPoint("TOPLEFT", 7, -5)
mmBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
local mmIcon = mm:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(17, 17); mmIcon:SetPoint("TOPLEFT", 7, -6)
mmIcon:SetTexture("Interface\\Icons\\Trade_Mining")
mmIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetSize(53, 53); mmBorder:SetPoint("TOPLEFT")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

-- full color when on, grey and dimmed when off
UpdateMMIcon = function()
  local on = IsEnabled()
  mmIcon:SetDesaturated(not on)
  if on then mmIcon:SetVertexColor(1, 1, 1) else mmIcon:SetVertexColor(0.5, 0.5, 0.5) end
end

local function UpdateMMPos()
  local a = rad(DB().mmAngle or 200)
  local r = (Minimap:GetWidth() / 2) + 5
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", cos(a) * r, sin(a) * r)
end

local function SetMinimapShown(show)
  DB().hideMinimap = not show
  mm:SetShown(show)
end

mm:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local sc = Minimap:GetEffectiveScale()
    DB().mmAngle = deg(atan2(cy / sc - my, cx / sc - mx))
    UpdateMMPos()
  end)
end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mm:SetScript("OnClick", function(self, button)
  if button == "RightButton" then
    OpenOptions()
  else
    SetEnabled(not IsEnabled())
    if self:IsMouseOver() and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end  -- refresh tooltip
  end
end)
mm:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Goblin Compass")
  if IsEnabled() then
    GameTooltip:AddLine("On", 0.3, 1, 0.3)
    local line = DB().autoTrack == false and "Manual: pick from the menu" or "Waiting for Find Minerals / Herbs / Treasure"
    if state.mode == "nodes" then line = "Hunting: " .. state.prof
    elseif state.mode == "route" then line = "Route: " .. state.route.ore .. " - " .. RouteLabel(state.route) end
    GameTooltip:AddLine(line, 1, 1, 1)
  else
    GameTooltip:AddLine("Off", 1, 0.3, 0.3)
  end
  GameTooltip:AddLine("Left-click: turn " .. (IsEnabled() and "off" or "on"), 0.7, 0.7, 0.7)
  GameTooltip:AddLine("Right-click: options", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("Drag: move button", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Options panel (Esc > Interface > AddOns > Goblin Compass)
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "GoblinCompassOptions", UIParent)
panel.name = "Goblin Compass"

local ptitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
ptitle:SetPoint("TOPLEFT", 16, -16)
ptitle:SetText("Goblin Compass")
local psub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
psub:SetPoint("TOPLEFT", ptitle, "BOTTOMLEFT", 0, -6)
psub:SetText("Left-click the minimap button to turn Goblin Compass on or off. Right-click the arrow for a quick menu.")

-- On/off
local enCheck = CreateFrame("CheckButton", "GoblinCompassEnabledCheck", panel, "InterfaceOptionsCheckButtonTemplate")
enCheck:SetPoint("TOPLEFT", psub, "BOTTOMLEFT", -2, -10)
_G["GoblinCompassEnabledCheckText"]:SetText("Enabled")
enCheck:SetScript("OnClick", function(self) SetEnabled(self:GetChecked() and true or false) end)

-- Automatic / Manual choice
local mlabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
mlabel:SetPoint("TOPLEFT", enCheck, "BOTTOMLEFT", 2, -10)
mlabel:SetText("What to follow")
local function MakeRadio(name, label, x, y, hint)
  local r = CreateFrame("CheckButton", name, panel, "UIRadioButtonTemplate")
  r:SetPoint("TOPLEFT", mlabel, "BOTTOMLEFT", x, y)
  local t = _G[name .. "Text"] or r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  t:ClearAllPoints(); t:SetPoint("LEFT", r, "RIGHT", 4, 0)
  t:SetText(label)
  r.tip = hint
  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(label)
    GameTooltip:AddLine(self.tip, 1, 1, 1, true); GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end
local autoRadio = MakeRadio("GoblinCompassAutoRadio", "Automatic (from tracking)", 0, -6,
  "Find Minerals, Find Herbs or Find Treasure picks the profession, and the zone you're in picks the route.")
local manualRadio = MakeRadio("GoblinCompassManualRadio", "Manual", 0, -28,
  "Nothing starts by itself. Pick a profession or route below, or from the menu.")
local function RefreshModeRadios()
  local on = DB().autoTrack ~= false
  autoRadio:SetChecked(on); manualRadio:SetChecked(not on)
end
autoRadio:SetScript("OnClick", function() SetAutoMode(true); RefreshModeRadios() end)
manualRadio:SetScript("OnClick", function() SetAutoMode(false); RefreshModeRadios() end)

-- Node-mode profession dropdown
local dlabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
dlabel:SetPoint("TOPLEFT", mlabel, "BOTTOMLEFT", 0, -60)
dlabel:SetText("Gather nodes (GatherMate2)")
local dd = CreateFrame("Frame", "GoblinCompassProfDropdown", panel, "UIDropDownMenuTemplate")
dd:SetPoint("TOPLEFT", dlabel, "BOTTOMLEFT", -16, -2)
UIDropDownMenu_SetWidth(dd, 160)

-- Route dropdown
local rlabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
rlabel:SetPoint("LEFT", dlabel, "LEFT", 230, 0)
rlabel:SetText("Planned zone route")
local rd = CreateFrame("Frame", "GoblinCompassRouteDropdown", panel, "UIDropDownMenuTemplate")
rd:SetPoint("TOPLEFT", rlabel, "BOTTOMLEFT", -16, -2)
UIDropDownMenu_SetWidth(rd, 230)

local function RefreshDropdownText()
  if state.mode == "nodes" then
    UIDropDownMenu_SetText(dd, state.prof); UIDropDownMenu_SetText(rd, "Off")
  elseif state.mode == "route" then
    UIDropDownMenu_SetText(dd, "Off"); UIDropDownMenu_SetText(rd, state.route.ore .. " - " .. RouteLabel(state.route))
  else
    UIDropDownMenu_SetText(dd, "Off"); UIDropDownMenu_SetText(rd, "Off")
  end
end

UIDropDownMenu_Initialize(dd, function(self, level)
  local function add(text, prof)
    local info = UIDropDownMenu_CreateInfo()
    info.text = text
    info.checked = (state.mode == "nodes" and state.prof == prof) or (prof == nil and state.mode == nil)
    info.func = function() SetProf(prof); RefreshDropdownText() end
    UIDropDownMenu_AddButton(info, level)
  end
  add("Off", nil)
  for _, prof in ipairs(PROF_ORDER) do add(prof, prof) end
end)

UIDropDownMenu_Initialize(rd, function(self, level)
  local info = UIDropDownMenu_CreateInfo()
  info.text, info.checked = "Off", (state.mode ~= "route")
  info.func = function() if state.mode == "route" then Stop() end; RefreshDropdownText() end
  UIDropDownMenu_AddButton(info, level)
  for _, ore in ipairs(RouteResources()) do
    local h = UIDropDownMenu_CreateInfo()
    h.text, h.isTitle, h.notCheckable = ore, true, true
    UIDropDownMenu_AddButton(h, level)
    for _, r in ipairs(AllRoutes()) do
      if r.ore == ore then
        local i = UIDropDownMenu_CreateInfo()
        i.text = RouteLabel(r)
        i.checked = (state.mode == "route" and state.route == r)
        i.func = function() StartRoute(r); RefreshDropdownText() end
        UIDropDownMenu_AddButton(i, level)
      end
    end
  end
end)

-- Filter (node mode)
local flabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
flabel:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 16, -14)
flabel:SetText("Node name filter (node mode, e.g. copper)")
local edit = CreateFrame("EditBox", "GoblinCompassFilterBox", panel, "InputBoxTemplate")
edit:SetSize(180, 20)
edit:SetPoint("TOPLEFT", flabel, "BOTTOMLEFT", 6, -6)
edit:SetAutoFocus(false)
edit:SetScript("OnEnterPressed", function(self)
  DB().filter = self:GetText(); state.target = nil; self:ClearFocus()
end)
edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local function MakeCheck(name, label, anchor, dy, onClick)
  local c = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
  c:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor == edit and -6 or 0, dy)
  _G[name .. "Text"]:SetText(label)
  c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
  return c
end

local rev  = MakeCheck("GoblinCompassReverseCheck", "Walk planned routes in reverse", edit, -14, SetReverse)
local lock = MakeCheck("GoblinCompassLockCheck", "Lock arrow position", rev, -2, function(v) DB().locked = v end)
local mmCheck = MakeCheck("GoblinCompassMinimapCheck", "Show minimap button", lock, -2, SetMinimapShown)

local function MakeSlider(name, label, minv, maxv, step, anchor, onChange)
  local s = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -26)
  s:SetWidth(220)
  s:SetMinMaxValues(minv, maxv)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  _G[name .. "Low"]:SetText(minv)
  _G[name .. "High"]:SetText(maxv)
  s:SetScript("OnValueChanged", function(self, v)
    v = floor(v / step + 0.5) * step
    _G[name .. "Text"]:SetText(label .. ": " .. v)
    onChange(v)
  end)
  return s
end

local scale = MakeSlider("GoblinCompassScaleSlider", "Arrow size", 0.5, 2.5, 0.1, mmCheck, function(v)
  DB().scale = v; arrow:SetScale(v)
end)
local arrive = MakeSlider("GoblinCompassArriveSlider", "Node arrival distance (yd)", 5, 40, 1, scale, function(v)
  DB().arrive = v
end)
local wpr = MakeSlider("GoblinCompassWaypointSlider", "Route waypoint radius (yd)", 20, 120, 5, arrive, function(v)
  DB().wpRadius = v
end)

local resetPos = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetPos:SetSize(150, 24)
resetPos:SetPoint("TOPLEFT", wpr, "BOTTOMLEFT", -4, -26)
resetPos:SetText("Reset arrow position")
resetPos:SetScript("OnClick", function()
  DB().pos = nil
  arrow:ClearAllPoints(); arrow:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
end)
local resetVisited = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetVisited:SetSize(150, 24)
resetVisited:SetPoint("LEFT", resetPos, "RIGHT", 8, 0)
resetVisited:SetText("Clear visited nodes")
resetVisited:SetScript("OnClick", function() wipe(state.visited); state.target = nil end)

local function RefreshPanel()
  RefreshDropdownText()
  edit:SetText(DB().filter or "")
  rev:SetChecked(DB().reverse and true or false)
  lock:SetChecked(DB().locked and true or false)
  mmCheck:SetChecked(not DB().hideMinimap)
  RefreshModeRadios()
  enCheck:SetChecked(IsEnabled())
  scale:SetValue(DB().scale or 1)
  arrive:SetValue(DB().arrive or ARRIVE_YARDS)
  wpr:SetValue(DB().wpRadius or WP_RADIUS)
end
panel:SetScript("OnShow", RefreshPanel)
panel.refresh = RefreshPanel

local category
if Settings and Settings.RegisterCanvasLayoutCategory then
  category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
  InterfaceOptions_AddCategory(panel)
end

function OpenOptions()
  if category and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel) -- called twice: known Blizzard quirk
  end
end

---------------------------------------------------------------------------
-- Init + slash commands
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("MINIMAP_UPDATE_TRACKING")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == ADDON_NAME then
    local db = DB()
    local p = db.pos
    if p then arrow:ClearAllPoints(); arrow:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    arrow:SetScale(db.scale or 1)
    UpdateMMPos()
    UpdateMMIcon()
    mm:SetShown(not db.hideMinimap)
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    state.nodes, state.target, state.mapID, state.axesMap = nil, nil, nil, nil
    if state.mode == "route" then state.wp = nil end
    AutoPick(false)
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- give the map and tracking info a moment to settle after loading
    C_Timer.After(2, function()
      state.lastTrack = ActiveTracking()
      AutoPick(false)
    end)
  elseif event == "MINIMAP_UPDATE_TRACKING" or event == "UNIT_AURA" then
    OnTrackingMaybeChanged()
  end
end)

---------------------------------------------------------------------------
-- Route recorder: /gc record walks a loop and saves it in Routes.lua format
---------------------------------------------------------------------------
local rec  -- { map, zone, prof, pts = {x,y,...}, lastWX, lastWY }
local function NPts(r) return floor(#r.pts / 2) end
local function Num(v) return (string.format("%.1f", v):gsub("%.0$", "")) end  -- 45.0 -> "45", 45.25 -> "45.3"

local function RecAdd(force)
  local mapID, x, y = PlayerPos()
  if not mapID then return end
  if mapID ~= rec.map then
    if force then Print("you're on a different map than the recording; point not added.") end
    return
  end
  local wx, wy = ToWorld(mapID, x, y)
  if not force and rec.lastWX and wx then
    local d = sqrt((wx - rec.lastWX) ^ 2 + (wy - rec.lastWY) ^ 2)
    if d < (DB().recStep or REC_STEP) then return end
  end
  rec.pts[#rec.pts + 1] = x * 100
  rec.pts[#rec.pts + 1] = y * 100
  rec.lastWX, rec.lastWY = wx, wy
  if force then Print("point " .. NPts(rec) .. " added.") end
end

local recTicker
local function RecordCommand(arg)
  local sub, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  if sub == "" or sub == "start" then
    if rec then return Print("already recording (" .. NPts(rec) .. " points). /gc record stop to save.") end
    local mapID = C_Map.GetBestMapForUnit("player")
    local info = mapID and C_Map.GetMapInfo(mapID)
    if not info then return Print("can't read your map position here.") end
    rec = { map = mapID, zone = info.name, pts = {}, prof = state.lastTrack or "Mining" }
    RecAdd(false)  -- first point: always added, since there's no previous one
    recTicker = C_Timer.NewTicker(0.5, function() RecAdd(false) end)
    Print("recording a " .. rec.prof .. " route in " .. rec.zone .. ". Walk your loop; a point is added every "
      .. (DB().recStep or REC_STEP) .. " yd. /gc record point adds one now, /gc record stop saves.")
  elseif sub == "point" then
    if not rec then return Print("not recording. /gc record to start.") end
    RecAdd(true)
  elseif sub == "stop" or sub == "cancel" then
    if not rec then return Print("not recording.") end
    if recTicker then recTicker:Cancel(); recTicker = nil end
    local r = rec; rec = nil
    if sub == "cancel" then return Print("recording thrown away.") end
    if #r.pts < 6 then return Print("only " .. NPts(r) .. " points recorded; a route needs at least 3. Nothing saved.") end
    local nums = {}
    for i = 1, #r.pts, 2 do nums[#nums + 1] = Num(r.pts[i]) .. "," .. Num(r.pts[i + 1]) end
    local id = (r.zone .. "-" .. r.prof):lower():gsub("'", ""):gsub("[^%w]+", "-")
    local entry = string.format('{ id="%s", zone="%s", map=%d, prof="%s", ore="CHANGE ME", levels="?",\n    pts={ %s } },',
      id, r.zone, r.map, r.prof, table.concat(nums, ", "))
    local db = DB()
    db.recorded = db.recorded or {}
    db.recorded[#db.recorded + 1] = entry
    Print("saved " .. NPts(r) .. " points as recording #" .. #db.recorded
      .. ". Log out or /reload, then copy it from WTF\\Account\\<account>\\SavedVariables\\GoblinCompass.lua (look for \"recorded\").")
  elseif sub == "clear" then
    DB().recorded = nil
    Print("saved recordings cleared.")
  elseif sub == "step" then
    local n = tonumber(rest)
    if not n or n < 5 then return Print("usage: /gc record step <yards>, e.g. /gc record step 40") end
    DB().recStep = n
    Print("recording step: " .. n .. " yd")
  else
    Print("/gc record [start] | point | stop | cancel | clear | step <yards>")
  end
end

local function ListRoutes()
  Print("planned routes (use /gc route <text>):")
  for _, ore in ipairs(RouteResources()) do
    for _, r in ipairs(AllRoutes()) do
      if r.ore == ore then print("  " .. ore .. ": " .. RouteLabel(r) .. "  |cff888888[" .. r.id .. "]|r") end
    end
  end
end

local function RouteCommand(q)
  local matches
  if q == "" then
    matches = RoutesHere()
    if #matches == 0 then return ListRoutes() end
  else
    matches = FindRoutes(q)
    if #matches == 0 then Print("no route matches '" .. q .. "'."); return ListRoutes() end
  end
  if #matches == 1 then return StartRoute(matches[1]) end
  -- several matches: prefer an exact id, otherwise list them
  for _, r in ipairs(matches) do if r.id == q then return StartRoute(r) end end
  Print("several routes match, be more specific:")
  for _, r in ipairs(matches) do print("  " .. r.ore .. ": " .. RouteLabel(r) .. "  |cff888888[" .. r.id .. "]|r") end
end

SLASH_GOBLINCOMPASS1, SLASH_GOBLINCOMPASS2 = "/goblin", "/gc"
SlashCmdList["GOBLINCOMPASS"] = function(msg)
  msg = (msg or ""):lower()
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  if cmd == "" then
    ShowMenu()
  elseif cmd == "options" or cmd == "config" then
    OpenOptions()
  elseif ALIASES[cmd] then
    SetProf(ALIASES[cmd])
  elseif cmd == "route" then
    RouteCommand(rest)
  elseif cmd == "routes" then
    ListRoutes()
  elseif cmd == "reverse" then
    SetReverse(not DB().reverse); Print("route direction: " .. (DB().reverse and "reverse" or "normal"))
  elseif cmd == "on" or cmd == "off" or cmd == "toggle" then
    SetEnabled(cmd == "on" or (cmd == "toggle" and not IsEnabled()))
  elseif cmd == "stop" then
    Stop()
  elseif cmd == "skip" then
    Skip()
  elseif cmd == "reset" then
    wipe(state.visited); state.target = nil; Print("visited nodes cleared.")
  elseif cmd == "filter" then
    DB().filter = rest; state.target = nil
    Print(rest == "" and "filter cleared." or ("filter: " .. rest))
  elseif cmd == "record" then
    RecordCommand(rest)
  elseif cmd == "auto" then
    SetAutoMode(DB().autoTrack == false)
    Print("choosing: " .. (DB().autoTrack and "automatic (from tracking)" or "manual"))
  elseif cmd == "debug" then
    Debug()
  else
    Print("/gc (menu) | /gc options | /gc mining|herb|fish|treasure | /gc route [zone/ore] | routes | reverse | stop | skip | reset | filter <text> | on | off | auto | record | debug")
  end
end
