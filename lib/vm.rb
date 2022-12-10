class VM
  def initialize(instructions)
    @instructions = instructions
    @stack = []
    @scope_stack = [{ vars: {} }]
    @call_stack = []
    @methods = {}
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

  def execute(instruction)
    case instruction.name
    when :push_int, :push_str
      @stack << instruction.arg
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
      @index = @call_stack.pop.fetch(:return_index)
    when :call
      args = @stack.pop(instruction.extra_arg)
      @call_stack << { return_index: @index, args: args }
      @index = @methods.fetch(instruction.arg) - 1
    when :push_arg
      @stack << @call_stack.last.fetch(:args)[instruction.arg]
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
end
