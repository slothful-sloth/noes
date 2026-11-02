-- ui.lua: Global XML UI updates and the 3D scoreboard.
local C = require("config")
local R = require("rules")
local U = require("util")

local UIx = {}

local ALL = { "White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink", "Grey", "Black" }
local viewers = { scorePanel = {}, rulesPanel = {} }   -- panel -> set of colours that opened it
local lobbyHidden = {}                                 -- colours that collapsed the lobby
local bannerToken = 0

local function setText(id, v) UI.setValue(id, v) end
-- Button labels are the "text" attribute; UI.setValue does not change them.
local function setLabel(id, v) UI.setAttribute(id, "text", v) end
UIx.setLabel = setLabel
local function setAttr(id, k, v) UI.setAttribute(id, k, v) end

-- Selected buttons are gold, unselected are dark slate; text colour follows.
local ON_COLORS = "#c9a46a|#e0bd82|#a8854c|#c9a46a80"
local OFF_COLORS = "#3a4048|#4b525c|#2a2f35|#2a2f3580"
local function styleButton(id, on)
  setAttr(id, "colors", on and ON_COLORS or OFF_COLORS)
  setAttr(id, "textColor", on and "#1b1b1b" or "#f1ece2")
end
UIx.styleButton = styleButton

local function joinColors(set)
  local list = {}
  for _, c in ipairs(ALL) do if set[c] then list[#list + 1] = c end end
  return table.concat(list, "|")
end

-- Panel visibility ------------------------------------------------------------------------

function UIx.togglePanel(panel, color)
  local set = viewers[panel]
  set[color] = not set[color] or nil
  local vis = joinColors(set)
  if vis == "" then
    setAttr(panel, "active", "false")
  else
    setAttr(panel, "visibility", vis)
    setAttr(panel, "active", "true")
  end
end

function UIx.refreshLobbyVisibility()
  if S.phase ~= "lobby" then
    setAttr("lobby", "active", "false")
    return
  end
  local set = {}
  for _, c in ipairs(ALL) do if not lobbyHidden[c] then set[c] = true end end
  local vis = joinColors(set)
  if vis == "" then setAttr("lobby", "active", "false") return end
  setAttr("lobby", "visibility", vis)
  setAttr("lobby", "active", "true")
end

function UIx.toggleLobby(color)
  lobbyHidden[color] = not lobbyHidden[color] or nil
  UIx.refreshLobbyVisibility()
end

function UIx.show(panel, on, onlyColor)
  if on and onlyColor then setAttr(panel, "visibility", onlyColor) end
  if on and not onlyColor then setAttr(panel, "visibility", "") end
  setAttr(panel, "active", on and "true" or "false")
end

function UIx.status(text) setText("status", text) end

function UIx.banner(text, seconds, color)
  bannerToken = bannerToken + 1
  local my = bannerToken
  setText("bannerText", text)
  setAttr("bannerText", "color", color or "#ffd36b")
  setAttr("banner", "active", "true")
  Wait.time(function()
    if my == bannerToken then setAttr("banner", "active", "false") end
  end, seconds or 3)
end

-- Rules text -----------------------------------------------------------------------------------

function UIx.rulesText()
  local rs = R.RULESETS[S.settings.ruleset]
  local lines = { "<b>" .. rs.name .. "</b>" }
  for _, l in ipairs(rs.summary) do lines[#lines + 1] = "• " .. l end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "<b>Always</b>"
  for _, l in ipairs(R.COMMON_SUMMARY) do lines[#lines + 1] = "• " .. l end
  lines[#lines + 1] = "• Series: best of " .. S.settings.bestOf
  return table.concat(lines, "\n")
end

-- Lobby ----------------------------------------------------------------------------------------

local function nameOf(list, id)
  for _, e in ipairs(list) do if e.id == id then return e.name end end
  return id
end

function UIx.refreshLobby()
  local st = S.settings
  local seated = 0
  for seat = 1, 4 do
    local sd = C.SEATS[seat]
    local p = U.playerAt(seat)
    local team = R.teamOf(seat)
    setLabel("seat" .. seat, sd.pos .. " · " .. sd.color .. "\n" .. (p and p.steam_name or "Sit here"))
    if p then
      seated = seated + 1
      setAttr("seat" .. seat, "colors", C.TEAM_BUTTON[team])
      setAttr("seat" .. seat, "textColor", "#ffffff")
      local partner = U.playerAt(R.partnerOf(seat))
      setText("youAt" .. seat, string.format("You're sitting %s (%s) · %s · partner: %s", sd.pos, sd.color,
        U.teamName(team), partner and partner.steam_name or "empty"))
    else
      styleButton("seat" .. seat, false)
      setText("youAt" .. seat, " ")
    end
  end
  local canStart = S.settings.dev and seated >= 1 or seated == 4
  setAttr("btnStart", "interactable", canStart and "true" or "false")
  setAttr("btnStart", "colors", canStart and "#c9a46a|#e0bd82|#a8854c|#c9a46a80" or "#5a5a5a|#5a5a5a|#5a5a5a|#5a5a5a")
  setAttr("btnStart", "textColor", canStart and "#1b1b1b" or "#9a9a9a")
  UIx.canStart = canStart
  UIx.seatedCount = seated
  setAttr("team1", "text", S.teams[1].name)
  setAttr("team2", "text", S.teams[2].name)
  styleButton("rsPr", st.ruleset == "pr")
  styleButton("rsCustom", st.ruleset == "custom")
  for _, n in ipairs({ 1, 3, 5 }) do styleButton("bo" .. n, st.bestOf == n) end

  setLabel("faceBtn", "Face: " .. nameOf(C.FACES, st.face))
  setLabel("backBtn", "Back: " .. nameOf(C.BACKS, st.back))
  setLabel("tableBtn", "Table: " .. nameOf(C.TABLE_FACES, st.tableFace))
  -- setting a label resets the text colour, so style afterwards
  for _, id in ipairs({ "faceBtn", "backBtn", "tableBtn" }) do styleButton(id, false) end
  setAttr("backUrl", "text", st.backUrl or "")
  setAttr("tableUrl", "text", st.tableUrl or "")
  setLabel("devMode", "Developer mode: " .. (st.dev and "ON" or "off"))
  styleButton("devMode", st.dev)
  setText("lobbyRules", UIx.rulesText())
  setText("rulesText", UIx.rulesText())
  UIx.refreshLobbyVisibility()
end

function UIx.lobbyStatus(text) setText("lobbyStatus", text) end

-- Scoreboard --------------------------------------------------------------------------------------

local KIND_LABEL = { domino = "Dominó", capicu = "¡Capicú!", chuchazo = "¡Chuchazo!", tranque = "Tranque", pass = "Pass bonus" }

function UIx.rowHow(row)
  local parts = { KIND_LABEL[row.kind] or row.kind }
  if row.kind ~= "pass" then
    parts[#parts + 1] = row.pips .. " pips"
    if row.bonus > 0 then parts[#parts + 1] = "+" .. row.bonus end
    if row.premio > 0 then parts[#parts + 1] = "premio " .. row.premio end
  end
  if (row.pass[1] or 0) + (row.pass[2] or 0) > 0 then parts[#parts + 1] = "(pases)" end
  return table.concat(parts, " ")
end

local function seriesLine()
  return string.format("Game %d of best of %d  ·  Games: %s %d – %d %s",
    S.series.gameNo, S.settings.bestOf, U.teamName(1), S.series.games[1], S.series.games[2], U.teamName(2))
end

function UIx.refreshScore()
  local rows = S.game.rows
  local c1, c2, c3, c4, c5 = {}, {}, {}, {}, {}
  local first = math.max(1, #rows - 17)
  for i = first, #rows do
    local row = rows[i]
    c1[#c1 + 1] = tostring(row.n)
    c2[#c2 + 1] = row.winnerName or "-"
    c3[#c3 + 1] = UIx.rowHow(row)
    c4[#c4 + 1] = (row.points[1] > 0) and ("+" .. row.points[1]) or "·"
    c5[#c5 + 1] = (row.points[2] > 0) and ("+" .. row.points[2]) or "·"
  end
  local live = S.hand and S.hand.passBonus
  if S.phase == "play" and live and (live[1] + live[2] > 0) then
    c1[#c1 + 1] = tostring(S.game.handNo + 1)
    c2[#c2 + 1] = "(in progress)"
    c3[#c3 + 1] = "pass bonuses"
    c4[#c4 + 1] = live[1] > 0 and ("+" .. live[1]) or "·"
    c5[#c5 + 1] = live[2] > 0 and ("+" .. live[2]) or "·"
  end
  local rs = R.RULESETS[S.settings.ruleset]
  setText("scoreTitle", "Score · " .. rs.name .. " · to " .. rs.target)
  setText("scoreSeries", seriesLine())
  setText("scoreCol1", #c1 > 0 and table.concat(c1, "\n") or " ")
  setText("scoreCol2", #c2 > 0 and table.concat(c2, "\n") or " ")
  setText("scoreCol3", #c3 > 0 and table.concat(c3, "\n") or " ")
  setText("scoreCol4", "<b>" .. U.teamName(1) .. "</b>\n" .. table.concat(c4, "\n"))
  setText("scoreCol5", "<b>" .. U.teamName(2) .. "</b>\n" .. table.concat(c5, "\n"))
  setText("scoreTotals", string.format("Total:  %s %d   ·   %s %d",
    U.teamName(1), S.game.scores[1], U.teamName(2), S.game.scores[2]))
  UIx.refreshBoard3D(rows, first)
end

-- 3D scoreboard: text labels (zero-size buttons) on the chalk face (local -Z).
-- Seen from the front, local +X is on the viewer's left, so `x` below is measured from the left
-- edge's centre line and negated.
function UIx.refreshBoard3D(rows, first)
  local b = getObjectFromGUID(OBJ_GUIDS.scoreboard)
  if not b then return end
  b.clearButtons()
  local function label(text, x, y, size, color)
    b.createButton({
      label = text, click_function = "noop", function_owner = Global,
      position = { -x, y, -0.15 }, rotation = { 90, 180, 0 },
      width = 0, height = 0, font_size = size, font_color = color or { 0.95, 0.95, 0.9 },
    })
  end
  local rs = R.RULESETS[S.settings.ruleset]
  label(rs.name .. " · to " .. rs.target, 0, 8.3, 420, { 1, 0.85, 0.5 })
  label(seriesLine(), 0, 7.55, 300)
  local y = 6.75
  local startRow = math.max(first, #rows - 7)
  for i = startRow, #rows do
    local row = rows[i]
    label(string.format("%d. %s: %s", row.n, row.winnerName or "-", UIx.rowHow(row)), -1.4, y, 260)
    label((row.points[1] > 0 and ("+" .. row.points[1]) or "·"), 3.9, y, 280, C.TEAM_RGB[1])
    label((row.points[2] > 0 and ("+" .. row.points[2]) or "·"), 5.5, y, 280, C.TEAM_RGB[2])
    y = y - 0.62
  end
  label(U.teamName(1) .. "  " .. S.game.scores[1], -3.1, 1.25, 480, C.TEAM_RGB[1])
  label(U.teamName(2) .. "  " .. S.game.scores[2], 3.1, 1.25, 480, C.TEAM_RGB[2])
end

-- Hand panels ------------------------------------------------------------------------------------

local ACTIONS = { "shuffle", "draw", "lead", "left", "right", "pass", "spin", "commit", "back" }
UIx.displayed = { {}, {}, {}, {} }   -- seat -> keys in button order
UIx.devView = 0                      -- developer mode: 0 = follow the turn, else a seat

-- Developer mode during the sopa: show the hand of the seat the (single) tester sits in.
function UIx.devHomeSeat()
  for seat = 1, 4 do if U.playerAt(seat) then return seat end end
  return 1
end

function UIx.refreshHands()
  local inHand = (S.phase == "sopa" or S.phase == "play")
  for seat = 1, 4 do
    local id = "hand" .. seat
    local color = C.SEATS[seat].color
    local show = inHand and UIx.handView ~= nil
    if S.settings.dev then
      local want = (UIx.devView ~= 0) and UIx.devView or (S.phase == "play" and S.hand.turn) or UIx.devHomeSeat()
      show = show and want == seat
    end
    if not show then
      setAttr(id, "active", "false")
    else
      local v = UIx.handView(seat)
      UIx.displayed[seat] = v.tiles
      for i = 1, 7 do
        local bid = "h" .. seat .. "_t" .. i
        local key = v.tiles[i]
        if key then
          setAttr(bid, "icon", S.settings.face .. "_" .. key:gsub("-", ""))
          local border = "#00000000"
          if key == v.selected then border = v.selectedBad and "#e23b2eff" or "#ffd36bff" end
          setAttr("h" .. seat .. "_b" .. i, "color", border)
          setAttr("h" .. seat .. "_b" .. i, "active", "true")
        else
          setAttr("h" .. seat .. "_b" .. i, "active", "false")
        end
      end
      setText("h" .. seat .. "_info", (S.settings.dev and (U.nameAt(seat) .. " · ") or "") .. (v.info or ""))
      for _, a in ipairs(ACTIONS) do
        local bid = "h" .. seat .. "_" .. a
        if v.actions[a] then
          setLabel(bid, v.actions[a])
          setAttr(bid, "active", "true")
        else
          setAttr(bid, "active", "false")
        end
      end
      setAttr(id, "visibility", S.settings.dev and "" or color)
      setAttr(id, "active", "true")
    end
  end
  local devBar = S.settings.dev and (S.phase == "play" or S.phase == "sopa")
  setAttr("devBar", "active", devBar and "true" or "false")
  if devBar then
    for i = 0, 4 do styleButton("dv" .. i, UIx.devView == i) end
  end
end

-- Result panel -----------------------------------------------------------------------------------

function UIx.result(title, text, button)
  setText("resultTitle", title)
  setText("resultText", text)
  if button then
    setLabel("resultBtn", button)
    setAttr("resultBtn", "active", "true")
  else
    setAttr("resultBtn", "active", "false")
  end
  setAttr("resultPanel", "active", "true")
end

function UIx.hideResult()
  setAttr("resultPanel", "active", "false")
  UIx.showSwaps(false)
end

function UIx.showSwaps(on)
  setAttr("swap1", "active", on and "true" or "false")
  setAttr("swap2", "active", on and "true" or "false")
  if on then
    setLabel("swap1", "Swap seats: " .. U.teamName(1))
    setLabel("swap2", "Swap seats: " .. U.teamName(2))
  end
end

return UIx
