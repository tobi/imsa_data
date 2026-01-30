#!/usr/bin/env ruby
# frozen_string_literal: true

# Plackett-Luce Rating System for Motorsport
#
# For each race, for each lap number, all drivers in the specified class(es)
# who completed that lap are ranked by lap time. This ranking is used to
# update driver/car ratings using the Plackett-Luce model.
#
# Plackett-Luce models the probability of a ranking as:
#   P(r1 > r2 > ... > rn) = ∏ γ_ri / (γ_ri + γ_r(i+1) + ... + γ_rn)
#
# Where γ_i = exp(skill_i) is the "strength" of player i.
#
# Ratings are displayed in Elo-style format (centered at 1500).

require 'csv'
require 'optparse'
require 'set'

class PlackettLuceRating
  attr_accessor :skill, :sigma, :laps_completed, :last_seen, :last_seen_date, :series_seen, :license
  attr_accessor :skill_12m_ago, :skill_before_last_race, :skill_at_session_start
  attr_accessor :laps_in_session

  INITIAL_SKILL = 0.0
  INITIAL_SIGMA = 2.0
  MIN_SIGMA = 0.3

  def initialize
    @skill = INITIAL_SKILL
    @sigma = INITIAL_SIGMA
    @laps_completed = 0
    @last_seen = ""
    @last_seen_date = ""
    @series_seen = Set.new
    @license = nil
    @skill_12m_ago = nil
    @skill_before_last_race = nil
    @skill_at_session_start = nil
    @laps_in_session = 0
  end

  def gamma
    Math.exp(@skill)
  end

  def conservative
    @skill - 2 * @sigma
  end

  def delta_12m
    return nil unless @skill_12m_ago
    @skill - @skill_12m_ago
  end

  def delta_last_race
    return nil unless @skill_before_last_race
    @skill - @skill_before_last_race
  end
end

class PlackettLuceEngine
  BASE_LEARNING_RATE = 0.04
  SIGMA_DECAY = 0.997

  def self.update_ratings(rankings, ratings_hash)
    return if rankings.size < 2

    n = rankings.size
    entities = rankings.map { |key, _| key }
    gammas = entities.map { |e| ratings_hash[e].gamma }

    suffix_sums = Array.new(n, 0.0)
    suffix_sums[n - 1] = gammas[n - 1]
    (n - 2).downto(0) do |i|
      suffix_sums[i] = gammas[i] + suffix_sums[i + 1]
    end

    gradients = Array.new(n, 0.0)
    entities.each_with_index do |_entity, i|
      positive = 1.0
      negative = 0.0
      (0..i).each do |j|
        negative += gammas[i] / suffix_sums[j]
      end
      gradients[i] = positive - negative
    end

    entities.each_with_index do |entity, i|
      rating = ratings_hash[entity]
      lr = BASE_LEARNING_RATE * (rating.sigma / PlackettLuceRating::INITIAL_SIGMA)
      rating.skill += lr * gradients[i]
      rating.sigma = [rating.sigma * SIGMA_DECAY, PlackettLuceRating::MIN_SIGMA].max
    end
  end
end

class RatingSystem
  ELO_CENTER = 1500
  ELO_SCALE = 400

  def initialize(db_path, options)
    @db_path = db_path
    @options = options
    @driver_ratings = Hash.new { |h, k| h[k] = PlackettLuceRating.new }
    @car_ratings = Hash.new { |h, k| h[k] = PlackettLuceRating.new }
    @history = []  # For --output-history: records Elo after each event
  end

  def load_race_laps
    classes = @options[:classes].map { |c| "'#{c}'" }.join(', ')

    conditions = [
      "class IN (#{classes})",
      "session ILIKE '%race%'",
      "lap_time IS NOT NULL",
      "lap_time > 0",
      "lap_time < 600"
    ]

    if @options[:until]
      conditions << "start_date <= '#{@options[:until]}'"
    end

    query = <<~SQL
      SELECT series_code, year, event, session, start_date, car, driver, lap, lap_time, license
      FROM laps
      WHERE #{conditions.join(' AND ')}
      ORDER BY start_date, session, lap, lap_time
    SQL

    $stderr.puts "Querying database for #{@options[:classes].join(', ')} race laps..."
    csv_output = `duckdb "#{@db_path}" -csv -c "#{query.gsub("\n", ' ')}"`

    laps = []
    CSV.parse(csv_output, headers: true) do |row|
      laps << {
        series_code: row['series_code'], year: row['year'], event: row['event'],
        session: row['session'], start_date: row['start_date'], car: row['car'],
        driver: row['driver'], lap: row['lap'].to_i, lap_time: row['lap_time'].to_f,
        license: row['license']
      }
    end
    laps
  end

  def process_ratings
    laps = load_race_laps
    $stderr.puts "Found #{format_number(laps.size)} race laps"
    $stderr.puts "Processing Plackett-Luce ratings..."

    # Find max date to calculate 12-month cutoff
    max_date = laps.map { |l| l[:start_date] }.max
    cutoff_12m = date_minus_months(max_date, 12) if max_date
    crossed_12m = false

    current_session, current_lap, lap_group = nil, nil, []
    drivers_in_session = Set.new
    current_session_meta = nil  # Track metadata for history recording

    laps.each_with_index do |lap_data, idx|
      session_key = [lap_data[:start_date], lap_data[:session]]
      lap_num = lap_data[:lap]
      current_date = lap_data[:start_date]

      # Check if we've crossed the 12-month cutoff
      if !crossed_12m && cutoff_12m && current_date >= cutoff_12m
        crossed_12m = true
        # Snapshot all existing driver skills as "12 months ago"
        @driver_ratings.each_value { |r| r.skill_12m_ago = r.skill }
      end

      # New session started
      if session_key != current_session
        # Finalize previous session - update "before last race" for drivers who participated
        drivers_in_session.each do |driver|
          rating = @driver_ratings[driver]
          rating.skill_before_last_race = rating.skill_at_session_start
        end

        # Process remaining lap group from previous session
        process_lap_group(lap_group) if lap_group.size >= 2

        # Record history for drivers in the completed session
        if @options[:output_history] && current_session_meta && drivers_in_session.any?
          record_session_history(drivers_in_session, current_session_meta)
        end

        # Start new session
        current_session = session_key
        current_lap = nil
        lap_group = []
        drivers_in_session = Set.new

        # Store metadata for the new session
        current_session_meta = {
          session_date: lap_data[:start_date],
          event: lap_data[:event],
          series_code: lap_data[:series_code],
          year: lap_data[:year]
        }

        # Reset laps_in_session for all drivers
        @driver_ratings.each_value { |r| r.laps_in_session = 0 }

        # Snapshot skill at session start for all drivers we'll see
        @driver_ratings.each { |name, r| r.skill_at_session_start = r.skill }
      end

      # New lap within session
      if lap_num != current_lap
        process_lap_group(lap_group) if lap_group.size >= 2
        current_lap = lap_num
        lap_group = []
      end

      lap_group << lap_data
      drivers_in_session << lap_data[:driver] if lap_data[:driver]

      $stderr.puts "  Processed #{format_number(idx + 1)} laps..." if (idx + 1) % 50_000 == 0
    end

    # Finalize last session
    drivers_in_session.each do |driver|
      rating = @driver_ratings[driver]
      rating.skill_before_last_race = rating.skill_at_session_start
    end
    process_lap_group(lap_group) if lap_group.size >= 2

    # Record history for the final session
    if @options[:output_history] && current_session_meta && drivers_in_session.any?
      record_session_history(drivers_in_session, current_session_meta)
    end

    $stderr.puts "Done! Rated #{@driver_ratings.size} drivers and #{@car_ratings.size} cars"
  end

  def record_session_history(drivers, meta)
    drivers.each do |driver|
      rating = @driver_ratings[driver]
      delta = rating.skill_at_session_start ? rating.skill - rating.skill_at_session_start : 0.0
      @history << {
        driver: driver,
        session_date: meta[:session_date],
        event: meta[:event],
        series_code: meta[:series_code],
        class: @options[:classes].first,  # Primary class being rated
        elo: skill_to_elo(rating.skill),
        delta: (delta * ELO_SCALE).round,
        laps: rating.laps_in_session,
        cumulative_laps: rating.laps_completed,
        license: rating.license || ""
      }
    end
  end

  def date_minus_months(date_str, months)
    return nil unless date_str
    year, month, day = date_str.split('-').map(&:to_i)
    month -= months
    while month <= 0
      month += 12
      year -= 1
    end
    "%04d-%02d-%02d" % [year, month, [day, days_in_month(year, month)].min]
  end

  def days_in_month(year, month)
    [nil, 31, (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0) ? 29 : 28,
     31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month]
  end

  def format_number(n)
    n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def process_lap_group(lap_group)
    return if lap_group.size < 2

    sorted_laps = lap_group.sort_by { |l| l[:lap_time] }
    driver_rankings = []
    car_rankings = []

    sorted_laps.each_with_index do |lap_data, rank|
      driver, car = lap_data[:driver], lap_data[:car]
      next unless driver && car && !driver.empty? && !car.empty?

      @driver_ratings[driver].laps_completed += 1
      @driver_ratings[driver].laps_in_session += 1
      @driver_ratings[driver].last_seen = "#{lap_data[:year]} #{lap_data[:event]}"
      @driver_ratings[driver].last_seen_date = lap_data[:start_date]
      @driver_ratings[driver].series_seen << lap_data[:series_code]
      @driver_ratings[driver].license = lap_data[:license] if lap_data[:license]&.length&.positive?

      @car_ratings[car].laps_completed += 1
      @car_ratings[car].series_seen << lap_data[:series_code]

      driver_rankings << [driver, rank]
      car_rankings << [car, rank]
    end

    PlackettLuceEngine.update_ratings(driver_rankings, @driver_ratings) if driver_rankings.size >= 2
    PlackettLuceEngine.update_ratings(car_rankings, @car_ratings) if car_rankings.size >= 2
  end

  def skill_to_elo(skill)
    (ELO_CENTER + skill * ELO_SCALE).round
  end

  def current_cutoff_date
    # "Current" means active in the last 12 months from the most recent data
    max_date = @driver_ratings.values.map(&:last_seen_date).max
    return nil unless max_date

    year, month, day = max_date.split('-').map(&:to_i)
    year -= 1
    "%04d-%02d-%02d" % [year, month, day]
  end

  def print_standings
    min_laps = @options[:min_laps]
    cutoff = @options[:current] ? current_cutoff_date : nil

    by_license = Hash.new { |h, k| h[k] = [] }
    @driver_ratings.each do |name, rating|
      next if rating.laps_completed < min_laps
      next if cutoff && rating.last_seen_date < cutoff
      by_license[rating.license || "Unknown"] << [name, rating]
    end

    total_shown = 0
    %w[Platinum Gold Silver Bronze Unknown].each do |license|
      drivers = by_license[license]
      next if drivers.empty?

      sorted = drivers.sort_by { |_, r| -r.conservative }

      puts ""
      puts "=" * 115
      puts "#{license.upcase} (#{drivers.size} drivers)"
      puts "=" * 115
      puts "%-4s %-30s %6s %7s %7s %7s  %-18s" % ['#', 'Name', 'Elo', 'Δ12mo', 'ΔRace', 'Laps', 'Last Seen']
      puts '-' * 115

      sorted.each_with_index do |(name, rating), idx|
        elo = skill_to_elo(rating.skill)
        delta_12m = format_delta(rating.delta_12m)
        delta_race = format_delta(rating.delta_last_race)
        puts "%-4d %-30s %6d %7s %7s %7d  %-18s" % [
          idx + 1, name[0, 29], elo, delta_12m, delta_race,
          rating.laps_completed, rating.last_seen[0, 17]
        ]
      end
      total_shown += drivers.size
    end

    # Statistics
    $stderr.puts ""
    $stderr.puts "Total: #{total_shown} drivers shown (min #{min_laps} laps#{cutoff ? ', active since ' + cutoff : ''})"

    skills = @driver_ratings.values.select { |v| v.laps_completed >= min_laps }.map(&:skill)
    if skills.any?
      $stderr.puts "Elo range: #{skill_to_elo(skills.min)} - #{skill_to_elo(skills.max)}"
    end
  end

  def format_delta(delta)
    return "-" unless delta
    elo_delta = (delta * ELO_SCALE).round
    elo_delta >= 0 ? "+#{elo_delta}" : elo_delta.to_s
  end

  def print_history
    puts "driver,session_date,event,series_code,class,elo,delta,laps,cumulative_laps,license"
    @history.sort_by { |h| [h[:session_date], h[:driver]] }.each do |h|
      puts [
        csv_escape(h[:driver]),
        h[:session_date],
        csv_escape(h[:event]),
        h[:series_code],
        csv_escape(h[:class]),
        h[:elo],
        h[:delta],
        h[:laps],
        h[:cumulative_laps],
        h[:license]
      ].join(',')
    end
    $stderr.puts "Output #{@history.size} history records"
  end

  def csv_escape(str)
    return str unless str.to_s.include?(',') || str.to_s.include?('"')
    '"' + str.to_s.gsub('"', '""') + '"'
  end
end

# Default classes for LMP2
DEFAULT_CLASSES = ['LMP2', 'LMP2 Pro/Am', 'LMP2 PRO/AM'].freeze

AVAILABLE_CLASSES = %w[
  DPi GTD GTDPRO GTDPro GTLM GTP HYPERCAR LMGT3 LMP2 LMP3
].freeze

if __FILE__ == $PROGRAM_NAME
  options = {
    classes: DEFAULT_CLASSES.dup,
    current: true,
    until: nil,
    min_laps: 50,
    output_history: false
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

    opts.on('-c', '--class CLASS', "Class to rate (can specify multiple times). Default: LMP2") do |c|
      # Reset default on first explicit class
      options[:classes] = [] if options[:classes] == DEFAULT_CLASSES

      # Handle LMP2 variants
      if c.upcase == 'LMP2'
        options[:classes] += ['LMP2', 'LMP2 Pro/Am', 'LMP2 PRO/AM']
      else
        options[:classes] << c
      end
    end

    opts.on('--[no-]current', "Only show drivers active in last 12 months (default: on)") do |v|
      options[:current] = v
    end

    opts.on('-u', '--until DATE', "Only include data up to DATE (YYYY-MM-DD)") do |d|
      options[:until] = d
    end

    opts.on('-m', '--min-laps N', Integer, "Minimum laps to be included (default: 50)") do |n|
      options[:min_laps] = n
    end

    opts.on('--list-classes', "List available classes and exit") do
      puts "Available classes: #{AVAILABLE_CLASSES.join(', ')}"
      puts "Note: 'LMP2' automatically includes 'LMP2 Pro/Am' variants"
      exit
    end

    opts.on('--output-history', "Output CSV history with Elo after each event (for time-series)") do
      options[:output_history] = true
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit
    end
  end.parse!

  options[:classes].uniq!

  system = RatingSystem.new("output/imsa.duckdb", options)
  system.process_ratings

  if options[:output_history]
    system.print_history
  else
    system.print_standings
  end
end
