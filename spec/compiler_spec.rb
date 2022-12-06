require 'minitest/autorun'
require 'minitest/focus'

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
      { type: :int, instruction: [:set_var, :a] },
      { type: :int, instruction: [:push_var, :a] }
    ]
  end

  it 'can set a variable more than once' do
    expect(compile('a = 1; a = 2')).must_equal [
      { type: :int, instruction: [:push_int, 1] },
      { type: :int, instruction: [:set_var, :a] },
      { type: :int, instruction: [:push_int, 2] },
      { type: :int, instruction: [:set_var, :a] }
    ]
  end

  it 'raises an error if the variable type changes' do
    e = expect do
      compile('a = 1; a = "foo"')
    end.must_raise TypeError
    expect(e.message).must_equal 'Variable a was set with more than one type: [:int, :str]'
  end
end
