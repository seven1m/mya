require 'bundler/setup'
require 'prism'
require_relative './compiler/instruction'
require_relative './compiler/type_checker'
require_relative './compiler/backends/llvm_backend'

class Compiler
  def initialize(code)
    @code = code
    @result = Prism.parse(code)
    @ast = @result.value
    @directives = @result.comments.each_with_object({}) do |comment, directives|
      text = comment.location.slice
      text.split.each do |directive|
        if directive =~ /^([a-z][a-z_]*):([a-z_]+)$/
          line = comment.location.start_line
          directives[line] ||= {}
          directives[line][$1.to_sym] ||= []
          directives[line][$1.to_sym] << $2.to_sym
        end
      end
    end
  end

  def compile
    @scope_stack = [{ vars: {} }]
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
    when Prism::NilNode
      instruction = PushNilInstruction.new(line: node.location.start_line)
      instructions << instruction
      instruction
    when Prism::StatementsNode
      node.body.map do |n|
        transform(n, instructions)
      end.last
    when Prism::LocalVariableWriteNode
      value_instruction = transform(node.value, instructions)
      directives = @directives.dig(node.location.start_line, node.name) || []
      nillable = directives.include?(:nillable) || node.name.match?(/_or_nil$/)
      instruction = SetVarInstruction.new(node.name, nillable:, line: node.location.start_line)
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
        i2 = SetVarInstruction.new(param.name, nillable: false, line: node.location.start_line)
        def_instructions << i2
        instruction.params << param.name
      end
      return_instruction = transform(node.body, def_instructions)
      instruction.body = def_instructions
      @scope_stack.pop
      instruction
    when Prism::CallNode
      transform(node.receiver, instructions) if node.receiver
      args = (node.arguments&.arguments || [])
      arg_instructions = args.map do |arg|
        transform(arg, instructions)
      end
      instruction = CallInstruction.new(
        node.name,
        has_receiver: !!node.receiver,
        arg_count: args.size,
        arg_instructions:,
        line: node.location.start_line
      )
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
    when Prism::ClassNode
      name = node.constant_path.name
      body = node.body
      instruction = ClassInstruction.new(name, line: node.location.start_line)
      instructions << instruction
      class_instructions = []
      transform(node.body || Prism::NilNode.new(node.location), class_instructions)
      instruction.body = class_instructions
      instruction
    when Prism::InstanceVariableWriteNode
      value_instruction = transform(node.value, instructions)
      directives = @directives.dig(node.location.start_line, node.name) || []
      nillable = directives.include?(:nillable) || node.name.match?(/_or_nil$/)
      instruction = SetInstanceVarInstruction.new(node.name, nillable:, line: node.location.start_line)
      instructions << instruction
      instruction
    when Prism::ConstantReadNode
      instruction = PushConstInstruction.new(node.name, line: node.location.start_line)
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
