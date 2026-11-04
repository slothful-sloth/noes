-- Exercise real game/physical modules with a small TTS object and event scheduler.
local passed, failed = 0, 0
local function check(name, condition)
  if condition then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. name) end
end
local objects, callbacks, nextId = {}, {}, 0
local function vector(v) return { x = v.x or v[1], y = v.y or v[2], z = v.z or v[3] } end
local function object(guid, pos)
  local o = { position = vector(pos), rotation = { x = 0, y = 0, z = 0 }, spawning = false, loading_custom = false }
  o.getGUID = function() return guid end
  o.isDestroyed = function() return o.destroyed == true end
  o.destruct = function() o.destroyed = true; objects[guid] = nil end
  o.setLock = function(v) o.locked = v end
  o.setGMNotes = function(v) o.notes = v end
  o.getGMNotes = function() return o.notes or "" end
  o.setName = function(v) o.name = v end
  o.setInvisibleTo = function(v) o.hidden = v end
  o.setCustomObject = function(v) o.custom = v end
  o.getCustomObject = function() return o.custom or { mesh = "tile", collider = "collider" } end
  o.getDecals = function() return {} end
  o.setDecals = function(v) o.decals = v end
  o.setPositionSmooth = function(v) o.position = vector(v) end
  o.setRotationSmooth = function(v) o.rotation = vector(v) end
  o.getPosition = function() return o.position end
  o.getRotation = function() return o.rotation end
  o.setVelocity = function(v) o.velocity = v end
  o.setAngularVelocity = function(v) o.angularVelocity = v end
  o.clearButtons = function() end
  o.createButton = function() end
  o.setColorTint = function() end
  objects[guid] = o
  return o
end
function spawnObject(params)
  nextId = nextId + 1
  return object("mock" .. nextId, params.position)
end
function getObjectFromGUID(guid) return objects[guid] end
function getObjects()
  local out = {}; for _, o in pairs(objects) do out[#out + 1] = o end; return out
end
Wait = {
  time = function(fn) callbacks[#callbacks + 1] = fn end,
  frames = function(fn) callbacks[#callbacks + 1] = fn end,
  condition = function(fn) callbacks[#callbacks + 1] = fn end,
}
local function flush()
  local pending = callbacks; callbacks = {}
  for _, fn in ipairs(pending) do fn() end
end
UI = { setValue = function() end, setAttribute = function() end }
JSON = { encode = function() return "" end }
Global = {}
ASSET_BASE = "https://example.invalid/"
OBJ_GUIDS = {}
Player = { Action = { Copy = 1, Cut = 2, Delete = 3, Group = 4, PickUp = 5, FlipOver = 6 } }
function Player.getAvailableColors() return { "Red", "Blue", "Orange", "Teal" } end
local messages = {}
for _, color in ipairs(Player.getAvailableColors()) do
  Player[color] = { color = color, seated = true, steam_name = color, broadcast = function(msg) messages[#messages + 1] = msg end }
end
function broadcastToAll() end

local C = require("config")
local R = require("rules")
local Layout = require("layout")
local Store = require("store")
local Tiles = require("tiles")
local Physical = require("physical")
local G = require("game")
dofile(SOURCE_ROOT .. "/src/main.lua")

local function setup(keys)
  Physical.clear(); Tiles.clearMarkers(); callbacks = {}
  S = Store.new(); S.phase = "play"; S.hand.turn = 1
  S.hand.hands = { keys or { "6-6", "6-5", "5-4" }, { "6-3" }, { "3-2" }, { "2-1" } }
  for _, key in ipairs(Tiles.allKeys()) do object(C.tileGuid(key), { 0, 1.25, 0 }) end
  G.physicalSeats = { [1] = true }; G.selected = {}
  G.refreshPhysical(); flush()
end
local function proxy(key)
  for _, o in pairs(objects) do
    local info = Physical.info(o)
    if info and info.key == key then return o end
  end
end
local function contains(list, value)
  for _, v in ipairs(list) do if v == value then return true end end
  return false
end
local function dropAt(o, x, y, z, color)
  o.position = { x = x, y = y, z = z }
  onObjectDrop(color or "Red", o); flush()
end

setup()
local p = proxy("6-6")
check("private rack is grabbable after assets load", p.interactable and not p.locked)
check("tile faces hidden from other seats and spectators", not contains(p.hidden, "Red") and contains(p.hidden, "Blue") and contains(p.hidden, "Grey") and contains(p.hidden, "Black"))
check("proxies cannot be mistaken for authoritative tiles", Tiles.keyOf(p) == nil)
check("owner may pick up", onPlayerAction(Player.Red, Player.Action.PickUp, { p }))
check("opponent cannot pick up", not onPlayerAction(Player.Blue, Player.Action.PickUp, { p }))
check("owner can rotate", onPlayerAction(Player.Red, Player.Action.FlipOver, { p }))
check("owner cannot duplicate", not onPlayerAction(Player.Red, Player.Action.Copy, { p }))
check("mixed selection cannot bypass duplicate guard", not onPlayerAction(Player.Red, Player.Action.Group, { Tiles.obj("6-6"), p }))
onObjectPickUp("Red", p); flush()
check("pickup selects tile and shows legal marker", G.selected[1] == "6-6" and #Tiles.markers() == 1)
onObjectPickUp("Red", p); flush()
check("repeat pickup retains selection", G.selected[1] == "6-6" and #Tiles.markers() == 1)
dropAt(p, 0, 1.25, 0)
check("valid release plays exactly one tile", S.hand.board.count == 1 and #S.hand.hands[1] == 2 and S.hand.turn == 2)
check("placed tile is locked", Tiles.obj("6-6").locked and not Tiles.obj("6-6").interactable)
check("old proxies destroyed when turn changes", p.destroyed and Physical.info(p) == nil)
G.dropPhysical("Red", p)
check("delayed duplicate drop does not play twice", S.hand.board.count == 1)

setup()
p = proxy("6-6")
local home = Physical.info(p).home
dropAt(p, 10, 1.25, 10)
check("off-target drop preserves hand and board", #S.hand.hands[1] == 3 and S.hand.board.count == 0)
check("off-target drop returns tile", p.position.x == home.x and p.position.z == home.z)
dropAt(p, 0, 12, 0)
check("release far above marker is rejected", S.hand.board.count == 0)
dropAt(p, 0, 1.25, 0, "Blue")
check("unauthorized drop rejected", S.hand.board.count == 0)
S.hand.turn = 2
dropAt(p, 0, 1.25, 0)
check("stale turn rejected", S.hand.board.count == 0)

setup()
S.hand.mustLeadKey = "6-6"
p = proxy("6-5"); dropAt(p, 0, 1.25, 0)
check("forced opening respected", S.hand.board.count == 0)
S.hand.mustLeadKey = nil; S.hand.committed[1] = "6-6"
dropAt(p, 0, 1.25, 0)
check("commitment respected", S.hand.board.count == 0)

setup({ "6-5", "4-4", "3-3" })
Layout.place(S.hand.layout, R.parse("6-6"), "C")
S.hand.board = R.play(S.hand.board, R.parse("6-6"), "C")
p = proxy("4-4"); dropAt(p, 1.04, 1.25, 0)
check("illegal pip match rejected", S.hand.board.count == 1)
p = proxy("6-5")
local target = Layout.preview(S.hand.layout, R.parse("6-5"), "L", 6)
dropAt(p, target.x, 1.25, target.z)
check("nearest legal end chosen", S.hand.board.count == 2 and S.hand.board.L == 5 and S.hand.board.R == 6)

setup()
p = proxy("6-6")
G.handAction("Blue", 2, "physical")
check("waiting player toggle does not destroy active rack", not p.destroyed)
G.handAction("Red", 1, "physical")
check("toggle off removes proxies", p.destroyed and not G.physicalSeats[1])
check("panel actions remain available", G.handView(1).actions.physical == "Physical tiles: off")

setup()
Physical.show(1) -- callbacks still pending
p = proxy("6-6")
Physical.clear(); flush()
check("late asset callback cannot revive removed proxy", p.destroyed and not p.interactable)

setup()
p = proxy("6-6"); p.held_by_color = "Red"
dropAt(p, 0, 1.25, 0)
check("release handler ignores regrabbed tile", S.hand.board.count == 0)
p.held_by_color = nil
G.selected[1] = "6-6"; G.playSelected("Red", 1, "C")
check("panel play still works while physical mode enabled", S.hand.board.count == 1 and p.destroyed)

setup({ "6-6" })
p = proxy("6-6"); dropAt(p, 0, 1.25, 0)
check("winning play removes private rack", S.phase == "handover" and p.destroyed)

setup()
p = proxy("6-6")
S.hand.hands[1] = { "6-5", "5-4" }
dropAt(p, 0, 1.25, 0)
check("tile no longer owned cannot be played", S.hand.board.count == 0)

setup()
p = proxy("6-6")
Tiles.clearStrays()
check("saved transient proxies are removed on load cleanup", p.destroyed)
Physical.clear()

print(string.format("Physical interaction tests: %d passed, %d failed", passed, failed))
return failed > 0
