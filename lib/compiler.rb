require 'bundler/setup'
require 'natalie_parser'
require_relative './compiler/instruction'
require_relative './compiler/dependency'
require_relative './compiler/variable_dependency'

class Compiler
  def initialize(code)
    @code = code
    @ast = NatalieParser.parse(code)
  end

  def compile
    @instructions = []
    transform(@ast)
    @instructions
  end

  private

  def transform(node)
    case node.sexp_type
    when :lit
      _, value = node
      instruction = Instruction.new(:push_int, arg: value, type: :int)
      @instructions << instruction
      instruction
    when :str
      _, value = node
      instruction = Instruction.new(:push_str, arg: value, type: :str)
      @instructions << instruction
      instruction
    when :block
      _, *nodes = node
      nodes.each { |n| transform(n) }
    when :lasgn
      _, name, value = node
      value_instruction = transform(value)
      instruction = Instruction.new(:set_var, arg: name)
      instruction.add_dependency(Dependency.new(instruction: value_instruction))
      @instructions << instruction
      instruction
    when :lvar
      _, name = node
      instruction = Instruction.new(:push_var, arg: name)
      instruction.add_dependency(VariableDependency.new(name: name))
      @instructions << instruction
      instruction
    else
      raise "unknown node: #{node.inspect}"
    end
  end
end
