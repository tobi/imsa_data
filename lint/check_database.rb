#!/usr/bin/env ruby
# Database linting script - comprehensive checks for data quality
# Run with: ruby lint/check_database.rb

require 'open3'
require 'json'

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

    # Track & location checks
    check_unknown_tracks
    check_duplicate_aliases
    check_missing_coordinates

    # Event checks
    check_missing_events_json
    check_orphan_events
    check_missing_weather
    check_missing_race_data

    # Chassis & homologation checks
    check_unknown_chassis
    check_unknown_homologation
    check_manufacturer_coverage

    # Data quality checks
    check_lap_time_outliers
    check_temperature_outliers
    check_pit_time_outliers

    # Driver checks
    check_driver_license_distribution
    check_missing_licenses

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

  def check_temperature_outliers
    section "Checking for temperature outliers"
    outliers = query(<<~SQL)
      SELECT series_code, year, event, MIN(air_temp_f) as min_temp, MAX(air_temp_f) as max_temp
      FROM event_weather
      WHERE air_temp_f < 20 OR air_temp_f > 120
      GROUP BY series_code, year, event
    SQL

    if outliers.empty?
      ok "No temperature outliers"
    else
      outliers.each do |row|
        warn "Temperature outlier: #{row['series_code']}/#{row['year']}/#{row['event']} (#{row['min_temp']}-#{row['max_temp']}°F) - likely Celsius data"
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

  def check_driver_license_distribution
    section "Checking driver license distribution"
    distribution = query(<<~SQL)
      SELECT license, COUNT(DISTINCT driver_id) as drivers
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
      SELECT COUNT(DISTINCT driver_id)
      FROM laps
      WHERE license IS NULL
    SQL

    total = query_single("SELECT COUNT(DISTINCT driver_id) FROM laps")

    if missing.to_i == 0
      ok "All drivers have license data"
    else
      pct = (missing.to_f / total * 100).round(1)
      if pct > 10
        warn "#{missing} drivers (#{pct}%) missing license data"
      else
        info "#{missing} drivers (#{pct}%) missing license data"
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
        COUNT(DISTINCT driver_id) as drivers,
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
