require_relative 'spec_helper'

describe Compiler do
  def compile(code)
    Compiler.new(code).compile.map(&:to_h)
  end

  it 'compiles integers' do
    expect(compile('1')).must_equal_with_diff [{ type: 'Integer', instruction: :push_int, value: 1 }]
  end

  it 'compiles strings' do
    expect(compile('"foo"')).must_equal_with_diff [{ type: 'String', instruction: :push_str, value: 'foo' }]
  end

  it 'compiles booleans' do
    expect(compile('true')).must_equal_with_diff [{ type: 'Boolean', instruction: :push_true }]
    expect(compile('false')).must_equal_with_diff [{ type: 'Boolean', instruction: :push_false }]
  end

  it 'compiles variables set and get' do
    expect(compile('a = 1; a')).must_equal_with_diff [
                             { type: 'Integer', instruction: :push_int, value: 1 },
                             { type: 'Integer', instruction: :set_var, name: :a },
                             { type: 'Integer', instruction: :push_var, name: :a },
                           ]
    expect(compile('a = 1; b = a; b')).must_equal_with_diff [
                             { type: 'Integer', instruction: :push_int, value: 1 },
                             { type: 'Integer', instruction: :set_var, name: :a },
                             { type: 'Integer', instruction: :push_var, name: :a },
                             { type: 'Integer', instruction: :set_var, name: :b },
                             { type: 'Integer', instruction: :push_var, name: :b },
                           ]
  end

  it 'can set a variable more than once' do
    expect(compile('a = 1; a = 2')).must_equal_with_diff [
                             { type: 'Integer', instruction: :push_int, value: 1 },
                             { type: 'Integer', instruction: :set_var, name: :a },
                             { type: 'Integer', instruction: :push_int, value: 2 },
                             { type: 'Integer', instruction: :set_var, name: :a },
                             { type: 'Integer', instruction: :push_var, name: :a },
                           ]
  end

  it 'raises error for variable type changes' do
    e = expect { compile('a = 1; a = "foo"') }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal 'the variable `a` has type Integer already; you cannot change it to type String'
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
                               type: 'Object#foo() => String',
                               instruction: :def,
                               name: :foo,
                               params: [],
                               body: [{ type: 'String', instruction: :push_str, value: 'foo' }],
                             },
                             {
                               type: 'Object#bar() => Integer',
                               instruction: :def,
                               name: :bar,
                               params: [],
                               body: [{ type: 'Integer', instruction: :push_int, value: 1 }],
                             },
                             { type: 'Object', instruction: :push_self },
                             { type: 'Object#foo() => String', instruction: :call, name: :foo, arg_count: 0 },
                             { type: 'NilClass', instruction: :pop },
                             { type: 'Object', instruction: :push_self },
                             { type: 'Object#bar() => Integer', instruction: :call, name: :bar, arg_count: 0 },
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

      def baz(a)
        temp1 = a
        temp2 = temp1
        bar(temp2)
      end

      foo('foo', 1)

      bar(2)

      baz(3)
    CODE
    expect(compile(code)).must_equal_with_diff [
                             {
                               type: 'Object#bar(Integer) => Integer',
                               instruction: :def,
                               name: :bar,
                               params: [:a],
                               body: [
                                 { type: 'Integer', instruction: :push_arg, index: 0 },
                                 { type: 'Integer', instruction: :set_var, name: :a },
                                 { type: 'Integer', instruction: :push_var, name: :a },
                               ],
                             },
                             {
                               type: 'Object#foo(String, Integer) => String',
                               instruction: :def,
                               name: :foo,
                               params: %i[a b],
                               body: [
                                 { type: 'String', instruction: :push_arg, index: 0 },
                                 { type: 'String', instruction: :set_var, name: :a },
                                 { type: 'Integer', instruction: :push_arg, index: 1 },
                                 { type: 'Integer', instruction: :set_var, name: :b },
                                 { type: 'String', instruction: :push_var, name: :a },
                               ],
                             },
                             {
                               type: 'Object#baz(Integer) => Integer',
                               instruction: :def,
                               name: :baz,
                               params: [:a],
                               body: [
                                 { type: 'Integer', instruction: :push_arg, index: 0 },
                                 { type: 'Integer', instruction: :set_var, name: :a },
                                 { type: 'Integer', instruction: :push_var, name: :a },
                                 { type: 'Integer', instruction: :set_var, name: :temp1 },
                                 { type: 'Integer', instruction: :push_var, name: :temp1 },
                                 { type: 'Integer', instruction: :set_var, name: :temp2 },
                                 { type: 'Object', instruction: :push_self },
                                 { type: 'Integer', instruction: :push_var, name: :temp2 },
                                 {
                                   type: 'Object#bar(Integer) => Integer',
                                   instruction: :call,
                                   name: :bar,
                                   arg_count: 1,
                                 },
                               ],
                             },
                             { type: 'Object', instruction: :push_self },
                             { type: 'String', instruction: :push_str, value: 'foo' },
                             { type: 'Integer', instruction: :push_int, value: 1 },
                             {
                               type: 'Object#foo(String, Integer) => String',
                               instruction: :call,
                               name: :foo,
                               arg_count: 2,
                             },
                             { type: 'NilClass', instruction: :pop },
                             { type: 'Object', instruction: :push_self },
                             { type: 'Integer', instruction: :push_int, value: 2 },
                             { type: 'Object#bar(Integer) => Integer', instruction: :call, name: :bar, arg_count: 1 },
                             { type: 'NilClass', instruction: :pop },
                             { type: 'Object', instruction: :push_self },
                             { type: 'Integer', instruction: :push_int, value: 3 },
                             { type: 'Object#baz(Integer) => Integer', instruction: :call, name: :baz, arg_count: 1 },
                           ]
  end

  it 'raises error for unknown method arg type' do
    code = <<~CODE
       def foo(a)
         a
       end
     CODE
    e = expect { compile(code) }.must_raise TypeError
    expect(e.message).must_equal("Not enough information to infer type of variable 'a'")
  end

  # NOTE: we don't support monomorphization (yet!)
  it 'raises error for method arg with multiple types' do
    code = <<~CODE
       def foo(x)
         x
       end

       foo(1)

       foo('bar')
     CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal 'Object#foo argument 1 has type Integer, but you passed String'
  end

  it 'raises error for method/call arg count mismatch' do
    code = <<~CODE
      def foo(x)
        x
      end

      foo(1, 2)
    CODE
    e = expect { compile(code) }.must_raise ArgumentError
    expect(e.message).must_equal 'method foo expects 1 argument, got 2'
  end

  it 'compiles operator expressions' do
    code = <<~CODE
      def num(a) = a
      1 + 2
      3 == 4
      num(100) * 2
    CODE
    expect(compile(code)).must_equal_with_diff [
                             {
                               type: 'Object#num(Integer) => Integer',
                               instruction: :def,
                               name: :num,
                               params: [:a],
                               body: [
                                 { type: 'Integer', instruction: :push_arg, index: 0 },
                                 { type: 'Integer', instruction: :set_var, name: :a },
                                 { type: 'Integer', instruction: :push_var, name: :a },
                               ],
                             },
                             { type: 'Integer', instruction: :push_int, value: 1 },
                             { type: 'Integer', instruction: :push_int, value: 2 },
                             { type: 'Integer#+(Integer) => Integer', instruction: :call, name: :+, arg_count: 1 },
                             { type: 'NilClass', instruction: :pop },
                             { type: 'Integer', instruction: :push_int, value: 3 },
                             { type: 'Integer', instruction: :push_int, value: 4 },
                             { type: 'Integer#==(Integer) => Boolean', instruction: :call, name: :==, arg_count: 1 },
                             { type: 'NilClass', instruction: :pop },
                             { type: 'Object', instruction: :push_self },
                             { type: 'Integer', instruction: :push_int, value: 100 },
                             { type: 'Object#num(Integer) => Integer', instruction: :call, name: :num, arg_count: 1 },
                             { type: 'Integer', instruction: :push_int, value: 2 },
                             { type: 'Integer#*(Integer) => Integer', instruction: :call, name: :*, arg_count: 1 },
                           ]
  end

  it 'compiles classes' do
    code = <<~CODE
      class Foo
        def set_bar(x)
          @bar = x
        end

        def bar = @bar
      end
      foo = Foo.new
      foo.set_bar(10)
      foo.bar
    CODE
    expect(compile(code)).must_equal_with_diff [
                             {
                               type: 'Foo',
                               instruction: :class,
                               name: :Foo,
                               body: [
                                 {
                                   type: 'Foo#set_bar(Integer) => Integer',
                                   instruction: :def,
                                   name: :set_bar,
                                   params: [:x],
                                   body: [
                                     { type: 'Integer', instruction: :push_arg, index: 0 },
                                     { type: 'Integer', instruction: :set_var, name: :x },
                                     { type: 'Integer', instruction: :push_var, name: :x },
                                     { type: 'Integer', instruction: :set_ivar, name: :@bar },
                                   ],
                                 },
                                 {
                                   type: 'Foo#bar() => Integer',
                                   instruction: :def,
                                   name: :bar,
                                   params: [],
                                   body: [{ type: 'Integer', instruction: :push_ivar, name: :@bar }],
                                 },
                               ],
                             },
                             { type: 'Foo', instruction: :push_const, name: :Foo },
                             { type: 'Foo#new() => Foo', instruction: :call, name: :new, arg_count: 0 },
                             { type: 'Foo', instruction: :set_var, name: :foo },
                             { type: 'Foo', instruction: :push_var, name: :foo },
                             { type: 'Integer', instruction: :push_int, value: 10 },
                             {
                               type: 'Foo#set_bar(Integer) => Integer',
                               instruction: :call,
                               name: :set_bar,
                               arg_count: 1,
                             },
                             { type: 'NilClass', instruction: :pop },
                             { type: 'Foo', instruction: :push_var, name: :foo },
                             { type: 'Foo#bar() => Integer', instruction: :call, name: :bar, arg_count: 0 },
                           ]
  end

  it 'raises an error if two objects cannot unify' do
    code = <<~CODE
      class Foo; end
      class Bar; end

      def same?(a); nil; end
      same?(Foo.new)
      same?(Bar.new)
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal('Object#same? argument 1 has type Foo, but you passed Bar')
  end

  it 'compiles method definitions with type annotations' do
    code = <<~CODE
      def add(a, b) # a:Integer, b:Integer
        a + b
      end

      def greet(name) # name:String
        "Hello " + name
      end

      add(5, 10)
      greet("World")
    CODE
    expect(compile(code)).must_equal_with_diff [
                             {
                               type: 'Object#add(Integer, Integer) => Integer',
                               instruction: :def,
                               name: :add,
                               params: %i[a b],
                               body: [
                                 { type: 'Integer', instruction: :push_arg, index: 0 },
                                 { type: 'Integer', instruction: :set_var, name: :a },
                                 { type: 'Integer', instruction: :push_arg, index: 1 },
                                 { type: 'Integer', instruction: :set_var, name: :b },
                                 { type: 'Integer', instruction: :push_var, name: :a },
                                 { type: 'Integer', instruction: :push_var, name: :b },
                                 { type: 'Integer#+(Integer) => Integer', instruction: :call, name: :+, arg_count: 1 },
                               ],
                             },
                             {
                               type: 'Object#greet(String) => String',
                               instruction: :def,
                               name: :greet,
                               params: [:name],
                               body: [
                                 { type: 'String', instruction: :push_arg, index: 0 },
                                 { type: 'String', instruction: :set_var, name: :name },
                                 { type: 'String', instruction: :push_str, value: 'Hello ' },
                                 { type: 'String', instruction: :push_var, name: :name },
                                 { type: 'String#+(String) => String', instruction: :call, name: :+, arg_count: 1 },
                               ],
                             },
                             { type: 'Object', instruction: :push_self },
                             { type: 'Integer', instruction: :push_int, value: 5 },
                             { type: 'Integer', instruction: :push_int, value: 10 },
                             {
                               type: 'Object#add(Integer, Integer) => Integer',
                               instruction: :call,
                               name: :add,
                               arg_count: 2,
                             },
                             { type: 'NilClass', instruction: :pop },
                             { type: 'Object', instruction: :push_self },
                             { type: 'String', instruction: :push_str, value: 'World' },
                             { type: 'Object#greet(String) => String', instruction: :call, name: :greet, arg_count: 1 },
                           ]
  end

  it 'raises error for type annotation with wrong type' do
    code = <<~CODE
      def add(a, b) # a:Integer, b:Integer
        a + b
      end

      add("hello", 5)
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal 'Object#add argument 1 has type Integer, but you passed String'
  end

  it 'compiles method with Option type annotations' do
    code = <<~CODE
      def maybe_greet(name) # name:Option[String]
        if name
          puts "Hello, " + name.value
        else
          0
        end
      end

      maybe_greet(nil)
      maybe_greet("Tim")
    CODE
    expect(compile(code)).must_equal_with_diff [
                             {
                               type: 'Object#maybe_greet(Option[String]) => Integer',
                               instruction: :def,
                               name: :maybe_greet,
                               params: [:name],
                               body: [
                                 { type: 'Option[String]', instruction: :push_arg, index: 0 },
                                 { type: 'Option[String]', instruction: :set_var, name: :name },
                                 { type: 'Option[String]', instruction: :push_var, name: :name },
                                 {
                                   type: 'Integer',
                                   instruction: :if,
                                   if_true: [
                                     { type: 'Object', instruction: :push_self },
                                     { type: 'String', instruction: :push_str, value: 'Hello, ' },
                                     { type: 'Option[String]', instruction: :push_var, name: :name },
                                     {
                                       type: 'Option[String]#value() => String',
                                       instruction: :call,
                                       name: :value,
                                       arg_count: 0,
                                     },
                                     { type: 'String#+(String) => String', instruction: :call, name: :+, arg_count: 1 },
                                     {
                                       type: 'Object#puts(String) => Integer',
                                       instruction: :call,
                                       name: :puts,
                                       arg_count: 1,
                                     },
                                   ],
                                   if_false: [{ type: 'Integer', instruction: :push_int, value: 0 }],
                                 },
                               ],
                             },
                             { type: 'Object', instruction: :push_self },
                             { type: 'NilClass', instruction: :push_nil },
                             {
                               type: 'Object#maybe_greet(Option[String]) => Integer',
                               instruction: :call,
                               name: :maybe_greet,
                               arg_count: 1,
                             },
                             { type: 'NilClass', instruction: :pop },
                             { type: 'Object', instruction: :push_self },
                             { type: 'String', instruction: :push_str, value: 'Tim' },
                             {
                               type: 'Object#maybe_greet(Option[String]) => Integer',
                               instruction: :call,
                               name: :maybe_greet,
                               arg_count: 1,
                             },
                           ]
  end

  it 'raises for invalid type passed to Option parameter' do
    code = <<~CODE
      def process_optional(value) # value:Option[String]
        value
      end

      process_optional(42)
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal 'Object#process_optional argument 1 has type Option[String], but you passed Integer'
  end

  it 'compiles arrays' do
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
                             { type: 'Integer', instruction: :push_int, value: 1 },
                             { type: 'Integer', instruction: :push_int, value: 2 },
                             { type: 'Integer', instruction: :push_int, value: 3 },
                             { type: 'Array[Integer]', instruction: :push_array, size: 3 },
                             { type: 'Array[Integer]', instruction: :set_var, name: :a },
                             { type: 'Array[Integer]', instruction: :push_var, name: :a },
                             {
                               type: 'Array[Integer]#first() => Integer',
                               instruction: :call,
                               name: :first,
                               arg_count: 0,
                             },
                             { type: 'NilClass', instruction: :pop },
                             { type: 'Array[String]', instruction: :push_array, size: 0 },
                             { type: 'Array[String]', instruction: :set_var, name: :b },
                             { type: 'Array[String]', instruction: :push_var, name: :b },
                             { type: 'String', instruction: :push_str, value: 'foo' },
                             {
                               type: 'Array[String]#<<(String) => Array[String]',
                               instruction: :call,
                               name: :<<,
                               arg_count: 1,
                             },
                             { type: 'NilClass', instruction: :pop },
                             { type: 'Array[String]', instruction: :push_var, name: :b },
                             { type: 'String', instruction: :push_str, value: 'bar' },
                             {
                               type: 'Array[String]#<<(String) => Array[String]',
                               instruction: :call,
                               name: :<<,
                               arg_count: 1,
                             },
                             { type: 'NilClass', instruction: :pop },
                             { type: 'Integer', instruction: :push_int, value: 4 },
                             { type: 'Integer', instruction: :push_int, value: 5 },
                             { type: 'Integer', instruction: :push_int, value: 6 },
                             { type: 'Array[Integer]', instruction: :push_array, size: 3 },
                             { type: 'Array[Integer]', instruction: :set_var, name: :c },
                             { type: 'Array[Integer]', instruction: :push_var, name: :c },
                             { type: 'Array[Integer]', instruction: :push_var, name: :c },
                             { type: 'Array[Array[Integer]]', instruction: :push_array, size: 2 },
                             { type: 'Array[Array[Integer]]', instruction: :set_var, name: :d },
                             { type: 'Array[Array[Integer]]', instruction: :push_var, name: :d },
                           ]
  end

  it 'raises error for mixed array element types' do
    code = <<~CODE
      [1, "foo"]
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal 'the array contains type Integer but you are trying to push type String'

    code = <<~CODE
      a = [1]
      a << "foo"
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal 'Array[Integer]#<< argument 1 has type Integer, but you passed String'

    code = <<~CODE
      [
        [1, 2, 3],
        ['foo', 'bar', 'baz']
      ]
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal 'the array contains type Array[Integer] but you are trying to push type Array[String]'
  end

  it 'compiles if expressions' do
    code = <<~CODE
      if true
        2
      else
        3
      end
    CODE
    expect(compile(code)).must_equal_with_diff [
                             { type: 'Boolean', instruction: :push_true },
                             {
                               type: 'Integer',
                               instruction: :if,
                               if_true: [{ type: 'Integer', instruction: :push_int, value: 2 }],
                               if_false: [{ type: 'Integer', instruction: :push_int, value: 3 }],
                             },
                           ]
  end

  it 'raises error for if branches with different types' do
    code = <<~CODE
      if true
        2
      else
        'foo'
      end
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal 'one branch of `if` has type Integer and the other has type String'
  end

  it 'raises error for if without else clause' do
    code = <<~CODE
       if true
         42
       end
     CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal 'one branch of `if` has type Integer and the other has type NilClass'
  end

  it 'raises error for non-boolean if condition' do
    code = <<~CODE
       if 42
         1
       else
         2
       end
     CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal '`if` condition must be Boolean, got Integer'
  end

  it 'compiles while expressions' do
    code = <<~CODE
      i = 0
      while i < 5
        i = i + 1
      end
    CODE
    expect(compile(code)).must_equal_with_diff [
                             { type: 'Integer', instruction: :push_int, value: 0 },
                             { type: 'Integer', instruction: :set_var, name: :i },
                             {
                               type: 'NilClass',
                               instruction: :while,
                               condition: [
                                 { type: 'Integer', instruction: :push_var, name: :i },
                                 { type: 'Integer', instruction: :push_int, value: 5 },
                                 { type: 'Integer#<(Integer) => Boolean', instruction: :call, name: :<, arg_count: 1 },
                               ],
                               body: [
                                 { type: 'Integer', instruction: :push_var, name: :i },
                                 { type: 'Integer', instruction: :push_int, value: 1 },
                                 { type: 'Integer#+(Integer) => Integer', instruction: :call, name: :+, arg_count: 1 },
                                 { type: 'Integer', instruction: :set_var, name: :i },
                               ],
                             },
                           ]
  end

  it 'raises error for non-boolean while condition' do
    code = <<~CODE
      while "foo"
        1
      end
    CODE
    e = expect { compile(code) }.must_raise Compiler::TypeChecker::TypeClash
    expect(e.message).must_equal '`while` condition must be Boolean, got String'
  end

  # it 'compiles examples/fib.rb' do
  #   code = File.read(File.expand_path('../examples/fib.rb', __dir__))
  #   expect(compile(code)).must_equal_with_diff [
  #                            {
  #                              type: '([(object main), int] -> int)',
  #                              instruction: :def,
  #                              name: :fib,
  #                              params: [:n],
  #                              body: [
  #                                { type: 'Integer', instruction: :push_arg, index: 0 },
  #                                { type: 'Integer', instruction: :set_var, name: :n },
  #                                { type: 'Integer', instruction: :push_var, name: :n },
  #                                { type: 'Integer', instruction: :push_int, value: 0 },
  #                                { type: 'Boolean', instruction: :call, name: :==, arg_count: 1 },
  #                                {
  #                                  type: 'Integer',
  #                                  instruction: :if,
  #                                  if_true: [{ type: 'Integer', instruction: :push_int, value: 0 }],
  #                                  if_false: [
  #                                    { type: 'Integer', instruction: :push_var, name: :n },
  #                                    { type: 'Integer', instruction: :push_int, value: 1 },
  #                                    { type: 'Boolean', instruction: :call, name: :==, arg_count: 1 },
  #                                    {
  #                                      type: 'Integer',
  #                                      instruction: :if,
  #                                      if_true: [{ type: 'Integer', instruction: :push_int, value: 1 }],
  #                                      if_false: [
  #                                        { type: '(object main)', instruction: :push_self },
  #                                        { type: 'Integer', instruction: :push_var, name: :n },
  #                                        { type: 'Integer', instruction: :push_int, value: 1 },
  #                                        { type: 'Integer', instruction: :call, name: :-, arg_count: 1 },
  #                                        {
  #                                          type: 'Integer',
  #                                          instruction: :call,
  #                                          name: :fib,
  #                                          arg_count: 1,
  #                                        },
  #                                        { type: '(object main)', instruction: :push_self },
  #                                        { type: 'Integer', instruction: :push_var, name: :n },
  #                                        { type: 'Integer', instruction: :push_int, value: 2 },
  #                                        { type: 'Integer', instruction: :call, name: :-, arg_count: 1 },
  #                                        {
  #                                          type: 'Integer',
  #                                          instruction: :call,
  #                                          name: :fib,
  #                                          arg_count: 1,
  #                                        },
  #                                        { type: 'Integer', instruction: :call, name: :+, arg_count: 1 },
  #                                      ],
  #                                    },
  #                                  ],
  #                                },
  #                              ],
  #                            },
  #                            { type: '(object main)', instruction: :push_self },
  #                            { type: '(object main)', instruction: :push_self },
  #                            { type: 'Integer', instruction: :push_int, value: 10 },
  #                            { type: 'Integer', instruction: :call, name: :fib, arg_count: 1 },
  #                            { type: 'Integer', instruction: :call, name: :puts, arg_count: 1 },
  #                          ]
  # end
  #
  # it 'compiles examples/fact.rb' do
  #   code = File.read(File.expand_path('../examples/fact.rb', __dir__))
  #   expect(compile(code)).must_equal_with_diff [
  #                            {
  #                              type: '([(object main), int, int] -> int)',
  #                              instruction: :def,
  #                              name: :fact,
  #                              params: %i[n result],
  #                              body: [
  #                                { type: 'Integer', instruction: :push_arg, index: 0 },
  #                                { type: 'Integer', instruction: :set_var, name: :n },
  #                                { type: 'Integer', instruction: :push_arg, index: 1 },
  #                                { type: 'Integer', instruction: :set_var, name: :result },
  #                                { type: 'Integer', instruction: :push_var, name: :n },
  #                                { type: 'Integer', instruction: :push_int, value: 0 },
  #                                { type: 'Boolean', instruction: :call, name: :==, arg_count: 1 },
  #                                {
  #                                  type: 'Integer',
  #                                  instruction: :if,
  #                                  if_true: [{ type: 'Integer', instruction: :push_var, name: :result }],
  #                                  if_false: [
  #                                    { type: '(object main)', instruction: :push_self },
  #                                    { type: 'Integer', instruction: :push_var, name: :n },
  #                                    { type: 'Integer', instruction: :push_int, value: 1 },
  #                                    { type: 'Integer', instruction: :call, name: :-, arg_count: 1 },
  #                                    { type: 'Integer', instruction: :push_var, name: :result },
  #                                    { type: 'Integer', instruction: :push_var, name: :n },
  #                                    { type: 'Integer', instruction: :call, name: :*, arg_count: 1 },
  #                                    {
  #                                      type: 'Integer',
  #                                      instruction: :call,
  #                                      name: :fact,
  #                                      arg_count: 2,
  #                                    },
  #                                  ],
  #                                },
  #                              ],
  #                            },
  #                            { type: '(object main)', instruction: :push_self },
  #                            { type: '(object main)', instruction: :push_self },
  #                            { type: 'Integer', instruction: :push_int, value: 10 },
  #                            { type: 'Integer', instruction: :push_int, value: 1 },
  #                            {
  #                              type: 'Integer',
  #                              instruction: :call,
  #                              name: :fact,
  #                              arg_count: 2,
  #                            },
  #                            { type: 'Integer', instruction: :call, name: :puts, arg_count: 1 },
  #                          ]
  # end
end
