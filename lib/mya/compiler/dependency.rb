class Compiler
  class Dependency
    def initialize(instruction:)
      @instruction = instruction
    end

    attr_reader :instruction

    def type!
      instruction.type!
    end
  end
end
