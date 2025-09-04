class Compiler
  module Backends
    class LLVMBackend
      class ObjectBuilder < RcBuilder
        def initialize(builder:, mod:, struct:)
          super(builder:, mod:, ptr: nil)

          obj = builder.malloc(struct)
          obj_ptr = @builder.alloca(LLVM::Type.pointer(LLVM::Int8))
          @builder.store(obj, obj_ptr)
          store_ptr(obj_ptr)
        end
      end
    end
  end
end
