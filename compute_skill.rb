#!/usr/bin/env ruby
# frozen_string_literal: true

# Compute driver skill ratings using Plackett-Luce (Weng–Lin).
#
# Each green-flag wall-clock window is ONE multiplayer match: the full field is
# ranked by pace and updated in a single Plackett-Luce step. Every driver carries
# mu (skill) and sigma (uncertainty); ordinal = mu - 3*sigma.
#
# TWO POOLS in the same csv:
#   overall: license-seeded, full same-class field
#            skill_mu/skill_sigma/ordinal/elo
#   peer:    same windows, same-license only (flat seed)
#            peer_mu/peer_sigma/peer_ordinal/peer_elo
#
# DuckDB pre-aggregates green laps into (event, window, driver) medians so this
# script only rates ~windows, not raw laps.
#
# Usage:
#   ruby compute_skill.rb                 # CSV to stdout
#   ruby compute_skill.rb --summary       # leaderboards on stderr
#   ruby compute_skill.rb -m 50           # min green laps for summary
#   ruby compute_skill.rb --bucket 600    # window width seconds (default 600)

require "csv"
require "open3"
require "optparse"
require "time"
require_relative "lib/plackett_luce"

BUCKET_SECONDS = 600
DB_PATH = File.expand_path("output/imsa.duckdb", __dir__)

LICENSE_MU = {
  "Bronze" => 22.0,
  "Silver" => 25.0,
  "Gold" => 28.0,
  "Platinum" => 31.0
}.freeze
DEFAULT_MU = PlackettLuce::DEFAULT_MU
DEFAULT_SIGMA = PlackettLuce::DEFAULT_SIGMA
TAU_PER_YEAR = 3.0
ELO_SCALE = 25.0
ELO_CENTER = 1500.0
MEDIAN_MIN_LAPS = 100
MEDIAN_MIN_DRIVERS = 5

HEADER = %w[
  driver_id driver_name class series_code year event session_date
  laps cumulative_laps license
  skill_mu skill_sigma ordinal elo
  peer_mu peer_sigma peer_ordinal peer_elo
].freeze

def duckdb_csv(sql)
  stdout, stderr, status = Open3.capture3(
    "duckdb", "-readonly", "-no-stdin", DB_PATH,
    "-csv", "-nullvalue", "", "-c", sql
  )
  abort("duckdb failed: #{stderr}") unless status.success?
  CSV.parse(stdout, headers: true)
end

def blank?(v)
  v.nil? || v.empty?
end

def parse_date(s)
  return nil if blank?(s)
  Time.parse(s)
rescue ArgumentError
  nil
end

def median(values)
  sorted = values.sort
  n = sorted.length
  return nil if n.zero?
  mid = n / 2
  n.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
end

def widen_sigma!(sigma, did, years)
  return if years.nil? || years <= 0
  extra = TAU_PER_YEAR * years
  new_sigma = Math.sqrt(sigma[did]**2 + extra**2)
  new_sigma = DEFAULT_SIGMA if new_sigma > DEFAULT_SIGMA
  sigma[did] = new_sigma if new_sigma > sigma[did]
end

def field_median(mu, sigma, green_laps)
  established = []
  mu.each_key do |did|
    established << (mu[did] - 3.0 * sigma[did]) if green_laps[did] >= MEDIAN_MIN_LAPS
  end
  established = mu.map { |did, m| m - 3.0 * sigma[did] } if established.size < MEDIAN_MIN_DRIVERS
  return 0.0 if established.empty?
  median(established)
end

def to_elo(ordinal, mid)
  ELO_CENTER + ELO_SCALE * (ordinal - mid)
end

def rate_ids!(ids, mu, sigma)
  return if ids.size < 2
  mus = ids.map { |id| mu[id] }
  sigs = ids.map { |id| sigma[id] }
  PlackettLuce.update_sorted!(mus, sigs)
  ids.each_with_index do |id, i|
    mu[id] = mus[i]
    sigma[id] = sigs[i]
  end
end

options = { summary: false, min_laps: 0, bucket: BUCKET_SECONDS }
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.on("--summary", "print leaderboards to stderr") { options[:summary] = true }
  opts.on("-m", "--min-laps LAPS", Integer, "min green laps for summary") { |v| options[:min_laps] = v }
  opts.on("--bucket SECONDS", Integer, "window width seconds") { |v| options[:bucket] = v }
end.parse!

bucket = Integer(options[:bucket])
abort("database not found: #{DB_PATH}") unless File.exist?(DB_PATH)

warn "Loading window medians from #{DB_PATH}..."

meta_sql = <<~SQL
  WITH race AS (
    SELECT
      driver_id,
      driver_name,
      COALESCE(class_category, class) AS class,
      start_date,
      session_time,
      license
    FROM laps
    WHERE (session = 'race' OR session LIKE 'race-hour-%')
      AND lap_time IS NOT NULL
      AND driver_id IS NOT NULL
  )
  SELECT
    class,
    driver_id,
    last(driver_name ORDER BY start_date, session_time) AS driver_name,
    first(license ORDER BY start_date, session_time)
      FILTER (WHERE license IS NOT NULL AND license <> '') AS license
  FROM race
  GROUP BY class, driver_id
SQL

window_sql = <<~SQL
  WITH race AS (
    SELECT
      driver_id,
      COALESCE(class_category, class) AS class,
      series_code,
      year,
      event,
      lap,
      CAST(lap_time AS DOUBLE) AS lap_time,
      CAST(session_time AS DOUBLE) AS session_time,
      flags,
      CAST(pit_time AS DOUBLE) AS pit_time,
      start_date AS session_date
    FROM laps
    WHERE (session = 'race' OR session LIKE 'race-hour-%')
      AND lap_time IS NOT NULL
      AND driver_id IS NOT NULL
      AND lap_time > 0
  ),
  event_flag AS (
    SELECT class, series_code, year, event,
           BOOL_OR(flags IS NOT NULL AND flags <> '') AS has_flags
    FROM race
    GROUP BY 1, 2, 3, 4
  ),
  green AS (
    SELECT r.*
    FROM race r
    JOIN event_flag e USING (class, series_code, year, event)
    WHERE r.pit_time IS NULL
      AND (NOT e.has_flags OR r.flags = 'GF')
  )
  SELECT
    class,
    series_code,
    year,
    event,
    MIN(session_date) AS session_date,
    CAST(floor(
      (COALESCE(session_time - lap_time / 2.0, lap * 100.0)) / #{bucket}
    ) AS INTEGER) AS win,
    driver_id,
    MEDIAN(lap_time) AS rep_time,
    MIN(COALESCE(session_time, lap * 100.0)) AS first_seen,
    COUNT(*) AS laps
  FROM green
  GROUP BY class, series_code, year, event, win, driver_id
  ORDER BY class, session_date, series_code, year, event, win, rep_time, first_seen
SQL

names = Hash.new { |h, k| h[k] = {} }
licenses = Hash.new { |h, k| h[k] = {} }
duckdb_csv(meta_sql).each do |row|
  klass = row["class"]
  did = row["driver_id"]
  names[klass][did] = row["driver_name"]
  licenses[klass][did] = row["license"] unless blank?(row["license"])
end

window_rows = duckdb_csv(window_sql)
warn "Loaded #{window_rows.size} driver-windows"

by_class = Hash.new { |h, k| h[k] = [] }
window_rows.each do |row|
  by_class[row["class"]] << {
    series: row["series_code"],
    year: row["year"],
    event: row["event"],
    session_date: row["session_date"],
    window: row["win"].to_i,
    driver_id: row["driver_id"],
    rep_time: row["rep_time"].to_f,
    laps: row["laps"].to_i
  }
end
window_rows = nil

out_rows = []

by_class.each do |klass, class_rows|
  warn "Processing #{klass}: #{class_rows.size} driver-windows"
  class_names = names[klass]
  class_lic = licenses[klass]

  overall_mu = {}
  overall_sigma = {}
  peer_mu = {}
  peer_sigma = {}
  green_laps = Hash.new(0)
  last_seen = {}
  history = []

  events = class_rows.group_by { |r| [r[:series], r[:year], r[:event]] }
  sorted_events = events.sort_by { |_key, rows| rows.first[:session_date] || "1970-01-01" }

  sorted_events.each do |ekey, event_rows|
    session_date = event_rows.first[:session_date]
    event_date = parse_date(session_date)
    event_green = Hash.new(0)
    event_rows.each { |r| event_green[r[:driver_id]] += r[:laps] }
    participants = event_green.keys

    participants.each do |did|
      lic = class_lic[did]
      if !overall_mu.key?(did)
        overall_mu[did] = LICENSE_MU.fetch(lic, DEFAULT_MU)
        overall_sigma[did] = DEFAULT_SIGMA
        peer_mu[did] = DEFAULT_MU
        peer_sigma[did] = DEFAULT_SIGMA
      elsif event_date && last_seen[did]
        years = ((event_date - last_seen[did]) / 86_400.0).to_i / 365.25
        widen_sigma!(overall_sigma, did, years)
        widen_sigma!(peer_sigma, did, years)
      end
    end

    windows = event_rows.group_by { |r| r[:window] }
    windows.keys.sort.each do |w|
      reps = windows[w]
      next if reps.size < 2
      ids = reps.map { |r| r[:driver_id] }
      rate_ids!(ids, overall_mu, overall_sigma)

      by_tier = Hash.new { |h, k| h[k] = [] }
      ids.each { |did| by_tier[class_lic[did]] << did }
      by_tier.each_value { |tier_ids| rate_ids!(tier_ids, peer_mu, peer_sigma) }
    end

    event_green.each do |did, cnt|
      green_laps[did] += cnt
      last_seen[did] = event_date if event_date
      omu = overall_mu[did]
      osig = overall_sigma[did]
      pmu = peer_mu[did]
      psig = peer_sigma[did]
      history << [
        ekey, session_date, did, cnt,
        omu, osig, omu - 3.0 * osig,
        pmu, psig, pmu - 3.0 * psig
      ]
    end
  end

  overall_median = field_median(overall_mu, overall_sigma, green_laps)
  tier_mu = Hash.new { |h, k| h[k] = {} }
  tier_sigma = Hash.new { |h, k| h[k] = {} }
  peer_mu.each_key do |did|
    tier = class_lic[did] || ""
    tier_mu[tier][did] = peer_mu[did]
    tier_sigma[tier][did] = peer_sigma[did]
  end
  peer_median = {}
  tier_mu.each { |tier, tmu| peer_median[tier] = field_median(tmu, tier_sigma[tier], green_laps) }

  cum = Hash.new(0)
  history.each do |ekey, session_date, did, cnt, omu, osig, oord, pmu, psig, pord|
    series, year, event = ekey
    cum[did] += cnt
    lic = class_lic[did] || ""
    out_rows << [
      did, class_names[did], klass, series, year, event, session_date,
      cnt, cum[did], lic,
      omu.round(4), osig.round(4), oord.round(4), to_elo(oord, overall_median).round,
      pmu.round(4), psig.round(4), pord.round(4), to_elo(pord, peer_median[lic] || 0.0).round
    ]
  end

  next unless options[:summary]

  qualified = overall_mu.keys.select { |did| green_laps[did] >= options[:min_laps] }
  next if qualified.empty?

  warn "\n#{klass} OVERALL (#{qualified.size} drivers, #{options[:min_laps]}+ green laps, " \
       "median ord=#{format('%.2f', overall_median)} -> elo 1500):"
  warn "-" * 76
  qualified.sort_by { |did| -(overall_mu[did] - 3.0 * overall_sigma[did]) }
           .first(15)
           .each_with_index do |did, i|
    ordn = overall_mu[did] - 3.0 * overall_sigma[did]
    warn format("%3d. %-25s ord=%6.2f  sig=%4.2f  elo=%4d  %4d laps  [%s]",
                i + 1, class_names[did] || did, ordn, overall_sigma[did],
                to_elo(ordn, overall_median).round, green_laps[did], class_lic[did] || "-")
  end

  br = qualified.select { |did| class_lic[did] == "Bronze" }
  next if br.empty?
  bm = peer_median["Bronze"] || 0.0
  warn "\n#{klass} WITHIN-BRONZE peer pool (#{br.size} drivers, " \
       "median ord=#{format('%.2f', bm)} -> peer_elo 1500):"
  warn "-" * 76
  br.sort_by { |did| -(peer_mu[did] - 3.0 * peer_sigma[did]) }
    .first(15)
    .each_with_index do |did, i|
    ordn = peer_mu[did] - 3.0 * peer_sigma[did]
    warn format("%3d. %-25s peer_ord=%6.2f  sig=%4.2f  peer_elo=%4d  %4d laps",
                i + 1, class_names[did] || did, ordn, peer_sigma[did],
                to_elo(ordn, bm).round, green_laps[did])
  end
end

puts HEADER.join(",")
out_rows.sort_by { |r| [r[6].to_s, r[2].to_s, r[0].to_s] }.each do |r|
  puts r.join(",")
end

warn "\nWrote #{out_rows.length} rows"
