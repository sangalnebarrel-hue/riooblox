#!/usr/bin/env python3
"""Offline preview renderer for part-built models (QA without Roblox Studio).

Reads the JSON written by tools/qa/scene.luau (one entry per BasePart: shape, CFrame, size,
colour, material, transparency) and ray-casts it with numpy into a PNG: several camera views
side by side. Supported shapes: Block, Ball, Ellipsoid (SpecialMesh Sphere), Cylinder (Roblox axis = local X), Wedge (full
height at local +Z, slope down towards -Z, as WedgePart). CornerWedge is drawn as a Wedge and
other parts (MeshPart, Truss) as their bounding box. Neon is emissive, transparent parts are
blended over the opaque image (one layer).

usage: python3 -I tools/qa/render.py scene.json out.png [--views iso,front,side,top] [--size 360]
       [--yaw 35 --pitch 22] [--bg 30,32,40]
"""
import argparse
import json
import math

import numpy as np
from PIL import Image, ImageDraw

EPS = 1e-6


def rot_from_json(r):
    # r = 9 numbers, row-major R00..R22 (columns are RightVector, UpVector, -LookVector).
    return np.array(r, dtype=np.float64).reshape(3, 3)


def intersect(part, o, d):
    """o, d: (N,3) world rays. Returns t (N,) with inf for misses and normals (N,3) world."""
    R = part["R"]
    c = part["P"]
    lo = (o - c) @ R  # local origin (R columns are local axes)
    ld = d @ R
    hx, hy, hz = part["S"] / 2.0
    n = o.shape[0]
    t_out = np.full(n, np.inf)
    nrm = np.zeros((n, 3))
    shape = part["shape"]
    with np.errstate(divide="ignore", invalid="ignore"):
        if shape == "Ellipsoid":
            # SpecialMesh Sphere: an ellipsoid filling the part size
            sc = np.array([max(hx, EPS), max(hy, EPS), max(hz, EPS)])
            so, sd = lo / sc, ld / sc
            a = np.sum(sd * sd, axis=1)
            b = np.sum(so * sd, axis=1)
            cc = np.sum(so * so, axis=1) - 1.0
            disc = b * b - a * cc
            ok = disc >= 0
            sq = np.sqrt(np.where(ok, disc, 0))
            t0 = (-b - sq) / a
            t1 = (-b + sq) / a
            t = np.where(t0 > EPS, t0, t1)
            ok &= t > EPS
            p = lo + ld * t[:, None]
            t_out = np.where(ok, t, np.inf)
            nrm = p / (sc * sc)
        elif shape == "Ball":
            r = min(hx, hy, hz)
            b = np.sum(lo * ld, axis=1)
            cc = np.sum(lo * lo, axis=1) - r * r
            a = np.sum(ld * ld, axis=1)
            disc = b * b - a * cc
            ok = disc >= 0
            sq = np.sqrt(np.where(ok, disc, 0))
            t0 = (-b - sq) / a
            t1 = (-b + sq) / a
            t = np.where(t0 > EPS, t0, t1)
            ok &= t > EPS
            p = lo + ld * t[:, None]
            ln = p / max(r, EPS)
            t_out = np.where(ok, t, np.inf)
            nrm = ln
        elif shape == "Cylinder":
            r = min(hy, hz)
            # side
            a = ld[:, 1] ** 2 + ld[:, 2] ** 2
            b = lo[:, 1] * ld[:, 1] + lo[:, 2] * ld[:, 2]
            cc = lo[:, 1] ** 2 + lo[:, 2] ** 2 - r * r
            disc = b * b - a * cc
            ok = (disc >= 0) & (a > EPS)
            sq = np.sqrt(np.where(ok, disc, 0))
            ts = (-b - sq) / np.where(a > EPS, a, 1)
            xs = lo[:, 0] + ld[:, 0] * ts
            side_ok = ok & (ts > EPS) & (np.abs(xs) <= hx)
            # caps
            best = np.where(side_ok, ts, np.inf)
            side_n = np.zeros((n, 3))
            ps = lo + ld * ts[:, None]
            side_n[:, 1] = ps[:, 1]
            side_n[:, 2] = ps[:, 2]
            ln = side_n
            for sgn in (-1.0, 1.0):
                tc = (sgn * hx - lo[:, 0]) / ld[:, 0]
                pc = lo + ld * tc[:, None]
                cap_ok = (tc > EPS) & (pc[:, 1] ** 2 + pc[:, 2] ** 2 <= r * r) & (tc < best)
                best = np.where(cap_ok, tc, best)
                capn = np.zeros((n, 3))
                capn[:, 0] = sgn
                ln = np.where(cap_ok[:, None], capn, ln)
            t_out = best
            nrm = ln
        else:
            # convex: box slabs (+ wedge half-space)
            tmin = np.full(n, -np.inf)
            tmax = np.full(n, np.inf)
            ln = np.zeros((n, 3))
            for axis, h in ((0, hx), (1, hy), (2, hz)):
                inv = 1.0 / ld[:, axis]
                t1 = (-h - lo[:, axis]) * inv
                t2 = (h - lo[:, axis]) * inv
                tnear = np.minimum(t1, t2)
                tfar = np.maximum(t1, t2)
                # parallel rays outside the slab miss
                par = np.abs(ld[:, axis]) < EPS
                outside = par & (np.abs(lo[:, axis]) > h)
                tnear = np.where(par, np.where(outside, np.inf, -np.inf), tnear)
                tfar = np.where(par, np.where(outside, -np.inf, np.inf), tfar)
                upd = tnear > tmin
                axn = np.zeros((n, 3))
                axn[:, axis] = np.where(t1 < t2, -1.0, 1.0)
                ln = np.where(upd[:, None], axn, ln)
                tmin = np.maximum(tmin, tnear)
                tmax = np.minimum(tmax, tfar)
            if shape in ("Wedge", "CornerWedge"):
                # inside: y/hy - z/hz <= 0
                pn = np.array([0.0, 1.0 / max(hy, EPS), -1.0 / max(hz, EPS)])
                denom = ld @ pn
                num = -(lo @ pn)
                th = num / denom
                enter = denom < -EPS
                exit_ = denom > EPS
                inside0 = (lo @ pn) <= 0
                upd = enter & (th > tmin)
                ln = np.where(upd[:, None], np.broadcast_to(pn / np.linalg.norm(pn), (n, 3)), ln)
                tmin = np.where(enter, np.maximum(tmin, th), tmin)
                tmax = np.where(exit_, np.minimum(tmax, th), tmax)
                par = np.abs(denom) <= EPS
                tmin = np.where(par & ~inside0, np.inf, tmin)
            ok = (tmax >= tmin) & (tmax > EPS)
            t = np.where(tmin > EPS, tmin, np.inf)
            ok &= np.isfinite(t)
            t_out = np.where(ok, t, np.inf)
            nrm = ln
    world_n = nrm @ R.T
    norm = np.linalg.norm(world_n, axis=1)
    world_n = world_n / np.where(norm > EPS, norm, 1)[:, None]
    return t_out, world_n


MAT_SPEC = {"Metal": 0.45, "DiamondPlate": 0.35, "Foil": 0.6, "Glass": 0.7, "Ice": 0.4, "Marble": 0.25,
            "SmoothPlastic": 0.15, "Plastic": 0.08, "Granite": 0.1, "Glacier": 0.35, "Pebble": 0.05}


def shade(color, normal, viewdir, material, light):
    if material == "Neon":
        return np.clip(color * 1.35 + 0.08, 0, 1)
    ndl = np.clip(normal @ light, 0, 1)
    fill = np.clip(normal @ np.array([-0.5, 0.25, 0.6]), 0, 1) * 0.18
    amb = 0.36 + 0.12 * normal[:, 1:2].clip(0, 1)
    base = color * (amb + 0.62 * ndl[:, None] + fill[:, None])
    spec_k = MAT_SPEC.get(material, 0.05)
    if spec_k > 0:
        h = light - viewdir
        h = h / np.linalg.norm(h, axis=1)[:, None]
        spec = np.clip(np.sum(normal * h, axis=1), 0, 1) ** 40 * spec_k
        base = base + spec[:, None]
    return np.clip(base, 0, 1)


def camera_rays(target, radius, yaw, pitch, size, fov=30.0):
    yaw_r, pitch_r = math.radians(yaw), math.radians(pitch)
    fwd = np.array([-math.sin(yaw_r) * math.cos(pitch_r), -math.sin(pitch_r), -math.cos(yaw_r) * math.cos(pitch_r)])
    dist = radius / math.sin(math.radians(fov / 2)) * 1.05
    eye = target - fwd * dist
    up0 = np.array([0.0, 1.0, 0.0]) if abs(fwd[1]) < 0.99 else np.array([0.0, 0.0, -1.0])
    right = np.cross(fwd, up0)
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    half = math.tan(math.radians(fov / 2))
    xs = np.linspace(-half, half, size)
    ys = np.linspace(half, -half, size)
    gx, gy = np.meshgrid(xs, ys)
    d = fwd[None, :] + gx.reshape(-1, 1) * right[None, :] + gy.reshape(-1, 1) * up[None, :]
    d /= np.linalg.norm(d, axis=1)[:, None]
    o = np.broadcast_to(eye, d.shape).copy()
    return o, d


def render_view(parts, yaw, pitch, size, bg):
    opaque = [p for p in parts if p["T"] < 0.98]
    if not opaque:
        return np.ones((size, size, 3)) * np.array(bg) / 255.0
    pts = []
    for p in opaque:
        for sx in (-0.5, 0.5):
            for sy in (-0.5, 0.5):
                for sz in (-0.5, 0.5):
                    pts.append(p["P"] + p["R"] @ (p["S"] * np.array([sx, sy, sz])))
    pts = np.array(pts)
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    target = (lo + hi) / 2
    radius = max(np.linalg.norm(hi - lo) / 2, 0.5)
    o, d = camera_rays(target, radius, yaw, pitch, size)
    n = o.shape[0]
    light = np.array([0.45, 0.8, 0.35])
    light /= np.linalg.norm(light)
    depth = np.full(n, np.inf)
    col = np.tile(np.array(bg, dtype=np.float64) / 255.0, (n, 1))
    # vertical gradient background
    grad = np.linspace(1.08, 0.78, size).repeat(size)
    col = np.clip(col * grad[:, None], 0, 1)
    solid = [p for p in opaque if p["T"] <= 0.25]
    clear = [p for p in opaque if p["T"] > 0.25]
    for p in solid:
        t, nr = intersect(p, o, d)
        hit = t < depth
        if not hit.any():
            continue
        depth = np.where(hit, t, depth)
        c = shade(np.broadcast_to(p["C"], (n, 3)), nr, d, p["M"], light)
        col = np.where(hit[:, None], c, col)
    # transparent layer, back-to-front by part distance
    for p in sorted(clear, key=lambda q: -np.linalg.norm(q["P"] - o[0])):
        t, nr = intersect(p, o, d)
        hit = t < depth
        if not hit.any():
            continue
        a = 1.0 - p["T"]
        if p["M"] == "Neon":
            a = min(1.0, a * 1.4)
        c = shade(np.broadcast_to(p["C"], (n, 3)), nr, d, p["M"], light)
        col = np.where(hit[:, None], col * (1 - a) + c * a, col)
    # edge darkening from depth discontinuities (reads silhouettes like Studio outlines)
    dep = depth.reshape(size, size)
    finite = np.isfinite(dep)
    dd = np.where(finite, dep, dep[finite].max() * 3 if finite.any() else 1)
    edge = np.zeros_like(dd, dtype=bool)
    rel = 0.03 * radius
    edge[1:, :] |= np.abs(dd[1:, :] - dd[:-1, :]) > rel
    edge[:, 1:] |= np.abs(dd[:, 1:] - dd[:, :-1]) > rel
    img = col.reshape(size, size, 3)
    img = np.where(edge[:, :, None], img * 0.55, img)
    return img


# yaw 180 looks at the model's front (models face -Z, the Roblox LookVector).
VIEWS = {"iso": (215, 22), "iso2": (145, 22), "front": (180, 4), "back": (0, 4), "side": (90, 4), "top": (180, 89), "low": (215, -12)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scene")
    ap.add_argument("out")
    ap.add_argument("--views", default="iso,front,side,top")
    ap.add_argument("--size", type=int, default=360)
    ap.add_argument("--bg", default="34,36,46")
    ap.add_argument("--title", default=None)
    args = ap.parse_args()
    data = json.load(open(args.scene))
    entries = data["parts"] if isinstance(data, dict) else data
    parts = []
    for e in entries:
        parts.append(dict(shape=e["shape"], P=np.array(e["p"], dtype=np.float64), R=rot_from_json(e["r"]),
                          S=np.maximum(np.array(e["s"], dtype=np.float64), 0.02), C=np.array(e["c"], dtype=np.float64),
                          M=e.get("m", "Plastic"), T=float(e.get("t", 0))))
    bg = [int(x) for x in args.bg.split(",")]
    views = [v.strip() for v in args.views.split(",") if v.strip()]
    tiles = []
    for v in views:
        yaw, pitch = VIEWS[v] if v in VIEWS else [float(x) for x in v.split(":")]
        tiles.append((render_view(parts, yaw, pitch, args.size, bg) * 255).astype(np.uint8))
    strip = np.concatenate(tiles, axis=1)
    im = Image.fromarray(strip)
    title = args.title or (data.get("title") if isinstance(data, dict) else None)
    if title:
        dr = ImageDraw.Draw(im)
        dr.text((8, 6), "%s  (%d parts)" % (title, len(parts)), fill=(240, 240, 240))
    im.save(args.out)
    print("wrote", args.out, im.size, len(parts), "parts")


if __name__ == "__main__":
    main()
