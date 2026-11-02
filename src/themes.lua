-- themes.lua: tile and table appearance.
local C = require("config")
local Tiles = require("tiles")

local Themes = {}

local function decalBack(o, url)
  -- Custom back image as a decal on the tile's underside (local -Y).
  o.setDecals({ {
    name = "noes_back", url = url,
    position = { 0, -C.TILE_T / 2 - 0.002, 0 },
    rotation = { -90, 0, 0 },
    scale = { C.TILE_L - 0.1, C.TILE_W - 0.08, 1 },
  } })
end

function Themes.applyTiles()
  local st = S.settings
  Tiles.applyTheme(st.face, st.back)
  -- reload() respawns objects; decals and menus must be re-added once they exist again.
  Wait.time(function()
    for _, key in ipairs(Tiles.allKeys()) do
      local o = Tiles.obj(key)
      if o then
        if st.back == "custom" and st.backUrl and st.backUrl ~= "" then decalBack(o, st.backUrl) else o.setDecals({}) end
      end
    end
    if Themes.onTilesReloaded then Themes.onTilesReloaded() end
  end, 1.5)
end

function Themes.applyTable()
  local st = S.settings
  local url
  if st.tableFace == "custom" then
    if not st.tableUrl or st.tableUrl == "" then return end
    url = st.tableUrl
  else
    url = C.tableFace(st.tableFace)
  end
  local o = getObjectFromGUID(OBJ_GUIDS.tableFace)
  if not o then return end
  o.setCustomObject({ mesh = C.asset("models/table/table_face.obj"), diffuse = url, type = 4, material = 3 })
  o.reload()
end

return Themes
