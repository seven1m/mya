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
        @rc = LLVM::Struct(LLVM::Type.pointer, LLVM::Int32, 'rc')
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
        'puts': ->(builder, arg) { build_puts(builder, arg) },
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
            #case function.return_type
            #when :str
              #builder.ret builder.gep(return_value, LLVM::Int(0))
            #else
              #builder.ret return_value
            #end
          end
        end
        @scope_stack.pop
      end

      def build_instructions(function, builder, instructions)
        instructions.each do |instruction|
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
          str = build_string(builder, instruction.value)
          @stack << str
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
        when DefInstruction
          @index += 1
          name = instruction.name
          param_types = (0...instruction.params.size).map do |i|
            llvm_type(instruction.body.fetch(i * 2).type!)
          end
          return_type = llvm_type(instruction.return_type)
          @methods[name] = fn  = @module.functions.add(name, param_types, return_type)
          build_function(fn, instruction.body)
        when CallInstruction
          args = @stack.pop(instruction.arg_count)
          if (built_in_method = BUILT_IN_METHODS[instruction.name])
            @stack << instance_exec(builder, *args, &built_in_method)
          else
            name = instruction.name
            function = @methods[name] or raise(NoMethodError, "Method '#{name}' not found")
            @stack << builder.call(function, *args)
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
        case type.to_sym
        when :bool
          value.to_i == -1
        when :int
          value.to_i
        when :str
          #     RC*    RC           RC.ptr
          value.to_ptr.read_pointer.read_pointer.read_string
        else
          raise "Unknown type: #{type.inspect}"
        end
      end

      def build_puts(builder, arg)
        case arg.type.kind
        when :integer
          builder.call(fn_puts_int, arg)
        when :pointer # FIXME: need our own type information here
          builder.call(fn_puts_str, arg)
        else
          raise "Unhandled type: #{arg.type}"
        end
      end

      def build_string(builder, value)
        rc = builder.call(fn_rc_new)
        str = LLVM::ConstantArray.string(value)
        str_ptr = builder.alloca(LLVM::Type.pointer(LLVM::UInt8))
        builder.store(str, str_ptr)
        builder.call(fn_rc_set_str, rc, str_ptr)
        rc
      end

      def rc_struct
        @rc_struct ||= LLVM::Struct(LLVM::Type.ptr, LLVM::UInt64)
      end

      def fn_puts_int
        @fn_puts_int ||= @module.functions.add('puts_int', [LLVM::Int32], LLVM::Int32)
      end

      def fn_puts_str
        @fn_puts_str ||= @module.functions.add('puts_str', [LLVM::Type.pointer(rc_struct)], LLVM::Type.pointer(rc_struct))
      end

      def fn_rc_new
        @fn_rc_new ||= @module.functions.add('rc_new', [], LLVM::Type.pointer(rc_struct))
      end

      def fn_rc_set_str
        @fn_rc_set_str ||= @module.functions.add('rc_set_str', [LLVM::Type.pointer(rc_struct), LLVM::Type.pointer(LLVM::UInt8)], LLVM::Type.void)
      end

      def fn_rc_take
        @fn_rc_take ||= @module.functions.add('rc_take', [LLVM::Type.pointer(rc_struct)], LLVM::Type.void)
      end

      def fn_rc_drop
        @fn_rc_drop ||= @module.functions.add('rc_drop', [LLVM::Type.pointer(rc_struct)], LLVM::Type.void)
      end
    end
  end
end
