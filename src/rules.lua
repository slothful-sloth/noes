-- rules.lua: pure game rules. No TTS API calls; testable in plain Lua 5.2.
--
-- Conventions
--   tile   = { hi = n, lo = n } with hi >= lo, 0..6
--   key    = "hi-lo" string, e.g. "6-4"
--   seat   = 1..4 in turn order (counter-clockwise); teams: seats 1,3 -> team 1; seats 2,4 -> team 2
--   board  = { count = n, L = v|nil, R = v|nil }  (open end values; nil when empty)
--   hands  = { [seat] = { tile, tile, ... } }
--   ruleset fields: target, forceDoubleSixLead, premios (list), passBonus, capicu, chuchazo

local R = {}

R.SEATS = 4
R.HAND_SIZE = 7

R.RULESETS = {
  pr = {
    id = "pr",
    name = "Puerto Rican rules",
    target = 500,
    forceDoubleSixLead = true,
    premios = { 100, 75, 50, 25 },
    passBonus = 25,
    capicu = 100,
    chuchazo = 100,
    summary = {
      "Game to 500",
      "Series-opening lead must be the 6/6",
      "Premios for winning hands 1-4 of each game: 100 / 75 / 50 / 25",
      "Pass bonus: 25 to the team that made an opponent pass",
      "Capicú: 100   Chuchazo: 100",
    },
  },
  custom = {
    id = "custom",
    name = "Four Horsies",
    target = 300,
    forceDoubleSixLead = false,
    premios = {},
    passBonus = 0,
    capicu = 60,
    chuchazo = 60,
    summary = {
      "Game to 300",
      "Holder of the 6/6 leads the series, with any tile",
      "No premios",
      "No pass bonus",
      "Capicú: 60   Chuchazo: 60",
    },
  },
}

R.COMMON_SUMMARY = {
  "Winner of each hand scores the pips in the other three hands",
  "Tranque: lowest player wins (then fewer tiles, then previous hand's winners) and scores every pip left",
  "Capicú does not count when both ends show the same number",
  "Winner of the previous hand leads the next one",
  "A player dealt 5+ doubles may ask for a redeal",
}

-- Tiles --------------------------------------------------------------------

function R.tile(a, b)
  if a < b then a, b = b, a end
  return { hi = a, lo = b }
end

function R.key(t) return t.hi .. "-" .. t.lo end

function R.parse(k)
  local a, b = string.match(k, "^(%d)-(%d)$")
  if not a then return nil end
  return R.tile(tonumber(a), tonumber(b))
end

function R.pips(t) return t.hi + t.lo end
function R.isDouble(t) return t.hi == t.lo end

function R.allTiles()
  local list = {}
  for hi = 0, 6 do
    for lo = 0, hi do list[#list + 1] = R.tile(hi, lo) end
  end
  return list
end

function R.matches(t, v) return t.hi == v or t.lo == v end

function R.handPips(hand)
  local s = 0
  for _, t in ipairs(hand) do s = s + R.pips(t) end
  return s
end

function R.countDoubles(hand)
  local n = 0
  for _, t in ipairs(hand) do if R.isDouble(t) then n = n + 1 end end
  return n
end

function R.canRequestRedeal(hand) return R.countDoubles(hand) >= 5 end

function R.handHas(hand, k)
  for i, t in ipairs(hand) do if R.key(t) == k then return i end end
  return nil
end

-- Seats and teams ------------------------------------------------------------

function R.teamOf(seat) return ((seat - 1) % 2) + 1 end
function R.nextSeat(seat) return (seat % R.SEATS) + 1 end
function R.prevSeat(seat) return ((seat - 2) % R.SEATS) + 1 end
function R.partnerOf(seat) return ((seat + 1) % R.SEATS) + 1 end

-- Board ----------------------------------------------------------------------

function R.newBoard() return { count = 0, L = nil, R = nil } end

-- Which sides ("C" for the opening tile, else "L"/"R") tile t may be played on.
-- opts.mustLeadKey: when the board is empty, only that tile may be led.
function R.legalSides(board, t, opts)
  if board.count == 0 then
    if opts and opts.mustLeadKey and R.key(t) ~= opts.mustLeadKey then return {} end
    return { "C" }
  end
  local sides = {}
  if R.matches(t, board.L) then sides[#sides + 1] = "L" end
  if R.matches(t, board.R) then sides[#sides + 1] = "R" end
  return sides
end

function R.isLegal(board, t, side, opts)
  for _, s in ipairs(R.legalSides(board, t, opts)) do
    if s == side then return true end
  end
  return false
end

-- All legal moves for a hand: list of { key = k, side = s }
function R.legalMoves(board, hand, opts)
  local moves = {}
  for _, t in ipairs(hand) do
    for _, s in ipairs(R.legalSides(board, t, opts)) do
      moves[#moves + 1] = { key = R.key(t), side = s }
    end
  end
  return moves
end

function R.hasLegalMove(board, hand, opts)
  return #R.legalMoves(board, hand, opts) > 0
end

-- Value of the pip that faces outward after playing t on a side whose open value is v.
function R.outerValue(t, v)
  if t.hi == v then return t.lo end
  return t.hi
end

-- Returns a new board after playing t on side ("C", "L" or "R"). Errors on illegal play.
function R.play(board, t, side)
  local nb = { count = board.count + 1, L = board.L, R = board.R }
  if side == "C" then
    assert(board.count == 0, "C is only valid on an empty board")
    nb.L, nb.R = t.hi, t.lo
  elseif side == "L" then
    assert(board.count > 0 and R.matches(t, board.L), "illegal play on L")
    nb.L = R.outerValue(t, board.L)
  elseif side == "R" then
    assert(board.count > 0 and R.matches(t, board.R), "illegal play on R")
    nb.R = R.outerValue(t, board.R)
  else
    error("bad side " .. tostring(side))
  end
  return nb
end

-- True when no seat can make any move (tranque).
function R.isBlocked(board, hands)
  for seat = 1, R.SEATS do
    if hands[seat] and R.hasLegalMove(board, hands[seat]) then return false end
  end
  return true
end

-- Special endings ------------------------------------------------------------

-- Capicú: the winning tile fits both open ends, and the ends differ.
function R.isCapicu(boardBefore, t)
  if boardBefore.count == 0 then return false end
  local l, r = boardBefore.L, boardBefore.R
  if l == r then return false end
  return (t.hi == l and t.lo == r) or (t.hi == r and t.lo == l)
end

function R.isChuchazo(t) return t.hi == 0 and t.lo == 0 end

-- Premio for winning the n-th hand of a game.
function R.premio(ruleset, handNumberInGame)
  return ruleset.premios[handNumberInGame] or 0
end

-- Scoring --------------------------------------------------------------------

-- Hand ended by `winner` playing their last tile `lastTile` onto `boardBefore`.
-- `hands` are the remaining hands after the play (winner's is empty).
function R.scoreDomino(ruleset, winner, hands, lastTile, boardBefore, handNumberInGame)
  local pips = 0
  for seat = 1, R.SEATS do
    if seat ~= winner then pips = pips + R.handPips(hands[seat]) end
  end
  local kind, bonus = "domino", 0
  if R.isChuchazo(lastTile) then
    kind, bonus = "chuchazo", ruleset.chuchazo
  elseif R.isCapicu(boardBefore, lastTile) then
    kind, bonus = "capicu", ruleset.capicu
  end
  local premio = R.premio(ruleset, handNumberInGame)
  return {
    kind = kind,
    winner = winner,
    team = R.teamOf(winner),
    pips = pips,
    bonus = bonus,
    premio = premio,
    total = pips + bonus + premio,
  }
end

-- Tranque winner: lowest individual pip total; ties -> fewer tiles; ties -> a seat of
-- `fallbackTeam` (team that won the previous hand, or the leader's team in hand 1).
-- Returns winnerSeat, or nil plus the tied team when tied seats are partners with
-- identical totals (any of them may be credited; we return the first).
function R.tranqueWinner(hands, fallbackTeam)
  local best = nil
  for seat = 1, R.SEATS do
    local p, n = R.handPips(hands[seat]), #hands[seat]
    if best == nil or p < best.p or (p == best.p and n < best.n) then
      best = { p = p, n = n, seats = { seat } }
    elseif p == best.p and n == best.n then
      best.seats[#best.seats + 1] = seat
    end
  end
  if #best.seats == 1 then return best.seats[1] end
  -- Several seats tie on pips and tile count.
  local teams = {}
  for _, s in ipairs(best.seats) do teams[R.teamOf(s)] = s end
  if teams[1] and teams[2] then return teams[fallbackTeam] end
  return best.seats[1] -- all tied seats are on the same team
end

function R.scoreTranque(ruleset, hands, fallbackTeam, handNumberInGame)
  local winner = R.tranqueWinner(hands, fallbackTeam)
  local pips = 0
  for seat = 1, R.SEATS do pips = pips + R.handPips(hands[seat]) end
  local premio = R.premio(ruleset, handNumberInGame)
  return {
    kind = "tranque",
    winner = winner,
    team = R.teamOf(winner),
    pips = pips,
    bonus = 0,
    premio = premio,
    total = pips + premio,
  }
end

-- Pass bonus. `lastPlayer` is the seat that placed the most recent tile.
-- Returns team, points; or nil when no bonus applies (no bonus in the rule set,
-- nobody has played yet, or the passer is the last player's partner).
function R.passBonus(ruleset, passer, lastPlayer)
  if (ruleset.passBonus or 0) <= 0 or lastPlayer == nil then return nil end
  if R.teamOf(passer) == R.teamOf(lastPlayer) then return nil end
  return R.teamOf(lastPlayer), ruleset.passBonus
end

-- Series ---------------------------------------------------------------------

function R.gamesNeeded(bestOf) return math.floor(bestOf / 2) + 1 end

-- Returns winning team or nil.
function R.gameWinner(ruleset, scores)
  for team = 1, 2 do
    if scores[team] >= ruleset.target then return team end
  end
  return nil
end

function R.seriesWinner(bestOf, gamesWon)
  local need = R.gamesNeeded(bestOf)
  for team = 1, 2 do
    if gamesWon[team] >= need then return team end
  end
  return nil
end

-- Shuffle helper (rng: function(n) -> 1..n; defaults to math.random)
function R.shuffled(list, rng)
  rng = rng or math.random
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  for i = #out, 2, -1 do
    local j = rng(i)
    out[i], out[j] = out[j], out[i]
  end
  return out
end

return R
