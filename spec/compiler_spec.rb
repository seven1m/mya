require 'minitest/autorun'

require_relative '../lib/compiler'

describe Compiler do
  def compile(code)
    Compiler.new(code).compile.map(&:to_h)
  end

  it 'compiles integers' do
    expect(compile('1')).must_equal [
      { type: :int, instruction: [:push_int, 1] }
    ]
  end

  it 'compiles strings' do
    expect(compile('"foo"')).must_equal [
      { type: :str, instruction: [:push_str, 'foo'] }
    ]
  end

  it 'compiles variables set and get' do
    expect(compile('a = 1; a')).must_equal [
      { type: :int, instruction: [:push_int, 1] },
      { type: nil, instruction: [:set_var, :a] },
      { type: nil, instruction: [:push_var, :a] }
    ]
  end
end
