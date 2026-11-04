# VR tile handling

Tabletop Simulator runs on your PC. For a Quest 3, connect through SteamVR
(for example, using Steam Link) and launch Tabletop Simulator in VR.
Use the Touch controllers for this workflow.

## Physical tiles

During play, click **Physical tiles: off** in your private hand panel to turn
it on. This preference applies to your seat for the current session and starts
off when a save is loaded. You can enable it while waiting for your turn.

On your turn, a private, face-up 3D rack appears just behind your public rack.
Grab a tile, rotate it to inspect it, and release it near a green placement
marker to play. The game snaps the authoritative tile into the correct position.
A release outside the markers, more than three units above/below the tabletop
tile height, or an illegal move returns the private tile to its rack. Forced
opening tiles and commitments still apply. If you have no legal move, use
**¡Paso!** in the hand panel.

Only the active player's enabled rack is spawned. Other players and spectators
cannot see these private tiles, even when they are turned over. The public
face-down rack still shows your tile count. The private tiles are disposable
interaction copies; they never add tiles to the authoritative hand or board.
They are removed on a turn change, hand end, reset, toggle off, or save reload.

The existing hand-panel buttons, placement-marker buttons, taunts, and physical
shuffle/draw remain available. Physical mode can also be used with a mouse.

## Controller bindings

In SteamVR's controller bindings for Tabletop Simulator, check:

- **Grab**: grip, held. Use the VR action in SteamVR, rather than the desktop
  Grab binding in TTS's regular Controls window.
- **Activate Laser Pointer** and **Interface Click**: trigger.
- **Main Menu** and **Enable Movement**: accessible controller buttons.

See the [official TTS VR controls](https://api.tabletopsimulator.com/vr/) and
[Steam Link setup for Quest](https://help.steampowered.com/en/faqs/view/0E2C-406B-9135-38A4).
Bindings can vary with the selected SteamVR profile.

## Build and automated checks

Install Python and `lupa`, then run:

```text
python tools/run_tests.py
python tools/build.py --assets github --sha <published-asset-commit> --out Noes-VR.json
```

The tests cover rule/layout behavior and physical interaction events using
stubbed TTS objects. They do not emulate SteamVR, headset tracking, rendering,
network visibility, or physics.

## Headset smoke test (required before claiming Quest 3 verification)

1. Load the built save on the PC; connect the Quest 3 and launch TTS in VR.
2. Seat players and start a hand. Test loose-tile pickup, rotation, release,
   and manual drawing during the sopa.
3. Enable physical tiles. On your turn, verify all private rack tiles load and
   can be picked up, rotated, and released with both controllers.
4. With another client seated elsewhere and then spectating, confirm the
   private rack/held tile faces never appear to that client. Confirm the public
   rack count remains correct.
5. Grab the forced opening tile and release near the lead marker. Confirm
   exactly one tile is played, the board tile locks, and private copies vanish.
6. Test a tile matching both ends: release at each end in separate turns.
   Try an illegal tile, an off-target drop, a release high above the marker,
   and a tile other than a committed tile. Confirm no illegal play occurs.
7. Test pickup/drop with both hands, a quick release/regrab, switching between
   panel and physical play, turning the mode off/on, passing, a winning play,
   resetting, and saving/loading during play. Confirm no stale private copies
   remain and panel play still works with mixed desktop/VR players.

Quest 3 hardware and multiplayer visual/physics behavior have not yet been
verified by the automated tests.
