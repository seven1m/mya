class Compiler
  module Backends
    class LLVMBackend
      class StringBuilder < RcBuilder
        def initialize(builder:, mod:, string: nil, ptr: nil)
          super(builder:, mod:, ptr:)

          string = string.to_s

          return if ptr
          str = LLVM::ConstantArray.string(string)
          str_global = @module.globals.add(LLVM::Type.array(LLVM::Int8, string.bytesize + 1), '')
          str_global.initializer = str
          str_global.linkage = :private
          str_global.global_constant = true
          str_ptr =
            @builder.gep2(
              LLVM::Type.array(LLVM::Int8, string.bytesize + 1),
              str_global,
              [LLVM.Int(0), LLVM.Int(0)],
              'str',
            )
          @builder.call(fn_rc_set_str, @ptr, str_ptr, LLVM.Int(string.bytesize))

          store_size(string.bytesize)
        end

        def fn_rc_set_str
          return @fn_rc_set_str if @fn_rc_set_str

          @fn_rc_set_str =
            @module.functions['rc_set_str'] ||
              @module.functions.add(
                'rc_set_str',
                [pointer_type, LLVM::Type.pointer(LLVM::Int8), LLVM::Int32],
                LLVM::Type.void,
              )
        end
      end
    end
  end
end
