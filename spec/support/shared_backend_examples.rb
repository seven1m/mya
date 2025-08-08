module SharedBackendExamples
  def self.included(base)
    base.class_eval do
      it 'evaluates integers' do
        expect(execute('123')).must_equal(123)
      end

      it 'evaluates strings' do
        expect(execute('"foo"')).must_equal('foo')
      end

      it 'evaluates nil' do
        expect(execute('nil')).must_be_nil
      end

      it 'evaluates booleans' do
        expect(execute('true')).must_equal(true)
        expect(execute('false')).must_equal(false)
      end

      it 'evaluates classes' do
        code = <<~CODE
          class Foo
            def bar
              @bar = 10
            end
          end
          Foo.new.bar
        CODE
        expect(execute(code)).must_equal(10)
      end

      it 'evaluates variables set and get' do
        expect(execute('a = 1; a + a')).must_equal(2)
      end

      it 'evaluates arrays' do
        code = <<~CODE
          a = [1, 2, 3]
          a.first
        CODE
        expect(execute(code)).must_equal(1)

        code = <<~CODE
          a = [1, 2, 3]
          a.last
        CODE
        expect(execute(code)).must_equal(3)

        code = <<~CODE
          a = []
          a << 4
          a << 5
          a.last
        CODE
        expect(execute(code)).must_equal(5)

        code = <<~CODE
          a = []
          a << "foo"
          a << "bar"
          a.last
        CODE
        expect(execute(code)).must_equal('bar')

        code = <<~CODE
          a = ["foo", "bar", "baz"]
          a.first
        CODE
        expect(execute(code)).must_equal('foo')

        code = <<~CODE
          a = ["foo", "bar", "baz"]
          a.last
        CODE
        expect(execute(code)).must_equal('baz')

        code = <<~CODE
          a = [nil, "foo", "bar"]
          a.last
        CODE
        expect(execute(code)).must_equal('bar')

        code = <<~CODE
          a = ["foo", "bar", nil]
          a.last
        CODE
        expect(execute(code)).must_be_nil

        code = <<~CODE
          a = [1, 2, 3]
          b = [4, 5, 6]
          c = [a, b, nil]
          c.last
        CODE
        expect(execute(code)).must_be_nil
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
        expect(execute('1 < 2')).must_equal true
        expect(execute('2 < 1')).must_equal false
        expect(execute('2 < 2')).must_equal false
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

      it 'evaluates puts for both int and str' do
        code = <<~CODE
          puts(123)
          puts("foo")
        CODE
        out = execute_with_output(code)
        expect(out).must_equal("123\nfoo\n")
      end

      it 'evaluates nillable strings' do
        code = <<~CODE
          a = "foo" # a:nillable
          a = nil
          a
        CODE
        expect(execute(code)).must_be_nil

        code = <<~CODE
          a = nil
          a = "foo"
          a
        CODE
        expect(execute(code)).must_equal('foo')
      end

      it 'evaluates examples/fib.rb' do
        result = execute_file(File.expand_path('../../examples/fib.rb', __dir__))
        expect(result).must_equal("55\n")
      end

      it 'evaluates examples/fact.rb' do
        result = execute_file(File.expand_path('../../examples/fact.rb', __dir__))
        expect(result).must_equal("3628800\n")
      end
    end
  end
end
