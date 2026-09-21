# Driver duplicate-identity review — 2026-08

Curation of the 67 duplicate-identity candidate pairs left after the alias
resolution fix. A candidate pair is two `drivers_v` ids sharing a last token
with `jaro_winkler_similarity(a.driver_id, b.driver_id) >= 0.80`.

| verdict | pairs | outcome |
|---|---|---|
| AUTO-MERGE | 27 | alias added |
| NEEDS-DECISION | 20 | 19 merged after review, 1 kept separate (`jon miller` / `jonathan miller`) |
| REJECT | 20 | two different people; never merge |

Net: 46 merged, 21 kept separate; distinct driver ids 1114 → 1068. Canonical
id = the id with more career laps.

## Method

- **Co-occurrence guard.** Two ids in the same `session_id` are different
  people — one person cannot drive two stints at once. 26 of 67 pairs co-occur.
- **Same-car exception.** Co-occurrence in *different* cars is airtight; in the
  *same* car it can also be a source-data name split. Discriminator: a real
  driver change needs a pit stop, so a hand-over between the two ids on
  consecutive laps with no `pit_time` on the incoming lap is impossible.

  ```sql
  SELECT session_id, car, lap, driver_id,
         lead(driver_id) OVER w AS next_driver,
         lead(pit_time)  OVER w AS next_pit
  FROM (SELECT DISTINCT session_id, car, lap, driver_id, pit_time FROM laps)
  WINDOW w AS (PARTITION BY session_id, car ORDER BY lap);
  -- next_pit IS NULL on a hand-over = impossible
  ```

  Perfectly bimodal: 5 same-car pairs have zero impossible hand-overs
  (relatives/team-mates → REJECT), 14 have many (→ the artifact below).
- **Country and licence are not evidence.** Both vary within one driver
  (`nico muller` is SUI and CHE; `finn gehrsitz` GER and DEU; `benji goethe`
  MCO/Silver and DEU/Gold in the same car and year). Country counts only when
  it names two genuinely different countries, never alone.
- **Positive evidence for a merge:** nickname / middle-name / hyphen /
  transliteration pattern, plus one of: overlapping team, strictly
  complementary seasons, or both spellings on the same car at the same event.

## The 2026 Daytona split-name artifact (14 pairs)

IMSA 2026 Daytona practice emits two spellings of one driver, alternating lap
by lap through a single run with no pit stops — car #6, session 703:

```
lap  driver_name        lap_time  pit_time
  9  Matt Campbell        101.711  NULL
 10  Matthew Campbell      98.168  NULL
 11  Matthew Campbell      98.607  NULL
 12  Matt Campbell         98.260  NULL
```

Together the two spellings partition laps 8-43 exactly: one driver, two feed
spellings. Same shape for Palou, Hesse, Tandy, Keating, Blomqvist, Dillmann,
Cassidy, Sargent, Esterson, Barnicoat, Green, Gamble, Rockenfeller. These
co-occur in the same car, so the guard flags them; the honest reading is
*same person*. Filed NEEDS-DECISION rather than auto-merged because it
overrides the pass's own rule; **decision: merge all 14 via aliases**
(alternative considered: normalise the 2026 Daytona names at import).
`dan harper` / `daniel harper` is the same artifact and was auto-merged only
because its two spellings never share a session.

## Judgement calls (decided)

| pair | decision | basis |
|---|---|---|
| `benjamin goethe` ↔ `benji goethe` | merge | standard diminutive; both Garage 59; complementary seasons |
| `abdulla al-khelaifi` ↔ `abdulla ali al-khelaifi` | merge | middle-name superset; same team **and car number** (#62) in two championships |
| `nico muller` ↔ `nicolas muller` | merge | complementary seasons, same country/licence, nickname-shaped |
| `ed jones` ↔ `edward jones` | merge | nickname, same licence, no co-occurrence; 2022 IMSA + WEC compatible |
| `eddie cheever` ↔ `edward cheever` | merge | nickname, same country/licence, no co-occurrence |
| `jon miller` ↔ `jonathan miller` | **keep separate** | different championships, no team link, common surname |

---

## AUTO-MERGE — applied (27 pairs)

Each of these is now one line in `driver_aliases.json`. Canonical id = the id
with more career laps, as measured before the merge; the *displayed* name is
chosen independently by `010-event-drivers.sql`, which prefers the shorter,
proper-cased spelling — so merging into `jonathan bennett` still displays
"Jon Bennett".

### `fin gehrsitz` ↔ `finn gehrsitz`

**AUTO-MERGE** → canonical `finn gehrsitz` (874 laps vs 155).

Spelling variant of one German first name. Same surname, both Bronze at some point, no co-occurrence, no shared event. Countries read DEU/GER — the *same* country under two codes; `finn gehrsitz` alone carries both codes across his own laps, so the field is not evidence.

| evidence | A | B |
|---|---|---|
| driver_id | `fin gehrsitz` | `finn gehrsitz` |
| display name | Fin Gehrsitz | Finn Gehrsitz |
| career laps | 155 | 874 |
| events | 2 | 16 |
| years active | 2022 | 2021,2022,2025,2026 |
| series | alms | elms/wec |
| licence(s) | Bronze | Bronze,Silver |
| country | DEU | GER |
| teams | Herberth Motorsport | Akkodis ASP Team; Eurointernational; Garage 59; United Autosports |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9821 |

### `jean baptiste simmenauer` ↔ `jean-baptiste simmenauer`

**AUTO-MERGE** → canonical `jean-baptiste simmenauer` (580 laps vs 46).

Pure hyphenation variant. Same country, same team (Duqueine), same seasons, never co-occurring. This is the pair DI0 deliberately left for curation when it made hyphen folding match-key-only.

| evidence | A | B |
|---|---|---|
| driver_id | `jean baptiste simmenauer` | `jean-baptiste simmenauer` |
| display name | Jean Baptiste Simmenauer | Jean-Baptiste SIMMENAUER |
| career laps | 46 | 580 |
| events | 1 | 13 |
| years active | 2024,2025 | 2024,2025 |
| series | alms | elms/wec |
| licence(s) | Gold,Silver | Gold |
| country | FRA | FRA |
| teams | Duqueine Team | Duqueine Team; Inter Europol Competition |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9486 |

### `tim creswick` ↔ `timothy creswick`

**AUTO-MERGE** → canonical `timothy creswick` (283 laps vs 239).

Nickname; same country, same licence, **same team** (Inter Europol Competition), no co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `tim creswick` | `timothy creswick` |
| display name | Tim Creswick | Timothy CRESWICK |
| career laps | 239 | 283 |
| events | 3 | 6 |
| years active | 2023,2025 | 2025 |
| series | alms | elms |
| licence(s) | Bronze | Bronze |
| country | GBR | GBR |
| teams | Inter Europol Competition | Inter Europol Competition |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9417 |

### `thomas fleming` ↔ `tom fleming`

**AUTO-MERGE** → canonical `thomas fleming` (234 laps vs 129).

tom/thomas nickname; same country and licence; seasons complementary (2024-25 ELMS vs 2026 WEC); no co-occurrence, no shared event.

| evidence | A | B |
|---|---|---|
| driver_id | `thomas fleming` | `tom fleming` |
| display name | Thomas Fleming | Tom FLEMING |
| career laps | 234 | 129 |
| events | 3 | 5 |
| years active | 2026 | 2024,2025 |
| series | wec | elms |
| licence(s) | Silver | Silver |
| country | GBR | GBR |
| teams | Garage 59 | GR Racing |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9357 |

### `thomas van rompuy` ↔ `tom van rompuy`

**AUTO-MERGE** → canonical `tom van rompuy` (1152 laps vs 670).

tom/thomas nickname; same country; **overlapping team** (DKR Engineering); no co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `thomas van rompuy` | `tom van rompuy` |
| display name | Thomas van Rompuy | Tom VAN ROMPUY |
| career laps | 670 | 1152 |
| events | 8 | 23 |
| years active | 2023,2026 | 2022,2023,2024,2025 |
| series | alms/wec | elms/wec |
| licence(s) | Bronze | Bronze,Silver |
| country | BEL | BEL |
| teams | Akkodis ASP Team; DKR Engineering; Racing Team Turkey | DKR Engineering; TF Sport |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9256 |

### `dustin blattner` ↔ `dustin scott blattner`

**AUTO-MERGE** → canonical `dustin scott blattner` (514 laps vs 90).

Middle-name superset; same country, same licence, **same team** (Kessel Racing); no co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `dustin blattner` | `dustin scott blattner` |
| display name | Dustin Blattner | Dustin Scott Blattner |
| career laps | 90 | 514 |
| events | 1 | 6 |
| years active | 2026 | 2025,2026 |
| series | wec | alms |
| licence(s) | Bronze | Bronze |
| country | USA | USA |
| teams | Kessel Racing | Kessel Racing |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9162 |

### `ben tuck` ↔ `benjamin tuck`

**AUTO-MERGE** → canonical `ben tuck` (992 laps vs 549).

ben/benjamin nickname; same country and licence; **two overlapping teams** (Kessel Racing, Proton Competition); no co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `ben tuck` | `benjamin tuck` |
| display name | Ben Tuck | Benjamin Tuck |
| career laps | 992 | 549 |
| events | 20 | 9 |
| years active | 2024,2025 | 2024,2025,2026 |
| series | elms/imsa/wec | alms/wec |
| licence(s) | Silver | Silver |
| country | GBR | GBR |
| teams | Conquest Racing; JMW Motorsport; Kessel Racing; Proton Competition | Kessel Racing; Proton Competition; TF Sport |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9103 |

### `guilherme de oliveira` ↔ `guilherme moura de oliveira`

**AUTO-MERGE** → canonical `guilherme de oliveira` (400 laps vs 122).

Middle-name superset; same country and licence; **overlapping team** (Inter Europol Competition); no co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `guilherme de oliveira` | `guilherme moura de oliveira` |
| display name | Guilherme de Oliveira | Guilherme Moura de Oliveira |
| career laps | 400 | 122 |
| events | 11 | 2 |
| years active | 2021,2022,2023,2024 | 2022 |
| series | elms/imsa | alms |
| licence(s) | Silver | Silver |
| country | PRT | PRT |
| teams | DKR Engineering; Inter Europol Competition; Jr III Racing; MRS GT-Racing; Racing Experience | Inter Europol Competition |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9079 |

### `manny franco` ↔ `manuel franco`

**AUTO-MERGE** → canonical `manny franco` (1383 laps vs 158).

manny/manuel nickname; same country and licence; no co-occurrence, no shared event; the 2025 Asian LMS calendar (Jan-Feb) does not conflict with an IMSA season.

| evidence | A | B |
|---|---|---|
| driver_id | `manny franco` | `manuel franco` |
| display name | Manny Franco | Manuel Franco |
| career laps | 1383 | 158 |
| events | 22 | 3 |
| years active | 2024,2025,2026 | 2025 |
| series | imsa | alms |
| licence(s) | Silver | Silver |
| country | USA | USA |
| teams | Conquest Racing | AF Corse |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9073 |

### `horst felbermayr` ↔ `horst jr felbermayr`

> NOTE (review): the target id also absorbs 905 rows of bare 'Horst FELBERMAYR' (ELMS 2023/2025) via a PRE-EXISTING fold, alongside 'Horst Felbermayr JR'. All three spellings are session-disjoint, so no conflict is visible — but if bare 'Horst Felbermayr' is ever the father (Sr.), that older fold is wrong. Flag when reviewing.

**AUTO-MERGE** → canonical `horst felbermayr` (812 laps vs 93).

**Both ids are 'Horst Felbermayr JR'** — one spelled 'Horst Felbermayr JR', the other 'Horst Jr Felbermayr'. Same country, same licence, same team (Proton Competition), and they never co-occur. The proof is triangulation: the *third* id, `horst felix felbermayr`, co-occurs with `horst felbermayr` in 33 sessions and with `horst jr felbermayr` in 7 — so Felix is the relative, and the two JR spellings are one man.

| evidence | A | B |
|---|---|---|
| driver_id | `horst felbermayr` | `horst jr felbermayr` |
| display name | Horst Felbermayr JR | Horst Jr Felbermayr |
| career laps | 812 | 93 |
| events | 18 | 1 |
| years active | 2022,2023,2025,2026 | 2026 |
| series | alms/elms | wec |
| licence(s) | Bronze | Bronze |
| country | AUT | AUT |
| teams | Proton Competition; RLR M Sport; RLR MSport | Proton Competition |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9059 |

### `kaku ohta` ↔ `kakunoshin ohta`

**AUTO-MERGE** → canonical `kaku ohta` (537 laps vs 126).

Kaku is the standard short form of Kakunoshin; same country, same licence (Gold); no co-occurrence, no shared event.

| evidence | A | B |
|---|---|---|
| driver_id | `kaku ohta` | `kakunoshin ohta` |
| display name | Kaku Ohta | Kakunoshin Ohta |
| career laps | 537 | 126 |
| events | 6 | 1 |
| years active | 2024,2025,2026 | 2026 |
| series | imsa | wec |
| licence(s) | Gold | Gold |
| country | JPN | JPN |
| teams | Acura Meyer Shank Racing w/Curb Agajanian; Era Motorsport | Proton Competition |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8978 |

### `oliver millroy` ↔ `ollie millroy`

**AUTO-MERGE** → canonical `ollie millroy` (2153 laps vs 143).

ollie/oliver nickname; same country and licence; no co-occurrence, no shared event.

| evidence | A | B |
|---|---|---|
| driver_id | `oliver millroy` | `ollie millroy` |
| display name | Oliver Millroy | Ollie Millroy |
| career laps | 143 | 2153 |
| events | 3 | 23 |
| years active | 2024 | 2022,2023,2024,2025,2026 |
| series | alms | alms/imsa |
| licence(s) | Silver | Silver |
| country | GBR | GBR |
| teams | Optimum Motorsport | Hub Auto Racing; Inception Racing |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8969 |

### `gregory bennett` ↔ `gregory slatin bennett`

**AUTO-MERGE** → canonical `gregory slatin bennett` (256 laps vs 182).

Middle-name superset; same country and licence; consecutive, non-overlapping Asian LMS seasons (2025 then 2026); no co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `gregory bennett` | `gregory slatin bennett` |
| display name | Gregory Bennett | Gregory Slatin Bennett |
| career laps | 182 | 256 |
| events | 3 | 3 |
| years active | 2025 | 2026 |
| series | alms | alms |
| licence(s) | Bronze | Bronze |
| country | USA | USA |
| teams | Absolute Racing | Amerasian Fragrance by AF Racing |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8964 |

### `fred makowiecki` ↔ `frederic makowiecki`

**AUTO-MERGE** → canonical `frederic makowiecki` (1573 laps vs 453).

fred/frederic nickname; same country and licence (Platinum); **overlapping team** (Porsche Penske); no co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `fred makowiecki` | `frederic makowiecki` |
| display name | Fred Makowiecki | Frederic Makowiecki |
| career laps | 453 | 1573 |
| events | 3 | 22 |
| years active | 2021,2024 | 2023,2024,2025,2026 |
| series | imsa | wec |
| licence(s) | Platinum | Platinum |
| country | FRA | FRA |
| teams | Porsche Penske Motorsports; WeatherTech Racing; Wright Motorsports | Alpine Endurance Team; Porsche Penske Motorsport |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8912 |

### `carl bennett` ↔ `carl wattana bennett`

**AUTO-MERGE** → canonical `carl wattana bennett` (682 laps vs 343).

Middle-name superset; same country (THA) and licence; no co-occurrence, no shared event; the programmes (ELMS/IMSA vs Asian LMS/WEC) are compatible for one driver.

| evidence | A | B |
|---|---|---|
| driver_id | `carl bennett` | `carl wattana bennett` |
| display name | Carl Bennett | Carl Wattana Bennett |
| career laps | 343 | 682 |
| events | 5 | 12 |
| years active | 2024,2026 | 2023,2024,2025,2026 |
| series | elms/imsa | alms/wec |
| licence(s) | Silver | Silver |
| country | THA | THA |
| teams | COOL Racing; van der Steur Racing | Absolute Racing; Amerasian Fragrance by AF Racing; Duqueine Team; Isotta Fraschini |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8867 |

### `dan harper` ↔ `daniel harper`

**AUTO-MERGE** → canonical `dan harper` (970 laps vs 417).

dan/daniel nickname; same country and licence (Platinum). Decisive: both spellings appear at IMSA 2026 Daytona **in the same car (#1, Paul Miller Racing)** in different sessions — the same source-data split documented in section 'The 2026 Daytona split-name artifact' below, here without a co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `dan harper` | `daniel harper` |
| display name | Dan Harper | Daniel Harper |
| career laps | 970 | 417 |
| events | 11 | 9 |
| years active | 2024,2025,2026 | 2024,2026 |
| series | imsa | alms/wec |
| licence(s) | Platinum | Platinum |
| country | GBR | GBR |
| teams | Paul Miller Racing | Project 1; Team Project 1; Team WRT |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8762 |
| shared event | | IMSA 2026 Daytona — **same car #1**, different sessions |

### `seb priaulx` ↔ `sebastian priaulx`

**AUTO-MERGE** → canonical `seb priaulx` (1682 laps vs 1566).

seb/sebastian nickname; same country; strictly complementary seasons (2022-24 vs 2025-26); no co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `seb priaulx` | `sebastian priaulx` |
| display name | Seb Priaulx | Sebastian Priaulx |
| career laps | 1682 | 1566 |
| events | 18 | 17 |
| years active | 2022,2023,2024 | 2025,2026 |
| series | imsa | elms/imsa/wec |
| licence(s) | Gold,Silver | Gold |
| country | GBR | GBR |
| teams | AO Racing; Inception Racing; Sean Creech Motorsport | Ford Multimatic Motorsports; Ford Racing; Proton Competition |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8752 |

### `juan correa` ↔ `juan manuel correa`

**AUTO-MERGE** → canonical `juan correa` (387 laps vs 294).

Middle-name superset; same country and licence; strictly complementary seasons (2022-23 vs 2025); no co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `juan correa` | `juan manuel correa` |
| display name | Juan Correa | Juan Manuel CORREA |
| career laps | 387 | 294 |
| events | 4 | 5 |
| years active | 2025 | 2022,2023 |
| series | imsa | elms/wec |
| licence(s) | Silver | Silver |
| country | USA | USA |
| teams | United Autosports USA | Prema Racing |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8677 |

### `dudu barrichello` ↔ `eduardo barrichello`

**AUTO-MERGE** → canonical `eduardo barrichello` (835 laps vs 535).

dudu/eduardo nickname; same country and licence; **same team** (Heart of Racing) in the overlapping 2026 season, yet never in the same session.

| evidence | A | B |
|---|---|---|
| driver_id | `dudu barrichello` | `eduardo barrichello` |
| display name | Dudu Barrichello | Eduardo Barrichello |
| career laps | 535 | 835 |
| events | 7 | 11 |
| years active | 2026 | 2025,2026 |
| series | imsa | imsa/wec |
| licence(s) | Silver | Silver |
| country | BRA | BRA |
| teams | Heart of Racing Team | Heart of Racing Team; Racing Spirit of Leman; van der Steur Racing |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8645 |

### `jon bennett` ↔ `jonathan bennett`

**AUTO-MERGE** → canonical `jonathan bennett` (526 laps vs 494).

jon/jonathan nickname; same country and licence; **same team** (CORE Autosport); consecutive non-overlapping seasons (2021 then 2022). NOTE: 'more laps wins' picks `jonathan bennett` by 526 to 494; the displayed name stays 'Jon Bennett' because the display-name picker prefers the shorter spelling.

| evidence | A | B |
|---|---|---|
| driver_id | `jon bennett` | `jonathan bennett` |
| display name | Jon Bennett | Jonathan Bennett |
| career laps | 494 | 526 |
| events | 7 | 7 |
| years active | 2022 | 2021 |
| series | imsa | imsa |
| licence(s) | Bronze | Bronze |
| country | USA | USA |
| teams | CORE Autosport | CORE Autosport |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8634 |

### `oliver caldwell` ↔ `olli caldwell`

**AUTO-MERGE** → canonical `olli caldwell` (1184 laps vs 96).

olli/oliver nickname; same country. Decisive: both spellings appear at WEC 2023 Sebring **in the same car (#35)** in different sessions.

| evidence | A | B |
|---|---|---|
| driver_id | `oliver caldwell` | `olli caldwell` |
| display name | Oliver Caldwell | Olli Caldwell |
| career laps | 96 | 1184 |
| events | 1 | 23 |
| years active | 2021,2022,2023,2026 | 2023,2024,2025 |
| series | wec | alms/elms/wec |
| licence(s) | Gold,Silver | Gold |
| country | GBR | GBR |
| teams | ARC Bratislava | Algarve Pro Racing; Alpine Elf Team; Inter Europol Competition |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8595 |
| shared event | | WEC 2023 Sebring — **same car #35**, different sessions |

### `rui andrade` ↔ `rui pinto de andrade`

**AUTO-MERGE** → canonical `rui andrade` (2410 laps vs 906).

Middle-name superset; same licence; ANG and AGO are the same country under two codes; no co-occurrence, no shared event.

| evidence | A | B |
|---|---|---|
| driver_id | `rui andrade` | `rui pinto de andrade` |
| display name | Rui Andrade | Rui Pinto de Andrade |
| career laps | 2410 | 906 |
| events | 50 | 9 |
| years active | 2021,2022,2023,2024,2025,2026 | 2022,2024 |
| series | alms/elms/wec | imsa |
| licence(s) | Silver | Silver |
| country | ANG | AGO |
| teams | Dragon Racing; Duqueine Team; G-Drive Racing; Inter Europol Competition; Iron Lynx; Realteam by WRT; TF Sport; Team WRT | Lone Star Racing; Tower Motorsport |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8555 |

### `nicholas adcock` ↔ `nick adcock`

**AUTO-MERGE** → canonical `nicholas adcock` (1293 laps vs 650).

nick/nicholas nickname; same country and licence; **overlapping team** (RLR M Sport); seasons overlap in ELMS yet they never share a session.

| evidence | A | B |
|---|---|---|
| driver_id | `nicholas adcock` | `nick adcock` |
| display name | Nicholas Adcock | Nick ADCOCK |
| career laps | 1293 | 650 |
| events | 21 | 23 |
| years active | 2021,2022,2023,2024,2025,2026 | 2022,2023,2024,2025 |
| series | alms/elms | elms |
| licence(s) | Bronze | Bronze |
| country | RSA | RSA |
| teams | CD Sport; Forestier Racing by VPS; M Racing; Nielsen Racing; RLR M Sport | RLR M Sport; RLR MSport; Team Virage |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8543 |

### `jonathan adam` ↔ `jonny adam`

**AUTO-MERGE** → canonical `jonathan adam` (1033 laps vs 225).

jonny/jonathan nickname; same country; no co-occurrence, no shared event.

| evidence | A | B |
|---|---|---|
| driver_id | `jonathan adam` | `jonny adam` |
| display name | Jonathan Adam | Jonny Adam |
| career laps | 1033 | 225 |
| events | 19 | 3 |
| years active | 2022,2023,2024,2025,2026 | 2025,2026 |
| series | alms/elms/imsa | wec |
| licence(s) | Bronze,Platinum | Platinum |
| country | GBR | GBR |
| teams | Blackthorn; Ecurie Ecosse Blackthorn; Grid Motorsport by TF; Magnus Racing; TF Sport | Heart of Racing Team |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.853 |

### `alexander malykhin` ↔ `aliaksandr malykhin`

**AUTO-MERGE** → canonical `aliaksandr malykhin` (805 laps vs 413).

Transliteration variant of one Belarusian first name; **overlapping team** (Pure Rxcing); same licence; no co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `alexander malykhin` | `aliaksandr malykhin` |
| display name | Alexander Malykhin | Aliaksandr Malykhin |
| career laps | 413 | 805 |
| events | 5 | 15 |
| years active | 2023,2024 | 2024,2025 |
| series | alms | alms/elms/wec |
| licence(s) | Bronze | Bronze,Silver |
| country | KNA | GBR |
| teams | Herberth Motorsport; Pure Rxcing | CLX - Pure Rxcing; Manthey PureRxcing; Pure Rxcing |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8461 |

### `nicholas moss` ↔ `nick moss`

**AUTO-MERGE** → canonical `nicholas moss` (115 laps vs 58).

nick/nicholas nickname; same country and licence (Bronze); consecutive non-overlapping seasons (2022 then 2023); no co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `nicholas moss` | `nick moss` |
| display name | Nicholas Moss | Nick MOSS |
| career laps | 115 | 58 |
| events | 2 | 1 |
| years active | 2022 | 2023 |
| series | alms | elms |
| licence(s) | Bronze | Bronze |
| country | GBR | GBR |
| teams | Optimum Motorsport | Eurointernational |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.826 |

### `michael conway` ↔ `mike conway`

**AUTO-MERGE** → canonical `mike conway` (3255 laps vs 223).

mike/michael nickname; same country and licence (Platinum); **same team lineage** (Toyota Gazoo Racing 2021-25, Toyota Racing 2026); strictly complementary seasons; no co-occurrence.

| evidence | A | B |
|---|---|---|
| driver_id | `michael conway` | `mike conway` |
| display name | Michael Conway | Mike Conway |
| career laps | 223 | 3255 |
| events | 3 | 38 |
| years active | 2026 | 2021,2022,2023,2024,2025 |
| series | wec | imsa/wec |
| licence(s) | Platinum | Platinum |
| country | GBR | GBR |
| teams | Toyota Racing | Toyota Gazoo Racing; Vasser Sullivan; VasserSullivan; Whelen Engineering Racing |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8196 |

## NEEDS-DECISION — resolved (20 pairs: 19 merged, 1 kept separate)

### `benjamin goethe` ↔ `benji goethe`

**NEEDS-DECISION → merged**

Standard diminutive; both Garage 59; complementary seasons (2023/2025 vs 2026); no co-occurrence. Country reads DEN vs DEU (not evidence — see Method); career laps 228 vs 230, so canonical `benjamin goethe` was a coin flip.

| evidence | A | B |
|---|---|---|
| driver_id | `benjamin goethe` | `benji goethe` |
| display name | Benjamin Goethe | Benji Goethe |
| career laps | 228 | 230 |
| events | 3 | 5 |
| years active | 2026 | 2023,2025 |
| series | wec | alms |
| licence(s) | Gold | Gold,Silver |
| country | DEN | DEU |
| teams | Garage 59 | Garage 59; Optimum Motorsport |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.96 |

### `abdulla al-khelaifi` ↔ `abdulla ali al-khelaifi`

**NEEDS-DECISION → merged**

Middle-name superset; same country, licence, and in 2026 the same team **and car number** (Team Qatar by Iron Lynx #62) across two championships — one driver's split programme. Caveat: 'Ali' is a patronymic and the sibling pattern produced the two Princes Ibrahim below; the guard has no purchase across championships.

| evidence | A | B |
|---|---|---|
| driver_id | `abdulla al-khelaifi` | `abdulla ali al-khelaifi` |
| display name | Abdulla AL-Khelaifi | Abdulla ALI AL-Khelaifi |
| career laps | 193 | 415 |
| events | 2 | 6 |
| years active | 2025,2026 | 2026 |
| series | alms/wec | alms/elms |
| licence(s) | Bronze | Bronze |
| country | QAT | QAT |
| teams | QMMF by Herberth; Team Qatar by Iron Lynx | QMMF by GetSpeed; Team Qatar by Iron Lynx |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9231 |

### `jon miller` ↔ `jonathan miller`

**NEEDS-DECISION → kept separate**

Nickname-shaped, same country/licence, both 2022 — but different championships (IMSA Crucial #59 vs Asian LMS Walkenhorst #34), no team link, and a common surname already holding several drivers (Joel Miller raced against Jon Miller in 2022).

| evidence | A | B |
|---|---|---|
| driver_id | `jon miller` | `jonathan miller` |
| display name | Jon Miller | Jonathan Miller |
| career laps | 266 | 118 |
| events | 4 | 2 |
| years active | 2022 | 2022 |
| series | imsa | alms |
| licence(s) | Silver | Silver |
| country | USA | USA |
| teams | Crucial Motorsports | Walkenhorst Motorsport |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9222 |

### `nico muller` ↔ `nicolas muller`

**NEEDS-DECISION → merged**

Complementary seasons (2022-25 vs 2026), same country and licence (Platinum), nickname-shaped. Against: no team link, and the surname cluster already holds several distinct drivers (`dirk mueller`, `sven muller`).

| evidence | A | B |
|---|---|---|
| driver_id | `nico muller` | `nicolas muller` |
| display name | Nico MÜLLER | Nicolas Muller |
| career laps | 977 | 141 |
| events | 16 | 1 |
| years active | 2022,2023,2024,2025 | 2026 |
| series | wec | wec |
| licence(s) | Platinum | Platinum |
| country | SUI | SUI |
| teams | Peugeot TotalEnergies; Porsche Penske Motorsport; Vector Sport | Inter Europol Competition |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9208 |

### `ed jones` ↔ `edward jones`

**NEEDS-DECISION → merged**

Nickname, same licence (Gold), no co-occurrence or shared event; 2022 IMSA and WEC programmes compatible. Against: country ARE vs GBR (a real distinction) and no team link.

| evidence | A | B |
|---|---|---|
| driver_id | `ed jones` | `edward jones` |
| display name | Ed Jones | Edward JONES |
| career laps | 1036 | 423 |
| events | 9 | 6 |
| years active | 2021,2022,2023 | 2022 |
| series | imsa | wec |
| licence(s) | Gold | Gold |
| country | ARE | GBR |
| teams | G-Drive Racing By APR; High Class Racing; Scuderia Corsa | JOTA |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9111 |

### `eddie cheever` ↔ `edward cheever`

**NEEDS-DECISION → merged**

Nickname, same country and licence, no co-occurrence or shared event. Against: a multi-generation racing family, both active in 2025 with different teams, no team link.

| evidence | A | B |
|---|---|---|
| driver_id | `eddie cheever` | `edward cheever` |
| display name | Eddie Cheever | Edward Cheever |
| career laps | 321 | 228 |
| events | 2 | 2 |
| years active | 2024,2025 | 2022,2025 |
| series | imsa | imsa/wec |
| licence(s) | Gold | Gold |
| country | ITA | ITA |
| teams | CETILAR RACING; Triarsi Competizione | Risi Competizione; Ziggo Sport Tempesta |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8291 |

### `alex palou` ↔ `alexander palou`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 6 same-car hand-overs, 6 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `alex palou` | `alexander palou` |
| display name | Alex Palou | Alexander Palou |
| career laps | 853 | 79 |
| events | 5 | 1 |
| years active | 2022,2024,2025,2026 | 2026 |
| series | imsa | imsa |
| licence(s) | Gold,Platinum | Platinum |
| country | ESP | ESP |
| teams | Acura Meyer Shank Racing w/Curb Agajanian; Cadillac Racing | Acura Meyer Shank Racing w/Curb Agajanian |
| **shared sessions** | | same car: **1**, different car: **0** |
| **hand-overs / impossible** | | 6 hand-overs, **6** with no pit stop |
| name similarity (jw) | | 0.9133 |

### `thomas gamble` ↔ `tom gamble`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 2 same-car hand-overs, 2 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `thomas gamble` | `tom gamble` |
| display name | Thomas Gamble | Tom Gamble |
| career laps | 910 | 2695 |
| events | 13 | 34 |
| years active | 2022,2023,2024,2025,2026 | 2021,2022,2023,2024,2025,2026 |
| series | alms/imsa/wec | elms/imsa/wec |
| licence(s) | Gold,Silver | Gold,Silver |
| country | GBR | GBR |
| teams | Aston Martin Thor Team; D'Station Racing; Garage 59; Heart of Racing Team; Optimum Motorsport | Aston Martin Thor Team; Heart of Racing Team; Inception Racing; United Autosports; United Autosports USA |
| **shared sessions** | | same car: **1**, different car: **0** |
| **hand-overs / impossible** | | 2 hand-overs, **2** with no pit stop |
| name similarity (jw) | | 0.9008 |

### `ben green` ↔ `benjamin green`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 2 same-car hand-overs, 2 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `ben green` | `benjamin green` |
| display name | Ben Green | Benjamin Green |
| career laps | 179 | 257 |
| events | 1 | 3 |
| years active | 2026 | 2026 |
| series | imsa | alms/wec |
| licence(s) | Platinum | Platinum |
| country | GBR | GBR |
| teams | 13 Autosport | JMR; TF Sport |
| **shared sessions** | | same car: **1**, different car: **0** |
| **hand-overs / impossible** | | 2 hand-overs, **2** with no pit stop |
| name similarity (jw) | | 0.8648 |

### `ben barnicoat` ↔ `benjamin barnicoat`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 5 same-car hand-overs, 5 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `ben barnicoat` | `benjamin barnicoat` |
| display name | Ben Barnicoat | Benjamin Barnicoat |
| career laps | 3610 | 827 |
| events | 48 | 12 |
| years active | 2021,2022,2023,2024,2025,2026 | 2022,2025,2026 |
| series | elms/imsa/wec | alms/imsa/wec |
| licence(s) | Gold,Platinum | Gold,Platinum |
| country | GBR | GBR |
| teams | AF Corse; Akkodis ASP Team; Inception Racing; Vasser Sullivan; Vasser Sullivan Racing; VasserSullivan | 2Seas Motorsport; AF Corse; Inception Racing; Vasser Sullivan Racing; Vasser Sullivan Racing w/Dreyer & Reinbold |
| **shared sessions** | | same car: **1**, different car: **0** |
| **hand-overs / impossible** | | 5 hand-overs, **5** with no pit stop |
| name similarity (jw) | | 0.8634 |

### `michael rockenfeller` ↔ `mike rockenfeller`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 1 same-car hand-overs, 1 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `michael rockenfeller` | `mike rockenfeller` |
| display name | Michael Rockenfeller | Mike Rockenfeller |
| career laps | 165 | 3309 |
| events | 3 | 34 |
| years active | 2026 | 2021,2022,2023,2024,2025,2026 |
| series | elms/imsa | imsa/wec |
| licence(s) | Platinum | Platinum |
| country | SUI | CHE |
| teams | Ford Racing; Proton Competition | Ally Cadillac; Ally Cadillac Racing; Ford Multimatic Motorsports; Ford Racing; JDC Miller MotorSports; Proton Competition Mustang Sampling; Vector Sport |
| **shared sessions** | | same car: **1**, different car: **0** |
| **hand-overs / impossible** | | 1 hand-overs, **1** with no pit stop |
| name similarity (jw) | | 0.8476 |

### `matt campbell` ↔ `matthew campbell`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 23 same-car hand-overs, 21 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `matt campbell` | `matthew campbell` |
| display name | Matt Campbell | Matthew Campbell |
| career laps | 4588 | 79 |
| events | 47 | 1 |
| years active | 2021,2022,2023,2024,2025,2026 | 2026 |
| series | imsa/wec | imsa |
| licence(s) | Gold,Platinum | Platinum |
| country | AUS | AUS |
| teams | Pfaff Motorsports; Porsche Penske Motorsport; Porsche Penske Motorsports; WeatherTech Racing | Porsche Penske Motorsport |
| **shared sessions** | | same car: **2**, different car: **0** |
| **hand-overs / impossible** | | 23 hand-overs, **21** with no pit stop |
| name similarity (jw) | | 0.9163 |

### `thomas sargent` ↔ `tom sargent`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 11 same-car hand-overs, 8 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `thomas sargent` | `tom sargent` |
| display name | Thomas Sargent | Tom Sargent |
| career laps | 279 | 546 |
| events | 6 | 5 |
| years active | 2026 | 2024,2025,2026 |
| series | elms/imsa | imsa |
| licence(s) | Silver | Silver |
| country | AUS | AUS |
| teams | Proton Competition; Wright Motorsports | Wright Motorsports |
| **shared sessions** | | same car: **2**, different car: **0** |
| **hand-overs / impossible** | | 11 hand-overs, **8** with no pit stop |
| name similarity (jw) | | 0.9084 |

### `max hesse` ↔ `maximilian hesse`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 8 same-car hand-overs, 7 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `max hesse` | `maximilian hesse` |
| display name | Max Hesse | Maximilian Hesse |
| career laps | 1039 | 89 |
| events | 11 | 1 |
| years active | 2024,2025,2026 | 2026 |
| series | imsa | imsa |
| licence(s) | Gold | Gold |
| country | DEU | DEU |
| teams | Paul Miller Racing | Paul Miller Racing |
| **shared sessions** | | same car: **2**, different car: **0** |
| **hand-overs / impossible** | | 8 hand-overs, **7** with no pit stop |
| name similarity (jw) | | 0.8979 |

### `nicholas tandy` ↔ `nick tandy`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 16 same-car hand-overs, 16 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `nicholas tandy` | `nick tandy` |
| display name | Nicholas Tandy | Nick Tandy |
| career laps | 462 | 3924 |
| events | 6 | 40 |
| years active | 2023,2026 | 2021,2022,2023,2024,2025,2026 |
| series | imsa | imsa/wec |
| licence(s) | Platinum | Platinum |
| country | GBR | GBR |
| teams | AO Racing | AO Racing; Corvette Racing; Porsche Penske Motorsport; Porsche Penske Motorsports |
| **shared sessions** | | same car: **2**, different car: **0** |
| **hand-overs / impossible** | | 16 hand-overs, **16** with no pit stop |
| name similarity (jw) | | 0.8674 |

### `ben keating` ↔ `benjamin keating`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 7 same-car hand-overs, 7 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `ben keating` | `benjamin keating` |
| display name | Ben Keating | Benjamin Keating |
| career laps | 3148 | 86 |
| events | 36 | 1 |
| years active | 2021,2022,2023,2024,2025,2026 | 2026 |
| series | imsa/wec | wec |
| licence(s) | Bronze | Bronze |
| country | USA | USA |
| teams | Bryan Herta Autosport with PR1/Mathiasen; PR1 Mathiasen Motorsports; Proton Competition; TF Sport; United Autosports USA | TF Sport |
| **shared sessions** | | same car: **2**, different car: **0** |
| **hand-overs / impossible** | | 7 hand-overs, **7** with no pit stop |
| name similarity (jw) | | 0.8634 |

### `max esterson` ↔ `maximilian esterson`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 5 same-car hand-overs, 5 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `max esterson` | `maximilian esterson` |
| display name | Max Esterson | Maximilian Esterson |
| career laps | 276 | 436 |
| events | 2 | 6 |
| years active | 2025,2026 | 2026 |
| series | imsa | imsa |
| licence(s) | Silver | Silver |
| country | USA | USA |
| teams | JDC Miller MotorSports; RLL Team McLaren | RLL Team McLaren |
| **shared sessions** | | same car: **2**, different car: **0** |
| **hand-overs / impossible** | | 5 hand-overs, **5** with no pit stop |
| name similarity (jw) | | 0.8363 |

### `nicholas cassidy` ↔ `nick cassidy`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 10 same-car hand-overs, 9 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `nicholas cassidy` | `nick cassidy` |
| display name | Nicholas Cassidy | Nick Cassidy |
| career laps | 305 | 211 |
| events | 4 | 1 |
| years active | 2026 | 2025,2026 |
| series | alms/wec | imsa |
| licence(s) | Platinum | Platinum |
| country | NZL | NZL |
| teams | Inter Europol Competition; Peugeot TotalEnergies | Inter Europol Competition |
| **shared sessions** | | same car: **3**, different car: **0** |
| **hand-overs / impossible** | | 10 hand-overs, **9** with no pit stop |
| name similarity (jw) | | 0.8652 |

### `thomas dillmann` ↔ `tom dillmann`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 23 same-car hand-overs, 19 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `thomas dillmann` | `tom dillmann` |
| display name | Thomas Dillmann | Tom Dillmann |
| career laps | 1227 | 2525 |
| events | 17 | 30 |
| years active | 2024,2025,2026 | 2023,2024,2025,2026 |
| series | alms/elms/imsa/wec | elms/imsa/wec |
| licence(s) | Gold | Gold |
| country | FRA | FRA |
| teams | Algarve Pro Racing; DKR Engineering; Inter Europol Competition; Proton Competition | Floyd Vanwall Racing Team; Inter Europol  by PR1 Mathiasen Motorsports; Inter Europol Competition; Inter Europol by PR1 Mathiasen Motorsports |
| **shared sessions** | | same car: **3**, different car: **0** |
| **hand-overs / impossible** | | 23 hand-overs, **19** with no pit stop |
| name similarity (jw) | | 0.865 |

### `thomas blomqvist` ↔ `tom blomqvist`

**NEEDS-DECISION → merged**

2026 Daytona split-name artifact: 23 same-car hand-overs, 21 with no pit stop. Merged.

| evidence | A | B |
|---|---|---|
| driver_id | `thomas blomqvist` | `tom blomqvist` |
| display name | Thomas Blomqvist | Tom Blomqvist |
| career laps | 479 | 4452 |
| events | 6 | 45 |
| years active | 2026 | 2021,2022,2023,2024,2025,2026 |
| series | imsa | elms/imsa/wec |
| licence(s) | Platinum | Gold,Platinum |
| country | GBR | GBR |
| teams | Acura Meyer Shank Racing w/Curb Agajanian | Acura Meyer Shank Racing w/Curb Agajanian; CLX - Pure Rxcing; JOTA; Meyer Shank Racing W/Curb-Agajanian; Meyer Shank Racing w/ Curb Agajanian; United Autosports; United Autosports USA; Whelen Cadillac Racing; Whelen Engineering Cadillac Racing |
| **shared sessions** | | same car: **4**, different car: **0** |
| **hand-overs / impossible** | | 23 hand-overs, **21** with no pit stop |
| name similarity (jw) | | 0.8514 |

## REJECT — never merge (20 pairs)

### `mikkel gaarde pedersen` ↔ `mikkel pedersen`

**REJECT**

**Two different Danes.** They appear at the same event — ELMS 2025 Portimao — in different cars (#4 for DKR Engineering vs #85/#86 for R-ACE GP). They never share a session only because they were in separate entries; the shared-event/different-car test settles it.

| evidence | A | B |
|---|---|---|
| driver_id | `mikkel gaarde pedersen` | `mikkel pedersen` |
| display name | Mikkel Gaarde Pedersen | Mikkel Pedersen |
| career laps | 244 | 428 |
| events | 9 | 8 |
| years active | 2024,2025,2026 | 2023,2024,2025,2026 |
| series | elms | alms/imsa/wec |
| licence(s) | Silver | Silver |
| country | DEN | DNK |
| teams | DKR Engineering; Rinaldi Racing | AO Racing; Herberth Motorsport; Proton Competition |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8964 |
| shared event | | ELMS 2025 Portimao — **different cars** (#4 vs #85/#86) |

### `jake pedersen` ↔ `mikkel pedersen`

**REJECT**

Different first names (Jake vs Mikkel), different countries; matched only because the surname dominates the similarity score.

| evidence | A | B |
|---|---|---|
| driver_id | `jake pedersen` | `mikkel pedersen` |
| display name | Jake Pedersen | Mikkel Pedersen |
| career laps | 47 | 428 |
| events | 1 | 8 |
| years active | 2024 | 2023,2024,2025,2026 |
| series | imsa | alms/imsa/wec |
| licence(s) | Silver | Silver |
| country | USA | DNK |
| teams | Kellymoss with Riley | AO Racing; Herberth Motorsport; Proton Competition |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8598 |

### `vic stevens` ↔ `will stevens`

**REJECT**

Different first names, different countries, different licence tiers; surname-driven false match.

| evidence | A | B |
|---|---|---|
| driver_id | `vic stevens` | `will stevens` |
| display name | Vic Stevens | Will Stevens |
| career laps | 147 | 4003 |
| events | 3 | 50 |
| years active | 2025,2026 | 2021,2022,2023,2024,2025,2026 |
| series | alms | alms/elms/imsa/wec |
| licence(s) | Silver | Gold,Platinum |
| country | BEL | GBR |
| teams | Team Virage | Cadillac Hertz Team JOTA; Cadillac Wayne Taylor Racing; Hertz Team JOTA; JOTA; Konica Minolta Acura ARX-05; Nielsen Racing; Panis Racing; Racing Team Turkey; Tower Motorsport; Tower Motorsports; Wayne Taylor Racing |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8561 |

### `joel miller` ↔ `jonathan miller`

**REJECT**

Different first names; Joel Miller and Jon Miller raced against each other in 2022 (different cars), so this surname genuinely holds several drivers.

| evidence | A | B |
|---|---|---|
| driver_id | `joel miller` | `jonathan miller` |
| display name | Joel Miller | Jonathan Miller |
| career laps | 125 | 118 |
| events | 2 | 2 |
| years active | 2022,2025 | 2022 |
| series | imsa | alms |
| licence(s) | Gold | Silver |
| country | USA | USA |
| teams | Muehlner Motorsports America; Triarsi Competizione | Walkenhorst Motorsport |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8448 |

### `nico muller` ↔ `sven muller`

**REJECT**

Different first names, different countries, different licence tiers.

| evidence | A | B |
|---|---|---|
| driver_id | `nico muller` | `sven muller` |
| display name | Nico MÜLLER | Sven Muller |
| career laps | 977 | 209 |
| events | 16 | 1 |
| years active | 2022,2023,2024,2025 | 2021,2026 |
| series | wec | imsa |
| licence(s) | Platinum | Gold |
| country | SUI | DEU |
| teams | Peugeot TotalEnergies; Porsche Penske Motorsport; Vector Sport | RWR-Eurasia |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8182 |

### `leonardo pulcini` ↔ `marco pulcini`

**REJECT**

Different first names, different licence tiers, different teams; surname-driven false match.

| evidence | A | B |
|---|---|---|
| driver_id | `leonardo pulcini` | `marco pulcini` |
| display name | Leonardo Pulcini | Marco Pulcini |
| career laps | 126 | 279 |
| events | 1 | 4 |
| years active | 2024 | 2024,2025 |
| series | imsa | alms |
| licence(s) | Gold | Bronze |
| country | ITA | ITA |
| teams | Iron Lynx | Dragon Racing |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8142 |

### `kevin conway` ↔ `mike conway`

**REJECT**

Different first names, different countries (USA vs GBR), different licence tiers.

| evidence | A | B |
|---|---|---|
| driver_id | `kevin conway` | `mike conway` |
| display name | Kevin Conway | Mike Conway |
| career laps | 31 | 3255 |
| events | 1 | 38 |
| years active | 2023 | 2021,2022,2023,2024,2025 |
| series | imsa | imsa/wec |
| licence(s) | Bronze | Platinum |
| country | USA | GBR |
| teams | Ave Motorsports | Toyota Gazoo Racing; Vasser Sullivan; VasserSullivan; Whelen Engineering Racing |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8141 |

### `jimmie johnson` ↔ `nikita johnson`

**REJECT**

Different first names; surname-driven false match.

| evidence | A | B |
|---|---|---|
| driver_id | `jimmie johnson` | `nikita johnson` |
| display name | Jimmie Johnson | Nikita Johnson |
| career laps | 684 | 471 |
| events | 7 | 7 |
| years active | 2021,2022 | 2026 |
| series | imsa | imsa |
| licence(s) | Platinum | Silver |
| country | USA | USA |
| teams | Ally Cadillac; Ally Cadillac Racing | RLL Team McLaren |
| **shared sessions** | | same car: **0**, different car: **0** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8095 |

### `christina nielsen` ↔ `nicklas nielsen`

**REJECT**

Shared IMSA 2021 Daytona sessions in different cars (#88 vs #21).

| evidence | A | B |
|---|---|---|
| driver_id | `christina nielsen` | `nicklas nielsen` |
| display name | Christina Nielsen | Nicklas Nielsen |
| career laps | 239 | 4411 |
| events | 2 | 53 |
| years active | 2021 | 2021,2022,2023,2024,2025,2026 |
| series | imsa | alms/elms/imsa/wec |
| licence(s) | Silver | Gold,Platinum |
| country | DNK | DEN |
| teams | Team Hardpoint EBM | AF Corse; Af Corse Usa; Ferrari AF Corse; Formula Racing; Richard Mille AF Corse |
| **shared sessions** | | same car: **0**, different car: **2** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8002 |

### `mikey taylor` ↔ `ricky taylor`

**REJECT**

Shared IMSA 2025 Watkins Glen sessions in different cars (#32 vs #10).

| evidence | A | B |
|---|---|---|
| driver_id | `mikey taylor` | `ricky taylor` |
| display name | Mikey Taylor | Ricky Taylor |
| career laps | 55 | 5008 |
| events | 1 | 56 |
| years active | 2025 | 2021,2022,2023,2024,2025,2026 |
| series | imsa | imsa/wec |
| licence(s) | Silver | Platinum |
| country | USA | USA |
| teams | Korthoff Competition Motors | Bryan Herta Autosport with PR1/Mathiasen; COOL Racing; Cadillac WTR; Cadillac Wayne Taylor Racing; Konica Minolta Acura ARX-05; Konica Minolta Acura ARX-06; Wayne Taylor Racing; Wayne Taylor Racing with Andretti |
| **shared sessions** | | same car: **0**, different car: **3** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8889 |

### `joel miller` ↔ `jon miller`

**REJECT**

Shared IMSA 2022 Daytona sessions in different cars (#6 vs #59).

| evidence | A | B |
|---|---|---|
| driver_id | `joel miller` | `jon miller` |
| display name | Joel Miller | Jon Miller |
| career laps | 125 | 266 |
| events | 2 | 4 |
| years active | 2022,2025 | 2022 |
| series | imsa | imsa |
| licence(s) | Gold | Silver |
| country | USA | USA |
| teams | Muehlner Motorsports America; Triarsi Competizione | Crucial Motorsports |
| **shared sessions** | | same car: **0**, different car: **3** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8656 |

### `dirk mueller` ↔ `nico mueller`

**REJECT**

Shared IMSA 2022 Daytona sessions in different cars (#15 vs #20).

| evidence | A | B |
|---|---|---|
| driver_id | `dirk mueller` | `nico mueller` |
| display name | Dirk Mueller | Nico Mueller |
| career laps | 1301 | 290 |
| events | 14 | 3 |
| years active | 2022,2024 | 2022,2025 |
| series | imsa | imsa |
| licence(s) | Platinum | Platinum |
| country | CHE | CHE |
| teams | Ford Multimatic Motorsports; Proton USA; Team Korthoff Motorsports | High Class Racing; JDC Miller MotorSports |
| **shared sessions** | | same car: **0**, different car: **4** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8333 |

### `horst felix felbermayr` ↔ `horst jr felbermayr`

**REJECT**

7 shared sessions in car #44 at Le Mans 2026; all 8 hand-overs are at pit stops. (Note `horst jr felbermayr` is merged into `horst felbermayr` above, so this pair collapses into the row above it.)

| evidence | A | B |
|---|---|---|
| driver_id | `horst felix felbermayr` | `horst jr felbermayr` |
| display name | Horst Felix Felbermayr | Horst Jr Felbermayr |
| career laps | 520 | 93 |
| events | 9 | 1 |
| years active | 2025,2026 | 2026 |
| series | alms/elms/wec | wec |
| licence(s) | Gold,Silver | Bronze |
| country | AUT | AUT |
| teams | Proton Competition | Proton Competition |
| **shared sessions** | | same car: **7**, different car: **0** |
| **hand-overs / impossible** | | 8 hand-overs, **0** with no pit stop |
| name similarity (jw) | | 0.8747 |

### `matthew bell` ↔ `matthew richard bell`

**REJECT**

8 shared sessions in different cars (ELMS 2024, #19 vs #11). Despite the middle-name-superset shape, these are two people.

| evidence | A | B |
|---|---|---|
| driver_id | `matthew bell` | `matthew richard bell` |
| display name | Matt Bell | Matthew Richard Bell |
| career laps | 5635 | 748 |
| events | 71 | 13 |
| years active | 2021,2022,2023,2024,2025,2026 | 2023,2024,2026 |
| series | alms/elms/imsa/wec | elms |
| licence(s) | Bronze,Gold,Silver | Bronze |
| country | GBR | GBR |
| teams | 13 Autosport; AWA; AWA Racing; COOL Racing; Eurointernational; Forty7 Motorsports; Nielsen Racing; TF Sport; Team Virage; WIN Autosport | Eurointernational |
| **shared sessions** | | same car: **0**, different car: **8** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.92 |

### `peter kox` ↔ `stephane kox`

**REJECT**

5 shared sessions in car #48 (Saalocin by Kox Racing); all 6 hand-overs are at pit stops. Relatives sharing a car.

| evidence | A | B |
|---|---|---|
| driver_id | `peter kox` | `stephane kox` |
| display name | Peter KOX | Stephane KOX |
| career laps | 172 | 79 |
| events | 2 | 2 |
| years active | 2022 | 2022 |
| series | alms | alms |
| licence(s) | Silver | Silver |
| country | NLD | NLD |
| teams | Saalocin by Kox Racing | Saalocin by Kox Racing |
| **shared sessions** | | same car: **9**, different car: **0** |
| **hand-overs / impossible** | | 6 hand-overs, **0** with no pit stop |
| name similarity (jw) | | 0.8102 |

### `prince abu bakar ibrahim` ↔ `prince jefri ibrahim`

**REJECT**

11 shared sessions — 8 of them in **different cars** (#66 vs #99) and 3 sharing car #66, with all hand-overs at pit stops. Two people, confirmed twice over.

| evidence | A | B |
|---|---|---|
| driver_id | `prince abu bakar ibrahim` | `prince jefri ibrahim` |
| display name | Prince Abu Bakar Ibrahim | Prince Jefri Ibrahim |
| career laps | 103 | 309 |
| events | 3 | 4 |
| years active | 2026 | 2026 |
| series | alms | alms/wec |
| licence(s) | Silver | Bronze |
| country | MAS | MAS |
| teams | JMR | JMR; TF Sport |
| **shared sessions** | | same car: **3**, different car: **8** |
| **hand-overs / impossible** | | 4 hand-overs, **0** with no pit stop |
| name similarity (jw) | | 0.8558 |

### `luis perez companc` ↔ `matias perez companc`

**REJECT**

12 shared sessions in car #88; all 16 hand-overs are at pit stops, with clean contiguous stints. Father and son sharing a car.

| evidence | A | B |
|---|---|---|
| driver_id | `luis perez companc` | `matias perez companc` |
| display name | Luis Perez Companc | Matias Perez Companc |
| career laps | 1418 | 351 |
| events | 19 | 5 |
| years active | 2022,2023,2024,2025 | 2025 |
| series | imsa | imsa |
| licence(s) | Bronze | Silver |
| country | ARG | ARG |
| teams | AF Corse; Richard Mille AF Corse | AF Corse |
| **shared sessions** | | same car: **17**, different car: **0** |
| **hand-overs / impossible** | | 16 hand-overs, **0** with no pit stop |
| name similarity (jw) | | 0.8963 |

### `horst felbermayr` ↔ `horst felix felbermayr`

**REJECT**

31 shared sessions sharing car #60/#44. Every one of the 33 hand-overs lands on a lap with a recorded pit stop — real driver changes. Relatives, not spellings.

| evidence | A | B |
|---|---|---|
| driver_id | `horst felbermayr` | `horst felix felbermayr` |
| display name | Horst Felbermayr JR | Horst Felix Felbermayr |
| career laps | 812 | 520 |
| events | 18 | 9 |
| years active | 2022,2023,2025,2026 | 2025,2026 |
| series | alms/elms | alms/elms/wec |
| licence(s) | Bronze | Gold,Silver |
| country | AUT | AUT |
| teams | Proton Competition; RLR M Sport; RLR MSport | Proton Competition |
| **shared sessions** | | same car: **33**, different car: **0** |
| **hand-overs / impossible** | | 33 hand-overs, **0** with no pit stop |
| name similarity (jw) | | 0.933 |

### `celia martin` ↔ `maxime martin`

**REJECT**

37 shared sessions in different cars; also different first names and countries.

| evidence | A | B |
|---|---|---|
| driver_id | `celia martin` | `maxime martin` |
| display name | Celia Martin | Maxime Martin |
| career laps | 1062 | 2327 |
| events | 17 | 32 |
| years active | 2024,2025 | 2022,2023,2024,2025,2026 |
| series | alms/elms/wec | elms/imsa/wec |
| licence(s) | Bronze | Platinum |
| country | FRA | BEL |
| teams | Iron Dames | BMW M Team RLL; GetSpeed; Heart of Racing Team; Iron Lynx; Paul Miller Racing; Team Qatar by Iron Lynx; Team WRT; Winward Racing |
| **shared sessions** | | same car: **0**, different car: **37** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.8009 |

### `michael jensen` ↔ `mikkel jensen`

**REJECT**

42 shared sessions, always in **different cars**. Two different Danes.

| evidence | A | B |
|---|---|---|
| driver_id | `michael jensen` | `mikkel jensen` |
| display name | Michael Jensen | Mikkel Jensen |
| career laps | 1694 | 5372 |
| events | 42 | 62 |
| years active | 2022,2023,2024,2025,2026 | 2021,2022,2023,2024,2025,2026 |
| series | alms/elms/wec | alms/elms/imsa/wec |
| licence(s) | Bronze | Gold,Platinum,Silver |
| country | DEN | DNK |
| teams | Algarve Pro Racing; CD Sport; RLR M Sport; RLR MSport; Team Virage | Car Guy; G-Drive Racing; Kessel Racing; PR1 Mathiasen Motorsports; Peugeot TotalEnergies; TDS Racing; United Autosports; United Autosports USA |
| **shared sessions** | | same car: **0**, different car: **42** |
| **hand-overs / impossible** | | n/a — never shared a car in a session |
| name similarity (jw) | | 0.9018 |

---

## Out of scope, worth a follow-up

`rake lint_drivers` still reports near-identical name pairs that this pass could
not see, because they differ in the *last* token and so never became candidates:
`marvin kirchhofer`/`marvin kirchofer`, `laurents hoerr`/`laurents horr`,
`aaron telitz`/`aaron tellitz`, `jens reno moeller`/`jens reno moller`,
`axcil jefferies`/`axcil jeffries`. These are surname typos and umlaut
transliterations rather than identity ambiguities; a second pass keyed on the
*first* token would catch them.
