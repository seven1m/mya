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
    @scope_stack = [{ vars: {} }]
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
      set_var(name, instruction)
      @instructions << instruction
      instruction
    when :lvar
      _, name = node
      instruction = Instruction.new(:push_var, arg: name)
      instruction.add_dependency(VariableDependency.new(name: name, scope: scope))
      @instructions << instruction
      instruction
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
  end
end
