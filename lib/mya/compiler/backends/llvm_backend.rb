require 'llvm/core'
require 'llvm/execution_engine'
require 'llvm/linker'

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
        @methods = {}
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

      BUILT_IN_METHODS = {
        '+': ->(builder, lhs, rhs) { builder.add(lhs, rhs) },
        '-': ->(builder, lhs, rhs) { builder.sub(lhs, rhs) },
        '*': ->(builder, lhs, rhs) { builder.mul(lhs, rhs) },
        '/': ->(builder, lhs, rhs) { builder.sdiv(lhs, rhs) },
        '==': ->(builder, lhs, rhs) { builder.icmp(:eq, lhs, rhs) },
        'puts': ->(builder, arg) { compile_puts(builder, arg) },
      }.freeze

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
        build_function(@entry)
        @lib.link_into(@module)
        @module.dump if @dump
        raise 'Bad code generated' unless @module.valid?
      end

      def build_function(function)
        @scope_stack << { function:, vars: {} }
        function.basic_blocks.append.build do |builder|
          build_instructions(function, builder, stop_at: [:end_def]) do |return_value|
            case function.return_type
            when :str
              zero = LLVM.Int(0)
              builder.ret builder.gep(return_value, zero)
            else
              builder.ret return_value
            end
          end
        end
        @scope_stack.pop
      end

      def build_instructions(function, builder, stop_at: [])
        while @index < @instructions.size
          instruction = @instructions[@index]
          build(instruction, function, builder)
          @index += 1
          break if stop_at.include?(@instructions[@index]&.legacy_name)
        end
        return_value = @stack.pop
        yield return_value
      end

      def build(instruction, function, builder)
        case instruction
        when PushIntInstruction
          @stack << LLVM::Int(instruction.arg)
        when PushStrInstruction
          # FIXME: don't always want a global string here probably
          str = @module.globals.add(LLVM::ConstantArray.string(instruction.arg), 'str') do |var|
            var.initializer = LLVM::ConstantArray.string(instruction.arg)
          end
          @stack << str
        when PushTrueInstruction
          @stack << LLVM::TRUE
        when PushFalseInstruction
          @stack << LLVM::FALSE
        when SetVarInstruction
          value = @stack.pop
          variable = builder.alloca(value.type, "var_#{instruction.arg}")
          builder.store(value, variable)
          vars[instruction.arg] = variable
        when PushVarInstruction
          variable = vars.fetch(instruction.arg)
          @stack << builder.load(variable)
        when DefInstruction
          @index += 1
          name = instruction.arg
          arg_types = (0...instruction.extra_arg).map do |i|
            llvm_type(@instructions.fetch(@index + (i * 2)).type!)
          end
          return_type = llvm_type(instruction.type!)
          @methods[name] = fn  = @module.functions.add(name, arg_types, return_type)
          build_function(fn)
        when CallInstruction
          args = @stack.pop(instruction.extra_arg)
          if (built_in_method = BUILT_IN_METHODS[instruction.arg])
            @stack << instance_exec(builder, *args, &built_in_method)
          else
            name = instruction.arg
            function = @methods[name] or raise(NoMethodError, "Method '#{name}' not found")
            @stack << builder.call(function, *args)
          end
        when PushArgInstruction
          function = @scope_stack.last.fetch(:function)
          @stack << function.params[instruction.arg]
        when IfInstruction
          result = builder.alloca(llvm_type(instruction.type!), "if_line_#{instruction.line}")
          then_block = function.basic_blocks.append
          else_block = function.basic_blocks.append
          result_block = function.basic_blocks.append
          condition = @stack.pop
          builder.cond(condition, then_block, else_block)
          raise 'bad if' if @index >= @instructions.size || @instructions[@index].legacy_name != :if
          @index += 1
          then_block.build do |then_builder|
            build_instructions(function, then_builder, stop_at: [:else]) do |value|
              then_builder.store(value, result)
              then_builder.br(result_block)
            end
          end
          raise 'bad else' if @index >= @instructions.size || @instructions[@index].legacy_name != :else
          @index += 1
          else_block.build do |else_builder|
            build_instructions(function, else_builder, stop_at: [:end_if]) do |value|
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
        case type
        when :bool
          LLVM::Int1
        when :int
          LLVM::Int32
        when :str
          LLVM::Type.pointer(LLVM::UInt8)
        else
          raise "Unknown type: #{type.inspect}"
        end
      end

      def llvm_type_to_ruby(value, type)
        case type
        when :bool
          value.to_i == -1
        when :int
          value.to_i
        when :str
          value.to_ptr.read_pointer.read_string
          #value.to_ptr.read_string
        end
      end

      def compile_puts(builder, arg)
        case arg.type
        when LLVM::IntType
          builder.call(fn_puts_int, arg)
        else
          raise "Unhandled type: #{arg.class}"
        end
      end

      def fn_puts_int
        @fn_puts_int ||= @module.functions.add('puts_int', [LLVM::Int32], LLVM::Int32)
      end
    end
  end
end
