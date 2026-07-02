-- Ingest tobi/track-atlas (https://github.com/tobi/track-atlas) tracks.jsonl,
-- fetched fresh at import time by `rake db:update_track_atlas` (see Rakefile),
-- cached at data/track-atlas/tracks.jsonl.
--
-- track-atlas gives us, per circuit layout, REAL physical distances for
-- timing sectors (S1/S2/S3) and — where published — IMSA microsectors
-- (currently only Watkins Glen from the Timing All Sections Map PDF) and
-- WEC slow zones (currently only Le Mans, from the HH Timing .cha config).
-- This is the "big unlock": Alkamel's own CSVs never carry sector distances,
-- only times — track-atlas is the only source that ties sector splits to
-- real track geometry (meters), letting us derive speed/pace-per-meter
-- instead of just time.
--
-- Runs immediately after 000-settings.sql (which defines `tracks`,
-- `normalize_track_name`) so downstream files can join against it.

CREATE OR REPLACE TABLE track_atlas_raw AS
SELECT
    slug,
    name,
    json_extract_string(external_ids, '$.imsa_data') AS imsa_slug,
    layouts
FROM read_json_auto('data/track-atlas/tracks.jsonl', format='newline_delimited')
WHERE json_extract_string(external_ids, '$.imsa_data') IS NOT NULL;

-- One row per (track, layout). A track normally has a single "gp" layout;
-- Sebring is the current exception with series-specific wec/imsa layouts.
CREATE OR REPLACE TABLE track_atlas_layouts AS
WITH layouts_unnested AS (
    SELECT slug, imsa_slug, unnest(layouts, recursive := false) AS layout
    FROM track_atlas_raw
)
SELECT
    slug,
    imsa_slug,
    json_extract_string(layout, '$.id') AS layout_id,
    json_extract(layout, '$.length_m')::DOUBLE AS length_m,
    list_transform(
        from_json(
            CASE
                WHEN json_extract(layout, '$.series') IS NULL
                  OR json(json_extract(layout, '$.series')) = 'null'::JSON
                THEN '[]'
                ELSE json_extract(layout, '$.series')
            END,
            '["json"]'
        ),
        x -> json_extract_string(x, '$')
    ) AS layout_series,
    json_extract(layout, '$.range_layers') AS range_layers
FROM layouts_unnested;

-- Picks the layout to use for a given (imsa_slug, series_code): the
-- series-specific layout when one exists (Sebring), otherwise the track's
-- sole layout.
CREATE OR REPLACE TABLE track_atlas_layout_choice AS
SELECT
    tal.imsa_slug,
    sc.series_code,
    tal.layout_id,
    tal.length_m,
    tal.range_layers
FROM track_atlas_layouts tal
CROSS JOIN (SELECT DISTINCT series_code FROM series_metadata) sc
WHERE list_contains(tal.layout_series, sc.series_code)
   OR (
        list_count(tal.layout_series) = 0
        AND (SELECT COUNT(*) FROM track_atlas_layouts t2 WHERE t2.imsa_slug = tal.imsa_slug) = 1
   );

-- One row per (track, layout, range-layer item): timing_sectors (S1/S2/S3,
-- every track we have geometry for) and imsa_microsectors / slow_zones
-- (only where a source PDF/config has been curated upstream — currently
-- Watkins Glen microsectors and Le Mans WEC slow zones).
CREATE OR REPLACE TABLE track_atlas_sectors AS
WITH range_layers_unnested AS (
    SELECT
        imsa_slug, series_code, layout_id, length_m AS layout_length_m,
        unnest(from_json(range_layers, '["json"]'), recursive := false) AS range_layer
    FROM track_atlas_layout_choice
),
range_layer_flat AS (
    SELECT
        imsa_slug, series_code, layout_id, layout_length_m,
        json_extract_string(range_layer, '$.id') AS range_layer_id,
        json_extract_string(range_layer, '$.kind') AS kind,
        json_extract(range_layer, '$.items') AS items
    FROM range_layers_unnested
    WHERE json_extract_string(range_layer, '$.kind') IN ('timing_sectors', 'microsectors', 'slow_zones')
),
items_unnested AS (
    SELECT
        imsa_slug, series_code, layout_id, layout_length_m, range_layer_id, kind,
        unnest(from_json(items, '["json"]'), recursive := false) AS item
    FROM range_layer_flat
)
SELECT
    imsa_slug,
    series_code,
    layout_id,
    layout_length_m,
    range_layer_id,
    kind,
    json_extract_string(item, '$.id') AS item_id,
    UPPER(json_extract_string(item, '$.label')) AS label,
    json_extract(item, '$.start')::DOUBLE AS start_frac,
    json_extract(item, '$.end')::DOUBLE AS end_frac,
    -- Explicit length_m on the item wins (microsectors carry it); otherwise
    -- derive it from the lap-fraction span * the layout's total length.
    COALESCE(
        json_extract(item, '$.length_m')::DOUBLE,
        (json_extract(item, '$.end')::DOUBLE - json_extract(item, '$.start')::DOUBLE) * layout_length_m
    ) AS length_m,
    UPPER(json_extract_string(item, '$.entry_ref')) AS entry_ref,
    UPPER(json_extract_string(item, '$.exit_ref')) AS exit_ref
FROM items_unnested;

-- Point markers (T1, FL, Z4, IP1, A7-1, ...) derived from the microsector /
-- slow-zone range items' entry_ref/exit_ref + start/end fractions. This lets
-- 020-event-laps.sql join a CSV microsector column name (e.g. "a71_time",
-- normalized to "A71") to a cumulative-meters marker on the circuit,
-- independent of hyphenation differences between Alkamel's column names and
-- track-atlas's point ids (A7-1 vs a71).
CREATE OR REPLACE TABLE track_atlas_points AS
WITH points AS (
    SELECT imsa_slug, series_code, layout_id, layout_length_m, entry_ref AS point_name, start_frac AS marker
    FROM track_atlas_sectors
    WHERE kind IN ('microsectors', 'slow_zones') AND entry_ref IS NOT NULL
    UNION
    SELECT imsa_slug, series_code, layout_id, layout_length_m, exit_ref AS point_name, end_frac AS marker
    FROM track_atlas_sectors
    WHERE kind IN ('microsectors', 'slow_zones') AND exit_ref IS NOT NULL
),
deduped AS (
    SELECT DISTINCT
        imsa_slug,
        series_code,
        layout_id,
        -- Normalized join key: strip non-alphanumerics, uppercase, so CSV column
        -- names like "a71"/"a8_1" match track-atlas point ids like "A7-1"/"A8-1".
        UPPER(REGEXP_REPLACE(point_name, '[^A-Za-z0-9]', '', 'g')) AS point_key,
        point_name,
        marker,
        layout_length_m
    FROM points
)
-- A point can appear at BOTH marker=0.0 (entry of the first range) and
-- marker=1.0 (exit of the last range) when it's the start/finish line
-- (e.g. Le Mans's "FL"). Per-lap microsector columns always mean "crossing
-- this point during THIS lap", so for that ambiguous case we want the
-- finish-line / end-of-lap position (marker=1.0), not the start position —
-- otherwise every lap's FL crossing would wrongly report meters=0.
SELECT
    imsa_slug,
    series_code,
    layout_id,
    point_key,
    point_name,
    marker,
    ROUND(marker * layout_length_m, 1) AS meters
FROM deduped
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY imsa_slug, series_code, layout_id, point_key
    ORDER BY marker DESC
) = 1;


-- tracks.json) with track-atlas geometry: real lap length, per-sector
-- meters (S1/S2/S3 as a map), and a flag for whether atlas coverage exists
-- at all. `atlas_sector_meters` is a MAP so callers can look up any track's
-- S1/S2/S3 length without a join; per-lap S1/S2/S3-in-meters in `laps` reads
-- from track_atlas_sectors directly keyed by (imsa_slug, series_code).
CREATE OR REPLACE TABLE tracks AS
SELECT
    t.*,
    tal.length_m AS atlas_length_m,
    tal.imsa_slug IS NOT NULL AS has_track_atlas,
    (
        SELECT MAP(LIST(label), LIST(length_m))
        FROM (
            SELECT DISTINCT tas.label, tas.length_m
            FROM track_atlas_sectors tas
            WHERE tas.imsa_slug = tal.imsa_slug
              AND tas.layout_id = tal.layout_id
              AND tas.kind = 'timing_sectors'
        )
    ) AS atlas_sector_meters,
    EXISTS (
        SELECT 1 FROM track_atlas_sectors tas
        WHERE tas.imsa_slug = tal.imsa_slug AND tas.kind = 'microsectors'
    ) AS has_microsector_geometry
FROM (
    -- Re-derive the base tracks table exactly as 000-settings.sql built it,
    -- since CREATE OR REPLACE TABLE tracks there ran before this file.
    SELECT
        unnest.id AS track_id,
        unnest.official_name,
        unnest.short_name,
        unnest.country,
        unnest.latitude,
        unnest.longitude,
        unnest.aliases,
        unnest.length_km
    FROM read_json_auto('tracks.json') j,
         UNNEST(j.tracks)
) t
-- One arbitrary layout per imsa_slug for the has_track_atlas/length_m flags
-- (Sebring's wec/imsa layouts share the same length_m so it's not lossy).
LEFT JOIN (
    SELECT DISTINCT ON (imsa_slug) imsa_slug, layout_id, length_m
    FROM track_atlas_layouts
    ORDER BY imsa_slug, layout_id
) tal ON tal.imsa_slug = t.track_id;

-- Rebuild track_aliases (000-settings.sql's version) since we replaced `tracks`.
CREATE OR REPLACE TABLE track_aliases AS
SELECT
    t.track_id,
    t.short_name,
    UNNEST(t.aliases) AS alias
FROM tracks t;

-- Flag any headline event (from events.json) whose normalized track has NO
-- track-atlas coverage at all, so gaps in sector-meters data are visible
-- instead of silently falling back to NULL.
CREATE OR REPLACE TABLE track_atlas_gaps AS
SELECT DISTINCT
    de.series_code,
    de.year,
    de.event_folder,
    de.display_name,
    normalize_track_name(de.event_folder) AS normalized_track,
    t.track_id
FROM defined_events de
LEFT JOIN tracks t ON t.short_name = normalize_track_name(de.event_folder)
WHERE t.track_id IS NULL OR NOT t.has_track_atlas
ORDER BY de.series_code, de.year, de.event_folder;

SELECT
    COUNT(*) AS events_missing_track_atlas,
    STRING_AGG(DISTINCT track_id, ', ') AS missing_tracks
FROM track_atlas_gaps;
