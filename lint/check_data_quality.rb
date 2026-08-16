#!/usr/bin/env ruby
# Data quality checks - validates lap data completeness and sanity
# Run with: ruby lint/check_data_quality.rb

require 'open3'
require 'json'

DB_PATH = "output/imsa.duckdb"

class DataQualityChecker
  def initialize
    @issues = []
  end

  # duckdb -json emits DECIMAL values as strings ("50.746"); coerce once here
  DECIMAL_STRING = /\A-?\d+(\.\d+)?\z/

  def query(sql)
    stdout, stderr, status = Open3.capture3("duckdb", DB_PATH, "-json", "-c", sql)
    raise "Query failed: #{stderr}" unless status.success?
    JSON.parse(stdout).map do |row|
      row.each_with_object({}) do |(k, v), out|
        out[k] = v.is_a?(String) && v.match?(DECIMAL_STRING) ? v.to_f : v
      end
    end
  rescue JSON::ParserError
    []
  end

  def issue(severity, event, msg)
    @issues << { severity: severity, event: event, message: msg }
    icon = case severity
           when :error then "❌"
           when :warning then "⚠️ "
           when :info then "ℹ️ "
           end
    puts "  #{icon} #{msg}"
  end

  def run_all_checks
    puts "=" * 70
    puts "Data Quality Check: Analyzing all race sessions"
    puts "=" * 70

    unless File.exist?(DB_PATH)
      puts "❌ Database not found: #{DB_PATH}"
      puts "   Run 'rake db:update' first"
      exit 1
    end

    # Get all race sessions
    races = query(<<~SQL)
      SELECT DISTINCT
        series_code,
        year,
        event,
        session_id,
        MIN(start_date) as race_date,
        MAX(session_time) / 3600.0 as duration_hours
      FROM laps
      WHERE session = 'race'
        AND lap_time IS NOT NULL
      GROUP BY series_code, year, event, session_id
      ORDER BY series_code, year, event
    SQL

    puts "\nFound #{races.length} race sessions to analyze\n"

    races.each do |race|
      check_race(race)
    end

    summary
  end

  def check_race(race)
    event_key = "#{race['series_code']}/#{race['year']}/#{race['event']}"
    session_id = race['session_id']
    duration = race['duration_hours']&.round(1)

    puts "\n--- #{event_key} (#{duration}h) ---"

    check_lap_coverage(session_id, event_key, duration)
    check_lap_time_consistency(session_id, event_key)
    check_driver_stints(session_id, event_key)
    check_car_coverage(session_id, event_key)
    check_flag_distribution(session_id, event_key)
    check_pit_stops(session_id, event_key)
    check_bpillar(session_id, event_key)
  end

  def check_lap_coverage(session_id, event_key, duration_hours)
    return unless duration_hours

    # Check that we have laps throughout the race duration
    coverage = query(<<~SQL)
      WITH time_buckets AS (
        SELECT
          FLOOR(session_time / 1800) as half_hour,  -- 30-minute buckets
          COUNT(*) as lap_count,
          COUNT(DISTINCT car) as cars
        FROM laps
        WHERE session_id = #{session_id}
          AND lap_time IS NOT NULL
        GROUP BY FLOOR(session_time / 1800)
      )
      SELECT
        half_hour,
        lap_count,
        cars
      FROM time_buckets
      ORDER BY half_hour
    SQL

    if coverage.empty?
      issue(:error, event_key, "No lap coverage data")
      return
    end

    expected_buckets = (duration_hours * 2).ceil
    actual_buckets = coverage.length

    # Check for gaps in coverage
    bucket_nums = coverage.map { |c| c['half_hour'].to_i }
    max_bucket = bucket_nums.max || 0

    gaps = []
    (0..max_bucket).each do |i|
      unless bucket_nums.include?(i)
        gaps << i
      end
    end

    if gaps.length > 2
      issue(:warning, event_key, "Coverage gaps in half-hours: #{gaps.first(5).join(', ')}#{gaps.length > 5 ? '...' : ''}")
    end

    # Check for sudden drops in activity
    coverage.each_cons(2) do |prev, curr|
      if prev['lap_count'] > 50 && curr['lap_count'] < prev['lap_count'] * 0.3
        issue(:warning, event_key, "Sudden lap count drop at half-hour #{curr['half_hour']}: #{prev['lap_count']} -> #{curr['lap_count']}")
      end
    end

    avg_cars = coverage.map { |c| c['cars'] }.sum.to_f / coverage.length
    if avg_cars < 10
      issue(:warning, event_key, "Low average car count: #{avg_cars.round(1)}")
    end
  end

  def check_lap_time_consistency(session_id, event_key)
    stats = query(<<~SQL)
      SELECT
        class,
        COUNT(*) as laps,
        AVG(lap_time) as avg_lap,
        STDDEV(lap_time) as stddev_lap,
        MIN(lap_time) as min_lap,
        MAX(lap_time) as max_lap,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY lap_time) as median_lap
      FROM laps
      WHERE session_id = #{session_id}
        AND lap_time IS NOT NULL
        AND flags = 'GF'
      GROUP BY class
    SQL

    stats.each do |cls|
      class_name = cls['class'] || 'Unknown'
      avg = cls['avg_lap']
      stddev = cls['stddev_lap']
      min_lap = cls['min_lap']
      max_lap = cls['max_lap']

      next unless avg && stddev

      # Check coefficient of variation (CV)
      cv = (stddev / avg * 100).round(2)
      if cv > 15
        issue(:warning, event_key, "High lap time variance in #{class_name}: CV=#{cv}% (stddev=#{stddev.round(2)}s)")
      end

      # Check for impossible lap times
      if min_lap && min_lap < 40
        issue(:error, event_key, "Impossibly fast lap in #{class_name}: #{min_lap.round(3)}s")
      end

      # Check for extremely slow laps under green
      if max_lap && max_lap > avg * 2
        issue(:info, event_key, "Very slow green flag lap in #{class_name}: #{max_lap.round(1)}s (avg: #{avg.round(1)}s)")
      end
    end
  end

  def check_driver_stints(session_id, event_key)
    stint_stats = query(<<~SQL)
      SELECT
        car,
        driver_name,
        stint_number,
        COUNT(*) as stint_laps,
        MIN(lap_time) as best_lap,
        AVG(lap_time) as avg_lap
      FROM laps
      WHERE session_id = #{session_id}
        AND lap_time IS NOT NULL
        AND stint_number IS NOT NULL
      GROUP BY car, driver_name, stint_number
      HAVING COUNT(*) > 1
      ORDER BY car, stint_number
    SQL

    # Check for unusually long stints (>4 hours of laps is suspicious)
    long_stints = stint_stats.select { |s| s['stint_laps'] > 120 }
    if long_stints.any?
      long_stints.first(3).each do |stint|
        issue(:info, event_key, "Long stint: Car ##{stint['car']} #{stint['driver_name']} - #{stint['stint_laps']} laps")
      end
    end

    # Check for drivers with only 1-2 laps (possible data issues)
    tiny_stints = stint_stats.select { |s| s['stint_laps'] <= 2 }
    if tiny_stints.length > 10
      issue(:warning, event_key, "Many tiny stints (<=2 laps): #{tiny_stints.length} occurrences")
    end
  end

  def check_car_coverage(session_id, event_key)
    car_laps = query(<<~SQL)
      SELECT
        car,
        class,
        COUNT(*) as total_laps,
        COUNT(DISTINCT driver_name) as drivers,
        MIN(lap) as first_lap,
        MAX(lap) as last_lap
      FROM laps
      WHERE session_id = #{session_id}
      GROUP BY car, class
      ORDER BY total_laps DESC
    SQL

    if car_laps.empty?
      issue(:error, event_key, "No car data found")
      return
    end

    max_laps = car_laps.map { |c| c['total_laps'] }.max
    avg_laps = car_laps.map { |c| c['total_laps'] }.sum.to_f / car_laps.length

    # Cars with very few laps compared to leaders
    low_lap_cars = car_laps.select { |c| c['total_laps'] < max_laps * 0.2 }
    if low_lap_cars.length > car_laps.length * 0.3
      issue(:info, event_key, "#{low_lap_cars.length}/#{car_laps.length} cars completed <20% of leader laps")
    end

    # Check for cars with no drivers assigned
    no_drivers = car_laps.select { |c| c['drivers'] == 0 }
    if no_drivers.any?
      issue(:warning, event_key, "Cars with no driver data: #{no_drivers.map { |c| c['car'] }.join(', ')}")
    end
  end

  def check_flag_distribution(session_id, event_key)
    flags = query(<<~SQL)
      SELECT
        flags,
        COUNT(*) as laps,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) as pct
      FROM laps
      WHERE session_id = #{session_id}
        AND lap_time IS NOT NULL
      GROUP BY flags
      ORDER BY laps DESC
    SQL

    if flags.empty?
      issue(:warning, event_key, "No flag data")
      return
    end

    green_pct = flags.find { |f| f['flags'] == 'GF' }&.dig('pct') || 0
    yellow_pct = flags.find { |f| f['flags'] == 'FCY' }&.dig('pct') || 0

    if green_pct < 50
      issue(:warning, event_key, "Low green flag percentage: #{green_pct}% (FCY: #{yellow_pct}%)")
    end

    # Check for unknown flags
    unknown_flags = flags.reject { |f| ['GF', 'FCY', 'SC', 'VSC', 'RED', nil, ''].include?(f['flags']) }
    if unknown_flags.any?
      issue(:info, event_key, "Unusual flags: #{unknown_flags.map { |f| "#{f['flags']}(#{f['pct']}%)" }.join(', ')}")
    end
  end

  def check_pit_stops(session_id, event_key)
    pit_stats = query(<<~SQL)
      SELECT
        COUNT(*) as pit_count,
        AVG(pit_time) as avg_pit,
        MIN(pit_time) as min_pit,
        MAX(pit_time) as max_pit
      FROM laps
      WHERE session_id = #{session_id}
        AND pit_time IS NOT NULL
        AND pit_time > 0
    SQL

    return if pit_stats.empty? || pit_stats.first['pit_count'] == 0

    stats = pit_stats.first
    avg_pit = stats['avg_pit']
    min_pit = stats['min_pit']
    max_pit = stats['max_pit']

    if min_pit && min_pit < 20
      issue(:warning, event_key, "Very fast pit stop: #{min_pit.round(1)}s")
    end

    if max_pit && max_pit > 600
      issue(:info, event_key, "Very long pit stop: #{(max_pit / 60).round(1)} min")
    end

    if avg_pit && (avg_pit < 30 || avg_pit > 120)
      issue(:warning, event_key, "Unusual average pit time: #{avg_pit.round(1)}s")
    end
  end

  # bpillar_quartile sanity (see 060-bpillar.sql). It is legitimately NULL for
  # non-race sessions and for laps that fail the eligibility window, so a blanket
  # "no nulls" check is wrong. The real failure mode is a race session+class that
  # ends up with ZERO classified (non-null) laps — that signals the bpillar UPDATE
  # silently matched nothing (e.g. the multi-driver-car join key regression noted
  # in 060-bpillar.sql), which would quietly break the Pace Hub's race ladder.
  def check_bpillar(session_id, event_key)
    rows = query(<<~SQL)
      SELECT
        class,
        COUNT(*)                                                   AS race_laps,
        COUNT(bpillar_quartile)                                    AS classified_laps,
        COUNT(*) FILTER (WHERE bpillar_quartile NOT IN (1,2,3,4)
                            AND bpillar_quartile IS NOT NULL)      AS out_of_range
      FROM laps
      WHERE session = 'race'
        AND session_id = '#{session_id}'
        AND lap_time IS NOT NULL
      GROUP BY class
      ORDER BY class
    SQL

    return if rows.empty?

    rows.each do |r|
      cls = r['class']
      race_laps = r['race_laps'].to_i
      classified = r['classified_laps'].to_i
      out_of_range = r['out_of_range'].to_i
      next if race_laps.zero?

      # Hard error: a class ran a race but NOTHING got a bpillar quartile.
      if classified.zero?
        issue(:error, event_key,
              "bpillar: class #{cls} has #{race_laps} race laps but 0 classified " \
              "(bpillar_quartile all NULL — the UPDATE in 060-bpillar.sql matched no rows)")
        next
      end

      # Hard error: a quartile column should only ever hold NULL or 1..4.
      if out_of_range.positive?
        issue(:error, event_key,
              "bpillar: class #{cls} has #{out_of_range} laps with an out-of-range " \
              "bpillar_quartile (expected NULL or 1-4)")
      end

      # Warning: implausibly thin classification (a healthy class classifies a
      # large share of its green laps; <10% usually means the eligibility window
      # or a join is off rather than a genuinely scrappy race).
      pct = (classified.to_f / race_laps * 100).round(1)
      if pct < 10
        issue(:warning, event_key,
              "bpillar: class #{cls} only #{pct}% of race laps classified " \
              "(#{classified}/#{race_laps})")
      end
    end
  end

  def summary
    puts "\n" + "=" * 70
    puts "DATA QUALITY SUMMARY"
    puts "=" * 70

    errors = @issues.select { |i| i[:severity] == :error }
    warnings = @issues.select { |i| i[:severity] == :warning }
    infos = @issues.select { |i| i[:severity] == :info }

    puts "Errors:   #{errors.length}"
    puts "Warnings: #{warnings.length}"
    puts "Info:     #{infos.length}"

    if errors.any?
      puts "\n❌ ERRORS requiring attention:"
      errors.group_by { |e| e[:event] }.each do |event, issues|
        puts "  #{event}:"
        issues.each { |i| puts "    - #{i[:message]}" }
      end
    end

    if warnings.length > 10
      puts "\n⚠️  Top warning categories:"
      warnings.group_by { |w| w[:message].split(':').first }
              .sort_by { |_, v| -v.length }
              .first(5)
              .each { |cat, issues| puts "  #{cat}: #{issues.length} occurrences" }
    end

    puts

    if errors.any?
      puts "❌ Data quality check FAILED"
      exit 1
    elsif warnings.length > 20
      puts "⚠️  Data quality check passed with many warnings"
      exit 0
    else
      puts "✅ Data quality check passed"
      exit 0
    end
  end
end

if __FILE__ == $0
  checker = DataQualityChecker.new
  checker.run_all_checks
end
