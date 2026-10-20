#!/usr/bin/env python3
"""Render exported parts (tools/export_parts.luau JSON) to PNG previews for visual QA of offline-built geometry.

usage: python3 -I tools/render_preview.py <parts.json> <out_prefix> [--views top,iso_ne,iso_sw,front] [--size 1600]
       [--box x0,z0,x1,z1] [--hide-transparent 0.95] [--label] [--exclude REGEX] [--ymax Y] [--ymin Y] [--margin 20]

Views: top (orthographic from above, height-shaded), iso_ne / iso_sw / iso_nw / iso_se (30 deg isometric from that
corner), front (from -Z looking +Z), side (from +X looking -X). Faces are flat-shaded with a fixed light; Neon
parts are drawn bright; transparent parts are blended. Blocks, wedges, corner wedges, cylinders and balls are
approximated by their polygons; big faces are split into tiles so the painter's sort stays correct for large floors
and walls. --exclude drops parts whose name matches the regex, --ymax / --ymin drop parts centred above / below a
height (cut away walls or ceilings to look inside), --margin widens the --box part filter (default 20 studs; 0 for
tight close-ups). Writes <out_prefix>_<view>.png.
"""
import json
import math
import re
import sys

from PIL import Image, ImageDraw, ImageFont


def parse_args(argv):
    opts = {"views": "top,iso_ne,iso_sw", "size": 1600, "box": None, "hide": 0.95, "label": False, "exclude": None,
            "ymax": None, "ymin": None, "margin": 20.0}
    pos = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--views":
            opts["views"] = argv[i + 1]; i += 2
        elif a == "--size":
            opts["size"] = int(argv[i + 1]); i += 2
        elif a == "--box":
            opts["box"] = [float(v) for v in argv[i + 1].split(",")]; i += 2
        elif a == "--hide-transparent":
            opts["hide"] = float(argv[i + 1]); i += 2
        elif a == "--label":
            opts["label"] = True; i += 1
        elif a == "--exclude":
            opts["exclude"] = re.compile(argv[i + 1]); i += 2
        elif a == "--ymax":
            opts["ymax"] = float(argv[i + 1]); i += 2
        elif a == "--ymin":
            opts["ymin"] = float(argv[i + 1]); i += 2
        elif a == "--margin":
            opts["margin"] = float(argv[i + 1]); i += 2
        else:
            pos.append(a); i += 1
    return pos, opts


def mat_apply(r, v):
    return (r[0] * v[0] + r[1] * v[1] + r[2] * v[2], r[3] * v[0] + r[4] * v[1] + r[5] * v[2], r[6] * v[0] + r[7] * v[1] + r[8] * v[2])


def polys_for(part):
    """Return list of (world_polygon[list of xyz], normal_world) faces."""
    sx, sy, sz = [s / 2 for s in part["z"]]
    p = part["p"]
    r = part["r"]
    shape = part["s"]

    def w(v):
        a = mat_apply(r, v)
        return (p[0] + a[0], p[1] + a[1], p[2] + a[2])

    faces = []
    if shape in ("Block", "Ball", "Cylinder") or shape not in ("Wedge", "Corner"):
        if shape == "Cylinder":
            # cylinder along local X: approximate with an 8-gon prism
            n = 8
            ring_l, ring_r = [], []
            rad_y, rad_z = sy, sz
            for k in range(n):
                a = 2 * math.pi * k / n
                ring_l.append(w((-sx, math.cos(a) * rad_y, math.sin(a) * rad_z)))
                ring_r.append(w((sx, math.cos(a) * rad_y, math.sin(a) * rad_z)))
            faces.append((ring_l[::-1], mat_apply(r, (-1, 0, 0))))
            faces.append((ring_r, mat_apply(r, (1, 0, 0))))
            for k in range(n):
                k2 = (k + 1) % n
                a = 2 * math.pi * (k + .5) / n
                faces.append(([ring_l[k], ring_l[k2], ring_r[k2], ring_r[k]], mat_apply(r, (0, math.cos(a), math.sin(a)))))
            return faces
        if shape == "Ball":
            # octahedron-ish 3 rings approximation
            n = 8
            pts = []
            for lat in (-0.5, 0.0, 0.5):
                ring = []
                for k in range(n):
                    a = 2 * math.pi * k / n
                    c = math.cos(lat * math.pi / 2)
                    ring.append(w((math.cos(a) * sx * c, math.sin(lat * math.pi / 2) * sy, math.sin(a) * sz * c)))
                pts.append(ring)
            top = w((0, sy, 0)); bot = w((0, -sy, 0))
            for k in range(n):
                k2 = (k + 1) % n
                a = 2 * math.pi * (k + .5) / n
                for li in range(2):
                    lat = (li - 0.5) * 0.5
                    nrm = mat_apply(r, (math.cos(a) * math.cos(lat), math.sin(lat), math.sin(a) * math.cos(lat)))
                    faces.append(([pts[li][k], pts[li][k2], pts[li + 1][k2], pts[li + 1][k]], nrm))
                faces.append(([pts[2][k], pts[2][k2], top], mat_apply(r, (math.cos(a) * .4, .9, math.sin(a) * .4))))
                faces.append(([pts[0][k2], pts[0][k], bot], mat_apply(r, (math.cos(a) * .4, -.9, math.sin(a) * .4))))
            return faces
        c = [w((x, y, z)) for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
        # index: x*4 + y*2 + z  (0 = negative)
        def idx(x, y, z):
            return x * 4 + y * 2 + z
        quads = [
            ([idx(1, 0, 0), idx(1, 1, 0), idx(1, 1, 1), idx(1, 0, 1)], (1, 0, 0)),
            ([idx(0, 0, 1), idx(0, 1, 1), idx(0, 1, 0), idx(0, 0, 0)], (-1, 0, 0)),
            ([idx(0, 1, 0), idx(0, 1, 1), idx(1, 1, 1), idx(1, 1, 0)], (0, 1, 0)),
            ([idx(0, 0, 0), idx(1, 0, 0), idx(1, 0, 1), idx(0, 0, 1)], (0, -1, 0)),
            ([idx(0, 0, 1), idx(1, 0, 1), idx(1, 1, 1), idx(0, 1, 1)], (0, 0, 1)),
            ([idx(0, 0, 0), idx(0, 1, 0), idx(1, 1, 0), idx(1, 0, 0)], (0, 0, -1)),
        ]
        for q, n in quads:
            faces.append(([c[i] for i in q], mat_apply(r, n)))
        return faces
    if shape == "Wedge":
        # Roblox WedgePart: the vertical rectangular face is the BACK (+Z), the slope descends to the front edge
        # (bottom, -Z) and faces front/up (that is how Kit roofs and YardKit.GableTri use it: a wedge in the front half
        # of a gable has its tall side on the ridge at +Z).
        b = [w((x, -sy, z)) for x in (-sx, sx) for z in (-sz, sz)]  # 0:(-,-) 1:(-,+) 2:(+,-) 3:(+,+)
        t0 = w((-sx, sy, sz)); t1 = w((sx, sy, sz))
        nrm = math.sqrt(sz * sz + sy * sy) or 1
        faces.append(([b[0], b[2], b[3], b[1]], mat_apply(r, (0, -1, 0))))
        faces.append(([b[1], b[3], t1, t0], mat_apply(r, (0, 0, 1))))
        faces.append(([b[0], t0, t1, b[2]], mat_apply(r, (0, sz / nrm, -sy / nrm))))
        faces.append(([b[0], b[1], t0], mat_apply(r, (-1, 0, 0))))
        faces.append(([b[2], t1, b[3]], mat_apply(r, (1, 0, 0))))
        return faces
    # Corner wedge: apex above (+x, -z) corner
    b = [w((x, -sy, z)) for x in (-sx, sx) for z in (-sz, sz)]
    apex = w((sx, sy, -sz))
    faces.append(([b[0], b[2], b[3], b[1]], mat_apply(r, (0, -1, 0))))
    faces.append(([b[0], apex, b[2]], mat_apply(r, (0, 0, -1))))
    faces.append(([b[2], apex, b[3]], mat_apply(r, (1, 0, 0))))
    faces.append(([b[3], apex, b[1]], mat_apply(r, (0, .7, .7))))
    faces.append(([b[1], apex, b[0]], mat_apply(r, (-.7, .7, 0))))
    return faces


LIGHT = (0.35, 0.85, -0.4)
LN = math.sqrt(sum(v * v for v in LIGHT))
LIGHT = tuple(v / LN for v in LIGHT)


def shade(color, normal, neon, alpha):
    nl = math.sqrt(sum(v * v for v in normal)) or 1
    d = sum(LIGHT[i] * normal[i] / nl for i in range(3))
    k = 0.45 + 0.55 * max(0.0, d)
    if neon:
        k = 1.25
    col = tuple(max(0, min(255, int(c * k))) for c in color)
    return col + (int(255 * alpha),)


def view_setup(view):
    if view == "top":
        return None
    yaw = {"iso_ne": 45, "iso_nw": 135, "iso_sw": 225, "iso_se": 315, "front": 0, "side": 90}[view]
    pitch = 0 if view in ("front", "side") else 32
    return yaw, pitch


def project(pt, setup):
    if setup is None:
        return (pt[0], pt[2]), pt[1]
    yaw, pitch = setup
    a = math.radians(yaw); b = math.radians(pitch)
    # rotate around Y so the camera looks along -forward
    x = pt[0] * math.cos(a) - pt[2] * math.sin(a)
    z = pt[0] * math.sin(a) + pt[2] * math.cos(a)
    y = pt[1]
    # tilt
    y2 = y * math.cos(b) + z * math.sin(b)
    depth = -y * math.sin(b) + z * math.cos(b)
    return (x, -y2), depth


TILE = 18.0


def tiles(poly):
    """Split a big quad into a grid of smaller quads (painter's sort works per tile)."""
    if len(poly) != 4:
        return [poly]
    a, b, c, d = poly
    def dist(p, q):
        return math.sqrt(sum((p[i] - q[i]) ** 2 for i in range(3)))
    nu = max(1, min(24, int(max(dist(a, b), dist(d, c)) / TILE + .999)))
    nv = max(1, min(24, int(max(dist(a, d), dist(b, c)) / TILE + .999)))
    if nu == 1 and nv == 1:
        return [poly]
    def lerp(p, q, t):
        return tuple(p[i] + (q[i] - p[i]) * t for i in range(3))
    def at(u, v):
        return lerp(lerp(a, b, u), lerp(d, c, u), v)
    out = []
    for i in range(nu):
        for j in range(nv):
            u0, u1, v0, v1 = i / nu, (i + 1) / nu, j / nv, (j + 1) / nv
            out.append([at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)])
    return out


def render(parts, view, size, box, label):
    setup = view_setup(view)
    faces = []
    for part in parts:
        alpha = 1 - part["t"]
        if alpha <= 0.02:
            continue
        neon = part["m"] == "Neon"
        split = []
        for poly, normal in polys_for(part):
            tl = tiles(poly)
            for tile in tl:
                split.append((tile, normal, len(tl) > 1))
        for poly, normal, tiled in split:
            if setup is None and normal[1] <= 0.05:
                continue  # top view: only upward faces
            proj = [project(v, setup) for v in poly]
            pts2 = [q[0] for q in proj]
            if setup is None:
                depth = sum(v[1] for v in poly) / len(poly)
            else:
                depth = -sum(q[1] for q in proj) / len(proj)
            faces.append((depth, pts2, shade(part["c"], normal, neon, alpha), tiled))
    if not faces:
        return None
    xs = [p[0] for f in faces for p in f[1]]
    ys = [p[1] for f in faces for p in f[1]]
    if box and setup is None:
        x0, z0, x1, z1 = box
    else:
        x0, x1, z0, z1 = min(xs), max(xs), min(ys), max(ys)
    w = max(x1 - x0, 1e-3); h = max(z1 - z0, 1e-3)
    scale = (size - 40) / max(w, h)
    W = int(w * scale) + 40; H = int(h * scale) + 40
    img = Image.new("RGBA", (W, H), (22, 20, 30, 255))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer, "RGBA")
    # painter's order: far to near; nearly coplanar faces (a pane on a wall, a dial on a tower) draw the bigger one first
    def area(pts):
        a = 0.0
        for i in range(len(pts)):
            x0, y0 = pts[i]; x1, y1 = pts[(i + 1) % len(pts)]
            a += x0 * y1 - x1 * y0
        return abs(a) / 2
    faces.sort(key=lambda f: (round(f[0] / 0.6), -area(f[1])))
    for _, pts2, col, tiled in faces:
        pts = [((p[0] - x0) * scale + 20, (p[1] - z0) * scale + 20) for p in pts2]
        if len(pts) >= 3:
            draw.polygon(pts, fill=col, outline=col if tiled else (0, 0, 0, min(90, col[3])))
    img = Image.alpha_composite(img, layer)
    d2 = ImageDraw.Draw(img)
    # scale bar + axis note
    bar = 50 * scale
    d2.rectangle([20, H - 14, 20 + bar, H - 10], fill=(255, 255, 255, 255))
    d2.text((24 + bar, H - 20), "50 studs  view=" + view + ("  (x right, z down)" if setup is None else ""), fill=(255, 255, 255, 255))
    if label and setup is None:
        seen = set()
        for part in parts:
            n = part["n"]
            if n in seen or part["t"] > 0.98:
                continue
            seen.add(n)
            x, z = part["p"][0], part["p"][2]
            d2.text(((x - x0) * scale + 20, (z - z0) * scale + 20), n[:14], fill=(255, 255, 160, 255))
    return img


def main():
    pos, opts = parse_args(sys.argv[1:])
    if len(pos) < 2:
        print(__doc__)
        sys.exit(1)
    parts = json.load(open(pos[0]))
    parts = [p for p in parts if p["t"] < opts["hide"]]
    if opts["exclude"] is not None:
        parts = [p for p in parts if not opts["exclude"].search(p["n"])]
    if opts["ymax"] is not None:
        parts = [p for p in parts if p["p"][1] <= opts["ymax"]]
    if opts["ymin"] is not None:
        parts = [p for p in parts if p["p"][1] >= opts["ymin"]]
    if opts["box"]:
        x0, z0, x1, z1 = opts["box"]
        mg = opts["margin"]
        parts = [p for p in parts if x0 - mg <= p["p"][0] <= x1 + mg and z0 - mg <= p["p"][2] <= z1 + mg]
    for view in opts["views"].split(","):
        img = render(parts, view, opts["size"], opts["box"], opts["label"])
        if img is None:
            print("nothing to draw for", view)
            continue
        out = "%s_%s.png" % (pos[1], view)
        img.convert("RGB").save(out)
        print("wrote", out, img.size, len(parts), "parts")


if __name__ == "__main__":
    main()
