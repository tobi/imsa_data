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
    start = body.index('-- DRIVER IDENTITY RESOLUTION')
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

  def test_folding_merges_hyphen_variants
    a, b = fold('Jean-Baptiste Simmenauer', 'Jean Baptiste Simmenauer')
    assert_equal a, b
    assert_equal 'jean baptiste simmenauer', a
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

  def test_distinct_names_are_not_merged
    tom, thomas = resolve('Tom Blomqvist', 'Thomas Blomqvist')
    refute_equal tom, thomas
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
