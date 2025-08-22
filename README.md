# Mya

[![Specs](https://github.com/seven1m/mya/actions/workflows/specs.yml/badge.svg)](https://github.com/seven1m/mya/actions/workflows/specs.yml)

This is maybe going to be a statically-typed subset of the Ruby language. Or it could become something else entirely! It's mostly a playground for learning about type systems and inference.

This is also my first foray into using LLVM as a backend, so there's a lot of learning going on here!

The name "mya" is just a working name... the name will likely change.

## TODO

- **LLVM backend issues with if statements**: The LLVM backend has problems with certain if statement patterns, particularly those without else clauses in some contexts, causing runtime errors during code generation
- **Missing Array type annotations**: While the type system supports `Array[Type]` internally, the syntax for array type annotations in comments may not be fully implemented
- **No generic type syntax documentation**: The supported generic type syntax (e.g., `Option[String]`) needs better documentation and examples
- **Type annotation error messages**: Error messages for type annotation mismatches could be more descriptive and include context about where the annotation was defined
- **Method return type annotations**: No syntax exists for annotating method return types (e.g., `def method_name -> ReturnType`)
- **Class inheritance type checking**: Type checking for class inheritance and method overriding is not implemented
- **Nil safety**: While Option types exist, there's no comprehensive nil safety system like other modern typed languages
