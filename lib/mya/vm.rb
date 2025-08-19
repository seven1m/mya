class VM
  class ClassType
    def initialize(name)
      @name = name
      @methods = {}
    end

    attr_reader :methods, :name

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

    def get_ivar(name)
      @ivars[name]
    end
  end

  class OptionType
    def initialize(value)
      @value = value
    end

    attr_reader :value

    def methods
      {
        value!: [{ instruction: :push_option_value }],
        is_some: [{ instruction: :push_option_is_some }],
        is_none: [{ instruction: :push_option_is_none }],
      }
    end

    def to_bool
      !@value.nil?
    end

    def nil?
      @value.nil?
    end
  end

  MainClass = ClassType.new('main')
  MainObject = ObjectType.new(MainClass)

  def initialize(instructions, io: $stdout)
    @instructions = instructions
    @stack = []
    @frames = [{ instructions:, return_index: nil }]
    @scope_stack = [{ args: [], vars: {}, self_obj: MainObject }]
    @if_depth = 0
    @classes = {}
    @io = io
  end

  def run
    @index = 0
    execute_frame_stack
    @stack.pop
  end

  private

  def instructions
    @frames.last.fetch(:instructions)
  end

  BUILT_IN_METHODS = {
    puts: ->(arg, io:) do
      io.puts(arg)
      arg.to_s.size
    end,
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

    receiver = @stack.pop or raise(ArgumentError, 'No receiver')
    name = instruction.name

    if receiver.is_a?(OptionType)
      case name
      when :'value!'
        raise RuntimeError, 'Cannot call value! on None option' if receiver.nil?
        @stack << receiver.value
        return
      when :is_some
        @stack << !receiver.nil?
        return
      when :is_none
        @stack << receiver.nil?
        return
      end
    end

    if receiver.respond_to?(name)
      @stack << receiver.send(name, *new_args)
      return
    end
    if receiver.respond_to?(:methods) && receiver.methods.key?(name)
      push_frame(instructions: receiver.methods[name], return_index: @index, with_scope: true)
      @scope_stack << { args: new_args, vars: {}, self_obj: receiver }
      return
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

    condition = condition.to_bool if condition.is_a?(OptionType)

    body = condition ? instruction.if_true : instruction.if_false
    push_frame(instructions: body, return_index: @index)
  end

  def execute_while(instruction)
    loop do
      condition_frame = { instructions: instruction.condition, return_index: nil, with_scope: false }
      condition_result = execute_frames([condition_frame])

      condition_result = condition_result.to_bool if condition_result.is_a?(OptionType)

      break unless condition_result

      body_frame = { instructions: instruction.body, return_index: nil, with_scope: false }
      execute_frames([body_frame])
    end

    # While loops always return nil
    @stack << nil
  end

  def execute_pop(_)
    @stack.pop
  end

  private

  def execute_frames(frames)
    saved_frames = @frames
    saved_index = @index

    @frames = frames
    @index = 0

    execute_frame_stack

    result = @stack.last

    @frames = saved_frames
    @index = saved_index

    result
  end

  def execute_frame_stack
    while @frames.any?
      while @index < instructions.size
        instruction = instructions[@index]
        @index += 1
        execute(instruction)
      end
      frame = @frames.pop
      @scope_stack.pop if frame[:with_scope]
      @index = frame[:return_index] if frame[:return_index]
    end
  end

  def execute_push_arg(instruction)
    arg = args.fetch(instruction.index)

    if instruction.type!.name == :Option
      arg = OptionType.new(arg) unless arg.is_a?(OptionType)
    end

    @stack << arg
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

  def execute_push_self(_instruction)
    @stack << self_obj
  end

  def execute_push_true(_)
    @stack << true
  end

  def execute_push_var(instruction)
    var = vars.fetch(instruction.name)

    if instruction.type!.name == :Option
      var = OptionType.new(var) unless var.is_a?(OptionType)
    end

    @stack << var
  end

  def execute_set_var(instruction)
    value = @stack.pop

    if instruction.type!.name == :Option
      value = OptionType.new(value) unless value.is_a?(OptionType)
    end

    vars[instruction.name] = value
  end

  def execute_set_ivar(instruction)
    value = @stack.last
    self_obj.set_ivar(instruction.name, value)
  end

  def execute_push_ivar(instruction)
    value = self_obj.get_ivar(instruction.name)
    @stack << value
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
