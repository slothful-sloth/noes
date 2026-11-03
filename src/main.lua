-- main.lua: TTS event handlers and XML UI callbacks (globals).
local C = require("config")
local R = require("rules")
local U = require("util")
local Store = require("store")
local Tiles = require("tiles")
local UIx = require("ui")
local Themes = require("themes")
local G = require("game")
local Physical = require("physical")

local function addMenus()
  for _, key in ipairs(Tiles.allKeys()) do
    local o = Tiles.obj(key)
    if o then o.clearContextMenu() end
  end
  for seat = 1, 4 do if S.phase == "sopa" or S.phase == "play" then Tiles.arrangeRack(seat) end end
end
Themes.onTilesReloaded = addMenus

function onLoad(saved)
  math.randomseed(os.time())
  Store.load(saved)
  addMenus()
  Tiles.clearStrays()
  UIx.refreshLobby()
  UIx.refreshScore()
  UIx.refreshHands()
  -- restore phase-specific UI
  UIx.show("sopaPanel", false)
  if S.phase == "sopa" then
    if S.hand.sopaStage == "draw" then Tiles.showZones(true) else G.startStir() end
  end
  if S.phase == "play" then
    for key in pairs(S.hand.revealedHideable or {}) do
      if S.hand.revealed[key] then Tiles.addHideButton(key) end
    end
  end
  if S.phase == "play" then
    G.startTurn()
  elseif S.phase == "lobby" then
    UIx.status("Lobby: choose your seats")
    G.checkStart()
  elseif S.phase == "handover" or S.phase == "gameover" or S.phase == "seriesover" then
    UIx.result("Paused", "Game restored.", S.phase == "seriesover" and "Back to lobby" or "Continue")
  end
end

function onSave() return Store.save() end

function noop() end

-- Players ----------------------------------------------------------------------------------

function onPlayerChangeColor(color)
  local seat = U.seatOf(color)
  if seat and Player[color] and Player[color].seated then
    Player[color].lookAt({ position = { 0, C.TABLE_Y, 0 }, pitch = 55, yaw = C.SEATS[seat].yaw, distance = 40 })
  end
  if S.phase == "lobby" or S.phase == "gameover" then
    G.checkStart()
  else
    UIx.refreshHands()
  end
end

function onPlayerDisconnect(player)
  if S.phase ~= "lobby" and U.seatOf(player.color) then
    U.announce(player.steam_name .. " left. Another player can take the " .. player.color .. " seat to continue.", { 1, 0.6, 0.4 })
  end
end

-- Objects -------------------------------------------------------------------------------------

function onObjectPickUp(color, obj)
  if Physical.info(obj) then return G.pickUpPhysical(color, obj) end
  local key = Tiles.keyOf(obj)
  if key then G.sopaPickUp(color, key, obj) end
end

function onObjectDrop(color, obj)
  if Physical.info(obj) then
    Wait.frames(function()
      if not obj.isDestroyed() and not obj.held_by_color then G.dropPhysical(color, obj) end
    end, 1)
    return
  end
  local key = Tiles.keyOf(obj)
  if key then
    Wait.frames(function() G.drop(color, key, obj) end, 1)
  end
end

function onPlayerAction(player, action, targets)
  for _, obj in ipairs(targets) do
    local info = Physical.info(obj)
    if info then
      if not G.canHandlePhysical(player.color, info) then return false end
      -- Proxies represent existing tiles and must never enter the game as extra pieces.
      if action == Player.Action.Copy or action == Player.Action.Cut
        or action == Player.Action.Delete or action == Player.Action.Group then return false end
    end
  end
  return true
end

function onObjectRotate(obj, spin, flip, color, oldSpin, oldFlip)
  local key = Tiles.keyOf(obj)
  if key then G.onRotate(key, obj, flip, oldFlip) end
end

-- UI callbacks -----------------------------------------------------------------------------------

function uiToggleLobby(player) UIx.toggleLobby(player.color) end
function uiToggleScore(player) UIx.togglePanel("scorePanel", player.color) end
function uiToggleRules(player) UIx.togglePanel("rulesPanel", player.color) end

function uiSeat1(player) G.sit(player, 1) end
function uiSeat2(player) G.sit(player, 2) end
function uiSeat3(player) G.sit(player, 3) end
function uiSeat4(player) G.sit(player, 4) end
function uiStart(player) G.start(player) end
function uiSwap1(player) G.swapSeats(player, 1) end
function uiSwap2(player) G.swapSeats(player, 2) end

function uiTeamName(player, value, id)
  G.setTeamName(player, id == "team1" and 1 or 2, value)
end

function uiRulesPr(player) G.changeSetting(player, "ruleset", "pr") end
function uiRulesCustom(player) G.changeSetting(player, "ruleset", "custom") end
function uiBestOf1(player) G.changeSetting(player, "bestOf", 1) end
function uiBestOf3(player) G.changeSetting(player, "bestOf", 3) end
function uiBestOf5(player) G.changeSetting(player, "bestOf", 5) end

local function cycle(list, current)
  for i, e in ipairs(list) do
    if e.id == current then return list[(i % #list) + 1].id end
  end
  return list[1].id
end

function uiCycleFace(player) G.changeSetting(player, "face", cycle(C.FACES, S.settings.face)) end
function uiCycleBack(player) G.changeSetting(player, "back", cycle(C.BACKS, S.settings.back)) end
function uiCycleTable(player) G.changeSetting(player, "tableFace", cycle(C.TABLE_FACES, S.settings.tableFace)) end
function uiBackUrl(player, value) G.changeSetting(player, "backUrl", value or "") end
function uiTableUrl(player, value) G.changeSetting(player, "tableUrl", value or "") end

function uiDevMode(player)
  if not player.host then return U.tell(player.color, "Only the host can toggle developer mode.") end
  G.changeSetting(player, "dev", not S.settings.dev)
  G.checkStart()
end

function uiShuffle(player) G.shuffle(player) end
function uiDraw7(player) G.draw7(player) end
function uiRedealYes(player) G.answerRedeal(player, true) end
function uiRedealNo(player) G.answerRedeal(player, false) end
function uiHandTile(player, value, id)
  local seat, i = string.match(id, "^h(%d)_t(%d)$")
  seat, i = tonumber(seat), tonumber(i)
  local key = UIx.displayed[seat] and UIx.displayed[seat][i]
  if key then G.selectTile(player.color, seat, key) end
end

function uiHandAct(player, value, id)
  local seat, action = string.match(id, "^h(%d)_(%a+)$")
  G.handAction(player.color, tonumber(seat), action)
end

local pendingConfirm = {}   -- colour -> "round" | "match"

local function askConfirm(player, what, text)
  if not U.seatOf(player.color) and not S.settings.dev and not player.host then
    return U.tell(player.color, "Only seated players can reset.")
  end
  pendingConfirm[player.color] = what
  UI.setValue("confirmText", text)
  UIx.show("confirmPanel", true, player.color)
end

function uiResetRound(player)
  askConfirm(player, "round", "Reset this hand? The tiles are reshuffled and any pass bonuses from this hand are taken back.")
end

function uiResetMatch(player)
  askConfirm(player, "match", "Reset the whole match? All scores and games are cleared and everyone returns to the lobby.")
end

function uiConfirmYes(player)
  local what = pendingConfirm[player.color]
  pendingConfirm[player.color] = nil
  UIx.show("confirmPanel", false)
  if what == "round" then G.resetRound(player) elseif what == "match" then G.resetMatch(player) end
end

function uiConfirmNo(player)
  pendingConfirm[player.color] = nil
  UIx.show("confirmPanel", false)
end

function onRevealedClick(obj, color, altClick)
  local key = Tiles.keyOf(obj)
  if key then G.hideRevealed(color, key) end
end

function uiDevView(player, value, id)
  if not S.settings.dev then return end
  UIx.devView = tonumber(string.match(id, "^dv(%d)$")) or 0
  UIx.refreshHands()
end

function onMarkerClick(obj, color, altClick)
  local ok, info = pcall(JSON.decode, obj.memo or "")
  if ok then G.markerClick(color, info) end
end
function uiResultNext(player) G.resultNext(player) end

-- Developer helpers (call through tools/tts.py exec) -------------------------------------------------

function dev_state()
  local h = S.hand
  local lines = { "phase=" .. S.phase .. " turn=" .. tostring(h.turn) .. " board L=" .. tostring(h.board.L)
    .. " R=" .. tostring(h.board.R) .. " n=" .. h.board.count,
    "scores " .. S.game.scores[1] .. "-" .. S.game.scores[2] .. " handNo=" .. S.game.handNo
    .. " games " .. S.series.games[1] .. "-" .. S.series.games[2] }
  for seat = 1, 4 do lines[#lines + 1] = seat .. ": " .. table.concat(h.hands[seat], " ") end
  print(table.concat(lines, "\n"))
end

-- Deal fixed hands: dev_deal({{"6-6",...}, {...}, {...}, {...}}) during the sopa.
function dev_deal(hands)
  if S.phase ~= "sopa" then return print("dev_deal: only during the sopa") end
  for seat = 1, 4 do
    S.hand.hands[seat] = {}
    for _, k in ipairs(hands[seat]) do S.hand.hands[seat][#S.hand.hands[seat] + 1] = k end
    Tiles.arrangeRack(seat)
  end
  G.checkDealt()
end

-- Play a tile for whoever's turn it is: dev_play("6-4", "L")
function dev_play(key, side)
  local seat = S.hand.turn
  if not U.indexOf(S.hand.hands[seat], key) then return print("seat " .. seat .. " lacks " .. key) end
  G.play(seat, key, side)
end

function dev_pass()
  G.pass({ color = C.SEATS[S.hand.turn].color, steam_name = "dev", host = true })
end
