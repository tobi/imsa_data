#!/usr/bin/env ruby
# frozen_string_literal: true

# Compute Elo ratings for drivers across all classes.
# Each class has its own independent rating pool.
#
# RATING MODEL (v2 — "same green window" pairwise pace Elo):
#   A driver's rating moves only when their pace is compared against OTHER
#   drivers IN THE SAME CLASS who were ON TRACK AT THE SAME TIME, under
#   green-flag conditions. Concretely, within each event we:
#     1. Keep only green-flag (flags='GF'), non-pit, valid laps.
#        (Events with no flag data at all fall back to all valid racing laps.)
#     2. Bucket every lap into a wall-clock window by its mid-point
#        session_time (BUCKET_SECONDS wide). A bucket is a slice of real race
#        time, so drivers in the pits / stopped / off-track simply don't appear
#        in it — you only get compared to cars circulating alongside you.
#     3. Within each window, each driver contributes ONE representative lap =
#        the median of their green laps in that window (robust to a single
#        traffic-compromised lap). Drivers are then compared pairwise on pace.
#
#   This replaces the old model, which compared lap NUMBER N across drivers
#   (different wall-clock moments) and included yellow-flag, pit, and incident
#   laps — penalising e.g. a clean Bronze for an unrelated off or for sharing a
#   class with factory pros during a safety car.
#
# The first event for a driver in a class includes +1500 in delta,
# so SUM(delta) = current Elo for any driver/class combination.
#
# Usage:
#   ruby compute_elo.rb                    # Output CSV to stdout
#   ruby compute_elo.rb --summary          # Also print summary to stderr
#   ruby compute_elo.rb -m 50              # Minimum laps filter for summary
#   ruby compute_elo.rb --bucket 600       # Window width in seconds (default 600)

require 'csv'
require 'optparse'

# Configuration
K_FACTOR = 32           # How much ratings change per update
INITIAL_ELO = 1500      # Starting Elo for new drivers
BUCKET_SECONDS = 600    # Wall-clock window width (10 min) for "same time on track"
DB_PATH = File.expand_path('output/imsa.duckdb', __dir__)

options = {
  summary: false,
  min_laps: 0,
  bucket: BUCKET_SECONDS
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on("--summary", "Print summary to stderr") do
    options[:summary] = true
  end

  opts.on("-m", "--min-laps LAPS", Integer, "Minimum laps filter for summary") do |laps|
    options[:min_laps] = laps
  end

  opts.on("--bucket SECONDS", Integer, "Wall-clock window width in seconds (default #{BUCKET_SECONDS})") do |s|
    options[:bucket] = s
  end
end.parse!

# Load lap data from DuckDB
def load_lap_data(db_path)
  query = <<~SQL
    SELECT
      driver_id,
      driver_name,
      COALESCE(class_category, class) as class,
      series_code,
      year,
      event,
      session,
      lap,
      lap_time,
      session_time,
      flags,
      pit_time,
      license,
      start_date as session_date
    FROM laps
    WHERE (session = 'race' OR session LIKE 'race-hour-%')
      AND lap_time IS NOT NULL
      AND driver_id IS NOT NULL
    ORDER BY start_date, series_code, year, event, session_time
  SQL

  # DuckDB CSV uses '-nullstr NULL' by default, emitting the literal string
  # "NULL" for SQL NULLs. Normalise that (and empty) to Ruby nil.
  nn = ->(v) { v.nil? || v.empty? || v == 'NULL' ? nil : v }

  result = `duckdb "#{db_path}" -csv -c "#{query.gsub('"', '\\"').gsub("\n", ' ')}"`

  laps = []
  CSV.parse(result, headers: true) do |row|
    st = nn.call(row['session_time'])
    pt = nn.call(row['pit_time'])
    laps << {
      driver_id: row['driver_id'],
      driver_name: row['driver_name'],
      class: row['class'],
      series_code: row['series_code'],
      year: row['year'],
      event: row['event'],
      session: row['session'],
      lap: row['lap'].to_i,
      lap_time: row['lap_time'].to_f,
      session_time: (st ? st.to_f : nil),
      flags: nn.call(row['flags']),
      pit_time: (pt ? pt.to_f : nil),
      license: nn.call(row['license']),
      session_date: row['session_date']
    }
  end
  laps
end

# Elo calculation helpers
def expected_score(rating_a, rating_b)
  1.0 / (1.0 + 10 ** ((rating_b - rating_a) / 400.0))
end

def median(values)
  sorted = values.sort
  n = sorted.length
  return sorted[n / 2] if n.odd?
  (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
end

# Group laps into events for processing
def group_by_event(laps)
  laps.group_by { |l| [l[:series_code], l[:year], l[:event], l[:class]] }
end

# Keep only laps that represent clean, comparable green-flag racing pace.
# Falls back to all valid laps when an event carries no flag data at all.
def filter_green(event_laps)
  has_flags = event_laps.any? { |l| !l[:flags].nil? && !l[:flags].empty? }
  event_laps.select do |l|
    next false if l[:lap_time] <= 0
    next false unless l[:pit_time].nil?       # drop in/out (pit) laps
    if has_flags
      l[:flags] == 'GF'                       # green-flag only
    else
      true                                    # legacy event, no flag data
    end
  end
end

# Compare drivers within a single wall-clock window. Each driver is represented
# by ONE lap (median of their green laps in the window). Ratings mutate in place.
def process_window(window_reps, ratings, window_counts)
  updates = Hash.new { |h, k| h[k] = { delta_sum: 0.0, comparisons: 0 } }

  # window_reps: array of { driver_id:, rep_time: }
  sorted = window_reps.sort_by { |r| r[:rep_time] }

  sorted.each_with_index do |faster, i|
    sorted[(i + 1)..].each do |slower|
      next if faster[:driver_id] == slower[:driver_id]

      faster_elo = ratings[faster[:driver_id]] || INITIAL_ELO
      slower_elo = ratings[slower[:driver_id]] || INITIAL_ELO

      expected = expected_score(faster_elo, slower_elo)
      delta = K_FACTOR * (1 - expected) / 10.0  # Reduce K for individual windows

      updates[faster[:driver_id]][:delta_sum] += delta
      updates[faster[:driver_id]][:comparisons] += 1
      updates[slower[:driver_id]][:delta_sum] -= delta
      updates[slower[:driver_id]][:comparisons] += 1
    end
  end

  updates.each do |driver_id, data|
    next if data[:comparisons] == 0
    avg_delta = data[:delta_sum] / data[:comparisons]
    ratings[driver_id] ||= INITIAL_ELO
    ratings[driver_id] += avg_delta
    window_counts[driver_id] ||= 0
    window_counts[driver_id] += 1
  end
end

# Main processing
STDERR.puts "Loading lap data from #{DB_PATH}..."
all_laps = load_lap_data(DB_PATH)
STDERR.puts "Loaded #{all_laps.length} laps"

bucket_seconds = options[:bucket].to_f

# Group by class - each class has independent ratings
laps_by_class = all_laps.group_by { |l| l[:class] }

# Track which drivers have had their first event (for +1500 delta)
first_event_seen = {}  # [driver_id, class] => true

# Output storage
rows = []

laps_by_class.each do |klass, class_laps|
  STDERR.puts "Processing #{klass}: #{class_laps.length} laps"

  ratings = {}           # driver_id => current elo
  green_laps = {}        # driver_id => cumulative green lap count (reporting)
  driver_names = {}      # driver_id => name
  driver_licenses = {}   # driver_id => license

  # Group by event and process chronologically
  events = group_by_event(class_laps)

  sorted_events = events.sort_by do |key, laps|
    laps.first[:session_date] || '1970-01-01'
  end

  sorted_events.each do |(series, year, event, _), event_laps|
    session_date = event_laps.first[:session_date]

    # Track names and licenses (from all laps, even non-green)
    event_laps.each do |lap|
      driver_names[lap[:driver_id]] = lap[:driver_name]
      driver_licenses[lap[:driver_id]] = lap[:license] if lap[:license]
    end

    # Keep only clean green racing laps for the comparison
    green = filter_green(event_laps)
    next if green.empty?

    # Snapshot pre-event state
    pre_event_elo = ratings.dup
    pre_event_green = green_laps.dup

    # Count this event's green laps per driver (for reporting)
    event_green_count = Hash.new(0)
    green.each { |l| event_green_count[l[:driver_id]] += 1 }

    # Bucket laps into wall-clock windows by lap mid-point session_time.
    # Within a window, each driver is represented by the median of their laps.
    windows = green.group_by do |l|
      st = l[:session_time]
      mid = st ? (st - l[:lap_time] / 2.0) : (l[:lap] * 100.0)  # fallback ordering
      (mid / bucket_seconds).floor
    end

    window_counts = {}  # driver_id => windows participated (for chronology only)

    windows.sort_by { |bucket, _| bucket }.each do |_bucket, window_laps|
      by_driver = window_laps.group_by { |l| l[:driver_id] }
      reps = by_driver.map do |driver_id, laps|
        { driver_id: driver_id, rep_time: median(laps.map { |l| l[:lap_time] }) }
      end
      next if reps.length < 2   # need at least 2 cars on track to compare
      process_window(reps, ratings, window_counts)
    end

    # Commit cumulative green lap counts
    event_green_count.each do |driver_id, cnt|
      green_laps[driver_id] = (green_laps[driver_id] || 0) + cnt
    end

    # Record history for drivers who completed green laps this event
    event_green_count.keys.each do |driver_id|
      old_elo = pre_event_elo[driver_id] || INITIAL_ELO
      new_elo = ratings[driver_id] || INITIAL_ELO
      raw_delta = new_elo - old_elo
      event_lap_count = event_green_count[driver_id]
      new_cumulative = green_laps[driver_id] || 0

      next if event_lap_count == 0

      first_key = [driver_id, klass]
      is_first = !first_event_seen[first_key]
      first_event_seen[first_key] = true

      delta = is_first ? (INITIAL_ELO + raw_delta) : raw_delta
      elo_before = is_first ? 0 : old_elo.round(0)
      elo_after = new_elo.round(0)

      rows << {
        driver_id: driver_id,
        driver_name: driver_names[driver_id],
        class: klass,
        series_code: series,
        year: year,
        event: event,
        session_date: session_date,
        elo_before: elo_before,
        elo_after: elo_after,
        delta: delta.round(0),
        laps: event_lap_count,
        cumulative_laps: new_cumulative,
        license: driver_licenses[driver_id]
      }
    end
  end

  # Print summary if requested
  if options[:summary]
    qualified = ratings.select { |id, _| (green_laps[id] || 0) >= options[:min_laps] }
    next if qualified.empty?

    STDERR.puts "\n#{klass} (#{qualified.length} drivers with #{options[:min_laps]}+ green laps):"
    STDERR.puts "-" * 60

    qualified.sort_by { |_, elo| -elo }.first(20).each_with_index do |(driver_id, elo), i|
      name = driver_names[driver_id] || driver_id
      laps = green_laps[driver_id] || 0
      license = driver_licenses[driver_id] || '-'
      STDERR.printf "%3d. %-25s %4d Elo  %4d laps  [%s]\n", i + 1, name, elo.round, laps, license
    end
  end
end

# Output CSV
puts "driver_id,driver_name,class,series_code,year,event,session_date,elo_before,elo_after,delta,laps,cumulative_laps,license"
rows.sort_by { |r| [r[:session_date] || '', r[:class], r[:driver_id]] }.each do |r|
  puts [
    r[:driver_id],
    r[:driver_name],
    r[:class],
    r[:series_code],
    r[:year],
    r[:event],
    r[:session_date],
    r[:elo_before],
    r[:elo_after],
    r[:delta],
    r[:laps],
    r[:cumulative_laps],
    r[:license]
  ].join(',')
end

STDERR.puts "\nWrote #{rows.length} rows"
