-- Private, disposable 3D hand tiles. The authoritative tiles stay in the public rack.
local C = require("config")
local U = require("util")
local Tiles = require("tiles")

local Physical = {}
local proxies = {}

function Physical.info(obj)
  return obj and proxies[obj.getGUID()] or nil
end

function Physical.clear()
  local old = proxies
  proxies = {} -- invalidate pending asset-load callbacks before destroying objects
  for _, info in pairs(old) do
    if not info.obj.isDestroyed() then info.obj.destruct() end
  end
end

function Physical.show(seat)
  Physical.clear()
  local color = C.SEATS[seat].color
  local keys = S.hand.hands[seat]
  for i, key in ipairs(keys) do
    local pos = U.seatPoint(seat, C.RACK_DIST + 2, U.slotLateral(i, #keys), C.TABLE_Y + 0.5)
    local obj = spawnObject({ type = "Custom_Model", position = pos, rotation = U.faceUpRot(seat), sound = false })
    local guid = obj.getGUID()
    local info = { obj = obj, key = key, seat = seat, home = pos }
    proxies[guid] = info
    obj.setLock(true)
    obj.interactable = false
    obj.setGMNotes("noes_proxy")
    obj.setName("")
    obj.tooltip = false
    obj.setInvisibleTo(U.otherColors(color))
    obj.setCustomObject(Tiles.obj(key).getCustomObject())
    obj.setDecals(Tiles.obj(key).getDecals())
    Tiles.whenLoaded(obj, function(o)
      if proxies[guid] ~= info then return end
      o.setInvisibleTo(U.otherColors(color))
      o.interactable = true
      o.setLock(false)
    end)
  end
end

function Physical.returnTile(obj)
  local info = Physical.info(obj)
  if not info then return end
  obj.setPositionSmooth(info.home, false, true)
  obj.setRotationSmooth(U.faceUpRot(info.seat), false, true)
  obj.setVelocity({ 0, 0, 0 })
  obj.setAngularVelocity({ 0, 0, 0 })
end

return Physical
