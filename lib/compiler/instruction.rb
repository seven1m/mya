class Compiler
  class Instruction
    def initialize(name, arg: nil, type: nil)
      @name = name
      @arg = arg
      @type = type
    end

    attr_reader :name, :arg, :type

    def to_h
      {
        type: type,
        instruction: [@name, @arg].compact
      }
    end
  end
end
