require_relative '../../spec_helper'
require_relative '../../support/shared_backend_examples'
require 'tempfile'

describe Compiler::Backends::LLVMBackend do
  include SharedBackendExamples

  def execute(code)
    instructions = Compiler.new(code).compile
    Compiler::Backends::LLVMBackend.new(instructions).run
  end

  def execute_with_output(code)
    temp = Tempfile.create('compiled.ll')
    temp.close
    instructions = Compiler.new(code).compile
    Compiler::Backends::LLVMBackend.new(instructions).dump_ir_to_file(temp.path)
    `#{lli} #{temp.path} 2>&1`
  ensure
    File.unlink(temp.path)
  end

  def execute_file(path)
    execute_with_output(File.read(path))
  end

  private

  def lli
    return @lli if @lli

    major_version = LLVM::RUBY_LLVM_VERSION.split('.').first
    @lli = (system("command -v lli-#{major_version} 2>/dev/null >/dev/null") ? "lli-#{major_version}" : 'lli')
  end
end
