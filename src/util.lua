-- util.lua: small helpers (geometry, players, messaging).
local C = require("config")

local U = {}

function U.right(seat)
  local d = C.SEATS[seat].dir
  return { -d[2], d[1] }
end

-- Position from the seat frame: `dist` toward the player, `lat` to the player's right.
function U.seatPoint(seat, dist, lat, y)
  local d, r = C.SEATS[seat].dir, U.right(seat)
  return { x = d[1] * dist + r[1] * lat, y = y, z = d[2] * dist + r[2] * lat }
end

function U.slotLateral(i, n)
  n = n or 7
  return (i - (n + 1) / 2) * C.SLOT_SPACING
end

local function rowLateral(i, n) return (i - ((n or 7) + 1) / 2) * C.ROW_SPACING end

function U.rackPos(seat, i, n)
  return U.seatPoint(seat, C.RACK_DIST, rowLateral(i, n), C.TABLE_Y + C.TILE_T / 2 + 0.02)
end
function U.rowYaw(seat) return (C.SEATS[seat].yaw + 90) % 360 end
function U.rackRot(seat) return { x = -90, y = C.SEATS[seat].yaw, z = 0 } end

function U.revealPos(seat, i, n)
  return U.seatPoint(seat, C.REVEAL_DIST, rowLateral(i, n), C.TABLE_Y + C.TILE_T / 2 + 0.05)
end
function U.faceUpRot(seat) return { x = 0, y = U.rowYaw(seat), z = 0 } end

function U.tauntPos(seat) return U.seatPoint(seat, C.TAUNT_DIST, C.TAUNT_LATERAL, C.TABLE_Y + C.TILE_T / 2 + 0.06) end

-- Which seat's area (rack/taunt/reveal band) a point lies in, or nil.
function U.seatArea(p)
  for seat, s in ipairs(C.SEATS) do
    local d, r = s.dir, U.right(seat)
    local along = p.x * d[1] + p.z * d[2]
    local lat = p.x * r[1] + p.z * r[2]
    if along > C.ZONE_DIST - C.ZONE_HALF_RAD - 0.6 and along < C.RACK_DIST + 3 and math.abs(lat) < C.ZONE_HALF_LAT + 1 then
      return seat, along, lat
    end
  end
  return nil
end

function U.onBoard(p) return math.abs(p.x) < C.BOARD_LIMIT and math.abs(p.z) < C.BOARD_LIMIT end

function U.nearTaunt(seat, p)
  local t = U.tauntPos(seat)
  return math.abs(p.x - t.x) < 1.8 and math.abs(p.z - t.z) < 1.8
end

function U.dist2(a, b)
  local dx, dz = a.x - b.x, a.z - b.z
  return dx * dx + dz * dz
end

-- Players ---------------------------------------------------------------------

function U.seatOf(color) return C.SEAT_OF_COLOR[color] end

function U.playerAt(seat)
  local p = Player[C.SEATS[seat].color]
  if p and p.seated then return p end
  return nil
end

function U.nameAt(seat)
  local p = U.playerAt(seat)
  if p then return p.steam_name end
  return C.SEATS[seat].color
end

function U.teamName(team)
  return (S and S.teams[team] and S.teams[team].name) or C.TEAM_DEFAULT_NAMES[team]
end

function U.otherColors(color)
  local list = {}
  for _, c in ipairs(Player.getAvailableColors()) do
    if c ~= color then list[#list + 1] = c end
  end
  for _, c in ipairs({ "Grey", "Black" }) do
    if c ~= color then list[#list + 1] = c end
  end
  return list
end

function U.tell(color, msg, rgb)
  local p = Player[color]
  if p and p.seated then p.broadcast(msg, rgb or { 1, 0.85, 0.5 }) end
end

function U.announce(msg, rgb) broadcastToAll(msg, rgb or { 1, 1, 1 }) end

function U.copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = U.copy(v) end
  return o
end

function U.indexOf(list, v)
  for i, x in ipairs(list) do if x == v then return i end end
  return nil
end

function U.removeValue(list, v)
  local i = U.indexOf(list, v)
  if i then table.remove(list, i) end
  return i
end

return U
