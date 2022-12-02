class Compiler
  class VariableDependency
    def initialize(name:)
      @name = name
    end

    attr_reader :name

    def type!
      raise 'todo'
    end
  end
end
