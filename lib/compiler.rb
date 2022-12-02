require 'bundler/setup'
require 'natalie_parser'

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
      @instructions << [:push_int, value]
    when :str
      _, value = node
      @instructions << [:push_str, value]
    when :block
      _, *nodes = node
      nodes.each { |n| transform(n) }
    when :lasgn
      _, name, value = node
      transform(value)
      @instructions << [:set_var, name]
    when :lvar
      _, name = node
      @instructions << [:push_var, name]
    else
      raise "unknown node: #{node.inspect}"
    end
  end
end
