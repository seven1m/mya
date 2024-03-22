require 'set'

class Hash
  def deep_dup
    each_with_object({}) do |(key, val), hash|
      hash[key] = val.is_a?(Hash) ? val.deep_dup : val
    end
  end
end

class Compiler
  class TypeVariable
    def initialize(type_checker)
      @type_checker = type_checker
      @id = @type_checker.next_variable_id
      @generic = true
    end

    attr_accessor :id, :instance

    def name
      @name ||= @type_checker.next_variable_name
    end

    def to_s
      name.to_s
    end

    def to_sym
      name.to_sym
    end

    def inspect
      "TypeVariable(id = #{id})"
    end

    def generic? = @generic

    def non_generic!
      @generic = false
      self
    end

    def prune
      return self if @instance.nil?

      @instance = @instance.prune
      @instance.non_generic! unless generic?
      @instance
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

    def to_sym
      to_s.to_sym
    end

    def inspect
      "#<TypeOperator name=#{name} types=#{types.join(', ')}>"
    end

    def non_generic!
      types.each(&:non_generic!)
      self
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
      "#<FunctionType #{types.map(&:inspect).join(', ')}>"
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

  class NillableType < TypeOperator
    def initialize(type)
      super('nillable', [type])
    end

    def to_s
      "(nillable #{types[0]})"
    end
  end

  class ClassType < TypeOperator
    def initialize(name, attributes)
      super('class', [])
      @name = name
      @attributes = attributes
    end

    def to_s
      "(class #{@name})"
    end
  end

  IntType = TypeOperator.new('int', [])
  StrType = TypeOperator.new('str', [])
  NilType = TypeOperator.new('nil', [])
  BoolType = TypeOperator.new('bool', [])

  class TypeChecker
    class Error < StandardError; end
    class RecursiveUnification < Error; end
    class TypeClash < Error; end
    class UndefinedSymbol < Error; end

    def initialize
      @stack = []
      @scope_stack = []
      @classes = {}
      @calls_to_unify = []
    end

    def analyze(exp, env = build_initial_env)
      analyze_exp(exp, env).prune
      @calls_to_unify.each do |call|
        type_of_receiver = call.fetch(:type_of_receiver).prune
        exp = call.fetch(:exp)
        type_of_fun = retrieve_type(type_of_receiver, exp.name, call.fetch(:env))
        raise UndefinedSymbol, "undefined method #{exp.name} on #{type_of_receiver.inspect} on line #{exp.line}" unless type_of_fun
        unify_type(type_of_fun, call.fetch(:type_of_fun), exp)
      end
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

    def analyze_exp(exp, env)
      case exp
      when Array
        last_type = nil
        exp.each do |e|
          last_type = analyze_exp(e, env)
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
      when PushNilInstruction
        @stack << NilType
        exp.type = NilType
      when SetVarInstruction
        type = @stack.pop
        if (existing_type = env.dig(nil, exp.name))
          unify_type(existing_type, type, exp)
          type = existing_type
        elsif type == NilType
          type = NillableType.new(TypeVariable.new(self))
        elsif exp.nillable?
          type = NillableType.new(type)
        end
        env[nil][exp.name] = type
        exp.type = type
      when PushVarInstruction
        type = retrieve_type(nil, exp.name, env)
        raise UndefinedSymbol, "undefined symbol #{exp.name.inspect}" unless type
        @stack << type
        exp.type = type
      when PushArgInstruction
        type = @scope_stack.last.fetch(:parameter_types).fetch(exp.index)
        @stack << type
        exp.type = type
      when DefInstruction
        new_type_var = TypeVariable.new(self)
        env[nil][exp.name] = new_type_var.non_generic!

        body_env = env.deep_dup

        parameter_types = exp.params.map do |param|
          type_of_parameter = TypeVariable.new(self).non_generic!
          body_env.merge!(param => type_of_parameter)
          type_of_parameter
        end

        @scope_stack << { parameter_types: }
        type_of_body = analyze_exp(exp.body, body_env)
        @scope_stack.pop

        type_of_fun = FunctionType.new(*parameter_types, type_of_body)
        unify_type(type_of_fun, new_type_var, exp)

        env[nil][exp.name] = type_of_fun.non_generic!
        exp.type = type_of_fun

        type_of_fun
      when CallInstruction
        type_of_args = @stack.pop(exp.arg_count)

        if exp.has_receiver?
          type_of_receiver = @stack.pop or raise('Expected receiver on stack but got nil')
          type_of_args.unshift(type_of_receiver)
        end

        if type_of_receiver&.prune.is_a?(TypeVariable)
          # We cannot unify yet, since we don't know the receiver type.
          # Save this call for later unification.
          type_of_return = TypeVariable.new(self)
          type_of_fun = FunctionType.new(*type_of_args, type_of_return)
          @calls_to_unify << { type_of_receiver:, type_of_fun:, exp:, env: }
          exp.type = type_of_return
          @stack << type_of_return
          return type_of_return
        end

        type_of_fun = retrieve_type(type_of_receiver, exp.name, env)
        raise UndefinedSymbol, "undefined method #{exp.name}" unless type_of_fun

        type_of_return = TypeVariable.new(self)
        unify_type(type_of_fun, FunctionType.new(*type_of_args, type_of_return), exp)

        exp.type = type_of_return
        @stack << type_of_return
        type_of_return
      when IfInstruction
        condition = @stack.pop
        type_of_then = analyze_exp(exp.if_true, env)
        type_of_else = analyze_exp(exp.if_false, env)
        unify_type(type_of_then, type_of_else, exp)
        exp.type = type_of_then
      when PushArrayInstruction
        members = @stack.pop(exp.size)
        if members.any?(NilType)
          members.map! do |type|
            if type == NilType
              NillableType.new(TypeVariable.new(self))
            else
              NillableType.new(type)
            end
          end
        end
        members.each_cons(2) do |a, b|
          unify_type(a, b, exp)
        end
        member_type = members.first || TypeVariable.new(self)
        member_type.non_generic!
        type_of_array = AryType.new(member_type)
        @stack << type_of_array
        exp.type = type_of_array
      when PushConstInstruction
        klass = @classes[exp.name]
        @stack << klass
        exp.type = klass
      when ClassInstruction
        klass = @classes[exp.name] = ClassType.new(exp.name, {})
        exp.type = klass
      else
        raise "unknown expression: #{exp.inspect}"
      end
    end

    def retrieve_type(type, name, env)
      return unless (exp = env.dig(type&.name, name))

      fresh_type(exp)
    end

    def fresh_type(type_exp, env = {})
      type_exp = type_exp.prune
      case type_exp
      when TypeVariable
        if type_exp.generic?
          env[type_exp] ||= TypeVariable.new(self)
        else
          type_exp
        end
      when TypeOperator
        type_exp.dup.tap do |new_type|
          new_type.types = type_exp.types.map { |t| fresh_type(t, env) }
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
          elsif a.name == 'nillable'
            if b.name == 'nil'
              # noop
            elsif b.name == 'nillable'
              unify_type(a.types.first, b.types.first, instruction)
            elsif a.types.first.is_a?(TypeVariable)
              unify_type(a.types.first, b)
            else
              raise_type_clash_error(a, b, instruction)
            end
          elsif a.name == b.name && a.types.size == b.types.size
            begin
              unify_args(a.types, b.types, instruction)
            rescue TypeClash
              raise_type_clash_error(a, b, instruction)
            end
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
        "#{a} cannot unify with #{b} in call to #{instruction.name} on line #{instruction.line}"
      when IfInstruction
        "one branch of `if` has type #{a} and the other has type #{b}"
      when SetVarInstruction
        "the variable #{instruction.name} has type #{a} already; you cannot change it to type #{b}"
      when PushArrayInstruction
        "the array contains type #{a} but you are trying to push type #{b}"
      else
        "#{a} cannot unify with #{b} #{instruction.inspect}"
      end
      raise TypeClash, message
    end

    def build_initial_env
      array_type = TypeVariable.new(self)
      array = AryType.new(array_type)
      {
        nil => {
          "true": BoolType,
          "false": BoolType,
          puts: FunctionType.new(UnionType.new(IntType, StrType), IntType),
        },
        'int' => {
          zero?: FunctionType.new(IntType, BoolType),
          "+": FunctionType.new(IntType, IntType, IntType),
          "==": FunctionType.new(IntType, IntType, BoolType),
          "-": FunctionType.new(IntType, IntType, IntType),
          "*": FunctionType.new(IntType, IntType, IntType),
          "/": FunctionType.new(IntType, IntType, IntType),
        },
        'array' => {
          nth: FunctionType.new(array, IntType, array_type),
          first: FunctionType.new(array, array_type),
          last: FunctionType.new(array, array_type),
          '<<': FunctionType.new(array, array_type, array),
          push: FunctionType.new(array, array_type, array_type),
        },
      }
    end
  end
end
