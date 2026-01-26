#!/usr/bin/env ruby
# One-time script to normalize driver names in existing CSV files
# Run once, then the importer will handle new files

require 'csv'
require 'fileutils'
require_relative '../lib/driver_normalizer'

DRY_RUN = ARGV.include?('--dry-run')
VERBOSE = ARGV.include?('-v') || ARGV.include?('--verbose')

normalizer = DriverNormalizer.new

# Find all laps and results files
# Optionally filter by pattern from command line
pattern = ARGV.find { |a| !a.start_with?('-') } || 'data/**/*'
files = Dir["#{pattern}-laps.csv"] + Dir["#{pattern}-results.csv"]
puts "Found #{files.length} files to process\n\n"

files_modified = 0
rows_modified = 0

files.each do |file|
  rows = CSV.read(file)
  next if rows.length < 2
  
  header = rows.first
  modified = false
  file_changes = 0
  
  # Find driver columns
  driver_name_idx = header.index('DRIVER_NAME')
  driver_pairs = []
  (1..6).each do |n|
    first_idx = header.index("DRIVER#{n}_FIRSTNAME")
    second_idx = header.index("DRIVER#{n}_SECONDNAME")
    if first_idx && second_idx
      driver_pairs << [first_idx, second_idx]
    end
  end
  
  next if driver_name_idx.nil? && driver_pairs.empty?
  
  # Process each row
  rows[1..].each do |row|
    # Normalize DRIVER_NAME
    if driver_name_idx && row[driver_name_idx]
      orig = row[driver_name_idx]
      normalized = normalizer.normalize(orig)
      if orig != normalized
        row[driver_name_idx] = normalized unless DRY_RUN
        modified = true
        file_changes += 1
        puts "  #{orig} => #{normalized}" if VERBOSE
      end
    end
    
    # Normalize DRIVER#_FIRSTNAME + SECONDNAME
    driver_pairs.each do |first_idx, second_idx|
      first = row[first_idx]
      second = row[second_idx]
      
      if first && second && !first.strip.empty? && !second.strip.empty?
        full_name = "#{first} #{second}"
        normalized = normalizer.normalize(full_name)
        parts = normalized.split(' ', 2)
        
        if parts[0] != first || parts[1] != second
          row[first_idx] = parts[0] unless DRY_RUN
          row[second_idx] = parts[1] unless DRY_RUN
          modified = true
          file_changes += 1
          puts "  #{first} #{second} => #{normalized}" if VERBOSE
        end
      end
    end
  end
  
  if modified
    files_modified += 1
    rows_modified += file_changes
    
    if DRY_RUN
      puts "[DRY RUN] Would modify #{file} (#{file_changes} changes)"
    else
      # Write back
      CSV.open(file, 'w') do |csv|
        rows.each { |row| csv << row }
      end
      print '.'
    end
  end
end

puts "\n\nSummary:"
puts "  Files #{DRY_RUN ? 'would be ' : ''}modified: #{files_modified}"
puts "  Rows #{DRY_RUN ? 'would be ' : ''}modified: #{rows_modified}"

normalizer.save_cache
normalizer.report

if DRY_RUN
  puts "\nThis was a dry run. Run without --dry-run to apply changes."
end
