require 'open-uri'
require 'fileutils'
require 'date'
require 'cgi'
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'fastcsv'
end

BASE_URL = "https://imsa.results.alkamelcloud.com/Results/"
DEFAULT_SERIES_PATTERN = "IMSA WeatherTech"

def fetch_links(url)
  print '.'
  body = URI.open(url, &:read)
  body.scan(/href="([^"]+)"/).reject { _1.first.start_with?("/") }.map(&:first)
end

def best_file(files)
  files.sort_by do |f|
    case f
    when /Official/i then 0
    when /Unofficial/i then 1
    else 2
    end
  end.first
end



def import_race(year, outpath, series_pattern = DEFAULT_SERIES_PATTERN)
  year_prefix = "#{year.to_s[-2..] }_#{year}"

  # Get list of event folders for this year
  events_url = "#{BASE_URL}#{year_prefix}/"
  event_folders = fetch_links(events_url).select { _1.end_with?("/") && _1 !~ /\A\./ }

  event_folders.each do |event_folder|
    event_url = "#{events_url}#{event_folder}"
    series_folders = fetch_links(event_url).select { _1.end_with?("/") && _1 !~ /\A\./ }

    series_folders.each do |series_folder|
      next unless SERIES_FILTER.match?(CGI.unescape(series_folder))

      series_url = "#{event_url}#{series_folder}"
      race_folders = fetch_links(series_url).select { _1.end_with?("/") && _1 !~ /\A\./ }

      race_folders.each do |race_folder|
        race_url = "#{series_url}#{race_folder}"
        files = fetch_links(race_url).reject { _1.end_with?("/") }

        %w[03 23 26].zip(%w[results laps weather]).each do |prefix, label|
          matches = files.grep(/\A#{prefix}_.*\.CSV\z/i)
          next if matches.empty?
          file_name = best_file(matches)
          target = "#{race_folder.chomp('/')}-#{label}.csv"


          target = File.join(
            outpath,
            "#{year}/",
            # "#{series_folder.chomp('/')}/",
            "#{event_folder.chomp('/')}/",
            target,
          )
          target = target.downcase
          target = target.gsub(/%20/, ' ')
          target = target.gsub(/[^a-z0-9\.\-\/]+/, '-')

          FileUtils.mkdir_p(File.dirname(target))
          unless File.exist?(target)
            print "\n[dl] → #{target}"
            URI.open("#{race_url}#{file_name}") do |remote|
              content = remote.read
              File.open(target, 'w') do |f|
                FastCSV.raw_parse(content, col_sep: ';', row_sep: "\n") do |csv|
                  f.write(csv.to_csv)
                end
              end
              print "✅"
            end
            print "\n"
          end
        end
      end
    end
  end 
end

if __FILE__ == $0

  require 'optparse'

  options = {
    year: Date.today.year,
    outpath: 'data/',
    series_pattern: DEFAULT_SERIES_PATTERN
  }
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"
  
    opts.on("-y", "--year YEAR", Integer, "Year to fetch (default: current year)") do |year|
      options[:year] = year
    end
  
    opts.on("-o", "--outpath PATH", String, "Output directory (default: data/)") do |path|
      options[:outpath] = path
    end

    opts.on("-s", "--series-pattern PATTERN", String, "Series pattern (default: #{DEFAULT_SERIES_PATTERN})") do |pattern|
      options[:series_pattern] = pattern
    end
  end.parse!
  
  import_race(options[:year], options[:outpath], options[:series_pattern])
end