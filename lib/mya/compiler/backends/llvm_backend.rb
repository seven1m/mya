require 'llvm/core'
require 'llvm/execution_engine'
require 'llvm/linker'
require_relative 'llvm_backend/rc_builder'
require_relative 'llvm_backend/array_builder'
require_relative 'llvm_backend/object_builder'
require_relative 'llvm_backend/string_builder'

class Compiler
  module Backends
    class LLVMBackend
      class LLVMClass
        attr_reader :struct, :ivar_map, :superclass

        def initialize(struct, ivar_map, superclass: nil)
          @struct = struct
          @ivar_map = ivar_map
          @superclass = superclass
        end

        def find_ivar_index(ivar_name)
          return @ivar_map[ivar_name] if @ivar_map.key?(ivar_name)
          @superclass&.find_ivar_index(ivar_name)
        end
      end

      LIB_PATH = File.expand_path('../../../../build/lib.ll', __dir__)

      def initialize(instructions, dump: false)
        @instructions = instructions
        @stack = []
        @scope_stack = [{ vars: {} }]
        @call_stack = []
        @if_depth = 0
        @methods = build_methods
        @classes = {}
        @dump = dump
        @lib = LLVM::Module.parse_ir(LIB_PATH)
      end

      attr_reader :instructions

      def run
        build_main_module
        execute(@entry)
      end

      def dump_ir_to_file(path)
        build_main_module
        File.write(path, @module.to_s)
      end

      private

      def execute(fn)
        LLVM.init_jit

        engine = LLVM::JITCompiler.new(@module)
        value = engine.run_function(fn)
        return_value = llvm_type_to_ruby(value, @return_type)
        engine.dispose

        return_value
      end

      def build_main_module
        @module = LLVM::Module.new('llvm')
        @return_type = @instructions.last.type!
        @entry = @module.functions.add('main', [], llvm_type(@return_type))
        build_main_function(@entry, @instructions)
        @lib.link_into(@module)
        @module.dump if @dump || !@module.valid?
        @module.verify!
      end

      def build_main_function(function, instructions)
        function.basic_blocks.append.build do |builder|
          unused_for_now = LLVM::Int # need at least one struct member
          main_obj_struct = LLVM.Struct(unused_for_now, 'main')
          @main_obj = ObjectBuilder.new(builder:, mod: @module, struct: main_obj_struct).to_ptr
          @scope_stack << { function:, vars: {}, self_obj: @main_obj }
          build_instructions(function, builder, instructions) { |return_value| builder.ret return_value }
          @scope_stack.pop
        end
      end

      def build_instructions(function, builder, instructions)
        instructions.each { |instruction| build(instruction, function, builder) }
        return_value = @stack.pop
        yield return_value if block_given?
      end

      def build(instruction, function, builder)
        send("build_#{instruction.instruction_name}", instruction, function, builder)
      end

      def build_call(instruction, _function, builder)
        args = @stack.pop(instruction.arg_count)
        receiver = @stack.pop
        receiver_type = instruction.method_type.self_type
        args.unshift(receiver)
        name = instruction.name
        fn = @methods.dig(receiver_type.name.to_sym, name.to_sym) or raise(NoMethodError, "Method '#{name}' not found")
        fn.respond_to?(:call) ? @stack << fn.call(builder:, instruction:, args:) : @stack << builder.call(fn, *args)
      end

      def build_class(instruction, function, builder)
        name = instruction.name

        superclass_llvm = nil
        if instruction.superclass
          superclass_llvm = @classes[instruction.superclass.to_sym]
          raise "Superclass #{instruction.superclass} not found" unless superclass_llvm
        end

        ivar_map = {}
        attr_types = []

        # First, add superclass instance variables if any
        if superclass_llvm
          superclass_llvm.ivar_map.each do |ivar_name, index|
            ivar_map[ivar_name] = attr_types.size
            attr_types << superclass_llvm.struct.element_types[index]
          end
        end

        # Then add this class's own instance variables
        instruction.type!.each_instance_variable.with_index do |(ivar_name, ivar_type), _|
          # Skip if already inherited from superclass
          next if ivar_map.key?(ivar_name)

          ivar_map[ivar_name] = attr_types.size
          attr_types << llvm_type(ivar_type)
        end

        # Ensure the struct has at least one field
        attr_types << LLVM::Int8 if attr_types.empty?

        struct = LLVM.Struct(*attr_types, name.to_s)
        llvm_class = @classes[name.to_sym] = LLVMClass.new(struct, ivar_map, superclass: superclass_llvm)

        @methods[name.to_sym] = if superclass_llvm
          @methods[instruction.superclass.to_sym].dup
        else
          {}
        end
        @methods[name.to_sym][:new] = method(:build_call_new)

        @scope_stack << { function:, vars: {}, self_obj: llvm_class }
        build_instructions(function, builder, instruction.body)
        @scope_stack.pop
      end

      def build_def(instruction, _function, _builder)
        name = instruction.name
        param_types = (0...instruction.params.size).map { |i| llvm_type(instruction.body.fetch(i * 2).type!) }
        receiver_type = instruction.receiver_type
        param_types.unshift(llvm_type(receiver_type))
        return_type = llvm_type(instruction.return_type.resolve!)
        @methods[receiver_type.name.to_sym] ||= {}
        @methods[receiver_type.name.to_sym][name.to_sym] = fn = @module.functions.add(name, param_types, return_type)

        llvm_class = @classes[receiver_type.name.to_sym]

        fn.basic_blocks.append.build do |builder|
          @scope_stack << { function: fn, vars: {}, self_obj: fn.params.first, llvm_class: }
          build_instructions(fn, builder, instruction.body) { |return_value| builder.ret return_value }
          @scope_stack.pop
        end
      end

      def build_if(instruction, function, builder)
        result = builder.alloca(llvm_type(instruction.type!), "if_line_#{instruction.line}")
        then_block = function.basic_blocks.append
        else_block = function.basic_blocks.append
        result_block = function.basic_blocks.append
        condition = @stack.pop

        # Convert Option types to boolean for conditionals
        if condition.type == RcBuilder.pointer_type
          # Option type: check if it's not null (Some vs None)
          condition = builder.icmp(:ne, condition, RcBuilder.pointer_type.null_pointer)
        end

        builder.cond(condition, then_block, else_block)
        then_block.build do |then_builder|
          build_instructions(function, then_builder, instruction.if_true) do |value|
            value = RcBuilder.pointer_type.null_pointer if value.nil?
            then_builder.store(value, result)
            then_builder.br(result_block)
          end
        end
        else_block.build do |else_builder|
          build_instructions(function, else_builder, instruction.if_false) do |value|
            value = RcBuilder.pointer_type.null_pointer if value.nil?
            else_builder.store(value, result)
            else_builder.br(result_block)
          end
        end
        builder.position_at_end(result_block)
        @stack << builder.load(result)
      end

      def build_while(instruction, function, builder)
        condition_block = function.basic_blocks.append
        body_block = function.basic_blocks.append
        exit_block = function.basic_blocks.append

        builder.br(condition_block)

        condition_block.build do |condition_builder|
          build_instructions(function, condition_builder, instruction.condition) do |condition_value|
            condition_builder.cond(condition_value, body_block, exit_block)
          end
        end

        body_block.build do |body_builder|
          build_instructions(function, body_builder, instruction.body)
          body_builder.br(condition_block) # Loop back to condition
        end

        builder.position_at_end(exit_block)

        # While loops always return nil
        @stack << RcBuilder.pointer_type.null_pointer
      end

      def build_pop(_instruction, _function, _builder)
        @stack.pop
      end

      def build_push_arg(instruction, _function, _builder)
        function = @scope_stack.last.fetch(:function)
        @stack << function.params[instruction.index + 1] # receiver is always 0
      end

      def build_push_array(instruction, _function, builder)
        @stack << build_array(builder, instruction)
      end

      def build_push_const(instruction, _function, _builder)
        llvm_class = @classes.fetch(instruction.name)
        @stack << llvm_class.struct
      end

      def build_push_false(_instruction, _function, _builder)
        @stack << LLVM::FALSE
      end

      def build_push_int(instruction, _function, _builder)
        @stack << LLVM.Int(instruction.value)
      end

      def build_push_nil(_instruction, _function, _builder)
        @stack << RcBuilder.pointer_type.null_pointer
      end

      def build_push_self(_instruction, _function, _builder)
        @stack << self_obj
      end

      def build_push_str(instruction, _function, builder)
        @stack << build_string(builder, instruction.value)
      end

      def build_push_true(_instruction, _function, _builder)
        @stack << LLVM::TRUE
      end

      def build_push_var(instruction, _function, builder)
        variable = vars.fetch(instruction.name)
        @stack << builder.load(variable)
      end

      def build_push_ivar(instruction, _function, builder)
        ivar_name = instruction.name
        llvm_class = scope.fetch(:llvm_class)
        field_index = llvm_class.find_ivar_index(ivar_name)
        raise "Instance variable #{ivar_name} not found" unless field_index

        self_ptr = scope.fetch(:function).params.first
        struct_type = llvm_class.struct
        field_ptr = builder.struct_gep2(struct_type, self_ptr, field_index, "ivar_#{ivar_name}")
        expected_type = llvm_type(instruction.type!)
        value = builder.load2(expected_type, field_ptr, "load_#{ivar_name}")
        @stack << value
      end

      def build_set_ivar(instruction, _function, builder)
        ivar_name = instruction.name
        llvm_class = scope.fetch(:llvm_class)
        field_index = llvm_class.find_ivar_index(ivar_name)
        raise "Instance variable #{ivar_name} not found" unless field_index

        value = @stack.last
        self_ptr = scope.fetch(:function).params.first
        struct_type = llvm_class.struct
        field_ptr = builder.struct_gep2(struct_type, self_ptr, field_index, "ivar_#{ivar_name}")
        builder.store(value, field_ptr)
      end

      def build_set_var(instruction, _function, builder)
        value = @stack.pop
        if vars[instruction.name]
          builder.store(value, vars[instruction.name])
        else
          variable = builder.alloca(value.type, "var_#{instruction.name}")
          builder.store(value, variable)
          vars[instruction.name] = variable
        end
      end

      def scope
        @scope_stack.last
      end

      def vars
        scope.fetch(:vars)
      end

      def self_obj
        scope.fetch(:self_obj)
      end

      def llvm_type(type)
        case type.name
        when 'Boolean'
          LLVM::Int1.type
        when 'Integer'
          LLVM::Int32.type
        when 'Option'
          # Option types are represented as pointers (null for None, non-null for Some)
          RcBuilder.pointer_type
        else
          RcBuilder.pointer_type
        end
      end

      def llvm_type_to_ruby(value, type)
        case type.name
        when 'Boolean', 'Integer', 'NilClass'
          read_llvm_type_as_ruby(value, type)
        when 'String'
          ptr = read_rc_pointer(value)
          read_llvm_type_as_ruby(ptr, type)
        else
          raise "Unknown type: #{type.inspect}"
        end
      end

      def read_rc_pointer(value)
        rc_ptr = value.to_ptr.read_pointer
        # NOTE: this works because the ptr is the first field of the RC struct.
        rc_ptr.read_pointer
      end

      def read_llvm_type_as_ruby(value, type)
        case type.name
        when 'Boolean'
          value.to_i == -1
        when 'Integer'
          value.to_i
        when 'String'
          value.read_string
        when 'NilClass'
          nil
        else
          raise "Unknown type: #{type.inspect}"
        end
      end

      def build_string(builder, value)
        string = StringBuilder.new(builder:, mod: @module, string: value)
        string.to_ptr
      end

      def build_array(builder, instruction)
        elements = @stack.pop(instruction.size)
        array_type = instruction.type!
        element_type = llvm_type(array_type.element_type)
        array = ArrayBuilder.new(builder:, mod: @module, element_type:, elements:)
        array.to_ptr
      end

      def fn_puts
        @fn_puts ||= @module.functions.add('puts_string', [RcBuilder.pointer_type], LLVM::Int32)
      end

      def fn_int_to_string
        @fn_int_to_string ||= @module.functions.add('int_to_string', [LLVM::Int32], RcBuilder.pointer_type)
      end

      def fn_bool_to_string
        @fn_bool_to_string ||= @module.functions.add('bool_to_string', [LLVM::Int1], RcBuilder.pointer_type)
      end

      def fn_string_concat
        @fn_string_concat ||=
          @module.functions.add(
            'string_concat',
            [RcBuilder.pointer_type, RcBuilder.pointer_type],
            RcBuilder.pointer_type,
          )
      end

      def build_methods
        {
          Array: {
            first: ->(builder:, instruction:, args:) do
              element_type = llvm_type(instruction.type!)
              array = ArrayBuilder.new(ptr: args.first, builder:, mod: @module, element_type:)
              array.first
            end,
            last: ->(builder:, instruction:, args:) do
              element_type = llvm_type(instruction.type!)
              array = ArrayBuilder.new(ptr: args.first, builder:, mod: @module, element_type:)
              array.last
            end,
            '<<': ->(builder:, args:, **) do
              element_type = args.last.type
              array = ArrayBuilder.new(ptr: args.first, builder:, mod: @module, element_type:)
              array.push(args.last)
            end,
          },
          Integer: {
            '+': ->(builder:, args:, **) { builder.add(*args) },
            '-': ->(builder:, args:, **) { builder.sub(*args) },
            '*': ->(builder:, args:, **) { builder.mul(*args) },
            '/': ->(builder:, args:, **) { builder.sdiv(*args) },
            '==': ->(builder:, args:, **) { builder.icmp(:eq, *args) },
            '<': ->(builder:, args:, **) { builder.icmp(:slt, *args) },
            '>': ->(builder:, args:, **) { builder.icmp(:sgt, *args) },
            to_s: ->(builder:, args:, **) { builder.call(fn_int_to_string, args.first) },
          },
          String: {
            '+': ->(builder:, args:, **) { builder.call(fn_string_concat, *args) },
            '==': ->(builder:, args:, **) do
              raise NotImplementedError, 'String comparison not yet implemented in LLVM backend'
            end,
          },
          Boolean: {
            '==': ->(builder:, args:, **) { builder.icmp(:eq, *args) },
            to_s: ->(builder:, args:, **) { builder.call(fn_bool_to_string, args.first) },
          },
          Object: {
            puts: ->(builder:, args:, **) do
              arg = args[1]
              builder.call(fn_puts, arg)
            end,
          },
          Option: {
            value!: ->(builder:, args:, **) do
              # For Option types, the value is the pointer itself (when not null)
              # This works for Option[String] since strings are already pointers
              # Note: Option[Integer] is not supported - integers are native types
              args.first
            end,
            is_some: ->(builder:, args:, **) do
              # Check if the Option pointer is not null
              builder.icmp(:ne, args.first, RcBuilder.pointer_type.null_pointer)
            end,
            is_none: ->(builder:, args:, **) do
              # Check if the Option pointer is null
              builder.icmp(:eq, args.first, RcBuilder.pointer_type.null_pointer)
            end,
          },
        }
      end

      def build_call_new(builder:, args:, instruction:, **)
        struct = args.first
        instance = ObjectBuilder.new(builder:, mod: @module, struct:).to_ptr

        class_name = instruction.method_type.self_type.name.to_sym
        if (initialize_fn = @methods.dig(class_name, :initialize))
          initialize_args = [instance] + args[1..]
          builder.call(initialize_fn, *initialize_args)
        end

        instance
      end

      # usage:
      # diff(@module.functions[11].to_s, @module.functions[0].to_s)
      def diff(expected, actual)
        File.write('/tmp/actual.ll', actual)
        File.write('/tmp/expected.ll', expected)
        puts `diff -y -W 134 /tmp/expected.ll /tmp/actual.ll`
      end
    end
  end
end
