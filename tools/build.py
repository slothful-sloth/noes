#!/usr/bin/env python3
"""Bundle the Lua sources and write the TTS save file.

usage:
  build.py [--assets local|github] [--sha SHA] [--out PATH]

  --assets local   asset URLs are file:// paths into this checkout (single-machine testing)
  --assets github  asset URLs are https://raw.githubusercontent.com/<repo>/<sha>/assets/...
                   (sha defaults to `git rev-parse HEAD`; commit + push the assets first)
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
UI = ROOT / "ui" / "Global.xml"
REPO = "slothful-sloth/noes"


def tts_saves_dir() -> Path:
    """The Tabletop Simulator Saves folder. Set TTS_SAVES to override it (for example when the
    save location was changed in TTS's menu)."""
    if os.environ.get("TTS_SAVES"):
        return Path(os.environ["TTS_SAVES"]).expanduser()
    home = Path.home()
    if sys.platform == "win32":
        # Documents may be redirected to OneDrive.
        docs = [home / "Documents"]
        if os.environ.get("OneDrive"):
            docs.insert(0, Path(os.environ["OneDrive"]) / "Documents")
        candidates = [d / "My Games" / "Tabletop Simulator" / "Saves" for d in docs]
        for c in candidates:
            if c.is_dir():
                return c
        return candidates[-1]
    if sys.platform == "darwin":
        return home / "Library" / "Tabletop Simulator" / "Saves"
    return home / ".local" / "share" / "Tabletop Simulator" / "Saves"


SAVES = tts_saves_dir()
STATE_FILE = ROOT / ".build_assets"

MODULE_ORDER = ["rules", "layout", "config", "util", "store", "tiles", "physical", "ui", "sound", "themes", "game"]

TABLE_Y = 1.0
SEATS = [  # seat number -> colour, direction (x, z) from the centre toward the player
    (1, "Red", (0, -1)),
    (2, "Blue", (1, 0)),
    (3, "Orange", (0, 1)),
    (4, "Teal", (-1, 0)),
]


def tile_guid(hi: int, lo: int) -> str:
    return f"d0{hi}{lo}0e"


GUIDS = {
    "tableFace": "7ab1e0",
    "tableBorder": "7ab1e1",
    "scoreboard": "5c0b0a",
}


def local_asset_dir() -> Path:
    """TTS caches assets by URL (local files too). Serve them through a symlink named after a
    hash of the asset files, so changed assets get new URLs and unchanged ones keep theirs."""
    import hashlib
    h = hashlib.sha1()
    for f in sorted((ROOT / "assets").rglob("*")):
        if f.is_file():
            st = f.stat()
            h.update(f"{f.relative_to(ROOT)}:{st.st_size}:{st.st_mtime_ns}".encode())
    d = ROOT / ".build"
    d.mkdir(exist_ok=True)
    link = d / f"assets-{h.hexdigest()[:8]}"
    for old in d.glob("assets-*"):
        if old != link:
            _remove_link(old)
    if not link.exists():
        _make_link(link, ROOT / "assets")
    return link


def _is_junction(p: Path) -> bool:
    return bool(getattr(p, "is_junction", lambda: False)())


def _remove_link(p: Path) -> None:
    """Remove a symlink, junction or copied folder under .build/ without touching assets/."""
    if p.is_symlink():
        p.unlink()
    elif _is_junction(p):
        os.rmdir(p)  # removes the junction only, never the target's contents
    elif p.is_dir():
        shutil.rmtree(p)


def _make_link(link: Path, target: Path) -> None:
    """Symlink on Linux/macOS. On Windows, symlinks need Developer Mode, so fall back to a
    directory junction (no special rights), and finally to a copy."""
    try:
        link.symlink_to(target, target_is_directory=True)
        return
    except OSError:
        if sys.platform != "win32":
            raise
    try:
        import _winapi
        _winapi.CreateJunction(str(target), str(link))
        return
    except (ImportError, AttributeError, OSError):
        pass
    shutil.copytree(target, link)


def asset_base(mode: str, sha: str | None) -> str:
    if mode == "local":
        return local_asset_dir().as_uri() + "/"
    sha = sha or subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    return f"https://raw.githubusercontent.com/{REPO}/{sha}/assets/"


def current_base() -> str:
    if STATE_FILE.exists():
        return STATE_FILE.read_text(encoding="utf-8").strip()
    return asset_base("local", None)


FACE_STYLES = ["white", "ivory", "colors"]


def hand_panels_xml() -> str:
    """One private hand panel per seat (visibility is set at runtime by src/ui.lua)."""
    out = []
    for seat, colour, _ in SEATS:
        h = f"h{seat}"
        tiles = "\n".join(
            f'      <Panel id="{h}_b{i}" preferredWidth="78" preferredHeight="146" color="#00000000" active="false">\n'
            f'        <Button id="{h}_t{i}" rectAlignment="MiddleCenter" width="66" height="132" icon="" '
            f'colors="#ffffff|#fff6dc|#e8dcc0|#ffffff80" onClick="uiHandTile"></Button>\n'
            f'      </Panel>'
            for i in range(1, 8))
        acts = "\n".join(
            f'      <Button id="{h}_{a}" preferredHeight="34" fontSize="16" onClick="uiHandAct" active="false">{label}</Button>'
            for a, label in (("shuffle", "Shuffle"), ("draw", "Draw 7"), ("lead", "Lead this tile"), ("left", "Play left"), ("right", "Play right"),
                             ("pass", "¡Paso!"), ("spin", "Spin it (taunt)"), ("commit", "Commit ¡Va!"),
                             ("back", "Take it back"), ("physical", "Physical tiles: off")))
        out.append(f"""<Panel id="hand{seat}" class="card" active="false" visibility="{colour}" rectAlignment="LowerCenter"
       offsetXY="0 10" width="900" height="200">
  <Text id="{h}_info" rectAlignment="UpperLeft" offsetXY="16 -6" width="860" height="28" fontSize="17" alignment="MiddleLeft">Your hand</Text>
  <HorizontalLayout rectAlignment="LowerLeft" offsetXY="14 8" width="640" height="150" spacing="4"
                    childForceExpandWidth="false" childForceExpandHeight="false" childAlignment="MiddleLeft">
{tiles}
  </HorizontalLayout>
  <VerticalLayout rectAlignment="LowerRight" offsetXY="-14 10" width="210" height="156" spacing="4"
                  childForceExpandHeight="false" childAlignment="LowerCenter">
{acts}
  </VerticalLayout>
</Panel>""")
    return "\n".join(out)


def ui_assets(base: str) -> list[dict]:
    return [{"Type": 0, "Name": f"{face}_{hi}{lo}", "URL": f"{base}textures/ui/{face}/tv_{hi}{lo}.png"}
            for face in FACE_STYLES for hi in range(7) for lo in range(hi + 1)]


def bundle(base: str | None = None) -> tuple[str, str]:
    """Return (global_lua, global_xml)."""
    base = base or current_base()
    parts = [
        "-- Noes: Puerto Rican partner dominoes. GENERATED by tools/build.py from src/ - edit those files.",
        f"ASSET_BASE = {json.dumps(base)}",
        f"OBJ_GUIDS = {lua_table(GUIDS)}",
        "local __mods, __loaded = {}, {}",
        "function require(name)",
        "  if __loaded[name] == nil then",
        "    local f = __mods[name]",
        "    if not f then error('module not found: ' .. name) end",
        "    __loaded[name] = f() or true",
        "  end",
        "  return __loaded[name]",
        "end",
    ]
    for name in MODULE_ORDER:
        path = SRC / f"{name}.lua"
        if not path.exists():
            continue
        parts.append(f"__mods[{json.dumps(name)}] = function()\n{path.read_text(encoding='utf-8')}\nend")
    parts.append((SRC / "main.lua").read_text(encoding="utf-8"))
    xml = UI.read_text(encoding="utf-8").replace("<!--HAND_PANELS-->", hand_panels_xml()) if UI.exists() else ""
    return "\n".join(parts), xml


def lua_table(d: dict) -> str:
    return "{ " + ", ".join(f"{k} = {json.dumps(v)}" for k, v in d.items()) + " }"


def transform(x, y, z, rx=0.0, ry=0.0, rz=0.0, s=1.0):
    return {"posX": x, "posY": y, "posZ": z, "rotX": rx, "rotY": ry, "rotZ": rz,
            "scaleX": s, "scaleY": s, "scaleZ": s}


def custom_model(guid, name, tr, mesh, diffuse, collider="", convex=True, locked=False, material=0,
                 type_index=0, tags=None, color=(1, 1, 1), gm="", tooltip=True, hands=False):
    return {
        "GUID": guid, "Name": "Custom_Model", "Transform": tr, "Nickname": name, "Description": "",
        "GMNotes": gm, "ColorDiffuse": {"r": color[0], "g": color[1], "b": color[2]},
        "Tags": tags or [], "Locked": locked, "Grid": False, "Snap": False, "IgnoreFoW": False,
        "MeasureMovement": False, "DragSelectable": True, "Autoraise": True, "Sticky": False,
        "Tooltip": tooltip, "GridProjection": False, "HideWhenFaceDown": False, "Hands": hands,
        "CustomMesh": {"MeshURL": mesh, "DiffuseURL": diffuse, "NormalURL": "", "ColliderURL": collider,
                       "Convex": convex, "MaterialIndex": material, "TypeIndex": type_index,
                       "CastShadows": True},
        "LuaScript": "", "LuaScriptState": "", "XmlUI": "",
    }


def hand_trigger(guid, colour, dx, dz):
    return {
        "GUID": guid, "Name": "HandTrigger",
        "Transform": {"posX": dx * 34.0, "posY": 6.0, "posZ": dz * 34.0, "rotX": 0.0,
                      "rotY": {(0, -1): 0.0, (1, 0): 270.0, (0, 1): 180.0, (-1, 0): 90.0}[(dx, dz)],
                      "rotZ": 0.0, "scaleX": 8.0, "scaleY": 3.0, "scaleZ": 2.0},
        "GMNotes": "", "ColorDiffuse": {"r": 0.25, "g": 0.25, "b": 0.25, "a": 0.0},
        "Locked": True, "Grid": False, "Snap": False, "IgnoreFoW": False, "MeasureMovement": False,
        "DragSelectable": True, "Autoraise": True, "Sticky": True, "Tooltip": True,
        "GridProjection": False, "HideWhenFaceDown": False, "Hands": False, "FogColor": colour,
    }


def objects(base: str) -> list[dict]:
    m, t = base + "models/", base + "textures/"
    objs = [
        custom_model(GUIDS["tableFace"], "Table", transform(0, TABLE_Y, 0), m + "table/table_face.obj",
                     t + "table/face_felt.jpg", locked=True, material=3, type_index=4,
                     tags=["noes_fixed"], tooltip=False),
        custom_model(GUIDS["tableBorder"], "Table rail", transform(0, TABLE_Y, 0), m + "table/table_border.obj",
                     t + "table/border_maple.jpg", collider=m + "table/table_border_collider.obj",
                     convex=False, locked=True, material=1, type_index=4, tags=["noes_fixed"], tooltip=False),
        custom_model(GUIDS["scoreboard"], "Scoreboard", transform(26.0, -3.0, 26.0, ry=45.0),
                     m + "board/scoreboard.obj", t + "board/scoreboard.jpg",
                     collider=m + "board/scoreboard_collider.obj", locked=True, material=1, type_index=4,
                     tags=["noes_fixed"], tooltip=False),
    ]
    k = 0
    for hi in range(7):
        for lo in range(hi + 1):
            ang = 2 * 3.14159265 * k / 28
            x, z = 8 * math.cos(ang), 8 * math.sin(ang)
            objs.append(custom_model(
                tile_guid(hi, lo), f"{hi}|{lo}", transform(round(x, 3), TABLE_Y + 0.25, round(z, 3), rz=180.0),
                m + f"tiles/tile_{hi}{lo}.obj", t + "tiles/white_pr.jpg", collider=m + "tiles/tile_collider.obj",
                material=0, type_index=0, tags=["noes_tile"], gm=f"{hi}-{lo}", tooltip=False))
            k += 1
    return objs


def save_json(base: str) -> dict:
    script, ui = bundle(base)
    return {
        "SaveName": "Noes - Partner Dominoes", "EpochTime": int(time.time()),
        "Date": time.strftime("%m/%d/%Y %I:%M:%S %p"), "VersionNumber": "v14.0.3",
        "GameMode": "Noes - Partner Dominoes", "GameType": "Game", "GameComplexity": "",
        "PlayingTime": [30, 90], "PlayerCounts": [4, 4], "Tags": ["Dominoes"],
        "Gravity": 0.5, "PlayArea": 0.6, "Table": "Table_None", "Sky": "Sky_Museum", "Note": "",
        "TabStates": {}, "Grid": {"Type": 0, "Lines": False, "Snapping": False},
        "Lighting": {"LightIntensity": 0.6, "LightColor": {"r": 1.0, "g": 0.97, "b": 0.9},
                     "AmbientIntensity": 1.2, "AmbientType": 0,
                     "AmbientSkyColor": {"r": 0.5, "g": 0.5, "b": 0.5},
                     "AmbientEquatorColor": {"r": 0.5, "g": 0.5, "b": 0.5},
                     "AmbientGroundColor": {"r": 0.5, "g": 0.5, "b": 0.5},
                     "ReflectionIntensity": 1.0, "LutIndex": 0, "LutContribution": 1.0, "LutURL": ""},
        "Hands": {"Enable": False, "DisableUnused": True, "Hiding": 0},
        "ComponentTags": {"labels": [{"displayed": "noes_tile", "normalized": "noes_tile"},
                                     {"displayed": "noes_fixed", "normalized": "noes_fixed"}]},
        "Turns": {"Enable": False, "Type": 0, "TurnOrder": [], "Reverse": False, "SkipEmpty": False,
                  "DisableInteractions": False, "PassTurns": True, "TurnColor": ""},
        "CameraStates": [], "DecalPallet": [], "LuaScript": script, "LuaScriptState": "",
        "XmlUI": ui, "CustomUIAssets": ui_assets(base), "SnapPoints": [], "ObjectStates": objects(base),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", choices=["local", "github"], default="local")
    ap.add_argument("--sha")
    ap.add_argument("--out", default=str(SAVES / "Noes.json"))
    a = ap.parse_args()
    base = asset_base(a.assets, a.sha)
    STATE_FILE.write_text(base + "\n", encoding="utf-8")
    data = save_json(base)
    out = Path(a.out)
    out.write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
    lua_lines = data["LuaScript"].count("\n")
    print(f"wrote {out} ({len(data['ObjectStates'])} objects, Global script {lua_lines} lines)")
    print(f"asset base: {base}")


if __name__ == "__main__":
    main()
