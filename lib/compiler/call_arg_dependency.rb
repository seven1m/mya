class Compiler
  class CallArgDependency
    def initialize(method_name:, calls:, arg_index:, arg_name:)
      @method_name = method_name
      @calls = calls
      @arg_index = arg_index
      @arg_name = arg_name
    end

    attr_reader :method_name, :calls, :arg_index, :arg_name

    def type!
      unique_types = @calls.map { |call| call.fetch(:args)[@arg_index].type! }.compact.uniq

      if unique_types.empty?
        raise TypeError, "Not enough information to infer type of argument '#{@arg_name}' in method '#{@method_name}'"
      elsif unique_types.size == 1
        unique_types.first
      else
        raise TypeError,
              "Argument '#{@arg_name}' in method '#{@method_name}' was called with more than one type: " +
              unique_types.sort.inspect
      end
    end
  end
end
