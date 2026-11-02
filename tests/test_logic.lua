-- Pure-logic tests for rules.lua and layout.lua.
-- Run with: .venv/bin/python tools/run_tests.py   (Lua 5.2 via lupa)
-- Expects `R` (rules) and `Layout` to be provided as globals by the runner.

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. name .. (detail and (" -- " .. tostring(detail)) or ""))
  end
end
local function eq(name, got, want) check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want)) end

local T = R.tile
local function hand(...)
  local h = {}
  for _, k in ipairs({ ... }) do h[#h + 1] = R.parse(k) end
  return h
end

local PR, CU = R.RULESETS.pr, R.RULESETS.custom

-- Tiles ------------------------------------------------------------------------
eq("28 tiles", #R.allTiles(), 28)
eq("tile normalises", R.key(T(2, 5)), "5-2")
eq("parse", R.key(R.parse("6-6")), "6-6")
eq("pips", R.pips(T(6, 4)), 10)
check("double", R.isDouble(T(3, 3)))
eq("set pips 168", R.handPips(R.allTiles()), 168)

-- Seats --------------------------------------------------------------------------
eq("team 1", R.teamOf(1), 1); eq("team 3", R.teamOf(3), 1)
eq("team 2", R.teamOf(2), 2); eq("team 4", R.teamOf(4), 2)
eq("next 4", R.nextSeat(4), 1); eq("prev 1", R.prevSeat(1), 4)
eq("partner 1", R.partnerOf(1), 3); eq("partner 4", R.partnerOf(4), 2)

-- Legality -----------------------------------------------------------------------
local b = R.newBoard()
eq("forced 6-6 lead blocks others", #R.legalSides(b, T(5, 5), { mustLeadKey = "6-6" }), 0)
eq("forced 6-6 lead allows 6-6", R.legalSides(b, T(6, 6), { mustLeadKey = "6-6" })[1], "C")
b = R.play(b, T(6, 4), "C")
eq("open L", b.L, 6); eq("open R", b.R, 4)
local s = R.legalSides(b, T(6, 4))
eq("both sides", #s, 2)
b = R.play(b, T(4, 1), "R")
eq("R becomes 1", b.R, 1)
check("illegal detected", not R.isLegal(b, T(3, 2), "L"))
local ok = pcall(R.play, b, T(3, 2), "L")
check("illegal play errors", not ok)
eq("legal moves", #R.legalMoves(b, hand("6-2", "1-0", "3-3")), 2)

-- Capicú / chuchazo ----------------------------------------------------------------
check("capicu", R.isCapicu({ count = 5, L = 3, R = 5 }, T(5, 3)))
check("no capicu equal ends", not R.isCapicu({ count = 5, L = 3, R = 3 }, T(3, 3)))
check("no capicu one end", not R.isCapicu({ count = 5, L = 3, R = 5 }, T(5, 1)))
check("chuchazo", R.isChuchazo(T(0, 0)))

local function emptyHandsExcept(winner, others)
  local h = {}
  for seat = 1, 4 do h[seat] = (seat == winner) and {} or others[seat] end
  return h
end
local hs = emptyHandsExcept(1, { [2] = hand("6-6"), [3] = hand("1-0"), [4] = hand("2-2", "3-1") })

local sc = R.scoreDomino(PR, 1, hs, T(5, 2), { count = 20, L = 5, R = 1 }, 1)
eq("domino pips all 3 hands", sc.pips, 12 + 1 + 4 + 4)
eq("domino kind", sc.kind, "domino")
eq("premio hand 1", sc.premio, 100)
eq("domino total", sc.total, 21 + 100)

sc = R.scoreDomino(PR, 3, emptyHandsExcept(3, { [1] = hand("1-1"), [2] = hand("2-0"), [4] = {} }), T(5, 2), { count = 20, L = 5, R = 2 }, 5)
eq("capicu kind", sc.kind, "capicu"); eq("capicu bonus", sc.bonus, 100)
eq("no premio hand 5", sc.premio, 0); eq("capicu total", sc.total, 4 + 100)
eq("capicu team", sc.team, 1)

sc = R.scoreDomino(CU, 2, emptyHandsExcept(2, { [1] = hand("1-1"), [3] = {}, [4] = {} }), T(0, 0), { count = 20, L = 0, R = 4 }, 1)
eq("chuchazo kind", sc.kind, "chuchazo"); eq("custom chuchazo 60", sc.bonus, 60)
eq("custom no premio", sc.premio, 0); eq("chuchazo total", sc.total, 62)

eq("premio 2", R.premio(PR, 2), 75); eq("premio 3", R.premio(PR, 3), 50); eq("premio 4", R.premio(PR, 4), 25)

-- Tranque ------------------------------------------------------------------------------
local th = { hand("6-6"), hand("1-0", "2-0"), hand("5-5"), hand("4-4") }
eq("tranque lowest", R.tranqueWinner(th, 1), 2)
th = { hand("2-1"), hand("1-0", "2-0"), hand("5-5"), hand("4-4") }
eq("tranque tie fewer tiles", R.tranqueWinner(th, 2), 1)
th = { hand("2-1"), hand("3-0"), hand("5-5"), hand("4-4") }
eq("tranque full tie -> fallback team 2", R.tranqueWinner(th, 2), 2)
eq("tranque full tie -> fallback team 1", R.tranqueWinner(th, 1), 1)
th = { hand("2-1"), hand("6-6"), hand("3-0"), hand("4-4") }
eq("tranque partners tie", R.teamOf(R.tranqueWinner(th, 2)), 1)

sc = R.scoreTranque(PR, { hand("6-6"), hand("1-0"), hand("5-5"), hand("4-4") }, 1, 3)
eq("tranque scores all pips", sc.pips, 12 + 1 + 10 + 8)
eq("tranque premio", sc.premio, 50)
eq("tranque winner", sc.winner, 2)

-- Blocked detection --------------------------------------------------------------------
check("blocked", R.isBlocked({ count = 20, L = 3, R = 3 }, { hand("6-6"), hand("1-0"), hand("5-5"), hand("4-4") }))
check("not blocked", not R.isBlocked({ count = 20, L = 3, R = 1 }, { hand("6-6"), hand("1-0"), hand("5-5"), hand("4-4") }))

-- Pass bonus -----------------------------------------------------------------------------
local team, pts = R.passBonus(PR, 2, 1)
eq("pass bonus team", team, 1); eq("pass bonus pts", pts, 25)
check("no bonus for partner pass", R.passBonus(PR, 3, 1) == nil)
check("no bonus custom", R.passBonus(CU, 2, 1) == nil)
check("no bonus before any play", R.passBonus(PR, 2, nil) == nil)

-- Games and series -------------------------------------------------------------------------
eq("game winner", R.gameWinner(PR, { 510, 200 }), 1)
check("no game winner", R.gameWinner(PR, { 499, 200 }) == nil)
eq("custom target", R.gameWinner(CU, { 0, 300 }), 2)
eq("bo3 needs 2", R.gamesNeeded(3), 2); eq("bo5 needs 3", R.gamesNeeded(5), 3); eq("bo1 needs 1", R.gamesNeeded(1), 1)
eq("series winner", R.seriesWinner(3, { 1, 2 }), 2)
check("series open", R.seriesWinner(5, { 2, 2 }) == nil)

-- Redeal ------------------------------------------------------------------------------------
check("redeal 5 doubles", R.canRequestRedeal(hand("0-0", "1-1", "2-2", "3-3", "4-4", "6-1", "5-2")))
check("no redeal 4 doubles", not R.canRequestRedeal(hand("0-0", "1-1", "2-2", "3-3", "6-4", "6-1", "5-2")))

-- Shuffle ------------------------------------------------------------------------------------
local sh = R.shuffled(R.allTiles())
eq("shuffle keeps size", #sh, 28)
eq("shuffle keeps pips", R.handPips(sh), 168)

-- Layout ----------------------------------------------------------------------------------------
-- Orientation: a non-double's yaw maps local +X (hi half) to the outer direction.
local function dirOfYaw(yaw)
  local r = math.rad(yaw)
  return math.cos(r), -math.sin(r)
end

local st = Layout.new()
local p = Layout.place(st, T(6, 4), "C")
local dx = dirOfYaw(p.yaw)
check("opening hi points -x (L)", dx < -0.99, p.yaw)

-- Rectangles for overlap checks: footprint of a placement.
local function rect(pl, t)
  local dxx, dzz = dirOfYaw(pl.yaw)
  local hx, hz
  if math.abs(dxx) > 0.5 then hx, hz = Layout.L / 2, Layout.W / 2 else hx, hz = Layout.W / 2, Layout.L / 2 end
  return { pl.x - hx, pl.z - hz, pl.x + hx, pl.z + hz }
end
local function overlaps(a, b2)
  local eps = 0.01
  return a[1] < b2[3] - eps and b2[1] < a[3] - eps and a[2] < b2[4] - eps and b2[2] < a[4] - eps
end

-- Simulate many random full games of placements (ignoring rules except matching) and ensure
-- no overlaps and everything stays inside the board square.
math.randomseed(12345)
local maxExtent = 0
for trial = 1, 400 do
  local tiles = R.shuffled(R.allTiles())
  local board = R.newBoard()
  local lst = Layout.new()
  local rects = {}
  local remaining = tiles
  local first = table.remove(remaining, 1)
  local pl = Layout.place(lst, first, "C")
  board = R.play(board, first, "C")
  rects[#rects + 1] = rect(pl, first)
  local progress = true
  while progress do
    progress = false
    for i, t in ipairs(remaining) do
      local sides = R.legalSides(board, t)
      if #sides > 0 then
        local side = sides[math.random(#sides)]
        local v = board[side]
        local pp = Layout.place(lst, t, side, v)
        -- orientation check: the matching value must face the chain.
        if t.hi ~= t.lo then
          local ddx, ddz = dirOfYaw(pp.yaw)
          local outer = R.outerValue(t, v)
          local arm = lst.arms[side]
          -- after placement, arm.dir is the direction the tile was laid along
          local sign = ddx * arm.dir[1] + ddz * arm.dir[2]
          if outer == t.hi then
            check("hi outward t" .. trial, sign > 0.99, R.key(t))
          else
            check("lo outward t" .. trial, sign < -0.99, R.key(t))
          end
        end
        local r = rect(pp, t)
        for _, other in ipairs(rects) do
          if overlaps(r, other) then
            check("no overlap t" .. trial .. " " .. R.key(t), false)
            break
          end
        end
        rects[#rects + 1] = r
        for _, c in ipairs(r) do maxExtent = math.max(maxExtent, math.abs(c)) end
        board = R.play(board, t, side)
        table.remove(remaining, i)
        progress = true
        break
      end
    end
  end
end
check("layout stays within 14 units", maxExtent <= 14.0, maxExtent)
print(string.format("layout max extent: %.2f", maxExtent))

print(string.format("%d passed, %d failed", passed, failed))
return failed
