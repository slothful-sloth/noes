# Noes

Puerto Rican partner dominoes for [Tabletop Simulator](https://store.steampowered.com/app/286160/) (TTS), for four players.
The full rules, the scoring options and the feature list are in [`noes_rules.md`](noes_rules.md).

## Playing

Download `Noes_Online.json` from the [latest release](https://github.com/slothful-sloth/noes/releases/latest)
and put it in your TTS `Saves` folder:

| System | Saves folder |
|---|---|
| Windows | `%USERPROFILE%\Documents\My Games\Tabletop Simulator\Saves` (or `OneDrive\Documents\…` when Documents is redirected) |
| macOS | `~/Library/Tabletop Simulator/Saves` |
| Linux | `~/.local/share/Tabletop Simulator/Saves` |

In TTS, open **Games → Save & Load** and load **Noes - Partner Dominoes (online)**, then host a multiplayer game.
Only the host needs the file. Players who join get the game from the host and download the tiles,
textures and sounds from this repository.

## Development setup

You need Git, Python 3.12 or newer, and TTS installed through Steam (launch it once so it creates its folders).

### Linux / macOS

```sh
git clone https://github.com/slothful-sloth/noes.git
cd noes
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

### Windows (PowerShell)

```powershell
git clone https://github.com/slothful-sloth/noes.git
cd noes
py -m venv .venv
.venv\Scripts\pip install -r requirements.txt
```

In the commands below, replace `.venv/bin/python` with `.venv\Scripts\python`.

### Optional: cairosvg

`cairosvg` is only needed to regenerate the flag textures (`tools/gen_textures.py tiles` and `table`).
Everything else works without it.

- Fedora: `sudo dnf install cairo`, then `.venv/bin/pip install cairosvg`
- Debian/Ubuntu: `sudo apt install libcairo2`, then `.venv/bin/pip install cairosvg`
- Windows: `cairosvg` needs a Cairo DLL (for example from the GTK runtime or MSYS2) on `PATH`.
  It is simpler to leave flag regeneration to a Linux machine.

## Day-to-day workflow

```sh
.venv/bin/python tools/run_tests.py          # pure rules and layout tests (Lua 5.2 via lupa)
.venv/bin/python tools/sim.py --series 12    # full series against a mock TTS API
.venv/bin/python tools/build.py              # write Saves/Noes.json with local file:// assets
```

Load **Noes** in TTS. While it is running, script and UI changes can be pushed into the open game
without reloading:

```sh
.venv/bin/python tools/tts.py push           # bundle src/ + ui/ and Save & Play into TTS
.venv/bin/python tools/tts.py exec 'print(S.phase)'
```

`tools/tts.py` uses the TTS [External Editor API](https://api.tabletopsimulator.com/externaleditorapi/)
on `localhost:39999`, with replies on `localhost:39998`. Close any other TTS editor plugin (such as the
VS Code or Atom extension) first, because it holds port 39998.

Notes:

- New or changed images (tile atlases, UI tile images, table faces) only show after the save is
  rebuilt with `build.py` and reloaded in TTS. A `push` only replaces the script and the XML UI.
- TTS caches assets by URL, including local files. `build.py` serves `assets/` through
  `.build/assets-<hash>` so that changed assets get a new URL. On Windows this is a directory
  junction, or a copy if a junction cannot be created.
- If you moved the TTS save location in its settings, set `TTS_SAVES` to that folder, or pass
  `--out PATH` to `build.py`.
- In the lobby, **Developer mode** lets one person drive every seat to test taunts, passes and
  endings alone.
- TTS autosaves appear under the same name in the load menu. The clean development save is the file `Noes`.

## Regenerating assets

The generated assets are committed, so this is only needed after changing a generator.

```sh
.venv/bin/python tools/gen_tiles.py          # tile meshes and colliders
.venv/bin/python tools/gen_table.py          # table, border, scoreboard, markers, rack zones
.venv/bin/python tools/gen_textures.py [tiles|table|ui|board]
.venv/bin/python tools/gen_misc.py           # white.png and sounds
.venv/bin/python tools/preview.py --help     # software render of a mesh for quick checks
```

## Publishing the online save

Online games must load assets from GitHub, not from local files. Asset URLs are pinned to a commit,
so commit and push the assets first, then build against that commit:

```sh
git push
.venv/bin/python tools/build.py --assets github --sha <commit with the current assets> \
    --out "<Saves folder>/Noes_Online.json"
.venv/bin/python tools/build.py              # switch tools/tts.py back to local assets
```

Then attach the new `Noes_Online.json` to a GitHub release:

```sh
gh release create vX.Y.Z "<Saves folder>/Noes_Online.json" --title "Noes vX.Y.Z" --notes "..."
```

If assets have not changed, keep the earlier asset commit with `--sha`, so players' TTS caches stay valid.

## Layout

| Path | Contents |
|---|---|
| `src/` | Global Lua script, split into modules (`rules`, `layout`, `game`, `ui`, …) that `build.py` bundles |
| `ui/Global.xml` | XML UI; `build.py` fills in the four hand panels |
| `assets/` | Generated meshes, textures, UI images and sounds, plus third-party sources in `assets/src/downloads/` |
| `tools/` | Build, TTS client, simulator, tests and asset generators |
| `tests/` | Lua tests for `rules.lua` and `layout.lua` |

Third-party sources and licences are listed in [`ATTRIBUTION.md`](ATTRIBUTION.md).
