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

  it 'compiles method definitions with arguments' do
    code = <<~CODE
      def bar(x)
        x
      end

      def foo(a, b)
        bar(b)
      end

      foo('foo', 100)
    CODE
    expect(execute(code)).must_equal(100)
  end
end
