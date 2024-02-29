require_relative './spec_helper'

describe Compiler do
  def compile(code)
    Compiler.new(code).compile.map(&:to_h)
  end

  it 'compiles integers' do
    expect(compile('1')).must_equal_with_diff [
      { type: 'int', instruction: :push_int, value: 1 }
    ]
  end

  it 'compiles strings' do
    expect(compile('"foo"')).must_equal_with_diff [
      { type: 'str', instruction: :push_str, value: 'foo' }
    ]
  end

  it 'compiles booleans' do
    expect(compile('true')).must_equal_with_diff [{ type: 'bool', instruction: :push_true }]
    expect(compile('false')).must_equal_with_diff [{ type: 'bool', instruction: :push_false }]
  end

  it 'compiles variables set and get' do
    expect(compile('a = 1; a')).must_equal_with_diff [
      { type: 'int', instruction: :push_int, value: 1 },
      { type: 'int', instruction: :set_var, name: :a },
      { type: 'int', instruction: :push_var, name: :a }
    ]
  end

  it 'can set a variable more than once' do
    expect(compile('a = 1; a = 2')).must_equal_with_diff [
      { type: 'int', instruction: :push_int, value: 1 },
      { type: 'int', instruction: :set_var, name: :a },
      { type: 'int', instruction: :push_int, value: 2 },
      { type: 'int', instruction: :set_var, name: :a }
    ]
  end

  it 'raises an error if the variable type changes' do
    e = expect do
      compile('a = 1; a = "foo"')
    end.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal 'the variable a has type int already; you cannot change it to type str'
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
    expect(compile(code)).must_equal_with_diff [
      {
        type: '([] -> str)',
        instruction: :def,
        name: :foo,
        params: [],
        body: [
          { type: 'str', instruction: :push_str, value: 'foo' },
        ]
      },
      {
        type: '([] -> int)',
        instruction: :def,
        name: :bar,
        params: [],
        body: [
          { type: 'int', instruction: :push_int, value: 1 },
        ]
      },
      {
        type: 'str',
        instruction: :call,
        name: :foo,
        arg_count: 0,
      },
      {
        type: 'int',
        instruction: :call,
        name: :bar,
        arg_count: 0,
      }
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
      {
        type: '([int] -> int)',
        instruction: :def,
        name: :bar,
        params: [:a],
        body: [
          { type: 'int', instruction: :push_arg, index: 0 },
          { type: 'int', instruction: :set_var, name: :a },
          { type: 'int', instruction: :push_var, name: :a },
        ]
      },

      {
        type: '([str, int] -> str)',
        instruction: :def,
        name: :foo,
        params: [:a, :b],
        body: [
          { type: 'str', instruction: :push_arg, index: 0 },
          { type: 'str', instruction: :set_var, name: :a },
          { type: 'int', instruction: :push_arg, index: 1 },
          { type: 'int', instruction: :set_var, name: :b },
          { type: 'str', instruction: :push_var, name: :a },
        ]
      },

      { type: 'str', instruction: :push_str, value: 'foo' },
      { type: 'int', instruction: :push_int, value: 1 },
      { type: 'str', instruction: :call, name: :foo, arg_count: 2 },

      { type: 'int', instruction: :push_int, value: 2 },
      { type: 'int', instruction: :call, name: :bar, arg_count: 1 }
    ]
  end

  it 'raises an error if the method arg type is unknown' do
    code = <<~CODE
      def foo(a)
        a
      end
    CODE
    e = expect { compile(code) }.must_raise TypeError
    expect(e.message).must_match /Not enough information to infer type of/
  end

  # NOTE: we don't support monomorphization (yet!)
  it 'raises an error if the method arg has more than one type' do
    code = <<~CODE
      def foo(a)
        a
      end

      foo(1)

      foo('bar')
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal 'int cannot unify with str in call to foo'
  end

  it 'raises an error if the arg count of method and call do not match' do
    code = <<~CODE
      def foo(a)
        a
      end

      foo(1, 2)
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal '([a] -> a) cannot unify with ([int, int] -> b) in call to foo'
  end

  it 'compiles operator expressions' do
    code = <<~CODE
      1 + 2
      3 == 4
    CODE
    expect(compile(code)).must_equal_with_diff [
      { type: 'int', instruction: :push_int, value: 1 },
      { type: 'int', instruction: :push_int, value: 2 },
      { type: 'int', instruction: :call, name: :+, arg_count: 2 },

      { type: 'int', instruction: :push_int, value: 3 },
      { type: 'int', instruction: :push_int, value: 4 },
      { type: 'bool', instruction: :call, name: :==, arg_count: 2 }
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
      { type: 'int', instruction: :push_int, value: 1 },
      {
        type: 'int',
        instruction: :if,
        if_true: [
          { type: 'int', instruction: :push_int, value: 2 },
        ],
        if_false: [
          { type: 'int', instruction: :push_int, value: 3 },
        ]
      },
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
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal 'one branch of `if` has type int and the other has type str'
  end

  it 'compiles calls to puts for both int and str' do
    expect(compile('puts(1)')).must_equal_with_diff [
      { type: 'int', instruction: :push_int, value: 1 },
      { type: 'int', instruction: :call, name: :puts, arg_count: 1 }
    ]
    expect(compile('puts("foo")')).must_equal_with_diff [
      { type: 'str', instruction: :push_str, value: 'foo' },
      { type: 'int', instruction: :call, name: :puts, arg_count: 1 }
    ]
  end

  it 'compiles examples/fib.rb' do
    code = File.read(File.expand_path('../examples/fib.rb', __dir__))
    expect(compile(code)).must_equal_with_diff [
      {
        type: '([int] -> int)',
        instruction: :def,
        name: :fib,
        params: [:n],
        body: [
          { type: 'int', instruction: :push_arg, index: 0 },
          { type: 'int', instruction: :set_var, name: :n },
          { type: 'int', instruction: :push_var, name: :n },
          { type: 'int', instruction: :push_int, value: 0 },
          { type: 'bool', instruction: :call, name: :==, arg_count: 2 },
          {
            type: 'int',
            instruction: :if,
            if_true: [
              { type: 'int', instruction: :push_int, value: 0 },
            ],
            if_false: [
              { type: 'int', instruction: :push_var, name: :n },
              { type: 'int', instruction: :push_int, value: 1 },
              { type: 'bool', instruction: :call, name: :==, arg_count: 2 },
              {
                type: 'int',
                instruction: :if,
                if_true: [
                  { type: 'int', instruction: :push_int, value: 1 },
                ],
                if_false: [
                  { type: 'int', instruction: :push_var, name: :n },
                  { type: 'int', instruction: :push_int, value: 1 },
                  { type: 'int', instruction: :call, name: :-, arg_count: 2 },
                  { type: 'int', instruction: :call, name: :fib, arg_count: 1 },
                  { type: 'int', instruction: :push_var, name: :n },
                  { type: 'int', instruction: :push_int, value: 2 },
                  { type: 'int', instruction: :call, name: :-, arg_count: 2 },
                  { type: 'int', instruction: :call, name: :fib, arg_count: 1 },
                  { type: 'int', instruction: :call, name: :+, arg_count: 2 },
                ]
              },
            ]
          },
        ]
      },

      { type: 'int', instruction: :push_int, value: 10 },
      { type: 'int', instruction: :call, name: :fib, arg_count: 1 },
      { type: 'int', instruction: :call, name: :puts, arg_count: 1 }
    ]
  end

  it 'compiles examples/fact.rb' do
    code = File.read(File.expand_path('../examples/fact.rb', __dir__))
    expect(compile(code)).must_equal_with_diff [
      {
        type: "([int, int] -> int)",
        instruction: :def,
        name: :fact,
        params: [:n, :result],
        body: [
          { type: 'int', instruction: :push_arg, index: 0 },
          { type: 'int', instruction: :set_var, name: :n },
          { type: 'int', instruction: :push_arg, index: 1 },
          { type: 'int', instruction: :set_var, name: :result },
          { type: 'int', instruction: :push_var, name: :n },
          { type: 'int', instruction: :push_int, value: 0 },
          { type: 'bool', instruction: :call, name: :==, arg_count: 2 },
          {
            type: 'int',
            instruction: :if,
            if_true: [
              {
                type: 'int',
                instruction: :push_var,
                name: :result
              }
            ],
            if_false: [
              { type: 'int', instruction: :push_var, name: :n },
              { type: 'int', instruction: :push_int, value: 1 },
              { type: 'int', instruction: :call, name: :-, arg_count: 2 },
              { type: 'int', instruction: :push_var, name: :result },
              { type: 'int', instruction: :push_var, name: :n },
              { type: 'int', instruction: :call, name: :*, arg_count: 2 },
              { type: 'int', instruction: :call, name: :fact, arg_count: 2 }
            ]
          }
        ]
      },

      { type: 'int', instruction: :push_int, value: 10 },
      { type: 'int', instruction: :push_int, value: 1 },
      { type: 'int', instruction: :call, name: :fact, arg_count: 2 },
      { type: 'int', instruction: :call, name: :puts, arg_count: 1 },
    ]
  end
end
