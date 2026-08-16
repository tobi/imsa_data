require 'date'
require 'fileutils'

OUTPUT_DIR = File.expand_path("output")

def duckdb_available?
  system("which duckdb > /dev/null 2>&1") || system("command -v duckdb > /dev/null 2>&1")
end

def print_duckdb_install_instructions
  puts "\n❌ DuckDB binary not found in PATH"
  puts "\nInstall DuckDB using one of the following methods:\n"
  puts "Linux:"
  puts "  wget https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip"
  puts "  unzip duckdb_cli-linux-amd64.zip"
  puts "  sudo mv duckdb /usr/local/bin/"
  puts "  chmod +x /usr/local/bin/duckdb"
  puts "\nmacOS (using Homebrew):"
  puts "  brew install duckdb"
  puts "\nmacOS (manual):"
  puts "  wget https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-osx-universal.zip"
  puts "  unzip duckdb_cli-osx-universal.zip"
  puts "  sudo mv duckdb /usr/local/bin/"
  puts "  chmod +x /usr/local/bin/duckdb"
  puts "\nOr visit: https://duckdb.org/docs/installation/"
  puts ""
end

task default: "db:update"

TRACK_ATLAS_URL = "https://raw.githubusercontent.com/tobi/track-atlas/main/tracks.jsonl"
TRACK_ATLAS_PATH = "data/track-atlas/tracks.jsonl"

desc "Fetch the latest tracks.jsonl from tobi/track-atlas (circuit geometry, sector/microsector meters)"
task :update_track_atlas do
  FileUtils.mkdir_p(File.dirname(TRACK_ATLAS_PATH))
  puts "Fetching track-atlas dataset from #{TRACK_ATLAS_URL}..."
  tmp_path = "#{TRACK_ATLAS_PATH}.tmp"
  fetched = system("curl -sL --fail #{TRACK_ATLAS_URL} -o #{tmp_path}") &&
            File.size?(tmp_path) && File.size(tmp_path) > 1000

  if fetched
    FileUtils.mv(tmp_path, TRACK_ATLAS_PATH)
    line_count = File.readlines(TRACK_ATLAS_PATH).size
    puts "  Saved #{TRACK_ATLAS_PATH} (#{line_count} tracks)"
  else
    FileUtils.rm_f(tmp_path)
    if File.exist?(TRACK_ATLAS_PATH)
      puts "  ⚠️  Fetch failed (network error or repo moved) — keeping existing cached #{TRACK_ATLAS_PATH}"
    else
      abort("❌ Failed to fetch track-atlas tracks.jsonl and no cached copy exists at #{TRACK_ATLAS_PATH}. " \
            "The build requires this file for sector/microsector meter data.")
    end
  end
end

namespace :db do
  desc "Regenerate and open the database"
  task update: :update_track_atlas do
    unless duckdb_available?
      print_duckdb_install_instructions
      abort("Please install DuckDB and try again.")
    end

    FileUtils.mkdir_p(OUTPUT_DIR)

    # Phase 1: Run all SQL files except Elo (which needs precomputed CSV)
    sql_files = Dir["*.sql"].sort.reject { |f| f.include?("elo") }
    sql_commands = sql_files.collect { |file| ".read #{file}" }.join("\n")

    puts "Creating DuckDB database (phase 1: #{sql_files.length} SQL files)..."
    script = <<~SQL
      .output /dev/null
      #{sql_commands}
      .output stdout

      COPY drivers TO '#{OUTPUT_DIR}/drivers.csv' (HEADER, DELIMITER ',');
      COPY laps TO '#{OUTPUT_DIR}/laps.csv' (HEADER, DELIMITER ',');
      COPY seasons TO '#{OUTPUT_DIR}/seasons.csv' (HEADER, DELIMITER ',');
    SQL

    IO.popen("duckdb #{OUTPUT_DIR}/imsa.duckdb", "w") do |duckdb|
      duckdb.write(script)
    end

    # Phase 2: Compute skill ratings (OpenSkill: multiplayer + confidence,
    # two pools = overall license-seeded + within-tier peer; time-aware sigma
    # widening + field-median-anchored elo). Dependencies are declared inline
    # in compute_skill.py and uv creates the isolated environment.
    unless system("command -v uv > /dev/null 2>&1")
      abort("❌ uv not found in PATH. Install it: https://docs.astral.sh/uv/getting-started/installation/")
    end
    puts "Computing skill ratings (OpenSkill, two-pool)..."
    unless system("uv", "run", "--python", "3.11", "compute_skill.py", out: "#{OUTPUT_DIR}/driver_elo.csv")
      abort("❌ compute_skill.py failed. Check uv output above for details.")
    end

    # Phase 3: Load Elo data
    elo_sql_files = Dir["*.sql"].sort.select { |f| f.include?("elo") }
    if elo_sql_files.any?
      puts "Loading Elo data (phase 2: #{elo_sql_files.length} SQL files)..."
      elo_commands = elo_sql_files.collect { |file| ".read #{file}" }.join("\n")
      IO.popen("duckdb #{OUTPUT_DIR}/imsa.duckdb", "w") do |duckdb|
        duckdb.write(elo_commands)
      end
    end

    Rake::Task[:lint].invoke

    puts "Database updated successfully!"
    puts "  #{OUTPUT_DIR}/imsa.duckdb"
    puts "  #{OUTPUT_DIR}/drivers.csv"
    puts "  #{OUTPUT_DIR}/laps.csv"
    puts "  #{OUTPUT_DIR}/seasons.csv"
    puts "  #{OUTPUT_DIR}/driver_elo.csv"
  end

  desc "Open the database in interactive mode"
  task open: :update do
    unless duckdb_available?
      print_duckdb_install_instructions
      abort("Please install DuckDB and try again.")
    end
    exec "duckdb #{OUTPUT_DIR}/imsa.duckdb"
  end
end

desc "Import IMSA data for the current year"
task :import do
  current_year = Date.today.year
  puts "Importing IMSA data for #{current_year}..."
  sh "ruby import.rb --series imsa --year #{current_year}"
end

desc "Import data for a specific series and year"
task :import_series, [:series, :year] do |t, args|
  series = args[:series] || 'imsa'
  year = args[:year] || Date.today.year
  puts "Importing #{series.upcase} data for #{year}..."
  sh "ruby import.rb --series #{series} --year #{year}"
end

desc "Import IMSA data for the last 3 years"
task :import_recent do
  current_year = Date.today.year
  years = (current_year - 2)..current_year

  puts "Importing IMSA data for years: #{years.to_a.join(', ')}"
  years.each do |year|
    puts "\n--- Importing #{year} ---"
    sh "ruby import.rb --series imsa --year #{year}"
  end
end

desc "Import all series for a given year"
task :import_all, [:year] do |t, args|
  year = args[:year] || Date.today.year
  series_list = %w[imsa wec elms alms lmc]

  puts "Importing all series for #{year}..."
  puts "Series: #{series_list.join(', ')}"

  series_list.each do |series|
    puts "\n=== Importing #{series.upcase} #{year} ==="
    begin
      sh "ruby import.rb --series #{series} --year #{year}"
    rescue => e
      puts "⚠️  Warning: Failed to import #{series}: #{e.message}"
      puts "Continuing with next series..."
    end
  end

  puts "\n✅ Multi-series import completed!"
end

desc "Import WEC data (including 24h Le Mans) for current year"
task :import_wec do
  current_year = Date.today.year
  puts "Importing WEC data (including 24 Hours of Le Mans) for #{current_year}..."
  sh "ruby import.rb --series wec --year #{current_year}"
end

desc "Import ELMS data for current year"
task :import_elms do
  current_year = Date.today.year
  puts "Importing European Le Mans Series data for #{current_year}..."
  sh "ruby import.rb --series elms --year #{current_year}"
end

desc "Import Asian Le Mans data for current year"
task :import_alms do
  current_year = Date.today.year
  puts "Importing Asian Le Mans Series data for #{current_year}..."
  sh "ruby import.rb --series alms --year #{current_year}"
end

desc "Import Le Mans Cup data for current year"
task :import_lmc do
  current_year = Date.today.year
  puts "Importing Le Mans Cup data for #{current_year}..."
  sh "ruby import.rb --series lmc --year #{current_year}"
end

desc "Run all tests"
task :test do
  sh "ruby test_database.rb"
end

desc "Run database linting checks"
task :lint do
  sh "ruby lint/check_database.rb"
end

desc "Run data quality checks on all race sessions"
task :lint_data do
  sh "ruby lint/check_data_quality.rb"
end

desc "Run driver data quality checks"
task :lint_drivers do
  sh "ruby lint/check_drivers.rb"
end

desc "Run all checks (lint + data quality + drivers)"
task check: ["db:update", :lint, :lint_data, :lint_drivers]

desc "Clean output directory"
task :clean do
  if Dir.exist?(OUTPUT_DIR)
    puts "Cleaning output directory..."
    FileUtils.rm_rf(OUTPUT_DIR)
    puts "Output directory cleaned!"
  else
    puts "Output directory doesn't exist, nothing to clean."
  end
end


desc "Publish the database to Hugging Face"
task publish: "db:update" do
  FileUtils.mkdir_p("#{OUTPUT_DIR}/hf")
  cd "#{OUTPUT_DIR}/hf" do
    cp "#{OUTPUT_DIR}/drivers.csv", "."
    cp "#{OUTPUT_DIR}/laps.csv", "."
    cp "#{OUTPUT_DIR}/imsa.duckdb", "."
    cp "#{OUTPUT_DIR}/../README.hf.md", "README.md"
    sh "hf upload tobil/imsa . --repo-type dataset"
  end
end

namespace :dashboard do
  desc "Build the Observable Framework dashboard"
  task :build => "db:update" do
    Dir.chdir("pages") { sh "npm run build" }
  end

  desc "Start the Observable Framework dev server"
  task :dev do
    Dir.chdir("pages") { exec "npm run dev" }
  end
end
