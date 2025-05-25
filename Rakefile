require 'date'
require 'fileutils'

OUTPUT_DIR = File.expand_path("output")

task default: "db:update"

namespace :db do
  desc "Regenerate and open the database"
  task :update do
    FileUtils.mkdir_p(OUTPUT_DIR)
    
    puts "Creating DuckDB database..."
    sh "cat *.sql | duckdb #{OUTPUT_DIR}/imsa.duckdb"
    
    puts "Exporting CSV files..."
    sh <<~CMD
      echo "
        COPY event_drivers TO '#{OUTPUT_DIR}/drivers.csv' (HEADER, DELIMITER ',');
        COPY event_laps TO '#{OUTPUT_DIR}/laps.csv' (HEADER, DELIMITER ',');
      " | duckdb #{OUTPUT_DIR}/imsa.duckdb
    CMD
    
    puts "Database updated successfully!"
  end

  desc "Open the database in interactive mode"
  task open: :update do
    exec "duckdb #{OUTPUT_DIR}/imsa.duckdb"
  end
end

desc "Import data for the current year"
task :import do
  current_year = Date.today.year
  puts "Importing data for #{current_year}..."
  sh "ruby import.rb --year #{current_year}"
end

desc "Import data for the last 3 years"
task :import_recent do
  current_year = Date.today.year
  years = (current_year - 2)..current_year
  
  puts "Importing data for years: #{years.to_a.join(', ')}"
  years.each do |year|
    puts "\n--- Importing #{year} ---"
    sh "ruby import.rb --year #{year}"
  end
end

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