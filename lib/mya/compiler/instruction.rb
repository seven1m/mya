class Compiler
  class Instruction
    def initialize(line: nil)
      @line = line
    end

    attr_reader :line

    attr_writer :type

    def to_h
      raise NotImplementedError, __method__
    end

    def type!
      return @pruned_type if @pruned_type

      raise "No type set on #{inspect}" unless @type

      pruned = @type.prune
      raise TypeError, "Not enough information to infer type of #{inspect}" if pruned.is_a?(TypeVariable)

      @pruned_type = pruned
    end

    def inspect
      "<#{self.class.name} #{instance_variables.map { |iv| "#{iv}=#{instance_variable_get(iv).inspect}" }.join(' ')}>"
    end

    def to_h
      {
        type: type!.to_s,
        instruction: instruction_name,
      }
    end
  end

  class PushIntInstruction < Instruction
    def initialize(value, line:)
      super(line:)
      @value = value
    end

    attr_reader :value

    def instruction_name
      :push_int
    end

    def to_h
      super.merge(value:)
    end
  end

  class PushStrInstruction < Instruction
    def initialize(value, line:)
      super(line:)
      @value = value
    end

    attr_reader :value

    def instruction_name
      :push_str
    end

    def to_h
      super.merge(value:)
    end
  end

  class PushTrueInstruction < Instruction
    def instruction_name
      :push_true
    end
  end

  class PushFalseInstruction < Instruction
    def instruction_name
      :push_false
    end
  end

  class PushNilInstruction < Instruction
    def instruction_name
      :push_nil
    end
  end

  class PushArrayInstruction < Instruction
    def initialize(size, line:)
      super(line:)
      @size = size
    end

    attr_reader :size

    def instruction_name
      :push_array
    end

    def to_h
      super.merge(size:)
    end
  end

  class PushVarInstruction < Instruction
    def initialize(name, line:)
      super(line:)
      @name = name
    end

    attr_reader :name

    def instruction_name
      :push_var
    end

    def to_h
      super.merge(name:)
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

    def instruction_name
      :set_var
    end

    def to_h
      super.merge(name:, nillable: nillable?)
    end
  end

  class SetInstanceVarInstruction < Instruction
    def initialize(name, nillable:, line:)
      super(line:)
      @name = name
      @nillable = nillable
    end

    attr_reader :name

    def nillable? = @nillable

    def instruction_name
      :set_ivar
    end

    def to_h
      super.merge(name:, nillable: nillable?)
    end
  end

  class PushArgInstruction < Instruction
    def initialize(index, line:)
      super(line:)
      @index = index
    end

    attr_reader :index

    def instruction_name
      :push_arg
    end

    def to_h
      super.merge(index:)
    end
  end

  class PushConstInstruction < Instruction
    def initialize(name, line:)
      super(line:)
      @name = name
    end

    attr_reader :name

    def instruction_name
      :push_const
    end

    def to_h
      super.merge(name:)
    end
  end

  class CallInstruction < Instruction
    def initialize(name, has_receiver:, arg_count:, line:)
      super(line:)
      @name = name
      @has_receiver = has_receiver
      @arg_count = arg_count
    end

    attr_reader :name, :has_receiver, :arg_count

    def instruction_name
      :call
    end

    def has_receiver? = @has_receiver

    def to_h
      super.merge(name:, has_receiver:, arg_count:)
    end
  end

  class IfInstruction < Instruction
    attr_accessor :if_true, :if_false

    def instruction_name
      :if
    end

    def to_h
      super.merge(
        if_true: if_true.map(&:to_h),
        if_false: if_false.map(&:to_h)
      )
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

    def instruction_name
      :def
    end

    def return_type
      (@pruned_type || @type.prune).types.last
    end

    def to_h
      super.merge(
        name:,
        params:,
        body: body.map(&:to_h)
      )
    end
  end

  class ClassInstruction < Instruction
    def initialize(name, line:)
      super(line:)
      @name = name
    end

    attr_reader :name
    attr_accessor :body

    def instruction_name
      :class
    end

    def to_h
      super.merge(
        name:,
        body: body.map(&:to_h)
      )
    end
  end

  class PopInstruction < Instruction
    def instruction_name
      :pop
    end
  end
end
