#!/usr/bin/env python3
"""Tiny software renderer for sanity-checking generated OBJ + texture (no Blender needed).

usage: preview.py MODEL.obj TEXTURE.jpg OUT.png [--flip] [--yaw DEG] [--pitch DEG]
"""
from __future__ import annotations

import argparse
import math

import numpy as np
from PIL import Image


def load_obj(path):
    v, vt, vn, faces = [], [], [], []
    for line in open(path, encoding="utf-8"):
        if line.startswith("v "):
            v.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("vt "):
            vt.append([float(x) for x in line.split()[1:3]])
        elif line.startswith("vn "):
            vn.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("f "):
            idx = []
            for part in line.split()[1:]:
                bits = part.split("/")
                idx.append([int(bits[0]) - 1,
                            int(bits[1]) - 1 if len(bits) > 1 and bits[1] else -1,
                            int(bits[2]) - 1 if len(bits) > 2 and bits[2] else -1])
            for k in range(1, len(idx) - 1):
                faces.append([idx[0], idx[k], idx[k + 1]])
    return np.array(v), np.array(vt) if vt else None, np.array(vn) if vn else None, np.array(faces)


def rot(yaw, pitch, roll=0.0):
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    cr, sr = math.cos(math.radians(roll)), math.sin(math.radians(roll))
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    rz = np.array([[cr, -sr, 0], [sr, cr, 0], [0, 0, 1]])
    return rx @ ry @ rz


def render(obj, tex_path, out, size=900, yaw=20.0, pitch=55.0, roll=0.0, scale=None):
    v, vt, vn, f = load_obj(obj)
    tex = np.asarray(Image.open(tex_path).convert("RGB"), np.float32) / 255.0 if tex_path else None
    th, tw = (tex.shape[0], tex.shape[1]) if tex is not None else (1, 1)
    m = rot(yaw, pitch, roll)
    pv = v @ m.T
    pn = vn @ m.T if vn is not None else None
    ext = np.abs(pv[:, :2]).max()
    s = scale or (size * 0.45 / ext)
    sx = size / 2 + pv[:, 0] * s
    sy = size / 2 - pv[:, 1] * s
    depth = pv[:, 2]
    img = np.full((size, size, 3), 0.18, np.float32)
    zbuf = np.full((size, size), -1e9, np.float32)
    light = np.array([-0.4, 0.8, 0.45])
    light /= np.linalg.norm(light)
    for tri in f:
        ids = tri[:, 0]
        x0, y0, x1, y1 = sx[ids].min(), sy[ids].min(), sx[ids].max(), sy[ids].max()
        xa, xb = max(int(x0), 0), min(int(x1) + 1, size - 1)
        ya, yb = max(int(y0), 0), min(int(y1) + 1, size - 1)
        if xa > xb or ya > yb:
            continue
        px, py = np.meshgrid(np.arange(xa, xb + 1) + 0.5, np.arange(ya, yb + 1) + 0.5)
        ax, ay = sx[ids[0]], sy[ids[0]]
        bx, by = sx[ids[1]], sy[ids[1]]
        cx, cy = sx[ids[2]], sy[ids[2]]
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        w0 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
        w1 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
        if not inside.any():
            continue
        z = w0 * depth[ids[0]] + w1 * depth[ids[1]] + w2 * depth[ids[2]]
        sub = zbuf[ya:yb + 1, xa:xb + 1]
        upd = inside & (z > sub)
        if not upd.any():
            continue
        sub[upd] = z[upd]
        if pn is not None:
            ni = tri[:, 2]
            n = (w0[..., None] * pn[ni[0]] + w1[..., None] * pn[ni[1]] + w2[..., None] * pn[ni[2]])
            n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9
            shade = 0.35 + 0.65 * np.clip(n @ light, 0, 1)
        else:
            shade = np.ones_like(w0)
        if tex is not None and vt is not None:
            ti = tri[:, 1]
            u = w0 * vt[ti[0], 0] + w1 * vt[ti[1], 0] + w2 * vt[ti[2], 0]
            vv = w0 * vt[ti[0], 1] + w1 * vt[ti[1], 1] + w2 * vt[ti[2], 1]
            tx = np.clip((u * tw).astype(int), 0, tw - 1)
            ty = np.clip(((1 - vv) * th).astype(int), 0, th - 1)
            col = tex[ty, tx]
        else:
            col = np.full(w0.shape + (3,), 0.8)
        region = img[ya:yb + 1, xa:xb + 1]
        region[upd] = (col * shade[..., None])[upd]
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("obj")
    ap.add_argument("tex")
    ap.add_argument("out")
    ap.add_argument("--yaw", type=float, default=20)
    ap.add_argument("--pitch", type=float, default=55)
    ap.add_argument("--roll", type=float, default=0)
    ap.add_argument("--size", type=int, default=900)
    a = ap.parse_args()
    render(a.obj, a.tex if a.tex != "-" else None, a.out, a.size, a.yaw, a.pitch, a.roll)
