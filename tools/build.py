#!/usr/bin/env python3
"""Build the DOGROTS place: apply every Luau file under src/ onto the base place.

File naming (Rojo-style, mirrors the Roblox hierarchy):
  src/<Service>/<...>/<Name>.server.luau  -> Script
  src/<Service>/<...>/<Name>.client.luau  -> LocalScript
  src/<Service>/<...>/<Name>.luau         -> ModuleScript
Directories that do not exist in the place are created as Folders.

Existing instances keep every property except Source; new instances are cloned from a
template instance of the same class. Untouched chunks of the place are written back
byte-for-byte (see rbxl.py).

usage: python3 -I tools/build.py [base.rbxl] [out.rbxl]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import rbxl  # noqa: E402

TEMPLATES = {
    "ModuleScript": "ReplicatedStorage/MapRouting",
    "LocalScript": "StarterPlayer/StarterPlayerScripts/WorldSignController",
    "Script": "ServerScriptService/LightingController",
    "Folder": "ReplicatedStorage/DogEconomy",
}
CLEAR = {"AttributesSerialize": b"", "LinkedSource": b"", "SerializedOverrides": b""}


def classify(filename):
    for suffix, cls in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if filename.endswith(suffix):
            return filename[: -len(suffix)], cls
    return None, None


def collect(src_root):
    items = []
    for dirpath, _, files in os.walk(src_root):
        for fn in sorted(files):
            name, cls = classify(fn)
            if not cls:
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), src_root).replace(os.sep, "/")
            with open(os.path.join(dirpath, fn), "rb") as f:
                items.append((rel, cls, f.read()))
    # Parents before children (a module may parent another module).
    items.sort(key=lambda x: (x[0].count("/"), x[0]))
    return items


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "place", "DOGROTS_base.rbxl")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "build", "DOGROTS_MINING.rbxl")
    place = rbxl.Place(base)
    templates = {}
    for cls, path in TEMPLATES.items():
        refs = place.find_by_path(path)
        assert len(refs) == 1 and place.class_of(refs[0]) == cls, ("bad template", cls, path)
        templates[cls] = refs[0]

    report = {"modified": [], "created": []}
    for rel, cls, source in collect(os.path.join(ROOT, "src")):
        parts = rel.split("/")
        found = place.find_by_path(rel)
        if found:
            assert len(found) == 1, ("ambiguous path in place", rel)
            ref = found[0]
            assert place.class_of(ref) == cls, ("class mismatch", rel, place.class_of(ref), cls)
            if place.get_string_prop(ref, "Source").encode("utf-8") != source:
                place.set_string_prop(ref, "Source", source)
                report["modified"].append(rel)
            continue
        # Ensure the parent chain exists (missing directories become Folders).
        parent_refs = place.find_by_path(parts[0])
        assert len(parent_refs) == 1, ("missing service", parts[0])
        parent = parent_refs[0]
        for i in range(1, len(parts) - 1):
            sub = place.find_by_path("/".join(parts[: i + 1]))
            if sub:
                assert len(sub) == 1, ("ambiguous", parts[: i + 1])
                parent = sub[0]
            else:
                overrides = dict(CLEAR)
                overrides["Name"] = parts[i].encode("utf-8")
                parent = place.clone_instance(templates["Folder"], parent, overrides)
                report["created"].append("/".join(parts[: i + 1]) + " (Folder)")
        overrides = dict(CLEAR)
        overrides["Name"] = parts[-1].encode("utf-8")
        overrides["Source"] = source
        place.clone_instance(templates[cls], parent, overrides)
        report["created"].append(rel + " (" + cls + ")")

    os.makedirs(os.path.dirname(out), exist_ok=True)
    place.save(out)
    with open(os.path.join(os.path.dirname(out), "build_report.json"), "w") as f:
        json.dump(report, f, indent=1, ensure_ascii=False)
    print("modified:", len(report["modified"]))
    for r in report["modified"]:
        print("  ~", r)
    print("created:", len(report["created"]))
    for r in report["created"]:
        print("  +", r)
    print("wrote", out, os.path.getsize(out), "bytes")


if __name__ == "__main__":
    main()
