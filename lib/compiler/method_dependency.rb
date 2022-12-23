class Compiler
  class MethodDependency
    BUILT_INS = {
      '+': { args: [:int, :int], return_type: :int },
      '-': { args: [:int, :int], return_type: :int },
      '*': { args: [:int, :int], return_type: :int },
      '/': { args: [:int, :int], return_type: :int },
      '==': { args: [:int, :int], return_type: :int },
      'p': { args: [:int], return_type: :int },
    }

    def initialize(name:, methods:)
      @name = name
      @methods = methods
    end

    attr_reader :name

    def type!
      if (built_in = BUILT_INS[@name])
        return built_in.fetch(:return_type)
      else
        method = @methods.fetch(@name)
        method.type!
      end
    end
  end
end
