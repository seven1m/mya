class Compiler
  module Backends
    class LLVMBackend
      class ObjectBuilder < RcBuilder
        def initialize(builder:, mod:, ptr: nil)
          super(builder:, mod:, ptr:)

          unless ptr
            # FIXME: build a class and pass it in here.
            obj = @builder.call(fn_object_new, LLVM::Type.ptr.null_pointer)
            obj_ptr = @builder.alloca(LLVM::Type.pointer(LLVM::UInt8))
            @builder.store(obj, obj_ptr)
            store_ptr(obj_ptr)
          end
        end

        def fn_object_new
          return @fn_object_new if @fn_object_new

          @fn_object_new = @module.functions['object_new'] ||
            @module.functions.add('object_new', [pointer_type], object_pointer_type)
        end

        private

        def object_pointer_type = self.class.object_pointer_type
        def object_type = self.class.object_type

        def self.object_pointer_type
          @object_pointer_type ||= LLVM::Type.pointer(object_type)
        end

        def self.object_type
          @object_type ||= LLVM::Struct(LLVM::Type.ptr, 'Object')
        end
      end
    end
  end
end
