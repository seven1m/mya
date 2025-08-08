require 'minitest/assertions'
require 'tempfile'
require 'pp'

module Minitest::Assertions
  def assert_equal_with_diff(expected, actual)
    if expected != actual
      expected_file = Tempfile.new('expected')
      actual_file = Tempfile.new('actual')
      PP.pp(expected, expected_file)
      PP.pp(actual, actual_file)
      expected_file.close
      actual_file.close
      puts `diff #{expected_file.path} #{actual_file.path}`
      expected_file.unlink
      actual_file.unlink
    end
    assert_equal expected, actual
  end
end

require 'minitest/spec'

module Minitest::Expectations
  Enumerable.infect_an_assertion :assert_equal_with_diff, :must_equal_with_diff
end
