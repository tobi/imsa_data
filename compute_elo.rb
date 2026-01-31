#!/usr/bin/env ruby
# frozen_string_literal: true

# Compute Elo ratings for drivers across all classes
# Each class has its own independent rating pool
#
# The first event for a driver in a class includes +1500 in delta,
# so SUM(delta) = current Elo for any driver/class combination.
#
# Usage:
#   ruby compute_elo.rb                    # Output CSV to stdout
#   ruby compute_elo.rb --summary          # Also print summary to stderr
#   ruby compute_elo.rb -m 50              # Minimum laps filter for summary

require 'csv'
require 'optparse'

# Configuration
K_FACTOR = 32           # How much ratings change per update
INITIAL_ELO = 1500      # Starting Elo for new drivers
DB_PATH = File.expand_path('output/imsa.duckdb', __dir__)

options = {
  summary: false,
  min_laps: 0
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  
  opts.on("--summary", "Print summary to stderr") do
    options[:summary] = true
  end
  
  opts.on("-m", "--min-laps LAPS", Integer, "Minimum laps filter for summary") do |laps|
    options[:min_laps] = laps
  end
end.parse!

# Load lap data from DuckDB
def load_lap_data(db_path)
  query = <<~SQL
    SELECT 
      driver_id,
      driver_name,
      class,
      series_code,
      year,
      event,
      session,
      lap,
      lap_time,
      license,
      start_date as session_date
    FROM laps
    WHERE (session = 'race' OR session LIKE 'race-hour-%')
      AND lap_time IS NOT NULL
      AND driver_id IS NOT NULL
    ORDER BY start_date, series_code, year, event, lap, lap_time
  SQL
  
  result = `duckdb "#{db_path}" -csv -c "#{query.gsub('"', '\\"').gsub("\n", ' ')}"`
  
  laps = []
  CSV.parse(result, headers: true) do |row|
    laps << {
      driver_id: row['driver_id'],
      driver_name: row['driver_name'],
      class: row['class'],
      series_code: row['series_code'],
      year: row['year'],
      event: row['event'],
      session: row['session'],
      lap: row['lap'].to_i,
      lap_time: row['lap_time'],
      license: row['license'],
      session_date: row['session_date']
    }
  end
  laps
end

# Elo calculation helpers
def expected_score(rating_a, rating_b)
  1.0 / (1.0 + 10 ** ((rating_b - rating_a) / 400.0))
end

# Group laps into events for processing
def group_by_event(laps)
  laps.group_by { |l| [l[:series_code], l[:year], l[:event], l[:class]] }
end

# Process a single lap within an event
def process_lap_comparisons(lap_group, ratings, driver_laps)
  updates = Hash.new { |h, k| h[k] = { delta_sum: 0.0, comparisons: 0 } }
  
  # Sort by lap time (faster is better)
  sorted = lap_group.sort_by { |l| l[:lap_time].to_f }
  sorted.reject! { |l| l[:lap_time].to_f <= 0 }
  
  # Compare each pair
  sorted.each_with_index do |faster, i|
    sorted[(i + 1)..].each do |slower|
      next if faster[:driver_id] == slower[:driver_id]
      
      faster_elo = ratings[faster[:driver_id]] || INITIAL_ELO
      slower_elo = ratings[slower[:driver_id]] || INITIAL_ELO
      
      # Faster driver "wins" this lap comparison
      expected = expected_score(faster_elo, slower_elo)
      delta = K_FACTOR * (1 - expected) / 10.0  # Reduce K for individual laps
      
      updates[faster[:driver_id]][:delta_sum] += delta
      updates[faster[:driver_id]][:comparisons] += 1
      updates[slower[:driver_id]][:delta_sum] -= delta
      updates[slower[:driver_id]][:comparisons] += 1
    end
  end
  
  # Apply averaged updates
  updates.each do |driver_id, data|
    next if data[:comparisons] == 0
    avg_delta = data[:delta_sum] / data[:comparisons]
    ratings[driver_id] ||= INITIAL_ELO
    ratings[driver_id] += avg_delta
    driver_laps[driver_id] ||= 0
    driver_laps[driver_id] += 1
  end
end

# Main processing
STDERR.puts "Loading lap data from #{DB_PATH}..."
all_laps = load_lap_data(DB_PATH)
STDERR.puts "Loaded #{all_laps.length} laps"

# Group by class - each class has independent ratings
laps_by_class = all_laps.group_by { |l| l[:class] }

# Track which drivers have had their first event (for +1500 delta)
first_event_seen = {}  # [driver_id, class] => true

# Output storage
rows = []

laps_by_class.each do |klass, class_laps|
  STDERR.puts "Processing #{klass}: #{class_laps.length} laps"
  
  ratings = {}           # driver_id => current elo
  driver_laps = {}       # driver_id => lap count
  driver_names = {}      # driver_id => name
  driver_licenses = {}   # driver_id => license
  
  # Group by event and process chronologically
  events = group_by_event(class_laps)
  
  # Sort events by date
  sorted_events = events.sort_by do |key, laps|
    laps.first[:session_date] || '1970-01-01'
  end
  
  sorted_events.each do |(series, year, event, _), event_laps|
    session_date = event_laps.first[:session_date]
    
    # Track names and licenses
    event_laps.each do |lap|
      driver_names[lap[:driver_id]] = lap[:driver_name]
      driver_licenses[lap[:driver_id]] = lap[:license] if lap[:license]
    end
    
    # Snapshot pre-event state
    pre_event_elo = ratings.dup
    pre_event_laps = driver_laps.dup
    
    # Group by lap number and process
    laps_by_number = event_laps.group_by { |l| l[:lap] }
    laps_by_number.sort.each do |lap_num, lap_group|
      process_lap_comparisons(lap_group, ratings, driver_laps)
    end
    
    # Record history for drivers who participated
    participating_drivers = event_laps.map { |l| l[:driver_id] }.uniq
    participating_drivers.each do |driver_id|
      old_elo = pre_event_elo[driver_id] || INITIAL_ELO
      new_elo = ratings[driver_id] || INITIAL_ELO
      raw_delta = new_elo - old_elo
      old_laps = pre_event_laps[driver_id] || 0
      new_laps = driver_laps[driver_id] || 0
      event_lap_count = new_laps - old_laps
      
      next if event_lap_count == 0
      
      # Check if this is the driver's first event in this class
      first_key = [driver_id, klass]
      is_first = !first_event_seen[first_key]
      first_event_seen[first_key] = true
      
      # First event includes +1500 in delta so SUM(delta) = current elo
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
        cumulative_laps: new_laps,
        license: driver_licenses[driver_id]
      }
    end
  end
  
  # Print summary if requested
  if options[:summary]
    qualified = ratings.select { |id, _| (driver_laps[id] || 0) >= options[:min_laps] }
    next if qualified.empty?
    
    STDERR.puts "\n#{klass} (#{qualified.length} drivers with #{options[:min_laps]}+ laps):"
    STDERR.puts "-" * 60
    
    qualified.sort_by { |_, elo| -elo }.first(20).each_with_index do |(driver_id, elo), i|
      name = driver_names[driver_id] || driver_id
      laps = driver_laps[driver_id] || 0
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
