#!/usr/bin/env python3
"""Tiny flat-shaded software renderer for part dumps (tools/render/dump.luau).
usage: render.py scenes.json out_dir [--size 360] [--views front,iso,top]
scenes.json: {"name": {"parts":[...], "camera": optional {"eye":[x,y,z],"at":[x,y,z],"fov":40}}}
"""
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw

def mat3(cf):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf
    return np.array([x, y, z]), np.array([[r00, r01, r02], [r10, r11, r12], [r20, r21, r22]])

def box_mesh():
    v = np.array([[sx, sy, sz] for sx in (-.5, .5) for sy in (-.5, .5) for sz in (-.5, .5)])
    f = [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
    return v, f

def sphere_mesh(n=10):
    v, f = [], []
    for i in range(n + 1):
        th = math.pi * i / n
        for j in range(2 * n):
            ph = 2 * math.pi * j / (2 * n)
            v.append([.5 * math.sin(th) * math.cos(ph), .5 * math.cos(th), .5 * math.sin(th) * math.sin(ph)])
    for i in range(n):
        for j in range(2 * n):
            a = i * 2 * n + j; b = i * 2 * n + (j + 1) % (2 * n)
            c = (i + 1) * 2 * n + (j + 1) % (2 * n); d = (i + 1) * 2 * n + j
            f.append((a, b, c, d))
    return np.array(v), f

def cyl_mesh(n=16):
    v = []
    for s in (-.5, .5):
        for j in range(n):
            a = 2 * math.pi * j / n
            v.append([s, .5 * math.cos(a), .5 * math.sin(a)])
    f = [(j, (j + 1) % n, n + (j + 1) % n, n + j) for j in range(n)]
    f.append(tuple(range(n))[::-1]); f.append(tuple(range(n, 2 * n)))
    return np.array(v), f

def wedge_mesh():
    # Roblox wedge: full height at +Z, slope down towards -Z.
    v = np.array([[-.5,-.5,-.5],[.5,-.5,-.5],[.5,-.5,.5],[-.5,-.5,.5],[-.5,.5,.5],[.5,.5,.5]])
    f = [(0,1,2,3),(3,2,5,4),(0,3,4),(1,5,2),(0,4,5,1)]
    return v, f

MESH = {"Block": box_mesh(), "Ball": sphere_mesh(), "Sphere": sphere_mesh(), "Cylinder": cyl_mesh(), "Wedge": wedge_mesh()}

def look_at(eye, at):
    f = np.array(at, float) - np.array(eye, float); f /= np.linalg.norm(f)
    up = np.array([0, 1, 0.])
    if abs(f @ up) > .99: up = np.array([0, 0, -1.])
    r = np.cross(f, up); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return np.array(eye, float), r, u, f

def render(parts, eye, at, fov, size):
    E, R, U, F = look_at(eye, at)
    light = np.array([-.4, .8, .45]); light /= np.linalg.norm(light)
    polys = []
    for p in parts:
        if p["t"] >= .98: continue
        pos, rot = mat3(p["cf"])
        shape = p["shape"] if p["shape"] in MESH else "Block"
        if shape == "Ball":
            d = min(p["size"]); size3 = np.array([d, d, d])
        else:
            size3 = np.array(p["size"])
        v, faces = MESH[shape]
        w = (rot @ (v * size3).T).T + pos
        col = np.array(p["color"])
        if p["mat"] == "Neon": col = np.minimum(1, col * 1.25 + .1)
        for face in faces:
            pts = w[list(face)]
            n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
            if np.linalg.norm(n) < 1e-9: continue
            n /= np.linalg.norm(n)
            cen = pts.mean(axis=0)
            if (cen - E) @ n > 0: continue  # backface
            rel = pts - E
            z = rel @ F
            if (z <= .05).any(): continue
            sx = rel @ R / z; sy = rel @ U / z
            k = size / (2 * math.tan(math.radians(fov) / 2))
            scr = [(size / 2 + a * k, size / 2 - b * k) for a, b in zip(sx, sy)]
            shade = .35 + .65 * max(0, n @ light) if p["mat"] != "Neon" else 1
            c = np.clip(col * shade, 0, 1)
            alpha = 1 - min(.85, p["t"])
            polys.append(((cen - E) @ F, scr, tuple(int(x * 255) for x in c), int(alpha * 255)))
    polys.sort(key=lambda t: -t[0])
    img = Image.new("RGBA", (size, size), (34, 44, 62, 255))
    for _, scr, c, a in polys:
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(layer).polygon(scr, fill=c + (a,), outline=(0, 0, 0, min(a, 90)))
        img.alpha_composite(layer) if a < 255 else ImageDraw.Draw(img).polygon(scr, fill=c + (255,), outline=(0, 0, 0, 90))
    return img

def bounds(parts):
    pts = []
    for p in parts:
        if p["t"] >= .98: continue
        pos, rot = mat3(p["cf"])
        h = np.array(p["size"]) / 2
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    pts.append(rot @ (h * [sx, sy, sz]) + pos)
    pts = np.array(pts)
    return pts.min(axis=0), pts.max(axis=0)

def main():
    src, out = sys.argv[1], sys.argv[2]
    size = 360
    views = ["front", "iso"]
    for i, a in enumerate(sys.argv):
        if a == "--size": size = int(sys.argv[i + 1])
        if a == "--views": views = sys.argv[i + 1].split(",")
    os.makedirs(out, exist_ok=True)
    scenes = json.load(open(src))
    sheet = []
    for name, sc in scenes.items():
        parts = [p for p in sc["parts"] if p and None not in p["size"] and None not in p["cf"]]
        lo, hi = bounds(parts)
        c = (lo + hi) / 2; r = np.linalg.norm(hi - lo) / 2 + .5
        imgs = []
        cams = sc.get("cameras") or {}
        for view in views:
            if view in cams:
                cam = cams[view]; img = render(parts, cam["eye"], cam["at"], cam.get("fov", 40), size)
            else:
                d = {"front": [0, 0, 1], "iso": [.7, .45, .75], "top": [0, 1, .02], "side": [1, 0, 0], "back": [0, 0, -1]}[view]
                d = np.array(d, float); d /= np.linalg.norm(d)
                dist = r / math.tan(math.radians(20)) * 1.05
                img = render(parts, c + d * dist, c, 40, size)
            imgs.append(img)
        row = Image.new("RGBA", (size * len(imgs), size + 22), (20, 26, 38, 255))
        for i, im in enumerate(imgs): row.paste(im, (i * size, 22))
        ImageDraw.Draw(row).text((6, 4), name, fill=(255, 255, 255, 255))
        row.save(os.path.join(out, name + ".png"))
        sheet.append(row)
    if sheet:
        w = max(r.width for r in sheet); cols = 2
        rows = math.ceil(len(sheet) / cols)
        big = Image.new("RGBA", (w * cols, sheet[0].height * rows), (10, 12, 18, 255))
        for i, r in enumerate(sheet): big.paste(r, ((i % cols) * w, (i // cols) * r.height))
        big.save(os.path.join(out, "_sheet.png"))
    print("rendered", len(sheet), "scenes to", out)

if __name__ == "__main__":
    main()
