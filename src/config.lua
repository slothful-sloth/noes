-- config.lua: constants shared by the TTS modules.
-- ASSET_BASE and OBJ_GUIDS are injected by tools/build.py.

local C = {}

C.TABLE_Y = 1.0            -- top of the table face
C.TILE_L, C.TILE_W, C.TILE_T = 2.0, 1.0, 0.42
C.BOARD_LIMIT = 14.0       -- |x| and |z| below this count as "on the board"
C.RACK_DIST = 17.6         -- rack centre distance from the table centre
C.REVEAL_DIST = 15.1       -- face-up row in front of the rack
C.ROW_SPACING = 1.15       -- tiles in the public rows lie pointing at the centre
C.TAUNT_DIST = 15.6
C.TAUNT_LATERAL = 5.6      -- taunt spot offset to the seat's right
C.SLOT_SPACING = 2.1
C.SOPA_RADIUS = 9.0
C.MARKER_SNAP = 1.6        -- drop within this distance of a marker to play there

-- Seats in turn order (counter-clockwise seen from above). dir points from the centre to the player.
-- Teams: seats 1 & 3 -> team 1, seats 2 & 4 -> team 2.
C.SEATS = {
  { color = "Red",    dir = { 0, -1 }, yaw = 0,   pos = "South" },
  { color = "Blue",   dir = { 1, 0 },  yaw = 270, pos = "East" },
  { color = "Orange", dir = { 0, 1 },  yaw = 180, pos = "North" },
  { color = "Teal",   dir = { -1, 0 }, yaw = 90,  pos = "West" },
}
C.SEAT_OF_COLOR = {}
for i, s in ipairs(C.SEATS) do C.SEAT_OF_COLOR[s.color] = i end

C.TEAM_DEFAULT_NAMES = { "Team Red", "Team Blue" }
C.TEAM_HEX = { "#E8743B", "#3BA3E8" }
C.TEAM_RGB = { { 0.91, 0.45, 0.23 }, { 0.23, 0.64, 0.91 } }
C.TEAM_BUTTON = { "#b8592c|#cf6a3a|#9a4a24|#b8592c80", "#2c79b8|#3a8bcf|#24659a|#2c79b880" }

C.FACES = {
  { id = "white",  name = "White with black pips" },
  { id = "ivory",  name = "Classic ivory" },
  { id = "colors", name = "Pip colours by number" },
}
C.BACKS = {
  { id = "pr",       name = "Puerto Rico" },
  { id = "tw",       name = "Taiwan" },
  { id = "bd",       name = "Bangladesh" },
  { id = "nj",       name = "New Jersey" },
  { id = "horsemen", name = "Dürer: The Four Horsemen" },
  { id = "plain",    name = "Plain" },
  { id = "custom",   name = "Custom image URL" },
}
C.TABLE_FACES = {
  { id = "felt",    name = "Green felt" },
  { id = "maple",   name = "Maple wood" },
  { id = "pr",      name = "Puerto Rico / coquí" },
  { id = "slate",   name = "Dark slate" },
  { id = "suckers", name = "Suckers" },
  { id = "custom",  name = "Custom image URL" },
}

function C.asset(path) return ASSET_BASE .. path end
function C.tileMesh(key) return C.asset("models/tiles/tile_" .. string.gsub(key, "-", "") .. ".obj") end
C.TILE_COLLIDER = "models/tiles/tile_collider.obj"
function C.tileAtlas(face, back) return C.asset("textures/tiles/" .. face .. "_" .. back .. ".jpg") end
function C.tableFace(id) return C.asset("textures/table/face_" .. id .. ".jpg") end
C.PROXY_COLLIDER = "models/tiles/proxy_collider.obj"
C.MARKER_OK = "models/markers/marker_ok.obj"
C.MARKER_BAD = "models/markers/marker_bad.obj"
C.ZONE_MESH = "models/markers/rack_zone.obj"
C.ZONE_DIST = 16.8         -- centre of the virtual rack drawn during the sopa
C.ZONE_HALF_LAT = 5.0
C.ZONE_HALF_RAD = 1.9
C.WHITE_TEX = "textures/white.png"
C.RAIL_DIST = 22.1          -- middle of the maple rail (face apothem 21, outer edge 23.2)
C.RAIL_TOP = 0.75           -- rail top above C.TABLE_Y
C.KNOCK_SOUND = "sounds/knock.wav"
C.SLAM_SOUND = "sounds/slam.wav"

function C.tileGuid(key)
  local hi, lo = string.match(key, "^(%d)-(%d)$")
  return "d0" .. hi .. lo .. "0e"
end

return C
