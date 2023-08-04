class VM
  def initialize(instructions, io: $stdout)
    @instructions = instructions
    @stack = []
    @scope_stack = [{ vars: {} }]
    @call_stack = []
    @if_depth = 0
    @methods = {}
    @io = io
  end

  attr_reader :instructions

  def run
    @index = 0
    while @index < @instructions.size
      instruction = @instructions[@index]
      execute(instruction)
      @index += 1
    end
    @stack.pop
  end

  private

  BUILT_IN_METHODS = {
    '+': nil,
    '-': nil,
    '*': nil,
    '/': nil,
    '==': nil,
    'p': ->(arg, io:) { io.puts(arg.inspect) },
  }.freeze

  def execute(instruction)
    case instruction.name
    when :push_int, :push_str
      @stack << instruction.arg
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
      until @instructions[@index].name == :end_def
        @index += 1
      end
    when :end_def
      @scope_stack.pop
      @index = @call_stack.pop.fetch(:return_index)
    when :call
      args = @stack.pop(instruction.extra_arg)
      if BUILT_IN_METHODS.key?(instruction.arg)
        if (built_in_method = BUILT_IN_METHODS[instruction.arg])
          @stack << built_in_method.call(*args, io: @io)
        else
          @stack << args.first.send(instruction.arg, *args[1..])
        end
      else
        @call_stack << { return_index: @index, args: args }
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
end
