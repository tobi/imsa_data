require 'open-uri'
require 'fileutils'
require 'date'
require 'cgi'
require 'csv'
require 'set'

BASE_URL = "https://imsa.results.alkamelcloud.com/Results/"
DEFAULT_SERIES_PATTERN = "IMSA WeatherTech"

class IMSAImporter
  def initialize
    @visited = Set.new
  end

  def import_year(year, output_path = 'data/', series_pattern = DEFAULT_SERIES_PATTERN)
    year_prefix = "#{year.to_s[-2..]}_#{year}"
    events_url = "#{BASE_URL}#{year_prefix}/"
    
    puts "Importing IMSA data for #{year}..."
    
    fetch_links(events_url).each do |event_folder|
      next unless event_folder.end_with?('/') && !event_folder.start_with?('.')
      
      import_event(events_url + event_folder, year, output_path, series_pattern)
    end
  end

  private

  def fetch_links(url)
    url = url.gsub(/\?.*$/, '')
    return [] if @visited.include?(url)
    
    @visited.add(url)
    
    begin
      body = URI.open(url, &:read)
      body.scan(/href="([^"]+)"/)
          .map(&:first)
          .reject { |link| link.start_with?('/') }
    rescue => e
      puts "Error fetching #{url}: #{e.message}"
      []
    end
  end

  def import_event(event_url, year, output_path, series_pattern)
    fetch_links(event_url).each do |series_folder|
      next unless series_folder.end_with?('/') && !series_folder.start_with?('.')
      next unless CGI.unescape(series_folder).include?(series_pattern)
      
      import_series(event_url + series_folder, year, output_path, 
                   extract_folder_name(event_url), extract_folder_name(series_folder))
    end
  end

  def import_series(series_url, year, output_path, event_name, series_name)
    fetch_links(series_url).each do |race_folder|
      next unless race_folder.end_with?('/') && race_folder.match(/\A\d{12}_/)
      
      import_race(series_url + race_folder, year, output_path, event_name, race_folder)
    end
  end

  def import_race(race_url, year, output_path, event_name, race_folder)
    csv_files = find_csv_files(race_url)
    
    %w[results laps weather].each do |file_type|
      csv_file = csv_files[file_type.to_sym]
      next unless csv_file
      
      download_and_convert_csv(race_url + csv_file, year, output_path, 
                              event_name, race_folder, file_type)
    end
  end

  def find_csv_files(race_url)
    all_files = []
    
    # Get files from main folder and subfolders
    links = fetch_links(race_url)
    files, folders = links.partition { |link| !link.end_with?('/') }
    all_files.concat(files)
    
    # Check subfolders for additional CSV files
    folders.each do |folder|
      next if folder.include?('?')
      
      subfolder_files = fetch_links(race_url + folder)
                       .reject { |f| f.end_with?('/') }
                       .map { |f| folder + f }
      all_files.concat(subfolder_files)
    end
    
    csvs = all_files.grep(/\.csv$/i).reverse
    
    {
      results: find_best_file(csvs, /03_.*\.csv$/i),
      laps: csvs.find { |f| f.match(/23_.*\.csv$/i) },
      weather: csvs.find { |f| f.match(/26_.*\.csv$/i) }
    }
  end

  def find_best_file(files, pattern)
    candidates = files.grep(pattern)
    candidates.find { |f| f.match(/official/i) } ||
    candidates.find { |f| f.match(/unofficial/i) } ||
    candidates.first
  end

  def download_and_convert_csv(url, year, output_path, event_name, race_folder, file_type)
    target_file = build_target_path(output_path, year, event_name, race_folder, file_type)
    
    return if File.exist?(target_file)
    
    FileUtils.mkdir_p(File.dirname(target_file))
    
    print "\n[downloading] → #{target_file}"
    
    begin
      URI.open(url) do |remote|
        content = remote.read
        convert_semicolon_csv(content, target_file)
      end
      print " ✅"
    rescue => e
      print " ❌"
      puts "\nError downloading #{url}: #{e.message}"
    end
  end

  def build_target_path(output_path, year, event_name, race_folder, file_type)
    filename = "#{race_folder.chomp('/')}-#{file_type}.csv"
    path = File.join(output_path, year.to_s, event_name, filename)
    
    # Clean up the path
    path.downcase
        .gsub(/%20/, ' ')
        .gsub(/[^a-z0-9.\-\/]+/, '-')
  end

  def convert_semicolon_csv(content, target_file)
    File.open(target_file, 'w') do |output|
      CSV.parse(content, col_sep: ';') do |row|
        output.puts(CSV.generate_line(row))
      end
    end
  end

  def extract_folder_name(url)
    url.split('/').last.chomp('/')
  end
end

# Command line interface
if __FILE__ == $0
  require 'optparse'

  options = {
    year: Date.today.year,
    output_path: 'data/',
    series_pattern: DEFAULT_SERIES_PATTERN
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"
    
    opts.on("-y", "--year YEAR", Integer, "Year to fetch (default: current year)") do |year|
      options[:year] = year
    end
    
    opts.on("-o", "--output-path PATH", String, "Output directory (default: data/)") do |path|
      options[:output_path] = path
    end
    
    opts.on("-s", "--series-pattern PATTERN", String, "Series pattern (default: #{DEFAULT_SERIES_PATTERN})") do |pattern|
      options[:series_pattern] = pattern
    end
    
    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!

  importer = IMSAImporter.new
  importer.import_year(options[:year], options[:output_path], options[:series_pattern])
  puts "\nImport completed!"
end
