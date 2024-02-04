require 'llvm/core'
require 'llvm/execution_engine'

class JIT
  def initialize(instructions, io: $stdout, dump_jit: false)
    @instructions = instructions
    @stack = []
    @scope_stack = [{ vars: {} }]
    @call_stack = []
    @if_depth = 0
    @methods = {}
    @io = io
    @dump_jit = dump_jit
    @module = LLVM::Module.new('jit')
  end

  attr_reader :instructions

  def run
    return_type = @instructions.last.type!

    @index = 0
    main = build_function('main', [], llvm_type(return_type))

    @module.dump if @dump_jit

    LLVM.init_jit

    engine = LLVM::JITCompiler.new(@module)
    value = engine.run_function(main)
    return_value = case return_type
                   when :bool
                     value.to_i == -1
                   when :int
                     value.to_i
                   when :str
                     value.to_ptr.read_pointer.read_string
                     #value.to_ptr.read_string
                   end
    engine.dispose

    return_value
  end

  private

  BUILT_IN_METHODS = {
    '+': ->(builder, lhs, rhs) { builder.add(lhs, rhs) },
    '-': ->(builder, lhs, rhs) { builder.sub(lhs, rhs) },
    '*': ->(builder, lhs, rhs) { builder.mul(lhs, rhs) },
    '/': ->(builder, lhs, rhs) { builder.sdiv(lhs, rhs) },
    '==': ->(builder, lhs, rhs) { builder.icmp(:eq, lhs, rhs) },
    'p': ->(arg, io:) { io.puts(arg.inspect) }
  }.freeze

  def build_function(name, arg_types, return_type)
    @module.functions.add(name, arg_types, return_type) do |function|
      function.basic_blocks.append.build do |builder|
        @scope_stack << { function:, vars: {} }
        while @index < @instructions.size
          instruction = @instructions[@index]
          build(instruction, builder)
          @index += 1
          break if @instructions[@index]&.name == :end_def
        end
        @scope_stack.pop
        return_value = @stack.pop
        case return_type
        when :str
          zero = LLVM.Int(0)
          builder.ret builder.gep(return_value, zero)
        else
          builder.ret return_value
        end
      end
    end
  end

  def build(instruction, builder)
    case instruction.name
    when :push_int
      @stack << LLVM::Int(instruction.arg)
    when :push_str
      # FIXME: don't always want a global string here probably
      str = @module.globals.add(LLVM::ConstantArray.string(instruction.arg), 'str') do |var|
        var.initializer = LLVM::ConstantArray.string(instruction.arg)
      end
      @stack << str
    when :push_true
      @stack << LLVM::TRUE
    when :push_false
      @stack << LLVM::FALSE
    when :set_var
      value = @stack.pop
      variable = builder.alloca(value.type)
      builder.store(value, variable)
      vars[instruction.arg] = variable
    when :push_var
      variable = vars.fetch(instruction.arg)
      @stack << builder.load(variable)
    when :def
      @index += 1
      name = instruction.arg
      arg_types = (0...instruction.extra_arg).map { |i| llvm_type(@instructions.fetch(@index + (i * 2)).type!) }
      @methods[name] = build_function(name, arg_types, llvm_type(instruction.type!))
    when :end_def
      @index = @call_stack.pop.fetch(:return_index)
    when :call
      args = @stack.pop(instruction.extra_arg)
      if (built_in_method = BUILT_IN_METHODS[instruction.arg])
        @stack << built_in_method.call(builder, *args)
      else
        name = instruction.arg
        function = @methods[name] or raise(NoMethodError, "Method '#{name}' not found")
        @stack << builder.call(function, *args)
      end
    when :push_arg
      function = @scope_stack.last.fetch(:function)
      @stack << function.params[instruction.arg]
    when :if
      condition = @stack.pop
      if condition
        :noop # just execute next expression
      else
        @index += 1
        skip_to_next_instruction_by_name(:else)
      end
    when :else
      skip_to_next_instruction_by_name(:end_if)
    when :end_if
      :noop
    else
      raise "Unknown instruction: #{instruction.inspect}"
    end
  end

  def skip_to_next_instruction_by_name(name)
    start_if_depth = @if_depth
    until @instructions[@index].name == name && @if_depth == start_if_depth
      case @instructions[@index].name
      when :if
        @if_depth += 1
      when :end_if
        @if_depth -= 1
      end
      @index += 1
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
end
