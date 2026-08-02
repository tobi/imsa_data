#!/usr/bin/env python3
"""Compute driver skill ratings using OpenSkill (Plackett-Luce).

Each green-flag wall-clock window is ONE multiplayer match: the full field is
ranked by pace and updated in a single Plackett-Luce step (not O(n^2) pairwise
duels). Every driver carries mu (skill) and sigma (uncertainty); the
conservative rating `ordinal = mu - 3*sigma` keeps small-sample drivers honest
until they've proven the pace, then the band tightens. (TrueSkill-like, but
MIT-licensed and patent-free.)

TWO POOLS are computed and emitted in the SAME csv:
  1. FULL-FIELD ("overall"): license-seeded priors (Bronze < Silver < Gold <
     Platinum). Every same-class car on track in a window is ranked together --
     raw pace vs the whole field. Columns skill_mu/skill_sigma/ordinal/elo.
  2. WITHIN-TIER ("peer"): same green windows, but a driver is ONLY ranked
     against same-license drivers circulating at that moment. Seeded flat (all
     start equal within their tier). Answers "how good am I FOR a Bronze?".
     Columns peer_mu/peer_sigma/peer_ordinal/peer_elo.

TIME-AWARE CONFIDENCE (sigma widening):
  Skill doesn't decay with a layoff, but our CERTAINTY does. Before an event,
  a returning driver's sigma is widened by the elapsed time since they last
  raced -- sigma' = min(sqrt(sigma^2 + (TAU_PER_YEAR*years)^2), prior). Because
  ordinal = mu - 3*sigma, a long gap drops the conservative rating until the
  next race re-confirms pace, then it tightens again. mu (the skill estimate)
  is left untouched -- we don't assume a returning driver got slower, only that
  we're less sure. Capped at the seed sigma, so a returnee is never treated as
  MORE unknown than a brand-new driver.

NORMALIZATION (relatable elo):
  `elo` and `peer_elo` are readable, 1500-centered transforms of the
  conservative ordinal, anchored on the ACTUAL field:
    elo      = 1500 + ELO_SCALE * (ordinal      - class_median_ordinal)
    peer_elo = 1500 + ELO_SCALE * (peer_ordinal - tier_median_peer_ordinal)
  So 1500 = a literal median driver in your class (overall) / median driver of
  your license (peer), computed from established drivers (>= MEDIAN_MIN_LAPS
  green laps). The same fixed class/tier anchor maps every historical event row,
  so an elo trajectory is comparable over time.

MATCH DEFINITION (both pools):
  Within each event keep green-flag (flags='GF'), non-pit, valid laps. Bucket
  every lap into a wall-clock window (BUCKET_SECONDS wide) by its mid-point
  session_time, so you are only ranked against cars actually circulating
  alongside you. Each driver contributes ONE representative lap per window =
  the median of their green laps in that window. The window's pace ranking is
  one OpenSkill match.

OUTPUT CSV:
  driver_id, driver_name, class, series_code, year, event, session_date,
  laps, cumulative_laps, license,
  skill_mu, skill_sigma, ordinal, elo,          # overall (full-field) pool
  peer_mu, peer_sigma, peer_ordinal, peer_elo   # within-tier (same license) pool

Usage:
  python compute_skill.py                 # CSV to stdout
  python compute_skill.py --summary       # also print leaderboards to stderr
  python compute_skill.py -m 50           # min green laps for summary
  python compute_skill.py --bucket 600    # window width seconds (default 600)
"""

# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "duckdb>=1.0",
#   "openskill>=6.0",
# ]
# ///

import argparse
import math
import os
import statistics
import sys
from datetime import datetime
from collections import defaultdict

import duckdb
from openskill.models import PlackettLuce

# --- Configuration -----------------------------------------------------------
BUCKET_SECONDS = 600          # wall-clock window width (10 min)
DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output", "imsa.duckdb")

# License-seeded starting mu for the OVERALL pool (OpenSkill default mu 25.0).
LICENSE_MU = {
    "Bronze": 22.0,
    "Silver": 25.0,
    "Gold": 28.0,
    "Platinum": 31.0,
}
DEFAULT_MU = 25.0
DEFAULT_SIGMA = 25.0 / 3.0    # OpenSkill default

# Time-aware confidence: sigma drift per YEAR of inactivity (mu-units). Added in
# quadrature to the standing sigma, capped at the seed prior. ~3.0 means a
# ~3-year layoff fully resets a driver's certainty to "brand new".
TAU_PER_YEAR = 3.0

# Normalization: readable elo = ELO_CENTER + ELO_SCALE*(ordinal - field_median).
ELO_SCALE = 25.0
ELO_CENTER = 1500.0
# Drivers need this many green laps to count toward the median anchor (keeps
# one-off entries from dragging the center). Falls back to all if too few.
MEDIAN_MIN_LAPS = 100
MEDIAN_MIN_DRIVERS = 5

MODEL = PlackettLuce(mu=DEFAULT_MU, sigma=DEFAULT_SIGMA)


def parse_date(s):
    """Best-effort parse of a session_date string to a datetime; None on failure."""
    if not s:
        return None
    s = str(s)
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d"):
        try:
            return datetime.strptime(s[:len(fmt) + 2].strip(), fmt)
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def widen_sigma(rating, years):
    """Return a rating with sigma widened for `years` of inactivity (mu kept)."""
    if years is None or years <= 0:
        return rating
    extra = TAU_PER_YEAR * years
    new_sigma = min(math.sqrt(rating.sigma ** 2 + extra ** 2), DEFAULT_SIGMA)
    if new_sigma <= rating.sigma:
        return rating
    return MODEL.rating(mu=rating.mu, sigma=new_sigma, name=rating.name)


def load_laps(db_path: str):
    con = duckdb.connect(db_path, read_only=True)
    rows = con.execute(
        """
        SELECT
          driver_id,
          driver_name,
          COALESCE(class_category, class) AS class,
          series_code,
          year,
          event,
          lap,
          CAST(lap_time AS DOUBLE)     AS lap_time,
          CAST(session_time AS DOUBLE) AS session_time,
          flags,
          CAST(pit_time AS DOUBLE)     AS pit_time,
          license,
          start_date AS session_date
        FROM laps
        WHERE (session = 'race' OR session LIKE 'race-hour-%')
          AND lap_time IS NOT NULL
          AND driver_id IS NOT NULL
        ORDER BY start_date, series_code, year, event, session_time
        """
    ).fetchall()
    con.close()
    cols = ["driver_id", "driver_name", "class", "series_code", "year", "event",
            "lap", "lap_time", "session_time", "flags", "pit_time", "license",
            "session_date"]
    return [dict(zip(cols, r)) for r in rows]


def filter_green(event_laps):
    """Keep clean green racing laps. Fall back to all valid laps when an event
    carries no flag data at all (older imports)."""
    has_flags = any(l["flags"] for l in event_laps)
    out = []
    for l in event_laps:
        if l["lap_time"] is None or l["lap_time"] <= 0:
            continue
        if l["pit_time"] is not None:          # drop in/out (pit) laps
            continue
        if has_flags and l["flags"] != "GF":   # green only when flags exist
            continue
        out.append(l)
    return out


def build_windows(green, bucket):
    """Bucket green laps into wall-clock windows -> {window: [laps]}."""
    windows = defaultdict(list)
    for l in green:
        st = l["session_time"]
        mid = (st - l["lap_time"] / 2.0) if st is not None else (l["lap"] * 100.0)
        windows[int(mid // bucket)].append(l)
    return windows


def rate_window(window_laps, ratings, restrict_ids=None):
    """Run one OpenSkill match for a wall-clock window. Each driver represented
    by the median of their green laps. `restrict_ids` (a set) limits the match
    to a subset (used for the within-tier pool). Mutates `ratings` in place.
    Returns True if a match was run."""
    by_driver = defaultdict(list)
    for l in window_laps:
        did = l["driver_id"]
        if restrict_ids is not None and did not in restrict_ids:
            continue
        by_driver[did].append(l["lap_time"])
    if len(by_driver) < 2:
        return False
    reps = [(did, statistics.median(times)) for did, times in by_driver.items()]
    reps.sort(key=lambda x: x[1])              # faster = better
    teams = [[ratings[did]] for did, _ in reps]
    ranks = list(range(len(reps)))             # 0 = best
    updated = MODEL.rate(teams, ranks=ranks)
    for (did, _), grp in zip(reps, updated):
        ratings[did] = grp[0]
    return True


def compute_pool(class_laps, bucket, seed_mu_fn, peer=False, licenses=None):
    """Process all events for one class chronologically and return
    {driver_id: {event_key: (mu, sigma, ordinal)}} plus final ratings and
    cumulative green-lap counts.

    seed_mu_fn(driver_id) -> starting mu for a new driver.
    peer=True runs SEPARATE matches per license tier (within-tier pool).

    Before each event a returning driver's sigma is widened for the elapsed
    time since they last raced (time-aware confidence; mu untouched).
    """
    ratings = {}
    green_laps = defaultdict(int)
    last_seen = {}                # driver_id -> datetime of last event raced
    history = defaultdict(dict)   # driver_id -> {event_key: (mu, sigma, ord)}

    events = defaultdict(list)
    for l in class_laps:
        events[(l["series_code"], l["year"], l["event"])].append(l)
    sorted_events = sorted(events.items(),
                           key=lambda kv: kv[1][0]["session_date"] or "1970-01-01")

    for ekey, event_laps in sorted_events:
        green = filter_green(event_laps)
        if not green:
            continue

        event_date = parse_date(event_laps[0]["session_date"])
        participants = {l["driver_id"] for l in green}

        for did in participants:
            if did not in ratings:
                ratings[did] = MODEL.rating(mu=seed_mu_fn(did), sigma=DEFAULT_SIGMA, name=did)
            elif event_date is not None and last_seen.get(did) is not None:
                years = (event_date - last_seen[did]).days / 365.25
                ratings[did] = widen_sigma(ratings[did], years)

        windows = build_windows(green, bucket)
        for w in sorted(windows):
            wl = windows[w]
            if peer:
                # one match per license tier present in this window
                tiers = set(licenses.get(l["driver_id"]) for l in wl)
                for tier in tiers:
                    ids = {l["driver_id"] for l in wl if licenses.get(l["driver_id"]) == tier}
                    rate_window(wl, ratings, restrict_ids=ids)
            else:
                rate_window(wl, ratings)

        event_green = defaultdict(int)
        for l in green:
            event_green[l["driver_id"]] += 1
        for did, cnt in event_green.items():
            green_laps[did] += cnt
            r = ratings[did]
            history[did][ekey] = (r.mu, r.sigma, r.ordinal())
            if event_date is not None:
                last_seen[did] = event_date

    return history, ratings, green_laps


def field_median(final_ratings, green_laps, key=lambda r: r.ordinal()):
    """Median conservative rating over ESTABLISHED drivers (>= MEDIAN_MIN_LAPS
    green laps), falling back to all when too few qualify. Anchors the elo
    scale on a real, representative driver rather than the abstract seed."""
    established = [key(r) for did, r in final_ratings.items()
                  if green_laps.get(did, 0) >= MEDIAN_MIN_LAPS]
    if len(established) < MEDIAN_MIN_DRIVERS:
        established = [key(r) for r in final_ratings.values()]
    if not established:
        return 0.0
    return statistics.median(established)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", action="store_true", help="print leaderboards to stderr")
    ap.add_argument("-m", "--min-laps", type=int, default=0, help="min green laps for summary")
    ap.add_argument("--bucket", type=int, default=BUCKET_SECONDS, help="window width seconds")
    args = ap.parse_args()
    bucket = float(args.bucket)

    print(f"Loading lap data from {DB_PATH}...", file=sys.stderr)
    all_laps = load_laps(DB_PATH)
    print(f"Loaded {len(all_laps)} laps", file=sys.stderr)

    laps_by_class = defaultdict(list)
    for l in all_laps:
        laps_by_class[l["class"]].append(l)

    out_rows = []

    for klass, class_laps in laps_by_class.items():
        print(f"Processing {klass}: {len(class_laps)} laps", file=sys.stderr)

        # Names + licenses (first seen)
        names, licenses = {}, {}
        for l in class_laps:
            names[l["driver_id"]] = l["driver_name"]
            if l["license"] and l["driver_id"] not in licenses:
                licenses[l["driver_id"]] = l["license"]

        # Pool 1: overall, license-seeded
        overall_hist, overall_final, green_laps = compute_pool(
            class_laps, bucket,
            seed_mu_fn=lambda did: LICENSE_MU.get(licenses.get(did), DEFAULT_MU),
        )
        # Pool 2: within-tier, flat seed
        peer_hist, peer_final, _ = compute_pool(
            class_laps, bucket,
            seed_mu_fn=lambda did: DEFAULT_MU,
            peer=True, licenses=licenses,
        )

        # Normalization anchors (computed from final, established drivers).
        # Overall: one class-wide median. Peer: per-license-tier median so
        # peer_elo 1500 = median driver OF THAT LICENSE.
        overall_median = field_median(overall_final, green_laps)
        tier_members = defaultdict(dict)
        for did, r in peer_final.items():
            tier_members[licenses.get(did, "")][did] = r
        peer_median = {
            tier: field_median(members, green_laps)
            for tier, members in tier_members.items()
        }

        def to_elo(ordinal, median):
            return ELO_CENTER + ELO_SCALE * (ordinal - median)

        # Re-walk events to emit ordered history with cumulative laps.
        events = defaultdict(list)
        for l in class_laps:
            events[(l["series_code"], l["year"], l["event"])].append(l)
        sorted_events = sorted(events.items(),
                               key=lambda kv: kv[1][0]["session_date"] or "1970-01-01")

        cum = defaultdict(int)
        for ekey, event_laps in sorted_events:
            series, year, event = ekey
            session_date = event_laps[0]["session_date"]
            green = filter_green(event_laps)
            if not green:
                continue
            event_green = defaultdict(int)
            for l in green:
                event_green[l["driver_id"]] += 1
            for did in event_green:
                if ekey not in overall_hist.get(did, {}):
                    continue
                mu, sigma, ordn = overall_hist[did][ekey]
                default_ord = MODEL.rating().ordinal()
                pmu, psig, pord = peer_hist.get(did, {}).get(
                    ekey, (DEFAULT_MU, DEFAULT_SIGMA, default_ord))
                cum[did] += event_green[did]
                lic = licenses.get(did, "")
                out_rows.append({
                    "driver_id": did,
                    "driver_name": names[did],
                    "class": klass,
                    "series_code": series,
                    "year": year,
                    "event": event,
                    "session_date": session_date,
                    "laps": event_green[did],
                    "cumulative_laps": cum[did],
                    "license": lic,
                    "skill_mu": round(mu, 4),
                    "skill_sigma": round(sigma, 4),
                    "ordinal": round(ordn, 4),
                    "elo": round(to_elo(ordn, overall_median)),
                    "peer_mu": round(pmu, 4),
                    "peer_sigma": round(psig, 4),
                    "peer_ordinal": round(pord, 4),
                    "peer_elo": round(to_elo(pord, peer_median.get(lic, 0.0))),
                })

        if args.summary:
            qualified = [(did, overall_final[did]) for did in overall_final
                         if green_laps.get(did, 0) >= args.min_laps]
            if not qualified:
                continue
            print(f"\n{klass} OVERALL ({len(qualified)} drivers, {args.min_laps}+ green laps, "
                  f"median ord={overall_median:.2f} -> elo 1500):", file=sys.stderr)
            print("-" * 76, file=sys.stderr)
            for i, (did, r) in enumerate(sorted(qualified, key=lambda kv: kv[1].ordinal(), reverse=True)[:15], 1):
                print(f"{i:3d}. {names.get(did, did):<25} ord={r.ordinal():6.2f}  "
                      f"sig={r.sigma:4.2f}  elo={round(to_elo(r.ordinal(), overall_median)):4d}  "
                      f"{green_laps.get(did,0):4d} laps  [{licenses.get(did,'-')}]", file=sys.stderr)
            # within-tier leaderboard for Bronze
            br = [(did, peer_final[did]) for did in peer_final
                  if licenses.get(did) == "Bronze" and green_laps.get(did, 0) >= args.min_laps]
            if br:
                bm = peer_median.get("Bronze", 0.0)
                print(f"\n{klass} WITHIN-BRONZE peer pool ({len(br)} drivers, "
                      f"median ord={bm:.2f} -> peer_elo 1500):", file=sys.stderr)
                print("-" * 76, file=sys.stderr)
                for i, (did, r) in enumerate(sorted(br, key=lambda kv: kv[1].ordinal(), reverse=True)[:15], 1):
                    print(f"{i:3d}. {names.get(did, did):<25} peer_ord={r.ordinal():6.2f}  "
                          f"sig={r.sigma:4.2f}  peer_elo={round(to_elo(r.ordinal(), bm)):4d}  "
                          f"{green_laps.get(did,0):4d} laps", file=sys.stderr)

    header = ["driver_id", "driver_name", "class", "series_code", "year", "event",
              "session_date", "laps", "cumulative_laps", "license",
              "skill_mu", "skill_sigma", "ordinal", "elo",
              "peer_mu", "peer_sigma", "peer_ordinal", "peer_elo"]
    print(",".join(header))
    out_rows.sort(key=lambda r: (str(r["session_date"] or ""), r["class"], r["driver_id"]))
    for r in out_rows:
        print(",".join(str(r[c]) for c in header))

    print(f"\nWrote {len(out_rows)} rows", file=sys.stderr)


if __name__ == "__main__":
    main()
