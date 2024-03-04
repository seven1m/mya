class Compiler
  module Backends
    class LLVMBackend
      class RC
        def initialize(builder:, mod:, ptr: nil)
          @builder = builder
          @module = mod
          if ptr
            @ptr = ptr
          else
            @ptr = builder.malloc(RC.type, 'rc')
            store_ptr(LLVM::Type.ptr.null_pointer)
            store_ref_count(1)
          end
        end

        def to_ptr = @ptr

        def type = self.class.type
        def pointer_type = self.class.pointer_type

        def store_ptr(ptr)
          @builder.store(
            ptr,
            @builder.gep2(type, @ptr, [LLVM::Int(0), LLVM::Int(0)], '')
          )
        end

        def store_string(string)
          str = LLVM::ConstantArray.string(string)
          str_ptr = @builder.alloca(LLVM::Type.pointer(LLVM::UInt8))
          @builder.store(str, str_ptr)
          @builder.call(fn_rc_set_str, @ptr, str_ptr, LLVM::Int(string.bytesize))
        end

        def load_ptr(ptr_type)
          @builder.load2(
            ptr_type,
            @builder.gep2(type, @ptr, [LLVM::Int(0), LLVM::Int(0)], '')
          )
        end

        def store_ref_count(count)
          @builder.store(
            LLVM::Int(count),
            @builder.gep2(type, @ptr, [LLVM::Int(0), LLVM::Int(1)], '')
          )
        end

        def self.type
          @type ||= LLVM::Struct(LLVM::Type.ptr, LLVM::UInt64, 'rc')
        end

        def self.pointer_type
          @pointer_type ||= LLVM::Type.pointer(type)
        end

        private

        def fn_rc_set_str
          @fn_rc_set_str ||= @module.functions.add('rc_set_str', [pointer_type, LLVM::Type.pointer(LLVM::UInt8), LLVM::UInt32], LLVM::Type.void)
        end

        def fn_rc_take
          @fn_rc_take ||= @module.functions.add('rc_take', [pointer_type], LLVM::Type.void)
        end

        def fn_rc_drop
          @fn_rc_drop ||= @module.functions.add('rc_drop', [pointer_type], LLVM::Type.void)
        end
      end
    end
  end
end
