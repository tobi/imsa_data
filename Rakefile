require 'date'
require 'fileutils'

task :default => "db:update"

output_dir = File.expand_path("output")

namespace :db do
  desc "Regenerate and open the database"
  task :update do
    sh "cat *.sql | duckdb #{output_dir}/imsa.duckdb"
    sh <<~CMD
    echo " \
      COPY event_drivers TO '#{output_dir}/drivers.csv' (HEADER, DELIMITER ','); \
      COPY event_laps TO '#{output_dir}/laps.csv' (HEADER, DELIMITER ','); | \
      " duckdb #{output_dir}/imsa.duckdb
    CMD
  end

  desc "Open the database"
  task :open => :update do
    exec "duckdb #{output_dir}/imsa.duckdb"
  end
end

desc "Import data for the current year"
task :import do
  require 'date'
  sh "ruby import.rb --year #{Date.today.year}"
end

desc "Import data for the last 3 years"
task :import_recent do
  require 'date'
  ((Date.today.year-3)..Date.today.year).each do |year|
    sh "ruby import.rb --year #{year}"
  end
end