class Compiler
  class Instruction
    def initialize(line: nil)
      @line = line
    end

    attr_reader :line

    attr_accessor :type

    def to_h
      raise NotImplementedError, __method__
    end

    def type!
      return @pruned_type.to_s if @pruned_type

      raise "No type set!" unless @type

      pruned = @type.prune
      raise TypeError, "Not enough information to infer type of #{inspect}" if pruned.is_a?(TypeVariable)

      @pruned_type = pruned
      @pruned_type.to_s
    end

    # FIXME: need better way to get type info
    attr_reader :pruned_type

    def inspect
      "<#{self.class.name} #{instance_variables.map { |iv| "#{iv}=#{instance_variable_get(iv).inspect}" }.join(' ')}>"
    end
  end

  class PushIntInstruction < Instruction
    def initialize(value, line:)
      super(line:)
      @value = value
    end

    attr_reader :value

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
      super(line:)
      @value = value
    end

    attr_reader :value

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
      super(line:)
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
      super(line:)
    end

    def to_h
      {
        type: type!,
        instruction: :push_false,
      }
    end
  end

  class PushNilInstruction < Instruction
    def initialize(line:)
      super(line:)
    end

    def to_h
      {
        type: type!,
        instruction: :push_nil,
      }
    end
  end

  class PushArrayInstruction < Instruction
    def initialize(size, line:)
      super(line:)
      @size = size
    end

    attr_reader :size

    def to_h
      {
        type: type!,
        instruction: :push_array,
        size:
      }
    end
  end

  class PushVarInstruction < Instruction
    def initialize(name, line:)
      super(line:)
      @name = name
    end

    attr_reader :name

    def to_h
      {
        type: type!,
        instruction: :push_var,
        name:,
      }
    end
  end

  class SetVarInstruction < Instruction
    def initialize(name, nillable:, line:)
      super(line:)
      @name = name
      @nillable = nillable
    end

    attr_reader :name

    def nillable? = @nillable

    def to_h
      {
        type: type!,
        instruction: :set_var,
        name:,
        nillable: nillable?,
      }
    end
  end

  class PushArgInstruction < Instruction
    def initialize(index, line:)
      super(line:)
      @index = index
    end

    attr_reader :index

    def to_h
      {
        type: type!,
        instruction: :push_arg,
        index:,
      }
    end
  end

  class CallInstruction < Instruction
    def initialize(name, arg_count:, line:)
      super(line:)
      @name = name
      @arg_count = arg_count
    end

    attr_reader :name, :arg_count

    def to_h
      {
        type: type!,
        instruction: :call,
        name:,
        arg_count:,
      }
    end
  end

  class IfInstruction < Instruction
    def initialize(line:)
      super(line:)
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
  end

  class DefInstruction < Instruction
    def initialize(name, line:)
      super(line:)
      @name = name
      @params = []
    end

    attr_reader :name
    attr_accessor :body, :params

    def return_type
      (@pruned_type || @type.prune).types.last.name.to_sym
    end

    def to_h
      {
        type: type!,
        instruction: :def,
        name:,
        params:,
        body: body.map(&:to_h)
      }
    end
  end
end
