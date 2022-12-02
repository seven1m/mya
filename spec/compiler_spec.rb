require 'minitest/autorun'

require_relative '../lib/compiler'

describe Compiler do
  def compile(code)
    Compiler.new(code).compile
  end

  it 'compiles integers' do
    expect(compile('1')).must_equal [
      [:push_int, 1]
    ]
  end

  it 'compiles strings' do
    expect(compile('"foo"')).must_equal [
      [:push_str, 'foo']
    ]
  end

  it 'compiles variables set and get' do
    expect(compile('a = 1; a')).must_equal [
      [:push_int, 1],
      [:set_var, :a],
      [:push_var, :a],
    ]
  end
end
