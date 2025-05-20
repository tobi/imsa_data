
namespace :db do
  desc "Regenerate and open the database"
  task :update do
    sh "cat *.sql | duckdb /tmp/imsa.duckdb"
  end

  desc "Open the database"
  task :open => :update do
    exec "duckdb /tmp/imsa.duckdb"
  end


end


desc "Import data for the current year"
task :import do
  require 'date'
  sh "ruby import.rb --year #{Date.today.year}"
end
