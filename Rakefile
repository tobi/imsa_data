
namespace :db do
  desc "Regenerate and open the database"
  task :update do
    sh "cat *.sql | duckdb output/imsa.duckdb"
    sh <<~CMD
	      echo " \
        COPY event_drivers TO 'output/drivers.csv' (HEADER, DELIMITER ','); \
	      COPY event_laps TO 'output/laps.csv' (HEADER, DELIMITER ','); \
        " | duckdb output/imsa.duckdb
    CMD


  end

  desc "Open the database"
  task :open => :update do
    exec "duckdb output/imsa.duckdb"
  end


end


desc "Import data for the current year"
task :import do
  require 'date'
  sh "ruby import.rb --year #{Date.today.year}"
end
