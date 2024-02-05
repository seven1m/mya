require_relative './spec_helper'
require 'stringio'

describe JIT do
  def execute(code, io: $stdout)
    instructions = Compiler.new(code).compile
    JIT.new(instructions, io:).run
  end

  it 'evaluates integers' do
    expect(execute('123')).must_equal(123)
  end

  it 'evaluates strings' do
    expect(execute('"foo"')).must_equal('foo')
  end

  it 'evaluates booleans' do
    expect(execute('true')).must_equal(true)
    expect(execute('false')).must_equal(false)
  end

  it 'evaluates variables set and get' do
    expect(execute('a = 1; a + a')).must_equal(2)
  end

  it 'evaluates method definitions' do
    code = <<~CODE
      def foo
        'foo'
      end

      foo
    CODE
    expect(execute(code)).must_equal('foo')
  end

  it 'evaluates method definitions with arguments' do
    code = <<~CODE
      def bar(x)
        x
      end

      def foo(a, b)
        bar(b - 10)
      end

      foo('foo', 100)
    CODE
    expect(execute(code)).must_equal(90)
  end

  it 'does not stomp on method arguments' do
    code = <<~CODE
      def bar(b)
        b
      end

      def foo(a, b)
        bar(b - 10)
        b
      end

      foo('foo', 100)
    CODE
    expect(execute(code)).must_equal(100)
  end

  it 'evaluates operator expressions' do
    expect(execute('1 + 2')).must_equal 3
    expect(execute('3 - 1')).must_equal 2
    expect(execute('2 * 3')).must_equal 6
    expect(execute('6 / 2')).must_equal 3
    expect(execute('3 == 3')).must_equal true
    expect(execute('3 == 4')).must_equal false
  end

  it 'evaluates simple if expressions' do
    code = <<~CODE
      if true
        3
      else
        4
      end
    CODE
    expect(execute(code)).must_equal(3)

    code = <<~CODE
      if false
        3
      else
        4
      end
    CODE
    expect(execute(code)).must_equal(4)
  end

  it 'evaluates nested if expressions' do
    skip
    code = <<~CODE
      if false
        if true
          1
        else
          2
        end
      else
        if true
          3           # <-- this one
        else
          4
        end
      end
    CODE
    expect(execute(code)).must_equal(3)

    code = <<~CODE
      if true
        if false
          1
        else
          2           # <-- this one
        end
      else
        if false
          3
        else
          4
        end
      end
    CODE
    expect(execute(code)).must_equal(2)

    code = <<~CODE
      if false
        if false
          1
        else
          2
        end
      elsif false
        3
      else
        if false
          4
        else
          5           # <-- this one
        end
      end
    CODE
    expect(execute(code)).must_equal(5)
  end

  #it 'evaluates examples/fib.rb' do
    #code = File.read(File.expand_path('../examples/fib.rb', __dir__))
    #io = StringIO.new
    #execute(code, io:)
    #io.rewind
    #expect(io.read).must_equal("610\n")
  #end
end
