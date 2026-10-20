#!/usr/bin/env python3
"""CHAPTER I (THE DEAD YARD) rebalance model — docs/halloween2/CHAPTER1_BALANCE.md.

Reads the NEW numbers straight from src/ReplicatedStorage/Halloween/Config.luau (a tiny Luau table reader, no Roblox
needed), keeps the OLD (pre-rebalance) Chapter I numbers below as a frozen baseline (audited from the shipped place,
scratchpad audit A01 §5 / A02 §6 / A03 §4), applies the rare prize philosophy exactly like
ReplicatedStorage.Halloween.DropRates.Rescale, and prints (markdown):
  * the old -> new Pumpkin / Cursed Pumpkin tables with every probability and the expected opens per prize,
  * the boss drop chances, the TRICK price ladder, the brew catch-up,
  * expected candy / hour and Pumpkin blocks / hour before and after for an active player (assumptions in ASSUME),
  * expected opens and hours of play for each chase item.

usage: python3 -I tools/chapter1_balance.py [--hours 2] [--players 6] [--json out.json]
"""
import argparse
import json
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "src", "ReplicatedStorage", "Halloween", "Config.luau")
SCALE = 1_000_000


# ---------------------------------------------------------------- tiny Luau reader (the C.X = {...} statements)
TOKEN = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|--[^\n]*|[A-Za-z_][A-Za-z0-9_]*|\d+\.\d*(?:e[+-]?\d+)?|\.\d+|\d+(?:e[+-]?\d+)?|[{}=,;\[\]\*/+\-().:]')


def tokens(src):
    return [t for t in TOKEN.findall(src) if not t.startswith("--")]


class Reader:
    def __init__(self, toks):
        self.t, self.i = toks, 0

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else None

    def take(self, want=None):
        tok = self.t[self.i]
        if want is not None and tok != want:
            raise ValueError("expected %s got %s" % (want, tok))
        self.i += 1
        return tok

    def atom(self):
        tok = self.take()
        if tok == "{":
            return self.table()
        if tok == "(":
            v = self.expr()
            self.take(")")
            return v
        if tok == "-":
            return -self.atom()
        if tok[0] in "\"'":
            return tok[1:-1]
        if tok == "true":
            return True
        if tok == "false":
            return False
        if tok == "nil":
            return None
        if re.match(r"^[\d.]", tok):
            return float(tok) if re.search(r"[.e]", tok) else int(tok)
        # a reference (C.X, math.huge ...): keep the name; the model never needs its value
        while self.peek() in (".", ":"):
            self.take()
            tok += "." + self.take()
        return tok

    def term(self):
        v = self.atom()
        while self.peek() in ("*", "/"):
            op = self.take()
            w = self.atom()
            v = v * w if op == "*" else v / w
        return v

    def expr(self):
        v = self.term()
        while self.peek() in ("+", "-") and isinstance(v, (int, float)):
            op = self.take()
            w = self.term()
            v = v + w if op == "+" else v - w
        return v

    def table(self):
        out, n = {}, 0
        while self.peek() != "}":
            if self.peek() == "[":
                self.take("[")
                key = self.expr()
                self.take("]")
                self.take("=")
                out[key] = self.expr()
            elif re.match(r"^[A-Za-z_]", self.peek() or "") and self.peek(1) == "=":
                key = self.take()
                self.take("=")
                out[key] = self.expr()
            else:
                n += 1
                out[n] = self.expr()
            if self.peek() in (",", ";"):
                self.take()
        self.take("}")
        if out and all(isinstance(k, int) for k in out) and sorted(out) == list(range(1, len(out) + 1)):
            return [out[k] for k in range(1, len(out) + 1)]
        return out


def read_config(path=CONFIG):
    src = open(path, encoding="utf-8").read()
    toks = tokens(src)
    cfg = {}
    for i in range(len(toks) - 3):
        if toks[i] == "C" and toks[i + 1] == "." and toks[i + 3] == "=" and (i == 0 or toks[i - 1] not in (".", "=")):
            name = toks[i + 2]
            r = Reader(toks)
            r.i = i + 4
            try:
                cfg[name] = r.expr()
            except (ValueError, IndexError, TypeError):
                pass
    return cfg


# ---------------------------------------------------------------- the pre-rebalance Chapter I (frozen baseline)
OLD = {
    "TrickCost": 80, "TrickLadder": None, "CursedChance": .06,
    "PerfectHitCap": 40, "MinuteCap": 220, "CapBeforeMult": False,
    "OreCandy": (1, 3), "RareFind": (3, 8), "OreRare": .06,
    "Spots": {"CursedSoil": (30, 2, 4, .22), "GhostSoil": (26, 2, 4, .10), "PumpkinPatch": (24, 6, 10, .06),
              "BoneGrave": (17, 1, 3, .08), "CursedTreasure": (3, 14, 24, 1.0)},
    "Treat": (6, 14), "Trick": (2, 5), "TreatChance": .62, "MiniBoss": (6, 12), "MiniBossShare": 12 / 100,
    "BloodMoonBonus": .5,
    "Quests": {"DigSpots": 45, "Perfect": 30, "EarnCandy": 25, "BloodMoon": 40, "BossDamage": 50, "OpenPumpkin": 35,
               "FindMutation": 50, "MineOre": 30, "Knock": 25},
    "AllBonusCandy": 30,
    "Boss": [(20, 35, .02, 0, 0), (30, 50, .04, 0, 0), (45, 70, .07, 0, 0), (60, 85, .12, .35, 0), (80, 100, .2, 1.0, .03)],
    "BossDogWeights": (3, 1),
    "YardChance": {"HAUNTED": .004, "PUMPKINIZED": .0015, "BLOOD MOON": .0012}, "PassiveScale": 1.0,
    "ExorcismBlockToAll": True, "BrewDeadline": None,
}

# ---------------------------------------------------------------- model assumptions (one active player)
ASSUME = {
    "perfect_per_min": 45,       # Perfect hits an engaged player lands per minute on ore / spots (any mid pickaxe)
    "ore_breaks_per_min": 6,     # ore nodes broken per minute between Blood Moons (A01 §5: ~6/min)
    "spots_per_min": 3,          # haunted dig spots dug per minute while a Blood Moon is ACTIVE
    "moon_share": 150 / 915,     # Blood Moon ACTIVE 150 s of every 915 s world-event cycle
    "rush_seconds": 600,         # personal Candy Rush x2: 10 minutes of active play per UTC day
    "curse_mult": 1.0,           # an active player keeps the curse below 60%
    "boss_kills_per_day": 1,     # one solo Gravekeeper II kill (full reward, perf 1) per day
    "boss_difficulty": 2,
    "yard_players": 6,           # players active in the Dead Yard on the server (exorcism souls)
    "boss_fight_minutes": 5,     # exorcism cycle pause: the summoned Gravekeeper fight
    "souls_per_ore": 3, "souls_per_spot": 6, "souls_per_quest": 20,
}


def mean(lo, hi):
    return (lo + hi) / 2


def classify(row):
    if row.get("Kind") in ("Cash", "Coins", "Bones", "Candy", "Dust", "Shards", "Stone"):
        return "Resource"
    rar = row.get("Rarity")
    if rar in ("Common", "Rare", "Epic", "Legendary", "Mythic", "Secret"):
        return rar
    return ["Common", "Rare", "Epic", "Legendary", "Mythic", "Secret"][max(1, min(6, int(row.get("Rank", 1)))) - 1]


def rescale(rows, factors, filler):
    """DropRates.Rescale: integer weights on a 1e6 scale; chance = old x factor; the rest to the filler."""
    total = sum(r["Weight"] for r in rows)
    out, used = [], 0
    for r in rows:
        f = factors[classify(r)]
        exact = r["Weight"] / total * f * SCALE
        w = int(math.floor(exact + .5))
        if w < 1 and exact > 0:
            w = 1
        used += w
        out.append(dict(r, Weight=w, WeightWas=r["Weight"], ChanceWas=r["Weight"] / total, Factor=f, Class=classify(r)))
    out.append(dict(filler, Weight=SCALE - used, WeightWas=0, ChanceWas=0.0, Factor=1, Class="Filler"))
    for r in out:
        r["Chance"] = r["Weight"] / SCALE
    return out


def odds(rows):
    total = sum(r["Weight"] for r in rows)
    return [dict(r, Chance=r["Weight"] / total) for r in rows]


def epic_plus(rows):
    """The exorcism RARE pumpkin (Core ctx.Block MinRank 3): only rows of Rank >= 3, renormalised."""
    kept = [r for r in rows if int(r.get("Rank", 1)) >= 3]
    return odds(kept)


def trick_price(n, base, esc):
    if not esc:
        return base
    raw = base * (1 + esc["Step"]) ** n if esc.get("Compound", True) else base * (1 + esc["Step"] * n)
    rnd = esc.get("Round", 1)
    return max(1, int(min(math.floor(raw / rnd + .5) * rnd, esc.get("Max", math.inf))))


def per_minute(state, p):
    """Base candy of one minute of play and its multiplier. state: 'ore' | 'moon'."""
    a = ASSUME
    perfect = min(p["PerfectHitCap"], a["perfect_per_min"])
    if state == "ore":
        loot = a["ore_breaks_per_min"] * (mean(*p["OreCandy"]) + p["OreRare"] * mean(*p["RareFind"]))
    else:
        w = sum(s[0] for s in p["Spots"].values())
        spot = sum(s[0] / w * (mean(s[1], s[2]) + s[3] * mean(*p["RareFind"])) for s in p["Spots"].values())
        loot = a["spots_per_min"] * spot
    return perfect + loot


def candy_minute(base, mult, p):
    cap = p["MinuteCap"]
    if p["CapBeforeMult"]:
        return min(base, cap) * mult
    return min(base * mult, cap)


def daily_fixed(p):
    q = p["Quests"]
    always = q["Perfect"] + q["EarnCandy"]
    others = [v for k, v in q.items() if k not in ("Perfect", "EarnCandy")]
    quests = always + 3 * sum(others) / len(others) + p["AllBonusCandy"]
    knock = p["TreatChance"] * mean(*p["Treat"]) + (1 - p["TreatChance"]) * (mean(*p["Trick"]) + p["MiniBossShare"] * mean(*p["MiniBoss"]))
    doors = 7 * knock
    b = p["Boss"][ASSUME["boss_difficulty"] - 1]
    boss = ASSUME["boss_kills_per_day"] * b[1]
    return {"quests": quests, "doors": doors, "boss": boss}


def candy_per_hour(p, hours):
    a = ASSUME
    rush_share = min(1.0, a["rush_seconds"] / (hours * 3600))
    total = 0.0
    for state, share in (("ore", 1 - a["moon_share"]), ("moon", a["moon_share"])):
        base = per_minute(state, p)
        moon = 1 + p["BloodMoonBonus"] if state == "moon" else 1
        for rush, rshare in ((2, rush_share), (1, 1 - rush_share)):
            total += share * rshare * candy_minute(base, a["curse_mult"] * moon * rush, p)
    play = total * 60
    fixed = daily_fixed(p)
    return play, fixed, play + sum(fixed.values()) / hours


def tricks_per_day(candy, p):
    n, spent = 0, 0
    while True:
        price = trick_price(n, p["TrickCost"], p["TrickLadder"])
        if spent + price > candy:
            return n + (candy - spent) / price  # the fractional rest: progress toward the next trick
        spent += price
        n += 1


def exorcism_cycles_per_hour(p, hours):
    a = ASSUME
    play, fixed, per_h = candy_per_hour(p, hours)
    souls = per_h  # 1 soul per candy granted
    souls += 60 * (1 - a["moon_share"]) * a["ore_breaks_per_min"] * a["souls_per_ore"]
    souls += 60 * a["moon_share"] * a["spots_per_min"] * a["souls_per_spot"]
    souls += 5 * a["souls_per_quest"] / hours
    server = souls * a["yard_players"]
    minutes = 5000 / server * 60 + a["boss_fight_minutes"]
    return 60 / minutes


def blocks_per_hour(p, hours):
    play, fixed, per_h = candy_per_hour(p, hours)
    day_candy = per_h * hours
    tricks = tricks_per_day(day_candy, p) / hours
    quest = 1 / hours
    exo = exorcism_cycles_per_hour(p, hours)
    return {"trick": tricks, "quest": quest, "exorcism": exo, "total": tricks + quest + exo,
            "pumpkin_trick": tricks * (1 - p["CursedChance"]), "cursed_trick": tricks * p["CursedChance"]}


def new_params(cfg):
    rb = cfg["Rebalance"]
    spots = {t["Id"]: (t["Weight"], t["Candy"][0], t["Candy"][1], t["RareChance"]) for t in cfg["DigSpots"]["Types"]}
    quests = {q["Id"]: q["Candy"] for q in cfg["Quests"]["Pool"]}
    boss = [(d["Candy"][0], d["Candy"][1], d["DogChance"], d.get("CursedBlock", 0), d.get("EclipseChance", 0))
            for d in cfg["Boss"]["Difficulties"]]
    return {
        "TrickCost": cfg["Cauldron"]["TrickCost"], "TrickLadder": rb["TrickEscalation"], "CursedChance": cfg["Cauldron"]["CursedChance"],
        "PerfectHitCap": cfg["Candy"]["PerfectHitCap"], "MinuteCap": cfg["Candy"]["MinuteCap"], "CapBeforeMult": True,
        "OreCandy": tuple(cfg["Ore"]["Candy"]), "RareFind": tuple(cfg["Candy"]["RareFind"]), "OreRare": cfg["Ore"]["RareChance"],
        "Spots": spots, "Treat": tuple(cfg["Candy"]["TreatHouse"]), "Trick": tuple(cfg["Candy"]["TrickHouse"]),
        "TreatChance": cfg["TrickOrTreat"]["TreatChance"], "MiniBoss": tuple(cfg["TrickOrTreat"]["MiniBossCandy"]),
        "MiniBossShare": 12 / 100, "BloodMoonBonus": cfg["BloodMoon"]["CandyBonus"], "Quests": quests,
        "AllBonusCandy": cfg["Quests"]["AllBonus"]["Candy"], "Boss": boss,
        "BossDogWeights": (cfg["Boss"]["DogWeights"]["Normal"], cfg["Boss"]["DogWeights"]["Rank5"]),
        "YardChance": cfg["Mutations"]["YardChance"], "PassiveScale": rb["PassiveScale"],
        "ExorcismBlockToAll": False, "BrewDeadline": rb["BrewDeadline"],
    }


# ---------------------------------------------------------------- report
def pct(x):
    if x == 0:
        return "0%"
    if x >= .001:
        return "%.4f%%" % (x * 100)
    return "%.6f%%" % (x * 100)


def one_in(x):
    if x <= 0:
        return "never"
    v = 1 / x
    return "%s" % format(int(round(v)), ",") if v >= 10 else "%.1f" % v


def table_report(name, old_rows, new_rows):
    lines = ["#### %s" % name, "",
             "| Row | Kind | Rarity | Class | x | Weight was | Chance was | 1 in (was) | Weight now (1e6) | Chance now | 1 in (now) |",
             "|---|---|---|---|---|---:|---:|---:|---:|---:|---:|"]
    for r in new_rows:
        filler = r["Class"] == "Filler"
        lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            r.get("Name"), r.get("Kind"), r.get("Rarity", ""), "filler" if filler else r["Class"],
            "-" if filler else ("%g" % r["Factor"]), "-" if filler else format(r["WeightWas"], ","),
            "-" if filler else pct(r["ChanceWas"]), "-" if filler else one_in(r["ChanceWas"]),
            format(r["Weight"], ","), pct(r["Chance"]), one_in(r["Chance"])))
    lines.append("")
    return lines


def hours_text(h):
    if not h < 1e12:
        return "-"
    return "%.1f" % h if h < 100 else format(int(round(h)), ",")


def group(rows, key):
    out = {}
    for r in rows:
        k = key(r)
        out[k] = out.get(k, 0) + r["Chance"]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float, default=2.0, help="hours of Dead Yard play per UTC day")
    ap.add_argument("--players", type=int, default=6, help="players active in the Dead Yard (exorcism)")
    ap.add_argument("--json", help="also write the numbers to this file")
    args = ap.parse_args()
    ASSUME["yard_players"] = args.players
    cfg = read_config()
    rb = cfg["Rebalance"]
    new = new_params(cfg)
    rewards = cfg["Rewards"]
    old_p = [r for r in rewards["Pumpkin"]]
    old_c = [r for r in rewards["CursedPumpkin"]]
    new_pt = rescale(old_p, rb["RarityScale"], rb["Filler"]["Pumpkin"])
    new_ct = rescale(old_c, rb["RarityScale"], rb["Filler"]["CursedPumpkin"])
    old_pt, old_ct = odds(old_p), odds(old_c)
    for r in new_pt + new_ct:  # sanity: the same contract the Lune test asserts
        if r["Class"] != "Filler":
            assert abs(r["Chance"] - r["ChanceWas"] * r["Factor"]) <= 1e-6, r
    assert sum(r["Weight"] for r in new_pt) == SCALE and sum(r["Weight"] for r in new_ct) == SCALE

    out = ["<!-- generated by tools/chapter1_balance.py --hours %g --players %d -->" % (args.hours, args.players), ""]
    out += ["### Pumpkin / Cursed Pumpkin (rare prize philosophy)", ""]
    out += table_report("PUMPKIN LUCKY BLOCK (filler: Lucky Dust %d-%d)" % tuple(rb["Filler"]["Pumpkin"]["Amount"]), old_pt, new_pt)
    out += table_report("CURSED PUMPKIN (filler: Lucky Dust %d-%d)" % tuple(rb["Filler"]["CursedPumpkin"]["Amount"]), old_ct, new_ct)
    out += ["By kind (chance per open, was -> now):", "",
            "| Kind | Pumpkin was | Pumpkin now | Cursed was | Cursed now |", "|---|---:|---:|---:|---:|"]
    kinds = ["Cash", "Bones", "Decor", "Mutation", "Skin", "Dog", "Dust"]
    gp_o, gp_n = group(old_pt, lambda r: r["Kind"]), group(new_pt, lambda r: r["Kind"])
    gc_o, gc_n = group(old_ct, lambda r: r["Kind"]), group(new_ct, lambda r: r["Kind"])
    for k in kinds:
        out.append("| %s | %s | %s | %s | %s |" % (k, pct(gp_o.get(k, 0)), pct(gp_n.get(k, 0)), pct(gc_o.get(k, 0)), pct(gc_n.get(k, 0))))
    out.append("")

    # exorcism Epic+ pumpkin
    ex_o, ex_n = epic_plus(old_p), epic_plus([r for r in new_pt if r["Class"] != "Filler"])
    out += ["#### Exorcism RARE PUMPKIN (MinRank 3: only Epic+ rows, renormalised; the Dust filler is Rank 1 and never in it)", "",
            "| Row | Chance was | Chance now |", "|---|---:|---:|"]
    for a, b in zip(ex_o, ex_n):
        out.append("| %s | %s | %s |" % (a["Name"], pct(a["Chance"]), pct(b["Chance"])))
    out.append("")

    # boss
    out += ["### The Gravekeeper (full reward)", "",
            "| Difficulty | Candy was | Candy now | Dog chance was | Dog chance now | per Legendary dog was -> now | per Mythic dog was -> now | Cursed block was -> now | ECLIPSED find was -> now |",
            "|---|---|---|---:|---:|---|---|---|---|"]
    names = ["I EASY", "II UNEASY", "III NIGHTMARE", "IV HELL", "V ???"]
    ow, nw = OLD["BossDogWeights"], new["BossDogWeights"]
    for i, (o, n) in enumerate(zip(OLD["Boss"], new["Boss"])):
        ot, nt = 2 * ow[0] + 2 * ow[1], 2 * nw[0] + 2 * nw[1]
        out.append("| %s | %d-%d | %d-%d | %s | %s | %s -> %s | %s -> %s | %s -> %s | %s -> %s |" % (
            names[i], o[0], o[1], n[0], n[1], pct(o[2]), pct(n[2]), pct(o[2] * ow[0] / ot), pct(n[2] * nw[0] / nt),
            pct(o[2] * ow[1] / ot), pct(n[2] * nw[1] / nt), pct(o[3]), pct(n[3]), pct(o[4]), pct(n[4])))
    out.append("")

    # trick ladder
    ladder = [trick_price(i, new["TrickCost"], new["TrickLadder"]) for i in range(8)]
    out += ["### TRICK price ladder (per UTC day)", "",
            "| Trick of the day | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |", "|---|---|---|---|---|---|---|---|---|",
            "| was | " + " | ".join(["80"] * 8) + " |", "| now | " + " | ".join(str(x) for x in ladder) + " |",
            "| now / was | " + " | ".join("%.2fx" % (x / 80) for x in ladder) + " |", ""]

    # economy
    res = {}
    for label, p in (("before", OLD), ("after", new)):
        play, fixed, per_h = candy_per_hour(p, args.hours)
        blocks = blocks_per_hour(p, args.hours)
        res[label] = {"play_candy_h": play, "fixed_day": fixed, "candy_h": per_h, "blocks": blocks,
                      "minute_ore": per_minute("ore", p), "minute_moon": per_minute("moon", p)}
    b, a = res["before"], res["after"]
    out += ["### Candy and Pumpkin blocks per hour (model, %g h of play per UTC day, %d active players in the yard)" % (args.hours, args.players), "",
            "| | before | after | after / before |", "|---|---:|---:|---:|"]

    def row(name, x, y, fmt="%.0f"):
        out.append("| %s | %s | %s | %s |" % (name, fmt % x, fmt % y, ("%.2f" % (y / x)) if x else "-"))
    row("base candy / minute, mining ore (pre-multiplier)", b["minute_ore"], a["minute_ore"], "%.1f")
    row("base candy / minute, Blood Moon spots (pre-multiplier)", b["minute_moon"], a["minute_moon"], "%.1f")
    row("candy / hour from play (incl. rush, Blood Moon, cap)", b["play_candy_h"], a["play_candy_h"])
    row("daily quests + all-quests bonus candy / day", b["fixed_day"]["quests"], a["fixed_day"]["quests"])
    row("door candy / day (7 knocks)", b["fixed_day"]["doors"], a["fixed_day"]["doors"])
    row("boss candy / day (1 kill, difficulty II)", b["fixed_day"]["boss"], a["fixed_day"]["boss"])
    row("**candy / hour (all sources)**", b["candy_h"], a["candy_h"])
    row("TRICK blocks / hour", b["blocks"]["trick"], a["blocks"]["trick"], "%.2f")
    row("daily all-quests block / hour", b["blocks"]["quest"], a["blocks"]["quest"], "%.2f")
    row("exorcism RARE pumpkins / hour", b["blocks"]["exorcism"], a["blocks"]["exorcism"], "%.2f")
    row("**Pumpkin-family blocks / hour**", b["blocks"]["total"], a["blocks"]["total"], "%.2f")
    out.append("")
    out.append("Blocks per hour of grinding: **%.1fx fewer** (target 4-6x). Without the exorcism share (a solo server): %.1fx." % (
        b["blocks"]["total"] / a["blocks"]["total"],
        (b["blocks"]["trick"] + b["blocks"]["quest"]) / (a["blocks"]["trick"] + a["blocks"]["quest"])))
    out.append("")

    # by hours of play
    out += ["Sensitivity (hours of play per UTC day):", "", "| hours / day | candy/h before | candy/h after | blocks/h before | blocks/h after | fewer |",
            "|---|---:|---:|---:|---:|---:|"]
    for hours in (0.5, 1, 2, 3, 5):
        bb, aa = blocks_per_hour(OLD, hours), blocks_per_hour(new, hours)
        out.append("| %g | %.0f | %.0f | %.2f | %.2f | %.1fx |" % (hours, candy_per_hour(OLD, hours)[2], candy_per_hour(new, hours)[2],
                                                           bb["total"], aa["total"], bb["total"] / aa["total"]))
    out.append("")

    # passive
    ys = new["YardChance"]
    out += ["### Passive yard event mutations (per item attempt of an ordinary yard dig)", "",
            "| Mutation | was | now |", "|---|---:|---:|"]
    for k in ("HAUNTED", "PUMPKINIZED", "BLOOD MOON"):
        out.append("| %s%s | %s | %s |" % (k, " (Blood Moon only)" if k == "BLOOD MOON" else "", pct(ys[k]), pct(ys[k] * new["PassiveScale"])))
    out.append("")

    # chase items
    out += ["### Chase items: expected opens and hours of play (model above)", "",
            "| Prize | Pumpkin opens was | Pumpkin opens now | Cursed opens was | Cursed opens now | hours of play was | hours of play now |",
            "|---|---:|---:|---:|---:|---:|---:|"]

    def chance_of(rows, ident):
        return sum(r["Chance"] for r in rows if (r.get("Kind"), r.get("Id")) == ident)
    idents = []
    for r in old_p + old_c:
        if r["Kind"] in ("Dog", "Skin", "Mutation", "Decor") and (r["Kind"], r["Id"]) not in idents:
            idents.append((r["Kind"], r["Id"]))
    names = {(r["Kind"], r.get("Id")): r["Name"] for r in old_p + old_c}

    def hours_for(ident, which):
        p = OLD if which == "before" else new
        pt, ct = (old_pt, old_ct) if which == "before" else (new_pt, new_ct)
        ex = ex_o if which == "before" else ex_n
        bl = blocks_per_hour(p, args.hours)
        rate = (bl["pumpkin_trick"] + bl["quest"]) * chance_of(pt, ident) + bl["cursed_trick"] * chance_of(ct, ident) \
            + bl["exorcism"] * chance_of(ex, ident)
        if ident[0] == "Dog" and ident[1] in ("HW_Frankenpug", "HW_BatDachshund", "HW_PlaguePug", "HW_HeadlessHound"):
            bo = p["Boss"][ASSUME["boss_difficulty"] - 1]
            w = p["BossDogWeights"]
            share = (w[1] if ident[1] in ("HW_PlaguePug", "HW_HeadlessHound") else w[0]) / (2 * w[0] + 2 * w[1])
            rate += ASSUME["boss_kills_per_day"] / args.hours * bo[2] * share
        return 1 / rate if rate > 0 else math.inf
    chase = []
    for ident in idents:
        po, pn = chance_of(old_pt, ident), chance_of(new_pt, ident)
        co, cn = chance_of(old_ct, ident), chance_of(new_ct, ident)
        hb, ha = hours_for(ident, "before"), hours_for(ident, "after")
        chase.append({"Prize": names[ident], "Kind": ident[0], "Id": ident[1], "PumpkinWas": po, "PumpkinNow": pn,
                      "CursedWas": co, "CursedNow": cn, "HoursWas": hb, "HoursNow": ha})
        out.append("| %s (%s) | %s | %s | %s | %s | %s | %s |" % (
            names[ident], ident[0], one_in(po) if po else "-", one_in(pn) if pn else "-", one_in(co) if co else "-",
            one_in(cn) if cn else "-", hours_text(hb), hours_text(ha)))
    out.append("")
    out.append("(\"opens\" = expected blocks of that tier opened for one copy; \"hours\" = expected hours of play at the model's block, "
               "boss and exorcism rates, all sources combined)")
    print("\n".join(out))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump({"before": res["before"], "after": res["after"], "chase": chase,
                       "pumpkin": new_pt, "cursed": new_ct, "assume": ASSUME}, f, indent=1, default=str)


if __name__ == "__main__":
    main()
