require_relative '../../spec_helper'
require_relative '../../support/shared_backend_examples'
require 'stringio'

describe Compiler::Backends::VMBackend do
  include SharedBackendExamples

  def execute(code, io: $stdout)
    instructions = Compiler.new(code).compile
    Compiler::Backends::VMBackend.new(instructions, io:).run
  end

  def execute_with_output(code)
    io = StringIO.new
    execute(code, io:)
    io.rewind
    io.read
  end

  def execute_file(path)
    execute_with_output(File.read(path))
  end
end
