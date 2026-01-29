#!/usr/bin/env ruby
# Test driver name normalization on existing CSV files

require 'csv'
require_relative 'lib/driver_normalizer'

normalizer = DriverNormalizer.new

# Test on a sample laps file
sample_files = Dir['data/imsa/2025/02-*/202501251340-race-laps.csv'].first

unless sample_files
  puts "No sample file found"
  exit 1
end

puts "Testing on: #{sample_files}\n\n"

# Read the file and check driver names
rows = CSV.read(sample_files)
header = rows.first
driver_idx = header.index('DRIVER_NAME')

unless driver_idx
  puts "No DRIVER_NAME column found"
  exit 1
end

# Collect unique driver names and their normalized versions
drivers = {}
rows[1..].each do |row|
  name = row[driver_idx]
  next if name.nil? || name.strip.empty?
  
  normalized = normalizer.normalize(name)
  drivers[name] ||= { normalized: normalized, count: 0 }
  drivers[name][:count] += 1
end

# Show names that would change
changes = drivers.select { |orig, data| orig != data[:normalized] }

puts "Driver names that would be normalized (#{changes.length}/#{drivers.length}):\n\n"

changes.sort_by { |_, data| -data[:count] }.each do |orig, data|
  puts "  #{orig.ljust(35)} => #{data[:normalized]} (#{data[:count]} laps)"
end

puts "\nNormalization Report:"
normalizer.report
