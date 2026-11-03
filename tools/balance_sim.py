#!/usr/bin/env python3
"""Throw a Ball for Dogs balance simulator (Monte Carlo + analytic).

Every number is parsed from the REAL game config (src/shared/Config/*.luau) and the roster
(data/zones/*.csv), so re-running after a tuning pass reflects the game as shipped.

Usage:
  python3 tools/balance_sim.py                 # full report (default 60 runs per scenario)
  python3 tools/balance_sim.py --runs 200      # more Monte Carlo runs
  python3 tools/balance_sim.py --hours 30      # simulated PLAY hours (default 30)
  python3 tools/balance_sim.py --quick         # 20 runs, F2P baseline only

Player model (a "typical F2P player"; all assumptions are constants below):
  * Sessions of SESSION_MIN minutes of play, then a long offline gap (offline earnings capped by
    Timers.OfflineCapSeconds x Timers.OfflineRate; puppies keep growing in real time). One daily
    walk claimed per session (= one per real day).
  * Inside a session the player alternates THROW blocks and TRAIN blocks (THROW_SHARE of play time
    throwing), plus a small walking overhead.
  * Timing skill: release error ~ N(0, TIMING_SD) seconds around the meter peak -> mean quality
    ~0.70 (see analytic table). Tutorial throw is guaranteed Common in the Backyard.
  * Training: Pull-Up Bar at PULLUP_RPS reps/s (human pressing the prompt), Throwing Machine at
    1 rep/s whenever unlocked and the rep cost is < 2% of cash, Sprint laps ignored for the F2P baseline
    (reported analytically).
  * Shopping: greedy "cheapest useful upgrade first" over {next Training level, next Ball, +Slots
    when the yard is full}. Boosts/consumables only in the dedicated scenarios.
  * Yard: keeps the best dogs by adult income; when full, sells the weakest if the new dog is better
    (manual sell pays SellIncomeSeconds of adult income) otherwise sells the new one. Dupes auto-sell
    per Shop.DefaultKeepDupes. Kennel Book milestones are claimed automatically.
"""
import csv
import glob
import math
import os
import random
import re
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG = os.path.join(ROOT, "src", "shared", "Config")

# ------------------------------------------------------------------ player-model assumptions
SESSION_MIN = 60          # minutes of play per session (one session per real day)
THROW_SHARE = 0.5         # share of play time spent throwing (rest: training)
BLOCK_SEC = 120           # length of one throw block / train block
WALK_OVERHEAD = 10        # seconds lost walking pad <-> plaza per block switch
TARGET_MEAN_QUALITY = 0.70  # "average player"; TIMING_SD is calibrated to hit this
TIMING_SD = 0.5           # release timing error (s); overwritten by calibrate()
REACTION = 0.8            # seconds of human slack per throw
PULLUP_RPS = 1.6          # pull-up reps / second a person actually presses
FTUE_SECONDS = 45         # spawn -> walk to pad -> tutorial throw starts
SHOP_WALK = 25            # walk to the shop + buy (first training purchase)
SQUIRREL_WIN_P = 1 / 6    # 6-player servers


# ------------------------------------------------------------------ parsing helpers
def read(name):
    with open(os.path.join(CFG, name), encoding="utf-8") as f:
        return f.read()


def ev(expr):
    expr = expr.replace("_", "").strip()
    if not re.fullmatch(r"[\d.\s*+/()-]+", expr):
        raise ValueError("unsafe expr " + expr)
    return eval(expr)  # noqa: S307  (digits/operators only, checked above)


NUM = r"([\d_.]+(?:\s*[*/]\s*[\d_.]+)*)"


def field(text, key):
    m = re.search(r"\b" + key + r"\s*=\s*" + NUM, text)
    if not m:
        raise SystemExit("config key not found: " + key)
    return ev(m.group(1))


def block(text, name):
    """Text of the table literal `name = { ... }` (brace matched)."""
    m = re.search(r"\b" + re.escape(name) + r"\s*=\s*\{", text)
    if not m:
        raise SystemExit("config table not found: " + name)
    i, depth = m.end() - 1, 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i:j + 1]
    raise SystemExit("unbalanced table " + name)


def load_config():
    c = {}
    g = read("Game.luau")
    c["StartingCash"] = field(g, "Game.StartingCash")
    c["StartingThrowPower"] = field(g, "Game.StartingThrowPower")
    meter = block(g, "Game.Meter")
    c["Meter"] = {k: field(meter, k) for k in ("Period", "PerfectMin", "GoodMin", "GoodQualityMin", "GoodQualityMax",
                                              "OkQualityMin", "OkQualitySpan", "FlubQuality")}
    thr = block(g, "Game.Throw")
    c["Throw"] = {k: field(thr, k) for k in ("MinChargeSeconds", "MinSecondsBetweenThrows", "Scatter", "MinDistance")}
    c["MinCommonOdds"] = field(block(g, "Game.Luck"), "MinCommonOdds")
    c["MaxCatch"] = field(block(g, "Game.Catch"), "MaxChance")

    r = read("Rarities.luau")
    c["Order"] = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
    c["Tiers"] = {}
    for m in re.finditer(r"(\w+)\s*=\s*\{\s*Odds\s*=\s*([\d.]+),\s*Catch\s*=\s*([\d.]+),\s*IncomeMult\s*=\s*([\d.]+)", r):
        c["Tiers"][m.group(1)] = {"Odds": float(m.group(2)), "Catch": float(m.group(3)), "IncomeMult": float(m.group(4))}
    c["Variants"] = {}
    for m in re.finditer(r"(Gold|Shadow|Rainbow)\s*=\s*\{\s*Chance\s*=\s*([\d.]+),\s*IncomeMult\s*=\s*([\d.]+)", r):
        c["Variants"][m.group(1)] = {"Chance": float(m.group(2)), "IncomeMult": float(m.group(3))}
    c["VariantOrder"] = ["Gold", "Shadow", "Rainbow"]
    c["StreakMisses"] = field(r, "Rarities.LuckyStreakMisses")

    z = read("Zones.luau")
    c["Zones"] = []
    for m in re.finditer(r'Id\s*=\s*"(\w+)",\s*Name\s*=\s*"([^"]+)",\s*Order\s*=\s*\d+,\s*MinDistance\s*=\s*([\d.]+),'
                         r'\s*MaxDistance\s*=\s*([\d.]+),\s*BaseIncome\s*=\s*([\d.]+)', z):
        c["Zones"].append({"Id": m.group(1), "Name": m.group(2), "Min": float(m.group(3)), "Max": float(m.group(4)),
                           "Base": float(m.group(5))})

    b = read("Balls.luau")
    c["Balls"] = []
    for m in re.finditer(r'(\w+)\s*=\s*\{\s*Id\s*=\s*"\w+",\s*Name\s*=\s*"([^"]+)",\s*Order\s*=\s*(\d+),\s*RangeMult\s*=\s*([\d.]+),'
                         r'\s*Luck\s*=\s*([\d.]+),\s*Price\s*=\s*([\d_]+)', b):
        c["Balls"].append({"Id": m.group(1), "Name": m.group(2), "Order": int(m.group(3)), "Range": float(m.group(4)),
                           "Luck": float(m.group(5)), "Price": ev(m.group(6))})
    c["Balls"].sort(key=lambda x: x["Order"])

    t = read("Training.luau")
    c["MaxThrowPower"] = field(t, "Training.MaxThrowPower")
    c["Stations"] = {}
    for sid in ("PullUpBar", "ThrowingMachine", "Sprint"):
        s = block(t, sid)
        c["Stations"][sid] = {k: field(s, k) for k in ("Gain", "Cooldown", "UnlockPower", "CashPerRepMin",
                                                      "CashPerRepPerPower")}
    up = block(t, "Training.Upgrades")
    c["Upg"] = {k: field(up, k) for k in ("MaxLevel", "MultBase", "BaseCost", "CostGrowth")}
    c["Upg"]["Caps"] = [ev(x) for x in re.findall(r"[\d_.]+", re.sub(r"--[^\n]*", "", block(up, "Caps")[1:-1]))]

    s = read("Shop.luau")
    sl = block(s, "Shop.Slots")
    c["Slots"] = {k: field(sl, k) for k in ("Start", "Step", "Max", "BaseCost", "CostGrowth")}
    c["Boosts"] = {}
    for bid in ("StickyBall", "LuckyBiscuit"):
        bb = block(s, bid)
        c["Boosts"][bid] = {k: field(bb, k) for k in ("Amount", "Duration", "BaseCost", "IncomeSeconds")}
    c["Items"] = {}
    for iid in ("GoldenWhistle", "TreatPocket"):
        bb = block(s, iid)
        c["Items"][iid] = {k: field(bb, k) for k in ("BaseCost", "IncomeSeconds")}
    c["SellSeconds"] = field(s, "Shop.SellIncomeSeconds")
    keep = block(s, "Shop.DefaultKeepDupes")
    c["KeepDupes"] = {k: v == "true" for k, v in re.findall(r"(\w+)\s*=\s*(true|false)", keep)}
    dw = block(s, "Shop.DailyWalk")
    c["DailyWalk"] = {k: field(dw, k) for k in ("IncomeSeconds", "MinCash", "Bones", "PremiumThrows")}
    c["PremiumCatch"] = field(block(s, "Shop.PremiumThrow"), "CatchBonus")
    sq = block(s, "Shop.Squirrel")
    c["Squirrel"] = {k: field(sq, k) for k in ("WinnerBones", "BonesPerPlayer", "ConsolationBones")}
    br = block(s, "Shop.BookRewards")
    c["BookCashSeconds"] = field(br, "ZoneIncomeSeconds")
    c["BookLuck"] = field(br, "Luck")
    c["BookBones"] = [int(x) for x in re.findall(r"Bones\s*=\s*(\d+)", br)]
    cos = block(s, "Shop.Cosmetics")
    c["CosmeticBones"] = [int(x) for x in re.findall(r"Bones\s*=\s*(\d+)", cos)]

    tm = read("Timers.luau")
    gr = block(tm, "Timers.Growth")
    c["Growth"] = {k: field(gr, k) for k in c["Order"]}
    c["PuppyFrac"] = field(tm, "Timers.PuppyIncomeFraction")
    cu = block(tm, "Timers.Cutscene")
    c["Cutscene"] = {k: field(cu, k) for k in c["Order"]}
    c["SkipAfter"] = field(tm, "Timers.CommonSkippableAfter")
    c["SquirrelInterval"] = field(tm, "Timers.SquirrelInterval")
    c["OfflineCap"] = field(tm, "Timers.OfflineCapSeconds")
    c["OfflineRate"] = field(tm, "Timers.OfflineRate")

    p = read("Products.luau")
    c["Pass"] = {
        "DoubleCash": field(block(p, "DoubleCash"), "IncomeMult"),
        "ExtraSlots": field(block(p, "ExtraSlots"), "Slots"),
        "FastGrowth": field(block(p, "FastGrowth"), "GrowthSpeed"),
        "LuckyPaw": field(block(p, "LuckyPaw"), "Luck"),
    }
    c["ServerLuck"] = field(block(p, "ServerLuck"), "ServerLuck")

    # roster
    c["Dogs"] = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "zones", "*.csv"))):
        with open(path, encoding="utf-8") as f:
            for row in csv.DictReader(f):
                zt = c["Dogs"].setdefault(row["zone"], {})
                zt.setdefault(row["rarity"], []).append((row["id"], float(row["income"])))
    return c


# ------------------------------------------------------------------ game maths (mirrors the Luau)
class Game:
    def __init__(self, c):
        self.c = c
        self.non_common = sum(c["Tiers"][t]["Odds"] for t in c["Order"][1:])
        self.max_luck = (1 - c["MinCommonOdds"]) / self.non_common - 1

    def tier_odds(self, luck):  # Util/Odds.TierOdds
        mult = min(1 + max(0, luck), 1 + self.max_luck)
        out = {t: self.c["Tiers"][t]["Odds"] * mult for t in self.c["Order"][1:]}
        out["Common"] = max(0, 1 - sum(out.values()))
        return out

    def catch(self, tier, bonus):
        return min(max(self.c["Tiers"][tier]["Catch"] + max(0, bonus), 0), self.c["MaxCatch"])

    def quality(self, pos):  # Util/Meter.QualityForPosition
        m = self.c["Meter"]
        if pos >= m["PerfectMin"]:
            return 1.0
        if pos >= m["GoodMin"]:
            a = (pos - m["GoodMin"]) / (m["PerfectMin"] - m["GoodMin"])
            return m["GoodQualityMin"] + (m["GoodQualityMax"] - m["GoodQualityMin"]) * a
        return m["OkQualityMin"] + m["OkQualitySpan"] * (pos / m["GoodMin"])

    def sample_quality(self, rng, sd=None):
        P = self.c["Meter"]["Period"]
        e = rng.gauss(0, TIMING_SD if sd is None else sd)
        pos = max(0.0, 1 - 2 * abs(e) / P)
        return self.quality(pos)

    def zone_index(self, d):
        zs = self.c["Zones"]
        for i, z in enumerate(zs):
            if d >= z["Min"] and (d < z["Max"] or i == len(zs) - 1):
                return i
        return 0 if d < zs[0]["Min"] else len(zs) - 1

    def train_mult(self, lvl):
        return self.c["Upg"]["MultBase"] ** lvl

    def power_cap(self, lvl):  # Config/Training.PowerCap
        caps = self.c["Upg"]["Caps"]
        return min(self.c["MaxThrowPower"], caps[max(0, min(int(lvl), len(caps) - 1))])

    def train_cost(self, nxt):
        u = self.c["Upg"]
        return math.floor(u["BaseCost"] * u["CostGrowth"] ** (nxt - 1))

    def slot_cost(self, slots):
        s = self.c["Slots"]
        bought = max(0, (slots - s["Start"]) // s["Step"])
        return math.floor(s["BaseCost"] * s["CostGrowth"] ** bought)

    def rep_cost(self, sid, tp):
        st = self.c["Stations"][sid]
        if st["CashPerRepPerPower"] <= 0:
            return 0
        return math.floor(max(st["CashPerRepMin"], tp * st["CashPerRepPerPower"]))


# ------------------------------------------------------------------ one simulated player
class Player:
    def __init__(self, g, rng, opts):
        self.g, self.c, self.rng, self.o = g, g.c, rng, opts
        c = self.c
        self.t = 0.0          # play seconds
        self.real = 0.0       # real seconds (play + offline)
        self.cash = float(c["StartingCash"])
        self.tp = float(c["StartingThrowPower"])
        self.lvl = 0
        self.ball = 0
        self.slots = c["Slots"]["Start"] + (c["Pass"]["ExtraSlots"] if opts.get("ExtraSlots") else 0)
        self.slot_buys = 0
        self.dogs = []        # [income_adult, grown_at_real, dog_id, variant, tier]
        self.book = {}        # zone -> set(dog ids)
        self.claimed = set()
        self.perm_luck = 0.0
        self.streak = 0
        self.bones = 0
        self.premium = 0
        self.whistles = 0
        self.pockets = 0
        self.common_seen = 0
        self.income_mult = c["Pass"]["DoubleCash"] if opts.get("DoubleCash") else 1
        self.grow_speed = c["Pass"]["FastGrowth"] if opts.get("FastGrowth") else 1
        self.boost_until = {"StickyBall": -1, "LuckyBiscuit": -1}
        self.events = {}      # first-time events -> play seconds
        self.purchases = []   # (play_s, what, cost, income_at_purchase)
        self.samples = []     # (play_s, income, tp, zone_idx_median, cash)
        self.spent = {"Training": 0, "Ball": 0, "Slots": 0, "Boosts": 0, "Items": 0, "MachineReps": 0}
        self.earned = {"Active": 0, "Offline": 0, "Sell": 0, "Daily": 0, "Book": 0}
        self.catches = {t: 0 for t in c["Order"]}
        self.misses = {t: 0 for t in c["Order"]}
        self.last_squirrel = 0.0
        self.recalls = 0

    # -- derived
    def income(self, real=None):
        real = self.real if real is None else real
        s = 0.0
        for inc, grown, *_ in self.dogs:
            s += inc if real >= grown else inc * self.c["PuppyFrac"]
        return s * self.income_mult

    def range_mult(self):
        return self.c["Balls"][self.ball]["Range"]

    def median_zone(self):
        return self.g.zone_index(self.tp * self.range_mult() * self.o.get("q_median", 0.72))

    def luck(self, premium=False):
        l = self.c["Balls"][self.ball]["Luck"] + self.perm_luck
        if self.boost_until["LuckyBiscuit"] > self.real:
            l += self.c["Boosts"]["LuckyBiscuit"]["Amount"]
        if self.o.get("LuckyPaw"):
            l += self.c["Pass"]["LuckyPaw"]
        if premium:
            l += max(0, self.c["Balls"][-1]["Luck"] - self.c["Balls"][self.ball]["Luck"])
        return l

    def mark(self, key):
        if key not in self.events:
            self.events[key] = self.t

    # -- time passes (active play)
    def advance(self, dt):
        inc0 = self.income()
        self.t += dt
        self.real += dt
        inc1 = self.income()
        gain = (inc0 + inc1) / 2 * dt
        self.cash += gain
        self.earned["Active"] += gain
        # squirrel (every interval of play; joins, wins 1/6)
        while self.t - self.last_squirrel >= self.c["SquirrelInterval"]:
            self.last_squirrel += self.c["SquirrelInterval"]
            sq = self.c["Squirrel"]
            if self.rng.random() < SQUIRREL_WIN_P:
                self.bones += sq["WinnerBones"] + sq["BonesPerPlayer"] * 6
            else:
                self.bones += sq["ConsolationBones"]

    def offline(self, seconds):
        cap = min(seconds, self.c["OfflineCap"])
        self.real += seconds
        amt = self.income() * cap * self.c["OfflineRate"]  # rate at login (puppies grown meanwhile)
        self.cash += amt
        self.earned["Offline"] += amt

    def daily_walk(self):
        dw = self.c["DailyWalk"]
        amt = max(dw["MinCash"], self.income() * dw["IncomeSeconds"])
        self.cash += amt
        self.earned["Daily"] += amt
        self.bones += dw["Bones"]
        self.premium += dw["PremiumThrows"]

    # -- yard
    def sell_value(self, inc):
        return inc * self.c["SellSeconds"]

    def add_dog(self, dog_id, tier, variant, inc_base, zone):
        c = self.c
        vm = c["Variants"][variant]["IncomeMult"] if variant else 1
        inc = inc_base * vm
        self.book.setdefault(zone, set()).add(dog_id)
        self.claim_book(zone)
        dupe = any(d[2] == dog_id and d[3] == variant for d in self.dogs)
        if dupe and not c["KeepDupes"].get(tier, False):
            v = self.sell_value(inc)
            self.cash += v
            self.earned["Sell"] += v
            return
        grown = self.real + math.ceil(c["Growth"][tier] / self.grow_speed)
        rec = [inc, grown, dog_id, variant, tier]
        if len(self.dogs) < self.slots:
            self.dogs.append(rec)
            return
        weakest = min(range(len(self.dogs)), key=lambda i: self.dogs[i][0])
        if self.dogs[weakest][0] < inc:
            v = self.sell_value(self.dogs[weakest][0])
            self.dogs[weakest] = rec
        else:
            v = self.sell_value(inc)
        self.cash += v
        self.earned["Sell"] += v

    def claim_book(self, zone):
        zi = [z["Id"] for z in self.c["Zones"]].index(zone)
        n = len(self.book[zone])
        for k, m in enumerate((25, 50, 75, 100)):
            if (zone, m) not in self.claimed and n >= math.ceil(80 * m / 100):
                self.claimed.add((zone, m))
                if m == 25:
                    amt = self.c["Zones"][zi]["Base"] * self.c["BookCashSeconds"]
                    self.cash += amt
                    self.earned["Book"] += amt
                elif m == 50:
                    self.perm_luck += self.c["BookLuck"]
                if k < len(self.c["BookBones"]):
                    self.bones += self.c["BookBones"][k]

    # -- the throw
    def throw(self, tutorial=False):
        g, c, rng = self.g, self.c, self.rng
        q = g.sample_quality(rng, self.o.get("sd"))
        if tutorial:
            zi = 0
        else:
            d = self.tp * self.range_mult() * q * (1 + rng.uniform(-c["Throw"]["Scatter"], c["Throw"]["Scatter"]))
            d = max(d, c["Throw"]["MinDistance"])
            zi = g.zone_index(d)
            self.mark("land:" + c["Zones"][zi]["Id"])
        zone = c["Zones"][zi]["Id"]
        premium = (not tutorial) and self.premium > 0
        if premium:
            self.premium -= 1
        luck = self.luck(premium)
        if tutorial:
            tier = "Common"
        else:
            odds = g.tier_odds(luck)
            r, acc, tier = rng.random(), 0.0, "Common"
            for t in c["Order"]:
                acc += odds[t]
                if r < acc:
                    tier = t
                    break
        dog_id, inc = rng.choice(c["Dogs"][zone][tier])
        variant = None
        if tier != "Common" and not tutorial:
            for v in reversed(c["VariantOrder"]):
                if rng.random() < c["Variants"][v]["Chance"]:
                    variant = v
                    break
        bonus = 0.0
        if self.boost_until["StickyBall"] > self.real:
            bonus += c["Boosts"]["StickyBall"]["Amount"]
        elif premium:
            bonus += c["PremiumCatch"]
        chance = g.catch(tier, bonus)
        legend = tier in ("Legendary", "Mythic")
        if tutorial:
            caught = True
        elif legend and self.streak >= c["StreakMisses"]:
            caught = True
        else:
            caught = rng.random() < chance
            if not caught and self.pockets > 0 and (self.o.get("PocketMode") == "Always" or
                                                     c["Order"].index(tier) >= 3):
                self.pockets -= 1
                caught = rng.random() < chance
        if legend:
            self.streak = 0 if caught else self.streak + 1
        if not caught and self.whistles > 0 and c["Order"].index(tier) >= self.o.get("WhistleMin", 3):
            self.whistles -= 1
            self.recalls += 1
            caught = True
            if legend:
                self.streak = 0
        if caught:
            self.catches[tier] += 1
            self.mark("catch:" + tier)
            self.add_dog(dog_id, tier, variant, inc, zone)
            if variant:
                self.mark("variant:" + variant)
        else:
            self.misses[tier] += 1
        cut = c["Cutscene"][tier]
        if tier == "Common":
            self.common_seen += 1
            if self.common_seen > c["SkipAfter"] and not tutorial:
                cut = 0.6
        charge = c["Meter"]["Period"] / 2 * (2 if tutorial else 1)
        return charge + max(c["Throw"]["MinSecondsBetweenThrows"], cut) + REACTION

    # -- training (returns the seconds actually spent; the player stops at the power cap)
    def train(self, seconds):
        c, g = self.c, self.g
        mult = g.train_mult(self.lvl)
        mach = c["Stations"]["ThrowingMachine"]
        pull = c["Stations"]["PullUpBar"]
        dt = 5.0
        el = 0.0
        while el < seconds - 1e-9:
            cap = g.power_cap(self.lvl)
            if self.tp >= cap:
                break
            mult = g.train_mult(self.lvl)
            step = min(dt, seconds - el)
            cost = g.rep_cost("ThrowingMachine", self.tp)
            use_machine = self.tp >= mach["UnlockPower"] and cost * 50 <= self.cash and not self.o.get("NoMachine")
            if use_machine:
                reps = step / mach["Cooldown"]
                self.cash -= cost * reps
                self.spent["MachineReps"] += cost * reps
                self.tp += reps * mach["Gain"] * mult
            else:
                self.tp += step * PULLUP_RPS * pull["Gain"] * mult
            self.tp = min(self.tp, cap)
            self.advance(step)
            self.after_step()
            el += step
        return el

    # -- purchases
    def options(self):
        g, c = self.g, self.c
        opts = []
        if self.lvl < c["Upg"]["MaxLevel"]:
            opts.append(("Training", g.train_cost(self.lvl + 1)))
        if self.ball + 1 < len(c["Balls"]):
            opts.append(("Ball", c["Balls"][self.ball + 1]["Price"]))
        if self.slots < c["Slots"]["Max"] + (c["Pass"]["ExtraSlots"] if self.o.get("ExtraSlots") else 0) \
                and len(self.dogs) >= self.slots:
            opts.append(("Slots", g.slot_cost(self.slots - (c["Pass"]["ExtraSlots"] if self.o.get("ExtraSlots") else 0))))
        return opts

    def shop(self):
        c = self.c
        while True:
            opts = self.options()
            if not opts:
                return
            what, cost = min(opts, key=lambda x: x[1])
            if cost > self.cash:
                break
            inc = self.income()
            self.cash -= cost
            self.spent[what] += cost
            if what == "Training":
                self.lvl += 1
                self.mark("buy:Training%d" % self.lvl)
                label = "Training L%d" % self.lvl
            elif what == "Ball":
                self.ball += 1
                label = "Ball " + c["Balls"][self.ball]["Id"]
                self.mark("buy:" + label)
            else:
                self.slots += c["Slots"]["Step"]
                self.slot_buys += 1
                label = "Slots ->%d" % self.slots
                self.mark("buy:" + label)
            self.purchases.append((self.t, label, cost, inc))
        # optional consumables
        inc = self.income()
        for bid in self.o.get("Boosts", ()):
            if self.boost_until[bid] <= self.real:
                b = c["Boosts"][bid]
                price = max(b["BaseCost"], math.ceil(inc * b["IncomeSeconds"]))
                if price <= self.cash * 0.25:
                    self.cash -= price
                    self.spent["Boosts"] += price
                    self.boost_until[bid] = self.real + b["Duration"]
        for iid, field_ in (("GoldenWhistle", "whistles"), ("TreatPocket", "pockets")):
            if iid in self.o.get("Items", ()) and getattr(self, field_) < 1:
                it = c["Items"][iid]
                price = max(it["BaseCost"], math.ceil(inc * it["IncomeSeconds"]))
                if price <= self.cash * 0.25:
                    self.cash -= price
                    self.spent["Items"] += price
                    setattr(self, field_, getattr(self, field_) + 1)

    def after_step(self):
        self.shop()
        zi = self.median_zone()
        self.mark("reach:" + self.c["Zones"][zi]["Id"])
        for j in range(zi):
            self.mark("reach:" + self.c["Zones"][j]["Id"])

    def sample(self):
        self.samples.append((self.t, self.income(), self.tp, self.median_zone(), self.cash, self.lvl, self.ball,
                             self.slots))

    # -- the whole run
    def run(self, play_hours):
        end = play_hours * 3600
        # FTUE
        self.advance(FTUE_SECONDS)
        self.advance(self.throw(tutorial=True))
        self.advance(SHOP_WALK)
        self.shop()
        self.mark("ftue_done")
        next_sample = 0.0
        smin = self.o.get("session_min", SESSION_MIN)
        session_end = smin * 60
        first_session = True
        while self.t < end:
            if self.t >= session_end:
                self.offline(24 * 3600 - smin * 60)
                session_end = self.t + smin * 60
                first_session = False
                self.daily_walk()
                self.shop()
            if first_session and self.t < 70 and not self.events.get("dw"):
                self.events["dw"] = 1
                self.daily_walk()
            # throw block
            blk_end = min(self.t + BLOCK_SEC * THROW_SHARE * 2, session_end, end)
            while self.t < blk_end:
                dt = self.throw()
                self.advance(dt)
                self.after_step()
                if self.t >= next_sample:
                    self.sample()
                    next_sample += 300
            tr = min(BLOCK_SEC * (1 - THROW_SHARE) * 2, max(0, session_end - self.t), max(0, end - self.t))
            if tr > 0 and self.tp < self.g.power_cap(self.lvl):
                self.advance(WALK_OVERHEAD)
                self.train(tr)
                self.advance(WALK_OVERHEAD)
            if self.t >= next_sample:
                self.sample()
                next_sample += 300
        self.sample()
        return self


# ------------------------------------------------------------------ reporting
def fmt_t(s):
    if s is None:
        return "never"
    if s < 120:
        return "%ds" % s
    if s < 7200:
        return "%.0fm" % (s / 60)
    return "%.1fh" % (s / 3600)


def fmt_n(x):
    for unit, v in (("T", 1e12), ("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if abs(x) >= v:
            return "%.2f%s" % (x / v, unit)
    return "%.1f" % x


def med(vals):
    vals = [v for v in vals if v is not None]
    return statistics.median(vals) if vals else None


def ev_time(runs, key):
    """Median time of an event; None counts as 'never' (sorted last)."""
    xs = sorted((r.events.get(key, math.inf) for r in runs))
    m = xs[len(xs) // 2]
    return None if m == math.inf else m


def frac(runs, key):
    return sum(1 for r in runs if key in r.events) / len(runs)


def run_scenario(c, n, hours, opts, seed=1):
    g = Game(c)
    out = []
    for i in range(n):
        rng = random.Random(seed * 100003 + i)
        out.append(Player(g, rng, opts).run(hours))
    return out


def analytic(c, out):
    g = Game(c)
    rng = random.Random(7)
    qs = sorted(g.sample_quality(rng) for _ in range(200000))
    meanq = sum(qs) / len(qs)
    out.append("## Analytic\n")
    out.append("Timing quality (release error sd %.2fs): mean %.3f, median %.3f, P10 %.3f, P90 %.3f; "
               "Perfect-band share %.0f%%\n" % (TIMING_SD, meanq, qs[len(qs) // 2], qs[len(qs) // 10],
                                               qs[len(qs) * 9 // 10], 100 * sum(1 for q in qs if q >= 1) / len(qs)))
    out.append("| Zone | Min dist | ThrowPower for median throw (Tennis / Rubber / Flying Disc / Glow / Golden) | Common $/s | "
               "Mythic $/s |")
    out.append("|---|---|---|---|---|")
    qm = qs[len(qs) // 2]
    for z in c["Zones"]:
        need = " / ".join("%d" % math.ceil(z["Min"] / (b["Range"] * qm)) for b in c["Balls"])
        inc = c["Dogs"][z["Id"]]
        out.append("| %s | %d | %s | %s | %s |" % (z["Name"], z["Min"], need, fmt_n(inc["Common"][0][1]),
                                                  fmt_n(inc["Mythic"][0][1])))
    out.append("")
    # tier odds per ball + expected value of one throw into a zone (relative to a Common)
    out.append("| Ball | Range | Luck | Price | Common | Uncommon | Rare | Epic | Legendary | Mythic | E[income/throw] vs Tennis |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|")
    base_ev = None
    for b in c["Balls"]:
        o = g.tier_odds(b["Luck"])
        e = sum(o[t] * g.catch(t, 0) * c["Tiers"][t]["IncomeMult"] for t in c["Order"])
        base_ev = base_ev or e
        out.append("| %s | x%.2f | +%.2f | %s | %s |  x%.2f |" % (
            b["Name"], b["Range"], b["Luck"], fmt_n(b["Price"]),
            " | ".join("%.2f%%" % (100 * o[t]) for t in c["Order"]), e / base_ev))
    out.append("")
    # per-tier catch (with streak) + variant chances
    rem, vc = 1.0, {}
    for v in reversed(c["VariantOrder"]):
        vc[v] = rem * c["Variants"][v]["Chance"]
        rem *= 1 - c["Variants"][v]["Chance"]
    out.append("Variant odds per non-Common: " + ", ".join("%s %.3f%%" % (v, 100 * vc[v]) for v in c["VariantOrder"]) +
               " (none %.2f%%). Expected variant income mult per non-Common: x%.3f\n" % (
                   100 * rem, rem + sum(vc[v] * c["Variants"][v]["IncomeMult"] for v in vc)))
    # training stations
    out.append("Training rates at level L (TP/s x 1.5^L): Pull-Up %.2f (at %.1f reps/s), Throwing Machine %.2f "
               "(costs max($%d, TP x %.2f)/rep), Sprint %.2f (one lap of %d studs at WalkSpeed 16 = %.1fs)\n" % (
                   PULLUP_RPS * c["Stations"]["PullUpBar"]["Gain"], PULLUP_RPS,
                   c["Stations"]["ThrowingMachine"]["Gain"] / c["Stations"]["ThrowingMachine"]["Cooldown"],
                   c["Stations"]["ThrowingMachine"]["CashPerRepMin"], c["Stations"]["ThrowingMachine"]["CashPerRepPerPower"],
                   c["Stations"]["Sprint"]["Gain"] / max(c["Stations"]["Sprint"]["Cooldown"], 220 / 16), 220, 220 / 16))
    out.append("| Training level | Cost | Gain mult |")
    out.append("|---|---|---|")
    for L in (1, 2, 3, 4, 5, 6, 8, 10, 12, 15):
        out.append("| %d | %s | x%.1f |" % (L, fmt_n(g.train_cost(L)), g.train_mult(L)))
    out.append("")
    out.append("| Slot purchase # | Slots after | Cost |")
    out.append("|---|---|---|")
    s = c["Slots"]["Start"]
    for i in range(1, 9):
        out.append("| %d | %d | %s |" % (i, s + c["Slots"]["Step"], fmt_n(g.slot_cost(s))))
        s += c["Slots"]["Step"]
    out.append("")
    return qm


def sd_for(c, target_mean):
    """Release-timing sd that gives this mean quality, and the resulting median quality."""
    g = Game(c)
    lo, hi = 0.01, 2.0
    for _ in range(30):
        sd = (lo + hi) / 2
        rng = random.Random(11)
        m = sum(g.sample_quality(rng, sd) for _ in range(40000)) / 40000
        if m > target_mean:
            lo = sd
        else:
            hi = sd
    rng = random.Random(12)
    qs = sorted(g.sample_quality(rng, sd) for _ in range(40000))
    return sd, qs[len(qs) // 2]


def calibrate(c):
    global TIMING_SD
    TIMING_SD = sd_for(c, TARGET_MEAN_QUALITY)[0]


def report(c, runs_n, hours, quick):
    out = ["# Throw a Ball for Dogs balance simulation\n",
           "Generated by `python3 tools/balance_sim.py --runs %d --hours %g`. Medians over %d runs.\n" %
           (runs_n, hours, runs_n)]
    qm = analytic(c, out)
    base = run_scenario(c, runs_n, hours, {"q_median": qm})

    out.append("## F2P baseline: milestones (median play time)\n")
    out.append("| Milestone | Target | Median | P10 run | P90 run | Reached in %gh |" % hours)
    out.append("|---|---|---|---|---|---|")
    targets = {"Park": 5 * 60, "Beach": 15 * 60, "Farm": 35 * 60, "Forest": 3600, "SnowyPeaks": 7200,
               "CityRooftops": 4 * 3600, "SpaceStation": 8 * 3600, "MythicMeadow": 15 * 3600}

    def row(label, key, target):
        xs = sorted(r.events.get(key, math.inf) for r in base)
        p = lambda k: None if xs[k] == math.inf else xs[k]  # noqa: E731
        out.append("| %s | %s | %s | %s | %s | %.0f%% |" % (label, target, fmt_t(p(len(xs) // 2)), fmt_t(p(len(xs) // 10)),
                                                          fmt_t(p(len(xs) * 9 // 10)), 100 * frac(base, key)))

    row("First training purchase", "buy:Training1", "< 2m")
    for z in c["Zones"][1:]:
        row("Reach %s (median throw lands there)" % z["Name"], "reach:" + z["Id"], fmt_t(targets[z["Id"]]))
    for z in c["Zones"][1:]:
        row("First throw lands in %s" % z["Name"], "land:" + z["Id"], "-")
    for t in ("Uncommon", "Rare", "Epic", "Legendary", "Mythic"):
        row("First %s caught" % t, "catch:" + t, "-")
    for v in c["VariantOrder"]:
        row("First %s variant caught" % v, "variant:" + v, "-")
    for b in c["Balls"][1:]:
        row("Buy %s" % b["Name"], "buy:Ball " + b["Id"], "-")
    out.append("")

    out.append("## F2P baseline: curve at checkpoints (medians)\n")
    out.append("| Play time | Income $/s | ThrowPower | Training lvl | Ball | Slots | Median-throw zone | Cash on hand |")
    out.append("|---|---|---|---|---|---|---|---|")
    for h in (5 / 60, 15 / 60, 0.5, 1, 2, 3, 5, 10, 15, 20, 30):
        if h > hours:
            continue
        ts = h * 3600
        rows = []
        for r in base:
            s = min(r.samples, key=lambda x: abs(x[0] - ts))
            rows.append(s)
        out.append("| %s | %s | %s | %d | %s | %d | %s | %s |" % (
            fmt_t(ts), fmt_n(med([x[1] for x in rows])), fmt_n(med([x[2] for x in rows])), med([x[5] for x in rows]),
            c["Balls"][int(med([x[6] for x in rows]))]["Id"], med([x[7] for x in rows]),
            c["Zones"][int(med([x[3] for x in rows]))]["Name"], fmt_n(med([x[4] for x in rows]))))
    out.append("")

    # payback / affordability of each purchase
    out.append("## Purchases: cost in minutes of income at the moment of purchase (median)\n")
    out.append("| Purchase | Median play time | Cost | Minutes of income it cost |")
    out.append("|---|---|---|---|")
    labels = []
    for r in base:
        for p in r.purchases:
            if p[1] not in labels:
                labels.append(p[1])
    for lab in labels:
        ps = [p for r in base for p in r.purchases if p[1] == lab]
        if len(ps) < len(base) * 0.5:
            continue
        out.append("| %s | %s | %s | %.1f |" % (lab, fmt_t(med([p[0] for p in ps])), fmt_n(med([p[2] for p in ps])),
                                                med([p[2] / max(p[3], 1e-9) / 60 for p in ps])))
    out.append("")

    # economy breakdown
    out.append("## Where the money came from / went (median share over %gh)\n" % hours)
    keys_e = list(base[0].earned)
    keys_s = list(base[0].spent)
    te = [sum(r.earned.values()) for r in base]
    ts_ = [sum(r.spent.values()) for r in base]
    out.append("Earned: " + ", ".join("%s %.1f%%" % (k, 100 * med([r.earned[k] / max(1, t) for r, t in zip(base, te)]))
                                      for k in keys_e))
    out.append("\nSpent: " + ", ".join("%s %.1f%%" % (k, 100 * med([r.spent[k] / max(1, t) for r, t in zip(base, ts_)]))
                                       for k in keys_s))
    out.append("\nCatches by tier (median): " + ", ".join("%s %d" % (t, med([r.catches[t] for r in base])) for t in c["Order"]))
    out.append("\nMisses by tier (median): " + ", ".join("%s %d" % (t, med([r.misses[t] for r in base])) for t in c["Order"]))
    out.append("\nBones after %gh: %d (all cosmetics cost %d)\n" % (hours, med([r.bones for r in base]),
                                                                  sum(c["CosmeticBones"])))

    if quick:
        return "\n".join(out)

    # scenarios
    out.append("## Scenarios vs F2P baseline (medians)\n")
    out.append("| Scenario | Income @3h | Income @10h | Zone @10h | Reach Farm | Reach Snowy | Reach City | Reach Space | Reach Mythic Meadow | First Legendary | Notes |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|")
    scen = [
        ("F2P baseline", {}, ""),
        ("No Throwing Machine (pull-ups only)", {"NoMachine": True}, "checks the machine matters"),
        ("Buys Lucky Biscuit when cheap", {"Boosts": ("LuckyBiscuit",)}, "cash boost"),
        ("Buys Sticky Ball when cheap", {"Boosts": ("StickyBall",)}, "cash boost"),
        ("Carries a Golden Whistle (Legendary+)", {"Items": ("GoldenWhistle",), "WhistleMin": 4}, "cash consumable"),
        ("Carries a Treat Pocket (EpicPlus mode)", {"Items": ("TreatPocket",)}, "cash consumable"),
        ("Casual: 30-min sessions", {"session_min": 30}, "same play hours, 2x the offline gaps"),
        ("Grinder: 3-h sessions", {"session_min": 180}, "fewer offline top-ups"),
        ("Weak timing (mean quality 0.60)", {"skill": 0.60}, ""),
        ("Skilled timing (mean quality 0.85)", {"skill": 0.85}, ""),
        ("Robux: 2x Cash pass", {"DoubleCash": True}, "gamepass"),
        ("Robux: Extra Slots pass", {"ExtraSlots": True}, "gamepass"),
        ("Robux: Fast Growth pass", {"FastGrowth": True}, "gamepass"),
        ("Robux: Lucky Paw pass", {"LuckyPaw": True}, "gamepass"),
        ("Robux: all passes", {"DoubleCash": True, "ExtraSlots": True, "FastGrowth": True, "LuckyPaw": True}, "whale"),
    ]
    n2 = max(10, runs_n // 3)
    h2 = min(hours, 20)
    for name, o, note in scen:
        o = dict(o, q_median=qm)
        if "skill" in o:
            o["sd"], o["q_median"] = sd_for(c, o["skill"])
        rs = base if name == "F2P baseline" else run_scenario(c, n2, h2, o, seed=3)

        def at(h, idx):
            vals = [min(r.samples, key=lambda x: abs(x[0] - h * 3600))[idx] for r in rs]
            return med(vals)
        out.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            name, fmt_n(at(3, 1)), fmt_n(at(min(10, hours), 1)),
            c["Zones"][int(at(min(10, hours), 3))]["Name"], fmt_t(ev_time(rs, "reach:Farm")),
            fmt_t(ev_time(rs, "reach:SnowyPeaks")), fmt_t(ev_time(rs, "reach:CityRooftops")),
            fmt_t(ev_time(rs, "reach:SpaceStation")),
            fmt_t(ev_time(rs, "reach:MythicMeadow")), fmt_t(ev_time(rs, "catch:Legendary")), note))
    out.append("\n(Scenario runs are capped at %gh of play; 'never' = not within that window.)\n" % h2)
    return "\n".join(out)


def main(argv):
    runs, hours, quick = 60, 30.0, False
    i = 1
    while i < len(argv):
        if argv[i] == "--runs":
            runs = int(argv[i + 1]); i += 1
        elif argv[i] == "--hours":
            hours = float(argv[i + 1]); i += 1
        elif argv[i] == "--quick":
            quick, runs = True, 12
        i += 1
    c = load_config()
    calibrate(c)
    assert len(c["Zones"]) == 9 and len(c["Balls"]) == 5 and len(c["Tiers"]) == 6, "config parse failed"
    print(report(c, runs, hours, quick))


if __name__ == "__main__":
    main(sys.argv)
