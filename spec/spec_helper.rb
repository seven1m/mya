require 'minitest/autorun'
require 'minitest/focus'
require 'minitest/reporters'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

require_relative '../lib/compiler'
require_relative '../lib/jit'
require_relative '../lib/vm'
require_relative '../spec/support/expectations'
