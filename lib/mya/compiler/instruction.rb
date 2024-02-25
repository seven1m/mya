class Compiler
  class Instruction
    def initialize(legacy_name, arg: nil, extra_arg: nil, type: nil, line: nil)
      @legacy_name = legacy_name
      @arg = arg
      @extra_arg = extra_arg
      @type = type
      @line = line
    end

    attr_reader :legacy_name, :arg, :extra_arg, :type, :line

    attr_accessor :type

    def to_h
      raise NotImplementedError, __method__
    end

    INSTRUCTIONS_WITH_NO_TYPE = %i[
      else
      end_def
    ].freeze

    def type!
      return @pruned_type.to_s if @pruned_type

      raise "No type set!" unless @type

      pruned = @type.prune
      raise TypeError, "Not enough information to infer type of #{inspect}" if pruned.is_a?(TypeVariable)

      @pruned_type = pruned

      @pruned_type.to_s
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
      @params = []
    end

    attr_accessor :body, :params

    def name = arg
    def param_size = extra_arg

    def return_type
      (@pruned_type || @type.prune).types.last.name.to_sym
    end

    def to_h
      {
        type: type!,
        instruction: :def,
        name:,
        param_size:,
        params:,
        body: body.map(&:to_h)
      }
    end

    def inspect(indent = 0, index = nil)
      s = "#{' ' * indent}#{index ? "#{index}. " : ''}<#{self.class.name} name: #{name}>"
      s << "\n#{' ' * indent}  params: #{params.inspect}"
      s << "\n#{' ' * indent}  body: ["
      body.each_with_index do |instruction, index|
        s << "\n#{instruction.inspect(indent + 4, index)}"
      end
      s << "\n#{' ' * indent}  ]"
      s
    end
  end
end
