class Compiler
  class Instruction
    def initialize(legacy_name, arg: nil, extra_arg: nil, type: nil, line: nil)
      @legacy_name = legacy_name
      @arg = arg
      @extra_arg = extra_arg
      @type = type
      @line = line
      @dependencies = []
    end

    attr_reader :legacy_name, :arg, :extra_arg, :type, :line, :dependencies

    def to_h
      raise NotImplementedError, __method__
    end

    def add_dependency(dependency)
      @dependencies << dependency
    end

    INSTRUCTIONS_WITH_NO_TYPE = %i[
      else
      end_def
    ].freeze

    def type!
      return @type if @type

      return if INSTRUCTIONS_WITH_NO_TYPE.include?(@legacy_name)

      unique_types = @dependencies.map(&:type!).compact.uniq

      if unique_types.empty?
        raise TypeError, "Not enough information to infer type of instruction '#{@legacy_name}'"
      elsif unique_types.size == 1
        unique_types.first
      else
        raise TypeError, "Instruction '#{@legacy_name}' could have more than one type: #{unique_types.sort.inspect}"
      end
    end

    def inspect(indent = 0, index = nil)
      "#{' ' * indent}#{index ? "#{index}. " : ''}<#{self.class.name} #{@legacy_name}, arg: #{@arg.inspect}>"
    end
  end

  class PushIntInstruction < Instruction
    def initialize(value, line:)
      super(:push_int, arg: value, type: :int, line:)
    end

    def value = arg

    def to_h
      {
        type: type!,
        instruction: :push_int,
        value:,
      }
    end
  end

  class PushStrInstruction < Instruction
    def initialize(value, line:)
      super(:push_str, arg: value, type: :str, line:)
    end

    def value = arg

    def to_h
      {
        type: type!,
        instruction: :push_str,
        value:,
      }
    end
  end

  class PushTrueInstruction < Instruction
    def initialize(line:)
      super(:push_true, type: :bool, line:)
    end

    def to_h
      {
        type: type!,
        instruction: :push_true,
      }
    end
  end

  class PushFalseInstruction < Instruction
    def initialize(line:)
      super(:push_false, type: :bool, line:)
    end

    def to_h
      {
        type: type!,
        instruction: :push_false,
      }
    end
  end

  class PushVarInstruction < Instruction
    def initialize(name, line:)
      super(:push_var, arg: name, line:)
    end

    def name = arg

    def to_h
      {
        type: type!,
        instruction: :push_var,
        name:,
      }
    end
  end

  class SetVarInstruction < Instruction
    def initialize(name, line:)
      super(:set_var, arg: name, line:)
    end

    def name = arg

    def to_h
      {
        type: type!,
        instruction: :set_var,
        name:,
      }
    end
  end

  class PushArgInstruction < Instruction
    def initialize(index, line:)
      super(:push_arg, arg: index, line:)
    end

    def index = arg

    def to_h
      {
        type: type!,
        instruction: :push_arg,
        index:,
      }
    end
  end

  class CallInstruction < Instruction
    def initialize(name, arg_size:, line:)
      super(:call, arg: name, extra_arg: arg_size, line:)
    end

    def name = arg
    def arg_size = extra_arg

    def to_h
      {
        type: type!,
        instruction: :call,
        name:,
        arg_size:,
      }
    end
  end

  class IfInstruction < Instruction
    def initialize(line:)
      super(:if, line:)
    end

    attr_accessor :if_true, :if_false

    def to_h
      {
        type: type!,
        instruction: :if,
        if_true: if_true.map(&:to_h),
        if_false: if_false.map(&:to_h)
      }
    end

    def inspect(indent = 0, index = nil)
      s = "#{' ' * indent}#{index ? "#{index}. " : ''}<#{self.class.name} #{@legacy_name}, arg: #{@arg.inspect}>"
      s << "\n#{' ' * indent}  if_true: ["
      if_true.each_with_index do |instruction, index|
        s << "\n#{instruction.inspect(indent + 4, index)}"
      end
      s << "\n#{' ' * indent}  ]"
      s << "\n#{' ' * indent}  if_false: ["
      if_false.each_with_index do |instruction, index|
        s << "\n#{instruction.inspect(indent + 4, index)}"
      end
      s << "\n#{' ' * indent}  ]"
      s
    end
  end

  class DefInstruction < Instruction
    def initialize(name, param_size:, line:)
      super(:def, arg: name, extra_arg: param_size, line:)
    end

    attr_accessor :body

    def name = arg
    def param_size = extra_arg

    def to_h
      {
        type: type!,
        instruction: :def,
        name:,
        param_size:,
        body: body.map(&:to_h)
      }
    end

    def inspect(indent = 0, index = nil)
      s = "#{' ' * indent}#{index ? "#{index}. " : ''}<#{self.class.name} #{@legacy_name}, arg: #{@arg.inspect}>"
      s << "\n#{' ' * indent}  body: ["
      body.each_with_index do |instruction, index|
        s << "\n#{instruction.inspect(indent + 4, index)}"
      end
      s << "\n#{' ' * indent}  ]"
      s
    end
  end
end
