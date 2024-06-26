require_relative "spec_helper"

describe Compiler do
  def compile(code)
    Compiler.new(code).compile.map(&:to_h)
  end

  it "compiles integers" do
    expect(compile("1")).must_equal_with_diff [{ type: "int", instruction: :push_int, value: 1 }]
  end

  it "compiles strings" do
    expect(compile('"foo"')).must_equal_with_diff [{ type: "str", instruction: :push_str, value: "foo" }]
  end

  it "compiles booleans" do
    expect(compile("true")).must_equal_with_diff [{ type: "bool", instruction: :push_true }]
    expect(compile("false")).must_equal_with_diff [{ type: "bool", instruction: :push_false }]
  end

  it "compiles classes" do
    code = <<~CODE
      class Foo
        def bar
          @bar = 1
        end
      end
      Foo.new.bar
    CODE
    expect(compile(code)).must_equal_with_diff [
                             {
                               type: "(class Foo @bar:int)",
                               instruction: :class,
                               name: :Foo,
                               body: [
                                 {
                                   type: "([(object Foo)] -> int)",
                                   instruction: :def,
                                   name: :bar,
                                   params: [],
                                   body: [
                                     { type: "int", instruction: :push_int, value: 1 },
                                     { type: "int", instruction: :set_ivar, name: :@bar, nillable: false }
                                   ]
                                 }
                               ]
                             },
                             { type: "(class Foo @bar:int)", instruction: :push_const, name: :Foo },
                             {
                               type: "([(class Foo @bar:int)] -> (object Foo))",
                               instruction: :call,
                               name: :new,
                               arg_count: 0
                             },
                             { type: "([(object Foo)] -> int)", instruction: :call, name: :bar, arg_count: 0 }
                           ]
  end

  it "raises an error if two objects cannot unify" do
    code = <<~CODE
      class Foo; end
      class Bar; end

      def same?(a); nil; end
      same?(Foo.new)
      same?(Bar.new)
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal(
      "([(object main), (object Foo)] -> nil) cannot unify with " \
        "([(object main), (object Bar)] -> a) in call to same? on line 6"
    )
  end

  it "compiles variables set and get" do
    expect(compile("a = 1; a")).must_equal_with_diff [
                             { type: "int", instruction: :push_int, value: 1 },
                             { type: "int", instruction: :set_var, name: :a, nillable: false },
                             { type: "int", instruction: :push_var, name: :a }
                           ]
  end

  it "can set a variable more than once" do
    expect(compile("a = 1; a = 2")).must_equal_with_diff [
                             { type: "int", instruction: :push_int, value: 1 },
                             { type: "int", instruction: :set_var, name: :a, nillable: false },
                             { type: "int", instruction: :push_int, value: 2 },
                             { type: "int", instruction: :set_var, name: :a, nillable: false },
                             { type: "int", instruction: :push_var, name: :a }
                           ]
  end

  it "raises an error if the variable type changes" do
    e = expect { compile('a = 1; a = "foo"') }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal "the variable a has type int already; you cannot change it to type str"
  end

  it "compiles arrays" do
    code = <<~CODE
      a = [1, 2, 3]
      a.first

      b = []
      b << "foo"
      b << "bar"

      c = [4, 5, 6]
      d = [c, c]
    CODE
    expect(compile(code)).must_equal_with_diff [
                             { type: "int", instruction: :push_int, value: 1 },
                             { type: "int", instruction: :push_int, value: 2 },
                             { type: "int", instruction: :push_int, value: 3 },
                             { type: "(int array)", instruction: :push_array, size: 3 },
                             { type: "(int array)", instruction: :set_var, name: :a, nillable: false },
                             { type: "(int array)", instruction: :push_var, name: :a },
                             { type: "([(int array)] -> int)", instruction: :call, name: :first, arg_count: 0 },
                             { type: "nil", instruction: :pop },
                             { type: "(str array)", instruction: :push_array, size: 0 },
                             { type: "(str array)", instruction: :set_var, name: :b, nillable: false },
                             { type: "(str array)", instruction: :push_var, name: :b },
                             { type: "str", instruction: :push_str, value: "foo" },
                             {
                               type: "([(str array), str] -> (str array))",
                               instruction: :call,
                               name: :<<,
                               arg_count: 1
                             },
                             { type: "nil", instruction: :pop },
                             { type: "(str array)", instruction: :push_var, name: :b },
                             { type: "str", instruction: :push_str, value: "bar" },
                             {
                               type: "([(str array), str] -> (str array))",
                               instruction: :call,
                               name: :<<,
                               arg_count: 1
                             },
                             { type: "nil", instruction: :pop },
                             { type: "int", instruction: :push_int, value: 4 },
                             { type: "int", instruction: :push_int, value: 5 },
                             { type: "int", instruction: :push_int, value: 6 },
                             { type: "(int array)", instruction: :push_array, size: 3 },
                             { type: "(int array)", instruction: :set_var, name: :c, nillable: false },
                             { type: "(int array)", instruction: :push_var, name: :c },
                             { type: "(int array)", instruction: :push_var, name: :c },
                             { type: "((int array) array)", instruction: :push_array, size: 2 },
                             { type: "((int array) array)", instruction: :set_var, name: :d, nillable: false },
                             { type: "((int array) array)", instruction: :push_var, name: :d }
                           ]
  end

  it "raises an error if the array elements do not have the same type" do
    code = <<~CODE
      [1, "foo"]
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal "the array contains type int but you are trying to push type str"

    code = <<~CODE
      a = [1]
      a << "foo"
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(
      e.message
    ).must_equal "([(a array), a] -> (a array)) cannot unify with ([(int array), str] -> b) in call to << on line 2"

    code = <<~CODE
      [
        [1, 2, 3],
        ['foo', 'bar', 'baz']
      ]
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal "the array contains type (int array) but you are trying to push type (str array)"
  end

  it "compiles method definitions" do
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
                               type: "([(object main)] -> str)",
                               instruction: :def,
                               name: :foo,
                               params: [],
                               body: [{ type: "str", instruction: :push_str, value: "foo" }]
                             },
                             {
                               type: "([(object main)] -> int)",
                               instruction: :def,
                               name: :bar,
                               params: [],
                               body: [{ type: "int", instruction: :push_int, value: 1 }]
                             },
                             { type: "(object main)", instruction: :push_self },
                             { type: "([(object main)] -> str)", instruction: :call, name: :foo, arg_count: 0 },
                             { type: "nil", instruction: :pop },
                             { type: "(object main)", instruction: :push_self },
                             { type: "([(object main)] -> int)", instruction: :call, name: :bar, arg_count: 0 }
                           ]
  end

  it "compiles method definitions with arguments" do
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
                               type: "([(object main), int] -> int)",
                               instruction: :def,
                               name: :bar,
                               params: [:a],
                               body: [
                                 { type: "int", instruction: :push_arg, index: 0 },
                                 { type: "int", instruction: :set_var, name: :a, nillable: false },
                                 { type: "int", instruction: :push_var, name: :a }
                               ]
                             },
                             {
                               type: "([(object main), str, int] -> str)",
                               instruction: :def,
                               name: :foo,
                               params: %i[a b],
                               body: [
                                 { type: "str", instruction: :push_arg, index: 0 },
                                 { type: "str", instruction: :set_var, name: :a, nillable: false },
                                 { type: "int", instruction: :push_arg, index: 1 },
                                 { type: "int", instruction: :set_var, name: :b, nillable: false },
                                 { type: "str", instruction: :push_var, name: :a }
                               ]
                             },
                             { type: "(object main)", instruction: :push_self },
                             { type: "str", instruction: :push_str, value: "foo" },
                             { type: "int", instruction: :push_int, value: 1 },
                             {
                               type: "([(object main), str, int] -> str)",
                               instruction: :call,
                               name: :foo,
                               arg_count: 2
                             },
                             { type: "nil", instruction: :pop },
                             { type: "(object main)", instruction: :push_self },
                             { type: "int", instruction: :push_int, value: 2 },
                             { type: "([(object main), int] -> int)", instruction: :call, name: :bar, arg_count: 1 }
                           ]
  end

  it "raises an error if the method arg type is unknown" do
    code = <<~CODE
      def foo(a)
        a
      end
    CODE
    e = expect { compile(code) }.must_raise TypeError
    expect(e.message).must_match(/Not enough information to infer type of/)
  end

  # NOTE: we don't support monomorphization (yet!)
  it "raises an error if the method arg has more than one type" do
    code = <<~CODE
      def foo(x)
        x
      end

      foo(1)

      foo('bar')
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(
      e.message
    ).must_equal "([(object main), int] -> int) cannot unify with ([(object main), str] -> a) in call to foo on line 7"
  end

  it "raises an error if the arg count of method and call do not match" do
    code = <<~CODE
      def foo(x)
        x
      end

      foo(1, 2)
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(
      e.message
    ).must_equal "([(object main), a] -> a) cannot unify with ([(object main), int, int] -> b) in call to foo on line 5"
  end

  it "compiles operator expressions" do
    code = <<~CODE
      1 + 2
      3 == 4
    CODE
    expect(compile(code)).must_equal_with_diff [
                             { type: "int", instruction: :push_int, value: 1 },
                             { type: "int", instruction: :push_int, value: 2 },
                             { type: "([int, int] -> int)", instruction: :call, name: :+, arg_count: 1 },
                             { type: "nil", instruction: :pop },
                             { type: "int", instruction: :push_int, value: 3 },
                             { type: "int", instruction: :push_int, value: 4 },
                             { type: "([int, int] -> bool)", instruction: :call, name: :==, arg_count: 1 }
                           ]
  end

  it "compiles if expressions" do
    code = <<~CODE
      if 1
        2
      else
        3
      end
    CODE
    expect(compile(code)).must_equal_with_diff [
                             { type: "int", instruction: :push_int, value: 1 },
                             {
                               type: "int",
                               instruction: :if,
                               if_true: [{ type: "int", instruction: :push_int, value: 2 }],
                               if_false: [{ type: "int", instruction: :push_int, value: 3 }]
                             }
                           ]
  end

  it "raises an error if both branches of an if expression do not have the same type" do
    code = <<~CODE
      if 1
        2
      else
        'foo'
      end
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal "one branch of `if` has type int and the other has type str"
  end

  it "compiles calls to puts for both int and str" do
    expect(compile("puts(1)")).must_equal_with_diff [
                             { type: "(object main)", instruction: :push_self },
                             { type: "int", instruction: :push_int, value: 1 },
                             { type: "([(object main), int] -> int)", instruction: :call, name: :puts, arg_count: 1 }
                           ]
    expect(compile('puts("foo")')).must_equal_with_diff [
                             { type: "(object main)", instruction: :push_self },
                             { type: "str", instruction: :push_str, value: "foo" },
                             { type: "([(object main), str] -> int)", instruction: :call, name: :puts, arg_count: 1 }
                           ]
  end

  it "raises an error if a variable is changed to nil" do
    e = expect { compile('a = "foo"; a = nil') }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal "the variable a has type str already; you cannot change it to type nil"

    e = expect { compile('a = ["foo"]; a << nil') }.must_raise Compiler::TypeChecker::TypeClash
    expect(
      e.message
    ).must_equal "([(a array), a] -> (a array)) cannot unify with ([(str array), nil] -> b) in call to << on line 1"
  end

  it 'allows assignment of nil when the variable is named with the suffix "_or_nil"' do
    code = <<~CODE
      a_or_nil = "foo"
      a_or_nil = nil
    CODE
    expect(compile(code)).must_equal_with_diff [
                             { type: "str", instruction: :push_str, value: "foo" },
                             { type: "(nillable str)", instruction: :set_var, name: :a_or_nil, nillable: true },
                             { type: "nil", instruction: :push_nil },
                             { type: "(nillable str)", instruction: :set_var, name: :a_or_nil, nillable: true },
                             { type: "(nillable str)", instruction: :push_var, name: :a_or_nil }
                           ]

    code = <<~CODE
      a_or_nil = nil
      a_or_nil = "foo"
    CODE
    expect(compile(code)).must_equal_with_diff [
                             { type: "nil", instruction: :push_nil },
                             { type: "(nillable str)", instruction: :set_var, name: :a_or_nil, nillable: true },
                             { type: "str", instruction: :push_str, value: "foo" },
                             { type: "(nillable str)", instruction: :set_var, name: :a_or_nil, nillable: true },
                             { type: "(nillable str)", instruction: :push_var, name: :a_or_nil }
                           ]
  end

  it 'allows assignment of nil when the variable is marked with the special "nillable" comment' do
    code = <<~CODE
      a = "foo" # a:nillable
      a = nil
    CODE
    expect(compile(code)).must_equal_with_diff [
                             { type: "str", instruction: :push_str, value: "foo" },
                             { type: "(nillable str)", instruction: :set_var, name: :a, nillable: true },
                             { type: "nil", instruction: :push_nil },
                             { type: "(nillable str)", instruction: :set_var, name: :a, nillable: false },
                             { type: "(nillable str)", instruction: :push_var, name: :a }
                           ]
  end

  it "allows assignment of nil when the variable is first set to nil and changed to something else" do
    code = <<~CODE
      a = nil
      a = "foo"
    CODE
    expect(compile(code)).must_equal_with_diff [
                             { type: "nil", instruction: :push_nil },
                             { type: "(nillable str)", instruction: :set_var, name: :a, nillable: false },
                             { type: "str", instruction: :push_str, value: "foo" },
                             { type: "(nillable str)", instruction: :set_var, name: :a, nillable: false },
                             { type: "(nillable str)", instruction: :push_var, name: :a }
                           ]
  end

  it "raises an error if a method returns nil and is assigned to a variable" do
    code = <<~CODE
      def foo
        nil
      end

      a = foo
      a = "bar"
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal "the variable a has type nil already; you cannot change it to type str"
  end

  it "compiles examples/fib.rb" do
    code = File.read(File.expand_path("../examples/fib.rb", __dir__))
    expect(compile(code)).must_equal_with_diff [
                             {
                               type: "([(object main), int] -> int)",
                               instruction: :def,
                               name: :fib,
                               params: [:n],
                               body: [
                                 { type: "int", instruction: :push_arg, index: 0 },
                                 { type: "int", instruction: :set_var, name: :n, nillable: false },
                                 { type: "int", instruction: :push_var, name: :n },
                                 { type: "int", instruction: :push_int, value: 0 },
                                 { type: "([int, int] -> bool)", instruction: :call, name: :==, arg_count: 1 },
                                 {
                                   type: "int",
                                   instruction: :if,
                                   if_true: [{ type: "int", instruction: :push_int, value: 0 }],
                                   if_false: [
                                     { type: "int", instruction: :push_var, name: :n },
                                     { type: "int", instruction: :push_int, value: 1 },
                                     { type: "([int, int] -> bool)", instruction: :call, name: :==, arg_count: 1 },
                                     {
                                       type: "int",
                                       instruction: :if,
                                       if_true: [{ type: "int", instruction: :push_int, value: 1 }],
                                       if_false: [
                                         { type: "(object main)", instruction: :push_self },
                                         { type: "int", instruction: :push_var, name: :n },
                                         { type: "int", instruction: :push_int, value: 1 },
                                         { type: "([int, int] -> int)", instruction: :call, name: :-, arg_count: 1 },
                                         {
                                           type: "([(object main), int] -> int)",
                                           instruction: :call,
                                           name: :fib,
                                           arg_count: 1
                                         },
                                         { type: "(object main)", instruction: :push_self },
                                         { type: "int", instruction: :push_var, name: :n },
                                         { type: "int", instruction: :push_int, value: 2 },
                                         { type: "([int, int] -> int)", instruction: :call, name: :-, arg_count: 1 },
                                         {
                                           type: "([(object main), int] -> int)",
                                           instruction: :call,
                                           name: :fib,
                                           arg_count: 1
                                         },
                                         { type: "([int, int] -> int)", instruction: :call, name: :+, arg_count: 1 }
                                       ]
                                     }
                                   ]
                                 }
                               ]
                             },
                             { type: "(object main)", instruction: :push_self },
                             { type: "(object main)", instruction: :push_self },
                             { type: "int", instruction: :push_int, value: 10 },
                             { type: "([(object main), int] -> int)", instruction: :call, name: :fib, arg_count: 1 },
                             { type: "([(object main), int] -> int)", instruction: :call, name: :puts, arg_count: 1 }
                           ]
  end

  it "compiles examples/fact.rb" do
    code = File.read(File.expand_path("../examples/fact.rb", __dir__))
    expect(compile(code)).must_equal_with_diff [
                             {
                               type: "([(object main), int, int] -> int)",
                               instruction: :def,
                               name: :fact,
                               params: %i[n result],
                               body: [
                                 { type: "int", instruction: :push_arg, index: 0 },
                                 { type: "int", instruction: :set_var, name: :n, nillable: false },
                                 { type: "int", instruction: :push_arg, index: 1 },
                                 { type: "int", instruction: :set_var, name: :result, nillable: false },
                                 { type: "int", instruction: :push_var, name: :n },
                                 { type: "int", instruction: :push_int, value: 0 },
                                 { type: "([int, int] -> bool)", instruction: :call, name: :==, arg_count: 1 },
                                 {
                                   type: "int",
                                   instruction: :if,
                                   if_true: [{ type: "int", instruction: :push_var, name: :result }],
                                   if_false: [
                                     { type: "(object main)", instruction: :push_self },
                                     { type: "int", instruction: :push_var, name: :n },
                                     { type: "int", instruction: :push_int, value: 1 },
                                     { type: "([int, int] -> int)", instruction: :call, name: :-, arg_count: 1 },
                                     { type: "int", instruction: :push_var, name: :result },
                                     { type: "int", instruction: :push_var, name: :n },
                                     { type: "([int, int] -> int)", instruction: :call, name: :*, arg_count: 1 },
                                     {
                                       type: "([(object main), int, int] -> int)",
                                       instruction: :call,
                                       name: :fact,
                                       arg_count: 2
                                     }
                                   ]
                                 }
                               ]
                             },
                             { type: "(object main)", instruction: :push_self },
                             { type: "(object main)", instruction: :push_self },
                             { type: "int", instruction: :push_int, value: 10 },
                             { type: "int", instruction: :push_int, value: 1 },
                             {
                               type: "([(object main), int, int] -> int)",
                               instruction: :call,
                               name: :fact,
                               arg_count: 2
                             },
                             { type: "([(object main), int] -> int)", instruction: :call, name: :puts, arg_count: 1 }
                           ]
  end
end
