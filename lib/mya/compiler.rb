require 'bundler/setup'
require 'prism'
require_relative './compiler/instruction'
require_relative './compiler/dependency'
require_relative './compiler/call_arg_dependency'
require_relative './compiler/method_dependency'
require_relative './compiler/variable_dependency'
require_relative './compiler/backends/llvm_backend'

class Compiler
  def initialize(code)
    @code = code
    @ast = Prism.parse(code).value
  end

  def compile
    @scope_stack = [{ vars: {} }]
    @methods = {}
    @calls = Hash.new { |h, k| h[k] = [] }
    @instructions = []
    transform(@ast, @instructions)
    @instructions
  end

  private

  def transform(node, instructions)
    case node
    when Prism::ProgramNode
      transform(node.statements, instructions)
    when Prism::IntegerNode
      instruction = PushIntInstruction.new(node.value, line: node.location.start_line)
      instructions << instruction
      instruction
    when Prism::StringNode
      instruction = PushStrInstruction.new(node.unescaped, line: node.location.start_line)
      instructions << instruction
      instruction
    when Prism::TrueNode
      instruction = PushTrueInstruction.new(line: node.location.start_line)
      instructions << instruction
      instruction
    when Prism::FalseNode
      instruction = PushFalseInstruction.new(line: node.location.start_line)
      instructions << instruction
      instruction
    when Prism::StatementsNode
      node.body.map do |n|
        transform(n, instructions)
      end.last
    when Prism::LocalVariableWriteNode
      value_instruction = transform(node.value, instructions)
      instruction = SetVarInstruction.new(node.name, line: node.location.start_line)
      instruction.add_dependency(Dependency.new(instruction: value_instruction))
      set_var(node.name, instruction)
      instructions << instruction
      instruction
    when Prism::LocalVariableReadNode
      instruction = PushVarInstruction.new(node.name, line: node.location.start_line)
      instruction.add_dependency(VariableDependency.new(name: node.name, scope:))
      instructions << instruction
      instruction
    when Prism::DefNode
      @scope_stack << { vars: {} }
      params = (node.parameters&.requireds || [])
      instruction = DefInstruction.new(node.name, param_size: params.size, line: node.location.start_line)
      instructions << instruction
      def_instructions = []
      params.each_with_index do |arg, index|
        i1 = PushArgInstruction.new(index, line: node.location.start_line)
        i1.add_dependency(
          CallArgDependency.new(
            method_name: node.name,
            calls: @calls[node.name],
            arg_index: index,
            arg_name: arg.name
          )
        )
        def_instructions << i1
        i2 = SetVarInstruction.new(arg.name, line: node.location.start_line)
        i2.add_dependency(i1)
        def_instructions << i2
        set_var(arg.name, i2)
      end
      return_instruction = transform(node.body, def_instructions)
      instruction.body = def_instructions
      instruction.add_dependency(return_instruction)
      set_method(node.name, instruction)
      @scope_stack.pop
      instruction
    when Prism::CallNode
      args = (node.arguments&.arguments || [])
      args.unshift(node.receiver) if node.receiver
      arg_instructions = args.map do |arg|
        transform(arg, instructions)
      end
      @calls[node.name] << { args: arg_instructions }
      instruction = CallInstruction.new(node.name, arg_size: args.size, line: node.location.start_line)
      instruction.add_dependency(MethodDependency.new(name: node.name, methods: @methods))
      instructions << instruction
      instruction
    when Prism::IfNode
      transform(node.predicate, instructions)
      instruction = IfInstruction.new(line: node.location.start_line)
      instructions << instruction
      instruction.if_true = []
      true_result = transform(node.statements, instruction.if_true)
      instruction.if_false = []
      false_result = transform(node.consequent, instruction.if_false)
      instruction.add_dependency(true_result)
      instruction.add_dependency(false_result)
      instruction
    when Prism::ElseNode
      transform(node.statements, instructions)
    else
      raise "unknown node: #{node.inspect}"
    end
  end

  def scope
    @scope_stack.last
  end

  def vars
    scope.fetch(:vars)
  end

  def set_var(name, instruction)
    vars[name] ||= []
    vars[name] << instruction
    unique_types = vars[name].map do |dep|
      dep.type!
    rescue TypeError
      # If we don't yet know the type for this dependency,
      # that's fine, because we might know it later.
    end.compact.uniq
    return unless unique_types.size > 1

    raise TypeError, "Variable a was set with more than one type: #{unique_types.inspect}"
  end

  def set_method(name, instruction)
    raise TypeError, 'TODO' if @methods[name]

    @methods[name] = instruction
  end
end
