# Type checking and inference algorithm based on the paper
# Basic Polymorphic Typechecking by Luca Cardelli [1987]
# https://pages.cs.wisc.edu/~horwitz/CS704-NOTES/PAPERS/cardelli.pdf
#
# See https://gist.github.com/seven1m/205e64d05ff56c36b68416691a0dbe7c
# for the original port from Modula-2 to Ruby.
#
# The version here is modified to work with the semantics of my
# Ruby-like compiled language Mya.

require 'set'

Cond = Struct.new(:test, :if_true, :if_false)

class Function
  def initialize(parameters, body)
    @parameters = Array(parameters)
    @body = body
  end

  attr_reader :parameters, :body

  def to_s
    "(fn (#{parameters.join(', ')}) => #{body})"
  end
end

Identifier = Struct.new(:name) do
  alias to_s name
end

class Call
  def initialize(fun, *args)
    @fun = fun
    @args = args
  end

  attr_reader :fun, :args

  def to_s
    "(#{fun} #{args.join(', ')})"
  end
end

Var = Struct.new(:binder, :def)

class Block
  def initialize(*exprs)
    @exprs = exprs
  end

  attr_reader :exprs
end

class TypeVariable
  def initialize(type_checker)
    @type_checker = type_checker
    @id = @type_checker.next_variable_id
  end

  attr_accessor :id, :instance

  def name
    @name ||= @type_checker.next_variable_name
  end

  alias to_s name

  def inspect
    "TypeVariable(id = #{id})"
  end
end

TypeOperator = Struct.new(:name, :types) do
  def to_s
    case types.size
    when 0
      name
    when 2
      "(#{types[0]} #{name} #{types[1]})"
    else
      "#{name} #{types.join(' ')}"
    end
  end
end

class FunctionType < TypeOperator
  def initialize(*types)
    super('->', types)
  end

  def to_s
    arg_types = types[0...-1]
    return_type = types.last
    return "([#{arg_types.join(', ')}] -> #{return_type})"
  end

  def inspect
    "#<FunctionType #{types.join(', ')}>"
  end
end

IntType = TypeOperator.new('int', [])
BoolType = TypeOperator.new('bool', [])

class TypeChecker
  class Error < StandardError; end
  class RecursiveUnification < Error; end
  class TypeClash < Error; end
  class UndefinedSymbol < Error; end

  def analyze(exp, env = build_initial_env, non_generic_vars = Set.new)
    prune(analyze_exp(exp, env, non_generic_vars))
  end

  def next_variable_id
    if @next_variable_id
      @next_variable_id += 1
    else
      @next_variable_id = 0
    end
  end

  def next_variable_name
    if @next_variable_name
      @next_variable_name = @next_variable_name.succ
    else
      @next_variable_name = 'a'
    end
  end

  private

  def analyze_exp(exp, env, non_generic_vars)
    case exp
    when Identifier
      if (exp2 = retrieve_type(exp.name, env, non_generic_vars))
        exp2
      elsif exp.name =~ /^\d+$/
        IntType
      else
        raise UndefinedSymbol, "undefined symbol #{exp.name}"
      end
    when Cond
      unify_type(analyze_exp(exp.test, env, non_generic_vars), BoolType)
      type_of_then = analyze_exp(exp.if_true, env, non_generic_vars)
      type_of_else = analyze_exp(exp.if_false, env, non_generic_vars)
      unify_type(type_of_then, type_of_else)
      type_of_then
    when Function
      body_env = env.dup
      body_non_generic_vars = non_generic_vars.dup
      parameter_types = exp.parameters.map do |parameter|
        type_of_parameter = TypeVariable.new(self)
        body_env.merge!(parameter => type_of_parameter)
        body_non_generic_vars << type_of_parameter
        type_of_parameter
      end
      type_of_body = analyze_exp(exp.body, body_env, body_non_generic_vars)
      FunctionType.new(*parameter_types, type_of_body)
    when Call
      type_of_fun = analyze_exp(exp.fun, env, non_generic_vars)
      type_of_args = exp.args.map { |arg| analyze_exp(arg, env, non_generic_vars) }
      type_of_res = TypeVariable.new(self)
      unify_type(type_of_fun, FunctionType.new(*type_of_args, type_of_res))
      type_of_res
    when Block
      env = env.dup
      non_generic_vars = non_generic_vars.dup
      last_type = nil
      exp.exprs.each do |e|
        last_type = analyze_exp(e, env, non_generic_vars)
      end
      last_type
    when Var
      new_type_var = TypeVariable.new(self)
      env[exp.binder] = new_type_var
      non_generic_vars << new_type_var
      env[exp.binder] = analyze_exp(exp.def, env, non_generic_vars)
    else
      raise "unknown expression: #{exp.inspect}"
    end
  end

  def retrieve_type(name, env, non_generic_vars)
    return unless (exp = env[name])

    fresh_type(exp, non_generic_vars)
  end

  def fresh_type(type_exp, non_generic_vars, env = {})
    type_exp = prune(type_exp)
    case type_exp
    when TypeVariable
      if occurs_in_type_list?(type_exp, non_generic_vars)
        type_exp
      else
        env[type_exp] ||= TypeVariable.new(self)
      end
    when TypeOperator
      type_exp.dup.tap do |new_type|
        new_type.types = type_exp.types.map { |t| fresh_type(t, non_generic_vars, env) }
      end
    end
  end

  def prune(type_exp)
    case type_exp
    when TypeVariable
      if type_exp.instance.nil?
        type_exp
      else
        type_exp.instance = prune(type_exp.instance)
      end
    when TypeOperator
      type_exp.dup.tap do |new_type|
        new_type.types = type_exp.types.map { |t| prune(t) }
      end
    end
  end

  def occurs_in_type?(type_var, type_exp)
    type_exp = prune(type_exp)
    case type_exp
    when TypeVariable
      type_var == type_exp
    when TypeOperator
      occurs_in_type_list?(type_var, type_exp.types)
    end
  end

  def occurs_in_type_list?(type_var, list)
    list.any? { |t| occurs_in_type?(type_var, t) }
  end

  def unify_type(a, b)
    a = prune(a)
    b = prune(b)
    case a
    when TypeVariable
      if occurs_in_type?(a, b)
        unless a == b
          raise RecursiveUnification, "recursive unification: #{b} contains #{a}"
        end
      else
        a.instance = b
      end
    when TypeOperator
      case b
      when TypeVariable
        unify_type(b, a)
      when TypeOperator
        if a.name == b.name && a.types.size == b.types.size
          unify_args(a.types, b.types)
        else
          raise TypeClash, "#{a} cannot unify with #{b}"
        end
      end
    end
  end

  def unify_args(list1, list2)
    list1.zip(list2) do |a, b|
      unify_type(a, b)
    end
  end

  def build_initial_env
    pair_first = TypeVariable.new(self)
    pair_second = TypeVariable.new(self)
    pair_type = TypeOperator.new('×', [pair_first, pair_second])
    list_type = TypeVariable.new(self)
    list = TypeOperator.new('list', [list_type])
    list_pair_type = TypeOperator.new('×', [list_type, list])
    {
      'true' => BoolType,
      'false' => BoolType,
      'succ' => FunctionType.new(IntType, IntType),
      'pred' => FunctionType.new(IntType, IntType),
      'zero?' => FunctionType.new(IntType, BoolType),
      'times' => FunctionType.new(IntType, IntType, IntType),
      'minus' => FunctionType.new(IntType, IntType, IntType),
      'pair' => FunctionType.new(pair_first, pair_second, pair_type),
      'fst' => FunctionType.new(pair_type, pair_first), # car
      'snd' => FunctionType.new(pair_type, pair_second), # cdr
      'nil' => list,
      'cons' => FunctionType.new(list_pair_type, list),
      'head' => FunctionType.new(list, list_type),
      'tail' => FunctionType.new(list, list),
      'null?' => FunctionType.new(list, BoolType),
    }
  end
end

def debug(type, indent = 0)
  case type
  when FunctionType
    puts ' ' * indent + 'FunctionType'
    puts ' ' * indent + '  arg:'
    debug(type.types[0], indent + 4)
    puts ' ' * indent + '  body:'
    debug(type.types[1], indent + 4)
  when TypeVariable
    puts ' ' * indent + 'TypeVariable'
    puts ' ' * indent + "  id: #{type.id}"
    puts ' ' * indent + "  name: #{type.name}"
    puts ' ' * indent + '  instance:'
    debug(type.instance, indent + 4)
  when nil
    puts ' ' * indent + 'nil'
  end
end

if $0 == __FILE__
  require 'minitest/autorun'
  require 'minitest/spec'

  describe TypeChecker do
    describe '#analyze' do
      def analyze(exp)
        TypeChecker.new.analyze(exp)
      end

      it 'determines type of the expression' do
        exp = Function.new('f', Identifier.new('f'))
        expect(analyze(exp).to_s).must_equal '([a] -> a)'

        exp = Function.new('f',
                Function.new('g',
                  Function.new('arg',
                    Call.new(Identifier.new('g'),
                      Call.new(Identifier.new('f'), Identifier.new('arg'))))))
        expect(analyze(exp).to_s).must_equal '([([a] -> b)] -> ([([b] -> c)] -> ([a] -> c)))'

        exp = Function.new('g',
          Block.new(
            Var.new('f',
              Function.new('x', Identifier.new('g'))),
            Call.new(
              Identifier.new('pair'),
                Call.new(Identifier.new('f'), Identifier.new('3')),
                Call.new(Identifier.new('f'), Identifier.new('true')))))
        expect(analyze(exp).to_s).must_equal '([a] -> (a × a))'

        exp = Block.new(
          Var.new('g',
            Function.new('f', Identifier.new('5'))),
          Call.new(Identifier.new('g'), Identifier.new('g')))
        expect(analyze(exp).to_s).must_equal 'int'

        pair = Call.new(
          Identifier.new('pair'),
          Call.new(
            Identifier.new('f'),
            Identifier.new('4')
          ),
          Call.new(
            Identifier.new('f'),
            Identifier.new('true')
          ))
        exp = Block.new(
          Var.new('f', Function.new('x', Identifier.new('x'))),
          pair)
        expect(analyze(exp).to_s).must_equal '(int × bool)'

        # def factorial(n)
        #   if n.zero?
        #     1
        #   else
        #     n * factorial(n - 1)
        #   end
        # end
        exp = Block.new(
          Var.new('factorial',
            Function.new('n', # def factorial
              Cond.new( # if
                Call.new(Identifier.new('zero?'), Identifier.new('n')), # (zero? n)
                Identifier.new('1'), # then 1
                Call.new( # else
                  Identifier.new('times'), # (times n ...)
                  Identifier.new('n'),
                  Call.new( # (factorial (minus n 1))
                    Identifier.new('factorial'),
                    Call.new( # (minus n 1)
                      Identifier.new('minus'),
                      Identifier.new('n'),
                      Identifier.new('1'))))))),
          Call.new(Identifier.new('factorial'), Identifier.new('5')))
        expect(analyze(exp).to_s).must_equal 'int'

        # (list 1 2)
        exp = Call.new(Identifier.new('cons'),
                Call.new(Identifier.new('pair'),
                  Identifier.new('1'),
                  Call.new(Identifier.new('cons'),
                    Call.new(Identifier.new('pair'),
                      Identifier.new('2'),
                      Identifier.new('nil')))))
        expect(analyze(exp).to_s).must_equal 'list int'

        exp = Block.new(
                Var.new('x', Identifier.new('2')),
                Var.new('fn', Function.new('n',
                  Call.new(
                    Identifier.new('times'),
                    Identifier.new('n'),
                    Identifier.new('x')))),
                Call.new(
                  Identifier.new('pair'),
                  Identifier.new('x'),
                  Call.new(Identifier.new('fn'), Identifier.new('3'))))
        expect(analyze(exp).to_s).must_equal '(int × int)'
      end

      it 'can pass no arguments to a lambda' do
        exp = Block.new(
                Var.new('fn', Function.new([], Identifier.new('1'))),
                Call.new(Identifier.new('fn')))
        expect(analyze(exp).to_s).must_equal 'int'

        exp = Call.new(Identifier.new('pair'), Identifier.new('1'), Identifier.new('true'))
        expect(analyze(exp).to_s).must_equal '(int × bool)'
      end

      it 'can pass more than one argument to a lambda' do
        exp = Call.new(Identifier.new('pair'), Identifier.new('1'), Identifier.new('2'))
        expect(analyze(exp).to_s).must_equal '(int × int)'

        exp = Call.new(Identifier.new('pair'), Identifier.new('1'), Identifier.new('true'))
        expect(analyze(exp).to_s).must_equal '(int × bool)'

        exp = Block.new(
                Var.new('fn', Function.new(['a', 'b'],
                  Call.new(
                    Identifier.new('pair'),
                    Identifier.new('b'),
                    Identifier.new('a')))),
                Call.new(Identifier.new('fn'), Identifier.new('1'), Identifier.new('true')))
        expect(analyze(exp).to_s).must_equal '(bool × int)'
      end

      it 'raises an error if the number of arguments does not match' do
        exp = Call.new(Identifier.new('pair'), Identifier.new('1'))
        err = expect { analyze(exp) }.must_raise TypeChecker::TypeClash
        expect(err.message).must_equal '([a, b] -> (a × b)) cannot unify with ([int] -> c)'

        exp = Call.new(Identifier.new('pair'), Identifier.new('1'), Identifier.new('2'), Identifier.new('3'))
        err = expect { analyze(exp) }.must_raise TypeChecker::TypeClash
        expect(err.message).must_equal '([a, b] -> (a × b)) cannot unify with ([int, int, int] -> c)'
      end

      it 'raises an error on type clash' do
        exp = Function.new('x',
          Call.new(
            Identifier.new('pair'),
            Call.new(Identifier.new('x'), Identifier.new('3')),
            Call.new(Identifier.new('x'), Identifier.new('true'))))
        err = expect { analyze(exp) }.must_raise TypeChecker::TypeClash
        expect(err.message).must_equal 'int cannot unify with bool'
      end

      it 'raises an error on type clash with a list' do
        list = Call.new(
                Identifier.new('cons'),
                Call.new(Identifier.new('pair'),
                  Identifier.new('true'),
                  Call.new(Identifier.new('cons'),
                    Call.new(Identifier.new('pair'), Identifier.new('2'), Identifier.new('nil')))))
        err = expect { analyze(list) }.must_raise TypeChecker::TypeClash
        expect(err.message).must_equal 'bool cannot unify with int'
      end

      it 'raises an error when the symbol is undefined' do
        exp = Call.new(
          Identifier.new('pair'),
          Call.new(Identifier.new('f'), Identifier.new('4')),
          Call.new(Identifier.new('f'), Identifier.new('true')))
        err = expect { analyze(exp) }.must_raise TypeChecker::UndefinedSymbol
        expect(err.message).must_equal 'undefined symbol f'
      end

      it 'raises an error on recursive unification' do
        exp = Function.new('f', Call.new(Identifier.new('f'), Identifier.new('f')))
        err = expect { analyze(exp) }.must_raise TypeChecker::RecursiveUnification
        expect(err.message).must_equal 'recursive unification: ([a] -> b) contains a'
      end
    end
  end
end
