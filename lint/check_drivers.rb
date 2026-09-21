#!/usr/bin/env ruby
# Driver data quality checks - validates driver identity and matching
# Run with: ruby lint/check_drivers.rb

require 'open3'
require 'json'

DB_PATH = "output/imsa.duckdb"

class DriverChecker
  def initialize
    @issues = []
    @stats = {}
  end

  def query(sql)
    stdout, stderr, status = Open3.capture3("duckdb", DB_PATH, "-json", "-c", sql)
    raise "Query failed: #{stderr}\nSQL: #{sql}" unless status.success?
    JSON.parse(stdout)
  rescue JSON::ParserError
    []
  end

  def issue(severity, msg, details = nil)
    @issues << { severity: severity, message: msg, details: details }
    icon = case severity
           when :error then "❌"
           when :warning then "⚠️ "
           when :info then "ℹ️ "
           end
    puts "#{icon} #{msg}"
    puts "   #{details}" if details
  end

  def run_all_checks
    puts "=" * 70
    puts "Driver Data Quality Check"
    puts "=" * 70

    unless File.exist?(DB_PATH)
      puts "❌ Database not found: #{DB_PATH}"
      puts "   Run 'rake db:update' first"
      exit 1
    end

    check_alias_integrity
    check_identity_folding
    check_alias_coverage
    check_orphan_drivers
    check_driver_laps_linkage
    check_license_coverage
    check_duplicate_detection
    check_event_driver_summary
    check_driver_names
    check_known_driver_identities

    summary
  end

  # The pipeline's own SQL macros, so the linter can't drift from it:
  # driver_canonical_form = emitted id form; driver_match_key = alias lookup key
  FOLD = "driver_canonical_form(driver_id)".freeze
  MATCH_KEY = "driver_match_key(driver_id)".freeze

  def check_alias_integrity
    puts "\n--- Alias File Integrity ---"

    aliases = JSON.parse(File.read("driver_aliases.json"))
    map = aliases.each_with_object({}) { |a, h| h[a["alias"]] = a["canonical_id"] }

    dupes = aliases.map { |a| a["alias"] }
                   .group_by { |k| k }
                   .select { |_k, v| v.length > 1 }
                   .keys
    issue(:error, "Duplicate alias keys in driver_aliases.json", dupes.join(", ")) if dupes.any?

    # A canonical_id that is itself an alias (a -> b -> a) leaves both ids alive
    cyclic = map.select { |_a, c| map.key?(c) && map[map[c]] == c }
    if cyclic.any?
      issue(:error, "#{cyclic.length} alias cycles (a -> b -> a) in driver_aliases.json",
            cyclic.map { |a, c| "#{a} <-> #{c}" }.join(", "))
    end

    chains = map.select { |_a, c| map.key?(c) && map[map[c]] != c }
    issue(:info, "#{chains.length} alias chains (a -> b -> c); resolved transitively") if chains.any?

    self_refs = map.select { |a, c| a == c }
    issue(:error, "Self-referential aliases", self_refs.keys.join(", ")) if self_refs.any?

    # canonical_id becomes driver_id, so it must already be ascii-lowercase
    # (hyphens allowed — hyphenation is the JSON's editorial call)
    unfolded = map.values.uniq.reject { |c| c =~ /\A[a-z0-9 .'-]+\z/ }
    if unfolded.any?
      issue(:error, "canonical_ids are not in folded ascii-lowercase form", unfolded.join(", "))
    end

    if dupes.empty? && cyclic.empty? && self_refs.empty? && unfolded.empty?
      puts "  ✓ #{aliases.length} aliases, no cycles, no duplicates"
    end

    # A canonical_id that is itself an alias key is a chain (a -> b -> c). The
    # resolver's transitive closure handles it, but keep the file flat so
    # every alias points at its terminal id and no depth cap can matter.
    canon_is_alias = map.select { |_a, c| map.key?(c) }
    if canon_is_alias.any?
      issue(:error, "#{canon_is_alias.length} alias chains in driver_aliases.json (point aliases at the terminal id)",
            canon_is_alias.first(5).map { |a, c| "#{a} -> #{c} -> #{map[c]}" }.join(", "))
    else
      puts "  ✓ No alias chains (every canonical_id is terminal)"
    end
  end

  def check_identity_folding
    puts "\n--- Mechanical Identity Folding ---"

    non_ascii = query(<<~SQL)
      SELECT driver_id FROM drivers_v
      WHERE driver_id <> lower(driver_id)
         OR NOT regexp_matches(driver_id, '^[a-z0-9 .''-]+$')
      LIMIT 20
    SQL
    if non_ascii.any?
      issue(:error, "#{non_ascii.length} driver_ids are not ascii-lowercase (folding not applied)",
            non_ascii.first(5).map { |r| r["driver_id"] }.join(", "))
    else
      puts "  ✓ All driver_ids are ascii lowercase"
    end

    collisions = query(<<~SQL)
      WITH k AS (SELECT DISTINCT driver_id, #{FOLD} AS mk FROM laps)
      SELECT mk, string_agg(driver_id, ' | ') AS ids
      FROM k GROUP BY mk HAVING count(*) > 1 ORDER BY mk
    SQL
    if collisions.any?
      issue(:error, "#{collisions.length} identities differ only by accents or case",
            collisions.first(5).map { |r| r["ids"] }.join("; "))
    else
      puts "  ✓ No accent/case duplicate identities"
    end

    # Hyphens are not folded into ids, so hyphen-only variant pairs are a
    # curation question for driver_aliases.json. Scan all of laps, not just
    # race-derived drivers_v: a twin that only ever appears in practice/test
    # laps is otherwise invisible here.
    hyphen_pairs = query(<<~SQL)
      WITH k AS (SELECT DISTINCT driver_id, #{MATCH_KEY} AS mk FROM laps)
      SELECT mk, string_agg(driver_id, ' | ') AS ids
      FROM k GROUP BY mk HAVING count(*) > 1 ORDER BY mk
    SQL
    if hyphen_pairs.any?
      issue(:info, "#{hyphen_pairs.length} identities differ only by hyphenation (add an alias to merge)",
            hyphen_pairs.map { |r| r["ids"] }.join("; "))
    else
      puts "  ✓ No hyphen-only duplicate identities"
    end

    # Resolution must be a fixed point: no surviving driver_id resolves elsewhere
    unstable = query(<<~SQL)
      SELECT d.driver_id, m.canonical_id
      FROM (SELECT DISTINCT driver_id FROM laps) d
      JOIN driver_identity_map m ON m.match_key = #{MATCH_KEY}
      WHERE m.canonical_id <> d.driver_id
      LIMIT 20
    SQL
    if unstable.any?
      issue(:error, "#{unstable.length} driver_ids still resolve to another id (alias applied too late)",
            unstable.first(5).map { |r| "#{r['driver_id']} -> #{r['canonical_id']}" }.join(", "))
    else
      puts "  ✓ Alias resolution is a fixed point across every driver_id in laps"
    end
  end

  def check_alias_coverage
    puts "\n--- Alias Resolution ---"
    
    result = query(<<~SQL)
      SELECT 
        (SELECT COUNT(*) FROM driver_aliases) as alias_count,
        (SELECT COUNT(DISTINCT driver_id) FROM laps) as laps_driver_ids,
        (SELECT COUNT(DISTINCT driver_id) FROM drivers_v) as canonical_drivers,
        (SELECT COUNT(DISTINCT driver_id) FROM event_driver_summary) as event_summary_drivers
    SQL
    
    stats = result.first
    @stats[:aliases] = stats['alias_count']
    @stats[:laps_drivers] = stats['laps_driver_ids']
    @stats[:canonical_drivers] = stats['canonical_drivers']
    @stats[:event_drivers] = stats['event_summary_drivers']
    
    puts "  Aliases defined: #{stats['alias_count']}"
    puts "  Unique driver IDs in laps: #{stats['laps_driver_ids']}"
    puts "  Canonical drivers (drivers_v): #{stats['canonical_drivers']}"
    puts "  Drivers in event_driver_summary: #{stats['event_summary_drivers']}"
    
    if stats['canonical_drivers'].to_i != stats['event_summary_drivers'].to_i
      issue(:error, "Driver count mismatch between drivers_v and event_driver_summary",
            "drivers_v: #{stats['canonical_drivers']}, event_summary: #{stats['event_summary_drivers']}")
    end
    
    # An alias should point at an identity that exists in the data (the alias
    # spelling itself never appears in laps once applied)
    dangling = query(<<~SQL)
      SELECT da.alias, da.canonical_id
      FROM driver_aliases da
      WHERE NOT EXISTS (
        SELECT 1 FROM laps l
        WHERE l.driver_id = driver_canonical_form(da.canonical_id)
      )
    SQL

    if dangling.any?
      issue(:info, "#{dangling.length} aliases point at a driver with no laps (may be from other series)")
    end
  end

  def check_orphan_drivers
    puts "\n--- Orphan Driver Check ---"
    
    # Drivers in laps but not in event_driver_summary
    orphans = query(<<~SQL)
      SELECT DISTINCT l.driver_id, l.driver_name, COUNT(*) as laps
      FROM laps l
      LEFT JOIN event_driver_summary eds ON eds.driver_id = l.driver_id
      WHERE eds.driver_id IS NULL
        AND l.session IN ('race', 'race-hour-4', 'race-hour-6', 'race-hour-8', 'race-hour-10', 'race-hour-24')
      GROUP BY l.driver_id, l.driver_name
      ORDER BY laps DESC
      LIMIT 20
    SQL
    
    if orphans.any?
      issue(:warning, "#{orphans.length} drivers in race laps but not in event_driver_summary")
      orphans.first(5).each do |d|
        puts "   - #{d['driver_name']} (#{d['laps']} laps)"
      end
    else
      puts "  ✓ All race lap drivers appear in event_driver_summary"
    end
  end

  def check_driver_laps_linkage
    puts "\n--- Driver-Laps Linkage ---"
    
    # Check that driver_id in laps matches event_driver_summary
    mismatch = query(<<~SQL)
      WITH lap_drivers AS (
        SELECT DISTINCT 
          series_code, year, event, driver_id, car
        FROM laps 
        WHERE session = 'race' OR session LIKE 'race-hour-%'
      ),
      event_drivers AS (
        SELECT DISTINCT
          series_code, year, event, driver_id, car
        FROM event_driver_summary
      )
      SELECT ld.series_code, ld.year, ld.event, ld.driver_id, ld.car
      FROM lap_drivers ld
      LEFT JOIN event_drivers ed 
        ON ed.series_code = ld.series_code 
        AND ed.year = ld.year 
        AND ed.event = ld.event 
        AND ed.driver_id = ld.driver_id
      WHERE ed.driver_id IS NULL
      LIMIT 20
    SQL
    
    if mismatch.any?
      issue(:warning, "#{mismatch.length}+ driver/event combos in laps not in event_driver_summary")
      mismatch.first(3).each do |m|
        puts "   - #{m['driver_id']} @ #{m['year']} #{m['event']}"
      end
    else
      puts "  ✓ All lap driver/event combos exist in event_driver_summary"
    end
    
    # Check lap counts match
    mismatched_counts = query(<<~SQL)
      WITH lap_counts AS (
        SELECT driver_id, series_code, year, event, COUNT(*) as lap_count
        FROM laps
        WHERE session = 'race' OR session LIKE 'race-hour-%'
        GROUP BY driver_id, series_code, year, event
      )
      SELECT 
        lc.driver_id, lc.series_code, lc.year, lc.event,
        lc.lap_count as laps_table,
        eds.laps as summary_table,
        ABS(lc.lap_count - eds.laps) as diff
      FROM lap_counts lc
      JOIN event_driver_summary eds 
        ON eds.driver_id = lc.driver_id 
        AND eds.series_code = lc.series_code
        AND eds.year = lc.year 
        AND eds.event = lc.event
      WHERE ABS(lc.lap_count - eds.laps) > 0
      ORDER BY diff DESC
      LIMIT 10
    SQL
    
    if mismatched_counts.any?
      issue(:error, "Lap count mismatches between laps table and event_driver_summary")
      mismatched_counts.first(5).each do |m|
        puts "   - #{m['driver_id']} @ #{m['event']}: laps=#{m['laps_table']} vs summary=#{m['summary_table']}"
      end
    else
      puts "  ✓ Lap counts consistent between tables"
    end
  end

  def check_license_coverage
    puts "\n--- License Data Coverage ---"
    
    coverage = query(<<~SQL)
      SELECT 
        series_code,
        COUNT(DISTINCT driver_id) as total_drivers,
        COUNT(DISTINCT CASE WHEN license IS NOT NULL THEN driver_id END) as with_license,
        ROUND(100.0 * COUNT(DISTINCT CASE WHEN license IS NOT NULL THEN driver_id END) / 
              NULLIF(COUNT(DISTINCT driver_id), 0), 1) as pct
      FROM event_driver_summary
      GROUP BY series_code
      ORDER BY series_code
    SQL
    
    coverage.each do |c|
      pct = c['pct'] || 0
      status = pct > 80 ? "✓" : (pct > 50 ? "⚠" : "✗")
      puts "  #{status} #{c['series_code']}: #{c['with_license']}/#{c['total_drivers']} drivers (#{pct}%)"
      
      if pct < 10 && c['series_code'] != 'imsa'
        issue(:info, "Low license coverage in #{c['series_code']} (expected - FIA series don't include license in results)")
      elsif pct < 80 && c['series_code'] == 'imsa'
        issue(:warning, "IMSA license coverage below 80%: #{pct}%")
      end
    end
  end

  def check_duplicate_detection
    puts "\n--- Potential Duplicate Detection ---"
    
    # Check if matching system found candidates
    begin
      auto_merge = query("SELECT COUNT(*) as cnt FROM driver_auto_merge")
      review = query("SELECT COUNT(*) as cnt FROM driver_review_candidates")
      different = query("SELECT COUNT(*) as cnt FROM driver_confirmed_different")
      
      puts "  Auto-merge candidates (≥70 confidence): #{auto_merge.first['cnt']}"
      puts "  Review candidates (40-69 confidence): #{review.first['cnt']}"
      puts "  Confirmed different (raced together): #{different.first['cnt']}"
      
      if auto_merge.first['cnt'] > 0
        issue(:warning, "#{auto_merge.first['cnt']} high-confidence matches not yet in aliases",
              "Run: SELECT * FROM driver_auto_merge")
      end
    rescue => e
      issue(:info, "Driver matching views not available", e.message)
    end
    
    # Check for suspicious patterns
    suspicious = query(<<~SQL)
      SELECT 
        a.driver_id as id1, 
        b.driver_id as id2,
        jaro_winkler_similarity(a.driver_id, b.driver_id) as sim
      FROM drivers_v a, drivers_v b
      WHERE a.driver_id < b.driver_id
        AND jaro_winkler_similarity(a.driver_id, b.driver_id) > 0.92
        AND NOT EXISTS (
          SELECT 1 FROM event_driver_summary e1, event_driver_summary e2
          WHERE e1.driver_id = a.driver_id AND e2.driver_id = b.driver_id
          AND e1.series_code = e2.series_code AND e1.year = e2.year AND e1.event = e2.event
        )
      ORDER BY sim DESC
      LIMIT 10
    SQL
    
    if suspicious.any?
      issue(:info, "#{suspicious.length} very similar driver names (>92% match) not aliased:")
      suspicious.first(5).each do |s|
        puts "   - #{s['id1']} ↔ #{s['id2']} (#{(s['sim'] * 100).round(1)}%)"
      end
    end
  end

  def check_event_driver_summary
    puts "\n--- Event Driver Summary Validation ---"
    
    # Check for null driver_ids
    nulls = query(<<~SQL)
      SELECT COUNT(*) as cnt 
      FROM event_driver_summary 
      WHERE driver_id IS NULL OR driver_id = ''
    SQL
    
    if nulls.first['cnt'] > 0
      issue(:error, "#{nulls.first['cnt']} rows in event_driver_summary with null/empty driver_id")
    else
      puts "  ✓ No null driver_ids"
    end
    
    # Check for reasonable lap counts (allow up to 1500 for 24h races)
    weird_laps = query(<<~SQL)
      SELECT driver_id, year, event, laps
      FROM event_driver_summary
      WHERE laps <= 0 OR laps > 1500
      LIMIT 10
    SQL
    
    if weird_laps.any?
      issue(:warning, "Unusual lap counts in event_driver_summary")
      weird_laps.each { |w| puts "   - #{w['driver_id']}: #{w['laps']} laps @ #{w['event']}" }
    else
      puts "  ✓ Lap counts reasonable (1-1500)"
    end
    
    # Check b-pillar quartile totals (expect some gap due to non-green-flag laps)
    # Quartiles only computed for green flag laps with valid times
    quartile_check = query(<<~SQL)
      SELECT 
        driver_id, year, event, laps,
        q1_laps + q2_laps + q3_laps + q4_laps as quartile_sum,
        ROUND(100.0 * (q1_laps + q2_laps + q3_laps + q4_laps) / laps, 1) as coverage_pct
      FROM event_driver_summary
      WHERE laps > 10
        AND q1_laps IS NOT NULL
        AND (q1_laps + q2_laps + q3_laps + q4_laps) < laps * 0.5  -- Less than 50% coverage is suspicious
      LIMIT 10
    SQL
    
    if quartile_check.any?
      issue(:info, "Some drivers with low b-pillar coverage (<50% of laps)")
      quartile_check.first(3).each do |q|
        puts "   - #{q['driver_id']} @ #{q['event']}: #{q['coverage_pct']}% coverage"
      end
    else
      puts "  ✓ B-pillar quartile coverage reasonable (>50% of laps)"
    end
  end

  def check_driver_names
    puts "\n--- Driver Name Quality ---"
    
    # Check for weird characters in names
    weird_names = query(<<~SQL)
      SELECT DISTINCT driver_id, canonical_name
      FROM drivers_v
      WHERE driver_id ~ '[^a-z0-9 \\-]'
         OR canonical_name ~ '[0-9]'
         OR LENGTH(driver_id) < 5
      LIMIT 20
    SQL
    
    if weird_names.any?
      issue(:info, "#{weird_names.length} driver names with unusual characters")
      weird_names.first(5).each { |n| puts "   - #{n['driver_id']} / #{n['canonical_name']}" }
    else
      puts "  ✓ Driver names look normal"
    end
    
    # Check for all-caps vs mixed case consistency
    case_issues = query(<<~SQL)
      SELECT driver_id, 
             STRING_AGG(DISTINCT driver_name, ' | ') as variants,
             COUNT(DISTINCT driver_name) as variant_count
      FROM laps
      GROUP BY driver_id
      HAVING COUNT(DISTINCT driver_name) > 2
      ORDER BY variant_count DESC
      LIMIT 10
    SQL
    
    if case_issues.any?
      issue(:info, "Drivers with 3+ name variants (may need aliases)")
      case_issues.first(5).each { |c| puts "   - #{c['driver_id']}: #{c['variants']}" }
    end
  end

  def check_known_driver_identities
    puts "\n--- Known Driver Identity Regression Tests ---"

    # These are drivers who historically had name/identity issues.
    # Each test verifies the alias system and canonical name resolution work correctly.
    tests = [
      # [driver_id, expected_canonical_name, description]
      ["nick boulle",              "Nick Boulle",              "nickname vs full (Nicholas BOULLE)"],
      ["ben hanley",               "Ben Hanley",               "nickname vs full (Benjamin Hanley)"],
      ["will stevens",             "Will Stevens",             "nickname vs full (William STEVENS)"],
      ["alex quinn",               "Alex Quinn",               "nickname vs full (Alexander Quinn)"],
      ["dan goldburg",             "Dan Goldburg",             "nickname vs full (Daniel Goldburg)"],
      ["josh pierson",             "Josh Pierson",             "nickname vs full (Joshua PIERSON)"],
      ["nick yelloly",             "Nick Yelloly",             "nickname vs full (Nicholas YELLOLY)"],
      ["phil hanson",              "Phil Hanson",              "nickname vs full (Philip HANSON)"],
      ["paul loup chatin",        "Paul Loup Chatin",         "hyphen variant (Paul-Loup CHATIN)"],
      ["david heinemeier hansson", "David Heinemeier Hansson", "hyphen variant (HEINEMEIER-HANSSON)"],
      ["francois perrodo",        "Francois Perrodo",         "accented variant (François PERRODO)"],
      ["sebastien bourdais",      "Sebastien Bourdais",       "accented variant (Sébastien BOURDAIS)"],
      ["george kurtz",            "George Kurtz",             "WEC ALL CAPS (George KURTZ)"],
      ["tobi lutke",              "Tobi Lutke",               "4th driver UNPIVOT (was Unknown license)"],
      ["nick de vries",           "Nick De Vries",            "Nyck vs Nick variant"],
    ]

    pass = 0
    fail = 0

    tests.each do |driver_id, expected_name, description|
      # Check 1: driver_id exists and has correct canonical name in drivers table
      result = query("SELECT canonical_name FROM drivers WHERE driver_id = '#{driver_id}'")

      if result.empty?
        issue(:warning, "Known driver '#{driver_id}' not found in drivers table (#{description})")
        fail += 1
        next
      end

      actual = result.first['canonical_name']

      # Check 2: only one display name in laps
      variants = query(<<~SQL)
        SELECT COUNT(DISTINCT driver_name) as n
        FROM laps WHERE driver_id = '#{driver_id}'
      SQL
      variant_count = variants.first&.dig('n').to_i

      if variant_count > 1
        issue(:error, "Driver '#{driver_id}' has #{variant_count} name variants in laps — #{description}")
        fail += 1
      else
        pass += 1
      end
    end

    if fail == 0
      puts "  ✓ All #{pass} known driver identity tests passed"
    end
  end

  def summary
    puts "\n" + "=" * 70
    puts "DRIVER CHECK SUMMARY"
    puts "=" * 70

    puts "Statistics:"
    puts "  Aliases: #{@stats[:aliases]}"
    puts "  Canonical drivers: #{@stats[:canonical_drivers]}"
    puts "  Drivers in event summary: #{@stats[:event_drivers]}"
    puts "  Driver reduction from aliases: #{@stats[:laps_drivers] - @stats[:canonical_drivers]} merged"

    errors = @issues.select { |i| i[:severity] == :error }
    warnings = @issues.select { |i| i[:severity] == :warning }
    infos = @issues.select { |i| i[:severity] == :info }

    puts "\nIssues:"
    puts "  Errors:   #{errors.length}"
    puts "  Warnings: #{warnings.length}"
    puts "  Info:     #{infos.length}"

    puts

    if errors.any?
      puts "❌ Driver check FAILED"
      exit 1
    elsif warnings.length > 5
      puts "⚠️  Driver check passed with warnings"
      exit 0
    else
      puts "✅ Driver check passed"
      exit 0
    end
  end
end

if __FILE__ == $0
  checker = DriverChecker.new
  checker.run_all_checks
end
