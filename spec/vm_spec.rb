require_relative './spec_helper'

describe VM do
  def execute(code)
    instructions = Compiler.new(code).compile
    VM.new(instructions).run
  end

  it 'evaluates integers' do
    expect(execute('1')).must_equal(1)
  end

  it 'evaluates strings' do
    expect(execute('"foo"')).must_equal('foo')
  end

  it 'evaluates booleans' do
    expect(execute('true')).must_equal(true)
    expect(execute('false')).must_equal(false)
  end

  it 'evaluates variables set and get' do
    expect(execute('a = 1; a')).must_equal(1)
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
      def foo(a, b)
        bar(b)
      end

      def bar(x)
        x
      end

      foo('foo', 100)
    CODE
    expect(execute(code)).must_equal(100)
  end

  it 'evaluates if expressions' do
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
end
