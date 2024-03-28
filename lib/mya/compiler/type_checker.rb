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

    def name_for_method_lookup = name

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
    def initialize(class_name)
      super('class', [])
      @class_name = class_name.to_s
      @attributes = {}
    end

    attr_reader :class_name, :attributes

    def to_s
      attrs = attributes.map { |name, type| "#{name}:#{type}" }.join(', ')
      "(class #{@class_name} #{attrs})"
    end

    def name_for_method_lookup = @class_name
  end

  class ObjectType < TypeOperator
    def initialize(klass)
      super('object', [])
      @klass = klass
    end

    attr_reader :klass

    def to_s
      "(object #{@klass.class_name})"
    end

    def name_for_method_lookup = to_s
  end

  IntType = TypeOperator.new('int', [])
  StrType = TypeOperator.new('str', [])
  NilType = TypeOperator.new('nil', [])
  BoolType = TypeOperator.new('bool', [])

  class TypeChecker
    class Error < StandardError; end
    class RecursiveUnification < Error; end
    class TypeClash < Error; end
    class UndefinedMethod < Error; end
    class UndefinedVariable < Error; end

    def initialize
      @stack = []
      @scope_stack = [{ vars: {}, class_type: nil }]
      @classes = {}
      @calls_to_unify = []
      @methods = build_initial_methods
    end

    def analyze(instruction)
      analyze_instruction(instruction).prune
      @calls_to_unify.each do |call|
        type_of_receiver = call.fetch(:type_of_receiver).prune
        retrieve_method_and_analyze_call(**call, type_of_receiver:)
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

    def analyze_instruction(instruction)
      return analyze_array_of_instructions(instruction) if instruction.is_a?(Array)

      send("analyze_#{instruction.instruction_name}", instruction)
    end

    def analyze_array_of_instructions(array)
      array.map do |instruction|
        analyze_instruction(instruction)
      end.last
    end

    def analyze_call(instruction)
      type_of_args = pop(instruction.arg_count)

      if instruction.has_receiver?
        type_of_receiver = pop&.prune or raise('expected receiver on stack but got nil')
        type_of_args.unshift(type_of_receiver)
      end

      type_of_return = TypeVariable.new(self)
      type_of_call = FunctionType.new(*type_of_args, type_of_return)

      if type_of_receiver.is_a?(TypeVariable)
        # We cannot unify yet, since we don't know the receiver type.
        # Save this call for later unification.
        @calls_to_unify << { type_of_receiver:, type_of_call:, instruction: }
        instruction.type = type_of_return
        @stack << type_of_return
        return type_of_return
      end

      retrieve_method_and_analyze_call(type_of_receiver:, type_of_call:, instruction:)

      instruction.type = type_of_return
      @stack << type_of_return
      type_of_return
    end

    def retrieve_method_and_analyze_call(type_of_receiver:, type_of_call:, instruction:)
      type_of_fun = retrieve_method(type_of_receiver, instruction.name)
      raise UndefinedMethod, "undefined method #{instruction.name} for type #{type_of_receiver}" unless type_of_fun

      unify_type(type_of_fun, type_of_call, instruction)
    end

    def analyze_class(instruction)
      class_type = @classes[instruction.name] = ClassType.new(instruction.name)
      object_type = ObjectType.new(class_type)
      @methods[class_type.name_for_method_lookup] = {
        new: FunctionType.new(class_type, object_type)
      }

      @scope_stack << { vars: {}, class_type: }
      analyze_instruction(instruction.body)
      @scope_stack.pop

      instruction.type = class_type
    end

    def analyze_def(instruction)
      placeholder_var = TypeVariable.new(self)
      vars[instruction.name] = placeholder_var.non_generic!
      @methods[current_object_type&.name_for_method_lookup][instruction.name] = placeholder_var.non_generic!

      new_vars = {}
      parameter_types = instruction.params.map do |param|
        new_vars[param] = TypeVariable.new(self).non_generic!
      end
      parameter_types.unshift(current_object_type) if current_object_type

      @scope_stack << scope.merge(parameter_types:, vars: new_vars)
      type_of_body = analyze_instruction(instruction.body)
      @scope_stack.pop

      type_of_fun = FunctionType.new(*parameter_types, type_of_body)
      unify_type(type_of_fun, placeholder_var, instruction)

      @methods[current_object_type&.name_for_method_lookup][instruction.name] = type_of_fun.non_generic!
      instruction.type = type_of_fun

      type_of_fun
    end

    def analyze_if(instruction)
      condition = pop
      type_of_then = analyze_instruction(instruction.if_true)
      type_of_else = analyze_instruction(instruction.if_false)
      unify_type(type_of_then, type_of_else, instruction)
      instruction.type = type_of_then
    end

    def analyze_push_arg(instruction)
      type = scope.fetch(:parameter_types).fetch(instruction.index)
      @stack << type
      instruction.type = type
    end

    def analyze_push_array(instruction)
      members = pop(instruction.size)
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
        unify_type(a, b, instruction)
      end
      member_type = members.first || TypeVariable.new(self)
      member_type.non_generic!
      type_of_array = AryType.new(member_type)
      @stack << type_of_array
      instruction.type = type_of_array
    end

    def analyze_push_const(instruction)
      klass = @classes[instruction.name]
      @stack << klass
      instruction.type = klass
    end

    def analyze_push_false(instruction)
      @stack << BoolType
      instruction.type = BoolType
    end

    def analyze_push_int(instruction)
      @stack << IntType
      instruction.type = IntType
    end

    def analyze_push_nil(instruction)
      @stack << NilType
      instruction.type = NilType
    end

    def analyze_push_str(instruction)
      @stack << StrType
      instruction.type = StrType
    end

    def analyze_push_true(instruction)
      @stack << BoolType
      instruction.type = BoolType
    end

    def analyze_push_var(instruction)
      type = retrieve_var(instruction.name)
      raise UndefinedVariable, "undefined variable #{instruction.name.inspect}" unless type

      @stack << type
      instruction.type = type
    end

    def analyze_set_ivar(instruction)
      type = pop
      if (existing_type = vars[instruction.name])
        unify_type(existing_type, type, instruction)
        type = existing_type
      elsif type == NilType
        type = NillableType.new(TypeVariable.new(self))
      elsif instruction.nillable?
        type = NillableType.new(type)
      end
      current_class_type.attributes[instruction.name] = type
      instruction.type = type
    end

    def analyze_set_var(instruction)
      type = pop
      if (existing_type = vars[instruction.name])
        unify_type(existing_type, type, instruction)
        type = existing_type
      elsif type == NilType
        type = NillableType.new(TypeVariable.new(self))
      elsif instruction.nillable?
        type = NillableType.new(type)
      end
      vars[instruction.name] = type
      instruction.type = type
    end

    def retrieve_method(type, name)
      return unless (method = @methods.dig(type&.name_for_method_lookup, name))

      fresh_type(method)
    end

    def retrieve_var(name)
      return unless (type = vars[name])

      fresh_type(type)
    end

    def fresh_type(type, env = {})
      type = type.prune
      case type
      when TypeVariable
        if type.generic?
          env[type] ||= TypeVariable.new(self)
        else
          type
        end
      when TypeOperator
        type.dup.tap do |new_type|
          new_type.types = type.types.map { |t| fresh_type(t, env) }
        end
      end
    end

    def occurs_in_type?(type_var, type)
      type = type.prune
      case type
      when TypeVariable
        type_var == type
      when TypeOperator
        occurs_in_type_list?(type_var, type.types)
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

    def pop(count = nil)
      (count ? @stack.pop(count) : @stack.pop).tap do |value|
        raise 'Nothing on stack!' unless value
      end
    end

    def scope
      @scope_stack.last or raise('No scope!')
    end

    def vars
      scope.fetch(:vars)
    end

    def current_class_type
      scope.fetch(:class_type)
    end

    def current_object_type
      ObjectType.new(current_class_type) if current_class_type
    end

    def build_initial_methods
      array_type = TypeVariable.new(self)
      array = AryType.new(array_type)
      {
        nil => {
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
      }.tap do |hash|
        hash.default_proc = proc { |hash, key| hash[key] = {} }
      end
    end
  end
end
