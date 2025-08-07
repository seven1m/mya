require_relative "spec_helper"
require_relative "support/shared_backend_examples"
require "stringio"

describe VM do
  include SharedBackendExamples

  def execute(code, io: $stdout)
    instructions = Compiler.new(code).compile
    VM.new(instructions, io:).run
  end

  def execute_code(code)
    io = StringIO.new
    execute(code, io:)
    io.rewind
    io.read
  end

  def execute_file(path)
    execute_code(File.read(path))
  end
end
