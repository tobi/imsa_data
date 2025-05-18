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


$visited ||= Set.new

def fetch_links(url)
  url = url.gsub(/\?.*$/, '')
  return [] if $visited.include?(url)
  $visited.add(url)
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



def race_files(race_url)
  files, folders = fetch_links(race_url).partition { not _1.end_with?("/") }

  # get files in subfolders if there are any because for some races there are these Hour01-04 type folders which sometimes hide them
  #  in that case we take the last
  folders.each do |folder|
    next if folder.include?("?")
    # next unless folder.end_with?("?")
    folder_url = "#{race_url}#{folder}"
    additional_files = fetch_links(folder_url).reject { _1.end_with?("/") }
    additional_files.map! { |f| "#{folder}#{f}" }
    files.concat(additional_files)
  end

  files.reverse!

  csvs = files.grep(/\.CSV$/i)

  result = {
    laps: csvs.find { |f| f.match(/23_.*\.CSV\z/i) },
    weather: csvs.find { |f| f.match(/26_.*\.CSV\z/i) },
    files: csvs
  }
  result[:results] = [
    csvs.find { |f| f.match(/03_.*Official\.CSV\z/i) },
    csvs.find { |f| f.match(/03_.*Unofficial\.CSV\z/i) },
    *csvs.grep(/03_.*\.CSV\z/i)
  ]
  result[:results] = result[:results].compact.first
  result[:success] = (result[:results] and result[:laps] and result[:weather])
  result
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
      unescaped_series_folder = CGI.unescape(series_folder)
      match = unescaped_series_folder.include?(series_pattern)
      next unless match

      series_url = "#{event_url}#{series_folder}"
      race_folders = fetch_links(series_url).select { _1.end_with?("/") && _1 !~ /\A\./ }

      race_folders.each do |race_folder|
        next unless race_folder.match(/\A\d{12}\_/)

        race_url = "#{series_url}#{race_folder}"
        csvs = race_files(race_url)

        [:results, :laps, :weather].each do |label|
          file_name = csvs[label]

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
              print " ✅"
            end
          end
        end

        #   target = File.join(
        #     outpath,
        #     "#{year}/",
        #     # "#{series_folder.chomp('/')}/",
        #     "#{event_folder.chomp('/')}/",
        #     target,
        #   )
        #   target = target.downcase
        #   target = target.gsub(/%20/, ' ')
        #   target = target.gsub(/[^a-z0-9\.\-\/]+/, '-')

        #   FileUtils.mkdir_p(File.dirname(target))
        #   unless File.exist?(target)
        #     print "\n[dl] → #{target}"
        #     URI.open("#{race_url}#{file_name}") do |remote|
        #       content = remote.read
        #       File.open(target, 'w') do |f|
        #         FastCSV.raw_parse(content, col_sep: ';', row_sep: "\n") do |csv|
        #           f.write(csv.to_csv)
        #         end
        #       end
        #       print " ✅"
        #     end
        #   end
        # end
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
