require_relative './spec_helper'

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

  it 'compiles booleans' do
    expect(compile('true')).must_equal [{ type: :bool, instruction: [:push_true] }]
    expect(compile('false')).must_equal [{ type: :bool, instruction: [:push_false] }]
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

  it 'compiles method definitions' do
    code = <<~CODE
      def foo
        'foo'
      end
      def bar
        1
      end
      foo
      bar
    CODE
    expect(compile(code)).must_equal [
      { type: :str, instruction: [:def, :foo] },
      { type: :str, instruction: [:push_str, 'foo'] },
      { type: nil, instruction: [:end_def, :foo] },
      { type: :int, instruction: [:def, :bar] },
      { type: :int, instruction: [:push_int, 1] },
      { type: nil, instruction: [:end_def, :bar] },
      { type: :str, instruction: [:call, :foo, 0] },
      { type: :int, instruction: [:call, :bar, 0] }
    ]
  end

  it 'compiles method definitions with arguments' do
    code = <<~CODE
      def bar(a)
        a
      end

      def foo(a, b)
        a
      end

      foo('foo', 1)

      bar(2)
    CODE
    expect(compile(code)).must_equal_with_diff [
      { type: :int, instruction: [:def, :bar] },
      { type: :int, instruction: [:push_arg, 0] },
      { type: :int, instruction: [:set_var, :a] },
      { type: :int, instruction: [:push_var, :a] },
      { type: nil, instruction: [:end_def, :bar] },

      { type: :str, instruction: [:def, :foo] },
      { type: :str, instruction: [:push_arg, 0] },
      { type: :str, instruction: [:set_var, :a] },
      { type: :int, instruction: [:push_arg, 1] },
      { type: :int, instruction: [:set_var, :b] },
      { type: :str, instruction: [:push_var, :a] },
      { type: nil, instruction: [:end_def, :foo] },

      { type: :str, instruction: [:push_str, 'foo'] },
      { type: :int, instruction: [:push_int, 1] },
      { type: :str, instruction: [:call, :foo, 2] },

      { type: :int, instruction: [:push_int, 2] },
      { type: :int, instruction: [:call, :bar, 1] }
    ]
  end

  it 'raises an error if the method arg type is unknown' do
    code = <<~CODE
      def foo(a)
        a
      end
    CODE
    e = expect { compile(code) }.must_raise TypeError
    expect(e.message).must_equal "Not enough information to infer type of argument 'a' in method 'foo'"
  end

  # NOTE: we don't support monomorphization (yet!)
  it 'raises an error if the method arg can have more than one type' do
    code = <<~CODE
      def foo(a)
        a
      end

      foo(1)

      foo('bar')
    CODE
    e = expect { compile(code) }.must_raise TypeError
    expect(e.message).must_equal "Argument 'a' in method 'foo' was called with more than one type: [:int, :str]"
  end

  it 'compiles operator expressions' do
    code = <<~CODE
      1 + 2
      3 == 4
    CODE
    expect(compile(code)).must_equal [
      { type: :int, instruction: [:push_int, 1] },
      { type: :int, instruction: [:push_int, 2] },
      { type: :int, instruction: [:call, :+, 2] },

      { type: :int, instruction: [:push_int, 3] },
      { type: :int, instruction: [:push_int, 4] },
      { type: :int, instruction: [:call, :==, 2] }
    ]
  end

  it 'compiles if expressions' do
    code = <<~CODE
      if 1
        2
      else
        3
      end
    CODE
    expect(compile(code)).must_equal_with_diff [
      { type: :int, instruction: [:push_int, 1] },
      { type: :int, instruction: [:if] },
      { type: :int, instruction: [:push_int, 2] },
      { type: nil, instruction: [:else] },
      { type: :int, instruction: [:push_int, 3] },
      { type: nil, instruction: [:end_if] }
    ]
  end

  it 'raises an error if both branches of an if expression do not have the same type' do
    code = <<~CODE
      if 1
        2
      else
        'foo'
      end
    CODE
    e = expect { compile(code) }.must_raise TypeError
    expect(e.message).must_equal "Instruction 'if' could have more than one type: [:int, :str]"
  end

  it 'compiles examples/fib.rb' do
    code = File.read(File.expand_path('../examples/fib.rb', __dir__))
    expect(compile(code)).must_equal_with_diff [
      { type: :int, instruction: [:def, :fib] },
      { type: :int, instruction: [:push_arg, 0] },
      { type: :int, instruction: [:set_var, :n] },
      { type: :int, instruction: [:push_var, :n] },
      { type: :int, instruction: [:push_int, 0] },
      { type: :int, instruction: [:call, :==, 2] },
      { type: :int, instruction: [:if] },
      { type: :int, instruction: [:push_int, 0] },
      { type: nil, instruction: [:else] },
      { type: :int, instruction: [:push_var, :n] },
      { type: :int, instruction: [:push_int, 1] },
      { type: :int, instruction: [:call, :==, 2] },
      { type: :int, instruction: [:if] },
      { type: :int, instruction: [:push_int, 1] },
      { type: nil, instruction: [:else] },
      { type: :int, instruction: [:push_var, :n] },
      { type: :int, instruction: [:push_int, 1] },
      { type: :int, instruction: [:call, :-, 2] },
      { type: :int, instruction: [:call, :fib, 1] },
      { type: :int, instruction: [:push_var, :n] },
      { type: :int, instruction: [:push_int, 2] },
      { type: :int, instruction: [:call, :-, 2] },
      { type: :int, instruction: [:call, :fib, 1] },
      { type: :int, instruction: [:call, :+, 2] },
      { type: nil, instruction: [:end_if] },
      { type: nil, instruction: [:end_if] },
      { type: nil, instruction: [:end_def, :fib] },
      { type: :int, instruction: [:push_int, 15] },
      { type: :int, instruction: [:call, :fib, 1] },
      { type: :int, instruction: [:call, :p, 1] }
    ]
  end
end
