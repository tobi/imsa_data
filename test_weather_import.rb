require 'minitest/autorun'
require_relative 'import'

class WeatherImportTest < Minitest::Test
  def test_decimal_comma_temperature_is_not_truncated
    importer = EnduranceSeriesImporter.new('elms')
    rows = [['AIR_TEMP', 'TRACK_TEMP'], ['20,5', '30,25']]
    converted = importer.send(:normalize_weather_temperatures, rows)
    assert_equal ['68.9', '86.45'], converted[1]
    assert_equal ['20,5', '30,25'], rows[1]
  end
end
