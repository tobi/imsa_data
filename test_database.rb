#!/usr/bin/env ruby
# Database integrity and data quality tests
# Run with: ruby test_database.rb

require 'minitest/autorun'
require 'open3'
require 'json'

DB_PATH = "output/imsa.duckdb"

class DatabaseTest < Minitest::Test
  def query(sql)
    stdout, stderr, status = Open3.capture3("duckdb", DB_PATH, "-json", "-c", sql)
    raise "Query failed: #{stderr}" unless status.success?
    JSON.parse(stdout)
  end

  def query_single(sql)
    result = query(sql)
    result.first&.values&.first
  end

  # === Database Structure Tests ===

  def test_database_exists
    assert File.exist?(DB_PATH), "Database file should exist at #{DB_PATH}"
  end

  def test_required_tables_exist
    tables = query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'main'")
    table_names = tables.map { |t| t["table_name"] }

    %w[laps drivers seasons tracks events event_metadata].each do |table|
      assert_includes table_names, table, "Table '#{table}' should exist"
    end
  end

  def test_tracks_table_has_required_columns
    columns = query("SELECT column_name FROM information_schema.columns WHERE table_name = 'tracks'")
    column_names = columns.map { |c| c["column_name"] }

    %w[track_id official_name short_name country latitude longitude aliases].each do |col|
      assert_includes column_names, col, "Tracks table should have '#{col}' column"
    end
  end

  def test_events_table_has_required_columns
    columns = query("SELECT column_name FROM information_schema.columns WHERE table_name = 'events'")
    column_names = columns.map { |c| c["column_name"] }

    %w[event_id series_code year track start_date race_duration_minutes avg_air_temp_f dry].each do |col|
      assert_includes column_names, col, "Events table should have '#{col}' column"
    end
  end

  # === Data Quality Tests ===

  def test_tracks_have_valid_coordinates
    invalid = query(<<~SQL)
      SELECT track_id, latitude, longitude
      FROM tracks
      WHERE latitude IS NULL
         OR longitude IS NULL
         OR latitude < -90 OR latitude > 90
         OR longitude < -180 OR longitude > 180
    SQL

    assert_empty invalid, "All tracks should have valid GPS coordinates: #{invalid}"
  end

  def test_tracks_have_aliases
    tracks_without_aliases = query(<<~SQL)
      SELECT track_id FROM tracks WHERE aliases IS NULL OR LENGTH(aliases) = 0
    SQL

    assert_empty tracks_without_aliases, "All tracks should have at least one alias"
  end

  def test_no_duplicate_track_ids
    duplicates = query(<<~SQL)
      SELECT track_id, COUNT(*) as cnt
      FROM tracks
      GROUP BY track_id
      HAVING COUNT(*) > 1
    SQL

    assert_empty duplicates, "Track IDs should be unique: #{duplicates}"
  end

  def test_events_have_valid_event_ids
    invalid = query(<<~SQL)
      SELECT event_id
      FROM events
      WHERE event_id IS NULL
         OR event_id NOT LIKE '%-%-%'
    SQL

    assert_empty invalid, "All events should have valid event_id format (series-year-track)"
  end

  def test_events_reference_valid_tracks
    orphan_events = query(<<~SQL)
      SELECT DISTINCT e.track
      FROM events e
      LEFT JOIN tracks t ON t.short_name = e.track
      WHERE t.track_id IS NULL AND e.track IS NOT NULL
    SQL

    assert_empty orphan_events, "All event tracks should exist in tracks table: #{orphan_events}"
  end

  def test_laps_have_required_fields
    null_check = query(<<~SQL)
      SELECT COUNT(*) as cnt
      FROM laps
      WHERE series_code IS NULL
         OR year IS NULL
         OR event IS NULL
         OR session IS NULL
    SQL

    assert_equal 0, null_check.first["cnt"], "Laps should have series_code, year, event, and session"
  end

  def test_lap_times_are_positive
    # A lap includes time stopped in the pits/red flags; ten minutes is not an
    # upper physical bound. Keep authentic long laps, reject nonpositive timing.
    assert_equal 0, query_single("SELECT COUNT(*) FROM laps WHERE lap_time <= 0")
    assert_equal 0, query_single("SELECT COUNT(*) FROM laps WHERE lap_time < 30")
  end

  def test_duration_parser_preserves_missing_and_long_times
    {nil => nil, '' => nil, '-' => nil, 'bad' => nil, '1:60.000' => nil,
     '1:02:60.000' => nil, '-1.000' => nil, '0' => 0,
     '4.074' => 4.074, '1:20.638' => 80.638, '25:51.654' => 1551.654,
     '60:00.000' => 3600, '24:01:02.345' => 86462.345,
     ' 1:02:03 ' => 3723, '23:59:59.000' => 86399}.each do |raw, expected|
      literal = raw.nil? ? 'NULL' : "'#{raw}'"
      actual = query_single("SELECT parse_time(#{literal})")
      if expected.nil?
        assert_nil actual, "Missing/invalid #{raw.inspect} must not become a duration"
      else
        assert_in_delta expected, actual.to_f, 0.0001, raw.inspect
      end
    end
  end

  def test_recorded_long_pit_lap_is_preserved
    # Source: 202601241340-race-hour-24-laps.csv, car 11, lap 102:
    # LAP_TIME=12:18.929, PIT_TIME=0:10:52.239. Do not trim authentic delays.
    rows = query(<<~SQL)
      SELECT lap_time, pit_time FROM laps
      WHERE series_code = 'imsa' AND year = '2026' AND event = 'Daytona'
        AND session = 'race' AND car = '11' AND lap = 102
    SQL
    assert_equal 1, rows.size
    assert_in_delta 738.929, rows.first['lap_time'].to_f, 0.0001
    assert_in_delta 652.239, rows.first['pit_time'].to_f, 0.0001
  end

  def test_weather_temperatures_are_reasonable
    unreasonable = query(<<~SQL)
      SELECT COUNT(*) as cnt
      FROM event_weather
      WHERE air_temp_f IS NOT NULL
        AND (air_temp_f < 0 OR air_temp_f > 130)
    SQL

    assert_equal 0, unreasonable.first["cnt"], "Air temperatures should be between 0-130°F"
  end

  # === Data Completeness Tests ===

  def test_minimum_tracks_exist
    track_count = query_single("SELECT COUNT(*) FROM tracks")
    assert track_count >= 30, "Should have at least 30 tracks, found #{track_count}"
  end

  def test_minimum_events_exist
    event_count = query_single("SELECT COUNT(*) FROM events WHERE start_date IS NOT NULL")
    assert event_count >= 50, "Should have at least 50 events with dates, found #{event_count}"
  end

  def test_minimum_drivers_exist
    driver_count = query_single("SELECT COUNT(*) FROM drivers")
    assert driver_count >= 500, "Should have at least 500 drivers, found #{driver_count}"
  end

  def test_minimum_laps_exist
    lap_count = query_single("SELECT COUNT(*) FROM laps")
    assert lap_count >= 100000, "Should have at least 100,000 laps, found #{lap_count}"
  end

  def test_multiple_series_exist
    series = query("SELECT DISTINCT series_code FROM laps")
    series_codes = series.map { |s| s["series_code"] }

    assert_includes series_codes, "imsa", "Should have IMSA data"
    assert series_codes.length >= 2, "Should have at least 2 series, found: #{series_codes.join(', ')}"
  end

  def test_multiple_years_exist
    years = query("SELECT DISTINCT year FROM laps ORDER BY year")
    year_list = years.map { |y| y["year"] }

    assert year_list.length >= 3, "Should have at least 3 years of data, found: #{year_list.join(', ')}"
  end

  # === Referential Integrity Tests ===

  def test_laps_reference_valid_events
    orphan_laps = query(<<~SQL)
      SELECT DISTINCT l.series_code, l.year, l.event, l.event_id
      FROM laps l LEFT JOIN events e ON e.event_id = l.event_id
      WHERE e.event_id IS NULL OR e.event <> l.event
    SQL
    assert_empty orphan_laps, "Every lap must reference its exact event: #{orphan_laps}"
  end

  def test_event_ids_are_unique
    assert_empty query("SELECT event_id FROM events GROUP BY event_id HAVING COUNT(*) > 1")
  end

  def test_event_session_counts
    assert_empty query(<<~SQL)
      WITH counts AS (
        SELECT event_id, COUNT(DISTINCT session_id) AS sessions,
          COUNT(DISTINCT session_id) FILTER (WHERE session = 'race') AS races
        FROM laps GROUP BY event_id
      )
      SELECT e.event_id FROM events e JOIN counts c USING (event_id)
      WHERE e.session_count IS DISTINCT FROM c.sessions
         OR e.race_count IS DISTINCT FROM c.races
    SQL
  end

  def test_events_have_weather_data_when_observations_exist
    # Coverage is source-dependent. Check every aggregate against the actual
    # observations at the event-folder grain, including explicitly missing data.
    assert_empty query(<<~SQL)
      WITH expected AS (
        SELECT series_code, year, event_folder, COUNT(*) AS readings,
          COUNT(air_temp_f) AS usable, ROUND(AVG(air_temp_f), 1) AS air,
          BOOL_OR(raining) AS rain
        FROM event_weather GROUP BY series_code, year, event_folder
      )
      SELECT e.event_id FROM events e LEFT JOIN expected w
        USING (series_code, year, event_folder)
      WHERE e.avg_air_temp_f IS DISTINCT FROM w.air
         OR e.weather_readings <> COALESCE(w.readings, 0)
         OR e.air_temp_readings <> COALESCE(w.usable, 0)
         OR e.had_rain IS DISTINCT FROM w.rain
         OR e.dry IS DISTINCT FROM NOT w.rain
         OR e.weather_status IS DISTINCT FROM
           CASE WHEN w.readings IS NULL THEN 'no_observations'
                WHEN w.usable = 0 THEN 'no_usable_air_temperature'
                ELSE 'available' END
    SQL
    # Retain a broad ingestion smoke check as well as exact per-event joins.
    assert_operator query_single("SELECT COUNT(*) FROM events WHERE weather_status = 'available' AND start_date IS NOT NULL"), :>, 50
  end

  # === Track Alias Tests ===

  def test_track_aliases_are_unique
    # Each alias should map to only one track
    duplicate_aliases = query(<<~SQL)
      WITH expanded AS (
        SELECT track_id, UNNEST(aliases) as alias FROM tracks
      )
      SELECT alias, COUNT(DISTINCT track_id) as track_count
      FROM expanded
      GROUP BY alias
      HAVING COUNT(DISTINCT track_id) > 1
    SQL

    assert_empty duplicate_aliases, "Each alias should map to only one track: #{duplicate_aliases}"
  end

  def test_normalize_track_name_works
    # Test that the normalize function can find tracks
    result = query(<<~SQL)
      SELECT normalize_track_name('02-daytona-international-speedway') as track
    SQL

    assert_equal "Daytona", result.first["track"]
  end
end

class EventsJsonTest < Minitest::Test
  def test_events_json_files_exist
    json_files = Dir["data/*/*/events.json"]
    assert json_files.length >= 5, "Should have at least 5 events.json files, found #{json_files.length}"
  end

  def test_events_json_is_valid
    Dir["data/*/*/events.json"].each do |file|
      content = File.read(file)
      events = JSON.parse(content)

      assert events.is_a?(Array), "#{file} should contain an array"

      events.each do |event|
        assert event["event_number"], "#{file}: event should have event_number"
        assert event["event_name"], "#{file}: event should have event_name"
        assert event["event_folder"], "#{file}: event should have event_folder"
      end
    end
  end
end

class TracksJsonTest < Minitest::Test
  def setup
    @tracks = JSON.parse(File.read("tracks.json"))["tracks"]
  end

  def test_tracks_json_exists
    assert File.exist?("tracks.json"), "tracks.json should exist"
  end

  def test_tracks_json_is_valid
    assert @tracks.is_a?(Array), "tracks.json should contain an array of tracks"
    assert @tracks.length >= 30, "Should have at least 30 tracks"
  end

  def test_each_track_has_required_fields
    @tracks.each do |track|
      assert track["id"], "Track should have id: #{track}"
      assert track["official_name"], "Track should have official_name: #{track["id"]}"
      assert track["short_name"], "Track should have short_name: #{track["id"]}"
      assert track["country"], "Track should have country: #{track["id"]}"
      assert track["latitude"], "Track should have latitude: #{track["id"]}"
      assert track["longitude"], "Track should have longitude: #{track["id"]}"
      assert track["aliases"]&.is_a?(Array), "Track should have aliases array: #{track["id"]}"
      assert track["aliases"].length >= 1, "Track should have at least 1 alias: #{track["id"]}"
    end
  end

  def test_no_duplicate_track_ids
    ids = @tracks.map { |t| t["id"] }
    assert_equal ids.length, ids.uniq.length, "Track IDs should be unique"
  end

  def test_coordinates_are_valid
    @tracks.each do |track|
      lat = track["latitude"]
      lon = track["longitude"]

      assert lat >= -90 && lat <= 90, "#{track["id"]}: latitude #{lat} out of range"
      assert lon >= -180 && lon <= 180, "#{track["id"]}: longitude #{lon} out of range"
    end
  end
end

# === Driver identity: ids must resolve identically at every pipeline stage ===
class DriverIdentityTest < Minitest::Test
  # The pipeline's own SQL macros, so the tests can't drift from it
  FOLD_SQL = "driver_canonical_form(driver_id)".freeze
  MATCH_KEY_SQL = "driver_match_key(driver_id)".freeze

  def query(sql)
    stdout, stderr, status = Open3.capture3("duckdb", DB_PATH, "-json", "-c", sql)
    raise "Query failed: #{stderr}" unless status.success?
    JSON.parse(stdout)
  end

  def query_single(sql)
    query(sql).first&.values&.first
  end

  def aliases
    @aliases ||= JSON.parse(File.read("driver_aliases.json"))
  end

  def test_alias_graph_has_no_cycles
    map = aliases.each_with_object({}) { |a, h| h[a["alias"]] = a["canonical_id"] }
    cyclic = map.select { |_alias, canonical| map.key?(canonical) }
    assert_empty cyclic.keys,
                 "driver_aliases.json canonical_ids must not themselves be aliases " \
                 "(a -> b -> a never converges): #{cyclic.inspect}"
  end

  def test_alias_keys_are_unique
    keys = aliases.map { |a| a["alias"] }
    dupes = keys.group_by { |k| k }.select { |_k, v| v.length > 1 }.keys
    assert_empty dupes, "Duplicate alias keys in driver_aliases.json: #{dupes.inspect}"
  end

  def test_driver_ids_are_ascii_lowercase
    bad = query(<<~SQL)
      SELECT driver_id FROM drivers_v
      WHERE driver_id <> lower(driver_id)
         OR NOT regexp_matches(driver_id, '^[a-z0-9 .''-]+$')
      LIMIT 10
    SQL
    assert_empty bad.map { |r| r["driver_id"] },
                 "driver_ids must be ascii lowercase (diacritics folded)"
  end

  def test_no_diacritic_duplicate_identities
    dupes = query(<<~SQL)
      WITH k AS (SELECT driver_id, #{FOLD_SQL} AS mk FROM drivers_v)
      SELECT mk, list(driver_id) AS ids FROM k GROUP BY mk HAVING count(*) > 1
    SQL
    assert_empty dupes, "driver_ids differing only by accents or case must be merged: #{dupes.inspect}"
  end

  def test_hyphenation_is_not_folded_into_ids
    # Hyphens are part of established ids and are the JSON's editorial call,
    # so the pipeline must not rewrite them on its own.
    hyphenated = query("SELECT driver_id FROM drivers_v WHERE driver_id LIKE '%-%'")
    refute_empty hyphenated, "hyphenated driver_ids should survive folding"
    assert_includes hyphenated.map { |r| r["driver_id"] }, "ryan hunter-reay"
  end

  def test_resolution_is_idempotent
    # No driver_id may itself be an alias key: that would mean a second pass
    # over the alias graph moves the identity again.
    leaked = query(<<~SQL)
      SELECT d.driver_id
      FROM drivers_v d
      JOIN driver_identity_map m ON m.match_key = #{MATCH_KEY_SQL}
      WHERE m.canonical_id <> d.driver_id
      LIMIT 10
    SQL
    assert_empty leaked.map { |r| r["driver_id"] },
                 "driver_ids that still resolve to some other id (alias applied too late)"
  end

  def test_driver_ids_agree_across_surfaces
    # Every identity that raced must exist with the same id in each surface
    # that exposes drivers: laps, event_driver_summary, drivers_v, driver_elo.
    %w[event_driver_summary drivers_v driver_elo].each do |surface|
      missing = query(<<~SQL)
        SELECT DISTINCT l.driver_id
        FROM laps l
        WHERE (l.session = 'race' OR l.session LIKE 'race-hour-%')
          AND l.driver_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM #{surface} s WHERE s.driver_id = l.driver_id)
        LIMIT 10
      SQL
      # driver_elo only covers classes it can rate, so allow a shortfall there
      next if surface == "driver_elo"

      assert_empty missing.map { |r| r["driver_id"] },
                   "race-lap driver_ids missing from #{surface}"
    end
  end

  def test_known_alias_merges_are_applied
    # Curated alias in driver_aliases.json: benjamin hanley -> ben hanley
    ids = query("SELECT driver_id FROM drivers_v WHERE #{FOLD_SQL} LIKE '%hanley'").map { |r| r["driver_id"] }
    assert_equal ["ben hanley"], ids, "ben/benjamin hanley must be one identity"
  end

  def test_diacritic_variants_merge_without_an_alias
    # No alias entry exists for Lotterer: folding alone must merge these.
    ids = query("SELECT driver_id FROM drivers_v WHERE #{FOLD_SQL} = 'andre lotterer'").map { |r| r["driver_id"] }
    assert_equal ["andre lotterer"], ids, "andre/andré lotterer must be one identity"
  end

  def test_distinct_drivers_are_not_over_merged
    # jon/jonathan miller were reviewed and deliberately kept separate (see
    # doc/driver-merge-review-2026-08.md); no alias exists, and folding alone
    # must not merge them.
    ids = query("SELECT driver_id FROM drivers_v WHERE driver_id IN ('jon miller', 'jonathan miller')").map { |r| r["driver_id"] }.sort
    assert_equal ["jon miller", "jonathan miller"], ids
  end

  # --- DI1 curation fixtures (doc/driver-merge-review-2026-08.md) ---------
  # Three merges from the 2026-08 duplicate-identity review, one per class of
  # evidence, so a regression in the alias file or the resolver is caught.

  def test_nickname_merge_conway
    # michael conway -> mike conway. Complementary seasons (2021-2025 vs 2026),
    # same team (Toyota), never co-occurring in a session.
    ids = query("SELECT driver_id FROM drivers_v WHERE driver_id LIKE '%conway'").map { |r| r["driver_id"] }
    assert_includes ids, "mike conway"
    refute_includes ids, "michael conway", "michael/mike conway must be one identity"
    # ... but Kevin Conway raced against Mike Conway and must stay separate.
    assert_includes ids, "kevin conway"
  end

  def test_middle_name_superset_merge_andrade
    # rui pinto de andrade -> rui andrade, and the laps must be summed, not lost.
    rows = query("SELECT driver_id, total_laps FROM drivers_v WHERE driver_id LIKE '%andrade'")
    assert_equal ["rui andrade"], rows.map { |r| r["driver_id"] }
    assert_equal 3316, rows.first["total_laps"].to_i,
                 "merged career laps must equal 2410 + 906"
  end

  def test_suffix_variant_merge_does_not_swallow_a_relative
    # 'Horst Felbermayr JR' was split across two ids ('horst felbermayr' and
    # 'horst jr felbermayr') that never co-occur -> merged. His relative
    # 'Horst Felix Felbermayr' co-occurs with him (31 sessions / 33 hand-overs pre-merge; 40/46 post-merge) -> kept apart.
    ids = query("SELECT driver_id FROM drivers_v WHERE driver_id LIKE '%felbermayr'").map { |r| r["driver_id"] }
    assert_equal ["horst felbermayr", "horst felix felbermayr"].sort, ids.sort
  end
end

if __FILE__ == $0
  # Run with verbose output
  Minitest.run(ARGV + ["--verbose"])
end
