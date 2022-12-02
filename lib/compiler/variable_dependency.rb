class Compiler
  class VariableDependency
    def initialize(name:, scope:)
      @name = name
      @scope = scope
    end

    attr_reader :name

    def type!
      dependencies = @scope.fetch(:vars).fetch(@name)

      types = dependencies.map(&:type!)
      if types.uniq.size == 1
        types.first
      else
        raise TypeError, "Variable #{@name} was set with more than one type: #{types.uniq.sort.inspect}"
      end
    end
  end
end