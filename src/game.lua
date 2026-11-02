-- game.lua: lobby, sopa/draw, turns, passing, taunts, scoring and series flow.
local C = require("config")
local R = require("rules")
local Layout = require("layout")
local U = require("util")
local Store = require("store")
local Tiles = require("tiles")
local UIx = require("ui")
local Sound = require("sound")
local Themes = require("themes")

local G = {}

local startToken = 0
local spinToken = {}      -- seat -> token of the running spin animation

local function rs() return R.RULESETS[S.settings.ruleset] end

local function handTiles(seat)
  local list = {}
  for _, k in ipairs(S.hand.hands[seat]) do list[#list + 1] = R.parse(k) end
  return list
end

local function allHandTiles()
  return { handTiles(1), handTiles(2), handTiles(3), handTiles(4) }
end

function G.ownerOf(key)
  for seat = 1, 4 do
    if U.indexOf(S.hand.hands[seat], key) then return seat end
  end
  return nil
end

local function isPlaced(key)
  for _, p in ipairs(S.hand.placed) do if p.key == key then return true end end
  return false
end

function G.canControl(color, seat)
  if S.settings.dev then return Player[color] ~= nil end
  return U.seatOf(color) == seat
end

local function legalOpts()
  if S.hand.board.count == 0 and S.hand.mustLeadKey then return { mustLeadKey = S.hand.mustLeadKey } end
  return nil
end

local function seatLabel(seat)
  return U.nameAt(seat) .. " (" .. U.teamName(R.teamOf(seat)) .. ")"
end

-- Lobby ----------------------------------------------------------------------------------

function G.sit(player, seat)
  if S.phase ~= "lobby" then return U.tell(player.color, "Seats are locked during a game. Partners can swap between games.") end
  local color = C.SEATS[seat].color
  if player.color == color then
    player.changeColor("Grey")      -- clicking your own seat stands you up
    return
  end
  if Player[color].seated then return U.tell(player.color, "That seat is taken.") end
  player.changeColor(color)
end

-- Between games of a series, partners may swap seats.
function G.swapSeats(player, team)
  if S.phase ~= "gameover" then return end
  if not S.settings.dev then
    local mine = U.seatOf(player.color)
    if not mine or R.teamOf(mine) ~= team then
      return U.tell(player.color, "Only " .. U.teamName(team) .. " can swap their seats.")
    end
  end
  local a, b = (team == 1) and 1 or 2, (team == 1) and 3 or 4
  local ca, cb = C.SEATS[a].color, C.SEATS[b].color
  local pa, pb = U.playerAt(a), U.playerAt(b)
  if S.lastWinnerSeat == a then S.lastWinnerSeat = b elseif S.lastWinnerSeat == b then S.lastWinnerSeat = a end
  local idA = pa and pa.steam_id
  local function findById(id)
    for _, p in ipairs(Player.getPlayers()) do if p.steam_id == id then return p end end
    for _, p in ipairs(Player.getSpectators()) do if p.steam_id == id then return p end end
  end
  if pa then pa.changeColor("Grey") end
  Wait.frames(function()
    if pb then pb.changeColor(ca) end
    Wait.frames(function()
      local p = idA and findById(idA)
      if p then p.changeColor(cb) end
      Wait.frames(function() UIx.refreshLobby() end, 5)
    end, 10)
  end, 10)
  U.announce(U.teamName(team) .. " swap seats.", C.TEAM_RGB[team])
end

function G.setTeamName(player, team, value)
  if S.phase ~= "lobby" and S.phase ~= "seriesover" then
    UIx.refreshLobby()
    return
  end
  local seat = U.seatOf(player.color)
  if not S.settings.dev and (seat == nil or R.teamOf(seat) ~= team) then
    U.tell(player.color, "Only members of that team can rename it.")
    UIx.refreshLobby()
    return
  end
  value = (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if value == "" then value = C.TEAM_DEFAULT_NAMES[team] end
  S.teams[team].name = value
  UIx.refreshLobby()
  UIx.refreshScore()
end

function G.changeSetting(player, field, value)
  if S.phase ~= "lobby" then return U.tell(player.color, "Settings are locked once the series starts.") end
  if not U.seatOf(player.color) and not S.settings.dev and not player.host then
    return U.tell(player.color, "Take a seat to change settings.")
  end
  S.settings[field] = value
  if field == "face" or field == "back" or field == "backUrl" then Themes.applyTiles() end
  if field == "tableFace" or field == "tableUrl" then Themes.applyTable() end
  UIx.refreshLobby()
  UIx.refreshScore()
end

function G.checkStart()
  UIx.refreshLobby()
  if S.phase ~= "lobby" then return end
  if UIx.canStart then
    UIx.lobbyStatus(S.settings.dev and "Developer mode: press ¡A jugar! to start" or "Everyone's seated. Press ¡A jugar!")
  else
    UIx.lobbyStatus(string.format("%d of 4 seated", UIx.seatedCount or 0))
  end
end

function G.start(player)
  if S.phase ~= "lobby" then return end
  if not U.seatOf(player.color) and not player.host then return U.tell(player.color, "Take a seat first.") end
  G.checkStart()
  if not UIx.canStart then return U.tell(player.color, "All four seats must be filled.") end
  G.startSeries()
end

function G.startSeries()
  S.series = { games = { 0, 0 }, gameNo = 1, past = {} }
  S.game = Store.newGame()
  S.handsPlayed = 0
  S.lastWinnerSeat = nil
  U.announce("The series begins: " .. U.teamName(1) .. " vs " .. U.teamName(2) .. " · best of " .. S.settings.bestOf
    .. " · " .. rs().name, { 1, 0.85, 0.5 })
  G.startHand()
end

-- Sopa and draw ---------------------------------------------------------------------------

function G.startHand()
  for seat = 1, 4 do spinToken[seat] = (spinToken[seat] or 0) + 1 end
  Tiles.clearMarkers()
  S.hand = Store.newHand()
  S.redealAsked = {}
  S.phase = "sopa"
  UIx.hideResult()
  G.selected = {}
  UIx.show("redealPanel", false)
  UIx.refreshLobbyVisibility()
  Tiles.scatter(Tiles.allKeys())
  G.startStir()
  UIx.refreshHands()
  UIx.status(string.format("Game %d · hand %d · la sopa", S.series.gameNo, S.game.handNo + 1))
  UIx.refreshScore()
end

-- First hand of the series: anyone may shuffle. Afterwards only the team that lost the last hand.
function G.canShuffle(color)
  if S.settings.dev then return Player[color] ~= nil end
  local seat = U.seatOf(color)
  if not seat then return false end
  if S.handsPlayed == 0 or not S.lastWinnerSeat then return true end
  return R.teamOf(seat) ~= R.teamOf(S.lastWinnerSeat)
end

local stirToken = 0
function G.startStir()
  stirToken = stirToken + 1
  local my = stirToken
  Tiles.resetStir()
  local function free(key) return not G.ownerOf(key) end
  local function loop()
    if my ~= stirToken or S.phase ~= "sopa" or S.hand.sopaStage ~= "stir" then return end
    Tiles.stirStep(0.1, free, G.canShuffle)
    Wait.time(loop, 0.1)
  end
  Wait.time(loop, 1.0)   -- let the scatter animation settle first
end

function G.shuffle(player)
  if S.phase ~= "sopa" then return end
  if not G.canShuffle(player.color) then
    return U.tell(player.color, "Only the team that lost the last hand shuffles.")
  end
  if S.hand.sopaStage ~= "stir" then return end
  local free = {}
  for _, k in ipairs(Tiles.allKeys()) do if not G.ownerOf(k) then free[#free + 1] = k end end
  Tiles.scatter(free)
  S.hand.sopaStage = "draw"
  stirToken = stirToken + 1
  Tiles.showZones(true)
  U.announce(player.steam_name .. " shuffles. Draw your tiles!", { 1, 0.85, 0.5 })
  UIx.status(string.format("Game %d · hand %d · la sopa: draw 7", S.series.gameNo, S.game.handNo + 1))
  UIx.refreshHands()
end

local function drawFor(seat, n)
  local free = {}
  for _, k in ipairs(Tiles.allKeys()) do if not G.ownerOf(k) then free[#free + 1] = k end end
  free = R.shuffled(free)
  local hand = S.hand.hands[seat]
  local i = 1
  while #hand < n and free[i] do
    hand[#hand + 1] = free[i]
    i = i + 1
  end
  Tiles.arrangeRack(seat)
  Tiles.zoneLabel(seat)
  UIx.refreshHands()
end

function G.draw7(player)
  if S.phase ~= "sopa" then return end
  if S.hand.sopaStage ~= "draw" then return U.tell(player.color, "Wait for the sopa to be shuffled.") end
  if S.settings.dev then
    for seat = 1, 4 do drawFor(seat, R.HAND_SIZE) end
  else
    local seat = U.seatOf(player.color)
    if not seat then return U.tell(player.color, "Take a seat first.") end
    drawFor(seat, R.HAND_SIZE)
  end
  G.checkDealt()
end

-- A face-down tile dropped into a seat's area during the sopa is drawn by that seat.
-- During the draw, only seated players who still need tiles may take loose tiles.
function G.mayTakeTile(color)
  if S.settings.dev then return true end
  local seat = U.seatOf(color)
  return seat ~= nil and #S.hand.hands[seat] < R.HAND_SIZE
end

function G.sopaPickUp(color, key, obj)
  if S.phase ~= "sopa" or S.hand.sopaStage ~= "draw" or G.ownerOf(key) then return end
  if not G.mayTakeTile(color) then
    U.tell(color, U.seatOf(color) and "You already have 7 tiles." or "Take a seat to draw tiles.", { 1, 0.6, 0.4 })
  end
end

function G.sopaDrop(color, key, obj)
  if S.hand.sopaStage ~= "draw" then return end   -- while stirring, tiles are just moved around
  local owner = G.ownerOf(key)
  if not owner and not G.mayTakeTile(color) then
    Tiles.scatter({ key })                        -- back into the sopa
    return
  end
  local p = obj.getPosition()
  local seat = U.seatArea(p)
  if owner then
    Tiles.arrangeRack(owner)   -- already drawn: it stays in its owner's row
    return
  end
  if seat and G.canControl(color, seat) then
    if #S.hand.hands[seat] >= R.HAND_SIZE then
      U.tell(color, "You already have 7 tiles.")
      Tiles.scatter({ key })
      return
    end
    S.hand.hands[seat][#S.hand.hands[seat] + 1] = key
    Tiles.arrangeRack(seat)
    Tiles.zoneLabel(seat)
    UIx.refreshHands()
    G.checkDealt()
  end
end

function G.checkDealt()
  for seat = 1, 4 do
    if #S.hand.hands[seat] < R.HAND_SIZE then
      local waiting = {}
      for s = 1, 4 do if #S.hand.hands[s] < R.HAND_SIZE then waiting[#waiting + 1] = U.nameAt(s) end end
      UIx.status("La sopa · waiting for: " .. table.concat(waiting, ", "))
      return
    end
  end
  Tiles.showZones(false)
  -- Redeal offers
  for seat = 1, 4 do
    if not S.redealAsked[seat] and R.canRequestRedeal(handTiles(seat)) then
      S.redealAsked[seat] = "asking"
      S.redealSeat = seat
      UIx.show("redealPanel", true, (not S.settings.dev) and C.SEATS[seat].color or nil)
      UIx.status(U.nameAt(seat) .. " may ask for a redeal…")
      return
    end
  end
  G.beginPlay()
end

function G.answerRedeal(player, yes)
  local seat = S.redealSeat
  if S.phase ~= "sopa" or not seat or S.redealAsked[seat] ~= "asking" then return end
  if not G.canControl(player.color, seat) then return end
  UIx.show("redealPanel", false)
  if yes then
    U.announce(U.nameAt(seat) .. " had 5+ doubles and asked for a redeal.", { 1, 0.85, 0.5 })
    G.startHand()
  else
    S.redealAsked[seat] = "no"
    G.checkDealt()
  end
end

-- Turns ----------------------------------------------------------------------------------------

function G.beginPlay()
  S.phase = "play"
  local leader
  if S.handsPlayed == 0 then
    for seat = 1, 4 do if U.indexOf(S.hand.hands[seat], "6-6") then leader = seat end end
    if rs().forceDoubleSixLead then S.hand.mustLeadKey = "6-6" end
  else
    leader = S.lastWinnerSeat or 1
  end
  S.hand.leader, S.hand.turn = leader, leader
  local msg = seatLabel(leader) .. " leads"
  if S.hand.mustLeadKey then msg = msg .. " with the 6|6" end
  U.announce(msg .. ".", { 1, 0.85, 0.5 })
  G.startTurn()
end

local function returnTaunt(seat)
  local key = S.hand.taunt[seat]
  if not key then return nil end
  spinToken[seat] = (spinToken[seat] or 0) + 1
  S.hand.taunt[seat] = nil
  return key
end

function G.startTurn()
  local h = S.hand
  local seat = h.turn
  local color = C.SEATS[seat].color
  Tiles.clearMarkers()

  -- Taunt tile comes home; a commitment is checked now.
  local tauntKey = returnTaunt(seat)
  local committed = h.committed[seat]
  if committed then
    if #R.legalSides(h.board, R.parse(committed), legalOpts()) > 0 then
      U.tell(color, "You committed to the " .. committed:gsub("-", "|") .. ". It fits, so you must play it.")
    else
      h.revealed[committed] = true
      h.committed[seat] = nil
      local key, myHand = committed, h
      Wait.time(function()
        if S.hand == myHand and S.phase == "play" and myHand.revealed[key] then
          myHand.revealedHideable = myHand.revealedHideable or {}
          myHand.revealedHideable[key] = true
          Tiles.addHideButton(key)
        end
      end, 3)
      UIx.banner("Bluff called!", 3, "#ff7a6b")
      U.announce(U.nameAt(seat) .. " committed to the " .. committed:gsub("-", "|") .. " and it doesn't fit!", { 1, 0.5, 0.4 })
      Sound.play("slam")
    end
  end
  if tauntKey or committed then Tiles.arrangeRack(seat) end

  UIx.status(string.format("Game %d · hand %d · %s to play", S.series.gameNo, S.game.handNo + 1, seatLabel(seat)))
  if h.committed[seat] then
    G.selected[seat] = h.committed[seat]
  elseif G.selected[seat] and not U.indexOf(h.hands[seat], G.selected[seat]) then
    G.selected[seat] = nil
  end
  if R.hasLegalMove(h.board, handTiles(seat), legalOpts()) then
    U.tell(color, "Your turn.", { 0.6, 1, 0.6 })
    if G.selected[seat] and #R.legalSides(h.board, R.parse(G.selected[seat]), legalOpts()) > 0 then
      G.showMarkersFor(seat, G.selected[seat])
    end
  else
    U.tell(color, "You have no legal moves. Press ¡Paso!", { 1, 0.7, 0.4 })
  end
  UIx.refreshHands()
  UIx.refreshScore()
end

-- Hand panel: selecting tiles and acting ------------------------------------------------------

G.selected = {}   -- seat -> key currently selected in that seat's panel

function G.showMarkersFor(seat, key)
  Tiles.clearMarkers()
  local h = S.hand
  local color = C.SEATS[seat].color
  local t = R.parse(key)
  for _, side in ipairs(R.legalSides(h.board, t, legalOpts())) do
    local p = Layout.preview(h.layout, t, side, h.board[side])
    Tiles.spawnMarker(color, p, "ok", { key = key, side = side })
  end
end

function G.selectTile(color, seat, key)
  if S.phase ~= "play" or not G.canControl(color, seat) then return end
  local h = S.hand
  if not U.indexOf(h.hands[seat], key) then return end
  if G.selected[seat] == key then G.selected[seat] = nil else G.selected[seat] = key end
  if seat == h.turn then
    Tiles.clearMarkers()
    local sel = G.selected[seat]
    if sel then
      if h.committed[seat] and h.committed[seat] ~= sel then
        U.tell(color, "You committed to the " .. h.committed[seat]:gsub("-", "|") .. ". Play that one.")
      elseif #R.legalSides(h.board, R.parse(sel), legalOpts()) == 0 then
        local m = h.mustLeadKey and (" You must lead the " .. h.mustLeadKey:gsub("-", "|") .. ".") or ""
        U.tell(color, "The " .. sel:gsub("-", "|") .. " doesn't fit." .. m, { 1, 0.45, 0.4 })
      else
        G.showMarkersFor(seat, sel)
      end
    end
  end
  UIx.refreshHands()
end

-- Play the selected tile on a side (from the panel buttons or a board marker).
function G.playSelected(color, seat, side)
  local h = S.hand
  local key = G.selected[seat]
  if S.phase ~= "play" or seat ~= h.turn or not key or not G.canControl(color, seat) then return end
  if h.committed[seat] and h.committed[seat] ~= key then
    return U.tell(color, "You committed to the " .. h.committed[seat]:gsub("-", "|") .. ". Play that one.")
  end
  if not R.isLegal(h.board, R.parse(key), side, legalOpts()) then
    return U.tell(color, "The " .. key:gsub("-", "|") .. " doesn't fit there.", { 1, 0.45, 0.4 })
  end
  G.play(seat, key, side)
end

function G.markerClick(color, info)
  if not info or S.phase ~= "play" then return end
  local seat = S.hand.turn
  if G.ownerOf(info.key) ~= seat or not G.canControl(color, seat) then return end
  G.selected[seat] = info.key
  G.playSelected(color, seat, info.side)
end

function G.handAction(color, seat, action)
  if (S.phase ~= "play" and S.phase ~= "sopa") or not G.canControl(color, seat) then return end
  local h = S.hand
  if action == "lead" then return G.playSelected(color, seat, "C") end
  if action == "left" then return G.playSelected(color, seat, "L") end
  if action == "right" then return G.playSelected(color, seat, "R") end
  if action == "pass" then return G.pass({ color = color, steam_name = U.nameAt(seat) }) end
  if action == "shuffle" then return G.shuffle({ color = color, steam_name = U.nameAt(seat) }) end
  if action == "draw" then
    if S.phase ~= "sopa" or S.hand.sopaStage ~= "draw" then return end
    drawFor(seat, R.HAND_SIZE)
    return G.checkDealt()
  end
  if action == "spin" then
    local key = G.selected[seat]
    if seat == h.turn then return U.tell(color, "It's your turn. Just play!") end
    if not key then return U.tell(color, "Select a tile to spin first.") end
    G.startTaunt(seat, key)
  elseif action == "commit" or action == "back" then
    local key = h.taunt[seat]
    if key then G.tauntMenu(action, color, Tiles.obj(key)) end
  end
  UIx.refreshHands()
end

-- What a seat's hand panel shows: { tiles = sorted keys, selected, info, actions = {name = label|nil} }
local function sortedHand(seat)
  local list = {}
  for _, k in ipairs(S.hand.hands[seat]) do list[#list + 1] = k end
  table.sort(list, function(a, b)
    local ta, tb = R.parse(a), R.parse(b)
    if ta.hi ~= tb.hi then return ta.hi > tb.hi end
    return ta.lo > tb.lo
  end)
  return list
end

function G.handView(seat)
  local h = S.hand
  local v = { tiles = sortedHand(seat), selected = G.selected[seat], actions = {} }
  if S.phase == "sopa" then
    local n = #h.hands[seat]
    local shuf = G.canShuffle(C.SEATS[seat].color)
    if h.sopaStage == "stir" then
      if shuf then
        v.info = "La sopa · sweep your cursor over the tiles to stir them. Click Shuffle when done."
        v.actions.shuffle = "Shuffle"
      else
        v.info = "La sopa · the other team is stirring…"
      end
    elseif n >= 7 then
      v.info = "La sopa · you have 7. Waiting for the others."
    else
      v.info = string.format("La sopa · drag tiles into your rack, or draw (%d/7).", n)
      v.actions.draw = (n == 0) and "Draw 7" or "Draw the rest"
    end
    return v
  end
  if S.phase ~= "play" then
    v.info = "Hand over"
    return v
  end
  local sel = G.selected[seat]
  local ends = (h.board.count > 0) and string.format("  ·  Ends: %d and %d", h.board.L, h.board.R) or ""
  if seat == h.turn then
    if not R.hasLegalMove(h.board, handTiles(seat), legalOpts()) then
      v.info = "No legal moves." .. ends
      v.actions.pass = "¡Paso!"
    elseif h.committed[seat] then
      v.info = "You committed to the " .. h.committed[seat]:gsub("-", "|") .. ". Play it." .. ends
    elseif not sel then
      v.info = "Your turn: pick a tile." .. ends
    end
    if sel and #R.legalSides(h.board, R.parse(sel), legalOpts()) == 0 then v.selectedBad = true end
    if sel and R.hasLegalMove(h.board, handTiles(seat), legalOpts()) then
      local sides = R.legalSides(h.board, R.parse(sel), legalOpts())
      if #sides == 0 then
        v.selectedBad = true
        v.info = "The " .. sel:gsub("-", "|") .. " doesn't fit." .. ends
      else
        v.info = v.info or ("Play the " .. sel:gsub("-", "|") .. ": click a green spot or a button." .. ends)
        for _, sd in ipairs(sides) do
          if sd == "C" then v.actions.lead = "Lead the " .. sel:gsub("-", "|") end
          if sd == "L" then v.actions.left = "Play on the " .. h.board.L .. " (left)" end
          if sd == "R" then v.actions.right = "Play on the " .. h.board.R .. " (right)" end
        end
      end
    end
  else
    v.info = "Waiting for " .. U.nameAt(h.turn) .. "." .. ends
    if h.taunt[seat] then
      if h.committed[seat] then
        v.info = "Committed to your spinning tile. ¡Va!" .. ends
      else
        v.actions.commit = "Commit ¡Va!"
        v.actions.back = "Take it back"
      end
      v.actions.spin = sel and sel ~= h.taunt[seat] and not h.committed[seat] and "Spin this one instead" or nil
    elseif sel then
      v.actions.spin = "Spin it (taunt)"
    end
  end
  return v
end
UIx.handView = G.handView

function G.hideRevealed(color, key)
  local h = S.hand
  local owner = G.ownerOf(key)
  if S.phase ~= "play" or not owner or not h.revealed[key] then return end
  if not G.canControl(color, owner) then return U.tell(color, "Only " .. U.nameAt(owner) .. " can hide that tile.") end
  h.revealed[key] = nil
  if h.revealedHideable then h.revealedHideable[key] = nil end
  local o = Tiles.obj(key)
  if o then o.clearButtons() end
  Tiles.arrangeRack(owner)
end

-- Resets (confirmed through a prompt) ----------------------------------------------------------

function G.resetRound(player)
  if S.phase ~= "sopa" and S.phase ~= "play" then
    return U.tell(player.color, "There is no hand in progress to reset.")
  end
  for team = 1, 2 do S.game.scores[team] = S.game.scores[team] - (S.hand.passBonus[team] or 0) end
  U.announce(player.steam_name .. " reset the hand. Reshuffling…", { 1, 0.7, 0.4 })
  G.startHand()
end

function G.resetMatch(player)
  if S.phase == "lobby" then return end
  for seat = 1, 4 do spinToken[seat] = (spinToken[seat] or 0) + 1 end
  Tiles.clearMarkers()
  S.phase = "lobby"
  S.ready = {}
  S.series = { games = { 0, 0 }, gameNo = 1, past = {} }
  S.game = Store.newGame()
  S.hand = Store.newHand()
  S.handsPlayed = 0
  S.lastWinnerSeat = nil
  G.selected = {}
  UIx.hideResult()
  UIx.show("redealPanel", false)
  Tiles.showZones(false)
  Tiles.scatter(Tiles.allKeys())
  U.announce(player.steam_name .. " reset the match. Back to the lobby.", { 1, 0.7, 0.4 })
  UIx.status("Lobby: choose your seats")
  UIx.refreshLobby()
  UIx.refreshHands()
  UIx.refreshScore()
  G.checkStart()
end

-- Sopa: tiles are handled physically only while drawing.
function G.drop(color, key, obj)
  if S.phase == "sopa" then return G.sopaDrop(color, key, obj) end
end

function G.play(seat, key, side)
  local h = S.hand
  local t = R.parse(key)
  if not R.isLegal(h.board, t, side, legalOpts()) then return end
  local before = { count = h.board.count, L = h.board.L, R = h.board.R }
  local p = Layout.place(h.layout, t, side, h.board[side])
  h.board = R.play(h.board, t, side)
  U.removeValue(h.hands[seat], key)
  h.placed[#h.placed + 1] = { key = key, side = side, x = p.x, z = p.z, yaw = p.yaw }
  h.revealed[key] = nil
  h.committed[seat] = nil
  h.lastPlayer = seat
  h.mustLeadKey = nil
  G.selected[seat] = nil
  Tiles.clearMarkers()
  Tiles.placeOnBoard(key, p)
  Tiles.arrangeRack(seat)

  if #h.hands[seat] == 0 then
    return G.endDomino(seat, t, before)
  end
  if R.isBlocked(h.board, allHandTiles()) then
    return G.endTranque()
  end
  h.turn = R.nextSeat(seat)
  G.startTurn()
end

function G.pass(player)
  if S.phase ~= "play" then return end
  local h = S.hand
  local seat = h.turn
  if not G.canControl(player.color, seat) then return end
  if R.hasLegalMove(h.board, handTiles(seat), legalOpts()) then
    return U.tell(player.color, "You have a legal move, so you can't pass.")
  end
  Sound.play("knock")
  U.announce(U.nameAt(seat) .. ": ¡Paso!", { 0.9, 0.9, 0.9 })
  UIx.banner("¡Paso!", 1.5, "#d9d2c3")
  h.passes = h.passes + 1
  local team, pts = R.passBonus(rs(), seat, h.lastPlayer)
  if team then
    S.game.scores[team] = S.game.scores[team] + pts
    h.passBonus[team] = h.passBonus[team] + pts
    U.announce(string.format("+%d to %s for the pase", pts, U.teamName(team)), C.TEAM_RGB[team])
    if R.gameWinner(rs(), S.game.scores) then
      return G.endByPassBonus(team)
    end
  end
  h.turn = R.nextSeat(seat)
  G.startTurn()
end

-- Taunts ----------------------------------------------------------------------------------------

local function spin(seat, key)
  spinToken[seat] = (spinToken[seat] or 0) + 1
  local my = spinToken[seat]
  local pos = U.tauntPos(seat)
  local o = Tiles.obj(key)
  if not o then return end
  o.setLock(true)
  o.setPosition({ pos.x, pos.y + 0.05, pos.z })
  local frames, total = 0, 210
  local angle = math.random(0, 359)
  local function step()
    if my ~= spinToken[seat] or S.hand.taunt[seat] ~= key then return end
    local oo = Tiles.obj(key)
    if not oo then return end
    frames = frames + 1
    local t = frames / total
    local speed = 32 * math.max(0, 1 - t) ^ 1.4
    angle = (angle + speed) % 360
    local wob = 4 * math.max(0, 1 - t) * math.sin(frames * 0.35)
    oo.setRotation({ wob, angle, 180 + wob * 0.6 })
    if frames < total then Wait.frames(step, 1) else oo.setRotation({ 0, angle, 180 }) end
  end
  step()
end

function G.startTaunt(seat, key)
  local h = S.hand
  if h.taunt[seat] and h.taunt[seat] ~= key then
    if h.committed[seat] then
      Tiles.arrangeRack(seat)
      return U.tell(C.SEATS[seat].color, "You already committed to a tile.")
    end
    returnTaunt(seat)
  end
  h.taunt[seat] = key
  Tiles.arrangeRack(seat)
  spin(seat, key)
  Sound.play("spin")
end

function G.tauntMenu(action, color, obj)
  if S.phase ~= "play" then return end
  local key = Tiles.keyOf(obj)
  local owner = key and G.ownerOf(key)
  if not owner or S.hand.taunt[owner] ~= key or not G.canControl(color, owner) then
    return U.tell(color, "Only the spinning tile on your taunt spot can do that.")
  end
  if action == "spin" then
    spin(owner, key)
  elseif action == "commit" then
    if S.hand.committed[owner] then return U.tell(color, "Already committed.") end
    if S.hand.turn == owner then return U.tell(color, "It's your turn. Just play!") end
    S.hand.committed[owner] = key
    UIx.banner("¡Va!", 2, "#ffd36b")
    U.announce(U.nameAt(owner) .. " commits to the spinning tile. ¡Va!", { 1, 0.85, 0.5 })
    spin(owner, key)
  elseif action == "back" then
    if S.hand.committed[owner] then return U.tell(color, "You committed to it. It stays until your turn.") end
    returnTaunt(owner)
    Tiles.arrangeRack(owner)
  end
end

-- End of hand, game and series ------------------------------------------------------------------

local function revealAll()
  for seat = 1, 4 do
    returnTaunt(seat)
    Tiles.revealHand(seat)
  end
end

local KIND_BANNER = { domino = "¡Dominó!", capicu = "¡Capicú!", chuchazo = "¡Chuchazo!", tranque = "¡Tranque!" }

local function recordRow(sc)
  local h = S.hand
  local pts = { h.passBonus[1], h.passBonus[2] }
  if sc.team then pts[sc.team] = pts[sc.team] + sc.total end
  local row = {
    n = S.game.handNo, winnerSeat = sc.winner, winnerName = sc.winner and U.nameAt(sc.winner) or "-",
    kind = sc.kind, pips = sc.pips or 0, bonus = sc.bonus or 0, premio = sc.premio or 0,
    pass = { h.passBonus[1], h.passBonus[2] }, team = sc.team, points = pts,
    totals = { S.game.scores[1], S.game.scores[2] },
  }
  S.game.rows[#S.game.rows + 1] = row
  return row
end

local function finishHand(sc)
  S.game.scores[sc.team] = S.game.scores[sc.team] + sc.total
  local row = recordRow(sc)
  S.lastWinnerSeat = sc.winner
  S.handsPlayed = S.handsPlayed + 1
  Tiles.clearMarkers()
  revealAll()
  UIx.refreshHands()
  UIx.banner(KIND_BANNER[sc.kind], 3.5)
  Sound.play((sc.kind == "capicu" or sc.kind == "chuchazo") and "slam" or "knock")
  local detail = string.format("%s wins the hand for %s: %d pips", U.nameAt(sc.winner), U.teamName(sc.team), sc.pips)
  if sc.bonus > 0 then detail = detail .. string.format(" + %d %s", sc.bonus, sc.kind == "capicu" and "capicú" or "chuchazo") end
  if sc.premio > 0 then detail = detail .. string.format(" + %d premio", sc.premio) end
  detail = detail .. string.format(" = %d.\n%s %d · %s %d", sc.total, U.teamName(1), S.game.scores[1], U.teamName(2), S.game.scores[2])
  U.announce(detail, { 1, 0.85, 0.5 })
  UIx.refreshScore()
  local winner = R.gameWinner(rs(), S.game.scores)
  if winner then return G.endGame(winner) end
  S.phase = "handover"
  UIx.status(string.format("Game %d · hand %d over", S.series.gameNo, S.game.handNo))
  UIx.result(KIND_BANNER[sc.kind] .. "  " .. U.teamName(sc.team) .. " +" .. row.points[sc.team], detail, "Next hand")
end

function G.endDomino(seat, lastTile, before)
  S.game.handNo = S.game.handNo + 1
  local sc = R.scoreDomino(rs(), seat, allHandTiles(), lastTile, before, S.game.handNo)
  finishHand(sc)
end

function G.endTranque()
  S.game.handNo = S.game.handNo + 1
  local fallback = S.lastWinnerSeat and R.teamOf(S.lastWinnerSeat) or R.teamOf(S.hand.leader)
  local sc = R.scoreTranque(rs(), allHandTiles(), fallback, S.game.handNo)
  U.announce("¡Tranque! Nobody can play.", { 1, 0.7, 0.4 })
  finishHand(sc)
end

function G.endByPassBonus(team)
  S.game.handNo = S.game.handNo + 1
  local seat = S.hand.lastPlayer
  recordRow({ kind = "pass", winner = seat, team = nil, total = 0 })
  S.game.rows[#S.game.rows].team = team
  S.lastWinnerSeat = seat
  S.handsPlayed = S.handsPlayed + 1
  revealAll()
  UIx.refreshHands()
  UIx.refreshScore()
  G.endGame(team)
end

function G.endGame(team)
  S.series.games[team] = S.series.games[team] + 1
  S.series.past[#S.series.past + 1] = { winner = team, scores = { S.game.scores[1], S.game.scores[2] } }
  UIx.refreshScore()
  local seriesWinner = R.seriesWinner(S.settings.bestOf, S.series.games)
  local score = string.format("%s %d · %s %d", U.teamName(1), S.game.scores[1], U.teamName(2), S.game.scores[2])
  local games = string.format("Games: %s %d – %d %s", U.teamName(1), S.series.games[1], S.series.games[2], U.teamName(2))
  if seriesWinner then
    S.phase = "seriesover"
    UIx.banner(U.teamName(seriesWinner) .. " win the series!", 6)
    Sound.play("slam")
    UIx.status("Series over")
    UIx.result(U.teamName(seriesWinner) .. " win the series!", score .. "\n" .. games, "Back to lobby")
  else
    S.phase = "gameover"
    UIx.banner(U.teamName(team) .. " win game " .. S.series.gameNo .. "!", 4)
    UIx.status("Game " .. S.series.gameNo .. " over")
    UIx.result(U.teamName(team) .. " win game " .. S.series.gameNo, score .. "\n" .. games .. "\nPartners may swap seats before the next game.", "Next game")
    UIx.showSwaps(true)
  end
end

function G.resultNext(player)
  if not U.seatOf(player.color) and not S.settings.dev and not player.host then return end
  if S.phase == "handover" then
    G.startHand()
  elseif S.phase == "gameover" then
    S.series.gameNo = S.series.gameNo + 1
    S.game = Store.newGame()
    G.startHand()
  elseif S.phase == "seriesover" then
    S.phase = "lobby"
    S.ready = {}
    UIx.hideResult()
    Tiles.scatter(Tiles.allKeys())
    UIx.status("Lobby: choose your seats")
    UIx.refreshLobby()
    G.checkStart()
  end
end

-- Sopa tiles must stay face down.
function G.onRotate(key, obj, flip, oldFlip)
  if S.phase ~= "sopa" or G.ownerOf(key) then return end
  if flip ~= oldFlip then
    Wait.frames(function()
      local o = Tiles.obj(key)
      if o then
        local r = o.getRotation()
        o.setRotationSmooth({ 0, r.y, 180 }, false, true)
      end
    end, 2)
  end
end

return G
