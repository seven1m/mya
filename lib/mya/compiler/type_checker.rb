require 'set'

class Compiler
  class TypeVariable
    def initialize(type_checker)
      @type_checker = type_checker
      @id = @type_checker.next_variable_id
    end

    attr_accessor :id, :instance

    def name
      @name ||= @type_checker.next_variable_name
    end

    def to_s
      name.to_s
    end

    def inspect
      "TypeVariable(id = #{id})"
    end

    def prune
      return self if @instance.nil?

      @instance = instance.prune
    end
  end

  class TypeOperator
    def initialize(name, types)
      @name = name
      @types = types
    end

    attr_accessor :name, :types

    def to_s
      case types.size
      when 0
        name.to_s
      when 2
        "(#{types[0]} #{name} #{types[1]})"
      else
        "#{name} #{types.join(' ')}"
      end
    end

    def inspect
      "#<TypeOperator name=#{name} types=#{types.join(', ')}>"
    end

    def prune
      dup.tap do |new_type|
        new_type.types = types.map(&:prune)
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
      "([#{arg_types.join(', ')}] -> #{return_type})"
    end

    def inspect
      "#<FunctionType #{types.join(', ')}>"
    end
  end

  class UnionType < TypeOperator
    def initialize(*types)
      super('union', types)
    end

    def to_s
      "(#{types.join(' | ')})"
    end
  end

  class AryType < TypeOperator
    def initialize(type)
      super('array', [type])
    end

    def to_s
      "(#{types[0]} array)"
    end
  end

  IntType = TypeOperator.new('int', [])
  StrType = TypeOperator.new('str', [])
  BoolType = TypeOperator.new('bool', [])

  class TypeChecker
    class Error < StandardError; end
    class RecursiveUnification < Error; end
    class TypeClash < Error; end
    class UndefinedSymbol < Error; end

    def initialize
      @stack = []
      @scope_stack = []
    end

    def analyze(exp, env = build_initial_env, non_generic_vars = Set.new)
      analyze_exp(exp, env, non_generic_vars).prune
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
      when Array
        last_type = nil
        # FIXME: I think there's a bug here.
        # Do we lose type information for the first N-1 instructions?
        # Well, kind of.
        # Everything gets analyzed, which is great. But not every type
        # gets pruned!
        exp.each do |e|
          last_type = analyze_exp(e, env, non_generic_vars)
        end
        last_type
      when PushIntInstruction
        @stack << IntType
        exp.type = IntType
      when PushStrInstruction
        @stack << StrType
        exp.type = StrType
      when PushTrueInstruction, PushFalseInstruction
        @stack << BoolType
        exp.type = BoolType
      when SetVarInstruction
        type = @stack.pop
        if (existing_type = env[exp.name])
          unify_type(existing_type, type, exp)
        else
          env[exp.name] = type
        end
        exp.type = type
      when PushVarInstruction
        type = retrieve_type(exp.name, env, non_generic_vars)
        raise UndefinedSymbol, "undefined symbol #{exp.name}" unless type
        @stack << type
        exp.type = type
      when PushArgInstruction
        type = @scope_stack.last.fetch(:parameter_types).fetch(exp.index)
        @stack << type
        exp.type = type
      when DefInstruction
        new_type_var = TypeVariable.new(self)
        env[exp.name] = new_type_var
        non_generic_vars << new_type_var

        body_env = env.dup
        body_non_generic_vars = non_generic_vars.dup

        parameter_types = exp.params.map do |param|
          type_of_parameter = TypeVariable.new(self)
          body_env.merge!(param => type_of_parameter)
          body_non_generic_vars << type_of_parameter
          type_of_parameter
        end

        @scope_stack << { parameter_types: }
        type_of_body = analyze_exp(exp.body, body_env, body_non_generic_vars)
        @scope_stack.pop

        type_of_fun = FunctionType.new(*parameter_types, type_of_body)

        env[exp.name] = type_of_fun
        non_generic_vars << type_of_fun
        exp.type = type_of_fun

        type_of_fun
      when CallInstruction
        type_of_fun = retrieve_type(exp.name, env, non_generic_vars)
        raise UndefinedSymbol, "undefined method #{exp.name}" unless type_of_fun

        type_of_args = @stack.pop(exp.arg_count)

        type_of_return = TypeVariable.new(self)
        unify_type(type_of_fun, FunctionType.new(*type_of_args, type_of_return), exp)

        exp.type = type_of_return

        @stack << type_of_return
        type_of_return
      when IfInstruction
        condition = @stack.pop
        type_of_then = analyze_exp(exp.if_true, env, non_generic_vars)
        type_of_else = analyze_exp(exp.if_false, env, non_generic_vars)
        unify_type(type_of_then, type_of_else, exp)
        exp.type = type_of_then
      #when Ary
        #exp.members.each_cons(2) do |a, b|
          #unify_type(
            #analyze_exp(a, env, non_generic_vars),
            #analyze_exp(b, env, non_generic_vars)
          #)
        #end
        #member_type = if exp.members.any?
          #analyze_exp(exp.members.first, env, non_generic_vars)
        #else
          #TypeVariable.new(self)
        #end
        #non_generic_vars << member_type
        #AryType.new(member_type)
      else
        raise "unknown expression: #{exp.inspect}"
      end
    end

    def retrieve_type(name, env, non_generic_vars)
      return unless (exp = env[name])

      fresh_type(exp, non_generic_vars)
    end

    def fresh_type(type_exp, non_generic_vars, env = {})
      type_exp = type_exp.prune
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

    def occurs_in_type?(type_var, type_exp)
      type_exp = type_exp.prune
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

    def unify_type(a, b, instruction = nil)
      a = a.prune
      b = b.prune
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
          unify_type(b, a, instruction)
        when TypeOperator
          if a.name == 'union' && (matching = a.types.detect { |t| t.name == b.name && t.types.size == b.types.size })
            unify_type(matching, b, instruction)
          elsif a.name == b.name && a.types.size == b.types.size
            unify_args(a.types, b.types, instruction)
          else
            raise_type_clash_error(a, b, instruction)
          end
        else
          raise "Unknown type: #{b.inspect}"
        end
      else
        raise "Unknown type: #{a.inspect}"
      end
    end

    def unify_args(list1, list2, instruction)
      list1.zip(list2) do |a, b|
        unify_type(a, b, instruction)
      end
    end

    def raise_type_clash_error(a, b, instruction = nil)
      message = case instruction
      when CallInstruction
        "#{a} cannot unify with #{b} in call to #{instruction.name}"
      when IfInstruction
        "one branch of `if` has type #{a} and the other has type #{b}"
      when SetVarInstruction
        "the variable #{instruction.name} has type #{a} already; you cannot change it to type #{b}"
      else
        "#{a} cannot unify with #{b} #{instruction.inspect}"
      end
      raise TypeClash, message
    end

    def build_initial_env
      array_type = TypeVariable.new(self)
      array = AryType.new(array_type)
      {
        "true": BoolType,
        "false": BoolType,
        zero?: FunctionType.new(IntType, BoolType),
        "+": FunctionType.new(IntType, IntType, IntType),
        "==": FunctionType.new(IntType, IntType, BoolType),
        "-": FunctionType.new(IntType, IntType, IntType),
        "*": FunctionType.new(IntType, IntType, IntType),
        "/": FunctionType.new(IntType, IntType, IntType),
        nth: FunctionType.new(array, IntType, array_type),
        push: FunctionType.new(array, array_type, array_type),
        puts: FunctionType.new(UnionType.new(IntType, StrType), IntType),
      }
    end
  end
end
