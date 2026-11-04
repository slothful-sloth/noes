#!/usr/bin/env python3
"""Tabletop Simulator External Editor API client.

TTS listens on localhost:39999; it answers by connecting to localhost:39998.
Docs: https://api.tabletopsimulator.com/externaleditorapi/

usage:
  tts.py push            bundle src/ + ui/ and Save & Play them into the running game (Global only)
  tts.py exec 'lua...'   run Lua in Global, print output
  tts.py execf FILE.lua  run a Lua file in Global
  tts.py listen [secs]   print messages from TTS
"""
from __future__ import annotations

import json
import socket
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build  # noqa: E402

HOST = "127.0.0.1"
TO_TTS, FROM_TTS = 39999, 39998


class Listener:
    def __init__(self):
        self.msgs: list[dict] = []
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((HOST, FROM_TTS))
        self.sock.listen(8)
        self.sock.settimeout(0.2)
        self.stop = False
        self.t = threading.Thread(target=self.run, daemon=True)
        self.t.start()

    def run(self):
        while not self.stop:
            try:
                conn, _ = self.sock.accept()
            except socket.timeout:
                continue
            with conn:
                conn.settimeout(2)
                buf = b""
                while True:
                    try:
                        chunk = conn.recv(65536)
                    except socket.timeout:
                        break
                    if not chunk:
                        break
                    buf += chunk
            text = buf.decode("utf-8", "replace").strip()
            dec = json.JSONDecoder()
            i = 0
            while i < len(text):
                try:
                    obj, j = dec.raw_decode(text, i)
                except json.JSONDecodeError:
                    break
                self.msgs.append(obj)
                show(obj)
                i = j
                while i < len(text) and text[i].isspace():
                    i += 1

    def close(self):
        self.stop = True
        self.t.join()
        self.sock.close()


def show(m: dict):
    mid = m.get("messageID")
    if mid == 2:
        print("[print]", m.get("message"))
    elif mid == 3:
        print("[ERROR]", m.get("guid"), m.get("error"))
    elif mid == 1:
        print("[reloaded]", len(m.get("scriptStates", [])), "script states")
    elif mid == 4:
        print("[custom]", json.dumps(m.get("customMessage")))
    elif mid == 5:
        print("[return]", json.dumps(m.get("returnValue")))
    elif mid == 6:
        print("[game saved]")
    elif mid == 7:
        print("[object created]", m.get("guid"))
    else:
        print("[msg]", json.dumps(m)[:500])


def send(payload: dict):
    with socket.create_connection((HOST, TO_TTS), timeout=5) as s:
        s.sendall(json.dumps(payload).encode())


def with_listener(payload: dict, wait: float):
    lst = Listener()
    try:
        send(payload)
        time.sleep(wait)
    finally:
        lst.close()
    return lst.msgs


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    cmd = argv[0]
    if cmd == "push":
        script, ui = build.bundle()
        msgs = with_listener({"messageID": 1, "scriptStates": [
            {"name": "Global", "guid": "-1", "script": script, "ui": ui}]}, float(argv[1]) if len(argv) > 1 else 6)
        return 1 if any(m.get("messageID") == 3 for m in msgs) else 0
    if cmd in ("exec", "execf"):
        code = argv[1] if cmd == "exec" else Path(argv[1]).read_text(encoding="utf-8")
        wait = float(argv[2]) if len(argv) > 2 else 3
        msgs = with_listener({"messageID": 3, "guid": "-1", "script": code}, wait)
        return 1 if any(m.get("messageID") == 3 for m in msgs) else 0
    if cmd == "listen":
        lst = Listener()
        try:
            time.sleep(float(argv[1]) if len(argv) > 1 else 30)
        finally:
            lst.close()
        return 0
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
