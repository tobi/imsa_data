#!/usr/bin/env ruby
# Database linting script - checks for common problems
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

  def run_all_checks
    puts "=" * 60
    puts "Database Linting: #{DB_PATH}"
    puts "=" * 60
    puts

    unless File.exist?(DB_PATH)
      error "Database file not found: #{DB_PATH}"
      error "Run 'rake db:update' first"
      return summary
    end

    check_unknown_tracks
    check_missing_events_json
    check_duplicate_aliases
    check_orphan_events
    check_missing_weather
    check_missing_race_data
    check_lap_time_outliers
    check_temperature_outliers
    check_duplicate_event_ids
    check_missing_coordinates
    check_driver_license_distribution
    check_class_normalization

    summary
  end

  def check_unknown_tracks
    puts "\n--- Checking for unknown tracks ---"

    # Check if any event_folders fail to normalize
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
    puts "\n--- Checking for missing events.json ---"

    data_dirs = Dir["data/*/*"].select { |d| File.directory?(d) }
    year_dirs = data_dirs.map { |d| File.dirname(d) }.uniq

    year_dirs.each do |year_dir|
      events_json = File.join(year_dir, "events.json")
      unless File.exist?(events_json)
        warn "Missing events.json: #{events_json}"
      end
    end

    existing = Dir["data/*/*/events.json"].length
    ok "Found #{existing} events.json files" if existing > 0
  end

  def check_duplicate_aliases
    puts "\n--- Checking for duplicate track aliases ---"

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

  def check_orphan_events
    puts "\n--- Checking for orphan events (no lap data) ---"

    orphans = query(<<~SQL)
      SELECT e.event_id, e.event_name, e.track, e.start_date
      FROM events e
      WHERE e.start_date IS NULL
        AND e.track IS NOT NULL
      ORDER BY e.event_id
      LIMIT 20
    SQL

    if orphans.empty?
      ok "All events have associated lap data"
    else
      info "#{orphans.length} events without lap data (support series, tests):"
      orphans.first(5).each do |row|
        info "  - #{row['event_id']}: #{row['event_name']}"
      end
      info "  ... and #{orphans.length - 5} more" if orphans.length > 5
    end
  end

  def check_missing_weather
    puts "\n--- Checking for events without weather data ---"

    missing = query(<<~SQL)
      SELECT e.event_id, e.event_name, e.start_date
      FROM events e
      WHERE e.start_date IS NOT NULL
        AND e.avg_air_temp_f IS NULL
      ORDER BY e.start_date DESC
      LIMIT 10
    SQL

    if missing.empty?
      ok "All events with lap data have weather data"
    else
      missing.each do |row|
        warn "No weather data: #{row['event_id']} (#{row['start_date']})"
      end
    end
  end

  def check_missing_race_data
    puts "\n--- Checking for events without race sessions ---"

    missing = query(<<~SQL)
      SELECT e.event_id, e.event_name, e.start_date, e.session_count
      FROM events e
      WHERE e.start_date IS NOT NULL
        AND e.race_count = 0
      ORDER BY e.start_date DESC
    SQL

    if missing.empty?
      ok "All events have race data"
    else
      missing.each do |row|
        info "No race session: #{row['event_id']} (#{row['session_count']} sessions total)"
      end
    end
  end

  def check_lap_time_outliers
    puts "\n--- Checking for lap time outliers ---"

    outliers = query(<<~SQL)
      SELECT
        series_code, year, event, session,
        MIN(lap_time) as min_lap,
        MAX(lap_time) as max_lap,
        COUNT(*) as outlier_count
      FROM laps
      WHERE lap_time IS NOT NULL
        AND (lap_time < 30 OR lap_time > 600)
      GROUP BY series_code, year, event, session
      HAVING COUNT(*) > 10
      ORDER BY outlier_count DESC
      LIMIT 5
    SQL

    if outliers.empty?
      ok "No significant lap time outliers found"
    else
      outliers.each do |row|
        warn "Lap time outliers in #{row['series_code']}/#{row['year']}/#{row['event']}/#{row['session']}: #{row['outlier_count']} laps (#{row['min_lap']}-#{row['max_lap']}s)"
      end
    end
  end

  def check_temperature_outliers
    puts "\n--- Checking for temperature outliers ---"

    outliers = query(<<~SQL)
      SELECT series_code, year, event, MIN(air_temp_f) as min_temp, MAX(air_temp_f) as max_temp
      FROM event_weather
      WHERE air_temp_f < 20 OR air_temp_f > 120
      GROUP BY series_code, year, event
    SQL

    if outliers.empty?
      ok "No temperature outliers found"
    else
      outliers.each do |row|
        warn "Temperature outlier: #{row['series_code']}/#{row['year']}/#{row['event']} (#{row['min_temp']}-#{row['max_temp']}°F)"
      end
    end
  end

  def check_duplicate_event_ids
    puts "\n--- Checking for problematic event_id patterns ---"

    # Multiple events at same track/year is OK, but check for excessive duplicates
    duplicates = query(<<~SQL)
      SELECT event_id, COUNT(*) as cnt
      FROM events
      GROUP BY event_id
      HAVING COUNT(*) > 5
    SQL

    if duplicates.empty?
      ok "No excessive event_id duplicates"
    else
      duplicates.each do |row|
        warn "Many events with same ID: #{row['event_id']} (#{row['cnt']} entries)"
      end
    end
  end

  def check_missing_coordinates
    puts "\n--- Checking tracks for missing coordinates ---"

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

  def check_driver_license_distribution
    puts "\n--- Checking driver license distribution ---"

    distribution = query(<<~SQL)
      SELECT license, COUNT(DISTINCT driver_id) as drivers
      FROM laps
      WHERE license IS NOT NULL
      GROUP BY license
      ORDER BY drivers DESC
    SQL

    if distribution.empty?
      warn "No driver license data found"
    else
      info "Driver license distribution:"
      distribution.each do |row|
        info "  #{row['license']}: #{row['drivers']} drivers"
      end
    end
  end

  def check_class_normalization
    puts "\n--- Checking class normalization ---"

    unmapped = query(<<~SQL)
      SELECT DISTINCT class, series_code
      FROM laps
      WHERE class_normalized IS NULL AND class IS NOT NULL
      ORDER BY series_code, class
    SQL

    if unmapped.empty?
      ok "All classes are normalized"
    else
      unmapped.each do |row|
        warn "Unmapped class: '#{row['class']}' in #{row['series_code']}"
      end
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
