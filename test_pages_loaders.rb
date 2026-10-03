#!/usr/bin/env ruby
# frozen_string_literal: true

# Focused dashboard-loader regression tests. Requires Ruby and the DuckDB CLI,
# but neither the full database nor npm. Run: ruby test_pages_loaders.rb

require "minitest/autorun"
require "csv"
require "fileutils"
require "open3"
require "tmpdir"

class PagesLoadersTest < Minitest::Test
  ROOT = File.expand_path(__dir__)
  LOADERS = %w[elo-history gentleman-elo].freeze
  RATING_FIELDS = %w[skill_mu skill_sigma ordinal peer_mu peer_sigma peer_ordinal peer_elo].freeze

  def setup
    @tmp = Dir.mktmpdir("imsa-pages-loaders-")
    @db = File.join(@tmp, "fixture.duckdb")

    # Use the production CSV header without requiring the executable computation
    # script. This catches loaders accidentally depending on obsolete columns.
    source = File.read(File.join(ROOT, "compute_skill.rb"))
    @header = source.match(/HEADER = %w\[(.*?)\]\.freeze/m)[1].split
    @ratings = [
      rating("bronze", event: "Old", session_date: "2024-01-01", year: "2024", elo: 1400),
      rating("bronze", event: "Other class", session_date: "2025-01-02", class: "GTD", elo: 2200),
      rating("bronze", event: "Second", session_date: "2025-01-03", elo: 1430),
      # Deliberately out of order: tie-breaking must not depend on CSV row order.
      rating("bronze", event: "Zeta", session_date: "2025-01-04", elo: 1450),
      rating("bronze", event: "Alpha", session_date: "2025-01-04", elo: 1440),
      rating("silver", license: "Silver", elo: 1500),
      rating("unknown", license: "Unknown", elo: 1510),
      rating("old", year: "2024", session_date: "2024-01-01"),
      rating("practice"),
      rating("otherclass", class: "GTD"),
      rating("gold", license: "Gold"),
      rating("platinum", license: "Platinum"),
      rating("promoted"),
      rating("other_class_pro")
    ]
    csv_path = File.join(@tmp, "driver_elo.csv")
    CSV.open(csv_path, "w") do |csv|
      csv << @header
      @ratings.each { |row| csv << @header.map { |field| row.fetch(field) } }
    end

    query(<<~SQL)
      CREATE TABLE driver_elo AS SELECT * FROM '#{csv_path}';
      CREATE TABLE laps (driver_id VARCHAR, class VARCHAR, session VARCHAR, year VARCHAR, license VARCHAR);
      INSERT INTO laps VALUES
        ('bronze', 'LMP2', 'race', '2025', 'Bronze'),
        ('silver', 'LMP2', 'race', '2025', 'Silver'),
        ('unknown', 'LMP2', 'race', '2025', 'Unknown'),
        ('old', 'LMP2', 'race', '2024', 'Bronze'),
        ('practice', 'LMP2', 'practice', '2025', 'Bronze'),
        ('otherclass', 'GTD', 'race', '2025', 'Bronze'),
        ('gold', 'LMP2', 'race', '2025', 'Gold'),
        ('platinum', 'LMP2', 'race', '2025', 'Platinum'),
        ('promoted', 'LMP2', 'race', '2025', 'Bronze'),
        ('promoted', 'LMP2', 'race', '2026', 'Gold'),
        ('other_class_pro', 'LMP2', 'race', '2025', 'Bronze'),
        ('other_class_pro', 'GTD', 'race', '2025', 'Gold');
    SQL
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.directory?(@tmp)
  end

  def test_aliases_and_skill_fields_match_production_schema
    LOADERS.each do |loader|
      rows = load_rows(loader)
      rows.each do |row|
        original = @ratings.find do |rating|
          %w[driver_id class event].all? { |field| rating[field] == row[field] }
        end
        refute_nil original
        assert_equal original.fetch("driver_name"), row["driver"]
        assert_equal original.fetch("driver_name"), row["driver_name"]
        assert_equal original.fetch("elo"), row["elo"].to_i
        assert_equal row["elo"], row["elo_after"]
        RATING_FIELDS.each do |field|
          assert_in_delta original.fetch(field), row.fetch(field).to_f, 1e-9, "#{loader}: #{field}"
        end
      end
    end
  end

  def test_history_is_partitioned_by_driver_and_class_with_null_first_delta
    LOADERS.each do |loader|
      rows = load_rows(loader)
      bronze = rows.select { |row| row["driver_id"] == "bronze" && row["class"] == "LMP2" }
      assert_equal %w[Old Second Alpha Zeta], bronze.map { |row| row["event"] }
      assert_equal [nil, "1400", "1430", "1440"], bronze.map { |row| row["elo_before"] }
      assert_equal [nil, "30", "10", "10"], bronze.map { |row| row["delta"] }
      rows.group_by { |row| [row["driver_id"], row["class"]] }.each_value do |history|
        assert_nil history.first["elo_before"]
        assert_nil history.first["delta"]
      end
    end
    other_class = load_rows("elo-history").find { |row| row["driver_id"] == "bronze" && row["class"] == "GTD" }
    refute_nil other_class
    assert_nil other_class["elo_before"]
    assert_nil other_class["delta"]
  end

  def test_gentleman_eligibility_and_full_history
    rows = load_rows("gentleman-elo")
    assert_equal %w[bronze other_class_pro silver unknown], rows.map { |row| row["driver_id"] }.uniq.sort
    assert rows.all? { |row| row["class"] == "LMP2" }
    assert rows.any? { |row| row["driver_id"] == "bronze" && row["year"] == "2024" },
           "an eligible driver's history must include earlier seasons"
  end

  def test_database_errors_fail_the_shell_loader
    query("DROP TABLE driver_elo;")
    LOADERS.each do |loader|
      stdout, stderr, status = run_loader(loader)
      refute status.success?, "#{loader} must propagate a DuckDB query error"
      assert_empty stdout
      assert_match(/driver_elo/, stderr)
    end
  end

  def test_missing_database_is_not_created
    missing_db = File.join(@tmp, "missing.duckdb")
    LOADERS.each do |loader|
      stdout, stderr, status = run_loader(loader, missing_db)
      refute status.success?, "#{loader} must fail when its database is missing"
      assert_empty stdout
      refute_empty stderr
      refute File.exist?(missing_db), "read-only loaders must not create an empty database"
    end
  end

  private

  def rating(id, **overrides)
    {
      "driver_id" => id, "driver_name" => "Driver #{id}", "class" => "LMP2",
      "series_code" => "imsa", "year" => "2025", "event" => "Season opener",
      "session_date" => "2025-01-01", "laps" => 25, "cumulative_laps" => 100,
      "license" => "Bronze", "skill_mu" => 28.5, "skill_sigma" => 2.5,
      "ordinal" => 21.0, "elo" => 1420, "peer_mu" => 26.5,
      "peer_sigma" => 2.0, "peer_ordinal" => 20.5, "peer_elo" => 1480
    }.merge(overrides.transform_keys(&:to_s))
  end

  def query(sql)
    _stdout, stderr, status = Open3.capture3("duckdb", "-bail", @db, "-c", sql)
    assert status.success?, "fixture setup failed: #{stderr}"
  end

  def run_loader(loader, database = @db)
    script = File.join(ROOT, "pages", "src", "data", "#{loader}.csv.sh")
    Open3.capture3({ "IMSA_DB" => database }, "bash", script, chdir: @tmp)
  end

  def load_rows(loader)
    stdout, stderr, status = run_loader(loader)
    assert status.success?, "#{loader} failed: #{stderr}"
    rows = CSV.parse(stdout, headers: true)
    refute_empty rows
    rows
  end
end
