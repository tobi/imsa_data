require 'open-uri'
require 'fileutils'
require 'date'
require 'cgi'
require 'csv'
require 'set'
require 'json'

# Load driver normalizer
require_relative 'lib/driver_normalizer'

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
    base_url: 'https://fiawec.alkamelsystems.com/Results/',
    season_page: 'https://fiawec.alkamelsystems.com/?season=',
    series_pattern: 'FIA WEC',
    year_prefix: ->(year) { "#{(year - 2011)}_#{year}" },  # "13_2024" for 2024 (started 2012)
    use_html_scraping: true
  },
  'elms' => {
    name: 'European Le Mans Series',
    base_url: 'https://elms.alkamelsystems.com/Results/',
    season_page: 'https://elms.alkamelsystems.com/?season=',
    series_pattern: 'European Le Mans Series',
    year_prefix: ->(year) { "#{(year - 2005)}_#{year}" },  # "19_2024" for 2024 (started 2006)
    use_html_scraping: true
  },
  'alms' => {
    name: 'Asian Le Mans Series',
    base_url: 'https://alms.alkamelsystems.com/Results/',
    season_page: 'https://alms.alkamelsystems.com/?season=',
    series_pattern: 'Asian Le Mans Series',
    # ALMS uses winter season format: "05_2025-2026" for 2025-2026 season
    year_prefix: ->(year) { sprintf("%02d_%d-%d", year - 2021, year - 1, year) },
    use_html_scraping: true
  },
  'lmc' => {
    name: 'Le Mans Cup',
    base_url: 'https://lemanscup.alkamelsystems.com/Results/',
    season_page: 'https://lemanscup.alkamelsystems.com/?season=',
    series_pattern: 'Le Mans Cup',
    year_prefix: ->(year) { "#{(year - 2015)}_#{year}" },  # Adjust if needed
    use_html_scraping: true
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
    @driver_normalizer = DriverNormalizer.new('driver_cache.json')
    puts "Initialized #{@series_config[:name]} importer"
  end

  def import_year(year, output_path = 'data/')
    year_prefix = @series_config[:year_prefix].call(year)

    puts "Importing #{@series_config[:name]} data for #{year}..."

    if @series_config[:use_html_scraping]
      import_year_via_html(year, year_prefix, output_path)
    else
      import_year_via_directory_listing(year, year_prefix, output_path)
    end
  end

  def import_year_via_html(year, year_prefix, output_path)
    season_url = "#{@series_config[:season_page]}#{year_prefix}"
    puts "  Source: #{season_url}"

    # First, get the list of all events from the dropdown
    events = fetch_events_from_html(season_url)
    puts "  Found #{events.length} events for #{year}"

    total_csvs = 0
    events_manifest = []

    events.each do |event_code, event_name|
      puts "\n  Importing #{event_name}..."
      event_url = "#{season_url}&evvent=#{CGI.escape(event_code)}"

      csv_files = fetch_csv_files_from_html(event_url)
      puts "    Found #{csv_files.length} CSV files"
      total_csvs += csv_files.length

      # Extract event number from code (e.g., "01_LOSAIL" -> "01")
      event_number = event_code.split('_').first
      event_folder = "#{event_number}-#{event_name.downcase.gsub(/[^a-z0-9]+/, '-')}"

      # Track event info for manifest
      events_manifest << {
        event_number: event_number,
        event_name: event_name,
        event_folder: event_folder
      }

      csv_files.each do |csv_path|
        download_csv_from_html(csv_path, year, output_path, event_number, event_name)
      end
    end

    # Save events manifest
    save_events_manifest(output_path, year, events_manifest)

    puts "\n  Total: #{total_csvs} CSV files across #{events.length} events"
    
    # Save driver cache and report
    save_driver_cache
  end

  def import_year_via_directory_listing(year, year_prefix, output_path)
    events_url = "#{@series_config[:base_url]}#{year_prefix}/"
    puts "  Source: #{events_url}"

    events_manifest = []

    fetch_links(events_url).each do |event_folder|
      next unless event_folder.end_with?('/') && !event_folder.start_with?('.')

      # Extract event name from folder (e.g., "02_Daytona International Speedway/" -> "Daytona International Speedway")
      decoded_folder = CGI.unescape(event_folder.chomp('/'))
      if decoded_folder =~ /^(\d+)_(.+)$/
        event_number = $1
        event_name = $2
        event_folder_clean = "#{event_number}-#{event_name.downcase.gsub(/[^a-z0-9]+/, '-')}"

        events_manifest << {
          event_number: event_number,
          event_name: event_name,
          event_folder: event_folder_clean
        }
      end

      import_event(events_url + event_folder, year, output_path)
    end

    # Save events manifest
    save_events_manifest(output_path, year, events_manifest)
    
    # Save driver cache and report
    save_driver_cache
  end

  private
  
  def save_driver_cache
    return unless @driver_normalizer
    
    @driver_normalizer.save_cache
    @driver_normalizer.report
  end

  def save_events_manifest(output_path, year, events)
    manifest_path = File.join(output_path, @series_code, year.to_s, 'events.json')
    FileUtils.mkdir_p(File.dirname(manifest_path))

    # Merge with existing manifest if present (don't overwrite)
    existing = []
    if File.exist?(manifest_path)
      existing = JSON.parse(File.read(manifest_path))
    end

    # Merge by event_folder, preferring new data
    merged = (existing + events).uniq { |e| e['event_folder'] || e[:event_folder] }

    File.write(manifest_path, JSON.pretty_generate(merged))
    puts "\n  Saved events manifest: #{manifest_path}"
  end

  def fetch_events_from_html(season_url)
    begin
      headers = {
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      }
      html = URI.open(season_url, headers, &:read).force_encoding("UTF-8")

      # Extract event options from dropdown
      # Pattern: <option Value="01_LOSAIL">LOSAIL</option>
      events = html.scan(/<option Value="(\d+_[^"]+)"[^>]*>([^<]+)<\/option>/)

      # Filter to only numeric event codes (exclude year selections like "14_2025")
      events.select { |code, name| code.match?(/^\d{2}_[A-Z]/) }
    rescue => e
      puts "Error fetching events from #{season_url}: #{e.message}"
      []
    end
  end

  def fetch_csv_files_from_html(season_url)
    begin
      headers = {
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      }
      html = URI.open(season_url, headers, &:read).force_encoding("UTF-8")

      # Extract all CSV file paths from href attributes
      # Includes files in subfolders (e.g., Le Mans hourly race data)
      csv_paths = html.scan(/href="(Results\/[^"]*\.CSV)"/).map(&:first)

      # Filter to results (03_), laps (23_), and weather (26_) files
      # Allow files in subfolders (e.g., Race/01_Hour 1/23_Analysis.CSV)
      csv_paths.select do |path|
        path.match?(/\/(03_[^\/]*|23_[^\/]*|26_[^\/]*)\.CSV$/i)
      end.uniq
    rescue => e
      puts "Error fetching season page #{season_url}: #{e.message}"
      []
    end
  end

  def download_csv_from_html(csv_path, year, output_path, event_number = nil, event_name = nil)
    # Parse the path to extract components
    # Example: Results/13_2024/08_BAHRAIN%20INTERNATIONAL%20CIRCUIT/575_FIA%20WEC/202410311215_Free%20Practice%201/23_Analysis_Free%20Practice%201.CSV
    # Or with subfolders: Results/13_2024/04_LE%20MANS/541_FIA%20WEC/202406151600_Race/24_Hour%2024/23_Analysis_Race_Hour%2024.CSV
    parts = csv_path.split('/')
    return unless parts.length >= 6

    # Use provided event_name if available, otherwise extract from path
    if event_number && event_name
      event_folder = "#{event_number}-#{event_name.downcase.gsub(/[^a-z0-9]+/, '-')}"
    else
      event_folder = CGI.unescape(parts[2]).downcase.gsub(/[^a-z0-9]+/, '-')
    end

    # Session folder is at index 4, but there may be subfolders for hourly data
    session_folder = parts[4]

    # Get filename (last part) to determine file type
    filename = parts.last

    # For hourly race data, include hour in the session name
    # e.g., 202406151600_Race/24_Hour 24/23_Analysis... -> 202406151600_Race-hour-24
    if parts.length > 6
      subfolder = CGI.unescape(parts[5]).downcase.gsub(/[^a-z0-9]+/, '-')
      if subfolder =~ /hour-?(\d+)/
        session_folder = "#{session_folder}-hour-#{$1}"
      end
    end

    # Determine file type from filename
    file_type = case filename
                when /^03_/i then 'results'
                when /^23_/i then 'laps'
                when /^26_/i then 'weather'
                else return
                end

    # Build target path
    target_file = File.join(
      output_path,
      @series_code,
      year.to_s,
      event_folder,
      "#{session_folder.downcase.gsub(/[^a-z0-9]+/, '-')}-#{file_type}.csv"
    )

    return if File.exist?(target_file)

    FileUtils.mkdir_p(File.dirname(target_file))

    full_url = "#{@series_config[:base_url].gsub(/Results\/$/, '')}#{csv_path}"
    print "\n[downloading] → #{target_file}"

    begin
      headers = {
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept' => 'text/csv,text/plain,*/*'
      }
      URI.open(full_url, headers) do |remote|
        content = remote.read
        convert_semicolon_csv(content, target_file)
      end
      print " ✅"
    rescue => e
      print " ❌"
      puts "\nError downloading #{full_url}: #{e.message}"
    end
  end

  def fetch_links(url)
    url = url.gsub(/\?.*$/, '')
    return [] if @visited.include?(url)
    @visited.add(url)

    begin
      # Add browser-like headers to avoid 403 errors
      headers = {
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language' => 'en-US,en;q=0.9',
        'Connection' => 'keep-alive'
      }
      body = URI.open(url, headers, &:read).force_encoding("ISO-8859-1").encode("UTF-8")
      body.scan(/href="([^"]+)"/)
          .map(&:first)
          .reject { |link| link.start_with?('/') }
    rescue => e
      puts "Error fetching #{url}: #{e.message}"
      puts e.backtrace.first(3).join("\n")
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
    # First, get the main session files
    csv_files = find_csv_files(race_url)

    %w[results laps weather].each do |file_type|
      csv_file = csv_files[file_type.to_sym]
      next unless csv_file

      download_and_convert_csv(race_url + csv_file, year, output_path,
                              event_name, race_folder, file_type)
    end

    # Then, check for hourly subfolders (common in endurance races)
    import_hourly_data(race_url, year, output_path, event_name, race_folder)
  end

  def import_hourly_data(race_url, year, output_path, event_name, race_folder)
    # Allow re-fetching this URL since find_csv_files already visited it
    @visited.delete(race_url.gsub(/\?.*$/, ''))
    links = fetch_links(race_url)
    # Match hourly folders: "01_Hour 1/", "01_Hour%201/", "24_Hour 24/", etc.
    hourly_folders = links.select { |f| f.match?(/^\d+_Hour(%20|\s)*\d+\//i) }

    return if hourly_folders.empty?

    # Sort by hour number and process each
    hourly_folders.sort_by { |f| f.match(/(\d+)_Hour/i)[1].to_i rescue 0 }.each do |hour_folder|
      # Extract hour number from folder name
      decoded = CGI.unescape(hour_folder)
      hour_num = decoded.match(/(\d+)_Hour\s*(\d+)/i)&.[](2) || decoded.match(/^(\d+)_/)[1]
      hour_url = race_url + hour_folder

      hour_files = find_csv_files(hour_url)

      %w[results laps weather].each do |file_type|
        csv_file = hour_files[file_type.to_sym]
        next unless csv_file

        # Add hour suffix to the race folder
        hourly_race_folder = "#{race_folder.chomp('/')}-hour-#{hour_num}"
        download_and_convert_csv(hour_url + csv_file, year, output_path,
                                event_name, hourly_race_folder, file_type)
      end
    end
  end

  def find_csv_files(race_url)
    all_files = []

    # Get files from main folder and subfolders (but not Hour folders - those are handled separately)
    links = fetch_links(race_url)
    files, folders = links.partition { |link| !link.end_with?('/') }
    all_files.concat(files)

    # Check non-hour subfolders for additional CSV files
    folders.each do |folder|
      next if folder.include?('?')
      next if folder.match?(/^\d+_Hour(%20|\s)*/i)  # Skip hour folders, handled separately

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
      # Add browser-like headers to avoid 403 errors
      headers = {
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept' => 'text/csv,text/plain,*/*',
        'Accept-Language' => 'en-US,en;q=0.9',
        'Referer' => url.split('/')[0..3].join('/')
      }
      URI.open(url, headers) do |remote|
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
    rows = CSV.parse(content, col_sep: ';')

    # For weather files, detect and convert temperature units
    if target_file.end_with?('-weather.csv') && rows.any?
      rows = normalize_weather_temperatures(rows)
    end

    # For laps and results files, normalize driver names
    if (target_file.end_with?('-laps.csv') || target_file.end_with?('-results.csv')) && rows.any?
      rows = normalize_driver_names(rows)
    end

    File.open(target_file, 'w') do |output|
      rows.each do |row|
        output.puts(CSV.generate_line(row))
      end
    end

    # Verify file type matches header and rename if needed
    verify_and_fix_file_type(target_file)
  end

  def normalize_weather_temperatures(rows)
    return rows if rows.length < 2

    header = rows.first.map { |h| h&.strip&.upcase }
    air_idx = header.index('AIR_TEMP')
    track_idx = header.index('TRACK_TEMP')

    return rows unless air_idx || track_idx

    # Sample temperature values to detect unit
    temp_samples = []
    rows[1..20].each do |row|
      temp_samples << row[air_idx].to_f if air_idx && row[air_idx]
      temp_samples << row[track_idx].to_f if track_idx && row[track_idx]
    end

    return rows if temp_samples.empty?

    # Heuristic: if median temp is < 45, it's likely Celsius
    # (45°C = 113°F, reasonable upper bound for ambient racing temps)
    # Racing doesn't happen below 0°C typically, so 0-45 range = Celsius
    median = temp_samples.sort[temp_samples.length / 2]
    is_celsius = median < 45

    return rows unless is_celsius

    puts " [converting °C→°F]"

    # Convert all temperature values
    rows.each_with_index.map do |row, idx|
      next row if idx == 0  # Skip header

      new_row = row.dup
      if air_idx && row[air_idx]
        celsius = row[air_idx].to_f
        new_row[air_idx] = ((celsius * 9.0 / 5.0) + 32).round(2).to_s
      end
      if track_idx && row[track_idx]
        celsius = row[track_idx].to_f
        new_row[track_idx] = ((celsius * 9.0 / 5.0) + 32).round(2).to_s
      end
      new_row
    end
  end

  def normalize_driver_names(rows)
    return rows if rows.length < 2 || @driver_normalizer.nil?

    header = rows.first.map { |h| h&.strip&.upcase }
    
    # Find driver name columns
    # Laps files: DRIVER_NAME
    # Results files: DRIVER1_FIRSTNAME + DRIVER1_SECONDNAME (up to DRIVER6)
    driver_name_idx = header.index('DRIVER_NAME')
    
    # Collect firstname/lastname pairs for results files
    driver_pairs = []
    (1..6).each do |n|
      first_idx = header.index("DRIVER#{n}_FIRSTNAME")
      second_idx = header.index("DRIVER#{n}_SECONDNAME")
      if first_idx && second_idx
        driver_pairs << [first_idx, second_idx]
      end
    end
    
    return rows if driver_name_idx.nil? && driver_pairs.empty?
    
    rows.each_with_index.map do |row, idx|
      next row if idx == 0  # Skip header
      
      new_row = row.dup
      
      # Normalize DRIVER_NAME column (laps files)
      if driver_name_idx && new_row[driver_name_idx]
        new_row[driver_name_idx] = @driver_normalizer.normalize(new_row[driver_name_idx])
      end
      
      # Normalize DRIVER#_FIRSTNAME + SECONDNAME pairs (results files)
      driver_pairs.each do |first_idx, second_idx|
        first = new_row[first_idx]
        second = new_row[second_idx]
        
        if first && second && !first.strip.empty? && !second.strip.empty?
          # Combine first + last, normalize, then split back
          full_name = "#{first} #{second}"
          normalized = @driver_normalizer.normalize(full_name)
          parts = normalized.split(' ', 2)
          
          new_row[first_idx] = parts[0] || first
          new_row[second_idx] = parts[1] || second
        end
      end
      
      new_row
    end
  end

  def verify_and_fix_file_type(file_path)
    return unless File.exist?(file_path)

    begin
      header = File.open(file_path, &:readline).strip.upcase

      # Determine actual type from headers
      actual_type = if header.include?('LAP_NUMBER') && header.include?('LAP_TIME')
                      'laps'
                    elsif header.include?('POSITION') && header.include?('TEAM')
                      'results'
                    elsif header.include?('AIR_TEMP') || header.include?('TRACK_TEMP')
                      'weather'
                    else
                      nil
                    end

      return unless actual_type

      # Check if filename matches actual type
      named_type = case File.basename(file_path)
                   when /-laps\.csv$/i then 'laps'
                   when /-results\.csv$/i then 'results'
                   when /-weather\.csv$/i then 'weather'
                   else return
                   end

      if actual_type != named_type
        # Rename file to correct type
        new_path = file_path.sub(/-#{named_type}\.csv$/i, "-#{actual_type}.csv")
        unless File.exist?(new_path)
          FileUtils.mv(file_path, new_path)
          puts " [renamed: #{named_type}→#{actual_type}]"
        else
          # Both files exist, delete the misnamed one
          FileUtils.rm(file_path)
          puts " [removed duplicate, kept correct #{actual_type}]"
        end
      end
    rescue => e
      # Ignore read errors
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
