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
    transform(@ast, used: true)
    type_check
    @instructions
  end

  private

  def transform(node, used:)
    send("transform_#{node.type}", node, used:)
  end

  def transform_array_node(node, used:)
    node.elements.each do |element|
      transform(element, used:)
    end
    instruction = PushArrayInstruction.new(node.elements.size, line: node.location.start_line)
    @instructions << instruction
    @instructions << PopInstruction.new unless used
  end

  def transform_call_node(node, used:)
    if node.receiver
      transform(node.receiver, used: true)
    else
      @instructions << PushSelfInstruction.new
    end
    args = (node.arguments&.arguments || [])
    args.each do |arg|
      transform(arg, used: true)
    end
    instruction = CallInstruction.new(
      node.name,
      arg_count: args.size,
      line: node.location.start_line
    )
    @instructions << instruction
    @instructions << PopInstruction.new unless used
  end

  def transform_class_node(node, used:)
    name = node.constant_path.name
    body = node.body
    instruction = ClassInstruction.new(name, line: node.location.start_line)
    class_instructions = []
    if node.body
      with_instructions_array(class_instructions) do
        transform(node.body, used: false)
      end
    end
    instruction.body = class_instructions
    @instructions << instruction
    @instructions << PushStrInstruction.new(instruction.name, line: node.location.start_line) if used
  end

  def transform_constant_read_node(node, used:)
    return unless used

    instruction = PushConstInstruction.new(node.name, line: node.location.start_line)
    @instructions << instruction
  end

  def transform_def_node(node, used:)
    @scope_stack << { vars: {} }
    params = (node.parameters&.requireds || [])
    instruction = DefInstruction.new(node.name, line: node.location.start_line)
    def_instructions = []
    params.each_with_index do |param, index|
      i1 = PushArgInstruction.new(index, line: node.location.start_line)
      def_instructions << i1
      i2 = SetVarInstruction.new(param.name, nillable: false, line: node.location.start_line)
      def_instructions << i2
      instruction.params << param.name
    end
    with_instructions_array(def_instructions) do
      transform(node.body, used: true)
    end
    instruction.body = def_instructions
    @scope_stack.pop
    @instructions << instruction
    @instructions << PushStrInstruction.new(instruction.name, line: node.location.start_line) if used
  end

  def transform_else_node(node, used:)
    transform(node.statements, used:)
  end

  def transform_false_node(node, used:)
    return unless used

    instruction = PushFalseInstruction.new(line: node.location.start_line)
    @instructions << instruction
  end

  def transform_if_node(node, used:)
    transform(node.predicate, used: true)
    instruction = IfInstruction.new(line: node.location.start_line)
    instruction.if_true = []
    with_instructions_array(instruction.if_true) do
      transform(node.statements, used: true)
    end
    instruction.if_false = []
    with_instructions_array(instruction.if_false) do
      transform(node.consequent, used: true)
    end
    @instructions << instruction
    @instructions << PopInstruction.new unless used
  end

  def transform_instance_variable_write_node(node, used:)
    transform(node.value, used: true)
    directives = @directives.dig(node.location.start_line, node.name) || []
    nillable = directives.include?(:nillable) || node.name.match?(/_or_nil$/)
    instruction = SetInstanceVarInstruction.new(node.name, nillable:, line: node.location.start_line)
    @instructions << instruction
    @instructions << PopInstruction.new unless used
  end

  def transform_integer_node(node, used:)
    return unless used

    instruction = PushIntInstruction.new(node.value, line: node.location.start_line)
    @instructions << instruction
  end

  def transform_local_variable_read_node(node, used:)
    return unless used

    instruction = PushVarInstruction.new(node.name, line: node.location.start_line)
    @instructions << instruction
  end

  def transform_local_variable_write_node(node, used:)
    transform(node.value, used: true)
    directives = @directives.dig(node.location.start_line, node.name) || []
    nillable = directives.include?(:nillable) || node.name.match?(/_or_nil$/)
    instruction = SetVarInstruction.new(node.name, nillable:, line: node.location.start_line)
    @instructions << instruction
    @instructions << PushVarInstruction.new(node.name, line: node.location.start_line) if used
  end

  def transform_nil_node(node, used:)
    return unless used

    instruction = PushNilInstruction.new(line: node.location.start_line)
    @instructions << instruction
  end

  def transform_program_node(node, used:)
    transform(node.statements, used:)
  end

  def transform_statements_node(node, used:)
    node.body.each_with_index do |n, i|
      transform(n, used: used && i == node.body.size - 1)
    end
  end

  def transform_string_node(node, used:)
    return unless used

    instruction = PushStrInstruction.new(node.unescaped, line: node.location.start_line)
    @instructions << instruction
  end

  def transform_true_node(node, used:)
    return unless used

    instruction = PushTrueInstruction.new(line: node.location.start_line)
    @instructions << instruction
  end

  def with_instructions_array(array)
    array_was = @instructions
    @instructions = array
    yield
  ensure
    @instructions = array_was
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
