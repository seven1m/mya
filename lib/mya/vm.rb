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
    'puts': ->(arg, io:) { io.puts(arg); arg.to_s.size },
  }.freeze

  def execute(instruction)
    send("execute_#{instruction.instruction_name}", instruction)
  end

  def execute_def(instruction)
    @methods[instruction.name] = instruction
  end

  def execute_call(instruction)
    new_args = @stack.pop(instruction.arg_count)

    if instruction.has_receiver?
      receiver = @stack.pop or raise(ArgumentError, 'No receiver')
      if receiver.respond_to?(instruction.name)
        @stack << receiver.send(instruction.name, *new_args)
        return
      end
    end

    if (built_in_method = BUILT_IN_METHODS[instruction.name])
      @stack << built_in_method.call(*new_args, io: @io)
      return
    end

    method = @methods[instruction.name]
    raise NoMethodError, "Undefined method #{instruction.name}" unless method

    push_frame(instructions: method.body, return_index: @index, with_scope: true)
    @scope_stack << { args: new_args, vars: {} }
  end

  def execute_if(instruction)
    condition = @stack.pop
    body = condition ? instruction.if_true : instruction.if_false
    push_frame(instructions: body, return_index: @index)
  end

  def execute_push_arg(instruction)
    @stack << args.fetch(instruction.index)
  end

  def execute_push_array(instruction)
    ary = @stack.pop(instruction.size)
    @stack << ary
  end

  def execute_push_false(_)
    @stack << false
  end

  def execute_push_int(instruction)
    @stack << instruction.value
  end

  def execute_push_nil(_)
    @stack << nil
  end

  def execute_push_str(instruction)
    @stack << instruction.value
  end

  def execute_push_true(_)
    @stack << true
  end

  def execute_push_var(instruction)
    @stack << vars.fetch(instruction.name)
  end

  def execute_set_var(instruction)
    vars[instruction.name] = @stack.pop
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
