class Compiler
  class Instruction
    def initialize(name, arg: nil, extra_arg: nil, type: nil)
      @name = name
      @arg = arg
      @extra_arg = extra_arg
      @type = type
      @dependencies = []
    end

    attr_reader :name, :arg, :extra_arg, :type, :dependencies

    def to_h
      {
        type: type!,
        instruction: [@name, @arg, @extra_arg].compact
      }
    end

    def add_dependency(dependency)
      @dependencies << dependency
    end

    INSTRUCTIONS_WITH_NO_TYPE = %i[
      else
      end_def
      end_if
    ].freeze

    def type!
      return @type if @type

      return if INSTRUCTIONS_WITH_NO_TYPE.include?(@name)

      unique_types = @dependencies.map(&:type!).compact.uniq

      if unique_types.empty?
        raise TypeError, "Not enough information to infer type of instruction '#{@name}'"
      elsif unique_types.size == 1
        unique_types.first
      else
        raise TypeError, "Instruction '#{@name}' could have more than one type: #{unique_types.sort.inspect}"
      end
    end

    def inspect
      "<Instruction #{@name}, arg: #{@arg.inspect}>"
    end
  end
end
