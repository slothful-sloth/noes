#!/usr/bin/env python3
"""Run the pure-logic Lua tests under Lua 5.2 (close to TTS's MoonSharp) via lupa."""
import sys
from pathlib import Path

from lupa import lua52

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    lua = lua52.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.R = lua.execute((ROOT / "src/rules.lua").read_text(encoding="utf-8"))
    g.Layout = lua.execute((ROOT / "src/layout.lua").read_text(encoding="utf-8"))
    failed = lua.execute((ROOT / "tests/test_logic.lua").read_text(encoding="utf-8"))
    interactions = lua52.LuaRuntime(unpack_returned_tuples=True)
    interactions.globals().SOURCE_ROOT = ROOT.as_posix()
    interactions.execute('package.path = SOURCE_ROOT .. "/src/?.lua;" .. package.path')
    failed = interactions.execute((ROOT / "tests/test_physical.lua").read_text(encoding="utf-8")) or failed
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
