require 'open-uri'
require 'fileutils'
require 'date'
require 'cgi'
require 'csv'
require 'set'

# Series Configuration
# Defines timing URLs and patterns for each supported racing series
SERIES_CONFIG = {
  'imsa' => {
    name: 'IMSA WeatherTech Championship',
    base_url: 'https://imsa.results.alkamelcloud.com/Results/',
    series_pattern: 'IMSA WeatherTech',
    year_prefix: ->(year) { "#{year.to_s[-2..]}_#{year}" }  # "24_2024"
  },
  'wec' => {
    name: 'FIA World Endurance Championship',
    base_url: 'http://fiawec.alkamelsystems.com/Results/',
    series_pattern: 'FIA WEC',
    year_prefix: ->(year) { "#{(year - 2011)}_#{year}" }  # "13_2024" for 2024 (started 2012)
  },
  'elms' => {
    name: 'European Le Mans Series',
    base_url: 'https://elms.alkamelsystems.com/Results/',
    series_pattern: 'European Le Mans Series',
    year_prefix: ->(year) { "#{(year - 2005)}_#{year}" }  # "19_2024" for 2024 (started 2006)
  },
  'alms' => {
    name: 'Asian Le Mans Series',
    base_url: 'http://alms.alkamelsystems.com/Results/',
    series_pattern: 'Asian Le Mans Series',
    year_prefix: ->(year) { "#{(year - 2020)}_#{year}" }  # Adjust if needed
  },
  'lmc' => {
    name: 'Le Mans Cup',
    base_url: 'https://lemanscup.alkamelsystems.com/Results/',
    series_pattern: 'Le Mans Cup',
    year_prefix: ->(year) { "#{(year - 2015)}_#{year}" }  # Adjust if needed
  }
}

# Legacy constants for backward compatibility
BASE_URL = SERIES_CONFIG['imsa'][:base_url]
DEFAULT_SERIES_PATTERN = SERIES_CONFIG['imsa'][:series_pattern]

class EnduranceSeriesImporter
  attr_reader :series_code, :series_config

  def initialize(series_code = 'imsa')
    @series_code = series_code.downcase
    @series_config = SERIES_CONFIG[@series_code]

    unless @series_config
      raise ArgumentError, "Unknown series: #{series_code}. Valid options: #{SERIES_CONFIG.keys.join(', ')}"
    end

    @visited = Set.new
    puts "Initialized #{@series_config[:name]} importer"
  end

  def import_year(year, output_path = 'data/')
    year_prefix = @series_config[:year_prefix].call(year)
    events_url = "#{@series_config[:base_url]}#{year_prefix}/"

    puts "Importing #{@series_config[:name]} data for #{year}..."
    puts "  Source: #{events_url}"

    fetch_links(events_url).each do |event_folder|
      next unless event_folder.end_with?('/') && !event_folder.start_with?('.')

      import_event(events_url + event_folder, year, output_path)
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

  def import_event(event_url, year, output_path)
    fetch_links(event_url).each do |series_folder|
      next unless series_folder.end_with?('/') && !series_folder.start_with?('.')
      next unless CGI.unescape(series_folder).include?(@series_config[:series_pattern])

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
    # New structure: data/{series}/{year}/{event}/{filename}
    path = File.join(output_path, @series_code, year.to_s, event_name, filename)

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

# Legacy class name for backward compatibility
IMSAImporter = EnduranceSeriesImporter

# Command line interface
if __FILE__ == $0
  require 'optparse'

  options = {
    year: Date.today.year,
    output_path: 'data/',
    series: 'imsa'
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"
    opts.separator ""
    opts.separator "Supported series: #{SERIES_CONFIG.keys.join(', ')}"
    opts.separator ""

    opts.on("-y", "--year YEAR", Integer, "Year to fetch (default: current year)") do |year|
      options[:year] = year
    end

    opts.on("-o", "--output-path PATH", String, "Output directory (default: data/)") do |path|
      options[:output_path] = path
    end

    opts.on("-s", "--series SERIES", String,
            "Series to import (default: imsa)",
            "  Options: #{SERIES_CONFIG.keys.join(', ')}",
            "  imsa  = IMSA WeatherTech Championship",
            "  wec   = FIA World Endurance Championship (includes 24h Le Mans)",
            "  elms  = European Le Mans Series",
            "  alms  = Asian Le Mans Series",
            "  lmc   = Le Mans Cup") do |series|
      options[:series] = series.downcase
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      puts "\nExamples:"
      puts "  #{$0} --series imsa --year 2024"
      puts "  #{$0} --series wec --year 2024"
      puts "  #{$0} --series elms --year 2023"
      exit
    end
  end.parse!

  begin
    importer = EnduranceSeriesImporter.new(options[:series])
    importer.import_year(options[:year], options[:output_path])
    puts "\n✅ Import completed successfully!"
    puts "   Data saved to: #{options[:output_path]}#{options[:series]}/#{options[:year]}/"
  rescue ArgumentError => e
    puts "❌ Error: #{e.message}"
    exit 1
  rescue => e
    puts "❌ Import failed: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end
end
