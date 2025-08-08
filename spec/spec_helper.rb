require 'minitest/autorun'
require 'minitest/focus'
require 'minitest/reporters'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

require_relative '../lib/mya'
require_relative '../spec/support/expectations'
