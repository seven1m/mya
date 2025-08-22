module SharedBackendExamples
  def self.included(base)
    base.class_eval do
      it 'evaluates integers' do
        expect(execute('123')).must_equal(123)
      end

      it 'evaluates strings' do
        expect(execute('"foo"')).must_equal('foo')
        expect(execute('"a longer string works too"')).must_equal('a longer string works too')
      end

      it 'evaluates nil' do
        expect(execute('nil')).must_be_nil
      end

      it 'evaluates booleans' do
        expect(execute('true')).must_equal(true)
        expect(execute('false')).must_equal(false)
      end

      it 'calls `initialize` on new objects' do
        code = <<~CODE
          class Foo
            def initialize(x)
              puts "Foo#initialize called with " + x
            end
          end
          Foo.new("bar")
        CODE
        out = execute_with_output(code)
        expect(out).must_equal("Foo#initialize called with bar\n")
      end

      it 'evaluates classes with instance variables' do
        code = <<~CODE
          class Person
            def initialize
              @name = ""
              @age = 0
            end

            def name=(name) # name:String
              @name = name
            end

            def age=(age) # age:Integer
              @age = age
            end

            def name
              @name
            end

            def age
              @age
            end

            def info
              @name + " is " + @age.to_s + " years old"
            end
          end

          person = Person.new
          person.name = "Alice"
          person.age = 30
          person.info
        CODE
        expect(execute(code)).must_equal('Alice is 30 years old')
      end

      it 'evaluates variables set and get' do
        expect(execute('a = 1; a + a')).must_equal(2)
      end

      it 'evaluates variables with type annotation' do
        code = <<~CODE
          x = 42 # x:Integer
          x + 8
        CODE
        expect(execute(code)).must_equal(50)

        code = <<~CODE
          name = "Alice" # name:String
          name + " Smith"
        CODE
        expect(execute(code)).must_equal('Alice Smith')

        code = <<~CODE
          message = "hello" # message:Option[String]
          if message
            message.value!
          else
            "no message"
          end
        CODE
        expect(execute(code)).must_equal('hello')
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

      it 'evaluates puts for strings' do
        code = <<~CODE
           puts("hello")
           puts("world")
         CODE
        out = execute_with_output(code)
        expect(out).must_equal("hello\nworld\n")
      end

      it 'evaluates strings' do
        code = <<~CODE
           a = "foo"
           a
         CODE
        expect(execute(code)).must_equal('foo')
      end

      it 'evaluates while loops' do
        code = <<~CODE
          i = 0
          sum = 0
          while i < 5
            sum = sum + i
            i = i + 1
          end
          sum
        CODE
        expect(execute(code)).must_equal(10)
      end

      it 'evaluates while loops that never execute' do
        code = <<~CODE
          i = 10
          sum = 42
          while i < 5
            sum = sum + i
            i = i + 1
          end
          sum
        CODE
        expect(execute(code)).must_equal(42)
      end

      it 'evaluates nested while loops' do
        code = <<~CODE
          i = 0
          result = 0
          while i < 3
            j = 0
            while j < 2
              result = result + 1
              j = j + 1
            end
            i = i + 1
          end
          result
        CODE
        expect(execute(code)).must_equal(6)
      end

      it 'evaluates examples/fib.rb' do
        result = execute_file(File.expand_path('../../examples/fib.rb', __dir__))
        expect(result).must_equal("55\n")
      end

      it 'evaluates examples/fact.rb' do
        result = execute_file(File.expand_path('../../examples/fact.rb', __dir__))
        expect(result).must_equal("3628800\n")
      end

      it 'evaluates examples/countdown.rb' do
        result = execute_file(File.expand_path('../../examples/countdown.rb', __dir__))
        expect(result).must_equal(<<~END)
          5
          4
          3
          2
          1
          Done!
        END
      end

      it 'evaluates examples/countdown.rb' do
        result = execute_file(File.expand_path('../../examples/type_annotations.rb', __dir__))
        expect(result).must_equal(<<~END)
          Alice is 25 years old with 0 points (active: false)
          Alice is 25 years old with 100 points (active: true)
          Adding 10 and 20
          Sum: 30
          Hello, Bob!
          Greeted: Bob
          Status is: false
          Final status: false
        END
      end

      it 'evaluates Option types with nil' do
        code = <<~CODE
          def maybe_greet(name) # name:Option[String]
            if name
              "Hello, " + name.value!
            else
              "No name provided"
            end
          end

          maybe_greet(nil)
        CODE
        expect(execute(code)).must_equal('No name provided')
      end

      it 'evaluates Option types with values' do
        code = <<~CODE
          def maybe_greet(name) # name:Option[String]
            if name
              "Hello, " + name.value!
            else
              "No name provided"
            end
          end

          maybe_greet("Tim")
        CODE
        expect(execute(code)).must_equal('Hello, Tim')
      end

      it 'evaluates Option types in conditional expressions' do
        code = <<~CODE
          def process_optional(value) # value:Option[String]
            if value
              value.value! + " processed"
            else
              "nothing to process"
            end
          end

          a = process_optional("data")
          b = process_optional(nil)
          a + " | " + b
        CODE
        expect(execute(code)).must_equal('data processed | nothing to process')
      end
    end
  end
end
