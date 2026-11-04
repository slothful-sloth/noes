#!/usr/bin/env python3
"""Generate the 28 domino tile meshes (OBJ) plus a box collider.

Geometry
  * Rounded box (all edges radius R) built from six tensor-product grids. Every box-surface
    point q is mapped to c + r * normalize(q - c), where c = clamp(q, inner box); flat areas stay
    flat and edges/corners become exact quarter-cylinders/spheres with analytic normals.
  * All faces share the same per-axis line sets, so seams coincide exactly (no cracks).
  * The top face (+Y) carries the pips as smooth spherical dimples, a divider groove across
    the middle and a domed spinner nub at the centre.

Conventions (shared with src/layout.lua and tools/gen_textures.py)
  * Long axis = X (length L), width = Z (W), thickness = Y (T); face on +Y.
  * "hi" half at +X in OBJ space. NOTE: Unity/TTS mirrors OBJ X on import; MIRROR_X below
    compensates so that in-game local +X is the hi half (verify with the TTS spike).
  * UVs point into a 4x8 atlas of 1024x512 cells (see ATLAS below).
"""
from __future__ import annotations

import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "models" / "tiles"

L, W, T = 2.0, 1.0, 0.42
R = 0.08                      # edge radius
PIP_OFF = 0.25                # pip offset from half centre
PIP_R = 0.085                 # pip radius
PIP_DEPTH = 0.035
GROOVE_HALF = 0.016           # half-width of the divider groove
GROOVE_DEPTH = 0.010
NUB_R = 0.065
NUB_H = 0.03
MIRROR_X = True               # negate X when writing OBJ (Unity flips X on import)

# Atlas: 4 columns x 8 rows of cells, each cell 1/4 x 1/8 of the texture.
ATLAS_COLS, ATLAS_ROWS = 4, 8
BACK_CELL = 28
BODY_CELL = 29


def cell_rect(index: int) -> tuple[float, float, float, float]:
    """(u0, v0, u1, v1) of an atlas cell; cell 0 is top-left in image space."""
    col, row = index % ATLAS_COLS, index // ATLAS_COLS
    u0 = col / ATLAS_COLS
    v1 = 1.0 - row / ATLAS_ROWS          # UV v grows upward; image rows grow downward
    return u0, v1 - 1.0 / ATLAS_ROWS, u0 + 1.0 / ATLAS_COLS, v1


def tile_index(hi: int, lo: int) -> int:
    """Atlas cell of a tile, in the order of rules.allTiles(): hi 0..6, lo 0..hi."""
    return hi * (hi + 1) // 2 + lo


PIP_LAYOUT = {
    0: [],
    1: [(0, 0)],
    2: [(-1, -1), (1, 1)],
    3: [(-1, -1), (0, 0), (1, 1)],
    4: [(-1, -1), (-1, 1), (1, -1), (1, 1)],
    5: [(-1, -1), (-1, 1), (0, 0), (1, -1), (1, 1)],
    6: [(-1, -1), (0, -1), (1, -1), (-1, 1), (0, 1), (1, 1)],
}


def pip_centres(hi: int, lo: int) -> list[tuple[float, float]]:
    """Pip centres in (x, z) tile space: hi half centred at x=+L/4, lo half at x=-L/4."""
    pts = []
    for value, cx in ((hi, L / 4), (lo, -L / 4)):
        for gx, gz in PIP_LAYOUT[value]:
            pts.append((cx + gx * PIP_OFF, gz * PIP_OFF))
    return pts


# --- grid lines -----------------------------------------------------------------

def band(centre: float, half: float, step: float) -> list[float]:
    n = max(2, int(round(2 * half / step)))
    return [centre - half + 2 * half * i / n for i in range(n + 1)]


def lines(extent: float, dense: list[float], dense_half: float, step: float, coarse: float) -> list[float]:
    """Sorted line positions in [-extent, extent]: rounded band near the ends, dense bands
    around `dense` centres, coarse fill elsewhere."""
    pts = set()
    inner = extent - R
    for i in range(5):                                   # rounded edge bands
        a = R * i / 4
        pts.add(round(inner + a, 5))
        pts.add(round(-inner - a, 5))
    for c in dense:
        for p in band(c, dense_half, step):
            if -inner < p < inner:
                pts.add(round(p, 5))
    srt = sorted(pts)
    out = [srt[0]]
    for p in srt[1:]:                                    # coarse fill of big gaps
        prev = out[-1]
        gap = p - prev
        if gap > coarse:
            n = int(math.ceil(gap / coarse))
            out.extend(round(prev + gap * k / n, 5) for k in range(1, n))
        if p - out[-1] > 1e-4:                           # drop near-duplicates
            out.append(p)
    return out


DENSE_HALF = PIP_R + 0.01
DENSE_STEP = 0.03
XS = lines(L / 2, [-L / 4 - PIP_OFF, -L / 4, -L / 4 + PIP_OFF, 0.0,
                   L / 4 - PIP_OFF, L / 4, L / 4 + PIP_OFF], DENSE_HALF, DENSE_STEP, 0.12)
ZS = lines(W / 2, [-PIP_OFF, 0.0, PIP_OFF], DENSE_HALF, DENSE_STEP, 0.12)
YS = lines(T / 2, [], 0.1, 0.05, 0.5)


# --- surface ------------------------------------------------------------------------

def clamp(v: float, lim: float) -> float:
    return max(-lim, min(lim, v))


def round_box(q: tuple[float, float, float]):
    hx, hy, hz = L / 2 - R, T / 2 - R, W / 2 - R
    c = (clamp(q[0], hx), clamp(q[1], hy), clamp(q[2], hz))
    d = (q[0] - c[0], q[1] - c[1], q[2] - c[2])
    n = math.sqrt(d[0] ** 2 + d[1] ** 2 + d[2] ** 2)
    if n < 1e-9:
        return q, None
    nrm = (d[0] / n, d[1] / n, d[2] / n)
    return (c[0] + nrm[0] * R, c[1] + nrm[1] * R, c[2] + nrm[2] * R), nrm


def top_height(x: float, z: float, pips: list[tuple[float, float]]) -> float:
    """Displacement (negative = inset) of the flat top at (x, z)."""
    h = 0.0
    for px, pz in pips:
        s = math.hypot(x - px, z - pz)
        if s < PIP_R:
            t = s / PIP_R
            h = min(h, -PIP_DEPTH * math.sqrt(max(0.0, 1 - t * t)))
    if abs(x) < GROOVE_HALF:
        t = abs(x) / GROOVE_HALF
        h = min(h, -GROOVE_DEPTH * (1 - t * t))
    s = math.hypot(x, z)
    if s < NUB_R:
        t = s / NUB_R
        h = max(h, NUB_H * math.sqrt(max(0.0, 1 - t * t)))
    return h


def build_tile(hi: int, lo: int):
    pips = pip_centres(hi, lo)
    verts: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    norms: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int]] = []
    face_cell = cell_rect(tile_index(hi, lo))
    back_cell = cell_rect(BACK_CELL)
    body_cell = cell_rect(BODY_CELL)
    flat_x, flat_z = L / 2 - R, W / 2 - R

    def uv_in(cell, s, t):
        u0, v0, u1, v1 = cell
        return u0 + (u1 - u0) * s, v0 + (v1 - v0) * t

    # Each face: (axis fixed, sign, line sets for the two free axes, uv mapping)
    specs = [
        ("y", +1, XS, ZS),   # top (face)
        ("y", -1, XS, ZS),   # bottom (back)
        ("x", +1, ZS, YS),
        ("x", -1, ZS, YS),
        ("z", +1, XS, YS),
        ("z", -1, XS, YS),
    ]
    for axis, sign, A, B in specs:
        base = len(verts)
        for b in B:
            for a in A:
                if axis == "y":
                    q = (a, sign * T / 2, b)
                elif axis == "x":
                    q = (sign * L / 2, b, a)
                else:
                    q = (a, b, sign * W / 2)
                p, n = round_box(q)
                if n is None:
                    n = {"x": (sign, 0, 0), "y": (0, sign, 0), "z": (0, 0, sign)}[axis]
                if axis == "y" and sign > 0 and abs(a) < flat_x - 1e-6 and abs(b) < flat_z - 1e-6:
                    h = top_height(a, b, pips)
                    if h != 0.0:
                        eps = 1e-3
                        gx = (top_height(a + eps, b, pips) - top_height(a - eps, b, pips)) / (2 * eps)
                        gz = (top_height(a, b + eps, pips) - top_height(a, b - eps, pips)) / (2 * eps)
                        ln = math.sqrt(gx * gx + 1 + gz * gz)
                        n = (-gx / ln, 1 / ln, -gz / ln)
                    p = (p[0], p[1] + h, p[2])
                verts.append(p)
                norms.append(n)
                if axis == "y" and sign > 0:
                    uvs.append(uv_in(face_cell, (a + L / 2) / L, (b + W / 2) / W))
                elif axis == "y":
                    # Back: viewed from below, so mirror X to read correctly when flipped over.
                    uvs.append(uv_in(back_cell, (-a + L / 2) / L, (b + W / 2) / W))
                else:
                    s = (a - A[0]) / (A[-1] - A[0])
                    t = (b - B[0]) / (B[-1] - B[0])
                    uvs.append(uv_in(body_cell, 0.05 + 0.9 * s, 0.05 + 0.9 * t))
        na, nb = len(A), len(B)
        is_top = axis == "y" and sign > 0
        # flat interior index range (lines strictly inside the rounded bands)
        lim_a = (L / 2 - R) if axis in ("y", "z") else (W / 2 - R)
        lim_b = (W / 2 - R) if axis == "y" else (T / 2 - R)
        ia = [i for i, a in enumerate(A) if abs(a) <= lim_a + 1e-6]
        ib = [j for j, b in enumerate(B) if abs(b) <= lim_b + 1e-6]
        i0, i1, j0, j1 = ia[0], ia[-1], ib[0], ib[-1]
        if not is_top:
            # boundary loop of the flat rectangle, fanned from an added centre vertex
            loop = ([base + j0 * na + i for i in range(i0, i1 + 1)] +
                    [base + j * na + i1 for j in range(j0 + 1, j1 + 1)] +
                    [base + j1 * na + i for i in range(i1 - 1, i0 - 1, -1)] +
                    [base + j * na + i0 for j in range(j1 - 1, j0, -1)])
            cpos = tuple((verts[loop[0]][k] + verts[base + j1 * na + i1][k]) / 2 for k in range(3))
            cuv = tuple((uvs[loop[0]][k] + uvs[base + j1 * na + i1][k]) / 2 for k in range(2))
            centre = len(verts)
            verts.append(cpos); uvs.append(cuv); norms.append(norms[loop[0]])
            for k in range(len(loop)):
                faces.append((centre, loop[k], loop[(k + 1) % len(loop)]))
        for j in range(nb - 1):
            for i in range(na - 1):
                if not is_top and i0 <= i < i1 and j0 <= j < j1:
                    continue
                v00 = base + j * na + i
                v10 = v00 + 1
                v01 = v00 + na
                v11 = v01 + 1
                faces.append((v00, v10, v11))
                faces.append((v00, v11, v01))
    return verts, uvs, norms, faces


def orient_faces(verts, norms, faces):
    """Make every triangle wind consistently with its vertex normals (counter-clockwise
    seen from outside, in OBJ's right-handed space)."""
    out = []
    for a, b, c in faces:
        pa, pb, pc = verts[a], verts[b], verts[c]
        e1 = (pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2])
        e2 = (pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2])
        cr = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        n = norms[a]
        if cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2] < 0:
            out.append((a, c, b))
        else:
            out.append((a, b, c))
    return out


def write_obj(path: Path, verts, uvs, norms, faces):
    sx = -1.0 if MIRROR_X else 1.0
    lines_out = ["# Noes domino tile, generated by tools/gen_tiles.py"]
    for x, y, z in verts:
        lines_out.append(f"v {sx * x:.4f} {y:.4f} {z:.4f}")
    for u, v in uvs:
        lines_out.append(f"vt {u:.5f} {v:.5f}")
    nidx, nlist = [], {}
    for x, y, z in norms:
        key = f"{sx * x:.4f} {y:.4f} {z:.4f}"
        if key not in nlist:
            nlist[key] = len(nlist) + 1
            lines_out.append("vn " + key)
        nidx.append(nlist[key])
    for a, b, c in faces:
        if MIRROR_X:          # mirroring flips winding; restore it
            b, c = c, b
        lines_out.append(f"f {a + 1}/{a + 1}/{nidx[a]} {b + 1}/{b + 1}/{nidx[b]} {c + 1}/{c + 1}/{nidx[c]}")
    path.write_text("\n".join(lines_out) + "\n", encoding="utf-8", newline="\n")


def write_collider(path: Path):
    hx, hy, hz = L / 2, T / 2, W / 2
    v = [(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    out = ["# Noes tile collider"] + [f"v {x:.4f} {y:.4f} {z:.4f}" for x, y, z in v]
    for a, b, c, d in quads:
        out.append(f"f {a + 1} {b + 1} {c + 1} {d + 1}")
    path.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")


def write_proxy_collider(path: Path):
    """Stand-in tiles must not touch the real tile they cover: their collider sits 40 units below."""
    out = ["# Noes proxy collider (deliberately far away)",
           "v 0 -40 0", "v 0.05 -40 0", "v 0 -40 0.05", "v 0 -39.95 0",
           "f 1 3 2", "f 1 2 4", "f 1 4 3", "f 2 3 4"]
    path.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    write_proxy_collider(OUT / "proxy_collider.obj")
    total = 0
    for hi in range(7):
        for lo in range(hi + 1):
            verts, uvs, norms, faces = build_tile(hi, lo)
            faces = orient_faces(verts, norms, faces)
            p = OUT / f"tile_{hi}{lo}.obj"
            write_obj(p, verts, uvs, norms, faces)
            total += p.stat().st_size
    write_collider(OUT / "tile_collider.obj")
    print(f"lines: X={len(XS)} Z={len(ZS)} Y={len(YS)}; verts/tile={len(verts)} tris/tile={len(faces)}")
    print(f"wrote 28 tiles, {total / 1e6:.1f} MB total, to {OUT}")


if __name__ == "__main__":
    main()
