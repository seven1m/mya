class Compiler
  class Instruction
    def initialize(name, arg: nil, type: nil)
      @name = name
      @arg = arg
      @type = type
      @dependencies = []
    end

    attr_reader :name, :arg, :type, :dependencies

    def to_h
      {
        type: type!,
        instruction: [@name, @arg].compact
      }
    end

    def add_dependency(dependency)
      @dependencies << dependency
    end

    def type!
      return @type if @type

      if @dependencies.size == 1
        @dependencies.first.type!
      else
        raise TypeError, 'some helpful message here'
      end
    end
  end
end
