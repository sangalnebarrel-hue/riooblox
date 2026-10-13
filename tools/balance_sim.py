#!/usr/bin/env python3
"""Active Mining balance simulator.

Reads the mining tables straight from src/ReplicatedStorage/DogEconomy/MiningConfig.luau
(a tiny Luau-table parser, no Roblox needed) and simulates a player mining with every
pickaxe: hit cadence from the client timing loop, perfect/good/miss mix, crits, combo,
ore luck, coin bonus.

Rare ores make a single random session very noisy (one Void Crystal is worth ~100 Limestones),
so the tables use EXPECTED values: every ore is mined on its own with every pickaxe (mean time
and hits per break), then combined with the luck-shifted ore chances. Prints coins/min,
ores/min, hits per ore, Stone/min, pickaxe payback minutes, strength-training times, and with
--compare the ratios against another config (e.g. the version before a balance change):

  git show HEAD~1:src/ReplicatedStorage/DogEconomy/MiningConfig.luau > /tmp/old.luau
  python3 -I tools/balance_sim.py --compare /tmp/old.luau

usage: python3 -I tools/balance_sim.py [--skill 0.6] [--minutes 240] [--config X] [--compare OLD]
"""
import argparse
import os
import random
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "src", "ReplicatedStorage", "DogEconomy", "MiningConfig.luau")

# Dog income per minute at each stage (docs/ECONOMY.md section 5: real 2-hour simulation, base
# upgrades; the full upgrade tree of section 12 multiplies these by 10-30).
DOG_INCOME = {
    1: (1164, 6699, "1-5 Common, Backyard"),
    2: (31501, 31501, "5 Rare, Caverns"),
    3: (109300, 109300, "5 Epic, Ruins"),
    4: (1121477, 1121477, "5 Legendary, Cursed"),
    5: (4398703, 7865744, "5 Mythic-Secret, VOID"),
}
# Where a pickaxe is typically used: deepest dig layer and the dog team at that point
# (layer unlocks cost 16K / 120K / 900K / 8M, the pickaxes 0.6K ... 600M; see docs/BALANCE.md).
# (layer, dog income low, high, team)
TYPICAL = {
    "Wooden": [(1, 1164, 2400, "1-2 Common")],
    "Stone": [(1, 2400, 6699, "2-5 Common"), (2, 31501, 31501, "5 Rare")],
    "Iron": [(1, 6699, 6699, "5 Common"), (2, 31501, 31501, "5 Rare")],
    "Steel": [(2, 31501, 31501, "5 Rare"), (3, 109300, 109300, "5 Epic")],
    "Crystal": [(3, 109300, 109300, "5 Epic"), (4, 1121477, 1121477, "5 Legendary")],
    "Inferno": [(4, 1121477, 1121477, "5 Legendary"), (5, 4398703, 7865744, "5 Mythic-Secret")],
    "Voidbreaker": [(5, 4398703, 7865744, "5 Mythic-Secret")],
}
TYPICAL_LAYERS = {k: tuple(row[0] for row in v) for k, v in TYPICAL.items()}


# ---------------------------------------------------------------- tiny Luau table reader
def parse_luau_table(src):
    src = re.sub(r"--\[\[.*?\]\]", "", src, flags=re.S)
    src = re.sub(r"--[^\n]*", "", src)
    start = src.index("return")
    tokens = re.findall(r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'|[A-Za-z_][A-Za-z0-9_]*|-?\d+(?:\.\d+)?(?:e[+-]?\d+)?|-?\.\d+|[{}=,;\[\]\*/+-]", src[start + 6:])
    pos = [0]

    def peek():
        return tokens[pos[0]] if pos[0] < len(tokens) else None

    def take():
        t = tokens[pos[0]]
        pos[0] += 1
        return t

    def value():
        t = take()
        if t == "{":
            return table()
        if t in ("true", "false"):
            return t == "true"
        if t == "nil":
            return None
        if t[0] in "\"'":
            return t[1:-1]
        num = float(t)
        # simple arithmetic like 90*1e6 or 5*60
        while peek() in ("*", "/"):
            op = take()
            rhs = float(take())
            num = num * rhs if op == "*" else num / rhs
        return num

    def table():
        arr, obj = [], {}
        while peek() != "}":
            t = peek()
            if t == "[":
                take()
                key = value()
                assert take() == "]"
                assert take() == "="
                obj[key] = value()
            elif re.match(r"[A-Za-z_]", t) and tokens[pos[0] + 1] == "=":
                key = take()
                take()
                obj[key] = value()
            else:
                arr.append(value())
            if peek() in (",", ";"):
                take()
        take()
        if obj and arr:
            obj["__array"] = arr
            return obj
        return arr if arr else obj

    assert take() == "{"
    return table()


def load_config(path=CONFIG):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    m = re.search(r"local M=(\{.*?\n\})\n", src, re.S)
    return parse_luau_table("return " + m.group(1))


# ------------------------------------------------------------------------- simulation
def ore_weights(M, luck):
    n = len(M["Ores"])
    return [o["Weight"] * (1 + luck * M["LuckSpread"] * i / max(1, n - 1)) for i, o in enumerate(M["Ores"])]


def strength_bonus(M, strength, pick):
    surplus = max(0, strength - pick["Strength"])
    return 1 + min(M["StrengthBonusMax"], surplus * M["StrengthBonusPerPoint"])


def hit_damage(M, pick, strength, quality, combo, crit):
    mult = strength_bonus(M, strength, pick)
    if quality == 2:
        mult *= pick.get("PerfectMult", M["PerfectMult"])
    mult *= 1 + min(pick.get("ComboMax", 0), combo * pick.get("ComboStep", 0))
    if crit:
        mult *= pick.get("CritMult", 2)
    return max(1, int(pick["Damage"] * mult + 0.5))


def stone_for_break(M, ore, layer):
    """Same formula as MiningRules.StoneForBreak."""
    base = ore.get("Stone", 0) or 0
    if base <= 0:
        return 0
    deep = max(1, min(int(layer), len(M["LayerValue"]))) - 1
    return max(0, int(base * (1 + M.get("StoneLayerBonus", 0) * deep) + 0.5))


def simulate(M, level, strength, skill, minutes, rng, layer=1, only=None):
    """Event simulation of the server-issued timing circles.

    Each pickaxe has `Circles` slots. A slot shows one circle that closes over `Window`
    seconds; the player clicks it at fraction f of the window. Perfect band and good band
    come from M.Timing. A missed circle is reported and respawns after RespawnDelay. The
    player cannot click two circles faster than HumanGap seconds.
    skill = probability that a click lands in the perfect band (else good, some misses).
    only = ore index to mine every time (per-ore statistics) instead of rolling.
    Returns coins/min, ores/min, hits/min, stone/min.
    """
    pick = M["Pickaxes"][level - 1]
    tm = M["Timing"]
    weights = ore_weights(M, pick.get("Luck", 0))
    total_w = sum(weights)
    T = minutes * 60.0
    coins = ores = hits = stone = 0
    combo = 0
    last_hit = -99.0
    w = pick["Window"]
    gap = M["Client"]["RespawnDelay"]
    human_gap = M["Client"]["HumanGap"]
    miss_rate = max(0.03, 0.18 * (1 - skill))

    def roll():
        if only is not None:
            return only
        r = rng.random() * total_w
        for i, wt in enumerate(weights):
            r -= wt
            if r <= 0:
                return i
        return len(weights) - 1

    def new_ore():
        i = roll()
        o = M["Ores"][i]
        val = int((o["ValueMin"] + (o["ValueMax"] - o["ValueMin"]) * rng.random()) * M["LayerValue"][layer - 1] + 0.5)
        return i, o["HP"], o["HP"], val, 0

    oi, hp, maxhp, value, earned = new_ore()
    slots = [k * (w + gap) / pick["Circles"] for k in range(int(pick["Circles"]))]  # spawn times
    pause_until = 0.0
    last_click = -99.0
    while True:
        k = min(range(len(slots)), key=lambda j: slots[j])
        spawn = max(slots[k], pause_until)
        if spawn > T:
            break
        r = rng.random()
        if r < miss_rate:
            slots[k] = spawn + w + gap + 0.12  # expired + miss report round trip
            combo = 0
            continue
        perfect = rng.random() < skill
        lo, hi = (tm["PerfectFrom"], tm["PerfectTo"]) if perfect else (tm["GoodFrom"], tm["PerfectFrom"])
        click = spawn + w * rng.uniform(lo, hi)
        click = max(click, last_click + human_gap)
        if click > spawn + w:  # too slow because busy with another circle
            slots[k] = spawn + w + gap + 0.12
            continue
        quality = 2 if (click - spawn) / w >= tm["PerfectFrom"] and (click - spawn) / w <= tm["PerfectTo"] else 1
        last_click = click
        if click - last_hit > M["ComboTimeout"]:
            combo = 0
        last_hit = click
        crit = rng.random() < pick.get("CritChance", 0)
        dmg = hit_damage(M, pick, strength, quality, combo, crit)
        combo = min(M["ComboCap"], combo + 1) if quality == 2 else 0
        applied = min(hp, dmg)
        hp -= applied
        hits += 1
        total = int(value * (1 + pick.get("CoinBonus", 0)) + 0.5)
        remaining = max(0, total - earned)
        pay = min(remaining, max(1, int(total * M["HitShare"] * applied / maxhp)))
        if hp <= 0:
            pay = remaining
        coins += pay
        earned += pay
        slots[k] = click + gap
        if hp <= 0:
            ores += 1
            stone += stone_for_break(M, M["Ores"][oi], layer)
            pause_until = click + M["Client"]["BreakPause"]
            slots = [pause_until + j * (w + gap) / pick["Circles"] for j in range(len(slots))]
            oi, hp, maxhp, value, earned = new_ore()
    return coins / minutes, ores / minutes, hits / minutes, stone / minutes


# --------------------------------------------------------------------- expected values
def per_ore_stats(M, skill, minutes, seed, surplus=50):
    """{pickaxe id: [(seconds per break, hits per break) for each ore]} at strength = requirement + surplus."""
    out = {}
    for level, p in enumerate(M["Pickaxes"], 1):
        row = []
        for i in range(len(M["Ores"])):
            _, opm, hpm, _ = simulate(M, level, p["Strength"] + surplus, skill, minutes, random.Random(seed * 7919 + level * 131 + i), 1, i)
            row.append((60.0 / opm, hpm / opm))
        out[p["Id"]] = row
    return out


def expected(M, stats, level, layer):
    """Expected coins/min, ores/min, hits per ore, hits/s and stone/min of one pickaxe at one layer."""
    p = M["Pickaxes"][level - 1]
    ws = ore_weights(M, p.get("Luck", 0))
    T = sum(ws)
    probs = [x / T for x in ws]
    rows = stats[p["Id"]]
    secs = sum(q * rows[i][0] for i, q in enumerate(probs))
    hits = sum(q * rows[i][1] for i, q in enumerate(probs))
    coins = sum(q * (o["ValueMin"] + o["ValueMax"]) / 2 for q, o in zip(probs, M["Ores"]))
    coins *= M["LayerValue"][layer - 1] * (1 + p.get("CoinBonus", 0))
    stone = sum(q * stone_for_break(M, o, layer) for q, o in zip(probs, M["Ores"]))
    return {"coins": coins / secs * 60, "ores": 60 / secs, "hits": hits, "hps": hits / secs, "stone": stone / secs * 60}


def fmt_k(n):
    if n >= 1e6:
        return "%.2fM" % (n / 1e6)
    if n >= 1e4:
        return "%.1fK" % (n / 1e3)
    return "%d" % round(n)


def report(M, stats, args):
    layers = range(1, len(M["LayerValue"]) + 1)
    tw = sum(o["Weight"] for o in M["Ores"])
    print("ORES (chance, HP, value at layer 1, Stone per break on layers 1-5)")
    for o in M["Ores"]:
        stones = "/".join(str(stone_for_break(M, o, L)) for L in layers)
        print("  %-12s %6.2f%%  HP %4d  value %9s-%-9s  stone %s" % (o["Id"], 100 * o["Weight"] / tw, o["HP"], f"{int(o['ValueMin']):,}", f"{int(o['ValueMax']):,}", stones))
    print()
    print("PICKAXES at layer 1 (expected values, strength = requirement + 50, skill %.2f)" % args.skill)
    for i, p in enumerate(M["Pickaxes"], 1):
        e = expected(M, stats, i, 1)
        mc = simulate(M, i, p["Strength"] + 50, args.skill, args.minutes, random.Random(args.seed * 1000 + i))[0]
        print("  %d %-12s price %12s  str %4d | %8s coins/min (one random %d-min run: %8s)  %5.1f ores/min  %5.1f hits/ore  %4.2f hits/s  %5.1f stone/min" % (
            i, p["Id"], f"{int(p['Price']):,}", p["Strength"], fmt_k(e["coins"]), args.minutes, fmt_k(mc), e["ores"], e["hits"], e["hps"], e["stone"]))
    print()
    print("COINS/MIN by pickaxe x deepest layer (expected); * = layers where the pickaxe is typical")
    print("  %-12s" % "" + "".join("%12s" % ("L%d" % L) for L in layers))
    for i, p in enumerate(M["Pickaxes"], 1):
        cells = []
        for L in layers:
            mark = "*" if L in TYPICAL_LAYERS.get(p["Id"], ()) else " "
            cells.append("%11s%s" % (fmt_k(expected(M, stats, i, L)["coins"]), mark))
        print("  %-12s" % p["Id"] + "".join(cells))
    print("  %-12s" % "dogs" + "".join("%12s" % (fmt_k(DOG_INCOME[L][0]) + ("-" + fmt_k(DOG_INCOME[L][1]) if DOG_INCOME[L][1] != DOG_INCOME[L][0] else "")) for L in layers))
    print("  (dogs: %s)" % " | ".join("L%d %s" % (L, DOG_INCOME[L][2]) for L in layers))
    print()
    print("MINING / DOG INCOME where the pickaxe is typical (principle: active mining <= ~1-1.5x dogs)")
    for i, p in enumerate(M["Pickaxes"], 1):
        parts = []
        for L, lo, hi, team in TYPICAL.get(p["Id"], ()):
            c = expected(M, stats, i, L)["coins"]
            ratio = "%.2f-%.2fx" % (c / hi, c / lo) if hi != lo else "%.2fx" % (c / lo)
            parts.append("L%d %s vs %s %s" % (L, fmt_k(c), team, ratio))
        print("  %-12s %s" % (p["Id"], "   ".join(parts)))
    print()
    print("STONE/MIN by pickaxe x deepest layer (expected)")
    print("  %-12s" % "" + "".join("%9s" % ("L%d" % L) for L in layers))
    for i, p in enumerate(M["Pickaxes"], 1):
        print("  %-12s" % p["Id"] + "".join("%9.1f" % expected(M, stats, i, L)["stone"] for L in layers))
    print()
    print("PAYBACK: minutes of active mining with the pickaxe itself to earn its price; * = typical layer")
    print("  %-12s %12s" % ("", "price") + "".join("%9s" % ("L%d" % L) for L in layers))
    for i, p in enumerate(M["Pickaxes"], 1):
        cells = []
        for L in layers:
            mins = p["Price"] / expected(M, stats, i, L)["coins"]
            mark = "*" if L in TYPICAL_LAYERS.get(p["Id"], ()) else " "
            cells.append("%8.1f%s" % (mins, mark))
        print("  %-12s %12s" % (p["Id"], f"{int(p['Price']):,}") + "".join(cells))
    print("  the same price in minutes of dog income + this mining, where the pickaxe is typical:")
    for i, p in enumerate(M["Pickaxes"], 1):
        parts = []
        for L, lo, hi, team in TYPICAL.get(p["Id"], ()):
            c = expected(M, stats, i, L)["coins"]
            a, b = "%.1f" % (p["Price"] / (hi + c)), "%.1f" % (p["Price"] / (lo + c))
            parts.append("L%d (%s) %s min" % (L, team, a if a == b else a + "-" + b))
        print("    %-12s %s" % (p["Id"], "   ".join(parts)))
    print()
    print("WEIGHTS (time to fill cap from previous requirement, continuous reps)")
    for i, w in enumerate(M["Weights"], 1):
        reps = max(0, (w["Cap"] - w["Strength"])) / w["Gain"]
        secs = reps * (w["Cooldown"] + M["Client"]["RepOverhead"])
        print("  %d %-16s price %12s  needs %4d str  +%-3d/rep  cap %4d  -> %5.1f min to cap" % (
            i, w["Id"], f"{int(w['Price']):,}", w["Strength"], w["Gain"], w["Cap"], secs / 60))
    print()
    print("Pickaxe strength gates: the first weight whose cap reaches the requirement")
    for i, p in enumerate(M["Pickaxes"], 1):
        need = p["Strength"]
        first = next((w for w in M["Weights"] if w["Cap"] >= need), None)
        print("  %-12s needs %4d  -> train with %s (cap %s)" % (p["Id"], need, first and first["Id"], first and int(first["Cap"])))


def compare(M, stats, old, old_stats):
    layers = range(1, len(M["LayerValue"]) + 1)
    print()
    print("COMPARED WITH THE OLD CONFIG (expected values)")
    print("  coins/min at layer 1 old -> new, and new/old on every layer:")
    print("  %-12s %21s" % ("", "L1 old -> new") + "".join("%8s" % ("L%d" % L) for L in layers))
    for i, p in enumerate(M["Pickaxes"], 1):
        a1 = expected(old, old_stats, i, 1)["coins"]
        b1 = expected(M, stats, i, 1)["coins"]
        ratios = "".join("%8s" % ("x%.2f" % (expected(M, stats, i, L)["coins"] / expected(old, old_stats, i, L)["coins"])) for L in layers)
        print("  %-12s %21s" % (p["Id"], "%s -> %s" % (fmt_k(a1), fmt_k(b1))) + ratios)
    print("  ores/min and hits/ore at layer 1 old -> new:")
    for i, p in enumerate(M["Pickaxes"], 1):
        a, b = expected(old, old_stats, i, 1), expected(M, stats, i, 1)
        print("    %-12s %5.1f -> %5.1f ores/min   %5.1f -> %5.1f hits/ore" % (p["Id"], a["ores"], b["ores"], a["hits"], b["hits"]))
    print("  pickaxe prices:")
    for p, q in zip(M["Pickaxes"], old["Pickaxes"]):
        print("    %-12s %14s -> %14s  x%.2f" % (p["Id"], f"{int(q['Price']):,}", f"{int(p['Price']):,}", p["Price"] / q["Price"]))
    print("  ores (HP, value at layer 1):")
    for o, q in zip(M["Ores"], old["Ores"]):
        print("    %-12s HP %4d -> %4d   value %6s-%-6s -> %6s-%-6s" % (o["Id"], q["HP"], o["HP"], int(q["ValueMin"]), int(q["ValueMax"]), int(o["ValueMin"]), int(o["ValueMax"])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skill", type=float, default=0.6, help="share of perfect-capable clicks (0..1)")
    ap.add_argument("--minutes", type=float, default=240, help="simulated minutes per ore and pickaxe")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--config", default=CONFIG, help="MiningConfig.luau to read")
    ap.add_argument("--compare", default=None, help="another MiningConfig.luau (e.g. before a change)")
    args = ap.parse_args()
    M = load_config(args.config)
    stats = per_ore_stats(M, args.skill, args.minutes, args.seed)
    report(M, stats, args)
    if args.compare:
        old = load_config(args.compare)
        compare(M, stats, old, per_ore_stats(old, args.skill, args.minutes, args.seed))


if __name__ == "__main__":
    main()
