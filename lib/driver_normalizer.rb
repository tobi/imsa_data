# Driver Name Normalization
# Applies consistent normalization to driver names at import time

require 'json'

class DriverNormalizer
  # Common accent/umlaut mappings
  ACCENT_MAP = {
    'à' => 'a', 'á' => 'a', 'â' => 'a', 'ã' => 'a', 'ä' => 'a', 'å' => 'a',
    'è' => 'e', 'é' => 'e', 'ê' => 'e', 'ë' => 'e',
    'ì' => 'i', 'í' => 'i', 'î' => 'i', 'ï' => 'i',
    'ò' => 'o', 'ó' => 'o', 'ô' => 'o', 'õ' => 'o', 'ö' => 'o', 'ø' => 'o',
    'ù' => 'u', 'ú' => 'u', 'û' => 'u', 'ü' => 'u',
    'ý' => 'y', 'ÿ' => 'y',
    'ñ' => 'n', 'ç' => 'c',
    'æ' => 'ae', 'œ' => 'oe', 'ß' => 'ss', 'đ' => 'd', 'ł' => 'l',
    # Uppercase versions
    'À' => 'A', 'Á' => 'A', 'Â' => 'A', 'Ã' => 'A', 'Ä' => 'A', 'Å' => 'A',
    'È' => 'E', 'É' => 'E', 'Ê' => 'E', 'Ë' => 'E',
    'Ì' => 'I', 'Í' => 'I', 'Î' => 'I', 'Ï' => 'I',
    'Ò' => 'O', 'Ó' => 'O', 'Ô' => 'O', 'Õ' => 'O', 'Ö' => 'O', 'Ø' => 'O',
    'Ù' => 'U', 'Ú' => 'U', 'Û' => 'U', 'Ü' => 'U',
    'Ý' => 'Y', 'Ÿ' => 'Y',
    'Ñ' => 'N', 'Ç' => 'C',
    'Æ' => 'AE', 'Œ' => 'OE', 'Đ' => 'D', 'Ł' => 'L'
  }

  # Known typos/variations (lowercase normalized form => canonical form)
  KNOWN_TYPOS = {
    'stoffel vandorne' => 'Stoffel Vandoorne',
    'matthieu jaminet' => 'Mathieu Jaminet',
    'gianmaria bruni' => 'Giammaria Bruni',
    'laurents horr' => 'Laurents Hoerr',
    'laurents hoerr' => 'Laurents Hoerr',  # Different from Hörr
    'james dayson' => 'James Davison',
    'nyck de vries' => 'Nick de Vries',  # Both used officially, pick one
  }

  # Common nickname expansions (nickname => canonical)
  NICKNAME_MAP = {
    'phil' => 'philip',
    'ben' => 'benjamin',
    'nick' => 'nicholas',
    'will' => 'william',
    'alex' => 'alexander',
    'dan' => 'daniel',
    'matt' => 'matthew',
    'mike' => 'michael',
    'tom' => 'thomas',
    'rob' => 'robert',
    'bob' => 'robert',
    'bill' => 'william',
    'jim' => 'james',
    'joe' => 'joseph',
    'tony' => 'anthony',
    'chris' => 'christopher',
    'nico' => 'nicolas',
    'maxi' => 'maximilian',
    'max' => 'maximilian',
    'josh' => 'joshua',
    'jon' => 'jonathan',
    'dave' => 'david',
    'andy' => 'andrew',
    'ed' => 'edward',
    'ted' => 'theodore',
    'sam' => 'samuel',
    'charlie' => 'charles',
    'chuck' => 'charles',
    'dick' => 'richard',
    'rick' => 'richard'
  }

  def initialize(cache_path = nil)
    @cache_path = cache_path || 'driver_cache.json'
    @seen_drivers = load_cache
    @stats = { normalized: 0, accent_stripped: 0, nickname_expanded: 0, new_drivers: 0 }
  end

  def load_cache
    return {} unless File.exist?(@cache_path)
    JSON.parse(File.read(@cache_path))
  rescue
    {}
  end

  def save_cache
    File.write(@cache_path, JSON.pretty_generate(@seen_drivers))
  end

  # Main normalization entry point
  def normalize(name)
    return name if name.nil? || name.strip.empty?
    
    original = name.strip
    
    # Step 1: Normalize whitespace
    normalized = original.gsub(/\s+/, ' ')
    
    # Step 2: Handle ALL CAPS or mixed case names (common in timing data)
    # Always normalize to Title Case for consistency
    normalized = to_title_case(normalized)
    
    # Step 3: Strip accents for canonical form
    ascii_form = strip_accents(normalized)
    if ascii_form != normalized
      @stats[:accent_stripped] += 1
      normalized = ascii_form
    end
    
    # Step 4: Expand nicknames in first name
    parts = normalized.split(' ')
    if parts.length >= 2
      first_lower = parts.first.downcase
      if NICKNAME_MAP[first_lower]
        canonical_first = to_title_case(NICKNAME_MAP[first_lower])
        parts[0] = canonical_first
        normalized = parts.join(' ')
        @stats[:nickname_expanded] += 1
      end
    end
    
    # Step 5: Check known typos/variations
    key = normalized.downcase.gsub(/[^a-z ]/, '').gsub(/\s+/, ' ')
    if KNOWN_TYPOS[key]
      normalized = KNOWN_TYPOS[key]
      @stats[:typo_fixed] ||= 0
      @stats[:typo_fixed] += 1
    end
    
    # Step 6: Normalize hyphen/space in compound names
    # "Paul-Loup" and "Paul Loup" -> "Paul-Loup" (keep hyphen if present anywhere)
    normalized = normalize_compound_name(normalized)
    
    # Step 7: Check cache for similar existing driver
    canonical = find_canonical(normalized)
    
    if canonical != normalized
      @stats[:normalized] += 1
    end
    
    # Track this driver
    track_driver(canonical, original)
    
    canonical
  end

  def strip_accents(str)
    result = str.dup
    ACCENT_MAP.each { |from, to| result.gsub!(from, to) }
    result
  end

  def to_title_case(str)
    # Handle special particles that should stay lowercase
    particles = %w[de da di van von der den ten la le du]
    
    str.split(' ').map.with_index do |word, idx|
      # Handle hyphenated names (e.g., "Heinemeier-Hansson")
      if word.include?('-')
        word.split('-').map { |part| capitalize_smart(part) }.join('-')
      else
        lower = word.downcase
        if idx > 0 && particles.include?(lower)
          lower
        else
          capitalize_smart(word)
        end
      end
    end.join(' ')
  end
  
  def capitalize_smart(word)
    lower = word.downcase
    upper = word.upcase
    
    # Handle initials (2-3 letter all-caps like PJ, JR, SR)
    if word.length <= 3 && word == upper && word.match?(/^[A-Z]+$/)
      return upper
    end
    
    # Handle Mc/Mac Scottish prefixes (McAleer, MacDonald)
    if lower.start_with?('mc') && lower.length > 2
      return 'Mc' + lower[2..].capitalize
    end
    if lower.start_with?('mac') && lower.length > 3 && lower[3] != 'h' # Not Machiavelli
      return 'Mac' + lower[3..].capitalize
    end
    
    # Handle O' Irish prefix (O'Brien)
    if lower.start_with?("o'") && lower.length > 2
      return "O'" + lower[2..].capitalize
    end
    
    lower.capitalize
  end

  def normalize_compound_name(name)
    # If name contains both hyphenated and non-hyphenated versions of same part,
    # prefer hyphenated (e.g., "Heinemeier-Hansson" over "Heinemeier Hansson")
    # But only for actual compound surnames, not "First Last"
    
    parts = name.split(' ')
    return name if parts.length < 2
    
    # Check if any part has a hyphen
    hyphenated_parts = parts.select { |p| p.include?('-') }
    return name if hyphenated_parts.empty?
    
    name
  end

  def find_canonical(normalized)
    key = normalized.downcase.gsub(/[^a-z ]/, '').gsub(/\s+/, ' ')
    
    # Check if we've seen this exact key
    if @seen_drivers[key]
      return @seen_drivers[key]['canonical']
    end
    
    # Check for similar drivers (Jaro-Winkler style but simpler)
    @seen_drivers.each do |existing_key, data|
      if similar_enough?(key, existing_key)
        return data['canonical']
      end
    end
    
    # New driver
    @stats[:new_drivers] += 1
    normalized
  end

  def similar_enough?(a, b)
    return true if a == b
    
    # Simple heuristics for matching:
    # 1. Same length, differ by 1-2 chars (typos)
    # 2. One is prefix/suffix of other (truncation)
    
    return false if (a.length - b.length).abs > 3
    
    # Check Levenshtein-like distance (simplified)
    diff_count = 0
    shorter, longer = [a, b].sort_by(&:length)
    
    # If lengths differ significantly, not similar
    return false if longer.length > shorter.length * 1.3
    
    # Count character differences
    shorter.chars.each_with_index do |char, i|
      diff_count += 1 if longer[i] != char
    end
    diff_count += (longer.length - shorter.length)
    
    # Allow 1-2 character differences for short names, more for longer
    max_diff = [2, shorter.length / 5].max
    diff_count <= max_diff
  end

  def track_driver(canonical, original)
    key = canonical.downcase.gsub(/[^a-z ]/, '').gsub(/\s+/, ' ')
    
    @seen_drivers[key] ||= {
      'canonical' => canonical,
      'variants' => []
    }
    
    unless @seen_drivers[key]['variants'].include?(original)
      @seen_drivers[key]['variants'] << original
    end
  end

  def stats
    @stats.merge(
      total_drivers: @seen_drivers.keys.length,
      drivers_with_variants: @seen_drivers.count { |_, v| v['variants'].length > 1 }
    )
  end

  def report
    puts "\nDriver Normalization Report:"
    puts "  Total unique drivers: #{@seen_drivers.keys.length}"
    puts "  Names normalized: #{@stats[:normalized]}"
    puts "  Accents stripped: #{@stats[:accent_stripped]}"
    puts "  Nicknames expanded: #{@stats[:nickname_expanded]}"
    puts "  New drivers found: #{@stats[:new_drivers]}"
    
    multi_variant = @seen_drivers.select { |_, v| v['variants'].length > 1 }
    if multi_variant.any?
      puts "\n  Drivers with multiple name variants (#{multi_variant.length}):"
      multi_variant.first(10).each do |key, data|
        puts "    #{data['canonical']}: #{data['variants'].join(' | ')}"
      end
    end
  end
end

# Standalone usage
if __FILE__ == $0
  normalizer = DriverNormalizer.new
  
  test_names = [
    "Mathias BECHE",
    "Louis DELÉTRAZ",
    "Louis Deletraz",
    "Phil Hanson",
    "Philip HANSON",
    "Kevin ESTRE",
    "Kévin Estre",
    "David HEINEMEIER-HANSSON",
    "David Heinemeier Hansson",
    "Paul-Loup CHATIN",
    "Paul Loup Chatin",
    "Stoffel VANDOORNE",
    "Stoffel Vandorne"
  ]
  
  puts "Testing driver name normalization:\n"
  test_names.each do |name|
    normalized = normalizer.normalize(name)
    puts "  #{name.ljust(30)} => #{normalized}" if name != normalized
    puts "  #{name.ljust(30)} (unchanged)" if name == normalized
  end
  
  normalizer.report
end
