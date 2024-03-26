class VM
  class ClassType
    def initialize(name)
      @name = name
      @methods = {}
    end

    attr_reader :methods

    attr_reader :name

    def new
      ObjectType.new(self)
    end
  end

  class ObjectType
    def initialize(klass)
      @klass = klass
      @ivars = {}
    end

    attr_reader :klass

    def methods = klass.methods

    def set_ivar(name, value)
      @ivars[name] = value
    end
  end

  MainClass = ClassType.new('main')
  MainObject = ObjectType.new(MainClass)

  def initialize(instructions, io: $stdout)
    @instructions = instructions
    @stack = []
    @frames = [
      { instructions:, return_index: nil }
    ]
    @scope_stack = [{ args: [], vars: {}, self_obj: MainObject }]
    @if_depth = 0
    @classes = {}
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

  def execute_class(instruction)
    klass = @classes[instruction.name] = ClassType.new(instruction.name)
    push_frame(instructions: instruction.body, return_index: @index, with_scope: true)
    @scope_stack << { vars: {}, self_obj: klass }
  end

  def execute_def(instruction)
    self_obj.methods[instruction.name] = instruction.body
  end

  def execute_call(instruction)
    new_args = @stack.pop(instruction.arg_count)

    if instruction.has_receiver?
      receiver = @stack.pop or raise(ArgumentError, 'No receiver')
      name = instruction.name
      if receiver.respond_to?(name)
        @stack << receiver.send(name, *new_args)
        return
      end
      if receiver.methods.key?(name)
        push_frame(instructions: receiver.methods[name], return_index: @index, with_scope: true)
        @scope_stack << { args: new_args, vars: {}, self_obj: receiver }
        return
      end
    end

    if (built_in_method = BUILT_IN_METHODS[instruction.name])
      @stack << built_in_method.call(*new_args, io: @io)
      return
    end

    method_body = self_obj.methods[instruction.name]
    raise NoMethodError, "Undefined method #{instruction.name}" unless method_body

    push_frame(instructions: method_body, return_index: @index, with_scope: true)
    @scope_stack << { args: new_args, vars: {}, self_obj: }
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

  def execute_push_const(instruction)
    @stack << @classes[instruction.name]
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

  def execute_set_ivar(instruction)
    # TODO: Need `used` argument to know whether to leave value on stack or not.
    value = @stack.last
    self_obj.set_ivar(instruction.name, value)
  end

  def push_frame(instructions:, return_index:, with_scope: false)
    @frames << { instructions:, return_index:, with_scope: }
    @index = 0
  end

  def scope
    @scope_stack.last
  end

  def self_obj
    scope.fetch(:self_obj)
  end

  def vars
    scope.fetch(:vars)
  end

  def args
    scope.fetch(:args)
  end
end
