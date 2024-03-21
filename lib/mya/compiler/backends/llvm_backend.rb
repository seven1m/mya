require 'llvm/core'
require 'llvm/execution_engine'
require 'llvm/linker'
require 'llvm/linker'
require_relative 'llvm_backend/rc_builder'
require_relative 'llvm_backend/array_builder'
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
        @index = 0
        build_function(@entry, @instructions)
        @lib.link_into(@module)
        @module.dump if @dump || !@module.valid?
        @module.verify!
      end

      def build_function(function, instructions)
        @scope_stack << { function:, vars: {} }
        function.basic_blocks.append.build do |builder|
          build_instructions(function, builder, instructions) do |return_value|
            builder.ret return_value
          end
        end
        @scope_stack.pop
      end

      def build_instructions(function, builder, instructions)
        instructions.each do |instruction|
          # FIXME: discard unused stack values
          build(instruction, function, builder)
        end
        return_value = @stack.pop
        yield return_value
      end

      def build(instruction, function, builder)
        case instruction
        when PushIntInstruction
          @stack << LLVM::Int(instruction.value)
        when PushStrInstruction
          @stack << build_string(builder, instruction.value)
        when PushNilInstruction
          @stack << RcBuilder.pointer_type.null_pointer
        when PushTrueInstruction
          @stack << LLVM::TRUE
        when PushFalseInstruction
          @stack << LLVM::FALSE
        when SetVarInstruction
          value = @stack.pop
          variable = builder.alloca(value.type, "var_#{instruction.name}")
          builder.store(value, variable)
          vars[instruction.name] = variable
        when PushVarInstruction
          variable = vars.fetch(instruction.name)
          @stack << builder.load(variable)
        when PushArrayInstruction
          @stack << build_array(builder, instruction)
        when DefInstruction
          @index += 1
          name = instruction.name
          param_types = (0...instruction.params.size).map do |i|
            llvm_type(instruction.body.fetch(i * 2).type!)
          end
          return_type = llvm_type(instruction.return_type)
          @methods[name] = fn = @module.functions.add(name, param_types, return_type)
          build_function(fn, instruction.body)
        when CallInstruction
          args = @stack.pop(instruction.arg_count)
          if instruction.has_receiver?
            args.unshift @stack.pop
          end
          name = instruction.name
          fn = @methods[name] or raise(NoMethodError, "Method '#{name}' not found")
          if fn.respond_to?(:call)
            @stack << fn.call(builder:, instruction:, args:)
          else
            @stack << builder.call(fn, *args)
          end
        when PushArgInstruction
          function = @scope_stack.last.fetch(:function)
          @stack << function.params[instruction.index]
        when IfInstruction
          result = builder.alloca(llvm_type(instruction.type!), "if_line_#{instruction.line}")
          then_block = function.basic_blocks.append
          else_block = function.basic_blocks.append
          result_block = function.basic_blocks.append
          condition = @stack.pop
          builder.cond(condition, then_block, else_block)
          @index += 1
          then_block.build do |then_builder|
            build_instructions(function, then_builder, instruction.if_true) do |value|
              then_builder.store(value, result)
              then_builder.br(result_block)
            end
          end
          @index += 1
          else_block.build do |else_builder|
            build_instructions(function, else_builder, instruction.if_false) do |value|
              else_builder.store(value, result)
              else_builder.br(result_block)
            end
          end
          builder.position_at_end(result_block)
          @stack << builder.load(result)
        else
          raise "Unknown instruction: #{instruction.inspect}"
        end
      end

      def scope
        @scope_stack.last
      end

      def vars
        scope.fetch(:vars)
      end

      def llvm_type(type)
        case type.to_sym
        when :bool
          LLVM::Int1.type
        when :int
          LLVM::Int32.type
        else
          RcBuilder.pointer_type
        end
      end

      def llvm_type_to_ruby(value, type)
        case type.to_sym
        when :bool, :int, :nil
          read_llvm_type_as_ruby(value, type)
        when :str
          ptr = read_rc_pointer(value)
          read_llvm_type_as_ruby(ptr, type)
        else
          if type.name == 'nillable'
            if (ptr = read_rc_pointer(value, nillable: true))
              read_llvm_type_as_ruby(ptr, type.types.first)
            else
              nil
            end
          else
            raise "Unknown type: #{type.inspect}"
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
        element_type = llvm_type(array_type.types.first.to_s)
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
          first: -> (builder:, instruction:, args:) do
            element_type = llvm_type(instruction.type!)
            array = ArrayBuilder.new(ptr: args.first, builder:, mod: @module, element_type:)
            array.first
          end,
          last: -> (builder:, instruction:, args:) do
            element_type = llvm_type(instruction.type!)
            array = ArrayBuilder.new(ptr: args.first, builder:, mod: @module, element_type:)
            array.last
          end,
          '<<': -> (builder:, instruction:, args:) do
            element_type = args.last.type
            array = ArrayBuilder.new(ptr: args.first, builder:, mod: @module, element_type:)
            array.push(args.last)
          end,
          '+': -> (builder:, args:, **) { builder.add(*args) },
          '-': -> (builder:, args:, **) { builder.sub(*args) },
          '*': -> (builder:, args:, **) { builder.mul(*args) },
          '/': -> (builder:, args:, **) { builder.sdiv(*args) },
          '==': -> (builder:, args:, **) { builder.icmp(:eq, *args) },
          'puts': -> (builder:, args:, instruction:) do
            arg = args.first
            arg_type = instruction.arg_instructions.first.type!.to_sym
            case arg_type
            when :int
              builder.call(fn_puts_int, arg)
            when :str
              builder.call(fn_puts_str, arg)
            else
              raise NoMethodError, "Method 'puts' for type #{arg_type.inspect} not found"
            end
          end
        }
      end

      # usage:
      # diff(@module.functions[11].to_s, @module.functions[0].to_s)
      def diff(expected, actual)
        File.write("/tmp/actual.ll", actual)
        File.write("/tmp/expected.ll", expected)
        puts `diff -y -W 134 /tmp/expected.ll /tmp/actual.ll`
      end
    end
  end
end
