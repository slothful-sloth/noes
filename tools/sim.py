#!/usr/bin/env python3
"""Offline simulation: run the bundled Global script against a mock TTS API and play full series.

usage: sim.py [--series N] [--seed S] [--ruleset pr|custom] [--bestof 1|3|5] [-v]
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

from lupa import lua52

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build  # noqa: E402

MOCK = r"""
local clock, queue, seq = 0, {}, 0
function __advance(dt)
  local target = clock + dt
  while true do
    local best, bi = nil, nil
    for i, e in ipairs(queue) do
      if e.due <= target and (best == nil or e.due < best.due or (e.due == best.due and e.seq < best.seq)) then best, bi = e, i end
    end
    if not best then break end
    table.remove(queue, bi)
    clock = math.max(clock, best.due)
    best.fn()
  end
  clock = target
end
local function enqueue(fn, delay) seq = seq + 1; queue[#queue + 1] = { due = clock + delay, fn = fn, seq = seq } end
Wait = {
  time = function(fn, s) enqueue(fn, s or 0) end,
  frames = function(fn, n) enqueue(fn, (n or 1) / 60) end,
  condition = function(fn, cond, timeout, onTimeout) enqueue(fn, 0) end,
}

local objects = {}
__objects = objects
local guidSeq = 0
local function vec(t) return { x = t.x or t[1] or 0, y = t.y or t[2] or 0, z = t.z or t[3] or 0 } end
function __makeObject(guid, notes)
  local o = { guid = guid, interactable = true, memo = "", __pos = { x = 0, y = 0, z = 0 }, __rot = { x = 0, y = 0, z = 0 },
              __hidden = {}, __locked = false, __destroyed = false, __buttons = {}, __menus = {} }
  o.getGUID = function() return o.guid end
  o.getGMNotes = function() return notes or "" end
  o.setGMNotes = function(n) notes = n end
  o.spawning, o.loading_custom = false, false
  o.getPosition = function() return vec(o.__pos) end
  o.getRotation = function() return vec(o.__rot) end
  o.setPosition = function(p) o.__pos = vec(p) end
  o.setPositionSmooth = function(p) o.__pos = vec(p) end
  o.setRotation = function(r) o.__rot = vec(r) end
  o.setRotationSmooth = function(r) o.__rot = vec(r) end
  o.setLock = function(b) o.__locked = b end
  o.addForce = function() end
  o.addTorque = function() end
  o.setHiddenFrom = function(list) o.__hidden = list end
  o.setInvisibleTo = function(list) o.__invisible = list end
  o.setColorTint = function() end
  o.setCustomObject = function(t) o.__custom = t end
  o.reload = function() return o end
  o.setDecals = function(d) o.__decals = d end
  o.clearButtons = function() o.__buttons = {} end
  o.createButton = function(b) o.__buttons[#o.__buttons + 1] = b end
  o.clearContextMenu = function() o.__menus = {} end
  o.addContextMenuItem = function(label, fn) o.__menus[label] = fn end
  o.destruct = function() o.__destroyed = true; objects[o.guid] = nil end
  o.isDestroyed = function() return o.__destroyed end
  objects[guid] = o
  return o
end
function getObjectFromGUID(g) return objects[g] end
function getObjects() local l = {} for _, o in pairs(objects) do l[#l + 1] = o end return l end
function spawnObject(p)
  guidSeq = guidSeq + 1
  local o = __makeObject(string.format("s%05d", guidSeq))
  o.__pos = vec(p.position or {})
  o.__rot = vec(p.rotation or {})
  if p.callback_function then enqueue(function() p.callback_function(o) end, 0) end
  return o
end

UI = { __vals = {}, __attrs = {} }
UI.setValue = function(id, v) UI.__vals[id] = v end
UI.getValue = function(id) return UI.__vals[id] end
UI.setAttribute = function(id, k, v) UI.__attrs[id .. "." .. k] = v end
UI.getAttribute = function(id, k) return UI.__attrs[id .. "." .. k] end

__messages = {}
local function msg(m) __messages[#__messages + 1] = m end
function broadcastToAll(m) msg("[all] " .. m) end
Player = {}
local COLORS = { "White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink", "Grey", "Black" }
for _, c in ipairs(COLORS) do
  local p = { color = c, seated = false, steam_name = c .. "Player", host = (c == "Red") }
  p.broadcast = function(m) msg("[" .. c .. "] " .. m) end
  p.changeColor = function(nc) end
  p.lookAt = function(t) end
  p.steam_id = c
  p.getPointerPosition = function() return { x = math.random() * 10 - 5, y = 1.2, z = math.random() * 10 - 5 } end
  Player[c] = p
end
Player.getPlayers = function()
  local l = {}
  for _, c in ipairs(COLORS) do if Player[c].seated then l[#l + 1] = Player[c] end end
  return l
end
Player.getSpectators = function() return {} end
Player.getAvailableColors = function()
  return { "White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink" }
end
MusicPlayer = { setCurrentAudioclip = function() end, play = function() end }
Global = {}
"""


def lua_to_py(v):
    if hasattr(v, "items") and not isinstance(v, dict):
        d = dict(v.items())
        keys = list(d.keys())
        if keys and all(isinstance(k, (int, float)) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [lua_to_py(d[k]) for k in sorted(keys)]
        return {str(k): lua_to_py(x) for k, x in d.items()}
    return v


def make_runtime(seed: int):
    lua = lua52.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f"math.randomseed({seed})")
    lua.execute(MOCK)
    g = lua.globals()

    def py_to_lua(v):
        if isinstance(v, dict):
            t = lua.table()
            for k, x in v.items():
                t[k] = py_to_lua(x)
            return t
        if isinstance(v, list):
            t = lua.table()
            for i, x in enumerate(v, 1):
                t[i] = py_to_lua(x)
            return t
        return v

    j = lua.table()
    j.encode = lambda v: json.dumps(lua_to_py(v))
    j.decode = lambda s: py_to_lua(json.loads(s))
    g.JSON = j
    for i in range(7):
        for k in range(i + 1):
            g.__makeObject(build.tile_guid(i, k), f"{i}-{k}")
    for gid in build.GUIDS.values():
        g.__makeObject(gid, "")
    script, _ = build.bundle("file:///mock/assets/")
    lua.execute(script)
    return lua, g


def run_series(seed: int, ruleset: str, bestof: int, verbose: bool) -> dict:
    random.seed(seed)
    lua, g = make_runtime(seed)
    adv = g.__advance
    players = {c: g.Player[c] for c in ("Red", "Blue", "Orange", "Teal")}
    g.onLoad("")
    for c, p in players.items():
        p.seated = True
    g.onPlayerChangeColor("Red")
    # settings
    {"pr": g.uiRulesPr, "custom": g.uiRulesCustom}[ruleset](players["Red"])
    {1: g.uiBestOf1, 3: g.uiBestOf3, 5: g.uiBestOf5}[bestof](players["Red"])
    g.uiStart(players["Blue"])
    adv(0.5)
    S = g.S
    assert S.phase == "sopa", S.phase
    color_of = {1: "Red", 2: "Blue", 3: "Orange", 4: "Teal"}
    hands_played = 0
    stats = {"hands": 0, "kinds": {}, "passes": 0, "games": 0}
    steps = 0
    while steps < 20000:
        steps += 1
        S = g.S
        phase = S.phase
        if phase == "sopa":
            # Draw: physical drops into the virtual rack, the panel buttons, and the old button.
            U = g.require("util")
            if g.S.hand.sopaStage == "stir":
                g.uiDraw7(players["Red"])          # must be refused while stirring
                assert len(lua_to_py(g.S.hand.hands[1]) or []) == 0
                shufflers = [s_ for s_ in range(1, 5) if g.require("game").canShuffle(color_of[s_])]
                assert shufflers and (g.S.handsPlayed == 0 or len(shufflers) == 2), shufflers
                g.uiHandAct(players[color_of[shufflers[0]]], None, f"h{shufflers[0]}_shuffle")
                assert g.S.hand.sopaStage == "draw"
            for seat in range(1, 5):
                free = [k for k in (lua_to_py(g.require("tiles").allKeys()) or []) if not g.require("game").ownerOf(k)]
                for k in random.sample(free, min(len(free), random.randint(0, 4))):
                    obj = g.getObjectFromGUID(build.tile_guid(int(k[0]), int(k[2])))
                    obj.setPosition(U.seatPoint(seat, 16.8, random.uniform(-4.5, 4.5), 1.3))
                    g.onObjectDrop(color_of[seat], obj)
                adv(0.1)
                g.uiHandAct(players[color_of[seat]], None, f"h{seat}_shuffle")
                if seat == 2 and len(lua_to_py(g.S.hand.hands[1]) or []) == 7:
                    # seat 1 is full: grabbing another loose tile must not give it a tile
                    free = [k for k in (lua_to_py(g.require("tiles").allKeys()) or []) if not g.require("game").ownerOf(k)]
                    if free:
                        o3 = g.getObjectFromGUID(build.tile_guid(int(free[0][0]), int(free[0][2])))
                        g.onObjectPickUp("Red", o3)
                        o3.setPosition(U.seatPoint(1, 16.8, 0, 1.3))
                        g.onObjectDrop("Red", o3)
                        assert len(lua_to_py(g.S.hand.hands[1]) or []) == 7
                if random.random() < 0.5:
                    g.uiHandAct(players[color_of[seat]], None, f"h{seat}_draw")
                else:
                    g.uiDraw7(players[color_of[seat]])
            for seat in range(1, 5):
                assert len(lua_to_py(g.S.hand.hands[seat]) or []) == 7 or g.S.phase != "sopa"
            adv(0.1)
            if g.S.phase == "sopa" and g.S.redealSeat:
                seat = g.S.redealSeat
                g.uiRedealNo(players[color_of[seat]])
            adv(0.1)
            continue
        if phase == "play":
            h = S.hand
            seat = h.turn
            color = color_of[seat]
            keys = list(lua_to_py(h.hands[seat]) or [])
            moves = []
            for k in keys:
                sides = g.require("rules").legalSides(h.board, g.require("rules").parse(k),
                                                      lua.eval("function(k) if S.hand.board.count == 0 and S.hand.mustLeadKey then return {mustLeadKey=S.hand.mustLeadKey} end end")(k))
                for s in lua_to_py(sides) or []:
                    moves.append((k, s))
            def select(seat_, key_):
                disp = lua_to_py(g.require("ui").displayed[seat_]) or []
                i = disp.index(key_) + 1
                g.uiHandTile(players[color_of[seat_]], None, f"h{seat_}_t{i}")
            if not moves:
                g.uiHandAct(players[color], None, f"h{seat}_pass")
                stats["passes"] += 1
                adv(0.05)
                continue
            # Occasionally taunt with a non-active seat first (through its hand panel).
            if random.random() < 0.15:
                other = random.choice([s_ for s_ in range(1, 5) if s_ != seat])
                okeys = lua_to_py(h.hands[other]) or []
                if okeys:
                    g.require("ui").refreshHands()
                    select(other, random.choice(okeys))
                    g.uiHandAct(players[color_of[other]], None, f"h{other}_spin")
                    adv(0.05)
                    r = random.random()
                    if r < 0.4:
                        g.uiHandAct(players[color_of[other]], None, f"h{other}_commit")
                    elif r < 0.6:
                        g.uiHandAct(players[color_of[other]], None, f"h{other}_back")
                    adv(0.05)
            ck = h.committed[seat]
            if ck:
                moves = [m for m in moves if m[0] == ck] or moves
            # hide any revealed tiles that became hideable; occasionally reset the round
            for sk in range(1, 5):
                for rk in list(lua_to_py(h.hands[sk]) or []):
                    if h.revealedHideable[rk] and random.random() < 0.5:
                        o2 = g.getObjectFromGUID(build.tile_guid(int(rk[0]), int(rk[2])))
                        g.onRevealedClick(o2, color_of[sk], False)
            if random.random() < 0.004:
                g.uiResetRound(players["Red"]); g.uiConfirmYes(players["Red"]); adv(1.2)
                continue
            k, side = random.choice(moves)
            r = random.random()
            if r < 0.3:
                g.dev_play(k, side)
            else:
                g.require("ui").refreshHands()
                cur = g.require("game").selected[seat]
                if cur != k:
                    select(seat, k)
                adv(0.05)
                if r < 0.65:
                    g.uiHandAct(players[color], None, f"h{seat}_" + {"C": "lead", "L": "left", "R": "right"}[side])
                else:
                    mk = g.require("tiles").markers()
                    clicked = False
                    for i in range(1, len(lua_to_py(mk) or []) + 1):
                        m = mk[i]
                        info = json.loads(m.memo) if m.memo else None
                        if info and info["key"] == k and info["side"] == side:
                            g.onMarkerClick(m, color, False)
                            clicked = True
                            break
                    if not clicked:
                        raise RuntimeError(f"no marker for {k} {side}")
            adv(0.9)
            continue
        if phase == "handover":
            row = lua_to_py(S.game.rows)[-1]
            stats["hands"] += 1
            stats["kinds"][row["kind"]] = stats["kinds"].get(row["kind"], 0) + 1
            check_row(row, ruleset)
            g.uiResultNext(players["Red"])
            adv(0.5)
            continue
        if phase in ("gameover", "seriesover"):
            rows = lua_to_py(S.game.rows)
            tot = [sum(r["points"][0] for r in rows), sum(r["points"][1] for r in rows)]
            assert tot == lua_to_py(S.game.scores), (tot, lua_to_py(S.game.scores))
            target = 500 if ruleset == "pr" else 300
            assert max(tot) >= target and min(tot) < target, tot
        if phase == "gameover":
            g.uiSwap1(players["Red"]); g.uiSwap2(players["Red"])   # second one must be refused (Red is team 1)
            adv(0.5)
            stats["games"] += 1
            g.uiResultNext(players["Red"])
            adv(0.5)
            continue
        if phase == "seriesover":
            stats["games"] += 1
            stats["series_games"] = lua_to_py(S.series.games)
            break
        raise RuntimeError(f"unexpected phase {phase}")
    if verbose:
        for m in list(lua_to_py(g.__messages) or [])[-15:]:
            print("   ", m)
    return stats


def check_row(row, ruleset):
    rs = {"pr": {"capicu": 100, "chuchazo": 100, "premios": [100, 75, 50, 25]},
          "custom": {"capicu": 60, "chuchazo": 60, "premios": []}}[ruleset]
    if row["kind"] in ("capicu", "chuchazo"):
        assert row["bonus"] == rs[row["kind"]], row
    exp_premio = rs["premios"][row["n"] - 1] if row["n"] <= len(rs["premios"]) else 0
    if row["kind"] != "pass":
        assert row["premio"] == exp_premio, row
    if ruleset == "custom":
        assert row["pass"] == [0, 0], row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--series", type=int, default=20)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--ruleset", choices=["pr", "custom", "both"], default="both")
    ap.add_argument("--bestof", type=int, default=3)
    ap.add_argument("-v", action="store_true")
    a = ap.parse_args()
    totals = {"hands": 0, "kinds": {}, "passes": 0, "games": 0}
    rulesets = ["pr", "custom"] if a.ruleset == "both" else [a.ruleset]
    for i in range(a.series):
        rsid = rulesets[i % len(rulesets)]
        st = run_series(a.seed + i, rsid, a.bestof, a.v)
        for k in ("hands", "passes", "games"):
            totals[k] += st[k]
        for k, v in st["kinds"].items():
            totals["kinds"][k] = totals["kinds"].get(k, 0) + v
        if a.v:
            print(f"series {i} ({rsid}): {st}")
    print(f"OK: {a.series} series, {totals['games']} games, {totals['hands']} hands, "
          f"{totals['passes']} passes, endings {totals['kinds']}")


if __name__ == "__main__":
    main()
