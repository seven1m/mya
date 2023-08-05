require 'llvm/core'
require 'llvm/execution_engine'

class JIT
  def initialize(instructions, io: $stdout)
    @instructions = instructions
    @stack = []
    @scope_stack = [{ vars: {} }]
    @call_stack = []
    @if_depth = 0
    @methods = {}
    @io = io
    @module = LLVM::Module.new('jit')
  end

  attr_reader :instructions

  def run
    return_type = @instructions.last.type

    main = @module.functions.add('main', [], llvm_type(return_type)) do |function|
      function.basic_blocks.append.build do |builder|
        @index = 0
        while @index < @instructions.size
          instruction = @instructions[@index]
          build(instruction, builder)
          @index += 1
        end
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

    #@module.dump

    LLVM.init_jit

    engine = LLVM::JITCompiler.new(@module)
    value = engine.run_function(main)
    return_value = case return_type
                   when :int
                     value.to_i
                   when :str
                     value.to_ptr.read_pointer.read_string
                   end
    engine.dispose

    return_value
  end

  private

  BUILT_IN_METHODS = {
    '+': nil,
    '-': nil,
    '*': nil,
    '/': nil,
    '==': nil,
    'p': ->(arg, io:) { io.puts(arg.inspect) }
  }.freeze

  def build(instruction, builder)
    case instruction.name
    when :push_int
      @stack << LLVM::Int(instruction.arg)
    when :push_str
      # FIXME: don't always want a global string here probably
      str = @module.globals.add(LLVM::ConstantArray.string(instruction.arg), 'str') do |var|
        var.initializer = LLVM::ConstantArray.string(instruction.arg)
      end
      var = builder.alloca(str.type)
      builder.store(str, var)
      @stack << builder.load(var)
    when :push_true
      @stack << true
    when :push_false
      @stack << false
    when :set_var
      vars[instruction.arg] = @stack.pop
    when :push_var
      @stack << vars.fetch(instruction.arg)
    when :def
      @methods[instruction.arg] = @index + 1
      @index += 1 until @instructions[@index].name == :end_def
    when :end_def
      @scope_stack.pop
      @index = @call_stack.pop.fetch(:return_index)
    when :call
      args = @stack.pop(instruction.extra_arg)
      if BUILT_IN_METHODS.key?(instruction.arg)
        @stack << if (built_in_method = BUILT_IN_METHODS[instruction.arg])
                    built_in_method.call(*args, io: @io)
                  else
                    args.first.send(instruction.arg, *args[1..])
                  end
      else
        @call_stack << ({ return_index: @index, args: })
        @scope_stack << { vars: {} }
        @index = @methods.fetch(instruction.arg) - 1
      end
    when :push_arg
      @stack << @call_stack.last.fetch(:args)[instruction.arg]
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
    when :int
      LLVM::Int32
    when :str
      LLVM::Type.pointer(LLVM::UInt8)
    else
      raise "Unknown type: #{type}"
    end
  end
end
