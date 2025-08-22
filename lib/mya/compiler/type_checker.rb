class Compiler
  class TypeChecker
    MAX_CONSTRAINT_ITERATIONS = 100

    class Error < StandardError
    end
    class TypeClash < Error
    end
    class UndefinedMethod < Error
    end
    class UndefinedVariable < Error
    end

    class Type
      private

      def get_builtin_method_type(method_name, builtin_methods)
        return nil unless builtin_methods

        method_def = builtin_methods[method_name]
        return nil unless method_def

        if method_def.respond_to?(:call)
          method_def.call(self)
        else
          method_def
        end
      end
    end

    class Constraint
      def initialize(target, source, context: nil, context_data: {})
        @target = target
        @source = source
        @context = context
        @context_data = context_data
      end

      attr_reader :target, :source, :context, :context_data

      def solve!
        target_resolved = @target.resolve!
        source_resolved = @source.resolve!

        return false if target_resolved == source_resolved

        if target_resolved.is_a?(TypeVariable)
          target_resolved.instance = source_resolved
          return true
        elsif source_resolved.is_a?(TypeVariable)
          # This constraint will be solved later when the source type is resolved
          return false
        elsif can_coerce_to_option?(target_resolved, source_resolved)
          # Allow coercion to Option types:
          # - nil can be coerced to Option[T] (representing None)
          # - T can be coerced to Option[T] (representing Some(T))
          return false
        elsif can_use_as_boolean?(target_resolved, source_resolved)
          # Allow Option types to be used as boolean conditions
          return false
        elsif target_resolved.class != source_resolved.class ||
              (target_resolved.respond_to?(:name) && target_resolved.name != source_resolved.name)
          case @context
          when :if_condition
            line_info = @context_data[:line] ? " (line #{@context_data[:line]})" : ''
            raise TypeClash, "`if` condition must be Boolean, got #{source_resolved}#{line_info}"
          when :while_condition
            line_info = @context_data[:line] ? " (line #{@context_data[:line]})" : ''
            raise TypeClash, "`while` condition must be Boolean, got #{source_resolved}#{line_info}"
          when :if_branches
            line_info = @context_data[:line] ? " (line #{@context_data[:line]})" : ''
            raise TypeClash,
                  "one branch of `if` has type #{target_resolved} and the other has type #{source_resolved}#{line_info}"
          when :variable_reassignment
            var_name = @context_data[:variable_name]
            line_info = @context_data[:line] ? " (line #{@context_data[:line]})" : ''
            raise TypeClash,
                  "the variable `#{var_name}` has type #{target_resolved} already; you cannot change it to type #{source_resolved}#{line_info}"
          when :method_argument
            method_name = @context_data[:method_name]
            receiver_type = @context_data[:receiver_type]
            arg_index = @context_data[:arg_index]
            line_info = @context_data[:line] ? " (line #{@context_data[:line]})" : ''
            raise TypeClash,
                  "#{receiver_type}##{method_name} argument #{arg_index} has type #{target_resolved}, but you passed #{source_resolved}#{line_info}"
          else
            raise TypeClash, "cannot constrain #{target_resolved} to #{source_resolved}"
          end
        end

        return false
      end

      private

      def can_coerce_to_option?(target, source)
        return false unless target.is_a?(OptionType)

        # Allow nil to be coerced to Option[T] (None)
        return true if source.name == 'NilClass'

        # Allow T to be coerced to Option[T] (Some(T))
        return true if target.inner_type == source

        false
      end

      def can_use_as_boolean?(target, source)
        # Allow Option types to be used as boolean conditions
        return true if target.name == 'Boolean' && source.is_a?(OptionType)

        false
      end
    end

    class TypeVariable < Type
      def initialize(type_checker, context: nil, context_data: {})
        @type_checker = type_checker
        @id = @type_checker.next_variable_id
        @context = context
        @context_data = context_data
        @type_checker.register_type_variable(self)
      end

      attr_accessor :id, :instance, :context, :context_data

      def name
        @name ||= @type_checker.next_variable_name
      end

      def to_s = name.to_s

      def to_sym = name.to_sym

      def inspect = "TypeVariable(id = #{id}, name = #{name})"

      def resolve!
        return @instance.resolve! if @instance
        self
      end

      def get_method_type(method_name)
        resolved = resolve!
        return nil if resolved == self
        resolved.get_method_type(method_name)
      end

      def ==(other)
        return true if equal?(other)
        return @instance == other if @instance
        false
      end
    end

    class MethodCallConstraint < Constraint
      def initialize(target:, receiver_type:, method_name:, arg_types:, type_checker:, instruction:)
        @target = target
        @receiver_type = receiver_type
        @method_name = method_name
        @arg_types = arg_types
        @type_checker = type_checker
        @instruction = instruction
      end

      attr_reader :target, :receiver_type, :method_name, :arg_types

      def solve!
        receiver_resolved = @receiver_type.resolve!

        return false if receiver_resolved.is_a?(TypeVariable)

        method_type = receiver_resolved.get_method_type(@method_name)
        unless method_type
          # Method definitely not found on this resolved type
          raise UndefinedMethod, "undefined method `#{@method_name}` for #{receiver_resolved}"
        end

        # Store the full method type separately and set the return type as the main type
        @instruction.method_type = method_type
        @instruction.type = method_type.return_type

        expected_count = method_type.param_types.length
        actual_count = @arg_types.length
        if actual_count != expected_count
          raise ArgumentError,
                "method #{@method_name} expects #{expected_count} argument#{'s' if expected_count != 1}, got #{actual_count}"
        end

        @arg_types.each_with_index do |arg_type, index|
          constraint = Constraint.new(method_type.param_types[index], arg_type)
          @type_checker.add_constraint(constraint)
        end

        target_resolved = @target.resolve!
        return_resolved = method_type.return_type.resolve!

        return false if target_resolved == return_resolved

        if target_resolved.is_a?(TypeVariable)
          target_resolved.instance = return_resolved
          return true
        elsif return_resolved.is_a?(TypeVariable)
          return false
        elsif target_resolved.class != return_resolved.class ||
              (target_resolved.respond_to?(:name) && target_resolved.name != return_resolved.name)
          raise TypeClash, "Cannot constrain #{target_resolved} to #{return_resolved}"
        end

        return false
      end
    end

    class ClassType < Type
      def initialize(name, native: false)
        @name = name
        @methods = {}
        @instance_variables = {}
        @native = native
      end

      attr_reader :name

      def native? = @native

      def resolve! = self

      def to_s = name

      def get_method_type(method_name)
        return @methods[method_name] if @methods[method_name]

        method_type = get_builtin_method_type(method_name, BUILTIN_METHODS[name.to_sym])
        return method_type if method_type

        # Fall back to Object methods
        # FIXME: implement inheritance
        get_builtin_method_type(method_name, BUILTIN_METHODS[:Object])
      end

      def define_method_type(name, method_type)
        @methods[name] = method_type
      end

      def each_instance_variable(&block)
        @instance_variables.each(&block)
      end

      def get_instance_variable(name)
        @instance_variables[name]
      end

      def define_instance_variable(name, variable_type)
        @instance_variables[name] = variable_type
      end

      def resolve! = self
    end

    class MethodType < Type
      def initialize(self_type:, param_types:, return_type:, name:)
        @self_type = self_type
        @param_types = param_types
        @return_type = return_type
        @name = name
      end

      attr_reader :self_type, :param_types, :return_type, :name

      def resolve! = self

      def to_s
        resolved_params = param_types.map(&:resolve!)
        resolved_return = return_type.resolve!
        if resolved_params.empty?
          "#{self_type}##{name}() => #{resolved_return}"
        else
          param_str = resolved_params.map(&:to_s).join(', ')
          "#{self_type}##{name}(#{param_str}) => #{resolved_return}"
        end
      end
    end

    class ArrayType < Type
      def initialize(element_type)
        @element_type = element_type
      end

      attr_reader :element_type

      def resolve! = self

      def to_s = "Array[#{element_type.resolve!}]"

      def name = :Array

      def get_method_type(method_name)
        get_builtin_method_type(method_name, BUILTIN_METHODS[:Array])
      end

      def ==(other)
        return false unless other.is_a?(ArrayType)
        element_type == other.element_type
      end
    end

    class OptionType < Type
      def initialize(inner_type)
        @inner_type = inner_type
      end

      attr_reader :inner_type

      def resolve! = self

      def to_s = "Option[#{inner_type.resolve!}]"

      def name = :Option

      def get_method_type(method_name)
        get_builtin_method_type(method_name, BUILTIN_METHODS[:Option])
      end

      def ==(other)
        return false unless other.is_a?(OptionType)
        inner_type == other.inner_type
      end
    end

    BoolType = ClassType.new('Boolean', native: true)
    IntType = ClassType.new('Integer', native: true)
    NilType = ClassType.new('NilClass', native: true)
    StrType = ClassType.new('String')

    ObjectClass = ClassType.new('Object')

    class Scope
      def initialize(self_type:, method_params:, type_checker:)
        @self_type = self_type
        @variables = {}
        @method_params = method_params
        @type_checker = type_checker
      end

      attr_reader :self_type, :method_params

      def set_var_type(name, type)
        if (existing_type = @variables[name])
          constraint =
            Constraint.new(existing_type, type, context: :variable_reassignment, context_data: { variable_name: name })
          constraint.solve!
        else
          @variables[name] = type
        end
      end

      def get_var_type(name)
        @variables[name]
      end
    end

    def initialize
      @stack = []
      @scope_stack = [Scope.new(self_type: ObjectClass, method_params: [], type_checker: self)]
      @classes = {}
      @type_variables = []
      @constraints = []
    end

    def scope = @scope_stack.last

    def analyze(instruction)
      analyze_instruction(instruction)
      solve_constraints
      check_unresolved_types
    end

    def add_constraint(constraint)
      @constraints << constraint
    end

    def solve_constraints
      iteration = 0

      loop do
        iteration += 1
        if iteration > MAX_CONSTRAINT_ITERATIONS
          raise Error, "Constraint solving did not converge after #{MAX_CONSTRAINT_ITERATIONS} iterations"
        end

        break unless @constraints.any?(&:solve!)
      end
    end

    def register_type_variable(type_variable)
      @type_variables << type_variable
    end

    def check_unresolved_types
      @type_variables.each do |type_var|
        resolved = type_var.resolve!
        if resolved.is_a?(TypeVariable)
          error_message = generate_type_error_message(type_var)
          raise TypeError, error_message
        end
      end
    end

    def generate_type_error_message(type_var)
      if type_var.context == :method_parameter
        method_name = type_var.context_data[:method_name]
        param_name = type_var.context_data[:param_name]
        line = type_var.context_data[:line]
        "Not enough information to infer type of parameter `#{param_name}` for method `#{method_name}` (line #{line})"
      else
        "Not enough information to infer type of type variable '#{type_var.name}'"
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

    def analyze_array_of_instructions(array)
      array.each { |instruction| analyze_instruction(instruction) }
      @stack.last
    end

    def analyze_call(instruction)
      arg_types = pop_arguments(instruction.arg_count)
      receiver_type = @stack.pop
      result_type = TypeVariable.new(self)

      method_type = receiver_type.get_method_type(instruction.name)

      if method_type
        handle_known_method_call(instruction, method_type, arg_types, result_type, receiver_type)
      else
        handle_unknown_method_call(instruction, receiver_type, arg_types, result_type)
      end

      @stack << result_type
    end

    def analyze_class(instruction)
      class_type = ClassType.new(instruction.name.to_s)

      @classes[instruction.name.to_sym] = class_type

      new_method_type = MethodType.new(name: :new, self_type: class_type, param_types: [], return_type: class_type)
      class_type.define_method_type(:new, new_method_type)

      class_scope = Scope.new(self_type: class_type, method_params: [], type_checker: self)
      @scope_stack.push(class_scope)
      analyze_array_of_instructions(instruction.body)
      @scope_stack.pop

      instruction.type = class_type
    end

    def analyze_def(instruction)
      param_types =
        instruction.params.map.with_index do |param_name, index|
          # Check if there's a type annotation for this parameter
          if instruction.type_annotations && (type_name = instruction.type_annotations[param_name])
            resolve_type_from_name(type_name)
          else
            TypeVariable.new(
              self,
              context: :method_parameter,
              context_data: {
                method_name: instruction.name,
                param_name: param_name,
                line: instruction.line,
              },
            )
          end
        end

      method_scope = Scope.new(self_type: scope.self_type, method_params: param_types, type_checker: self)
      instruction.params.each_with_index do |param_name, index|
        method_scope.set_var_type(param_name, param_types[index])
      end

      @scope_stack.push(method_scope)
      return_type = analyze_array_of_instructions(instruction.body)
      @scope_stack.pop

      method_type = MethodType.new(name: instruction.name, self_type: scope.self_type, param_types:, return_type:)
      scope.self_type.define_method_type(instruction.name, method_type)

      if instruction.name == :initialize
        # update the new method to have the same parameters
        new_method_type =
          MethodType.new(name: :new, self_type: scope.self_type, param_types:, return_type: scope.self_type)
        scope.self_type.define_method_type(:new, new_method_type)
      end

      instruction.type = method_type
    end

    def analyze_if(instruction)
      condition_type = @stack.pop
      add_constraint(
        Constraint.new(BoolType, condition_type, context: :if_condition, context_data: { line: instruction.line }),
      )

      if_true_type = analyze_array_of_instructions(instruction.if_true)
      if_false_type = analyze_array_of_instructions(instruction.if_false)

      if instruction.used
        result_type = TypeVariable.new(self)
        add_constraint(
          Constraint.new(result_type, if_true_type, context: :if_branches, context_data: { line: instruction.line }),
        )
        add_constraint(
          Constraint.new(result_type, if_false_type, context: :if_branches, context_data: { line: instruction.line }),
        )
        instruction.type = result_type
        @stack << result_type
      else
        instruction.type = NilType
        @stack << NilType
      end
    end

    def analyze_instruction(instruction)
      return analyze_array_of_instructions(instruction) if instruction.is_a?(Array)

      send("analyze_#{instruction.instruction_name}", instruction)
    end

    def analyze_pop(instruction)
      instruction.type = NilType
      @stack.pop
    end

    def analyze_push_arg(instruction)
      if scope.method_params && instruction.index < scope.method_params.size
        param_type = scope.method_params[instruction.index]
        @stack << param_type
        instruction.type = param_type
      else
        type_var = TypeVariable.new(self)
        @stack << type_var
        instruction.type = type_var
      end
    end

    def analyze_push_array(instruction)
      element_types = []
      instruction.size.times { element_types.unshift(@stack.pop) }

      if element_types.empty?
        element_type = TypeVariable.new(self)
        array_type = ArrayType.new(element_type)
      else
        first_element_type = element_types.first
        element_types[1..].each do |element_type|
          if !types_compatible?(first_element_type, element_type)
            raise TypeClash,
                  "the array contains type #{first_element_type} but you are trying to push type #{element_type}"
          end
        end

        array_type = ArrayType.new(first_element_type)
      end

      instruction.type = array_type
      @stack << array_type
    end

    def analyze_push_const(instruction)
      class_type = @classes[instruction.name]
      raise UndefinedVariable, "undefined constant #{instruction.name}" unless class_type

      @stack << class_type
      instruction.type = class_type
    end

    def analyze_push_false(instruction)
      @stack << BoolType
      instruction.type = BoolType
    end

    def analyze_push_int(instruction)
      @stack << IntType
      instruction.type = IntType
    end

    def analyze_push_ivar(instruction)
      class_type = scope.self_type

      var_type = class_type.get_instance_variable(instruction.name)
      unless var_type
        var_type = NilType
        class_type.define_instance_variable(instruction.name, var_type)
      end

      @stack << var_type
      instruction.type = var_type
    end

    def analyze_push_nil(instruction)
      @stack << NilType
      instruction.type = NilType
    end

    def analyze_push_self(instruction)
      @stack << scope.self_type
      instruction.type = scope.self_type
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
      value_type = scope.get_var_type(instruction.name)
      raise UndefinedVariable, "undefined local variable or method `#{instruction.name}`" unless value_type
      @stack << value_type
      instruction.type = value_type
    end

    def analyze_set_ivar(instruction)
      value_type = @stack.pop

      class_type = scope.self_type

      if instruction.type_annotation
        annotated_type = resolve_type_from_name(instruction.type_annotation)

        if (existing_type = class_type.get_instance_variable(instruction.name))
          constraint =
            Constraint.new(
              existing_type,
              annotated_type,
              context: :type_annotation_mismatch,
              context_data: {
                variable_name: instruction.name,
                annotation: instruction.type_annotation,
              },
            )
          add_constraint(constraint)
        else
          class_type.define_instance_variable(instruction.name, annotated_type)
        end

        constraint =
          Constraint.new(
            annotated_type,
            value_type,
            context: :type_annotation_assignment,
            context_data: {
              variable_name: instruction.name,
              annotation: instruction.type_annotation,
            },
          )
        add_constraint(constraint)

        @stack << annotated_type
        instruction.type = annotated_type
      else
        existing_type = class_type.get_instance_variable(instruction.name)
        if existing_type
          constraint =
            Constraint.new(
              existing_type,
              value_type,
              context: :variable_reassignment,
              context_data: {
                variable_name: instruction.name,
              },
            )
          add_constraint(constraint)
        else
          class_type.define_instance_variable(instruction.name, value_type)
        end

        @stack << (existing_type || value_type)
        instruction.type = existing_type || value_type
      end
    end

    def analyze_set_var(instruction)
      value_type = @stack.pop

      if instruction.type_annotation
        annotated_type = resolve_type_from_name(instruction.type_annotation)
        add_constraint(
          Constraint.new(
            annotated_type,
            value_type,
            context: :variable_type_annotation,
            context_data: {
              name: instruction.name,
              line: instruction.line,
            },
          ),
        )
        scope.set_var_type(instruction.name, annotated_type)
        instruction.type = annotated_type
      else
        existing_type = scope.get_var_type(instruction.name)
        scope.set_var_type(instruction.name, value_type)
        instruction.type = existing_type || value_type
      end
    end

    def analyze_while(instruction)
      condition_type = analyze_array_of_instructions(instruction.condition)
      add_constraint(
        Constraint.new(BoolType, condition_type, context: :while_condition, context_data: { line: instruction.line }),
      )

      analyze_array_of_instructions(instruction.body)

      instruction.type = NilType
      @stack << NilType
    end

    def resolve_type_from_name(type_spec)
      # Handle generic types like { generic: :Option, inner: :String }
      if type_spec.is_a?(Hash) && type_spec[:generic]
        case type_spec[:generic]
        when :Option
          inner_type = resolve_type_from_name(type_spec[:inner])
          if inner_type.native?
            raise NotImplementedError,
                  "Option[#{inner_type.name}] is not supported since #{inner_type.name} is a native type"
          end

          OptionType.new(inner_type)
        when :Array
          inner_type = resolve_type_from_name(type_spec[:inner])
          ArrayType.new(inner_type)
        else
          raise UndefinedVariable, "undefined generic type #{type_spec[:generic]}"
        end
      else
        # Handle simple types
        case type_spec
        when :Integer, :Int
          IntType
        when :String, :Str
          StrType
        when :Boolean, :Bool
          BoolType
        when :NilClass, :Nil
          NilType
        else
          # Check if it's a defined class
          @classes[type_spec] || raise(UndefinedVariable, "undefined type #{type_spec}")
        end
      end
    end

    def pop_arguments(arg_count)
      arg_types = []
      arg_count.times { arg_types.unshift(@stack.pop) }
      arg_types
    end

    def handle_known_method_call(instruction, method_type, arg_types, result_type, receiver_type)
      validate_argument_count(instruction.name, method_type.param_types.length, instruction.arg_count)
      create_argument_constraints(method_type, arg_types, instruction.name, receiver_type)
      add_constraint(Constraint.new(result_type, method_type.return_type))
      # Store the full method type separately and set the return type as the main type
      instruction.method_type = method_type
      instruction.type = method_type.return_type
    end

    def handle_unknown_method_call(instruction, receiver_type, arg_types, result_type)
      method_call_constraint =
        MethodCallConstraint.new(
          target: result_type,
          receiver_type:,
          method_name: instruction.name,
          arg_types:,
          type_checker: self,
          instruction:,
        )
      add_constraint(method_call_constraint)
      instruction.type = result_type
    end

    def validate_argument_count(method_name, expected_count, actual_count)
      return if actual_count == expected_count

      raise ArgumentError,
            "method #{method_name} expects #{expected_count} argument#{'s' if expected_count != 1}, got #{actual_count}"
    end

    def create_argument_constraints(method_type, arg_types, method_name, receiver_type)
      arg_types.each_with_index do |arg_type, index|
        next unless index < method_type.param_types.length

        add_constraint(
          Constraint.new(
            method_type.param_types[index],
            arg_type,
            context: :method_argument,
            context_data: {
              method_name: method_name,
              receiver_type: receiver_type,
              arg_index: index + 1,
            },
          ),
        )
      end
    end

    def types_compatible?(type1, type2)
      resolved1 = type1.resolve!
      resolved2 = type2.resolve!

      return true if resolved1.is_a?(TypeVariable) || resolved2.is_a?(TypeVariable)

      resolved1 == resolved2
    end

    BUILTIN_METHODS = {
      Array: {
        :first => ->(self_type) do
          MethodType.new(self_type:, param_types: [], return_type: self_type.element_type, name: :first)
        end,
        :last => ->(self_type) do
          MethodType.new(self_type:, param_types: [], return_type: self_type.element_type, name: :last)
        end,
        :<< => ->(self_type) do
          MethodType.new(self_type:, param_types: [self_type.element_type], return_type: self_type, name: :<<)
        end,
      },
      Option: {
        is_some: ->(self_type) { MethodType.new(self_type:, param_types: [], return_type: BoolType, name: :is_some) },
        is_none: ->(self_type) { MethodType.new(self_type:, param_types: [], return_type: BoolType, name: :is_none) },
        value!: ->(self_type) do
          MethodType.new(self_type:, param_types: [], return_type: self_type.inner_type, name: :value!)
        end,
        value_or: ->(self_type) do
          MethodType.new(
            self_type:,
            param_types: [self_type.inner_type],
            return_type: self_type.inner_type,
            name: :value_or,
          )
        end,
      },
      Integer: {
        :+ => MethodType.new(self_type: IntType, param_types: [IntType], return_type: IntType, name: :+),
        :- => MethodType.new(self_type: IntType, param_types: [IntType], return_type: IntType, name: :-),
        :* => MethodType.new(self_type: IntType, param_types: [IntType], return_type: IntType, name: :*),
        :/ => MethodType.new(self_type: IntType, param_types: [IntType], return_type: IntType, name: :/),
        :== => MethodType.new(self_type: IntType, param_types: [IntType], return_type: BoolType, name: :==),
        :< => MethodType.new(self_type: IntType, param_types: [IntType], return_type: BoolType, name: :<),
        :> => MethodType.new(self_type: IntType, param_types: [IntType], return_type: BoolType, name: :>),
        :<= => MethodType.new(self_type: IntType, param_types: [IntType], return_type: BoolType, name: :<=),
        :>= => MethodType.new(self_type: IntType, param_types: [IntType], return_type: BoolType, name: :>=),
        :to_s => MethodType.new(self_type: IntType, param_types: [], return_type: StrType, name: :to_s),
      },
      String: {
        :+ => MethodType.new(self_type: StrType, param_types: [StrType], return_type: StrType, name: :+),
        :== => MethodType.new(self_type: StrType, param_types: [StrType], return_type: BoolType, name: :==),
        :length => MethodType.new(self_type: StrType, param_types: [], return_type: IntType, name: :length),
      },
      Boolean: {
        :== => MethodType.new(self_type: BoolType, param_types: [BoolType], return_type: BoolType, name: :==),
        :to_s => MethodType.new(self_type: BoolType, param_types: [], return_type: StrType, name: :to_s),
      },
      Object: {
        puts: MethodType.new(self_type: ObjectClass, param_types: [StrType], return_type: IntType, name: :puts),
      },
    }.freeze
  end
end
