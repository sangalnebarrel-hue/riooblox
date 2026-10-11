#!/usr/bin/env python3
"""Run luau-lsp on the scripts that live in src/, for the base place and the built place,
and print only diagnostics that are NEW in the build (line numbers ignored).

usage: analyze_diff.py <luau-lsp> <defs> <base_export_dir> <build_export_dir> <src_dir>
"""
import collections
import os
import re
import subprocess
import sys

lsp, defs, base_dir, build_dir, src_dir = sys.argv[1:6]
NOISE = ("LocalUnused", "ImplicitReturn", "SameLineStatement", "FunctionUnused", "LocalShadow",
         "Cyclic module dependency", "MultiLineStatement", "UnknownGlobal: Unknown global 'shared'")


def mangled_names():
    names = []
    for root, _, files in os.walk(src_dir):
        for f in files:
            if not f.endswith(".luau"):
                continue
            rel = os.path.relpath(os.path.join(root, f), src_dir).replace(os.sep, "/")
            for suf in (".server.luau", ".client.luau", ".luau"):
                if rel.endswith(suf):
                    rel = rel[: -len(suf)]
                    break
            names.append(re.sub(r"[^A-Za-z0-9._-]", "_", rel))
    return names


def files_in(export_dir, names):
    out = {}
    for f in os.listdir(export_dir):
        m = re.match(r"^\d{5}_(.+)\.luau$", f)
        if m and m.group(1) in names:
            out[m.group(1)] = f
    return out


STRICT_KEEP = ("not found in class", "Unknown global", "not found in enum", "is not a valid member", "Unknown require")


def run(export_dir, files, strict=False):
    if not files:
        return collections.Counter(), []
    rc = os.path.join(export_dir, ".luaurc")
    if strict:
        with open(rc, "w") as f:
            f.write('{"languageMode":"strict"}')
    elif os.path.exists(rc):
        os.remove(rc)
    proc = subprocess.run([lsp, "analyze", "--sourcemap=sourcemap.json", "--definitions=" + defs] + sorted(files.values()),
                          cwd=export_dir, capture_output=True, text=True)
    if strict:
        os.remove(rc)
    raw = [l for l in (proc.stdout + proc.stderr).splitlines() if l.strip()]
    if strict:
        raw = [l for l in raw if any(k in l for k in STRICT_KEEP) and "unsupported path" not in l]
    keyed = []
    for line in raw:
        if any(n in line for n in NOISE):
            continue
        m = re.match(r"^(?:\S*/)?\d{5}_(.+?)\.luau(?: \[[^\]]*\])?\((\d+),(\d+)\): (.*)$", line)
        if not m:
            continue
        keyed.append(((m.group(1), m.group(4)), line))
    return collections.Counter(k for k, _ in keyed), keyed


names = set(mangled_names())
shown = 0
for strict in (False, True):
    base_counts, _ = run(base_dir, files_in(base_dir, names), strict)
    build_counts, build_lines = run(build_dir, files_in(build_dir, names), strict)
    new = build_counts - base_counts
    for key, line in build_lines:
        if new[key] > 0:
            new[key] -= 1
            print(("[strict] " if strict else "") + line)
            shown += 1
print("analyze: %d new diagnostic(s) in %d src script(s)" % (shown, len(names)))
