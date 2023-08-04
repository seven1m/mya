class Compiler
  class VariableDependency
    def initialize(name:, scope:)
      @name = name
      @scope = scope
    end

    attr_reader :name

    def type!
      dependencies = @scope.dig(:vars, @name)

      raise TypeError, "Unknown variable: #{@name}" unless dependencies

      types = dependencies.map(&:type!)
      unless types.uniq.size == 1
        raise TypeError, "Variable #{@name} was set with more than one type: #{types.uniq.sort.inspect}"
      end

      types.first
    end
  end
end
