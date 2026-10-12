#!/usr/bin/env python3
"""Active Mining balance simulator.

Reads the mining tables straight from src/ReplicatedStorage/DogEconomy/MiningConfig.luau
(a tiny Luau-table parser, no Roblox needed) and simulates a player mining with every
pickaxe: hit cadence from the client timing loop, perfect/good/miss mix, crits, combo,
ore luck, coin bonus. Prints coins/min, ores/min, hits per ore and pickaxe payback times,
plus strength-training times for the weights.

usage: python3 -I tools/balance_sim.py [--skill 0.6] [--minutes 60]
"""
import argparse
import os
import random
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "src", "ReplicatedStorage", "DogEconomy", "MiningConfig.luau")


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


def load_config():
    with open(CONFIG, encoding="utf-8") as f:
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


def short(n):
    for div, suf in ((1e9, "B"), (1e6, "M"), (1e3, "K")):
        if n >= div:
            return ("%.1f" % (n / div)).rstrip("0").rstrip(".") + suf
    return str(int(n))


def simulate(M, level, strength, skill, minutes, rng, layer=1):
    """Event simulation of the server-issued timing circles.

    Each pickaxe has `Circles` slots. A slot shows one circle that closes over `Window`
    seconds; the player clicks it at fraction f of the window. Perfect band and good band
    come from M.Timing. A missed circle is reported and respawns after RespawnDelay. The
    player cannot click two circles faster than HumanGap seconds.
    skill = probability that a click lands in the perfect band (else good, some misses).
    """
    pick = M["Pickaxes"][level - 1]
    tm = M["Timing"]
    weights = ore_weights(M, pick.get("Luck", 0))
    total_w = sum(weights)
    T = minutes * 60.0
    coins = ores = hits = 0
    combo = 0
    last_hit = -99.0
    w = pick["Window"]
    gap = M["Client"]["RespawnDelay"]
    human_gap = M["Client"]["HumanGap"]
    miss_rate = max(0.03, 0.18 * (1 - skill))

    def roll():
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
            pause_until = click + M["Client"]["BreakPause"]
            slots = [pause_until + j * (w + gap) / pick["Circles"] for j in range(len(slots))]
            oi, hp, maxhp, value, earned = new_ore()
    return coins / minutes, ores / minutes, hits / minutes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skill", type=float, default=0.6, help="share of perfect-capable clicks (0..1)")
    ap.add_argument("--minutes", type=float, default=240)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    M = load_config()
    rng = random.Random(args.seed)
    print("ORES (weight%, HP, value, expected wooden hits)")
    tw = sum(o["Weight"] for o in M["Ores"])
    for o in M["Ores"]:
        print("  %-12s %6.2f%%  HP %4d  value %9s-%-9s" % (o["Id"], 100 * o["Weight"] / tw, o["HP"], f"{int(o['ValueMin']):,}", f"{int(o['ValueMax']):,}"))
    print()
    print("PICKAXES at layer 1 (strength = requirement, and +150 surplus)")
    for i, p in enumerate(M["Pickaxes"], 1):
        # Same seed for both runs so the +150 column shows the Strength effect, not RNG noise.
        cpm, opm, hpm = simulate(M, i, p["Strength"], args.skill, args.minutes, random.Random(args.seed * 1000 + i))
        cpm2, _, _ = simulate(M, i, p["Strength"] + 150, args.skill, args.minutes, random.Random(args.seed * 1000 + i))
        print("  %d %-12s price %12s  str %4d | %9s coins/min (%9s +150str)  %5.1f ores/min  %5.1f hits/ore  %5.1f hits/s" % (
            i, p["Id"], f"{int(p['Price']):,}", p["Strength"], f"{int(cpm):,}", f"{int(cpm2):,}", opm, hpm / max(opm, 1e-9), hpm / 60))
    print()
    # Dog income per minute by stage (Rules.IncomeModel, docs/ECONOMY.md and OVERHAUL_AUDIT economy section):
    # old-style upgrades / full upgrade tree. Mining should stay ~0.5-1x of the first column.
    dog_refs = {1: (6600, 178000), 2: (37300, 773000), 3: (122000, 1840000), 4: (1160000, 13600000), 5: (4520000, 45400000)}
    print("COINS/MIN by pickaxe x deepest layer (dog team refs, old upgrades | full tree: " + " | ".join(
        "L%d %s/%s" % (L, short(a), short(b)) for L, (a, b) in dog_refs.items()) + ")")
    print("  %-12s" % "" + "".join("%12s" % ("L%d" % L) for L in range(1, 6)))
    table = {}
    for i, p in enumerate(M["Pickaxes"], 1):
        row = []
        for L in range(1, 6):
            cpm, _, _ = simulate(M, i, p["Strength"] + 50, args.skill, args.minutes / 4, rng, L)
            row.append(cpm)
        table[i] = row
        print("  %-12s" % p["Id"] + "".join("%12s" % f"{int(c):,}" for c in row))
    print()
    # Payback: minutes to earn a pickaxe's price at the layer where players usually buy it,
    # by mining with the previous pickaxe alone and with mining + the dog team (old upgrades / full tree).
    stage = {1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 4, 7: 5}
    print("PICKAXE PAYBACK (minutes) at the usual buying layer: mining only (previous pickaxe) | + dogs old upgrades | + dogs full tree")
    for i, p in enumerate(M["Pickaxes"], 1):
        L = stage.get(i, 5)
        prev = table[max(1, i - 1)][L - 1]
        a, b = dog_refs[L]
        price = p["Price"]
        print("  %-12s L%d price %12s  %9.1f | %9.1f | %9.1f" % (
            p["Id"], L, f"{int(price):,}", price / max(prev, 1), price / max(prev + a, 1), price / max(prev + b, 1)))
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


if __name__ == "__main__":
    main()
