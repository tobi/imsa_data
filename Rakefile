require 'date'
require 'fileutils'

OUTPUT_DIR = File.expand_path("output")

task default: "db:update"

namespace :db do
  desc "Regenerate and open the database"
  task :update do
    FileUtils.mkdir_p(OUTPUT_DIR)

    sql_files = Dir["*.sql"].sort.collect { |file| ".read #{file}" }.join("\n")
    
    puts "Creating DuckDB database..."
    script = <<~SQL
      #{sql_files}

      COPY drivers TO '#{OUTPUT_DIR}/drivers.csv' (HEADER, DELIMITER ',');
      COPY laps TO '#{OUTPUT_DIR}/laps.csv' (HEADER, DELIMITER ',');
    SQL

    IO.popen("duckdb #{OUTPUT_DIR}/imsa.duckdb", "w") do |duckdb|
      duckdb.write(script)
    end

    puts "Database updated successfully!"
    puts "  #{OUTPUT_DIR}/imsa.duckdb"
    puts "  #{OUTPUT_DIR}/drivers.csv"
    puts "  #{OUTPUT_DIR}/laps.csv"
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


desc "Publish the database to Hugging Face"
task :publish do
  FileUtils.mkdir_p("#{OUTPUT_DIR}/hf")
  cd "#{OUTPUT_DIR}/hf" do
    cp "#{OUTPUT_DIR}/drivers.csv", "."
    cp "#{OUTPUT_DIR}/laps.csv", "."
    cp "#{OUTPUT_DIR}/imsa.duckdb", "."
    cp "#{OUTPUT_DIR}/../README.hf.md", "README.md"
    sh "huggingface-cli upload tobil/imsa . --repo-type dataset . "
  end
  
end