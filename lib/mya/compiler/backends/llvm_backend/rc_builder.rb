class Compiler
  module Backends
    class LLVMBackend
      class RcBuilder
        def initialize(builder:, mod:, ptr: nil)
          @builder = builder
          @module = mod
          if ptr
            @ptr = ptr
          else
            @ptr = builder.malloc(type, 'rc')
            store_ptr(LLVM::Type.ptr.null_pointer)
            store_ref_count(1)
          end
        end

        def to_ptr = @ptr

        def type = self.class.type
        def pointer_type = self.class.pointer_type

        def store_ptr(ptr)
          @builder.store(ptr, field(0))
        end

        def store_string(string)
          str = LLVM::ConstantArray.string(string)
          str_ptr = @builder.alloca(LLVM::Type.pointer(LLVM::UInt8))
          @builder.store(str, str_ptr)
          @builder.call(fn_rc_set_str, @ptr, str_ptr, LLVM::Int(string.bytesize))
          store_size(string.bytesize)
        end

        def load_ptr(ptr_type)
          @builder.load2(ptr_type, field(0))
        end

        def store_size(size)
          @builder.store(LLVM::Int(size), field(1))
        end

        def load_size
          @builder.load2(LLVM::UInt64, field(1))
        end

        def store_ref_count(count)
          @builder.store(LLVM::Int(count), field(2))
        end

        def field(index)
          @builder.struct_gep2(type, @ptr, index, '')
        end

        def self.type
          @type ||= LLVM::Struct(LLVM::Type.ptr, LLVM::UInt64, LLVM::UInt64, 'rc')
        end

        def self.pointer_type
          @pointer_type ||= LLVM::Type.pointer(type)
        end

        private

        def fn_rc_set_str
          return @fn_rc_set_str if @fn_rc_set_str

          @fn_rc_set_str = @module.functions['rc_set_str'] ||
            @module.functions.add('rc_set_str', [pointer_type, LLVM::Type.pointer(LLVM::UInt8), LLVM::UInt32], LLVM::Type.void)
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
