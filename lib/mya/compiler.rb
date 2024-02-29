require 'bundler/setup'
require 'prism'
require_relative './compiler/instruction'
require_relative './compiler/type_checker'
require_relative './compiler/backends/llvm_backend'

class Compiler
  def initialize(code)
    @code = code
    @ast = Prism.parse(code).value
  end

  def compile
    @scope_stack = [{ vars: {} }]
    @calls = Hash.new { |h, k| h[k] = [] }
    @instructions = []
    transform(@ast, @instructions)
    type_check
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
      instructions << instruction
      instruction
    when Prism::LocalVariableReadNode
      instruction = PushVarInstruction.new(node.name, line: node.location.start_line)
      instructions << instruction
      instruction
    when Prism::DefNode
      @scope_stack << { vars: {} }
      params = (node.parameters&.requireds || [])
      instruction = DefInstruction.new(node.name, line: node.location.start_line)
      instructions << instruction
      def_instructions = []
      params.each_with_index do |param, index|
        i1 = PushArgInstruction.new(index, line: node.location.start_line)
        def_instructions << i1
        i2 = SetVarInstruction.new(param.name, line: node.location.start_line)
        def_instructions << i2
        instruction.params << param.name
      end
      return_instruction = transform(node.body, def_instructions)
      instruction.body = def_instructions
      @scope_stack.pop
      instruction
    when Prism::CallNode
      args = (node.arguments&.arguments || [])
      args.unshift(node.receiver) if node.receiver
      arg_instructions = args.map do |arg|
        transform(arg, instructions)
      end
      @calls[node.name] << { args: arg_instructions }
      instruction = CallInstruction.new(node.name, arg_count: args.size, line: node.location.start_line)
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
      instruction
    when Prism::ElseNode
      transform(node.statements, instructions)
    when Prism::ArrayNode
      node.elements.each do |element|
        transform(element, instructions)
      end
      instruction = PushArrayInstruction.new(node.elements.size, line: node.location.start_line)
      instructions << instruction
      instruction
    else
      raise "unknown node: #{node.inspect}"
    end
  end

  def type_check
    TypeChecker.new.analyze(@instructions)
  end

  def scope
    @scope_stack.last
  end

  def vars
    scope.fetch(:vars)
  end
end
