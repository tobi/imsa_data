#!/usr/bin/env ruby
# Database linting script - comprehensive checks for data quality
# Run with: ruby lint/check_database.rb

require 'open3'
require 'json'
require 'set'

DB_PATH = "output/imsa.duckdb"

class DatabaseLinter
  def initialize
    @errors = []
    @warnings = []
    @info = []
  end

  def query(sql)
    stdout, stderr, status = Open3.capture3("duckdb", DB_PATH, "-json", "-c", sql)
    raise "Query failed: #{stderr}\nSQL: #{sql}" unless status.success?
    JSON.parse(stdout)
  rescue JSON::ParserError
    []
  end

  def query_single(sql)
    result = query(sql)
    result.first&.values&.first
  end

  def error(msg)
    @errors << msg
    puts "❌ ERROR: #{msg}"
  end

  def warn(msg)
    @warnings << msg
    puts "⚠️  WARNING: #{msg}"
  end

  def info(msg)
    @info << msg
    puts "ℹ️  INFO: #{msg}"
  end

  def ok(msg)
    puts "✅ #{msg}"
  end

  def section(title)
    puts "\n--- #{title} ---"
  end

  def run_all_checks
    puts "=" * 60
    puts "MotorsportDB Linting: #{DB_PATH}"
    puts "=" * 60
    puts

    unless File.exist?(DB_PATH)
      error "Database file not found: #{DB_PATH}"
      error "Run 'rake db:update' first"
      return summary
    end

    # Schema checks
    check_required_tables
    check_required_columns

    # CSV file checks
    check_csv_headers

    # Track & location checks
    check_unknown_tracks
    check_duplicate_aliases
    check_missing_coordinates

    # Event checks
    check_missing_events_json
    check_undefined_event_folders
    check_series_season_coverage
    check_orphan_events
    check_missing_weather
    check_missing_race_data

    # Chassis & homologation checks
    check_unknown_chassis
    check_similar_chassis
    check_unknown_homologation
    check_manufacturer_coverage

    # Row uniqueness
    check_duplicate_laps

    # Name consistency
    check_driver_name_variants
    check_team_name_variants

    # Data quality checks
    check_rain_plausibility
    check_lap_time_outliers
    check_temperature_outliers
    check_pit_time_outliers
    check_bpillar_populated
    check_race_coverage_plausibility

    # Driver checks
    check_driver_license_distribution
    check_missing_licenses

    # Session type consistency
    check_session_type_consistency
    check_race_events_have_qualifying
    check_single_race_per_event
    check_race_results_presence

    # Tire age estimation sanity
    check_tire_allocation

    # Class normalization
    check_class_normalization

    # Coverage summary
    coverage_summary

    summary
  end

  def check_required_tables
    section "Checking required tables"
    required = %w[laps drivers tracks chassis_homologation main_classes seasons events]

    existing = query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'main'").map { |r| r['table_name'] }

    missing = required - existing
    if missing.empty?
      ok "All required tables exist"
    else
      missing.each { |t| error "Missing table: #{t}" }
    end
  end

  def check_required_columns
    section "Checking required columns in laps table"
    required = %w[series_code year event session car class driver_name lap lap_time chassis homologation manufacturer]

    existing = query("SELECT column_name FROM information_schema.columns WHERE table_name = 'laps'").map { |r| r['column_name'] }

    missing = required - existing
    if missing.empty?
      ok "All required columns exist in laps"
    else
      missing.each { |c| error "Missing column in laps: #{c}" }
    end
  end

  def check_csv_headers
    section "Checking CSV file headers match expected patterns"

    # Expected headers for each file type
    expected_headers = {
      'laps' => ['NUMBER', 'DRIVER_NUMBER', 'LAP_NUMBER', 'LAP_TIME'],
      'results' => ['POSITION', 'NUMBER', 'TEAM'],
      'weather' => ['TIME_UTC', 'AIR_TEMP', 'TRACK_TEMP']
    }

    mismatched = []

    Dir.glob("data/*/*/*/*.csv").each do |file|
      # Determine expected type from filename
      type = case File.basename(file)
             when /-laps\.csv$/i then 'laps'
             when /-results\.csv$/i then 'results'
             when /-weather\.csv$/i then 'weather'
             else next
             end

      begin
        # Read first line (header)
        header = File.open(file, &:readline).strip.upcase

        expected = expected_headers[type]
        has_expected = expected.all? { |col| header.include?(col) }

        unless has_expected
          # Check if it's a different type misnamed
          actual_type = expected_headers.find { |t, cols| cols.all? { |c| header.include?(c) } }&.first

          if actual_type && actual_type != type
            mismatched << {
              file: file.sub('data/', ''),
              named_as: type,
              actually: actual_type,
              header_sample: header[0..80]
            }
          elsif header.include?('POSITION') && header.include?('TEAM') && type == 'laps'
            # Common case: results file named as laps
            mismatched << {
              file: file.sub('data/', ''),
              named_as: type,
              actually: 'results',
              header_sample: header[0..80]
            }
          end
        end
      rescue => e
        warn "Could not read #{file}: #{e.message}"
      end
    end

    if mismatched.empty?
      ok "All CSV files have headers matching their file type"
    else
      mismatched.each do |m|
        error "File type mismatch: #{m[:file]} named as '#{m[:named_as]}' but has '#{m[:actually]}' headers"
      end
    end
  end

  def check_unknown_tracks
    section "Checking for unknown tracks"
    begin
      unknown = query(<<~SQL)
        WITH all_folders AS (
          SELECT DISTINCT event_folder
          FROM read_json_auto('data/*/*/events.json')
        ),
        known AS (
          SELECT DISTINCT UNNEST(aliases) as alias FROM tracks
        )
        SELECT af.event_folder
        FROM all_folders af
        WHERE NOT EXISTS (
          SELECT 1 FROM known k WHERE af.event_folder ILIKE '%' || k.alias || '%'
        )
        ORDER BY af.event_folder
      SQL

      if unknown.empty?
        ok "All event folders map to known tracks"
      else
        unknown.each do |row|
          error "Unknown track: #{row['event_folder']} - add to tracks.json"
        end
      end
    rescue => e
      warn "Could not check unknown tracks: #{e.message}"
    end
  end

  def check_missing_events_json
    section "Checking for missing events.json"
    data_dirs = Dir["data/*/*"].select { |d| File.directory?(d) }
    year_dirs = data_dirs.map { |d| File.dirname(d) }.uniq

    missing = year_dirs.reject { |d| File.exist?(File.join(d, "events.json")) }

    if missing.empty?
      ok "All series/year directories have events.json"
    else
      missing.each { |d| warn "Missing events.json: #{d}" }
    end
  end

  def check_duplicate_aliases
    section "Checking for duplicate track aliases"
    duplicates = query(<<~SQL)
      WITH expanded AS (
        SELECT track_id, short_name, UNNEST(aliases) as alias FROM tracks
      )
      SELECT alias, STRING_AGG(track_id, ', ') as tracks, COUNT(*) as cnt
      FROM expanded
      GROUP BY alias
      HAVING COUNT(*) > 1
    SQL

    if duplicates.empty?
      ok "No duplicate aliases found"
    else
      duplicates.each do |row|
        error "Duplicate alias '#{row['alias']}' used by: #{row['tracks']}"
      end
    end
  end

  def check_missing_coordinates
    section "Checking tracks for missing coordinates"
    missing = query(<<~SQL)
      SELECT track_id, official_name
      FROM tracks
      WHERE latitude IS NULL OR longitude IS NULL
    SQL

    if missing.empty?
      ok "All tracks have coordinates"
    else
      missing.each do |row|
        error "Missing coordinates: #{row['track_id']} (#{row['official_name']})"
      end
    end
  end

  def excluded_patterns_by_series
    # Per-series "intentionally excluded" fnmatch globs (tests, ROAR, prologues)
    # read from data/<series>/events.json -> excluded_event_patterns.
    @excluded_patterns_by_series ||= begin
      h = {}
      Dir.glob("data/*/events.json").each do |f|
        series = f[%r{^data/([^/]+)/events\.json$}, 1]
        begin
          h[series] = JSON.parse(File.read(f))['excluded_event_patterns'] || []
        rescue
          h[series] = []
        end
      end
      h
    end
  end

  # Every (series, year, slug, dir) folder on disk that carries timing data and
  # is not intentionally excluded. Shared by the folder-level and year-level
  # coverage checks so they can never disagree about what "has data" means.
  def event_folders_with_data
    @event_folders_with_data ||= Dir.glob("data/*/*/*").select { |d| File.directory?(d) }.filter_map do |dir|
      m = dir.match(%r{^data/([^/]+)/(\d{4})/\d\d-(.+)$})
      next unless m
      series, year, slug = m[1], m[2], m[3]
      has_data = !Dir.glob(File.join(dir, "*-laps.csv")).empty? ||
                 !Dir.glob(File.join(dir, "*-results.csv")).empty?
      next unless has_data
      next if (excluded_patterns_by_series[series] || []).any? { |p| File.fnmatch(p, slug) }
      [series, year, slug, dir]
    end
  end

  def check_undefined_event_folders
    section "Checking for event folders with data but no events.json entry"
    # Any folder under data/<series>/<year>/NN-<slug>/ that contains lap or
    # results CSVs MUST be registered in defined_events (sourced from the
    # curated data/<series>/events.json). Otherwise the build SILENTLY drops
    # every lap in that folder — exactly the Watkins Glen 2026 failure mode.
    # This is a HARD error so `rake` fails loudly instead of ignoring new data.
    defined = query(<<~SQL)
      SELECT series_code, year, event_folder FROM defined_events
    SQL
    defined_set = defined.map { |r| [r['series_code'], r['year'].to_s, r['event_folder']] }.to_set

    undefined = event_folders_with_data.reject do |series, year, slug, _dir|
      defined_set.include?([series, year, slug])
    end

    if undefined.empty?
      ok "Every event folder with lap/results data is registered in events.json"
    else
      undefined.sort.each do |series, year, slug, dir|
        error "Undefined event with data: #{dir} — add {\"year\":\"#{year}\",\"folder\":\"#{slug}\",\"name\":\"...\"} to data/#{series}/events.json (its laps are being DROPPED)"
      end
    end
  end

  # Catches the failure mode the folder-level check CANNOT see: a season that
  # was never scraped at all. If nothing was ever downloaded there is no folder
  # on disk, so check_undefined_event_folders has nothing to flag and the DB
  # just quietly lacks a whole series-year. This is how ELMS 2026 went missing
  # for months while imsa/wec/alms all carried 2026 data.
  #
  # Two independent signals, both offline (no network):
  #   1. HARD ERROR — a series-year has data folders on disk but ZERO laps in
  #      the DB. Means the allowlist/build dropped an entire season.
  #   2. WARNING — a series' newest season lags the newest season any other
  #      series has. Means that series is probably not being imported at all.
  def check_series_season_coverage
    section "Checking for missing/stale series seasons"

    db_rows = query(<<~SQL)
      SELECT series_code, year, COUNT(*) AS laps
      FROM laps
      GROUP BY series_code, year
    SQL

    if db_rows.empty?
      error "No laps in the database at all — every series is missing"
      return
    end

    db_year_set = db_rows.map { |r| [r['series_code'], r['year'].to_s] }.to_set

    # --- Signal 1: whole season on disk but absent from the DB ---
    disk_years = event_folders_with_data.map { |series, year, _slug, _dir| [series, year] }.uniq
    dropped = disk_years.reject { |series, year| db_year_set.include?([series, year]) }

    if dropped.empty?
      ok "Every series-year with data on disk is present in the database"
    else
      dropped.sort.each do |series, year|
        n = event_folders_with_data.count { |s, y, _sl, _d| s == series && y == year }
        error "Whole season dropped: #{series} #{year} has #{n} event folder(s) with data on disk but 0 laps in the DB — check data/#{series}/events.json has #{year} entries"
      end
    end

    # --- Signal 2: a series' newest season lags the rest ---
    max_year_by_series = db_rows.group_by { |r| r['series_code'] }
                                .transform_values { |rs| rs.map { |r| r['year'].to_i }.max }
    global_max = max_year_by_series.values.max
    stale = max_year_by_series.select { |_s, y| y < global_max }

    if stale.empty?
      ok "Every series has data for the newest season on record (#{global_max})"
    else
      stale.sort.each do |series, year|
        warn "Stale series: #{series} has no #{global_max} data (newest is #{year}) while other series do — is it being imported? Try: ruby import.rb --series #{series} --year #{global_max}"
      end
    end
  end

  def check_orphan_events
    section "Checking for orphan events (no lap data)"
    orphans = query(<<~SQL)
      SELECT e.event_id, e.event_name, e.track
      FROM events e
      WHERE e.start_date IS NULL AND e.track IS NOT NULL
      ORDER BY e.event_id
      LIMIT 20
    SQL

    if orphans.empty?
      ok "All events have associated lap data"
    else
      info "#{orphans.length} events without lap data (support series, tests)"
    end
  end

  def check_missing_weather
    section "Checking for events without weather data"
    missing = query(<<~SQL)
      SELECT e.event_id, e.event_name
      FROM events e
      WHERE e.start_date IS NOT NULL AND e.avg_air_temp_f IS NULL
      LIMIT 10
    SQL

    if missing.empty?
      ok "All events with lap data have weather data"
    else
      missing.each do |row|
        warn "No weather data: #{row['event_id']}"
      end
    end
  end

  def check_missing_race_data
    section "Checking for events without race sessions"
    missing = query(<<~SQL)
      SELECT e.event_id, e.session_count
      FROM events e
      WHERE e.start_date IS NOT NULL AND e.race_count = 0
    SQL

    if missing.empty?
      ok "All events have race data"
    else
      missing.each do |row|
        info "No race session: #{row['event_id']} (#{row['session_count']} sessions)"
      end
    end
  end

  def check_unknown_chassis
    section "Checking for unknown chassis"
    unknown = query(<<~SQL)
      SELECT DISTINCT chassis, COUNT(*) as laps
      FROM laps
      WHERE homologation = 'Unknown' OR homologation IS NULL
      GROUP BY chassis
      ORDER BY laps DESC
      LIMIT 10
    SQL

    if unknown.empty?
      ok "All chassis have homologation data"
    else
      unknown.each do |row|
        error "Unknown chassis: '#{row['chassis']}' (#{row['laps']} laps) - add to chassis.json"
      end
    end
  end

  def levenshtein_distance(a, b)
    return b.length if a.empty?
    return a.length if b.empty?

    prev_row = (0..b.length).to_a
    a.each_char.with_index(1) do |char_a, i|
      current_row = [i]
      b.each_char.with_index(1) do |char_b, j|
        insert_cost = current_row[j - 1] + 1
        delete_cost = prev_row[j] + 1
        replace_cost = prev_row[j - 1] + (char_a == char_b ? 0 : 1)
        current_row << [insert_cost, delete_cost, replace_cost].min
      end
      prev_row = current_row
    end

    prev_row.last
  end

  def check_similar_chassis
    section "Checking for similar chassis names"
    chassis_rows = query("SELECT DISTINCT chassis FROM laps WHERE chassis IS NOT NULL ORDER BY chassis")
    chassis_list = chassis_rows.map { |row| row['chassis'] }

    pairs = []
    chassis_list.each_with_index do |left, i|
      (i + 1...chassis_list.length).each do |j|
        right = chassis_list[j]
        distance = levenshtein_distance(left.downcase, right.downcase)
        if distance <= 2
          pairs << [left, right, distance]
        end
      end
    end

    if pairs.empty?
      ok "No near-duplicate chassis names"
    else
      pairs.sort_by! { |(_, _, distance)| distance }
      pairs.first(20).each do |left, right, distance|
        warn "Similar chassis names: '#{left}' vs '#{right}' (distance #{distance})"
      end
    end
  end

  def check_unknown_homologation
    section "Checking homologation coverage"
    coverage = query(<<~SQL)
      SELECT
        homologation,
        COUNT(DISTINCT chassis) as chassis_count,
        COUNT(*) as lap_count
      FROM laps
      WHERE homologation IS NOT NULL
      GROUP BY homologation
      ORDER BY lap_count DESC
    SQL

    if coverage.empty?
      error "No homologation data found"
    else
      info "Homologation coverage:"
      coverage.each do |row|
        info "  #{row['homologation']}: #{row['chassis_count']} chassis, #{row['lap_count']} laps"
      end
    end
  end

  def check_manufacturer_coverage
    section "Checking manufacturer coverage"
    unknown = query(<<~SQL)
      SELECT DISTINCT manufacturer, chassis, COUNT(*) as laps
      FROM laps
      WHERE manufacturer = 'Unknown' OR manufacturer IS NULL
      GROUP BY manufacturer, chassis
      ORDER BY laps DESC
      LIMIT 5
    SQL

    if unknown.empty?
      ok "All chassis have manufacturer data"
    else
      unknown.each do |row|
        warn "Unknown manufacturer for '#{row['chassis']}' (#{row['laps']} laps)"
      end
    end
  end

  def check_duplicate_laps
    section "Checking for duplicate rows in laps table"

    # (session_id, car, lap) should be unique — each car completes each lap once
    duplicates = query(<<~SQL)
      SELECT series_code, year, event, session, session_id,
        COUNT(*) as total_rows,
        COUNT(*) - COUNT(DISTINCT car || '|' || lap::VARCHAR) as duplicate_rows
      FROM laps
      GROUP BY series_code, year, event, session, session_id
      HAVING COUNT(*) > COUNT(DISTINCT car || '|' || lap::VARCHAR)
      ORDER BY duplicate_rows DESC
      LIMIT 10
    SQL

    if duplicates.empty?
      ok "No duplicate rows in laps table (unique on session_id, car, lap)"
    else
      total_dupes = duplicates.sum { |r| r['duplicate_rows'].to_i }
      duplicates.each do |row|
        error "#{row['duplicate_rows']} duplicate rows: #{row['series_code']}/#{row['year']}/#{row['event']}/#{row['session']} (session_id=#{row['session_id']})"
      end
    end
  end

  def check_driver_name_variants
    section "Checking for inconsistent driver display names"

    # Each driver_id should map to exactly one driver_name across all laps.
    # Multiple variants (e.g. "Nick Boulle" vs "Nicholas BOULLE") indicate
    # the canonical name resolution or alias system has gaps.
    variants = query(<<~SQL)
      SELECT driver_id,
        LIST(DISTINCT driver_name ORDER BY driver_name) AS variants,
        COUNT(DISTINCT driver_name) AS variant_count
      FROM laps
      GROUP BY driver_id
      HAVING COUNT(DISTINCT driver_name) > 1
      ORDER BY variant_count DESC, driver_id
      LIMIT 20
    SQL

    if variants.empty?
      ok "All drivers have a single consistent display name"
    else
      variants.each do |row|
        names = row['variants']
        error "Driver '#{row['driver_id']}' has #{row['variant_count']} display name variants: #{names}"
      end
    end
  end

  def check_team_name_variants
    section "Checking for inconsistent team display names"

    variants = query(<<~SQL)
      SELECT
        LOWER(REGEXP_REPLACE(team_name, '\\s+', ' ')) AS team_key,
        LIST(DISTINCT team_name ORDER BY team_name) AS variants,
        COUNT(DISTINCT team_name) AS variant_count
      FROM laps
      WHERE team_name IS NOT NULL
      GROUP BY team_key
      HAVING COUNT(DISTINCT team_name) > 1
      ORDER BY variant_count DESC
      LIMIT 20
    SQL

    if variants.empty?
      ok "All teams have a single consistent display name"
    else
      variants.each do |row|
        error "Team '#{row['team_key']}' has #{row['variant_count']} name variants: #{row['variants']}"
      end
    end
  end

  def check_lap_time_outliers
    section "Checking for lap time outliers"
    outliers = query(<<~SQL)
      SELECT
        series_code, year, event, session,
        COUNT(*) as outlier_count
      FROM laps
      WHERE lap_time IS NOT NULL AND (lap_time < 30 OR lap_time > 600)
      GROUP BY series_code, year, event, session
      HAVING COUNT(*) > 10
      ORDER BY outlier_count DESC
      LIMIT 5
    SQL

    if outliers.empty?
      ok "No significant lap time outliers"
    else
      outliers.each do |row|
        warn "Lap time outliers: #{row['series_code']}/#{row['year']}/#{row['event']}/#{row['session']} (#{row['outlier_count']} laps)"
      end
    end
  end

  def check_rain_plausibility
    section "Checking rain data plausibility"
    # If >90% of a series' readings are "raining", the rain column is likely inverted
    rain_stats = query(<<~SQL)
      SELECT series_code,
        COUNT(*) as total,
        COUNT(CASE WHEN raining THEN 1 END) as rain_count,
        ROUND(100.0 * COUNT(CASE WHEN raining THEN 1 END) / COUNT(*), 1) as rain_pct
      FROM event_weather
      GROUP BY series_code
      HAVING COUNT(*) > 100
    SQL

    rain_stats.each do |row|
      pct = row['rain_pct'].to_f
      if pct > 80
        error "#{row['series_code']}: #{pct}% of weather readings show rain (#{row['rain_count']}/#{row['total']}) — rain column likely inverted or miscoded"
      elsif pct > 50
        warn "#{row['series_code']}: #{pct}% of weather readings show rain — suspiciously high"
      end
    end

    ok "Rain data looks plausible" if rain_stats.none? { |r| r['rain_pct'].to_f > 50 }
  end

  def check_temperature_outliers
    section "Checking for temperature outliers"
    # Air temps below 32°F (freezing) or above 130°F are suspicious
    # Track temps can legitimately hit 140°F+ on hot days
    outliers = query(<<~SQL)
      SELECT series_code, year, event, MIN(air_temp_f) as min_temp, MAX(air_temp_f) as max_temp
      FROM event_weather
      WHERE air_temp_f < 32 OR air_temp_f > 130
      GROUP BY series_code, year, event
    SQL

    if outliers.empty?
      ok "No temperature outliers"
    else
      outliers.each do |row|
        min_t = row['min_temp'].to_f
        max_t = row['max_temp'].to_f
        if min_t < 32
          warn "Temperature outlier: #{row['series_code']}/#{row['year']}/#{row['event']} (#{min_t.round(1)}-#{max_t.round(1)}°F) - sub-freezing temps, likely unconverted Celsius"
        else
          warn "Temperature outlier: #{row['series_code']}/#{row['year']}/#{row['event']} (#{min_t.round(1)}-#{max_t.round(1)}°F) - unusually hot"
        end
      end
    end
  end

  def check_pit_time_outliers
    section "Checking for pit time outliers"
    outliers = query(<<~SQL)
      SELECT
        series_code, year, event,
        AVG(pit_time) as avg_pit,
        MAX(pit_time) as max_pit,
        COUNT(*) as pit_count
      FROM laps
      WHERE pit_time IS NOT NULL AND pit_time > 300
      GROUP BY series_code, year, event
      HAVING COUNT(*) > 5
      ORDER BY avg_pit DESC
      LIMIT 5
    SQL

    if outliers.empty?
      ok "No unusual pit times"
    else
      outliers.each do |row|
        warn "High pit times: #{row['series_code']}/#{row['year']}/#{row['event']} (avg: #{row['avg_pit'].to_i}s)"
      end
    end
  end

  def check_bpillar_populated
    section "Checking bpillar_quartile is populated for race sessions"

    # bpillar_quartile (060-bpillar.sql) ranks each driver on the fastest 50%
    # of their green-flag race laps. It is *expected* NULL for non-race sessions
    # and for off-pace / pit / lap-1 laps, but a race session with a healthy
    # field MUST yield some quartiles. An all-NULL column means the eligibility
    # filter or the UPDATE join silently matched nothing (the classic failure:
    # `pit_time > 600` excludes the NULL-pit_time green laps we want, and the
    # car/lap UPDATE join collides multi-driver cars). Catch that here so a
    # broken bpillar pass can never ship green again.

    # 1) Global guard: race laps exist but ZERO carry a quartile -> hard error.
    totals = query(<<~SQL).first || {}
      SELECT
        COUNT(*) FILTER (WHERE session = 'race') AS race_laps,
        COUNT(*) FILTER (WHERE session = 'race' AND bpillar_quartile IS NOT NULL) AS filled
      FROM laps
    SQL
    race_laps = totals['race_laps'].to_i
    filled = totals['filled'].to_i

    if race_laps.zero?
      info "No race-session laps present; skipping bpillar check"
      return
    end

    if filled.zero?
      error "bpillar_quartile is NULL for ALL #{race_laps} race laps - 060-bpillar.sql matched nothing (check the pit_time/stint_lap filter and the UPDATE join keys)"
      return
    end

    # 2) Quartiles must span 1..4 (NTILE(4) over eligible laps). A degenerate
    # spread means the eligibility set is too thin to be trustworthy.
    distinct_q = query(<<~SQL).map { |r| r['bpillar_quartile'] }.compact
      SELECT DISTINCT bpillar_quartile
      FROM laps
      WHERE session = 'race' AND bpillar_quartile IS NOT NULL
    SQL
    unless (1..4).to_a.all? { |q| distinct_q.include?(q) }
      warn "bpillar_quartile only spans #{distinct_q.sort.inspect} (expected 1..4) - eligibility set may be too small"
    end

    # 3) Per-session guard: a substantial race session (>=20 cars, lots of clean
    # laps) with ZERO quartiles is a localized failure worth flagging.
    empty_sessions = query(<<~SQL)
      WITH race AS (
        SELECT
          series_code, year, event, session, session_id,
          COUNT(*) AS laps,
          COUNT(DISTINCT car) AS cars,
          COUNT(*) FILTER (WHERE bpillar_quartile IS NOT NULL) AS filled
        FROM laps
        WHERE session = 'race'
        GROUP BY series_code, year, event, session, session_id
      )
      SELECT series_code, year, event, session, laps, cars
      FROM race
      WHERE filled = 0 AND laps > 500 AND cars >= 10
      ORDER BY year DESC, event
      LIMIT 20
    SQL

    if empty_sessions.empty?
      ok "bpillar_quartile populated across race sessions (#{filled} of #{race_laps} race laps)"
    else
      empty_sessions.each do |row|
        error "bpillar_quartile all-NULL for race session #{row['series_code']}/#{row['year']}/#{row['event']} (#{row['laps']} laps, #{row['cars']} cars)"
      end
    end
  end

  def check_race_coverage_plausibility
    section "Checking race session coverage plausibility"

    # For each race session, check if we have reasonable coverage:
    # - Enough cars reporting laps
    # - Timestamps spanning a reasonable portion of race duration
    # Expected race durations (hours): Le Mans = 24, Daytona = 24, Sebring = 12, others = 2-10
    races = query(<<~SQL)
      WITH race_stats AS (
        SELECT
          series_code,
          year,
          event,
          session,
          COUNT(*) as total_laps,
          COUNT(DISTINCT car) as car_count,
          MIN(session_time) as first_lap_time,
          MAX(session_time) as last_lap_time,
          (MAX(session_time) - MIN(session_time)) / 3600.0 as hours_covered
        FROM laps
        WHERE session ILIKE '%race%'
          AND session NOT ILIKE '%practice%'
          AND session NOT ILIKE '%qualifying%'
        GROUP BY series_code, year, event, session
      ),
      with_expected AS (
        SELECT
          *,
          -- Estimate expected race hours based on event name
          CASE
            WHEN event ILIKE '%le mans%' THEN 24.0
            WHEN event ILIKE '%daytona%' THEN 24.0
            WHEN event ILIKE '%sebring%' THEN 12.0
            WHEN event ILIKE '%petit%' THEN 10.0
            WHEN event ILIKE '%spa%' THEN 6.0
            WHEN event ILIKE '%fuji%' THEN 6.0
            WHEN event ILIKE '%bahrain%' THEN 8.0
            WHEN event ILIKE '%losail%' THEN 10.0
            ELSE 2.0  -- Sprint races
          END as expected_hours,
          -- Expected laps: cars * (race_hours * 60 / avg_lap_minutes)
          -- Assume ~2 min average lap for prototypes
          CASE
            WHEN event ILIKE '%le mans%' THEN car_count * 350
            WHEN event ILIKE '%daytona%' THEN car_count * 700
            WHEN event ILIKE '%sebring%' THEN car_count * 350
            WHEN event ILIKE '%petit%' THEN car_count * 300
            ELSE car_count * 60
          END as expected_min_laps
        FROM race_stats
      )
      SELECT
        series_code, year, event, session,
        total_laps, car_count,
        ROUND(hours_covered, 1) as hours_covered,
        expected_hours,
        expected_min_laps,
        ROUND(hours_covered / expected_hours * 100, 0) as coverage_pct,
        ROUND(total_laps::FLOAT / expected_min_laps * 100, 0) as lap_pct
      FROM with_expected
      WHERE hours_covered < expected_hours * 0.5  -- Less than 50% time coverage
         OR total_laps < expected_min_laps * 0.5  -- Less than 50% expected laps
      ORDER BY series_code, year, event
    SQL

    if races.empty?
      ok "All race sessions have plausible lap coverage"
    else
      races.each do |row|
        coverage = row['coverage_pct'].to_i
        lap_pct = row['lap_pct'].to_i
        hours = row['hours_covered'].to_f
        expected = row['expected_hours'].to_f

        severity = coverage < 30 || lap_pct < 30 ? :error : :warn
        msg = "Incomplete race data: #{row['series_code']}/#{row['year']}/#{row['event']}/#{row['session']} - " \
              "#{row['total_laps']} laps (#{lap_pct}% of expected), " \
              "#{hours}h covered of #{expected}h (#{coverage}%), " \
              "#{row['car_count']} cars"

        if severity == :error
          error msg
        else
          warn msg
        end
      end
    end
  end

  def check_driver_license_distribution
    section "Checking driver license distribution"
    distribution = query(<<~SQL)
      SELECT license, COUNT(DISTINCT driver_name) as drivers
      FROM laps
      WHERE license IS NOT NULL
      GROUP BY license
      ORDER BY drivers DESC
    SQL

    if distribution.empty?
      warn "No driver license data"
    else
      info "License distribution:"
      distribution.each { |row| info "  #{row['license']}: #{row['drivers']} drivers" }
    end
  end

  def check_missing_licenses
    section "Checking for missing licenses"
    missing = query_single(<<~SQL)
      SELECT COUNT(DISTINCT driver_name)
      FROM laps
      WHERE license IS NULL
    SQL

    total = query_single("SELECT COUNT(DISTINCT driver_name) FROM laps")

    if missing.to_i == 0
      ok "All drivers have license data"
    else
      pct = (missing.to_f / total * 100).round(1)
      error "#{missing} drivers (#{pct}%) missing license data"
    end
  end

  def check_session_type_consistency
    section "Checking session type consistency"

    # Valid normalized session types:
    # - race: main race sessions
    # - qualifying: qualifying sessions
    # - practice: free practice sessions
    # - warmup: warmup sessions
    # - test: private test sessions
    valid_pattern = /^(race|qualifying|practice|warmup|test)$/

    sessions = query(<<~SQL)
      SELECT session, COUNT(*) as laps
      FROM laps
      GROUP BY session
      ORDER BY laps DESC
    SQL

    invalid = sessions.reject { |row| row['session'] =~ valid_pattern }

    if invalid.empty?
      ok "All sessions have valid normalized types (race, qualifying, practice, warmup, test)"
    else
      invalid.each do |row|
        error "Invalid session type: '#{row['session']}' (#{row['laps']} laps) - should be race, qualifying, practice, warmup, or test"
      end
    end
  end

  def check_race_events_have_qualifying
    section "Checking race events have qualifying sessions"

    # Events with race sessions should also have qualifying sessions
    events_missing_qualify = query(<<~SQL)
      WITH event_sessions AS (
        SELECT
          series_code, year, event,
          MAX(CASE WHEN session = 'race' THEN 1 ELSE 0 END) as has_race,
          MAX(CASE WHEN session IN ('qualifying', 'qualify', 'qualify-race') THEN 1 ELSE 0 END) as has_qualify
        FROM laps
        GROUP BY series_code, year, event
      )
      SELECT series_code, year, event
      FROM event_sessions
      WHERE has_race = 1 AND has_qualify = 0
      ORDER BY series_code, year, event
    SQL

    if events_missing_qualify.empty?
      ok "All race events have qualifying sessions"
    else
      events_missing_qualify.each do |row|
        warn "Race event missing qualifying: #{row['series_code']}/#{row['year']}/#{row['event']}"
      end
    end
  end

  def check_single_race_per_event
    section "Checking multi-race events disambiguate via race_label"

    # Multi-race weekends (e.g. ALMS double-headers) are kept under ONE event and
    # disambiguated by race_label ("Race 1" / "Race 2" / custom). The data-quality
    # rule is therefore: if an event has >1 race session, every race session_id must
    # carry a DISTINCT, non-NULL race_label. A missing or duplicated label is the bug.
    # Note: Multiple qualifying sessions per event is valid - WEC/ELMS have separate
    # qualifying for each class (qualifying-lmp2, qualifying-gt3) which are all normalized
    # to "qualifying" but have different session_ids
    multi_race_label_problems = query(<<~SQL)
      WITH race_sessions AS (
        SELECT DISTINCT series_code, year, event, session_id, race_label
        FROM laps
        WHERE session = 'race'
      ),
      per_event AS (
        SELECT
          series_code, year, event,
          COUNT(*) as race_count,
          COUNT(DISTINCT race_label) as distinct_labels,
          COUNT(*) FILTER (WHERE race_label IS NULL) as null_labels
        FROM race_sessions
        GROUP BY series_code, year, event
      )
      SELECT series_code, year, event, race_count, distinct_labels, null_labels
      FROM per_event
      WHERE race_count > 1
        AND (null_labels > 0 OR distinct_labels < race_count)
      ORDER BY series_code, year, event
    SQL

    if multi_race_label_problems.empty?
      ok "All multi-race events disambiguate every race with a distinct race_label"
    else
      multi_race_label_problems.each do |row|
        if row['null_labels'].to_i > 0
          error "Multi-race event has #{row['null_labels']} race session(s) missing race_label: " \
                "#{row['series_code']}/#{row['year']}/#{row['event']} - add a 'races' entry in events.json"
        else
          error "Multi-race event has duplicate race_labels (#{row['distinct_labels']} distinct for " \
                "#{row['race_count']} races): #{row['series_code']}/#{row['year']}/#{row['event']} - " \
                "race names must be unique within an event"
        end
      end
    end
  end

  def check_race_results_presence
    section "Checking race sessions have results files"

    # For each race lap file, there should be a corresponding results file
    # This catches cases where laps were imported but results weren't
    race_sessions = query(<<~SQL)
      SELECT DISTINCT
        series_code,
        year,
        event,
        session,
        session_id,
        COUNT(*) as lap_count
      FROM laps
      WHERE session = 'race'
      GROUP BY series_code, year, event, session, session_id
      ORDER BY series_code, year, event
    SQL

    missing_results = []
    race_sessions.each do |row|
      # Check if we have driver info (which comes from results files)
      drivers = query(<<~SQL)
        SELECT COUNT(DISTINCT driver_id) as driver_count
        FROM event_driver_summary
        WHERE series_code = '#{row['series_code']}'
          AND year = '#{row['year']}'
          AND event = '#{row['event']}'
      SQL

      if drivers.empty? || drivers.first['driver_count'].to_i == 0
        missing_results << row
      end
    end

    if missing_results.empty?
      ok "All race sessions have results data"
    else
      missing_results.each do |row|
        warn "Race session may be missing results: #{row['series_code']}/#{row['year']}/#{row['event']} (#{row['lap_count']} laps, no drivers)"
      end
    end
  end

  def check_tire_allocation
    section "Checking est_tire_age against known tire allocations"

    # Known IMSA Michelin tire allocations per car per event:
    #   Sebring (12h): 6 sets practice, 12 sets race+qualifying
    # Race allocation is the hard upper bound for race-only sets. Most teams
    # reuse their qualifying tires in the race, so the 12 sets effectively
    # cover both sessions. We check race sets against 12 (not race+qualifying
    # combined) since qualifying tires carry over.
    #
    # We count new tire sets as laps where est_tire_age = 0 on a clean
    # green-flag lap (not an outlap, not a pit lap).
    allocation_checks = [
      # [event, years, session_filter, max_sets, label]
      ["Sebring", %w[2025 2026], "race",     12, "race"],
      ["Sebring", %w[2025 2026], "practice",  6, "practice"],
    ]

    allocation_checks.each do |event, years, session_group, max_sets, label|
      session_filter = case session_group
                       when "race" then "session = 'race'"
                       when "practice" then "session LIKE 'practice%'"
                       else next
                       end

      years.each do |year|
        violations = query(<<~SQL)
          SELECT car, class,
            COUNT(DISTINCT CASE
              WHEN est_tire_age = 0 AND flags = 'GF' AND lap_time IS NOT NULL
                   AND stint_lap >= 1 AND pit_time IS NULL
              THEN session_id::VARCHAR || '-' || lap::VARCHAR
            END) AS est_sets
          FROM laps
          WHERE event = '#{event}' AND series_code = 'imsa' AND year = '#{year}'
            AND #{session_filter}
          GROUP BY car, class
          HAVING est_sets > #{max_sets}
          ORDER BY est_sets DESC
        SQL

        if violations.empty?
          ok "#{event} #{year} #{label}: all cars within #{max_sets}-set allocation"
        else
          violations.each do |v|
            warn "#{event} #{year} #{label}: car ##{v['car']} (#{v['class']}) estimated #{v['est_sets']} tire sets, " \
                 "allocation is #{max_sets} — est_tire_age algorithm may be over-counting"
          end
        end
      end
    end
  end

  def check_class_normalization
    section "Checking class normalization"
    unmapped = query(<<~SQL)
      SELECT DISTINCT class, series_code, COUNT(*) as laps
      FROM laps
      WHERE class IS NOT NULL
      GROUP BY class, series_code
      ORDER BY series_code, class
    SQL

    info "Classes by series:"
    current_series = nil
    unmapped.each do |row|
      if row['series_code'] != current_series
        current_series = row['series_code']
        info "  #{current_series}:"
      end
      info "    #{row['class']}: #{row['laps']} laps"
    end
  end

  def coverage_summary
    section "Data coverage summary"

    stats = query(<<~SQL)
      SELECT
        series_code,
        COUNT(DISTINCT year) as years,
        COUNT(DISTINCT event) as events,
        COUNT(DISTINCT session_id) as sessions,
        COUNT(*) as laps,
        COUNT(DISTINCT driver_name) as drivers,
        COUNT(DISTINCT chassis) as chassis_types
      FROM laps
      GROUP BY series_code
      ORDER BY laps DESC
    SQL

    puts "\n  Series coverage:"
    puts "  #{'Series'.ljust(8)} #{'Years'.rjust(6)} #{'Events'.rjust(7)} #{'Sessions'.rjust(9)} #{'Laps'.rjust(10)} #{'Drivers'.rjust(8)} #{'Chassis'.rjust(8)}"
    puts "  " + "-" * 60
    stats.each do |row|
      puts "  #{row['series_code'].ljust(8)} #{row['years'].to_s.rjust(6)} #{row['events'].to_s.rjust(7)} #{row['sessions'].to_s.rjust(9)} #{row['laps'].to_s.rjust(10)} #{row['drivers'].to_s.rjust(8)} #{row['chassis_types'].to_s.rjust(8)}"
    end
  end

  def summary
    puts "\n" + "=" * 60
    puts "SUMMARY"
    puts "=" * 60
    puts "Errors:   #{@errors.length}"
    puts "Warnings: #{@warnings.length}"
    puts "Info:     #{@info.length}"
    puts

    if @errors.any?
      puts "❌ Linting FAILED - fix errors before proceeding"
      exit 1
    elsif @warnings.any?
      puts "⚠️  Linting passed with warnings"
      exit 0
    else
      puts "✅ All checks passed!"
      exit 0
    end
  end
end

if __FILE__ == $0
  linter = DatabaseLinter.new
  linter.run_all_checks
end
