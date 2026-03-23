# Estimating Tire Age from Lap Data

## Overview

IMSA timing data does not include tire information — no tire compound, no tire
set number, no pit stop service details. But tire state has a massive influence
on lap times, and estimating it unlocks degradation analysis, strategy insight,
and fairer driver comparisons.

This document describes what we know, what we measured from the data, and the
heuristics used to produce the `est_tire_age` column in the `laps` table.


## The Physics: What New Tires Look Like

Fresh tires follow a distinctive performance curve:

1. **Outlap (stint_lap 0):** Very slow. Tires are cold, car is leaving pit lane.
   Not useful for tire detection since it also includes pit traversal time.

2. **Warmup (green-flag laps 0–2):** Notably slower than peak. Rubber is coming
   up to temperature, driver is building confidence. The first green-flag lap
   is the strongest warmup signal.

3. **Peak (green-flag laps 3–5):** Optimal grip window. Tires are at temperature
   and the rubber surface is fresh. This is where the fastest laps happen.

4. **Plateau / slow degradation (laps 6–18ish):** Performance drifts slightly
   off peak as the tread surface wears and thermal degradation builds.

5. **Fall-off (lap 20+):** Measurable degradation, especially on high-energy
   circuits.

**Used tires** (carried over from the previous stint) skip steps 1–3. The driver
comes out of the pits and is at or near running pace within a lap — there's no
ramp-up because the rubber is already broken in. The tires may be slightly
cooled from sitting in pit lane, but they warm up much faster than a fresh set.


## Key Insight: Green-Flag Laps Are the Metric

Full-course yellows (FCY) barely wear tires. Cars circulate at reduced speed
with minimal lateral and longitudinal load. A car that spent 10 laps behind
the safety car has essentially the same tire state as when the yellow started.

Similarly, a "splash and go" pit stop under caution — where the team takes a
few gallons of fuel and sends the car back out on the same tires — does not
reset tire age.

**Tire age should be counted in green-flag laps, not total laps.**


## What the Data Shows

### Warmup Curve by Class

Median lap time vs stint median, by green-flag lap number (stints ≥ 15 GF laps):

| GF Lap | LMP2   | GTP    | GTD    | Hypercar |
|--------|--------|--------|--------|----------|
| 0      | +1.09s | +2.19s | +1.75s | +0.56s   |
| 1      | +0.07  | +0.57  | +0.39  | −0.34    |
| 2      | −0.29  | −0.20  | −0.07  | −0.50    |
| 3      | −0.45  | −0.29  | −0.25  | −0.48    |
| 4      | −0.53  | −0.41  | −0.33  | −0.52    |
| 5      | −0.53  | −0.46  | −0.31  | −0.44    |
| 10     | −0.18  | +0.06  | −0.15  | 0.00     |
| 15     | −0.17  | −0.17  | −0.03  | −0.13    |
| 20     | +0.30  | +0.02  | +0.01  | −0.13    |
| 25     | +0.11  | −0.02  | +0.06  | +0.03    |
| 30     | +0.10  | +0.10  | +0.07  | +0.18    |
| 35     | +0.19  | +0.07  | +0.01  | +0.15    |

Key observations:

- **All classes** show a clear warmup in the first 2 green-flag laps.
- **Peak grip** arrives at green-flag laps 4–5 across every class.
- **LMP2** has the most pronounced degradation curve: peak at −0.53s, crossing
  zero around lap 18, and +0.2–0.3s by lap 30+.
- **GTP** has a wider peak window (laps 4–8) and flatter late-stint behavior.
- **Hypercar** shows the least warmup on lap 0 (+0.56s vs +1.75 for GTD).
  This may reflect WEC tire blanket rules or different rubber compounds.
- **GTD** has substantial warmup (+1.75s on lap 0) but very flat long-run
  degradation, barely +0.1s by lap 35.

### Typical Stint Lengths (Green-Flag Laps)

| Class    | Median | P90  | Avg Total |
|----------|--------|------|-----------|
| LMP2     | 33     | 57   | 40        |
| LMP3     | 29     | 59   | 40        |
| GTP      | 49     | 88   | 57        |
| Hypercar | 45     | 75   | 52        |
| GTD      | 39     | 70   | 47        |
| GTDPRO   | 46     | 83   | 54        |
| LMGT3    | 32     | 61   | 39        |
| DPi      | 45     | 73   | 53        |

GTP and DPi stints tend to be the longest. The gap between green-flag laps
and total laps (typically 5–10) shows how much time is spent under yellows.

### Tire Changes Are the Norm

Looking at same-driver pit stops during races (where we can compare the same
driver's pace before and after), the majority result in faster post-pit pace
— strong evidence of a tire change:

| Class    | N pits | Median pace Δ | % faster after pit |
|----------|--------|---------------|--------------------|
| GTD      | 1,735  | −4.4s         | 91%                |
| GTDPRO   | 954    | −7.7s         | 91%                |
| GTP      | 1,131  | −3.1s         | 64%                |
| LMP2     | 5,408  | −1.5s         | 67%                |
| Hypercar | 1,635  | −1.3s         | 72%                |
| LMP3     | 1,285  | −2.8s         | 70%                |

(Pace Δ = avg of laps 2–4 after pit minus avg of last 4 laps before pit.
Negative = faster = new tires likely.)

GT classes show the strongest signal (91% of pits make you faster). Prototype
classes have more noise because their lap times are shorter and fuel load
effects are proportionally larger, but the pattern is clear.

### Pre-Pit Green-Flag Laps Predict Tire Changes

The number of green-flag laps before a pit stop strongly correlates with
whether new tires were fitted:

| Pre-pit GF laps | LMP2 % faster | GTD % faster | Hypercar % faster |
|------------------|---------------|--------------|-------------------|
| < 5 (splash)     | 72%           | 86%          | 92%               |
| 5–14 (short)     | 52%           | 78%          | 56%               |
| 15–24 (medium)   | 61%           | 83%          | 57%               |
| 25–34 (full)     | 68%           | 96%          | 71%               |
| 35+ (long)       | 82%           | 95%          | 80%               |

For LMP2 and Hypercar, short stints (5–14 GF laps) are essentially coin-flip
territory — roughly half of those pits were likely fuel-only. Full stints
(25+ GF laps) strongly indicate a tire change.

The "< 5 GF laps" category looks high but is misleading: those are often
yellow-to-green transitions where the pace jump is from the caution ending,
not from new rubber.


## Practical Tire Scenarios

### Race

- **Stint 1 (race start):** Always new tires. Formation lap provides some
  warmup, so the first green-flag lap is already partially warm.
- **Full pit stop after a normal stint:** New tires in the vast majority of
  cases. Teams almost always change rubber when they're already stopped for
  fuel and a driver change.
- **Splash under yellow:** Often same tires. The car pits for a quick fuel
  top-off during a caution and returns immediately. No tire change — no time
  advantage since the field is neutralized.
- **Short stint after a restart, then another yellow:** Probably same tires.
  Only a few green-flag laps were run, and the tires still have life.
- **Double/triple stinting:** Not a hard 2-stint cap. It's about total
  green-flag laps and time on the rubber. At most tracks ~90 minutes of
  green-flag running is the upper end for LMP2 tires. Le Mans, with its long
  straights and lower sustained lateral load, sometimes allows triple stints.
  You can tell because the car's pace will be noticeably worse in the
  third stint versus fresh-tire competitors.

#### End-of-Race Strategy Shift

Teams manage their tire allocation across the race. In longer endurance races
(Sebring 12h, Daytona 24h), tires are **double-stinted in the first half**
(same set across two fuel stints) and then **single-stinted toward the end**
as positions are being decided and every tenth matters. For Sebring, expect
essentially 100% single-stint tires in the last ~2 hours.

This creates a predictable pattern in the data: tire change frequency
increases as the race progresses. Early race segments between same-driver pits
are more likely to be fuel-only stops; late race segments are almost always
tire changes. The algorithm does not yet exploit this prior, but it could be
used to adjust confidence or thresholds based on race progress.

### Practice

Practice sessions have more varied tire usage:

- **New tire run:** Install, outlap, build for 2–3 laps, run at pace for
  5–10 laps, pit. Shows clear warmup curve.
- **Scrub tires:** Lightly used tires (one or two laps of running from a
  previous session). Behave somewhere between new and fully used — less
  dramatic warmup than a fresh set but faster than worn rubber.
- **Qualifying simulation:** Low fuel, new or scrub tires, short stint of
  3–7 laps. The giveaway is a slow outlap followed by a sudden peak that's
  among the driver's best times across all practice sessions for the event.
  Very distinctive pattern: the peak laps stand out against the event's pace
  distribution.
- **Race simulation:** Long run on a single set, deliberately checking
  degradation. Looks like a race stint.

### Qualifying

New tires for all meaningful laps. Qualifying stints are short (3–7 laps)
with clear warm-up → peak → done pattern.


## Detection Algorithm

The `est_tire_age` column estimates how many green-flag laps have been
completed on the current set of tires. The algorithm works per
`(session_id, car)` and processes pit stops within each stint.

### Step 1: Identify Tire Change Points

A tire change is detected at every pit stop (any lap with `pit_time IS NOT
NULL`) unless the evidence suggests otherwise. Evidence against a tire change:

1. **Pace continuity:** The first clean laps after the pit are no faster
   (or slower) than the last clean laps before the pit. Specifically, if
   the average of green-flag laps 2–4 after the pit is not measurably faster
   than the average of the last 4 green-flag laps before the pit, it's
   likely same tires.

2. **Short pre-pit green run:** Fewer than ~10 green-flag laps before the
   pit, combined with no pace improvement, suggests a fuel-only stop.

3. **No warmup signature:** The lap immediately after the pit is close in
   pace to subsequent laps (warmup gap < 0.3s), while new tires typically
   show 0.5–2.0s of warmup on the first green-flag lap.

### Step 2: Count Green-Flag Tire Age

Starting from each detected tire change point (or the start of the session),
count forward through green-flag laps only:

- `est_tire_age = 0` on the outlap or first lap of fresh tires
- Increments by 1 for each subsequent green-flag lap
- Does NOT increment during FCY laps (flag ≠ 'GF')
- Resets to 0 at the next detected tire change

### Step 3: Carry Forward Through Same Tires

If a pit stop is classified as "same tires" (fuel only), the tire age counter
does not reset. It continues from whatever it was before the pit stop.

### Confidence

This is an estimation. The algorithm is most confident when:
- The same driver stays in the car (no driver-change confound)
- There are enough green-flag laps before and after the pit to measure pace
- Track conditions are stable (no rain transition, no sudden temperature change)

It is least confident when:
- A driver change happens simultaneously (pace change reflects driver skill
  difference, not tire state)
- The stint before the pit was entirely under yellow
- Track conditions changed (grip level shifted for everyone)

For driver-change pit stops, the algorithm falls back to: assume new tires if
it was a full-length stint, assume same tires if the pre-pit green run was
very short (< 5 GF laps) and pitted under yellow.


## Column Reference

| Column | Type | Description |
|--------|------|-------------|
| `est_tire_age` | INTEGER | Estimated green-flag laps completed on the current tire set. 0 = fresh/outlap. **Race sessions only** — NULL for practice, qualifying, warmup, and test sessions (see below). |

### Why Practice Sessions Are NULL

Teams receive a limited tire allocation for practice (e.g., 6 sets at Sebring)
and reuse them heavily across all practice stints. A driver change or pit stop
in practice almost never means new tires — the crew grabs whatever used set is
in the stack. The true tire age is unknowable from timing data alone.

The one exception is **qualifying simulations** — short stints on fresh or scrub
tires with a distinctive pattern (slow outlap → peak laps among the driver's
event-best times). Detecting these is a future enhancement.


## Limitations

- **No ground truth.** We never truly know when tires were changed. This is
  a best-effort estimate derived from pace patterns.
- **Driver changes confound pace comparison.** A slower driver on fresh tires
  may be slower than a faster driver on used tires. The algorithm accounts
  for this by being more conservative when a driver change occurs.
- **Fuel load affects pace.** A car is ~1–2s faster at the end of a stint
  (light fuel) vs the start (heavy fuel). This works *against* tire detection
  since new tires + heavy fuel can look similar to old tires + light fuel.
- **Track evolution.** The track gets faster through a session as more rubber
  is laid down. Late stints may appear "faster on old tires" when it's
  actually the track that improved.
- **Rain transitions.** The algorithm does not attempt tire compound
  detection (slick vs wet). If it rains mid-stint, all bets are off.
- **BoP adjustments.** GTP/Hypercar classes have Balance of Performance that
  can change between events or even sessions. This affects absolute pace
  but not the within-stint patterns we rely on.
