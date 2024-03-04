class VM
  def initialize(instructions, io: $stdout)
    @instructions = instructions
    @stack = []
    @frames = [
      { instructions:, return_index: nil }
    ]
    @scope_stack = [{ args: [], vars: {} }]
    @if_depth = 0
    @methods = {}
    @io = io
  end

  attr_reader :instructions

  def run
    @index = 0
    while @frames.any?
      while @index < instructions.size
        instruction = instructions[@index]
        @index += 1
        execute(instruction)
      end
      frame = @frames.pop
      @scope_stack.pop if frame[:with_scope]
      @index = frame.fetch(:return_index)
    end
    @stack.pop
  end

  private

  def instructions
    @frames.last.fetch(:instructions)
  end

  BUILT_IN_METHODS = {
    '+': nil,
    '-': nil,
    '*': nil,
    '/': nil,
    '==': nil,
    'first': nil,
    'puts': ->(arg, io:) { io.puts(arg); arg.to_s.size },
  }.freeze

  def execute(instruction)
    case instruction
    when Compiler::PushIntInstruction, Compiler::PushStrInstruction
      @stack << instruction.value
    when Compiler::PushTrueInstruction
      @stack << true
    when Compiler::PushFalseInstruction
      @stack << false
    when Compiler::SetVarInstruction
      vars[instruction.name] = @stack.pop
    when Compiler::PushVarInstruction
      @stack << vars.fetch(instruction.name)
    when Compiler::PushArrayInstruction
      elements = @stack.pop(instruction.size)
      @stack << elements
    when Compiler::DefInstruction
      @methods[instruction.name] = instruction
    when Compiler::CallInstruction
      new_args = @stack.pop(instruction.arg_count)
      if BUILT_IN_METHODS.key?(instruction.name)
        @stack << if (built_in_method = BUILT_IN_METHODS[instruction.name])
                    built_in_method.call(*new_args, io: @io)
                  else
                    new_args.first.send(instruction.name, *new_args[1..])
                  end
      else
        method = @methods[instruction.name]
        raise NoMethodError, "Undefined method #{instruction.name}" unless method
        push_frame(instructions: method.body, return_index: @index, with_scope: true)
        @scope_stack << { args: new_args, vars: {} }
      end
    when Compiler::PushArgInstruction
      @stack << args[instruction.index]
    when Compiler::IfInstruction
      condition = @stack.pop
      body = if condition
        instruction.if_true
      else
        instruction.if_false
      end
      push_frame(instructions: body, return_index: @index)
    else
      raise "Unknown instruction: #{instruction.inspect}"
    end
  end

  def push_frame(instructions:, return_index:, with_scope: false)
    @frames << { instructions:, return_index:, with_scope: }
    @index = 0
  end

  def scope
    @scope_stack.last
  end

  def vars
    scope.fetch(:vars)
  end

  def args
    scope.fetch(:args)
  end
end
