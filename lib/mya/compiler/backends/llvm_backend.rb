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
        build_module
        execute(@entry)
      end

      def dump_ir_to_file(path)
        build_module
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

      def build_module
        @module = LLVM::Module.new('llvm')
        @return_type = @instructions.last.type!
        @entry = @module.functions.add('main', [], llvm_type(@return_type))
        build_function(@entry, @instructions)
        @lib.link_into(@module)
        #@module.dump if @dump || !@module.valid?
        @module.verify!
      end

      def build_function(function, instructions)
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
        receiver_type = instruction.type!.types.first
        args.unshift(receiver)
        name = instruction.name
        fn = @methods.dig(receiver_type.name_for_method_lookup, name) or
          raise(NoMethodError, "Method '#{name}' not found")
        fn.respond_to?(:call) ? @stack << fn.call(builder:, instruction:, args:) : @stack << builder.call(fn, *args)
      end

      def build_class(instruction, function, builder)
        name = instruction.name
        attr_types = instruction.type!.attributes.values.map { |t| llvm_type(t) }
        klass = @classes[name] = LLVM.Struct(*attr_types, name.to_s)
        @methods[name.to_sym] = { new: method(:build_call_new) }
        @scope_stack << { function:, vars: {}, self_obj: klass }
        build_instructions(function, builder, instruction.body)
        @scope_stack.pop
      end

      def build_def(instruction, _function, _builder)
        name = instruction.name
        param_types = (0...instruction.params.size).map { |i| llvm_type(instruction.body.fetch(i * 2).type!) }
        receiver_type = instruction.receiver_type
        param_types.unshift(llvm_type(receiver_type))
        return_type = llvm_type(instruction.return_type)
        @methods[receiver_type.name_for_method_lookup] ||= {}
        @methods[receiver_type.name_for_method_lookup][name] = fn =
          @module.functions.add(name, param_types, return_type)
        build_function(fn, instruction.body)
      end

      def build_if(instruction, function, builder)
        result = builder.alloca(llvm_type(instruction.type!), "if_line_#{instruction.line}")
        then_block = function.basic_blocks.append
        else_block = function.basic_blocks.append
        result_block = function.basic_blocks.append
        condition = @stack.pop
        builder.cond(condition, then_block, else_block)
        then_block.build do |then_builder|
          build_instructions(function, then_builder, instruction.if_true) do |value|
            then_builder.store(value, result)
            then_builder.br(result_block)
          end
        end
        else_block.build do |else_builder|
          build_instructions(function, else_builder, instruction.if_false) do |value|
            else_builder.store(value, result)
            else_builder.br(result_block)
          end
        end
        builder.position_at_end(result_block)
        @stack << builder.load(result)
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
        @stack << @classes.fetch(instruction.name)
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

      def build_set_ivar(_instruction, _function, _builder)
        # value = @stack.last
        # self_obj.set_ivar(instruction.name, value)
      end

      def build_set_var(instruction, _function, builder)
        value = @stack.pop
        variable = builder.alloca(value.type, "var_#{instruction.name}")
        builder.store(value, variable)
        vars[instruction.name] = variable
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
        case type.evaluated_type.to_sym
        when :bool
          LLVM::Int1.type
        when :int
          LLVM::Int32.type
        else
          RcBuilder.pointer_type
        end
      end

      def llvm_type_to_ruby(value, type)
        type = type.types.last if type.is_a?(Compiler::CallType)

        case type.to_sym
        when :bool, :int, :nil
          read_llvm_type_as_ruby(value, type)
        when :str
          ptr = read_rc_pointer(value)
          read_llvm_type_as_ruby(ptr, type)
        else
          raise "Unknown type: #{type.inspect}" unless type.name == 'nillable'
          if (ptr = read_rc_pointer(value, nillable: true))
            read_llvm_type_as_ruby(ptr, type.types.first)
          end
        end
      end

      def read_rc_pointer(value, nillable: false)
        rc_ptr = value.to_ptr.read_pointer
        if nillable && rc_ptr.null?
          nil
        else
          # NOTE: this works because the ptr is the first field of the RC struct.
          rc_ptr.read_pointer
        end
      end

      def read_llvm_type_as_ruby(value, type)
        case type.to_sym
        when :bool
          value.to_i == -1
        when :int
          value.to_i
        when :str
          value.read_string
        when :nil
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
        element_type = llvm_type(array_type.types.first)
        array = ArrayBuilder.new(builder:, mod: @module, element_type:, elements:)
        array.to_ptr
      end

      def fn_puts_int
        @fn_puts_int ||= @module.functions.add('puts_int', [LLVM::Int32], LLVM::Int32)
      end

      def fn_puts_str
        @fn_puts_str ||= @module.functions.add('puts_str', [RcBuilder.pointer_type], LLVM::Int32)
      end

      def build_methods
        {
          array: {
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
          int: {
            '+': ->(builder:, args:, **) { builder.add(*args) },
            '-': ->(builder:, args:, **) { builder.sub(*args) },
            '*': ->(builder:, args:, **) { builder.mul(*args) },
            '/': ->(builder:, args:, **) { builder.sdiv(*args) },
            '==': ->(builder:, args:, **) { builder.icmp(:eq, *args) },
          },
          '(object main)': {
            puts: ->(builder:, args:, instruction:) do
              arg = args[1] # receiver is arg 0
              arg_type = instruction.type!.types[1].to_sym
              case arg_type
              when :int
                builder.call(fn_puts_int, arg)
              when :str
                builder.call(fn_puts_str, arg)
              else
                raise NoMethodError, "Method 'puts' for type #{arg_type.inspect} not found"
              end
            end,
          },
        }
      end

      def build_call_new(builder:, args:, **)
        struct = args.first
        ObjectBuilder.new(builder:, mod: @module, struct:).to_ptr
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
