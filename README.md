# Mya

[![Specs](https://github.com/seven1m/mya/actions/workflows/specs.yml/badge.svg)](https://github.com/seven1m/mya/actions/workflows/specs.yml)

This is maybe going to be a statically-typed subset of the Ruby language. Or it could become something else entirely! It's mostly a playground for learning about type systems and inference.

This is also my first foray into using LLVM as a backend, so there's a lot of learning going on here!

The name "mya" is just a working name... the name will likely change.

## Building & Testing

```sh
bundle install
bundle exec rake spec
```

### Building LLVM

If you don't have LLVM version 20 libraries available on your system, you can build it like this:

```sh
bundle exec rake llvm:install
LVM_CONFIG=$(pwd)/vendor/llvm-install/bin/llvm-config bundle install
export LD_LIBRARY_PATH=$(pwd)/vendor/llvm-install/lib
bundle exec rake spec
```


## TODO

### Basic Ruby Syntax Missing
- **Logical operators**: `&&`, `||`, `!` (and, or, not operators)
- **Control flow**: `break`, `next`, `return` statements
- **Conditional statements**: `unless`, `elsif` (only basic `if`/`else` supported)
- **Pattern matching**: `case`/`when` statements
- **Loop constructs**: `until`, `for` loops (only `while` supported)
- **Exception handling**: `begin`/`rescue`/`ensure`/`raise`
- **Assignment operators**: `+=`, `-=`, `*=`, `/=`, `||=`, `&&=`
- **Range operators**: `..`, `...` (inclusive/exclusive ranges)
- **String interpolation**: `"Hello #{name}"` syntax
- **Symbols**: `:symbol` syntax
- **Hash literals**: `{ key: value }` syntax
- **Block syntax**: `{ |x| ... }` and `do |x| ... end`
- **Iterators**: `.each`, `.map`, `.select`, etc.
- **Multiple assignment**: `a, b = 1, 2`
- **Splat operators**: `*args`, `**kwargs`
- **Constants**: Proper constant definition and scoping
- **Module system**: `module` and `include`/`extend`

### Type System & Language Features
- **Missing Array type annotations**: While the type system supports `Array[Type]` internally, the syntax for array type annotations in comments may not be fully implemented
- **No generic type syntax documentation**: The supported generic type syntax (e.g., `Option[String]`) needs better documentation and examples
- **Type annotation error messages**: Error messages for type annotation mismatches could be more descriptive and include context about where the annotation was defined
- **Nil safety**: While Option types exist, there's no comprehensive nil safety system like other modern typed languages
