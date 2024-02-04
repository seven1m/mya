require 'bundler/setup'
require 'prism'
require_relative './compiler/instruction'
require_relative './compiler/dependency'
require_relative './compiler/call_arg_dependency'
require_relative './compiler/method_dependency'
require_relative './compiler/variable_dependency'

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
    transform(@ast)
    @instructions
  end

  private

  def transform(node)
    case node
    when Prism::ProgramNode
      transform(node.statements)
    when Prism::IntegerNode
      instruction = Instruction.new(:push_int, arg: node.value, type: :int)
      @instructions << instruction
      instruction
    when Prism::StringNode
      instruction = Instruction.new(:push_str, arg: node.unescaped, type: :str)
      @instructions << instruction
      instruction
    when Prism::TrueNode
      instruction = Instruction.new(:push_true, type: :bool)
      @instructions << instruction
      instruction
    when Prism::FalseNode
      instruction = Instruction.new(:push_false, type: :bool)
      @instructions << instruction
      instruction
    when Prism::StatementsNode
      node.body.map { |n| transform(n) }.last
    when Prism::LocalVariableWriteNode
      value_instruction = transform(node.value)
      instruction = Instruction.new(:set_var, arg: node.name)
      instruction.add_dependency(Dependency.new(instruction: value_instruction))
      set_var(node.name, instruction)
      @instructions << instruction
      instruction
    when Prism::LocalVariableReadNode
      instruction = Instruction.new(:push_var, arg: node.name)
      instruction.add_dependency(VariableDependency.new(name: node.name, scope:))
      @instructions << instruction
      instruction
    when Prism::DefNode
      @scope_stack << { vars: {} }
      params = (node.parameters&.requireds || [])
      instruction = Instruction.new(:def, arg: node.name, extra_arg: params.size)
      @instructions << instruction
      params.each_with_index do |arg, index|
        i1 = Instruction.new(:push_arg, arg: index)
        i1.add_dependency(
          CallArgDependency.new(
            method_name: node.name,
            calls: @calls[node.name],
            arg_index: index,
            arg_name: arg.name
          )
        )
        @instructions << i1
        i2 = Instruction.new(:set_var, arg: arg.name)
        i2.add_dependency(i1)
        @instructions << i2
        set_var(arg.name, i2)
      end
      return_instruction = transform(node.body)
      instruction.add_dependency(return_instruction)
      set_method(node.name, instruction)
      @scope_stack.pop
      @instructions << Instruction.new(:end_def, arg: node.name)
      instruction
    when Prism::CallNode
      args = (node.arguments&.arguments || [])
      args.unshift(node.receiver) if node.receiver
      arg_instructions = args.map do |arg|
        transform(arg)
      end
      @calls[node.name] << { args: arg_instructions }
      instruction = Instruction.new(:call, arg: node.name, extra_arg: args.size)
      instruction.add_dependency(MethodDependency.new(name: node.name, methods: @methods))
      @instructions << instruction
      instruction
    when Prism::IfNode
      transform(node.predicate)
      instruction = Instruction.new(:if)
      @instructions << instruction
      true_instruction = transform(node.statements)
      @instructions << Instruction.new(:else)
      false_instruction = transform(node.consequent)
      @instructions << Instruction.new(:end_if)
      instruction.add_dependency(true_instruction)
      instruction.add_dependency(false_instruction)
      instruction
    when Prism::ElseNode
      transform(node.statements)
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
