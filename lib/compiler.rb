require 'bundler/setup'
require 'natalie_parser'
require_relative './compiler/instruction'

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
      @instructions << Instruction.new(:push_int, arg: value, type: :int)
    when :str
      _, value = node
      @instructions << Instruction.new(:push_str, arg: value, type: :str)
    when :block
      _, *nodes = node
      nodes.each { |n| transform(n) }
    when :lasgn
      _, name, value = node
      transform(value)
      @instructions << Instruction.new(:set_var, arg: name)
    when :lvar
      _, name = node
      @instructions << Instruction.new(:push_var, arg: name)
    else
      raise "unknown node: #{node.inspect}"
    end
  end
end
