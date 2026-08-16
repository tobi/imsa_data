#!/usr/bin/env ruby
# Driver name normalization tests.
#
#   ruby test_driver_normalization.rb          # run the assertions
#   ruby test_driver_normalization.rb --demo   # dump what a sample laps CSV would change
#
# Two things are covered:
#   1. lib/driver_normalizer.rb  -- the Ruby normalizer used at import time.
#   2. driver_canonical_form() / resolve_driver_alias() -- the SQL macros in
#      000-settings.sql that actually derive driver_id. These are the ones that
#      matter for identity, so they are tested directly against duckdb.

require 'csv'
require 'json'
require 'open3'
require 'tmpdir'
require_relative 'lib/driver_normalizer'

SETTINGS_SQL = File.expand_path('000-settings.sql', __dir__)

# Extracts just the driver identity section of 000-settings.sql so the macros
# can be exercised without building the whole database.
def identity_sql
  @identity_sql ||= begin
    body = File.read(SETTINGS_SQL)
    start = body.index('-- Driver identity: raw name -> driver_id')
    raise 'driver identity section not found in 000-settings.sql' unless start

    body[start..]
  end
end

def duckdb_available?
  system('which duckdb > /dev/null 2>&1')
end

# Runs SELECT expressions against an in-memory duckdb loaded with the macros.
def duckdb_row(select_list)
  script = "#{identity_sql}\nSELECT #{select_list};"
  stdout, stderr, status = Open3.capture3('duckdb', '-json', '-c', script, chdir: __dir__)
  raise "duckdb failed: #{stderr}" unless status.success?

  JSON.parse(stdout).first
end

if ARGV.include?('--demo')
  normalizer = DriverNormalizer.new
  sample_file = Dir['data/imsa/*/*/*-race-laps.csv'].first
  abort 'No sample laps file found' unless sample_file

  puts "Testing on: #{sample_file}\n\n"
  rows = CSV.read(sample_file)
  driver_idx = rows.first.index('DRIVER_NAME')
  abort 'No DRIVER_NAME column found' unless driver_idx

  drivers = {}
  rows[1..].each do |row|
    name = row[driver_idx]
    next if name.nil? || name.strip.empty?

    drivers[name] ||= { normalized: normalizer.normalize(name), count: 0 }
    drivers[name][:count] += 1
  end

  changes = drivers.select { |orig, data| orig != data[:normalized] }
  puts "Driver names that would be normalized (#{changes.length}/#{drivers.length}):\n\n"
  changes.sort_by { |_, data| -data[:count] }.each do |orig, data|
    puts "  #{orig.ljust(35)} => #{data[:normalized]} (#{data[:count]} laps)"
  end
  normalizer.report
  exit 0
end

require 'minitest/autorun'

class DriverNormalizerTest < Minitest::Test
  def setup
    # Use a throwaway cache so the fuzzy "seen drivers" memory of a previous
    # run cannot leak into assertions.
    @normalizer = DriverNormalizer.new(File.join(Dir.tmpdir, "driver_cache_test_#{Process.pid}.json"))
  end

  def test_strips_diacritics
    {
      'André Lotterer' => 'Andre Lotterer',
      'Sébastien Buemi' => 'Sebastien Buemi',
      'Nico Müller' => 'Nico Muller',
      'François Perrodo' => 'Francois Perrodo',
      'Cem Bölükbasi' => 'Cem Bolukbasi',
      'Théo Pourchaire' => 'Theo Pourchaire'
    }.each do |input, expected|
      assert_equal expected, @normalizer.strip_accents(input)
    end
  end

  def test_strips_non_decomposable_letters
    assert_equal 'Boe', @normalizer.strip_accents('Bøe')
    assert_equal 'Strasse', @normalizer.strip_accents('Straße')
    assert_equal 'AEon', @normalizer.strip_accents('Æon')
  end

  def test_uppercase_surnames_are_title_cased
    assert_equal 'Mathias Beche', @normalizer.normalize('Mathias BECHE')
  end
end

class DriverIdMacroTest < Minitest::Test
  def setup
    skip 'duckdb CLI not installed' unless duckdb_available?
  end

  def fold(*names)
    list = names.each_with_index.map { |n, i| "driver_canonical_form('#{n.gsub("'", "''")}') AS c#{i}" }
    duckdb_row(list.join(', ')).values
  end

  def resolve(*names)
    list = names.each_with_index.map { |n, i| "resolve_driver_alias('#{n.gsub("'", "''")}') AS r#{i}" }
    duckdb_row(list.join(', ')).values
  end

  def test_folding_is_ascii_lowercase
    assert_equal ['andre lotterer', 'sebastien buemi', 'nico muller'],
                 fold('André LOTTERER', 'Sébastien Buemi', 'Nico Müller')
  end

  def test_folding_merges_diacritic_variants
    a, b = fold('André LOTTERER', 'Andre Lotterer')
    assert_equal a, b
  end

  def test_hyphens_survive_into_the_id
    # driver_id is public surface, so a name no curated alias touches keeps
    # the hyphenation it has always had.
    assert_equal ['ryan hunter-reay'], fold('Ryan HUNTER-REAY')
  end

  def test_match_key_folds_hyphens_even_though_the_id_does_not
    hyphen_id, plain_id = fold('Jean-Baptiste Simmenauer', 'Jean Baptiste Simmenauer')
    refute_equal hyphen_id, plain_id, 'the emitted id must keep the hyphen as written'

    keys = duckdb_row(<<~SQL).values
      driver_match_key('Jean-Baptiste Simmenauer') AS a,
      driver_match_key('Jean Baptiste Simmenauer') AS b
    SQL
    assert_equal keys[0], keys[1], 'alias lookup must be hyphen-insensitive'
  end

  def test_curated_alias_matches_either_hyphenation
    # driver_aliases.json spells this one 'jean-éric vergne'; a name written
    # without the hyphen (or the accent) must still find it.
    assert_equal ['jean-eric vergne', 'jean-eric vergne'],
                 resolve('Jean-Éric VERGNE', 'Jean Eric Vergne')
  end

  def test_folding_collapses_whitespace_and_case
    a, b = fold('  Kevin   ESTRE ', 'kevin estre')
    assert_equal a, b
  end

  def test_curated_alias_is_applied_in_both_spellings
    a, b = resolve('Ben Hanley', 'Benjamin HANLEY')
    assert_equal 'ben hanley', a
    assert_equal 'ben hanley', b
  end

  def test_resolution_is_idempotent
    once, twice = duckdb_row(<<~SQL).values
      resolve_driver_alias('Benjamin Hanley') AS once,
      resolve_driver_alias(resolve_driver_alias('Benjamin Hanley')) AS twice
    SQL
    assert_equal once, twice
  end

  # Mechanical folding must not merge distinct names on its own; only a
  # curated alias may. Uncurated look-alikes stay apart, and a curated pair
  # (tom/thomas blomqvist, the 2026 Daytona split-name artifact) merges.
  def test_distinct_names_are_not_merged_without_an_alias
    jon, jonathan = resolve('Jon Miller', 'Jonathan Miller')
    refute_equal jon, jonathan
  end

  def test_curated_pair_merges
    tom, thomas = resolve('Tom Blomqvist', 'Thomas Blomqvist')
    assert_equal tom, thomas
  end

  # Multi-hop chains are exercised against a synthetic alias file rather than
  # reasoned about: a -> b -> c must collapse to c for every spelling, and c
  # must resolve to itself.
  def test_multi_hop_alias_chain_collapses_to_the_end_of_the_chain
    Dir.mktmpdir do |dir|
      fixture = File.join(dir, 'chain_aliases.json')
      File.write(fixture, JSON.pretty_generate([
        { 'alias' => 'aaa driverone', 'canonical_id' => 'bbb driverone' },
        { 'alias' => 'bbb driverone', 'canonical_id' => 'ccc driverone' },
        { 'alias' => 'zzz drivertwo', 'canonical_id' => 'yyy drivertwo' }
      ]))

      script = identity_sql.sub("'driver_aliases.json'", "'#{fixture}'") + <<~SQL
        SELECT resolve_driver_alias('Aaa Driverone') AS head,
               resolve_driver_alias('Bbb Driverone') AS middle,
               resolve_driver_alias('Ccc Driverone') AS tail,
               resolve_driver_alias('Zzz Drivertwo') AS single;
      SQL
      stdout, stderr, status = Open3.capture3('duckdb', '-json', '-c', script, chdir: dir)
      raise "duckdb failed: #{stderr}" unless status.success?

      row = JSON.parse(stdout).first
      assert_equal 'ccc driverone', row['head'],   'a -> b -> c must collapse to c'
      assert_equal 'ccc driverone', row['middle'], 'b -> c'
      assert_equal 'ccc driverone', row['tail'],   'c must resolve to itself'
      assert_equal 'yyy drivertwo', row['single'], 'single-hop aliases still work'
    end
  end

  def test_alias_map_has_one_row_per_key
    dupes = duckdb_row(<<~SQL)['n']
      (SELECT count(*) FROM (
         SELECT match_key FROM driver_identity_map GROUP BY match_key HAVING count(*) > 1
       )) AS n
    SQL
    assert_equal 0, dupes.to_i
  end
end
