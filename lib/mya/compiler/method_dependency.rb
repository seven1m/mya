class Compiler
  class MethodDependency
    BUILT_INS = {
      '+': { args: %i[int int], return_type: :int },
      '-': { args: %i[int int], return_type: :int },
      '*': { args: %i[int int], return_type: :int },
      '/': { args: %i[int int], return_type: :int },
      '==': { args: %i[int int], return_type: :bool },
      'p': { args: [:int], return_type: :int }
    }.freeze

    def initialize(name:, methods:)
      @name = name
      @methods = methods
    end

    attr_reader :name

    def type!
      built_in = BUILT_INS[@name]
      return built_in.fetch(:return_type) if built_in

      method = @methods.fetch(@name)
      method.type!
    end
  end
end
