require 'set'

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

    def to_s = name.to_s

    def to_sym = name.to_sym

    def inspect = "TypeVariable(id = #{id})"

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
      "#<TypeOperator name=#{name} types=[#{types.join(', ')}]>"
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

    def contains?(other_type)
      raise 'expected TypeVariable' unless other_type.is_a?(TypeVariable)

      types.any? do |candidate|
        case candidate
        when TypeVariable
          candidate == other_type
        when TypeOperator
          candidate.contains?(other_type)
        else
          raise "Unexpected type: #{candidate.inspect}"
        end
      end
    end

    def evaluated_type = self
  end

  class MethodType < TypeOperator
    def initialize(*types)
      super('->', types)
    end

    def to_s
      arg_types = types[0...-1]
      return_type = types.last
      "([#{arg_types.join(', ')}] -> #{return_type})"
    end

    def inspect
      "#<MethodType types=[#{types.map(&:inspect).join(', ')}]>"
    end

    def evaluated_type = types.last
  end

  # This just exists for debugging purposes.
  # We could easily use MethodType, but would lose some context when puts debugging. :-)
  class CallType < MethodType
    def inspect
      super.sub('MethodType', 'CallType')
    end
  end

  class UnionType < TypeOperator
    def initialize(*types)
      super('union', types)
    end

    def to_s
      "(#{types.join(' | ')})"
    end

    def select_type(other_type)
      types.detect do |candidate|
        candidate.name == other_type.name && candidate.types.size == other_type.types.size
      end
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

    def inspect = "#<ClassType class_name=#{@class_name.inspect}>"

    def name_for_method_lookup = @class_name
  end

  class ObjectType < TypeOperator
    def initialize(klass)
      super('object', [])
      @klass = klass
    end

    attr_reader :klass

    def to_s = "(object #{@klass.class_name})"

    def inspect = "#<ObjectType klass=#{klass.inspect}>"

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

    MainClass = ClassType.new('main')
    MainObject = ObjectType.new(MainClass)

    def initialize
      @stack = []
      @scope_stack = [{ vars: {}, self_type: MainClass }]
      @classes = {}
      @calls_to_unify = []
      @methods = build_initial_methods
    end

    def analyze(instruction)
      analyze_instruction(instruction).prune
      @calls_to_unify.each do |call|
        type_of_receiver = call.fetch(:type_of_receiver).prune
        analyze_call_with_known_receiver(**call, type_of_receiver:)
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
      else
        type_of_receiver = current_object_type
      end

      type_of_return = TypeVariable.new(self)
      type_of_call = CallType.new(type_of_receiver, *type_of_args, type_of_return)

      if type_of_receiver.is_a?(TypeVariable)
        # We cannot unify yet, since we don't know the receiver type.
        # Save this call for later unification.
        @calls_to_unify << { type_of_receiver:, type_of_call:, instruction: }
        instruction.type = type_of_call
        @stack << type_of_return
        return type_of_return
      end

      analyze_call_with_known_receiver(type_of_receiver:, type_of_call:, instruction:)

      instruction.type = type_of_call
      @stack << type_of_return
      type_of_return
    end

    def analyze_call_with_known_receiver(type_of_receiver:, type_of_call:, instruction:)
      type_of_method = retrieve_method(type_of_receiver, instruction.name)
      raise UndefinedMethod, "undefined method #{instruction.name} for type #{type_of_receiver.inspect}" unless type_of_method

      unify_type(type_of_method, type_of_call, instruction)
    end

    def analyze_class(instruction)
      class_type = @classes[instruction.name] = ClassType.new(instruction.name)
      object_type = ObjectType.new(class_type)
      @methods[class_type.name_for_method_lookup] = {
        new: MethodType.new(class_type, object_type)
      }

      @scope_stack << { vars: {}, self_type: class_type }
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

      @scope_stack << scope.merge(parameter_types:, vars: new_vars)
      type_of_body = analyze_instruction(instruction.body)
      @scope_stack.pop

      type_of_method = MethodType.new(current_object_type, *parameter_types, type_of_body)
      unify_type(type_of_method, placeholder_var, instruction)

      @methods[current_object_type&.name_for_method_lookup][instruction.name] = type_of_method.non_generic!
      instruction.type = type_of_method

      type_of_method
    end

    def analyze_if(instruction)
      condition = pop
      type_of_then = analyze_instruction(instruction.if_true)
      type_of_else = analyze_instruction(instruction.if_false)
      unify_type(type_of_then, type_of_else, instruction)
      instruction.type = type_of_then
    end

    def analyze_pop(instruction)
      instruction.type = NilType
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

    def unify_type(a, b, instruction = nil)
      a = a.prune
      b = b.prune
      case a
      when TypeVariable
        unify_type_variable(a, b, instruction)
      when TypeOperator
        unify_type_operator(a, b, instruction)
      else
        raise "Unknown type: #{a.inspect}"
      end
    end

    def unify_type_variable(a, b, instruction)
      return if a == b

      if b.is_a?(TypeOperator) && b.contains?(a)
        raise RecursiveUnification, "recursive unification: #{b} contains #{a}"
      else
        a.instance = b
      end
    end

    def unify_type_operator(a, b, instruction)
      case b
      when TypeVariable
        unify_type_variable(b, a, instruction)
      when TypeOperator
        case a
        when UnionType
          unify_union_type(a, b, instruction)
        when NillableType
          unify_nillable_type(a, b, instruction)
        else
          unify_type_operator_with_type_operator(a, b, instruction)
        end
      else
        raise "Unknown type: #{b.inspect}"
      end
    end

    def unify_nillable_type(a, b, instruction)
      return if b.name == 'nil'

      if b.is_a?(NillableType)
        unify_type(a.types.first, b.types.first, instruction)
      elsif a.types.first.is_a?(TypeVariable)
        unify_type(a.types.first, b)
      else
        raise_type_clash_error(a, b, instruction)
      end
    end

    def unify_union_type(a, b, instruction)
      unless (selected = a.select_type(b))
        raise_type_clash_error(a, b, instruction)
      end

      unify_type(selected, b, instruction)
    end

    # FIXME: this won't work on ObjectType since we don't compare klass.class_name.
    # Need a test to prove that this breaks for two separate classes.
    def unify_type_operator_with_type_operator(a, b, instruction)
      unless a.name == b.name && a.types.size == b.types.size
        raise_type_clash_error(a, b, instruction)
      end

      begin
        unify_args(a.types, b.types, instruction)
      rescue TypeClash
        # We want to produce an error message for the whole instruction, e.g.
        # call, array, etc. -- not for an individual type inside.
        raise_type_clash_error(a, b, instruction)
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
      if count
        values = @stack.pop(count)
        raise "Not enough values on stack! (Expected #{count} but got #{values.inspect})" unless values.size == count
        return values
      end

      value = @stack.pop
      raise 'Nothing on stack!' unless value
      value
    end

    def scope
      @scope_stack.last or raise('No scope!')
    end

    def vars
      scope.fetch(:vars)
    end

    def current_class_type
      scope.fetch(:self_type)
    end

    def current_object_type
      ObjectType.new(current_class_type) if current_class_type
    end

    def build_initial_methods
      array_type = TypeVariable.new(self)
      array = AryType.new(array_type)
      {
        '(object main)' => {
          puts: MethodType.new(MainObject, UnionType.new(IntType, StrType), IntType),
        },
        'int' => {
          zero?: MethodType.new(IntType, BoolType),
          "+": MethodType.new(IntType, IntType, IntType),
          "==": MethodType.new(IntType, IntType, BoolType),
          "-": MethodType.new(IntType, IntType, IntType),
          "*": MethodType.new(IntType, IntType, IntType),
          "/": MethodType.new(IntType, IntType, IntType),
        },
        'array' => {
          nth: MethodType.new(array, IntType, array_type),
          first: MethodType.new(array, array_type),
          last: MethodType.new(array, array_type),
          '<<': MethodType.new(array, array_type, array),
          push: MethodType.new(array, array_type, array_type),
        },
      }.tap do |hash|
        hash.default_proc = proc { |hash, key| hash[key] = {} }
      end
    end
  end
end
