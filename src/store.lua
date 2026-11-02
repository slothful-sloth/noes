-- store.lua: the single game state table `S` (global), persisted through onSave/onLoad.
local C = require("config")
local R = require("rules")
local Layout = require("layout")

local Store = {}

local function newSettings()
  return {
    ruleset = "pr", bestOf = 3,
    face = "white", back = "pr", backUrl = "",
    tableFace = "felt", tableUrl = "",
    dev = false,
  }
end

function Store.newHand()
  return {
    board = R.newBoard(),
    layout = Layout.new(),
    placed = {},          -- list of { key, side, x, z, yaw }
    hands = { {}, {}, {}, {} },   -- seat -> list of tile keys (rack order)
    revealed = {},        -- key -> true (bluff called: visible to everyone)
    revealedHideable = {},-- key -> true once its owner may turn it back face down
    turn = nil, leader = nil, lastPlayer = nil,
    passBonus = { 0, 0 },
    passes = 0,
    taunt = {},           -- seat -> key currently on the taunt spot
    committed = {},       -- seat -> key
    mustLeadKey = nil,
    sopaStage = "stir",   -- "stir" (cursor stirs, no drawing) then "draw" after the final Shuffle
  }
end

function Store.newGame()
  return { scores = { 0, 0 }, handNo = 0, rows = {} }
end

function Store.new()
  return {
    version = 1,
    phase = "lobby",      -- lobby | sopa | play | handover | gameover | seriesover
    settings = newSettings(),
    teams = { { name = C.TEAM_DEFAULT_NAMES[1] }, { name = C.TEAM_DEFAULT_NAMES[2] } },
    ready = {},           -- seat -> true
    series = { games = { 0, 0 }, gameNo = 1, past = {} },
    game = Store.newGame(),
    hand = Store.newHand(),
    handsPlayed = 0,      -- across the series (first hand => 6/6 lead)
    lastWinnerSeat = nil,
    redealAsked = {},
  }
end

function Store.save() return JSON.encode(S) end

function Store.load(text)
  if text and text ~= "" then
    local ok, data = pcall(JSON.decode, text)
    if ok and type(data) == "table" and data.version == 1 then
      S = data
      Store.fixArrays()
      return true
    end
  end
  S = Store.new()
  return false
end

-- JSON round-trips turn sparse integer-keyed tables into string keys; normalise the ones we index by seat.
local function intKeys(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[tonumber(k) or k] = v end
  return o
end

function Store.fixArrays()
  S.ready = intKeys(S.ready)
  S.redealAsked = intKeys(S.redealAsked)
  local h = S.hand
  h.taunt = intKeys(h.taunt)
  h.committed = intKeys(h.committed)
  h.hands = intKeys(h.hands)
  for seat = 1, 4 do h.hands[seat] = h.hands[seat] or {} end
  h.revealed = h.revealed or {}
  h.revealedHideable = h.revealedHideable or {}
end

return Store
