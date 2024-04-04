class Compiler
  module Backends
    class LLVMBackend
      class StringBuilder < RcBuilder
        def initialize(builder:, mod:, string: nil, ptr: nil)
          super(builder:, mod:, ptr:)

          string = string.to_s

          unless ptr
            str = LLVM::ConstantArray.string(string)
            str_ptr = @builder.alloca(LLVM::Type.pointer(LLVM::UInt8))
            @builder.store(str, str_ptr)
            @builder.call(fn_rc_set_str, @ptr, str_ptr, LLVM::Int(string.bytesize))

            store_size(string.bytesize)
          end
        end

        def fn_rc_set_str
          return @fn_rc_set_str if @fn_rc_set_str

          @fn_rc_set_str = @module.functions['rc_set_str'] ||
            @module.functions.add('rc_set_str', [pointer_type, LLVM::Type.pointer(LLVM::UInt8), LLVM::UInt32], LLVM::Type.void)
        end
      end
    end
  end
end
