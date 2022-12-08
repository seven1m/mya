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
      end_def
    ].freeze

    def type!
      return @type if @type

      return if INSTRUCTIONS_WITH_NO_TYPE.include?(@name)
      
      if @dependencies.size == 1
        @dependencies.first.type!
      else
        return nil
        #raise TypeError, 'some helpful message here'
      end
    end

    def inspect
      "<Instruction #{@name}>"
    end
  end
end
