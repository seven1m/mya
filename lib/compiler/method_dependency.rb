class Compiler
  class MethodDependency
    def initialize(name:, methods:)
      @name = name
      @methods = methods
    end

    attr_reader :name

    def type!
      method = @methods.fetch(@name)
      method.type!
    end
  end
end
