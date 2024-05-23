class Compiler
  module Backends
    class LLVMBackend
      class ArrayBuilder < RcBuilder
        def initialize(builder:, mod:, element_type:, elements: nil, ptr: nil)
          super(builder:, mod:, ptr:)
          @element_type = element_type

          return if ptr
          ary_ptr = builder.array_malloc(element_type, LLVM.Int(elements.size))
          store_ptr(ary_ptr)

          elements.each_with_index do |element, index|
            gep = builder.gep2(LLVM::Type.array(element_type), ary_ptr, [LLVM.Int(0), LLVM.Int(index)], "")
            builder.store(element, gep)
          end

          store_size(elements.size)
        end

        def first
          fn_name = "array_first_#{type_name}"
          unless (fn = @module.functions[fn_name])
            fn = @module.functions.add(fn_name, [RcBuilder.pointer_type], @element_type)
          end
          @builder.call(fn, @ptr)
        end

        def last
          fn_name = "array_last_#{type_name}"
          unless (fn = @module.functions[fn_name])
            fn = @module.functions.add(fn_name, [RcBuilder.pointer_type], @element_type)
          end
          @builder.call(fn, @ptr)
        end

        def push(value)
          fn_name = "array_push_#{type_name}"
          unless (fn = @module.functions[fn_name])
            fn = @module.functions.add(fn_name, [RcBuilder.pointer_type, @element_type], RcBuilder.pointer_type)
          end
          @builder.call(fn, @ptr, value)
        end

        private

        def type_name
          @element_type.kind
        end

        def load_ary_ptr
          load_ptr(LLVM::Type.pointer(LLVM::Type.array(@element_type)))
        end
      end
    end
  end
end
