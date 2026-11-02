-- layout.lua: pure geometry for the line of play. No TTS API calls.
--
-- World plane is (x, z); y is handled by the caller.
-- Tile mesh convention (see tools/gen_tiles.py): long axis on local +X, the "hi" half at +X,
-- face on local +Y. Yaw follows Unity/TTS: rotating by yaw maps local +X to
-- (cos yaw, -sin yaw) in (x, z), i.e. yaw = atan2(-dz, dx).
--
-- The opening tile sits at the origin. The R arm runs +x and snakes into rows further and
-- further toward -z; the L arm runs -x and snakes toward +z. At the bound an arm takes two
-- corners: first toward its outward side (`vert`), then back along the reversed row direction.
-- Doubles lie crosswise and never take a corner.

local Layout = {}

Layout.L = 2.0       -- tile length (world units)
Layout.W = 1.0       -- tile width
Layout.GAP = 0.04    -- spacing between tiles
Layout.BOUND = 11.0  -- arms turn before their far edge would pass |x| > BOUND

local function add(a, b) return { a[1] + b[1], a[2] + b[2] } end
local function mul(a, s) return { a[1] * s, a[2] * s } end
local function turnRight(d) return { d[2], -d[1] } end -- clockwise seen from above

function Layout.yawFor(d)
  local deg = math.deg(math.atan2(-d[2], d[1]))
  if deg < 0 then deg = deg + 360 end
  return deg
end

-- Yaw that puts the half with value `outer` pointing along `d` (and the other half toward the chain).
function Layout.orientedYaw(t, outer, d)
  if t.hi == t.lo then return Layout.yawFor(turnRight(d)) end -- crosswise
  if t.hi == outer then return Layout.yawFor(d) end
  return Layout.yawFor(mul(d, -1))
end

-- State ----------------------------------------------------------------------
-- arm = { edge = {x,z}, dir = {dx,dz}, vert = {0,±1}, after = {±1,0}|nil, pending = n }
--   pending = corner turns still owed; after = row direction once the turn completes

function Layout.new()
  return { arms = nil }
end

local function along(arm, amount) return arm.edge[1] * arm.dir[1] + arm.edge[2] * arm.dir[2] + amount end

-- Opening tile: returns placement and initialises both arms.
local function placeCenter(state, t)
  local L, W, G = Layout.L, Layout.W, Layout.GAP
  local half = (t.hi == t.lo) and (W / 2) or (L / 2)
  state.arms = {
    R = { edge = { half + G, 0 }, dir = { 1, 0 }, vert = { 0, -1 }, pending = 0 },
    L = { edge = { -half - G, 0 }, dir = { -1, 0 }, vert = { 0, 1 }, pending = 0 },
  }
  -- Opening tile: rules.play sets L = hi, R = lo, so the hi half points -x.
  local yaw = (t.hi == t.lo) and Layout.yawFor({ 0, -1 }) or Layout.yawFor({ -1, 0 })
  return { x = 0, z = 0, yaw = yaw }
end

-- Computes the placement for tile t played on `side` whose open value was `v`,
-- without mutating state. Returns placement {x,z,yaw} and the arm's next state.
function Layout.preview(state, t, side, v)
  local L, W, G = Layout.L, Layout.W, Layout.GAP
  if side == "C" then
    local copy = { arms = nil }
    local p = placeCenter(copy, t)
    return p, copy.arms
  end
  local arm = state.arms[side]
  local outer = (t.hi == v) and t.lo or t.hi
  local isDouble = t.hi == t.lo
  local d = arm.dir
  local next = { edge = arm.edge, dir = arm.dir, vert = arm.vert, after = arm.after, pending = arm.pending }

  if isDouble then
    -- Crosswise, straight ahead, never a corner.
    local center = add(arm.edge, mul(d, W / 2))
    next.edge = add(arm.edge, mul(d, W + G))
    return { x = center[1], z = center[2], yaw = Layout.orientedYaw(t, outer, d) }, next
  end

  local mustTurn = arm.pending > 0
  if not mustTurn and math.abs(d[1]) > 0.5 and along(arm, L) > Layout.BOUND then
    mustTurn = true
    next.pending = 2
    next.after = mul(d, -1)
  end

  if mustTurn then
    -- Corner: the tile runs along d2 and covers the gap of width W in front of the edge.
    local d2 = (next.pending == 2) and arm.vert or next.after
    local center = add(add(arm.edge, mul(d, W / 2)), mul(d2, L / 2 - W / 2))
    next.edge = add(add(arm.edge, mul(d, W / 2)), mul(d2, L - W / 2 + G))
    next.dir = d2
    next.pending = next.pending - 1
    return { x = center[1], z = center[2], yaw = Layout.orientedYaw(t, outer, d2) }, next
  end

  local center = add(arm.edge, mul(d, L / 2))
  next.edge = add(arm.edge, mul(d, L + G))
  return { x = center[1], z = center[2], yaw = Layout.orientedYaw(t, outer, d) }, next
end

-- Commit a placement: mutates state and returns the placement.
function Layout.place(state, t, side, v)
  local p, nextArm = Layout.preview(state, t, side, v)
  if side == "C" then
    state.arms = nextArm
  else
    state.arms[side] = nextArm
  end
  return p
end

-- Serialisable copy (arms only contain numbers).
function Layout.serialize(state) return state end
function Layout.deserialize(data) return data or Layout.new() end

return Layout
