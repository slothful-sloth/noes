-- tiles.lua: everything that moves tile objects around.
--
-- Hands live in each player's private on-screen panel. On the table, each seat shows a
-- non-interactive row of its tiles lying face down (the public tile count). Tiles can only be
-- handled physically during the sopa.
local C = require("config")
local R = require("rules")
local U = require("util")

local Tiles = {}

local markers = {}        -- spawned marker objects

function Tiles.obj(key) return getObjectFromGUID(C.tileGuid(key)) end

function Tiles.keyOf(obj)
  if obj == nil or obj.getGMNotes == nil then return nil end
  local k = obj.getGMNotes()
  if k and string.match(k, "^%d%-%d$") then return k end
  return nil
end

function Tiles.allKeys()
  local list = {}
  for _, t in ipairs(R.allTiles()) do list[#list + 1] = R.key(t) end
  return list
end

-- Run fn(o) once a spawned custom object has finished loading its assets
-- (visibility set earlier is lost when the custom mesh loads).
local function whenLoaded(o, fn)
  Wait.condition(function() if o and not o.isDestroyed() then fn(o) end end,
    function() return o == nil or o.isDestroyed() or (o.spawning == false and o.loading_custom == false) end,
    5, function() if o and not o.isDestroyed() then fn(o) end end)
end
Tiles.whenLoaded = whenLoaded

-- Movement -----------------------------------------------------------------------------

local function setHandleable(o, yes)
  o.interactable = yes
end

-- Move a tile; when `lock` it ends locked in place.
function Tiles.moveTo(key, pos, rot, lock)
  local o = Tiles.obj(key)
  if not o then return end
  o.setLock(true)                       -- locked while animating so physics can't disturb it
  o.setPositionSmooth(pos, false, true)
  o.setRotationSmooth(rot, false, true)
  if not lock then
    Wait.time(function()
      local oo = Tiles.obj(key)
      if oo then oo.setLock(false) end
    end, 0.8)
  end
end

-- Lay every tile face down in the sopa area at random spots (handleable).
function Tiles.scatter(keys)
  local spots = {}
  for gx = -4, 4 do
    for gz = -6, 6 do
      local x, z = gx * 2.25, gz * 1.4
      if x * x + z * z < C.SOPA_RADIUS * C.SOPA_RADIUS then spots[#spots + 1] = { x, z } end
    end
  end
  spots = R.shuffled(spots)
  for i, key in ipairs(R.shuffled(keys)) do
    local s = spots[i]
    local o = Tiles.obj(key)
    if o and s then
      setHandleable(o, true)
      o.clearButtons()
      local jx, jz = (math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.3
      Tiles.moveTo(key, { s[1] + jx, C.TABLE_Y + C.TILE_T / 2 + 0.05, s[2] + jz }, { 0, math.random(0, 359), 180 }, false)
    end
  end
end

-- A seat's display: hidden tiles lie face down in a row; revealed (bluff-called) tiles lie face
-- up in front of the row. The taunt tile (if any) is elsewhere.
function Tiles.arrangeRack(seat)
  local h = S.hand
  local down, open = {}, {}
  for _, key in ipairs(h.hands[seat]) do
    if h.taunt[seat] ~= key then
      if h.revealed[key] then open[#open + 1] = key else down[#down + 1] = key end
    end
  end
  local yaw = U.rowYaw(seat)
  for i, key in ipairs(down) do
    local o = Tiles.obj(key)
    if o then
      setHandleable(o, false)
      o.clearButtons()
    end
    Tiles.moveTo(key, U.rackPos(seat, i, #down), { 0, yaw, 180 }, true)
  end
  for i, key in ipairs(open) do
    local o = Tiles.obj(key)
    if o then setHandleable(o, h.revealedHideable and h.revealedHideable[key] or false) end
    Tiles.moveTo(key, U.revealPos(seat, i, 7), { 0, yaw, 0 }, true)
  end
end

-- A bluff-called tile can be hidden again by its owner (button on the tile).
function Tiles.addHideButton(key)
  local o = Tiles.obj(key)
  if not o then return end
  o.clearButtons()
  o.interactable = true
  o.createButton({
    click_function = "onRevealedClick", function_owner = Global, label = "Hide",
    position = { 0, C.TILE_T / 2 + 0.05, 0 }, rotation = { 0, 90, 0 },
    width = 520, height = 260, font_size = 150,
    color = { 0.1, 0.1, 0.1, 0.75 }, hover_color = { 0.25, 0.25, 0.25, 0.9 }, font_color = { 1, 0.85, 0.5, 1 },
    tooltip = "Turn it back face down",
  })
end

-- Put a played tile on the board (face up, locked).
function Tiles.placeOnBoard(key, p)
  local o = Tiles.obj(key)
  if o then
    setHandleable(o, false)
    o.clearButtons()
  end
  Tiles.moveTo(key, { p.x, C.TABLE_Y + C.TILE_T / 2 + 0.02, p.z }, { 0, p.yaw, 0 }, true)
end

-- Lay a whole hand face up (end-of-hand count).
function Tiles.revealHand(seat)
  local keys = S.hand.hands[seat]
  for i, key in ipairs(keys) do
    Tiles.moveTo(key, U.revealPos(seat, i, math.max(#keys, 1)), U.faceUpRot(seat), true)
  end
end

-- Sopa stirring: moving a pointer quickly over loose tiles pushes them along. -----------------

local lastPointer = {}

local STIR_RADIUS = 3.0
local STIR_MIN_SPEED = 2.5

function Tiles.stirStep(dt, isFree, mayStir)
  for _, p in ipairs(Player.getPlayers()) do
    local ok, pos = pcall(function() return p.getPointerPosition() end)
    if ok and pos and mayStir(p.color) then
      local prev = lastPointer[p.color]
      lastPointer[p.color] = pos
      local r2 = pos.x * pos.x + pos.z * pos.z
      if prev and r2 < 14 * 14 and pos.y < C.TABLE_Y + 3 then
        local vx, vz = (pos.x - prev.x) / dt, (pos.z - prev.z) / dt
        local speed = math.sqrt(vx * vx + vz * vz)
        if speed > STIR_MIN_SPEED then
          local k = math.min(speed, 16) / speed      -- cap the push speed
          for _, key in ipairs(Tiles.allKeys()) do
            if isFree(key) then
              local o = Tiles.obj(key)
              local tp = o and o.getPosition()
              if tp then
                local dx, dz = tp.x - pos.x, tp.z - pos.z
                local d = math.sqrt(dx * dx + dz * dz)
                if d < STIR_RADIUS then
                  local fall = math.sqrt(1 - d / STIR_RADIUS)
                  -- along the stroke, plus a swirl around the cursor
                  local sw = (math.random() < 0.5) and -1 or 1
                  local px, pz = -dz / (d + 0.3), dx / (d + 0.3)
                  o.setLock(false)
                  o.addForce({ (vx * k * 0.85 + sw * px * 3) * fall, 0, (vz * k * 0.85 + sw * pz * 3) * fall }, 4)
                  o.addTorque({ 0, (math.random() - 0.5) * 30 * fall, 0 }, 4)
                end
              end
            end
          end
        end
      end
    else
      lastPointer[p.color] = nil
    end
  end
  -- keep loose tiles in the sopa and face down
  for _, key in ipairs(Tiles.allKeys()) do
    if isFree(key) then
      local o = Tiles.obj(key)
      if o and not o.held_by_color then
        local tp = o.getPosition()
        local d = math.sqrt(tp.x * tp.x + tp.z * tp.z)
        if d > C.SOPA_RADIUS + 2.5 and d < C.ZONE_DIST - C.ZONE_HALF_RAD - 0.8 then
          o.addForce({ -tp.x / d * 4, 0, -tp.z / d * 4 }, 4)
        end
        local rz = o.getRotation().z
        if rz < 90 or rz > 270 then
          o.setRotationSmooth({ 0, o.getRotation().y, 180 }, false, true)
        end
      end
    end
  end
end

-- Virtual racks shown during the sopa: drop tiles inside to draw them. --------------------------

local zones = {}   -- seat -> object

function Tiles.zoneLabel(seat)
  local z = zones[seat]
  if not z or z.isDestroyed() then return end
  z.clearButtons()
  local n = #S.hand.hands[seat]
  local text = (n >= 7) and "Your rack · 7/7 ✓" or string.format("Your rack · %d/7 · drag tiles here", n)
  z.createButton({
    click_function = "noop", function_owner = Global, label = text,
    position = { 0, 0.05, 1.15 }, rotation = { 0, 180, 0 }, width = 0, height = 0, font_size = 240,
    font_color = { 1, 0.9, 0.6, 0.9 },
  })
end

function Tiles.showZones(on)
  for seat = 1, 4 do
    local z = zones[seat]
    if z and not z.isDestroyed() then z.destruct() end
    zones[seat] = nil
  end
  if not on then return end
  for seat = 1, 4 do
    local p = U.seatPoint(seat, C.ZONE_DIST, 0, C.TABLE_Y + 0.02)
    local color = C.SEATS[seat].color
    local z = spawnObject({ type = "Custom_Model", position = p, rotation = { 0, C.SEATS[seat].yaw, 0 }, sound = false })
    z.setCustomObject({ mesh = C.asset(C.ZONE_MESH), diffuse = C.asset(C.WHITE_TEX), collider = C.asset(C.PROXY_COLLIDER),
      type = 0, material = 3, cast_shadows = false })
    z.setLock(true)
    z.setGMNotes("noes_marker")
    zones[seat] = z
    local private = not S.settings.dev
    whenLoaded(z, function(o)
      o.setLock(true)
      o.interactable = false
      o.setColorTint({ 1, 0.82, 0.4 })
      if private then o.setInvisibleTo(U.otherColors(color)) end
      Tiles.zoneLabel(seat)
    end)
  end
end

function Tiles.resetStir() lastPointer = {} end

-- Markers ----------------------------------------------------------------------------------

function Tiles.clearMarkers()
  for _, m in ipairs(markers) do
    if m and not m.isDestroyed() then m.destruct() end
  end
  markers = {}
end

function Tiles.markers() return markers end

local SIDE_LABEL = { L = "Left", R = "Right", C = "Lead" }

-- Spawn a private placement marker. kind = "ok" (clickable, info = {key, side}) or "bad".
function Tiles.spawnMarker(color, p, kind, info, lifetime)
  local mesh = (kind == "bad") and C.MARKER_BAD or C.MARKER_OK
  local tint = (kind == "bad") and { 0.9, 0.15, 0.1 } or { 0.2, 0.95, 0.35 }
  local obj = spawnObject({
    type = "Custom_Model",
    position = { p.x, C.TABLE_Y + 0.03, p.z },
    rotation = { 0, p.yaw or 0, 0 },
    sound = false,
  })
  obj.setCustomObject({ mesh = C.asset(mesh), diffuse = C.asset(C.WHITE_TEX), collider = C.asset(C.PROXY_COLLIDER),
    type = 0, material = 3, cast_shadows = false })
  obj.setLock(true)
  obj.setGMNotes("noes_marker")
  obj.memo = info and JSON.encode(info) or ""
  local private = not S.settings.dev
  if private then obj.setInvisibleTo(U.otherColors(color)) end
  whenLoaded(obj, function(o)
    o.setLock(true)
    o.setColorTint(tint)
    if private then o.setInvisibleTo(U.otherColors(color)) end
    if kind == "ok" and info then
      o.createButton({
        click_function = "onMarkerClick", function_owner = Global,
        label = SIDE_LABEL[info.side] or "", position = { 0, 0.08, 0 }, rotation = { 0, 0, 0 },
        width = 900, height = 420, font_size = 220,
        color = { 0.2, 0.95, 0.35, 0.35 }, hover_color = { 0.3, 1, 0.45, 0.6 },
        font_color = { 1, 1, 1, 1 }, tooltip = "Play here",
      })
    else
      o.interactable = false
    end
  end)
  markers[#markers + 1] = obj
  if lifetime then
    Wait.time(function()
      if obj and not obj.isDestroyed() then
        U.removeValue(markers, obj)
        obj.destruct()
      end
    end, lifetime)
  end
  return obj
end

-- Name signs: upright labels on the rail in front of each seat, facing the table so the other
-- three players can read them. Hidden from the seat's own player. ------------------------------

local signs = {}   -- seat -> object

local function signText(seat)
  local p = U.playerAt(seat)
  if p then return p.steam_name, C.TEAM_RGB[R.teamOf(seat)] end
  return "open seat", { 0.75, 0.75, 0.75 }
end

local function labelSign(seat)
  local o = signs[seat]
  if not o or o.isDestroyed() then return end
  local text, rgb = signText(seat)
  o.clearButtons()
  o.createButton({
    click_function = "noop", function_owner = Global, label = text,
    position = { 0, 0.55, 0 }, rotation = { 270, 0, 0 }, width = 0, height = 0,
    font_size = U.fitFont(text, 9, 420), font_color = { rgb[1], rgb[2], rgb[3], 1 },
  })
  if not S.settings.dev then o.setInvisibleTo({ C.SEATS[seat].color }) else o.setInvisibleTo({}) end
end

function Tiles.refreshSigns()
  for seat = 1, 4 do
    local o = signs[seat]
    if o and not o.isDestroyed() then
      if not o.spawning and not o.loading_custom then labelSign(seat) end
    else
      local pos = U.seatPoint(seat, C.RAIL_DIST, 0, C.TABLE_Y + C.RAIL_TOP)
      o = spawnObject({ type = "Custom_Model", position = pos, rotation = { 0, C.SEATS[seat].yaw, 0 }, sound = false })
      o.setCustomObject({ mesh = C.asset(C.PROXY_COLLIDER), collider = C.asset(C.PROXY_COLLIDER), type = 0,
        cast_shadows = false })
      o.setLock(true)
      o.setGMNotes("noes_marker")
      signs[seat] = o
      whenLoaded(o, function(obj)
        obj.setLock(true)
        obj.interactable = false
        labelSign(seat)
      end)
    end
  end
end

function Tiles.clearStrays()
  for _, o in ipairs(getObjects()) do
    local n = o.getGMNotes()
    if n == "noes_marker" or n == "noes_proxy" then o.destruct() end
  end
  markers = {}
end

-- Themes ------------------------------------------------------------------------------------

function Tiles.applyTheme(face, back)
  local backId = (back == "custom") and "plain" or back
  local diffuse = C.tileAtlas(face, backId)
  for _, key in ipairs(Tiles.allKeys()) do
    local o = Tiles.obj(key)
    if o then
      o.setCustomObject({ mesh = C.tileMesh(key), diffuse = diffuse, collider = C.asset(C.TILE_COLLIDER),
        type = 0, material = 0 })
      o.reload()
    end
  end
end

return Tiles
